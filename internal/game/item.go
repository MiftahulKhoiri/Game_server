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
	KindEquipment  = "equipment"  // bisa dipakai di slot perlengkapan
	KindFood       = "food"       // makanan: dimakan memulihkan HP
	KindSpecial    = "special"    // barang khusus pemberian NPC (mis. Radar Musuh); tidak bisa dijual atau dipakai
)

// Toko di desa. Pembelian hanya sah di toko yang menjualnya (pemain harus berada di toko itu).
const (
	ShopPotion = "toko"      // toko ramuan (ramuan, harta)
	ShopFood   = "makan"     // rumah makan
	ShopGear   = "peralatan" // toko peralatan (pedang, baju zirah)
)

// Slot perlengkapan.
const (
	SlotWeapon = "weapon" // menambah serangan
	SlotArmor  = "armor"  // menambah pertahanan
	SlotHelmet = "helmet" // menambah pertahanan (roadmap no. 16)
)

// MaxBuyQty membatasi jumlah satu kali transaksi.
const MaxBuyQty = 99

// ItemDef adalah definisi barang. Harga 0 berarti tidak bisa dibeli / dijual.
type ItemDef struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Kind      string `json:"kind"`
	BuyPrice  int    `json:"buy_price"`      // harga beli pemain dari toko
	SellPrice int    `json:"sell_price"`     // harga jual pemain ke toko
	Shop      string `json:"shop,omitempty"` // toko yang menjual barang ini (ShopPotion / ShopFood); kosong = tidak dijual
	Heal      int    `json:"heal,omitempty"` // HP yang dipulihkan saat dimakan (KindFood)
	// Khusus perlengkapan (Kind == KindEquipment):
	Slot    string `json:"slot,omitempty"`
	Attack  int    `json:"attack,omitempty"`  // bonus serangan (SlotWeapon)
	Defense int    `json:"defense,omitempty"` // bonus pertahanan (SlotArmor / SlotHelmet)
}

// Daftar barang. Barang baru: tambahkan satu baris di sini lalu (opsional)
// gambar client/assets/items/<id>.png. Draf harga untuk diseimbangkan.
var items = []ItemDef{
	{ID: PotionID, Name: "Ramuan Penyembuh", Kind: KindConsumable, BuyPrice: 15, SellPrice: 6, Shop: ShopPotion},
	{ID: "taring_goblin", Name: "Taring Goblin", Kind: KindMaterial, SellPrice: 12},
	{ID: "koin_kuno", Name: "Koin Kuno", Kind: KindTreasure, SellPrice: 25},
	{ID: "permata_merah", Name: "Permata Merah", Kind: KindTreasure, SellPrice: 60},
	{ID: DiamondID, Name: "Berlian", Kind: KindTreasure, SellPrice: DiamondGold},
	{ID: PowerPotionID, Name: "Ramuan Kekuatan", Kind: KindConsumable, BuyPrice: 40, SellPrice: 20, Shop: ShopPotion},
	{ID: "roti", Name: "Roti Hangat", Kind: KindFood, BuyPrice: 8, SellPrice: 3, Shop: ShopFood, Heal: 10},
	{ID: "sup_ayam", Name: "Sup Ayam", Kind: KindFood, BuyPrice: 20, SellPrice: 8, Shop: ShopFood, Heal: 25},
	{ID: "daging_bakar", Name: "Daging Bakar", Kind: KindFood, BuyPrice: 45, SellPrice: 18, Shop: ShopFood, Heal: 50},
	{ID: KartuKeahlianID, Name: "Kartu Keahlian", Kind: KindMaterial, BuyPrice: 60, SellPrice: 20, Shop: ShopGear},
	{ID: RadarID, Name: "Radar Musuh", Kind: KindSpecial}, // pemberian Kapten Rimba; tidak dijual
	{ID: "pedang_besi", Name: "Pedang Besi", Kind: KindEquipment, BuyPrice: 120, SellPrice: 40, Shop: ShopGear, Slot: SlotWeapon, Attack: 3},
	{ID: "pedang_baja", Name: "Pedang Baja", Kind: KindEquipment, BuyPrice: 320, SellPrice: 110, Shop: ShopGear, Slot: SlotWeapon, Attack: 6},
	{ID: "pedang_rune", Name: "Pedang Rune", Kind: KindEquipment, Slot: SlotWeapon, Attack: 10}, // hadiah misi, tidak dijual
	{ID: "baju_kulit", Name: "Baju Kulit", Kind: KindEquipment, BuyPrice: 80, SellPrice: 25, Shop: ShopGear, Slot: SlotArmor, Defense: 2},
	{ID: "zirah_besi", Name: "Zirah Besi", Kind: KindEquipment, BuyPrice: 240, SellPrice: 80, Shop: ShopGear, Slot: SlotArmor, Defense: 4},
	{ID: "helm_kulit", Name: "Helm Kulit", Kind: KindEquipment, BuyPrice: 60, SellPrice: 20, Shop: ShopGear, Slot: SlotHelmet, Defense: 1},
	{ID: "helm_besi", Name: "Helm Besi", Kind: KindEquipment, BuyPrice: 180, SellPrice: 60, Shop: ShopGear, Slot: SlotHelmet, Defense: 3},
}

// DiamondGold: nilai satu Berlian, barang paling berharga. Dijual seharga ini, atau ditukar (barter) dengan barang apa
// saja di toko: butuh ceil(harga / DiamondGold) berlian.
const DiamondGold = 500

// Kesalahan transaksi toko.
var (
	ErrUnknownItem   = errors.New("barang tidak dikenal")
	ErrNotForSale    = errors.New("barang ini tidak dijual di toko")
	ErrNotBuyable    = errors.New("toko tidak membeli barang ini")
	ErrBadQty        = fmt.Errorf("jumlah harus 1..%d", MaxBuyQty)
	ErrNoGold        = errors.New("emas tidak cukup")
	ErrNotEnough     = errors.New("barang yang dimiliki tidak cukup")
	ErrInventoryFull = errors.New("ransel penuh")
	ErrEquipped      = errors.New("lepas dulu perlengkapan ini sebelum menjualnya")
	ErrUnknownShop   = errors.New("toko tidak dikenal")
	ErrWrongShop     = errors.New("toko ini tidak menjual barang itu")
	ErrNoDiamond     = errors.New("berlian tidak cukup")
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

// ValidShop: apakah `shop` salah satu toko di desa.
func ValidShop(shop string) bool {
	return shop == ShopPotion || shop == ShopFood || shop == ShopGear
}

// ShopItems: barang yang bisa dibeli atau dijual di toko `shop`. Rumah makan hanya membeli makanan,
// toko peralatan hanya perlengkapan, toko ramuan sisanya (ramuan dan harta).
func ShopItems(shop string) ([]ItemDef, error) {
	if !ValidShop(shop) {
		return nil, ErrUnknownShop
	}
	var out []ItemDef
	for _, it := range items {
		if it.Shop == shop || (it.SellPrice > 0 && shopBuys(shop, it)) {
			out = append(out, it)
		}
	}
	return out, nil
}

// shopBuys: apakah toko `shop` mau membeli barang ini dari pemain.
func shopBuys(shop string, it ItemDef) bool {
	switch shop {
	case ShopFood:
		return it.Kind == KindFood
	case ShopGear:
		return it.Kind == KindEquipment
	}
	return it.Kind != KindFood && it.Kind != KindEquipment
}

// Buy membeli qty barang di toko mana pun yang menjualnya (dipakai tes dan aturan inti).
func Buy(st *State, id string, qty int) error { return BuyAt(st, "", id, qty) }

// BuyAt membeli qty barang dari toko `shop`; "" = tanpa memeriksa toko.
func BuyAt(st *State, shop, id string, qty int) error {
	if shop != "" && !ValidShop(shop) {
		return ErrUnknownShop
	}
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
	if shop != "" && def.Shop != shop {
		return ErrWrongShop
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

// Sell menjual qty barang ke toko mana pun (dipakai tes dan aturan inti).
func Sell(st *State, id string, qty int) error { return SellAt(st, "", id, qty) }

// SellAt menjual qty barang ke toko `shop`; "" = tanpa memeriksa toko.
func SellAt(st *State, shop, id string, qty int) error {
	if shop != "" && !ValidShop(shop) {
		return ErrUnknownShop
	}
	def, ok := ItemByID(id)
	if !ok {
		return ErrUnknownItem
	}
	if qty < 1 || qty > MaxBuyQty {
		return ErrBadQty
	}
	if def.SellPrice <= 0 || (shop != "" && !shopBuys(shop, def)) {
		return ErrNotBuyable
	}
	owned := st.itemQty(id)
	if owned < qty {
		return ErrNotEnough
	}
	if st.Equipment.Has(id) && owned-qty < 1 {
		return ErrEquipped // salinan terakhir yang sedang dipakai tidak boleh dijual
	}
	st.RemoveItem(id, qty)
	st.Gold += def.SellPrice * qty
	return nil
}

// BarterCost: berlian yang dibutuhkan untuk menukar qty barang.
func BarterCost(def ItemDef, qty int) int {
	return (def.BuyPrice*qty + DiamondGold - 1) / DiamondGold
}

// BarterAt menukar berlian dengan qty barang yang dijual toko `shop` (barang apa saja, berapa pun harganya).
func BarterAt(st *State, shop, id string, qty int) error {
	if !ValidShop(shop) {
		return ErrUnknownShop
	}
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
	if def.Shop != shop {
		return ErrWrongShop
	}
	need := BarterCost(def, qty)
	if st.itemQty(DiamondID) < need {
		return ErrNoDiamond
	}
	if !st.AddItem(id, qty) {
		return ErrInventoryFull
	}
	st.RemoveItem(DiamondID, need)
	return nil
}
