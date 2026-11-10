package game

import (
	"errors"
	"strings"
	"testing"
)

func place(st *State, mapID string, x, y int) { st.Map, st.X, st.Y = mapID, x, y }

func TestStoryCatalogConsistent(t *testing.T) {
	if len(Story) != StoryEnd {
		t.Fatalf("StoryEnd %d harus sama dengan jumlah langkah %d", StoryEnd, len(Story))
	}
	seen := map[string]bool{}
	for i, st := range Story {
		if st.ID == "" || seen[st.ID] || st.Goal == "" || st.Chapter == "" || st.Done == "" {
			t.Errorf("langkah %d tidak lengkap/kembar: %+v", i, st)
		}
		seen[st.ID] = true
		switch st.Kind {
		case StoryTalk:
			if !ValidPosition(st.Map, st.X, st.Y) || st.NPC == "" || st.Near < 1 {
				t.Errorf("langkah %s: tempat bicara tidak sah", st.ID)
			}
		case StoryTrial:
			if _, ok := TrialFor(st.Trial); !ok {
				t.Errorf("langkah %s: peta ujian %s tidak ada", st.ID, st.Trial)
			}
		case StoryKill:
			if e, ok := EnemyByID(st.Enemy); !ok || !e.Boss {
				t.Errorf("langkah %s: bos %s tidak ada", st.ID, st.Enemy)
			}
		case StoryBrief:
		default:
			t.Errorf("langkah %s: jenis %q tidak dikenal", st.ID, st.Kind)
		}
		for _, it := range st.RewardItems {
			if _, ok := ItemByID(it.ID); !ok || it.Qty < 1 {
				t.Errorf("langkah %s: hadiah %+v tidak sah", st.ID, it)
			}
		}
	}
	// Urutan wilayah cerita tidak boleh berubah (docs/STORY.md, aturan 7).
	order := []string{MapDesaAwal, MapHutanLebat, MapGuaGoblin, MapGunungBatu, MapGuaBatu, MapIstana, MapTakhta}
	last := -1
	for _, st := range Story[:len(Story)-1] {
		m := st.Map
		if st.Kind == StoryTrial {
			m = st.Trial
		}
		if st.Kind == StoryKill {
			e, _ := EnemyByID(st.Enemy)
			m = e.Zones[0]
		}
		if m == "" {
			continue
		}
		i := -1
		for k, o := range order {
			if o == m {
				i = k
			}
		}
		if i < last {
			t.Errorf("langkah %s mundur ke %s", st.ID, m)
		}
		last = i
	}
}

func TestStoryPrologueTalkNeedsPositionAndGivesSupplies(t *testing.T) {
	st := NewState()
	if _, err := st.TalkStory(PenjagaHutan); !errors.Is(err, ErrStoryNotHere) {
		t.Errorf("NPC lain belum waktunya: %v", err)
	}
	place(&st, MapDesaAwal, 5, 5)
	if _, err := st.TalkStory(KepalaDesaID); !errors.Is(err, ErrStoryFar) {
		t.Errorf("jauh dari Kepala Desa: %v", err)
	}
	place(&st, MapDesaAwal, 40, 9)
	potions := st.itemQty(PotionID)
	log, err := st.TalkStory(KepalaDesaID)
	if err != nil || st.Story != 1 {
		t.Fatalf("prolog: %v story=%d", err, st.Story)
	}
	if st.itemQty(PotionID) != potions+3 || st.itemQty("roti") != 2 || !strings.Contains(strings.Join(log, "|"), "Elara") {
		t.Errorf("bekal/log salah: %+v %v", st.Inventory, log)
	}
	if _, err := st.TalkStory(KepalaDesaID); !errors.Is(err, ErrStoryNotHere) {
		t.Errorf("tidak bisa diulang: %v", err)
	}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestStoryFullRun(t *testing.T) {
	p := newPlayer()
	st := &p.State
	place(st, MapDesaAwal, 40, 7)
	if _, err := st.TalkStory(KepalaDesaID); err != nil {
		t.Fatal(err)
	}
	place(st, MapPerbatasan, KaptenX, KaptenY)
	if err := st.BriefHutan(); err != nil || st.Story != 2 {
		t.Fatalf("arahan Kapten harus memajukan cerita: %v story=%d", err, st.Story)
	}
	place(st, MapHutanLebat, 26, 5)
	if _, err := st.TalkStory(PenjagaHutan); err != nil || st.Story != 3 {
		t.Fatalf("penjaga hutan: %v %d", err, st.Story)
	}
	// Ujian tiga wilayah tuntas: cerita maju sendiri sampai Benteng Orc.
	st.Hutan.Wave = HutanWaves
	st.Trials = map[string]HutanProgress{MapGuaGoblin: {Wave: HutanWaves}, MapGunungBatu: {Wave: HutanWaves}}
	st.advanceStory()
	if st.Story != 6 || st.itemQty(LambangID) != 1 {
		t.Fatalf("harus sampai langkah Panglima dengan Lambang Malzareth: story=%d lambang=%d", st.Story, st.itemQty(LambangID))
	}
	// Bos cerita Bab 4 belum boleh dilawan.
	place(st, MapIstana, 15, 14)
	if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrStoryBoss) {
		t.Errorf("Aldragor terlalu dini: %v", err)
	}
	st.storyKill(PanglimaID)
	if st.Story != 7 {
		t.Fatalf("Panglima: %d", st.Story)
	}
	place(st, MapGuaBatu, 9, 12)
	if _, err := st.TalkStory(BatuSihirID); err != nil {
		t.Fatal(err)
	}
	place(st, MapGuaBatu, 5, 13)
	if _, err := st.TalkStory(OrcTuaID); err != nil || st.Story != StoryGates {
		t.Fatalf("orc tua: %v %d", err, st.Story)
	}
	place(st, MapIstana, 15, 14)
	b, err := StartBossBattle(p, 0)
	if err != nil || b.EnemyID != AldragorID {
		t.Fatalf("Aldragor: %+v %v", b, err)
	}
	st.storyKill(AldragorID)
	place(st, MapIstana, 15, 14)
	if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrStoryFreed) {
		t.Errorf("Aldragor tidak dilawan lagi setelah kalah: %v", err)
	}
	place(st, MapTakhta, 10, 13)
	if b, err := StartBossBattle(p, 0); err != nil || b.EnemyID != MalzarethID {
		t.Fatalf("Malzareth: %+v %v", b, err)
	}
	st.storyKill(MalzarethID)
	place(st, MapDesaAwal, 41, 8)
	gold := st.Gold
	if _, err := st.TalkStory(KepalaDesaID); err != nil || st.Story != StoryEnd {
		t.Fatalf("epilog: %v %d", err, st.Story)
	}
	if st.itemQty("pedang_rune") != 1 || st.Gold <= gold || !st.achieved("legenda") {
		t.Errorf("hadiah tamat kurang: rune=%d gold %d->%d", st.itemQty("pedang_rune"), gold, st.Gold)
	}
	if v := st.StoryProgress(); !v.Done || v.Cur != nil {
		t.Errorf("tampilan tamat: %+v", v)
	}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestStoryKillCountsOnlyCurrentBoss(t *testing.T) {
	st := NewState()
	st.Story = 6
	if log := st.storyKill(AldragorID); len(log) != 0 || st.Story != 6 {
		t.Errorf("bos lain tidak memajukan cerita: %v", log)
	}
	// Panglima Orc Batu tetap bisa dilawan lagi (untuk hadiah) setelah langkahnya lewat.
	st.Story = 9
	if err := st.storyBossAllowed(PanglimaID); err != nil {
		t.Error(err)
	}
}

func TestStoryWinAdvancesThroughBattle(t *testing.T) {
	p := newPlayer()
	p.State.Story = 6
	b := battleVs(PanglimaID, 1)
	res, err := act(b, p, ActionAttack, seq(20, 99, 99, 99))
	if err != nil || res.Status != StatusWon || p.State.Story != 7 {
		t.Fatalf("menang lawan Panglima harus memajukan cerita: %v %+v story=%d", err, res, p.State.Story)
	}
	if !strings.Contains(strings.Join(res.Log, "|"), "Batu Sihir") {
		t.Errorf("log cerita: %v", res.Log)
	}
}

func TestMalzarethThreePhases(t *testing.T) {
	e := mustEnemy(MalzarethID)
	b := newBattle(e, 0)
	var res Result
	b.Round = 3
	if sp, name := b.malzarethPhase(e, &res); sp != SpecialGempa || name == "" || b.Phase != 1 {
		t.Errorf("fase 1: %s %s %d", sp, name, b.Phase)
	}
	b.EnemyHP = e.HP / 2
	b.Round = 4
	if sp, _ := b.malzarethPhase(e, &res); sp != SpecialTerkam || b.Phase != 2 {
		t.Errorf("fase 2: %s %d", sp, b.Phase)
	}
	b.EnemyHP = e.HP / 5
	if sp, name := b.malzarethPhase(e, &res); sp != SpecialKutukan || name != "Kutukan Terakhir" || b.Phase != 3 {
		t.Errorf("fase 3: %s %d", sp, b.Phase)
	}
	if len(res.Log) != 2 {
		t.Errorf("pergantian fase harus dicatat: %v", res.Log)
	}
}

func TestStoryValidate(t *testing.T) {
	st := NewState()
	st.Story = StoryEnd + 1
	if st.Validate() == nil {
		t.Error("langkah cerita di luar batas harus ditolak")
	}
}
