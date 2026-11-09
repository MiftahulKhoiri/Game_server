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
}

// BattleView adalah tampilan pertarungan untuk klien: semua waktu relatif terhadap
// sekarang, jadi jam klien tidak perlu sama dengan jam server.
type BattleView struct {
	EnemyID    string `json:"enemy_id"`
	EnemyName  string `json:"enemy_name"`
	EnemyHP    int    `json:"enemy_hp"`
	EnemyMaxHP int    `json:"enemy_max_hp"`
	Round      int    `json:"round"`

	EnemyNextMs     int64            `json:"enemy_next_ms"`     // sisa waktu sampai serangan musuh berikutnya
	AllyNextMs      int64            `json:"ally_next_ms"`      // sisa waktu sampai pendamping menyerang
	AllyIntervalMs  int64            `json:"ally_interval_ms"`  // jeda antar serangan pendamping
	EnemyIntervalMs int64            `json:"enemy_interval_ms"` // jeda antar serangan musuh
	Cooldowns       map[string]int64 `json:"cooldowns"`         // sisa cooldown per aksi (ms)
	CooldownMax     map[string]int64 `json:"cooldown_max"`      // cooldown penuh per aksi (ms)
	GuardMs         int64            `json:"guard_ms"`          // sisa jendela bertahan
	ShieldMs        int64            `json:"shield_ms"`         // sisa Perisai Cahaya
}

// Event adalah satu kejadian untuk dianimasikan klien.
type Event struct {
	Who  string `json:"who"`            // "player", "enemy", atau "ally" (pendamping)
	Kind string `json:"kind"`           // attack, crit, skill1, skill2, guard, potion, hit, perfect, shield
	Dmg  int    `json:"dmg,omitempty"`  // kerusakan yang diterima target
	Heal int    `json:"heal,omitempty"` // HP yang dipulihkan
	Hero string `json:"hero,omitempty"` // id pahlawan pendamping (Who == "ally")
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
	return newBattle(PickEnemy(p.State.Level, p.State.Map, rng), now)
}

// StartBattleWith seperti StartBattle, tetapi memakai musuh `want` (id) bila boleh muncul di
// peta pemain pada levelnya. Dipakai saat pemain menyentuh musuh yang berkeliaran di peta.
func StartBattleWith(p *Player, want string, rng Rand, now int64) Battle {
	return newBattle(PickEnemyFor(p.State.Level, p.State.Map, want, rng), now)
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
		return newBattle(he, now), nil
	}
	return newBattle(e, now), nil
}

func newBattle(e Enemy, now int64) Battle {
	return Battle{
		EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1,
		NextEnemyMs: now + FirstHitDelayMs, NextAllyMs: now + AllyFirstMs,
	}
}

func enemyInterval(e Enemy) int64 {
	if e.Boss {
		return BossIntervalMs
	}
	return EnemyIntervalMs
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
	}
	if e, ok := EnemyByID(b.EnemyID); ok {
		v.EnemyIntervalMs = enemyInterval(e)
	}
	for a, cd := range CooldownMs {
		v.CooldownMax[a] = cd
		v.Cooldowns[a] = left(b.Ready[a])
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
		b.Ready[action] = now + CooldownMs[action]
	}
	strike := func(power int, kind string) bool {
		dmg, crit := rollDamage(power, e.Defense, rng, true)
		b.EnemyHP -= dmg
		if crit && kind == "attack" {
			kind = "crit"
		}
		res.Events = append(res.Events, Event{Who: "player", Kind: kind, Dmg: dmg})
		switch {
		case kind == "skill1":
			logf("%s! %s kehilangan %d HP.", st.HeroDef().Skill1, b.EnemyName, dmg)
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
		cd()
		st.gainEnergy(EnergyPerAttack)
		if strike(st.Attack(), "attack") {
			return res, nil
		}
	case ActionSkill1:
		if !st.spendEnergy(Skill1Energy) {
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
		if !st.spendEnergy(Skill2Energy) {
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
	iv := enemyInterval(e)
	if b.NextEnemyMs == 0 { // pertarungan lama tanpa jadwal
		b.NextEnemyMs = upto + FirstHitDelayMs
	}
	// Klien lama tidak menyapa (app ditutup): jangan menumpuk serangan.
	if lag := upto - b.NextEnemyMs; lag > maxCatchUpHits*iv {
		b.NextEnemyMs += lag - maxCatchUpHits*iv
	}
	st.ensureAllyHealth()
	allyOn := st.hasHealthyAlly() || st.Soldiers > 0
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
		dmg, _ := rollDamage(e.Attack, st.Defense(), rng, false)
		kind := "hit"
		next := t + iv
		guarded := t >= b.GuardPress-LagGraceMs && t <= b.GuardUntil && b.GuardUntil > 0
		switch {
		case guarded && t-b.GuardPress <= PerfectMs:
			dmg, kind = 0, "perfect"
			next += PerfectDelayMs
		case t < b.ShieldUntil:
			dmg, kind = max(1, dmg*ShieldPercent/100), "shield"
		case guarded:
			dmg, kind = max(1, dmg/DefendDivisor), "guard"
		}
		b.Round++
		b.NextEnemyMs = next
		// Setiap serangan musuh ketiga diarahkan ke pendamping sehat pertama.
		// Ini deterministik, tidak mengubah urutan RNG atau perilaku akun tanpa pendamping.
		targetAlly := ""
		if kind != "perfect" && (b.Round-1)%3 == 0 {
			for _, id := range st.Party {
				if hp, _, ok := st.AllyHealth(id); ok && hp > 0 {
					targetAlly = id
					break
				}
			}
		}
		if targetAlly != "" {
			remaining, down := st.damageAlly(targetAlly, dmg)
			allyKind := "hit"
			if down {
				allyKind = "down"
			}
			res.Events = append(res.Events, Event{Who: "ally", Kind: allyKind, Dmg: dmg, Hero: targetAlly})
			name := targetAlly
			if h, ok := HeroByID(targetAlly); ok { name = h.Name }
			if down {
				res.Log = append(res.Log, fmt.Sprintf("%s tumbang! Gunakan ramuan kesehatan untuk menyembuhkannya.", name))
			} else {
				res.Log = append(res.Log, fmt.Sprintf("%s terkena serangan: -%d HP (tersisa %d).", name, dmg, remaining))
			}
			continue
		}
		st.HP -= dmg
		res.Events = append(res.Events, Event{Who: "enemy", Kind: kind, Dmg: dmg})
		if kind == "perfect" {
			res.Log = append(res.Log, fmt.Sprintf("Tangkisan sempurna! Serangan %s tidak berefek.", b.EnemyName))
		} else {
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
		if hp, _, ok := st.AllyHealth(id); ok && hp <= 0 { continue }
		dmg, _ := rollDamage(st.heroPower(id), e.Defense, rng, false)
		b.EnemyHP -= dmg
		res.Events = append(res.Events, Event{Who: "ally", Kind: "attack", Dmg: dmg, Hero: id})
		name := id
		if h, ok := HeroByID(id); ok {
			name = h.Name
		}
		res.Log = append(res.Log, fmt.Sprintf("%s membantu: %s -%d HP.", name, b.EnemyName, dmg))
		if b.EnemyHP <= 0 {
			b.EnemyHP = 0
			b.win(p, e, rng, res)
			return true
		}
	}
	for n := 1; n <= st.Soldiers; n++ {
		dmg, _ := rollDamage(st.soldierPower(), e.Defense, rng, false)
		b.EnemyHP -= dmg
		res.Events = append(res.Events, Event{Who: "ally", Kind: "attack", Dmg: dmg, Hero: SoldierID(n)})
		res.Log = append(res.Log, fmt.Sprintf("Prajurit %d membantu: %s -%d HP.", n, b.EnemyName, dmg))
		if b.EnemyHP <= 0 {
			b.EnemyHP = 0
			b.win(p, e, rng, res)
			return true
		}
	}
	return false
}

func (b *Battle) win(p *Player, e Enemy, rng Rand, res *Result) {
	st := &p.State
	rw := &Rewards{XP: e.XP, Gold: e.Gold}
	res.Status = StatusWon
	st.endBattleBuffs()
	res.Rewards = rw
	res.Log = append(res.Log, fmt.Sprintf("%s kalah! +%d XP, +%d emas.", b.EnemyName, e.XP, e.Gold))

	st.XP += e.XP
	st.Gold += e.Gold
	st.gainEnergy(EnergyPerWin)
	for st.Level < MaxLevel && st.XP >= XPToNext(st.Level) {
		st.XP -= XPToNext(st.Level)
		st.Level++
		st.MaxHP = MaxHPForLevel(st.Level)
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
	res.Log = append(res.Log, st.RecordKill(e.ID)...)
	res.Log = append(res.Log, st.recordHutan(e)...)
}

// lose: pemain pingsan, kehilangan separuh emas, dibawa pulang ke desa dengan separuh HP.
func (b *Battle) lose(p *Player, res *Result) {
	st := &p.State
	lost := st.Gold / 2
	st.Gold -= lost
	st.HP = max(1, st.MaxHP/2)
	st.Map, st.X, st.Y = SpawnMap, SpawnX, SpawnY
	st.PlaceAtTileCenter()
	st.endBattleBuffs()
	res.Status = StatusLost
	res.Log = append(res.Log, fmt.Sprintf("Kamu pingsan... dibawa pulang ke desa (emas hilang: %d).", lost))
}

// rollDamage menghitung kerusakan: (serang - pertahanan), minimal 1, dengan
// variasi 80-120%. Serangan pemain bisa kritis (x1,5).
func rollDamage(attack, defense int, rng Rand, canCrit bool) (dmg int, crit bool) {
	base := max(1, attack-defense)
	dmg = max(1, base*(80+rng.Intn(41))/100)
	if canCrit && rng.Intn(100) < CritChance {
		dmg = dmg * 3 / 2
		crit = true
	}
	return dmg, crit
}
