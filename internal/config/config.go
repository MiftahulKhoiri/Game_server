// Package config membaca pengaturan server dari environment variable.
package config

import "os"

// Config adalah pengaturan runtime server.
type Config struct {
	// Addr adalah alamat dengar HTTP, misalnya ":8090".
	Addr string
	// DBPath adalah lokasi file SQLite.
	DBPath string
}

// Load membaca konfigurasi. Nilai bawaan cocok untuk pengembangan di Pi.
//
//	GAME_ADDR  alamat dengar HTTP   (bawaan ":8090")
//	GAME_DB    lokasi file database (bawaan "data/game.db")
func Load() Config {
	return Config{
		Addr:   env("GAME_ADDR", ":8090"),
		DBPath: env("GAME_DB", "data/game.db"),
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
