package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/catalog"
)

// Platform multi-game (v0.84.0): katalog game unduhan dan progres per game. Isi katalog dibuat dan
// ditandatangani scripts/build-game-pack.sh; server hanya melayani berkasnya (lihat internal/catalog).
//
// Tanpa login (katalog publik):
//
//	GET /v1/games                     catalog.json (byte persis yang ditandatangani)
//	GET /v1/games/catalog.sig         tanda tangan katalog (base64)
//	GET /v1/games/{id}                satu entri katalog (JSON, untuk tampilan; klien memakai versi bertanda tangan)
//	GET /v1/games/{id}/version        {"id","version"}
//	GET /v1/games/{id}/manifest       manifest.json (byte persis yang ditandatangani)
//	GET /v1/games/{id}/manifest.sig   tanda tangan manifest
//	GET /v1/games/{id}/download       berkas .pck (mendukung HTTP Range untuk melanjutkan unduhan)
//	GET /v1/games/{id}/icon           icon.png game (diverifikasi klien dengan icon_sha256 di manifest)
//
// Butuh login (Authorization: Bearer):
//
//	GET  /v1/games/{id}/progress      progres pemain di game itu ({} bila belum ada)
//	POST /v1/games/{id}/progress      simpan progres {"schema_version", "data": {...}, "updated_at"}

// CatalogDir memasang folder katalog game platform. dir kosong = endpoint ada tetapi katalog kosong (404).
func CatalogDir(dir string) Option {
	return func(o *options) { o.catalogDir = dir }
}

// maxGameProgressBytes membatasi data progres satu game (sama dengan batas badan permintaan umum).
const maxGameProgressBytes = maxBodyBytes

func (s *Server) registerGames(mux *http.ServeMux, dir string) {
	c := catalog.New(dir)
	mux.HandleFunc("GET /v1/games", func(w http.ResponseWriter, r *http.Request) {
		raw, _, err := c.CatalogFile()
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		writeRaw(w, "application/json; charset=utf-8", raw)
	})
	mux.HandleFunc("GET /v1/games/catalog.sig", func(w http.ResponseWriter, r *http.Request) {
		_, sig, err := c.CatalogFile()
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		writeRaw(w, "text/plain; charset=utf-8", sig)
	})
	mux.HandleFunc("GET /v1/games/{id}", func(w http.ResponseWriter, r *http.Request) {
		e, err := c.Entry(r.PathValue("id"))
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, e)
	})
	mux.HandleFunc("GET /v1/games/{id}/version", func(w http.ResponseWriter, r *http.Request) {
		_, _, m, err := c.ManifestFile(r.PathValue("id"))
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"id": m.ID, "version": m.Version})
	})
	mux.HandleFunc("GET /v1/games/{id}/manifest", func(w http.ResponseWriter, r *http.Request) {
		raw, _, _, err := c.ManifestFile(r.PathValue("id"))
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		writeRaw(w, "application/json; charset=utf-8", raw)
	})
	mux.HandleFunc("GET /v1/games/{id}/manifest.sig", func(w http.ResponseWriter, r *http.Request) {
		_, sig, _, err := c.ManifestFile(r.PathValue("id"))
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		writeRaw(w, "text/plain; charset=utf-8", sig)
	})
	mux.HandleFunc("GET /v1/games/{id}/download", func(w http.ResponseWriter, r *http.Request) {
		p, m, err := c.PackagePath(r.PathValue("id"))
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		// Paket bisa besar dan lewat data seluler: beri batas tulis lebih panjang dari batas umum (15 d).
		_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(15 * time.Minute))
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("X-Package-SHA256", m.SHA256)
		w.Header().Set("Content-Disposition", `attachment; filename="`+m.Package+`"`)
		// ServeFile melayani HTTP Range (206) sehingga unduhan yang putus bisa dilanjutkan.
		http.ServeFile(w, r, p)
	})
	mux.HandleFunc("GET /v1/games/{id}/icon", func(w http.ResponseWriter, r *http.Request) {
		b, err := c.Icon(r.PathValue("id"))
		if err != nil {
			s.catalogError(w, r, err)
			return
		}
		w.Header().Set("Cache-Control", "public, max-age=3600")
		writeRaw(w, "image/png", b)
	})
	mux.Handle("GET /v1/games/{id}/progress", s.auth(http.HandlerFunc(s.getGameProgress)))
	mux.Handle("POST /v1/games/{id}/progress", s.auth(http.HandlerFunc(s.putGameProgress)))
}

func (s *Server) catalogError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, catalog.ErrNotFound):
		writeError(w, http.StatusNotFound, "game atau katalog tidak ditemukan")
	case errors.Is(err, catalog.ErrInvalid):
		s.log.Warn("katalog game tidak sah", "path", r.URL.Path, "err", err)
		writeError(w, http.StatusServiceUnavailable, "katalog game sedang rusak di server")
	default:
		s.fail(w, r, err)
	}
}

func writeRaw(w http.ResponseWriter, contentType string, b []byte) {
	w.Header().Set("Content-Type", contentType)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(b)
}

// gameIDForProgress: progres hanya untuk game platform selain Game Petualangan (yang progresnya di
// players.state). Game tidak harus ada di katalog (game bawaan masa depan juga boleh menyimpan progres).
func gameIDForProgress(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := r.PathValue("id")
	if !catalog.ValidID(id) || id == "adventure" {
		writeError(w, http.StatusBadRequest, "id game tidak sah")
		return "", false
	}
	return id, true
}

type gameProgressOut struct {
	GameID        string          `json:"game_id"`
	SchemaVersion int             `json:"schema_version"`
	Data          json.RawMessage `json:"data"`
	UpdatedAt     string          `json:"updated_at,omitempty"`
	ClientUpdated string          `json:"client_updated,omitempty"`
	Revision      int             `json:"revision"`
}

func (s *Server) getGameProgress(w http.ResponseWriter, r *http.Request) {
	id, ok := gameIDForProgress(w, r)
	if !ok {
		return
	}
	g, found, err := s.store.GetGameProgress(r.Context(), playerFrom(r).ID, id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if !found {
		writeJSON(w, http.StatusOK, gameProgressOut{GameID: id, Data: json.RawMessage(`{}`)})
		return
	}
	writeJSON(w, http.StatusOK, gameProgressOut{GameID: id, SchemaVersion: g.SchemaVersion, Data: json.RawMessage(g.Data),
		UpdatedAt: g.UpdatedAt, ClientUpdated: g.ClientUpdated, Revision: g.Revision})
}

func (s *Server) putGameProgress(w http.ResponseWriter, r *http.Request) {
	id, ok := gameIDForProgress(w, r)
	if !ok {
		return
	}
	var in struct {
		SchemaVersion int             `json:"schema_version"`
		Data          json.RawMessage `json:"data"`
		UpdatedAt     string          `json:"updated_at"`
	}
	if !decode(w, r, &in) {
		return
	}
	data := strings.TrimSpace(string(in.Data))
	var obj map[string]any
	switch {
	case in.SchemaVersion < 1 || in.SchemaVersion > 1000:
		writeError(w, http.StatusBadRequest, "schema_version harus 1..1000")
		return
	case len(data) == 0 || data[0] != '{' || json.Unmarshal([]byte(data), &obj) != nil:
		writeError(w, http.StatusBadRequest, "data harus objek JSON")
		return
	case len(data) > maxGameProgressBytes:
		writeError(w, http.StatusRequestEntityTooLarge, "data progres terlalu besar")
		return
	case len(in.UpdatedAt) > 40:
		writeError(w, http.StatusBadRequest, "updated_at terlalu panjang")
		return
	}
	g, err := s.store.PutGameProgress(r.Context(), playerFrom(r).ID, id, in.SchemaVersion, data, in.UpdatedAt, s.clock())
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, gameProgressOut{GameID: id, SchemaVersion: g.SchemaVersion, Data: json.RawMessage(g.Data),
		UpdatedAt: g.UpdatedAt, ClientUpdated: g.ClientUpdated, Revision: g.Revision})
}
