package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
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
	p, err := st.CreatePlayer(context.Background(), "id-"+name, name, strings.ToLower(name)+"@contoh.id", "pw-"+name, "hash-"+name, game.NewState())
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

// legacyV1 adalah skema sebelum akun (v0.15.x): satu token per pemain di players.token_hash.
const legacyV1 = `
CREATE TABLE players (
	id         TEXT PRIMARY KEY,
	name       TEXT NOT NULL UNIQUE COLLATE NOCASE,
	token_hash TEXT NOT NULL UNIQUE,
	state      TEXT NOT NULL,
	version    INTEGER NOT NULL DEFAULT 1,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);
CREATE TABLE battles (
	player_id  TEXT PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
	state      TEXT NOT NULL,
	updated_at TEXT NOT NULL
);
INSERT INTO players VALUES ('p1', 'Lama', 'tokenlama', '{"level":3,"hp":20,"max_hp":38,"gold":50}', 7, '2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z');
INSERT INTO battles VALUES ('p1', '{"enemy_id":"tikus_sawah","enemy_hp":5,"enemy_max_hp":10,"round":2}', '2026-01-02T00:00:00Z');`

func TestMigrateFromV1KeepsPlayersTokensAndBattles(t *testing.T) {
	path := filepath.Join(t.TempDir(), "lama.db")
	raw, err := sql.Open("sqlite", "file:"+path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := raw.Exec(legacyV1); err != nil {
		t.Fatal(err)
	}
	raw.Close()

	st, err := Open(path)
	if err != nil {
		t.Fatalf("migrasi gagal: %v", err)
	}
	defer st.Close()
	ctx := context.Background()

	p, err := st.PlayerByTokenHash(ctx, "tokenlama")
	if err != nil || p.ID != "p1" || p.Name != "Lama" || p.Version != 7 || p.State.Level != 3 || p.State.Gold != 50 {
		t.Fatalf("pemain lama harus utuh dan token lama tetap berlaku: %+v %v", p, err)
	}
	if b, err := st.Battle(ctx, "p1"); err != nil || b.EnemyID != "tikus_sawah" || b.Round != 2 {
		t.Errorf("pertarungan lama tidak boleh hilang saat migrasi: %+v %v", b, err)
	}
	// Akun lama belum punya kata sandi: ditemukan lewat nama, tetapi hash kosong.
	if _, hash, err := st.PlayerByLogin(ctx, "lama"); err != nil || hash != "" {
		t.Errorf("akun lama harus punya hash kosong: %q %v", hash, err)
	}
	// Akun baru bisa dibuat di database hasil migrasi.
	if _, err := st.CreatePlayer(ctx, "p2", "Baru", "baru@contoh.id", "pw", "tokenbaru", game.NewState()); err != nil {
		t.Fatalf("buat akun baru setelah migrasi: %v", err)
	}
	var ver int
	if err := st.db.QueryRow(`PRAGMA user_version`).Scan(&ver); err != nil || ver != schemaVersion {
		t.Errorf("user_version harus %d, dapat %d (%v)", schemaVersion, ver, err)
	}
	// Foreign key tetap hidup setelah migrasi: menghapus pemain ikut menghapus sesi dan pertarungannya.
	if _, err := st.db.Exec(`DELETE FROM players WHERE id = 'p1'`); err != nil {
		t.Fatal(err)
	}
	var n int
	st.db.QueryRow(`SELECT (SELECT COUNT(*) FROM sessions WHERE player_id = 'p1') + (SELECT COUNT(*) FROM battles WHERE player_id = 'p1')`).Scan(&n)
	if n != 0 {
		t.Errorf("ON DELETE CASCADE harus berfungsi setelah migrasi, sisa %d baris", n)
	}

	// Membuka lagi database yang sudah v2 tidak mengubah apa pun.
	st.Close()
	st2, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	st2.Close()
}

func TestAccountUniquenessAndSessions(t *testing.T) {
	st, ctx := newStore(t), context.Background()
	newPlayer(t, st, "Budi")

	if _, err := st.CreatePlayer(ctx, "x1", "budi", "lain@contoh.id", "pw", "h1", game.NewState()); !errors.Is(err, ErrNameTaken) {
		t.Errorf("nama kembar harus ErrNameTaken, dapat %v", err)
	}
	if _, err := st.CreatePlayer(ctx, "x2", "Citra", "BUDI@contoh.id", "pw", "h2", game.NewState()); !errors.Is(err, ErrEmailTaken) {
		t.Errorf("email kembar harus ErrEmailTaken, dapat %v", err)
	}
	// Pendaftaran yang gagal tidak boleh meninggalkan sesi yatim.
	if _, err := st.PlayerByTokenHash(ctx, "h1"); !errors.Is(err, ErrNotFound) {
		t.Errorf("sesi dari pendaftaran gagal tidak boleh ada: %v", err)
	}

	p, hash, err := st.PlayerByLogin(ctx, "budi@contoh.id")
	if err != nil || p.Name != "Budi" || p.Email != "budi@contoh.id" || hash != "pw-Budi" {
		t.Fatalf("login lewat email: %+v %q %v", p, hash, err)
	}
	if _, _, err := st.PlayerByLogin(ctx, "tidak-ada"); !errors.Is(err, ErrNotFound) {
		t.Errorf("harus ErrNotFound, dapat %v", err)
	}

	// Sesi dibatasi maxSessions; yang tertua dibuang.
	for i := 0; i < maxSessions+3; i++ {
		if err := st.CreateSession(ctx, p.ID, fmt.Sprintf("tok-%02d", i)); err != nil {
			t.Fatal(err)
		}
	}
	var n int
	st.db.QueryRow(`SELECT COUNT(*) FROM sessions WHERE player_id = ?`, p.ID).Scan(&n)
	if n != maxSessions {
		t.Errorf("sesi harus dibatasi %d, dapat %d", maxSessions, n)
	}
	if _, err := st.PlayerByTokenHash(ctx, "hash-Budi"); !errors.Is(err, ErrNotFound) {
		t.Errorf("sesi tertua harus sudah dibuang: %v", err)
	}
	if _, err := st.PlayerByTokenHash(ctx, fmt.Sprintf("tok-%02d", maxSessions+2)); err != nil {
		t.Errorf("sesi terbaru harus ada: %v", err)
	}
	if err := st.DeleteSession(ctx, "tok-12"); err != nil {
		t.Fatal(err)
	}
	if _, err := st.PlayerByTokenHash(ctx, "tok-12"); !errors.Is(err, ErrNotFound) {
		t.Errorf("sesi yang dihapus harus hilang: %v", err)
	}
	if err := st.DeleteSession(ctx, "tidak-ada"); err != nil {
		t.Errorf("menghapus sesi yang tidak ada bukan error: %v", err)
	}
}
