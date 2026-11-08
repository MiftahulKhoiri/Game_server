package api

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func writePatch(t *testing.T, dir string, p PatchInfo, body string) {
	t.Helper()
	if p.ID != "" {
		if err := os.WriteFile(filepath.Join(dir, p.ID+".pck"), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	raw, _ := json.Marshal(p)
	if err := os.WriteFile(filepath.Join(dir, patchManifest), raw, 0o644); err != nil {
		t.Fatal(err)
	}
}

func getPatch(t *testing.T, h http.Handler, query string) PatchInfo {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/patch"+query, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /v1/patch%s = %d", query, rec.Code)
	}
	var p PatchInfo
	if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestPatchManifestSelection(t *testing.T) {
	dir := t.TempDir()
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusTeapot) })
	h := WithPatches(dir, next)

	if p := getPatch(t, h, "?apk=0.47.3"); p.ID != "" {
		t.Errorf("tanpa manifes harus kosong: %+v", p)
	}
	writePatch(t, dir, PatchInfo{ID: "p1", SHA256: "abc", Size: 5, Version: "0.47.5", MinAPK: "0.47.3"}, "12345")
	if p := getPatch(t, h, "?apk=0.47.3"); p.ID != "p1" || p.URL != "/v1/patch/p1.pck" || p.SHA256 != "abc" {
		t.Errorf("patch cocok untuk APK 0.47.3: %+v", p)
	}
	if p := getPatch(t, h, "?apk=0.47.5"); p.ID != "p1" {
		t.Errorf("APK sama dengan versi patch harus dapat: %+v", p)
	}
	if p := getPatch(t, h, "?apk=0.47.2"); p.ID != "" {
		t.Errorf("APK di bawah min_apk tidak boleh dapat: %+v", p)
	}
	if p := getPatch(t, h, "?apk=0.48.0"); p.ID != "" {
		t.Errorf("APK lebih baru dari patch tidak boleh dapat: %+v", p)
	}
	if p := getPatch(t, h, "?apk=ngawur"); p.ID != "" {
		t.Errorf("versi tidak sah harus ditolak: %+v", p)
	}
	if p := getPatch(t, h, ""); p.ID != "p1" {
		t.Errorf("tanpa apk = tanpa pemeriksaan versi: %+v", p)
	}
	// Berkas hilang = tidak ada patch.
	if err := os.Remove(filepath.Join(dir, "p1.pck")); err != nil {
		t.Fatal(err)
	}
	if p := getPatch(t, h, "?apk=0.47.3"); p.ID != "" {
		t.Errorf("berkas hilang harus kosong: %+v", p)
	}
	// Id berbahaya ditolak.
	writePatch(t, dir, PatchInfo{ID: "../rahasia"}, "")
	if p := getPatch(t, h, ""); p.ID != "" {
		t.Errorf("id tidak sah harus ditolak: %+v", p)
	}
	// Fitur mati bila dir kosong.
	if p := getPatch(t, WithPatches("", next), ""); p.ID != "" {
		t.Errorf("tanpa folder harus kosong: %+v", p)
	}
}

func TestPatchDownloadAndPassThrough(t *testing.T) {
	dir := t.TempDir()
	h := WithPatches(dir, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusTeapot) }))
	writePatch(t, dir, PatchInfo{ID: "20260101-abc"}, "ISI-PATCH")
	ts := httptest.NewServer(h)
	defer ts.Close()

	resp, err := http.Get(ts.URL + "/v1/patch/20260101-abc.pck")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || string(body) != "ISI-PATCH" {
		t.Errorf("unduh: %d %q", resp.StatusCode, body)
	}
	for _, bad := range []string{"/v1/patch/latest.json", "/v1/patch/..%2Fx.pck", "/v1/patch/tidak-ada.pck"} {
		resp, err := http.Get(ts.URL + bad)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound {
			t.Errorf("%s harus 404, dapat %d", bad, resp.StatusCode)
		}
	}
	resp, err = http.Get(ts.URL + "/v1/lain")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusTeapot {
		t.Errorf("jalur lain harus diteruskan ke handler utama, dapat %d", resp.StatusCode)
	}
}
