package game

import (
	"math/rand"
	"slices"
	"testing"
)

func playerAs(hero string) *Player {
	p := newPlayer()
	p.State.Hero = hero
	return p
}

func TestEveryHeroHasStyle(t *testing.T) {
	seen := map[string]bool{}
	for _, h := range Heroes {
		if _, ok := WeaponStyles[h.Style]; !ok {
			t.Errorf("%s: gaya %q tidak dikenal", h.ID, h.Style)
		}
		seen[h.Style] = true
	}
	for id := range WeaponStyles {
		if !seen[id] {
			t.Errorf("gaya %s tidak dipakai pahlawan mana pun", id)
		}
	}
}

func TestStyleCooldownAndView(t *testing.T) {
	p := playerAs("pendekar_kapak")
	b := StartBattleWith(p, "babi_hutan", seq(0, 0, 0, 0, 0), 0)
	if v := b.View(0); v.CooldownMax[ActionAttack] != WeaponStyles[StyleKapak].AttackMs {
		t.Fatalf("isi ulang kapak di tampilan: %d", v.CooldownMax[ActionAttack])
	}
	b.NextEnemyMs, b.EnemyHP = 100_000, 999
	if _, err := b.Act(p, ActionAttack, 0, seq(20, 99)); err != nil {
		t.Fatal(err)
	}
	if _, err := b.Act(p, ActionAttack, 1000, seq(20, 99)); err == nil {
		t.Fatal("kapak belum siap setelah 1000 ms")
	}
	if _, err := b.Act(p, ActionAttack, 1200, seq(20, 99)); err != nil {
		t.Fatalf("kapak siap setelah 1200 ms: %v", err)
	}
}

func TestStyleDamage(t *testing.T) {
	dmg := func(hero, enemy string) int {
		p := playerAs(hero)
		b := battleVs(enemy, 999)
		b.NextEnemyMs = 100_000
		if _, err := b.Act(p, ActionAttack, 0, seq(20, 99)); err != nil {
			t.Fatal(err)
		}
		return 999 - b.EnemyHP
	}
	pedang, kapak, tombak := dmg("ksatria", "babi_hutan"), dmg("pendekar_kapak", "babi_hutan"), dmg("pendekar_tombak", "babi_hutan")
	if !(kapak > pedang && pedang > tombak) {
		t.Errorf("kapak > pedang > tombak per pukulan: %d %d %d", kapak, pedang, tombak)
	}
	// Sihir menembus pertahanan: unggul melawan musuh berpertahanan tinggi.
	if s, k := dmg("penyihir", "golem_kerikil"), dmg("ksatria", "golem_kerikil"); s <= k {
		t.Errorf("sihir harus unggul melawan golem: sihir %d, pedang %d", s, k)
	}
}

func TestComboThirdHit(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 999)
	b.NextEnemyMs = 100_000
	var kinds []string
	for i, at := range []int64{0, 900, 1800, 2700} {
		res, err := b.Act(p, ActionAttack, at, seq(20, 99))
		if err != nil {
			t.Fatalf("serangan %d: %v", i, err)
		}
		kinds = append(kinds, res.Events[0].Kind)
	}
	if !slices.Equal(kinds, []string{"attack", "attack", "combo", "attack"}) {
		t.Fatalf("urutan kombo: %v", kinds)
	}
	// Jeda terlalu lama memutus kombo.
	b2 := battleVs("babi_hutan", 999)
	b2.NextEnemyMs = 100_000
	for _, at := range []int64{0, 900, 900 + 900 + ComboWindowMs + 1} {
		res, _ := b2.Act(p, ActionAttack, at, seq(20, 99))
		if res.Events[0].Kind == "combo" {
			t.Fatal("kombo harus putus setelah jeda panjang")
		}
	}
}

func TestComboBrokenByHit(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 999)
	b.NextEnemyMs = 1500
	_, _ = b.Act(p, ActionAttack, 0, seq(20, 99))
	_, _ = b.Act(p, ActionAttack, 900, seq(20, 99))
	res, err := b.Act(p, ActionAttack, 1800, seq(20, 20, 99)) // musuh memukul di 1500 dulu
	if err != nil {
		t.Fatal(err)
	}
	if res.Events[len(res.Events)-1].Kind == "combo" {
		t.Fatalf("terkena pukulan harus memutus kombo: %+v", res.Events)
	}
}

func TestDodgeMakesEnemyMiss(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 34)
	b.NextEnemyMs = 1300
	if _, err := b.Act(p, ActionDodge, 1000, seq()); err != nil {
		t.Fatal(err)
	}
	hp := p.State.HP
	res, err := b.Sync(p, 1400, seq(20))
	if err != nil {
		t.Fatal(err)
	}
	if p.State.HP != hp || len(res.Events) != 1 || res.Events[0].Kind != "miss" {
		t.Fatalf("harus meleset: hp %d->%d %+v", hp, p.State.HP, res.Events)
	}
	// Terlambat menghindar: kena.
	b.NextEnemyMs = 1000 + CooldownMs[ActionDodge] + DodgeMs + 400
	if _, err := b.Act(p, ActionDodge, 1000+CooldownMs[ActionDodge], seq()); err != nil {
		t.Fatal(err)
	}
	if _, err := b.Sync(p, b.NextEnemyMs, seq(20)); err != nil {
		t.Fatal(err)
	}
	if p.State.HP >= hp {
		t.Fatal("serangan di luar jendela hindar harus kena")
	}
	if _, err := b.Act(p, ActionDodge, 1000+CooldownMs[ActionDodge]+10, seq()); err == nil {
		t.Fatal("hindar harus punya isi ulang")
	}
}

// --- roadmap no. 170: uji keseimbangan ---

type simResult struct {
	wins, fights int
	totalMs      int64
}

// simulate: pemain sederhana menyerang secepat mungkin, memakai jurus 1 bila energi cukup, dan
// minum ramuan (3 buah) saat HP di bawah 30%. Tanpa bertahan/menghindar dan tanpa pendamping.
func simulate(hero, enemy string, level, n int, seed int64) simResult {
	r := rand.New(rand.NewSource(seed))
	rng := RandFunc(func(k int) int { return r.Intn(k) })
	var out simResult
	for range n {
		p := playerAs(hero)
		p.State.Level = level
		p.State.MaxHP = p.State.MaxHPNow()
		p.State.HP = p.State.MaxHP
		p.State.AddItem(PotionID, 3)
		e := mustEnemy(enemy)
		b := styled(p, newBattle(e, 0))
		out.fights++
		for now := int64(0); now < 120_000; now += 50 {
			var res Result
			var err error
			switch {
			case p.State.HP*10 < p.State.MaxHP*3 && b.Ready[ActionPotion] <= now && p.State.HP < p.State.MaxHP && potions(p) > 0:
				res, err = b.Act(p, ActionPotion, now, rng)
			case b.Ready[ActionSkill1] <= now && p.State.Energy() >= p.State.skillCost(Skill1Energy):
				res, err = b.Act(p, ActionSkill1, now, rng)
			case b.Ready[ActionAttack] <= now:
				res, err = b.Act(p, ActionAttack, now, rng)
			default:
				res, err = b.Sync(p, now, rng)
			}
			if err != nil {
				continue
			}
			if res.Status != StatusOngoing {
				if res.Status == StatusWon {
					out.wins++
					out.totalMs += now
				}
				break
			}
		}
	}
	return out
}

func TestBalanceHeroesVsEnemies(t *testing.T) {
	if testing.Short() {
		t.Skip("simulasi panjang")
	}
	const n = 120
	avgByHero := map[string]float64{}
	count := 0
	for _, e := range enemies {
		if e.Boss {
			continue
		}
		count++
		lv := max(1, e.MinLevel)
		for _, h := range Heroes {
			r := simulate(h.ID, e.ID, lv, n, int64(len(e.ID)*31+len(h.ID)))
			rate := float64(r.wins) / float64(r.fights)
			if rate < 0.6 {
				t.Errorf("%s (lv %d) vs %s: menang hanya %.0f%%", h.ID, lv, e.ID, rate*100)
			}
			if r.wins > 0 {
				avgByHero[h.ID] += float64(r.totalMs) / float64(r.wins)
			}
		}
	}
	base := avgByHero[DefaultHero] / float64(count)
	for id, total := range avgByHero {
		avg := total / float64(count)
		t.Logf("%-16s rata-rata waktu menang %.1f d", id, avg/1000)
		if avg > base*1.3 || avg < base*0.7 {
			t.Errorf("%s terlalu jauh dari patokan Ksatria: %.1f d vs %.1f d", id, avg/1000, base/1000)
		}
	}
}

func potions(p *Player) int {
	for _, it := range p.State.Inventory {
		if it.ID == PotionID {
			return it.Qty
		}
	}
	return 0
}
