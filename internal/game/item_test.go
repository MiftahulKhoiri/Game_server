package game

import (
	"errors"
	"testing"
)

func TestBuy(t *testing.T) {
	st := NewState()
	st.Gold = 40
	if err := Buy(&st, PotionID, 2); err != nil {
		t.Fatal(err)
	}
	if st.Gold != 10 || qtyOf(st, PotionID) != 4 {
		t.Errorf("emas %d, ramuan %d", st.Gold, qtyOf(st, PotionID))
	}
	cases := []struct {
		id   string
		qty  int
		want error
	}{
		{"naga", 1, ErrUnknownItem},
		{PotionID, 0, ErrBadQty},
		{PotionID, MaxBuyQty + 1, ErrBadQty},
		{PotionID, 5, ErrNoGold},
		{"taring_goblin", 1, ErrNotForSale},
	}
	for _, c := range cases {
		before := st.Gold
		if err := Buy(&st, c.id, c.qty); !errors.Is(err, c.want) {
			t.Errorf("Buy(%s,%d) = %v, mau %v", c.id, c.qty, err, c.want)
		}
		if st.Gold != before {
			t.Errorf("emas berubah saat gagal: %d -> %d", before, st.Gold)
		}
	}
}

func TestBuyInventoryFullKeepsGold(t *testing.T) {
	st := NewState()
	st.Gold = 100
	st.Inventory = nil
	for i := 0; i < MaxInventory; i++ {
		st.Inventory = append(st.Inventory, Item{ID: "x" + string(rune('a'+i%26)) + string(rune('a'+i/26)), Qty: 1})
	}
	if err := Buy(&st, PotionID, 1); !errors.Is(err, ErrInventoryFull) {
		t.Fatalf("mau ErrInventoryFull, dapat %v", err)
	}
	if st.Gold != 100 {
		t.Errorf("emas harus tetap 100, dapat %d", st.Gold)
	}
}

func TestSell(t *testing.T) {
	st := NewState()
	st.AddItem("taring_goblin", 3)
	if err := Sell(&st, "taring_goblin", 2); err != nil {
		t.Fatal(err)
	}
	if st.Gold != 24 || qtyOf(st, "taring_goblin") != 1 {
		t.Errorf("emas %d, taring %d", st.Gold, qtyOf(st, "taring_goblin"))
	}
	if err := Sell(&st, "taring_goblin", 5); !errors.Is(err, ErrNotEnough) {
		t.Errorf("mau ErrNotEnough, dapat %v", err)
	}
	if err := Sell(&st, "naga", 1); !errors.Is(err, ErrUnknownItem) {
		t.Errorf("mau ErrUnknownItem, dapat %v", err)
	}
}

func TestCatalogConsistent(t *testing.T) {
	seen := map[string]bool{}
	for _, it := range Items() {
		if it.ID == "" || it.Name == "" || seen[it.ID] {
			t.Errorf("barang tidak valid atau kembar: %+v", it)
		}
		seen[it.ID] = true
		if it.BuyPrice > 0 && it.SellPrice >= it.BuyPrice {
			t.Errorf("%s: harga jual harus lebih murah dari harga beli (cegah untung tanpa batas)", it.ID)
		}
	}
	for _, e := range enemies {
		if e.DropID != "" && !seen[e.DropID] {
			t.Errorf("musuh %s menjatuhkan barang yang tidak ada: %s", e.ID, e.DropID)
		}
	}
}

func qtyOf(st State, id string) int {
	for _, it := range st.Inventory {
		if it.ID == id {
			return it.Qty
		}
	}
	return 0
}
