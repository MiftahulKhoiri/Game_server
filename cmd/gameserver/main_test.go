package main

import (
	"testing"

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
