package api

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

func postJSON(t *testing.T, url string, body any, headers map[string]string) (*http.Response, []byte) {
	t.Helper()
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", url, bytes.NewReader(b))
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	return resp, data
}

func TestRegisterValidation(t *testing.T) {
	ts := newTestServer(t)
	register(t, ts, "Budi")

	cases := []struct {
		name string
		body map[string]string
		want int
	}{
		{"tanpa email", map[string]string{"name": "Citra", "password": testPassword}, 422},
		{"email rusak", map[string]string{"name": "Citra", "email": "citra", "password": testPassword}, 422},
		{"tanpa kata sandi", map[string]string{"name": "Citra", "email": "c@contoh.id"}, 422},
		{"sandi pendek", map[string]string{"name": "Citra", "email": "c@contoh.id", "password": "1234567"}, 422},
		{"sandi sama dengan nama", map[string]string{"name": "Citra_Dewi", "email": "c@contoh.id", "password": "citra_dewi"}, 422},
		{"nama dipakai", map[string]string{"name": "BUDI", "email": "lain@contoh.id", "password": testPassword}, 409},
		{"email dipakai (beda huruf)", map[string]string{"name": "Citra", "email": "BUDI@Contoh.ID", "password": testPassword}, 409},
		{"lolos", map[string]string{"name": "Citra", "email": "citra@contoh.id", "password": testPassword}, 201},
	}
	for _, c := range cases {
		resp, data := postJSON(t, ts.URL+"/v1/players", c.body, nil)
		if resp.StatusCode != c.want {
			t.Errorf("%s: status %d, harapan %d: %s", c.name, resp.StatusCode, c.want, data)
		}
	}
}

func TestRegisterDoesNotLeakSecrets(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Rahasia")
	_ = st
	_, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	for _, secret := range []string{testPassword, "password", "pbkdf2", cr.Token} {
		if strings.Contains(string(data), secret) {
			t.Errorf("respons /me tidak boleh memuat %q: %s", secret, data)
		}
	}
	var p game.Player
	_ = json.Unmarshal(data, &p)
	if p.Email != "rahasia@contoh.id" {
		t.Errorf("email pemilik harus tampil di /me, dapat %q", p.Email)
	}
}

func TestLoginByNameAndEmail(t *testing.T) {
	ts := newTestServer(t)
	reg := register(t, ts, "Petualang")

	for _, login := range []string{"Petualang", "petualang", "PETUALANG@contoh.id", "  petualang  "} {
		resp, data := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": login, "password": testPassword}, nil)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("login %q: status %d: %s", login, resp.StatusCode, data)
		}
		var cr createResponse
		_ = json.Unmarshal(data, &cr)
		if cr.Token == "" || cr.Token == reg.Token || cr.Player.ID != reg.Player.ID {
			t.Fatalf("login %q harus memberi token baru untuk pemain yang sama: %+v", login, cr)
		}
		if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil); resp.StatusCode != http.StatusOK {
			t.Errorf("token hasil login %q harus berlaku, dapat %d", login, resp.StatusCode)
		}
	}
	// Token dari pendaftaran tetap berlaku (HP lain / sesi lain).
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", reg.Token, nil); resp.StatusCode != http.StatusOK {
		t.Errorf("login tidak boleh mencabut token lain, dapat %d", resp.StatusCode)
	}
}

func TestLoginProgressSurvivesRelogin(t *testing.T) {
	ts := newTestServer(t)
	reg := register(t, ts, "Pejuang")
	resp, data := do(t, "PUT", ts.URL+"/v1/players/me/save", reg.Token, map[string]any{
		"version": 1, "state": map[string]any{"map": "desa_awal", "x": 3, "y": 4, "level": 1, "hp": 30, "max_hp": 30},
	})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("simpan: %d %s", resp.StatusCode, data)
	}
	// Token hilang / pindah HP: login ulang mengembalikan progress yang sama.
	_, data = postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Pejuang", "password": testPassword}, nil)
	var cr createResponse
	_ = json.Unmarshal(data, &cr)
	if cr.Player.State.Map != "desa_awal" || cr.Player.State.X != 3 || cr.Player.Version != 2 {
		t.Errorf("progress harus utuh setelah login ulang: %+v", cr.Player)
	}
}

func TestLoginRejectsSameMessageForUnknownAndWrong(t *testing.T) {
	ts := newTestServer(t)
	register(t, ts, "Ada")

	r1, b1 := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Ada", "password": "salah-banget"}, nil)
	r2, b2 := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "TidakAda", "password": "salah-banget"}, nil)
	if r1.StatusCode != 401 || r2.StatusCode != 401 {
		t.Fatalf("harus 401 keduanya, dapat %d dan %d", r1.StatusCode, r2.StatusCode)
	}
	if string(b1) != string(b2) {
		t.Errorf("pesan harus sama agar akun tidak bisa ditebak: %s vs %s", b1, b2)
	}
	for _, body := range []map[string]string{{"login": "", "password": "x"}, {"login": "Ada", "password": ""}} {
		if resp, _ := postJSON(t, ts.URL+"/v1/login", body, nil); resp.StatusCode != 422 {
			t.Errorf("isian kosong harus 422, dapat %d", resp.StatusCode)
		}
	}
}

func TestLoginRateLimit(t *testing.T) {
	ts := newTestServer(t)
	register(t, ts, "Korban")

	for i := 0; i < 5; i++ {
		if resp, _ := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Korban", "password": "tebakan-" + string(rune('a'+i))}, nil); resp.StatusCode != 401 {
			t.Fatalf("tebakan %d harus 401, dapat %d", i, resp.StatusCode)
		}
	}
	// Setelah 5 kegagalan, bahkan kata sandi benar ditolak sementara.
	resp, data := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "korban", "password": testPassword}, nil)
	if resp.StatusCode != http.StatusTooManyRequests || resp.Header.Get("Retry-After") == "" {
		t.Fatalf("harus 429 + Retry-After, dapat %d: %s", resp.StatusCode, data)
	}
	// Nama lain dari alamat yang sama tidak ikut terblokir (batas per nama).
	register(t, ts, "Tetangga")
	if resp, _ := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Tetangga", "password": testPassword}, nil); resp.StatusCode != 200 {
		t.Errorf("akun lain harus tetap bisa login, dapat %d", resp.StatusCode)
	}
}

func TestLoginSuccessResetsFailures(t *testing.T) {
	ts := newTestServer(t)
	register(t, ts, "Lupa")
	for i := 0; i < 4; i++ {
		postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Lupa", "password": "bukan-ini-ya"}, nil)
	}
	if resp, _ := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Lupa", "password": testPassword}, nil); resp.StatusCode != 200 {
		t.Fatalf("login benar sebelum batas harus lolos, dapat %d", resp.StatusCode)
	}
	for i := 0; i < 4; i++ {
		postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Lupa", "password": "bukan-ini-ya"}, nil)
	}
	if resp, _ := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "Lupa", "password": testPassword}, nil); resp.StatusCode != 200 {
		t.Errorf("hitungan gagal harus direset oleh login berhasil, dapat %d", resp.StatusCode)
	}
}

func TestRateLimitIPUsesForwardedHeaderOnlyFromLoopback(t *testing.T) {
	// Tes berjalan dari 127.0.0.1, jadi header X-Forwarded-For dipercaya: dua "klien" berbeda
	// tidak saling memblokir lewat batas IP.
	ts := newTestServer(t)
	for i := 0; i < 20; i++ {
		resp, _ := postJSON(t, ts.URL+"/v1/players", regBody("User"+string(rune('A'+i))), map[string]string{"X-Forwarded-For": "10.0.0.1"})
		if resp.StatusCode != 201 {
			t.Fatalf("daftar ke-%d dari IP A: %d", i, resp.StatusCode)
		}
	}
	if resp, _ := postJSON(t, ts.URL+"/v1/players", regBody("UserZ"), map[string]string{"X-Forwarded-For": "10.0.0.1"}); resp.StatusCode != 429 {
		t.Errorf("IP A harus kena batas daftar, dapat %d", resp.StatusCode)
	}
	if resp, _ := postJSON(t, ts.URL+"/v1/players", regBody("UserZ"), map[string]string{"X-Forwarded-For": "10.0.0.2"}); resp.StatusCode != 201 {
		t.Errorf("IP B tidak boleh ikut terblokir, dapat %d", resp.StatusCode)
	}
}

func TestLogoutRevokesOnlyThatToken(t *testing.T) {
	ts := newTestServer(t)
	hp1 := register(t, ts, "DuaHP")
	_, data := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": "DuaHP", "password": testPassword}, nil)
	var hp2 createResponse
	_ = json.Unmarshal(data, &hp2)

	if resp, _ := do(t, "POST", ts.URL+"/v1/logout", hp1.Token, nil); resp.StatusCode != http.StatusNoContent {
		t.Fatalf("logout harus 204, dapat %d", resp.StatusCode)
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", hp1.Token, nil); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("token yang di-logout harus 401, dapat %d", resp.StatusCode)
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", hp2.Token, nil); resp.StatusCode != http.StatusOK {
		t.Errorf("token HP lain harus tetap hidup, dapat %d", resp.StatusCode)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/logout", "", nil); resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("logout tanpa token harus 401, dapat %d", resp.StatusCode)
	}
}
