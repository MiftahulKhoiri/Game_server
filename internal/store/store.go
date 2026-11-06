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
	ErrNotFound   = errors.New("store: tidak ditemukan")
	ErrNameTaken  = errors.New("store: nama sudah dipakai")
	ErrEmailTaken = errors.New("store: email sudah dipakai")
	ErrConflict   = errors.New("store: versi data tidak cocok")
)

// schemaVersion disimpan di PRAGMA user_version. Naikkan saat skema berubah, dan tambahkan
// langkah di migrate.
//
//	1 = skema awal (players.token_hash, satu token per pemain)
//	2 = akun: email + password_hash di players, token pindah ke tabel sessions
const schemaVersion = 2

// playersDDL dipakai dua kali: tabel baru dan tabel bangun-ulang saat migrasi.
const playersDDL = `CREATE TABLE %s (
	id            TEXT PRIMARY KEY,
	name          TEXT NOT NULL UNIQUE COLLATE NOCASE,
	email         TEXT UNIQUE COLLATE NOCASE, -- NULL untuk akun lama (belum punya akun)
	password_hash TEXT,                       -- NULL untuk akun lama
	state         TEXT NOT NULL,
	version       INTEGER NOT NULL DEFAULT 1,
	created_at    TEXT NOT NULL,
	updated_at    TEXT NOT NULL
)`

const schemaRest = `
CREATE TABLE IF NOT EXISTS sessions (
	token_hash TEXT PRIMARY KEY,
	player_id  TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
	created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_player ON sessions(player_id);
CREATE TABLE IF NOT EXISTS battles (
	player_id  TEXT PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
	state      TEXT NOT NULL,
	updated_at TEXT NOT NULL
);`

// maxSessions membatasi jumlah token aktif per pemain (HP/perangkat); yang tertua dibuang.
const maxSessions = 10

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
	if err := migrate(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("siapkan skema: %w", err)
	}
	return &Store{db: db}, nil
}

// migrate membuat skema baru, atau memigrasikan database versi lama tanpa menghapus data.
func migrate(db *sql.DB) error {
	var ver int
	if err := db.QueryRow(`PRAGMA user_version`).Scan(&ver); err != nil {
		return err
	}
	if ver >= schemaVersion {
		return nil
	}
	var legacy int
	if err := db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('players') WHERE name = 'token_hash'`).Scan(&legacy); err != nil {
		return err
	}
	if legacy == 0 { // database baru
		if _, err := db.Exec(fmt.Sprintf(playersDDL, "players") + ";" + schemaRest); err != nil {
			return err
		}
		_, err := db.Exec(fmt.Sprintf(`PRAGMA user_version = %d`, schemaVersion))
		return err
	}
	return migrateFromV1(db)
}

// migrateFromV1 membangun ulang tabel players (SQLite tidak bisa mencabut kolom UNIQUE) dengan
// urutan resmi SQLite: foreign_keys dimatikan dulu supaya DROP TABLE tidak menghapus battles.
// Token lama dipindah ke sessions, jadi aplikasi lama tetap bisa masuk. Akun lama belum punya
// email/kata sandi (NULL) dan tidak bisa login dengan kata sandi.
func migrateFromV1(db *sql.DB) error {
	if _, err := db.Exec(`PRAGMA foreign_keys = OFF`); err != nil {
		return err
	}
	defer db.Exec(`PRAGMA foreign_keys = ON`)
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	steps := []string{
		fmt.Sprintf(playersDDL, "players_baru"),
		`INSERT INTO players_baru (id, name, state, version, created_at, updated_at)
		 SELECT id, name, state, version, created_at, updated_at FROM players`,
		`CREATE TABLE IF NOT EXISTS sessions (
			token_hash TEXT PRIMARY KEY,
			player_id  TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
			created_at TEXT NOT NULL
		)`,
		`INSERT OR IGNORE INTO sessions (token_hash, player_id, created_at)
		 SELECT token_hash, id, created_at FROM players`,
		`DROP TABLE players`,
		`ALTER TABLE players_baru RENAME TO players`,
		`CREATE INDEX IF NOT EXISTS sessions_player ON sessions(player_id)`,
		`CREATE TABLE IF NOT EXISTS battles (
			player_id  TEXT PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
			state      TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		fmt.Sprintf(`PRAGMA user_version = %d`, schemaVersion),
	}
	for _, q := range steps {
		if _, err := tx.Exec(q); err != nil {
			return fmt.Errorf("migrasi v1 -> v2: %w", err)
		}
	}
	var bad int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM pragma_foreign_key_check`).Scan(&bad); err == nil && bad > 0 {
		return fmt.Errorf("migrasi v1 -> v2: %d baris melanggar foreign key", bad)
	}
	return tx.Commit()
}

// Close menutup database.
func (s *Store) Close() error { return s.db.Close() }

// Ping memeriksa database masih bisa dijangkau.
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

// CreatePlayer menambah akun baru beserta sesi pertamanya dalam satu transaksi. email sudah
// dinormalkan (huruf kecil); passwordHash dan tokenHash adalah hash, bukan nilai aslinya.
func (s *Store) CreatePlayer(ctx context.Context, id, name, email, passwordHash, tokenHash string, st game.State) (game.Player, error) {
	js, err := json.Marshal(st)
	if err != nil {
		return game.Player{}, err
	}
	stamp := time.Now().UTC().Format(time.RFC3339Nano)
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return game.Player{}, fmt.Errorf("mulai transaksi: %w", err)
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx,
		`INSERT INTO players (id, name, email, password_hash, state, version, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, 1, ?, ?)`,
		id, name, email, passwordHash, string(js), stamp, stamp)
	if err != nil {
		switch {
		case strings.Contains(err.Error(), "players.email"):
			return game.Player{}, ErrEmailTaken
		case strings.Contains(err.Error(), "UNIQUE constraint failed"):
			return game.Player{}, ErrNameTaken
		}
		return game.Player{}, fmt.Errorf("simpan pemain: %w", err)
	}
	if err := insertSession(ctx, tx, id, tokenHash, stamp); err != nil {
		return game.Player{}, err
	}
	if err := tx.Commit(); err != nil {
		return game.Player{}, fmt.Errorf("simpan transaksi: %w", err)
	}
	return s.PlayerByID(ctx, id)
}

type execer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// insertSession menyimpan hash token dan membuang sesi tertua bila melebihi maxSessions.
func insertSession(ctx context.Context, q execer, playerID, tokenHash, stamp string) error {
	if _, err := q.ExecContext(ctx,
		`INSERT INTO sessions (token_hash, player_id, created_at) VALUES (?, ?, ?)`,
		tokenHash, playerID, stamp); err != nil {
		return fmt.Errorf("simpan sesi: %w", err)
	}
	if _, err := q.ExecContext(ctx,
		`DELETE FROM sessions WHERE player_id = ? AND token_hash NOT IN (
			SELECT token_hash FROM sessions WHERE player_id = ?
			ORDER BY created_at DESC, rowid DESC LIMIT ?)`,
		playerID, playerID, maxSessions); err != nil {
		return fmt.Errorf("rapikan sesi: %w", err)
	}
	return nil
}

// CreateSession menambah token baru (hash) untuk pemain yang berhasil login.
func (s *Store) CreateSession(ctx context.Context, playerID, tokenHash string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("mulai transaksi: %w", err)
	}
	defer tx.Rollback()
	if err := insertSession(ctx, tx, playerID, tokenHash, time.Now().UTC().Format(time.RFC3339Nano)); err != nil {
		return err
	}
	return tx.Commit()
}

// DeleteSession mencabut satu token (logout). Token yang tidak ada bukan kesalahan.
func (s *Store) DeleteSession(ctx context.Context, tokenHash string) error {
	if _, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, tokenHash); err != nil {
		return fmt.Errorf("hapus sesi: %w", err)
	}
	return nil
}

// PlayerByLogin mencari akun berdasarkan nama ATAU email (tanpa membedakan huruf besar/kecil)
// dan mengembalikan hash kata sandinya. Akun lama tanpa kata sandi mengembalikan hash kosong.
func (s *Store) PlayerByLogin(ctx context.Context, login string) (game.Player, string, error) {
	var hash string
	p, err := scanPlayer(s.db.QueryRowContext(ctx,
		`SELECT `+playerCols+`, COALESCE(password_hash, '') FROM players WHERE name = ?1 OR email = ?1`, login), &hash)
	return p, hash, err
}

// PlayerByID mengambil pemain berdasarkan id.
func (s *Store) PlayerByID(ctx context.Context, id string) (game.Player, error) {
	return scanPlayer(s.db.QueryRowContext(ctx, selectPlayer+` WHERE id = ?`, id))
}

// PlayerByTokenHash mengambil pemain berdasarkan hash token.
func (s *Store) PlayerByTokenHash(ctx context.Context, hash string) (game.Player, error) {
	return scanPlayer(s.db.QueryRowContext(ctx,
		selectPlayer+` WHERE id = (SELECT player_id FROM sessions WHERE token_hash = ?)`, hash))
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

const (
	playerCols   = `id, name, COALESCE(email, ''), state, version, created_at, updated_at`
	selectPlayer = `SELECT ` + playerCols + ` FROM players`
)

type rowScanner interface {
	Scan(dest ...any) error
}

type queryer interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// scanPlayer membaca kolom playerCols; extra adalah kolom tambahan di belakangnya (bila ada).
func scanPlayer(row rowScanner, extra ...any) (game.Player, error) {
	var (
		p                   game.Player
		stateJSON, cAt, uAt string
	)
	dest := append([]any{&p.ID, &p.Name, &p.Email, &stateJSON, &p.Version, &cAt, &uAt}, extra...)
	if err := row.Scan(dest...); err != nil {
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
