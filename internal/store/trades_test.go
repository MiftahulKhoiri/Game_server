package store

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Keamanan perdagangan antarpemain (audit v0.77.0): status bertarung kedua pemain, rollback, dan
// tidak ada barang/emas yang terduplikasi atau hilang.

func give(t *testing.T, st *Store, id string, gold int, items ...game.Item) {
	t.Helper()
	if _, err := st.Update(context.Background(), id, func(s *Session) error {
		s.Player.State.Gold = gold
		s.Player.State.Inventory = append([]game.Item{}, items...)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}

func setBattle(t *testing.T, st *Store, id string, on bool) {
	t.Helper()
	if _, err := st.Update(context.Background(), id, func(s *Session) error {
		s.Battle = nil
		if on {
			s.Battle = &game.Battle{EnemyID: "tikus_sawah", EnemyHP: 10, EnemyMaxHP: 10, Round: 1}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}

func qtyOf(p game.Player, item string) int {
	n := 0
	for _, it := range p.State.Inventory {
		if it.ID == item {
			n += it.Qty
		}
	}
	return n
}

func reload(t *testing.T, st *Store, id string) game.Player {
	t.Helper()
	p, err := st.PlayerByID(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

// tradePair: penjual punya 5 ramuan, pembeli punya 1000 emas.
func tradePair(t *testing.T) (*Store, game.Player, game.Player) {
	st := newStore(t)
	seller, buyer := newPlayer(t, st, "Penjual"), newPlayer(t, st, "Pembeli")
	give(t, st, seller.ID, 0, game.Item{ID: game.PotionID, Qty: 5})
	give(t, st, buyer.ID, 1000)
	return st, reload(t, st, seller.ID), reload(t, st, buyer.ID)
}

func pendingID(t *testing.T, st *Store, id string) int64 {
	t.Helper()
	list, err := st.Trades(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	for _, tr := range list {
		if tr.Status == game.TradePending {
			return tr.ID
		}
	}
	t.Fatal("tidak ada tawaran pending")
	return 0
}

func TestTradeBattleChecks(t *testing.T) {
	ctx := context.Background()
	cases := []struct {
		name                      string
		sellerFight, buyerFight   bool
		createErr, acceptErr      error
		cancelBySeller, declineOK bool
	}{
		{"keduanya tidak bertarung", false, false, nil, nil, true, true},
		{"penjual bertarung", true, false, ErrTradeBattle, ErrTradeBattle, false, false},
		{"pembeli bertarung", false, true, ErrTradeBattle, ErrTradeBattle, true, true},
		{"keduanya bertarung", true, true, ErrTradeBattle, ErrTradeBattle, false, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			// Membuat tawaran.
			st, seller, buyer := tradePair(t)
			setBattle(t, st, seller.ID, c.sellerFight)
			setBattle(t, st, buyer.ID, c.buyerFight)
			if _, err := st.CreateTrade(ctx, seller.ID, buyer.Name, game.PotionID, 2, 100); !errors.Is(err, c.createErr) {
				t.Fatalf("buat tawaran: %v, mau %v", err, c.createErr)
			}
			if c.createErr != nil && qtyOf(reload(t, st, seller.ID), game.PotionID) != 5 {
				t.Fatal("tawaran ditolak tetapi barang penjual berkurang")
			}

			// Menerima / membatalkan / menolak tawaran yang dibuat sebelum pertarungan dimulai.
			for _, op := range []string{"terima", "batal", "tolak"} {
				st, seller, buyer := tradePair(t)
				if _, err := st.CreateTrade(ctx, seller.ID, buyer.Name, game.PotionID, 2, 100); err != nil {
					t.Fatal(err)
				}
				id := pendingID(t, st, seller.ID)
				setBattle(t, st, seller.ID, c.sellerFight)
				setBattle(t, st, buyer.ID, c.buyerFight)
				var err error
				want := c.acceptErr
				switch op {
				case "terima":
					_, err = st.AcceptTrade(ctx, buyer.ID, id)
				case "batal":
					_, err = st.CancelTrade(ctx, seller.ID, id)
					if !c.cancelBySeller {
						want = ErrTradeBattle
					} else {
						want = nil
					}
				case "tolak":
					_, err = st.CancelTrade(ctx, buyer.ID, id)
					if !c.declineOK {
						want = ErrTradeBattle
					} else {
						want = nil
					}
				}
				if !errors.Is(err, want) {
					t.Fatalf("%s: %v, mau %v", op, err, want)
				}
				s, b := reload(t, st, seller.ID), reload(t, st, buyer.ID)
				if err != nil && (qtyOf(s, game.PotionID) != 3 || qtyOf(b, game.PotionID) != 0 || b.State.Gold != 1000 || s.State.Gold != 0) {
					t.Fatalf("%s ditolak tetapi data berubah: penjual %+v pembeli %+v", op, s.State, b.State)
				}
			}
		})
	}
}

func TestTradeNormalFlowConservesItemsAndGold(t *testing.T) {
	ctx := context.Background()
	st, seller, buyer := tradePair(t)
	if _, err := st.CreateTrade(ctx, seller.ID, buyer.Name, game.PotionID, 2, 150); err != nil {
		t.Fatal(err)
	}
	// Membuat tawaran tidak menyentuh data pembeli (versinya tetap, kliennya tidak mendapat 409).
	if b := reload(t, st, buyer.ID); b.Version != buyer.Version {
		t.Errorf("versi pembeli berubah saat tawaran dibuat: %d -> %d", buyer.Version, b.Version)
	}
	id := pendingID(t, st, buyer.ID)
	if _, err := st.AcceptTrade(ctx, buyer.ID, id); err != nil {
		t.Fatal(err)
	}
	s, b := reload(t, st, seller.ID), reload(t, st, buyer.ID)
	if qtyOf(s, game.PotionID) != 3 || qtyOf(b, game.PotionID) != 2 || s.State.Gold != 150 || b.State.Gold != 850 {
		t.Fatalf("hasil dagang salah: penjual %d ramuan %d emas, pembeli %d ramuan %d emas",
			qtyOf(s, game.PotionID), s.State.Gold, qtyOf(b, game.PotionID), b.State.Gold)
	}
	// Tidak bisa diselesaikan dua kali, dibatalkan setelah selesai, atau diterima oleh penjualnya sendiri.
	if _, err := st.AcceptTrade(ctx, buyer.ID, id); !errors.Is(err, ErrTradeNotFound) {
		t.Errorf("terima dua kali: %v", err)
	}
	if _, err := st.CancelTrade(ctx, seller.ID, id); !errors.Is(err, ErrTradeNotFound) {
		t.Errorf("batal setelah selesai: %v", err)
	}
}

func TestTradeOwnershipAndValidation(t *testing.T) {
	ctx := context.Background()
	st, seller, buyer := tradePair(t)
	other := newPlayer(t, st, "Orang")
	cases := []struct {
		name  string
		qty   int
		price int
		item  string
		want  error
	}{
		{"melebihi milik", 6, 10, game.PotionID, game.ErrNotEnough},
		{"jumlah nol", 0, 10, game.PotionID, game.ErrBadQty},
		{"jumlah negatif", -3, 10, game.PotionID, game.ErrBadQty},
		{"harga negatif", 1, -1, game.PotionID, game.ErrBadPrice},
		{"barang tidak dikenal", 1, 10, "pedang_dewa", game.ErrUnknownItem},
		{"barang yang tidak dimiliki", 1, 10, "roti", game.ErrNotEnough},
	}
	for _, c := range cases {
		if _, err := st.CreateTrade(ctx, seller.ID, buyer.Name, c.item, c.qty, c.price); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, mau %v", c.name, err, c.want)
		}
	}
	if _, err := st.CreateTrade(ctx, seller.ID, seller.Name, game.PotionID, 1, 1); !errors.Is(err, ErrTradeSelf) {
		t.Errorf("dagang dengan diri sendiri: %v", err)
	}
	if qtyOf(reload(t, st, seller.ID), game.PotionID) != 5 {
		t.Fatal("tawaran yang ditolak mengurangi barang")
	}
	if _, err := st.CreateTrade(ctx, seller.ID, buyer.Name, game.PotionID, 2, 100); err != nil {
		t.Fatal(err)
	}
	id := pendingID(t, st, seller.ID)
	// Pemain ketiga tidak bisa membeli atau membatalkan tawaran orang lain (IDOR).
	if _, err := st.AcceptTrade(ctx, other.ID, id); !errors.Is(err, ErrTradeNotFound) {
		t.Errorf("orang lain menerima: %v", err)
	}
	if _, err := st.CancelTrade(ctx, other.ID, id); !errors.Is(err, ErrTradeNotFound) {
		t.Errorf("orang lain membatalkan: %v", err)
	}
	// Penjual tidak bisa "membeli" tawarannya sendiri.
	if _, err := st.AcceptTrade(ctx, seller.ID, id); !errors.Is(err, ErrTradeNotFound) {
		t.Errorf("penjual menerima sendiri: %v", err)
	}
}

// Gagal di tengah proses (emas pembeli kurang / ransel penuh): seluruh transaksi dibatalkan.
func TestTradeFailureRollsBack(t *testing.T) {
	ctx := context.Background()
	st, seller, buyer := tradePair(t)
	if _, err := st.CreateTrade(ctx, seller.ID, buyer.Name, game.PotionID, 2, 5000); err != nil {
		t.Fatal(err)
	}
	id := pendingID(t, st, seller.ID)
	if _, err := st.AcceptTrade(ctx, buyer.ID, id); !errors.Is(err, game.ErrNoGold) {
		t.Fatalf("emas kurang: %v", err)
	}
	// Tumpukan ramuan pembeli sudah penuh: barang tidak muat.
	give(t, st, buyer.ID, 9000, game.Item{ID: game.PotionID, Qty: game.MaxStack})
	before := reload(t, st, buyer.ID)
	if _, err := st.AcceptTrade(ctx, buyer.ID, id); !errors.Is(err, game.ErrInventoryFull) {
		t.Fatalf("ransel penuh: %v", err)
	}
	s, b := reload(t, st, seller.ID), reload(t, st, buyer.ID)
	if s.State.Gold != 0 || b.State.Gold != 9000 || b.Version != before.Version || qtyOf(s, game.PotionID) != 3 || qtyOf(b, game.PotionID) != game.MaxStack {
		t.Fatalf("tidak di-rollback: penjual %+v pembeli emas %d", s.State, b.State.Gold)
	}
	if pendingID(t, st, seller.ID) != id {
		t.Fatal("tawaran harus tetap pending setelah gagal")
	}
}

// Banyak permintaan terima/batal bersamaan untuk tawaran yang sama: tepat satu berhasil, barang dan emas utuh.
func TestTradeConcurrentFinishNoDuplication(t *testing.T) {
	ctx := context.Background()
	st, seller, buyer := tradePair(t)
	if _, err := st.CreateTrade(ctx, seller.ID, buyer.Name, game.PotionID, 2, 100); err != nil {
		t.Fatal(err)
	}
	id := pendingID(t, st, seller.ID)
	var wg sync.WaitGroup
	var mu sync.Mutex
	ok := 0
	for i := range 16 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var err error
			switch i % 3 {
			case 0:
				_, err = st.AcceptTrade(ctx, buyer.ID, id)
			case 1:
				_, err = st.CancelTrade(ctx, seller.ID, id)
			default:
				_, err = st.CancelTrade(ctx, buyer.ID, id)
			}
			if err == nil {
				mu.Lock()
				ok++
				mu.Unlock()
			} else if !errors.Is(err, ErrTradeNotFound) {
				t.Errorf("kesalahan tak terduga: %v", err)
			}
		}()
	}
	wg.Wait()
	if ok != 1 {
		t.Fatalf("harus tepat satu yang berhasil, dapat %d", ok)
	}
	s, b := reload(t, st, seller.ID), reload(t, st, buyer.ID)
	potions := qtyOf(s, game.PotionID) + qtyOf(b, game.PotionID)
	gold := s.State.Gold + b.State.Gold
	if potions != 5 || gold != 1000 {
		t.Fatalf("barang/emas tidak kekal: ramuan %d (mau 5), emas %d (mau 1000)", potions, gold)
	}
}
