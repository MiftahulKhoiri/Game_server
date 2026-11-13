package api

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

// Patch konten klien (sejak v0.47.3): berkas .pck berisi skrip dan scene terbaru yang dimuat klien saat
// aplikasi dibuka, tanpa memasang APK baru. Berkas dibuat oleh scripts/build-patch.sh di folder patch server:
//
//	<dir>/latest.json   manifes patch yang sedang berlaku (hapus / kosongkan = tidak ada patch)
//	<dir>/<id>.pck      isi patch
//
// Endpoint (tanpa login):
//
//	GET /v1/patch?apk=0.47.3   manifes untuk APK itu, atau {"id":""} bila tidak ada patch yang cocok
//	GET /v1/patch/<id>.pck     unduh berkas patch
const patchManifest = "latest.json"

var patchFileRe = regexp.MustCompile(`^[A-Za-z0-9._-]{1,80}\.pck$`)

// PatchInfo adalah isi latest.json dan jawaban GET /v1/patch.
type PatchInfo struct {
	ID      string `json:"id"`                // pengenal unik patch (nama berkas tanpa .pck); "" = tidak ada patch
	SHA256  string `json:"sha256,omitempty"`  // sidik berkas, diperiksa klien setelah mengunduh
	Size    int64  `json:"size,omitempty"`    // ukuran berkas (byte)
	Version string `json:"version,omitempty"` // versi aplikasi (config/version) saat patch dibuat; APK yang lebih baru darinya tidak memakai patch ini
	MinAPK  string `json:"min_apk,omitempty"` // APK terlama yang boleh memakai patch (aset dan pengaturan sama)
	Built   string `json:"built,omitempty"`   // waktu pembuatan (teks bebas)
	URL     string `json:"url,omitempty"`     // alamat unduh relatif terhadap server
}

// WithPatches menambahkan endpoint patch di depan handler utama. dir kosong = fitur mati (selalu "tidak ada patch").
// Server produksi memakai opsi PatchDir di New supaya endpoint patch ikut middleware log, recover, dan
// pembatas laju; fungsi ini dipertahankan untuk pemakai lama.
func WithPatches(dir string, next http.Handler) http.Handler {
	mux := http.NewServeMux()
	registerPatches(mux, dir)
	mux.Handle("/", next)
	return mux
}

// registerPatches memasang GET /v1/patch dan GET /v1/patch/{name} pada mux.
func registerPatches(mux *http.ServeMux, dir string) {
	mux.HandleFunc("GET /v1/patch", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, patchFor(dir, r.URL.Query().Get("apk")))
	})
	mux.HandleFunc("GET /v1/patch/{name}", func(w http.ResponseWriter, r *http.Request) {
		name := r.PathValue("name")
		if dir == "" || !patchFileRe.MatchString(name) {
			writeError(w, http.StatusNotFound, "patch tidak ditemukan")
			return
		}
		// Unduhan bisa lebih lama dari batas tulis umum server (15 d), terutama lewat data seluler.
		_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(3 * time.Minute))
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		http.ServeFile(w, r, filepath.Join(dir, name))
	})
}

// patchFor memilih patch untuk APK `apk` (kosong = tanpa pemeriksaan versi).
func patchFor(dir, apk string) PatchInfo {
	none := PatchInfo{}
	if dir == "" {
		return none
	}
	raw, err := os.ReadFile(filepath.Join(dir, patchManifest))
	if err != nil {
		return none
	}
	var p PatchInfo
	if json.Unmarshal(raw, &p) != nil || p.ID == "" || !patchFileRe.MatchString(p.ID+".pck") {
		return none
	}
	if st, err := os.Stat(filepath.Join(dir, p.ID+".pck")); err != nil || st.IsDir() {
		return none
	}
	if apk != "" {
		// APK terlalu tua (aset berbeda) atau lebih baru dari patch (isi patch akan menimpa kode yang lebih baru): tidak dipakai.
		if p.MinAPK != "" {
			if c, err := version.Compare(apk, p.MinAPK); err != nil || c < 0 {
				return none
			}
		}
		if p.Version != "" {
			if c, err := version.Compare(apk, p.Version); err != nil || c > 0 {
				return none
			}
		}
	}
	p.URL = "/v1/patch/" + p.ID + ".pck"
	return p
}
