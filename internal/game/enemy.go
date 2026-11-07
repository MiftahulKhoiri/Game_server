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

// ZoneRetired menandai musuh yang tidak muncul di peta mana pun.
const ZoneRetired = "pensiun"

var enemies = []Enemy{
	// Hutan Perbatasan (sejak v0.32.0 desa aman dari musuh): hewan kecil yang paling mudah dikalahkan.
	{ID: "tikus_sawah", Zones: []string{MapPerbatasan}, Name: "Ayam Liar", HP: 10, Attack: 3, Defense: 0, XP: 6, Gold: 2, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "belalang_raksasa", Zones: []string{MapPerbatasan}, Name: "Kucing Liar", HP: 14, Attack: 4, Defense: 1, XP: 8, Gold: 3, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "ular_sawah", Zones: []string{MapPerbatasan}, Name: "Rubah Sawah", HP: 20, Attack: 6, Defense: 1, XP: 12, Gold: 5, MinLevel: 2, DropID: PotionID, DropPercent: 15},
	{ID: "babi_hutan", Zones: []string{MapPerbatasan}, Name: "Babi Hutan", HP: 34, Attack: 8, Defense: 3, XP: 22, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 25},
	// Perbatasan (hutan): binatang buas.
	{ID: "ular_hutan", Zones: []string{MapPerbatasan}, Name: "Ular Hutan", HP: 18, Attack: 6, Defense: 1, XP: 11, Gold: 5, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "serigala_hutan", Zones: []string{MapPerbatasan}, Name: "Serigala Hutan", HP: 32, Attack: 9, Defense: 2, XP: 20, Gold: 9, MinLevel: 2, DropID: PotionID, DropPercent: 20},
	{ID: "serigala_alfa", Zones: []string{MapPerbatasan}, Name: "Serigala Alfa", HP: 55, Attack: 12, Defense: 4, XP: 38, Gold: 16, MinLevel: 5, DropID: PotionID, DropPercent: 30},
	// Gunung Batu: goblin, dan Monster Batu sebagai penjaga.
	{ID: "goblin", Zones: []string{MapGunungBatu}, Name: "Goblin Gunung", HP: 34, Attack: 9, Defense: 2, XP: 24, Gold: 10, MinLevel: 2, DropID: "taring_goblin", DropPercent: 35},
	{ID: "goblin_pemburu", Zones: []string{MapGunungBatu}, Name: "Goblin Pemburu", HP: 48, Attack: 11, Defense: 3, XP: 32, Gold: 14, MinLevel: 4, DropID: "taring_goblin", DropPercent: 40},
	{ID: "ogre_batu", Zones: []string{MapGunungBatu}, Name: "Monster Batu", HP: 70, Attack: 12, Defense: 5, XP: 45, Gold: 25, MinLevel: 5, DropID: "permata_merah", DropPercent: 30},
	// Gua Batu: sarang orc dan Raja Iblis, dalang serangan monster.
	{ID: "orc_gua", Zones: []string{MapGuaBatu}, Name: "Orc Gua", HP: 56, Attack: 12, Defense: 5, XP: 34, Gold: 15, MinLevel: 5, DropID: "koin_kuno", DropPercent: 25},
	{ID: "orc_penjaga", Zones: []string{MapGuaBatu}, Name: "Orc Penjaga", HP: 68, Attack: 13, Defense: 6, XP: 42, Gold: 18, MinLevel: 6, DropID: "permata_merah", DropPercent: 20},
	{ID: "orc_buas", Zones: []string{MapGuaBatu}, Name: "Orc Buas", HP: 80, Attack: 15, Defense: 6, XP: 52, Gold: 22, MinLevel: 7, DropID: "permata_merah", DropPercent: 25},
	{ID: "raja_goblin", Zones: []string{MapGuaBatu}, Boss: true, Name: "Raja Iblis", HP: 120, Attack: 14, Defense: 6, XP: 100, Gold: 60, MinLevel: 7, DropID: "permata_merah", DropPercent: 100},
	// Pensiun (v0.29.0): tidak lagi muncul. Tetap terdaftar agar pertarungan lama yang masih berjalan bisa selesai.
	{ID: "kelelawar_gua", Zones: []string{ZoneRetired}, Name: "Kerangka Gua", HP: 28, Attack: 8, Defense: 1, XP: 18, Gold: 8, MinLevel: 3, DropID: PotionID, DropPercent: 20},
	{ID: "golem_kerikil", Zones: []string{ZoneRetired}, Name: "Kerangka Pejuang", HP: 50, Attack: 10, Defense: 6, XP: 32, Gold: 14, MinLevel: 4, DropID: "koin_kuno", DropPercent: 25},
	{ID: "goblin_penjaga", Zones: []string{ZoneRetired}, Name: "Kerangka Penjaga", HP: 45, Attack: 11, Defense: 4, XP: 28, Gold: 12, MinLevel: 5, DropID: "taring_goblin", DropPercent: 50},
	{ID: "golem_lava", Zones: []string{ZoneRetired}, Name: "Iblis Lava", HP: 62, Attack: 13, Defense: 6, XP: 40, Gold: 18, MinLevel: 6, DropID: "permata_merah", DropPercent: 20},
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

// PickEnemyFor memilih musuh untuk pertarungan yang dimulai pemain dengan menyentuh musuh
// berkeliaran di peta. `want` dipakai bila musuh itu memang boleh muncul di peta dan level
// pemain ini (sama seperti pilihan acak); selain itu server memilih sendiri.
func PickEnemyFor(level int, mapID, want string, rng Rand) Enemy {
	if want != "" {
		if e, ok := EnemyByID(want); ok && !e.Boss && e.inZone(mapID) && e.MinLevel <= level {
			return e
		}
		if e, ok := EnemyByID(want); ok && !e.Boss && e.inZone(mapID) && e.MinLevel == weakestMinLevel(mapID) {
			return e
		}
	}
	return PickEnemy(level, mapID, rng)
}

// weakestMinLevel adalah MinLevel terkecil di antara musuh biasa di peta itu.
func weakestMinLevel(mapID string) int {
	lowest := -1
	for _, e := range enemies {
		if e.Boss || !e.inZone(mapID) {
			continue
		}
		if lowest < 0 || e.MinLevel < lowest {
			lowest = e.MinLevel
		}
	}
	return lowest
}
