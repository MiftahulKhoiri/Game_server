package api

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/auth"
	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

func TestMain(m *testing.M) {
	auth.Iterations = 1000 // hash cepat untuk tes
	os.Exit(m.Run())
}

const testPassword = "sandi-rahasia-1"

// regBody adalah isi permintaan daftar yang sah untuk nama tertentu.
func regBody(name string) map[string]string {
	return map[string]string{"name": name, "email": strings.ToLower(name) + "@contoh.id", "password": testPassword}
}

var testInfo = version.Info{
	Server: "0.2.0", Commit: "test", API: 1,
	MinClient: "0.2.0", LatestClient: "0.3.0",
	UpdateURL: "https://example.test/unduh",
}

func newTestServer(t *testing.T) *httptest.Server {
	ts, _ := newTestServerWithStore(t)
	return ts
}

func newTestServerWithStore(t *testing.T) (*httptest.Server, *store.Store) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	// Jam buatan: maju 2,5 detik tiap permintaan pertarungan, jadi cooldown selalu siap
	// dan musuh menyerang kira-kira sekali per aksi.
	var tick atomic.Int64
	clock := func() time.Time { return time.UnixMilli(1_700_000_000_000 + tick.Add(2500)) }
	ts := httptest.NewServer(NewWithClock(st, log, testInfo, game.RandFunc(func(n int) int { return 99 % n }), clock))
	t.Cleanup(ts.Close)
	return ts, st
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
	resp, data := do(t, "POST", ts.URL+"/v1/players", "", regBody(name))
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

	resp, _ := do(t, "POST", ts.URL+"/v1/players", "", regBody("budi"))
	if resp.StatusCode != http.StatusConflict {
		t.Errorf("nama kembar (beda huruf besar) harus 409, dapat %d", resp.StatusCode)
	}
	resp, _ = do(t, "POST", ts.URL+"/v1/players", "", regBody("a"))
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

func TestSaveOnlyAppliesPosition(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Dewi")

	// Klien mencoba curang: menaikkan level, emas, dan tas sekaligus bergerak.
	st := cr.Player.State
	st.Level, st.XP, st.Gold = 50, 9999, 999999
	st.Inventory = []game.Item{{ID: "pedang_dewa", Qty: 1}}
	st.X, st.Y = 7, 8

	resp, data := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token,
		saveRequest{Version: cr.Player.Version, State: st})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan: status %d: %s", resp.StatusCode, data)
	}
	var saved game.Player
	_ = json.Unmarshal(data, &saved)
	if saved.State.X != 7 || saved.State.Y != 8 || saved.Version != 2 {
		t.Errorf("posisi/versi tidak tersimpan: %+v", saved)
	}
	if saved.State.Level != 1 || saved.State.Gold != 0 || saved.State.XP != 0 {
		t.Errorf("statistik tidak boleh bisa diubah klien: %+v", saved.State)
	}
	if len(saved.State.Inventory) != 1 || saved.State.Inventory[0].ID != game.PotionID {
		t.Errorf("tas tidak boleh bisa diubah klien: %+v", saved.State.Inventory)
	}
}

func TestSaveConflictAndValidation(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Eko")
	st := cr.Player.State
	st.X = 6

	resp, _ := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 1, State: st})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan pertama: %d", resp.StatusCode)
	}
	resp, _ = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 1, State: st})
	if resp.StatusCode != http.StatusConflict {
		t.Errorf("versi lama harus 409, dapat %d", resp.StatusCode)
	}
	bad := st
	bad.HP = bad.MaxHP + 10
	resp, _ = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 2, State: bad})
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

func TestVersionEndpoint(t *testing.T) {
	ts := newTestServer(t)
	resp, data := do(t, "GET", ts.URL+"/v1/version", "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d", resp.StatusCode)
	}
	var info version.Info
	if err := json.Unmarshal(data, &info); err != nil {
		t.Fatal(err)
	}
	if info != testInfo {
		t.Fatalf("info = %+v; mau %+v", info, testInfo)
	}
}

func doWithVersion(t *testing.T, method, url, clientVersion string, body any) (*http.Response, []byte) {
	t.Helper()
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(method, url, bytes.NewReader(b))
	if clientVersion != "" {
		req.Header.Set("X-Client-Version", clientVersion)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	return resp, data
}

func TestOldClientMustUpdate(t *testing.T) {
	ts := newTestServer(t)

	// Di bawah MinClient (0.2.0): ditolak 426 beserta alamat update.
	resp, data := doWithVersion(t, "POST", ts.URL+"/v1/players", "0.1.0", regBody("Lawas"))
	if resp.StatusCode != http.StatusUpgradeRequired {
		t.Fatalf("klien lama harus 426, dapat %d: %s", resp.StatusCode, data)
	}
	var e struct {
		MinClient string `json:"min_client"`
		UpdateURL string `json:"update_url"`
	}
	_ = json.Unmarshal(data, &e)
	if e.MinClient != "0.2.0" || e.UpdateURL != testInfo.UpdateURL {
		t.Errorf("isi 426 salah: %s", data)
	}

	// Tepat di MinClient atau lebih baru: boleh.
	for _, v := range []string{"0.2.0", "0.3.0", "1.0.0"} {
		resp, data = doWithVersion(t, "POST", ts.URL+"/v1/players", v, regBody("Baru"+v[:1]+v[2:3]))
		if resp.StatusCode != http.StatusCreated {
			t.Errorf("klien %s harus boleh, dapat %d: %s", v, resp.StatusCode, data)
		}
	}

	// Tanpa header (klien sangat lama) tidak bisa dipaksa, tetap dilayani.
	resp, _ = doWithVersion(t, "POST", ts.URL+"/v1/players", "", regBody("TanpaHeader"))
	if resp.StatusCode != http.StatusCreated {
		t.Errorf("tanpa header harus lolos, dapat %d", resp.StatusCode)
	}

	// /v1/version dan /healthz selalu terbuka agar klien lama bisa tahu harus update.
	resp, _ = doWithVersion(t, "GET", ts.URL+"/v1/version", "0.0.1", nil)
	if resp.StatusCode != http.StatusOK {
		t.Errorf("/v1/version harus terbuka untuk klien lama, dapat %d", resp.StatusCode)
	}
}

// --- pertarungan ---
// Sumber acak tetap (99 % n): tidak kritis, kabur selalu gagal, tidak ada drop,
// variasi kerusakan 97%, dan musuh level 1 dipilih tetap.

func battleCall(t *testing.T, ts *httptest.Server, token, method, path string, body any) (int, battleResponse, []byte) {
	t.Helper()
	resp, data := do(t, method, ts.URL+path, token, body)
	var br battleResponse
	_ = json.Unmarshal(data, &br)
	return resp.StatusCode, br, data
}

func TestBattleFullFlow(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Pejuang")

	if code, _, _ := battleCall(t, ts, cr.Token, "GET", "/v1/battle", nil); code != http.StatusNotFound {
		t.Errorf("sebelum mulai harus 404, dapat %d", code)
	}
	if code, _, d := battleCall(t, ts, cr.Token, "POST", "/v1/battle/action", map[string]string{"action": "attack"}); code != http.StatusNotFound {
		t.Errorf("aksi tanpa pertarungan harus 404, dapat %d: %s", code, d)
	}

	code, start, d := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil)
	if code != http.StatusCreated || start.Battle == nil || start.Battle.EnemyHP <= 0 {
		t.Fatalf("mulai: %d %s", code, d)
	}
	if code, _, _ := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil); code != http.StatusConflict {
		t.Errorf("mulai dua kali harus 409, dapat %d", code)
	}
	// Dapat dilanjutkan (mis. aplikasi ditutup di tengah pertarungan).
	code, resumed, _ := battleCall(t, ts, cr.Token, "GET", "/v1/battle", nil)
	if code != http.StatusOK || resumed.Battle == nil || resumed.Battle.EnemyID != start.Battle.EnemyID {
		t.Errorf("lanjutkan salah: %d %+v", code, resumed)
	}

	var last battleResponse
	for i := 0; i < 40; i++ {
		code, last, d = battleCall(t, ts, cr.Token, "POST", "/v1/battle/action", map[string]string{"action": "attack"})
		if code != http.StatusOK {
			t.Fatalf("aksi: %d %s", code, d)
		}
		if last.Status != "ongoing" {
			break
		}
	}
	if last.Status != "won" || last.Battle != nil || last.Rewards == nil {
		t.Fatalf("harus menang dan pertarungan hilang: %+v", last)
	}
	if last.Player.State.XP != last.Rewards.XP || last.Player.State.Gold != last.Rewards.Gold {
		t.Errorf("hadiah tidak masuk ke pemain: %+v", last)
	}
	if last.Player.Version <= cr.Player.Version {
		t.Errorf("versi harus naik: %d", last.Player.Version)
	}
	if code, _, _ := battleCall(t, ts, cr.Token, "GET", "/v1/battle", nil); code != http.StatusNotFound {
		t.Errorf("setelah selesai harus 404, dapat %d", code)
	}

	// Hasil tersimpan permanen.
	_, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	var me game.Player
	_ = json.Unmarshal(data, &me)
	if me.State.XP != last.Rewards.XP {
		t.Errorf("XP tidak tersimpan: %+v", me.State)
	}
}

func TestBattleActionErrors(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Teliti")
	battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil)

	if code, _, _ := battleCall(t, ts, cr.Token, "POST", "/v1/battle/action", map[string]string{"action": "teleport"}); code != http.StatusUnprocessableEntity {
		t.Errorf("aksi asing harus 422, dapat %d", code)
	}
	// Semua aksi real-time dikenali dan hasilnya memuat tampilan cooldown + kejadian.
	for _, a := range []string{"defend", "skill1", "skill2"} {
		code, br, d := battleCall(t, ts, cr.Token, "POST", "/v1/battle/action", map[string]string{"action": a})
		if code != http.StatusOK {
			t.Fatalf("%s: %d %s", a, code, d)
		}
		if br.Battle != nil && (br.Battle.CooldownMax[a] == 0 || len(br.Events) == 0) {
			t.Errorf("%s: tampilan/kejadian kosong: %s", a, d)
		}
	}
	if code, _, _ := battleCall(t, ts, "", "POST", "/v1/battle/start", nil); code != http.StatusUnauthorized {
		t.Errorf("tanpa token harus 401, dapat %d", code)
	}
}

func TestBattleAndSaveDoNotOverwriteEachOther(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Balapan")
	_, start, _ := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil)

	// Simpan posisi dengan versi LAMA (klien belum tahu pertarungan menaikkan versi): 409.
	st := cr.Player.State
	st.X = 9
	resp, _ := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: cr.Player.Version, State: st})
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("versi lama setelah pertarungan harus 409, dapat %d", resp.StatusCode)
	}
	// Dengan versi terbaru: berhasil, dan pertarungan tidak terganggu.
	resp, _ = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: start.Player.Version, State: st})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan versi terbaru: %d", resp.StatusCode)
	}
	if code, b, _ := battleCall(t, ts, cr.Token, "GET", "/v1/battle", nil); code != http.StatusOK || b.Player.State.X != 9 {
		t.Errorf("pertarungan/posisi salah: %d %+v", code, b.Player.State)
	}
}

// --- toko ---

func TestShop(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Pedagang")

	resp, data := do(t, "GET", ts.URL+"/v1/shop", cr.Token, nil)
	var catalog struct {
		Items []game.ItemDef `json:"items"`
	}
	if resp.StatusCode != http.StatusOK || json.Unmarshal(data, &catalog) != nil || len(catalog.Items) == 0 {
		t.Fatalf("daftar toko: %d %s", resp.StatusCode, data)
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/shop", "", nil); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token harus 401, dapat %d", resp.StatusCode)
	}

	call := func(path string, body any) (int, game.Player) {
		resp, data := do(t, "POST", ts.URL+path, cr.Token, body)
		var p game.Player
		_ = json.Unmarshal(data, &p)
		return resp.StatusCode, p
	}

	code, p := call("/v1/shop/sell", map[string]any{"item": "ramuan", "qty": 2})
	if code != http.StatusOK || p.State.Gold != 12 || len(p.State.Inventory) != 0 || p.Version != 2 {
		t.Fatalf("jual 2 ramuan: %d gold=%d inv=%v ver=%d", code, p.State.Gold, p.State.Inventory, p.Version)
	}
	for _, c := range []struct {
		path string
		body map[string]any
		want int
	}{
		{"/v1/shop/buy", map[string]any{"item": "ramuan", "qty": 1}, http.StatusUnprocessableEntity}, // emas 12 < 15
		{"/v1/shop/buy", map[string]any{"item": "naga", "qty": 1}, http.StatusNotFound},
		{"/v1/shop/buy", map[string]any{"item": "taring_goblin", "qty": 1}, http.StatusUnprocessableEntity},
		{"/v1/shop/sell", map[string]any{"item": "ramuan", "qty": 1}, http.StatusUnprocessableEntity}, // sudah habis
		{"/v1/shop/sell", map[string]any{"item": "ramuan", "qty": 0}, http.StatusUnprocessableEntity},
	} {
		if code, _ := call(c.path, c.body); code != c.want {
			t.Errorf("%s %v: mau %d, dapat %d", c.path, c.body, c.want, code)
		}
	}
	battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil)
	if code, _ := call("/v1/shop/sell", map[string]any{"item": "ramuan", "qty": 1}); code != http.StatusConflict {
		t.Errorf("berdagang saat bertarung harus 409, dapat %d", code)
	}
}

// --- misi ---

func TestQuestEndToEnd(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Penolong")

	type qresp struct {
		Player     game.Player      `json:"player"`
		Quests     []game.QuestView `json:"quests"`
		RewardGold int              `json:"reward_gold"`
	}
	call := func(path string, body any) (int, qresp) {
		resp, data := do(t, "POST", ts.URL+path, cr.Token, body)
		var q qresp
		_ = json.Unmarshal(data, &q)
		return resp.StatusCode, q
	}
	list := func() []game.QuestView {
		resp, data := do(t, "GET", ts.URL+"/v1/quests", cr.Token, nil)
		var out struct {
			Quests []game.QuestView `json:"quests"`
		}
		if resp.StatusCode != http.StatusOK || json.Unmarshal(data, &out) != nil {
			t.Fatalf("GET /v1/quests: %d %s", resp.StatusCode, data)
		}
		return out.Quests
	}

	if resp, _ := do(t, "GET", ts.URL+"/v1/quests", "", nil); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token harus 401, dapat %d", resp.StatusCode)
	}
	qs := list()
	if len(qs) == 0 || qs[0].ID != "selamatkan_nenek" || qs[0].Status != game.QuestAvailable {
		t.Fatalf("daftar misi awal salah: %+v", qs)
	}

	if len(qs) < 2 || qs[1].ID != "selamatkan_petani" || qs[1].Status != game.QuestLocked {
		t.Fatalf("misi petani harus terkunci: %+v", qs)
	}
	if code, _ := call("/v1/quests/accept", map[string]string{"quest": "selamatkan_petani"}); code != http.StatusUnprocessableEntity {
		t.Errorf("menerima misi terkunci harus 422, dapat %d", code)
	}

	q := map[string]string{"quest": "selamatkan_nenek"}
	if code, _ := call("/v1/quests/claim", q); code != http.StatusUnprocessableEntity {
		t.Errorf("klaim sebelum terima harus 422, dapat %d", code)
	}
	if code, _ := call("/v1/quests/accept", map[string]string{"quest": "naga"}); code != http.StatusNotFound {
		t.Errorf("misi asing harus 404, dapat %d", code)
	}
	if code, r := call("/v1/quests/accept", q); code != http.StatusOK || r.Quests[0].Status != game.QuestActive {
		t.Fatalf("terima: %d %+v", code, r.Quests)
	}
	if code, _ := call("/v1/quests/accept", q); code != http.StatusConflict {
		t.Errorf("terima dua kali harus 409, dapat %d", code)
	}
	if code, _ := call("/v1/quests/claim", q); code != http.StatusUnprocessableEntity {
		t.Errorf("klaim saat belum selesai harus 422, dapat %d", code)
	}

	// Satu kemenangan atas musuh target menaikkan kemajuan (musuh level 1 hanya tikus/belalang).
	if code, _, d := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil); code != http.StatusCreated {
		t.Fatalf("mulai: %d %s", code, d)
	}
	var last battleResponse
	for j := 0; j < 60; j++ {
		code, resp, d := battleCall(t, ts, cr.Token, "POST", "/v1/battle/action", map[string]string{"action": "attack"})
		if code != http.StatusOK {
			t.Fatalf("aksi: %d %s", code, d)
		}
		last = resp
		if last.Status != game.StatusOngoing {
			break
		}
	}
	if last.Status != game.StatusWon || list()[0].Progress != 1 {
		t.Fatalf("menang harus menaikkan kemajuan: status=%s %+v", last.Status, list()[0])
	}
	if !strings.Contains(strings.Join(last.Log, "|"), "Selamatkan Nenek") {
		t.Errorf("log pertarungan harus menyebut misi: %v", last.Log)
	}

	// Selesaikan misi langsung lewat store (pertarungan ke-5 tergantung level musuh), lalu klaim.
	if _, err := st.Update(t.Context(), cr.Player.ID, func(sess *store.Session) error {
		sess.Player.State.Quests[0].Status = game.QuestDone
		sess.Player.State.Quests[0].Progress = sess.Player.State.Quests[0].Progress + 4
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	done := list()[0]
	if done.Status != game.QuestDone {
		t.Fatalf("misi harus selesai: %+v", done)
	}

	_, me := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	var before game.Player
	_ = json.Unmarshal(me, &before)
	code, r := call("/v1/quests/claim", q)
	if code != http.StatusOK || r.RewardGold != done.RewardGold || r.Player.State.Gold != before.State.Gold+done.RewardGold {
		t.Fatalf("klaim: %d reward=%d gold %d -> %d", code, r.RewardGold, before.State.Gold, r.Player.State.Gold)
	}
	if code, _ := call("/v1/quests/claim", q); code != http.StatusConflict {
		t.Errorf("klaim dua kali harus 409, dapat %d", code)
	}
	if list()[0].Status != game.QuestClaimed {
		t.Error("status akhir harus claimed")
	}
}

func TestSaveRejectsUnknownMapAndOutOfBounds(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Penjelajah")
	save := func(version int, mapID string, x, y int) int {
		st := cr.Player.State
		st.Map, st.X, st.Y = mapID, x, y
		resp, _ := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: version, State: st})
		return resp.StatusCode
	}
	if code := save(1, "neraka", 1, 1); code != http.StatusUnprocessableEntity {
		t.Errorf("peta asing harus 422, dapat %d", code)
	}
	if code := save(1, game.MapDesaAwal, 99, 3); code != http.StatusUnprocessableEntity {
		t.Errorf("di luar peta harus 422, dapat %d", code)
	}
	if code := save(1, game.MapGunungBatu, 99, 1); code != http.StatusUnprocessableEntity {
		t.Errorf("di luar peta gunung harus 422, dapat %d", code)
	}
	if code := save(1, game.MapPerbatasan, 7, 1); code != http.StatusOK {
		t.Errorf("pindah ke perbatasan harus 200, dapat %d", code)
	}
}

func TestBattleEnemyDependsOnMap(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Pemburu")
	st := cr.Player.State
	st.Map, st.X, st.Y = game.MapPerbatasan, 7, 2
	if resp, d := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 1, State: st}); resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan: %d %s", resp.StatusCode, d)
	}
	_, start, d := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil)
	if start.Battle == nil || start.Battle.EnemyID != "goblin" {
		t.Errorf("level 1 di perbatasan harus bertemu goblin: %s", d)
	}
}

func TestBossBattleOnlyAtBossSpot(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Penantang")
	if code, _, _ := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", map[string]bool{"boss": true}); code != http.StatusUnprocessableEntity {
		t.Errorf("minta bos jauh dari singgasana harus 422, dapat %d", code)
	}
	st := cr.Player.State
	st.Map, st.X, st.Y = game.MapGuaBatu, 7, 14
	if resp, d := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 1, State: st}); resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan: %d %s", resp.StatusCode, d)
	}
	code, start, d := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", map[string]bool{"boss": true})
	if code != http.StatusCreated || start.Battle == nil || start.Battle.EnemyID != "raja_goblin" {
		t.Fatalf("bos: %d %s", code, d)
	}
	if code, _, _ := battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", map[string]bool{"boss": true}); code != http.StatusConflict {
		t.Errorf("mulai dua kali harus 409, dapat %d", code)
	}
}

// --- tas, perlengkapan, istirahat ---

func TestInventoryEquipUseRest(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Pemakai")
	call := func(path string, body any) (int, game.Player) {
		resp, data := do(t, "POST", ts.URL+path, cr.Token, body)
		var p game.Player
		_ = json.Unmarshal(data, &p)
		return resp.StatusCode, p
	}
	item := func(id string) map[string]string { return map[string]string{"item": id} }

	if code, _ := call("/v1/inventory/equip", item("pedang_besi")); code != http.StatusUnprocessableEntity {
		t.Errorf("equip barang yang tidak dimiliki harus 422, dapat %d", code)
	}
	if code, _ := call("/v1/inventory/equip", item("naga")); code != http.StatusNotFound {
		t.Errorf("barang asing harus 404, dapat %d", code)
	}
	if code, _ := call("/v1/inventory/use", item("ramuan")); code != http.StatusUnprocessableEntity {
		t.Errorf("ramuan saat HP penuh harus 422, dapat %d", code)
	}
	if code, _ := call("/v1/rest", nil); code != http.StatusUnprocessableEntity {
		t.Errorf("istirahat saat HP penuh harus 422, dapat %d", code)
	}

	// Beri pedang dan luka lewat store (sama seperti hadiah/pertarungan).
	if _, err := st.Update(t.Context(), cr.Player.ID, func(sess *store.Session) error {
		sess.Player.State.AddItem("pedang_besi", 1)
		sess.Player.State.HP = 4
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	code, p := call("/v1/inventory/equip", item("pedang_besi"))
	if code != http.StatusOK || p.State.Equipment.Weapon != "pedang_besi" {
		t.Fatalf("equip: %d %+v", code, p.State.Equipment)
	}
	if code, p := call("/v1/inventory/use", item("ramuan")); code != http.StatusOK || p.State.HP != 4+game.PotionHeal {
		t.Errorf("pakai ramuan: %d hp=%d", code, p.State.HP)
	}
	if code, _ := call("/v1/shop/sell", map[string]any{"item": "pedang_besi", "qty": 1}); code != http.StatusUnprocessableEntity {
		t.Errorf("menjual pedang yang dipakai harus 422, dapat %d", code)
	}
	if code, p := call("/v1/rest", nil); code != http.StatusOK || p.State.HP != p.State.MaxHP {
		t.Errorf("istirahat di desa: %d hp=%d/%d", code, p.State.HP, p.State.MaxHP)
	}
	if code, p := call("/v1/inventory/unequip", map[string]string{"slot": "weapon"}); code != http.StatusOK || p.State.Equipment.Weapon != "" {
		t.Errorf("lepas: %d %+v", code, p.State.Equipment)
	}
	if code, _ := call("/v1/inventory/unequip", map[string]string{"slot": "weapon"}); code != http.StatusUnprocessableEntity {
		t.Errorf("lepas slot kosong harus 422, dapat %d", code)
	}

	// Tidak bisa saat bertarung.
	battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil)
	if code, _ := call("/v1/rest", nil); code != http.StatusConflict {
		t.Errorf("istirahat saat bertarung harus 409, dapat %d", code)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/rest", "", nil); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token harus 401, dapat %d", resp.StatusCode)
	}
}

func TestRestRefusedOutsideVillage(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Pengembara")
	st := cr.Player.State
	st.Map, st.X, st.Y = game.MapPerbatasan, 7, 1
	do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 1, State: st})
	if resp, _ := do(t, "POST", ts.URL+"/v1/rest", cr.Token, nil); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("istirahat di perbatasan harus 422, dapat %d", resp.StatusCode)
	}
}

func TestSaveFinePosition(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Pejalan3D")
	if cr.Player.State.FX != float64(game.SpawnX)+0.5 || cr.Player.State.FZ != float64(game.SpawnY)+0.5 {
		t.Fatalf("pemain baru harus di tengah petak awal: %+v", cr.Player.State)
	}
	st := cr.Player.State
	st.Map, st.X, st.Y, st.FX, st.FZ, st.Yaw = game.MapPerbatasan, 7, 2, 7.3, 2.8, 1.2
	resp, data := do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 1, State: st})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan pose: %d %s", resp.StatusCode, data)
	}
	var saved game.Player
	if err := json.Unmarshal(data, &saved); err != nil {
		t.Fatal(err)
	}
	if saved.State.FX != 7.3 || saved.State.FZ != 2.8 || saved.State.Yaw != 1.2 {
		t.Errorf("posisi halus tidak tersimpan: %+v", saved.State)
	}
	// Posisi halus yang tidak cocok dengan petak diperbaiki ke tengah petak.
	st.FX, st.FZ = 1.1, 1.1
	_, data = do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: 2, State: st})
	var fixed game.Player
	if err := json.Unmarshal(data, &fixed); err != nil {
		t.Fatal(err)
	}
	if fixed.State.FX != 7.5 || fixed.State.FZ != 2.5 {
		t.Errorf("harus di tengah petak: %+v", fixed.State)
	}
}

func TestHeroSelection(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Pemilih")
	if cr.Player.State.Hero != "ksatria" {
		t.Fatalf("pemain baru harus Ksatria: %q", cr.Player.State.Hero)
	}
	resp, data := do(t, "GET", ts.URL+"/v1/heroes", cr.Token, nil)
	var list struct {
		Heroes  []game.HeroDef `json:"heroes"`
		Default string         `json:"default"`
	}
	_ = json.Unmarshal(data, &list)
	if resp.StatusCode != http.StatusOK || len(list.Heroes) != 4 || list.Default != "ksatria" {
		t.Fatalf("daftar pahlawan: %d %s", resp.StatusCode, data)
	}

	resp, data = do(t, "POST", ts.URL+"/v1/players/me/hero", cr.Token, map[string]string{"hero": "pemanah"})
	var p game.Player
	_ = json.Unmarshal(data, &p)
	if resp.StatusCode != http.StatusOK || p.State.Hero != "pemanah" || p.Version <= cr.Player.Version {
		t.Fatalf("ganti pahlawan: %d %s", resp.StatusCode, data)
	}
	// Tersimpan, dan simpan posisi dari klien tidak menimpanya.
	st := p.State
	st.X = 6
	st.Hero = "ksatria"
	do(t, "PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: p.Version, State: st})
	_, data = do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	var me game.Player
	_ = json.Unmarshal(data, &me)
	if me.State.Hero != "pemanah" {
		t.Errorf("klien tidak boleh menimpa pahlawan lewat simpan: %q", me.State.Hero)
	}

	if resp, _ := do(t, "POST", ts.URL+"/v1/players/me/hero", cr.Token, map[string]string{"hero": "naga"}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("pahlawan asing harus 422, dapat %d", resp.StatusCode)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/players/me/hero", "", map[string]string{"hero": "pemanah"}); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("tanpa token harus 401, dapat %d", resp.StatusCode)
	}
	battleCall(t, ts, cr.Token, "POST", "/v1/battle/start", nil)
	if resp, _ := do(t, "POST", ts.URL+"/v1/players/me/hero", cr.Token, map[string]string{"hero": "ksatria"}); resp.StatusCode != http.StatusConflict {
		t.Errorf("ganti pahlawan saat bertarung harus 409, dapat %d", resp.StatusCode)
	}
}
