package game

import (
	"errors"
	"fmt"
	"math"
	"time"
)

// Hadiah dunia: menghancurkan pohon, batu, dan rumput, serta membuka peti harta.
// Server yang mengundi hadiah; klien hanya melaporkan apa yang dipukul dan di mana pemain berdiri.
// Bentuk peta (pohon mana yang ada) milik klien, jadi pembatasnya: jarak, jeda antar-permintaan,
// dan masa tumbuh ulang tiap petak.

// Jenis benda yang bisa dihancurkan.
const (
	KindPohon  = "pohon"
	KindBatu   = "batu"
	KindRumput = "rumput"
)

// Barang hadiah dunia.
const (
	DiamondID     = "berlian"
	PowerPotionID = "ramuan_kekuatan"
)

// Aturan hadiah dunia (draf awal untuk diseimbangkan).
const (
	BreakReach      = 4.5  // petak: jarak terjauh pemain ke benda yang dihancurkan
	BreakRespawnSec = 600  // benda tumbuh lagi sekian detik setelah hancur
	MaxBreakBatch   = 12   // paling banyak benda dalam satu permintaan
	MinWorldGapMs   = 120  // jeda minimal antar-permintaan hadiah dunia
	maxBrokenKept   = 1500 // catatan benda hancur yang disimpan per pemain
	ChestReach      = 2.8  // petak: jarak pemain ke peti saat membuka
	ChestRespawnSec = 1800 // peti terisi lagi sekian detik setelah dibuka
	PowerBattles    = 3    // Ramuan Kekuatan berlaku untuk sekian pertarungan
	PowerPercent    = 130  // serangan x1,3 saat ramuan kekuatan aktif
)

// Kesalahan hadiah dunia.
var (
	ErrBadObject    = errors.New("benda tidak sah")
	ErrTooFar       = errors.New("terlalu jauh")
	ErrTooFast      = errors.New("terlalu cepat")
	ErrUnknownChest = errors.New("peti tidak dikenal")
	ErrChestEmpty   = errors.New("peti ini masih kosong, tunggu sebentar")
	ErrNoPower      = errors.New("tidak punya ramuan kekuatan")
)

// ChestDef adalah satu peti harta. Tier menentukan besarnya hadiah (1..4).
type ChestDef struct {
	ID   string `json:"id"`
	Map  string `json:"map"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
	Tier int    `json:"tier"`
}

// Posisi peti harus sama dengan CHESTS di client/scripts/maps.gd.
var chests = []ChestDef{
	{ID: "desa_1", Map: MapDesaAwal, X: 43, Y: 8, Tier: 1},
	{ID: "desa_2", Map: MapDesaAwal, X: 2, Y: 22, Tier: 1},
	{ID: "desa_3", Map: MapDesaAwal, X: 20, Y: 44, Tier: 1},
	{ID: "timur_1", Map: MapDesaAwal, X: 50, Y: 10, Tier: 1},
	{ID: "timur_2", Map: MapDesaAwal, X: 77, Y: 7, Tier: 2},
	{ID: "timur_3", Map: MapDesaAwal, X: 81, Y: 22, Tier: 2},
	{ID: "timur_4", Map: MapDesaAwal, X: 59, Y: 33, Tier: 1},
	{ID: "timur_5", Map: MapDesaAwal, X: 80, Y: 44, Tier: 3},
	{ID: "timur_6", Map: MapDesaAwal, X: 51, Y: 44, Tier: 2},
	{ID: "perbatasan_1", Map: MapPerbatasan, X: 3, Y: 3, Tier: 2},
	{ID: "perbatasan_2", Map: MapPerbatasan, X: 30, Y: 17, Tier: 2},
	{ID: "perbatasan_3", Map: MapPerbatasan, X: 40, Y: 24, Tier: 2},
	{ID: "perbatasan_4", Map: MapPerbatasan, X: 6, Y: 45, Tier: 2},
	{ID: "perbatasan_5", Map: MapPerbatasan, X: 40, Y: 45, Tier: 2},
	{ID: "gunung_1", Map: MapGunungBatu, X: 40, Y: 7, Tier: 3},
	{ID: "gunung_2", Map: MapGunungBatu, X: 3, Y: 28, Tier: 3},
	{ID: "gunung_3", Map: MapGunungBatu, X: 42, Y: 32, Tier: 3},
	{ID: "gunung_4", Map: MapGunungBatu, X: 5, Y: 45, Tier: 3},
	{ID: "gunung_5", Map: MapGunungBatu, X: 39, Y: 45, Tier: 3},
	{ID: "gua_1", Map: MapGuaBatu, X: 1, Y: 1, Tier: 4},
	{ID: "gua_2", Map: MapGuaBatu, X: 13, Y: 1, Tier: 4},
}

// Chests mengembalikan salinan seluruh peti.
func Chests() []ChestDef { return append([]ChestDef(nil), chests...) }

// ChestByID mencari peti.
func ChestByID(id string) (ChestDef, bool) {
	for _, c := range chests {
		if c.ID == id {
			return c, true
		}
	}
	return ChestDef{}, false
}

// BreakTarget adalah benda yang dipukul klien: petak (X, Z) di peta pemain.
type BreakTarget struct {
	Kind string `json:"kind"`
	X    int    `json:"x"`
	Z    int    `json:"z"`
}

// Loot adalah hasil satu permintaan: emas dan barang yang masuk ke pemain.
type Loot struct {
	Gold  int    `json:"gold"`
	Items []Item `json:"items"`
	// Broken: berapa benda yang benar-benar menghasilkan undian (belum dalam masa tumbuh ulang).
	Broken int `json:"broken"`
}

func (l *Loot) addItem(id string, qty int) {
	for i := range l.Items {
		if l.Items[i].ID == id {
			l.Items[i].Qty += qty
			return
		}
	}
	l.Items = append(l.Items, Item{ID: id, Qty: qty})
}

// rollBreak mengundi hadiah satu benda. Hasilnya emas, satu barang, atau tidak ada.
func rollBreak(kind string, level int, rng Rand) (gold int, item string) {
	r := rng.Intn(100)
	scale := func(lo, hi int) int { // emas naik pelan mengikuti level
		return (lo + rng.Intn(hi-lo+1)) * (10 + min(level, 30)) / 10
	}
	switch kind {
	case KindRumput:
		switch {
		case r < 20:
			return scale(1, 3), ""
		case r < 24:
			return 0, PotionID
		}
	case KindPohon:
		switch {
		case r < 35:
			return scale(3, 9), ""
		case r < 43:
			return 0, PotionID
		case r < 45:
			return 0, DiamondID
		case r < 48:
			return 0, PowerPotionID
		}
	case KindBatu:
		switch {
		case r < 35:
			return scale(5, 14), ""
		case r < 39:
			return 0, PotionID
		case r < 44:
			return 0, DiamondID
		case r < 48:
			return 0, PowerPotionID
		}
	}
	return 0, ""
}

func brokenKey(mapID, kind string, x, z int) string {
	return fmt.Sprintf("%s|%s|%d|%d", mapID, kind, x, z)
}

func dist(fx, fz float64, x, z int) float64 {
	return math.Hypot(fx-(float64(x)+0.5), fz-(float64(z)+0.5))
}

// throttle menolak permintaan yang datang terlalu rapat.
func (s *State) throttle(now time.Time) error {
	ms := now.UnixMilli()
	if s.LastWorldMs > 0 && ms-s.LastWorldMs < MinWorldGapMs {
		return ErrTooFast
	}
	s.LastWorldMs = ms
	return nil
}

// pruneBroken membuang catatan yang sudah lewat masa tumbuh ulang; bila masih kebanyakan, yang terlama dibuang.
func (s *State) pruneBroken(now int64) {
	for k, t := range s.Broken {
		if now-t >= BreakRespawnSec {
			delete(s.Broken, k)
		}
	}
	for len(s.Broken) > maxBrokenKept {
		oldestK, oldestT := "", int64(math.MaxInt64)
		for k, t := range s.Broken {
			if t < oldestT {
				oldestK, oldestT = k, t
			}
		}
		delete(s.Broken, oldestK)
	}
}

// BreakObjects menghancurkan benda-benda dekat pemain dan membagikan hadiahnya.
// Posisi pemain (Map, FX, FZ) sudah diperbarui dari permintaan sebelum dipanggil.
func (s *State) BreakObjects(now time.Time, targets []BreakTarget, rng Rand) (Loot, error) {
	var loot Loot
	if len(targets) == 0 || len(targets) > MaxBreakBatch {
		return loot, ErrBadObject
	}
	info, ok := worldMaps[s.Map]
	if !ok {
		return loot, ErrBadObject
	}
	for _, t := range targets {
		if t.Kind != KindPohon && t.Kind != KindBatu && t.Kind != KindRumput {
			return loot, ErrBadObject
		}
		if t.X < 0 || t.Z < 0 || t.X >= info.Width || t.Z >= info.Height {
			return loot, ErrBadObject
		}
		if dist(s.FX, s.FZ, t.X, t.Z) > BreakReach {
			return loot, ErrTooFar
		}
	}
	if err := s.throttle(now); err != nil {
		return loot, err
	}
	sec := now.Unix()
	if s.Broken == nil {
		s.Broken = map[string]int64{}
	}
	s.pruneBroken(sec)
	for _, t := range targets {
		key := brokenKey(s.Map, t.Kind, t.X, t.Z)
		if _, hidup := s.Broken[key]; hidup {
			continue // masih dalam masa tumbuh ulang: tidak ada hadiah
		}
		s.Broken[key] = sec
		loot.Broken++
		gold, item := rollBreak(t.Kind, s.Level, rng)
		loot.Gold += gold
		if item != "" {
			loot.addItem(item, 1)
		}
	}
	s.grant(loot)
	return loot, nil
}

// grant memasukkan hadiah ke pemain. Barang yang tidak muat di tas dilewati.
func (s *State) grant(l Loot) {
	s.Gold += l.Gold
	for _, it := range l.Items {
		s.AddItem(it.ID, it.Qty)
	}
}

// OpenChest membuka peti harta bila pemain cukup dekat dan peti sudah terisi.
func (s *State) OpenChest(now time.Time, id string, rng Rand) (Loot, error) {
	var loot Loot
	c, ok := ChestByID(id)
	if !ok {
		return loot, ErrUnknownChest
	}
	if s.Map != c.Map || dist(s.FX, s.FZ, c.X, c.Y) > ChestReach {
		return loot, ErrTooFar
	}
	if err := s.throttle(now); err != nil {
		return loot, err
	}
	sec := now.Unix()
	if t, opened := s.Chests[id]; opened && sec-t < ChestRespawnSec {
		return loot, ErrChestEmpty
	}
	if s.Chests == nil {
		s.Chests = map[string]int64{}
	}
	s.Chests[id] = sec

	loot.Broken = 1
	// Tiga hadiah acak yang berbeda dari kumpulan hadiah peti; berlian hanya bila beruntung (peti lebih tinggi = lebih mungkin).
	pool := chestPool(c.Tier)
	for range ChestRewards {
		total := 0
		for _, e := range pool {
			total += e.weight
		}
		r := rng.Intn(total)
		for i, e := range pool {
			if r < e.weight {
				if e.id == "" {
					loot.Gold += (40 + rng.Intn(41)) * c.Tier * (10 + min(s.Level, 30)) / 10
				} else {
					loot.addItem(e.id, e.qty)
				}
				pool = append(pool[:i], pool[i+1:]...)
				break
			}
			r -= e.weight
		}
	}
	s.grant(loot)
	return loot, nil
}

// ChestRewards: jumlah hadiah acak dalam satu peti.
const ChestRewards = 3

type chestEntry struct {
	id     string // kosong = emas
	qty    int
	weight int
}

// chestPool: kumpulan hadiah peti beserta bobot undian. Peluang berlian = 3 + 2 x tier (%) dari bobot.
func chestPool(tier int) []chestEntry {
	return []chestEntry{
		{"", 0, 36},
		{PotionID, 2, 20},
		{PowerPotionID, 1, 12},
		{KartuKeahlianID, 1, 9},
		{"koin_kuno", 1, 8},
		{"permata_merah", 1, 7},
		{DiamondID, 1, 3 + 2*tier},
	}
}

// WorldItem: benda hancur atau peti terbuka yang belum tumbuh/terisi lagi, untuk digambar klien.
type WorldItem struct {
	Kind string `json:"kind,omitempty"` // kosong untuk peti
	ID   string `json:"id,omitempty"`   // id peti
	X    int    `json:"x"`
	Z    int    `json:"z"`
	Left int64  `json:"left"` // sisa detik sampai pulih
}

// WorldView mendaftar benda hancur dan peti terbuka di sebuah peta.
func (s State) WorldView(now time.Time, mapID string) []WorldItem {
	sec := now.Unix()
	out := []WorldItem{}
	for key, t := range s.Broken {
		var m, kind string
		var x, z int
		if n, _ := fmt.Sscanf(splitBar(key), "%s %s %d %d", &m, &kind, &x, &z); n != 4 || m != mapID {
			continue
		}
		if left := BreakRespawnSec - (sec - t); left > 0 {
			out = append(out, WorldItem{Kind: kind, X: x, Z: z, Left: left})
		}
	}
	for _, c := range chests {
		if c.Map != mapID {
			continue
		}
		if t, opened := s.Chests[c.ID]; opened {
			if left := ChestRespawnSec - (sec - t); left > 0 {
				out = append(out, WorldItem{ID: c.ID, X: c.X, Z: c.Y, Left: left})
			}
		}
	}
	return out
}

func splitBar(s string) string {
	b := []byte(s)
	for i := range b {
		if b[i] == '|' {
			b[i] = ' '
		}
	}
	return string(b)
}

// UsePowerPotion meminum Ramuan Kekuatan: serangan naik untuk beberapa pertarungan berikutnya.
func (s *State) UsePowerPotion() error {
	if s.itemQty(PowerPotionID) < 1 {
		return ErrNoPower
	}
	s.RemoveItem(PowerPotionID, 1)
	s.PowerLeft = PowerBattles
	s.gainEnergy(EnergyPowerPotion)
	return nil
}

// endBattleBuffs dipanggil tiap pertarungan berakhir (menang, kalah, kabur).
func (s *State) endBattleBuffs() {
	if s.PowerLeft > 0 {
		s.PowerLeft--
	}
}
