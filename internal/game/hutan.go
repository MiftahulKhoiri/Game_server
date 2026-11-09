package game

import (
	"errors"
	"fmt"
)

// Hutan Lebat (v0.46.0): peta luas 170x50 setelah Perbatasan. Pemain harus mengalahkan 100 binatang, lalu
// bos Goblin Level 1 muncul di singgasana tengah hutan; setelah ia kalah muncul lagi 100 binatang, lalu
// Goblin Level 2, lalu 100 binatang lagi dan Goblin Level 3. Setelah ketiganya kalah, pintu ke Gua Goblin
// (peta 3) terbuka. Server yang menghitung kemajuan ini (State.Hutan); klien hanya menampilkan.
const (
	MapHutanLebat = "hutan_lebat" // hutan luas di selatan Perbatasan
	MapGuaGoblin  = "gua_goblin"  // peta 3: gua sarang goblin, terbuka setelah tiga Goblin kalah

	HutanBeasts = 100 // binatang yang harus dikalahkan di tiap tahap
	HutanWaves  = 3   // jumlah bos Goblin (Level 1..3)

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

// ErrNotBriefed: pemain melawan musuh di Hutan Lebat sebelum bicara dengan Kapten Rimba.
var ErrNotBriefed = errors.New("bicaralah dulu dengan Kapten Rimba di kem hutan sebelum melawan musuh di hutan")

// ErrNoKapten: pemain menyapa Kapten Rimba dari tempat yang terlalu jauh dari kem.
var ErrNoKapten = errors.New("Kapten Rimba tidak ada di sini: temui dia di kem hutan")

// ErrBossNotReady: pemain menginjak singgasana bos hutan sebelum 100 binatang tahap ini kalah (atau semua bos sudah kalah).
var ErrBossNotReady = errors.New("bos Goblin belum muncul: kalahkan dulu semua binatang di hutan")

// HutanProgress: Wave = jumlah bos Goblin yang sudah kalah (0..3); Kills = binatang yang sudah kalah di tahap ini (0..100).
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

// BossReady: 100 binatang tahap ini sudah kalah dan Goblin berikutnya menunggu di singgasana.
func (h HutanProgress) BossReady() bool { return h.Wave < HutanWaves && h.Kills >= HutanBeasts }

// BossID adalah id musuh bos tahap ini (goblin_hutan_1..3).
func (h HutanProgress) BossID() string { return fmt.Sprintf("goblin_hutan_%d", h.Wave+1) }

func (h HutanProgress) valid() bool {
	return h.Wave >= 0 && h.Wave <= HutanWaves && h.Kills >= 0 && h.Kills <= HutanBeasts
}

// HutanBossRadius: jarak terjauh (petak) dari singgasana tempat bos hutan boleh menyambut pemain. Bos berkeliaran
// di sekitar singgasana dan mengejar pemain yang mendekat, jadi pertarungannya dimulai di dunia, bukan di petak K saja.
const HutanBossRadius = 20

// IsHutanBossID: id musuh bos hutan (goblin_hutan_1..3).
func IsHutanBossID(id string) bool {
	for i := 1; i <= HutanWaves; i++ {
		if id == fmt.Sprintf("goblin_hutan_%d", i) {
			return true
		}
	}
	return false
}

// hutanBoss: bos hutan untuk pemain ini (bila sudah waktunya). Pemain harus berada di Hutan Lebat dalam
// HutanBossRadius petak dari singgasana; tepat di petak singgasana selalu sah.
func hutanBoss(p *Player) (Enemy, error) {
	st := &p.State
	if st.Map != MapHutanLebat {
		return Enemy{}, ErrNoBoss
	}
	dx, dy := st.X-HutanBossX, st.Y-HutanBossY
	if dx*dx+dy*dy > HutanBossRadius*HutanBossRadius {
		return Enemy{}, ErrNoBoss
	}
	if !st.Hutan.BossReady() {
		if st.Hutan.Done() {
			return Enemy{}, ErrBossNotReady
		}
		return Enemy{}, fmt.Errorf("%w (%d/%d)", ErrBossNotReady, st.Hutan.Kills, HutanBeasts)
	}
	e, ok := EnemyByID(st.Hutan.BossID())
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
	return newBattle(e, now), nil
}

// recordHutan mencatat kemenangan di Hutan Lebat. Mengembalikan baris log tambahan.
func (s *State) recordHutan(e Enemy) []string {
	if s.Map != MapHutanLebat {
		return nil
	}
	h := &s.Hutan
	if e.Boss {
		if !h.BossReady() || e.ID != h.BossID() {
			return nil
		}
		h.Wave++
		h.Kills = 0
		if h.Done() {
			return []string{"Ketiga Goblin sudah kalah! Pintu menuju Gua Goblin terbuka."}
		}
		return []string{fmt.Sprintf("Goblin Level %d kalah! %d binatang baru muncul di hutan.", h.Wave, HutanBeasts)}
	}
	if h.Done() || h.BossReady() {
		return nil
	}
	h.Kills++
	if h.BossReady() {
		return []string{fmt.Sprintf("Semua binatang tahap ini kalah! Goblin Level %d menunggu di singgasana hutan.", h.Wave+1)}
	}
	return nil
}
