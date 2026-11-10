package api

// Tolok ukur endpoint utama (roadmap no. 269). Jalankan: make bench
// (go test ./internal/... -run '^$' -bench . -benchmem).

import (
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

func benchServer(b *testing.B) (*httptest.Server, createResponse) {
	b.Helper()
	st, err := store.Open(filepath.Join(b.TempDir(), "bench.db"))
	if err != nil {
		b.Fatal(err)
	}
	b.Cleanup(func() { st.Close() })
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	var tick int64
	clock := func() time.Time { tick += 2500; return time.UnixMilli(1_700_000_000_000 + tick) }
	ts := httptest.NewServer(NewWithClock(st, log, testInfo, game.RandFunc(func(n int) int { return 99 % n }), clock))
	b.Cleanup(ts.Close)
	var cr createResponse
	if code, err := call("POST", ts.URL+"/v1/players", "", regBody("Tolok"), &cr); err != nil || code != http.StatusCreated {
		b.Fatalf("daftar: %d %v", code, err)
	}
	return ts, cr
}

func BenchmarkGetMe(b *testing.B) {
	ts, cr := benchServer(b)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if code, err := call("GET", ts.URL+"/v1/players/me", cr.Token, nil, nil); err != nil || code != http.StatusOK {
			b.Fatalf("%d %v", code, err)
		}
	}
}

func BenchmarkSavePosition(b *testing.B) {
	ts, cr := benchServer(b)
	ver, st := cr.Player.Version, cr.Player.State
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		st.X = 6 + i%5
		var saved game.Player
		if code, err := call("PUT", ts.URL+"/v1/players/me/save", cr.Token, saveRequest{Version: ver, State: st}, &saved); err != nil || code != http.StatusOK {
			b.Fatalf("%d %v", code, err)
		}
		ver, st = saved.Version, saved.State
	}
}

func BenchmarkBattleRound(b *testing.B) {
	ts, cr := benchServer(b)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		var br battleResponse
		code, err := call("POST", ts.URL+"/v1/battle/action", cr.Token, map[string]string{"action": "attack"}, &br)
		if code == http.StatusNotFound {
			code, err = call("POST", ts.URL+"/v1/battle/start", cr.Token, nil, &br)
		}
		if err != nil || code >= 400 {
			b.Fatal(fmt.Sprintf("%d %v", code, err))
		}
	}
}
