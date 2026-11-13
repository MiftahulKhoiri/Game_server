package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Masa berlaku sesi (roadmap no. 221-223). Token yang tidak dipakai selama SessionIdle, atau yang
// umurnya melewati SessionMax, ditolak dan dihapus; pemain harus masuk lagi dengan kata sandi.
var (
	SessionIdle = 30 * 24 * time.Hour
	SessionMax  = 180 * 24 * time.Hour
	// touchEvery: last_used hanya diperbarui sekali per jam per token (hemat tulis ke kartu SD).
	touchEvery = time.Hour
)

// ErrSessionExpired berarti token dikenal tetapi sudah kedaluwarsa (dan sudah dihapus).
var ErrSessionExpired = errors.New("store: sesi kedaluwarsa")

// ErrSessionTouch: sesi SAH, tetapi waktu terakhir dipakainya gagal diperbarui. AuthSession tetap mengembalikan
// pemainnya (bersama error yang membungkus ErrSessionTouch) supaya permintaan tidak gagal hanya karena catatan
// pemakaian; pemanggil wajib mencatatnya di log.
var ErrSessionTouch = errors.New("store: gagal memperbarui waktu pakai sesi")

// SessionInfo adalah satu sesi (perangkat) milik pemain, tanpa tokennya.
type SessionInfo struct {
	Created  time.Time `json:"created"`
	LastUsed time.Time `json:"last_used"`
	Current  bool      `json:"current"`
}

func stampOf(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

// AuthSession mencari pemain pemilik token (hash) dan memeriksa masa berlakunya pada `now`.
//   - token tidak ada: ErrNotFound; kesalahan database lain dikembalikan apa adanya (bukan dianggap 401).
//   - kedaluwarsa (atau cap waktunya rusak — gagal aman): sesi dihapus, ErrSessionExpired.
//   - sah: waktu terakhir dipakai diperbarui paling sering sekali per touchEvery (hemat tulis). Bila
//     pembaruan itu gagal, pemain tetap dikembalikan bersama error yang membungkus ErrSessionTouch.
func (s *Store) AuthSession(ctx context.Context, hash string, now time.Time) (game.Player, error) {
	var playerID, created, used string
	err := s.db.QueryRowContext(ctx, `SELECT player_id, created_at, last_used FROM sessions WHERE token_hash = ?`, hash).
		Scan(&playerID, &created, &used)
	if errors.Is(err, sql.ErrNoRows) {
		return game.Player{}, ErrNotFound
	}
	if err != nil {
		return game.Player{}, fmt.Errorf("baca sesi: %w", err)
	}
	c, err1 := time.Parse(time.RFC3339Nano, created)
	u, err2 := time.Parse(time.RFC3339Nano, used)
	if err2 != nil && used == "" { // baris lama sebelum kolom last_used terisi
		u, err2 = c, err1
	}
	if err1 != nil || err2 != nil || now.Sub(u) > SessionIdle || now.Sub(c) > SessionMax {
		if _, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, hash); err != nil {
			return game.Player{}, fmt.Errorf("%w (hapus sesi gagal: %v)", ErrSessionExpired, err)
		}
		return game.Player{}, ErrSessionExpired
	}
	var touchErr error
	if now.Sub(u) > touchEvery {
		// Bersyarat pada nilai lama: dua permintaan bersamaan tidak menulis dua kali.
		if _, err := s.db.ExecContext(ctx, `UPDATE sessions SET last_used = ? WHERE token_hash = ? AND last_used = ?`,
			stampOf(now), hash, used); err != nil {
			touchErr = fmt.Errorf("%w: %v", ErrSessionTouch, err)
		}
	}
	p, err := s.PlayerByID(ctx, playerID)
	if err != nil {
		return game.Player{}, err
	}
	return p, touchErr
}

// Sessions: semua sesi pemain, terbaru dipakai di atas. `current` = hash token permintaan ini.
func (s *Store) Sessions(ctx context.Context, playerID, current string) ([]SessionInfo, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT token_hash, created_at, last_used FROM sessions WHERE player_id = ?`, playerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SessionInfo{}
	for rows.Next() {
		var h, c, u string
		if err := rows.Scan(&h, &c, &u); err != nil {
			return nil, err
		}
		ct, _ := time.Parse(time.RFC3339Nano, c)
		ut, err := time.Parse(time.RFC3339Nano, u)
		if err != nil {
			ut = ct
		}
		out = append(out, SessionInfo{Created: ct, LastUsed: ut, Current: h == current})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].LastUsed.After(out[j].LastUsed) })
	return out, rows.Err()
}

// RevokeOthers mencabut semua sesi pemain kecuali `keep` (keluar dari perangkat lain). Mengembalikan jumlahnya.
func (s *Store) RevokeOthers(ctx context.Context, playerID, keep string) (int, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE player_id = ? AND token_hash != ?`, playerID, keep)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return int(n), nil
}

// PasswordHash mengambil hash kata sandi pemain ("" untuk akun lama).
func (s *Store) PasswordHash(ctx context.Context, playerID string) (string, error) {
	var h *string
	if err := s.db.QueryRowContext(ctx, `SELECT password_hash FROM players WHERE id = ?`, playerID).Scan(&h); err != nil {
		return "", ErrNotFound
	}
	if h == nil {
		return "", nil
	}
	return *h, nil
}

// SetPassword mengganti hash kata sandi. Bila revokeKeep != "", semua sesi lain (selain token itu) dicabut
// dalam transaksi yang sama.
func (s *Store) SetPassword(ctx context.Context, playerID, hash, revokeKeep string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `UPDATE players SET password_hash = ? WHERE id = ?`, hash, playerID); err != nil {
		return err
	}
	if revokeKeep != "" {
		if _, err := tx.ExecContext(ctx, `DELETE FROM sessions WHERE player_id = ? AND token_hash != ?`, playerID, revokeKeep); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// --- cadangan & pemeriksaan (roadmap no. 220, 235-236) ---

// QuickCheck menjalankan PRAGMA quick_check; "" bila database sehat.
func (s *Store) QuickCheck(ctx context.Context) (string, error) {
	rows, err := s.db.QueryContext(ctx, `PRAGMA quick_check`)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var msgs []string
	for rows.Next() {
		var m string
		if err := rows.Scan(&m); err != nil {
			return "", err
		}
		if m != "ok" {
			msgs = append(msgs, m)
		}
	}
	return strings.Join(msgs, "; "), rows.Err()
}

// Backup menyalin seluruh database ke dir/game-YYYYMMDD-HHMMSS.db memakai VACUUM INTO (salinan utuh dan
// konsisten walau server sedang berjalan), lalu menyisakan `keep` cadangan terbaru. Mengembalikan path-nya.
//
// Aman terhadap kegagalan: salinan ditulis dulu ke berkas sementara (.tmp), diperiksa (quick_check +
// tabel players terbaca), di-fsync, baru diganti nama menjadi nama akhirnya. Cadangan lama baru dihapus
// setelah cadangan baru dipastikan berhasil. Database utama hanya dibaca.
func (s *Store) Backup(ctx context.Context, dir string, keep int, now time.Time) (string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("buat folder cadangan: %w", err)
	}
	path := filepath.Join(dir, "game-"+now.UTC().Format("20060102-150405")+".db")
	if _, err := os.Stat(path); err == nil {
		return path, nil
	}
	tmp := path + ".tmp"
	_ = os.Remove(tmp) // sisa percobaan yang gagal sebelumnya
	if _, err := s.db.ExecContext(ctx, `VACUUM INTO ?`, tmp); err != nil {
		_ = os.Remove(tmp)
		return "", fmt.Errorf("cadangkan database: %w", err)
	}
	if err := VerifyBackup(ctx, tmp); err != nil {
		_ = os.Remove(tmp)
		return "", fmt.Errorf("cadangan tidak lolos pemeriksaan: %w", err)
	}
	if err := syncFile(tmp); err != nil {
		_ = os.Remove(tmp)
		return "", fmt.Errorf("tulis cadangan ke disk: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return "", fmt.Errorf("simpan cadangan: %w", err)
	}
	_ = syncFile(dir) // nama berkas baru ikut tersimpan di disk
	if keep > 0 {
		old, _ := filepath.Glob(filepath.Join(dir, "game-*.db"))
		sort.Strings(old) // nama memuat waktu: urut = urut waktu
		for i := 0; i < len(old)-keep; i++ {
			if old[i] != path {
				_ = os.Remove(old[i])
			}
		}
	}
	return path, nil
}

// VerifyBackup membuka berkas database hanya-baca dan memastikan sehat (quick_check) serta berisi tabel
// pemain yang terbaca. Dipakai untuk cadangan baru dan sebelum memulihkan.
func VerifyBackup(ctx context.Context, path string) error {
	if _, err := os.Stat(path); err != nil {
		return err
	}
	db, err := sql.Open("sqlite", "file:"+path+"?mode=ro&_pragma=busy_timeout(5000)")
	if err != nil {
		return err
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	var msgs []string
	rows, err := db.QueryContext(ctx, `PRAGMA quick_check`)
	if err != nil {
		return fmt.Errorf("quick_check: %w", err)
	}
	for rows.Next() {
		var m string
		if err := rows.Scan(&m); err != nil {
			rows.Close()
			return err
		}
		if m != "ok" {
			msgs = append(msgs, m)
		}
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return fmt.Errorf("quick_check: %w", err)
	}
	if len(msgs) > 0 {
		return fmt.Errorf("database rusak: %s", strings.Join(msgs, "; "))
	}
	var n int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM players`).Scan(&n); err != nil {
		return fmt.Errorf("tabel players tidak terbaca: %w", err)
	}
	return nil
}

func syncFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}

// LatestBackup: cadangan terbaru di dir dan waktunya ("" bila belum ada).
func LatestBackup(dir string) (string, time.Time) {
	files, _ := filepath.Glob(filepath.Join(dir, "game-*.db"))
	if len(files) == 0 {
		return "", time.Time{}
	}
	sort.Strings(files)
	last := files[len(files)-1]
	st, err := os.Stat(last)
	if err != nil {
		return last, time.Time{}
	}
	return last, st.ModTime()
}

// Counts: jumlah baris tabel utama (untuk memeriksa hasil pemulihan cadangan).
func (s *Store) Counts(ctx context.Context) (map[string]int, error) {
	out := map[string]int{}
	for _, t := range []string{"players", "sessions", "battles", "trades"} {
		var n int
		if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+t).Scan(&n); err != nil {
			return nil, err
		}
		out[t] = n
	}
	return out, nil
}
