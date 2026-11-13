package api

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestFormationEndpoint(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Panglima")
	resp, data := do(t, "POST", ts.URL+"/v1/soldiers/formation", cr.Token, map[string]string{"formation": "perisai"})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || p.State.Formation != "perisai" {
		t.Fatalf("pilih formasi: %d %s", resp.StatusCode, data)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/soldiers/formation", cr.Token, map[string]string{"formation": "naga"}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("formasi asing: %d", resp.StatusCode)
	}
	_, data = do(t, "GET", ts.URL+"/v1/progress", cr.Token, nil)
	var pr struct {
		Formations []map[string]any  `json:"formations"`
		Roles      map[string]string `json:"roles"`
	}
	if json.Unmarshal(data, &pr) != nil || len(pr.Formations) != 6 || pr.Roles["ksatria"] != "tank" {
		t.Errorf("daftar formasi & peran: %s", data)
	}
	// Simpan posisi dari klien tidak mengubah formasi.
	_, data = do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	me := playerOf(t, data)
	st := me.State
	st.Formation = "serbu"
	_, data = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: me.Version, State: st})
	if p := playerOf(t, data); p.State.Formation != "perisai" {
		t.Errorf("klien tidak boleh mengubah formasi lewat simpan: %q", p.State.Formation)
	}
}
