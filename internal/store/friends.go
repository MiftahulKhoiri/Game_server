package store

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

// Teman dan pemain aktif (roadmap no. 176, v0.79.0): membantu memilih tujuan dagang tanpa mengetik nama.
// Hanya nama pemain yang dikeluarkan (nama sudah terlihat di dagang); email, id, dan isi state tidak.

// PlayerName mencari pemain dari nama (tanpa beda huruf besar/kecil). Mengembalikan id dan nama aslinya,
// atau ErrNotFound.
func (s *Store) PlayerName(ctx context.Context, name string) (id, realName string, err error) {
	err = s.db.QueryRowContext(ctx, `SELECT id, name FROM players WHERE name = ?`, name).Scan(&id, &realName)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", ErrNotFound
	}
	return id, realName, err
}

// RecentPlayers: nama pemain lain yang memiliki sesi aktif sejak `since` (yang terbaru dulu), paling banyak limit.
// Aktivitas diukur dari sessions.last_used, bukan players.updated_at yang hanya berubah saat state ditulis.
func (s *Store) RecentPlayers(ctx context.Context, exceptID string, since time.Time, limit int) ([]string, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT p.name
		 FROM players p JOIN sessions s ON s.player_id = p.id
		 WHERE p.id != ? AND julianday(s.last_used) >= julianday(?)
		 GROUP BY p.id, p.name
		 ORDER BY MAX(julianday(s.last_used)) DESC
		 LIMIT ?`,
		exceptID, stampOf(since), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	names := []string{}
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			return nil, err
		}
		names = append(names, n)
	}
	return names, rows.Err()
}
