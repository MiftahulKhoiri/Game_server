package game

import (
	"errors"
	"slices"
)

// Peran pahlawan pendamping dan formasi prajurit (v0.78.0, AI hybrid fase 2). Semua dihitung server; klien hanya
// menggambar posisi dan animasi. Tidak ada angka acak tambahan: tiap pendamping tetap memakai satu angka acak per
// giliran seperti sebelumnya.

// Peran (Event.Tactic pada kejadian pendamping).
const (
	RoleTank   = "tank"   // Ksatria: menarik perhatian musuh, melindungi prajurit
	RoleHeavy  = "heavy"  // Pendekar Kapak: pukulan berat yang menembus separuh pertahanan
	RoleRanged = "ranged" // Pemanah: menjaga jarak (jarang diincar), unggul melawan musuh lincah/terbang
	RoleQuick  = "quick"  // Pendekar Tombak: tusukan cepat dari jangkauan menengah yang menunda serangan musuh
	RoleMagic  = "magic"  // Penyihir: sihir menembus separuh pertahanan, atau menyembuhkan kawan yang terluka
	RoleHeal   = "heal"
)

// HeroRole: peran pahlawan pendamping menurut id (id pahlawan tidak diubah).
var HeroRole = map[string]string{
	"ksatria": RoleTank, "pendekar_kapak": RoleHeavy, "pemanah": RoleRanged, "pendekar_tombak": RoleQuick, "penyihir": RoleMagic,
}

// Angka peran.
const (
	TankAtkPct      = 90  // Ksatria memukul sedikit lebih lemah (ia menahan serangan)
	TankGuardPct    = 85  // selama Ksatria sehat, prajurit menerima sekian persen kerusakan
	RangedVsAirPct  = 125 // Pemanah melawan musuh lincah/terbang (kelelawar, belalang, naga)
	QuickPushMs     = 150 // tusukan Pendekar Tombak menunda serangan musuh berikutnya sekian ms ...
	QuickPushMaxMs  = 600 // ... paling banyak sekian ms di depan jadwal semula per serangan musuh
	MageHealBelow   = 50  // Penyihir menyembuhkan bila ada kawan (atau pemain) di bawah sekian persen HP
	MageHealPct     = 120 // besar penyembuhan = kerusakan sihirnya x ini persen
	pushOriginUnset = -1
)

// Formasi prajurit (State.Formation). "" = barisan (perilaku lama).
const (
	FormationLine   = ""          // barisan biasa
	FormationShield = "perisai"   // Shield Wall: menahan kerusakan, serangan lebih lemah
	FormationSpear  = "tombak"    // Spear Formation: serangan lebih kuat, sedikit lebih rentan
	FormationArcher = "pemanah"   // Archer Formation: jarang diincar musuh, serangan sedikit lebih lemah
	FormationCircle = "lingkaran" // Circle Formation: mengepung pemain, menahan semua serangan yang bukan untuk pendamping
	FormationCharge = "serbu"     // Charge Formation: serbuan pembuka dua kali lipat, lebih rentan
)

// FormationDef: pengaruh formasi pada prajurit (persen).
type FormationDef struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Desc     string `json:"desc"`
	AtkPct   int    `json:"atk_pct"`   // serangan prajurit
	TakenPct int    `json:"taken_pct"` // kerusakan yang diterima prajurit
	Share    int    `json:"share"`     // dari 3 serangan musuh yang tidak mengincar pahlawan, sekian mengenai prajurit
	FirstPct int    `json:"first_pct"` // serangan pertama pasukan (serbuan); 0 = sama
}

// Formations: daftar formasi (urutan untuk layar klien).
var Formations = []FormationDef{
	{ID: FormationLine, Name: "Barisan", Desc: "Seimbang: prajurit menahan 2 dari 3 serangan.", AtkPct: 100, TakenPct: 100, Share: 2},
	{ID: FormationShield, Name: "Dinding Perisai", Desc: "Kerusakan diterima -30%, serangan -20%.", AtkPct: 80, TakenPct: 70, Share: 2},
	{ID: FormationSpear, Name: "Formasi Tombak", Desc: "Serangan +25%, kerusakan diterima +15%.", AtkPct: 125, TakenPct: 115, Share: 2},
	{ID: FormationArcher, Name: "Formasi Pemanah", Desc: "Jarang diincar (1 dari 3 serangan), serangan -10%.", AtkPct: 90, TakenPct: 100, Share: 1},
	{ID: FormationCircle, Name: "Lingkaran", Desc: "Mengepung pemain: menahan semua serangan, kerusakan diterima -10%, serangan -20%.", AtkPct: 80, TakenPct: 90, Share: 3},
	{ID: FormationCharge, Name: "Serbuan", Desc: "Serbuan pembuka x2, kerusakan diterima +15%.", AtkPct: 100, TakenPct: 115, Share: 2, FirstPct: 200},
}

// ErrUnknownFormation: id formasi tidak dikenal.
var ErrUnknownFormation = errors.New("formasi tidak dikenal")

// FormationByID mencari formasi ("" = barisan).
func FormationByID(id string) (FormationDef, bool) {
	for _, f := range Formations {
		if f.ID == id {
			return f, true
		}
	}
	return FormationDef{}, false
}

// SetFormation memilih formasi prajurit.
func (s *State) SetFormation(id string) error {
	if _, ok := FormationByID(id); !ok {
		return ErrUnknownFormation
	}
	s.Formation = id
	return nil
}

func validFormation(id string) bool {
	_, ok := FormationByID(id)
	return ok
}

func (s State) formation() FormationDef {
	if f, ok := FormationByID(s.Formation); ok {
		return f
	}
	return Formations[0]
}

// tankUp: Ksatria ada di party dan masih sehat.
func (s State) tankUp() bool {
	if !slices.Contains(s.Party, "ksatria") {
		return false
	}
	hp, _, ok := s.AllyHealth("ksatria")
	return ok && hp > 0
}

// tauntTarget: SELECT_TARGET musuh terhadap pendamping. Ksatria sehat menarik perhatian; Pemanah menjaga jarak
// (hanya diincar bila tidak ada pendamping sehat lain). "" bila tidak ada pendamping sehat.
func (s State) tauntTarget() string {
	if s.tankUp() {
		return "ksatria"
	}
	fallback := ""
	for _, id := range s.Party {
		if hp, _, ok := s.AllyHealth(id); !ok || hp <= 0 {
			continue
		}
		if HeroRole[id] == RoleRanged {
			fallback = id
			continue
		}
		return id
	}
	return fallback
}

// allyTurn: daya serang satu pendamping menurut perannya. defense = pertahanan yang dipakai, pct = pengali.
func allyTurn(id string, e Enemy) (defense, pct int) {
	defense, pct = e.Defense, 100
	switch HeroRole[id] {
	case RoleTank:
		pct = TankAtkPct
	case RoleHeavy, RoleMagic:
		defense = e.Defense / 2
	case RoleRanged:
		if ProfileFor(e).Evasive || ProfileFor(e).ID == "naga" {
			pct = RangedVsAirPct
		}
	}
	return defense, pct
}

// healTarget: kawan dengan persen HP terendah di bawah MageHealBelow ("" = pemain, ok=false = tidak ada).
func (s State) healTarget() (id string, ok bool) {
	best := MageHealBelow
	if s.MaxHP > 0 && s.HP*100/s.MaxHP < best {
		best, id, ok = s.HP*100/s.MaxHP, "", true
	}
	for _, a := range s.Party {
		hp, mx, has := s.AllyHealth(a)
		if !has || hp <= 0 || mx <= 0 {
			continue
		}
		if pct := hp * 100 / mx; pct < best {
			best, id, ok = pct, a, true
		}
	}
	return id, ok
}
