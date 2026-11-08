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
	HutanBossX = 85
	HutanBossY = 25
)

// ErrBossNotReady: pemain menginjak singgasana bos hutan sebelum 100 binatang tahap ini kalah (atau semua bos sudah kalah).
var ErrBossNotReady = errors.New("bos Goblin belum muncul: kalahkan dulu semua binatang di hutan")

// HutanProgress: Wave = jumlah bos Goblin yang sudah kalah (0..3); Kills = binatang yang sudah kalah di tahap ini (0..100).
type HutanProgress struct {
	Wave  int `json:"wave"`
	Kills int `json:"kills"`
}

// Done: ketiga Goblin sudah kalah, pintu ke Gua Goblin terbuka.
func (h HutanProgress) Done() bool { return h.Wave >= HutanWaves }

// BossReady: 100 binatang tahap ini sudah kalah dan Goblin berikutnya menunggu di singgasana.
func (h HutanProgress) BossReady() bool { return h.Wave < HutanWaves && h.Kills >= HutanBeasts }

// BossID adalah id musuh bos tahap ini (goblin_hutan_1..3).
func (h HutanProgress) BossID() string { return fmt.Sprintf("goblin_hutan_%d", h.Wave+1) }

func (h HutanProgress) valid() bool {
	return h.Wave >= 0 && h.Wave <= HutanWaves && h.Kills >= 0 && h.Kills <= HutanBeasts
}

// hutanBoss: bos di singgasana hutan untuk pemain ini (bila sudah waktunya).
func hutanBoss(p *Player) (Enemy, error) {
	st := &p.State
	if st.Map != MapHutanLebat || st.X != HutanBossX || st.Y != HutanBossY {
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
