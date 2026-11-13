package game

import (
	"errors"
	"math"
	"slices"
)

// Gerakan pemain yang dikendalikan server (audit keamanan v0.77.0).
//
// Klien melaporkan posisinya (simpan posisi dan aksi hadiah dunia), tetapi server hanya menerimanya bila
// posisi itu bisa dicapai dari posisi tersimpan terakhir dalam waktu yang sudah berlalu: jarak jalan menyusuri
// petak yang bisa diinjak (pathing.go; lewat pintu antarpeta bila pindah peta) tidak boleh melebihi MaxMoveSpeed x waktu + MoveGrace. Pintu
// yang masih terkunci (gerbang wilayah ujian, gerbang cerita, rumah milik orang lain) tidak bisa dilewati.
// Semua pemeriksaan jarak untuk hadiah (peti, benda, rahasia, NPC) memakai posisi yang sudah lolos di sini.

// Batas gerakan. Kecepatan tercepat di klien: 3,3 petak/detik x Boost 1,35 ≈ 4,5 petak/detik, ditambah
// lompatan singkat (menghindar/hantaman). Angka di bawah sengaja longgar supaya jeda jaringan, sinyal
// putus-sambung, dan urutan permintaan yang tertukar tidak membuat pemain jujur ditolak.
const (
	MaxMoveSpeed = 9.0 // petak per detik
	MoveGrace    = 8.0 // petak: kelonggaran tetap (jeda jaringan, posisi aman di samping pintu)
	arriveSlack  = 6.0 // petak: klien boleh menaruh pemain sedikit di samping petak tujuan pintu (safe_spot)
)

// Kesalahan gerakan.
var (
	ErrMoveTooFar  = errors.New("posisi tidak sah: perpindahan terlalu jauh untuk waktu sesingkat itu")
	ErrMapLocked   = errors.New("posisi tidak sah: wilayah itu belum bisa dimasuki")
	ErrMoveBlocked = errors.New("posisi tidak sah: petak itu tidak bisa diinjak")
)

// Door adalah satu petak pintu: menginjak (X, Y) di Map memindahkan pemain ke To di petak (AtX, AtY).
// Daftar ini HARUS sama dengan EXITS di client/scripts/maps.gd.
type Door struct {
	Map      string
	X, Y     int
	To       string
	AtX, AtY int
}

// Doors: semua pintu antarpeta.
var Doors = []Door{
	{MapDesaAwal, 21, 49, MapPerbatasan, 21, 1},
	{MapDesaAwal, 22, 49, MapPerbatasan, 22, 1},
	{MapDesaAwal, 23, 49, MapPerbatasan, 23, 1},
	{MapDesaAwal, 4, 2, MapTokoAlat, 4, 6},
	{MapDesaAwal, 38, 20, MapAula, 5, 6},
	{MapDesaAwal, 16, 2, MapTokoRamuan, 4, 6},
	{MapDesaAwal, 22, 2, MapRumahMakan, 4, 6},
	{MapDesaAwal, 28, 2, MapRumahSehat, 4, 6},
	{MapDesaAwal, 29, 39, MapPenginapan, 4, 6},
	{MapDesaAwal, 15, 39, MapRumahPemain, 4, 6},
	{MapTokoAlat, 4, 7, MapDesaAwal, 4, 3},
	{MapAula, 5, 7, MapDesaAwal, 38, 21},
	{MapTokoRamuan, 4, 7, MapDesaAwal, 16, 3},
	{MapRumahMakan, 4, 7, MapDesaAwal, 22, 3},
	{MapRumahSehat, 4, 7, MapDesaAwal, 28, 3},
	{MapPenginapan, 4, 7, MapDesaAwal, 29, 40},
	{MapRumahPemain, 4, 7, MapDesaAwal, 15, 40},
	{MapPerbatasan, 21, 0, MapDesaAwal, 21, 48},
	{MapPerbatasan, 22, 0, MapDesaAwal, 22, 48},
	{MapPerbatasan, 23, 0, MapDesaAwal, 23, 48},
	{MapPerbatasan, 22, 49, MapHutanLebat, 22, 1},
	{MapHutanLebat, 22, 0, MapPerbatasan, 22, 48},
	{MapHutanLebat, 146, 49, MapGuaGoblin, 30, 1},
	{MapHutanLebat, 147, 49, MapGuaGoblin, 31, 1},
	{MapGuaGoblin, 29, 0, MapHutanLebat, 146, 48},
	{MapGuaGoblin, 30, 0, MapHutanLebat, 147, 48},
	{MapGuaGoblin, 31, 0, MapHutanLebat, 147, 48},
	{MapGuaGoblin, 29, 71, MapGunungBatu, 21, 1},
	{MapGuaGoblin, 30, 71, MapGunungBatu, 22, 1},
	{MapGuaGoblin, 31, 71, MapGunungBatu, 23, 1},
	{MapGunungBatu, 21, 0, MapGuaGoblin, 29, 70},
	{MapGunungBatu, 22, 0, MapGuaGoblin, 30, 70},
	{MapGunungBatu, 23, 0, MapGuaGoblin, 31, 70},
	{MapGunungBatu, 159, 49, MapGuaBatu, 7, 1},
	{MapGunungBatu, 160, 49, MapGuaBatu, 7, 1},
	{MapGunungBatu, 161, 49, MapGuaBatu, 7, 1},
	{MapGuaBatu, 7, 0, MapGunungBatu, 160, 48},
	{MapGuaBatu, 7, 19, MapIstana, 15, 1},
	{MapIstana, 14, 0, MapGuaBatu, 7, 18},
	{MapIstana, 15, 0, MapGuaBatu, 7, 18},
	{MapIstana, 16, 0, MapGuaBatu, 7, 18},
	{MapIstana, 14, 25, MapTakhta, 10, 1},
	{MapIstana, 15, 25, MapTakhta, 10, 1},
	{MapIstana, 16, 25, MapTakhta, 10, 1},
	{MapTakhta, 9, 0, MapIstana, 15, 24},
	{MapTakhta, 10, 0, MapIstana, 15, 24},
	{MapTakhta, 11, 0, MapIstana, 15, 24},
}

// Gerbang cerita (sama dengan STORY_GATES di maps.gd): pintu ini baru terbuka mulai langkah cerita tertentu.
var storyGates = map[[2]string]int{
	{MapGuaBatu, MapIstana}: 9,
	{MapIstana, MapTakhta}:  10,
}

// DoorOpen: boleh melewati pintu d? Rumah pemain hanya untuk pemiliknya, gerbang wilayah ujian terbuka
// setelah ketiga bos peta itu kalah, gerbang cerita sesuai langkah cerita. Pemain lama yang sudah pernah
// sampai ke peta tujuan (tercatat di Visited) tidak dikunci lagi setelah pembaruan.
func (s State) DoorOpen(d Door) bool {
	if !s.CanEnter(d.To) {
		return false
	}
	if t, ok := TrialFor(d.Map); ok && t.Next == d.To && !s.Trial(d.Map).Done() {
		return false
	}
	if step, ok := storyGates[[2]string{d.Map, d.To}]; ok && s.Story < step && !slices.Contains(s.Visited, d.To) {
		return false
	}
	return true
}

// TravelCost: jarak jalan terpendek (petak) dari posisi (fromMap, fx, fz) ke (toMap, tx, tz), menyusuri petak yang
// bisa diinjak dan lewat pintu yang terbuka bagi pemain ini. +Inf bila tidak bisa dicapai. Peta tanpa data
// petak memakai jarak garis lurus (straightCost).
func (s State) TravelCost(fromMap string, fx, fz float64, toMap string, tx, tz float64) float64 {
	_, fromTiles := mapRows[fromMap]
	_, toTiles := mapRows[toMap]
	if !fromTiles || !toTiles {
		return s.straightCost(fromMap, fx, fz, toMap, tx, tz)
	}
	sx, sy := int(math.Floor(fx)), int(math.Floor(fz))
	gx, gy := int(math.Floor(tx)), int(math.Floor(tz))
	var start []float32
	if x, y, ok := nearestWalkable(fromMap, sx, sy, 3); ok { // posisi lama bisa berada di petak terhalang
		start = distField(fromMap, x, y)
	}
	if start == nil {
		return s.straightCost(fromMap, fx, fz, toMap, tx, tz)
	}
	best := math.Inf(1)
	if fromMap == toMap {
		best = pathLen(fromMap, start, gx, gy)
	}
	n := len(Doors)
	cost := make([]float64, n)
	done := make([]bool, n)
	for i, d := range Doors {
		cost[i] = math.Inf(1)
		if d.Map == fromMap && s.DoorOpen(d) {
			cost[i] = pathLen(fromMap, start, d.X, d.Y)
		}
	}
	for {
		u := -1
		for i := range Doors {
			if !done[i] && !math.IsInf(cost[i], 1) && (u < 0 || cost[i] < cost[u]) {
				u = i
			}
		}
		if u < 0 || cost[u] >= best {
			break
		}
		done[u] = true
		du := Doors[u]
		ax, ay, ok := nearestWalkable(du.To, du.AtX, du.AtY, int(arriveSlack))
		if !ok {
			continue
		}
		arrive := cachedField(du.To, ax, ay)
		if du.To == toMap {
			best = min(best, cost[u]+max(0, pathLen(toMap, arrive, gx, gy)-arriveSlack))
		}
		for j, dj := range Doors {
			if done[j] || dj.Map != du.To || !s.DoorOpen(dj) {
				continue
			}
			if c := cost[u] + pathLen(du.To, arrive, dj.X, dj.Y); c < cost[j] {
				cost[j] = c
			}
		}
	}
	return best
}

// straightCost: seperti TravelCost tetapi dengan jarak garis lurus (mengabaikan tembok). Hanya untuk peta tanpa
// data petak.
func (s State) straightCost(fromMap string, fx, fz float64, toMap string, tx, tz float64) float64 {
	best := math.Inf(1)
	if fromMap == toMap {
		best = math.Hypot(tx-fx, tz-fz)
	}
	n := len(Doors)
	cost := make([]float64, n)
	done := make([]bool, n)
	for i, d := range Doors {
		cost[i] = math.Inf(1)
		if d.Map == fromMap && s.DoorOpen(d) {
			cost[i] = math.Hypot(float64(d.X)+0.5-fx, float64(d.Y)+0.5-fz)
		}
	}
	for {
		u := -1
		for i := range Doors {
			if !done[i] && !math.IsInf(cost[i], 1) && (u < 0 || cost[i] < cost[u]) {
				u = i
			}
		}
		if u < 0 || cost[u] >= best {
			break
		}
		done[u] = true
		du := Doors[u]
		ax, az := float64(du.AtX)+0.5, float64(du.AtY)+0.5
		if du.To == toMap {
			best = min(best, cost[u]+max(0, math.Hypot(tx-ax, tz-az)-arriveSlack))
		}
		for j, dj := range Doors {
			if done[j] || dj.Map != du.To || !s.DoorOpen(dj) {
				continue
			}
			if c := cost[u] + math.Hypot(float64(dj.X)+0.5-ax, float64(dj.Y)+0.5-az); c < cost[j] {
				cost[j] = c
			}
		}
	}
	return best
}

// MoveTo menerima posisi baru dari klien bila bisa dicapai dari posisi tersimpan dalam waktu sejak gerakan
// terakhir yang diterima (PoseMs). nowMs = jam server (milidetik). Pose harus sudah lolos NormalizePose.
// Bila ditolak, state tidak berubah.
func (s *State) MoveTo(p Pose, nowMs int64) error {
	if !s.CanEnter(p.Map) {
		return ErrHouseLocked
	}
	if _, known := mapRows[p.Map]; known && !Walkable(p.Map, p.X, p.Y) {
		return ErrMoveBlocked // berdiri di dalam tembok, air, atau lava
	}
	fromMap, fx, fz := s.Map, s.FX, s.FZ
	if !ValidPosition(fromMap, s.X, s.Y) || !finite(fx) || !finite(fz) {
		fromMap, fx, fz = SpawnMap, SpawnX+0.5, SpawnY+0.5 // data lama/rusak: anggap dari titik awal
	}
	cost := s.TravelCost(fromMap, fx, fz, p.Map, p.FX, p.FZ)
	if math.IsInf(cost, 1) {
		return ErrMapLocked
	}
	elapsed := 0.0
	if s.PoseMs > 0 && nowMs > s.PoseMs {
		elapsed = float64(nowMs-s.PoseMs) / 1000
	}
	if cost > MaxMoveSpeed*elapsed+MoveGrace {
		return ErrMoveTooFar
	}
	s.Map, s.X, s.Y = p.Map, p.X, p.Y
	s.FX, s.FZ, s.Yaw = p.FX, p.FZ, p.Yaw
	s.PoseMs = nowMs
	s.visit(p.Map) // penjelajahan (roadmap no. 198)
	return nil
}
