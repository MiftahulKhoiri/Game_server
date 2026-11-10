package game

import (
	"errors"
	"testing"
)

// Roadmap no. 145: menempa memakai bahan dan hanya di desa.
func TestCraft(t *testing.T) {
	st := NewState()
	if err := st.Craft("pedang_besi", 1); !errors.Is(err, ErrNotEnough) {
		t.Fatalf("bahan kurang: %v", err)
	}
	st.AddItem(BatuID, 6)
	st.AddItem(KayuID, 3)
	st.Map = MapPerbatasan
	if err := st.Craft("pedang_besi", 1); !errors.Is(err, ErrCraftFar) {
		t.Fatalf("hanya di desa: %v", err)
	}
	st.Map = MapDesaAwal
	if err := st.Craft("pedang_besi", 1); err != nil {
		t.Fatal(err)
	}
	if st.itemQty("pedang_besi") != 1 || st.itemQty(BatuID) != 0 || st.itemQty(KayuID) != 0 || st.Crafted != 1 {
		t.Fatalf("hasil tempa: %+v crafted=%d", st.Inventory, st.Crafted)
	}
	if !st.achieved("tempa_1") {
		t.Error("pencapaian Pengrajin harus terbuka")
	}
	if err := st.Craft("naga", 1); !errors.Is(err, ErrUnknownRecipe) {
		t.Errorf("resep asing: %v", err)
	}
}

// Roadmap no. 139: pohon kemampuan dengan poin dari level dan prasyarat.
func TestTalents(t *testing.T) {
	st := NewState()
	if err := st.LearnTalent("tajam"); !errors.Is(err, ErrNoTalentPoints) {
		t.Fatalf("level 1 belum punya poin: %v", err)
	}
	st.Level = 6 // 5 poin
	atk := st.Attack()
	for i := 0; i < 3; i++ {
		if err := st.LearnTalent("tajam"); err != nil {
			t.Fatal(err)
		}
	}
	if st.Attack() != atk+6 {
		t.Errorf("tajam 3 = serangan +6: %d -> %d", atk, st.Attack())
	}
	if err := st.LearnTalent("hemat_tenaga"); !errors.Is(err, ErrTalentLocked) {
		t.Errorf("butuh vitalitas 2: %v", err)
	}
	if err := st.LearnTalent("mata_elang"); err != nil || st.CritPercent() != CritChance+4 {
		t.Errorf("mata elang: %v crit=%d", err, st.CritPercent())
	}
	hp := st.MaxHPNow()
	if err := st.LearnTalent("vitalitas"); err != nil || st.MaxHP != hp+10 {
		t.Errorf("vitalitas: %v maxhp=%d", err, st.MaxHP)
	}
	if err := st.LearnTalent("vitalitas"); !errors.Is(err, ErrNoTalentPoints) {
		t.Errorf("poin habis: %v", err)
	}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
	st.Talent["tajam"] = 9
	if err := st.Validate(); err == nil {
		t.Error("peringkat di atas maksimum harus ditolak")
	}
}

// Roadmap no. 150: pencapaian terbuka otomatis, hadiahnya diambil sekali.
func TestAchievements(t *testing.T) {
	st := NewState()
	st.Level = 5
	st.checkAchievements()
	if !st.achieved("level_5") || st.achieved("level_10") {
		t.Fatalf("level 5: %v", st.Done)
	}
	if err := st.ClaimAchievement("level_10"); !errors.Is(err, ErrAchievementLocked) {
		t.Errorf("belum terbuka: %v", err)
	}
	g := st.Gold
	if err := st.ClaimAchievement("level_5"); err != nil || st.Gold != g+50 {
		t.Errorf("ambil hadiah: %v gold=%d", err, st.Gold)
	}
	if err := st.ClaimAchievement("level_5"); !errors.Is(err, ErrAchievementTaken) {
		t.Errorf("dua kali: %v", err)
	}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
}

// Roadmap no. 144: kelangkaan barang.
func TestRarity(t *testing.T) {
	if Rarity("pedang_rune") != "epik" || Rarity("permata_merah") != "langka" || Rarity(PotionID) != "biasa" {
		t.Error("kelangkaan salah")
	}
	if d, _ := ItemByID("pedang_rune"); d.Rarity != "epik" {
		t.Error("katalog barang harus membawa kelangkaan")
	}
}
