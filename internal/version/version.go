// Package version memegang nomor versi server dan aturan membandingkan versi.
//
// Format versi: MAJOR.MINOR.PATCH (mis. 0.2.0). Aturan lengkap ada di
// docs/VERSIONING.md.
package version

import (
	"fmt"
	"strconv"
	"strings"
)

const (
	// API adalah nomor kontrak API (naik hanya bila ada perubahan yang memutus klien lama).
	API = 1

	// Nilai bawaan; bisa ditimpa lewat environment (lihat internal/config).
	DefaultMinClient    = "0.18.0"
	DefaultLatestClient = "0.64.0"
	DefaultUpdateURL    = "https://github.com/MiftahulKhoiri/Game_server/releases/latest"
)

// Server adalah versi server ini. Naikkan saat merilis.
// Commit diisi saat build lewat -ldflags (lihat Makefile).
var (
	Server = "0.64.0"
	Commit = "dev"
)

// Info adalah isi jawaban GET /v1/version.
type Info struct {
	Server       string `json:"server"`
	Commit       string `json:"commit"`
	API          int    `json:"api"`
	MinClient    string `json:"min_client"`    // klien di bawah ini WAJIB update
	LatestClient string `json:"latest_client"` // klien terbaru yang tersedia
	UpdateURL    string `json:"update_url"`    // tempat mengunduh APK
}

// Parse memecah "1.2.3" (boleh diawali "v") menjadi tiga angka.
func Parse(v string) ([3]int, error) {
	var out [3]int
	parts := strings.Split(strings.TrimPrefix(strings.TrimSpace(v), "v"), ".")
	if len(parts) != 3 {
		return out, fmt.Errorf("versi %q harus berbentuk MAJOR.MINOR.PATCH", v)
	}
	for i, p := range parts {
		if p == "" || strings.Trim(p, "0123456789") != "" {
			return out, fmt.Errorf("versi %q berisi bagian bukan angka: %q", v, p)
		}
		n, err := strconv.Atoi(p)
		if err != nil {
			return out, fmt.Errorf("versi %q: %w", v, err)
		}
		out[i] = n
	}
	return out, nil
}

// Valid melaporkan apakah v berbentuk MAJOR.MINOR.PATCH.
func Valid(v string) bool {
	_, err := Parse(v)
	return err == nil
}

// Compare mengembalikan -1 jika a < b, 0 jika sama, 1 jika a > b.
func Compare(a, b string) (int, error) {
	pa, err := Parse(a)
	if err != nil {
		return 0, err
	}
	pb, err := Parse(b)
	if err != nil {
		return 0, err
	}
	for i := range pa {
		switch {
		case pa[i] < pb[i]:
			return -1, nil
		case pa[i] > pb[i]:
			return 1, nil
		}
	}
	return 0, nil
}
