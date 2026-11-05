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
	ErrNotFound  = errors.New("store: pemain tidak ditemukan")
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
);`

// Store membungkus koneksi database.
type Store struct {
	db *sql.DB
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
	// SQLite hanya mengizinkan satu penulis; satu koneksi menjaga semuanya sederhana.
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
	return s.scan(s.db.QueryRowContext(ctx, selectPlayer+` WHERE id = ?`, id))
}

// PlayerByTokenHash mengambil pemain berdasarkan hash token.
func (s *Store) PlayerByTokenHash(ctx context.Context, hash string) (game.Player, error) {
	return s.scan(s.db.QueryRowContext(ctx, selectPlayer+` WHERE token_hash = ?`, hash))
}

// SaveState menimpa progress pemain. expectedVersion harus sama dengan versi
// yang tersimpan; jika tidak, ErrConflict dikembalikan (mencegah simpanan lama
// menimpa yang baru).
func (s *Store) SaveState(ctx context.Context, id string, st game.State, expectedVersion int) (game.Player, error) {
	js, err := json.Marshal(st)
	if err != nil {
		return game.Player{}, err
	}
	res, err := s.db.ExecContext(ctx,
		`UPDATE players SET state = ?, version = version + 1, updated_at = ?
		 WHERE id = ? AND version = ?`,
		string(js), time.Now().UTC().Format(time.RFC3339Nano), id, expectedVersion)
	if err != nil {
		return game.Player{}, fmt.Errorf("simpan progress: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return game.Player{}, err
	}
	if n == 0 {
		if _, err := s.PlayerByID(ctx, id); err != nil {
			return game.Player{}, err // ErrNotFound
		}
		return game.Player{}, ErrConflict
	}
	return s.PlayerByID(ctx, id)
}

const selectPlayer = `SELECT id, name, state, version, created_at, updated_at FROM players`

func (s *Store) scan(row *sql.Row) (game.Player, error) {
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
