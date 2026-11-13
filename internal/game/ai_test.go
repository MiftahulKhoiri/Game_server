package game

import (
	"encoding/json"
	"testing"
)

// AI hybrid musuh (ai.go, v0.78.0).

func TestProfileFor(t *testing.T) {
	cases := map[string]string{
		"goblin": "goblin", "goblin_pemburu": "goblin", "goblin_hutan_1": "goblin",
		"orc_gua": "orc", "ogre_rawa": "orc", "kepala_goblin_2": "orc", "raja_goblin": "orc",
		"serigala_hutan": "serigala", "serigala_lava": "serigala",
		"ular_sawah": "ular", "ular_tulang": "ular", "babi_hutan": "babi", "babi_bayangan": "babi",
		"kelelawar_gua": "kelelawar", "belalang_raksasa": "belalang", "golem_lava": "golem",
		"naga_api": "naga", "ogre_gunung_1": "naga", AldragorID: "naga", MalzarethID: "malzareth",
		"tikus_sawah": "biasa", "kancil_hutan": "biasa",
	}
	for id, want := range cases {
		e, ok := EnemyByID(id)
		if !ok {
			t.Fatalf("musuh %s tidak ada", id)
		}
		if got := ProfileFor(e).ID; got != want {
			t.Errorf("%s: profil %s, mau %s", id, got, want)
		}
	}
}

// AI tidak memakai angka acak tambahan: tiap serangan musuh tetap memakai tepat satu angka acak, apa pun
// profilnya (urutan acak pertarungan lama tidak berubah).
func TestAIUsesNoExtraRandomness(t *testing.T) {
	for _, e := range enemies {
		p := newPlayer()
		p.State.HP, p.State.MaxHP = 100000, 100000
		b := &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1, NextEnemyMs: 1000}
		calls := 0
		rng := RandFunc(func(n int) int { calls++; return 0 })
		var res Result
		for i := 0; i < 12; i++ {
			b.settle(p, e, b.NextEnemyMs, rng, &res)
		}
		if calls != 12 {
			t.Errorf("%s: %d angka acak untuk 12 serangan", e.ID, calls)
		}
	}
}

func syncAt(b *Battle, p *Player, rng Rand) Result {
	r, _ := b.Sync(p, b.NextEnemyMs, rng)
	return r
}

func TestOrcHeavyEveryThirdWithRecovery(t *testing.T) {
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 1000, 1000
	b := battleVs("orc_gua", 56)
	var tactics []string
	for i := 0; i < 6; i++ {
		before := b.NextEnemyMs
		res := syncAt(b, p, seq(20))
		tactics = append(tactics, res.Events[0].Tactic)
		gap := b.NextEnemyMs - before
		e, _ := EnemyByID("orc_gua")
		base := enemyInterval(e) * 110 / 100
		if res.Events[0].Tactic == TacticHeavy && gap != base+700 {
			t.Errorf("serangan berat harus diikuti pemulihan: jeda %d, mau %d", gap, base+700)
		}
	}
	want := []string{"", "", TacticHeavy, "", "", TacticHeavy}
	for i := range want {
		if tactics[i] != want[i] {
			t.Fatalf("pola taktik orc %v, mau %v", tactics, want)
		}
	}
	if b.Intent != "" || b.AIState != AIRecover {
		t.Errorf("setelah serangan ke-6: niat %q keadaan %q", b.Intent, b.AIState)
	}
}

func TestGoblinRetreatsOnceWhenLosing(t *testing.T) {
	p := newPlayer()
	b := battleVs("goblin", 5) // HP 5 dari 34: di bawah 25%
	b.Round = 2
	hp := p.State.HP
	res := syncAt(b, p, seq(20))
	if len(res.Events) != 1 || res.Events[0].Kind != "retreat" || p.State.HP != hp || !b.Retreated {
		t.Fatalf("goblin lemah harus mundur tanpa menyerang: %+v hp=%d", res.Events, p.State.HP)
	}
	// Selama bertahan, pukulan pemain hanya separuh (dibanding pertarungan yang sama tanpa bertahan).
	at := b.NextEnemyMs - 1000
	plain := *b
	plain.EnemyGuardUntil = 0
	b.Ready, plain.Ready = nil, nil
	b.EnemyHP, plain.EnemyHP = 30, 30
	r1, _ := b.Act(p, ActionAttack, at, seq(99, 99))
	p2 := newPlayer()
	r2, _ := plain.Act(p2, ActionAttack, at, seq(99, 99))
	if r1.Events[0].Dmg != max(1, r2.Events[0].Dmg/2) {
		t.Errorf("kerusakan saat goblin bertahan harus separuh: %d vs %d", r1.Events[0].Dmg, r2.Events[0].Dmg)
	}
	// Mundur hanya sekali per pertarungan.
	b.EnemyHP = 5
	res = syncAt(b, p, seq(20))
	if res.Events[0].Kind == "retreat" {
		t.Error("goblin mundur dua kali")
	}
}

func TestEvasiveEnemyDodgesHeavySkill(t *testing.T) {
	p := newPlayer()
	p.State.EnergyUsed = 0
	b := battleVs("kelelawar_gua", 30)
	b.NextEnemyMs = 100000
	res, err := b.Act(p, ActionSkill1, 1000, seq(99, 99))
	if err != nil {
		t.Fatal(err)
	}
	// Pembanding: musuh berpertahanan sama tanpa profil lincah.
	ref := battleVs("rubah_hutan", 300)
	ref.NextEnemyMs = 100000
	p2 := newPlayer()
	full, err := ref.Act(p2, ActionSkill1, 1000, seq(99, 99))
	if err != nil {
		t.Fatal(err)
	}
	if res.Events[0].Dmg != max(1, full.Events[0].Dmg*EvadePct/100) {
		t.Errorf("kelelawar harus menghindar sebagian: %d, penuh %d", res.Events[0].Dmg, full.Events[0].Dmg)
	}
}

func TestDragonFireCannotBePerfectParried(t *testing.T) {
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 5000, 5000
	b := battleVs("naga_api", 300)
	b.Round = 3 // serangan ke-3 = semburan jarak jauh
	if _, err := b.Act(p, ActionDefend, b.NextEnemyMs-100, seq()); err != nil {
		t.Fatal(err)
	}
	res := syncAt(b, p, seq(20))
	if res.Events[0].Kind == "perfect" || res.Events[0].Tactic != TacticRanged || res.Events[0].Kind != "guard" {
		t.Errorf("semburan api tidak bisa ditangkis sempurna (tetap tertahan): %+v", res.Events)
	}
}

func TestAreaAttackHitsPartyAndFrontSoldiers(t *testing.T) {
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 5000, 5000
	p.State.Allies = []string{"pemanah", "pendekar_tombak"}
	p.State.Party = []string{"pemanah", "pendekar_tombak"}
	p.State.Soldiers = 5
	b := battleVs("golem_lava", 62)
	b.Round = 3 // serangan berat golem = area
	res := syncAt(b, p, seq(20))
	ally, soldiers, enemy := 0, 0, 0
	for _, ev := range res.Events {
		switch {
		case ev.Who == "enemy" && ev.Tactic == TacticArea:
			enemy++
		case ev.Who == "ally" && ev.Tactic == TacticArea && len(ev.Hero) > 9 && ev.Hero[:9] == "prajurit_":
			soldiers++
		case ev.Who == "ally" && ev.Tactic == TacticArea:
			ally++
		}
	}
	if enemy != 1 || ally != 2 || soldiers != areaSoldiers {
		t.Errorf("area: pemain %d, pendamping %d, prajurit %d (%+v)", enemy, ally, soldiers, res.Events)
	}
}

func TestPackFlanksHelpersOnEvenRounds(t *testing.T) {
	p := newPlayer()
	p.State.Soldiers = 4
	b := battleVs("serigala_hutan", 500)
	b.Round = 3
	b.NextAllyMs = 1 << 40 // prajurit belum menyerang, supaya kejadian pertama = serangan musuh
	zero := RandFunc(func(int) int { return 0 })
	syncAt(b, p, zero)
	res := syncAt(b, p, zero) // Round 4: genap, kawanan mengapit
	if len(res.Events) == 0 || res.Events[0].Who != "ally" {
		t.Errorf("serigala harus mengapit prajurit pada serangan genap: %+v", res.Events)
	}
	if v := b.View(b.NextEnemyMs); v.AIProfile != "serigala" {
		t.Errorf("View harus membawa profil AI: %+v", v)
	}
}

// Profil AI tidak boleh membuat musuh jauh lebih kuat/lemah: kerusakan per detik rata-rata 24 serangan
// (tanpa kemampuan khusus) dibanding perilaku lama tetap di 80%-125%.
func TestAIProfilesKeepBalance(t *testing.T) {
	for name, prof := range aiProfiles {
		b := &Battle{EnemyHP: 100, EnemyMaxHP: 100}
		var dmg, ms float64
		for r := 1; r <= 24; r++ {
			b.Round = r
			plan := b.assess(Enemy{}, prof, 80, 0)
			if plan.tactic == TacticRetreat {
				continue
			}
			dmg += float64(plan.dmgPct)
			ms += float64(EnemyIntervalMs*int64(plan.ivPct)/100 + plan.extraMs)
		}
		ratio := (dmg / ms) / (100.0 / float64(EnemyIntervalMs))
		if ratio < 0.8 || ratio > 1.25 {
			t.Errorf("profil %s: kerusakan per detik %.2fx perilaku lama", name, ratio)
		}
	}
}

// Pertarungan lama (tanpa kolom AI) tetap terbaca dan berjalan.
func TestOldBattleJSONStillWorks(t *testing.T) {
	old := `{"enemy_id":"orc_gua","enemy_name":"Orc Gua","enemy_hp":56,"enemy_max_hp":56,"round":2,"next_enemy_ms":1000}`
	var b Battle
	if err := json.Unmarshal([]byte(old), &b); err != nil {
		t.Fatal(err)
	}
	p := newPlayer()
	if res, err := b.Sync(p, 1000, seq(20)); err != nil || len(res.Events) != 1 {
		t.Fatalf("pertarungan lama: %v %+v", err, res)
	}
	js, _ := json.Marshal(Event{Who: "enemy", Kind: "hit", Dmg: 3})
	if string(js) != `{"who":"enemy","kind":"hit","dmg":3}` {
		t.Errorf("kejadian biasa tidak boleh membawa kolom baru: %s", js)
	}
}
