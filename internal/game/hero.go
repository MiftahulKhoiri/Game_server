package game

import "errors"

// Pahlawan yang bisa dipilih pemain. Statistik dasar sama untuk semua pahlawan; yang berbeda
// nama skill dan gaya senjata (combat_style.go: kecepatan, kerusakan, kritis, tembus pertahanan). Model 3D-nya ada di klien (id = nama berkas GLB).
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
	Price  int    `json:"price"` // harga membeli pahlawan ini sebagai pendamping
	Style  string `json:"style"` // gaya senjata (combat_style.go): pedang, kapak, busur, tombak, sihir
}

// Heroes adalah daftar pahlawan; urutannya dipakai di layar profil.
var Heroes = []HeroDef{
	{ID: "ksatria", Name: "Ksatria", Weapon: "Pedang dan perisai", Skill1: "Tebasan Kuat", Skill2: "Perisai Cahaya", Price: 250, Style: StylePedang},
	{ID: "pendekar_kapak", Name: "Pendekar Kapak", Weapon: "Kapak besar", Skill1: "Belahan Kapak", Skill2: "Teriakan Perang", Price: 350, Style: StyleKapak},
	{ID: "pemanah", Name: "Pemanah", Weapon: "Busur silang", Skill1: "Panah Tembus", Skill2: "Kabut Pelindung", Price: 300, Style: StyleBusur},
	{ID: "pendekar_tombak", Name: "Pendekar Tombak", Weapon: "Tombak", Skill1: "Tusukan Kilat", Skill2: "Putaran Tombak", Price: 300, Style: StyleTombak},
	{ID: "penyihir", Name: "Penyihir", Weapon: "Tongkat sihir", Skill1: "Bola Api", Skill2: "Perisai Mantra", Price: 400, Style: StyleSihir},
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

// NumOutfits adalah jumlah variasi pakaian yang bisa dipilih (warnanya diatur klien, models.gd OUTFITS).
const NumOutfits = 4

// ErrUnknownOutfit berarti nomor pakaian di luar 0..NumOutfits-1.
var ErrUnknownOutfit = errors.New("pakaian tidak dikenal")

// SetOutfit mengganti variasi pakaian pahlawan (gratis, hanya tampilan).
func (s *State) SetOutfit(n int) error {
	if n < 0 || n >= NumOutfits {
		return ErrUnknownOutfit
	}
	s.Outfit = n
	return nil
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
