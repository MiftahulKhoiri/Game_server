package api

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	ts := httptest.NewServer(New(st, log))
	t.Cleanup(ts.Close)
	return ts
}

func do(t *testing.T, method, url, token string, body any) (*http.Response, []byte) {
	t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, url, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	return resp, data
}

func register(t *testing.T, ts *httptest.Server, name string) createResponse {
	t.Helper()
	resp, data := do(t, "POST", ts.URL+"/v1/players", "", map[string]string{"name": name})
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("daftar %q: status %d: %s", name, resp.StatusCode, data)
	}
	var cr createResponse
	if err := json.Unmarshal(data, &cr); err != nil {
		t.Fatal(err)
	}
	return cr
}

func TestHealth(t *testing.T) {
	ts := newTestServer(t)
	resp, _ := do(t, "GET", ts.URL+"/healthz", "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestRegisterAndGetMe(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Petualang")
	if cr.Token == "" || cr.Player.ID == "" || cr.Player.Version != 1 {
		t.Fatalf("respons daftar tidak lengkap: %+v", cr)
	}

	resp, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d: %s", resp.StatusCode, data)
	}
	var p game.Player
	_ = json.Unmarshal(data, &p)
	if p.Name != "Petualang" || p.State.Level != 1 {
		t.Fatalf("data pemain salah: %+v", p)
	}
}

func TestRegisterRejects(t *testing.T) {
	ts := newTestServer(t)
	register(t, ts, "Budi")

	resp, _ := do(t, "POST", ts.URL+"/v1/players", "", map[string]string{"name": "budi"})
	if resp.StatusCode != http.StatusConflict {
		t.Errorf("nama kembar (beda huruf besar) harus 409, dapat %d", resp.StatusCode)
	}
	resp, _ = do(t, "POST", ts.URL+"/v1/players", "", map[string]string{"name": "a"})
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("nama pendek harus 422, dapat %d", resp.StatusCode)
	}
	resp, _ = do(t, "POST", ts.URL+"/v1/players", "", map[string]any{"name": "Citra", "admin": true})
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("field asing harus 400, dapat %d", resp.StatusCode)
	}
}

func TestAuthRequired(t *testing.T) {
	ts := newTestServer(t)
	resp, _ := do(t, "GET", ts.URL+"/v1/players/me", "", nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token harus 401, dapat %d", resp.StatusCode)
	}
	resp, _ = do(t, "GET", ts.URL+"/v1/players/me", "salah", nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("token salah harus 401, dapat %d", resp.StatusCode)
	}
}

func TestSaveAndConflict(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Dewi")

	st := cr.Player.State
	st.Level, st.XP, st.Gold = 2, 120, 50
	st.Inventory = []game.Item{{ID: "ramuan", Qty: 3}}

	resp, data := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token,
		saveRequest{Version: cr.Player.Version, State: st})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan: status %d: %s", resp.StatusCode, data)
	}
	var saved game.Player
	_ = json.Unmarshal(data, &saved)
	if saved.Version != 2 || saved.State.Level != 2 || len(saved.State.Inventory) != 1 {
		t.Fatalf("hasil simpan salah: %+v", saved)
	}

	// Menyimpan lagi dengan versi lama harus ditolak.
	resp, _ = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token,
		saveRequest{Version: 1, State: st})
	if resp.StatusCode != http.StatusConflict {
		t.Errorf("versi lama harus 409, dapat %d", resp.StatusCode)
	}

	// Data tidak masuk akal harus ditolak.
	bad := st
	bad.HP = bad.MaxHP + 10
	resp, _ = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token,
		saveRequest{Version: 2, State: bad})
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("state tidak valid harus 422, dapat %d", resp.StatusCode)
	}
}

func TestTokensAreIsolated(t *testing.T) {
	ts := newTestServer(t)
	a := register(t, ts, "Pemain_A")
	b := register(t, ts, "Pemain_B")

	_, data := do(t, "GET", ts.URL+"/v1/players/me", b.Token, nil)
	var p game.Player
	_ = json.Unmarshal(data, &p)
	if p.ID == a.Player.ID || p.Name != "Pemain_B" {
		t.Fatalf("token B harus mengembalikan pemain B, dapat %+v", p)
	}
}
