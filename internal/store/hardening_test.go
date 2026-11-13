package store

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Pengujian audit keamanan v0.77.0: sesi, migrasi skema, pemeriksaan integritas, cadangan & pemulihan.

// --- sesi ---

func TestAuthSessionStates(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Sesi") // token "hash-Sesi"
	now := time.Now()

	if got, err := st.AuthSession(ctx, "hash-Sesi", now); err != nil || got.ID != p.ID {
		t.Fatalf("sesi sah: %v", err)
	}
	if _, err := st.AuthSession(ctx, "tidak-ada", now); !errors.Is(err, ErrNotFound) {
		t.Errorf("sesi tidak ditemukan: %v", err)
	}
	// Dicabut (logout): tidak bisa dipakai lagi.
	if err := st.DeleteSession(ctx, "hash-Sesi"); err != nil {
		t.Fatal(err)
	}
	if _, err := st.AuthSession(ctx, "hash-Sesi", now); !errors.Is(err, ErrNotFound) {
		t.Errorf("sesi dicabut: %v", err)
	}
	// Kedaluwarsa karena lama tidak dipakai / umur maksimum: ditolak dan dihapus.
	if err := st.CreateSession(ctx, p.ID, "hash-lama"); err != nil {
		t.Fatal(err)
	}
	if _, err := st.AuthSession(ctx, "hash-lama", now.Add(SessionIdle+time.Hour)); !errors.Is(err, ErrSessionExpired) {
		t.Errorf("sesi menganggur: %v", err)
	}
	if _, err := st.AuthSession(ctx, "hash-lama", now); !errors.Is(err, ErrNotFound) {
		t.Errorf("sesi kedaluwarsa harus terhapus: %v", err)
	}
	// Cap waktu rusak: gagal aman (dianggap kedaluwarsa), bukan dianggap baru.
	if err := st.CreateSession(ctx, p.ID, "hash-rusak"); err != nil {
		t.Fatal(err)
	}
	if _, err := st.db.Exec(`UPDATE sessions SET created_at = 'kemarin' WHERE token_hash = 'hash-rusak'`); err != nil {
		t.Fatal(err)
	}
	if _, err := st.AuthSession(ctx, "hash-rusak", now); !errors.Is(err, ErrSessionExpired) {
		t.Errorf("cap waktu rusak: %v", err)
	}
}

func TestAuthSessionTouchFailureIsReported(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Sentuh")
	if _, err := st.db.Exec(`CREATE TRIGGER tolak_sentuh BEFORE UPDATE ON sessions BEGIN SELECT RAISE(ABORT, 'disk penuh (uji)'); END`); err != nil {
		t.Fatal(err)
	}
	got, err := st.AuthSession(ctx, "hash-Sentuh", time.Now().Add(2*touchEvery))
	if !errors.Is(err, ErrSessionTouch) || got.ID != p.ID {
		t.Fatalf("gagal memperbarui last_used harus dilaporkan (pemain tetap ada): %v %+v", err, got.ID)
	}
	if !strings.Contains(err.Error(), "disk penuh") {
		t.Errorf("penyebab asli hilang: %v", err)
	}
}

func TestAuthSessionDatabaseErrorIsNotUnauthorized(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	newPlayer(t, st, "Tutup")
	st.Close()
	_, err := st.AuthSession(ctx, "hash-Tutup", time.Now())
	if err == nil || errors.Is(err, ErrNotFound) {
		t.Fatalf("database tertutup harus menjadi kesalahan server, bukan 'tidak ditemukan': %v", err)
	}
}

func TestAuthSessionConcurrent(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Ramai")
	later := time.Now().Add(2 * touchEvery)
	var wg sync.WaitGroup
	for range 32 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if got, err := st.AuthSession(ctx, "hash-Ramai", later); err != nil || got.ID != p.ID {
				t.Errorf("auth bersamaan: %v", err)
			}
		}()
	}
	wg.Wait()
	list, err := st.Sessions(ctx, p.ID, "hash-Ramai")
	if err != nil || len(list) != 1 || list[0].LastUsed.Sub(later).Abs() > time.Millisecond {
		t.Fatalf("sesi setelah auth bersamaan: %+v %v", list, err)
	}
}

// --- migrasi skema ---

// openRaw membuka berkas database tanpa migrasi (untuk memeriksa/menyiapkan isinya di tes).
func openRaw(path string) (*sql.DB, error) { return sql.Open("sqlite", "file:"+path) }

func userVersion(t *testing.T, path string) int {
	t.Helper()
	s, err := openRaw(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	var v int
	if err := s.QueryRow(`PRAGMA user_version`).Scan(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestMigrateNewAndCurrent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "baru.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	p := newPlayer(t, s, "Baru")
	s.Close()
	if v := userVersion(t, path); v != schemaVersion {
		t.Fatalf("database baru v%d, mau v%d", v, schemaVersion)
	}
	// Dibuka lagi pada versi yang sama: data utuh, tidak ada migrasi.
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if got, err := s.PlayerByID(context.Background(), p.ID); err != nil || got.Name != "Baru" {
		t.Fatalf("data setelah dibuka ulang: %v", err)
	}
}

func TestMigrateRefusesNewerSchema(t *testing.T) {
	path := filepath.Join(t.TempDir(), "masa-depan.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	p := newPlayer(t, s, "Depan")
	if _, err := s.db.Exec(`PRAGMA user_version = 99`); err != nil {
		t.Fatal(err)
	}
	s.Close()
	if _, err := Open(path); !errors.Is(err, ErrSchemaTooNew) {
		t.Fatalf("skema lebih baru harus ditolak: %v", err)
	}
	// Tidak ada yang diubah: versi dan data tetap.
	if v := userVersion(t, path); v != 99 {
		t.Errorf("user_version berubah: %d", v)
	}
	raw, err := openRaw(path)
	if err != nil {
		t.Fatal(err)
	}
	defer raw.Close()
	var name string
	if err := raw.QueryRow(`SELECT name FROM players WHERE id = ?`, p.ID).Scan(&name); err != nil || name != "Depan" {
		t.Fatalf("data pemain: %q %v", name, err)
	}
}

// Migrasi yang gagal di tengah jalan tidak meninggalkan setengah perubahan; setelah penyebabnya diperbaiki,
// migrasi berjalan ulang dengan aman dan data pemain utuh.
func TestMigrateFailureIsAtomicAndRetryable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "gagal.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	p := newPlayer(t, s, "Tahan")
	if _, err := s.Update(context.Background(), p.ID, func(x *Session) error { x.Player.State.Gold = 321; return nil }); err != nil {
		t.Fatal(err)
	}
	// Bentuk v3 yang rusak: tabel sessions hilang, jadi langkah v3 -> v4 (ALTER TABLE sessions) gagal.
	if _, err := s.db.Exec(`DROP TABLE sessions; PRAGMA user_version = 3`); err != nil {
		t.Fatal(err)
	}
	s.Close()
	if _, err := Open(path); err == nil || !strings.Contains(err.Error(), "v3 -> v4") {
		t.Fatalf("migrasi harus gagal jelas: %v", err)
	}
	if v := userVersion(t, path); v != 3 {
		t.Fatalf("versi harus tetap 3 setelah gagal, dapat %d", v)
	}
	// Penyebab diperbaiki (tabel dibuat lagi tanpa last_used), lalu dibuka ulang.
	raw, err := openRaw(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := raw.Exec(`CREATE TABLE sessions (token_hash TEXT PRIMARY KEY, player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE, created_at TEXT NOT NULL)`); err != nil {
		t.Fatal(err)
	}
	raw.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatalf("migrasi ulang: %v", err)
	}
	defer s.Close()
	got, err := s.PlayerByID(context.Background(), p.ID)
	if err != nil || got.State.Gold != 321 {
		t.Fatalf("data pemain setelah migrasi ulang: %+v %v", got.State.Gold, err)
	}
	if v := userVersion(t, path); v != schemaVersion {
		t.Errorf("versi akhir %d", v)
	}
}

// --- integritas, cadangan, pemulihan ---

func TestQuickCheckAndVerifyDetectCorruption(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	for i := range 200 {
		newPlayer(t, st, "Isi"+strings.Repeat("x", i%7)+string(rune('A'+i%26))+string(rune('a'+i/26)))
	}
	if msg, err := st.QuickCheck(ctx); err != nil || msg != "" {
		t.Fatalf("database sehat: %q %v", msg, err)
	}
	dir := t.TempDir()
	path, err := st.Backup(ctx, dir, 3, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err := VerifyBackup(ctx, path); err != nil {
		t.Fatalf("cadangan sehat: %v", err)
	}
	// Rusakkan isi berkas cadangan (halaman di tengah ditimpa sampah).
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for i := 4096 * 2; i < len(raw) && i < 4096*6; i++ {
		raw[i] = 0xA5
	}
	bad := filepath.Join(t.TempDir(), "rusak.db")
	if err := os.WriteFile(bad, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := VerifyBackup(ctx, bad); err == nil {
		t.Fatal("berkas rusak harus ditolak sebelum dipulihkan")
	}
	// Bukan database sama sekali.
	junk := filepath.Join(t.TempDir(), "sampah.db")
	_ = os.WriteFile(junk, []byte("bukan sqlite"), 0o644)
	if err := VerifyBackup(ctx, junk); err == nil {
		t.Fatal("berkas sampah harus ditolak")
	}
	if err := VerifyBackup(ctx, filepath.Join(t.TempDir(), "tidak-ada.db")); err == nil {
		t.Fatal("berkas yang tidak ada harus ditolak")
	}
}

func TestBackupDuringActivity(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Sibuk")
	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
			}
			if _, err := st.Update(ctx, p.ID, func(x *Session) error { x.Player.State.Gold = i % 1000; return nil }); err != nil {
				t.Errorf("tulis saat cadangan: %v", err)
				return
			}
		}
	}()
	dir := t.TempDir()
	base := time.Now()
	for i := range 5 {
		path, err := st.Backup(ctx, dir, 10, base.Add(time.Duration(i)*time.Second))
		if err != nil {
			t.Fatalf("cadangan saat ramai: %v", err)
		}
		if err := VerifyBackup(ctx, path); err != nil {
			t.Fatalf("cadangan saat ramai tidak sehat: %v", err)
		}
	}
	close(stop)
	wg.Wait()
	if left, _ := filepath.Glob(filepath.Join(dir, "*.tmp")); len(left) != 0 {
		t.Errorf("berkas sementara tertinggal: %v", left)
	}
}

func TestBackupFailureKeepsOldBackupsAndNoPartialFile(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	newPlayer(t, st, "Aman")
	dir := t.TempDir()
	base := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	for i := range 2 {
		if _, err := st.Backup(ctx, dir, 2, base.Add(time.Duration(i)*time.Hour)); err != nil {
			t.Fatal(err)
		}
	}
	before, _ := filepath.Glob(filepath.Join(dir, "game-*.db"))
	// Nama berkas sementara sudah dipakai oleh sebuah FOLDER berisi berkas: VACUUM INTO gagal.
	next := base.Add(5 * time.Hour)
	blocker := filepath.Join(dir, "game-"+next.Format("20060102-150405")+".db.tmp")
	if err := os.MkdirAll(filepath.Join(blocker, "isi"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := st.Backup(ctx, dir, 2, next); err == nil {
		t.Fatal("cadangan harus gagal")
	}
	after, _ := filepath.Glob(filepath.Join(dir, "game-*.db"))
	if len(after) != len(before) {
		t.Fatalf("cadangan lama tidak boleh terhapus saat cadangan baru gagal: %v -> %v", before, after)
	}
	if _, err := os.Stat(filepath.Join(dir, "game-"+next.Format("20060102-150405")+".db")); !os.IsNotExist(err) {
		t.Fatalf("tidak boleh ada berkas cadangan setengah jadi: %v", err)
	}
	// Database utama tetap sehat dan bisa ditulis.
	if msg, err := st.QuickCheck(ctx); err != nil || msg != "" {
		t.Fatalf("database utama: %q %v", msg, err)
	}
	if _, err := st.Update(ctx, "id-Aman", func(x *Session) error { x.Player.State.Gold = 5; return nil }); err != nil {
		t.Fatal(err)
	}
}

func TestRestoreFromValidBackup(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Pulih")
	if _, err := st.Update(ctx, p.ID, func(x *Session) error {
		x.Player.State.Gold = 4242
		x.Player.State.AddItem(game.PotionID, 7)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	path, err := st.Backup(ctx, t.TempDir(), 3, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err := VerifyBackup(ctx, path); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	target := filepath.Join(t.TempDir(), "game.db")
	if err := os.WriteFile(target, data, 0o644); err != nil {
		t.Fatal(err)
	}
	rs, err := Open(target)
	if err != nil {
		t.Fatal(err)
	}
	defer rs.Close()
	got, err := rs.PlayerByID(ctx, p.ID)
	if err != nil || got.State.Gold != 4242 {
		t.Fatalf("isi pemulihan: %+v %v", got.State, err)
	}
}
