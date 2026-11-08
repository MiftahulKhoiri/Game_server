package game

import (
	"errors"
	"testing"
)

func trainer() *State {
	st := NewState()
	st.Map = MapAula
	st.Gold = 1000
	st.Allies = []string{"pemanah"}
	st.Party = []string{"pemanah"}
	st.Soldiers = 2
	st.AddItem(KartuKeahlianID, 5)
	return &st
}

func TestTrainHeroFlow(t *testing.T) {
	st := trainer()
	if err := st.StartTrain(TrainHero, "pemanah", 1000); err != nil {
		t.Fatal(err)
	}
	if st.Gold != 920 || st.itemQty(KartuKeahlianID) != 4 || st.Energy() != MaxEnergy-HeroTrainEnergy {
		t.Fatalf("biaya salah: emas %d kartu %d energi %d", st.Gold, st.itemQty(KartuKeahlianID), st.Energy())
	}
	if err := st.StartTrain(TrainHero, "pemanah", 1000); !errors.Is(err, ErrTrainBusy) {
		t.Fatalf("tempat latihan harus penuh: %v", err)
	}
	if err := st.ClaimTrain(TrainHero, 1000+HeroTrainSec-1); !errors.Is(err, ErrTrainNotReady) {
		t.Fatalf("belum selesai: %v", err)
	}
	if err := st.ClaimTrain(TrainHero, 1000+HeroTrainSec); err != nil {
		t.Fatal(err)
	}
	if st.HeroLevel("pemanah") != 2 || len(st.Training) != 0 {
		t.Fatalf("level %d, sisa latihan %d", st.HeroLevel("pemanah"), len(st.Training))
	}
	// level 2 -> 3 lebih lama dan lebih mahal
	g := st.Gold
	if err := st.StartTrain(TrainHero, "pemanah", 5000); err != nil {
		t.Fatal(err)
	}
	j, _ := st.TrainJobOf(TrainHero)
	if g-st.Gold != 160 || j.ReadyAt != 5000+2*HeroTrainSec || j.ToLevel != 3 {
		t.Fatalf("level 2: emas %d siap %d ke %d", g-st.Gold, j.ReadyAt, j.ToLevel)
	}
}

func TestTrainSoldierSquad(t *testing.T) {
	st := trainer()
	if err := st.StartTrain(TrainSoldier, "", 0); err != nil {
		t.Fatal(err)
	}
	if err := st.StartTrain(TrainHero, "pemanah", 0); err != nil {
		t.Fatalf("dua tempat latihan berjalan bersamaan: %v", err)
	}
	if err := st.ClaimTrain(TrainSoldier, SoldierTrainSec); err != nil {
		t.Fatal(err)
	}
	if st.SquadLevel() != 2 {
		t.Fatalf("level pasukan %d", st.SquadLevel())
	}
	base := st.Level
	_ = base
	if p1, p2 := (State{Level: 10, Soldiers: 1}).soldierPower(), (State{Level: 10, Soldiers: 1, SoldierLevel: 5}).soldierPower(); p2 <= p1 {
		t.Fatalf("latihan harus menambah serangan prajurit: %d %d", p1, p2)
	}
	if p1, p2 := (State{Level: 10, Allies: []string{"pemanah"}}).heroPower("pemanah"), (State{Level: 10, HeroLevels: map[string]int{"pemanah": 5}}).heroPower("pemanah"); p2 <= p1 {
		t.Fatalf("latihan harus menambah serangan pahlawan: %d %d", p1, p2)
	}
}

func TestTrainRules(t *testing.T) {
	st := trainer()
	st.Map = MapDesaAwal
	if err := st.StartTrain(TrainHero, "pemanah", 0); !errors.Is(err, ErrTrainLocation) {
		t.Fatalf("di luar aula: %v", err)
	}
	st.Map = MapAula
	if err := st.StartTrain(TrainHero, "ksatria", 0); !errors.Is(err, ErrAllyNotOwn) {
		t.Fatalf("pahlawan belum dibeli: %v", err)
	}
	if err := st.StartTrain("lain", "", 0); !errors.Is(err, ErrTrainKind) {
		t.Fatalf("jenis: %v", err)
	}
	st.Soldiers = 0
	if err := st.StartTrain(TrainSoldier, "", 0); !errors.Is(err, ErrTrainNoSquad) {
		t.Fatalf("tanpa prajurit: %v", err)
	}
	st.Gold = 10
	if err := st.StartTrain(TrainHero, "pemanah", 0); !errors.Is(err, ErrNoGold) {
		t.Fatalf("emas: %v", err)
	}
	st.Gold = 1000
	st.RemoveItem(KartuKeahlianID, 5)
	if err := st.StartTrain(TrainHero, "pemanah", 0); !errors.Is(err, ErrTrainNoCard) {
		t.Fatalf("kartu: %v", err)
	}
	st.AddItem(KartuKeahlianID, 1)
	st.EnergyUsed = MaxEnergy - HeroTrainEnergy + 1
	if err := st.StartTrain(TrainHero, "pemanah", 0); !errors.Is(err, ErrNoEnergy) {
		t.Fatalf("energi: %v", err)
	}
	if st.Gold != 1000 || st.itemQty(KartuKeahlianID) != 1 {
		t.Fatal("latihan yang gagal tidak boleh memotong biaya")
	}
	st.EnergyUsed = 0
	st.HeroLevels = map[string]int{"pemanah": MaxTrainLevel}
	if err := st.StartTrain(TrainHero, "pemanah", 0); !errors.Is(err, ErrTrainMax) {
		t.Fatalf("level maksimum: %v", err)
	}
	if err := st.ClaimTrain(TrainHero, 0); !errors.Is(err, ErrTrainNone) {
		t.Fatalf("klaim kosong: %v", err)
	}
	if err := st.Validate(); err != nil {
		t.Fatalf("state sah: %v", err)
	}
	st.HeroLevels = map[string]int{"hantu": 3}
	if err := st.Validate(); err == nil {
		t.Fatal("level pahlawan tak dikenal harus ditolak")
	}
}

func TestKartuKeahlianShopAndDrop(t *testing.T) {
	st := NewState()
	st.Gold = 200
	if err := BuyAt(&st, ShopGear, KartuKeahlianID, 2); err != nil || st.Gold != 80 || st.itemQty(KartuKeahlianID) != 2 {
		t.Fatalf("beli kartu: %v emas %d", err, st.Gold)
	}
	if err := BuyAt(&st, ShopPotion, KartuKeahlianID, 1); !errors.Is(err, ErrWrongShop) {
		t.Fatalf("kartu hanya di toko peralatan: %v", err)
	}
	p := &Player{State: NewState()}
	b := battleVs("tikus_sawah", 1)
	res, err := b.Act(p, ActionAttack, 1000, seq(20, 99, 99, 0)) // tanpa drop biasa, kartu jatuh
	if err != nil || res.Status != StatusWon {
		t.Fatalf("menang: %v %v", err, res.Status)
	}
	if p.State.itemQty(KartuKeahlianID) != 1 {
		t.Fatalf("kartu keahlian harus jatuh, jumlah %d", p.State.itemQty(KartuKeahlianID))
	}
}
