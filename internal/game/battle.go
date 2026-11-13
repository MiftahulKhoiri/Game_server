package game

import (
	"errors"
	"fmt"
)

// Status hasil sebuah aksi atau sinkronisasi.
const (
	StatusOngoing = "ongoing" // pertarungan berlanjut
	StatusWon     = "won"     // musuh kalah
	StatusLost    = "lost"    // pemain pingsan dan dipulangkan ke desa
	StatusFled    = "fled"    // pemain berhasil kabur
)

// Aksi pemain. Pertarungan berjalan real-time: tiap aksi punya waktu isi ulang (cooldown)
// dan musuh menyerang sendiri secara berkala tanpa menunggu pemain.
const (
	ActionAttack = "attack" // serangan biasa, cooldown pendek
	ActionDefend = "defend" // bertahan: jendela waktu mengurangi kerusakan; tepat waktu = tangkis penuh
	ActionSkill1 = "skill1" // Tebasan Kuat: kerusakan besar
	ActionSkill2 = "skill2" // Perisai Cahaya: pulihkan HP dan kurangi kerusakan sesaat
	ActionPotion = "potion"
	ActionFlee   = "flee"
)

// Aturan pertarungan (draf awal untuk diseimbangkan). Satuan waktu: milidetik.
const (
	PotionID      = "ramuan"
	PotionHeal    = 15 // HP yang dipulihkan satu ramuan
	FleeChance    = 60 // persen peluang berhasil kabur
	CritChance    = 10 // persen peluang serangan pemain kritis
	DefendDivisor = 2  // bertahan membagi kerusakan musuh dengan ini

	Skill1Mult        = 22 // kerusakan Skill 1 = serangan x 2,2 (per 10)
	Skill2HealPercent = 25 // Skill 2 memulihkan sekian persen HP maksimum
	ShieldPercent     = 30 // selama perisai aktif pemain hanya menerima sekian persen kerusakan

	EnemyIntervalMs = 2000 // jeda antar serangan musuh biasa
	BossIntervalMs  = 1600 // jeda antar serangan bos
	FirstHitDelayMs = 3000 // musuh baru menyerang pertama kali setelah sekian ms
	GuardMs         = 1200 // lama jendela bertahan
	PerfectMs       = 450  // serangan musuh yang tiba dalam sekian ms setelah menekan Bertahan ditangkis penuh
	PerfectDelayMs  = 600  // tangkisan sempurna menunda serangan musuh berikutnya
	ShieldMs        = 3000 // lama Perisai Cahaya
	LagGraceMs      = 250  // kelonggaran jaringan: aksi dianggap terjadi sedikit lebih awal
	maxCatchUpHits  = 1    // serangan susulan maksimal saat klien lama tidak menyapa
)

// CooldownMs adalah waktu isi ulang tiap aksi.
var CooldownMs = map[string]int64{
	ActionAttack: 900,
	ActionDefend: 1800,
	ActionSkill1: 5000,
	ActionSkill2: 14000,
	ActionPotion: 2500,
	ActionFlee:   3000,
	ActionDodge:  2500,
}

// Kesalahan aturan pertarungan.
var (
	ErrBadAction = errors.New("aksi tidak dikenal")
	ErrNoPotion  = errors.New("kamu tidak punya ramuan")
	ErrFullHP    = errors.New("HP sudah penuh")
	ErrCorrupt   = errors.New("data pertarungan rusak")
	ErrCooldown  = errors.New("aksi belum siap")
)

// Battle adalah pertarungan yang sedang berjalan. Disimpan di server supaya
// klien tidak bisa mengubah musuh atau hasilnya. Semua waktu (…Ms) adalah
// milidetik jam server; klien hanya menerima selisih lewat View.
type Battle struct {
	EnemyID    string `json:"enemy_id"`
	EnemyName  string `json:"enemy_name"`
	EnemyHP    int    `json:"enemy_hp"`
	EnemyMaxHP int    `json:"enemy_max_hp"`
	Round      int    `json:"round"` // jumlah serangan musuh + 1

	NextEnemyMs int64            `json:"next_enemy_ms,omitempty"` // 0 = belum dijadwalkan (data lama)
	NextAllyMs  int64            `json:"next_ally_ms,omitempty"`  // serangan pendamping berikutnya (0 = belum)
	Ready       map[string]int64 `json:"ready,omitempty"`         // aksi -> kapan siap lagi
	GuardPress  int64            `json:"guard_press,omitempty"`
	GuardUntil  int64            `json:"guard_until,omitempty"`
	ShieldUntil int64            `json:"shield_until,omitempty"`

	// Roadmap no. 154-163: gaya senjata, kombo, dan menghindar.
	AttackMs   int64 `json:"attack_ms,omitempty"`   // isi ulang serangan biasa pemain ini (gaya senjata)
	ComboN     int   `json:"combo_n,omitempty"`     // serangan biasa berturut-turut
	ComboUntil int64 `json:"combo_until,omitempty"` // batas waktu serangan berikutnya agar kombo berlanjut
	DodgePress int64 `json:"dodge_press,omitempty"`
	// Night: pertarungan di luar ruangan saat malam (roadmap no. 186): musuh lebih kuat, XP lebih besar.
	Night bool `json:"night,omitempty"`
	// SoldierHP: HP tiap prajurit yang ikut bertarung (v0.66.0); diisi saat pendamping pertama kali bergerak.
	// Prajurit yang gugur dibuang dari daftar dan dari State.Soldiers.
	SoldierHP []int `json:"soldier_hp,omitempty"`
	// Phase: fase bos bertahap (Malzareth: 1 sihir hitam, 2 panggilan monster, 3 kutukan terakhir); 0 = belum.
	Phase int `json:"phase,omitempty"`
	// Penguatan musuh wilayah ujian (tahap.go): tahap 1..3 (0 = biasa), serangan dan hadiah dalam persen.
	Tahap     int `json:"tahap,omitempty"`
	AtkPct    int `json:"atk_pct,omitempty"`
	RewardPct int `json:"reward_pct,omitempty"`
	// AI hybrid (ai.go, v0.78.0): keadaan FSM, taktik serangan berikutnya (untuk ancang-ancang di klien), mundur
	// yang sudah dipakai, dan jendela bertahan musuh (kerusakan yang diterimanya separuh).
	AIState         string `json:"ai_state,omitempty"`
	Intent          string `json:"intent,omitempty"`
	Retreated       bool   `json:"retreated,omitempty"`
	EnemyGuardUntil int64  `json:"enemy_guard_until,omitempty"`
	// Fase 2 (party.go): dorongan Pendekar Tombak pada jadwal serangan musuh saat ini (ms) dan serbuan pembuka
	// pasukan yang sudah dipakai.
	Pushed  int64 `json:"pushed,omitempty"`
	Charged bool  `json:"charged,omitempty"`
}

// BattleView adalah tampilan pertarungan untuk klien: semua waktu relatif terhadap
// sekarang, jadi jam klien tidak perlu sama dengan jam server.
type BattleView struct {
	EnemyID    string `json:"enemy_id"`
	EnemyName  string `json:"enemy_name"`
	EnemyHP    int    `json:"enemy_hp"`
	EnemyMaxHP int    `json:"enemy_max_hp"`
	Round      int    `json:"round"`

	EnemyNextMs     int64            `json:"enemy_next_ms"`        // sisa waktu sampai serangan musuh berikutnya
	AllyNextMs      int64            `json:"ally_next_ms"`         // sisa waktu sampai pendamping menyerang
	AllyIntervalMs  int64            `json:"ally_interval_ms"`     // jeda antar serangan pendamping
	EnemyIntervalMs int64            `json:"enemy_interval_ms"`    // jeda antar serangan musuh
	Cooldowns       map[string]int64 `json:"cooldowns"`            // sisa cooldown per aksi (ms)
	CooldownMax     map[string]int64 `json:"cooldown_max"`         // cooldown penuh per aksi (ms)
	GuardMs         int64            `json:"guard_ms"`             // sisa jendela bertahan
	ShieldMs        int64            `json:"shield_ms"`            // sisa Perisai Cahaya
	Combo           int              `json:"combo"`                // serangan biasa berturut-turut saat ini
	ComboMs         int64            `json:"combo_ms"`             // sisa waktu agar kombo berlanjut
	SoldierHP       []int            `json:"soldier_hp,omitempty"` // HP tiap prajurit yang masih bertarung
	Phase           int              `json:"phase,omitempty"`      // fase bos bertahap (Malzareth 1..3)
	Tahap           int              `json:"tahap,omitempty"`      // musuh wilayah ujian diperkuat: Lv 1..3
	// AI hybrid (v0.78.0): profil perilaku musuh, keadaan FSM, taktik serangan berikutnya (heavy, quick, area,
	// ranged, ambush, retreat; kosong = biasa) untuk ancang-ancang, dan sisa waktu musuh bertahan.
	AIProfile    string `json:"ai_profile,omitempty"`
	AIState      string `json:"ai_state,omitempty"`
	EnemyIntent  string `json:"enemy_intent,omitempty"`
	EnemyGuardMs int64  `json:"enemy_guard_ms,omitempty"`
}

// Event adalah satu kejadian untuk dianimasikan klien.
type Event struct {
	Who  string `json:"who"`            // "player", "enemy", atau "ally" (pendamping)
	Kind string `json:"kind"`           // attack, crit, combo, skill1, skill2, guard, dodge, potion, hit, perfect, shield, miss
	Dmg  int    `json:"dmg,omitempty"`  // kerusakan yang diterima target
	Heal int    `json:"heal,omitempty"` // HP yang dipulihkan
	Hero string `json:"hero,omitempty"` // id pahlawan pendamping (Who == "ally")
	// Skill: nama kemampuan khusus musuh pada serangan ini (roadmap no. 85-86); Heal pada kejadian musuh =
	// HP yang dipulihkan musuh sendiri.
	Skill string `json:"skill,omitempty"`
	// Tactic (v0.78.0): taktik serangan musuh (heavy, quick, area, ranged, ambush, retreat) atau peran pendamping
	// (tank, heavy, ranged, quick, magic, heal); kosong = biasa. Klien lama mengabaikannya.
	Tactic string `json:"tactic,omitempty"`
}

// Rewards adalah hadiah setelah menang.
type Rewards struct {
	XP        int    `json:"xp"`
	Gold      int    `json:"gold"`
	Drop      string `json:"drop,omitempty"`
	LeveledUp bool   `json:"leveled_up"`
	NewLevel  int    `json:"new_level,omitempty"`
}

// Result adalah hasil satu ronde.
type Result struct {
	Status  string   `json:"status"`
	Log     []string `json:"log"`
	Events  []Event  `json:"events,omitempty"`
	Rewards *Rewards `json:"rewards,omitempty"`
}

// StartBattle memulai pertarungan melawan musuh acak yang cocok untuk level pemain.
// now adalah jam server (ms).
func StartBattle(p *Player, rng Rand, now int64) Battle {
	e := PickEnemy(p.State.Level, p.State.Map, rng)
	b := styled(p, newBattle(e, now))
	b.strengthen(p.State, e)
	return b
}

// styled mencatat isi ulang serangan biasa sesuai gaya senjata pahlawan (untuk View).
func styled(p *Player, b Battle) Battle {
	b.AttackMs = p.State.cooldown(ActionAttack)
	b.Night = Outdoors(p.State.Map) && IsNightAt(Now())
	return b
}

// StartBattleWith seperti StartBattle, tetapi memakai musuh `want` (id) bila boleh muncul di
// peta pemain pada levelnya. Dipakai saat pemain menyentuh musuh yang berkeliaran di peta.
func StartBattleWith(p *Player, want string, rng Rand, now int64) Battle {
	e := PickEnemyFor(p.State.Level, p.State.Map, want, rng)
	b := styled(p, newBattle(e, now))
	b.strengthen(p.State, e)
	return b
}

// ErrNoBoss berarti tidak ada bos di petak tempat pemain berdiri.
var ErrNoBoss = errors.New("tidak ada bos di sini")

// StartBossBattle memulai pertarungan dengan bos di petak pemain (posisi tersimpan di server).
func StartBossBattle(p *Player, now int64) (Battle, error) {
	e, ok := BossAt(p.State.Map, p.State.X, p.State.Y)
	if !ok {
		he, err := hutanBoss(p)
		if err != nil {
			return Battle{}, err
		}
		return styled(p, newBattle(he, now)), nil
	}
	if err := p.State.storyBossAllowed(e.ID); err != nil {
		return Battle{}, err
	}
	return styled(p, newBattle(e, now)), nil
}

func newBattle(e Enemy, now int64) Battle {
	return Battle{
		EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1,
		NextEnemyMs: now + FirstHitDelayMs, NextAllyMs: now + AllyFirstMs,
	}
}

func enemyInterval(e Enemy) int64 {
	if e.IntervalMs > 0 {
		return e.IntervalMs
	}
	if e.Boss {
		return BossIntervalMs
	}
	return EnemyIntervalMs
}

// interval: jeda serangan musuh saat ini. Bos yang HP-nya di bawah separuh mengamuk: 25% lebih cepat.
func (b *Battle) interval(e Enemy) int64 {
	iv := enemyInterval(e)
	if e.Boss && b.EnemyHP*2 < b.EnemyMaxHP {
		iv = iv * 3 / 4
	}
	return iv
}

// special: kemampuan khusus musuh pada serangan bernomor `round` (1, 2, ...); "" bila serangan biasa.
func special(e Enemy, round int) string {
	every := SpecialEvery
	if e.Boss {
		every = BossSpecialEvery
	}
	if e.Special == "" || round%every != 0 {
		return ""
	}
	return e.Special
}

// View membuat tampilan relatif untuk klien.
func (b *Battle) View(now int64) BattleView {
	left := func(t int64) int64 { return max(0, t-now) }
	v := BattleView{
		EnemyID: b.EnemyID, EnemyName: b.EnemyName, EnemyHP: b.EnemyHP, EnemyMaxHP: b.EnemyMaxHP, Round: b.Round,
		EnemyNextMs: left(b.NextEnemyMs), EnemyIntervalMs: EnemyIntervalMs,
		AllyNextMs: left(b.NextAllyMs), AllyIntervalMs: AllyIntervalMs,
		Cooldowns: map[string]int64{}, CooldownMax: map[string]int64{},
		GuardMs: left(b.GuardUntil), ShieldMs: left(b.ShieldUntil),
		Combo: b.ComboN, ComboMs: left(b.ComboUntil),
		SoldierHP: b.SoldierHP, Phase: b.Phase, Tahap: b.Tahap,
	}
	if e, ok := EnemyByID(b.EnemyID); ok {
		v.EnemyIntervalMs = enemyInterval(e)
		if prof := ProfileFor(e); prof.ID != "biasa" {
			v.AIProfile = prof.ID
		}
	}
	v.AIState, v.EnemyIntent, v.EnemyGuardMs = b.AIState, b.Intent, left(b.EnemyGuardUntil)
	for a, cd := range CooldownMs {
		if a == ActionAttack && b.AttackMs > 0 {
			cd = b.AttackMs
		}
		v.CooldownMax[a] = cd
		v.Cooldowns[a] = left(b.Ready[a])
	}
	if v.Combo > 0 && v.ComboMs == 0 {
		v.Combo = 0
	}
	return v
}

// Sync menyelesaikan semua serangan musuh yang jatuh tempo sampai now tanpa aksi pemain.
func (b *Battle) Sync(p *Player, now int64, rng Rand) (Result, error) {
	e, ok := EnemyByID(b.EnemyID)
	if !ok {
		return Result{}, ErrCorrupt
	}
	res := Result{Status: StatusOngoing}
	b.settle(p, e, now, rng, &res)
	return res, nil
}

// Act menjalankan satu aksi pemain pada waktu now (ms jam server). Sebelumnya semua
// serangan musuh yang sudah jatuh tempo diselesaikan dulu. State pemain diubah langsung.
func (b *Battle) Act(p *Player, action string, now int64, rng Rand) (Result, error) {
	e, ok := EnemyByID(b.EnemyID)
	if !ok {
		return Result{}, ErrCorrupt
	}
	if _, known := CooldownMs[action]; !known {
		return Result{}, ErrBadAction
	}
	st := &p.State
	b.AttackMs = st.cooldown(ActionAttack)
	style := st.Style()
	res := Result{Status: StatusOngoing}
	logf := func(format string, args ...any) { res.Log = append(res.Log, fmt.Sprintf(format, args...)) }

	// Serangan musuh sebelum (now - kelonggaran) terjadi sebelum aksi ini.
	if b.settle(p, e, now-LagGraceMs, rng, &res) {
		return res, nil
	}
	if left := b.Ready[action] - now; left > 0 {
		return Result{}, fmt.Errorf("%w (%d ms lagi)", ErrCooldown, left)
	}
	cd := func() {
		if b.Ready == nil {
			b.Ready = map[string]int64{}
		}
		b.Ready[action] = now + st.cooldown(action)
	}
	strike := func(power int, kind string) bool {
		dmg, crit := rollDamage(power, style.styleDefense(e.Defense), rng, st.CritPercent()+style.CritBonus)
		if kind == "combo" {
			dmg = dmg * ComboPct / 100
		}
		if kind == "skill1" && ProfileFor(e).Evasive { // musuh lincah menghindari jurus berat (ai.go)
			dmg = max(1, dmg*EvadePct/100)
			logf("%s melompat menghindar sebagian!", b.EnemyName)
		}
		if now < b.EnemyGuardUntil { // musuh sedang mundur bertahan
			dmg = max(1, dmg/2)
		}
		b.EnemyHP -= dmg
		if crit && (kind == "attack" || kind == "combo") {
			if kind == "combo" {
				logf("Kombo kritis!")
			}
			kind = map[string]string{"attack": "crit", "combo": "combo"}[kind]
		}
		res.Events = append(res.Events, Event{Who: "player", Kind: kind, Dmg: dmg})
		switch {
		case kind == "skill1":
			logf("%s! %s kehilangan %d HP.", st.HeroDef().Skill1, b.EnemyName, dmg)
		case kind == "combo":
			logf("Pukulan Kombo! %s kehilangan %d HP.", b.EnemyName, dmg)
		case crit:
			logf("Serangan kritis! %s kehilangan %d HP.", b.EnemyName, dmg)
		default:
			logf("Kamu menyerang %s: -%d HP.", b.EnemyName, dmg)
		}
		if b.EnemyHP <= 0 {
			b.EnemyHP = 0
			b.win(p, e, rng, &res)
			return true
		}
		return false
	}

	switch action {
	case ActionAttack:
		// Kombo: lanjut bila serangan ini datang sebelum batas waktu kombo.
		if b.ComboN > 0 && now <= b.ComboUntil {
			b.ComboN++
		} else {
			b.ComboN = 1
		}
		cd()
		b.ComboUntil = b.Ready[ActionAttack] + ComboWindowMs
		kind := "attack"
		if b.ComboN >= ComboHits {
			kind, b.ComboN = "combo", 0
		}
		st.gainEnergy(EnergyPerAttack)
		if strike(st.Attack()*style.DamagePct/100, kind) {
			return res, nil
		}
	case ActionDodge:
		cd()
		b.DodgePress = now
		res.Events = append(res.Events, Event{Who: "player", Kind: "dodge"})
		logf("Kamu melompat menghindar.")
	case ActionSkill1:
		if !st.spendEnergy(st.skillCost(Skill1Energy)) {
			return Result{}, ErrNoEnergy
		}
		cd()
		if strike(st.Attack()*Skill1Mult/10, "skill1") {
			return res, nil
		}
	case ActionDefend:
		cd()
		b.GuardPress, b.GuardUntil = now, now+GuardMs
		res.Events = append(res.Events, Event{Who: "player", Kind: "guard"})
		logf("Kamu bersiap bertahan.")
	case ActionSkill2:
		if !st.spendEnergy(st.skillCost(Skill2Energy)) {
			return Result{}, ErrNoEnergy
		}
		cd()
		heal := max(1, st.MaxHP*Skill2HealPercent/100)
		heal = min(heal, st.MaxHP-st.HP)
		st.HP += heal
		b.ShieldUntil = now + ShieldMs
		res.Events = append(res.Events, Event{Who: "player", Kind: "skill2", Heal: heal})
		logf("%s! +%d HP, kerusakan berkurang sesaat.", st.HeroDef().Skill2, heal)
	case ActionPotion:
		if st.HP >= st.MaxHP {
			return Result{}, ErrFullHP
		}
		if !st.RemoveItem(PotionID, 1) {
			return Result{}, ErrNoPotion
		}
		cd()
		heal := min(PotionHeal, st.MaxHP-st.HP)
		st.HP += heal
		res.Events = append(res.Events, Event{Who: "player", Kind: "potion", Heal: heal})
		logf("Kamu minum ramuan: +%d HP.", heal)
	case ActionFlee:
		cd()
		if rng.Intn(100) < FleeChance {
			res.Status = StatusFled
			p.State.endBattleBuffs()
			logf("Kamu berhasil kabur.")
			return res, nil
		}
		logf("Gagal kabur!")
	}

	// Serangan musuh yang jatuh tempo tepat setelah aksi (dalam kelonggaran jaringan).
	b.settle(p, e, now, rng, &res)
	return res, nil
}

// settle menjalankan semua serangan musuh dengan jadwal <= upto. Mengembalikan true bila
// pemain kalah (res sudah diisi).
func (b *Battle) settle(p *Player, e Enemy, upto int64, rng Rand, res *Result) bool {
	st := &p.State
	iv := b.interval(e)
	if b.NextEnemyMs == 0 { // pertarungan lama tanpa jadwal
		b.NextEnemyMs = upto + FirstHitDelayMs
	}
	// Klien lama tidak menyapa (app ditutup): jangan menumpuk serangan.
	if lag := upto - b.NextEnemyMs; lag > maxCatchUpHits*iv {
		b.NextEnemyMs += lag - maxCatchUpHits*iv
	}
	st.ensureAllyHealth()
	b.ensureSoldiers(st)
	prof := ProfileFor(e)
	if b.AIState == "" && b.Round == 1 {
		b.AIState = AIApproach
	}
	allyOn := st.hasHealthyAlly() || len(b.SoldierHP) > 0
	if allyOn {
		if b.NextAllyMs == 0 {
			b.NextAllyMs = upto + AllyFirstMs
		}
		if lag := upto - b.NextAllyMs; lag > AllyIntervalMs {
			b.NextAllyMs += lag - AllyIntervalMs
		}
	}
	for {
		enemyDue := b.NextEnemyMs <= upto
		allyDue := allyOn && b.NextAllyMs <= upto
		if !enemyDue && !allyDue {
			break
		}
		if allyDue && (!enemyDue || b.NextAllyMs < b.NextEnemyMs) {
			if b.allyStrike(p, e, rng, res) {
				return true // musuh tumbang oleh pendamping (kemenangan sudah dicatat)
			}
			continue
		}
		t := b.NextEnemyMs
		// ASSESS + SELECT_TARGET + SELECT_TACTIC (ai.go; tanpa angka acak tambahan).
		plan := b.assess(e, prof, hpPct(st), b.helpers(st))
		attack := b.enemyAttack(e)
		if b.Night {
			attack = max(attack+1, attack*NightAttack/100) // minimal +1 supaya musuh lemah pun terasa
		}
		dmg, _ := rollDamage(attack, st.Defense(), rng, 0)
		kind := "hit"
		iv = b.interval(e)
		if plan.tactic == TacticRetreat {
			b.Retreated, b.AIState = true, AIRetreat
			b.EnemyGuardUntil = t + RetreatGuardMs
			b.Round++
			b.NextEnemyMs = t + iv*int64(plan.ivPct)/100
			b.Intent = b.nextIntent(e, st)
			res.Events = append(res.Events, Event{Who: "enemy", Kind: "retreat", Tactic: TacticRetreat})
			res.Log = append(res.Log, fmt.Sprintf("%s mundur dan bertahan!", b.EnemyName))
			continue
		}
		next := t + iv*int64(plan.ivPct)/100 + plan.extraMs
		// Kemampuan khusus (tanpa memakai angka acak tambahan, jadi urutan acak tetap sama).
		sp := special(e, b.Round)
		spName := e.SpecialName
		switch {
		case e.ID == MalzarethID:
			sp, spName = b.malzarethPhase(e, res)
		case genericBoss(e): // pola fase bos (boss.go)
			ph := b.bossPhase(e, res)
			sp = bossSpecial(e, b.Round, ph)
			if sp == "" && bossArea(b.Round, ph) {
				plan.tactic, plan.area, plan.dmgPct = TacticArea, true, max(plan.dmgPct, 120)
			}
		}
		if sp != "" {
			plan.dmgPct = 100 // kemampuan khusus sudah kuat: tidak ditumpuk dengan serangan berat
		}
		if plan.dmgPct != 100 {
			dmg = max(1, dmg*plan.dmgPct/100)
		}
		healed := 0
		switch sp {
		case SpecialKutukan:
			dmg = dmg * 2
		case SpecialTerkam:
			dmg = dmg * 16 / 10
		case SpecialGempa:
			dmg = dmg * 18 / 10
		case SpecialRacun:
			dmg += max(1, b.enemyAttack(e)/4)
		case SpecialBatu:
			healed = min(b.EnemyMaxHP-b.EnemyHP, max(1, b.EnemyMaxHP*8/100))
			b.EnemyHP += healed
		}
		guarded := t >= b.GuardPress-LagGraceMs && t <= b.GuardUntil && b.GuardUntil > 0
		dodged := b.DodgePress > 0 && t >= b.DodgePress-LagGraceMs && t <= b.DodgePress+DodgeMs
		switch {
		case dodged:
			dmg, kind = 0, "miss"
		case guarded && t-b.GuardPress <= PerfectMs && !plan.noPerfect: // napas api tidak bisa ditangkis sempurna
			dmg, kind = 0, "perfect"
			next += PerfectDelayMs
		case t < b.ShieldUntil:
			dmg, kind = max(1, dmg*ShieldPercent/100), "shield"
		case guarded:
			dmg, kind = max(1, dmg/DefendDivisor), "guard"
		}
		b.Round++
		b.NextEnemyMs = next
		b.Pushed = 0
		b.AIState = AIWindup
		if plan.tactic == TacticHeavy || plan.tactic == TacticArea || plan.tactic == TacticRanged {
			b.AIState = AIRecover
		}
		tactic := plan.tactic
		if tactic == TacticNormal {
			tactic = ""
		}
		if plan.area && kind != "miss" && kind != "perfect" {
			b.areaSplash(st, dmg, res)
		}
		// Setiap serangan musuh ketiga diarahkan ke pendamping sehat pertama.
		// Ini deterministik, tidak mengubah urutan RNG atau perilaku akun tanpa pendamping.
		// Ksatria sehat (tank) menarik perhatian: tiap serangan ke-2 ke arahnya; Pemanah menjaga jarak (party.go).
		targetAlly := ""
		allyTurnDue := (b.Round-1)%3 == 0
		if st.tankUp() {
			allyTurnDue = (b.Round-1)%2 == 0
		}
		if kind != "perfect" && kind != "miss" && !plan.area && (allyTurnDue || plan.allyFirst) {
			targetAlly = st.tauntTarget()
		}
		// Prajurit (v0.66.0): serangan yang tidak mengenai pahlawan pendamping, dua dari tiga, mengenai
		// prajurit terdepan bila pasukan ikut bertarung.
		form := st.formation()
		if targetAlly == "" && kind != "perfect" && kind != "miss" && !plan.area && len(b.SoldierHP) > 0 && (int((b.Round-1)%3) < form.Share || plan.allyFirst) {
			dmg = max(1, dmg*form.TakenPct/100)
			if st.tankUp() {
				dmg = max(1, dmg*TankGuardPct/100) // Ksatria melindungi barisan
			}
			b.SoldierHP[0] -= dmg
			if b.SoldierHP[0] <= 0 {
				b.SoldierHP = b.SoldierHP[1:]
				st.Soldiers = max(0, st.Soldiers-1)
				st.SoldiersRest = min(st.SoldiersRest, st.Soldiers)
				res.Events = append(res.Events, Event{Who: "ally", Kind: "down", Dmg: dmg, Hero: SoldierID(1), Tactic: tactic})
				res.Log = append(res.Log, fmt.Sprintf("Seorang prajurit gugur! Tersisa %d prajurit.", st.Soldiers))
			} else {
				res.Events = append(res.Events, Event{Who: "ally", Kind: "hit", Dmg: dmg, Hero: SoldierID(1), Tactic: tactic})
				res.Log = append(res.Log, fmt.Sprintf("Prajurit terdepan terkena serangan: -%d HP (tersisa %d).", dmg, b.SoldierHP[0]))
			}
			b.Intent = b.nextIntent(e, st)
			continue
		}
		if targetAlly != "" {
			remaining, down := st.damageAlly(targetAlly, dmg)
			allyKind := "hit"
			if down {
				allyKind = "down"
			}
			res.Events = append(res.Events, Event{Who: "ally", Kind: allyKind, Dmg: dmg, Hero: targetAlly, Tactic: tactic})
			name := targetAlly
			if h, ok := HeroByID(targetAlly); ok {
				name = h.Name
			}
			if down {
				res.Log = append(res.Log, fmt.Sprintf("%s tumbang! Gunakan ramuan kesehatan untuk menyembuhkannya.", name))
			} else {
				res.Log = append(res.Log, fmt.Sprintf("%s terkena serangan: -%d HP (tersisa %d).", name, dmg, remaining))
			}
			b.Intent = b.nextIntent(e, st)
			continue
		}
		st.HP -= dmg
		if dmg > 0 && kind != "guard" && kind != "shield" {
			b.ComboN = 0 // terkena serangan telak memutus kombo
		}
		b.Intent = b.nextIntent(e, st)
		ev := Event{Who: "enemy", Kind: kind, Dmg: dmg, Tactic: tactic}
		if sp != "" {
			ev.Skill, ev.Heal = spName, healed
		}
		res.Events = append(res.Events, ev)
		switch {
		case kind == "perfect":
			res.Log = append(res.Log, fmt.Sprintf("Tangkisan sempurna! Serangan %s tidak berefek.", b.EnemyName))
		case kind == "miss":
			res.Log = append(res.Log, fmt.Sprintf("Kamu menghindar! Serangan %s meleset.", b.EnemyName))
		case sp != "" && healed > 0:
			res.Log = append(res.Log, fmt.Sprintf("%s memakai %s: -%d HP, ia pulih %d HP.", b.EnemyName, spName, dmg, healed))
		case sp != "":
			res.Log = append(res.Log, fmt.Sprintf("%s memakai %s! -%d HP.", b.EnemyName, spName, dmg))
		case tactic != "":
			res.Log = append(res.Log, fmt.Sprintf("%s %s: -%d HP.", b.EnemyName, tacticVerb[tactic], dmg))
		default:
			res.Log = append(res.Log, fmt.Sprintf("%s menyerang: -%d HP.", b.EnemyName, dmg))
		}
		if st.HP <= 0 {
			b.lose(p, res)
			return true
		}
	}
	return false
}

// allyStrike: semua pendamping yang dipasang menyerang sekali. true bila musuh tumbang.
func (b *Battle) allyStrike(p *Player, e Enemy, rng Rand, res *Result) bool {
	st := &p.State
	b.NextAllyMs += AllyIntervalMs
	for _, id := range st.Party {
		if hp, _, ok := st.AllyHealth(id); ok && hp <= 0 {
			continue // pendamping yang tumbang tidak menyerang
		}
		def, pct := allyTurn(id, e)
		dmg, _ := rollDamage(st.heroPower(id)*pct/100, def, rng, 0)
		name := id
		if h, ok := HeroByID(id); ok {
			name = h.Name
		}
		role := HeroRole[id]
		if role == RoleMagic {
			if who, ok := st.healTarget(); ok { // Penyihir: dukungan lebih penting daripada menyerang
				heal := max(1, dmg*MageHealPct/100)
				target := "kamu"
				if who == "" {
					heal = min(heal, st.MaxHP-st.HP)
					st.HP += heal
				} else {
					before, _, _ := st.AllyHealth(who)
					after, _ := st.HealAlly(who, heal)
					heal = max(0, after-before)
					if h, ok := HeroByID(who); ok {
						target = h.Name
					}
				}
				res.Events = append(res.Events, Event{Who: "ally", Kind: "heal", Heal: heal, Hero: id, Tactic: RoleHeal, Skill: who})
				res.Log = append(res.Log, fmt.Sprintf("%s menyembuhkan %s: +%d HP.", name, target, heal))
				continue
			}
		}
		if b.NextAllyMs-AllyIntervalMs < b.EnemyGuardUntil {
			dmg = max(1, dmg/2)
		}
		b.EnemyHP -= dmg
		if role == RoleQuick && b.Pushed < QuickPushMaxMs { // tusukan cepat menekan musuh: serangannya tertunda
			push := min(QuickPushMs, QuickPushMaxMs-b.Pushed)
			b.NextEnemyMs += push
			b.Pushed += push
		}
		res.Events = append(res.Events, Event{Who: "ally", Kind: "attack", Dmg: dmg, Hero: id, Tactic: role})
		res.Log = append(res.Log, fmt.Sprintf("%s membantu: %s -%d HP.", name, b.EnemyName, dmg))
		if b.EnemyHP <= 0 {
			b.EnemyHP = 0
			b.win(p, e, rng, res)
			return true
		}
	}
	total := 0
	form := st.formation()
	power := st.soldierPower() * form.AtkPct / 100
	if form.FirstPct > 0 && !b.Charged && len(b.SoldierHP) > 0 {
		power = power * form.FirstPct / 100 // serbuan pembuka
		res.Log = append(res.Log, "Pasukan menyerbu!")
	}
	if len(b.SoldierHP) > 0 {
		b.Charged = true
	}
	for n := 1; n <= len(b.SoldierHP); n++ {
		dmg, _ := rollDamage(max(1, power), e.Defense, rng, 0)
		b.EnemyHP -= dmg
		total += dmg
		if n <= maxSoldierEvents { // klien menggerakkan beberapa prajurit saja
			res.Events = append(res.Events, Event{Who: "ally", Kind: "attack", Dmg: dmg, Hero: SoldierID(n)})
		}
		if b.EnemyHP <= 0 {
			b.EnemyHP = 0
			res.Log = append(res.Log, fmt.Sprintf("Pasukan %d prajurit menyerang: %s -%d HP.", n, b.EnemyName, total))
			b.win(p, e, rng, res)
			return true
		}
	}
	if total > 0 {
		res.Log = append(res.Log, fmt.Sprintf("Pasukan %d prajurit menyerang: %s -%d HP.", len(b.SoldierHP), b.EnemyName, total))
	}
	return false
}

// maxSoldierEvents: kejadian serangan prajurit yang dikirim ke klien per giliran (sisanya hanya dijumlah di log).
const maxSoldierEvents = 8

// ensureSoldiers mengisi HP prajurit yang ikut bertarung (sekali per pertarungan), dan membuang kelebihan bila
// jumlah prajurit terpasang berkurang.
func (b *Battle) ensureSoldiers(st *State) {
	n := st.ActiveSoldiers()
	if b.SoldierHP == nil && n > 0 {
		b.SoldierHP = make([]int, n)
		for i := range b.SoldierHP {
			b.SoldierHP[i] = st.SoldierMaxHP()
		}
	}
	if len(b.SoldierHP) > n {
		b.SoldierHP = b.SoldierHP[:n]
	}
	if len(b.SoldierHP) == 0 {
		b.SoldierHP = nil
	}
}

func (b *Battle) win(p *Player, e Enemy, rng Rand, res *Result) {
	st := &p.State
	xp := b.reward(e.XP)
	gold := b.reward(e.Gold)
	if b.Night {
		xp = xp * NightXP / 100
	}
	rw := &Rewards{XP: xp, Gold: gold}
	res.Status = StatusWon
	st.endBattleBuffs()
	res.Rewards = rw
	res.Log = append(res.Log, fmt.Sprintf("%s kalah! +%d XP, +%d emas.", b.EnemyName, xp, gold))
	if b.Night {
		res.Log = append(res.Log, "Bonus malam: XP +25%.")
	}

	st.XP += xp
	st.gainGold(gold)
	st.gainEnergy(EnergyPerWin)
	for st.Level < MaxLevel && st.XP >= XPToNext(st.Level) {
		st.XP -= XPToNext(st.Level)
		st.Level++
		st.MaxHP = st.MaxHPNow()
		st.HP = st.MaxHP
		st.EnergyUsed = 0
		rw.LeveledUp = true
		rw.NewLevel = st.Level
	}
	if rw.LeveledUp {
		res.Log = append(res.Log, fmt.Sprintf("Naik level! Sekarang level %d, HP pulih penuh.", st.Level))
	}
	if e.DropID != "" && rng.Intn(100) < e.DropPercent && st.AddItem(e.DropID, 1) {
		rw.Drop = e.DropID
		res.Log = append(res.Log, fmt.Sprintf("%s menjatuhkan: %s.", b.EnemyName, e.DropID))
	}
	if rng.Intn(100) < KartuDropPercent && st.AddItem(KartuKeahlianID, 1) {
		res.Log = append(res.Log, "Kamu menemukan Kartu Keahlian!")
		if rw.Drop == "" {
			rw.Drop = KartuKeahlianID
		}
	}
	st.Wins++
	if e.Raid {
		res.Log = append(res.Log, st.recordRaid(Now()))
	}
	for _, a := range st.checkAchievements() {
		res.Log = append(res.Log, "Pencapaian baru: "+a+"!")
	}
	res.Log = append(res.Log, st.RecordKill(e.ID)...)
	res.Log = append(res.Log, st.recordHutan(e)...)
	res.Log = append(res.Log, st.storyKill(e.ID)...)
	res.Log = append(res.Log, st.advanceStory()...)
}

// lose: pemain pingsan, kehilangan separuh emas, dibawa pulang ke desa dengan separuh HP.
func (b *Battle) lose(p *Player, res *Result) {
	st := &p.State
	lost := st.Gold / 2
	st.Gold -= lost
	if lost > 0 {
		st.record(LedgerBattle, "Pingsan saat bertarung: separuh emas hilang (tabungan di bank aman)", -lost)
	}
	st.HP = max(1, st.MaxHP/2)
	st.Map, st.X, st.Y = SpawnMap, SpawnX, SpawnY
	st.PlaceAtTileCenter()
	st.endBattleBuffs()
	res.Status = StatusLost
	res.Log = append(res.Log, fmt.Sprintf("Kamu pingsan... dibawa pulang ke desa (emas hilang: %d).", lost))
}

// rollDamage menghitung kerusakan: (serang - pertahanan), minimal 1, dengan
// variasi 80-120%. Serangan pemain bisa kritis (x1,5).
// critPct = peluang kritis (persen); 0 = tidak bisa kritis (serangan musuh).
func rollDamage(attack, defense int, rng Rand, critPct int) (dmg int, crit bool) {
	base := max(1, attack-defense)
	dmg = max(1, base*(80+rng.Intn(41))/100)
	if critPct > 0 && rng.Intn(100) < critPct {
		dmg = dmg * 3 / 2
		crit = true
	}
	return dmg, crit
}

// Aturan AI tambahan (ai.go).
const (
	EvadePct       = 60   // jurus berat pemain hanya mengenai sekian persen musuh lincah
	RetreatGuardMs = 2500 // lama musuh bertahan setelah mundur (kerusakan diterima separuh)
	AreaPct        = 50   // serangan area: pendamping dan prajurit depan menerima sekian persen kerusakan
	areaSoldiers   = 3    // prajurit depan yang ikut terkena serangan area
)

// tacticVerb: kata kerja catatan pertarungan per taktik.
var tacticVerb = map[string]string{
	TacticHeavy: "menyerang sekuat tenaga", TacticQuick: "menyerang cepat", TacticAmbush: "menyergap",
	TacticArea: "menghantam ke segala arah", TacticRanged: "menyembur dari jauh",
}

// areaSplash: serangan area juga mengenai pendamping sehat dan beberapa prajurit terdepan (AreaPct kerusakan).
func (b *Battle) areaSplash(st *State, dmg int, res *Result) {
	splash := max(1, dmg*AreaPct/100)
	for _, id := range st.Party {
		if hp, _, ok := st.AllyHealth(id); !ok || hp <= 0 {
			continue
		}
		_, down := st.damageAlly(id, splash)
		kind := "hit"
		if down {
			kind = "down"
		}
		res.Events = append(res.Events, Event{Who: "ally", Kind: kind, Dmg: splash, Hero: id, Tactic: TacticArea})
	}
	fell := 0
	for i, hit := 0, 0; i < len(b.SoldierHP) && hit < areaSoldiers; hit++ {
		b.SoldierHP[i] -= splash
		if b.SoldierHP[i] <= 0 {
			b.SoldierHP = append(b.SoldierHP[:i], b.SoldierHP[i+1:]...)
			st.Soldiers = max(0, st.Soldiers-1)
			st.SoldiersRest = min(st.SoldiersRest, st.Soldiers)
			fell++
			res.Events = append(res.Events, Event{Who: "ally", Kind: "down", Dmg: splash, Hero: SoldierID(1), Tactic: TacticArea})
			continue
		}
		res.Events = append(res.Events, Event{Who: "ally", Kind: "hit", Dmg: splash, Hero: SoldierID(i + 1), Tactic: TacticArea})
		i++
	}
	if len(b.SoldierHP) == 0 {
		b.SoldierHP = nil
	}
	if fell > 0 {
		res.Log = append(res.Log, fmt.Sprintf("Serangan area menumbangkan %d prajurit! Tersisa %d prajurit.", fell, st.Soldiers))
	}
}
