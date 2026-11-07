package game

import (
	"errors"
	"slices"
)

// Equipment adalah perlengkapan yang sedang dipakai (id barang, "" = kosong).
type Equipment struct {
	Weapon string `json:"weapon"`
	Armor  string `json:"armor"`
}

// Has memberi tahu apakah barang ini sedang dipakai.
func (e Equipment) Has(id string) bool { return id != "" && (e.Weapon == id || e.Armor == id) }

// Kesalahan perlengkapan dan pemakaian barang.
var (
	ErrNotEquippable = errors.New("barang ini bukan perlengkapan")
	ErrNothingWorn   = errors.New("tidak ada perlengkapan di slot itu")
	ErrBadSlot       = errors.New("slot tidak dikenal")
	ErrNotUsable     = errors.New("barang ini tidak bisa dipakai di sini")
	ErrCannotRest    = errors.New("istirahat hanya bisa di desa")
)

func (s State) itemQty(id string) int {
	i := slices.IndexFunc(s.Inventory, func(it Item) bool { return it.ID == id })
	if i < 0 {
		return 0
	}
	return s.Inventory[i].Qty
}

// Attack adalah serangan total: dari level ditambah bonus senjata.
func (s State) Attack() int {
	def, _ := ItemByID(s.Equipment.Weapon)
	atk := AttackForLevel(s.Level) + def.Attack
	if s.PowerLeft > 0 {
		atk = atk * PowerPercent / 100
	}
	return atk
}

// Defense adalah pertahanan total: dari level ditambah bonus pelindung.
func (s State) Defense() int {
	def, _ := ItemByID(s.Equipment.Armor)
	return DefenseForLevel(s.Level) + def.Defense
}

// Equip memakai barang dari tas (barang tetap ada di tas). Perlengkapan lama di slot yang sama diganti.
func (s *State) Equip(id string) error {
	def, ok := ItemByID(id)
	if !ok {
		return ErrUnknownItem
	}
	if def.Kind != KindEquipment {
		return ErrNotEquippable
	}
	if s.itemQty(id) < 1 {
		return ErrNotEnough
	}
	switch def.Slot {
	case SlotWeapon:
		s.Equipment.Weapon = id
	case SlotArmor:
		s.Equipment.Armor = id
	default:
		return ErrNotEquippable
	}
	return nil
}

// Unequip melepas perlengkapan dari slot.
func (s *State) Unequip(slot string) error {
	var target *string
	switch slot {
	case SlotWeapon:
		target = &s.Equipment.Weapon
	case SlotArmor:
		target = &s.Equipment.Armor
	default:
		return ErrBadSlot
	}
	if *target == "" {
		return ErrNothingWorn
	}
	*target = ""
	return nil
}

// UseItem memakai barang di luar pertarungan. Saat ini hanya ramuan.
func (s *State) UseItem(id string) error {
	if id == PowerPotionID {
		return s.UsePowerPotion()
	}
	if id != PotionID {
		if _, ok := ItemByID(id); !ok {
			return ErrUnknownItem
		}
		return ErrNotUsable
	}
	if s.itemQty(id) < 1 {
		return ErrNoPotion
	}
	if s.HP >= s.MaxHP {
		return ErrFullHP
	}
	s.RemoveItem(id, 1)
	s.HP = min(s.MaxHP, s.HP+PotionHeal)
	return nil
}

// Rest memulihkan HP penuh, gratis, hanya di desa (wilayah aman).
func (s *State) Rest() error {
	if s.Map != MapDesaAwal {
		return ErrCannotRest
	}
	if s.HP >= s.MaxHP {
		return ErrFullHP
	}
	s.HP = s.MaxHP
	return nil
}
