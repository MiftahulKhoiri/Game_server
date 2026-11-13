package api

import (
	"net/http"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Bunga bank (no. 181, v0.79.0): klaim lewat server, tidak bisa diubah lewat simpan.
func TestBankInterestEndpoint(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Penabung")
	resp, data := do(t, "POST", ts.URL+"/v1/bank/interest", cr.Token, nil)
	p := playerOf(t, data)
	if resp.StatusCode != http.StatusOK || p.State.BankDay != game.Now()/86_400 {
		t.Fatalf("klaim bunga: %d %s", resp.StatusCode, data)
	}
	st := p.State
	st.Bank, st.BankDay = 99_999, 0
	_, data = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: p.Version, State: st})
	if q := playerOf(t, data); q.State.Bank != 0 || q.State.BankDay != p.State.BankDay {
		t.Errorf("klien mengubah tabungan/hari bunga lewat simpan: %+v", q.State)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/bank/interest", "", nil); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token: %d", resp.StatusCode)
	}
}
