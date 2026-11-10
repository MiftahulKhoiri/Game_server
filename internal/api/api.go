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
	"net"
	"net/http"
	"regexp"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/auth"
	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
	"github.com/MiftahulKhoiri/Game_server/internal/version"
)

const maxBodyBytes = 64 << 10 // 64 KiB

var nameRe = regexp.MustCompile(`^[A-Za-z0-9_]{3,20}$`)

type ctxKey struct{}

// tokenKey: hash token permintaan ini (untuk daftar sesi / keluar dari perangkat lain).
type tokenKey struct{}

// reqInfo diisi sepanjang permintaan untuk catatan log (pemain diisi oleh middleware auth).
type reqInfo struct{ player string }

type reqInfoKey struct{}

// Server adalah kumpulan handler HTTP.
type Server struct {
	store *store.Store
	log   *slog.Logger
	info  version.Info
	rng   game.Rand
	clock func() time.Time // jam server (dapat diganti di tes)

	// Pembatas percobaan: login gagal per nama/email dan per IP, serta pendaftaran per IP.
	loginByName *auth.Limiter
	loginByIP   *auth.Limiter
	signupByIP  *auth.Limiter
}

// New membuat http.Handler lengkap dengan routing.
func New(st *store.Store, log *slog.Logger, info version.Info) http.Handler {
	return NewWithRand(st, log, info, game.RandomSource{})
}

// NewWithRand sama seperti New tetapi dengan sumber acak buatan sendiri (untuk tes).
func NewWithRand(st *store.Store, log *slog.Logger, info version.Info, rng game.Rand) http.Handler {
	return NewWithClock(st, log, info, rng, time.Now)
}

// NewWithClock sama seperti NewWithRand tetapi dengan jam buatan sendiri (untuk tes
// pertarungan real-time).
func NewWithClock(st *store.Store, log *slog.Logger, info version.Info, rng game.Rand, clock func() time.Time) http.Handler {
	s := &Server{
		store: st, log: log, info: info, rng: rng, clock: clock,
		loginByName: auth.NewLimiter(5, 15*time.Minute),
		loginByIP:   auth.NewLimiter(30, 15*time.Minute),
		signupByIP:  auth.NewLimiter(20, time.Hour),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /v1/version", s.versionInfo)
	mux.HandleFunc("POST /v1/players", s.createPlayer)
	mux.HandleFunc("POST /v1/login", s.login)
	mux.Handle("POST /v1/logout", s.auth(http.HandlerFunc(s.logout)))
	mux.Handle("POST /v1/logout/others", s.auth(http.HandlerFunc(s.logoutOthers)))
	mux.Handle("GET /v1/sessions", s.auth(http.HandlerFunc(s.listSessions)))
	mux.Handle("POST /v1/players/me/password", s.auth(http.HandlerFunc(s.changePassword)))
	mux.Handle("GET /v1/players/me", s.auth(http.HandlerFunc(s.getMe)))
	mux.Handle("PUT /v1/players/me/save", s.auth(http.HandlerFunc(s.saveMe)))
	mux.Handle("GET /v1/battle", s.auth(http.HandlerFunc(s.getBattle)))
	mux.Handle("POST /v1/battle/start", s.auth(http.HandlerFunc(s.startBattle)))
	mux.Handle("POST /v1/battle/action", s.auth(http.HandlerFunc(s.battleAction)))
	mux.Handle("GET /v1/quests", s.auth(http.HandlerFunc(s.getQuests)))
	mux.Handle("POST /v1/quests/accept", s.auth(http.HandlerFunc(s.questAction(false))))
	mux.Handle("POST /v1/quests/claim", s.auth(http.HandlerFunc(s.questAction(true))))
	mux.Handle("POST /v1/inventory/use", s.auth(s.itemAction(func(st *game.State, item string) error { return st.UseItem(item) })))
	mux.Handle("POST /v1/inventory/equip", s.auth(s.itemAction(func(st *game.State, item string) error { return st.Equip(item) })))
	mux.Handle("POST /v1/inventory/unequip", s.auth(s.slotAction()))
	mux.Handle("POST /v1/rest", s.auth(s.restAction()))
	mux.Handle("GET /v1/heroes", s.auth(http.HandlerFunc(s.getHeroes)))
	mux.Handle("POST /v1/players/me/hero", s.auth(http.HandlerFunc(s.setHero)))
	mux.Handle("POST /v1/players/me/outfit", s.auth(http.HandlerFunc(s.setOutfit)))
	mux.Handle("POST /v1/warga/talk", s.auth(http.HandlerFunc(s.wargaTalk)))
	mux.Handle("POST /v1/house/buy", s.auth(http.HandlerFunc(s.buyHouse)))
	mux.Handle("GET /v1/progress", s.auth(http.HandlerFunc(s.progressInfo)))
	mux.Handle("POST /v1/craft", s.auth(http.HandlerFunc(s.craft)))
	mux.Handle("POST /v1/talent", s.auth(http.HandlerFunc(s.learnTalent)))
	mux.Handle("POST /v1/achievements/claim", s.auth(http.HandlerFunc(s.claimAchievement)))
	mux.Handle("POST /v1/allies/buy", s.auth(http.HandlerFunc(s.buyAlly)))
	mux.Handle("POST /v1/allies/heal", s.auth(http.HandlerFunc(s.healAlly)))
	mux.Handle("POST /v1/soldiers/buy", s.auth(http.HandlerFunc(s.buySoldier)))
	mux.Handle("POST /v1/soldiers/deploy", s.auth(http.HandlerFunc(s.deploySoldiers)))
	mux.HandleFunc("GET /v1/time", s.serverTime)
	mux.Handle("POST /v1/train/start", s.auth(http.HandlerFunc(s.trainStart)))
	mux.Handle("POST /v1/train/claim", s.auth(http.HandlerFunc(s.trainClaim)))
	mux.Handle("POST /v1/party", s.auth(http.HandlerFunc(s.setParty)))
	mux.Handle("GET /v1/world", s.auth(http.HandlerFunc(s.worldState)))
	mux.Handle("POST /v1/world/break", s.auth(http.HandlerFunc(s.worldBreak)))
	mux.Handle("POST /v1/hutan/brief", s.auth(http.HandlerFunc(s.hutanBrief)))
	mux.Handle("POST /v1/world/chest", s.auth(http.HandlerFunc(s.worldChest)))
	mux.Handle("GET /v1/world/events", s.auth(http.HandlerFunc(s.worldEvents)))
	mux.Handle("POST /v1/world/secret", s.auth(http.HandlerFunc(s.findSecret)))
	mux.Handle("POST /v1/world/raid/claim", s.auth(http.HandlerFunc(s.claimRaid)))
	mux.Handle("POST /v1/bank/deposit", s.auth(s.bankAction(true)))
	mux.Handle("POST /v1/bank/withdraw", s.auth(s.bankAction(false)))
	mux.Handle("POST /v1/storage/put", s.auth(s.storageAction(true)))
	mux.Handle("POST /v1/storage/take", s.auth(s.storageAction(false)))
	mux.Handle("GET /v1/trades", s.auth(http.HandlerFunc(s.listTrades)))
	mux.Handle("POST /v1/trades", s.auth(http.HandlerFunc(s.createTrade)))
	mux.Handle("POST /v1/trades/accept", s.auth(s.finishTrade(true)))
	mux.Handle("POST /v1/trades/cancel", s.auth(s.finishTrade(false)))
	mux.Handle("GET /v1/shop", s.auth(http.HandlerFunc(s.getShop)))
	mux.Handle("POST /v1/shop/buy", s.auth(http.HandlerFunc(s.shopTrade(game.BuyAt))))
	mux.Handle("POST /v1/shop/barter", s.auth(http.HandlerFunc(s.shopTrade(game.BarterAt))))
	mux.Handle("POST /v1/shop/sell", s.auth(http.HandlerFunc(s.shopTrade(game.SellAt))))
	// Jalur yang tidak dikenal dijawab JSON (bukan teks bawaan Go) supaya klien selalu bisa membacanya.
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "jalur tidak dikenal: "+r.Method+" "+r.URL.Path)
	})
	return s.logRequests(s.recoverPanic(s.clientGate(mux)))
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
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

// createResponse dipakai untuk daftar dan login: pemain beserta token sesi baru.
type createResponse struct {
	Player game.Player `json:"player"`
	// Token dipakai klien sebagai "Authorization: Bearer"; hanya ditampilkan sekali di sini.
	Token string `json:"token"`
}

func (s *Server) createPlayer(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if !decode(w, r, &req) {
		return
	}
	ip := clientIP(r)
	if s.tooMany(w, s.signupByIP, ip) {
		return
	}
	s.signupByIP.Fail(ip) // setiap percobaan daftar dihitung
	req.Name = strings.TrimSpace(req.Name)
	if !nameRe.MatchString(req.Name) {
		writeError(w, http.StatusUnprocessableEntity, "nama harus 3-20 karakter: huruf, angka, atau _")
		return
	}
	email, err := auth.NormalizeEmail(req.Email)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	if err := auth.ValidatePassword(req.Password); err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	if strings.EqualFold(req.Password, req.Name) || strings.EqualFold(req.Password, email) {
		writeError(w, http.StatusUnprocessableEntity, "kata sandi tidak boleh sama dengan nama atau email")
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
	pwHash, err := auth.Hash(req.Password)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	p, err := s.store.CreatePlayer(r.Context(), id, req.Name, email, pwHash, hashToken(token), game.NewState())
	switch {
	case errors.Is(err, store.ErrNameTaken):
		writeError(w, http.StatusConflict, "nama sudah dipakai")
	case errors.Is(err, store.ErrEmailTaken):
		writeError(w, http.StatusConflict, "email sudah terdaftar")
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusCreated, createResponse{Player: p, Token: token})
	}
}

type loginRequest struct {
	// Login berisi nama pemain ATAU email.
	Login    string `json:"login"`
	Password string `json:"password"`
}

const badLogin = "nama/email atau kata sandi salah"

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if !decode(w, r, &req) {
		return
	}
	req.Login = strings.TrimSpace(req.Login)
	if req.Login == "" || req.Password == "" {
		writeError(w, http.StatusUnprocessableEntity, "isi nama (atau email) dan kata sandi")
		return
	}
	key, ip := strings.ToLower(req.Login), clientIP(r)
	if s.tooMany(w, s.loginByName, key) || s.tooMany(w, s.loginByIP, ip) {
		return
	}
	reject := func() {
		s.loginByName.Fail(key)
		s.loginByIP.Fail(ip)
		writeError(w, http.StatusUnauthorized, badLogin)
	}
	if len(req.Password) > auth.MaxPassword || len(req.Login) > 254 {
		reject()
		return
	}
	p, hash, err := s.store.PlayerByLogin(r.Context(), req.Login)
	switch {
	case errors.Is(err, store.ErrNotFound), err == nil && hash == "": // tidak ada, atau akun lama tanpa kata sandi
		auth.BurnTime(req.Password) // samakan lama jawaban agar akun yang ada tidak bisa ditebak
		reject()
		return
	case err != nil:
		s.fail(w, r, err)
		return
	case !auth.Verify(req.Password, hash):
		reject()
		return
	}
	token, err := randomHex(32)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if err := s.store.CreateSession(r.Context(), p.ID, hashToken(token)); err != nil {
		s.fail(w, r, err)
		return
	}
	s.loginByName.Reset(key)
	// Hash lama (putaran PBKDF2 lebih sedikit) diperbarui diam-diam saat kata sandinya terbukti benar.
	if auth.NeedsRehash(hash) {
		if nh, err := auth.Hash(req.Password); err == nil {
			if err := s.store.SetPassword(r.Context(), p.ID, nh, ""); err != nil {
				s.log.Warn("gagal memperbarui hash kata sandi", "player", p.ID, "err", err)
			}
		}
	}
	writeJSON(w, http.StatusOK, createResponse{Player: p, Token: token})
}

// logout mencabut token yang dipakai permintaan ini; token di perangkat lain tetap hidup.
func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	token, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if err := s.store.DeleteSession(r.Context(), hashToken(token)); err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// tooMany menjawab 429 bila kunci sedang diblokir pembatas; true berarti sudah dijawab.
func (s *Server) tooMany(w http.ResponseWriter, l *auth.Limiter, key string) bool {
	wait, blocked := l.Blocked(key)
	if !blocked {
		return false
	}
	secs := int(wait.Seconds()) + 1
	w.Header().Set("Retry-After", strconv.Itoa(secs))
	writeError(w, http.StatusTooManyRequests, "terlalu banyak percobaan; coba lagi dalam "+strconv.Itoa(secs)+" detik")
	return true
}

// clientIP mengambil alamat peminta. Header proxy (Cloudflare / X-Forwarded-For) hanya dipercaya
// bila sambungan datang dari mesin ini sendiri (proxy lokal), supaya tidak bisa dipalsukan dari luar.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		for _, h := range []string{"CF-Connecting-IP", "X-Forwarded-For"} {
			first := strings.TrimSpace(strings.Split(r.Header.Get(h), ",")[0])
			if net.ParseIP(first) != nil {
				return first
			}
		}
	}
	return host
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
	// Server otoritatif: hanya posisi yang diterima dari klien, dan harus di dalam peta yang dikenal.
	st := req.State
	pose, ok := game.NormalizePose(game.Pose{Map: st.Map, X: st.X, Y: st.Y, FX: st.FX, FZ: st.FZ, Yaw: st.Yaw})
	if !ok {
		writeError(w, http.StatusUnprocessableEntity, "posisi di luar peta atau peta tidak dikenal")
		return
	}
	s.watchMovement(playerFrom(r), pose)
	p, err := s.store.SavePosition(r.Context(), playerFrom(r).ID, pose, req.Version)
	switch {
	case errors.Is(err, store.ErrConflict):
		writeError(w, http.StatusConflict, "versi data tidak cocok; ambil data terbaru dulu")
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "pemain tidak ditemukan")
	case errors.Is(err, game.ErrHouseLocked):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
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
	Battle  *game.BattleView `json:"battle"`
	Player  game.Player      `json:"player"`
	Status  string           `json:"status,omitempty"`
	Log     []string         `json:"log,omitempty"`
	Events  []game.Event     `json:"events,omitempty"`
	Rewards *game.Rewards    `json:"rewards,omitempty"`
}

func (s *Server) nowMs() int64 { return s.clock().UnixMilli() }

func battleView(b *game.Battle, now int64) *game.BattleView {
	if b == nil {
		return nil
	}
	v := b.View(now)
	return &v
}

// getBattle melanjutkan pertarungan sekaligus menyelesaikan serangan musuh yang jatuh tempo.
func (s *Server) getBattle(w http.ResponseWriter, r *http.Request) {
	now := s.nowMs()
	var result game.Result
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle == nil {
			return errNoBattle
		}
		res, err := sess.Battle.Sync(&sess.Player, now, s.rng)
		if err != nil {
			return err
		}
		result = res
		if res.Status != game.StatusOngoing {
			sess.Battle = nil
		}
		return nil
	})
	switch {
	case errors.Is(err, errNoBattle):
		writeError(w, http.StatusNotFound, errNoBattle.Error())
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusOK, battleResponse{
			Battle: battleView(sess.Battle, now), Player: sess.Player,
			Status: result.Status, Log: result.Log, Events: result.Events, Rewards: result.Rewards,
		})
	}
}

type startRequest struct {
	// Boss meminta pertarungan dengan bos di petak pemain (bukan musuh acak).
	Boss bool `json:"boss"`
	// Enemy (opsional) adalah id musuh berkeliaran yang disentuh pemain; dipakai bila sah di peta ini.
	Enemy string `json:"enemy"`
}

func (s *Server) startBattle(w http.ResponseWriter, r *http.Request) {
	var req startRequest
	if r.ContentLength != 0 && !decode(w, r, &req) { // body boleh kosong
		return
	}
	now := s.nowMs()
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle != nil {
			return errBattleActive
		}
		var b game.Battle
		if req.Boss {
			var err error
			if b, err = game.StartBossBattle(&sess.Player, now); err != nil {
				return err
			}
		} else if game.IsHutanBossID(req.Enemy) {
			var err error
			if b, err = game.StartHutanBossBattle(&sess.Player, now); err != nil {
				return err
			}
			if b.EnemyID != req.Enemy {
				return game.ErrBossNotReady // bos tahap lain: belum waktunya
			}
		} else {
			if st := &sess.Player.State; st.Map == game.MapHutanLebat && !st.Hutan.Started() {
				return game.ErrNotBriefed // belum bicara dengan Kapten Rimba
			}
			b = game.StartBattleWith(&sess.Player, req.Enemy, s.rng, now)
		}
		sess.Battle = &b
		return nil
	})
	switch {
	case errors.Is(err, game.ErrNoBoss), errors.Is(err, game.ErrBossNotReady), errors.Is(err, game.ErrNotBriefed):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	case errors.Is(err, errBattleActive):
		writeError(w, http.StatusConflict, "masih ada pertarungan yang berjalan; lanjutkan lewat GET /v1/battle")
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusCreated, battleResponse{Battle: battleView(sess.Battle, now), Player: sess.Player, Status: game.StatusOngoing})
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
	now := s.nowMs()
	var result game.Result
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle == nil {
			return errNoBattle
		}
		res, err := sess.Battle.Act(&sess.Player, req.Action, now, s.rng)
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
	case errors.Is(err, game.ErrBadAction), errors.Is(err, game.ErrNoPotion), errors.Is(err, game.ErrFullHP), errors.Is(err, game.ErrCooldown), errors.Is(err, game.ErrNoEnergy):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusOK, battleResponse{
			Battle: battleView(sess.Battle, now), Player: sess.Player,
			Status: result.Status, Log: result.Log, Events: result.Events, Rewards: result.Rewards,
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
	RewardText string           `json:"reward_text,omitempty"`
}

// questAction membuat handler terima misi (claim=false) atau ambil hadiah (claim=true).
func (s *Server) questAction(claim bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req questRequest
		if !decode(w, r, &req) {
			return
		}
		var claimed game.QuestDef
		sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
			if sess.Battle != nil {
				return errBattleActive
			}
			if claim {
				def, err := sess.Player.State.ClaimQuest(req.Quest)
				claimed = def
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
		case errors.Is(err, game.ErrQuestNotReady), errors.Is(err, game.ErrTooManyQuests),
			errors.Is(err, game.ErrQuestLocked), errors.Is(err, game.ErrInventoryFull):
			writeError(w, http.StatusUnprocessableEntity, err.Error())
		case err != nil:
			s.fail(w, r, err)
		default:
			writeJSON(w, http.StatusOK, questResponse{Player: sess.Player, Quests: sess.Player.State.QuestViews(), RewardGold: claimed.RewardGold, RewardText: claimed.RewardText()})
		}
	}
}

// --- tas, perlengkapan, istirahat ---

type itemRequest struct {
	Item string `json:"item"`
}

type slotRequest struct {
	Slot string `json:"slot"`
}

// applyToState menjalankan fn atas state pemain secara atomik (ditolak saat bertarung)
// lalu menjawab dengan pemain terbaru atau kode kesalahan yang sesuai.
func (s *Server) applyToState(w http.ResponseWriter, r *http.Request, fn func(*game.State) error) {
	sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
		if sess.Battle != nil {
			return errBattleActive
		}
		return fn(&sess.Player.State)
	})
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, sess.Player)
	case errors.Is(err, errBattleActive):
		writeError(w, http.StatusConflict, "tidak bisa dilakukan saat bertarung")
	case errors.Is(err, game.ErrUnknownItem):
		writeError(w, http.StatusNotFound, err.Error())
	case isRuleError(err):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	default:
		s.fail(w, r, err)
	}
}

// isRuleError: pelanggaran aturan game (bukan kesalahan server).
func isRuleError(err error) bool {
	for _, e := range []error{
		game.ErrNotEquippable, game.ErrNotEnough, game.ErrNothingWorn, game.ErrBadSlot,
		game.ErrNotUsable, game.ErrNoPotion, game.ErrFullHP, game.ErrCannotRest, game.ErrUnknownHero, game.ErrUnknownOutfit, game.ErrUnknownWarga, game.ErrHouseOwned, game.ErrHouseLocked, game.ErrHouseFar,
		game.ErrUnknownRecipe, game.ErrCraftFar, game.ErrUnknownTalent, game.ErrTalentMax, game.ErrTalentLocked, game.ErrNoTalentPoints, game.ErrBadQty,
		game.ErrUnknownAchievement, game.ErrAchievementLocked, game.ErrAchievementTaken, game.ErrNoPower,
		game.ErrAllyOwned, game.ErrAllyNotOwn, game.ErrAllyUnavailable, game.ErrAllyFullHP, game.ErrPartyFull, game.ErrPartyRepeat, game.ErrNoGold, game.ErrSoldiersMax, game.ErrSoldiersCount,
		game.ErrTrainBusy, game.ErrTrainMax, game.ErrTrainNoCard, game.ErrTrainNone, game.ErrTrainNotReady, game.ErrTrainKind, game.ErrTrainNoSquad, game.ErrTrainLocation, game.ErrNoEnergy, game.ErrNoKapten, game.ErrInventoryFull,
		game.ErrBankFar, game.ErrBankEmpty, game.ErrBankFull, game.ErrGoldMax, game.ErrBadAmount, game.ErrStorageFar, game.ErrStorageFull,
		game.ErrNotStored, game.ErrBadPrice, game.ErrNotTradable, game.ErrEquipped, store.ErrInvalidState,
		game.ErrUnknownSecret, game.ErrSecretFar, game.ErrSecretFound, game.ErrNoRaid, game.ErrRaidGoal, game.ErrRaidClaimed,
	} {
		if errors.Is(err, e) {
			return true
		}
	}
	return false
}

func (s *Server) itemAction(fn func(*game.State, string) error) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req itemRequest
		if !decode(w, r, &req) {
			return
		}
		s.applyToState(w, r, func(st *game.State) error { return fn(st, req.Item) })
	})
}

func (s *Server) slotAction() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req slotRequest
		if !decode(w, r, &req) {
			return
		}
		s.applyToState(w, r, func(st *game.State) error { return st.Unequip(req.Slot) })
	})
}

type healAllyRequest struct {
	Hero string `json:"hero"`
}

// healAlly memakai satu ramuan untuk memulihkan pahlawan pendamping yang terpasang.
// Perubahan HP dan inventaris tersimpan sebagai satu transaksi pemain.
func (s *Server) healAlly(w http.ResponseWriter, r *http.Request) {
	var req healAllyRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error {
		hp, maxHP, ok := st.AllyHealth(req.Hero)
		if !ok {
			return game.ErrAllyUnavailable
		}
		if hp >= maxHP {
			return game.ErrAllyFullHP
		}
		if !st.RemoveItem(game.PotionID, 1) {
			return game.ErrNoPotion
		}
		_, err := st.HealAlly(req.Hero, game.PotionHeal)
		return err
	})
}

func (s *Server) getHeroes(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"heroes": game.Heroes, "default": game.DefaultHero})
}

type heroRequest struct {
	Hero string `json:"hero"`
}

// setHero mengganti pahlawan yang dipakai (tidak bisa saat bertarung).
func (s *Server) setHero(w http.ResponseWriter, r *http.Request) {
	var req heroRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.SetHero(req.Hero) })
}

type outfitRequest struct {
	Outfit int `json:"outfit"`
}

// setOutfit mengganti variasi pakaian pahlawan (roadmap no. 14). Mengembalikan Player.
func (s *Server) setOutfit(w http.ResponseWriter, r *http.Request) {
	var req outfitRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.SetOutfit(req.Outfit) })
}

type wargaRequest struct {
	Warga string `json:"warga"`
}

// wargaTalk mencatat pembicaraan dengan warga (ingatan + keakraban, roadmap no. 58-59). Mengembalikan Player.
func (s *Server) wargaTalk(w http.ResponseWriter, r *http.Request) {
	var req wargaRequest
	if !decode(w, r, &req) {
		return
	}
	now := s.clock().Unix()
	s.applyToState(w, r, func(st *game.State) error { return st.TalkTo(req.Warga, now) })
}

// progressInfo: resep tempa, pohon kemampuan, dan daftar pencapaian (roadmap no. 139, 145, 150).
func (s *Server) progressInfo(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"recipes": game.Recipes, "talents": game.Talents, "achievements": game.Achievements,
	})
}

type craftRequest struct {
	Recipe string `json:"recipe"`
	Qty    int    `json:"qty"`
}

// craft menempa barang dari bahan (hanya di desa). Mengembalikan Player.
func (s *Server) craft(w http.ResponseWriter, r *http.Request) {
	var req craftRequest
	if !decode(w, r, &req) {
		return
	}
	if req.Qty == 0 {
		req.Qty = 1
	}
	s.applyToState(w, r, func(st *game.State) error { return st.Craft(req.Recipe, req.Qty) })
}

type talentRequest struct {
	Talent string `json:"talent"`
}

// learnTalent menaikkan satu peringkat kemampuan dengan poin kemampuan. Mengembalikan Player.
func (s *Server) learnTalent(w http.ResponseWriter, r *http.Request) {
	var req talentRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.LearnTalent(req.Talent) })
}

type achievementRequest struct {
	Achievement string `json:"achievement"`
}

// claimAchievement mengambil hadiah emas pencapaian yang sudah terbuka. Mengembalikan Player.
func (s *Server) claimAchievement(w http.ResponseWriter, r *http.Request) {
	var req achievementRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.ClaimAchievement(req.Achievement) })
}

// buyHouse membeli rumah di Desa Awal (roadmap no. 127). Mengembalikan Player.
func (s *Server) buyHouse(w http.ResponseWriter, r *http.Request) {
	s.applyToState(w, r, func(st *game.State) error { return st.BuyHouse() })
}

// buyAlly membeli pahlawan sebagai pendamping (tidak bisa saat bertarung).
func (s *Server) buyAlly(w http.ResponseWriter, r *http.Request) {
	var req heroRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.BuyAlly(req.Hero) })
}

// hutanBrief: pemain bicara dengan Kapten Rimba di kem hutan (Perbatasan). Memberi Radar Musuh dan membuka
// pertarungan di Hutan Lebat. Mengembalikan Player.
func (s *Server) hutanBrief(w http.ResponseWriter, r *http.Request) {
	s.applyToState(w, r, func(st *game.State) error { return st.BriefHutan() })
}

// buySoldier membeli satu prajurit biasa (tidak bisa saat bertarung).
func (s *Server) buySoldier(w http.ResponseWriter, r *http.Request) {
	s.applyToState(w, r, func(st *game.State) error { return st.BuySoldier() })
}

type deployRequest struct {
	Count int `json:"count"`
}

// deploySoldiers memasang `count` prajurit untuk ikut bertarung (0..jumlah prajurit); sisanya menunggu di kem.
func (s *Server) deploySoldiers(w http.ResponseWriter, r *http.Request) {
	var req deployRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.SetActiveSoldiers(req.Count) })
}

// serverTime: jam server (detik Unix) untuk menghitung sisa waktu latihan di klien.
func (s *Server) serverTime(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]int64{"unix": s.clock().Unix()})
}

type trainRequest struct {
	Kind   string `json:"kind"`
	Target string `json:"target,omitempty"`
}

// trainStart memulai latihan di Aula Pelatihan (jenis "pahlawan" + target, atau "prajurit").
func (s *Server) trainStart(w http.ResponseWriter, r *http.Request) {
	var req trainRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.StartTrain(req.Kind, req.Target, s.clock().Unix()) })
}

// trainClaim mengambil hasil latihan yang sudah selesai.
func (s *Server) trainClaim(w http.ResponseWriter, r *http.Request) {
	var req trainRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.ClaimTrain(req.Kind, s.clock().Unix()) })
}

type partyRequest struct {
	Party []string `json:"party"`
}

// setParty menetapkan pendamping yang dipasang di belakang pemain.
func (s *Server) setParty(w http.ResponseWriter, r *http.Request) {
	var req partyRequest
	if !decode(w, r, &req) {
		return
	}
	s.applyToState(w, r, func(st *game.State) error { return st.SetParty(req.Party) })
}

func (s *Server) restAction() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.applyToState(w, r, func(st *game.State) error { return st.Rest() })
	})
}

// --- toko ---

// getShop: katalog satu toko (?shop=toko|makan|peralatan; kosong = toko ramuan) berisi barang yang dijual
// dan yang bisa dijual pemain ke sana.
func (s *Server) getShop(w http.ResponseWriter, r *http.Request) {
	shop := r.URL.Query().Get("shop")
	if shop == "" {
		shop = game.ShopPotion
	}
	if shop == "semua" { // seluruh daftar barang (nama dan jenis), untuk ransel
		writeJSON(w, http.StatusOK, map[string]any{"shop": shop, "items": game.Items()})
		return
	}
	list, err := game.ShopItems(shop)
	if err != nil {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"shop": shop, "items": list})
}

type tradeRequest struct {
	Shop string `json:"shop"` // toko tempat transaksi (kosong = toko ramuan)
	Item string `json:"item"`
	Qty  int    `json:"qty"`
}

// shopTrade membuat handler jual/beli. Transaksi atomik: gagal berarti tidak ada yang berubah.
func (s *Server) shopTrade(trade func(*game.State, string, string, int) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req tradeRequest
		if !decode(w, r, &req) {
			return
		}
		sess, err := s.store.Update(r.Context(), playerFrom(r).ID, func(sess *store.Session) error {
			if sess.Battle != nil {
				return errBattleActive
			}
			shop := req.Shop
			if shop == "" {
				shop = game.ShopPotion
			}
			return trade(&sess.Player.State, shop, req.Item, req.Qty)
		})
		switch {
		case errors.Is(err, errBattleActive):
			writeError(w, http.StatusConflict, "tidak bisa berdagang saat bertarung")
		case errors.Is(err, game.ErrUnknownItem), errors.Is(err, game.ErrUnknownShop):
			writeError(w, http.StatusNotFound, err.Error())
		case errors.Is(err, game.ErrWrongShop), errors.Is(err, game.ErrNotForSale), errors.Is(err, game.ErrNotBuyable), errors.Is(err, game.ErrBadQty),
			errors.Is(err, game.ErrNoGold), errors.Is(err, game.ErrNotEnough), errors.Is(err, game.ErrInventoryFull),
			errors.Is(err, game.ErrEquipped), errors.Is(err, game.ErrNoDiamond), errors.Is(err, game.ErrGoldMax), errors.Is(err, store.ErrInvalidState):
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
		if len(token) > 128 {
			writeError(w, http.StatusUnauthorized, "token tidak valid")
			return
		}
		h := hashToken(token)
		p, err := s.store.AuthSession(r.Context(), h, s.clock())
		switch {
		case errors.Is(err, store.ErrSessionExpired):
			writeError(w, http.StatusUnauthorized, "sesi kedaluwarsa; silakan masuk lagi")
		case errors.Is(err, store.ErrNotFound):
			writeError(w, http.StatusUnauthorized, "token tidak valid")
		case err != nil:
			s.fail(w, r, err)
		default:
			if info, ok := r.Context().Value(reqInfoKey{}).(*reqInfo); ok {
				info.player = p.ID
			}
			ctx := context.WithValue(context.WithValue(r.Context(), ctxKey{}, p), tokenKey{}, h)
			next.ServeHTTP(w, r.WithContext(ctx))
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

// slowRequest: permintaan yang lebih lama dari ini dicatat sebagai peringatan (roadmap no. 233, 237).
const slowRequest = time.Second

// logRequests mencatat setiap permintaan: metode, jalur, status, lama, IP, dan pemain (bila masuk).
// 5xx dicatat sebagai ERROR, 4xx dan permintaan lambat sebagai WARN, sisanya INFO. "GET /v1/battle"
// 404 (tidak ada pertarungan yang perlu dilanjutkan) adalah alur biasa saat klien dibuka: INFO (no. 271).
func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		info := &reqInfo{}
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r.WithContext(context.WithValue(r.Context(), reqInfoKey{}, info)))
		dur := time.Since(start)
		level := slog.LevelInfo
		switch {
		case sw.status >= 500:
			level = slog.LevelError
		case sw.status == http.StatusNotFound && r.Method == http.MethodGet && r.URL.Path == "/v1/battle":
		case sw.status >= 400 || dur > slowRequest:
			level = slog.LevelWarn
		}
		s.log.Log(r.Context(), level, "request", "method", r.Method, "path", r.URL.Path,
			"status", sw.status, "dur", dur.Round(time.Microsecond), "ip", clientIP(r), "player", info.player)
	})
}

// recoverPanic: kesalahan tak terduga di handler tidak mematikan server; peminta mendapat 500 JSON
// dan jejaknya tercatat di log (roadmap no. 234).
func (s *Server) recoverPanic(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				if v == http.ErrAbortHandler {
					panic(v)
				}
				s.log.Error("panic di handler", "path", r.URL.Path, "panic", v, "stack", string(debug.Stack()))
				writeError(w, http.StatusInternalServerError, "kesalahan internal server")
			}
		}()
		next.ServeHTTP(w, r)
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
