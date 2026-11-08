package game

import (
	"errors"
	"testing"
)

func TestBuyAllyAndParty(t *testing.T) {
	st := NewState()
	st.Gold = 700
	if err := st.BuyAlly("pemanah"); err != nil {
		t.Fatal(err)
	}
	if st.Gold != 400 || !st.HasAlly("pemanah") || len(st.Party) != 1 {
		t.Fatalf("beli pemanah: gold=%d allies=%v party=%v", st.Gold, st.Allies, st.Party)
	}
	if err := st.BuyAlly("pemanah"); !errors.Is(err, ErrAllyOwned) {
		t.Fatalf("beli dua kali harus ditolak: %v", err)
	}
	if err := st.BuyAlly("pendekar_kapak"); err != nil || st.Gold != 50 {
		t.Fatalf("beli kapak: %v gold=%d", err, st.Gold)
	}
	if err := st.BuyAlly("ksatria"); !errors.Is(err, ErrNoGold) {
		t.Fatalf("emas kurang harus ditolak: %v", err)
	}
	if err := st.BuyAlly("naga"); !errors.Is(err, ErrUnknownHero) {
		t.Fatalf("pahlawan asing: %v", err)
	}
	if err := st.SetParty([]string{"pendekar_kapak"}); err != nil || len(st.Party) != 1 {
		t.Fatalf("set party: %v %v", err, st.Party)
	}
	if err := st.SetParty([]string{"ksatria"}); !errors.Is(err, ErrAllyNotOwn) {
		t.Fatalf("belum dibeli: %v", err)
	}
	if err := st.SetParty([]string{"pemanah", "pemanah"}); !errors.Is(err, ErrPartyRepeat) {
		t.Fatalf("dobel: %v", err)
	}
	if err := st.SetParty(nil); err != nil || len(st.Party) != 0 {
		t.Fatalf("kosongkan: %v %v", err, st.Party)
	}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
	st.Party = []string{"tidak_ada"}
	if err := st.Validate(); err == nil {
		t.Fatal("Validate harus menolak pendamping yang belum dibeli")
	}
}

func TestPartyFullLimit(t *testing.T) {
	st := NewState()
	st.Gold = 5000
	for _, h := range Heroes {
		if err := st.BuyAlly(h.ID); err != nil {
			t.Fatal(err)
		}
	}
	if len(st.Allies) != 4 || len(st.Party) != MaxParty {
		t.Fatalf("allies=%v party=%v", st.Allies, st.Party)
	}
	if err := st.SetParty(st.Allies); !errors.Is(err, ErrPartyFull) {
		t.Fatalf("4 pendamping harus ditolak: %v", err)
	}
}

func TestAlliesStrikeAndWin(t *testing.T) {
	p := newPlayer()
	p.State.Allies = []string{"ksatria", "pemanah"}
	p.State.Party = []string{"ksatria", "pemanah"}
	b := battleVs("tikus_sawah", 10)
	b.NextEnemyMs = 100000 // musuh tidak menyerang
	b.NextAllyMs = 1000
	// variasi 20 = 100% kerusakan
	res, err := b.Sync(p, 1000, seq(20, 20, 99))
	if err != nil {
		t.Fatal(err)
	}
	allies := 0
	for _, e := range res.Events {
		if e.Who == "ally" {
			allies++
			if e.Hero == "" || e.Dmg < 1 {
				t.Fatalf("event pendamping tidak lengkap: %+v", e)
			}
		}
	}
	if allies == 0 {
		t.Fatal("pendamping harus menyerang")
	}
	if b.NextAllyMs != 1000+AllyIntervalMs && res.Status == StatusOngoing {
		t.Fatalf("jadwal pendamping tidak maju: %d", b.NextAllyMs)
	}
	// Ayam Liar HP 10: dua pendamping (tiap ~6) menumbangkannya.
	if res.Status != StatusWon || p.State.XP == 0 {
		t.Fatalf("status=%s xp=%d", res.Status, p.State.XP)
	}
}

func TestNoAlliesNoAllyEvents(t *testing.T) {
	p := newPlayer()
	b := battleVs("tikus_sawah", 10)
	b.NextEnemyMs = 100000
	res, _ := b.Sync(p, 50000, seq())
	for _, e := range res.Events {
		if e.Who == "ally" {
			t.Fatal("tanpa pendamping tidak boleh ada serangan pendamping")
		}
	}
}
