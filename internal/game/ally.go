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
	AllyMaxHP      = 30   // HP dasar setiap pahlawan pendamping
	AllyPercent    = 70   // kerusakan pendamping = serangan dasar level pemain x ini persen
	AllyBonus      = 2    // ditambah sekian, supaya musuh berpertahanan tinggi tetap terasa
	AllyIntervalMs = 1800 // jeda antar serangan pendamping
	AllyFirstMs    = 800  // serangan pendamping pertama setelah pertarungan mulai

	MaxSoldiers    = 50 // prajurit biasa yang boleh dibeli (v0.66.0: dulu 5)
	SoldierPrice   = 60 // harga satu prajurit
	SoldierBaseHP  = 40 // HP prajurit di level pasukan 1
	SoldierHPLevel = 20 // tambahan HP tiap level latihan pasukan
	SoldierPercent = 20 // kerusakan satu prajurit = serangan dasar level pemain x ini persen
	SoldierBonus   = 1
)

// Kesalahan pendamping.
var (
	ErrAllyOwned       = errors.New("pahlawan ini sudah kamu beli")
	ErrAllyNotOwn      = errors.New("beli pahlawan ini dulu")
	ErrPartyFull       = errors.New("pendamping terlalu banyak")
	ErrPartyRepeat     = errors.New("pahlawan yang sama dipasang dua kali")
	ErrSoldiersMax     = errors.New("pasukan sudah penuh")
	ErrSoldiersCount   = errors.New("jumlah prajurit yang dipasang harus 0 sampai jumlah prajurit yang kamu punya")
	ErrAllyUnavailable = errors.New("pendamping tidak tersedia")
	ErrAllyFullHP      = errors.New("HP pendamping sudah penuh")
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
	s.record(LedgerPurchase, "Merekrut prajurit", -SoldierPrice)
	return nil
}

// ActiveSoldiers: jumlah prajurit yang ikut bertarung (yang dipasang), 0..Soldiers.
func (s State) ActiveSoldiers() int {
	return max(0, s.Soldiers-s.SoldiersRest)
}

// SetActiveSoldiers memasang n prajurit (0..Soldiers) untuk ikut bertarung; sisanya menunggu di kem.
func (s *State) SetActiveSoldiers(n int) error {
	if n < 0 || n > s.Soldiers {
		return ErrSoldiersCount
	}
	s.SoldiersRest = s.Soldiers - n
	return nil
}

// SoldierMaxHP: HP satu prajurit, naik menurut level latihan pasukan (v0.66.0). Prajurit yang HP-nya habis
// dalam pertarungan gugur selamanya (jumlah prajurit berkurang); yang selamat pulih penuh di pertarungan berikutnya.
func (s State) SoldierMaxHP() int {
	return SoldierBaseHP + SoldierHPLevel*(s.SquadLevel()-1)
}

// soldierPower adalah serangan satu prajurit; naik 5 poin persen tiap level latihan pasukan.
func (s State) soldierPower() int {
	return AttackForLevel(s.Level)*(SoldierPercent+5*(s.SquadLevel()-1))/100 + SoldierBonus
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
	s.record(LedgerPurchase, "Merekrut "+h.Name, -h.Price)
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
	if s.SoldiersRest < 0 || s.SoldiersRest > s.Soldiers {
		return ErrSoldiersCount
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

// ensureAllyHealth memberi HP penuh kepada pendamping lama yang belum memiliki data HP.
// Nilai ini disimpan di State sehingga kompatibel dengan data akun sebelum fitur ini.
func (s *State) ensureAllyHealth() {
	if s.AllyHP == nil {
		s.AllyHP = make(map[string]int, len(s.Allies))
	}
	for _, id := range s.Allies {
		if _, ok := s.AllyHP[id]; !ok {
			s.AllyHP[id] = AllyMaxHP
		}
	}
}

// AllyHealth mengembalikan HP dan HP maksimum pendamping yang dimiliki.
func (s State) AllyHealth(id string) (hp, maxHP int, ok bool) {
	if !slices.Contains(s.Allies, id) {
		return 0, AllyMaxHP, false
	}
	hp, ok = s.AllyHP[id]
	if !ok {
		return AllyMaxHP, AllyMaxHP, true // akun lama: dianggap sehat
	}
	return hp, AllyMaxHP, true
}

// damageAlly mengurangi HP pendamping yang terpasang. HP tidak pernah negatif.
func (s *State) damageAlly(id string, damage int) (remaining int, down bool) {
	s.ensureAllyHealth()
	if damage < 1 || !slices.Contains(s.Party, id) {
		return s.AllyHP[id], false
	}
	s.AllyHP[id] = max(0, s.AllyHP[id]-damage)
	return s.AllyHP[id], s.AllyHP[id] == 0
}

// HealAlly memulihkan HP pendamping yang terpasang. Pengurangan item dilakukan
// oleh pemanggil dalam transaksi penyimpanan yang sama.
func (s *State) HealAlly(id string, amount int) (int, error) {
	if amount < 1 || !slices.Contains(s.Party, id) || !slices.Contains(s.Allies, id) {
		return 0, ErrAllyUnavailable
	}
	s.ensureAllyHealth()
	if s.AllyHP[id] >= AllyMaxHP {
		return s.AllyHP[id], ErrAllyFullHP
	}
	s.AllyHP[id] = min(AllyMaxHP, s.AllyHP[id]+amount)
	return s.AllyHP[id], nil
}

// hasHealthyAlly reports whether at least one equipped companion can fight.
func (s State) hasHealthyAlly() bool {
	for _, id := range s.Party {
		if hp, _, ok := s.AllyHealth(id); ok && hp > 0 {
			return true
		}
	}
	return false
}
