package game

import "errors"

// Rumah milik pemain (roadmap no. 127): satu rumah kosong di Desa Awal bisa dibeli. Hanya pemiliknya
// yang boleh masuk (server menolak menyimpan posisi di dalamnya bagi yang belum punya). Di dalam ada
// ranjang untuk beristirahat (sama dengan istirahat di desa).

// HousePrice adalah harga rumah.
const HousePrice = 500

// Kesalahan rumah.
var (
	ErrHouseOwned  = errors.New("kamu sudah punya rumah ini")
	ErrHouseLocked = errors.New("rumah ini bukan milikmu")
	ErrHouseFar    = errors.New("beli rumah di Desa Awal, di depan rumahnya")
)

// BuyHouse membeli rumah: emas berkurang HousePrice, harus berada di Desa Awal.
func (s *State) BuyHouse() error {
	switch {
	case s.House:
		return ErrHouseOwned
	case s.Map != MapDesaAwal:
		return ErrHouseFar
	case s.Gold < HousePrice:
		return ErrNoGold
	}
	s.Gold -= HousePrice
	s.House = true
	return nil
}

// CanEnter: boleh berada di peta ini? Rumah pemain hanya untuk pemiliknya.
func (s State) CanEnter(mapID string) bool {
	return mapID != MapRumahPemain || s.House
}
