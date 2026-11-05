package game

import (
	"errors"
	"testing"
)

// seq mengembalikan Rand yang memberi angka berurutan (diambil modulo n).
// Urutan panggilan dalam satu ronde:
//
//	serang  : variasi(41), kritis(100), [musuh: variasi(41)], [menang: drop(100)]
//	bertahan: [musuh: variasi(41)]
//	ramuan  : [musuh: variasi(41)]
//	kabur   : peluang(100), [gagal -> musuh: variasi(41)]
//
// Variasi 20 = 100% kerusakan; kritis 99 = tidak kritis; drop 99 = tidak jatuh.
func seq(vals ...int) Rand {
	i := 0
	return RandFunc(func(n int) int {
		if i >= len(vals) {
			panic("seq habis: tes memanggil Rand lebih banyak dari yang disiapkan")
		}
		v := vals[i] % n
		i++
		return v
	})
}

func newPlayer() *Player { return &Player{State: NewState()} }

func battleVs(enemyID string, hp int) *Battle {
	e, _ := EnemyByID(enemyID)
	return &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: hp, EnemyMaxHP: e.HP, Round: 1}
}

func TestAttackKillsAndRewards(t *testing.T) {
	p := newPlayer()
	b := battleVs("tikus_sawah", 5)
	res, err := b.Act(p, ActionAttack, seq(20, 99, 99))
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != StatusWon || b.EnemyHP != 0 {
		t.Fatalf("harus menang: %+v, hp musuh %d", res, b.EnemyHP)
	}
	if p.State.XP != 6 || p.State.Gold != 2 || p.State.Level != 1 {
		t.Errorf("hadiah salah: %+v", p.State)
	}
	if res.Rewards == nil || res.Rewards.XP != 6 || res.Rewards.LeveledUp {
		t.Errorf("rewards salah: %+v", res.Rewards)
	}
}

func TestLevelUp(t *testing.T) {
	p := newPlayer()
	p.State.XP = 18
	b := battleVs("tikus_sawah", 1)
	res, err := b.Act(p, ActionAttack, seq(20, 99, 99))
	if err != nil {
		t.Fatal(err)
	}
	if !res.Rewards.LeveledUp || res.Rewards.NewLevel != 2 {
		t.Fatalf("harus naik level: %+v", res.Rewards)
	}
	if p.State.Level != 2 || p.State.XP != 4 || p.State.MaxHP != 38 || p.State.HP != 38 {
		t.Errorf("state setelah naik level salah: %+v", p.State)
	}
	if err := p.State.Validate(); err != nil {
		t.Errorf("state tidak valid: %v", err)
	}
}

func TestDropAddsItem(t *testing.T) {
	p := newPlayer() // mulai dengan 2 ramuan
	b := battleVs("tikus_sawah", 1)
	res, _ := b.Act(p, ActionAttack, seq(20, 99, 0)) // drop 0 < 10%
	if res.Rewards.Drop != PotionID || p.State.Inventory[0].Qty != 3 {
		t.Errorf("harus dapat ramuan: %+v %+v", res.Rewards, p.State.Inventory)
	}
}

func TestEnemyRetaliates(t *testing.T) {
	p := newPlayer()
	b := battleVs("tikus_sawah", 10)
	res, err := b.Act(p, ActionAttack, seq(20, 99, 20))
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != StatusOngoing || b.EnemyHP != 4 || p.State.HP != 29 || b.Round != 2 {
		t.Errorf("ronde salah: status=%s hp musuh=%d hp pemain=%d ronde=%d", res.Status, b.EnemyHP, p.State.HP, b.Round)
	}
	if len(res.Log) != 2 {
		t.Errorf("log harus 2 baris: %v", res.Log)
	}
}

func TestDefendHalvesDamage(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 34) // serang 8 - bertahan 2 = 6, dibagi 2 = 3
	if _, err := b.Act(p, ActionDefend, seq(20)); err != nil {
		t.Fatal(err)
	}
	if p.State.HP != 27 {
		t.Errorf("HP = %d; mau 27", p.State.HP)
	}
}

func TestPotion(t *testing.T) {
	p := newPlayer()
	p.State.HP = 10
	b := battleVs("tikus_sawah", 10)
	if _, err := b.Act(p, ActionPotion, seq(20)); err != nil {
		t.Fatal(err)
	}
	if p.State.HP != 24 { // 10 + 15 - 1 serangan tikus
		t.Errorf("HP = %d; mau 24", p.State.HP)
	}
	if p.State.Inventory[0].Qty != 1 {
		t.Errorf("ramuan harus tersisa 1: %+v", p.State.Inventory)
	}
}

func TestPotionRejected(t *testing.T) {
	p := newPlayer() // HP penuh
	b := battleVs("tikus_sawah", 10)
	if _, err := b.Act(p, ActionPotion, seq()); !errors.Is(err, ErrFullHP) {
		t.Errorf("HP penuh harus ErrFullHP, dapat %v", err)
	}
	if p.State.Inventory[0].Qty != 2 {
		t.Error("ramuan tidak boleh terpakai saat ditolak")
	}

	p.State.HP = 5
	p.State.Inventory = []Item{}
	if _, err := b.Act(p, ActionPotion, seq()); !errors.Is(err, ErrNoPotion) {
		t.Errorf("tanpa ramuan harus ErrNoPotion, dapat %v", err)
	}
}

func TestFlee(t *testing.T) {
	p := newPlayer()
	b := battleVs("tikus_sawah", 10)
	res, _ := b.Act(p, ActionFlee, seq(0))
	if res.Status != StatusFled || p.State.HP != 30 {
		t.Errorf("kabur berhasil: status=%s hp=%d", res.Status, p.State.HP)
	}

	res, _ = b.Act(p, ActionFlee, seq(99, 20))
	if res.Status != StatusOngoing || p.State.HP != 29 {
		t.Errorf("kabur gagal harus kena serang: status=%s hp=%d", res.Status, p.State.HP)
	}
}

func TestLoseRespawns(t *testing.T) {
	p := newPlayer()
	p.State.HP, p.State.Gold = 1, 11
	p.State.Map, p.State.X, p.State.Y = "peta_lain", 9, 9
	b := battleVs("tikus_sawah", 10)
	res, _ := b.Act(p, ActionFlee, seq(99, 20))
	if res.Status != StatusLost {
		t.Fatalf("harus kalah: %+v", res)
	}
	s := p.State
	if s.HP != 15 || s.Gold != 6 || s.Map != SpawnMap || s.X != SpawnX || s.Y != SpawnY {
		t.Errorf("pemulangan salah: %+v", s)
	}
}

func TestBadAction(t *testing.T) {
	b := battleVs("tikus_sawah", 10)
	if _, err := b.Act(newPlayer(), "teleport", seq()); !errors.Is(err, ErrBadAction) {
		t.Errorf("harus ErrBadAction, dapat %v", err)
	}
}

func TestPickEnemyRespectsLevel(t *testing.T) {
	for i := 0; i < 300; i++ {
		if e := PickEnemy(1, RandomSource{}); e.MinLevel > 1 {
			t.Fatalf("level 1 bertemu %s (butuh level %d)", e.ID, e.MinLevel)
		}
	}
	seen := map[string]bool{}
	for i := 0; i < 500; i++ {
		seen[PickEnemy(5, RandomSource{}).ID] = true
	}
	if len(seen) != len(enemies) {
		t.Errorf("level 5 harus bisa bertemu semua musuh, dapat %v", seen)
	}
}

func TestInventoryHelpers(t *testing.T) {
	var s State
	if !s.AddItem("a", 5) || !s.AddItem("a", 3) || s.Inventory[0].Qty != 8 {
		t.Fatalf("AddItem salah: %+v", s.Inventory)
	}
	if !s.AddItem("a", MaxStack) || s.Inventory[0].Qty != MaxStack {
		t.Errorf("harus dibatasi MaxStack: %+v", s.Inventory)
	}
	if s.RemoveItem("a", MaxStack+1) {
		t.Error("tidak boleh mengurangi lebih dari yang ada")
	}
	if !s.RemoveItem("a", MaxStack) || len(s.Inventory) != 0 {
		t.Errorf("tumpukan kosong harus hilang: %+v", s.Inventory)
	}
	if s.RemoveItem("tidak_ada", 1) {
		t.Error("barang tidak ada harus false")
	}
}

func TestBalanceFirstFightsAreWinnable(t *testing.T) {
	// Pemain level 1 yang hanya menyerang harus bisa mengalahkan musuh level 1 tanpa mati.
	for _, id := range []string{"tikus_sawah", "belalang_raksasa"} {
		p := newPlayer()
		b := battleVs(id, mustEnemy(id).HP)
		for round := 0; round < 50 && p.State.HP > 0; round++ {
			res, err := b.Act(p, ActionAttack, RandomSource{})
			if err != nil {
				t.Fatal(err)
			}
			if res.Status != StatusOngoing {
				if res.Status != StatusWon {
					t.Errorf("%s: pemain level 1 kalah", id)
				}
				break
			}
		}
	}
}

func mustEnemy(id string) Enemy {
	e, ok := EnemyByID(id)
	if !ok {
		panic("musuh tidak ada: " + id)
	}
	return e
}
