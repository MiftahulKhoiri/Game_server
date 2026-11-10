package store

import (
	"context"
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

// SessionInfo adalah satu sesi (perangkat) milik pemain, tanpa tokennya.
type SessionInfo struct {
	Created  time.Time `json:"created"`
	LastUsed time.Time `json:"last_used"`
	Current  bool      `json:"current"`
}

func stampOf(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

// AuthSession mencari pemain pemilik token (hash) dan memeriksa masa berlakunya pada `now`.
// Sesi yang masih berlaku diperbarui waktu terakhir dipakainya (paling sering sekali sejam).
func (s *Store) AuthSession(ctx context.Context, hash string, now time.Time) (game.Player, error) {
	var playerID, created, used string
	err := s.db.QueryRowContext(ctx, `SELECT player_id, created_at, last_used FROM sessions WHERE token_hash = ?`, hash).
		Scan(&playerID, &created, &used)
	if err != nil {
		return game.Player{}, ErrNotFound
	}
	c, err1 := time.Parse(time.RFC3339Nano, created)
	u, err2 := time.Parse(time.RFC3339Nano, used)
	if err1 != nil {
		c = now
	}
	if err2 != nil {
		u = c
	}
	if now.Sub(u) > SessionIdle || now.Sub(c) > SessionMax {
		_, _ = s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, hash)
		return game.Player{}, ErrSessionExpired
	}
	if now.Sub(u) > touchEvery {
		_, _ = s.db.ExecContext(ctx, `UPDATE sessions SET last_used = ? WHERE token_hash = ?`, stampOf(now), hash)
	}
	return s.PlayerByID(ctx, playerID)
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
func (s *Store) Backup(ctx context.Context, dir string, keep int, now time.Time) (string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("buat folder cadangan: %w", err)
	}
	path := filepath.Join(dir, "game-"+now.UTC().Format("20060102-150405")+".db")
	if _, err := os.Stat(path); err == nil {
		return path, nil
	}
	if _, err := s.db.ExecContext(ctx, `VACUUM INTO ?`, path); err != nil {
		return "", fmt.Errorf("cadangkan database: %w", err)
	}
	if keep > 0 {
		old, _ := filepath.Glob(filepath.Join(dir, "game-*.db"))
		sort.Strings(old) // nama memuat waktu: urut = urut waktu
		for i := 0; i < len(old)-keep; i++ {
			_ = os.Remove(old[i])
		}
	}
	return path, nil
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
