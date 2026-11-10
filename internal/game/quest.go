package game

import (
	"errors"
	"fmt"
	"slices"
	"strings"
)

// Status sebuah misi pada pemain. Misi yang belum diterima tidak ada di State.
const (
	QuestLocked    = "locked"    // belum bisa diterima: misi prasyarat belum selesai (hanya tampil di GET /v1/quests)
	QuestAvailable = "available" // belum diterima (hanya tampil di GET /v1/quests)
	QuestActive    = "active"    // sedang dikerjakan
	QuestDone      = "done"      // target tercapai, hadiah belum diambil
	QuestClaimed   = "claimed"   // hadiah sudah diambil
)

// MaxQuests membatasi jumlah catatan misi per pemain.
const MaxQuests = 100

// QuestDef adalah definisi misi "kalahkan N musuh". Misi baru: tambahkan satu
// baris di quests di bawah. Pemberi misi (Giver) adalah NPC yang memberi hadiah.
type QuestDef struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Giver       string   `json:"giver"` // id NPC, sama dengan nama gambar di client/assets/characters/
	Description string   `json:"description"`
	TargetIDs   []string `json:"target_ids"` // id musuh yang dihitung
	Count       int      `json:"target_count"`
	RewardGold  int      `json:"reward_gold"`
	// RewardItems adalah barang hadiah (id barang harus ada di item.go).
	RewardItems []Item `json:"reward_items,omitempty"`
	// Requires: id misi yang hadiahnya harus sudah diambil sebelum misi ini bisa diterima.
	Requires string `json:"requires,omitempty"`
	// CollectID: bila diisi, misi ini jenis "antar barang": pemain menyerahkan Count
	// buah barang ini ke pemberi misi (TargetIDs dikosongkan). Barang diambil saat hadiah diklaim.
	CollectID string `json:"collect_id,omitempty"`
	// StoryMin: langkah cerita utama (State.Story) minimum agar misi ini bisa diterima.
	StoryMin int `json:"story_min,omitempty"`
}

// RewardText menjelaskan hadiah untuk ditampilkan, mis. "25 emas, Permata Merah x1".
func (q QuestDef) RewardText() string {
	var parts []string
	if q.RewardGold > 0 {
		parts = append(parts, fmt.Sprintf("%d emas", q.RewardGold))
	}
	for _, it := range q.RewardItems {
		name := it.ID
		if def, ok := ItemByID(it.ID); ok {
			name = def.Name
		}
		parts = append(parts, fmt.Sprintf("%s x%d", name, it.Qty))
	}
	return strings.Join(parts, ", ")
}

// Misi utama lama (Nenek -> Petani -> Monster Batu -> Raja Iblis) diganti cerita utama The Last Dragon (story.go,
// docs/STORY.md) sejak v0.67.0; catatan misi lama di data pemain dibiarkan dan tidak berpengaruh. Yang tersisa di sini
// misi sampingan dari Nenek dan Petani; StoryMin = langkah cerita minimum agar misi bisa diterima.
var quests = []QuestDef{
	{
		ID:          "kebun_babi",
		Title:       "Kebun yang Dirusak",
		Giver:       "nenek_penjual",
		Description: "Sejak kutukan Malzareth, babi hutan di Perbatasan menjadi buas dan mengobrak-abrik kebun sayur desa. Kalahkan 3 babi hutan di Perbatasan.",
		TargetIDs:   []string{"babi_hutan"},
		Count:       3,
		RewardGold:  35,
		RewardItems: []Item{{ID: "baju_kulit", Qty: 1}},
		StoryMin:    1,
	},
	{
		ID:          "serigala_perbatasan",
		Title:       "Serigala di Jalan Raja",
		Giver:       "petani",
		Description: "Serigala-serigala yang terkena kutukan menghadang pedagang di jalan raja Perbatasan. Kalahkan 4 serigala hutan.",
		TargetIDs:   []string{"serigala_hutan"},
		Count:       4,
		RewardGold:  70,
		RewardItems: []Item{{ID: PotionID, Qty: 2}},
		StoryMin:    1,
	},
	{
		ID:          "ramuan_nenek",
		Title:       "Obat untuk Korban Serangan",
		Giver:       "nenek_penjual",
		Description: "Banyak warga terluka saat desa diserang malam itu. Nenek bisa meracik obat dari 3 Taring Goblin. Bawa taringnya ke Nenek, lalu ambil hadiahnya.",
		CollectID:   "taring_goblin",
		Count:       3,
		RewardGold:  30,
		RewardItems: []Item{{ID: PotionID, Qty: 3}},
		StoryMin:    3,
	},
	{
		ID:          "sisa_pasukan",
		Title:       "Sisa Pasukan Terkutuk",
		Giver:       "petani",
		Description: "Panglima Orc Batu sudah tumbang, tetapi orc-orc yang masih terkutuk berkeliaran di Benteng Orc. Kalahkan 5 orc di sana (Orc Gua, Orc Penjaga, atau Orc Buas).",
		TargetIDs:   []string{"orc_gua", "orc_penjaga", "orc_buas"},
		Count:       5,
		RewardGold:  300,
		RewardItems: []Item{{ID: "zirah_besi", Qty: 1}},
		StoryMin:    7,
	},
	{
		ID:          "permata_nenek",
		Title:       "Permata Pengikat Kutukan",
		Giver:       "nenek_penjual",
		Description: "Permata Merah menyimpan sisa sihir Malzareth. Serahkan 3 Permata Merah kepada Nenek agar disucikan di kuil desa.",
		CollectID:   "permata_merah",
		Count:       3,
		RewardGold:  120,
		RewardItems: []Item{{ID: "pedang_baja", Qty: 1}},
		StoryMin:    7,
	},
}

// QuestProgress adalah catatan misi pada pemain (disimpan di State).
type QuestProgress struct {
	ID       string `json:"id"`
	Status   string `json:"status"`
	Progress int    `json:"progress"`
}

// QuestView adalah gabungan definisi dan kemajuan pemain, untuk klien.
type QuestView struct {
	QuestDef
	Status     string `json:"status"`
	Progress   int    `json:"progress"`
	RewardText string `json:"reward_text"`
}

// Kesalahan misi.
var (
	ErrUnknownQuest  = errors.New("misi tidak dikenal")
	ErrQuestTaken    = errors.New("misi ini sudah diterima")
	ErrQuestNotReady = errors.New("misi belum selesai")
	ErrQuestClaimed  = errors.New("hadiah misi sudah diambil")
	ErrTooManyQuests = errors.New("catatan misi terlalu banyak")
	ErrQuestLocked   = errors.New("selesaikan misi sebelumnya dulu")
)

// Quests mengembalikan salinan semua definisi misi.
func Quests() []QuestDef { return slices.Clone(quests) }

// QuestByID mencari misi berdasarkan id.
func QuestByID(id string) (QuestDef, bool) {
	for _, q := range quests {
		if q.ID == id {
			return q, true
		}
	}
	return QuestDef{}, false
}

func (s *State) questIndex(id string) int {
	return slices.IndexFunc(s.Quests, func(q QuestProgress) bool { return q.ID == id })
}

// QuestViews menggabungkan semua misi dengan kemajuan pemain.
func (s State) QuestViews() []QuestView {
	out := make([]QuestView, 0, len(quests))
	for _, def := range quests {
		v := QuestView{QuestDef: def, Status: QuestAvailable, RewardText: def.RewardText()}
		if i := s.questIndex(def.ID); i >= 0 {
			v.Status, v.Progress = s.Quests[i].Status, s.Quests[i].Progress
			if def.CollectID != "" && v.Status == QuestActive {
				// Misi antar barang: kemajuan = barang yang sedang dibawa.
				v.Progress = min(s.itemQty(def.CollectID), def.Count)
				if v.Progress >= def.Count {
					v.Status = QuestDone
				}
			}
		} else if s.questLocked(def) {
			v.Status = QuestLocked
		}
		out = append(out, v)
	}
	return out
}

// questLocked: prasyarat misi ini belum diselesaikan (hadiahnya belum diambil).
func (s *State) questLocked(def QuestDef) bool {
	if s.Story < def.StoryMin {
		return true
	}
	if def.Requires == "" {
		return false
	}
	i := s.questIndex(def.Requires)
	return i < 0 || s.Quests[i].Status != QuestClaimed
}

// AcceptQuest menerima misi.
func (s *State) AcceptQuest(id string) error {
	def, ok := QuestByID(id)
	if !ok {
		return ErrUnknownQuest
	}
	if s.questIndex(id) >= 0 {
		return ErrQuestTaken
	}
	if s.questLocked(def) {
		return ErrQuestLocked
	}
	if len(s.Quests) >= MaxQuests {
		return ErrTooManyQuests
	}
	s.Quests = append(s.Quests, QuestProgress{ID: id, Status: QuestActive})
	return nil
}

// ClaimQuest mengambil hadiah misi yang sudah selesai dan mengembalikan definisinya.
func (s *State) ClaimQuest(id string) (QuestDef, error) {
	def, ok := QuestByID(id)
	if !ok {
		return QuestDef{}, ErrUnknownQuest
	}
	i := s.questIndex(id)
	switch {
	case i < 0:
		return QuestDef{}, ErrQuestNotReady
	case s.Quests[i].Status == QuestClaimed:
		return QuestDef{}, ErrQuestClaimed
	}
	// Barang masuk tas dulu; bila tas penuh, hadiah ditolak dan tidak ada yang berubah.
	probe := State{Inventory: slices.Clone(s.Inventory)}
	if def.CollectID != "" {
		// Misi antar barang: barang yang diminta diserahkan lebih dulu.
		if !probe.RemoveItem(def.CollectID, def.Count) {
			return QuestDef{}, ErrQuestNotReady
		}
	} else if s.Quests[i].Status == QuestActive {
		return QuestDef{}, ErrQuestNotReady
	}
	for _, it := range def.RewardItems {
		if !probe.AddItem(it.ID, it.Qty) {
			return QuestDef{}, ErrInventoryFull
		}
	}
	s.Inventory = probe.Inventory
	s.Quests[i].Status = QuestClaimed
	s.gainGold(def.RewardGold)
	if def.RewardGold > 0 {
		s.record(LedgerQuest, "Hadiah misi "+def.Title, def.RewardGold)
	}
	s.addRep(def.Giver, RepQuestBonus) // pemberi misi makin akrab (roadmap no. 59)
	s.checkAchievements()
	return def, nil
}

// RecordKill dicatat setiap pemain menang melawan musuh. Mengembalikan baris
// log untuk misi yang ikut maju.
func (s *State) RecordKill(enemyID string) []string {
	var log []string
	for i := range s.Quests {
		q := &s.Quests[i]
		def, ok := QuestByID(q.ID)
		if !ok || q.Status != QuestActive || !slices.Contains(def.TargetIDs, enemyID) {
			continue
		}
		q.Progress++
		if q.Progress >= def.Count {
			q.Progress = def.Count
			q.Status = QuestDone
			log = append(log, fmt.Sprintf("Misi \"%s\" selesai! Temui pemberi misi untuk mengambil hadiah.", def.Title))
		} else {
			log = append(log, fmt.Sprintf("Misi \"%s\": %d/%d.", def.Title, q.Progress, def.Count))
		}
	}
	return log
}

func validateQuests(qs []QuestProgress) error {
	if len(qs) > MaxQuests {
		return fmt.Errorf("catatan misi maksimal %d", MaxQuests)
	}
	seen := map[string]bool{}
	for _, q := range qs {
		if q.ID == "" || len(q.ID) > 64 || seen[q.ID] {
			return errors.New("id misi kosong, terlalu panjang, atau kembar")
		}
		seen[q.ID] = true
		if q.Status != QuestActive && q.Status != QuestDone && q.Status != QuestClaimed {
			return errors.New("status misi tidak dikenal")
		}
		if q.Progress < 0 || q.Progress > 100000 {
			return errors.New("kemajuan misi tidak masuk akal")
		}
	}
	return nil
}
