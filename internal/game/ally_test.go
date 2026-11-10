package game

import (
	"encoding/json"
	"errors"
	"strings"
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
	if len(st.Allies) != len(Heroes) || len(st.Party) != MaxParty {
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

func TestDeploySoldiers(t *testing.T) {
	st := NewState()
	st.Soldiers = 4
	if st.ActiveSoldiers() != 4 {
		t.Fatalf("data lama: semua prajurit ikut, dapat %d", st.ActiveSoldiers())
	}
	if err := st.SetActiveSoldiers(2); err != nil || st.ActiveSoldiers() != 2 || st.SoldiersRest != 2 {
		t.Fatalf("pasang 2: %v aktif=%d rest=%d", err, st.ActiveSoldiers(), st.SoldiersRest)
	}
	if err := st.SetActiveSoldiers(5); !errors.Is(err, ErrSoldiersCount) {
		t.Errorf("melebihi jumlah prajurit harus ditolak: %v", err)
	}
	if err := st.SetActiveSoldiers(-1); !errors.Is(err, ErrSoldiersCount) {
		t.Errorf("negatif harus ditolak: %v", err)
	}
	st.Gold = SoldierPrice
	if err := st.BuySoldier(); err != nil || st.ActiveSoldiers() != 3 {
		t.Errorf("prajurit baru ikut bertarung: %v aktif=%d", err, st.ActiveSoldiers())
	}
	if err := st.SetActiveSoldiers(0); err != nil || st.ActiveSoldiers() != 0 {
		t.Fatalf("pasang 0: %v", err)
	}
	st.SoldiersRest = st.Soldiers + 1
	if err := st.Validate(); err == nil {
		t.Error("soldiers_rest di luar batas harus ditolak")
	}
	// Hanya prajurit yang dipasang yang menyerang.
	p := newPlayer()
	p.State.Soldiers = 3
	if err := p.State.SetActiveSoldiers(1); err != nil {
		t.Fatal(err)
	}
	b := battleVs("tikus_sawah", 60)
	b.NextEnemyMs = 100000
	b.NextAllyMs = 1000
	res, err := b.Sync(p, 1000, seq(20, 20, 20, 99, 99))
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, e := range res.Events {
		if e.Who == "ally" {
			n++
		}
	}
	if n != 1 {
		t.Fatalf("hanya satu prajurit yang dipasang harus menyerang, dapat %d", n)
	}
	p.State.SoldiersRest = 3
	b2 := battleVs("tikus_sawah", 60)
	b2.NextEnemyMs = 100000
	b2.NextAllyMs = 1000
	res2, _ := b2.Sync(p, 1000, seq(20, 20, 20, 99, 99))
	for _, e := range res2.Events {
		if e.Who == "ally" {
			t.Fatal("tanpa prajurit terpasang tidak boleh ada serangan prajurit")
		}
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
	if err != nil {
		t.Fatal(err)
	}
	for _, ev := range res.Events {
		if ev.Who == "ally" {
			t.Fatalf("pendamping tumbang tidak boleh menyerang: %+v", ev)
		}
	}
	if res.Status != StatusOngoing {
		t.Fatalf("pertarungan harus berlanjut: %s", res.Status)
	}
}

func TestEnemyCanDownCompanionAfterThreeStrikes(t *testing.T) {
	p := newPlayer()
	p.State.Allies = []string{"ksatria"}
	p.State.Party = []string{"ksatria"}
	p.State.AllyHP = map[string]int{"ksatria": 1}
	b := battleVs("tikus_sawah", 1000)
	b.NextEnemyMs = 1000
	b.NextAllyMs = 100000 // cegah serangan balasan pendamping dalam tes ini

	for _, now := range []int64{1000, 3000, 5000} {
		res, err := b.Sync(p, now, seq(20))
		if err != nil {
			t.Fatal(err)
		}
		if now == 5000 {
			foundDown := false
			for _, ev := range res.Events {
				if ev.Who == "ally" && ev.Hero == "ksatria" && ev.Kind == "down" {
					foundDown = true
				}
			}
			if !foundDown {
				t.Fatalf("serangan musuh ketiga harus menumbangkan pendamping: %+v", res.Events)
			}
		}
	}
	if hp, _, _ := p.State.AllyHealth("ksatria"); hp != 0 {
		t.Fatalf("HP pendamping harus 0: %d", hp)
	}
	if p.State.HP >= p.State.MaxHP {
		t.Fatalf("dua serangan pertama harus mengenai pemain: %d", p.State.HP)
	}
}

func TestAllyHPAcceptsDecimalWholeNumbers(t *testing.T) {
	var st State
	if err := json.Unmarshal([]byte(`{"ally_hp":{"ksatria":30.0,"pemanah":0.0,"pendekar_kapak":12}}`), &st); err != nil {
		t.Fatalf("30.0 harus diterima: %v", err)
	}
	if st.AllyHP["ksatria"] != 30 || st.AllyHP["pemanah"] != 0 || st.AllyHP["pendekar_kapak"] != 12 {
		t.Fatalf("hasil salah: %v", st.AllyHP)
	}
	for _, bad := range []string{`{"ally_hp":{"ksatria":30.5}}`, `{"ally_hp":{"ksatria":"30"}}`, `{"ally_hp":{"ksatria":1e30}}`} {
		var s2 State
		if err := json.Unmarshal([]byte(bad), &s2); err == nil {
			t.Errorf("%s harus ditolak", bad)
		}
	}
	var s3 State
	if err := json.Unmarshal([]byte(`{"ally_hp":null}`), &s3); err != nil || s3.AllyHP != nil {
		t.Errorf("null harus jadi kosong: %v %v", err, s3.AllyHP)
	}
}

// v0.66.0: prajurit punya HP menurut level pasukan, menerima serangan, dan gugur selamanya.
func TestSoldiersTakeHitsAndFall(t *testing.T) {
	p := newPlayer()
	p.State.Soldiers = 3
	p.State.HP, p.State.MaxHP = 500, 500
	if p.State.SoldierMaxHP() != SoldierBaseHP {
		t.Fatalf("HP prajurit level 1 = %d", p.State.SoldierMaxHP())
	}
	b := battleVs("goblin_hutan_3", 100000) // musuh sangat kuat: prajurit tumbang cepat
	b.NextAllyMs = 10_000_000
	b.NextEnemyMs = 1000
	var res Result
	var err error
	for i := 0; i < 30 && p.State.Soldiers > 0; i++ {
		res, err = b.Sync(p, b.NextEnemyMs, seq(50, 50, 50, 50))
		if err != nil {
			t.Fatal(err)
		}
		if res.Status != StatusOngoing {
			break
		}
	}
	if p.State.Soldiers != 0 || len(b.SoldierHP) != 0 {
		t.Fatalf("semua prajurit harus gugur: tersisa %d, hp %v", p.State.Soldiers, b.SoldierHP)
	}
	if err := p.State.Validate(); err != nil {
		t.Errorf("state setelah prajurit gugur tidak sah: %v", err)
	}
	// Level pasukan menaikkan HP prajurit.
	q := NewState()
	q.SoldierLevel = 5
	if q.SoldierMaxHP() != SoldierBaseHP+4*SoldierHPLevel {
		t.Errorf("HP prajurit level 5 = %d", q.SoldierMaxHP())
	}
	// Prajurit yang disimpan di kem tidak ikut terkena.
	r := newPlayer()
	r.State.Soldiers, r.State.SoldiersRest = 4, 4
	b2 := battleVs("goblin_hutan_3", 100000)
	b2.NextAllyMs = 10_000_000
	b2.NextEnemyMs = 1000
	r.State.HP, r.State.MaxHP = 5000, 5000
	_, _ = b2.Sync(r, 1000, seq(50, 50))
	if r.State.Soldiers != 4 || b2.SoldierHP != nil {
		t.Errorf("prajurit di kem tidak boleh ikut: %d %v", r.State.Soldiers, b2.SoldierHP)
	}
}

func TestManySoldiersOneLogLine(t *testing.T) {
	p := newPlayer()
	p.State.Soldiers = 30
	b := battleVs("goblin_hutan_3", 100000)
	b.NextEnemyMs = 10_000_000
	b.NextAllyMs = 1000
	rolls := make([]int, 100)
	for i := range rolls {
		rolls[i] = 20
	}
	res, err := b.Sync(p, 1000, seq(rolls...))
	if err != nil {
		t.Fatal(err)
	}
	events, lines := 0, 0
	for _, e := range res.Events {
		if e.Who == "ally" && e.Kind == "attack" {
			events++
		}
	}
	for _, l := range res.Log {
		if strings.Contains(l, "Pasukan 30 prajurit") {
			lines++
		}
	}
	if events != maxSoldierEvents || lines != 1 || len(b.SoldierHP) != 30 {
		t.Errorf("30 prajurit: %d kejadian, %d baris log, %d HP", events, lines, len(b.SoldierHP))
	}
}
