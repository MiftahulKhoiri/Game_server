package api

import (
	"errors"
	"math"
	"net/http"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// Hadiah dunia: hancurkan pohon/batu/rumput dan buka peti harta. Server mengundi hadiah.
// Posisi pemain ikut dikirim tiap permintaan (sama seperti simpan posisi), lalu dipakai untuk memeriksa jarak.

type worldPose struct {
	Map string  `json:"map"`
	FX  float64 `json:"fx"`
	FZ  float64 `json:"fz"`
	Yaw float64 `json:"yaw"`
}

type breakRequest struct {
	worldPose
	Objects []game.BreakTarget `json:"objects"`
}

type chestRequest struct {
	worldPose
	ID string `json:"id"`
}

type worldResponse struct {
	Player game.Player `json:"player"`
	Loot   game.Loot   `json:"loot"`
}

// apply memperbarui posisi state dari permintaan (peta dan petak harus sah).
func (p worldPose) apply(st *game.State) bool {
	x, z := int(math.Floor(p.FX)), int(math.Floor(p.FZ))
	pose, ok := game.NormalizePose(game.Pose{Map: p.Map, X: x, Y: z, FX: p.FX, FZ: p.FZ, Yaw: p.Yaw})
	if !ok {
		return false
	}
	st.Map, st.X, st.Y = pose.Map, pose.X, pose.Y
	st.FX, st.FZ, st.Yaw = pose.FX, pose.FZ, pose.Yaw
	return true
}

var errBadPose = errors.New("posisi di luar peta atau peta tidak dikenal")

// worldAction menjalankan fn atas state pemain secara atomik (ditolak saat bertarung).
func (s *Server) worldAction(w http.ResponseWriter, r *http.Request, pose worldPose, fn func(st *game.State) (game.Loot, error)) {
	var loot game.Loot
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle != nil {
			return errBattleActive
		}
		st := &sess.Player.State
		if !pose.apply(st) {
			return errBadPose
		}
		l, err := fn(st)
		loot = l
		return err
	})
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, worldResponse{Player: sess.Player, Loot: loot})
	case errors.Is(err, errBattleActive):
		writeError(w, http.StatusConflict, "tidak bisa dilakukan saat bertarung")
	case errors.Is(err, errBadPose), errors.Is(err, game.ErrBadObject), errors.Is(err, game.ErrTooFar),
		errors.Is(err, game.ErrTooFast), errors.Is(err, game.ErrUnknownChest), errors.Is(err, game.ErrChestEmpty):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	default:
		s.fail(w, r, err)
	}
}

func (s *Server) worldBreak(w http.ResponseWriter, r *http.Request) {
	var req breakRequest
	if !decode(w, r, &req) {
		return
	}
	s.worldAction(w, r, req.worldPose, func(st *game.State) (game.Loot, error) {
		return st.BreakObjects(s.clock(), req.Objects, s.rng)
	})
}

func (s *Server) worldChest(w http.ResponseWriter, r *http.Request) {
	var req chestRequest
	if !decode(w, r, &req) {
		return
	}
	s.worldAction(w, r, req.worldPose, func(st *game.State) (game.Loot, error) {
		return st.OpenChest(s.clock(), req.ID, s.rng)
	})
}

// worldState: benda hancur dan peti terbuka di sebuah peta (untuk menggambar dunia saat dimuat).
func (s *Server) worldState(w http.ResponseWriter, r *http.Request) {
	p := playerFrom(r)
	mapID := r.URL.Query().Get("map")
	writeJSON(w, http.StatusOK, map[string]any{"map": mapID, "items": p.State.WorldView(s.clock(), mapID)})
}
