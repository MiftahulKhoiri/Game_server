package game

import "math"

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

// Pose adalah posisi pemain yang boleh disimpan klien.
type Pose struct {
	Map    string
	X, Y   int
	FX, FZ float64
	Yaw    float64
}

// NormalizePose memeriksa pose dari klien. Mengembalikan pose yang aman disimpan,
// atau false bila peta/petak tidak sah. Petak (X, Y) adalah acuan server; posisi
// halus dipakai hanya bila benar-benar berada di dalam petak itu. Klien lama
// (tanpa posisi halus) atau posisi yang tidak cocok diletakkan di tengah petak.
func NormalizePose(p Pose) (Pose, bool) {
	if !ValidPosition(p.Map, p.X, p.Y) || !finite(p.FX) || !finite(p.FZ) || !finite(p.Yaw) {
		return Pose{}, false
	}
	inside := p.FX >= float64(p.X) && p.FX < float64(p.X+1) && p.FZ >= float64(p.Y) && p.FZ < float64(p.Y+1)
	if !inside {
		p.FX, p.FZ = float64(p.X)+0.5, float64(p.Y)+0.5
	}
	p.Yaw = math.Remainder(p.Yaw, 2*math.Pi) // -pi..pi
	return p, true
}
