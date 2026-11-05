package game

// Peta yang dikenal server. Server hanya tahu ukuran peta untuk memeriksa
// posisi yang dikirim klien dan memilih musuh sesuai wilayah; bentuk petak
// (tembok, air) masih milik klien (client/scripts/maps.gd).
const (
	MapDesaAwal   = SpawnMap      // "desa_awal"
	MapPerbatasan = "perbatasan"  // ladang di luar gerbang selatan desa
	MapGunungBatu = "gunung_batu" // sarang Ogre Batu, di selatan Perbatasan
	MapGuaBatu    = "gua_batu"    // sarang dalang serangan monster, di dalam Gunung Batu
)

// MapInfo adalah ukuran sebuah peta dalam petak.
type MapInfo struct {
	Width, Height int
}

var worldMaps = map[string]MapInfo{
	MapDesaAwal:   {Width: 15, Height: 20},
	MapPerbatasan: {Width: 15, Height: 20},
	MapGunungBatu: {Width: 15, Height: 20},
	MapGuaBatu:    {Width: 15, Height: 20},
}

// BossSpot adalah petak tempat bos menunggu. Menginjaknya (di klien) lalu
// meminta pertarungan bos ke server; server memeriksa posisi tersimpan pemain.
type BossSpot struct {
	Map     string
	X, Y    int
	EnemyID string
}

var bossSpots = []BossSpot{
	{Map: MapGuaBatu, X: 7, Y: 14, EnemyID: "raja_goblin"},
}

// BossAt mengembalikan bos di petak itu, bila ada.
func BossAt(mapID string, x, y int) (Enemy, bool) {
	for _, b := range bossSpots {
		if b.Map == mapID && b.X == x && b.Y == y {
			return EnemyByID(b.EnemyID)
		}
	}
	return Enemy{}, false
}

// ValidPosition memeriksa peta dikenal dan (x, y) berada di dalamnya.
func ValidPosition(mapID string, x, y int) bool {
	m, ok := worldMaps[mapID]
	return ok && x >= 0 && y >= 0 && x < m.Width && y < m.Height
}
