// Package api berisi handler HTTP server game.
//
// Kontrak lengkap endpoint ada di docs/API.md.
package api

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

const maxBodyBytes = 64 << 10 // 64 KiB

var nameRe = regexp.MustCompile(`^[A-Za-z0-9_]{3,20}$`)

type ctxKey struct{}

// Server adalah kumpulan handler HTTP.
type Server struct {
	store *store.Store
	log   *slog.Logger
	info  version.Info
}

// New membuat http.Handler lengkap dengan routing.
func New(st *store.Store, log *slog.Logger, info version.Info) http.Handler {
	s := &Server{store: st, log: log, info: info}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /v1/version", s.versionInfo)
	mux.HandleFunc("POST /v1/players", s.createPlayer)
	mux.Handle("GET /v1/players/me", s.auth(http.HandlerFunc(s.getMe)))
	mux.Handle("PUT /v1/players/me/save", s.auth(http.HandlerFunc(s.saveMe)))
	return s.logRequests(s.clientGate(mux))
}

// --- handler ---

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "database tidak tersedia")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": s.info.Server})
}

func (s *Server) versionInfo(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.info)
}

type createRequest struct {
	Name string `json:"name"`
}

type createResponse struct {
	Player game.Player `json:"player"`
	// Token hanya ditampilkan sekali di sini; klien wajib menyimpannya.
	Token string `json:"token"`
}

func (s *Server) createPlayer(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if !decode(w, r, &req) {
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if !nameRe.MatchString(req.Name) {
		writeError(w, http.StatusUnprocessableEntity, "nama harus 3-20 karakter: huruf, angka, atau _")
		return
	}
	id, err := randomHex(8)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	token, err := randomHex(32)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	p, err := s.store.CreatePlayer(r.Context(), id, req.Name, hashToken(token), game.NewState())
	switch {
	case errors.Is(err, store.ErrNameTaken):
		writeError(w, http.StatusConflict, "nama sudah dipakai")
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusCreated, createResponse{Player: p, Token: token})
	}
}

func (s *Server) getMe(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, playerFrom(r))
}

type saveRequest struct {
	// Version adalah versi yang terakhir diterima klien dari server.
	Version int        `json:"version"`
	State   game.State `json:"state"`
}

func (s *Server) saveMe(w http.ResponseWriter, r *http.Request) {
	var req saveRequest
	if !decode(w, r, &req) {
		return
	}
	if err := req.State.Validate(); err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	p, err := s.store.SaveState(r.Context(), playerFrom(r).ID, req.State, req.Version)
	switch {
	case errors.Is(err, store.ErrConflict):
		writeError(w, http.StatusConflict, "versi data tidak cocok; ambil data terbaru dulu")
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "pemain tidak ditemukan")
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusOK, p)
	}
}

// --- middleware ---

func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || token == "" {
			writeError(w, http.StatusUnauthorized, "token tidak ada")
			return
		}
		p, err := s.store.PlayerByTokenHash(r.Context(), hashToken(token))
		switch {
		case errors.Is(err, store.ErrNotFound):
			writeError(w, http.StatusUnauthorized, "token tidak valid")
		case err != nil:
			s.fail(w, r, err)
		default:
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, p)))
		}
	})
}

// clientGate menolak klien yang versinya di bawah MinClient (426 Upgrade Required).
// Klien mengirim versinya lewat header X-Client-Version. Klien lama yang belum
// mengirim header tidak dapat dipaksa update.
func (s *Server) clientGate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v := r.Header.Get("X-Client-Version")
		exempt := r.URL.Path == "/healthz" || r.URL.Path == "/v1/version"
		if v != "" && !exempt {
			if c, err := version.Compare(v, s.info.MinClient); err == nil && c < 0 {
				writeJSON(w, http.StatusUpgradeRequired, map[string]any{
					"error":      "Versi aplikasi " + v + " sudah terlalu lama (minimal " + s.info.MinClient + "). Silakan update.",
					"min_client": s.info.MinClient,
					"update_url": s.info.UpdateURL,
				})
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		s.log.Info("request", "method", r.Method, "path", r.URL.Path,
			"status", sw.status, "dur", time.Since(start).Round(time.Microsecond))
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// --- util ---

func playerFrom(r *http.Request) game.Player {
	p, _ := r.Context().Value(ctxKey{}).(game.Player)
	return p
}

func (s *Server) fail(w http.ResponseWriter, r *http.Request, err error) {
	s.log.Error("kesalahan internal", "path", r.URL.Path, "err", err)
	writeError(w, http.StatusInternalServerError, "kesalahan internal server")
}

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "JSON tidak valid: "+err.Error())
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
