package game

import (
	"errors"
	"fmt"
	"slices"
)

// Status sebuah misi pada pemain. Misi yang belum diterima tidak ada di State.
const (
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
}

var quests = []QuestDef{
	{
		ID:          "selamatkan_nenek",
		Title:       "Selamatkan Nenek",
		Giver:       "nenek_penjual",
		Description: "Binatang-binatang kecil mengerumuni nenek dan merusak sayurannya. Usir 5 tikus sawah atau belalang raksasa.",
		TargetIDs:   []string{"tikus_sawah", "belalang_raksasa"},
		Count:       5,
		RewardGold:  40,
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
	Status   string `json:"status"`
	Progress int    `json:"progress"`
}

// Kesalahan misi.
var (
	ErrUnknownQuest  = errors.New("misi tidak dikenal")
	ErrQuestTaken    = errors.New("misi ini sudah diterima")
	ErrQuestNotReady = errors.New("misi belum selesai")
	ErrQuestClaimed  = errors.New("hadiah misi sudah diambil")
	ErrTooManyQuests = errors.New("catatan misi terlalu banyak")
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
		v := QuestView{QuestDef: def, Status: QuestAvailable}
		if i := s.questIndex(def.ID); i >= 0 {
			v.Status, v.Progress = s.Quests[i].Status, s.Quests[i].Progress
		}
		out = append(out, v)
	}
	return out
}

// AcceptQuest menerima misi.
func (s *State) AcceptQuest(id string) error {
	if _, ok := QuestByID(id); !ok {
		return ErrUnknownQuest
	}
	if s.questIndex(id) >= 0 {
		return ErrQuestTaken
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
	case i < 0 || s.Quests[i].Status == QuestActive:
		return QuestDef{}, ErrQuestNotReady
	case s.Quests[i].Status == QuestClaimed:
		return QuestDef{}, ErrQuestClaimed
	}
	s.Quests[i].Status = QuestClaimed
	s.Gold += def.RewardGold
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
