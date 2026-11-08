package game

import (
	"errors"
	"slices"
)

// Pahlawan pendamping: pemain boleh membeli pahlawan (harga di HeroDef.Price) lalu memasangnya
// mendampingi di belakang. Pendamping ikut menyerang musuh secara otomatis selama pertarungan.
const (
	MaxParty       = 3    // pendamping yang boleh dipasang sekaligus
	AllyPercent    = 70   // kerusakan pendamping = serangan dasar level pemain x ini persen
	AllyBonus      = 2    // ditambah sekian, supaya musuh berpertahanan tinggi tetap terasa
	AllyIntervalMs = 2400 // jeda antar serangan pendamping
	AllyFirstMs    = 1500 // serangan pendamping pertama setelah pertarungan mulai
)

// Kesalahan pendamping.
var (
	ErrAllyOwned   = errors.New("pahlawan ini sudah kamu beli")
	ErrAllyNotOwn  = errors.New("beli pahlawan ini dulu")
	ErrPartyFull   = errors.New("pendamping terlalu banyak")
	ErrPartyRepeat = errors.New("pahlawan yang sama dipasang dua kali")
)

// HasAlly memberi tahu apakah pahlawan sudah dibeli.
func (s State) HasAlly(id string) bool { return slices.Contains(s.Allies, id) }

// BuyAlly membeli pahlawan sebagai pendamping. Pahlawan baru langsung dipasang bila masih ada tempat.
func (s *State) BuyAlly(id string) error {
	h, ok := HeroByID(id)
	if !ok || id == "" {
		return ErrUnknownHero
	}
	if s.HasAlly(h.ID) {
		return ErrAllyOwned
	}
	if s.Gold < h.Price {
		return ErrNoGold
	}
	s.Gold -= h.Price
	s.Allies = append(s.Allies, h.ID)
	if len(s.Party) < MaxParty {
		s.Party = append(s.Party, h.ID)
	}
	return nil
}

// SetParty menetapkan pendamping yang dipasang (urutannya = urutan berbaris di belakang pemain).
func (s *State) SetParty(ids []string) error {
	if err := checkParty(s.Allies, ids); err != nil {
		return err
	}
	s.Party = append([]string(nil), ids...)
	return nil
}

func checkParty(owned, party []string) error {
	if len(party) > MaxParty {
		return ErrPartyFull
	}
	for i, id := range party {
		if !slices.Contains(owned, id) {
			return ErrAllyNotOwn
		}
		if slices.Contains(party[:i], id) {
			return ErrPartyRepeat
		}
	}
	return nil
}

func (s State) validateAllies() error {
	if len(s.Allies) > len(Heroes) {
		return ErrPartyFull
	}
	for i, id := range s.Allies {
		if _, ok := HeroByID(id); !ok || id == "" || slices.Contains(s.Allies[:i], id) {
			return ErrUnknownHero
		}
	}
	return checkParty(s.Allies, s.Party)
}

// allyPower adalah serangan satu pendamping.
func (s State) allyPower() int {
	return AttackForLevel(s.Level)*AllyPercent/100 + AllyBonus
}
