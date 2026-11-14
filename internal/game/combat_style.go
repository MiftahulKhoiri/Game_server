package game

// Gaya bertarung per senjata pahlawan (roadmap no. 154-163). Server yang menghitung semuanya;
// klien hanya menampilkan gerakan dan efek sesuai gaya.

// Gaya senjata.
const (
	StylePedang = "pedang" // seimbang (patokan)
	StyleKapak  = "kapak"  // lambat, pukulan berat
	StyleBusur  = "busur"  // jarak jauh, lebih mudah kritis
	StyleTombak = "tombak" // cepat, pukulan lebih ringan
	StyleSihir  = "sihir"  // menembus sebagian pertahanan musuh
)

// WeaponStyle adalah aturan satu gaya senjata.
type WeaponStyle struct {
	ID         string `json:"id"`
	AttackMs   int64  `json:"attack_ms"`   // waktu isi ulang serangan biasa
	DamagePct  int    `json:"damage_pct"`  // kerusakan serangan biasa (persen dari serangan)
	CritBonus  int    `json:"crit_bonus"`  // tambahan peluang kritis (persen)
	PierceDef  int    `json:"pierce_def"`  // persen pertahanan musuh yang diabaikan
	ReachTiles int    `json:"reach_tiles"` // jangkauan di dunia (petak, untuk klien)
}

// WeaponStyles: aturan semua gaya. Pedang = aturan lama (900 ms, 100%).
var WeaponStyles = map[string]WeaponStyle{
	StylePedang: {ID: StylePedang, AttackMs: 900, DamagePct: 100, ReachTiles: 2},
	StyleKapak:  {ID: StyleKapak, AttackMs: 1200, DamagePct: 128, ReachTiles: 2},
	StyleBusur:  {ID: StyleBusur, AttackMs: 950, DamagePct: 100, CritBonus: 8, ReachTiles: 6},
	StyleTombak: {ID: StyleTombak, AttackMs: 750, DamagePct: 92, ReachTiles: 3},
	StyleSihir:  {ID: StyleSihir, AttackMs: 1050, DamagePct: 95, PierceDef: 50, ReachTiles: 5},
}

// Kombo (no. 159): serangan biasa ketiga berturut-turut, masing-masing dalam ComboWindowMs setelah
// serangan sebelumnya siap, menjadi Pukulan Kombo. Terkena serangan musuh memutus kombo.
const (
	ComboHits     = 3
	ComboWindowMs = 1500
	ComboPct      = 150
)

// Menghindar (no. 162): serangan musuh yang tiba dalam DodgeMs setelah menekan Hindar meleset.
const (
	ActionDodge = "dodge"
	DodgeMs     = 500
)

// Style mengembalikan gaya senjata pahlawan aktif, disesuaikan senjata yang dipakai (v0.82.0):
// SpeedPct mengubah waktu isi ulang serangan biasa dan Crit menambah peluang kritis.
func (s State) Style() WeaponStyle {
	ws := WeaponStyles[s.HeroDef().styleID()]
	if def, ok := ItemByID(s.Equipment.Weapon); ok {
		if def.SpeedPct > 0 {
			ws.AttackMs = ws.AttackMs * int64(def.SpeedPct) / 100
		}
		ws.CritBonus += def.Crit
	}
	return ws
}

func (h HeroDef) styleID() string {
	if _, ok := WeaponStyles[h.Style]; ok {
		return h.Style
	}
	return StylePedang
}

// cooldown: waktu isi ulang aksi untuk pemain ini (serangan biasa mengikuti gaya senjata).
func (s State) cooldown(action string) int64 {
	if action == ActionAttack {
		return s.Style().AttackMs
	}
	return CooldownMs[action]
}

// styleDefense: pertahanan musuh setelah ditembus sihir.
func (ws WeaponStyle) styleDefense(def int) int {
	return def - def*ws.PierceDef/100
}
