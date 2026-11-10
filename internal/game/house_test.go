package game

import (
	"errors"
	"testing"
)

func TestBuyHouse(t *testing.T) {
	st := NewState()
	st.Gold = HousePrice - 1
	if err := st.BuyHouse(); !errors.Is(err, ErrNoGold) {
		t.Fatalf("emas kurang: %v", err)
	}
	if st.CanEnter(MapRumahPemain) || !st.CanEnter(MapDesaAwal) {
		t.Fatal("belum punya rumah: tidak boleh masuk rumah pemain")
	}
	st.Gold = HousePrice + 10
	st.Map = MapPerbatasan
	if err := st.BuyHouse(); !errors.Is(err, ErrHouseFar) {
		t.Fatalf("harus di desa: %v", err)
	}
	st.Map = MapDesaAwal
	if err := st.BuyHouse(); err != nil || !st.House || st.Gold != 10 {
		t.Fatalf("beli rumah: %v house=%v gold=%d", err, st.House, st.Gold)
	}
	if err := st.BuyHouse(); !errors.Is(err, ErrHouseOwned) {
		t.Fatalf("beli dua kali: %v", err)
	}
	if !st.CanEnter(MapRumahPemain) {
		t.Fatal("pemilik boleh masuk")
	}
	st.Map = MapRumahPemain
	st.HP = 1
	if err := st.Rest(); err != nil {
		t.Fatalf("istirahat di rumah sendiri: %v", err)
	}
}
