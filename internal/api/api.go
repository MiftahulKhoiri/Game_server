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
	rng   game.Rand
}

// New membuat http.Handler lengkap dengan routing.
func New(st *store.Store, log *slog.Logger, info version.Info) http.Handler {
	return NewWithRand(st, log, info, game.RandomSource{})
}

// NewWithRand sama seperti New tetapi dengan sumber acak buatan sendiri (untuk tes).
func NewWithRand(st *store.Store, log *slog.Logger, info version.Info, rng game.Rand) http.Handler {
	s := &Server{store: st, log: log, info: info, rng: rng}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /v1/version", s.versionInfo)
	mux.HandleFunc("POST /v1/players", s.createPlayer)
	mux.Handle("GET /v1/players/me", s.auth(http.HandlerFunc(s.getMe)))
	mux.Handle("PUT /v1/players/me/save", s.auth(http.HandlerFunc(s.saveMe)))
	mux.Handle("GET /v1/battle", s.auth(http.HandlerFunc(s.getBattle)))
	mux.Handle("POST /v1/battle/start", s.auth(http.HandlerFunc(s.startBattle)))
	mux.Handle("POST /v1/battle/action", s.auth(http.HandlerFunc(s.battleAction)))
	mux.Handle("GET /v1/quests", s.auth(http.HandlerFunc(s.getQuests)))
	mux.Handle("POST /v1/quests/accept", s.auth(http.HandlerFunc(s.questAction(false))))
	mux.Handle("POST /v1/quests/claim", s.auth(http.HandlerFunc(s.questAction(true))))
	mux.Handle("GET /v1/shop", s.auth(http.HandlerFunc(s.getShop)))
	mux.Handle("POST /v1/shop/buy", s.auth(http.HandlerFunc(s.shopTrade(game.Buy))))
	mux.Handle("POST /v1/shop/sell", s.auth(http.HandlerFunc(s.shopTrade(game.Sell))))
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
	// Server otoritatif: hanya posisi yang diterima dari klien.
	st := req.State
	p, err := s.store.SavePosition(r.Context(), playerFrom(r).ID, st.Map, st.X, st.Y, req.Version)
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

// --- pertarungan ---

var (
	errBattleActive = errors.New("sudah ada pertarungan yang berjalan")
	errNoBattle     = errors.New("tidak ada pertarungan")
)

type battleResponse struct {
	// Battle bernilai null bila pertarungan sudah selesai.
	Battle  *game.Battle  `json:"battle"`
	Player  game.Player   `json:"player"`
	Status  string        `json:"status,omitempty"`
	Log     []string      `json:"log,omitempty"`
	Rewards *game.Rewards `json:"rewards,omitempty"`
}

func (s *Server) getBattle(w http.ResponseWriter, r *http.Request) {
	id := playerFrom(r).ID
	b, err := s.store.Battle(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, errNoBattle.Error())
		return
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	p, err := s.store.PlayerByID(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, battleResponse{Battle: &b, Player: p, Status: game.StatusOngoing})
}

func (s *Server) startBattle(w http.ResponseWriter, r *http.Request) {
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle != nil {
			return errBattleActive
		}
		b := game.StartBattle(&sess.Player, s.rng)
		sess.Battle = &b
		return nil
	})
	switch {
	case errors.Is(err, errBattleActive):
		writeError(w, http.StatusConflict, "masih ada pertarungan yang berjalan; lanjutkan lewat GET /v1/battle")
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusCreated, battleResponse{Battle: sess.Battle, Player: sess.Player, Status: game.StatusOngoing})
	}
}

type actionRequest struct {
	Action string `json:"action"`
}

func (s *Server) battleAction(w http.ResponseWriter, r *http.Request) {
	var req actionRequest
	if !decode(w, r, &req) {
		return
	}
	var result game.Result
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle == nil {
			return errNoBattle
		}
		res, err := sess.Battle.Act(&sess.Player, req.Action, s.rng)
		if err != nil {
			return err
		}
		result = res
		if res.Status != game.StatusOngoing {
			sess.Battle = nil // pertarungan selesai
		}
		return nil
	})
	switch {
	case errors.Is(err, errNoBattle):
		writeError(w, http.StatusNotFound, errNoBattle.Error())
	case errors.Is(err, game.ErrBadAction), errors.Is(err, game.ErrNoPotion), errors.Is(err, game.ErrFullHP):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusOK, battleResponse{
			Battle: sess.Battle, Player: sess.Player,
			Status: result.Status, Log: result.Log, Rewards: result.Rewards,
		})
	}
}

// --- misi ---

func (s *Server) getQuests(w http.ResponseWriter, r *http.Request) {
	p, err := s.store.PlayerByID(r.Context(), playerFrom(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"quests": p.State.QuestViews()})
}

type questRequest struct {
	Quest string `json:"quest"`
}

type questResponse struct {
	Player     game.Player      `json:"player"`
	Quests     []game.QuestView `json:"quests"`
	RewardGold int              `json:"reward_gold,omitempty"`
}

// questAction membuat handler terima misi (claim=false) atau ambil hadiah (claim=true).
func (s *Server) questAction(claim bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req questRequest
		if !decode(w, r, &req) {
			return
		}
		reward := 0
		sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
			if sess.Battle != nil {
				return errBattleActive
			}
			if claim {
				def, err := sess.Player.State.ClaimQuest(req.Quest)
				reward = def.RewardGold
				return err
			}
			return sess.Player.State.AcceptQuest(req.Quest)
		})
		switch {
		case errors.Is(err, errBattleActive):
			writeError(w, http.StatusConflict, "tidak bisa mengurus misi saat bertarung")
		case errors.Is(err, game.ErrUnknownQuest):
			writeError(w, http.StatusNotFound, err.Error())
		case errors.Is(err, game.ErrQuestTaken), errors.Is(err, game.ErrQuestClaimed):
			writeError(w, http.StatusConflict, err.Error())
		case errors.Is(err, game.ErrQuestNotReady), errors.Is(err, game.ErrTooManyQuests):
			writeError(w, http.StatusUnprocessableEntity, err.Error())
		case err != nil:
			s.fail(w, r, err)
		default:
			writeJSON(w, http.StatusOK, questResponse{Player: sess.Player, Quests: sess.Player.State.QuestViews(), RewardGold: reward})
		}
	}
}

// --- toko ---

func (s *Server) getShop(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"items": game.Items()})
}

type tradeRequest struct {
	Item string `json:"item"`
	Qty  int    `json:"qty"`
}

// shopTrade membuat handler jual/beli. Transaksi atomik: gagal berarti tidak ada yang berubah.
func (s *Server) shopTrade(trade func(*game.State, string, int) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req tradeRequest
		if !decode(w, r, &req) {
			return
		}
		sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
			if sess.Battle != nil {
				return errBattleActive
			}
			return trade(&sess.Player.State, req.Item, req.Qty)
		})
		switch {
		case errors.Is(err, errBattleActive):
			writeError(w, http.StatusConflict, "tidak bisa berdagang saat bertarung")
		case errors.Is(err, game.ErrUnknownItem):
			writeError(w, http.StatusNotFound, err.Error())
		case errors.Is(err, game.ErrNotForSale), errors.Is(err, game.ErrNotBuyable), errors.Is(err, game.ErrBadQty),
			errors.Is(err, game.ErrNoGold), errors.Is(err, game.ErrNotEnough), errors.Is(err, game.ErrInventoryFull):
			writeError(w, http.StatusUnprocessableEntity, err.Error())
		case err != nil:
			s.fail(w, r, err)
		default:
			writeJSON(w, http.StatusOK, sess.Player)
		}
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
