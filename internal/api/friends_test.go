package api

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// Teman dan pemain aktif (no. 176, v0.79.0).
func TestFriendsAndRecentPlayers(t *testing.T) {
	ts := newTestServer(t)
	a := register(t, ts, "Sekar")
	register(t, ts, "Bayu")

	resp, data := do(t, "POST", ts.URL+"/v1/friends", a.Token, map[string]string{"name": "bayu"})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || len(p.State.Friends) != 1 || p.State.Friends[0] != "Bayu" {
		t.Fatalf("tambah teman (ejaan asli): %d %s", resp.StatusCode, data)
	}
	cases := []struct {
		name string
		code int
	}{{"Bayu", 422}, {"sekar", 422}, {"TidakAda", 404}, {"", 422}, {strings.Repeat("x", 80), 422}}
	for _, c := range cases {
		if resp, _ := do(t, "POST", ts.URL+"/v1/friends", a.Token, map[string]string{"name": c.name}); resp.StatusCode != c.code {
			t.Errorf("teman %q: %d, mau %d", c.name, resp.StatusCode, c.code)
		}
	}

	resp, data = do(t, "GET", ts.URL+"/v1/players/recent", a.Token, nil)
	var rp struct {
		Players []string `json:"players"`
	}
	if resp.StatusCode != http.StatusOK || json.Unmarshal(data, &rp) != nil || len(rp.Players) != 1 || rp.Players[0] != "Bayu" {
		t.Fatalf("pemain aktif: %d %s", resp.StatusCode, data)
	}
	if strings.Contains(string(data), "@") {
		t.Errorf("email bocor: %s", data)
	}

	resp, data = do(t, "POST", ts.URL+"/v1/friends/remove", a.Token, map[string]string{"name": "BAYU"})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || len(p.State.Friends) != 0 {
		t.Fatalf("hapus teman: %d %s", resp.StatusCode, data)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/friends/remove", a.Token, map[string]string{"name": "Bayu"}); resp.StatusCode != 422 {
		t.Errorf("hapus yang bukan teman: %d", resp.StatusCode)
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/recent", "", nil); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token: %d", resp.StatusCode)
	}

	// Simpan dari klien tidak bisa menulis daftar teman.
	_, data = do(t, "GET", ts.URL+"/v1/players/me", a.Token, nil)
	me := playerOf(t, data)
	st := me.State
	st.Friends = []string{"Palsu"}
	_, data = do(t, "PUT", ts.URL+"/v1/players/me/save", a.Token, saveRequest{Version: me.Version, State: st})
	if p := playerOf(t, data); len(p.State.Friends) != 0 {
		t.Errorf("klien mengubah daftar teman lewat simpan: %v", p.State.Friends)
	}
}
