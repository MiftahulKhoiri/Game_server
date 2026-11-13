package api

import (
	"errors"
	"math"
	"net/http"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// Hadiah dunia: hancurkan pohon/batu/rumput dan buka peti harta. Server mengundi hadiah.
// Posisi pemain ikut dikirim tiap permintaan (sama seperti simpan posisi) tetapi baru dipakai setelah lolos
// pemeriksaan gerakan server (store.MovePlayer / game.State.MoveTo).

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

// pose mengubah posisi permintaan menjadi Pose yang sudah dinormalkan (peta dikenal, petak di dalam peta,
// angka terhingga). Posisi ini BELUM dipercaya: worldAction memeriksanya lewat store.MovePlayer.
func (p worldPose) pose() (game.Pose, bool) {
	if !finiteCoord(p.FX) || !finiteCoord(p.FZ) || math.IsNaN(p.Yaw) || math.IsInf(p.Yaw, 0) {
		return game.Pose{}, false
	}
	x, z := int(math.Floor(p.FX)), int(math.Floor(p.FZ))
	return game.NormalizePose(game.Pose{Map: p.Map, X: x, Y: z, FX: p.FX, FZ: p.FZ, Yaw: p.Yaw})
}

// finiteCoord: bilangan terhingga dan cukup kecil untuk diubah ke int dengan aman (peta terbesar < 1000 petak).
func finiteCoord(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) && math.Abs(v) < 1e6 }

var errBadPose = errors.New("posisi di luar peta atau peta tidak dikenal")

// worldAction menjalankan fn atas state pemain secara atomik (ditolak saat bertarung). Posisi yang dikirim
// klien hanya dipakai bila lolos pemeriksaan gerakan server (bisa dicapai dari posisi tersimpan dalam waktu
// yang berlalu, lewat pintu yang terbuka); fn lalu memeriksa jarak dari posisi server yang sudah sah itu.
func (s *Server) worldAction(w http.ResponseWriter, r *http.Request, wp worldPose, fn func(st *game.State) (game.Loot, error)) {
	pose, ok := wp.pose()
	if !ok {
		writeError(w, http.StatusUnprocessableEntity, errBadPose.Error())
		return
	}
	now := s.clock()
	var loot game.Loot
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle != nil {
			return errBattleActive
		}
		if err := store.MovePlayer(&sess.Player, pose, now); err != nil {
			return err
		}
		l, err := fn(&sess.Player.State)
		loot = l
		return err
	})
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, worldResponse{Player: sess.Player, Loot: loot})
	case errors.Is(err, errBattleActive):
		writeError(w, http.StatusConflict, "tidak bisa dilakukan saat bertarung")
	case isMoveError(err):
		s.logMoveReject(r, pose, err)
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	case errors.Is(err, game.ErrBadObject), errors.Is(err, game.ErrTooFar),
		errors.Is(err, game.ErrTooFast), errors.Is(err, game.ErrUnknownChest), errors.Is(err, game.ErrChestEmpty):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	default:
		s.fail(w, r, err)
	}
}

// isMoveError: posisi baru ditolak aturan gerakan server.
func isMoveError(err error) bool {
	return errors.Is(err, game.ErrMoveTooFar) || errors.Is(err, game.ErrMapLocked) || errors.Is(err, game.ErrMoveBlocked) ||
		errors.Is(err, game.ErrHouseLocked)
}

// logMoveReject mencatat penolakan posisi untuk diperiksa pemilik server (tanpa token/data rahasia).
func (s *Server) logMoveReject(r *http.Request, pose game.Pose, err error) {
	s.log.Warn("posisi ditolak", "player", playerFrom(r).ID, "ip", clientIP(r), "path", r.URL.Path,
		"map", pose.Map, "x", pose.X, "y", pose.Y, "alasan", err.Error())
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
