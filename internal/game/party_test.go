package game

import (
	"encoding/json"
	"testing"
)

// Peran pahlawan pendamping dan formasi prajurit (party.go, v0.78.0).

func partyPlayer(party ...string) *Player {
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 5000, 5000
	p.State.Allies = append([]string{}, party...)
	p.State.Party = append([]string{}, party...)
	return p
}

var zeroRng = RandFunc(func(int) int { return 0 })

// enemyTurns menjalankan n serangan musuh tanpa giliran pendamping; mengembalikan kejadian musuh ke pendamping.
func enemyTurns(b *Battle, p *Player, n int) []Event {
	b.NextAllyMs = 1 << 40
	var out []Event
	for range n {
		res, _ := b.Sync(p, b.NextEnemyMs, zeroRng)
		for _, ev := range res.Events {
			if ev.Who == "ally" {
				out = append(out, ev)
			}
		}
	}
	return out
}

func TestTankDrawsAttacksEverySecondStrike(t *testing.T) {
	p := partyPlayer("pendekar_kapak", "ksatria")
	evs := enemyTurns(battleVs("tikus_sawah", 1000), p, 6)
	if len(evs) != 3 {
		t.Fatalf("Ksatria harus menerima 3 dari 6 serangan: %+v", evs)
	}
	for _, ev := range evs {
		if ev.Hero != "ksatria" {
			t.Fatalf("serangan ke pendamping harus ke Ksatria (tank): %+v", ev)
		}
	}
	// Tanpa Ksatria: pola lama tiap serangan ke-3.
	p2 := partyPlayer("pendekar_kapak")
	if evs := enemyTurns(battleVs("tikus_sawah", 1000), p2, 6); len(evs) != 2 {
		t.Fatalf("tanpa tank: %d serangan ke pendamping, mau 2", len(evs))
	}
}

func TestArcherKeepsDistance(t *testing.T) {
	p := partyPlayer("pemanah", "pendekar_tombak")
	evs := enemyTurns(battleVs("tikus_sawah", 1000), p, 6)
	for _, ev := range evs {
		if ev.Hero == "pemanah" {
			t.Fatalf("Pemanah diincar walau ada pendamping lain: %+v", evs)
		}
	}
	// Sendirian, Pemanah tetap bisa diincar.
	p2 := partyPlayer("pemanah")
	if evs := enemyTurns(battleVs("tikus_sawah", 1000), p2, 3); len(evs) != 1 || evs[0].Hero != "pemanah" {
		t.Fatalf("Pemanah sendirian: %+v", evs)
	}
}

func allyHit(t *testing.T, hero, enemy string) Event {
	t.Helper()
	p := partyPlayer(hero)
	b := battleVs(enemy, 100000)
	b.NextEnemyMs, b.NextAllyMs = 1<<40, 1000
	res, _ := b.Sync(p, 1000, RandFunc(func(n int) int { return n / 2 }))
	for _, ev := range res.Events {
		if ev.Who == "ally" && ev.Hero == hero {
			return ev
		}
	}
	t.Fatalf("%s tidak bergerak: %+v", hero, res.Events)
	return Event{}
}

func TestHeroRoles(t *testing.T) {
	p := partyPlayer("ksatria")
	pow := p.State.heroPower("ksatria")
	mid := func(atk, def int) int { return max(1, max(1, atk-def)*100/100) } // angka acak tengah = 100%
	e := mustEnemy("golem_lava")                                             // pertahanan 6
	if ev := allyHit(t, "pendekar_kapak", "golem_lava"); ev.Dmg != mid(pow, e.Defense/2) || ev.Tactic != RoleHeavy {
		t.Errorf("Pendekar Kapak harus menembus separuh pertahanan: %+v (mau %d)", ev, mid(pow, e.Defense/2))
	}
	if ev := allyHit(t, "ksatria", "golem_lava"); ev.Dmg != mid(pow*TankAtkPct/100, e.Defense) || ev.Tactic != RoleTank {
		t.Errorf("Ksatria: %+v", ev)
	}
	bat := mustEnemy("kelelawar_gua")
	if ev := allyHit(t, "pemanah", "kelelawar_gua"); ev.Dmg != mid(pow*RangedVsAirPct/100, bat.Defense) || ev.Tactic != RoleRanged {
		t.Errorf("Pemanah melawan kelelawar: %+v", ev)
	}
	if ev := allyHit(t, "penyihir", "golem_lava"); ev.Kind != "attack" || ev.Dmg != mid(pow, e.Defense/2) || ev.Tactic != RoleMagic {
		t.Errorf("Penyihir menyerang bila semua sehat: %+v", ev)
	}
}

func TestSpearmanPushesEnemyTiming(t *testing.T) {
	p := partyPlayer("pendekar_tombak")
	b := battleVs("tikus_sawah", 100000)
	b.NextEnemyMs, b.NextAllyMs = 10000, 1000
	for _, now := range []int64{1000, 2800, 4600, 6400, 8200} {
		b.Sync(p, now, zeroRng)
	}
	if b.NextEnemyMs != 10000+QuickPushMaxMs || b.Pushed != QuickPushMaxMs {
		t.Errorf("dorongan tombak dibatasi %d ms: jadwal %d, dorongan %d", QuickPushMaxMs, b.NextEnemyMs, b.Pushed)
	}
}

func TestMageHealsWoundedFriend(t *testing.T) {
	p := partyPlayer("penyihir", "pendekar_kapak")
	p.State.AllyHP = map[string]int{"pendekar_kapak": 5, "penyihir": AllyMaxHP}
	b := battleVs("tikus_sawah", 100000)
	b.NextEnemyMs, b.NextAllyMs = 1<<40, 1000
	res, _ := b.Sync(p, 1000, zeroRng)
	var heal *Event
	for i, ev := range res.Events {
		if ev.Hero == "penyihir" {
			heal = &res.Events[i]
		}
	}
	hp, _, _ := p.State.AllyHealth("pendekar_kapak")
	if heal == nil || heal.Kind != "heal" || heal.Skill != "pendekar_kapak" || hp != 5+heal.Heal || heal.Heal < 1 {
		t.Fatalf("Penyihir harus menyembuhkan Pendekar Kapak: %+v hp=%d", heal, hp)
	}
	// Pemain yang terluka parah juga disembuhkan (bila paling parah).
	p2 := partyPlayer("penyihir")
	p2.State.HP = 100
	b2 := battleVs("tikus_sawah", 100000)
	b2.NextEnemyMs, b2.NextAllyMs = 1<<40, 1000
	res2, _ := b2.Sync(p2, 1000, zeroRng)
	if p2.State.HP <= 100 || res2.Events[0].Kind != "heal" || res2.Events[0].Skill != "" {
		t.Fatalf("Penyihir harus menyembuhkan pemain: %+v hp=%d", res2.Events, p2.State.HP)
	}
}

func TestFallenAlliesDoNothing(t *testing.T) {
	p := partyPlayer("penyihir", "pendekar_tombak")
	p.State.AllyHP = map[string]int{"penyihir": 0, "pendekar_tombak": 0}
	p.State.HP = 10
	b := battleVs("tikus_sawah", 1000)
	b.NextEnemyMs, b.NextAllyMs = 1<<40, 1000
	res, _ := b.Sync(p, 1000, zeroRng)
	for _, ev := range res.Events {
		if ev.Who == "ally" {
			t.Fatalf("pendamping yang tumbang tidak boleh menyerang/menyembuhkan: %+v", ev)
		}
	}
}

func soldierDamageTaken(t *testing.T, formation string, attacks int) (hits int, lost int) {
	t.Helper()
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 5000, 5000
	p.State.Soldiers = 3
	p.State.Formation = formation
	b := battleVs("beruang_hutan", 100000) // serangan cukup besar supaya persen terasa (profil biasa)
	b.NextAllyMs = 1 << 40
	b.ensureSoldiers(&p.State)
	full := p.State.SoldierMaxHP() * 3
	for range attacks {
		res, _ := b.Sync(p, b.NextEnemyMs, zeroRng)
		for _, ev := range res.Events {
			if ev.Who == "ally" {
				hits++
			}
		}
	}
	left := 0
	for _, hp := range b.SoldierHP {
		left += hp
	}
	return hits, full - left
}

func TestFormationsChangeTargetingAndDamage(t *testing.T) {
	lineHits, lineLost := soldierDamageTaken(t, FormationLine, 6)
	if lineHits != 4 {
		t.Fatalf("barisan (perilaku lama) menahan 4 dari 6 serangan, dapat %d", lineHits)
	}
	if h, _ := soldierDamageTaken(t, FormationArcher, 6); h != 2 {
		t.Errorf("formasi pemanah: %d serangan, mau 2", h)
	}
	if h, _ := soldierDamageTaken(t, FormationCircle, 6); h != 6 {
		t.Errorf("lingkaran: %d serangan, mau 6", h)
	}
	if _, lost := soldierDamageTaken(t, FormationShield, 6); lost >= lineLost {
		t.Errorf("dinding perisai harus menahan lebih baik: %d vs barisan %d", lost, lineLost)
	}
	if _, lost := soldierDamageTaken(t, FormationSpear, 6); lost < lineLost {
		t.Errorf("formasi tombak lebih rentan: %d vs barisan %d", lost, lineLost)
	}
}

func TestChargeFormationOpensWithDoubleVolley(t *testing.T) {
	volley := func(form string, turns int) []int {
		p := newPlayer()
		p.State.Soldiers = 2
		p.State.Formation = form
		b := battleVs("tikus_sawah", 100000)
		b.NextEnemyMs, b.NextAllyMs = 1<<40, 1000
		var out []int
		for i := range turns {
			before := b.EnemyHP
			b.Sync(p, 1000+int64(i)*AllyIntervalMs, zeroRng)
			out = append(out, before-b.EnemyHP)
		}
		return out
	}
	line, charge := volley(FormationLine, 2), volley(FormationCharge, 2)
	if charge[0] <= line[0] || charge[1] != line[1] {
		t.Errorf("serbuan pembuka harus lebih kuat sekali saja: serbu %v, barisan %v", charge, line)
	}
}

func TestSetFormationAndValidation(t *testing.T) {
	st := NewState()
	for _, f := range Formations {
		if err := st.SetFormation(f.ID); err != nil {
			t.Errorf("formasi %q ditolak: %v", f.ID, err)
		}
	}
	if err := st.SetFormation("naga_terbang"); err != ErrUnknownFormation {
		t.Errorf("formasi asing: %v", err)
	}
	st.Formation = "kacau"
	if err := st.Validate(); err == nil {
		t.Error("state dengan formasi asing harus ditolak")
	}
	// Data lama tanpa formasi = barisan.
	var old State
	if err := json.Unmarshal([]byte(`{"level":1,"hp":30,"max_hp":30,"map":"desa_awal","x":5,"y":5,"hero":"ksatria","soldiers":2}`), &old); err != nil {
		t.Fatal(err)
	}
	if old.formation().ID != FormationLine {
		t.Errorf("data lama: %+v", old.formation())
	}
}
