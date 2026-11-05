package game

import (
	"errors"
	"fmt"
)

// Status hasil sebuah ronde.
const (
	StatusOngoing = "ongoing" // pertarungan berlanjut
	StatusWon     = "won"     // musuh kalah
	StatusLost    = "lost"    // pemain pingsan dan dipulangkan ke desa
	StatusFled    = "fled"    // pemain berhasil kabur
)

// Aksi pemain dalam satu ronde.
const (
	ActionAttack = "attack"
	ActionDefend = "defend"
	ActionPotion = "potion"
	ActionFlee   = "flee"
)

// Aturan pertarungan (draf awal untuk diseimbangkan).
const (
	PotionID      = "ramuan"
	PotionHeal    = 15 // HP yang dipulihkan satu ramuan
	FleeChance    = 60 // persen peluang berhasil kabur
	CritChance    = 10 // persen peluang serangan pemain kritis
	DefendDivisor = 2  // bertahan membagi kerusakan musuh dengan ini
)

// Kesalahan aturan pertarungan.
var (
	ErrBadAction = errors.New("aksi tidak dikenal")
	ErrNoPotion  = errors.New("kamu tidak punya ramuan")
	ErrFullHP    = errors.New("HP sudah penuh")
	ErrCorrupt   = errors.New("data pertarungan rusak")
)

// Battle adalah pertarungan yang sedang berjalan. Disimpan di server supaya
// klien tidak bisa mengubah musuh atau hasilnya.
type Battle struct {
	EnemyID    string `json:"enemy_id"`
	EnemyName  string `json:"enemy_name"`
	EnemyHP    int    `json:"enemy_hp"`
	EnemyMaxHP int    `json:"enemy_max_hp"`
	Round      int    `json:"round"`
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
	Rewards *Rewards `json:"rewards,omitempty"`
}

// StartBattle memulai pertarungan melawan musuh acak yang cocok untuk level pemain.
func StartBattle(p *Player, rng Rand) Battle {
	e := PickEnemy(p.State.Level, rng)
	return Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: e.HP, EnemyMaxHP: e.HP, Round: 1}
}

// Act menjalankan satu ronde: aksi pemain, lalu (bila musuh masih hidup dan
// pemain tidak kabur) giliran musuh. State pemain diubah langsung.
func (b *Battle) Act(p *Player, action string, rng Rand) (Result, error) {
	e, ok := EnemyByID(b.EnemyID)
	if !ok {
		return Result{}, ErrCorrupt
	}
	st := &p.State
	res := Result{Status: StatusOngoing}
	logf := func(format string, args ...any) { res.Log = append(res.Log, fmt.Sprintf(format, args...)) }
	defending := false

	switch action {
	case ActionAttack:
		dmg, crit := rollDamage(AttackForLevel(st.Level), e.Defense, rng, true)
		b.EnemyHP -= dmg
		if crit {
			logf("Serangan kritis! %s kehilangan %d HP.", b.EnemyName, dmg)
		} else {
			logf("Kamu menyerang %s: -%d HP.", b.EnemyName, dmg)
		}
		if b.EnemyHP <= 0 {
			b.EnemyHP = 0
			b.win(p, e, rng, &res)
			return res, nil
		}
	case ActionDefend:
		defending = true
		logf("Kamu bersiap bertahan.")
	case ActionPotion:
		if st.HP >= st.MaxHP {
			return Result{}, ErrFullHP
		}
		if !st.RemoveItem(PotionID, 1) {
			return Result{}, ErrNoPotion
		}
		heal := min(PotionHeal, st.MaxHP-st.HP)
		st.HP += heal
		logf("Kamu minum ramuan: +%d HP.", heal)
	case ActionFlee:
		if rng.Intn(100) < FleeChance {
			res.Status = StatusFled
			logf("Kamu berhasil kabur.")
			return res, nil
		}
		logf("Gagal kabur!")
	default:
		return Result{}, ErrBadAction
	}

	// Giliran musuh.
	dmg, _ := rollDamage(e.Attack, DefenseForLevel(st.Level), rng, false)
	if defending {
		dmg = max(1, dmg/DefendDivisor)
	}
	st.HP -= dmg
	logf("%s menyerang: -%d HP.", b.EnemyName, dmg)
	if st.HP <= 0 {
		b.lose(p, &res)
		return res, nil
	}
	b.Round++
	return res, nil
}

func (b *Battle) win(p *Player, e Enemy, rng Rand, res *Result) {
	st := &p.State
	rw := &Rewards{XP: e.XP, Gold: e.Gold}
	res.Status = StatusWon
	res.Rewards = rw
	res.Log = append(res.Log, fmt.Sprintf("%s kalah! +%d XP, +%d emas.", b.EnemyName, e.XP, e.Gold))

	st.XP += e.XP
	st.Gold += e.Gold
	for st.Level < MaxLevel && st.XP >= XPToNext(st.Level) {
		st.XP -= XPToNext(st.Level)
		st.Level++
		st.MaxHP = MaxHPForLevel(st.Level)
		st.HP = st.MaxHP
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
	res.Log = append(res.Log, st.RecordKill(e.ID)...)
}

// lose: pemain pingsan, kehilangan separuh emas, dibawa pulang ke desa dengan separuh HP.
func (b *Battle) lose(p *Player, res *Result) {
	st := &p.State
	lost := st.Gold / 2
	st.Gold -= lost
	st.HP = max(1, st.MaxHP/2)
	st.Map, st.X, st.Y = SpawnMap, SpawnX, SpawnY
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
