package game

import (
	"errors"
	"fmt"
	"slices"
)

// Ujian wilayah (v0.46.0, diubah v0.65.0): di Hutan Lebat, Gua Goblin, dan Gunung Batu pemain harus melewati
// tiga tahap. Tahap 1: kalahkan 25 musuh, lalu bos Level 1 muncul di singgasananya; tahap 2: 75 musuh lalu bos
// Level 2; tahap 3: 100 musuh lalu bos Level 3. Setelah ketiga bos kalah, pintu ke peta berikutnya terbuka
// (Hutan Lebat -> Gua Goblin -> Gunung Batu -> Gua Batu). Server yang menghitung kemajuan ini; klien hanya
// menampilkan. Kemajuan Hutan Lebat ada di State.Hutan (nama lama), peta lain di State.Trials.
const (
	MapHutanLebat = "hutan_lebat" // hutan luas di selatan Perbatasan
	MapGuaGoblin  = "gua_goblin"  // peta 3: gua sarang goblin, terbuka setelah tiga Goblin hutan kalah

	HutanWaves = 3 // jumlah bos tiap wilayah (Level 1..3)

	// Singgasana bos di tengah Hutan Lebat; posisinya sama dengan petak 'K' di client/scripts/maps.gd.
	// (v0.49.0: dipindah ke dekat gerbang Gua Goblin, di sebelah persimpangan tiga jalan.)
	HutanBossX = 142
	HutanBossY = 47

	// Kapten Rimba, penjaga kem hutan di Perbatasan (client/scripts/maps.gd, NPC "kapten_kem"), dan jarak
	// terjauh (petak) dari tempatnya berdiri agar pembicaraan dengannya sah.
	KaptenX      = 23
	KaptenY      = 4
	KaptenRadius = 8

	// RadarID: barang khusus pemberian Kapten Rimba; klien memakainya untuk menampilkan titik musuh di hutan.
	RadarID = "radar_musuh"
)

// StageKills: musuh yang harus dikalahkan sebelum bos tiap tahap muncul (tahap 1, 2, 3).
var StageKills = [HutanWaves]int{25, 75, 100}

// HutanBeasts: jumlah musuh terbanyak dalam satu tahap (tahap terakhir).
const HutanBeasts = 100

// StageNeed: musuh yang harus dikalahkan pada tahap `wave` (0 = tahap 1).
func StageNeed(wave int) int {
	if wave < 0 {
		wave = 0
	}
	if wave >= HutanWaves {
		return StageKills[HutanWaves-1]
	}
	return StageKills[wave]
}

// TrialDef: satu wilayah ujian. Bos = BossPrefix + "1".."3"; singgasana di (BossX, BossY), sama dengan
// Maps.TRIALS di klien.
type TrialDef struct {
	Map        string
	BossPrefix string
	BossX      int
	BossY      int
	Next       string // peta yang terbuka setelah ketiga bos kalah
	// v0.71.0: Hunt = bos memburu pemain ke seluruh peta (pertarungan boleh dimulai di mana saja di peta itu);
	// BossLevel > 0 = bos makin kuat untuk pemain di atas level ini (lihat strengthenBoss).
	Hunt      bool
	BossLevel int
}

// Trials: wilayah ujian berurutan.
var Trials = []TrialDef{
	{Map: MapHutanLebat, BossPrefix: "goblin_hutan_", BossX: HutanBossX, BossY: HutanBossY, Next: MapGuaGoblin},
	{Map: MapGuaGoblin, BossPrefix: "kepala_goblin_", BossX: 30, BossY: 61, Next: MapGunungBatu, Hunt: true, BossLevel: 6}, // v0.70.0: singgasana di depan pintu utama
	{Map: MapGunungBatu, BossPrefix: "ogre_gunung_", BossX: 21, BossY: 27, Next: MapGuaBatu},
}

// MapName: nama peta untuk pesan di log.
func MapName(id string) string {
	switch id {
	case MapHutanLebat:
		return "Hutan Binatang"
	case MapGuaGoblin:
		return "Gua Goblin"
	case MapGunungBatu:
		return "Lereng Gunung Berapi"
	case MapGuaBatu:
		return "Benteng Orc"
	case MapIstana:
		return "Istana Kegelapan"
	case MapTakhta:
		return "Ruang Takhta"
	}
	return id
}

// TrialFor: wilayah ujian untuk peta ini, bila ada.
func TrialFor(mapID string) (TrialDef, bool) {
	for _, t := range Trials {
		if t.Map == mapID {
			return t, true
		}
	}
	return TrialDef{}, false
}

// Trial: kemajuan ujian di peta itu. Pemain lama yang sudah pernah sampai ke peta sesudahnya (tercatat di
// Visited) dianggap sudah lulus, supaya tidak terkunci setelah pembaruan.
func (s *State) Trial(mapID string) HutanProgress {
	if mapID == MapHutanLebat {
		return s.Hutan
	}
	if p, ok := s.Trials[mapID]; ok {
		return p
	}
	if t, ok := TrialFor(mapID); ok && slices.Contains(s.Visited, t.Next) {
		return HutanProgress{Wave: HutanWaves}
	}
	return HutanProgress{}
}

func (s *State) setTrial(mapID string, p HutanProgress) {
	if mapID == MapHutanLebat {
		s.Hutan = p
		return
	}
	if s.Trials == nil {
		s.Trials = map[string]HutanProgress{}
	}
	s.Trials[mapID] = p
}

func (s *State) validTrials() bool {
	if len(s.Trials) > len(Trials) {
		return false
	}
	for m, p := range s.Trials {
		if _, ok := TrialFor(m); !ok || m == MapHutanLebat || !p.valid() {
			return false
		}
	}
	return s.Hutan.valid()
}

// ErrNotBriefed: pemain melawan musuh di Hutan Lebat sebelum bicara dengan Kapten Rimba.
var ErrNotBriefed = errors.New("bicaralah dulu dengan Kapten Rimba di kem hutan sebelum melawan musuh di hutan")

// ErrNoKapten: pemain menyapa Kapten Rimba dari tempat yang terlalu jauh dari kem.
var ErrNoKapten = errors.New("Kapten Rimba tidak ada di sini: temui dia di kem hutan")

// ErrBossNotReady: pemain menantang bos wilayah sebelum musuh tahap ini cukup dikalahkan (atau semua bos sudah kalah).
var ErrBossNotReady = errors.New("bos belum muncul: kalahkan dulu musuh tahap ini")

// HutanProgress: kemajuan satu wilayah ujian. Wave = jumlah bos yang sudah kalah (0..3); Kills = musuh yang
// sudah kalah di tahap ini (0..StageNeed(Wave)).
// Briefed: pemain sudah bicara dengan Kapten Rimba (pertarungan di hutan baru boleh dimulai setelahnya).
type HutanProgress struct {
	Wave    int  `json:"wave"`
	Kills   int  `json:"kills"`
	Briefed bool `json:"briefed,omitempty"`
}

// Started: pemain boleh melawan musuh di Hutan Lebat. Pemain lama yang sudah punya kemajuan dianggap sudah
// diberi arahan, supaya tidak terkunci setelah pembaruan.
func (h HutanProgress) Started() bool { return h.Briefed || h.Wave > 0 || h.Kills > 0 }

// Done: ketiga Goblin sudah kalah, pintu ke Gua Goblin terbuka.
func (h HutanProgress) Done() bool { return h.Wave >= HutanWaves }

// Need: musuh yang harus dikalahkan pada tahap sekarang.
func (h HutanProgress) Need() int { return StageNeed(h.Wave) }

// BossReady: musuh tahap ini sudah cukup dikalahkan dan bos berikutnya menunggu di singgasana.
func (h HutanProgress) BossReady() bool { return h.Wave < HutanWaves && h.Kills >= h.Need() }

// BossID adalah id musuh bos Hutan Lebat tahap ini (goblin_hutan_1..3).
func (h HutanProgress) BossID() string { return fmt.Sprintf("goblin_hutan_%d", h.Wave+1) }

func (h HutanProgress) valid() bool {
	return h.Wave >= 0 && h.Wave <= HutanWaves && h.Kills >= 0 && h.Kills <= HutanBeasts
}

// HutanBossRadius: jarak terjauh (petak) dari singgasana tempat bos wilayah boleh menyambut pemain. Bos berkeliaran
// di sekitar singgasana dan mengejar pemain yang mendekat, jadi pertarungannya dimulai di dunia, bukan di petak K saja.
const HutanBossRadius = 20

// IsHutanBossID: id musuh bos wilayah ujian (goblin_hutan_1..3, kepala_goblin_1..3, ogre_gunung_1..3).
func IsHutanBossID(id string) bool {
	for _, t := range Trials {
		for i := 1; i <= HutanWaves; i++ {
			if id == fmt.Sprintf("%s%d", t.BossPrefix, i) {
				return true
			}
		}
	}
	return false
}

// hutanBoss: bos wilayah ujian untuk pemain ini (bila sudah waktunya). Pemain harus berada di peta ujian dalam
// HutanBossRadius petak dari singgasana.
func hutanBoss(p *Player) (Enemy, error) {
	st := &p.State
	t, ok := TrialFor(st.Map)
	if !ok {
		return Enemy{}, ErrNoBoss
	}
	dx, dy := st.X-t.BossX, st.Y-t.BossY
	if !t.Hunt && dx*dx+dy*dy > HutanBossRadius*HutanBossRadius {
		return Enemy{}, ErrNoBoss
	}
	h := st.Trial(st.Map)
	if !h.BossReady() {
		if h.Done() {
			return Enemy{}, ErrBossNotReady
		}
		return Enemy{}, fmt.Errorf("%w (%d/%d)", ErrBossNotReady, h.Kills, h.Need())
	}
	e, ok := EnemyByID(fmt.Sprintf("%s%d", t.BossPrefix, h.Wave+1))
	if !ok {
		return Enemy{}, ErrNoBoss
	}
	return e, nil
}

// BriefHutan: pemain bicara dengan Kapten Rimba. Ia memberi Radar Musuh dan sejak itu musuh di hutan boleh dilawan.
// Aman diulang: radar yang hilang dari ransel diberikan lagi, selain itu tidak ada yang berubah.
func (s *State) BriefHutan() error {
	if s.Map != MapPerbatasan {
		return ErrNoKapten
	}
	dx, dy := s.X-KaptenX, s.Y-KaptenY
	if dx*dx+dy*dy > KaptenRadius*KaptenRadius {
		return ErrNoKapten
	}
	if !s.hasRadar() && !s.AddItem(RadarID, 1) {
		return ErrInventoryFull
	}
	s.Hutan.Briefed = true
	s.advanceStory() // langkah cerita "temui Kapten Rimba" (story.go)
	return nil
}

func (s *State) hasRadar() bool {
	for _, it := range s.Inventory {
		if it.ID == RadarID && it.Qty > 0 {
			return true
		}
	}
	return false
}

// StartHutanBossBattle memulai pertarungan dengan bos hutan yang sedang menyambut pemain (dari musuh di dunia).
func StartHutanBossBattle(p *Player, now int64) (Battle, error) {
	e, err := hutanBoss(p)
	if err != nil {
		return Battle{}, err
	}
	b := styled(p, newBattle(e, now))
	b.strengthenBoss(p.State, e)
	return b, nil
}

// recordHutan mencatat kemenangan di wilayah ujian (Hutan Lebat, Gua Goblin, Gunung Batu). Mengembalikan baris log.
func (s *State) recordHutan(e Enemy) []string {
	t, ok := TrialFor(s.Map)
	if !ok {
		return nil
	}
	h := s.Trial(s.Map)
	defer func() { s.setTrial(s.Map, h) }()
	if e.Boss {
		if !h.BossReady() || e.ID != fmt.Sprintf("%s%d", t.BossPrefix, h.Wave+1) {
			return nil
		}
		h.Wave++
		h.Kills = 0
		if h.Done() {
			return []string{fmt.Sprintf("Ketiga bos %s kalah! Pintu menuju %s terbuka.", MapName(t.Map), MapName(t.Next))}
		}
		return []string{fmt.Sprintf("%s kalah! Tahap %d: kalahkan %d musuh.", e.Name, h.Wave+1, h.Need())}
	}
	if h.Done() || h.BossReady() {
		return nil
	}
	h.Kills++
	if h.BossReady() {
		return []string{fmt.Sprintf("Tahap %d selesai! Bos Level %d menunggu di singgasana.", h.Wave+1, h.Wave+1)}
	}
	return nil
}
