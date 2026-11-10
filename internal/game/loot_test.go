package game

import (
	"errors"
	"testing"
	"time"
)

var t0 = time.Unix(1_700_000_000, 0)

func always(v int) Rand { return RandFunc(func(n int) int { return v % n }) }

// Berdiri di petak (x, z) di desa.
func standAt(x, z int) State {
	st := NewState()
	st.Map = MapDesaAwal
	st.FX, st.FZ = float64(x)+0.5, float64(z)+0.5
	return st
}

func TestBreakGivesGoldAndRespawns(t *testing.T) {
	st := standAt(10, 10)
	obj := []BreakTarget{{Kind: KindPohon, X: 11, Z: 10}}
	loot, err := st.BreakObjects(t0, obj, always(0)) // undian terendah: emas minimum
	if err != nil {
		t.Fatal(err)
	}
	if loot.Gold != 3*11/10 || loot.Broken != 1 || st.Gold != loot.Gold {
		t.Errorf("hadiah %+v, emas pemain %d", loot, st.Gold)
	}
	// Petak yang sama masih tumbuh: tidak ada hadiah baru.
	again, err := st.BreakObjects(t0.Add(time.Second), obj, always(0))
	if err != nil || again.Broken != 0 || again.Gold != 0 {
		t.Errorf("harus tanpa hadiah: %+v, %v", again, err)
	}
	// Sesudah masa tumbuh ulang, dapat lagi.
	later, err := st.BreakObjects(t0.Add((BreakRespawnSec+1)*time.Second), obj, always(0))
	if err != nil || later.Broken != 1 {
		t.Errorf("harus dapat lagi: %+v, %v", later, err)
	}
}

func TestBreakItems(t *testing.T) {
	cases := []struct {
		kind string
		roll int
		want string
	}{
		{KindPohon, 43, DiamondID},
		{KindPohon, 45, PowerPotionID},
		{KindPohon, 36, PotionID},
		{KindBatu, 40, DiamondID},
		{KindRumput, 21, PotionID},
	}
	for _, c := range cases {
		st := standAt(5, 5)
		loot, err := st.BreakObjects(t0, []BreakTarget{{Kind: c.kind, X: 5, Z: 5}}, always(c.roll))
		if err != nil {
			t.Fatal(err)
		}
		// Selain hadiah undian, tiap benda memberi satu bahan alam (v0.56.0).
		if st.itemQty(c.want) < 1 || len(loot.Items) != 2 || loot.Items[0].ID != c.want || loot.Items[1].ID != materialOf(c.kind) {
			t.Errorf("%s undian %d: dapat %+v, mau %s", c.kind, c.roll, loot.Items, c.want)
		}
	}
	st := standAt(5, 5)
	if loot, _ := st.BreakObjects(t0, []BreakTarget{{Kind: KindRumput, X: 5, Z: 5}}, always(99)); loot.Gold != 0 || len(loot.Items) != 1 || loot.Items[0].ID != SeratID || loot.Broken != 1 {
		t.Errorf("undian 99: hanya bahan (serat): %+v", loot)
	}
}

func TestBreakRejects(t *testing.T) {
	st := standAt(10, 10)
	cases := []struct {
		name string
		objs []BreakTarget
		want error
	}{
		{"jenis salah", []BreakTarget{{Kind: "pagar", X: 10, Z: 10}}, ErrBadObject},
		{"kosong", nil, ErrBadObject},
		{"terlalu banyak", make([]BreakTarget, MaxBreakBatch+1), ErrBadObject},
		{"di luar peta", []BreakTarget{{Kind: KindPohon, X: 999, Z: 10}}, ErrBadObject},
		{"jauh", []BreakTarget{{Kind: KindPohon, X: 20, Z: 10}}, ErrTooFar},
	}
	for _, c := range cases {
		if _, err := st.BreakObjects(t0, c.objs, always(0)); !errors.Is(err, c.want) {
			t.Errorf("%s: err = %v, mau %v", c.name, err, c.want)
		}
	}
	if st.Gold != 0 || len(st.Broken) != 0 {
		t.Errorf("permintaan ditolak tidak boleh mengubah apa pun: %+v", st)
	}
}

func TestBreakTooFast(t *testing.T) {
	st := standAt(10, 10)
	if _, err := st.BreakObjects(t0, []BreakTarget{{Kind: KindBatu, X: 10, Z: 11}}, always(0)); err != nil {
		t.Fatal(err)
	}
	_, err := st.BreakObjects(t0.Add(20*time.Millisecond), []BreakTarget{{Kind: KindBatu, X: 11, Z: 11}}, always(0))
	if !errors.Is(err, ErrTooFast) {
		t.Errorf("err = %v, mau ErrTooFast", err)
	}
}

func TestBrokenListIsBounded(t *testing.T) {
	st := standAt(10, 10)
	st.Broken = map[string]int64{}
	for i := 0; i < maxBrokenKept+500; i++ {
		st.Broken[brokenKey(MapDesaAwal, KindRumput, i, 0)] = t0.Unix() + int64(i)
	}
	st.pruneBroken(t0.Unix() + 10)
	if len(st.Broken) > maxBrokenKept {
		t.Errorf("catatan %d melebihi batas %d", len(st.Broken), maxBrokenKept)
	}
}

func TestOpenChest(t *testing.T) {
	c, _ := ChestByID("perbatasan_1")
	st := NewState()
	st.Map, st.FX, st.FZ = c.Map, float64(c.X)+0.5, float64(c.Y)+0.5
	st.Level = 5
	if _, err := (&State{Map: MapDesaAwal, FX: 3, FZ: 3}).OpenChest(t0, "perbatasan_1", always(0)); !errors.Is(err, ErrTooFar) {
		t.Errorf("peta salah: %v", err)
	}
	if _, err := st.OpenChest(t0, "tidak_ada", always(0)); !errors.Is(err, ErrUnknownChest) {
		t.Errorf("peti tak dikenal: %v", err)
	}
	loot, err := st.OpenChest(t0, "perbatasan_1", always(0))
	if err != nil {
		t.Fatal(err)
	}
	if loot.Gold != 40*2*15/10 || st.Gold != loot.Gold {
		t.Errorf("emas %d (pemain %d)", loot.Gold, st.Gold)
	}
	if n := len(loot.Items); n != ChestRewards-1 {
		t.Errorf("peti berisi %d jenis barang di samping emas, harus %d: %+v", n, ChestRewards-1, loot.Items)
	}
	if st.itemQty(DiamondID) != 0 {
		t.Errorf("tanpa keberuntungan tidak ada berlian: %+v", st.Inventory)
	}
	if _, err := st.OpenChest(t0.Add(time.Minute), "perbatasan_1", always(0)); !errors.Is(err, ErrChestEmpty) {
		t.Errorf("peti harus kosong: %v", err)
	}
	if _, err := st.OpenChest(t0.Add((ChestRespawnSec+5)*time.Second), "perbatasan_1", always(0)); err != nil {
		t.Errorf("peti harus terisi lagi: %v", err)
	}
}

func TestChestsAreOnKnownMaps(t *testing.T) {
	seen := map[string]bool{}
	for _, c := range Chests() {
		if seen[c.ID] {
			t.Errorf("id peti ganda: %s", c.ID)
		}
		seen[c.ID] = true
		if !ValidPosition(c.Map, c.X, c.Y) {
			t.Errorf("peti %s di luar peta", c.ID)
		}
		if c.Tier < 1 || c.Tier > 4 {
			t.Errorf("peti %s tier %d", c.ID, c.Tier)
		}
	}
}

func TestWorldView(t *testing.T) {
	st := standAt(10, 10)
	st.BreakObjects(t0, []BreakTarget{{Kind: KindPohon, X: 11, Z: 10}}, always(99))
	v := st.WorldView(t0.Add(100*time.Second), MapDesaAwal)
	if len(v) != 1 || v[0].Kind != KindPohon || v[0].X != 11 || v[0].Left != BreakRespawnSec-100 {
		t.Errorf("tampilan %+v", v)
	}
	if len(st.WorldView(t0.Add(100*time.Second), MapPerbatasan)) != 0 {
		t.Error("peta lain harus kosong")
	}
	if len(st.WorldView(t0.Add((BreakRespawnSec+1)*time.Second), MapDesaAwal)) != 0 {
		t.Error("sesudah tumbuh ulang harus kosong")
	}
}

func TestPowerPotion(t *testing.T) {
	st := NewState()
	base := st.Attack()
	if err := st.UseItem(PowerPotionID); !errors.Is(err, ErrNoPower) {
		t.Fatalf("tanpa ramuan: %v", err)
	}
	st.AddItem(PowerPotionID, 1)
	if err := st.UseItem(PowerPotionID); err != nil {
		t.Fatal(err)
	}
	if st.Attack() != base*PowerPercent/100 || st.PowerLeft != PowerBattles || st.itemQty(PowerPotionID) != 0 {
		t.Errorf("serangan %d (dasar %d), sisa %d", st.Attack(), base, st.PowerLeft)
	}
	for i := 0; i < PowerBattles; i++ {
		st.endBattleBuffs()
	}
	if st.PowerLeft != 0 || st.Attack() != base {
		t.Errorf("setelah %d pertarungan harus habis: sisa %d", PowerBattles, st.PowerLeft)
	}
}

func TestOpenChestLuckyDiamond(t *testing.T) {
	c, _ := ChestByID("perbatasan_1") // tier 2: total bobot 99, berlian di 92..98
	st := NewState()
	st.Map, st.FX, st.FZ = c.Map, float64(c.X)+0.5, float64(c.Y)+0.5
	loot, err := st.OpenChest(t0, "perbatasan_1", seq(95, 0, 0, 0))
	if err != nil {
		t.Fatal(err)
	}
	if st.itemQty(DiamondID) != 1 || loot.Gold == 0 || len(loot.Items) != 2 {
		t.Errorf("tiga hadiah dengan berlian: emas %d barang %+v", loot.Gold, loot.Items)
	}
}

func TestBarterDiamond(t *testing.T) {
	st := NewState()
	st.AddItem(DiamondID, 3)
	if err := BarterAt(&st, ShopGear, "zirah_besi", 1); err != nil || st.itemQty(DiamondID) != 2 || st.itemQty("zirah_besi") != 1 {
		t.Fatalf("zirah 240 emas = 1 berlian: %v %+v", err, st.Inventory)
	}
	if err := BarterAt(&st, ShopGear, KartuKeahlianID, 9); err != nil || st.itemQty(DiamondID) != 0 { // 9x60 = 540 emas = 2 berlian
		t.Fatalf("9 kartu = 2 berlian: %v %+v", err, st.Inventory)
	}
	if err := BarterAt(&st, ShopGear, "pedang_baja", 4); !errors.Is(err, ErrNoDiamond) { // 1280 = 3 berlian
		t.Fatalf("berlian kurang: %v", err)
	}
	if err := BarterAt(&st, ShopPotion, "zirah_besi", 1); !errors.Is(err, ErrWrongShop) {
		t.Fatalf("toko salah: %v", err)
	}
	if err := BarterAt(&st, ShopGear, "pedang_rune", 1); !errors.Is(err, ErrNotForSale) {
		t.Fatalf("tidak dijual: %v", err)
	}
	if st.Gold != NewState().Gold {
		t.Fatal("barter tidak memakai emas")
	}
	sell := NewState()
	sell.AddItem(DiamondID, 1)
	if err := Sell(&sell, DiamondID, 1); err != nil || sell.Gold != NewState().Gold+DiamondGold {
		t.Fatalf("jual berlian: %v emas %d", err, sell.Gold)
	}
}
