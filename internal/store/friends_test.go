package store

import (
	"context"
	"testing"
	"time"
)

func TestRecentPlayersUsesSessionActivity(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	self := newPlayer(t, st, "Diri")
	active := newPlayer(t, st, "Aktif")
	stale := newPlayer(t, st, "Lama")

	now := time.Now().UTC()
	since := now.Add(-7 * 24 * time.Hour)
	old := now.Add(-30 * 24 * time.Hour)

	// Pemain aktif tidak menulis state baru, tetapi tokennya baru saja dipakai.
	if _, err := st.db.ExecContext(ctx,
		`UPDATE players SET updated_at = ? WHERE id = ?`,
		stampOf(old), active.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := st.db.ExecContext(ctx,
		`UPDATE sessions SET last_used = ? WHERE player_id = ?`,
		stampOf(now), active.ID); err != nil {
		t.Fatal(err)
	}

	// Pemain yang tidak login baru-baru ini justru baru menulis state.
	if _, err := st.db.ExecContext(ctx,
		`UPDATE players SET updated_at = ? WHERE id = ?`,
		stampOf(now), stale.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := st.db.ExecContext(ctx,
		`UPDATE sessions SET last_used = ? WHERE player_id = ?`,
		stampOf(old), stale.ID); err != nil {
		t.Fatal(err)
	}

	// Satu pemain dengan beberapa perangkat tetap hanya muncul sekali.
	if err := st.CreateSession(ctx, active.ID, "hash-Aktif-perangkat-kedua"); err != nil {
		t.Fatal(err)
	}
	if _, err := st.db.ExecContext(ctx,
		`UPDATE sessions SET last_used = ? WHERE token_hash = ?`,
		stampOf(now.Add(-time.Hour)), "hash-Aktif-perangkat-kedua"); err != nil {
		t.Fatal(err)
	}

	got, err := st.RecentPlayers(ctx, self.ID, since, 20)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != active.Name {
		t.Fatalf("pemain terbaru harus berdasar sessions.last_used; dapat %v, ingin [%s]", got, active.Name)
	}
}
