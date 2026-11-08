package game

import (
	"errors"
	"fmt"
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

	MaxSoldiers    = 5  // prajurit biasa yang boleh dibeli
	SoldierPrice   = 60 // harga satu prajurit
	SoldierPercent = 20 // kerusakan satu prajurit = serangan dasar level pemain x ini persen
	SoldierBonus   = 1
)

// Kesalahan pendamping.
var (
	ErrAllyOwned   = errors.New("pahlawan ini sudah kamu beli")
	ErrAllyNotOwn  = errors.New("beli pahlawan ini dulu")
	ErrPartyFull   = errors.New("pendamping terlalu banyak")
	ErrPartyRepeat = errors.New("pahlawan yang sama dipasang dua kali")
	ErrSoldiersMax = errors.New("pasukan sudah penuh")
)

// SoldierID: id pendamping prajurit ke-n (1..MaxSoldiers) di kejadian pertarungan dan model klien.
func SoldierID(n int) string { return fmt.Sprintf("prajurit_%d", n) }

// BuySoldier membeli satu prajurit biasa untuk pasukan (ikut bertarung tanpa dipasang).
func (s *State) BuySoldier() error {
	if s.Soldiers >= MaxSoldiers {
		return ErrSoldiersMax
	}
	if s.Gold < SoldierPrice {
		return ErrNoGold
	}
	s.Gold -= SoldierPrice
	s.Soldiers++
	return nil
}

// soldierPower adalah serangan satu prajurit.
func (s State) soldierPower() int {
	return AttackForLevel(s.Level)*SoldierPercent/100 + SoldierBonus
}

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
	if s.Soldiers < 0 || s.Soldiers > MaxSoldiers {
		return ErrSoldiersMax
	}
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
