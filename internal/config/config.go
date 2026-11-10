// Package config membaca pengaturan server dari environment variable.
package config

import (
	"os"
	"strconv"
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
	}
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
