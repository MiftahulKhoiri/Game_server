// Package game berisi aturan dan model data inti game RPG.
//
// Paket ini sengaja tidak tahu apa pun soal HTTP atau database, supaya
// logika game mudah diuji dan dikembangkan tanpa menyentuh lapisan lain.
package game

import (
	"errors"
	"fmt"
	"time"
)

// Batas-batas dasar yang dipakai validasi. Angka-angka ini draf awal dan
// akan menyesuaikan desain game (lihat docs/GAME_DESIGN.md).
const (
	MaxLevel     = 100
	MaxInventory = 200
	MaxStack     = 999
)

// Item adalah satu tumpukan barang di tas pemain.
type Item struct {
	ID  string `json:"id"`
	Qty int    `json:"qty"`
}

// State adalah kemajuan permainan yang disimpan server untuk satu pemain.
type State struct {
	Level     int    `json:"level"`
	XP        int    `json:"xp"`
	HP        int    `json:"hp"`
	MaxHP     int    `json:"max_hp"`
	Gold      int    `json:"gold"`
	Map       string `json:"map"`
	X         int    `json:"x"`
	Y         int    `json:"y"`
	Inventory []Item `json:"inventory"`
}

// Player adalah pemain lengkap beserta metadata penyimpanannya.
type Player struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	State     State     `json:"state"`
	Version   int       `json:"version"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// NewState mengembalikan kondisi awal untuk pemain baru.
func NewState() State {
	return State{
		Level:     1,
		HP:        30,
		MaxHP:     30,
		Map:       SpawnMap,
		X:         SpawnX,
		Y:         SpawnY,
		Inventory: []Item{{ID: PotionID, Qty: 2}},
	}
}

// AddItem menambah qty barang ke tas. Mengembalikan false bila tas penuh.
func (s *State) AddItem(id string, qty int) bool {
	for i := range s.Inventory {
		if s.Inventory[i].ID == id {
			s.Inventory[i].Qty = min(MaxStack, s.Inventory[i].Qty+qty)
			return true
		}
	}
	if len(s.Inventory) >= MaxInventory {
		return false
	}
	s.Inventory = append(s.Inventory, Item{ID: id, Qty: min(MaxStack, qty)})
	return true
}

// RemoveItem mengurangi qty barang. Mengembalikan false bila jumlahnya kurang.
func (s *State) RemoveItem(id string, qty int) bool {
	for i := range s.Inventory {
		if s.Inventory[i].ID != id {
			continue
		}
		if s.Inventory[i].Qty < qty {
			return false
		}
		s.Inventory[i].Qty -= qty
		if s.Inventory[i].Qty == 0 {
			s.Inventory = append(s.Inventory[:i], s.Inventory[i+1:]...)
		}
		return true
	}
	return false
}

// Validate memeriksa apakah State masuk akal. Server tidak boleh percaya
// data dari klien begitu saja.
func (s State) Validate() error {
	switch {
	case s.Level < 1 || s.Level > MaxLevel:
		return fmt.Errorf("level harus 1..%d", MaxLevel)
	case s.XP < 0:
		return errors.New("xp tidak boleh negatif")
	case s.MaxHP < 1:
		return errors.New("max_hp harus minimal 1")
	case s.HP < 0 || s.HP > s.MaxHP:
		return errors.New("hp harus 0..max_hp")
	case s.Gold < 0:
		return errors.New("gold tidak boleh negatif")
	case s.Map == "" || len(s.Map) > 64:
		return errors.New("map wajib diisi (maksimal 64 karakter)")
	case s.X < 0 || s.Y < 0:
		return errors.New("posisi tidak boleh negatif")
	case len(s.Inventory) > MaxInventory:
		return fmt.Errorf("inventori maksimal %d tumpukan", MaxInventory)
	}
	for _, it := range s.Inventory {
		if it.ID == "" || len(it.ID) > 64 {
			return errors.New("id item wajib diisi (maksimal 64 karakter)")
		}
		if it.Qty < 1 || it.Qty > MaxStack {
			return fmt.Errorf("qty item harus 1..%d", MaxStack)
		}
	}
	return nil
}
