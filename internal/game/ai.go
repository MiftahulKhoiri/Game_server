package game

import "strings"

// AI musuh HYBRID (v0.78.0): mesin keadaan (FSM) + profil perilaku per keluarga musuh + keputusan situasional
// (HP sendiri, HP pemain, jumlah kawan pemain, ronde) + pilihan target + prioritas taktik. Bukan model bahasa:
// semua keputusan deterministik di server Go (TIDAK memakai angka acak tambahan, jadi urutan acak pertarungan
// tetap sama dengan sebelumnya) dan hasilnya hanya dikirim ke klien untuk dianimasikan.
//
// Alur: IDLE -> DETECT -> ASSESS -> SELECT_TARGET -> SELECT_TACTIC -> APPROACH -> WINDUP -> ATTACK -> RECOVER ->
// REASSESS. Server hanya menyimpan keadaan yang berarti untuk aturan (Battle.AIState): approach (sebelum serangan
// pertama), windup (taktik berikutnya sudah dipilih), recover (setelah serangan berat), retreat (mundur).
// IDLE/DETECT terjadi di dunia (klien: roamer.gd) sebelum pertarungan dimulai.

// Taktik serangan musuh.
const (
	TacticNormal  = "normal"  // serangan biasa
	TacticHeavy   = "heavy"   // serangan berat: kerusakan besar, ancang-ancang terlihat, jeda pemulihan lebih lama
	TacticQuick   = "quick"   // serangan cepat: kerusakan kecil, jeda pendek
	TacticAmbush  = "ambush"  // sergapan/terkaman pembuka
	TacticArea    = "area"    // serangan area: pemain, pendamping, dan barisan depan prajurit sekaligus
	TacticRanged  = "ranged"  // serangan jarak jauh (napas api): tidak bisa ditangkis sempurna, tetap bisa dihindari
	TacticRetreat = "retreat" // mundur bertahan sesaat (sekali per pertarungan): tidak menyerang, kerusakan diterima /2
)

// Keadaan FSM yang disimpan di Battle.AIState.
const (
	AIApproach = "approach"
	AIWindup   = "windup"
	AIRecover  = "recover"
	AIRetreat  = "retreat"
)

// AIProfile: profil perilaku satu keluarga musuh. Angka persen; 0 = tidak dipakai.
type AIProfile struct {
	ID          string
	HeavyEvery  int   // tiap serangan ke-N berat (0 = tidak pernah)
	HeavyPct    int   // kerusakan serangan berat (persen)
	RecoverMs   int64 // jeda tambahan setelah serangan berat
	QuickPct    int   // serangan biasa menjadi cepat: kerusakan sekian persen ...
	QuickIvPct  int   // ... dengan jeda sekian persen
	IntervalPct int   // pengali jeda semua serangan (lambat/lincah); 0 = 100
	Ambush      int   // serangan pertama = sergapan sekian persen kerusakan (0 = tidak)
	Pack        bool  // berkawanan/mengapit: lebih sering mengincar pendamping dan prajurit
	Press       bool  // menekan: saat HP pemain < 35% serangan berat tiap ke-2
	RetreatPct  int   // sekali per pertarungan mundur saat HP sendiri di bawah sekian persen
	Evasive     bool  // lincah: jurus berat pemain (Skill 1) hanya mengenai 60%
	HeavyArea   bool  // serangan berat mengenai area (pemain + pendamping + 3 prajurit depan)
	HeavyRanged bool  // serangan berat jarak jauh (tidak bisa ditangkis sempurna)
}

// Profil per keluarga. Keseimbangan: rata-rata kerusakan per detik kira-kira sama dengan serangan biasa
// (serangan berat lebih besar tetapi diikuti jeda pemulihan), jadi musuh terasa berbeda tanpa sekadar
// menaikkan angka. Diperiksa TestAIProfilesKeepBalance.
var aiProfiles = map[string]AIProfile{
	"goblin":    {ID: "goblin", Pack: true, RetreatPct: 25, QuickPct: 85, QuickIvPct: 85},
	"orc":       {ID: "orc", HeavyEvery: 3, HeavyPct: 160, RecoverMs: 700, IntervalPct: 110, Press: true},
	"serigala":  {ID: "serigala", Pack: true, Ambush: 140, Press: true},
	"ular":      {ID: "ular", Ambush: 150, IntervalPct: 105},
	"babi":      {ID: "babi", HeavyEvery: 2, HeavyPct: 150, RecoverMs: 900},
	"kelelawar": {ID: "kelelawar", QuickPct: 70, QuickIvPct: 70, Evasive: true},
	"belalang":  {ID: "belalang", QuickPct: 75, QuickIvPct: 75, Evasive: true, Ambush: 130},
	"golem":     {ID: "golem", HeavyEvery: 3, HeavyPct: 170, RecoverMs: 600, IntervalPct: 125, HeavyArea: true},
	"naga":      {ID: "naga", HeavyEvery: 3, HeavyPct: 150, RecoverMs: 500, HeavyRanged: true, HeavyArea: true},
}

// ProfileFor: profil AI musuh menurut id (dan model bos). Musuh tanpa keluarga yang dikenal memakai profil
// kosong = perilaku lama (serangan biasa berkala).
func ProfileFor(e Enemy) AIProfile {
	id := e.ID
	switch {
	case e.ID == MalzarethID:
		return AIProfile{ID: "malzareth"} // pola fase sendiri (story.go), tidak diubah
	case strings.HasPrefix(id, "naga") || e.ID == AldragorID || strings.HasPrefix(id, "ogre_gunung_"):
		return aiProfiles["naga"]
	case strings.HasPrefix(id, "golem") || strings.HasPrefix(id, "beruang_batu"):
		return aiProfiles["golem"]
	case strings.HasPrefix(id, "goblin"):
		return aiProfiles["goblin"]
	case strings.HasPrefix(id, "orc") || strings.HasPrefix(id, "ogre") || strings.HasPrefix(id, "kepala_goblin") ||
		id == "raja_goblin" || id == "prajurit_kutukan":
		return aiProfiles["orc"]
	case strings.HasPrefix(id, "serigala"):
		return aiProfiles["serigala"]
	case strings.HasPrefix(id, "ular"):
		return aiProfiles["ular"]
	case strings.HasPrefix(id, "babi"):
		return aiProfiles["babi"]
	case strings.HasPrefix(id, "kelelawar"):
		return aiProfiles["kelelawar"]
	case strings.HasPrefix(id, "belalang"):
		return aiProfiles["belalang"]
	}
	return AIProfile{ID: "biasa"}
}

// aiPlan: keputusan untuk satu serangan musuh.
type aiPlan struct {
	tactic    string
	dmgPct    int   // pengali kerusakan
	ivPct     int   // pengali jeda sampai serangan berikutnya
	extraMs   int64 // jeda pemulihan tambahan
	area      bool
	noPerfect bool // tidak bisa ditangkis sempurna
	allyFirst bool // serangan ini diarahkan ke pendamping/prajurit (mengapit)
}

// assess: ASSESS + SELECT_TACTIC untuk serangan bernomor b.Round. Hanya membaca keadaan pertarungan (tanpa
// angka acak). playerHPPct = sisa HP pemain (persen), helpers = jumlah pendamping sehat + prajurit.
func (b *Battle) assess(e Enemy, prof AIProfile, playerHPPct, helpers int) aiPlan {
	plan := aiPlan{tactic: TacticNormal, dmgPct: 100, ivPct: 100}
	if prof.IntervalPct > 0 {
		plan.ivPct = prof.IntervalPct
	}
	ownPct := 100
	if b.EnemyMaxHP > 0 {
		ownPct = b.EnemyHP * 100 / b.EnemyMaxHP
	}
	switch {
	case prof.RetreatPct > 0 && !b.Retreated && ownPct < prof.RetreatPct && b.Round > 1:
		// Kondisi tidak menguntungkan: mundur sekali, bertahan, lalu kembali menyerang.
		plan.tactic, plan.dmgPct, plan.ivPct = TacticRetreat, 0, 60
		return plan
	case prof.Ambush > 0 && b.Round == 1:
		plan.tactic, plan.dmgPct = TacticAmbush, prof.Ambush
	case prof.HeavyEvery > 0 && b.heavyDue(prof, playerHPPct):
		plan.tactic, plan.dmgPct, plan.extraMs = TacticHeavy, prof.HeavyPct, prof.RecoverMs
		plan.area = prof.HeavyArea
		plan.noPerfect = prof.HeavyRanged
		if prof.HeavyRanged {
			plan.tactic = TacticRanged
		}
		if prof.HeavyArea && !prof.HeavyRanged {
			plan.tactic = TacticArea
		}
	case prof.QuickPct > 0:
		plan.tactic, plan.dmgPct = TacticQuick, prof.QuickPct
		plan.ivPct = plan.ivPct * prof.QuickIvPct / 100
	}
	// SELECT_TARGET: kawanan mengapit pendamping/prajurit pada serangan genap bila pemain punya kawan.
	if prof.Pack && helpers > 0 && b.Round%2 == 0 {
		plan.allyFirst = true
	}
	return plan
}

func (b *Battle) heavyDue(prof AIProfile, playerHPPct int) bool {
	every := prof.HeavyEvery
	if prof.Press && playerHPPct < 35 && every > 2 {
		every = 2 // menekan target yang lemah
	}
	return b.Round%every == 0
}

// nextIntent: taktik yang akan dipakai pada serangan berikutnya (untuk ancang-ancang di klien). Sama dengan
// keputusan assess, dihitung dengan keadaan sekarang.
func (b *Battle) nextIntent(e Enemy, st *State) string {
	prof := ProfileFor(e)
	if prof.ID == "biasa" || prof.ID == "malzareth" {
		return ""
	}
	if t := b.assess(e, prof, hpPct(st), b.helpers(st)).tactic; t != TacticNormal {
		return t
	}
	return ""
}

func hpPct(st *State) int {
	if st.MaxHP <= 0 {
		return 100
	}
	return st.HP * 100 / st.MaxHP
}

// helpers: pendamping sehat + prajurit yang masih bertarung.
func (b *Battle) helpers(st *State) int {
	n := len(b.SoldierHP)
	for _, id := range st.Party {
		if hp, _, ok := st.AllyHealth(id); ok && hp > 0 {
			n++
		}
	}
	return n
}
