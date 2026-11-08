package game

import "errors"

// Energi (kekuatan): tenaga untuk jurus. Serangan biasa mengisinya sedikit, jurus menguras,
// Ramuan Kekuatan mengisinya, dan istirahat di desa memulihkannya penuh.
const (
	MaxEnergy         = 100
	Skill1Energy      = 20 // biaya Tebasan Kuat (skill1)
	Skill2Energy      = 25 // biaya Perisai Cahaya (skill2)
	EnergyPerAttack   = 4  // energi didapat tiap serangan biasa
	EnergyPerWin      = 15 // energi didapat tiap menang
	EnergyPowerPotion = 60 // energi yang dipulihkan Ramuan Kekuatan
)

// ErrNoEnergy berarti energi tidak cukup untuk jurus.
var ErrNoEnergy = errors.New("energi tidak cukup")

// Energy adalah energi yang tersisa, 0..MaxEnergy.
func (s State) Energy() int { return MaxEnergy - s.EnergyUsed }

// spendEnergy memakai n energi; false (tanpa perubahan) bila tidak cukup.
func (s *State) spendEnergy(n int) bool {
	if s.Energy() < n {
		return false
	}
	s.EnergyUsed += n
	return true
}

// gainEnergy menambah energi sampai penuh.
func (s *State) gainEnergy(n int) { s.EnergyUsed = max(0, s.EnergyUsed-n) }
