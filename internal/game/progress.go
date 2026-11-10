package game

import (
	"errors"
	"slices"
)

// Sistem kemajuan (roadmap no. 139, 145, 146, 150): bahan dari alam, tempa (crafting) di pandai besi,
// pohon kemampuan dengan poin dari naik level, dan pencapaian berhadiah. Semua aturan di server.

// Bahan alam (no. 146): setiap benda yang dihancurkan memberi satu bahan sesuai jenisnya.
const (
	KayuID   = "kayu"
	BatuID   = "bongkah_batu"
	SeratID  = "serat"
	maxCraft = 10 // paling banyak sekali tempa
)

// materialOf: bahan dari benda yang dihancurkan.
func materialOf(kind string) string {
	switch kind {
	case KindPohon:
		return KayuID
	case KindBatu:
		return BatuID
	case KindRumput:
		return SeratID
	}
	return ""
}

// Recipe adalah resep tempa: bahan masuk, satu barang keluar.
type Recipe struct {
	ID    string `json:"id"` // = id barang hasil
	Needs []Item `json:"needs"`
}

// Recipes adalah resep di pandai besi (no. 145).
var Recipes = []Recipe{
	{ID: PotionID, Needs: []Item{{ID: SeratID, Qty: 5}}},
	{ID: "helm_kulit", Needs: []Item{{ID: SeratID, Qty: 6}, {ID: KayuID, Qty: 1}}},
	{ID: "baju_kulit", Needs: []Item{{ID: SeratID, Qty: 8}, {ID: KayuID, Qty: 2}}},
	{ID: "pedang_besi", Needs: []Item{{ID: BatuID, Qty: 6}, {ID: KayuID, Qty: 3}}},
	{ID: "helm_besi", Needs: []Item{{ID: BatuID, Qty: 8}, {ID: KayuID, Qty: 2}}},
	{ID: "zirah_besi", Needs: []Item{{ID: BatuID, Qty: 12}, {ID: KayuID, Qty: 4}, {ID: "taring_goblin", Qty: 1}}},
	{ID: "pedang_baja", Needs: []Item{{ID: BatuID, Qty: 15}, {ID: KayuID, Qty: 5}, {ID: "taring_goblin", Qty: 2}}},
}

// Kesalahan kemajuan.
var (
	ErrUnknownRecipe  = errors.New("resep tidak dikenal")
	ErrCraftFar       = errors.New("tempa hanya di desa")
	ErrUnknownTalent  = errors.New("kemampuan tidak dikenal")
	ErrTalentMax      = errors.New("kemampuan ini sudah maksimal")
	ErrTalentLocked   = errors.New("kemampuan ini belum terbuka")
	ErrNoTalentPoints = errors.New("poin kemampuan habis; naikkan level")
)

// RecipeByID mencari resep.
func RecipeByID(id string) (Recipe, bool) {
	i := slices.IndexFunc(Recipes, func(r Recipe) bool { return r.ID == id })
	if i < 0 {
		return Recipe{}, false
	}
	return Recipes[i], true
}

// Craft menempa `qty` barang menurut resep `id` (bahan diambil dari tas). Hanya di desa.
func (s *State) Craft(id string, qty int) error {
	r, ok := RecipeByID(id)
	if !ok {
		return ErrUnknownRecipe
	}
	if qty < 1 || qty > maxCraft {
		return ErrBadQty
	}
	if !InVillage(s.Map) {
		return ErrCraftFar
	}
	for _, n := range r.Needs {
		if s.itemQty(n.ID) < n.Qty*qty {
			return ErrNotEnough
		}
	}
	probe := State{Inventory: slices.Clone(s.Inventory)}
	for _, n := range r.Needs {
		probe.RemoveItem(n.ID, n.Qty*qty)
	}
	if !probe.AddItem(id, qty) {
		return ErrInventoryFull
	}
	s.Inventory = probe.Inventory
	s.Crafted += qty
	s.checkAchievements()
	return nil
}

// --- pohon kemampuan (no. 139) ---

// TalentDef adalah satu kemampuan pasif. Needs/NeedRank: kemampuan prasyarat dan peringkatnya.
type TalentDef struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Max      int    `json:"max"`
	Per      int    `json:"per"` // besar efek per peringkat
	Needs    string `json:"needs,omitempty"`
	NeedRank int    `json:"need_rank,omitempty"`
}

// Talents adalah pohon kemampuan: dua akar (Tajam, Vitalitas) dan cabangnya.
var Talents = []TalentDef{
	{ID: "tajam", Name: "Tajam", Max: 5, Per: 2},                                                // serangan +2
	{ID: "kulit_tebal", Name: "Kulit Tebal", Max: 5, Per: 2},                                    // pertahanan +2
	{ID: "vitalitas", Name: "Vitalitas", Max: 5, Per: 10},                                       // HP maksimum +10
	{ID: "mata_elang", Name: "Mata Elang", Max: 3, Per: 4, Needs: "tajam", NeedRank: 3},         // peluang kritis +4%
	{ID: "hemat_tenaga", Name: "Hemat Tenaga", Max: 3, Per: 3, Needs: "vitalitas", NeedRank: 2}, // biaya jurus -3 energi
	{ID: "benteng", Name: "Benteng", Max: 3, Per: 5, Needs: "kulit_tebal", NeedRank: 3},         // HP maksimum +5 dan pertahanan +1
}

// TalentByID mencari kemampuan.
func TalentByID(id string) (TalentDef, bool) {
	i := slices.IndexFunc(Talents, func(t TalentDef) bool { return t.ID == id })
	if i < 0 {
		return TalentDef{}, false
	}
	return Talents[i], true
}

// rank: peringkat kemampuan `id` yang dimiliki.
func (s State) rank(id string) int { return s.Talent[id] }

// TalentPoints: poin yang belum dipakai (1 poin per naik level).
func (s State) TalentPoints() int {
	used := 0
	for _, r := range s.Talent {
		used += r
	}
	return max(0, s.Level-1-used)
}

// LearnTalent menaikkan satu peringkat kemampuan `id`.
func (s *State) LearnTalent(id string) error {
	t, ok := TalentByID(id)
	switch {
	case !ok:
		return ErrUnknownTalent
	case s.rank(id) >= t.Max:
		return ErrTalentMax
	case t.Needs != "" && s.rank(t.Needs) < t.NeedRank:
		return ErrTalentLocked
	case s.TalentPoints() < 1:
		return ErrNoTalentPoints
	}
	if s.Talent == nil {
		s.Talent = map[string]int{}
	}
	s.Talent[id]++
	if id == "vitalitas" || id == "benteng" {
		s.MaxHP = s.MaxHPNow()
	}
	s.checkAchievements()
	return nil
}

// MaxHPNow adalah HP maksimum dari level ditambah kemampuan.
func (s State) MaxHPNow() int {
	return MaxHPForLevel(s.Level) + s.rank("vitalitas")*10 + s.rank("benteng")*5
}

// talentAttack / talentDefense / CritPercent / skillCost: efek kemampuan pada pertarungan.
func (s State) talentAttack() int  { return s.rank("tajam") * 2 }
func (s State) talentDefense() int { return s.rank("kulit_tebal")*2 + s.rank("benteng") }

// CritPercent adalah peluang kritis pemain (persen).
func (s State) CritPercent() int { return CritChance + s.rank("mata_elang")*4 }

func (s State) skillCost(base int) int { return max(5, base-s.rank("hemat_tenaga")*3) }

func (s State) validTalents() bool {
	used := 0
	for id, r := range s.Talent {
		t, ok := TalentByID(id)
		if !ok || r < 0 || r > t.Max {
			return false
		}
		used += r
	}
	return used <= max(0, s.Level-1)
}

// --- pencapaian (no. 150) ---

// AchievementDef adalah satu pencapaian dan hadiah emasnya.
type AchievementDef struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Gold int    `json:"gold"`
}

// Achievements adalah daftar pencapaian.
var Achievements = []AchievementDef{
	{ID: "menang_10", Name: "Pemburu Pemula: menang 10 kali", Gold: 30},
	{ID: "menang_100", Name: "Pembasmi Monster: menang 100 kali", Gold: 200},
	{ID: "level_5", Name: "Petualang: mencapai level 5", Gold: 50},
	{ID: "level_10", Name: "Pahlawan Desa: mencapai level 10", Gold: 150},
	{ID: "misi_1", Name: "Penolong: menyelesaikan misi pertama", Gold: 20},
	{ID: "misi_5", Name: "Andalan Desa: menyelesaikan 5 misi", Gold: 100},
	{ID: "tempa_1", Name: "Pengrajin: menempa barang pertama", Gold: 20},
	{ID: "rumah", Name: "Tuan Rumah: memiliki rumah sendiri", Gold: 50},
	{ID: "sahabat", Name: "Kawan Sejati: bersahabat dengan seorang warga", Gold: 40},
	{ID: "kemampuan_1", Name: "Berkembang: mempelajari kemampuan pertama", Gold: 20},
}

// AchievementByID mencari pencapaian.
func AchievementByID(id string) (AchievementDef, bool) {
	i := slices.IndexFunc(Achievements, func(a AchievementDef) bool { return a.ID == id })
	if i < 0 {
		return AchievementDef{}, false
	}
	return Achievements[i], true
}

func (s State) achieved(id string) bool { return slices.Contains(s.Done, id) }

// checkAchievements membuka pencapaian yang syaratnya terpenuhi dan memberi emasnya.
// Mengembalikan nama pencapaian yang baru terbuka.
func (s *State) checkAchievements() []string {
	claimed := 0
	for _, q := range s.Quests {
		if q.Status == QuestClaimed {
			claimed++
		}
	}
	friend := false
	for _, r := range s.Reputation {
		if r.Points >= RepBestFriend {
			friend = true
		}
	}
	learned := 0
	for _, r := range s.Talent {
		learned += r
	}
	cond := map[string]bool{
		"menang_10": s.Wins >= 10, "menang_100": s.Wins >= 100,
		"level_5": s.Level >= 5, "level_10": s.Level >= 10,
		"misi_1": claimed >= 1, "misi_5": claimed >= 5,
		"tempa_1": s.Crafted >= 1, "rumah": s.House, "sahabat": friend, "kemampuan_1": learned >= 1,
	}
	var out []string
	for _, a := range Achievements {
		if cond[a.ID] && !s.achieved(a.ID) {
			s.Done = append(s.Done, a.ID) // terbuka; emasnya diambil di layar Pencapaian (ClaimAchievement)
			out = append(out, a.Name)
		}
	}
	return out
}

// Kesalahan pencapaian.
var (
	ErrUnknownAchievement = errors.New("pencapaian tidak dikenal")
	ErrAchievementLocked  = errors.New("pencapaian ini belum terbuka")
	ErrAchievementTaken   = errors.New("hadiah pencapaian ini sudah diambil")
)

// ClaimAchievement mengambil hadiah emas pencapaian yang sudah terbuka.
func (s *State) ClaimAchievement(id string) error {
	a, ok := AchievementByID(id)
	switch {
	case !ok:
		return ErrUnknownAchievement
	case !s.achieved(id):
		return ErrAchievementLocked
	case slices.Contains(s.Taken, id):
		return ErrAchievementTaken
	}
	s.Taken = append(s.Taken, id)
	s.gainGold(a.Gold)
	s.record(LedgerQuest, "Hadiah pencapaian "+a.Name, a.Gold)
	return nil
}

func (s State) validAchievements() bool {
	if len(s.Done) > len(Achievements) || len(s.Taken) > len(s.Done) {
		return false
	}
	for _, id := range s.Taken {
		if !s.achieved(id) {
			return false
		}
	}
	for _, id := range s.Done {
		if _, ok := AchievementByID(id); !ok {
			return false
		}
	}
	return s.Wins >= 0 && s.Crafted >= 0
}

// --- kelangkaan barang (no. 144) ---

// Rarity: "biasa", "langka", atau "epik" (warna nama di klien).
func Rarity(id string) string {
	switch id {
	case "pedang_rune":
		return "epik"
	case "permata_merah", DiamondID, "koin_kuno", "zirah_besi", "pedang_baja", "helm_besi", "taring_goblin":
		return "langka"
	}
	return "biasa"
}
