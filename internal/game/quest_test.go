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
		if q.Requires != "" {
			if _, ok := QuestByID(q.Requires); !ok || q.Requires == q.ID {
				t.Errorf("misi %s punya prasyarat tidak valid: %s", q.ID, q.Requires)
			}
		}
		for _, it := range q.RewardItems {
			if _, ok := ItemByID(it.ID); !ok || it.Qty < 1 {
				t.Errorf("misi %s: hadiah barang tidak valid %+v", q.ID, it)
			}
		}
		for _, id := range q.TargetIDs {
			if _, ok := EnemyByID(id); !ok {
				t.Errorf("misi %s menarget musuh yang tidak ada: %s", q.ID, id)
			}
		}
	}
}

const petaniQuest = "selamatkan_petani"

func claimNenek(t *testing.T, st *State) {
	t.Helper()
	if err := st.AcceptQuest(nenekQuest); err != nil {
		t.Fatal(err)
	}
	def, _ := QuestByID(nenekQuest)
	for i := 0; i < def.Count; i++ {
		st.RecordKill("tikus_sawah")
	}
	if _, err := st.ClaimQuest(nenekQuest); err != nil {
		t.Fatal(err)
	}
}

func TestSecondQuestIsLockedUntilFirstClaimed(t *testing.T) {
	st := NewState()
	if v := st.QuestViews()[1]; v.ID != petaniQuest || v.Status != QuestLocked {
		t.Fatalf("misi petani harus terkunci: %+v", v)
	}
	if err := st.AcceptQuest(petaniQuest); !errors.Is(err, ErrQuestLocked) {
		t.Errorf("terima saat terkunci: %v", err)
	}
	// Selesai tapi hadiah belum diambil: masih terkunci.
	_ = st.AcceptQuest(nenekQuest)
	for i := 0; i < 5; i++ {
		st.RecordKill("belalang_raksasa")
	}
	if err := st.AcceptQuest(petaniQuest); !errors.Is(err, ErrQuestLocked) {
		t.Errorf("hadiah belum diambil, harus terkunci: %v", err)
	}
	if _, err := st.ClaimQuest(nenekQuest); err != nil {
		t.Fatal(err)
	}
	if v := st.QuestViews()[1]; v.Status != QuestAvailable {
		t.Errorf("harus tersedia: %+v", v)
	}
	if err := st.AcceptQuest(petaniQuest); err != nil {
		t.Fatal(err)
	}
}

func TestPetaniQuestRewardsItem(t *testing.T) {
	st := NewState()
	claimNenek(t, &st)
	_ = st.AcceptQuest(petaniQuest)
	if log := st.RecordKill("tikus_sawah"); len(log) != 0 {
		t.Errorf("hanya goblin yang dihitung: %v", log)
	}
	for i := 0; i < 3; i++ {
		st.RecordKill("goblin")
	}
	gold := st.Gold
	def, err := st.ClaimQuest(petaniQuest)
	if err != nil {
		t.Fatal(err)
	}
	if st.Gold != gold+25 || qtyOf(st, "permata_merah") != 1 {
		t.Errorf("emas %d (dari %d), permata %d", st.Gold, gold, qtyOf(st, "permata_merah"))
	}
	if got := def.RewardText(); got != "25 emas, Permata Merah x1" {
		t.Errorf("teks hadiah: %q", got)
	}
}

func TestClaimWithFullInventoryChangesNothing(t *testing.T) {
	st := NewState()
	claimNenek(t, &st)
	_ = st.AcceptQuest(petaniQuest)
	for i := 0; i < 3; i++ {
		st.RecordKill("goblin")
	}
	st.Inventory = nil
	for i := 0; i < MaxInventory; i++ {
		st.Inventory = append(st.Inventory, Item{ID: "x" + string(rune('a'+i%26)) + string(rune('a'+i/26)), Qty: 1})
	}
	gold := st.Gold
	if _, err := st.ClaimQuest(petaniQuest); !errors.Is(err, ErrInventoryFull) {
		t.Fatalf("mau ErrInventoryFull, dapat %v", err)
	}
	i := st.questIndex(petaniQuest)
	if st.Gold != gold || st.Quests[i].Status != QuestDone || len(st.Inventory) != MaxInventory {
		t.Errorf("tidak boleh ada yang berubah: gold=%d status=%s inv=%d", st.Gold, st.Quests[i].Status, len(st.Inventory))
	}
}

func TestOgreQuestChain(t *testing.T) {
	st := NewState()
	claimNenek(t, &st)
	if v := st.QuestViews()[2]; v.ID != "usir_ogre" || v.Status != QuestLocked {
		t.Fatalf("misi ogre harus terkunci sebelum petani selesai: %+v", v)
	}
	_ = st.AcceptQuest(petaniQuest)
	for i := 0; i < 3; i++ {
		st.RecordKill("goblin")
	}
	if _, err := st.ClaimQuest(petaniQuest); err != nil {
		t.Fatal(err)
	}
	if err := st.AcceptQuest("usir_ogre"); err != nil {
		t.Fatal(err)
	}
	if log := st.RecordKill("goblin"); len(log) != 0 {
		t.Errorf("hanya ogre yang dihitung: %v", log)
	}
	st.RecordKill("ogre_batu")
	gold := st.Gold
	def, err := st.ClaimQuest("usir_ogre")
	if err != nil || st.Gold != gold+150 || qtyOf(st, "koin_kuno") != 2 {
		t.Errorf("hadiah salah: err=%v gold=%d->%d koin=%d (%s)", err, gold, st.Gold, qtyOf(st, "koin_kuno"), def.RewardText())
	}
}

func TestRajaGoblinQuestEndsChain(t *testing.T) {
	st := NewState()
	claimNenek(t, &st)
	_ = st.AcceptQuest(petaniQuest)
	for i := 0; i < 3; i++ {
		st.RecordKill("goblin")
	}
	_, _ = st.ClaimQuest(petaniQuest)
	_ = st.AcceptQuest("usir_ogre")
	st.RecordKill("ogre_batu")
	_, _ = st.ClaimQuest("usir_ogre")
	if v := st.QuestViews()[3]; v.ID != "hentikan_raja_goblin" || v.Status != QuestAvailable {
		t.Fatalf("misi terakhir harus tersedia: %+v", v)
	}
	if err := st.AcceptQuest("hentikan_raja_goblin"); err != nil {
		t.Fatal(err)
	}
	st.RecordKill("goblin_penjaga")
	st.RecordKill("raja_goblin")
	gold, gems := st.Gold, qtyOf(st, "permata_merah")
	if _, err := st.ClaimQuest("hentikan_raja_goblin"); err != nil || st.Gold != gold+500 || qtyOf(st, "permata_merah") != gems+3 {
		t.Errorf("hadiah salah: %v gold %d->%d permata %d->%d", err, gold, st.Gold, gems, qtyOf(st, "permata_merah"))
	}
}
