package api

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// setState mengubah state pemain langsung di database (persiapan tes).
func setState(t *testing.T, st *store.Store, id string, fn func(*game.State)) {
	t.Helper()
	if _, err := st.Update(context.Background(), id, func(s *store.Session) error {
		fn(&s.Player.State)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}

func playerOf(t *testing.T, data []byte) game.Player {
	t.Helper()
	var p game.Player
	if err := json.Unmarshal(data, &p); err != nil {
		t.Fatalf("respons pemain: %v %s", err, data)
	}
	return p
}

func TestBankEndpoints(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Penabung")
	setState(t, st, cr.Player.ID, func(s *game.State) { s.Gold = 300 })
	resp, data := do(t, "POST", ts.URL+"/v1/bank/deposit", cr.Token, map[string]int{"amount": 200})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || p.State.Gold != 100 || p.State.Bank != 200 {
		t.Fatalf("menabung: %d %s", resp.StatusCode, data)
	}
	if resp, data := do(t, "POST", ts.URL+"/v1/bank/withdraw", cr.Token, map[string]int{"amount": 500}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("ambil melebihi tabungan harus 422: %d %s", resp.StatusCode, data)
	}
	// Klien tidak bisa menulis emas/bank lewat simpan posisi.
	body := map[string]any{"version": 0, "state": map[string]any{"gold": 999999, "bank": 999999, "map": "desa_awal", "x": 5, "y": 5}}
	do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, body)
	_, data = do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	if p := playerOf(t, data); p.State.Gold != 100 || p.State.Bank != 200 {
		t.Fatalf("simpan dari klien tidak boleh mengubah emas/bank: %+v", p.State)
	}
}

func TestStorageEndpoints(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Penyimpan")
	if resp, _ := do(t, "POST", ts.URL+"/v1/storage/put", cr.Token, map[string]any{"item": game.PotionID, "qty": 1}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("tanpa rumah harus 422: %d", resp.StatusCode)
	}
	setState(t, st, cr.Player.ID, func(s *game.State) { s.House, s.Map = true, game.MapRumahPemain })
	resp, data := do(t, "POST", ts.URL+"/v1/storage/put", cr.Token, map[string]any{"item": game.PotionID, "qty": 2})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || len(p.State.Storage) != 1 || len(p.State.Inventory) != 0 {
		t.Fatalf("simpan: %d %s", resp.StatusCode, data)
	}
	resp, data = do(t, "POST", ts.URL+"/v1/storage/take", cr.Token, map[string]any{"item": game.PotionID, "qty": 2})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || len(p.State.Storage) != 0 {
		t.Fatalf("ambil: %d %s", resp.StatusCode, data)
	}
}

func TestTradeFlow(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	ani := register(t, ts, "Ani")
	budi := register(t, ts, "Budi")
	setState(t, st, ani.Player.ID, func(s *game.State) { s.AddItem("permata_merah", 3) })
	setState(t, st, budi.Player.ID, func(s *game.State) { s.Gold = 500 })

	offer := map[string]any{"to": "budi", "item": "permata_merah", "qty": 2, "price": 120}
	resp, data := do(t, "POST", ts.URL+"/v1/trades", ani.Token, offer)
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("buat tawaran: %d %s", resp.StatusCode, data)
	}
	for _, it := range playerOf(t, data).State.Inventory {
		if it.ID == "permata_merah" && it.Qty != 1 {
			t.Fatalf("barang harus dititipkan: %+v", it)
		}
	}
	for name, bad := range map[string]map[string]any{
		"diri sendiri":   {"to": "Ani", "item": "permata_merah", "qty": 1, "price": 1},
		"barang kurang":  {"to": "Budi", "item": "permata_merah", "qty": 5, "price": 1},
		"harga negatif":  {"to": "Budi", "item": "permata_merah", "qty": 1, "price": -1},
		"pemain tak ada": {"to": "Siapa", "item": "permata_merah", "qty": 1, "price": 1},
	} {
		if resp, d := do(t, "POST", ts.URL+"/v1/trades", ani.Token, bad); resp.StatusCode < 400 {
			t.Errorf("%s harus ditolak: %d %s", name, resp.StatusCode, d)
		}
	}

	_, data = do(t, "GET", ts.URL+"/v1/trades", budi.Token, nil)
	var list struct {
		Trades []game.Trade `json:"trades"`
	}
	_ = json.Unmarshal(data, &list)
	if len(list.Trades) != 1 || list.Trades[0].FromName != "Ani" || list.Trades[0].Status != game.TradePending {
		t.Fatalf("daftar tawaran Budi: %s", data)
	}
	id := list.Trades[0].ID
	if resp, _ := do(t, "POST", ts.URL+"/v1/trades/accept", ani.Token, map[string]int64{"id": id}); resp.StatusCode != http.StatusNotFound {
		t.Fatalf("penjual tidak bisa membeli sendiri: %d", resp.StatusCode)
	}

	// Dua permintaan terima bersamaan: hanya satu yang berhasil (tidak ada duplikasi).
	var wg sync.WaitGroup
	codes := make([]int, 6)
	for i := range codes {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, _ := do(t, "POST", ts.URL+"/v1/trades/accept", budi.Token, map[string]int64{"id": id})
			codes[i] = r.StatusCode
		}()
	}
	wg.Wait()
	okCount := 0
	for _, c := range codes {
		if c == http.StatusOK {
			okCount++
		}
	}
	if okCount != 1 {
		t.Fatalf("terima bersamaan harus berhasil tepat sekali: %v", codes)
	}
	_, data = do(t, "GET", ts.URL+"/v1/players/me", budi.Token, nil)
	b := playerOf(t, data)
	_, data = do(t, "GET", ts.URL+"/v1/players/me", ani.Token, nil)
	a := playerOf(t, data)
	gems := func(p game.Player) int {
		for _, it := range p.State.Inventory {
			if it.ID == "permata_merah" {
				return it.Qty
			}
		}
		return 0
	}
	if b.State.Gold != 380 || gems(b) != 2 || gems(a) != 1 || a.State.Gold != cr0Gold(ani)+120 {
		t.Fatalf("hasil dagang: Budi emas %d permata %d, Ani emas %d permata %d", b.State.Gold, gems(b), a.State.Gold, gems(a))
	}

	// Tolak: barang kembali ke penjual.
	resp, _ = do(t, "POST", ts.URL+"/v1/trades", ani.Token, map[string]any{"to": "Budi", "item": "permata_merah", "qty": 1, "price": 10})
	if resp.StatusCode != http.StatusCreated {
		t.Fatal("tawaran kedua")
	}
	_, data = do(t, "GET", ts.URL+"/v1/trades", budi.Token, nil)
	_ = json.Unmarshal(data, &list)
	resp, _ = do(t, "POST", ts.URL+"/v1/trades/cancel", budi.Token, map[string]int64{"id": list.Trades[0].ID})
	_, data = do(t, "GET", ts.URL+"/v1/players/me", ani.Token, nil)
	if resp.StatusCode != http.StatusOK || gems(playerOf(t, data)) != 1 {
		t.Fatalf("tolak harus mengembalikan barang: %d %s", resp.StatusCode, data)
	}
}

func cr0Gold(c createResponse) int { return c.Player.State.Gold }

// Banyak penjualan bersamaan atas barang yang sama tidak boleh menggandakan emas.
func TestConcurrentSellNoDuplicate(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Pedagang")
	setState(t, st, cr.Player.ID, func(s *game.State) { s.Gold = 0; s.AddItem("permata_merah", 3) })
	var wg sync.WaitGroup
	for range 12 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			do(t, "POST", ts.URL+"/v1/shop/sell", cr.Token, map[string]any{"item": "permata_merah", "qty": 1})
		}()
	}
	wg.Wait()
	_, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	p := playerOf(t, data)
	def, _ := game.ItemByID("permata_merah")
	if p.State.Gold != 3*def.SellPrice {
		t.Fatalf("emas harus %d (3 permata), dapat %d", 3*def.SellPrice, p.State.Gold)
	}
}

func TestWorldEventsAndSecret(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Penjelajah")
	resp, data := do(t, "GET", ts.URL+"/v1/world/events", cr.Token, nil)
	var ev struct {
		Hour    float64           `json:"hour"`
		Night   bool              `json:"night"`
		Events  []game.WorldEvent `json:"events"`
		Secrets []map[string]any  `json:"secrets"`
		Zones   []game.Zone       `json:"zones"`
	}
	_ = json.Unmarshal(data, &ev)
	if resp.StatusCode != http.StatusOK || ev.Night || len(ev.Events) != 2 || len(ev.Secrets) != len(game.Secrets) || len(ev.Zones) == 0 {
		t.Fatalf("kejadian dunia: %d %s", resp.StatusCode, data)
	}
	sec := game.Secrets[0]
	if resp, _ := do(t, "POST", ts.URL+"/v1/world/secret", cr.Token, map[string]string{"id": sec.ID}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("jauh dari rahasia harus 422: %d", resp.StatusCode)
	}
	setState(t, st, cr.Player.ID, func(s *game.State) { s.Map, s.X, s.Y = sec.Map, sec.X, sec.Y })
	resp, data = do(t, "POST", ts.URL+"/v1/world/secret", cr.Token, map[string]string{"id": sec.ID})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || len(p.State.Secrets) != 1 {
		t.Fatalf("menemukan rahasia: %d %s", resp.StatusCode, data)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/world/raid/claim", cr.Token, nil); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("tanpa serbuan harus 422: %d", resp.StatusCode)
	}
	// Penjelajahan dicatat server saat posisi disimpan.
	_, data = do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	me := playerOf(t, data)
	body := map[string]any{"version": me.Version, "state": map[string]any{"map": "perbatasan", "x": 22, "y": 2, "level": 1, "hp": 30, "max_hp": 30}}
	resp, data = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, body)
	if resp.StatusCode != http.StatusOK || len(playerOf(t, data).State.Visited) == 0 {
		t.Fatalf("kunjungan tercatat: %d %s", resp.StatusCode, data)
	}
}
