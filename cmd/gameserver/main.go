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
	"sync"
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
	proxies, err := config.ParseProxies(cfg.TrustedProxies)
	if err != nil {
		return err
	}
	api.TrustedProxies = proxies

	st, err := store.Open(cfg.DBPath)
	if err != nil {
		return err
	}
	defer st.Close()
	if err := checkDatabase(log, st, cfg.DBCheck); err != nil {
		return err
	}

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           api.New(st, log, info, api.PatchDir(cfg.PatchDir)),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    32 << 10, // header normal klien jauh lebih kecil; cegah header raksasa
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	// Goroutine latar harus selesai sebelum database ditutup (defer berjalan terbalik: Wait dulu, lalu Close).
	var bg sync.WaitGroup
	defer bg.Wait()
	defer stop() // hentikan goroutine latar saat run selesai karena sebab apa pun
	if cfg.BackupDir != "" && cfg.BackupEvery > 0 {
		bg.Add(1)
		go func() {
			defer bg.Done()
			backupLoop(ctx, log, st, cfg)
		}()
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

// checkDatabase menjalankan PRAGMA quick_check saat menyala. Fail-safe: database yang rusak (atau gagal
// diperiksa) membuat server menolak menyala supaya tidak terus menulis di atas data rusak; pemilik server
// memulihkan cadangan dulu (make restore, docs/BACKUP.md). GAME_DB_CHECK=warn menyalakan server walau rusak
// (hanya untuk penyelamatan data darurat), dengan catatan ERROR.
func checkDatabase(log *slog.Logger, st *store.Store, mode string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	msg, err := st.QuickCheck(ctx)
	if err == nil && msg == "" {
		log.Info("pemeriksaan database: sehat")
		return nil
	}
	log.Error("pemeriksaan database menemukan masalah", "pesan", msg, "err", err, "mode", mode)
	if mode == "warn" {
		log.Error("GAME_DB_CHECK=warn: server tetap dinyalakan walau database bermasalah; segera pulihkan cadangan")
		return nil
	}
	if err != nil {
		return fmt.Errorf("pemeriksaan database gagal: %w (pulihkan cadangan: make restore, atau GAME_DB_CHECK=warn)", err)
	}
	return fmt.Errorf("database rusak: %s (pulihkan cadangan: make restore, atau GAME_DB_CHECK=warn)", msg)
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
