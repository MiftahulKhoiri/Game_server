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

// Makin jauh petanya makin berat (v0.72.0). Musuh tiap peta = musuh peta sebelumnya + golongan baru (binatang hutan ->
// goblin -> orc batu -> naga), jadi musuh biasa diperkuat menurut kekuatan peta tempat ia dilawan dibanding peta
// asalnya (Zones[0]): HP, XP, dan emas x mapPower/homePower, serangan naik 60% dari kenaikan itu.
// v0.77.0 (roadmap no. 170): Perbatasan juga x1,5 — sebelumnya pertarungan di sana selesai dalam 0-2 detik.
var mapPower = map[string]int{MapPerbatasan: 150, MapHutanLebat: 100, MapGuaGoblin: 150, MapGunungBatu: 220, MapGuaBatu: 380, MapIstana: 500}

// homePower: kekuatan bawaan musuh menurut peta asalnya. Musuh asli Istana Kegelapan sudah dibuat kuat (400);
// musuh peta lain dirancang setara binatang hutan (100).
var homePower = map[string]int{MapIstana: 400}

// mapPct: pengali kekuatan (persen) musuh biasa `e` di peta pemain; 100 bila tidak diperkuat.
func mapPct(st State, e Enemy) int {
	if e.Boss || e.Raid {
		return 100
	}
	p, ok := mapPower[st.Map]
	if !ok {
		return 100
	}
	h := 100
	if len(e.Zones) > 0 {
		if v, ok := homePower[e.Zones[0]]; ok {
			h = v
		}
	}
	return max(100, p*100/h)
}

// strengthen menerapkan penguatan peta dan tahap ujian pada pertarungan baru melawan musuh biasa.
func (b *Battle) strengthen(st State, e Enemy) {
	mp := mapPct(st, e)
	t := st.tahapOf(e)
	if t == 0 && mp == 100 {
		return
	}
	hpPct, atkPct, rewPct := mp, 100+(mp-100)*3/5, mp
	if t > 0 {
		gap := min(TahapLevelMax, max(0, st.Level-e.MinLevel))
		hpPct = hpPct * tahapHP[t-1] / 100 * (100 + gap*TahapLevelHP) / 100
		atkPct = atkPct * tahapAtk[t-1] / 100 * (100 + gap*TahapLevelAtk) / 100
		rewPct = rewPct * tahapHadiah[t-1] / 100
		b.Tahap = t
		b.EnemyName = fmt.Sprintf("%s Lv %d", e.Name, t)
	}
	hp := e.HP * hpPct / 100
	b.AtkPct = atkPct
	b.RewardPct = rewPct
	b.EnemyHP, b.EnemyMaxHP = hp, hp
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

// Bos wilayah ujian yang memburu pemain (v0.71.0, Gua Goblin): untuk pemain di atas TrialDef.BossLevel HP bos naik
// BossLevelHP% dan serangannya BossLevelAtk% per level (paling banyak BossLevelMax level), supaya pemain yang
// sudah kuat tetap tertantang. Hadiah tidak berubah.
const (
	BossLevelHP  = 7
	BossLevelAtk = 4
	BossLevelMax = 15
)

func (b *Battle) strengthenBoss(st State, e Enemy) {
	t, ok := TrialFor(st.Map)
	if !ok || t.BossLevel <= 0 || !e.Boss {
		return
	}
	gap := min(BossLevelMax, max(0, st.Level-t.BossLevel))
	if gap == 0 {
		return
	}
	hp := e.HP * (100 + gap*BossLevelHP) / 100
	b.EnemyHP, b.EnemyMaxHP = hp, hp
	b.AtkPct = 100 + gap*BossLevelAtk
}
