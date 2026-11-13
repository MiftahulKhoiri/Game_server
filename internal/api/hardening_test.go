package api

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Pengujian audit keamanan v0.77.0: gerbang versi klien dan pembaca JSON.

func TestClientVersionGate(t *testing.T) {
	ts := newTestServer(t) // MinClient 0.2.0
	cases := []struct {
		name, header string
		want         int
	}{
		{"versi sama dengan minimum", "0.2.0", http.StatusOK},
		{"versi terbaru", "0.3.0", http.StatusOK},
		{"versi jauh lebih baru", "10.0.0", http.StatusOK},
		{"berawalan v", "v0.2.1", http.StatusOK},
		{"header kosong (klien lama)", "", http.StatusOK},
		{"terlalu lama", "0.1.9", http.StatusUpgradeRequired},
		{"format rusak", "0.2", http.StatusBadRequest},
		{"string acak", "halo-dunia", http.StatusBadRequest},
		{"angka negatif", "-1.0.0", http.StatusBadRequest},
		{"bagian negatif", "0.-2.0", http.StatusBadRequest},
		{"empat bagian", "0.2.0.1", http.StatusBadRequest},
		{"pra-rilis", "0.2.0-beta", http.StatusBadRequest},
		{"angka meluap", "99999999999999999999.0.0", http.StatusBadRequest},
		{"terlalu panjang", "0.2." + strings.Repeat("0", 40), http.StatusBadRequest},
		{"spasi di tengah", "0. 2.0", http.StatusBadRequest},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			resp, data := doWithVersion(t, "GET", ts.URL+"/v1/time", c.header, nil)
			if resp.StatusCode != c.want {
				t.Fatalf("X-Client-Version %q: status %d, mau %d: %s", c.header, resp.StatusCode, c.want, data)
			}
		})
	}
	// Pemeriksaan kesehatan dan info versi tetap terbuka untuk header apa pun.
	for _, path := range []string{"/healthz", "/v1/version"} {
		for _, h := range []string{"0.0.1", "rusak"} {
			if resp, _ := doWithVersion(t, "GET", ts.URL+path, h, nil); resp.StatusCode != http.StatusOK {
				t.Errorf("%s dengan versi %q: %d", path, h, resp.StatusCode)
			}
		}
	}
}

func TestDecodeStrictJSON(t *testing.T) {
	type body struct {
		Item string `json:"item"`
	}
	run := func(raw string) (int, string) {
		var got body
		rec := httptest.NewRecorder()
		req := httptest.NewRequest("POST", "/", strings.NewReader(raw))
		if decode(rec, req, &got) {
			return http.StatusOK, got.Item
		}
		return rec.Code, ""
	}
	cases := []struct {
		name, raw string
		want      int
	}{
		{"JSON sah", `{"item":"ramuan"}`, http.StatusOK},
		{"JSON sah berspasi di belakang", "{\"item\":\"ramuan\"}\n  \t", http.StatusOK},
		{"objek kosong", `{}`, http.StatusOK},
		{"badan kosong", ``, http.StatusBadRequest},
		{"JSON rusak", `{"item":}`, http.StatusBadRequest},
		{"terpotong", `{"item":"ram`, http.StatusBadRequest},
		{"dua objek", `{"item":"a"}{"item":"b"}`, http.StatusBadRequest},
		{"karakter sisa", `{"item":"a"}x`, http.StatusBadRequest},
		{"angka sisa", `{"item":"a"} 1`, http.StatusBadRequest},
		{"kolom tidak dikenal", `{"item":"a","gold":99999}`, http.StatusBadRequest},
		{"bukan objek", `["item"]`, http.StatusBadRequest},
		{"terlalu besar", `{"item":"` + strings.Repeat("a", maxBodyBytes+10) + `"}`, http.StatusRequestEntityTooLarge},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, item := run(c.raw)
			if code != c.want {
				t.Fatalf("status %d, mau %d", code, c.want)
			}
			if c.want == http.StatusOK && c.raw != `{}` && item != "ramuan" && item != "a" {
				t.Errorf("isi tidak terbaca: %q", item)
			}
		})
	}
}

// Lewat server sungguhan: permintaan dengan dua objek JSON tidak boleh menjalankan aksi apa pun.
func TestTrailingJSONRejectedEndToEnd(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Ganda")
	raw := `{"amount":1}{"amount":1}`
	req, _ := http.NewRequest("POST", ts.URL+"/v1/bank/deposit", bytes.NewBufferString(raw))
	req.Header.Set("Authorization", "Bearer "+cr.Token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("dua objek: status %d: %s", resp.StatusCode, data)
	}
	var e map[string]string
	if json.Unmarshal(data, &e) != nil || e["error"] == "" {
		t.Errorf("jawaban galat harus JSON {error}: %s", data)
	}
}

// Satu akun bisa dimasuki lewat nama atau email: berganti bentuk isian tidak menambah jatah tebakan.
func TestLoginLimitPerAccountAcrossNameAndEmail(t *testing.T) {
	ts := newTestServer(t)
	register(t, ts, "Sasaran")
	try := func(login, pw string) int {
		resp, _ := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": login, "password": pw}, nil)
		return resp.StatusCode
	}
	forms := []string{"Sasaran", "sasaran@contoh.id", "SASARAN", "  sasaran  ", "SaSaRaN@Contoh.ID"}
	got429 := false
	for i := range 12 {
		if code := try(forms[i%len(forms)], "salah-sekali-1"); code == http.StatusTooManyRequests {
			got429 = true
			break
		}
	}
	if !got429 {
		t.Fatal("berganti nama/email/huruf besar harus tetap terkena batas per akun")
	}
	// Bahkan kata sandi yang benar ditolak selama akun diblokir.
	if code := try("sasaran@contoh.id", testPassword); code != http.StatusTooManyRequests {
		t.Errorf("selama blokir: status %d, mau 429", code)
	}
}

func TestLoginOverlongInputDoesNotGrowLimiter(t *testing.T) {
	ts := newTestServer(t)
	long := strings.Repeat("x", 4000)
	resp, _ := postJSON(t, ts.URL+"/v1/login", map[string]string{"login": long, "password": "apa-saja-1"}, nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("isian panjang: %d", resp.StatusCode)
	}
}

func TestClientIPTrustedProxies(t *testing.T) {
	old := TrustedProxies
	t.Cleanup(func() { TrustedProxies = old })
	req := func(remote string, h map[string]string) *http.Request {
		r := httptest.NewRequest("GET", "/", nil)
		r.RemoteAddr = remote
		for k, v := range h {
			r.Header.Set(k, v)
		}
		return r
	}
	cases := []struct {
		name, remote string
		h            map[string]string
		want         string
	}{
		{"langsung dari luar: header diabaikan", "203.0.113.9:5000", map[string]string{"X-Forwarded-For": "1.2.3.4", "CF-Connecting-IP": "1.2.3.4"}, "203.0.113.9"},
		{"proxy lokal + Cloudflare", "127.0.0.1:5000", map[string]string{"CF-Connecting-IP": "198.51.100.7"}, "198.51.100.7"},
		{"proxy lokal + XFF", "127.0.0.1:5000", map[string]string{"X-Forwarded-For": "198.51.100.7"}, "198.51.100.7"},
		{"XFF dipalsukan di kiri", "127.0.0.1:5000", map[string]string{"X-Forwarded-For": "6.6.6.6, 198.51.100.7"}, "198.51.100.7"},
		{"XFF berujung proxy tepercaya", "127.0.0.1:5000", map[string]string{"X-Forwarded-For": "198.51.100.7, 127.0.0.1"}, "198.51.100.7"},
		{"XFF rusak", "127.0.0.1:5000", map[string]string{"X-Forwarded-For": "bukan-ip"}, "127.0.0.1"},
		{"IPv6 loopback", "[::1]:5000", map[string]string{"X-Forwarded-For": "2001:db8::5"}, "2001:db8::5"},
	}
	for _, c := range cases {
		if got := clientIP(req(c.remote, c.h)); got != c.want {
			t.Errorf("%s: %s, mau %s", c.name, got, c.want)
		}
	}
	// Tanpa proxy tepercaya ("none"), header dari loopback pun diabaikan.
	TrustedProxies = nil
	if got := clientIP(req("127.0.0.1:5000", map[string]string{"X-Forwarded-For": "1.2.3.4"})); got != "127.0.0.1" {
		t.Errorf("tanpa proxy tepercaya: %s", got)
	}
}
