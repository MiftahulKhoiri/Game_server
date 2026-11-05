package game

import (
	"errors"
	"fmt"
)

// Jenis barang.
const (
	KindConsumable = "consumable" // bisa dipakai (mis. ramuan)
	KindMaterial   = "material"   // bahan, dijatuhkan musuh
	KindTreasure   = "treasure"   // harta, hadiah misi
)

// MaxBuyQty membatasi jumlah satu kali transaksi.
const MaxBuyQty = 99

// ItemDef adalah definisi barang. Harga 0 berarti tidak bisa dibeli / dijual.
type ItemDef struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Kind      string `json:"kind"`
	BuyPrice  int    `json:"buy_price"`  // harga beli pemain dari toko
	SellPrice int    `json:"sell_price"` // harga jual pemain ke toko
}

// Daftar barang. Barang baru: tambahkan satu baris di sini lalu (opsional)
// gambar client/assets/items/<id>.png. Draf harga untuk diseimbangkan.
var items = []ItemDef{
	{ID: PotionID, Name: "Ramuan Penyembuh", Kind: KindConsumable, BuyPrice: 15, SellPrice: 6},
	{ID: "taring_goblin", Name: "Taring Goblin", Kind: KindMaterial, SellPrice: 12},
	{ID: "koin_kuno", Name: "Koin Kuno", Kind: KindTreasure, SellPrice: 25},
	{ID: "permata_merah", Name: "Permata Merah", Kind: KindTreasure, SellPrice: 60},
}

// Kesalahan transaksi toko.
var (
	ErrUnknownItem   = errors.New("barang tidak dikenal")
	ErrNotForSale    = errors.New("barang ini tidak dijual di toko")
	ErrNotBuyable    = errors.New("toko tidak membeli barang ini")
	ErrBadQty        = fmt.Errorf("jumlah harus 1..%d", MaxBuyQty)
	ErrNoGold        = errors.New("emas tidak cukup")
	ErrNotEnough     = errors.New("barang yang dimiliki tidak cukup")
	ErrInventoryFull = errors.New("tas penuh")
)

// Items mengembalikan salinan seluruh daftar barang.
func Items() []ItemDef { return append([]ItemDef(nil), items...) }

// ItemByID mencari barang berdasarkan id.
func ItemByID(id string) (ItemDef, bool) {
	for _, it := range items {
		if it.ID == id {
			return it, true
		}
	}
	return ItemDef{}, false
}

// Buy membeli qty barang dari toko.
func Buy(st *State, id string, qty int) error {
	def, ok := ItemByID(id)
	if !ok {
		return ErrUnknownItem
	}
	if qty < 1 || qty > MaxBuyQty {
		return ErrBadQty
	}
	if def.BuyPrice <= 0 {
		return ErrNotForSale
	}
	cost := def.BuyPrice * qty
	if st.Gold < cost {
		return ErrNoGold
	}
	if !st.AddItem(id, qty) {
		return ErrInventoryFull
	}
	st.Gold -= cost
	return nil
}

// Sell menjual qty barang ke toko.
func Sell(st *State, id string, qty int) error {
	def, ok := ItemByID(id)
	if !ok {
		return ErrUnknownItem
	}
	if qty < 1 || qty > MaxBuyQty {
		return ErrBadQty
	}
	if def.SellPrice <= 0 {
		return ErrNotBuyable
	}
	if !st.RemoveItem(id, qty) {
		return ErrNotEnough
	}
	st.Gold += def.SellPrice * qty
	return nil
}
