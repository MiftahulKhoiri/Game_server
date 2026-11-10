package game

import (
	"errors"
	"strings"
	"testing"
)

// Misi dasar untuk uji: Kebun yang Dirusak (3 babi hutan), terbuka setelah langkah cerita pertama.
const nenekQuest = "kebun_babi"

// storyState: pemain baru yang sudah bicara dengan Kepala Desa (misi sampingan pertama terbuka).
func storyState() State {
	st := NewState()
	st.Story = 1
	return st
}

func TestQuestFlow(t *testing.T) {
	st := storyState()
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
		log := st.RecordKill("babi_hutan")
		if len(log) != 1 || !strings.Contains(log[0], "/") {
			t.Fatalf("kemajuan %d: %v", i, log)
		}
	}
	if _, err := st.ClaimQuest(nenekQuest); !errors.Is(err, ErrQuestNotReady) {
		t.Errorf("klaim saat belum selesai: %v", err)
	}
	if log := st.RecordKill("babi_hutan"); len(log) != 1 || !strings.Contains(log[0], "selesai") {
		t.Fatalf("harus selesai: %v", log)
	}
	if v := st.QuestViews()[0]; v.Status != QuestDone || v.Progress != def.Count {
		t.Errorf("tampilan: %+v", v)
	}
	if log := st.RecordKill("babi_hutan"); len(log) != 0 {
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
	p.State.Story = 1
	if err := p.State.AcceptQuest(nenekQuest); err != nil {
		t.Fatal(err)
	}
	b := battleVs("babi_hutan", 1)
	res, err := act(b, p, ActionAttack, seq(20, 99, 99, 99))
	if err != nil || res.Status != StatusWon {
		t.Fatalf("harus menang: %v %+v", err, res)
	}
	if p.State.Quests[0].Progress != 1 {
		t.Errorf("kemenangan harus dihitung: %+v", p.State.Quests)
	}
	if !strings.Contains(strings.Join(res.Log, "|"), "Kebun yang Dirusak") {
		t.Errorf("log harus menyebut misi: %v", res.Log)
	}
}

func TestFleeAndLossDoNotCount(t *testing.T) {
	p := newPlayer()
	p.State.Story = 1
	_ = p.State.AcceptQuest(nenekQuest)
	p.State.HP = 1
	b := battleVs("babi_hutan", 34)
	_, _ = act(b, p, ActionAttack, seq(20, 99, 20, 99))
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
		if q.ID == "" || q.Giver == "" || q.Count < 1 || q.RewardGold < 0 {
			t.Errorf("misi tidak valid: %+v", q)
		}
		// Tiap misi punya target musuh ATAU barang yang diantar, tidak keduanya.
		if (len(q.TargetIDs) == 0) == (q.CollectID == "") {
			t.Errorf("misi %s harus punya TargetIDs atau CollectID (salah satu)", q.ID)
		}
		if q.CollectID != "" {
			if _, ok := ItemByID(q.CollectID); !ok {
				t.Errorf("misi %s meminta barang yang tidak ada: %s", q.ID, q.CollectID)
			}
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

func TestClaimWithFullInventoryChangesNothing(t *testing.T) {
	st := storyState()
	_ = st.AcceptQuest(nenekQuest)
	for i := 0; i < 3; i++ {
		st.RecordKill("babi_hutan")
	}
	st.Inventory = nil
	for i := 0; i < MaxInventory; i++ {
		st.Inventory = append(st.Inventory, Item{ID: "x" + string(rune('a'+i%26)) + string(rune('a'+i/26)), Qty: 1})
	}
	gold := st.Gold
	if _, err := st.ClaimQuest(nenekQuest); !errors.Is(err, ErrInventoryFull) {
		t.Fatalf("mau ErrInventoryFull, dapat %v", err)
	}
	i := st.questIndex(nenekQuest)
	if st.Gold != gold || st.Quests[i].Status != QuestDone || len(st.Inventory) != MaxInventory {
		t.Errorf("tidak boleh ada yang berubah: gold=%d status=%s inv=%d", st.Gold, st.Quests[i].Status, len(st.Inventory))
	}
}

func TestOldMainQuestsAreGone(t *testing.T) {
	for _, id := range []string{"selamatkan_nenek", "selamatkan_petani", "usir_ogre", "hentikan_raja_goblin"} {
		if _, ok := QuestByID(id); ok {
			t.Errorf("misi utama lama %s harus diganti cerita The Last Dragon", id)
		}
	}
	// Data lama yang masih menyimpan misi itu tetap sah dan tidak berpengaruh.
	st := NewState()
	st.Quests = []QuestProgress{{ID: "selamatkan_nenek", Status: QuestClaimed}, {ID: "usir_ogre", Status: QuestActive}}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
	if log := st.RecordKill("ogre_batu"); len(log) != 0 {
		t.Errorf("misi lama tidak boleh maju: %v", log)
	}
}

// finishQuest menamatkan satu misi sampingan (cerita harus sudah cukup jauh).
func finishQuest(t *testing.T, st *State, id string) {
	t.Helper()
	def, _ := QuestByID(id)
	if err := st.AcceptQuest(id); err != nil {
		t.Fatalf("terima %s: %v", id, err)
	}
	if def.CollectID != "" {
		if !st.AddItem(def.CollectID, def.Count) {
			t.Fatal("tas penuh")
		}
	} else {
		for i := 0; i < def.Count; i++ {
			st.RecordKill(def.TargetIDs[0])
		}
	}
	if _, err := st.ClaimQuest(id); err != nil {
		t.Fatalf("klaim %s: %v", id, err)
	}
}

func TestCollectQuestNeedsItemsAndConsumesThem(t *testing.T) {
	st := NewState()
	st.Story = 3
	if err := st.AcceptQuest("ramuan_nenek"); err != nil {
		t.Fatal(err)
	}
	if _, err := st.ClaimQuest("ramuan_nenek"); !errors.Is(err, ErrQuestNotReady) {
		t.Fatalf("klaim tanpa barang: %v", err)
	}
	st.AddItem("taring_goblin", 2)
	view := func() QuestView {
		for _, v := range st.QuestViews() {
			if v.ID == "ramuan_nenek" {
				return v
			}
		}
		t.Fatal("misi tidak ada di tampilan")
		return QuestView{}
	}
	if v := view(); v.Status != QuestActive || v.Progress != 2 {
		t.Errorf("baru 2 dari 3: %+v", v)
	}
	if _, err := st.ClaimQuest("ramuan_nenek"); !errors.Is(err, ErrQuestNotReady) {
		t.Fatalf("klaim dengan barang kurang: %v", err)
	}
	if st.itemQty("taring_goblin") != 2 {
		t.Error("klaim gagal tidak boleh mengambil barang")
	}
	st.AddItem("taring_goblin", 2) // sekarang 4, lebih dari cukup
	if v := view(); v.Status != QuestDone || v.Progress != 3 {
		t.Errorf("harus siap diklaim: %+v", v)
	}
	potions, gold := st.itemQty(PotionID), st.Gold
	if _, err := st.ClaimQuest("ramuan_nenek"); err != nil {
		t.Fatal(err)
	}
	if st.itemQty("taring_goblin") != 1 {
		t.Errorf("harus tersisa 1 taring, ada %d", st.itemQty("taring_goblin"))
	}
	if st.itemQty(PotionID) != potions+3 || st.Gold != gold+30 {
		t.Errorf("hadiah salah: ramuan %d, emas %d", st.itemQty(PotionID), st.Gold)
	}
	if _, err := st.ClaimQuest("ramuan_nenek"); !errors.Is(err, ErrQuestClaimed) {
		t.Errorf("klaim dua kali: %v", err)
	}
}

func TestSideQuestsFollowStory(t *testing.T) {
	st := NewState()
	locked := func(id string) bool {
		for _, v := range st.QuestViews() {
			if v.ID == id {
				return v.Status == QuestLocked
			}
		}
		t.Fatalf("misi %s tidak ada", id)
		return false
	}
	for _, id := range []string{"kebun_babi", "ramuan_nenek", "serigala_perbatasan", "sisa_pasukan", "permata_nenek"} {
		if !locked(id) {
			t.Errorf("%s harus terkunci sebelum bicara dengan Kepala Desa", id)
		}
	}
	if err := st.AcceptQuest("kebun_babi"); !errors.Is(err, ErrQuestLocked) {
		t.Errorf("terima saat terkunci: %v", err)
	}
	st.Story = 1
	if locked("kebun_babi") || locked("serigala_perbatasan") || !locked("ramuan_nenek") {
		t.Error("setelah prolog: kebun_babi dan serigala terbuka, ramuan_nenek belum")
	}
	finishQuest(t, &st, "kebun_babi")
	st.Story = 6
	if !locked("sisa_pasukan") || !locked("permata_nenek") {
		t.Error("misi Benteng Orc harus terkunci sampai Panglima Orc Batu dikalahkan")
	}
	st.Story = 7
	if locked("sisa_pasukan") || locked("permata_nenek") {
		t.Error("misi Benteng Orc harus terbuka setelah Panglima")
	}
	st.AddItem("permata_merah", 5)
	finishQuest(t, &st, "sisa_pasukan")
	finishQuest(t, &st, "permata_nenek")
	if st.itemQty("zirah_besi") != 1 || st.itemQty("pedang_baja") != 1 {
		t.Errorf("hadiah peralatan kurang: %+v", st.Inventory)
	}
}
