// Package store menyimpan data pemain ke SQLite.
//
// Memakai modernc.org/sqlite (Go murni, tanpa CGO) sehingga mudah dibangun
// di Pi maupun di-cross-compile dari mesin lain.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite" // driver SQLite

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Kesalahan yang bisa dikembalikan Store.
var (
	ErrNotFound  = errors.New("store: tidak ditemukan")
	ErrNameTaken = errors.New("store: nama sudah dipakai")
	ErrConflict  = errors.New("store: versi data tidak cocok")
)

const schema = `
CREATE TABLE IF NOT EXISTS players (
	id         TEXT PRIMARY KEY,
	name       TEXT NOT NULL UNIQUE COLLATE NOCASE,
	token_hash TEXT NOT NULL UNIQUE,
	state      TEXT NOT NULL,
	version    INTEGER NOT NULL DEFAULT 1,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS battles (
	player_id  TEXT PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
	state      TEXT NOT NULL,
	updated_at TEXT NOT NULL
);`

// Store membungkus koneksi database.
type Store struct {
	db *sql.DB
}

// Session adalah pemain beserta pertarungannya yang sedang berjalan (bila ada).
type Session struct {
	Player game.Player
	Battle *game.Battle
}

// Open membuka (dan membuat bila belum ada) database di path.
func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("buat folder database: %w", err)
	}
	dsn := "file:" + path +
		"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("buka database: %w", err)
	}
	// SQLite hanya mengizinkan satu penulis; satu koneksi menjaga semuanya sederhana
	// dan membuat setiap transaksi berjalan bergantian (tidak saling menimpa).
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("buat skema: %w", err)
	}
	return &Store{db: db}, nil
}

// Close menutup database.
func (s *Store) Close() error { return s.db.Close() }

// Ping memeriksa database masih bisa dijangkau.
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

// CreatePlayer menambah pemain baru. tokenHash adalah hash token, bukan token asli.
func (s *Store) CreatePlayer(ctx context.Context, id, name, tokenHash string, st game.State) (game.Player, error) {
	js, err := json.Marshal(st)
	if err != nil {
		return game.Player{}, err
	}
	now := time.Now().UTC()
	_, err = s.db.ExecContext(ctx,
		`INSERT INTO players (id, name, token_hash, state, version, created_at, updated_at)
		 VALUES (?, ?, ?, ?, 1, ?, ?)`,
		id, name, tokenHash, string(js), now.Format(time.RFC3339Nano), now.Format(time.RFC3339Nano))
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE constraint failed") {
			return game.Player{}, ErrNameTaken
		}
		return game.Player{}, fmt.Errorf("simpan pemain: %w", err)
	}
	return s.PlayerByID(ctx, id)
}

// PlayerByID mengambil pemain berdasarkan id.
func (s *Store) PlayerByID(ctx context.Context, id string) (game.Player, error) {
	return scanPlayer(s.db.QueryRowContext(ctx, selectPlayer+` WHERE id = ?`, id))
}

// PlayerByTokenHash mengambil pemain berdasarkan hash token.
func (s *Store) PlayerByTokenHash(ctx context.Context, hash string) (game.Player, error) {
	return scanPlayer(s.db.QueryRowContext(ctx, selectPlayer+` WHERE token_hash = ?`, hash))
}

// Battle mengambil pertarungan yang sedang berjalan, atau ErrNotFound bila tidak ada.
func (s *Store) Battle(ctx context.Context, playerID string) (game.Battle, error) {
	b, err := loadBattle(ctx, s.db, playerID)
	if err != nil {
		return game.Battle{}, err
	}
	return *b, nil
}

// SavePosition menyimpan posisi pemain (peta, petak, posisi halus, arah) dari klien. Hanya posisi yang
// diterima: HP, XP, emas, level, dan tas dihitung server dan tidak bisa diubah klien.
// expectedVersion harus sama dengan versi tersimpan, jika tidak ErrConflict.
func (s *Store) SavePosition(ctx context.Context, id string, pose game.Pose, expectedVersion int) (game.Player, error) {
	sess, err := s.mutate(ctx, id, expectedVersion, func(sess *Session) error {
		st := &sess.Player.State
		st.Map, st.X, st.Y = pose.Map, pose.X, pose.Y
		st.FX, st.FZ, st.Yaw = pose.FX, pose.FZ, pose.Yaw
		return nil
	})
	return sess.Player, err
}

// Update menjalankan fn atas pemain dan pertarungannya dalam SATU transaksi:
// semua perubahan tersimpan bersama, atau tidak sama sekali bila fn mengembalikan
// error. Versi pemain naik 1. Mengatur sess.Battle = nil menghapus pertarungan.
func (s *Store) Update(ctx context.Context, id string, fn func(*Session) error) (Session, error) {
	return s.mutate(ctx, id, -1, fn)
}

// mutate: expectedVersion < 0 berarti tanpa pemeriksaan versi.
func (s *Store) mutate(ctx context.Context, id string, expectedVersion int, fn func(*Session) error) (Session, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Session{}, fmt.Errorf("mulai transaksi: %w", err)
	}
	defer tx.Rollback() // tidak berpengaruh setelah Commit

	p, err := scanPlayer(tx.QueryRowContext(ctx, selectPlayer+` WHERE id = ?`, id))
	if err != nil {
		return Session{}, err
	}
	if expectedVersion >= 0 && p.Version != expectedVersion {
		return Session{}, ErrConflict
	}
	b, err := loadBattle(ctx, tx, id)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return Session{}, err
	}
	sess := Session{Player: p, Battle: b}

	if err := fn(&sess); err != nil {
		return Session{}, err
	}

	now := time.Now().UTC()
	stamp := now.Format(time.RFC3339Nano)
	js, err := json.Marshal(sess.Player.State)
	if err != nil {
		return Session{}, err
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE players SET state = ?, version = version + 1, updated_at = ? WHERE id = ?`,
		string(js), stamp, id); err != nil {
		return Session{}, fmt.Errorf("simpan progress: %w", err)
	}
	if sess.Battle != nil {
		bjs, err := json.Marshal(sess.Battle)
		if err != nil {
			return Session{}, err
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO battles (player_id, state, updated_at) VALUES (?, ?, ?)
			 ON CONFLICT(player_id) DO UPDATE SET state = excluded.state, updated_at = excluded.updated_at`,
			id, string(bjs), stamp); err != nil {
			return Session{}, fmt.Errorf("simpan pertarungan: %w", err)
		}
	} else if _, err := tx.ExecContext(ctx, `DELETE FROM battles WHERE player_id = ?`, id); err != nil {
		return Session{}, fmt.Errorf("hapus pertarungan: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Session{}, fmt.Errorf("simpan transaksi: %w", err)
	}

	sess.Player.Version++
	sess.Player.UpdatedAt = now
	if sess.Player.State.Inventory == nil {
		sess.Player.State.Inventory = []game.Item{}
	}
	return sess, nil
}

const selectPlayer = `SELECT id, name, state, version, created_at, updated_at FROM players`

type rowScanner interface {
	Scan(dest ...any) error
}

type queryer interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

func scanPlayer(row rowScanner) (game.Player, error) {
	var (
		p                   game.Player
		stateJSON, cAt, uAt string
	)
	if err := row.Scan(&p.ID, &p.Name, &stateJSON, &p.Version, &cAt, &uAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return game.Player{}, ErrNotFound
		}
		return game.Player{}, fmt.Errorf("baca pemain: %w", err)
	}
	if err := json.Unmarshal([]byte(stateJSON), &p.State); err != nil {
		return game.Player{}, fmt.Errorf("state rusak: %w", err)
	}
	var err error
	if p.CreatedAt, err = time.Parse(time.RFC3339Nano, cAt); err != nil {
		return game.Player{}, err
	}
	if p.UpdatedAt, err = time.Parse(time.RFC3339Nano, uAt); err != nil {
		return game.Player{}, err
	}
	if p.State.Inventory == nil {
		p.State.Inventory = []game.Item{}
	}
	return p, nil
}

func loadBattle(ctx context.Context, q queryer, playerID string) (*game.Battle, error) {
	var js string
	err := q.QueryRowContext(ctx, `SELECT state FROM battles WHERE player_id = ?`, playerID).Scan(&js)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("baca pertarungan: %w", err)
	}
	var b game.Battle
	if err := json.Unmarshal([]byte(js), &b); err != nil {
		return nil, fmt.Errorf("pertarungan rusak: %w", err)
	}
	return &b, nil
}
