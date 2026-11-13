// Package config membaca pengaturan server dari environment variable.
package config

import (
	"fmt"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

// Config adalah pengaturan runtime server.
type Config struct {
	// Addr adalah alamat dengar HTTP, misalnya ":8090".
	Addr string
	// DBPath adalah lokasi file SQLite.
	DBPath string
	// MinClient: klien di bawah versi ini ditolak dan wajib update.
	MinClient string
	// LatestClient: versi klien terbaru yang tersedia (untuk pemberitahuan update).
	LatestClient string
	// UpdateURL: alamat unduh APK yang ditampilkan ke pemain.
	UpdateURL string
	// PatchDir: folder patch konten klien (latest.json + *.pck); kosong = tanpa patch.
	PatchDir string
	// Cadangan otomatis database (roadmap no. 235): folder, jarak antar cadangan, jumlah yang disimpan.
	BackupDir   string
	BackupEvery time.Duration
	BackupKeep  int
	// TrustedProxies: isi GAME_TRUSTED_PROXIES apa adanya (lihat ParseProxies).
	TrustedProxies string
	// DBCheck: "strict" (bawaan) = server menolak menyala bila quick_check menemukan kerusakan; "warn" = tetap
	// menyala dengan catatan ERROR (penyelamatan darurat).
	DBCheck string
}

// Load membaca konfigurasi. Nilai bawaan cocok untuk pengembangan di Pi.
//
//	GAME_ADDR           alamat dengar HTTP        (bawaan ":8090")
//	GAME_DB             lokasi file database      (bawaan "data/game.db")
//	GAME_MIN_CLIENT     versi klien minimum       (bawaan dari paket version)
//	GAME_LATEST_CLIENT  versi klien terbaru       (bawaan dari paket version)
//	GAME_UPDATE_URL     alamat unduh APK          (bawaan halaman Releases)
//	GAME_PATCH_DIR      folder patch konten klien (bawaan "patches")
//	GAME_BACKUP_DIR     folder cadangan database  (bawaan "data/backup"; "off" = mati)
//	GAME_BACKUP_HOURS   jarak antar cadangan, jam (bawaan 24)
//	GAME_BACKUP_KEEP    jumlah cadangan disimpan  (bawaan 7)
//	GAME_TRUSTED_PROXIES proxy tepercaya untuk header IP asli, dipisah koma (IP atau CIDR;
//	                    bawaan "127.0.0.0/8,::1" = proxy lokal saja; "none" = tidak ada)
//	GAME_DB_CHECK       "strict" (bawaan) atau "warn": sikap bila database rusak saat menyala
//
// Dengan GAME_MIN_CLIENT dan GAME_LATEST_CLIENT, pemilik server bisa
// mewajibkan update tanpa membangun ulang server.
func Load() Config {
	return Config{
		Addr:         env("GAME_ADDR", ":8090"),
		DBPath:       env("GAME_DB", "data/game.db"),
		MinClient:    env("GAME_MIN_CLIENT", version.DefaultMinClient),
		LatestClient: env("GAME_LATEST_CLIENT", version.DefaultLatestClient),
		UpdateURL:    env("GAME_UPDATE_URL", version.DefaultUpdateURL),
		PatchDir:     env("GAME_PATCH_DIR", "patches"),
		BackupDir:    backupDir(env("GAME_BACKUP_DIR", "data/backup")),
		BackupEvery:  time.Duration(envInt("GAME_BACKUP_HOURS", 24)) * time.Hour,
		BackupKeep:   envInt("GAME_BACKUP_KEEP", 7),

		TrustedProxies: env("GAME_TRUSTED_PROXIES", DefaultTrustedProxies),
		DBCheck:        env("GAME_DB_CHECK", "strict"),
	}
}

// DefaultTrustedProxies: hanya proxy di mesin ini sendiri (mis. cloudflared/nginx di Pi).
const DefaultTrustedProxies = "127.0.0.0/8,::1"

// ParseProxies membaca daftar IP/CIDR dipisah koma. "none" atau kosong = tidak ada proxy tepercaya.
func ParseProxies(v string) ([]netip.Prefix, error) {
	v = strings.TrimSpace(v)
	if v == "" || v == "none" {
		return nil, nil
	}
	var out []netip.Prefix
	for _, part := range strings.Split(v, ",") {
		part = strings.TrimSpace(part)
		if p, err := netip.ParsePrefix(part); err == nil {
			out = append(out, p.Masked())
			continue
		}
		a, err := netip.ParseAddr(part)
		if err != nil {
			return nil, fmt.Errorf("GAME_TRUSTED_PROXIES: %q bukan IP/CIDR", part)
		}
		out = append(out, netip.PrefixFrom(a, a.BitLen()))
	}
	return out, nil
}

func backupDir(v string) string {
	if v == "off" {
		return ""
	}
	return v
}

func envInt(key string, fallback int) int {
	if n, err := strconv.Atoi(os.Getenv(key)); err == nil && n > 0 {
		return n
	}
	return fallback
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
