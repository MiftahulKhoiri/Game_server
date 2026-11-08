package game

import (
	"errors"
	"testing"
)

var quiet = RandFunc(func(n int) int { return n - 1 }) // tanpa kritis, tanpa drop

func TestEnergyRules(t *testing.T) {
	st := NewState()
	if st.Energy() != MaxEnergy {
		t.Fatalf("energi awal harus penuh: %d", st.Energy())
	}
	if !st.spendEnergy(Skill1Energy) || st.Energy() != MaxEnergy-Skill1Energy {
		t.Fatalf("pakai energi: %d", st.Energy())
	}
	if st.spendEnergy(MaxEnergy) {
		t.Fatal("energi kurang harus ditolak")
	}
	st.gainEnergy(1000)
	if st.Energy() != MaxEnergy {
		t.Fatalf("isi melebihi penuh: %d", st.Energy())
	}
	st.EnergyUsed = MaxEnergy + 1
	if st.Validate() == nil {
		t.Fatal("energi terpakai di luar batas harus ditolak")
	}
}

func TestSkillsCostEnergy(t *testing.T) {
	p := Player{State: NewState()}
	b := newBattle(mustEnemy("tikus_sawah"), 0)
	b.EnemyHP, b.EnemyMaxHP = 100000, 100000
	p.State.EnergyUsed = MaxEnergy - Skill1Energy + 1 // kurang 1 dari biaya
	if _, err := b.Act(&p, ActionSkill1, 10_000, quiet); !errors.Is(err, ErrNoEnergy) {
		t.Fatalf("skill1 tanpa energi: %v", err)
	}
	if _, err := b.Act(&p, ActionSkill2, 10_000, quiet); !errors.Is(err, ErrNoEnergy) {
		t.Fatalf("skill2 tanpa energi: %v", err)
	}
	if _, err := b.Act(&p, ActionAttack, 10_000, quiet); err != nil {
		t.Fatal(err)
	}
	if p.State.Energy() != Skill1Energy-1+EnergyPerAttack {
		t.Fatalf("serangan biasa mengisi energi: %d", p.State.Energy())
	}
	before := p.State.Energy()
	if _, err := b.Act(&p, ActionSkill1, 20_000, quiet); err != nil {
		t.Fatal(err)
	}
	if p.State.Energy() != before-Skill1Energy {
		t.Fatalf("skill1 menguras energi: %d", p.State.Energy())
	}
}

func TestPowerPotionRestoresEnergy(t *testing.T) {
	st := NewState()
	st.EnergyUsed = 80
	st.AddItem(PowerPotionID, 1)
	if err := st.UseItem(PowerPotionID); err != nil {
		t.Fatal(err)
	}
	if st.Energy() != MaxEnergy-80+EnergyPowerPotion || st.PowerLeft != PowerBattles {
		t.Fatalf("ramuan kekuatan: energi=%d buff=%d", st.Energy(), st.PowerLeft)
	}
}

func TestRestRefillsEnergy(t *testing.T) {
	st := NewState()
	st.EnergyUsed = 50
	if err := st.Rest(); err != nil || st.EnergyUsed != 0 {
		t.Fatalf("istirahat saat HP penuh tapi energi kurang: %v %d", err, st.EnergyUsed)
	}
	if err := st.Rest(); !errors.Is(err, ErrFullHP) {
		t.Fatalf("semua penuh: %v", err)
	}
}

func TestShopsAndFood(t *testing.T) {
	st := NewState()
	st.Gold = 500
	if err := BuyAt(&st, ShopFood, PotionID, 1); !errors.Is(err, ErrWrongShop) {
		t.Fatalf("ramuan di rumah makan: %v", err)
	}
	if err := BuyAt(&st, ShopPotion, "roti", 1); !errors.Is(err, ErrWrongShop) {
		t.Fatalf("roti di toko ramuan: %v", err)
	}
	if err := BuyAt(&st, "pasar", "roti", 1); !errors.Is(err, ErrUnknownShop) {
		t.Fatalf("toko asing: %v", err)
	}
	if err := BuyAt(&st, ShopPotion, PowerPotionID, 2); err != nil || st.Gold != 420 {
		t.Fatalf("beli ramuan kekuatan: %v gold=%d", err, st.Gold)
	}
	if err := BuyAt(&st, ShopFood, "sup_ayam", 2); err != nil || st.Gold != 380 {
		t.Fatalf("beli sup: %v gold=%d", err, st.Gold)
	}
	if err := st.UseItem("sup_ayam"); !errors.Is(err, ErrFullHP) {
		t.Fatalf("makan saat HP penuh: %v", err)
	}
	st.HP = 5
	if err := st.UseItem("sup_ayam"); err != nil || st.HP != 30 || st.itemQty("sup_ayam") != 1 {
		t.Fatalf("makan sup: %v hp=%d", err, st.HP)
	}
	if err := SellAt(&st, ShopPotion, "sup_ayam", 1); !errors.Is(err, ErrNotBuyable) {
		t.Fatalf("toko ramuan tidak beli makanan: %v", err)
	}
	if err := SellAt(&st, ShopFood, PowerPotionID, 1); !errors.Is(err, ErrNotBuyable) {
		t.Fatalf("rumah makan hanya beli makanan: %v", err)
	}
	if err := SellAt(&st, ShopFood, "sup_ayam", 1); err != nil {
		t.Fatalf("jual sup: %v", err)
	}
	list, err := ShopItems(ShopFood)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range list {
		if it.Kind != KindFood {
			t.Errorf("rumah makan memuat %s (%s)", it.ID, it.Kind)
		}
	}
	if _, err := ShopItems("pasar"); !errors.Is(err, ErrUnknownShop) {
		t.Fatalf("katalog toko asing: %v", err)
	}
}

func TestRestInsideVillageBuildings(t *testing.T) {
	for _, m := range []string{MapDesaAwal, MapTokoRamuan, MapRumahMakan, MapRumahSehat} {
		st := NewState()
		st.Map, st.HP, st.EnergyUsed = m, 3, 40
		if err := st.Rest(); err != nil || st.HP != st.MaxHP || st.EnergyUsed != 0 {
			t.Errorf("istirahat di %s: %v hp=%d", m, err, st.HP)
		}
		if m != MapDesaAwal && (!ValidPosition(m, 8, 7) || ValidPosition(m, 9, 7) || ValidPosition(m, 8, 8)) {
			t.Errorf("ukuran peta %s harus 9x8", m)
		}
	}
	st := NewState()
	st.Map, st.HP = MapPerbatasan, 3
	if err := st.Rest(); !errors.Is(err, ErrCannotRest) {
		t.Fatalf("istirahat di luar desa: %v", err)
	}
}

func TestGearShop(t *testing.T) {
	st := NewState()
	st.Gold = 500
	if err := BuyAt(&st, ShopPotion, "pedang_besi", 1); !errors.Is(err, ErrWrongShop) {
		t.Fatalf("pedang di toko ramuan: %v", err)
	}
	if err := BuyAt(&st, ShopGear, PotionID, 1); !errors.Is(err, ErrWrongShop) {
		t.Fatalf("ramuan di toko peralatan: %v", err)
	}
	if err := BuyAt(&st, ShopGear, "pedang_besi", 1); err != nil || st.Gold != 380 {
		t.Fatalf("beli pedang: %v gold=%d", err, st.Gold)
	}
	if err := SellAt(&st, ShopPotion, "pedang_besi", 1); !errors.Is(err, ErrNotBuyable) {
		t.Fatalf("toko ramuan tidak beli perlengkapan: %v", err)
	}
	if err := SellAt(&st, ShopGear, "pedang_besi", 1); err != nil {
		t.Fatalf("jual pedang: %v", err)
	}
	list, err := ShopItems(ShopGear)
	if err != nil || len(list) == 0 {
		t.Fatalf("katalog peralatan: %v %d", err, len(list))
	}
	for _, it := range list {
		if it.Kind != KindEquipment && it.ID != KartuKeahlianID {
			t.Errorf("toko peralatan memuat %s (%s)", it.ID, it.Kind)
		}
	}
	pot, _ := ShopItems(ShopPotion)
	for _, it := range pot {
		if it.Kind == KindEquipment {
			t.Errorf("toko ramuan memuat perlengkapan %s", it.ID)
		}
	}
}
