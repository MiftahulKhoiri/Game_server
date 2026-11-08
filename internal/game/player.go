// Package game berisi aturan dan model data inti game RPG.
//
// Paket ini sengaja tidak tahu apa pun soal HTTP atau database, supaya
// logika game mudah diuji dan dikembangkan tanpa menyentuh lapisan lain.
package game

import (
	"errors"
	"fmt"
	"math"
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
	Level int    `json:"level"`
	XP    int    `json:"xp"`
	HP    int    `json:"hp"`
	MaxHP int    `json:"max_hp"`
	Gold  int    `json:"gold"`
	Map   string `json:"map"`
	X     int    `json:"x"`
	Y     int    `json:"y"`
	// FX, FZ, Yaw adalah posisi halus untuk dunia 3D: satuan dunia = 1 petak, jadi
	// petak (X, Y) mencakup FX di [X, X+1) dan FZ di [Y, Y+1). Yaw = arah hadap (radian).
	// Petak (X, Y) tetap yang dipakai aturan server; lihat NormalizePose.
	FX        float64 `json:"fx"`
	FZ        float64 `json:"fz"`
	Yaw       float64 `json:"yaw"`
	Inventory []Item  `json:"inventory"`
	// Hero adalah id pahlawan yang dipakai (lihat hero.go); kosong = pahlawan bawaan.
	Hero string `json:"hero,omitempty"`
	// Allies: pahlawan yang sudah dibeli sebagai pendamping; Party: yang dipasang mendampingi (maks MaxParty).
	// Keduanya hanya diubah server (lihat ally.go).
	Allies []string `json:"allies,omitempty"`
	Party  []string `json:"party,omitempty"`
	// Soldiers: jumlah prajurit biasa yang dibeli (maks MaxSoldiers); semuanya ikut bertarung (lihat ally.go).
	Soldiers int `json:"soldiers,omitempty"`
	// Equipment hanya diubah server (equip/unequip).
	Equipment Equipment `json:"equipment"`
	// Quests hanya diubah server (terima, kemajuan, klaim hadiah).
	Quests []QuestProgress `json:"quests,omitempty"`
	// Broken: benda dunia yang dihancurkan ("peta|jenis|x|z" -> detik Unix), tumbuh lagi setelah BreakRespawnSec.
	Broken map[string]int64 `json:"broken,omitempty"`
	// Chests: peti harta yang sudah dibuka (id -> detik Unix), terisi lagi setelah ChestRespawnSec.
	Chests map[string]int64 `json:"chests,omitempty"`
	// LastWorldMs: waktu permintaan hadiah dunia terakhir (milidetik), untuk membatasi kecepatan.
	LastWorldMs int64 `json:"last_world_ms,omitempty"`
	// PowerLeft: sisa pertarungan dengan Ramuan Kekuatan aktif.
	PowerLeft int `json:"power_left,omitempty"`
	// EnergyUsed: energi (kekuatan) yang terpakai, 0..MaxEnergy; 0 = penuh. Disimpan sebagai
	// "terpakai" supaya data lama otomatis berenergi penuh. Lihat energy.go.
	EnergyUsed int `json:"energy_used,omitempty"`
}

// Player adalah pemain lengkap beserta metadata penyimpanannya.
type Player struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email,omitempty"` // kosong untuk akun lama
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
		FX:        SpawnX + 0.5,
		FZ:        SpawnY + 0.5,
		Inventory: []Item{{ID: PotionID, Qty: 2}},
		Hero:      DefaultHero,
	}
}

// PlaceAtTileCenter menaruh pemain di tengah petak (X, Y), menghadap ke bawah layar.
func (s *State) PlaceAtTileCenter() {
	s.FX, s.FZ, s.Yaw = float64(s.X)+0.5, float64(s.Y)+0.5, 0
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
	case !finite(s.FX) || !finite(s.FZ) || !finite(s.Yaw):
		return errors.New("posisi halus harus bilangan biasa")
	case len(s.Broken) > maxBrokenKept+MaxBreakBatch || len(s.Chests) > len(chests):
		return errors.New("catatan dunia terlalu banyak")
	case s.EnergyUsed < 0 || s.EnergyUsed > MaxEnergy:
		return fmt.Errorf("energi terpakai harus 0..%d", MaxEnergy)
	case s.PowerLeft < 0 || s.PowerLeft > PowerBattles:
		return errors.New("sisa ramuan kekuatan tidak sah")
	case len(s.Inventory) > MaxInventory:
		return fmt.Errorf("inventori maksimal %d tumpukan", MaxInventory)
	}
	if _, ok := HeroByID(s.Hero); !ok {
		return ErrUnknownHero
	}
	if err := s.validateAllies(); err != nil {
		return err
	}
	if len(s.Equipment.Weapon) > 64 || len(s.Equipment.Armor) > 64 {
		return errors.New("id perlengkapan terlalu panjang")
	}
	if err := validateQuests(s.Quests); err != nil {
		return err
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

func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }
