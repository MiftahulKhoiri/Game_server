package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// Teman dan pemain aktif (roadmap no. 176, v0.79.0).

const (
	recentPlayersDays  = 7
	recentPlayersLimit = 20
)

type friendRequest struct {
	Name string `json:"name"`
}

// addFriend: POST /v1/friends {"name"}. Nama harus pemain yang ada; disimpan dengan ejaan aslinya.
func (s *Server) addFriend(w http.ResponseWriter, r *http.Request) {
	var req friendRequest
	if !decode(w, r, &req) {
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || len(name) > game.MaxFriendName {
		writeError(w, http.StatusUnprocessableEntity, "nama pemain tidak sah")
		return
	}
	_, real, err := s.store.PlayerName(r.Context(), name)
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "pemain tidak ditemukan")
		return
	case err != nil:
		s.fail(w, r, err)
		return
	}
	self := playerFrom(r).Name
	s.applyToState(w, r, func(st *game.State) error { return st.AddFriend(real, self) })
}

// removeFriend: POST /v1/friends/remove {"name"}.
func (s *Server) removeFriend(w http.ResponseWriter, r *http.Request) {
	var req friendRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.RemoveFriend(strings.TrimSpace(req.Name)) })
}

// recentPlayers: GET /v1/players/recent — nama pemain lain yang bermain 7 hari terakhir (paling banyak 20).
func (s *Server) recentPlayers(w http.ResponseWriter, r *http.Request) {
	names, err := s.store.RecentPlayers(r.Context(), playerFrom(r).ID, s.clock().Add(-recentPlayersDays*24*time.Hour), recentPlayersLimit)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string][]string{"players": names})
}
