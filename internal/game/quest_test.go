package game

import (
	"errors"
	"strings"
	"testing"
)

const nenekQuest = "selamatkan_nenek"

func TestQuestFlow(t *testing.T) {
	st := NewState()
	if v := st.QuestViews(); len(v) == 0 || v[0].Status != QuestAvailable {
		t.Fatalf("misi harus tersedia: %+v", v)
	}
	if _, err := st.ClaimQuest(nenekQuest); !errors.Is(err, ErrQuestNotReady) {
		t.Errorf("klaim sebelum terima: %v", err)
	}
	if err := st.AcceptQuest("tidak_ada"); !errors.Is(err, ErrUnknownQuest) {
		t.Errorf("misi asing: %v", err)
	}
	if err := st.AcceptQuest(nenekQuest); err != nil {
		t.Fatal(err)
	}
	if err := st.AcceptQuest(nenekQuest); !errors.Is(err, ErrQuestTaken) {
		t.Errorf("terima dua kali: %v", err)
	}

	if log := st.RecordKill("goblin"); len(log) != 0 {
		t.Errorf("musuh di luar target tidak boleh menghitung: %v", log)
	}
	def, _ := QuestByID(nenekQuest)
	for i := 1; i < def.Count; i++ {
		log := st.RecordKill("tikus_sawah")
		if len(log) != 1 || !strings.Contains(log[0], "/") {
			t.Fatalf("kemajuan %d: %v", i, log)
		}
	}
	if _, err := st.ClaimQuest(nenekQuest); !errors.Is(err, ErrQuestNotReady) {
		t.Errorf("klaim saat belum selesai: %v", err)
	}
	if log := st.RecordKill("belalang_raksasa"); len(log) != 1 || !strings.Contains(log[0], "selesai") {
		t.Fatalf("harus selesai: %v", log)
	}
	if v := st.QuestViews()[0]; v.Status != QuestDone || v.Progress != def.Count {
		t.Errorf("tampilan: %+v", v)
	}
	if log := st.RecordKill("tikus_sawah"); len(log) != 0 {
		t.Errorf("misi selesai tidak menghitung lagi: %v", log)
	}

	gold := st.Gold
	if _, err := st.ClaimQuest(nenekQuest); err != nil {
		t.Fatal(err)
	}
	if st.Gold != gold+def.RewardGold {
		t.Errorf("emas %d, mau %d", st.Gold, gold+def.RewardGold)
	}
	if _, err := st.ClaimQuest(nenekQuest); !errors.Is(err, ErrQuestClaimed) {
		t.Errorf("klaim dua kali: %v", err)
	}
	if st.Gold != gold+def.RewardGold {
		t.Error("klaim kedua tidak boleh menambah emas")
	}
	if err := st.Validate(); err != nil {
		t.Errorf("state tidak valid: %v", err)
	}
}

func TestWinCountsTowardQuest(t *testing.T) {
	p := newPlayer()
	if err := p.State.AcceptQuest(nenekQuest); err != nil {
		t.Fatal(err)
	}
	b := battleVs("tikus_sawah", 1)
	res, err := b.Act(p, ActionAttack, seq(20, 99, 99))
	if err != nil || res.Status != StatusWon {
		t.Fatalf("harus menang: %v %+v", err, res)
	}
	if p.State.Quests[0].Progress != 1 {
		t.Errorf("kemenangan harus dihitung: %+v", p.State.Quests)
	}
	if !strings.Contains(strings.Join(res.Log, "|"), "Selamatkan Nenek") {
		t.Errorf("log harus menyebut misi: %v", res.Log)
	}
}

func TestFleeAndLossDoNotCount(t *testing.T) {
	p := newPlayer()
	_ = p.State.AcceptQuest(nenekQuest)
	p.State.HP = 1
	b := battleVs("babi_hutan", 34)
	_, _ = b.Act(p, ActionAttack, seq(20, 99, 20))
	if p.State.Quests[0].Progress != 0 {
		t.Errorf("kalah tidak boleh menambah kemajuan: %+v", p.State.Quests)
	}
}

func TestQuestValidate(t *testing.T) {
	bad := []State{NewState(), NewState(), NewState()}
	bad[0].Quests = []QuestProgress{{ID: "a", Status: "ngawur"}}
	bad[1].Quests = []QuestProgress{{ID: "a", Status: QuestActive}, {ID: "a", Status: QuestActive}}
	bad[2].Quests = []QuestProgress{{ID: "a", Status: QuestActive, Progress: -1}}
	for i, s := range bad {
		if s.Validate() == nil {
			t.Errorf("kasus %d harus ditolak", i)
		}
	}
}

func TestQuestCatalogConsistent(t *testing.T) {
	for _, q := range Quests() {
		if q.ID == "" || q.Giver == "" || q.Count < 1 || q.RewardGold < 0 || len(q.TargetIDs) == 0 {
			t.Errorf("misi tidak valid: %+v", q)
		}
		for _, id := range q.TargetIDs {
			if _, ok := EnemyByID(id); !ok {
				t.Errorf("misi %s menarget musuh yang tidak ada: %s", q.ID, id)
			}
		}
	}
}
