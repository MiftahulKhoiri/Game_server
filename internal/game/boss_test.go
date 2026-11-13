package game

import "testing"

// Pola dan fase bos (boss.go, v0.78.0).

func TestBossPhasesChangePattern(t *testing.T) {
	e := mustEnemy("goblin_hutan_2") // bos hutan, kemampuan khusus Hantaman Goblin
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 100000, 100000
	b := &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1, NextEnemyMs: 1000}
	type turn struct {
		round   int
		skill   string
		tactic  string
		phaseEv bool
	}
	run := func(hp int) turn {
		b.EnemyHP = hp
		r := b.Round
		res := syncAt(b, p, zeroRng)
		tn := turn{round: r}
		for _, ev := range res.Events {
			switch {
			case ev.Kind == "phase":
				tn.phaseEv = true
			case ev.Who == "enemy":
				tn.skill, tn.tactic = ev.Skill, ev.Tactic
			}
		}
		return tn
	}
	// Fase 1: kemampuan khusus tiap ke-3.
	for i := 0; i < 3; i++ {
		tn := run(e.HP)
		if (tn.round%3 == 0) != (tn.skill != "") {
			t.Fatalf("fase 1 ronde %d: %+v", tn.round, tn)
		}
	}
	// Fase 2 (HP 50%): pergantian fase tercatat, Hantaman Area tiap ke-4 bila bukan kemampuan khusus.
	sawArea, sawPhase := false, false
	for i := 0; i < 6; i++ {
		tn := run(e.HP / 2)
		sawPhase = sawPhase || tn.phaseEv
		if tn.round%4 == 0 && tn.round%3 != 0 {
			if tn.tactic != TacticArea {
				t.Fatalf("fase 2 ronde %d harus area: %+v", tn.round, tn)
			}
			sawArea = true
		}
	}
	if !sawArea || !sawPhase || b.Phase != 2 {
		t.Fatalf("fase 2: area %v, kejadian fase %v, fase %d", sawArea, sawPhase, b.Phase)
	}
	// Fase 3 (HP 20%): kemampuan khusus tiap ke-2.
	for i := 0; i < 4; i++ {
		tn := run(e.HP / 5)
		if (tn.round%2 == 0) != (tn.skill != "") {
			t.Fatalf("fase 3 ronde %d: %+v", tn.round, tn)
		}
	}
	if b.Phase != 3 {
		t.Fatalf("fase akhir %d", b.Phase)
	}
	// Fase tidak pernah turun walau HP bos pulih.
	run(e.HP)
	if b.Phase != 3 {
		t.Error("fase bos tidak boleh mundur")
	}
}

func TestBossIntentTelegraphsBigAttacks(t *testing.T) {
	e := mustEnemy("goblin_hutan_1")
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 100000, 100000
	b := &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1, NextEnemyMs: 1000}
	syncAt(b, p, zeroRng) // ronde 1 -> berikutnya ronde 2
	syncAt(b, p, zeroRng) // berikutnya ronde 3 = kemampuan khusus
	if v := b.View(b.NextEnemyMs - 500); v.EnemyIntent != IntentSpecial {
		t.Errorf("sebelum kemampuan khusus, niat harus %q: %+v", IntentSpecial, v.EnemyIntent)
	}
}

func TestMalzarethKeepsStoryPhases(t *testing.T) {
	e := mustEnemy(MalzarethID)
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 1000000, 1000000
	b := &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1, NextEnemyMs: 1000}
	names := map[string]bool{}
	for _, hp := range []int{e.HP, e.HP, e.HP, e.HP / 2, e.HP / 2, e.HP / 5, e.HP / 5} {
		b.EnemyHP = hp
		res := syncAt(b, p, zeroRng)
		for _, ev := range res.Events {
			if ev.Kind == "phase" {
				t.Fatalf("Malzareth tidak boleh memakai fase bos umum: %+v", ev)
			}
			if ev.Skill != "" {
				names[ev.Skill] = true
			}
		}
	}
	for _, want := range []string{"Gelombang Sihir Hitam", "Panggilan Monster", "Kutukan Terakhir"} {
		if !names[want] {
			t.Errorf("kemampuan cerita %q hilang (dapat %v)", want, names)
		}
	}
}

// Fase bos menambah tantangan tanpa melipatgandakan kerusakan: 24 serangan pola baru dibanding pola lama
// (kemampuan khusus tiap ke-3) pada HP bos yang menurun bertahap, rasio kerusakan maksimal 1,4x.
func TestBossPatternDamageBounded(t *testing.T) {
	for _, id := range []string{"goblin_hutan_3", "kepala_goblin_3", "ogre_gunung_3", AldragorID, "raja_goblin"} {
		e := mustEnemy(id)
		p := newPlayer()
		p.State.HP, p.State.MaxHP = 10000000, 10000000
		b := &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1, NextEnemyMs: 1000}
		start := p.State.HP
		oldTotal := 0
		for i := 0; i < 24; i++ {
			b.EnemyHP = e.HP - e.HP*i/24
			base := max(1, b.enemyAttack(e)-p.State.Defense())
			if special(e, b.Round) != "" {
				oldTotal += base * 18 / 10
			} else {
				oldTotal += base
			}
			syncAt(b, p, RandFunc(func(n int) int { return n / 2 })) // variasi tengah = 100%
		}
		ratio := float64(start-p.State.HP) / float64(oldTotal)
		if ratio > 1.4 || ratio < 0.8 { // per serangan (musuh cepat memukul lebih ringan tetapi lebih sering)
			t.Errorf("%s: kerusakan pola baru %.2fx pola lama", id, ratio)
		}
	}
}
