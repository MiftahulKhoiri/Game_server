package game

import "errors"

// Pahlawan yang bisa dipilih pemain. Sifatnya penampilan + nama skill: statistik dan
// keseimbangan sama untuk semua pahlawan. Model 3D-nya ada di klien (id = nama berkas GLB).
const DefaultHero = "ksatria"

// ErrUnknownHero berarti id pahlawan tidak dikenal.
var ErrUnknownHero = errors.New("pahlawan tidak dikenal")

// HeroDef menjelaskan satu pahlawan.
type HeroDef struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Weapon string `json:"weapon"`
	Skill1 string `json:"skill1"`
	Skill2 string `json:"skill2"`
}

// Heroes adalah daftar pahlawan; urutannya dipakai di layar profil.
var Heroes = []HeroDef{
	{ID: "ksatria", Name: "Ksatria", Weapon: "Pedang dan perisai", Skill1: "Tebasan Kuat", Skill2: "Perisai Cahaya"},
	{ID: "pendekar_kapak", Name: "Pendekar Kapak", Weapon: "Kapak besar", Skill1: "Belahan Kapak", Skill2: "Teriakan Perang"},
	{ID: "pemanah", Name: "Pemanah", Weapon: "Busur silang", Skill1: "Panah Tembus", Skill2: "Kabut Pelindung"},
	{ID: "pendekar_tombak", Name: "Pendekar Tombak", Weapon: "Tombak", Skill1: "Tusukan Kilat", Skill2: "Putaran Tombak"},
}

// HeroByID mencari pahlawan; "" berarti pahlawan bawaan (akun lama).
func HeroByID(id string) (HeroDef, bool) {
	if id == "" {
		id = DefaultHero
	}
	for _, h := range Heroes {
		if h.ID == id {
			return h, true
		}
	}
	return HeroDef{}, false
}

// HeroDef mengembalikan pahlawan aktif pemain (bawaan bila belum dipilih).
func (s State) HeroDef() HeroDef {
	h, _ := HeroByID(s.Hero)
	return h
}

// SetHero mengganti pahlawan yang dipakai.
func (s *State) SetHero(id string) error {
	h, ok := HeroByID(id)
	if !ok || id == "" {
		return ErrUnknownHero
	}
	s.Hero = h.ID
	return nil
}
