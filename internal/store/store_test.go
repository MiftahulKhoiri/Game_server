package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

func newStore(t *testing.T) *Store {
	t.Helper()
	st, err := Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	return st
}

func newPlayer(t *testing.T, st *Store, name string) game.Player {
	t.Helper()
	p, err := st.CreatePlayer(context.Background(), "id-"+name, name, "hash-"+name, game.NewState())
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestUpdateCommitsPlayerAndBattleTogether(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "A")

	sess, err := st.Update(ctx, p.ID, func(s *Session) error {
		s.Player.State.Gold = 42
		s.Battle = &game.Battle{EnemyID: "tikus_sawah", EnemyHP: 10, EnemyMaxHP: 10, Round: 1}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.Player.Version != 2 || sess.Player.State.Gold != 42 {
		t.Errorf("hasil update salah: %+v", sess.Player)
	}
	b, err := st.Battle(ctx, p.ID)
	if err != nil || b.EnemyID != "tikus_sawah" {
		t.Fatalf("pertarungan tidak tersimpan: %+v %v", b, err)
	}

	// Menghapus pertarungan lewat Update.
	if _, err := st.Update(ctx, p.ID, func(s *Session) error { s.Battle = nil; return nil }); err != nil {
		t.Fatal(err)
	}
	if _, err := st.Battle(ctx, p.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("pertarungan harus hilang, dapat %v", err)
	}
}

func TestUpdateRollsBackOnError(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "B")

	boom := errors.New("gagal di tengah")
	_, err := st.Update(ctx, p.ID, func(s *Session) error {
		s.Player.State.Gold = 999 // diubah dulu, lalu gagal
		s.Battle = &game.Battle{EnemyID: "tikus_sawah"}
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("error harus diteruskan, dapat %v", err)
	}
	after, _ := st.PlayerByID(ctx, p.ID)
	if after.State.Gold != 0 || after.Version != 1 {
		t.Errorf("perubahan harus dibatalkan: %+v", after)
	}
	if _, err := st.Battle(ctx, p.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("pertarungan tidak boleh tersimpan: %v", err)
	}
}

func TestSavePositionOnlyTouchesPosition(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "C")

	got, err := st.SavePosition(ctx, p.ID, game.Pose{Map: "desa_awal", X: 3, Y: 4, FX: 3.25, FZ: 4.75, Yaw: 1.5}, 1)
	if err != nil {
		t.Fatal(err)
	}
	if got.State.X != 3 || got.State.Y != 4 || got.State.FX != 3.25 || got.State.FZ != 4.75 || got.State.Yaw != 1.5 || got.Version != 2 || got.State.HP != p.State.HP {
		t.Errorf("hasil salah: %+v", got)
	}
	if _, err := st.SavePosition(ctx, p.ID, game.Pose{Map: "desa_awal", X: 1, Y: 1}, 1); !errors.Is(err, ErrConflict) {
		t.Errorf("versi lama harus ErrConflict, dapat %v", err)
	}
	if _, err := st.SavePosition(ctx, "tidak-ada", game.Pose{Map: "desa_awal", X: 1, Y: 1}, 1); !errors.Is(err, ErrNotFound) {
		t.Errorf("pemain tidak ada harus ErrNotFound, dapat %v", err)
	}
}

func TestBattleDeletedWithPlayerRow(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	p := newPlayer(t, st, "D")
	_, _ = st.Update(ctx, p.ID, func(s *Session) error { s.Battle = &game.Battle{EnemyID: "x"}; return nil })
	if _, err := st.db.ExecContext(ctx, `DELETE FROM players WHERE id = ?`, p.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := st.Battle(ctx, p.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("pertarungan harus ikut terhapus (ON DELETE CASCADE), dapat %v", err)
	}
}
