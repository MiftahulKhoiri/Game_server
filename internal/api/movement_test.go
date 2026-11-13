package api

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// Gerakan dikendalikan server (audit keamanan): posisi dari klien hanya diterima bila bisa dicapai.

// clockServer: server uji dengan jam yang diatur tes (milidetik), bukan jam yang maju sendiri.
func clockServer(t *testing.T) (*httptest.Server, *store.Store, *atomic.Int64) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "gerak.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	var ms atomic.Int64
	ms.Store(time.Now().UnixMilli())
	clock := func() time.Time { return time.UnixMilli(ms.Load()) }
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	ts := httptest.NewServer(NewWithClock(st, log, testInfo, game.RandFunc(func(n int) int { return 99 % n }), clock))
	t.Cleanup(ts.Close)
	return ts, st, &ms
}

// savePose mengirim posisi (peta, x halus, z halus) dengan versi terbaru; mengembalikan status dan pemain.
func savePose(t *testing.T, ts *httptest.Server, tok, mapID string, fx, fz float64) (int, game.Player) {
	t.Helper()
	_, data := do(t, "GET", ts.URL+"/v1/players/me", tok, nil)
	me := playerOf(t, data)
	st := me.State
	st.Map, st.X, st.Y, st.FX, st.FZ = mapID, int(fx), int(fz), fx, fz
	resp, data := do(t, "PUT", ts.URL+"/v1/players/me/save", tok, saveRequest{Version: me.Version, State: st})
	if resp.StatusCode != http.StatusOK {
		_, data = do(t, "GET", ts.URL+"/v1/players/me", tok, nil)
	}
	return resp.StatusCode, playerOf(t, data)
}

func TestSaveRejectsTeleport(t *testing.T) {
	ts, _, clock := clockServer(t)
	cr := register(t, ts, "Pelompat")
	clock.Add(1_000)
	code, p := savePose(t, ts, cr.Token, game.MapDesaAwal, 80.5, 45.5)
	if code != http.StatusUnprocessableEntity {
		t.Fatalf("teleport ke ujung desa: status %d, mau 422", code)
	}
	if p.State.X != game.SpawnX || p.State.Y != game.SpawnY {
		t.Errorf("posisi berubah walau ditolak: (%d,%d)", p.State.X, p.State.Y)
	}
	// Berjalan normal tetap diterima.
	clock.Add(2_000)
	if code, p = savePose(t, ts, cr.Token, game.MapDesaAwal, 12.5, 5.5); code != http.StatusOK || p.State.X != 12 {
		t.Fatalf("berjalan 7 petak dalam 2 detik: %d (%d,%d)", code, p.State.X, p.State.Y)
	}
}

func TestSaveRejectsLockedMap(t *testing.T) {
	ts, db, clock := clockServer(t)
	cr := register(t, ts, "Penyusup")
	place(t, db, cr.Player.ID, game.MapHutanLebat, 146, 48) // di depan gerbang Gua Goblin
	clock.Add(3_600_000)
	if code, p := savePose(t, ts, cr.Token, game.MapGuaGoblin, 30.5, 1.5); code != http.StatusUnprocessableEntity || p.State.Map != game.MapHutanLebat {
		t.Fatalf("gua terkunci: status %d, peta %s", code, p.State.Map)
	}
	// Langsung ke ruang takhta / rumah orang lewat parameter peta juga ditolak.
	for _, m := range []string{game.MapTakhta, game.MapIstana, game.MapRumahPemain} {
		if code, _ := savePose(t, ts, cr.Token, m, 4.5, 4.5); code != http.StatusUnprocessableEntity {
			t.Errorf("peta %s: status %d, mau 422", m, code)
		}
	}
	// Setelah ketiga bos hutan kalah, gerbang terbuka.
	setState(t, db, cr.Player.ID, func(s *game.State) { s.Hutan.Wave = game.HutanWaves })
	clock.Add(1_000)
	if code, p := savePose(t, ts, cr.Token, game.MapGuaGoblin, 30.5, 1.5); code != http.StatusOK || p.State.Map != game.MapGuaGoblin {
		t.Fatalf("gua terbuka: status %d, peta %s", code, p.State.Map)
	}
}

func TestWorldLootFromFarRejected(t *testing.T) {
	ts, _, clock := clockServer(t)
	cr := register(t, ts, "Penjarah")
	clock.Add(500)
	// Pemain di titik awal (5,5) mengaku berdiri di samping peti desa_1 (43,8) dan pohon di sebelahnya.
	chest := map[string]any{"map": "desa_awal", "fx": 43.5, "fz": 9.2, "yaw": 0, "id": "desa_1"}
	resp, data := do(t, "POST", ts.URL+"/v1/world/chest", cr.Token, chest)
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("peti dari jauh lewat posisi palsu: %d %s", resp.StatusCode, data)
	}
	brk := map[string]any{"map": "desa_awal", "fx": 43.5, "fz": 9.2, "yaw": 0,
		"objects": []map[string]any{{"kind": "pohon", "x": 44, "z": 9}}}
	if resp, data := do(t, "POST", ts.URL+"/v1/world/break", cr.Token, brk); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("benda dari jauh lewat posisi palsu: %d %s", resp.StatusCode, data)
	}
	// Peta lain sekaligus (mis. peti di hutan) juga ditolak.
	far := map[string]any{"map": "hutan_lebat", "fx": 38.5, "fz": 6.5, "yaw": 0, "id": "hutan_1"}
	if resp, _ := do(t, "POST", ts.URL+"/v1/world/chest", cr.Token, far); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("peti peta lain: %d", resp.StatusCode)
	}
	_, data = do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	me := playerOf(t, data)
	if me.State.Gold != 0 || len(me.State.Chests) != 0 || len(me.State.Broken) != 0 || me.State.X != game.SpawnX {
		t.Errorf("tidak boleh ada hadiah/perubahan: %+v", me.State)
	}
	// Setelah benar-benar berjalan ke sana (waktu cukup), peti boleh dibuka.
	clock.Add(15_000)
	if resp, data := do(t, "POST", ts.URL+"/v1/world/chest", cr.Token, chest); resp.StatusCode != http.StatusOK {
		t.Fatalf("peti setelah berjalan: %d %s", resp.StatusCode, data)
	}
}

func TestPoseRejectsNaNInfAndExtremes(t *testing.T) {
	ts, _, _ := clockServer(t)
	cr := register(t, ts, "Angka")
	raw := func(path, body string) int {
		req, _ := http.NewRequest("POST", ts.URL+path, bytes.NewBufferString(body))
		req.Header.Set("Authorization", "Bearer "+cr.Token)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	cases := []struct {
		body string
		want int
	}{
		{`{"map":"desa_awal","fx":NaN,"fz":5.5,"yaw":0,"id":"desa_1"}`, http.StatusBadRequest},
		{`{"map":"desa_awal","fx":"Inf","fz":5.5,"yaw":0,"id":"desa_1"}`, http.StatusBadRequest},
		{`{"map":"desa_awal","fx":1e309,"fz":5.5,"yaw":0,"id":"desa_1"}`, http.StatusBadRequest},
		{`{"map":"desa_awal","fx":1e300,"fz":5.5,"yaw":0,"id":"desa_1"}`, http.StatusUnprocessableEntity},
		{`{"map":"desa_awal","fx":-1e18,"fz":-1e18,"yaw":0,"id":"desa_1"}`, http.StatusUnprocessableEntity},
		{`{"map":"desa_awal","fx":5.5,"fz":5.5,"yaw":1e308,"id":"desa_1"}`, http.StatusUnprocessableEntity}, // posisi sah, peti jauh
		{`{"map":"","fx":5.5,"fz":5.5,"yaw":0,"id":"desa_1"}`, http.StatusUnprocessableEntity},
	}
	for _, c := range cases {
		if got := raw("/v1/world/chest", c.body); got != c.want {
			t.Errorf("%s: status %d, mau %d", c.body, got, c.want)
		}
	}
	// Simpan posisi: x/y di luar peta ditolak; posisi halus ekstrem di petak sah diletakkan di tengah petak.
	_, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	me := playerOf(t, data)
	st := me.State
	st.X, st.Y = -2147483648, 5
	if resp, _ := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: me.Version, State: st}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("x negatif ekstrem: %d", resp.StatusCode)
	}
	st.X, st.FX = game.SpawnX, 1e300
	resp, data := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: me.Version, State: st})
	if p := playerOf(t, data); resp.StatusCode != http.StatusOK || p.State.FX != float64(game.SpawnX)+0.5 {
		t.Errorf("fx ekstrem: %d fx=%v", resp.StatusCode, p.State.FX)
	}
}

// Pemain berjalan terus (4,4 petak/detik); klien menyimpan sesekali dan permintaan tiba dengan jeda jaringan
// yang berbeda-beda (sampai 2 detik lebih lambat, sehingga jarak antar-simpan di server bisa jauh lebih
// singkat dari waktu berjalan sesungguhnya). Semua harus diterima.
func TestMovementWithLatency(t *testing.T) {
	for _, jitter := range [][]int64{{0, 0, 0, 0}, {300, -200, 800, 0}, {1500, 0, 1200, 300}, {-1000, 2000, 1000, 500}} {
		ts, _, clock := clockServer(t)
		cr := register(t, ts, "Pejalan")
		base := clock.Load()
		x := float64(game.SpawnX) + 0.5
		for i, j := range jitter {
			x += 4.4 * 2 // 2 detik berjalan menyusuri jalan desa (baris 6)
			clock.Store(base + int64(i+1)*2000 + j)
			if code, _ := savePose(t, ts, cr.Token, game.MapDesaAwal, x, 6.5); code != http.StatusOK {
				t.Fatalf("jeda %v, langkah %d (x=%.1f): status %d", jitter, i, x, code)
			}
		}
	}
}

func TestReconnectResumesPosition(t *testing.T) {
	ts, _, clock := clockServer(t)
	cr := register(t, ts, "Pulang")
	clock.Add(2_000)
	if code, _ := savePose(t, ts, cr.Token, game.MapDesaAwal, 10.5, 6.5); code != http.StatusOK {
		t.Fatalf("simpan awal: %d", code)
	}
	// Sinyal putus 5 menit; aplikasi dibuka lagi di posisi yang sama, lalu berjalan.
	clock.Add(5 * 60_000)
	login := map[string]string{"login": "Pulang", "password": testPassword}
	_, data := postJSON(t, ts.URL+"/v1/login", login, nil)
	var again createResponse
	if err := json.Unmarshal(data, &again); err != nil || again.Player.State.X != 10 {
		t.Fatalf("login ulang: %v %s", err, data)
	}
	if code, _ := savePose(t, ts, again.Token, game.MapDesaAwal, 10.5, 6.5); code != http.StatusOK {
		t.Fatalf("posisi sama setelah tersambung: %d", code)
	}
	clock.Add(1_500)
	if code, p := savePose(t, ts, again.Token, game.MapDesaAwal, 14.5, 6.5); code != http.StatusOK || p.State.X != 14 {
		t.Fatalf("lanjut berjalan: %d", code)
	}
}
