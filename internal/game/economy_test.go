package game

import (
	"errors"
	"testing"
)

func villager() State {
	s := NewState()
	s.Map = MapDesaAwal
	return s
}

func TestBankDepositWithdraw(t *testing.T) {
	s := villager()
	s.Gold = 100
	if err := s.BankDeposit(70); err != nil {
		t.Fatal(err)
	}
	if s.Gold != 30 || s.Bank != 70 {
		t.Fatalf("setelah menabung: emas %d bank %d", s.Gold, s.Bank)
	}
	if err := s.BankWithdraw(71); !errors.Is(err, ErrBankEmpty) {
		t.Errorf("ambil melebihi tabungan: %v", err)
	}
	if err := s.BankDeposit(31); !errors.Is(err, ErrNoGold) {
		t.Errorf("menabung melebihi emas: %v", err)
	}
	for _, bad := range []int{0, -5} {
		if err := s.BankDeposit(bad); !errors.Is(err, ErrBadAmount) {
			t.Errorf("jumlah %d harus ditolak: %v", bad, err)
		}
	}
	if err := s.BankWithdraw(20); err != nil || s.Gold != 50 || s.Bank != 50 {
		t.Fatalf("ambil: %v emas %d bank %d", err, s.Gold, s.Bank)
	}
	s.Map = MapPerbatasan
	if err := s.BankDeposit(1); !errors.Is(err, ErrBankFar) {
		t.Errorf("bank hanya di desa: %v", err)
	}
	if len(s.Ledger) != 2 || s.Ledger[0].Gold != -70 || s.Ledger[1].Gold != 20 {
		t.Errorf("riwayat bank: %+v", s.Ledger)
	}
}

func TestBankSafeOnDefeat(t *testing.T) {
	p := &Player{State: villager()}
	p.State.Gold, p.State.Bank = 100, 500
	b := battleVs("babi_hutan", 34)
	b.lose(p, &Result{})
	if p.State.Gold != 50 || p.State.Bank != 500 {
		t.Fatalf("kalah: emas %d (harus 50), bank %d (harus tetap 500)", p.State.Gold, p.State.Bank)
	}
	if last := p.State.Ledger[len(p.State.Ledger)-1]; last.Kind != LedgerBattle || last.Gold != -50 {
		t.Errorf("kehilangan emas harus tercatat: %+v", last)
	}
}

func TestStoragePutTake(t *testing.T) {
	s := villager()
	s.AddItem("koin_kuno", 5)
	if err := s.StoragePut("koin_kuno", 2); !errors.Is(err, ErrStorageFar) {
		t.Fatalf("peti hanya di rumah sendiri: %v", err)
	}
	s.House, s.Map = true, MapRumahPemain
	if err := s.StoragePut("koin_kuno", 2); err != nil {
		t.Fatal(err)
	}
	if s.itemQty("koin_kuno") != 3 || qtyIn(s.Storage, "koin_kuno") != 2 {
		t.Fatalf("simpan: ransel %d peti %d", s.itemQty("koin_kuno"), qtyIn(s.Storage, "koin_kuno"))
	}
	if err := s.StorageTake("koin_kuno", 3); !errors.Is(err, ErrNotStored) {
		t.Errorf("ambil melebihi isi peti: %v", err)
	}
	if err := s.StorageTake("koin_kuno", 2); err != nil || len(s.Storage) != 0 || s.itemQty("koin_kuno") != 5 {
		t.Fatalf("ambil: %v %+v", err, s.Storage)
	}
	// Barang yang sedang dipakai (salinan terakhir) tidak boleh disimpan.
	s.AddItem("pedang_besi", 1)
	s.Equipment.Weapon = "pedang_besi"
	if err := s.StoragePut("pedang_besi", 1); !errors.Is(err, ErrEquipped) {
		t.Errorf("perlengkapan terpakai: %v", err)
	}
	// Peti penuh.
	for i := range StorageSlots {
		s.Storage = append(s.Storage, Item{ID: "x" + string(rune('a'+i)), Qty: 1})
	}
	if err := s.StoragePut("koin_kuno", 1); !errors.Is(err, ErrStorageFull) {
		t.Errorf("peti penuh: %v", err)
	}
}

func TestBuyNeverWastesGoldOnFullStack(t *testing.T) {
	s := villager()
	s.Gold = 1000
	s.Inventory = []Item{{ID: PotionID, Qty: MaxStack - 1}}
	if err := BuyAt(&s, ShopPotion, PotionID, 5); !errors.Is(err, ErrInventoryFull) {
		t.Fatalf("tumpukan akan meluap harus ditolak: %v", err)
	}
	if s.Gold != 1000 {
		t.Fatalf("emas tidak boleh berkurang: %d", s.Gold)
	}
	if err := BuyAt(&s, ShopPotion, PotionID, 1); err != nil || s.itemQty(PotionID) != MaxStack {
		t.Fatalf("tepat penuh boleh: %v", err)
	}
	if last := s.Ledger[len(s.Ledger)-1]; last.Kind != LedgerBuy || last.Gold != -15 {
		t.Errorf("pembelian tercatat: %+v", last)
	}
}

func TestGoldCapAndValidEconomy(t *testing.T) {
	s := villager()
	s.Gold = MaxGold - 5
	s.AddItem("permata_merah", 1)
	if err := Sell(&s, "permata_merah", 1); !errors.Is(err, ErrGoldMax) || s.itemQty("permata_merah") != 1 {
		t.Fatalf("jual melewati batas emas harus ditolak tanpa kehilangan barang: %v", err)
	}
	s.gainGold(100)
	if s.Gold != MaxGold {
		t.Fatalf("hadiah dipotong di batas: %d", s.Gold)
	}
	for name, bad := range map[string]func(*State){
		"emas negatif":       func(x *State) { x.Gold = -1 },
		"emas lewat batas":   func(x *State) { x.Gold = MaxGold + 1 },
		"bank negatif":       func(x *State) { x.Bank = -1 },
		"tumpukan kembar":    func(x *State) { x.Inventory = []Item{{"roti", 1}, {"roti", 1}} },
		"peti terlalu besar": func(x *State) { x.Storage = make([]Item, StorageSlots+1) },
		"qty lewat batas":    func(x *State) { x.Storage = []Item{{"roti", MaxStack + 1}} },
	} {
		c := villager()
		bad(&c)
		if c.ValidEconomy() == nil {
			t.Errorf("%s harus ditolak", name)
		}
	}
	if err := villager().ValidEconomy(); err != nil {
		t.Errorf("state baru sah: %v", err)
	}
}

func TestTradeRules(t *testing.T) {
	seller, buyer := villager(), villager()
	seller.AddItem("permata_merah", 2)
	if err := seller.EscrowTrade("permata_merah", 3, 100, "Budi"); !errors.Is(err, ErrNotEnough) {
		t.Fatalf("titip melebihi milik: %v", err)
	}
	if err := seller.EscrowTrade("permata_merah", 1, -1, "Budi"); !errors.Is(err, ErrBadPrice) {
		t.Fatalf("harga negatif: %v", err)
	}
	seller.AddItem(RadarID, 1)
	if err := seller.EscrowTrade(RadarID, 1, 0, "Budi"); !errors.Is(err, ErrNotTradable) {
		t.Fatalf("barang khusus tidak bisa dijual: %v", err)
	}
	if err := seller.EscrowTrade("permata_merah", 2, 150, "Budi"); err != nil || seller.itemQty("permata_merah") != 0 {
		t.Fatalf("titip: %v", err)
	}
	tr := Trade{FromName: "Ani", ToName: "Budi", Item: "permata_merah", Qty: 2, Price: 150}
	buyer.Gold = 100
	if err := buyer.TradeBuy(tr); !errors.Is(err, ErrNoGold) || buyer.Gold != 100 {
		t.Fatalf("emas pembeli kurang: %v", err)
	}
	buyer.Gold = 200
	if err := buyer.TradeBuy(tr); err != nil || buyer.Gold != 50 || buyer.itemQty("permata_merah") != 2 {
		t.Fatalf("beli: %v emas %d", err, buyer.Gold)
	}
	seller.Gold = 0
	if err := seller.TradeSold(tr); err != nil || seller.Gold != 150 {
		t.Fatalf("penjual dibayar: %v %d", err, seller.Gold)
	}
}
