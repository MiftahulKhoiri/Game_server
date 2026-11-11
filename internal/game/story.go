package game

import (
	"errors"
	"fmt"
)

// Cerita utama "The Last Dragon" (docs/STORY.md). Kemajuan pemain disimpan di State.Story: nomor langkah cerita
// yang sedang dijalani (0 = baru mulai, StoryEnd = tamat). Server yang memeriksa dan memajukan setiap langkah;
// klien hanya menampilkan tujuan, dialog, dan narasinya (client/scripts/story.gd).
//
// Jenis langkah:
//   - talk : bicara dengan NPC tertentu (posisi tersimpan pemain harus dekat NPC itu), lewat POST /v1/story/talk.
//     Dipakai juga untuk benda cerita (Batu Sihir) yang "dihancurkan" dengan tombol di dunia.
//   - brief: sudah diberi arahan Kapten Rimba (State.Hutan.Started).
//   - trial: ujian wilayah di peta itu tuntas (ketiga bos kalah, lihat hutan.go).
//   - kill : mengalahkan musuh tertentu (bos cerita).

// Jenis langkah cerita.
const (
	StoryTalk  = "talk"
	StoryBrief = "brief"
	StoryTrial = "trial"
	StoryKill  = "kill"
)

// Id NPC, benda, dan bos cerita (sama dengan client/scripts/maps.gd dan enemy.go).
const (
	KepalaDesaID  = "kepala_suku"
	PenjagaHutan  = "penjaga_hutan"
	OrcTuaID      = "orc_tua"
	BatuSihirID   = "batu_sihir"
	PanglimaID    = "raja_goblin" // id lama "Raja Iblis" di Gua Batu, kini Panglima Orc Batu
	AldragorID    = "aldragor"
	MalzarethID   = "malzareth"
	LambangID     = "lambang_malzareth"
	StoryTalkSlop = 9 // jarak terjauh (petak) dari NPC cerita agar pembicaraan sah (NPC berjalan-jalan)
)

// Peta baru Bab 4.
const (
	MapIstana  = "istana_kegelapan" // halaman Istana Kegelapan, tempat Aldragor berjaga
	MapTakhta  = "ruang_takhta"     // ruang takhta Malzareth
	StoryEnd   = 12                 // langkah setelah langkah terakhir = cerita tamat
	StoryGates = 9                  // Istana Kegelapan terbuka mulai langkah ini (setelah bicara dengan Orc Tua)
)

// StoryStep adalah satu langkah cerita utama.
type StoryStep struct {
	ID      string `json:"id"`
	Chapter string `json:"chapter"` // nama bab untuk ditampilkan
	Goal    string `json:"goal"`    // tujuan yang ditampilkan di layar
	Kind    string `json:"kind"`
	// talk: NPC/benda yang harus didatangi dan tempatnya.
	NPC  string `json:"npc,omitempty"`
	Map  string `json:"map,omitempty"`
	X    int    `json:"x,omitempty"`
	Y    int    `json:"y,omitempty"`
	Near int    `json:"near,omitempty"`
	// trial: peta ujian yang harus tuntas. kill: id musuh yang harus dikalahkan.
	Trial string `json:"trial,omitempty"`
	Enemy string `json:"enemy,omitempty"`
	// Hadiah saat langkah ini selesai.
	RewardGold  int    `json:"reward_gold,omitempty"`
	RewardItems []Item `json:"reward_items,omitempty"`
	// Done: kalimat log saat langkah selesai (narasi lengkap ada di klien).
	Done string `json:"done"`
}

// Story adalah seluruh langkah cerita utama, berurutan (indeks = State.Story).
var Story = []StoryStep{
	// Prolog — Serangan di Desa Awal
	{ID: "prolog_kepala", Chapter: "Prolog: Serangan di Desa Awal", Goal: "Bicara dengan Kepala Desa di utara desa",
		Kind: StoryTalk, NPC: KepalaDesaID, Map: MapDesaAwal, X: 40, Y: 7, Near: StoryTalkSlop,
		RewardItems: []Item{{ID: PotionID, Qty: 3}, {ID: "roti", Qty: 2}},
		Done:        "Kepala Desa memintamu mencari Elara. Bekal perjalanan masuk ke ransel."},
	{ID: "prolog_kapten", Chapter: "Prolog: Serangan di Desa Awal", Goal: "Keluar lewat gerbang selatan dan temui Kapten Rimba di kem Perbatasan",
		Kind: StoryBrief, Done: "Kapten Rimba menunjukkan jejak para penyerbu: semuanya menuju Hutan Binatang."},
	// Bab 1 — Hutan Binatang
	{ID: "hutan_penjaga", Chapter: "Bab 1: Hutan Binatang", Goal: "Masuki Hutan Binatang dan temukan Penjaga Hutan yang terluka",
		Kind: StoryTalk, NPC: PenjagaHutan, Map: MapHutanLebat, X: 26, Y: 4, Near: 5,
		RewardItems: []Item{{ID: PotionID, Qty: 2}},
		Done:        "Penjaga Hutan melihat pasukan Goblin membawa seorang gadis ke gua di balik hutan."},
	{ID: "hutan_goblin", Chapter: "Bab 1: Hutan Binatang", Goal: "Hadapi binatang terkutuk dan kalahkan tiga Goblin di Hutan Binatang",
		Kind: StoryTrial, Trial: MapHutanLebat, RewardGold: 150,
		Done: "Jejak pasukan Goblin mengarah ke Gua Goblin. Elara dibawa ke sana!"},
	// Bab 2 — Gua Goblin
	{ID: "gua_raja", Chapter: "Bab 2: Gua Goblin", Goal: "Masuki Gua Goblin dan kalahkan Raja Orc Batu yang menguasainya",
		Kind: StoryTrial, Trial: MapGuaGoblin, RewardGold: 250, RewardItems: []Item{{ID: LambangID, Qty: 1}},
		Done: "Kamu menemukan Lambang Malzareth: para Goblin dan Orc Batu hanya diperintah penyihir itu. Sumber kekuatannya ada di gunung berapi."},
	// Bab 3 — Gunung Berapi dan Orc Batu
	{ID: "gunung_orc", Chapter: "Bab 3: Gunung Berapi", Goal: "Lewati lereng Gunung Berapi dan kalahkan tiga Naga Lava",
		Kind: StoryTrial, Trial: MapGunungBatu, RewardGold: 350,
		Done: "Jalan ke Benteng Orc di perut gunung terbuka."},
	{ID: "benteng_panglima", Chapter: "Bab 3: Gunung Berapi", Goal: "Masuki Benteng Orc dan kalahkan Panglima Orc Batu di singgasananya",
		Kind: StoryKill, Enemy: PanglimaID, RewardGold: 400,
		Done: "Panglima Orc Batu tumbang. Di balik singgasananya berdenyut Batu Sihir penguat kutukan."},
	{ID: "benteng_batu", Chapter: "Bab 3: Gunung Berapi", Goal: "Hancurkan Batu Sihir penguat kutukan di Benteng Orc",
		Kind: StoryTalk, NPC: BatuSihirID, Map: MapGuaBatu, X: 9, Y: 12, Near: 2,
		Done: "Batu Sihir hancur! Kutukan di gunung melemah, tetapi belum hilang selama Malzareth hidup."},
	{ID: "benteng_orctua", Chapter: "Bab 3: Gunung Berapi", Goal: "Bicara dengan Orc Tua yang mulai sadar",
		Kind: StoryTalk, NPC: OrcTuaID, Map: MapGuaBatu, X: 5, Y: 12, Near: 4,
		RewardItems: []Item{{ID: PotionID, Qty: 3}},
		Done:        "Orc Tua menunjukkan lorong rahasia di selatan benteng: jalan menuju Istana Kegelapan."},
	// Bab 4 — Istana Kegelapan
	{ID: "istana_naga", Chapter: "Bab 4: Istana Kegelapan", Goal: "Masuki halaman Istana Kegelapan dan kalahkan Aldragor tanpa membunuhnya",
		Kind: StoryKill, Enemy: AldragorID, RewardGold: 600,
		Done: "Aldragor jatuh dan berhenti menyerang. Gerbang ruang takhta terbuka."},
	{ID: "istana_malzareth", Chapter: "Bab 4: Istana Kegelapan", Goal: "Masuki ruang takhta, bebaskan Elara, dan kalahkan Malzareth",
		Kind: StoryKill, Enemy: MalzarethID, RewardGold: 1000,
		Done: "Malzareth kalah! Kutukan terputus dan Elara bebas. Bawa dia pulang ke Desa Awal."},
	// Epilog — Dunia Kembali Damai
	{ID: "epilog", Chapter: "Epilog: Dunia Kembali Damai", Goal: "Bawa Elara pulang dan temui Kepala Desa",
		Kind: StoryTalk, NPC: KepalaDesaID, Map: MapDesaAwal, X: 40, Y: 7, Near: StoryTalkSlop,
		RewardGold: 1500, RewardItems: []Item{{ID: "pedang_rune", Qty: 1}, {ID: "permata_merah", Qty: 3}},
		Done: "Elara kembali ke pelukan ayahnya. Kutukan telah berakhir. TAMAT."},
}

// Kesalahan cerita.
var (
	ErrStoryNotHere = errors.New("belum saatnya: ikuti tujuan cerita yang sedang berjalan")
	ErrStoryFar     = errors.New("terlalu jauh: dekati dulu")
	ErrStoryBoss    = errors.New("belum saatnya melawan dia: ikuti tujuan cerita")
	ErrStoryFreed   = errors.New("kutukan sudah patah: dia tidak lagi menjadi musuh")
)

// StoryView adalah kemajuan cerita untuk klien.
type StoryView struct {
	Step  int        `json:"step"`
	Total int        `json:"total"`
	Done  bool       `json:"done"`
	Cur   *StoryStep `json:"current,omitempty"`
}

// StoryNow mengembalikan langkah cerita yang sedang dijalani pemain (false bila sudah tamat).
func (s State) StoryNow() (StoryStep, bool) {
	if s.Story < 0 || s.Story >= len(Story) {
		return StoryStep{}, false
	}
	return Story[s.Story], true
}

// StoryView merangkum kemajuan cerita.
func (s State) StoryProgress() StoryView {
	v := StoryView{Step: s.Story, Total: len(Story), Done: s.Story >= StoryEnd}
	if st, ok := s.StoryNow(); ok {
		v.Cur = &st
	}
	return v
}

// completeStory memberi hadiah langkah sekarang dan maju satu langkah. Hadiah barang yang tidak muat di
// ransel dilewati (langkah tetap selesai) kecuali `strict`: maka tidak ada yang berubah dan ErrInventoryFull.
func (s *State) completeStory(strict bool) ([]string, error) {
	st, ok := s.StoryNow()
	if !ok {
		return nil, nil
	}
	log := []string{st.Done}
	if strict {
		probe := State{Inventory: append([]Item(nil), s.Inventory...)}
		for _, it := range st.RewardItems {
			if !probe.AddItem(it.ID, it.Qty) {
				return nil, ErrInventoryFull
			}
		}
		s.Inventory = probe.Inventory
	} else {
		for _, it := range st.RewardItems {
			if !s.AddItem(it.ID, it.Qty) {
				log = append(log, "Ransel penuh: sebagian hadiah cerita tidak terbawa.")
			}
		}
	}
	if st.RewardGold > 0 {
		s.gainGold(st.RewardGold)
		s.record(LedgerQuest, "Cerita: "+st.Chapter, st.RewardGold)
		log = append(log, fmt.Sprintf("Hadiah cerita: +%d emas.", st.RewardGold))
	}
	s.Story++
	if s.Story >= StoryEnd {
		log = append(log, "Kutukan Malzareth telah berakhir. Kisahmu menjadi legenda Eldoria!")
	}
	s.checkAchievements()
	return log, nil
}

// advanceStory memajukan langkah yang syaratnya sudah terpenuhi tanpa tindakan khusus (arahan Kapten,
// ujian wilayah tuntas). Pemain lama yang sudah jauh berjalan ikut maju sampai langkah bicara berikutnya.
func (s *State) advanceStory() []string {
	var log []string
	for i := 0; i < len(Story); i++ {
		st, ok := s.StoryNow()
		if !ok {
			break
		}
		met := false
		switch st.Kind {
		case StoryBrief:
			met = s.Hutan.Started()
		case StoryTrial:
			met = s.Trial(st.Trial).Done()
		}
		if !met {
			break
		}
		l, _ := s.completeStory(false)
		log = append(log, l...)
	}
	return log
}

// AdvanceStory dipanggil setiap data pemain diambil/diubah server (aman diulang).
func (s *State) AdvanceStory() []string { return s.advanceStory() }

// storyKill: pemain mengalahkan musuh `enemyID`. Mengembalikan log bila itu bos langkah cerita sekarang.
func (s *State) storyKill(enemyID string) []string {
	st, ok := s.StoryNow()
	if !ok || st.Kind != StoryKill || st.Enemy != enemyID {
		return nil
	}
	log, _ := s.completeStory(false)
	return append(log, s.advanceStory()...)
}

// TalkStory: pemain bicara dengan NPC cerita / memakai benda cerita `npc`. Posisi tersimpan harus dekat.
func (s *State) TalkStory(npc string) ([]string, error) {
	log := s.advanceStory()
	st, ok := s.StoryNow()
	if !ok || st.Kind != StoryTalk || st.NPC != npc {
		return log, ErrStoryNotHere
	}
	if s.Map != st.Map || absInt(s.X-st.X) > st.Near || absInt(s.Y-st.Y) > st.Near {
		return log, ErrStoryFar
	}
	l, err := s.completeStory(true)
	if err != nil {
		return log, err
	}
	log = append(log, l...)
	return append(log, s.advanceStory()...), nil
}

// storyBossAllowed: bos cerita (Aldragor, Malzareth) hanya bisa dilawan pada langkah ceritanya.
// Bos lain selalu boleh.
func (s State) storyBossAllowed(enemyID string) error {
	for i, st := range Story {
		if st.Kind != StoryKill || st.Enemy != enemyID || enemyID == PanglimaID {
			continue
		}
		switch {
		case s.Story < i:
			return ErrStoryBoss
		case s.Story > i:
			return ErrStoryFreed
		}
	}
	return nil
}

func validStory(n int) bool { return n >= 0 && n <= StoryEnd }

// SpecialKutukan: serangan pamungkas Malzareth pada fase 3 (kerusakan x2).
const SpecialKutukan = "kutukan"

// malzarethPhase: Malzareth bertarung dalam tiga fase menurut sisa HP-nya (docs/STORY.md, Bab 4):
//  1. Sihir hitam (HP > 2/3): tiap serangan ke-3 gelombang sihir hitam (x1,8).
//  2. Panggilan monster (HP > 1/3): sisa pasukan terkutuk ikut menyerang tiap serangan ke-2 (x1,6).
//  3. Kutukan terakhir: tiap serangan ke-2 kutukan terakhir (x2); di bawah separuh HP ia juga mengamuk.
//
// Mengembalikan jenis dan nama kemampuan khusus serangan ini ("" = serangan biasa). Tidak memakai angka acak.
func (b *Battle) malzarethPhase(e Enemy, res *Result) (string, string) {
	phase := 3
	switch {
	case b.EnemyHP*3 > b.EnemyMaxHP*2:
		phase = 1
	case b.EnemyHP*3 > b.EnemyMaxHP:
		phase = 2
	}
	if phase > b.Phase {
		if b.Phase > 0 || phase > 1 {
			switch phase {
			case 2:
				res.Log = append(res.Log, "Malzareth memanggil sisa pasukan terkutuk! (Fase 2: Panggilan Monster)")
			case 3:
				res.Log = append(res.Log, "Malzareth mengerahkan seluruh kekuatannya! (Fase 3: Kutukan Terakhir)")
			}
		}
		b.Phase = phase
	}
	switch phase {
	case 1:
		if b.Round%3 == 0 {
			return SpecialGempa, "Gelombang Sihir Hitam"
		}
	case 2:
		if b.Round%2 == 0 {
			return SpecialTerkam, "Panggilan Monster"
		}
	default:
		if b.Round%2 == 0 {
			return SpecialKutukan, "Kutukan Terakhir"
		}
	}
	return "", ""
}
