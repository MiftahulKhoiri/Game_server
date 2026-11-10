package api

import (
	"errors"
	"math"
	"net/http"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/auth"
	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// Manajemen akun & sesi (roadmap no. 221-223).

func tokenFrom(r *http.Request) string {
	h, _ := r.Context().Value(tokenKey{}).(string)
	return h
}

// listSessions: perangkat yang sedang masuk ke akun ini.
func (s *Server) listSessions(w http.ResponseWriter, r *http.Request) {
	list, err := s.store.Sessions(r.Context(), playerFrom(r).ID, tokenFrom(r))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sessions": list, "idle_days": int(storeIdleDays())})
}

// logoutOthers: keluarkan akun dari semua perangkat lain (token permintaan ini tetap berlaku).
func (s *Server) logoutOthers(w http.ResponseWriter, r *http.Request) {
	n, err := s.store.RevokeOthers(r.Context(), playerFrom(r).ID, tokenFrom(r))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"revoked": n})
}

type passwordRequest struct {
	Old string `json:"old"`
	New string `json:"new"`
}

// changePassword: ganti kata sandi (wajib kata sandi lama). Sesi di perangkat lain dicabut.
func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) {
	var req passwordRequest
	if !decode(w, r, &req) {
		return
	}
	p := playerFrom(r)
	if s.tooMany(w, s.loginByName, "id:"+p.ID) {
		return
	}
	hash, err := s.store.PasswordHash(r.Context(), p.ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if hash == "" || len(req.Old) > auth.MaxPassword || !auth.Verify(req.Old, hash) {
		s.loginByName.Fail("id:" + p.ID)
		writeError(w, http.StatusUnauthorized, "kata sandi lama salah")
		return
	}
	if err := auth.ValidatePassword(req.New); err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	if req.New == req.Old {
		writeError(w, http.StatusUnprocessableEntity, "kata sandi baru harus berbeda")
		return
	}
	nh, err := auth.Hash(req.New)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if err := s.store.SetPassword(r.Context(), p.ID, nh, tokenFrom(r)); err != nil {
		s.fail(w, r, err)
		return
	}
	s.loginByName.Reset("id:" + p.ID)
	w.WriteHeader(http.StatusNoContent)
}

// --- pemantauan gerakan (roadmap no. 228) ---

// Kecepatan tercepat yang masuk akal (petak/detik, termasuk lari + Boost + menghindar) dan kelonggaran.
const (
	maxTilesPerSec = 12.0
	moveGrace      = 25.0
)

// errSuspicious hanya dipakai untuk log: posisi baru terlalu jauh dari posisi lama dalam waktu sesingkat itu.
var errSuspicious = errors.New("gerakan mencurigakan")

// watchMovement mencatat (tidak menolak) lompatan posisi yang mustahil di peta yang sama. Pindah peta
// lewat pintu dan pemulangan setelah kalah tidak dihitung. Ditolak langsung bisa membuat pemain yang
// sinyalnya putus-sambung tidak bisa menyimpan; jadi server mencatat untuk diperiksa pemilik server.
func (s *Server) watchMovement(p game.Player, pose game.Pose) {
	old := p.State
	if old.Map != pose.Map || (old.FX == 0 && old.FZ == 0) {
		return
	}
	dist := math.Hypot(pose.FX-old.FX, pose.FZ-old.FZ)
	elapsed := s.clock().Sub(p.UpdatedAt).Seconds()
	if elapsed < 0 {
		elapsed = 0
	}
	if dist > maxTilesPerSec*elapsed+moveGrace {
		s.log.Warn(errSuspicious.Error(), "player", p.ID, "map", pose.Map, "jarak", math.Round(dist), "detik", math.Round(elapsed))
	}
}

func storeIdleDays() float64 { return storeSessionIdle().Hours() / 24 }

func storeSessionIdle() time.Duration { return store.SessionIdle }
