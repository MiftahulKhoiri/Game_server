package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// gameProgressDDL: progres game platform multi-game (v0.84.0), satu baris per (pemain, game). Progres
// Game Petualangan tetap di players.state seperti sebelumnya; tabel ini untuk game lain (education_sd,
// education_smp, ...) sehingga data antargame tidak pernah bercampur.
const gameProgressDDL = `
CREATE TABLE IF NOT EXISTS game_progress (
	player_id      TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
	game_id        TEXT NOT NULL,
	schema_version INTEGER NOT NULL,
	data           TEXT NOT NULL,
	client_updated TEXT NOT NULL DEFAULT '',
	updated_at     TEXT NOT NULL,
	revision       INTEGER NOT NULL DEFAULT 1,
	PRIMARY KEY (player_id, game_id)
)`

// GameProgress adalah progres satu pemain di satu game platform.
type GameProgress struct {
	GameID        string `json:"game_id"`
	SchemaVersion int    `json:"schema_version"`
	Data          string `json:"-"` // objek JSON mentah (sudah divalidasi API)
	ClientUpdated string `json:"client_updated"`
	UpdatedAt     string `json:"updated_at"`
	Revision      int    `json:"revision"`
}

// GetGameProgress mengembalikan progres pemain di game itu; ok=false bila belum ada.
func (s *Store) GetGameProgress(ctx context.Context, playerID, gameID string) (GameProgress, bool, error) {
	var g GameProgress
	err := s.db.QueryRowContext(ctx, `SELECT game_id, schema_version, data, client_updated, updated_at, revision
		FROM game_progress WHERE player_id = ? AND game_id = ?`, playerID, gameID).
		Scan(&g.GameID, &g.SchemaVersion, &g.Data, &g.ClientUpdated, &g.UpdatedAt, &g.Revision)
	if errors.Is(err, sql.ErrNoRows) {
		return GameProgress{}, false, nil
	}
	if err != nil {
		return GameProgress{}, false, fmt.Errorf("baca progres game: %w", err)
	}
	return g, true, nil
}

// PutGameProgress menyimpan (menimpa) progres pemain di game itu dan menaikkan revisinya.
func (s *Store) PutGameProgress(ctx context.Context, playerID, gameID string, schema int, data, clientUpdated string, now time.Time) (GameProgress, error) {
	ts := now.UTC().Format(time.RFC3339)
	_, err := s.db.ExecContext(ctx, `INSERT INTO game_progress
		(player_id, game_id, schema_version, data, client_updated, updated_at, revision)
		VALUES (?, ?, ?, ?, ?, ?, 1)
		ON CONFLICT(player_id, game_id) DO UPDATE SET
			schema_version = excluded.schema_version, data = excluded.data,
			client_updated = excluded.client_updated, updated_at = excluded.updated_at,
			revision = game_progress.revision + 1`,
		playerID, gameID, schema, data, clientUpdated, ts)
	if err != nil {
		return GameProgress{}, fmt.Errorf("simpan progres game: %w", err)
	}
	g, _, err := s.GetGameProgress(ctx, playerID, gameID)
	return g, err
}
