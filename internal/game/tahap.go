package game

import "fmt"

// Musuh wilayah ujian makin tangguh (v0.69.0): di Hutan Binatang, Gua Goblin, dan Lereng Gunung Berapi musuh biasa
// diperkuat menurut tahap ujian yang sedang dijalani (Lv 1 = tahap 1, Lv 2 = tahap 2, Lv 3 = tahap 3) dan menurut
// selisih level pemain dengan level musuh itu, supaya pemain yang sudah kuat tetap tertantang. HP, serangan, XP,
// dan emas ikut naik. Bos wilayah dan musuh di peta lain tidak berubah.

// Pengali per tahap (persen): HP, serangan, hadiah.
var tahapHP = [HutanWaves]int{160, 240, 320}
var tahapAtk = [HutanWaves]int{115, 135, 160}
var tahapHadiah = [HutanWaves]int{130, 165, 210}

// Per level pemain di atas level musuh: HP +8%, serangan +5% (paling banyak 20 level).
const (
	TahapLevelHP  = 8
	TahapLevelAtk = 5
	TahapLevelMax = 20
)

// tahapOf: tahap ujian (1..3) bila musuh biasa `e` dilawan di wilayah ujian, 0 bila tidak diperkuat.
func (s State) tahapOf(e Enemy) int {
	if e.Boss || e.Raid {
		return 0
	}
	if _, ok := TrialFor(s.Map); !ok {
		return 0
	}
	return min(s.Trial(s.Map).Wave, HutanWaves-1) + 1
}

// strengthen menerapkan penguatan tahap pada pertarungan baru melawan musuh biasa di wilayah ujian.
func (b *Battle) strengthen(st State, e Enemy) {
	t := st.tahapOf(e)
	if t == 0 {
		return
	}
	gap := min(TahapLevelMax, max(0, st.Level-e.MinLevel))
	hp := e.HP * tahapHP[t-1] / 100 * (100 + gap*TahapLevelHP) / 100
	b.Tahap = t
	b.AtkPct = tahapAtk[t-1] * (100 + gap*TahapLevelAtk) / 100
	b.RewardPct = tahapHadiah[t-1]
	b.EnemyHP, b.EnemyMaxHP = hp, hp
	b.EnemyName = fmt.Sprintf("%s Lv %d", e.Name, t)
}

// enemyAttack: serangan musuh dalam pertarungan ini (sudah dengan penguatan tahap).
func (b *Battle) enemyAttack(e Enemy) int {
	if b.AtkPct <= 0 {
		return e.Attack
	}
	return e.Attack * b.AtkPct / 100
}

// reward: XP/emas setelah penguatan tahap.
func (b *Battle) reward(v int) int {
	if b.RewardPct <= 0 {
		return v
	}
	return v * b.RewardPct / 100
}
