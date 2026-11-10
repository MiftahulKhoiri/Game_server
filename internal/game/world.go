package game

import "math"

// Peta yang dikenal server. Server hanya tahu ukuran peta untuk memeriksa
// posisi yang dikirim klien dan memilih musuh sesuai wilayah; bentuk petak
// (tembok, air) masih milik klien (client/scripts/maps.gd).
const (
	MapDesaAwal   = SpawnMap      // "desa_awal"
	MapPerbatasan = "perbatasan"  // ladang di luar gerbang selatan desa
	MapGunungBatu = "gunung_batu" // sarang Ogre Batu, di selatan Gua Goblin (sejak v0.46.0)
	MapGuaBatu    = "gua_batu"    // sarang dalang serangan monster, di dalam Gunung Batu
	// Ruangan dalam bangunan Desa Awal (v0.40.0): tempat berbelanja dan beristirahat. Aman, tanpa musuh.
	MapTokoRamuan = "toko_ramuan"
	MapRumahMakan = "rumah_makan"
	MapRumahSehat = "rumah_sehat"
	MapTokoAlat   = "toko_peralatan"
	MapAula       = "aula_pelatihan" // Aula Pelatihan (v0.43.0): latih pahlawan pembantu dan prajurit
	// v0.55.0 (roadmap no. 115, 123, 127): penginapan dan rumah milik pemain (hanya bisa dimasuki pemiliknya).
	MapPenginapan  = "penginapan"
	MapRumahPemain = "rumah_pemain"
)

// MapInfo adalah ukuran sebuah peta dalam petak.
type MapInfo struct {
	Width, Height int
}

var worldMaps = map[string]MapInfo{
	MapDesaAwal:    {Width: 85, Height: 50},
	MapPerbatasan:  {Width: 45, Height: 50},
	MapHutanLebat:  {Width: 170, Height: 50},
	MapGuaGoblin:   {Width: 25, Height: 30},
	MapGunungBatu:  {Width: 45, Height: 50},
	MapGuaBatu:     {Width: 15, Height: 20},
	MapTokoRamuan:  {Width: 9, Height: 8},
	MapRumahMakan:  {Width: 9, Height: 8},
	MapRumahSehat:  {Width: 9, Height: 8},
	MapTokoAlat:    {Width: 9, Height: 8},
	MapAula:        {Width: 11, Height: 8},
	MapPenginapan:  {Width: 9, Height: 8},
	MapRumahPemain: {Width: 9, Height: 8},
}

// InVillage: peta tempat pemain aman dan boleh beristirahat gratis (desa dan ruangan di dalamnya).
func InVillage(mapID string) bool {
	return mapID == MapDesaAwal || mapID == MapTokoRamuan || mapID == MapRumahMakan || mapID == MapRumahSehat || mapID == MapTokoAlat || mapID == MapAula ||
		mapID == MapPenginapan || mapID == MapRumahPemain
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
