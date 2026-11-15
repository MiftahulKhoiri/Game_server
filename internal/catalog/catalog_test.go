package catalog

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// buatGame menulis manifest + paket contoh di folder katalog dan mengembalikan manifestnya.
func buatGame(t *testing.T, dir, id string, pck []byte, ubah func(m map[string]any)) map[string]any {
	t.Helper()
	sum := sha256.Sum256(pck)
	m := map[string]any{
		"id": id, "name": "Uji", "version": "1.0.0", "type": "download",
		"entry_scene": "res://games/" + id + "/main.tscn", "package": id + "-1.0.0.pck",
		"size": len(pck), "sha256": hex.EncodeToString(sum[:]),
		"min_launcher_version": "0.84.0", "min_engine_version": "4.7.2",
	}
	if ubah != nil {
		ubah(m)
	}
	gd := filepath.Join(dir, id)
	if err := os.MkdirAll(gd, 0o755); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(m)
	must(t, os.WriteFile(filepath.Join(gd, "manifest.json"), raw, 0o644))
	must(t, os.WriteFile(filepath.Join(gd, "manifest.sig"), []byte("c2ln"), 0o644))
	must(t, os.WriteFile(filepath.Join(gd, id+"-1.0.0.pck"), pck, 0o644))
	return m
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func TestKatalogMati(t *testing.T) {
	c := New("")
	if _, _, err := c.CatalogFile(); !errors.Is(err, ErrNotFound) {
		t.Fatalf("katalog mati harus ErrNotFound, dapat %v", err)
	}
	if _, _, err := c.PackagePath("education_sd"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("paket di katalog mati harus ErrNotFound, dapat %v", err)
	}
}

func TestKatalogDanEntri(t *testing.T) {
	dir := t.TempDir()
	must(t, os.WriteFile(filepath.Join(dir, "catalog.json"), []byte(`{"catalog_version":1,"games":[{"id":"education_sd","version":"1.0.0"}]}`), 0o644))
	must(t, os.WriteFile(filepath.Join(dir, "catalog.sig"), []byte("c2ln"), 0o644))
	c := New(dir)
	raw, sig, err := c.CatalogFile()
	if err != nil || len(raw) == 0 || string(sig) != "c2ln" {
		t.Fatalf("CatalogFile: %v", err)
	}
	e, err := c.Entry("education_sd")
	if err != nil || e["version"] != "1.0.0" {
		t.Fatalf("Entry: %v %v", e, err)
	}
	if _, err := c.Entry("tidak_ada"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("entri tak dikenal harus ErrNotFound, dapat %v", err)
	}
	if _, err := c.Entry("../x"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("id tidak sah harus ErrNotFound, dapat %v", err)
	}
}

func TestPaketSah(t *testing.T) {
	dir := t.TempDir()
	buatGame(t, dir, "education_sd", []byte("GDPC isi paket"), nil)
	p, m, err := New(dir).PackagePath("education_sd")
	if err != nil {
		t.Fatalf("PackagePath: %v", err)
	}
	if filepath.Base(p) != "education_sd-1.0.0.pck" || m.Version != "1.0.0" {
		t.Fatalf("hasil salah: %s %+v", p, m)
	}
}

func TestManifestDitolak(t *testing.T) {
	kasus := map[string]func(m map[string]any){
		"id lain":         func(m map[string]any) { m["id"] = "education_smp" },
		"tipe builtin":    func(m map[string]any) { m["type"] = "builtin" },
		"versi rusak":     func(m map[string]any) { m["version"] = "1.0" },
		"paket traversal": func(m map[string]any) { m["package"] = "../../etc/passwd" },
		"paket bukan pck": func(m map[string]any) { m["package"] = "x.sh" },
		"sha pendek":      func(m map[string]any) { m["sha256"] = "abc" },
		"ukuran nol":      func(m map[string]any) { m["size"] = 0 },
		"launcher kosong": func(m map[string]any) { m["min_launcher_version"] = "" },
	}
	for nama, ubah := range kasus {
		t.Run(nama, func(t *testing.T) {
			dir := t.TempDir()
			buatGame(t, dir, "education_sd", []byte("isi"), ubah)
			if _, _, err := New(dir).PackagePath("education_sd"); !errors.Is(err, ErrInvalid) {
				t.Fatalf("harus ErrInvalid, dapat %v", err)
			}
		})
	}
}

func TestUkuranPaketBedaDitolak(t *testing.T) {
	dir := t.TempDir()
	buatGame(t, dir, "education_sd", []byte("isi"), func(m map[string]any) { m["size"] = 999 })
	if _, _, err := New(dir).PackagePath("education_sd"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("ukuran beda harus ErrInvalid, dapat %v", err)
	}
}

func TestIDTidakSah(t *testing.T) {
	for _, id := range []string{"", "A", "a", "../a", "a/b", "Education", "a-b", "1abc", "abcdefghijabcdefghijabcdefghijabc"} {
		if ValidID(id) {
			t.Errorf("%q seharusnya tidak sah", id)
		}
	}
	for _, id := range []string{"adventure", "education_sd", "game4"} {
		if !ValidID(id) {
			t.Errorf("%q seharusnya sah", id)
		}
	}
}
