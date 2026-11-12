package game

import (
	"errors"
	"fmt"
	"math"
	"slices"
)

// Dunia yang hidup (roadmap no. 186-200): jam dunia bersama, cuaca, kejadian dunia (Serbuan Goblin ke
// desa, Hari Pasar), wilayah aman/berbahaya, penjelajahan, dan tempat rahasia.
//
// Jam dunia dihitung dari jam server (detik Unix), bukan dari kapan aplikasi dibuka, sehingga semua
// pemain melihat siang/malam, hujan, dan kejadian yang sama, dan server bisa memeriksanya. Klien
// memakai rumus yang sama (client/scripts/atmosphere.gd) dengan selisih jam dari GET /v1/time.
const (
	DaySeconds    = 720 // 12 menit nyata = 24 jam permainan
	WeatherBlockS = 150 // lama satu blok cuaca
	RainPercent   = 30  // peluang sebuah blok hujan
	NightFrom     = 19.0
	NightTo       = 5.0
	TimeGraceS    = 30 // kelonggaran 30 detik (= 1 jam permainan) untuk musuh siang/malam

	RaidEvery     = 3 // Serbuan Goblin: malam setiap hari ke-3 (hari % 3 == 1)
	MarketEvery   = 3 // Hari Pasar: siang setiap hari ke-3 (hari % 3 == 2), jam 8-17
	MarketFrom    = 8.0
	MarketTo      = 17.0
	MarketPercent = 10 // potongan harga di toko saat Hari Pasar
	RaidGoal      = 5  // kemenangan atas penyerbu untuk hadiah pertahanan desa
	RaidRewardG   = 200
	NightAttack   = 110 // musuh di luar ruangan saat malam: serangan 110% (minimal +1)
	NightXP       = 125 // ... dan hadiah XP 125%
)

// Jenis waktu muncul musuh.
const (
	TimeNight = "malam"
	TimeDay   = "siang"
)

// Kejadian dunia.
const (
	EventRaid   = "serbuan"
	EventMarket = "pasar"
)

// WorldHour: jam permainan 0..24 pada detik Unix `unix`.
func WorldHour(unix int64) float64 {
	return math.Mod(float64(unix%DaySeconds)/DaySeconds*24, 24)
}

// WorldDay: nomor hari permainan.
func WorldDay(unix int64) int64 { return unix / DaySeconds }

// IsNightAt: malam (19.00-05.00)?
func IsNightAt(unix int64) bool {
	h := WorldHour(unix)
	return h >= NightFrom || h < NightTo
}

// RainingAt: blok cuaca ini hujan? Rumus hash yang sama dengan klien (atmosphere.gd raining_now).
func RainingAt(unix int64) bool {
	block := unix / WeatherBlockS
	v := uint64((block*7919+13)%1000003) * 2654435761 & 0xFFFFFFFF
	return v%100 < RainPercent
}

// nightOf: hari tempat malam ini dimulai (jam < 5 masih malam hari sebelumnya).
func nightOf(unix int64) int64 {
	if WorldHour(unix) < NightTo {
		return WorldDay(unix) - 1
	}
	return WorldDay(unix)
}

// RaidActive: Serbuan Goblin sedang berlangsung di Desa Awal?
func RaidActive(unix int64) bool {
	return IsNightAt(unix) && posMod(nightOf(unix), RaidEvery) == 1
}

// RaidID: nomor serbuan yang sedang/terakhir berlangsung (hari mulai malamnya).
func RaidID(unix int64) int64 { return nightOf(unix) }

// MarketActive: Hari Pasar (potongan harga toko) sedang berlangsung?
func MarketActive(unix int64) bool {
	h := WorldHour(unix)
	return posMod(WorldDay(unix), MarketEvery) == 2 && h >= MarketFrom && h < MarketTo
}

func posMod(a, m int64) int64 { return ((a % m) + m) % m }

// WorldEvent: keadaan satu kejadian dunia untuk klien.
type WorldEvent struct {
	Kind   string `json:"kind"`
	Name   string `json:"name"`
	Active bool   `json:"active"`
	EndsIn int64  `json:"ends_in,omitempty"` // detik sampai selesai (bila aktif)
	NextIn int64  `json:"next_in,omitempty"` // detik sampai mulai (bila belum)
}

// Events: kedua kejadian dunia pada `unix` (dicari maju per 10 detik, paling jauh 3 hari).
func Events(unix int64) []WorldEvent {
	out := []WorldEvent{}
	for _, k := range []struct {
		kind, name string
		on         func(int64) bool
	}{{EventRaid, "Serbuan Goblin", RaidActive}, {EventMarket, "Hari Pasar", MarketActive}} {
		ev := WorldEvent{Kind: k.kind, Name: k.name, Active: k.on(unix)}
		limit := unix + DaySeconds*3
		for t := unix + 10; t <= limit; t += 10 {
			if k.on(t) != ev.Active {
				if ev.Active {
					ev.EndsIn = t - unix
				} else {
					ev.NextIn = t - unix
				}
				break
			}
		}
		out = append(out, ev)
	}
	return out
}

// within: f benar pada unix atau dalam TimeGraceS sebelum/sesudahnya.
func within(unix int64, f func(int64) bool) bool {
	return f(unix) || f(unix-TimeGraceS) || f(unix+TimeGraceS)
}

// timeAllows: musuh boleh muncul pada jam ini? (dengan kelonggaran untuk klien yang sedikit terlambat)
func (e Enemy) timeAllows(unix int64) bool {
	switch {
	case e.Raid && !within(unix, RaidActive):
		return false
	case e.Time == TimeNight:
		return within(unix, IsNightAt)
	case e.Time == TimeDay:
		return within(unix, func(u int64) bool { return !IsNightAt(u) })
	}
	return true
}

// outdoorMaps: peta terbuka yang mengikuti siang/malam (gua dan bangunan tidak).
var outdoorMaps = []string{MapDesaAwal, MapPerbatasan, MapGunungBatu, MapHutanLebat}

// Outdoors: peta mengikuti siang/malam?
func Outdoors(mapID string) bool { return slices.Contains(outdoorMaps, mapID) }

// --- wilayah (no. 195-196) ---

// Zone: tingkat bahaya peta dan level yang disarankan.
type Zone struct {
	Map    string `json:"map"`
	Danger string `json:"danger"` // aman, waspada, berbahaya
	Level  int    `json:"level"`  // level yang disarankan
}

// Zones: wilayah semua peta yang bisa dijelajahi.
var Zones = []Zone{
	{MapDesaAwal, "aman", 1}, {MapPerbatasan, "waspada", 1}, {MapHutanLebat, "berbahaya", 3},
	{MapGunungBatu, "berbahaya", 4}, {MapGuaGoblin, "berbahaya", 5}, {MapGuaBatu, "berbahaya", 6},
	{MapIstana, "berbahaya", 10}, {MapTakhta, "berbahaya", 12},
}

// --- penjelajahan (no. 198) ---

// ExploreMaps: peta yang dihitung untuk pencapaian Penjelajah.
var ExploreMaps = []string{MapDesaAwal, MapPerbatasan, MapHutanLebat, MapGunungBatu, MapGuaGoblin, MapGuaBatu, MapIstana, MapTakhta}

// visit mencatat peta baru yang dikunjungi. true bila baru.
func (s *State) visit(mapID string) bool {
	if !slices.Contains(ExploreMaps, mapID) || slices.Contains(s.Visited, mapID) {
		return false
	}
	s.Visited = append(s.Visited, mapID)
	s.checkAchievements()
	return true
}

// Visit dipanggil server setiap posisi disimpan.
func (s *State) Visit(mapID string) bool { return s.visit(mapID) }

// --- tempat rahasia (no. 199) ---

// Secret: tempat tersembunyi; menemukannya (berdiri di dekatnya) memberi hadiah sekali.
type Secret struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Map  string `json:"map"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
	Gold int    `json:"gold"`
	Item string `json:"item"`
	Hint string `json:"hint"`
}

// SecretRange: jarak petak terjauh dari tempat rahasia agar dianggap menemukannya.
const SecretRange = 2

// Secrets: tempat rahasia. Posisi harus sama dengan client/scripts/maps.gd RAHASIA.
var Secrets = []Secret{
	{ID: "batu_bertulis", Name: "Batu Bertulis Kuno", Map: MapPerbatasan, X: 2, Y: 47, Gold: 60, Item: "koin_kuno",
		Hint: "Di sudut barat daya Perbatasan ada batu tua bertulis."},
	{ID: "pohon_keramat", Name: "Pohon Keramat", Map: MapHutanLebat, X: 84, Y: 2, Gold: 120, Item: "permata_merah",
		Hint: "Di tepi utara Hutan Binatang, di tengah perjalanan, ada pohon tua bercahaya."},
	{ID: "sarang_naga", Name: "Sarang Naga Tua", Map: MapGunungBatu, X: 178, Y: 9, Gold: 200, Item: DiamondID,
		Hint: "Pendaki bercerita tentang sarang naga kosong di ujung lorong buntu pojok timur laut lereng Gunung Berapi."},
}

// Kesalahan dunia.
var (
	ErrUnknownSecret = errors.New("tempat rahasia tidak dikenal")
	ErrSecretFar     = errors.New("tidak ada apa-apa di sini")
	ErrSecretFound   = errors.New("tempat ini sudah kamu temukan")
	ErrNoRaid        = errors.New("tidak ada serbuan yang sedang/baru berlangsung")
	ErrRaidGoal      = fmt.Errorf("kalahkan %d penyerbu dulu", RaidGoal)
	ErrRaidClaimed   = errors.New("hadiah pertahanan desa sudah diambil")
)

// FindSecret: pemain (posisi tersimpan) menemukan tempat rahasia `id`.
func (s *State) FindSecret(id string) (Secret, error) {
	i := slices.IndexFunc(Secrets, func(x Secret) bool { return x.ID == id })
	if i < 0 {
		return Secret{}, ErrUnknownSecret
	}
	sec := Secrets[i]
	switch {
	case slices.Contains(s.Secrets, id):
		return Secret{}, ErrSecretFound
	case s.Map != sec.Map || absInt(s.X-sec.X) > SecretRange || absInt(s.Y-sec.Y) > SecretRange:
		return Secret{}, ErrSecretFar
	case sec.Item != "" && !s.canAdd(sec.Item, 1):
		return Secret{}, ErrInventoryFull
	}
	s.Secrets = append(s.Secrets, id)
	s.gainGold(sec.Gold)
	if sec.Item != "" {
		s.AddItem(sec.Item, 1)
	}
	s.record(LedgerQuest, "Menemukan "+sec.Name, sec.Gold)
	s.checkAchievements()
	return sec, nil
}

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

// --- pertahanan desa (no. 190-191) ---

// RaidProgress: kemenangan pemain atas penyerbu pada satu serbuan.
type RaidProgress struct {
	ID      int64 `json:"id"`
	Kills   int   `json:"kills"`
	Claimed bool  `json:"claimed,omitempty"`
}

// recordRaid dipanggil saat menang melawan penyerbu.
func (s *State) recordRaid(unix int64) string {
	id := RaidID(unix)
	if s.Raid.ID != id {
		s.Raid = RaidProgress{ID: id}
	}
	s.Raid.Kills++
	if s.Raid.Kills == RaidGoal {
		return fmt.Sprintf("Desa terlindungi! %d penyerbu dikalahkan: ambil hadiahmu (%d emas).", RaidGoal, RaidRewardG)
	}
	return fmt.Sprintf("Pertahanan desa: %d/%d penyerbu.", min(s.Raid.Kills, RaidGoal), RaidGoal)
}

// ClaimRaid mengambil hadiah pertahanan desa (serbuan yang sedang atau baru saja berlangsung).
func (s *State) ClaimRaid(unix int64) error {
	switch {
	case s.Raid.ID != RaidID(unix):
		return ErrNoRaid
	case s.Raid.Claimed:
		return ErrRaidClaimed
	case s.Raid.Kills < RaidGoal:
		return ErrRaidGoal
	}
	s.Raid.Claimed = true
	s.gainGold(RaidRewardG)
	s.Defended++
	s.record(LedgerQuest, "Hadiah pertahanan desa", RaidRewardG)
	s.checkAchievements()
	return nil
}

func (s State) validWorld() bool {
	if len(s.Visited) > len(ExploreMaps) || len(s.Secrets) > len(Secrets) || s.Raid.Kills < 0 || s.Defended < 0 {
		return false
	}
	for _, m := range s.Visited {
		if !slices.Contains(ExploreMaps, m) {
			return false
		}
	}
	for _, id := range s.Secrets {
		if !slices.ContainsFunc(Secrets, func(x Secret) bool { return x.ID == id }) {
			return false
		}
	}
	return true
}
