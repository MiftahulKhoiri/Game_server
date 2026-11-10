package game

import (
	"errors"
	"testing"
)

func TestTalkToRemembersAndCooldown(t *testing.T) {
	st := NewState()
	if err := st.TalkTo("naga", 100); !errors.Is(err, ErrUnknownWarga) {
		t.Fatalf("warga asing harus ditolak: %v", err)
	}
	_ = st.TalkTo("bu_sari", 1000)
	_ = st.TalkTo("bu_sari", 1100) // masih dalam jeda: diingat, poin tidak naik
	r := st.Reputation["bu_sari"]
	if r.Talks != 2 || r.Points != 1 {
		t.Fatalf("2 kali bicara, 1 poin: %+v", r)
	}
	_ = st.TalkTo("bu_sari", 1000+RepTalkCooldownSec)
	if st.Reputation["bu_sari"].Points != 2 {
		t.Fatalf("setelah jeda poin naik: %+v", st.Reputation["bu_sari"])
	}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestQuestClaimAddsGiverRep(t *testing.T) {
	st := NewState()
	def, _ := QuestByID("selamatkan_nenek")
	st.Quests = append(st.Quests, QuestProgress{ID: def.ID, Status: QuestDone, Progress: def.Count})
	if _, err := st.ClaimQuest(def.ID); err != nil {
		t.Fatal(err)
	}
	if st.Reputation[def.Giver].Points != RepQuestBonus {
		t.Fatalf("pemberi misi harus +%d: %+v", RepQuestBonus, st.Reputation)
	}
}

func TestBestFriendDiscount(t *testing.T) {
	st := NewState()
	st.Gold = 1000
	if err := BuyAt(&st, ShopGear, "pedang_besi", 1); err != nil {
		t.Fatal(err)
	}
	if st.Gold != 1000-120 || st.Reputation["penjaga_alat"].Points != 1 {
		t.Fatalf("harga penuh dan +1 keakraban: gold=%d rep=%+v", st.Gold, st.Reputation)
	}
	st.Reputation["penjaga_alat"] = Rep{Points: RepBestFriend}
	before := st.Gold
	if err := BuyAt(&st, ShopGear, "pedang_besi", 1); err != nil {
		t.Fatal(err)
	}
	if before-st.Gold != 120*(100-RepDiscountPercent)/100 {
		t.Fatalf("sahabat dapat potongan: bayar %d", before-st.Gold)
	}
	st.Reputation["siapa"] = Rep{Points: 1}
	if err := st.Validate(); err == nil {
		t.Error("keakraban dengan warga asing harus ditolak Validate")
	}
}
