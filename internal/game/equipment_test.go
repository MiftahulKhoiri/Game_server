package game

import (
	"errors"
	"testing"
)

func TestEquipAddsStats(t *testing.T) {
	st := NewState()
	base, baseDef := st.Attack(), st.Defense()
	if base != AttackForLevel(1) || baseDef != DefenseForLevel(1) {
		t.Fatalf("tanpa perlengkapan harus sama dengan rumus level: %d %d", base, baseDef)
	}
	if err := st.Equip("pedang_besi"); !errors.Is(err, ErrNotEnough) {
		t.Errorf("belum punya: %v", err)
	}
	st.AddItem("pedang_besi", 1)
	st.AddItem("baju_kulit", 1)
	if err := st.Equip("pedang_besi"); err != nil {
		t.Fatal(err)
	}
	if err := st.Equip("baju_kulit"); err != nil {
		t.Fatal(err)
	}
	if st.Attack() != base+3 || st.Defense() != baseDef+2 {
		t.Errorf("serang %d (mau %d), tahan %d (mau %d)", st.Attack(), base+3, st.Defense(), baseDef+2)
	}
	// Senjata lebih baik menggantikan yang lama.
	st.AddItem("pedang_baja", 1)
	_ = st.Equip("pedang_baja")
	if st.Attack() != base+6 || st.Equipment.Weapon != "pedang_baja" {
		t.Errorf("harus berganti ke pedang baja: %+v", st.Equipment)
	}
	if err := st.Equip(PotionID); !errors.Is(err, ErrNotEquippable) {
		t.Errorf("ramuan bukan perlengkapan: %v", err)
	}
	if err := st.Equip("naga"); !errors.Is(err, ErrUnknownItem) {
		t.Errorf("barang asing: %v", err)
	}
	if err := st.Unequip(SlotWeapon); err != nil || st.Attack() != base {
		t.Errorf("lepas senjata: %v attack=%d", err, st.Attack())
	}
	if err := st.Unequip(SlotWeapon); !errors.Is(err, ErrNothingWorn) {
		t.Errorf("slot kosong: %v", err)
	}
	if err := st.Unequip("topi"); !errors.Is(err, ErrBadSlot) {
		t.Errorf("slot asing: %v", err)
	}
	if err := st.Validate(); err != nil {
		t.Error(err)
	}
}

func TestCannotSellLastEquippedCopy(t *testing.T) {
	st := NewState()
	st.AddItem("pedang_besi", 2)
	_ = st.Equip("pedang_besi")
	if err := Sell(&st, "pedang_besi", 2); !errors.Is(err, ErrEquipped) {
		t.Fatalf("menjual semua salinan yang dipakai harus ditolak: %v", err)
	}
	if err := Sell(&st, "pedang_besi", 1); err != nil {
		t.Fatalf("menjual satu salinan cadangan boleh: %v", err)
	}
	if st.itemQty("pedang_besi") != 1 || st.Equipment.Weapon != "pedang_besi" {
		t.Error("satu salinan harus tersisa dan tetap terpakai")
	}
	if err := Sell(&st, "pedang_besi", 1); !errors.Is(err, ErrEquipped) {
		t.Errorf("salinan terakhir yang dipakai: %v", err)
	}
	if err := Sell(&st, "pedang_rune", 1); !errors.Is(err, ErrNotBuyable) && !errors.Is(err, ErrNotEnough) {
		t.Errorf("pedang rune tidak dijual: %v", err)
	}
}

func TestEquipmentChangesBattleDamage(t *testing.T) {
	// seq: variasi kerusakan 100% (indeks 20 -> 80+20=100), tidak kritis, tidak ada drop.
	enemyHP := func(withSword bool) int {
		p := newPlayer()
		if withSword {
			p.State.AddItem("pedang_baja", 1)
			_ = p.State.Equip("pedang_baja")
		}
		b := battleVs("babi_hutan", 34)
		if _, err := act(b, p, ActionAttack, seq(20, 99, 20)); err != nil {
			t.Fatal(err)
		}
		return b.EnemyHP
	}
	if without, with := enemyHP(false), enemyHP(true); with >= without {
		t.Errorf("pedang harus menambah kerusakan: tanpa=%d dengan=%d (sisa HP musuh)", without, with)
	}
}

func TestUseItemAndRest(t *testing.T) {
	st := NewState()
	if err := st.UseItem(PotionID); !errors.Is(err, ErrFullHP) {
		t.Errorf("HP penuh: %v", err)
	}
	st.HP = 5
	if err := st.UseItem(PotionID); err != nil || st.HP != 5+PotionHeal || st.itemQty(PotionID) != 1 {
		t.Errorf("pakai ramuan: %v hp=%d ramuan=%d", err, st.HP, st.itemQty(PotionID))
	}
	if err := st.UseItem("taring_goblin"); !errors.Is(err, ErrNotUsable) {
		t.Errorf("bukan ramuan: %v", err)
	}
	if err := st.UseItem("naga"); !errors.Is(err, ErrUnknownItem) {
		t.Errorf("barang asing: %v", err)
	}
	st.RemoveItem(PotionID, 1)
	st.HP = 5
	if err := st.UseItem(PotionID); !errors.Is(err, ErrNoPotion) {
		t.Errorf("tanpa ramuan: %v", err)
	}
	if err := st.Rest(); err != nil || st.HP != st.MaxHP {
		t.Errorf("istirahat di desa: %v hp=%d", err, st.HP)
	}
	if err := st.Rest(); !errors.Is(err, ErrFullHP) {
		t.Errorf("sudah penuh: %v", err)
	}
	st.HP, st.Map = 3, MapPerbatasan
	if err := st.Rest(); !errors.Is(err, ErrCannotRest) || st.HP != 3 {
		t.Errorf("istirahat di luar desa harus ditolak: %v", err)
	}
}

func TestEquipmentCatalogConsistent(t *testing.T) {
	for _, it := range Items() {
		if (it.Kind == KindEquipment) != (it.Slot != "") {
			t.Errorf("%s: jenis equipment dan slot harus berpasangan", it.ID)
		}
		switch it.Slot {
		case SlotWeapon:
			if it.Attack <= 0 || it.Defense != 0 {
				t.Errorf("%s: senjata harus menambah serangan saja", it.ID)
			}
		case SlotArmor:
			if it.Defense <= 0 || it.Attack != 0 {
				t.Errorf("%s: pelindung harus menambah pertahanan saja", it.ID)
			}
		}
	}
}

// Roadmap no. 16: slot helm menambah pertahanan dan bisa dilepas.
func TestHelmetSlot(t *testing.T) {
	st := NewState()
	baseDef := st.Defense()
	st.AddItem("helm_besi", 1)
	st.AddItem("zirah_besi", 1)
	if err := st.Equip("helm_besi"); err != nil {
		t.Fatal(err)
	}
	if err := st.Equip("zirah_besi"); err != nil {
		t.Fatal(err)
	}
	if st.Equipment.Helmet != "helm_besi" || st.Defense() != baseDef+3+4 {
		t.Fatalf("helm + zirah: %+v def=%d", st.Equipment, st.Defense())
	}
	if !st.Equipment.Has("helm_besi") {
		t.Error("helm yang dipakai harus terhitung Has")
	}
	if err := st.Unequip(SlotHelmet); err != nil || st.Defense() != baseDef+4 {
		t.Errorf("lepas helm: %v def=%d", err, st.Defense())
	}
	if err := st.Validate(); err != nil {
		t.Error(err)
	}
}

// Roadmap no. 14: variasi pakaian 0..NumOutfits-1.
func TestOutfit(t *testing.T) {
	st := NewState()
	if err := st.SetOutfit(NumOutfits - 1); err != nil || st.Outfit != NumOutfits-1 {
		t.Fatalf("pakaian sah ditolak: %v", err)
	}
	for _, bad := range []int{-1, NumOutfits} {
		if err := st.SetOutfit(bad); !errors.Is(err, ErrUnknownOutfit) {
			t.Errorf("pakaian %d harus ditolak: %v", bad, err)
		}
	}
	st.Outfit = NumOutfits
	if err := st.Validate(); err == nil {
		t.Error("Validate harus menolak pakaian di luar rentang")
	}
}
