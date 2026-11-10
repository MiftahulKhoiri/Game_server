package config

import (
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

func TestLoadDefaults(t *testing.T) {
	for _, k := range []string{"GAME_ADDR", "GAME_DB", "GAME_MIN_CLIENT", "GAME_LATEST_CLIENT", "GAME_UPDATE_URL",
		"GAME_PATCH_DIR", "GAME_BACKUP_DIR", "GAME_BACKUP_HOURS", "GAME_BACKUP_KEEP"} {
		t.Setenv(k, "")
	}
	c := Load()
	if c.Addr != ":8090" || c.DBPath != "data/game.db" || c.PatchDir != "patches" {
		t.Errorf("bawaan alamat/db/patch salah: %+v", c)
	}
	if c.MinClient != version.DefaultMinClient || c.LatestClient != version.DefaultLatestClient || c.UpdateURL != version.DefaultUpdateURL {
		t.Errorf("bawaan versi salah: %+v", c)
	}
	if c.BackupDir != "data/backup" || c.BackupEvery != 24*time.Hour || c.BackupKeep != 7 {
		t.Errorf("bawaan cadangan salah: %+v", c)
	}
}

func TestLoadFromEnv(t *testing.T) {
	t.Setenv("GAME_ADDR", "127.0.0.1:9000")
	t.Setenv("GAME_DB", "/tmp/x.db")
	t.Setenv("GAME_MIN_CLIENT", "0.50.0")
	t.Setenv("GAME_BACKUP_DIR", "off")
	t.Setenv("GAME_BACKUP_HOURS", "6")
	t.Setenv("GAME_BACKUP_KEEP", "3")
	c := Load()
	if c.Addr != "127.0.0.1:9000" || c.DBPath != "/tmp/x.db" || c.MinClient != "0.50.0" {
		t.Errorf("nilai env tidak dipakai: %+v", c)
	}
	if c.BackupDir != "" || c.BackupEvery != 6*time.Hour || c.BackupKeep != 3 {
		t.Errorf("cadangan dari env salah: %+v", c)
	}
}

func TestBadNumbersFallBack(t *testing.T) {
	for _, v := range []string{"abc", "0", "-5"} {
		t.Setenv("GAME_BACKUP_HOURS", v)
		t.Setenv("GAME_BACKUP_KEEP", v)
		c := Load()
		if c.BackupEvery != 24*time.Hour || c.BackupKeep != 7 {
			t.Errorf("angka %q harus kembali ke bawaan: %+v", v, c)
		}
	}
}
