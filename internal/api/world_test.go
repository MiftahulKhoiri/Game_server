package api

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

func TestWorldChestAndBreak(t *testing.T) {
	ts, db := newTestServerWithStore(t)
	cr := register(t, ts, "Pemburu")
	tok := cr.Token

	var empty struct {
		Items []game.WorldItem `json:"items"`
	}
	resp, data := do(t, "GET", ts.URL+"/v1/world?map=desa_awal", tok, nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d: %s", resp.StatusCode, data)
	}
	json.Unmarshal(data, &empty)
	if len(empty.Items) != 0 {
		t.Fatalf("awalnya kosong: %+v", empty.Items)
	}

	// Peti desa_1 ada di petak (43, 8): dari jauh harus ditolak.
	far := map[string]any{"map": "desa_awal", "fx": 5.5, "fz": 5.5, "yaw": 0, "id": "desa_1"}
	if resp, _ := do(t, "POST", ts.URL+"/v1/world/chest", tok, far); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("peti dari jauh: status %d, mau 422", resp.StatusCode)
	}

	place(t, db, cr.Player.ID, game.MapDesaAwal, 43, 9) // berjalan ke dekat peti (disiapkan lewat store)
	near := map[string]any{"map": "desa_awal", "fx": 43.5, "fz": 9.2, "yaw": 0, "id": "desa_1"}
	resp, data = do(t, "POST", ts.URL+"/v1/world/chest", tok, near)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("buka peti: status %d: %s", resp.StatusCode, data)
	}
	var got worldResponse
	json.Unmarshal(data, &got)
	if got.Loot.Gold <= 0 || got.Player.State.Gold != got.Loot.Gold {
		t.Errorf("emas peti %d, emas pemain %d", got.Loot.Gold, got.Player.State.Gold)
	}
	if got.Player.State.X != 43 || got.Player.State.Y != 9 {
		t.Errorf("posisi tidak ikut diperbarui: (%d,%d)", got.Player.State.X, got.Player.State.Y)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/world/chest", tok, near); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("peti kosong: status %d, mau 422", resp.StatusCode)
	}

	// Pohon di sebelah pemain.
	brk := map[string]any{"map": "desa_awal", "fx": 43.5, "fz": 9.2, "yaw": 0,
		"objects": []map[string]any{{"kind": "pohon", "x": 44, "z": 9}}}
	resp, data = do(t, "POST", ts.URL+"/v1/world/break", tok, brk)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("hancurkan: status %d: %s", resp.StatusCode, data)
	}
	json.Unmarshal(data, &got)
	if got.Loot.Broken != 1 {
		t.Errorf("harus tercatat 1 benda hancur: %+v", got.Loot)
	}
	bad := map[string]any{"map": "desa_awal", "fx": 43.5, "fz": 9.2, "yaw": 0,
		"objects": []map[string]any{{"kind": "emas", "x": 44, "z": 9}}}
	if resp, _ := do(t, "POST", ts.URL+"/v1/world/break", tok, bad); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("jenis salah: status %d, mau 422", resp.StatusCode)
	}

	resp, data = do(t, "GET", ts.URL+"/v1/world?map=desa_awal", tok, nil)
	json.Unmarshal(data, &empty)
	if len(empty.Items) != 2 {
		t.Errorf("harus ada peti terbuka + pohon hancur: %+v", empty.Items)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/world/break", "", brk); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token: status %d", resp.StatusCode)
	}
}
