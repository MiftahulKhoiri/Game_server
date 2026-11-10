package store

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSessionExpiryAndTouch(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Sesi")
	now := time.Now()
	if got, err := st.AuthSession(ctx, "hash-Sesi", now); err != nil || got.ID != p.ID {
		t.Fatalf("sesi baru berlaku: %v", err)
	}
	// Dipakai lagi 29 hari kemudian: masih berlaku dan waktu pakainya diperbarui.
	later := now.Add(29 * 24 * time.Hour)
	if _, err := st.AuthSession(ctx, "hash-Sesi", later); err != nil {
		t.Fatalf("29 hari tanpa dipakai masih berlaku: %v", err)
	}
	if _, err := st.AuthSession(ctx, "hash-Sesi", later.Add(29*24*time.Hour)); err != nil {
		t.Fatalf("dipakai lagi 29 hari setelah pemakaian terakhir: %v", err)
	}
	// Lewat 30 hari tanpa dipakai: kedaluwarsa dan dihapus.
	if _, err := st.AuthSession(ctx, "hash-Sesi", later.Add(29*24*time.Hour+31*24*time.Hour)); !errors.Is(err, ErrSessionExpired) {
		t.Fatalf("harus kedaluwarsa: %v", err)
	}
	if _, err := st.AuthSession(ctx, "hash-Sesi", later); !errors.Is(err, ErrNotFound) {
		t.Fatalf("sesi kedaluwarsa harus terhapus: %v", err)
	}
	// Umur maksimum: walau terus dipakai, setelah 180 hari harus masuk lagi.
	if err := st.CreateSession(ctx, p.ID, "h2"); err != nil {
		t.Fatal(err)
	}
	tick := now
	for i := 0; i < 7; i++ {
		tick = tick.Add(25 * 24 * time.Hour)
		if _, err := st.AuthSession(ctx, "h2", tick); err != nil {
			t.Fatalf("hari ke-%d: %v", 25*(i+1), err)
		}
	}
	if _, err := st.AuthSession(ctx, "h2", now.Add(SessionMax+time.Hour)); !errors.Is(err, ErrSessionExpired) {
		t.Fatalf("umur maksimum: %v", err)
	}
}

func TestSessionsListRevokeAndPassword(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Banyak")
	for _, h := range []string{"hp-2", "hp-3"} {
		if err := st.CreateSession(ctx, p.ID, h); err != nil {
			t.Fatal(err)
		}
	}
	list, err := st.Sessions(ctx, p.ID, "hp-2")
	if err != nil || len(list) != 3 {
		t.Fatalf("3 sesi: %v %v", list, err)
	}
	cur := 0
	for _, s := range list {
		if s.Current {
			cur++
		}
	}
	if cur != 1 {
		t.Fatalf("tepat satu sesi saat ini: %+v", list)
	}
	if n, err := st.RevokeOthers(ctx, p.ID, "hp-2"); err != nil || n != 2 {
		t.Fatalf("cabut 2 sesi lain: %d %v", n, err)
	}
	if _, err := st.AuthSession(ctx, "hash-Banyak", time.Now()); !errors.Is(err, ErrNotFound) {
		t.Fatal("sesi lain harus tercabut")
	}
	if err := st.CreateSession(ctx, p.ID, "hp-4"); err != nil {
		t.Fatal(err)
	}
	if err := st.SetPassword(ctx, p.ID, "baru", "hp-2"); err != nil {
		t.Fatal(err)
	}
	if h, _ := st.PasswordHash(ctx, p.ID); h != "baru" {
		t.Fatalf("hash baru tersimpan: %q", h)
	}
	if _, err := st.AuthSession(ctx, "hp-4", time.Now()); !errors.Is(err, ErrNotFound) {
		t.Fatal("ganti sandi mencabut sesi lain")
	}
	if _, err := st.AuthSession(ctx, "hp-2", time.Now()); err != nil {
		t.Fatalf("sesi yang mengganti sandi tetap: %v", err)
	}
}

func TestBackupRestoreRoundTrip(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "Cadang")
	if _, err := st.Update(ctx, p.ID, func(s *Session) error {
		s.Player.State.Gold = 777
		s.Player.State.Bank = 55
		s.Player.State.AddItem("permata_merah", 3)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(t.TempDir(), "cadangan")
	base := time.Date(2026, 11, 10, 8, 0, 0, 0, time.UTC)
	var last string
	for i := 0; i < 4; i++ {
		path, err := st.Backup(ctx, dir, 3, base.Add(time.Duration(i)*time.Hour))
		if err != nil {
			t.Fatal(err)
		}
		last = path
	}
	files, _ := filepath.Glob(filepath.Join(dir, "game-*.db"))
	if len(files) != 3 {
		t.Fatalf("hanya 3 cadangan terbaru yang disimpan: %v", files)
	}
	if lp, _ := LatestBackup(dir); lp != last {
		t.Fatalf("cadangan terbaru: %s vs %s", lp, last)
	}
	// Pulihkan: salin cadangan ke tempat database baru lalu buka.
	restored := filepath.Join(t.TempDir(), "pulih.db")
	raw, err := os.ReadFile(last)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(restored, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	rs, err := Open(restored)
	if err != nil {
		t.Fatal(err)
	}
	defer rs.Close()
	if msg, err := rs.QuickCheck(ctx); err != nil || msg != "" {
		t.Fatalf("cadangan sehat: %q %v", msg, err)
	}
	got, err := rs.PlayerByID(ctx, p.ID)
	if err != nil || got.State.Gold != 777 || got.State.Bank != 55 || len(got.State.Inventory) != 2 {
		t.Fatalf("isi cadangan: %+v %v", got.State, err)
	}
	a, _ := st.Counts(ctx)
	b, _ := rs.Counts(ctx)
	for k, v := range a {
		if b[k] != v {
			t.Errorf("jumlah %s: asli %d, cadangan %d", k, v, b[k])
		}
	}
	if _, err := rs.AuthSession(ctx, "hash-Cadang", time.Now()); err != nil {
		t.Fatalf("sesi ikut tercadang: %v", err)
	}
}

func TestMigrateV3AddsLastUsed(t *testing.T) {
	path := filepath.Join(t.TempDir(), "v3.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	p := newPlayer(t, s, "Lama")
	// Bentuk ulang tabel sessions seperti v3 (tanpa last_used).
	if _, err := s.db.Exec(`CREATE TABLE s3 (token_hash TEXT PRIMARY KEY, player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE, created_at TEXT NOT NULL);
		INSERT INTO s3 SELECT token_hash, player_id, created_at FROM sessions; DROP TABLE sessions; ALTER TABLE s3 RENAME TO sessions;
		PRAGMA user_version = 3`); err != nil {
		t.Fatal(err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if got, err := s.AuthSession(context.Background(), "hash-Lama", time.Now()); err != nil || got.ID != p.ID {
		t.Fatalf("token lama tetap berlaku setelah migrasi: %v", err)
	}
}
