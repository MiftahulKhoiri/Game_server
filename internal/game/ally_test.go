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
	res, err := b.Sync(p, 1000, seq(20, 20, 99, 99))
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

func TestBuySoldiers(t *testing.T) {
	st := NewState()
	st.Gold = SoldierPrice*MaxSoldiers + 10
	for i := 0; i < MaxSoldiers; i++ {
		if err := st.BuySoldier(); err != nil {
			t.Fatalf("prajurit %d: %v", i, err)
		}
	}
	if st.Soldiers != MaxSoldiers || st.Gold != 10 {
		t.Fatalf("soldiers=%d gold=%d", st.Soldiers, st.Gold)
	}
	if err := st.BuySoldier(); !errors.Is(err, ErrSoldiersMax) {
		t.Fatalf("pasukan penuh harus ditolak: %v", err)
	}
	st.Soldiers = 2
	if err := st.BuySoldier(); !errors.Is(err, ErrNoGold) {
		t.Fatalf("emas kurang harus ditolak: %v", err)
	}
	st.Soldiers = MaxSoldiers + 1
	if err := st.Validate(); err == nil {
		t.Fatal("jumlah prajurit di luar batas harus ditolak")
	}
}

func TestSoldiersStrike(t *testing.T) {
	p := newPlayer()
	p.State.Soldiers = 3
	b := battleVs("tikus_sawah", 60)
	b.NextEnemyMs = 100000
	b.NextAllyMs = 1000
	res, err := b.Sync(p, 1000, seq(20, 20, 20, 99, 99))
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, e := range res.Events {
		if e.Who == "ally" && e.Hero == SoldierID(n+1) && e.Dmg >= 1 {
			n++
		}
	}
	if n != 3 {
		t.Fatalf("tiga prajurit harus menyerang, dapat %d: %+v", n, res.Events)
	}
}


func TestAllyHealthDefaultsAndHealing(t *testing.T) {
	st := NewState()
	st.Allies = []string{"ksatria"}
	st.Party = []string{"ksatria"}
	if hp, maxHP, ok := st.AllyHealth("ksatria"); !ok || hp != AllyMaxHP || maxHP != AllyMaxHP {
		t.Fatalf("akun lama harus memiliki HP penuh: hp=%d max=%d ok=%v", hp, maxHP, ok)
	}
	st.ensureAllyHealth()
	if remaining, down := st.damageAlly("ksatria", AllyMaxHP); !down || remaining != 0 {
		t.Fatalf("pendamping harus tumbang: hp=%d down=%v", remaining, down)
	}
	if _, err := st.HealAlly("ksatria", PotionHeal); err != nil {
		t.Fatalf("ramuan harus menyembuhkan pendamping tumbang: %v", err)
	}
	if hp, _, _ := st.AllyHealth("ksatria"); hp != PotionHeal {
		t.Fatalf("HP setelah sembuh=%d; ingin %d", hp, PotionHeal)
	}
	if _, err := st.HealAlly("ksatria", AllyMaxHP); err != nil {
		t.Fatal(err)
	}
	if hp, _, _ := st.AllyHealth("ksatria"); hp != AllyMaxHP {
		t.Fatalf("HP harus dibatasi maksimum: %d", hp)
	}
	if _, err := st.HealAlly("ksatria", 1); !errors.Is(err, ErrAllyFullHP) {
		t.Fatalf("HP penuh harus ditolak: %v", err)
	}
	if err := st.Validate(); err != nil {
		t.Fatalf("state pendamping tidak valid: %v", err)
	}
}

func TestDownAllyStopsAttackingAndCanBeIgnoredByEnemyTargeting(t *testing.T) {
	p := newPlayer()
	p.State.Allies = []string{"ksatria"}
	p.State.Party = []string{"ksatria"}
	p.State.AllyHP = map[string]int{"ksatria": 0}
	b := battleVs("tikus_sawah", 100)
	b.NextEnemyMs = 100000
	b.NextAllyMs = 1000
	res, err := b.Sync(p, 1000, seq(99))
	if err != nil { t.Fatal(err) }
	for _, ev := range res.Events {
		if ev.Who == "ally" { t.Fatalf("pendamping tumbang tidak boleh menyerang: %+v", ev) }
	}
	if res.Status != StatusOngoing { t.Fatalf("pertarungan harus berlanjut: %s", res.Status) }
}
