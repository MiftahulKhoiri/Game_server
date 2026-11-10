package api

// Uji banyak pemain sekaligus (roadmap no. 267 dan 269): server dipakai bersama oleh beberapa HP.
// Tiap pemain berjalan di goroutine sendiri, jadi helper di sini mengembalikan error alih-alih t.Fatal.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// call adalah permintaan HTTP yang aman dipakai dari goroutine.
func call(method, url, token string, body any, out any) (int, error) {
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
		return 0, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if out != nil && resp.StatusCode < 300 {
		if err := json.Unmarshal(data, out); err != nil {
			return resp.StatusCode, fmt.Errorf("json %s: %v (%s)", url, err, data)
		}
	}
	if resp.StatusCode >= 500 {
		return resp.StatusCode, fmt.Errorf("%s %s: %d %s", method, url, resp.StatusCode, data)
	}
	return resp.StatusCode, nil
}

// session satu pemain: bergerak, bertarung, berbelanja, membaca kejadian dunia.
func playSession(ts *httptest.Server, cr createResponse, moves int) (game.Player, []byte, error) {
	ver := cr.Player.Version
	st := cr.Player.State
	for i := 0; i < moves; i++ {
		st.X, st.Y = 6+i%5, 6+i%4
		var saved game.Player
		code, err := call("PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: ver, State: st}, &saved)
		if err != nil || code != http.StatusOK {
			return game.Player{}, nil, fmt.Errorf("simpan ke-%d: %d %v", i, code, err)
		}
		ver = saved.Version
		st = saved.State
	}
	var br battleResponse
	if code, err := call("POST", ts.URL+"/v1/battle/start", cr.Token, nil, &br); err != nil || code != http.StatusCreated {
		return game.Player{}, nil, fmt.Errorf("mulai bertarung: %d %v", code, err)
	}
	for i := 0; i < 60 && (br.Status == "" || br.Status == "ongoing"); i++ {
		if code, err := call("POST", ts.URL+"/v1/battle/action", cr.Token, map[string]string{"action": "attack"}, &br); err != nil || code != http.StatusOK {
			return game.Player{}, nil, fmt.Errorf("aksi bertarung: %d %v", code, err)
		}
	}
	if br.Status == "" || br.Status == "ongoing" {
		return game.Player{}, nil, fmt.Errorf("pertarungan tidak selesai dalam 60 aksi")
	}
	if code, err := call("GET", ts.URL+"/v1/shop", cr.Token, nil, nil); err != nil || code != http.StatusOK {
		return game.Player{}, nil, fmt.Errorf("toko: %d %v", code, err)
	}
	var ev json.RawMessage
	if code, err := call("GET", ts.URL+"/v1/world/events", cr.Token, nil, &ev); err != nil || code != http.StatusOK {
		return game.Player{}, nil, fmt.Errorf("kejadian dunia: %d %v", code, err)
	}
	var me game.Player
	if code, err := call("GET", ts.URL+"/v1/players/me", cr.Token, nil, &me); err != nil || code != http.StatusOK {
		return game.Player{}, nil, fmt.Errorf("data pemain: %d %v", code, err)
	}
	return me, ev, nil
}

// TestManyPlayersAtOnce: 12 pemain bermain bersamaan. Tidak boleh ada galat server, data tiap pemain
// tetap miliknya sendiri, dan semua pemain melihat kejadian dunia yang sama (jam dunia bersama).
func TestManyPlayersAtOnce(t *testing.T) {
	ts := newTestServer(t)
	const n = 12
	players := make([]createResponse, n)
	for i := range players {
		players[i] = register(t, ts, fmt.Sprintf("Pemain%02d", i))
	}

	type result struct {
		me  game.Player
		ev  []byte
		err error
	}
	results := make([]result, n)
	var wg sync.WaitGroup
	for i := range players {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			me, ev, err := playSession(ts, players[i], 15)
			results[i] = result{me, ev, err}
		}(i)
	}
	wg.Wait()

	for i, r := range results {
		if r.err != nil {
			t.Fatalf("pemain %d: %v", i, r.err)
		}
		if r.me.ID != players[i].Player.ID || r.me.Name != players[i].Player.Name {
			t.Errorf("pemain %d menerima data pemain lain: %s/%s", i, r.me.ID, r.me.Name)
		}
		if r.me.Version < players[i].Player.Version+15 {
			t.Errorf("pemain %d: versi %d, harusnya ≥ %d (simpanan hilang)", i, r.me.Version, players[i].Player.Version+15)
		}
		if string(r.ev) != string(results[0].ev) {
			t.Errorf("pemain %d melihat kejadian dunia berbeda:\n%s\n%s", i, r.ev, results[0].ev)
		}
	}
}

// TestTradeWhileOthersPlay: satu-satunya interaksi antarpemain (dagang) tetap benar
// saat banyak pemain lain sibuk menyimpan pada waktu yang sama.
func TestTradeWhileOthersPlay(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	seller := register(t, ts, "Penjual")
	buyer := register(t, ts, "Pembeli")
	others := []createResponse{register(t, ts, "Ramai1"), register(t, ts, "Ramai2"), register(t, ts, "Ramai3")}
	setState(t, st, seller.Player.ID, func(s *game.State) { s.AddItem("permata_merah", 2) })
	setState(t, st, buyer.Player.ID, func(s *game.State) { s.Gold = 300 })

	var wg sync.WaitGroup
	errs := make(chan error, len(others))
	for _, o := range others {
		wg.Add(1)
		go func(o createResponse) {
			defer wg.Done()
			if _, _, err := playSession(ts, o, 10); err != nil {
				errs <- err
			}
		}(o)
	}
	code, err := call("POST", ts.URL+"/v1/trades", seller.Token,
		map[string]any{"to": "Pembeli", "item": "permata_merah", "qty": 2, "price": 100}, nil)
	if err != nil || code != http.StatusCreated {
		t.Fatalf("buat tawaran: %d %v", code, err)
	}
	var list struct {
		Trades []game.Trade `json:"trades"`
	}
	if code, err := call("GET", ts.URL+"/v1/trades", buyer.Token, nil, &list); err != nil || code != http.StatusOK || len(list.Trades) != 1 {
		t.Fatalf("daftar tawaran: %d %v %+v", code, err, list)
	}
	code, err = call("POST", ts.URL+"/v1/trades/accept", buyer.Token, map[string]int64{"id": list.Trades[0].ID}, nil)
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Errorf("pemain lain: %v", e)
	}
	if err != nil || code != http.StatusOK {
		t.Fatalf("terima tawaran: %d %v", code, err)
	}
	var s, b game.Player
	_, _ = call("GET", ts.URL+"/v1/players/me", seller.Token, nil, &s)
	_, _ = call("GET", ts.URL+"/v1/players/me", buyer.Token, nil, &b)
	if s.State.Gold != 100 || b.State.Gold != 200 || invQty(b.State.Inventory, "permata_merah") != 2 {
		t.Errorf("hasil dagang salah: penjual %d emas, pembeli %d emas, %d permata", s.State.Gold, b.State.Gold, invQty(b.State.Inventory, "permata_merah"))
	}
}

// TestServerLatencyUnderLoad (no. 269): 8 pemain x 25 simpan bersamaan. Mencatat waktu tiap
// permintaan; batasnya longgar (p95 < 250 ms) supaya tetap lolos di CI dengan -race.
func TestServerLatencyUnderLoad(t *testing.T) {
	if testing.Short() {
		t.Skip("uji beban dilewati pada -short")
	}
	ts := newTestServer(t)
	const n, saves = 8, 25
	players := make([]createResponse, n)
	for i := range players {
		players[i] = register(t, ts, fmt.Sprintf("Beban%d", i))
	}
	var mu sync.Mutex
	var lat []time.Duration
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for _, p := range players {
		wg.Add(1)
		go func(p createResponse) {
			defer wg.Done()
			ver, st := p.Player.Version, p.Player.State
			for i := 0; i < saves; i++ {
				st.X = 6 + i%5
				var saved game.Player
				t0 := time.Now()
				code, err := call("PUT", ts.URL+"/v1/players/me/save", p.Token, saveRequest{Version: ver, State: st}, &saved)
				d := time.Since(t0)
				if err != nil || code != http.StatusOK {
					errs <- fmt.Errorf("simpan: %d %v", code, err)
					return
				}
				ver, st = saved.Version, saved.State
				mu.Lock()
				lat = append(lat, d)
				mu.Unlock()
			}
		}(p)
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	sort.Slice(lat, func(i, j int) bool { return lat[i] < lat[j] })
	p50, p95 := lat[len(lat)/2], lat[len(lat)*95/100]
	t.Logf("%d simpan bersamaan oleh %d pemain: p50 %v, p95 %v, maks %v", len(lat), n, p50, p95, lat[len(lat)-1])
	if p95 > 250*time.Millisecond {
		t.Errorf("p95 terlalu lambat: %v", p95)
	}
}

func invQty(inv []game.Item, id string) int {
	n := 0
	for _, it := range inv {
		if it.ID == id {
			n += it.Qty
		}
	}
	return n
}
