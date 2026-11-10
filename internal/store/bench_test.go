package store

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Tolok ukur kueri utama (roadmap no. 237): `go test -bench . ./internal/store/`.

func benchStore(b *testing.B, players int) *Store {
	b.Helper()
	st, err := Open(b.TempDir() + "/b.db")
	if err != nil {
		b.Fatal(err)
	}
	b.Cleanup(func() { st.Close() })
	ctx := context.Background()
	for i := range players {
		id := fmt.Sprintf("id-%d", i)
		if _, err := st.CreatePlayer(ctx, id, fmt.Sprintf("p%d", i), fmt.Sprintf("p%d@x.id", i), "pw", fmt.Sprintf("h-%d", i), game.NewState()); err != nil {
			b.Fatal(err)
		}
	}
	return st
}

func BenchmarkAuthSession(b *testing.B) {
	st := benchStore(b, 500)
	ctx, now := context.Background(), time.Now()
	b.ResetTimer()
	for i := range b.N {
		if _, err := st.AuthSession(ctx, fmt.Sprintf("h-%d", i%500), now); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkUpdateState(b *testing.B) {
	st := benchStore(b, 500)
	ctx := context.Background()
	b.ResetTimer()
	for i := range b.N {
		if _, err := st.Update(ctx, fmt.Sprintf("id-%d", i%500), func(s *Session) error {
			s.Player.State.Gold++
			return nil
		}); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkTradesList(b *testing.B) {
	st := benchStore(b, 50)
	ctx := context.Background()
	b.ResetTimer()
	for range b.N {
		if _, err := st.Trades(ctx, "id-1"); err != nil {
			b.Fatal(err)
		}
	}
}

// Kueri yang sering dipakai harus memakai indeks, bukan memindai seluruh tabel.
func TestQueriesUseIndexes(t *testing.T) {
	st := newStore(t)
	for q, args := range map[string][]any{
		`SELECT player_id, created_at, last_used FROM sessions WHERE token_hash = ?`: {"x"},
		selectPlayer + ` WHERE id = ?`:                                         {"x"},
		`SELECT id, name FROM players WHERE name = ?`:                          {"x"},
		`SELECT COUNT(*) FROM trades WHERE from_id = ? AND status = 'pending'`: {"x"},
		`DELETE FROM sessions WHERE player_id = ? AND token_hash != ?`:         {"x", "y"},
	} {
		rows, err := st.db.Query(`EXPLAIN QUERY PLAN `+q, args...)
		if err != nil {
			t.Fatal(err)
		}
		var plan []string
		for rows.Next() {
			var id, parent, notused int
			var detail string
			_ = rows.Scan(&id, &parent, &notused, &detail)
			plan = append(plan, detail)
		}
		rows.Close()
		for _, d := range plan {
			if len(d) >= 4 && d[:4] == "SCAN" {
				t.Errorf("kueri memindai tabel: %s -> %v", q, plan)
			}
		}
	}
}
