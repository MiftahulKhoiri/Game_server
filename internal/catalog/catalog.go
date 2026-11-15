// Package catalog melayani katalog game platform multi-game (v0.84.0): daftar game unduhan, manifest
// bertanda tangan, dan berkas paket (.pck) untuk launcher Android.
//
// Server TIDAK memegang kunci privat dan tidak menandatangani apa pun. Semua berkas dibuat dan ditandatangani
// oleh scripts/build-game-pack.sh di lingkungan build, lalu ditaruh di folder katalog:
//
//	<dir>/catalog.json            daftar game (byte persis yang ditandatangani)
//	<dir>/catalog.sig             tanda tangan base64 (RSA PKCS#1 v1.5 + SHA-256) atas catalog.json
//	<dir>/<id>/manifest.json      manifest satu game
//	<dir>/<id>/manifest.sig       tanda tangan manifest
//	<dir>/<id>/<package>.pck      berkas paket yang disebut manifest
//
// Klien selalu memeriksa tanda tangan sendiri; pemeriksaan di sini hanya menjaga server agar tidak
// melayani berkas di luar folder katalog atau manifest yang jelas rusak.
package catalog

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
)

var (
	idRe      = regexp.MustCompile(`^[a-z][a-z0-9_]{1,31}$`)
	packageRe = regexp.MustCompile(`^[A-Za-z0-9._-]{1,80}\.pck$`)
	semverRe  = regexp.MustCompile(`^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$`)
	shaRe     = regexp.MustCompile(`^[0-9a-f]{64}$`)

	// ErrNotFound: game atau berkas tidak ada di katalog.
	ErrNotFound = errors.New("catalog: tidak ditemukan")
	// ErrInvalid: berkas katalog/manifest ada tetapi isinya tidak sah.
	ErrInvalid = errors.New("catalog: isi tidak sah")
)

const maxManifestBytes = 64 << 10
const maxCatalogBytes = 4 << 20

// Manifest adalah bagian manifest yang diperiksa server. Kolom lain dibiarkan apa adanya (klien membaca
// berkas aslinya, bukan struct ini).
type Manifest struct {
	ID                 string `json:"id"`
	Name               string `json:"name"`
	Version            string `json:"version"`
	Type               string `json:"type"`
	EntryScene         string `json:"entry_scene"`
	Package            string `json:"package"`
	Size               int64  `json:"size"`
	SHA256             string `json:"sha256"`
	MinLauncherVersion string `json:"min_launcher_version"`
	MinEngineVersion   string `json:"min_engine_version"`
}

// Catalog membaca folder katalog. Berkas dibaca ulang setiap permintaan (katalog kecil), jadi paket baru
// langsung berlaku tanpa restart server.
type Catalog struct {
	Dir string
}

// New membuat Catalog; dir kosong = fitur mati (semua permintaan ErrNotFound).
func New(dir string) *Catalog { return &Catalog{Dir: dir} }

// ValidID melaporkan apakah id game sah (huruf kecil, angka, garis bawah; 2–32 karakter).
func ValidID(id string) bool { return idRe.MatchString(id) }

// CatalogFile mengembalikan byte catalog.json dan tanda tangannya.
func (c *Catalog) CatalogFile() (raw []byte, sig []byte, err error) {
	if c.Dir == "" {
		return nil, nil, ErrNotFound
	}
	raw, err = readLimited(filepath.Join(c.Dir, "catalog.json"), maxCatalogBytes)
	if err != nil {
		return nil, nil, err
	}
	sig, err = readLimited(filepath.Join(c.Dir, "catalog.sig"), 4096)
	if err != nil {
		return nil, nil, err
	}
	return raw, sig, nil
}

// Entries mengembalikan isi catalog.json yang sudah di-parse (untuk GET /v1/games/{id}).
func (c *Catalog) Entries() ([]map[string]any, error) {
	raw, _, err := c.CatalogFile()
	if err != nil {
		return nil, err
	}
	var doc struct {
		Games []map[string]any `json:"games"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("%w: catalog.json: %v", ErrInvalid, err)
	}
	return doc.Games, nil
}

// Entry mengembalikan satu entri katalog.
func (c *Catalog) Entry(id string) (map[string]any, error) {
	if !ValidID(id) {
		return nil, ErrNotFound
	}
	games, err := c.Entries()
	if err != nil {
		return nil, err
	}
	for _, g := range games {
		if g["id"] == id {
			return g, nil
		}
	}
	return nil, ErrNotFound
}

// ManifestFile mengembalikan byte manifest.json, tanda tangannya, dan hasil parse yang sudah diperiksa.
func (c *Catalog) ManifestFile(id string) (raw, sig []byte, m Manifest, err error) {
	if c.Dir == "" || !ValidID(id) {
		return nil, nil, m, ErrNotFound
	}
	dir := filepath.Join(c.Dir, id)
	raw, err = readLimited(filepath.Join(dir, "manifest.json"), maxManifestBytes)
	if err != nil {
		return nil, nil, m, err
	}
	sig, err = readLimited(filepath.Join(dir, "manifest.sig"), 4096)
	if err != nil {
		return nil, nil, m, err
	}
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, nil, m, fmt.Errorf("%w: manifest %s: %v", ErrInvalid, id, err)
	}
	if err := m.Check(id); err != nil {
		return nil, nil, m, err
	}
	return raw, sig, m, nil
}

// Check memeriksa manifest unduhan untuk game id.
func (m Manifest) Check(id string) error {
	switch {
	case m.ID != id:
		return fmt.Errorf("%w: id manifest %q bukan %q", ErrInvalid, m.ID, id)
	case m.Type != "download":
		return fmt.Errorf("%w: tipe %q", ErrInvalid, m.Type)
	case !semverRe.MatchString(m.Version), !semverRe.MatchString(m.MinLauncherVersion), !semverRe.MatchString(m.MinEngineVersion):
		return fmt.Errorf("%w: versi tidak sah", ErrInvalid)
	case !packageRe.MatchString(m.Package):
		return fmt.Errorf("%w: nama paket %q", ErrInvalid, m.Package)
	case !shaRe.MatchString(m.SHA256):
		return fmt.Errorf("%w: sha256", ErrInvalid)
	case m.Size <= 0:
		return fmt.Errorf("%w: ukuran", ErrInvalid)
	}
	return nil
}

// PackagePath mengembalikan path berkas paket game id (sesuai manifest) dan manifest-nya. Ukuran berkas
// harus sama dengan manifest, supaya server tidak melayani paket setengah tersalin.
func (c *Catalog) PackagePath(id string) (string, Manifest, error) {
	_, _, m, err := c.ManifestFile(id)
	if err != nil {
		return "", m, err
	}
	p := filepath.Join(c.Dir, id, m.Package)
	if filepath.Dir(p) != filepath.Join(c.Dir, id) {
		return "", m, ErrInvalid
	}
	st, err := os.Stat(p)
	if err != nil || !st.Mode().IsRegular() {
		return "", m, ErrNotFound
	}
	if st.Size() != m.Size {
		return "", m, fmt.Errorf("%w: ukuran paket %d, manifest %d", ErrInvalid, st.Size(), m.Size)
	}
	return p, m, nil
}

// MaxIconBytes membatasi ikon game (PNG) yang dilayani server.
const MaxIconBytes = 1 << 20

var pngMagic = []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}

// Icon mengembalikan isi icon.png game id (bila ada). Keasliannya diperiksa klien lewat icon_sha256 di
// manifest yang ditandatangani; server hanya memastikan berkas berupa PNG dan tidak terlalu besar.
func (c *Catalog) Icon(id string) ([]byte, error) {
	if !ValidID(id) {
		return nil, ErrNotFound
	}
	b, err := readLimited(filepath.Join(c.Dir, id, "icon.png"), MaxIconBytes)
	if err != nil {
		return nil, err
	}
	if len(b) < len(pngMagic) || string(b[:len(pngMagic)]) != string(pngMagic) {
		return nil, fmt.Errorf("%w: icon.png bukan PNG", ErrInvalid)
	}
	return b, nil
}

func readLimited(path string, limit int64) ([]byte, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if !st.Mode().IsRegular() {
		return nil, ErrNotFound
	}
	if st.Size() > limit {
		return nil, fmt.Errorf("%w: %s terlalu besar", ErrInvalid, filepath.Base(path))
	}
	b := make([]byte, st.Size())
	if _, err := io.ReadFull(f, b); err != nil {
		return nil, err
	}
	return b, nil
}
