package game

import "math/rand/v2"

// Rand adalah sumber angka acak. Diganti di tes agar hasil bisa dipastikan.
type Rand interface {
	// Intn mengembalikan angka 0..n-1.
	Intn(n int) int
}

// RandomSource adalah sumber acak sungguhan untuk server.
type RandomSource struct{}

// Intn mengembalikan angka acak 0..n-1.
func (RandomSource) Intn(n int) int { return rand.IntN(n) }

// RandFunc membungkus fungsi biasa menjadi Rand (berguna di tes).
type RandFunc func(n int) int

// Intn memanggil fungsinya.
func (f RandFunc) Intn(n int) int { return f(n) }

// Titik awal dan tempat pemain dipulangkan setelah kalah.
const (
	SpawnMap = "desa_awal"
	SpawnX   = 5
	SpawnY   = 5
)

// Pengali keseimbangan pertarungan. Damage pemain/pendamping sedikit diturunkan,
// sementara serangan musuh diperkuat agar pertarungan tidak selesai terlalu cepat.
const (
	PlayerDamagePercent = 85
	AllyDamagePercent   = 85
	EnemyDamagePercent  = 125
)

// Rumus statistik pemain dari level. Angka-angka ini draf awal untuk diseimbangkan.

// MaxHPForLevel adalah HP maksimum pada level tertentu.
func MaxHPForLevel(level int) int { return 30 + 8*(level-1) }

// AttackForLevel adalah kekuatan serang pada level tertentu.
func AttackForLevel(level int) int { return 4 + 2*level }

// DefenseForLevel adalah pertahanan pada level tertentu.
func DefenseForLevel(level int) int { return 1 + level }

// XPToNext adalah XP yang dibutuhkan untuk naik dari level ini ke level berikutnya.
func XPToNext(level int) int { return 20 * level }
