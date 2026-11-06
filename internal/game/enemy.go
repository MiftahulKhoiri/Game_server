package game

import "slices"

// Enemy adalah jenis musuh. Tema: monster yang menyerang desa kerajaan.
type Enemy struct {
	ID          string
	Name        string
	HP          int
	Attack      int
	Defense     int
	XP          int
	Gold        int
	Zones       []string // peta tempat muncul (kosong = di mana saja)
	Boss        bool     // bos: tidak muncul acak, hanya lewat petak bos
	MinLevel    int      // baru muncul bila level pemain >= ini
	DropID      string   // barang yang mungkin dijatuhkan ("" = tidak ada)
	DropPercent int      // peluang jatuh, 0-100
}

var enemies = []Enemy{
	{ID: "tikus_sawah", Zones: []string{MapDesaAwal}, Name: "Ayam Liar", HP: 10, Attack: 3, Defense: 0, XP: 6, Gold: 2, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "belalang_raksasa", Zones: []string{MapDesaAwal}, Name: "Kucing Liar", HP: 14, Attack: 4, Defense: 1, XP: 8, Gold: 3, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "ular_sawah", Zones: []string{MapDesaAwal}, Name: "Rubah Sawah", HP: 20, Attack: 6, Defense: 1, XP: 12, Gold: 5, MinLevel: 2, DropID: PotionID, DropPercent: 15},
	{ID: "babi_hutan", Zones: []string{MapDesaAwal}, Name: "Babi Hutan", HP: 34, Attack: 8, Defense: 3, XP: 22, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 25},
	// Perbatasan: wilayah di luar gerbang desa, lebih berbahaya.
	{ID: "goblin", Zones: []string{MapPerbatasan}, Name: "Orc Ladang", HP: 26, Attack: 7, Defense: 2, XP: 15, Gold: 7, MinLevel: 1, DropID: "taring_goblin", DropPercent: 35},
	{ID: "serigala_hutan", Zones: []string{MapPerbatasan, MapGunungBatu}, Name: "Serigala Hutan", HP: 32, Attack: 9, Defense: 2, XP: 20, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 20},
	// Gunung Batu: sarang Ogre Batu, wilayah paling berbahaya saat ini.
	{ID: "kelelawar_gua", Zones: []string{MapGunungBatu, MapGuaBatu}, Name: "Kerangka Gua", HP: 28, Attack: 8, Defense: 1, XP: 18, Gold: 8, MinLevel: 3, DropID: PotionID, DropPercent: 20},
	{ID: "golem_kerikil", Zones: []string{MapGunungBatu, MapGuaBatu}, Name: "Kerangka Pejuang", HP: 50, Attack: 10, Defense: 6, XP: 32, Gold: 14, MinLevel: 4, DropID: "koin_kuno", DropPercent: 25},
	{ID: "ogre_batu", Zones: []string{MapGunungBatu}, Name: "Monster Batu", HP: 70, Attack: 12, Defense: 5, XP: 45, Gold: 25, MinLevel: 5, DropID: "permata_merah", DropPercent: 30},
	// Gua Batu: sarang dalang serangan monster.
	{ID: "goblin_penjaga", Zones: []string{MapGuaBatu}, Name: "Kerangka Penjaga", HP: 45, Attack: 11, Defense: 4, XP: 28, Gold: 12, MinLevel: 5, DropID: "taring_goblin", DropPercent: 50},
	{ID: "golem_lava", Zones: []string{MapGuaBatu}, Name: "Iblis Lava", HP: 62, Attack: 13, Defense: 6, XP: 40, Gold: 18, MinLevel: 6, DropID: "permata_merah", DropPercent: 20},
	{ID: "raja_goblin", Zones: []string{MapGuaBatu}, Boss: true, Name: "Raja Iblis", HP: 120, Attack: 14, Defense: 6, XP: 100, Gold: 60, MinLevel: 7, DropID: "permata_merah", DropPercent: 100},
}

// EnemyByID mencari musuh berdasarkan id.
func EnemyByID(id string) (Enemy, bool) {
	for _, e := range enemies {
		if e.ID == id {
			return e, true
		}
	}
	return Enemy{}, false
}

// inZone: apakah musuh muncul di peta ini.
func (e Enemy) inZone(mapID string) bool {
	return len(e.Zones) == 0 || slices.Contains(e.Zones, mapID)
}

// PickEnemy memilih musuh acak yang cocok untuk level pemain dan peta tempat ia berada.
// Bila pemain terlalu rendah levelnya untuk peta itu, ia tetap bertemu musuh terlemah
// di peta itu (masuk wilayah berbahaya terlalu dini memang berisiko).
func PickEnemy(level int, mapID string, rng Rand) Enemy {
	var eligible, inMap []Enemy
	for _, e := range enemies {
		if e.Boss || !e.inZone(mapID) {
			continue
		}
		inMap = append(inMap, e)
		if e.MinLevel <= level {
			eligible = append(eligible, e)
		}
	}
	if len(eligible) == 0 {
		if len(inMap) == 0 {
			for _, e := range enemies { // peta tak dikenal: semua musuh biasa
				if !e.Boss {
					inMap = append(inMap, e)
				}
			}
		}
		weakest := inMap[0]
		for _, e := range inMap {
			if e.MinLevel < weakest.MinLevel {
				weakest = e
			}
		}
		return weakest
	}
	return eligible[rng.Intn(len(eligible))]
}
