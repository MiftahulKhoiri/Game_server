package game

import "testing"

// Roadmap no. 85: setiap serangan ke-4 musuh berkemampuan khusus memakai kemampuannya.
func TestEnemySpecialEveryFourthHit(t *testing.T) {
	e, _ := EnemyByID("serigala_hutan")
	if special(e, 1) != "" || special(e, 3) != "" || special(e, 4) != SpecialTerkam || special(e, 8) != SpecialTerkam {
		t.Fatal("terkaman harus jatuh pada serangan ke-4, ke-8, ...")
	}
	plain, _ := EnemyByID("tikus_sawah")
	if special(plain, 4) != "" {
		t.Fatal("Tikus Raksasa tidak punya kemampuan khusus")
	}
	boss, _ := EnemyByID("goblin_hutan_1")
	if special(boss, 3) != SpecialGempa {
		t.Fatal("bos memakai kemampuannya tiap serangan ke-3")
	}
}

// Kemampuan khusus muncul sebagai kejadian bernama dengan kerusakan lebih besar dari serangan biasa.
func TestSpecialHitEventAndDamage(t *testing.T) {
	p := newPlayer()
	p.State.MaxHP, p.State.HP = 999, 999
	b := battleVs("serigala_hutan", 32)
	b.Round = 4 // serangan berikutnya = ke-4
	res := Result{}
	if b.settle(p, mustEnemy("serigala_hutan"), b.NextEnemyMs, seq(20), &res) {
		t.Fatal("pertarungan tidak boleh selesai")
	}
	if len(res.Events) != 1 || res.Events[0].Skill != "Terkaman" {
		t.Fatalf("kejadian terkaman: %+v", res.Events)
	}
	e := mustEnemy("serigala_hutan")
	base := max(1, e.Attack-p.State.Defense())
	if res.Events[0].Dmg != base*16/10 {
		t.Fatalf("kerusakan terkaman %d, mau %d", res.Events[0].Dmg, base*16/10)
	}
}

// Kulit Batu memulihkan HP musuh.
func TestStoneSkinHeals(t *testing.T) {
	p := newPlayer()
	p.State.MaxHP, p.State.HP = 999, 999
	b := battleVs("ogre_batu", 40)
	b.Round = 4
	res := Result{}
	b.settle(p, mustEnemy("ogre_batu"), b.NextEnemyMs, seq(20), &res)
	if b.EnemyHP <= 40 || res.Events[0].Heal != b.EnemyHP-40 {
		t.Fatalf("Monster Batu harus pulih: hp=%d ev=%+v", b.EnemyHP, res.Events)
	}
}

// Roadmap no. 86: bos di bawah separuh HP mengamuk dan menyerang lebih cepat.
func TestBossEnrage(t *testing.T) {
	e := mustEnemy("goblin_hutan_1")
	b := battleVs("goblin_hutan_1", e.HP)
	if b.interval(e) != BossIntervalMs {
		t.Fatal("HP penuh: jeda normal")
	}
	b.EnemyHP = e.HP/2 - 1
	if b.interval(e) != BossIntervalMs*3/4 {
		t.Fatal("HP di bawah separuh: bos mengamuk")
	}
}
