package api

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/auth"
	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// Uji keamanan server (roadmap no. 221-223, 228, 234, 238).

func loginToken(t *testing.T, ts *httptest.Server, login, password string) (int, string) {
	t.Helper()
	resp, data := do(t, "POST", ts.URL+"/v1/login", "", map[string]string{"login": login, "password": password})
	var cr createResponse
	_ = json.Unmarshal(data, &cr)
	return resp.StatusCode, cr.Token
}

func TestSessionsAndLogoutOthers(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Ganda")
	_, tok2 := loginToken(t, ts, "Ganda", testPassword)
	resp, data := do(t, "GET", ts.URL+"/v1/sessions", cr.Token, nil)
	var list struct {
		Sessions []store.SessionInfo `json:"sessions"`
	}
	_ = json.Unmarshal(data, &list)
	if resp.StatusCode != http.StatusOK || len(list.Sessions) != 2 {
		t.Fatalf("dua sesi: %d %s", resp.StatusCode, data)
	}
	resp, data = do(t, "POST", ts.URL+"/v1/logout/others", cr.Token, nil)
	if resp.StatusCode != http.StatusOK || !strings.Contains(string(data), `"revoked":1`) {
		t.Fatalf("keluar dari perangkat lain: %d %s", resp.StatusCode, data)
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", tok2, nil); resp.StatusCode != http.StatusUnauthorized {
		t.Fatal("token perangkat lain harus tercabut")
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil); resp.StatusCode != http.StatusOK {
		t.Fatal("token sendiri tetap berlaku")
	}
}

func TestChangePassword(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Pengganti")
	_, other := loginToken(t, ts, "Pengganti", testPassword)
	if resp, _ := do(t, "POST", ts.URL+"/v1/players/me/password", cr.Token, map[string]string{"old": "salah-sekali", "new": "sandi-baru-123"}); resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("kata sandi lama salah harus 401: %d", resp.StatusCode)
	}
	if resp, _ := do(t, "POST", ts.URL+"/v1/players/me/password", cr.Token, map[string]string{"old": testPassword, "new": "pendek"}); resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("sandi baru terlalu pendek harus 422: %d", resp.StatusCode)
	}
	if resp, d := do(t, "POST", ts.URL+"/v1/players/me/password", cr.Token, map[string]string{"old": testPassword, "new": "sandi-baru-123"}); resp.StatusCode != http.StatusNoContent {
		t.Fatalf("ganti sandi: %d %s", resp.StatusCode, d)
	}
	if code, _ := loginToken(t, ts, "Pengganti", testPassword); code != http.StatusUnauthorized {
		t.Fatal("sandi lama tidak berlaku lagi")
	}
	if code, _ := loginToken(t, ts, "Pengganti", "sandi-baru-123"); code != http.StatusOK {
		t.Fatal("sandi baru berlaku")
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", other, nil); resp.StatusCode != http.StatusUnauthorized {
		t.Fatal("ganti sandi mencabut sesi perangkat lain")
	}
}

func TestExpiredSessionMessage(t *testing.T) {
	st, err := store.Open(t.TempDir() + "/e.db")
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	now := time.Now()
	clock := func() time.Time { return now }
	ts := httptest.NewServer(NewWithClock(st, slog.New(slog.NewTextHandler(io.Discard, nil)), testInfo, game.RandomSource{}, clock))
	defer ts.Close()
	cr := register(t, ts, "Lupa_Main")
	now = now.Add(store.SessionIdle + time.Hour)
	resp, data := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	if resp.StatusCode != http.StatusUnauthorized || !strings.Contains(string(data), "kedaluwarsa") {
		t.Fatalf("sesi lama: %d %s", resp.StatusCode, data)
	}
}

func TestRehashOldPasswordOnLogin(t *testing.T) {
	ts, st := newTestServerWithStore(t)
	cr := register(t, ts, "Kuno")
	old := auth.Iterations
	auth.Iterations = 500
	weak, _ := auth.Hash(testPassword)
	auth.Iterations = old
	if err := st.SetPassword(t.Context(), cr.Player.ID, weak, ""); err != nil {
		t.Fatal(err)
	}
	if code, _ := loginToken(t, ts, "Kuno", testPassword); code != http.StatusOK {
		t.Fatal("masuk dengan hash lama")
	}
	h, _ := st.PasswordHash(t.Context(), cr.Player.ID)
	if auth.NeedsRehash(h) || !auth.Verify(testPassword, h) {
		t.Fatalf("hash harus diperbarui ke putaran sekarang: %s", h[:20])
	}
}

func TestSecurityInputs(t *testing.T) {
	ts := newTestServer(t)
	cr := register(t, ts, "Aman")
	// Nama berbau injeksi SQL ditolak aturan nama; login dengan injeksi gagal biasa (401), tidak membocorkan.
	for _, bad := range []string{"x' OR '1'='1", "Robert'); DROP TABLE players;--", "<script>", "a"} {
		resp, _ := do(t, "POST", ts.URL+"/v1/players", "", map[string]string{"name": bad, "email": "x@y.id", "password": testPassword})
		if resp.StatusCode != http.StatusUnprocessableEntity && resp.StatusCode != http.StatusTooManyRequests {
			t.Errorf("nama %q harus ditolak: %d", bad, resp.StatusCode)
		}
	}
	if code, _ := loginToken(t, ts, "' OR 1=1 --", "apa-saja-123"); code != http.StatusUnauthorized {
		t.Errorf("login injeksi harus 401: %d", code)
	}
	if resp, _ := do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil); resp.StatusCode != http.StatusOK {
		t.Fatal("tabel pemain masih utuh")
	}
	// Token palsu, diubah, terlalu panjang, atau header salah bentuk.
	for name, h := range map[string]string{
		"palsu":   "Bearer " + strings.Repeat("a", 64),
		"diubah":  "Bearer " + cr.Token[:len(cr.Token)-1] + "x",
		"panjang": "Bearer " + strings.Repeat("b", 5000),
		"tanpa":   cr.Token,
		"basic":   "Basic " + cr.Token,
		"kosong":  "Bearer ",
	} {
		req, _ := http.NewRequest("GET", ts.URL+"/v1/players/me", nil)
		req.Header.Set("Authorization", h)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("token %s harus 401: %d", name, resp.StatusCode)
		}
	}
	// Badan permintaan raksasa ditolak tanpa membuat server kehabisan memori.
	big := bytes.Repeat([]byte("a"), 200<<10)
	req, _ := http.NewRequest("POST", ts.URL+"/v1/bank/deposit", bytes.NewReader(append([]byte(`{"amount":`), big...)))
	req.Header.Set("Authorization", "Bearer "+cr.Token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("badan 200 KiB harus 400: %d", resp.StatusCode)
	}
	// Kolom tak dikenal (mis. mencoba menyelipkan emas) ditolak.
	if resp, _ := do(t, "POST", ts.URL+"/v1/bank/deposit", cr.Token, map[string]any{"amount": 1, "gold": 99999}); resp.StatusCode != http.StatusBadRequest {
		t.Errorf("kolom asing harus 400: %d", resp.StatusCode)
	}
	// Jalur tak dikenal dijawab JSON.
	resp2, data := do(t, "GET", ts.URL+"/v1/rahasia/admin", cr.Token, nil)
	if resp2.StatusCode != http.StatusNotFound || !strings.Contains(string(data), `"error"`) {
		t.Errorf("jalur asing: %d %s", resp2.StatusCode, data)
	}
}

func TestClientIPNotSpoofable(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "203.0.113.9:5555"
	r.Header.Set("X-Forwarded-For", "1.2.3.4")
	if ip := clientIP(r); ip != "203.0.113.9" {
		t.Errorf("header dari luar tidak dipercaya: %s", ip)
	}
	r.RemoteAddr = "127.0.0.1:5555"
	if ip := clientIP(r); ip != "1.2.3.4" {
		t.Errorf("proxy lokal dipercaya: %s", ip)
	}
}

func TestPanicRecovered(t *testing.T) {
	var buf bytes.Buffer
	s := &Server{log: slog.New(slog.NewTextHandler(&buf, nil))}
	h := s.recoverPanic(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { panic("uji") }))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/x", nil))
	if rec.Code != http.StatusInternalServerError || !strings.Contains(rec.Body.String(), "kesalahan internal") || !strings.Contains(buf.String(), "panic") {
		t.Fatalf("panic harus jadi 500 JSON dan tercatat: %d %s", rec.Code, rec.Body.String())
	}
}

func TestRequestLogHasPlayerAndLevel(t *testing.T) {
	st, err := store.Open(t.TempDir() + "/l.db")
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	var buf bytes.Buffer
	ts := httptest.NewServer(New(st, slog.New(slog.NewTextHandler(&buf, nil)), testInfo))
	defer ts.Close()
	cr := register(t, ts, "Tercatat")
	do(t, "GET", ts.URL+"/v1/players/me", cr.Token, nil)
	do(t, "GET", ts.URL+"/v1/players/me", "salah", nil)
	out := buf.String()
	if !strings.Contains(out, "player="+cr.Player.ID) || !strings.Contains(out, "level=WARN") || !strings.Contains(out, "ip=127.0.0.1") {
		t.Fatalf("catatan permintaan: %s", out)
	}
}
