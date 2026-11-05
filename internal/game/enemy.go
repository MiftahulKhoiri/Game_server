package game

// Enemy adalah jenis musuh. Tema: hama desa petani.
type Enemy struct {
	ID          string
	Name        string
	HP          int
	Attack      int
	Defense     int
	XP          int
	Gold        int
	MinLevel    int    // baru muncul bila level pemain >= ini
	DropID      string // barang yang mungkin dijatuhkan ("" = tidak ada)
	DropPercent int    // peluang jatuh, 0-100
}

var enemies = []Enemy{
	{ID: "tikus_sawah", Name: "Tikus Sawah", HP: 10, Attack: 3, Defense: 0, XP: 6, Gold: 2, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "belalang_raksasa", Name: "Belalang Raksasa", HP: 14, Attack: 4, Defense: 1, XP: 8, Gold: 3, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "ular_sawah", Name: "Ular Sawah", HP: 20, Attack: 6, Defense: 1, XP: 12, Gold: 5, MinLevel: 2, DropID: PotionID, DropPercent: 15},
	{ID: "babi_hutan", Name: "Babi Hutan", HP: 34, Attack: 8, Defense: 3, XP: 22, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 25},
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

// PickEnemy memilih musuh acak yang cocok untuk level pemain.
func PickEnemy(level int, rng Rand) Enemy {
	var eligible []Enemy
	for _, e := range enemies {
		if e.MinLevel <= level {
			eligible = append(eligible, e)
		}
	}
	return eligible[rng.Intn(len(eligible))]
}
