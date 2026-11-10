// Perintah gameserver menjalankan server game RPG.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/api"
	"github.com/MiftahulKhoiri/Game_server/internal/config"
	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	if err := run(log); err != nil {
		log.Error("server berhenti dengan error", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg := config.Load()
	// Khusus uji (scripts/client-test.sh): GAME_WORLD_START = detik Unix jam dunia saat server mulai, supaya
	// siang/malam dan kejadian dunia sama dengan jam klien uji. Produksi: kosong = jam server biasa.
	if v := os.Getenv("GAME_WORLD_START"); v != "" {
		if start, err := strconv.ParseInt(v, 10, 64); err == nil {
			began := time.Now().Unix()
			game.Now = func() int64 { return start + time.Now().Unix() - began }
			log.Info("jam dunia uji", "mulai", start)
		}
	}
	info := version.Info{
		Server:       version.Server,
		Commit:       version.Commit,
		API:          version.API,
		MinClient:    cfg.MinClient,
		LatestClient: cfg.LatestClient,
		UpdateURL:    cfg.UpdateURL,
	}
	if err := validateVersions(info); err != nil {
		return err
	}

	st, err := store.Open(cfg.DBPath)
	if err != nil {
		return err
	}
	defer st.Close()
	if msg, err := st.QuickCheck(context.Background()); err != nil || msg != "" {
		log.Error("pemeriksaan database menemukan masalah", "pesan", msg, "err", err)
	} else {
		log.Info("pemeriksaan database: sehat")
	}

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           api.WithPatches(cfg.PatchDir, api.New(st, log, info)),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if cfg.BackupDir != "" && cfg.BackupEvery > 0 {
		go backupLoop(ctx, log, st, cfg)
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("server berjalan", "addr", cfg.Addr, "db", cfg.DBPath,
			"versi", info.Server, "commit", info.Commit,
			"klien_min", info.MinClient, "klien_terbaru", info.LatestClient)
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	case <-ctx.Done():
		log.Info("mematikan server...")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}

// backupLoop mencadangkan database secara otomatis (roadmap no. 235): segera bila cadangan terakhir sudah
// lebih tua dari BackupEvery (atau belum ada), lalu setiap BackupEvery. Menyisakan BackupKeep cadangan.
func backupLoop(ctx context.Context, log *slog.Logger, st *store.Store, cfg config.Config) {
	run := func() {
		path, err := st.Backup(ctx, cfg.BackupDir, cfg.BackupKeep, time.Now())
		if err != nil {
			log.Error("cadangan database gagal", "err", err)
			return
		}
		log.Info("cadangan database dibuat", "path", path)
	}
	wait := time.Minute // beri server waktu menyala dulu
	if _, last := store.LatestBackup(cfg.BackupDir); !last.IsZero() && time.Since(last) < cfg.BackupEvery {
		wait = cfg.BackupEvery - time.Since(last)
	}
	timer := time.NewTimer(wait)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			run()
			timer.Reset(cfg.BackupEvery)
		}
	}
}

func validateVersions(info version.Info) error {
	for name, v := range map[string]string{
		"versi server":       info.Server,
		"GAME_MIN_CLIENT":    info.MinClient,
		"GAME_LATEST_CLIENT": info.LatestClient,
	} {
		if !version.Valid(v) {
			return fmt.Errorf("%s tidak valid: %q (harus MAJOR.MINOR.PATCH)", name, v)
		}
	}
	if c, _ := version.Compare(info.MinClient, info.LatestClient); c > 0 {
		return fmt.Errorf("GAME_MIN_CLIENT (%s) tidak boleh lebih baru dari GAME_LATEST_CLIENT (%s)",
			info.MinClient, info.LatestClient)
	}
	return nil
}
