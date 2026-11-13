package game

import "fmt"

// Pola dan fase bos (v0.78.0, AI hybrid fase 3). Bos tidak sekadar ber-HP besar: pertarungannya berubah menurut
// sisa HP, dengan ancang-ancang yang terlihat (BattleView.enemy_intent) sebelum serangan besar.
//
//	Fase 1 (HP > 2/3): pola profil AI-nya + kemampuan khusus tiap serangan ke-3 (seperti sebelumnya).
//	Fase 2 (HP > 1/3): ditambah Hantaman Area tiap serangan ke-4 (mengenai pemain, pendamping, prajurit depan).
//	Fase 3: kemampuan khusus tiap serangan ke-2; di bawah separuh HP ia juga mengamuk (menyerang lebih cepat).
//
// Malzareth memakai tiga fase ceritanya sendiri (story.go) dan tidak diubah. Tanpa angka acak tambahan.

// BossAreaEvery: pada fase 2 bos menghantam area tiap serangan ke-N.
const BossAreaEvery = 4

// bossPhase memperbarui fase bos menurut sisa HP dan mencatat pergantian fase. Mengembalikan fase sekarang.
func (b *Battle) bossPhase(e Enemy, res *Result) int {
	phase := 3
	switch {
	case b.EnemyHP*3 > b.EnemyMaxHP*2:
		phase = 1
	case b.EnemyHP*3 > b.EnemyMaxHP:
		phase = 2
	}
	if phase > b.Phase {
		if b.Phase > 0 || phase > 1 {
			text := map[int]string{2: "%s murka! (Fase 2: Hantaman Area)", 3: "%s mengerahkan seluruh kekuatannya! (Fase 3)"}[phase]
			res.Log = append(res.Log, fmt.Sprintf(text, b.EnemyName))
			res.Events = append(res.Events, Event{Who: "enemy", Kind: "phase", Skill: fmt.Sprintf("Fase %d", phase), Tactic: fmt.Sprintf("phase%d", phase)})
		}
		b.Phase = phase
	}
	return b.Phase
}

// bossSpecial: kemampuan khusus bos pada serangan bernomor round menurut fasenya.
func bossSpecial(e Enemy, round, phase int) string {
	every := BossSpecialEvery
	if phase >= 3 {
		every = 2
	}
	if e.Special == "" || round%every != 0 {
		return ""
	}
	return e.Special
}

// bossArea: fase 2 menambah Hantaman Area tiap serangan ke-BossAreaEvery (bila serangan itu bukan kemampuan khusus).
func bossArea(round, phase int) bool {
	return phase == 2 && round%BossAreaEvery == 0
}

// genericBoss: bos yang memakai pola fase umum ini (semua bos kecuali Malzareth).
func genericBoss(e Enemy) bool { return e.Boss && e.ID != MalzarethID }
