package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// newCatalogServer: server penuh (dengan middleware) + folder katalog berisi satu game unduhan.
func newCatalogServer(t *testing.T, pck []byte) (*httptest.Server, string) {
	t.Helper()
	dir := t.TempDir()
	sum := sha256.Sum256(pck)
	man := map[string]any{
		"id": "education_sd", "name": "Game Pembelajaran SD", "version": "1.0.0", "type": "download",
		"entry_scene": "res://games/education_sd/main.tscn", "package": "education_sd-1.0.0.pck",
		"size": len(pck), "sha256": hex.EncodeToString(sum[:]),
		"min_launcher_version": "0.84.0", "min_engine_version": "4.7.2",
	}
	raw, _ := json.Marshal(man)
	gd := filepath.Join(dir, "education_sd")
	if err := os.MkdirAll(gd, 0o755); err != nil {
		t.Fatal(err)
	}
	write := func(p string, b []byte) {
		if err := os.WriteFile(p, b, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(gd, "manifest.json"), raw)
	write(filepath.Join(gd, "manifest.sig"), []byte("TUFOSUZFU1Q="))
	write(filepath.Join(gd, "education_sd-1.0.0.pck"), pck)
	write(filepath.Join(dir, "catalog.json"), []byte(`{"catalog_version":1,"games":[`+string(raw)+`]}`))
	write(filepath.Join(dir, "catalog.sig"), []byte("S0FUQUxPRw=="))

	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	ts := httptest.NewServer(New(st, log, testInfo, CatalogDir(dir)))
	t.Cleanup(ts.Close)
	return ts, dir
}

func TestGameCatalogEndpoints(t *testing.T) {
	pck := []byte(strings.Repeat("GDPC-paket-uji-", 1000))
	ts, dir := newCatalogServer(t, pck)

	resp, body := do(t, "GET", ts.URL+"/v1/games", "", nil)
	want, _ := os.ReadFile(filepath.Join(dir, "catalog.json"))
	if resp.StatusCode != 200 || string(body) != string(want) {
		t.Fatalf("katalog harus byte persis: %d %s", resp.StatusCode, body)
	}
	resp, body = do(t, "GET", ts.URL+"/v1/games/catalog.sig", "", nil)
	if resp.StatusCode != 200 || string(body) != "S0FUQUxPRw==" {
		t.Fatalf("tanda tangan katalog: %d %s", resp.StatusCode, body)
	}
	resp, body = do(t, "GET", ts.URL+"/v1/games/education_sd", "", nil)
	if resp.StatusCode != 200 || !strings.Contains(string(body), `"version":"1.0.0"`) {
		t.Fatalf("entri: %d %s", resp.StatusCode, body)
	}
	resp, body = do(t, "GET", ts.URL+"/v1/games/education_sd/version", "", nil)
	if resp.StatusCode != 200 || !strings.Contains(string(body), `"version":"1.0.0"`) {
		t.Fatalf("versi: %d %s", resp.StatusCode, body)
	}
	resp, body = do(t, "GET", ts.URL+"/v1/games/education_sd/manifest", "", nil)
	wantMan, _ := os.ReadFile(filepath.Join(dir, "education_sd", "manifest.json"))
	if resp.StatusCode != 200 || string(body) != string(wantMan) {
		t.Fatalf("manifest harus byte persis: %d", resp.StatusCode)
	}
	resp, body = do(t, "GET", ts.URL+"/v1/games/education_sd/manifest.sig", "", nil)
	if resp.StatusCode != 200 || string(body) != "TUFOSUZFU1Q=" {
		t.Fatalf("tanda tangan manifest: %d %s", resp.StatusCode, body)
	}
	resp, body = do(t, "GET", ts.URL+"/v1/games/education_sd/download", "", nil)
	if resp.StatusCode != 200 || string(body) != string(pck) {
		t.Fatalf("unduh: %d (%d byte)", resp.StatusCode, len(body))
	}
	for _, p := range []string{"/v1/games/tidak_ada", "/v1/games/tidak_ada/manifest", "/v1/games/tidak_ada/download",
		"/v1/games/..%2Fetc/download", "/v1/games/Education/manifest"} {
		resp, _ := do(t, "GET", ts.URL+p, "", nil)
		if resp.StatusCode != http.StatusNotFound {
			t.Errorf("%s harus 404, dapat %d", p, resp.StatusCode)
		}
	}
}

// Unduhan yang putus dilanjutkan dengan HTTP Range (206) dan isinya menyambung tepat.
func TestGameDownloadResumeRange(t *testing.T) {
	pck := make([]byte, 50_000)
	for i := range pck {
		pck[i] = byte(i * 7)
	}
	ts, _ := newCatalogServer(t, pck)
	req, _ := http.NewRequest("GET", ts.URL+"/v1/games/education_sd/download", nil)
	req.Header.Set("Range", "bytes=20000-")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	rest, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("Range harus 206, dapat %d", resp.StatusCode)
	}
	joined := append(append([]byte{}, pck[:20000]...), rest...)
	a, b := sha256.Sum256(joined), sha256.Sum256(pck)
	if a != b {
		t.Fatal("hasil sambungan unduhan tidak sama dengan paket")
	}
}

// Paket yang ukurannya tidak sama dengan manifest (mis. masih disalin) tidak dilayani.
func TestGameDownloadRefusesSizeMismatch(t *testing.T) {
	ts, dir := newCatalogServer(t, []byte("isi-paket"))
	if err := os.WriteFile(filepath.Join(dir, "education_sd", "education_sd-1.0.0.pck"), []byte("isi-paket-yang-lebih-panjang"), 0o644); err != nil {
		t.Fatal(err)
	}
	resp, _ := do(t, "GET", ts.URL+"/v1/games/education_sd/download", "", nil)
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("paket tidak cocok harus 503, dapat %d", resp.StatusCode)
	}
}

func TestGameCatalogEmpty(t *testing.T) {
	ts := newTestServer(t) // tanpa CatalogDir
	resp, _ := do(t, "GET", ts.URL+"/v1/games", "", nil)
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("katalog kosong harus 404, dapat %d", resp.StatusCode)
	}
}

func TestGameProgressPerGame(t *testing.T) {
	ts, _ := newCatalogServer(t, []byte("x"))
	a := register(t, ts, "Murid")
	b := register(t, ts, "Teman")

	resp, _ := do(t, "GET", ts.URL+"/v1/games/education_sd/progress", "", nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("progres tanpa login harus 401, dapat %d", resp.StatusCode)
	}
	resp, body := do(t, "GET", ts.URL+"/v1/games/education_sd/progress", a.Token, nil)
	if resp.StatusCode != 200 || !strings.Contains(string(body), `"data":{}`) {
		t.Fatalf("progres kosong: %d %s", resp.StatusCode, body)
	}
	save := map[string]any{"schema_version": 1, "updated_at": "2026-11-15T10:00:00",
		"data": map[string]any{"levels": map[string]any{"matematika/k12": map[string]any{"best": 90}}}}
	resp, body = do(t, "POST", ts.URL+"/v1/games/education_sd/progress", a.Token, save)
	if resp.StatusCode != 200 || !strings.Contains(string(body), `"revision":1`) {
		t.Fatalf("simpan: %d %s", resp.StatusCode, body)
	}
	resp, body = do(t, "POST", ts.URL+"/v1/games/education_sd/progress", a.Token, save)
	if resp.StatusCode != 200 || !strings.Contains(string(body), `"revision":2`) {
		t.Fatalf("simpan kedua: %d %s", resp.StatusCode, body)
	}
	// Game lain dan pemain lain tidak ikut berubah.
	_, body = do(t, "GET", ts.URL+"/v1/games/education_smp/progress", a.Token, nil)
	if !strings.Contains(string(body), `"data":{}`) {
		t.Fatalf("progres SMP harus kosong: %s", body)
	}
	_, body = do(t, "GET", ts.URL+"/v1/games/education_sd/progress", b.Token, nil)
	if !strings.Contains(string(body), `"data":{}`) {
		t.Fatalf("progres pemain lain harus kosong: %s", body)
	}
	_, body = do(t, "GET", ts.URL+"/v1/games/education_sd/progress", a.Token, nil)
	if !strings.Contains(string(body), `"best":90`) {
		t.Fatalf("progres tersimpan hilang: %s", body)
	}
	bad := []map[string]any{
		{"schema_version": 0, "data": map[string]any{}},
		{"schema_version": 1, "data": []int{1}},
		{"schema_version": 1, "data": "teks"},
		{"schema_version": 1},
	}
	for _, in := range bad {
		resp, _ := do(t, "POST", ts.URL+"/v1/games/education_sd/progress", a.Token, in)
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("%v harus 400, dapat %d", in, resp.StatusCode)
		}
	}
	for _, id := range []string{"adventure", "Bad"} {
		resp, _ := do(t, "POST", ts.URL+"/v1/games/"+id+"/progress", a.Token, save)
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("progres %s harus 400, dapat %d", id, resp.StatusCode)
		}
	}
}

func TestGameIcon(t *testing.T) {
	ts, dir := newCatalogServer(t, []byte("pck"))
	resp, err := http.Get(ts.URL + "/v1/games/education_sd/icon")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("tanpa icon.png harus 404, dapat %d", resp.StatusCode)
	}
	png := append([]byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}, []byte("isi-ikon")...)
	if err := os.WriteFile(filepath.Join(dir, "education_sd", "icon.png"), png, 0o644); err != nil {
		t.Fatal(err)
	}
	resp, err = http.Get(ts.URL + "/v1/games/education_sd/icon")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || resp.Header.Get("Content-Type") != "image/png" || string(body) != string(png) {
		t.Fatalf("ikon: status %d, tipe %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	if err := os.WriteFile(filepath.Join(dir, "education_sd", "icon.png"), []byte("bukan png"), 0o644); err != nil {
		t.Fatal(err)
	}
	resp, _ = http.Get(ts.URL + "/v1/games/education_sd/icon")
	resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("berkas bukan PNG harus ditolak, dapat %d", resp.StatusCode)
	}
	resp, _ = http.Get(ts.URL + "/v1/games/..%2Fetc/icon")
	resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		t.Fatal("id tidak sah tidak boleh dilayani")
	}
}
