package game

// Enemy adalah jenis musuh. Tema: monster yang menyerang desa kerajaan.
type Enemy struct {
	ID          string
	Name        string
	HP          int
	Attack      int
	Defense     int
	XP          int
	Gold        int
	Zone        string // peta tempat muncul ("" = di mana saja)
	MinLevel    int    // baru muncul bila level pemain >= ini
	DropID      string // barang yang mungkin dijatuhkan ("" = tidak ada)
	DropPercent int    // peluang jatuh, 0-100
}

var enemies = []Enemy{
	{ID: "tikus_sawah", Zone: MapDesaAwal, Name: "Tikus Sawah", HP: 10, Attack: 3, Defense: 0, XP: 6, Gold: 2, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "belalang_raksasa", Zone: MapDesaAwal, Name: "Belalang Raksasa", HP: 14, Attack: 4, Defense: 1, XP: 8, Gold: 3, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "ular_sawah", Zone: MapDesaAwal, Name: "Ular Sawah", HP: 20, Attack: 6, Defense: 1, XP: 12, Gold: 5, MinLevel: 2, DropID: PotionID, DropPercent: 15},
	{ID: "babi_hutan", Zone: MapDesaAwal, Name: "Babi Hutan", HP: 34, Attack: 8, Defense: 3, XP: 22, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 25},
	// Perbatasan: wilayah di luar gerbang desa, lebih berbahaya.
	{ID: "goblin", Zone: MapPerbatasan, Name: "Goblin", HP: 26, Attack: 7, Defense: 2, XP: 15, Gold: 7, MinLevel: 1, DropID: "taring_goblin", DropPercent: 35},
	{ID: "serigala_hutan", Zone: MapPerbatasan, Name: "Serigala Hutan", HP: 32, Attack: 9, Defense: 2, XP: 20, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 20},
	{ID: "ogre_batu", Zone: MapPerbatasan, Name: "Ogre Batu", HP: 70, Attack: 12, Defense: 5, XP: 45, Gold: 25, MinLevel: 5, DropID: "permata_merah", DropPercent: 30},
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

// PickEnemy memilih musuh acak yang cocok untuk level pemain dan peta tempat ia berada.
// Bila peta tidak punya musuh yang cocok, dipilih dari semua musuh yang levelnya sesuai.
func PickEnemy(level int, mapID string, rng Rand) Enemy {
	var eligible, anywhere []Enemy
	for _, e := range enemies {
		if e.MinLevel > level {
			continue
		}
		anywhere = append(anywhere, e)
		if e.Zone == "" || e.Zone == mapID {
			eligible = append(eligible, e)
		}
	}
	if len(eligible) == 0 {
		eligible = anywhere
	}
	if len(eligible) == 0 {
		eligible = enemies[:1]
	}
	return eligible[rng.Intn(len(eligible))]
}
