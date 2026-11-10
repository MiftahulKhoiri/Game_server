package game

import (
	"errors"
	"fmt"
	"slices"
)

// Aula Pelatihan (v0.43.0): dua tempat latihan. Pahlawan pembantu berkelas dilatih satu per satu
// (level per pahlawan), prajurit biasa dilatih sebagai satu pasukan (satu level bersama).
// Tiap latihan memakai koin emas, 1 Kartu Keahlian, dan energi (dibayar di awal), lalu berjalan
// menurut jam server sampai selesai, juga saat game ditutup. Hasilnya diambil lewat "klaim".
const (
	KartuKeahlianID = "kartu_keahlian"

	MaxTrainLevel = 20

	TrainHero    = "pahlawan" // jenis latihan: satu pahlawan pembantu
	TrainSoldier = "prajurit" // jenis latihan: seluruh pasukan prajurit

	HeroTrainGold      = 80 // emas per level sekarang (level 1 -> 2 = 80)
	SoldierTrainGold   = 40
	HeroTrainEnergy    = 30
	SoldierTrainEnergy = 20
	HeroTrainSec       = 10 * 60 // detik per level sekarang (level 1 -> 2 = 10 menit)
	SoldierTrainSec    = 5 * 60

	KartuDropPercent = 8 // peluang musuh menjatuhkan Kartu Keahlian
)

// Kesalahan latihan.
var (
	ErrTrainBusy     = errors.New("tempat latihan ini sedang dipakai")
	ErrTrainMax      = errors.New("sudah mencapai level latihan tertinggi")
	ErrTrainNoCard   = errors.New("butuh 1 Kartu Keahlian")
	ErrTrainNone     = errors.New("tidak ada latihan yang berjalan")
	ErrTrainNotReady = errors.New("latihan belum selesai")
	ErrTrainKind     = errors.New("jenis latihan tidak dikenal")
	ErrTrainNoSquad  = errors.New("belum punya prajurit")
	ErrTrainLocation = errors.New("latihan hanya di Aula Pelatihan")
)

// TrainJob adalah satu latihan yang sedang berjalan. Target = id pahlawan (kosong untuk prajurit).
type TrainJob struct {
	Kind    string `json:"kind"`
	Target  string `json:"target,omitempty"`
	ToLevel int    `json:"to_level"`
	ReadyAt int64  `json:"ready_at"` // detik Unix
}

// HeroLevel adalah level latihan pahlawan pembantu (1 bila belum pernah dilatih).
func (s State) HeroLevel(id string) int {
	if l := s.HeroLevels[id]; l > 1 {
		return l
	}
	return 1
}

// SquadLevel adalah level latihan seluruh prajurit biasa (1 bila belum dilatih).
func (s State) SquadLevel() int {
	if s.SoldierLevel > 1 {
		return s.SoldierLevel
	}
	return 1
}

// TrainCost: biaya dan lama latihan dari level `from` ke from+1.
func TrainCost(kind string, from int) (gold, energy, sec int) {
	if kind == TrainSoldier {
		return SoldierTrainGold * from, SoldierTrainEnergy, SoldierTrainSec * from
	}
	return HeroTrainGold * from, HeroTrainEnergy, HeroTrainSec * from
}

// TrainJobOf mengembalikan latihan berjalan dari jenis itu.
func (s State) TrainJobOf(kind string) (TrainJob, bool) {
	for _, j := range s.Training {
		if j.Kind == kind {
			return j, true
		}
	}
	return TrainJob{}, false
}

// StartTrain memulai latihan. Satu tempat latihan (jenis) hanya satu latihan sekaligus.
// target = id pahlawan pembantu (jenis pahlawan) atau kosong (prajurit). now = detik Unix.
func (s *State) StartTrain(kind, target string, now int64) error {
	if s.Map != MapAula {
		return ErrTrainLocation
	}
	var from int
	switch kind {
	case TrainHero:
		if !s.HasAlly(target) {
			return ErrAllyNotOwn
		}
		from = s.HeroLevel(target)
	case TrainSoldier:
		if s.Soldiers < 1 {
			return ErrTrainNoSquad
		}
		target = ""
		from = s.SquadLevel()
	default:
		return ErrTrainKind
	}
	if _, busy := s.TrainJobOf(kind); busy {
		return ErrTrainBusy
	}
	if from >= MaxTrainLevel {
		return ErrTrainMax
	}
	gold, energy, sec := TrainCost(kind, from)
	if s.Gold < gold {
		return ErrNoGold
	}
	if s.itemQty(KartuKeahlianID) < 1 {
		return ErrTrainNoCard
	}
	if s.Energy() < energy {
		return ErrNoEnergy
	}
	s.Gold -= gold
	if gold > 0 {
		s.record(LedgerPurchase, "Biaya latihan", -gold)
	}
	s.RemoveItem(KartuKeahlianID, 1)
	s.spendEnergy(energy)
	s.Training = append(s.Training, TrainJob{Kind: kind, Target: target, ToLevel: from + 1, ReadyAt: now + int64(sec)})
	return nil
}

// ClaimTrain mengambil hasil latihan yang sudah selesai: level naik.
func (s *State) ClaimTrain(kind string, now int64) error {
	i := slices.IndexFunc(s.Training, func(j TrainJob) bool { return j.Kind == kind })
	if i < 0 {
		return ErrTrainNone
	}
	j := s.Training[i]
	if now < j.ReadyAt {
		return ErrTrainNotReady
	}
	switch j.Kind {
	case TrainHero:
		if s.HeroLevels == nil {
			s.HeroLevels = map[string]int{}
		}
		s.HeroLevels[j.Target] = j.ToLevel
	case TrainSoldier:
		s.SoldierLevel = j.ToLevel
	}
	s.Training = slices.Delete(s.Training, i, i+1)
	return nil
}

// heroPower adalah serangan satu pahlawan pembantu menurut level latihannya.
func (s State) heroPower(id string) int {
	l := s.HeroLevel(id)
	return AttackForLevel(s.Level)*(AllyPercent+10*(l-1))/100 + AllyBonus
}

func (s State) validateTraining() error {
	if s.SoldierLevel < 0 || s.SoldierLevel > MaxTrainLevel {
		return fmt.Errorf("level prajurit harus 0..%d", MaxTrainLevel)
	}
	if len(s.HeroLevels) > len(Heroes) {
		return ErrTrainKind
	}
	for id, l := range s.HeroLevels {
		if _, ok := HeroByID(id); !ok || id == "" || l < 1 || l > MaxTrainLevel {
			return ErrTrainKind
		}
	}
	if len(s.Training) > 2 {
		return ErrTrainKind
	}
	for i, j := range s.Training {
		if (j.Kind != TrainHero && j.Kind != TrainSoldier) || j.ToLevel < 2 || j.ToLevel > MaxTrainLevel || slices.ContainsFunc(s.Training[:i], func(o TrainJob) bool { return o.Kind == j.Kind }) {
			return ErrTrainKind
		}
	}
	return nil
}
