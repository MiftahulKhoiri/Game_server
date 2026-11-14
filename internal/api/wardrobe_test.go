package api

import (
	"encoding/json"
	"net/http"
	"slices"
	"sync"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

func TestWardrobeCatalog(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Penata")
	resp, data := do(t, "GET", ts.URL+"/v1/wardrobe", cr.Token, nil)
	var cat struct {
		Cosmetics []game.Cosmetic  `json:"cosmetics"`
		Options   map[string][]any `json:"options"`
		Gear      []game.ItemDef   `json:"gear"`
		Hair      []string         `json:"hair_colors"`
		Tiers     []string         `json:"tiers"`
	}
	if err := json.Unmarshal(data, &cat); err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("katalog: %d %v", resp.StatusCode, err)
	}
	if len(cat.Cosmetics) < 30 || len(cat.Gear) < 20 || len(cat.Options["face"]) == 0 || len(cat.Hair) == 0 || len(cat.Tiers) != 6 {
		t.Fatalf("katalog tidak lengkap: %d kosmetik, %d perlengkapan", len(cat.Cosmetics), len(cat.Gear))
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/wardrobe", "", nil); resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("katalog tanpa token: %d", resp.StatusCode)
	}
}

// Alur lengkap: buat karakter, beli, pakai, simpan, keluar-masuk, karakter tetap sama.
func TestCharacterCreatorFlow(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Pencipta")
	setState(t, st, cr.Player.ID, func(s *game.State) { s.Gold = 1000; s.Level = 5 })

	// Membuat karakter baru dengan pilihan gratis.
	look := game.Look{Hair: "rambut_panjang", HairColor: "#a8321e", SkinColor: "#c48a5e", Face: "lancip", Eyes: "besar", EyeColor: "#3c8c4a",
		Nose: "kecil", Mouth: "senyum", Brow: "melengkung", Beard: "lengkap", Body: "ramping", Height: 3, Width: -2, Muscle: 1, Head: 1, Torso: -1}
	resp, data := do(t, "POST", ts.URL+"/v1/players/me/look", cr.Token, map[string]any{"look": look})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || !p.State.Look.Made || p.State.Look.HairColor != "#a8321e" {
		t.Fatalf("simpan penampilan: %d %s", resp.StatusCode, data)
	}

	// Rambut berbayar belum dimiliki -> ditolak.
	look.Hair = "rambut_kepang"
	if resp, data := do(t, "POST", ts.URL+"/v1/players/me/look", cr.Token, map[string]any{"look": look}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("pakai kosmetik belum dimiliki harus 422: %d %s", resp.StatusCode, data)
	}

	// Beli: emas dikurangi server sesuai harga katalog (klien tidak mengirim harga).
	resp, data = do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "rambut_kepang", "request_id": "a1"})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || p.State.Gold != 780 || !slices.Contains(p.State.Wardrobe, "rambut_kepang") {
		t.Fatalf("beli: %d %s", resp.StatusCode, data)
	}
	// Permintaan yang diulang (id sama) tidak mengurangi saldo dua kali.
	resp, data = do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "rambut_kepang", "request_id": "a1"})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || p.State.Gold != 780 {
		t.Fatalf("beli ulang: %d %s", resp.StatusCode, data)
	}
	// Beli lagi dengan id baru: sudah dimiliki -> 422, saldo tetap.
	if resp, _ := do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "rambut_kepang", "request_id": "a2"}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("beli barang yang dimiliki: %d", resp.StatusCode)
	}
	// Tanpa saldo / item ilegal / kolom asing (harga dari klien) ditolak.
	if resp, _ := do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "mahkota"}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("emas kurang / level kurang: %d", resp.StatusCode)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "skin_gratis_hack"}); resp.StatusCode != http.StatusNotFound {
		t.Fatalf("item ilegal: %d", resp.StatusCode)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "jubah_merah", "price": 0}); resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("harga dari klien harus ditolak: %d", resp.StatusCode)
	}

	resp, data = do(t, "POST", ts.URL+"/v1/players/me/look", cr.Token, map[string]any{"look": look})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("pakai rambut kepang: %d %s", resp.StatusCode, data)
	}

	// Perlengkapan tempur: beli sepatu, pakai; perisai belum dimiliki ditolak.
	resp, data = do(t, "POST", ts.URL+"/v1/shop/buy", cr.Token, map[string]any{"shop": game.ShopGear, "item": "sepatu_kulit", "qty": 1, "request_id": "b1"})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("beli sepatu: %d %s", resp.StatusCode, data)
	}
	gold := playerOf(t, data).State.Gold
	resp, data = do(t, "POST", ts.URL+"/v1/shop/buy", cr.Token, map[string]any{"shop": game.ShopGear, "item": "sepatu_kulit", "qty": 1, "request_id": "b1"})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || p.State.Gold != gold || p.State.Inventory[len(p.State.Inventory)-1].Qty != 1 {
		t.Fatalf("beli ulang sepatu: %d %s", resp.StatusCode, data)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/inventory/equip", cr.Token, map[string]any{"item": "perisai_besi"}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("pakai perisai yang belum dimiliki: %d", resp.StatusCode)
	}
	if resp, data := do(t, "POST", ts.URL+"/v1/inventory/equip", cr.Token, map[string]any{"item": "sepatu_kulit"}); resp.StatusCode != http.StatusOK {
		t.Fatalf("pakai sepatu: %d %s", resp.StatusCode, data)
	}

	// Simpan posisi dari klien tidak bisa menulis penampilan/lemari.
	body := map[string]any{"version": 0, "state": map[string]any{"map": "desa_awal", "x": 5, "y": 5,
		"look": map[string]any{"hair": "rambut_jambul"}, "wardrobe": []string{"sayap_naga"}}}
	do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, body)

	// Keluar lalu masuk lagi: karakter tetap sama.
	do(t, "POST", ts.URL+"/v1/logout", cr.Token, nil)
	resp, data = do(t, "POST", ts.URL+"/v1/login", "", map[string]string{"login": "Pencipta", "password": testPassword})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("masuk: %d %s", resp.StatusCode, data)
	}
	var lr struct {
		Token string `json:"token"`
	}
	_ = json.Unmarshal(data, &lr)
	_, data = do(t, "GET", ts.URL+"/v1/players/me", lr.Token, nil)
	p := playerOf(t, data)
	got := p.State.Look
	if got.Hair != "rambut_kepang" || got.Face != "lancip" || got.Height != 3 || got.Beard != "lengkap" || p.State.Equipment.Boots != "sepatu_kulit" ||
		slices.Contains(p.State.Wardrobe, "sayap_naga") {
		t.Fatalf("karakter berubah setelah masuk ulang: %+v %+v %v", got, p.State.Equipment, p.State.Wardrobe)
	}
}

// Permintaan beli bersamaan dengan id sama hanya membayar sekali.
func TestCosmeticConcurrentBuy(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Pemborong")
	setState(t, st, cr.Player.ID, func(s *game.State) { s.Gold = 1000 })
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "jubah_merah", "request_id": "sama"})
		}()
	}
	wg.Wait()
	_, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	if p := playerOf(t, data); p.State.Gold != 780 || len(p.State.Wardrobe) != 1 {
		t.Fatalf("pembelian ganda: emas %d lemari %v", p.State.Gold, p.State.Wardrobe)
	}
}

// Ketukan Beli yang terkirim ulang bersamaan (id sama) di toko peralatan hanya membayar sekali, dan
// pembelian kosmetik bersamaan dengan id BERBEDA tetap hanya sekali karena kosmetik dimiliki sekali (v0.82.1).
func TestShopBuyConcurrentSameRequest(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Pembeli")
	setState(t, st, cr.Player.ID, func(s *game.State) { s.Gold = 1000; s.Level = 5 })
	var wg sync.WaitGroup
	for i := range 8 {
		wg.Add(2)
		go func() {
			defer wg.Done()
			do(t, "POST", ts.URL+"/v1/shop/buy", cr.Token, map[string]any{"shop": game.ShopGear, "item": "sepatu_kulit", "qty": 1, "request_id": "ketuk-1"})
		}()
		go func(i int) {
			defer wg.Done()
			do(t, "POST", ts.URL+"/v1/wardrobe/buy", cr.Token, map[string]any{"item": "jubah_biru", "request_id": "jubah-" + string(rune('a'+i))})
		}(i)
	}
	wg.Wait()
	_, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	p := playerOf(t, data)
	boots := 0
	for _, it := range p.State.Inventory {
		if it.ID == "sepatu_kulit" {
			boots = it.Qty
		}
	}
	// 1000 - 90 (sepatu, sekali) - 220 (jubah, sekali)
	if p.State.Gold != 690 || boots != 1 || len(p.State.Wardrobe) != 1 {
		t.Fatalf("transaksi ganda: emas %d sepatu %d lemari %v", p.State.Gold, boots, p.State.Wardrobe)
	}
}

// Syarat level dari katalog server berlaku saat membeli perlengkapan, bukan hanya saat memakai (v0.82.1).
func TestShopBuyLevelRequirement(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Pemula")
	setState(t, st, cr.Player.ID, func(s *game.State) { s.Gold = 99999 })
	resp, data := do(t, "POST", ts.URL+"/v1/shop/buy", cr.Token, map[string]any{"shop": game.ShopGear, "item": "pedang_legenda", "qty": 1})
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("level 1 membeli senjata Lv 30 harus 422: %d %s", resp.StatusCode, data)
	}
	_, data = do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	if p := playerOf(t, data); p.State.Gold != 99999 || len(p.State.Inventory) != 1 {
		t.Fatalf("penolakan tidak boleh mengubah emas/barang: %+v", p.State)
	}
}
