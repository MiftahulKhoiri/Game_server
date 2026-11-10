package api

import (
	"net/http"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Dunia yang hidup (roadmap no. 186-200).

type secretRequest struct {
	ID string `json:"id"`
}

type secretHint struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Map   string `json:"map"`
	X     int    `json:"x"`
	Y     int    `json:"y"`
	Hint  string `json:"hint"`
	Found bool   `json:"found"`
}

// worldEvents: jam dunia, cuaca, kejadian dunia, wilayah, petunjuk tempat rahasia, dan kemajuan
// pertahanan desa pemain.
func (s *Server) worldEvents(w http.ResponseWriter, r *http.Request) {
	unix := game.Now()
	p, err := s.store.PlayerByID(r.Context(), playerFrom(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	st := p.State
	secrets := make([]secretHint, 0, len(game.Secrets))
	for _, sec := range game.Secrets {
		found := false
		for _, id := range st.Secrets {
			found = found || id == sec.ID
		}
		secrets = append(secrets, secretHint{sec.ID, sec.Name, sec.Map, sec.X, sec.Y, sec.Hint, found})
	}
	raid := st.Raid
	if raid.ID != game.RaidID(unix) {
		raid = game.RaidProgress{ID: game.RaidID(unix)}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"unix": unix, "hour": game.WorldHour(unix), "day": game.WorldDay(unix),
		"night": game.IsNightAt(unix), "raining": game.RainingAt(unix),
		"events": game.Events(unix), "zones": game.Zones, "secrets": secrets,
		"raid": raid, "raid_goal": game.RaidGoal, "raid_reward": game.RaidRewardG,
		"visited": st.Visited, "explore": game.ExploreMaps,
	})
}

func (s *Server) findSecret(w http.ResponseWriter, r *http.Request) {
	var req secretRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error {
		_, err := st.FindSecret(req.ID)
		return err
	})
}

func (s *Server) claimRaid(w http.ResponseWriter, r *http.Request) {
	s.applyToState(w, r, func(st *game.State) error { return st.ClaimRaid(game.Now()) })
}
