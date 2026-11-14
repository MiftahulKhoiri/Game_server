package api

import (
	"net/http"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Character Creator, lemari kosmetik, dan toko kosmetik (v0.82.0). Klien hanya mengirim id dan tindakan;
// harga, level, kepemilikan, dan saldo diperiksa server di dalam satu transaksi (store.Update).

// getWardrobe: katalog kosmetik, pilihan wajah/tubuh, palet warna, dan perlengkapan tempur yang dijual.
func (s *Server) getWardrobe(w http.ResponseWriter, _ *http.Request) {
	gear, _ := game.ShopItems(game.ShopGear)
	var sale []game.ItemDef
	for _, it := range gear {
		if it.BuyPrice > 0 && it.Kind == game.KindEquipment {
			sale = append(sale, it)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"cosmetics":   game.Cosmetics,
		"categories":  game.CosmeticCats,
		"options":     game.LookOptions,
		"hair_colors": game.HairColors,
		"skin_colors": game.SkinColors,
		"eye_colors":  game.EyeColors,
		"tiers":       game.Tiers,
		"body_min":    game.BodyMin,
		"body_max":    game.BodyMax,
		"max_acc":     game.MaxAccessories,
		"gear":        sale,
		"gear_shop":   game.ShopGear,
	})
}

type lookRequest struct {
	Look game.Look `json:"look"`
}

// setLook menyimpan penampilan dari Character Creator. Mengembalikan Player.
func (s *Server) setLook(w http.ResponseWriter, r *http.Request) {
	var req lookRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.SetLook(req.Look) })
}

type cosmeticRequest struct {
	Item      string `json:"item"`
	RequestID string `json:"request_id,omitempty"`
}

// buyCosmetic membeli satu kosmetik. Permintaan yang diulang dengan request_id sama tidak membayar dua kali,
// dan kosmetik yang sudah dimiliki tidak bisa dibeli lagi. Mengembalikan Player.
func (s *Server) buyCosmetic(w http.ResponseWriter, r *http.Request) {
	var req cosmeticRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error {
		return st.Once(req.RequestID, func() error { return st.BuyCosmetic(req.Item) })
	})
}
