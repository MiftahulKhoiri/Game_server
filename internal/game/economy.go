package game

import (
	"errors"
	"fmt"
	"time"
)

// Ekonomi (roadmap no. 171-185): bank, peti simpan di rumah, perdagangan antarpemain, dan riwayat
// transaksi. Semua dihitung server; klien hanya mengirim permintaan.

const (
	MaxGold       = 99_999_999 // batas emas dibawa (mencegah luapan angka)
	MaxBank       = 99_999_999 // batas tabungan bank
	StorageSlots  = 30         // jumlah tumpukan di peti simpan rumah
	LedgerKeep    = 30         // jumlah catatan transaksi terakhir yang disimpan
	MaxTradePrice = 1_000_000  // harga tawaran dagang tertinggi
	MaxOpenTrades = 10         // tawaran keluar yang belum selesai per pemain
	BankKeeper    = "pak_saleh"

	// Bunga bank (no. 181, v0.79.0): bunga sederhana per hari nyata, hanya untuk BankInterestCap emas pertama, dan
	// paling banyak BankInterestMaxDays hari yang tertunda dihitung. Paling banyak 200 emas sehari, jadi tidak
	// mengalahkan hadiah bertarung; emas yang baru disimpan baru berbunga mulai hari berikutnya.
	BankInterestPermil  = 10     // 1% sehari
	BankInterestCap     = 20_000 // emas tabungan yang berbunga
	BankInterestMaxDays = 7      // hari tertunda yang dihitung (tidak ditabung tanpa batas)
	realDaySeconds      = 86_400
)

// Jenis catatan transaksi.
const (
	LedgerBuy      = "beli"
	LedgerSell     = "jual"
	LedgerBarter   = "tukar"
	LedgerBattle   = "pertarungan"
	LedgerQuest    = "misi"
	LedgerBank     = "bank"
	LedgerTrade    = "dagang"
	LedgerHouse    = "rumah"
	LedgerStorage  = "peti"
	LedgerPurchase = "bayar" // pembayaran lain: pendamping, prajurit, latihan
)

// LedgerEntry adalah satu catatan transaksi. Gold = perubahan emas dibawa (+ masuk, - keluar).
type LedgerEntry struct {
	At   int64  `json:"at"` // detik Unix
	Kind string `json:"kind"`
	Note string `json:"note"`
	Gold int    `json:"gold"`
}

// Now adalah jam yang dipakai catatan transaksi (bisa diganti dalam tes).
var Now = func() int64 { return time.Now().Unix() }

// Kesalahan ekonomi.
var (
	ErrBankFar     = errors.New("bank ada di Desa Awal (Pak Saleh)")
	ErrBankEmpty   = errors.New("tabungan tidak cukup")
	ErrBankFull    = errors.New("tabungan sudah penuh")
	ErrGoldMax     = errors.New("emas yang dibawa sudah maksimal")
	ErrBadAmount   = errors.New("jumlah emas tidak sah")
	ErrStorageFar  = errors.New("peti simpan ada di dalam rumahmu")
	ErrStorageFull = errors.New("peti simpan penuh")
	ErrNotStored   = errors.New("barang itu tidak ada di peti")
	ErrBadPrice    = fmt.Errorf("harga harus 0..%d", MaxTradePrice)
	ErrNotTradable = errors.New("barang ini tidak bisa diperdagangkan")
)

// record menambah satu catatan transaksi (hanya yang terakhir LedgerKeep disimpan).
func (s *State) record(kind, note string, gold int) {
	s.Ledger = append(s.Ledger, LedgerEntry{At: Now(), Kind: kind, Note: note, Gold: gold})
	if n := len(s.Ledger); n > LedgerKeep {
		s.Ledger = append([]LedgerEntry(nil), s.Ledger[n-LedgerKeep:]...)
	}
}

func itemName(id string) string {
	if def, ok := ItemByID(id); ok {
		return def.Name
	}
	return id
}

// canAdd: apakah qty barang muat di ransel tanpa terpotong batas tumpukan (mencegah emas hilang
// untuk barang yang tidak masuk).
func (s State) canAdd(id string, qty int) bool {
	return canAddTo(s.Inventory, MaxInventory, id, qty)
}

func canAddTo(list []Item, slots int, id string, qty int) bool {
	for _, it := range list {
		if it.ID == id {
			return it.Qty+qty <= MaxStack
		}
	}
	return len(list) < slots && qty <= MaxStack
}

// addGold menambah emas dibawa sampai MaxGold. false bila melewati batas (tidak ada yang diubah).
func (s *State) addGold(n int) bool {
	if n < 0 || s.Gold > MaxGold-n {
		return false
	}
	s.Gold += n
	return true
}

// gainGold: pemasukan dari hadiah (pertarungan, peti, misi, pencapaian), dipotong di MaxGold.
func (s *State) gainGold(n int) {
	if n > 0 {
		s.Gold = min(MaxGold, s.Gold+n)
	}
}

// --- bank (no. 181) ---

// today: nomor hari nyata (UTC) dari jam server.
func today() int64 { return Now() / realDaySeconds }

// BankInterestDue: bunga yang akan dikreditkan bila bank disentuh sekarang (untuk ditampilkan klien).
func (s State) BankInterestDue() int {
	if s.BankDay <= 0 || s.Bank <= 0 {
		return 0
	}
	days := min(int64(BankInterestMaxDays), max(0, today()-s.BankDay))
	return int(days) * min(s.Bank, BankInterestCap) * BankInterestPermil / 1000
}

// AccrueInterest mengkreditkan bunga hari-hari yang tertunda ke tabungan, lalu mencatat hari ini. Dipanggil
// sebelum setiap aksi bank, jadi emas yang baru disimpan tidak ikut berbunga untuk hari-hari yang lalu.
// Mengembalikan bunga yang dikreditkan.
func (s *State) AccrueInterest() int {
	now := today()
	gain := min(s.BankInterestDue(), MaxBank-s.Bank)
	if gain > 0 {
		s.Bank += gain
		s.record(LedgerBank, fmt.Sprintf("Bunga tabungan +%d emas (masuk ke bank)", gain), 0)
	}
	s.BankDay = now
	return gain
}

// BankClaim mengkreditkan bunga tertunda (saat pemain membuka layar bank).
func (s *State) BankClaim() error {
	if !InVillage(s.Map) {
		return ErrBankFar
	}
	s.AccrueInterest()
	return nil
}

// BankDeposit menyimpan emas di bank. Emas di bank aman: tidak hilang saat kalah bertarung.
func (s *State) BankDeposit(amount int) error {
	switch {
	case amount < 1:
		return ErrBadAmount
	case !InVillage(s.Map):
		return ErrBankFar
	case s.Gold < amount:
		return ErrNoGold
	case s.Bank > MaxBank-amount:
		return ErrBankFull
	}
	s.AccrueInterest()
	if s.Bank > MaxBank-amount {
		return ErrBankFull
	}
	s.Gold -= amount
	s.Bank += amount
	s.record(LedgerBank, fmt.Sprintf("Menabung %d emas", amount), -amount)
	return nil
}

// BankWithdraw mengambil emas dari bank.
func (s *State) BankWithdraw(amount int) error {
	switch {
	case amount < 1:
		return ErrBadAmount
	case !InVillage(s.Map):
		return ErrBankFar
	}
	s.AccrueInterest() // bunga masuk dulu (bila aksi gagal, perubahan tidak disimpan)
	switch {
	case s.Bank < amount:
		return ErrBankEmpty
	case s.Gold > MaxGold-amount:
		return ErrGoldMax
	}
	s.Bank -= amount
	s.Gold += amount
	s.record(LedgerBank, fmt.Sprintf("Mengambil %d emas", amount), amount)
	return nil
}

// --- peti simpan di rumah (no. 180) ---

func (s State) atStorage() bool { return s.House && s.Map == MapRumahPemain }

// StoragePut memindah qty barang dari ransel ke peti simpan.
func (s *State) StoragePut(id string, qty int) error {
	if _, ok := ItemByID(id); !ok {
		return ErrUnknownItem
	}
	switch {
	case qty < 1 || qty > MaxStack:
		return ErrBadQty
	case !s.atStorage():
		return ErrStorageFar
	case s.itemQty(id) < qty:
		return ErrNotEnough
	case s.Equipment.Has(id) && s.itemQty(id)-qty < 1:
		return ErrEquipped
	case !canAddTo(s.Storage, StorageSlots, id, qty):
		return ErrStorageFull
	}
	s.RemoveItem(id, qty)
	s.Storage = addTo(s.Storage, id, qty)
	s.record(LedgerStorage, fmt.Sprintf("Simpan %s x%d", itemName(id), qty), 0)
	return nil
}

// StorageTake memindah qty barang dari peti simpan ke ransel.
func (s *State) StorageTake(id string, qty int) error {
	switch {
	case qty < 1 || qty > MaxStack:
		return ErrBadQty
	case !s.atStorage():
		return ErrStorageFar
	case qtyIn(s.Storage, id) < qty:
		return ErrNotStored
	case !s.canAdd(id, qty):
		return ErrInventoryFull
	}
	s.Storage = removeFrom(s.Storage, id, qty)
	s.AddItem(id, qty)
	s.record(LedgerStorage, fmt.Sprintf("Ambil %s x%d", itemName(id), qty), 0)
	return nil
}

func qtyIn(list []Item, id string) int {
	for _, it := range list {
		if it.ID == id {
			return it.Qty
		}
	}
	return 0
}

func addTo(list []Item, id string, qty int) []Item {
	for i := range list {
		if list[i].ID == id {
			list[i].Qty += qty
			return list
		}
	}
	return append(list, Item{ID: id, Qty: qty})
}

func removeFrom(list []Item, id string, qty int) []Item {
	for i := range list {
		if list[i].ID == id {
			list[i].Qty -= qty
			if list[i].Qty <= 0 {
				return append(list[:i], list[i+1:]...)
			}
			return list
		}
	}
	return list
}

// --- perdagangan antarpemain (no. 176): barang dititipkan ke server sampai tawaran selesai ---

// Trade adalah satu tawaran dagang: penjual menawarkan Qty barang Item kepada pembeli seharga Price emas.
type Trade struct {
	ID       int64  `json:"id"`
	FromID   string `json:"-"`
	ToID     string `json:"-"`
	FromName string `json:"from"`
	ToName   string `json:"to"`
	Item     string `json:"item"`
	Qty      int    `json:"qty"`
	Price    int    `json:"price"`
	Status   string `json:"status"` // pending, done, cancelled, declined
	Created  int64  `json:"created"`
}

// Status tawaran.
const (
	TradePending   = "pending"
	TradeDone      = "done"
	TradeCancelled = "cancelled"
	TradeDeclined  = "declined"
)

// EscrowTrade memeriksa tawaran dan menitipkan barangnya (dikeluarkan dari ransel penjual).
func (s *State) EscrowTrade(item string, qty, price int, to string) error {
	def, ok := ItemByID(item)
	if !ok {
		return ErrUnknownItem
	}
	switch {
	case def.Kind == KindSpecial:
		return ErrNotTradable
	case qty < 1 || qty > MaxStack:
		return ErrBadQty
	case price < 0 || price > MaxTradePrice:
		return ErrBadPrice
	case s.itemQty(item) < qty:
		return ErrNotEnough
	case s.Equipment.Has(item) && s.itemQty(item)-qty < 1:
		return ErrEquipped
	}
	s.RemoveItem(item, qty)
	s.record(LedgerTrade, fmt.Sprintf("Menawarkan %s x%d ke %s (%d emas)", def.Name, qty, to, price), 0)
	return nil
}

// TradeBuy: pembeli membayar dan menerima barang tawaran t.
func (s *State) TradeBuy(t Trade) error {
	switch {
	case s.Gold < t.Price:
		return ErrNoGold
	case !s.canAdd(t.Item, t.Qty):
		return ErrInventoryFull
	}
	s.Gold -= t.Price
	s.AddItem(t.Item, t.Qty)
	s.record(LedgerTrade, fmt.Sprintf("Membeli %s x%d dari %s", itemName(t.Item), t.Qty, t.FromName), -t.Price)
	return nil
}

// TradeSold: penjual menerima bayaran tawaran t.
func (s *State) TradeSold(t Trade) error {
	if !s.addGold(t.Price) {
		return ErrGoldMax
	}
	s.record(LedgerTrade, fmt.Sprintf("Terjual %s x%d ke %s", itemName(t.Item), t.Qty, t.ToName), t.Price)
	return nil
}

// TradeReturn: barang titipan kembali ke penjual (dibatalkan/ditolak).
func (s *State) TradeReturn(t Trade) error {
	if !s.canAdd(t.Item, t.Qty) {
		return ErrInventoryFull
	}
	s.AddItem(t.Item, t.Qty)
	s.record(LedgerTrade, fmt.Sprintf("%s x%d kembali (tawaran ke %s selesai)", itemName(t.Item), t.Qty, t.ToName), 0)
	return nil
}

// ValidEconomy memeriksa batas emas, bank, peti, dan riwayat. Dipanggil server setiap kali state
// disimpan, jadi kesalahan aturan mana pun tidak bisa menghasilkan emas/barang yang mustahil.
func (s State) ValidEconomy() error {
	switch {
	case s.Gold < 0 || s.Gold > MaxGold:
		return fmt.Errorf("emas harus 0..%d", MaxGold)
	case s.Bank < 0 || s.Bank > MaxBank:
		return fmt.Errorf("tabungan harus 0..%d", MaxBank)
	case s.BankDay < 0 || s.BankDay > today()+1:
		return errors.New("hari bunga bank tidak sah")
	case len(s.Storage) > StorageSlots:
		return fmt.Errorf("peti simpan maksimal %d tumpukan", StorageSlots)
	case len(s.Ledger) > LedgerKeep:
		return errors.New("riwayat transaksi terlalu panjang")
	case len(s.Inventory) > MaxInventory:
		return fmt.Errorf("inventori maksimal %d tumpukan", MaxInventory)
	}
	for _, list := range [][]Item{s.Inventory, s.Storage} {
		seen := map[string]bool{}
		for _, it := range list {
			if it.ID == "" || len(it.ID) > 64 || it.Qty < 1 || it.Qty > MaxStack || seen[it.ID] {
				return errors.New("tumpukan barang tidak sah")
			}
			seen[it.ID] = true
		}
	}
	return nil
}
