package main

import (
	"io"
	"log/slog"
	"path/filepath"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/store"

	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

func TestValidateVersions(t *testing.T) {
	ok := version.Info{Server: "0.62.0", MinClient: "0.18.0", LatestClient: "0.62.0"}
	if err := validateVersions(ok); err != nil {
		t.Fatalf("versi sah ditolak: %v", err)
	}
	for name, bad := range map[string]version.Info{
		"server tidak valid":  {Server: "v1", MinClient: "0.1.0", LatestClient: "0.1.0"},
		"minimum tidak valid": {Server: "0.1.0", MinClient: "satu", LatestClient: "0.1.0"},
		"terbaru tidak valid": {Server: "0.1.0", MinClient: "0.1.0", LatestClient: ""},
		"minimum lebih baru":  {Server: "0.1.0", MinClient: "0.9.0", LatestClient: "0.2.0"},
	} {
		if validateVersions(bad) == nil {
			t.Errorf("%s harus ditolak: %+v", name, bad)
		}
	}
}

func TestCheckDatabaseFailSafe(t *testing.T) {
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	st, err := store.Open(filepath.Join(t.TempDir(), "g.db"))
	if err != nil {
		t.Fatal(err)
	}
	if err := checkDatabase(log, st, "strict"); err != nil {
		t.Fatalf("database sehat: %v", err)
	}
	st.Close() // pemeriksaan gagal (database tidak bisa dibaca)
	if err := checkDatabase(log, st, "strict"); err == nil {
		t.Fatal("mode strict harus menolak menyala")
	}
	if err := checkDatabase(log, st, "warn"); err != nil {
		t.Fatalf("mode warn tetap menyala: %v", err)
	}
}
