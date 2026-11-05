package game

// Peta yang dikenal server. Server hanya tahu ukuran peta untuk memeriksa
// posisi yang dikirim klien dan memilih musuh sesuai wilayah; bentuk petak
// (tembok, air) masih milik klien (client/scripts/maps.gd).
const (
	MapDesaAwal   = SpawnMap     // "desa_awal"
	MapPerbatasan = "perbatasan" // ladang di luar gerbang selatan desa
)

// MapInfo adalah ukuran sebuah peta dalam petak.
type MapInfo struct {
	Width, Height int
}

var worldMaps = map[string]MapInfo{
	MapDesaAwal:   {Width: 15, Height: 20},
	MapPerbatasan: {Width: 15, Height: 20},
}

// ValidPosition memeriksa peta dikenal dan (x, y) berada di dalamnya.
func ValidPosition(mapID string, x, y int) bool {
	m, ok := worldMaps[mapID]
	return ok && x >= 0 && y >= 0 && x < m.Width && y < m.Height
}
