package game

import "testing"

// Biaya AI hybrid per serangan musuh (assess + taktik + target), untuk memastikan server Pi tetap ringan.
func BenchmarkEnemyAttackAI(b *testing.B) {
	ids := []string{"tikus_sawah", "goblin", "orc_gua", "serigala_hutan", "golem_lava", "naga_api", MalzarethID}
	var es []Enemy
	for _, id := range ids {
		if e, ok := EnemyByID(id); ok {
			es = append(es, e)
		}
	}
	rng := RandFunc(func(n int) int { return n / 2 })
	p := newPlayer()
	p.State.Party = []string{"ksatria", "pemanah", "penyihir"}
	p.State.Soldiers = MaxSoldiers
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		e := es[i%len(es)]
		p.State.HP, p.State.MaxHP = 1_000_000, 1_000_000
		bt := &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1 + i%9, NextEnemyMs: 1000, NextAllyMs: 1 << 60}
		var res Result
		bt.settle(p, e, bt.NextEnemyMs, rng, &res)
	}
}

// Biaya adaptive difficulty saat pertarungan dimulai dan saat hasilnya dicatat.
func BenchmarkAdapt(b *testing.B) {
	e, _ := EnemyByID("beruang_hutan")
	st := NewState()
	st.Adapt = &Adapt{Factor: 1050, Recent: "EEWEEWE"}
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		bt := newBattle(e, 0)
		bt.strengthen(st, e)
		bt.adapt(st, e)
		st.recordAdapt(e, OutcomeEasy)
	}
}
