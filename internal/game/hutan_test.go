package game

import (
	"errors"
	"fmt"
	"testing"
)

// kalahkan membuat pemain menang atas musuh id lewat satu pukulan (HP musuh 1).
func kalahkan(t *testing.T, p *Player, id string) Result {
	t.Helper()
	e, ok := EnemyByID(id)
	if !ok {
		t.Fatalf("musuh %s tidak ada", id)
	}
	b := &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: 1, EnemyMaxHP: e.HP, Round: 1, NextEnemyMs: 1000}
	res, err := act(b, p, ActionAttack, seq(50, 99, 99, 99, 99, 99, 99, 99))
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != StatusWon {
		t.Fatalf("harus menang atas %s: %+v", id, res)
	}
	return res
}

// Tiga wilayah ujian: tahap 25, 75, 100 musuh, masing-masing ditutup bos Level 1..3 (v0.65.0).
func TestTrialProgression(t *testing.T) {
	if StageKills != [3]int{25, 75, 100} {
		t.Fatalf("tahap harus 25/75/100: %v", StageKills)
	}
	foe := map[string]string{MapHutanLebat: "kancil_hutan", MapGuaGoblin: "goblin", MapGunungBatu: "goblin"}
	for _, tr := range Trials {
		p := newPlayer()
		st := &p.State
		st.Map = tr.Map
		for wave := 0; wave < HutanWaves; wave++ {
			st.X, st.Y = tr.BossX, tr.BossY
			if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrBossNotReady) {
				t.Fatalf("%s tahap %d: bos terlalu cepat muncul: %v", tr.Map, wave+1, err)
			}
			for i := 0; i < StageKills[wave]; i++ {
				kalahkan(t, p, foe[tr.Map])
			}
			h := st.Trial(tr.Map)
			if h.Wave != wave || h.Kills != StageKills[wave] || !h.BossReady() {
				t.Fatalf("%s tahap %d: kemajuan salah %+v", tr.Map, wave+1, h)
			}
			kalahkan(t, p, foe[tr.Map]) // musuh tambahan tidak melewati batas tahap
			if st.Trial(tr.Map).Kills != StageKills[wave] {
				t.Fatalf("%s: kills melewati batas: %+v", tr.Map, st.Trial(tr.Map))
			}
			b, err := StartBossBattle(p, 0)
			want := fmt.Sprintf("%s%d", tr.BossPrefix, wave+1)
			if err != nil || b.EnemyID != want {
				t.Fatalf("%s tahap %d: bos salah: %+v %v (mau %s)", tr.Map, wave+1, b, err, want)
			}
			res := kalahkan(t, p, b.EnemyID)
			if h := st.Trial(tr.Map); h.Wave != wave+1 || h.Kills != 0 {
				t.Fatalf("%s setelah bos %d: %+v", tr.Map, wave+1, h)
			}
			if len(res.Log) == 0 {
				t.Error("kemenangan bos harus ada log")
			}
		}
		if !st.Trial(tr.Map).Done() {
			t.Fatalf("%s harus selesai: %+v", tr.Map, st.Trial(tr.Map))
		}
		if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrBossNotReady) {
			t.Errorf("%s setelah selesai tidak ada bos lagi: %v", tr.Map, err)
		}
		kalahkan(t, p, foe[tr.Map])
		if st.Trial(tr.Map) != (HutanProgress{Wave: HutanWaves}) {
			t.Errorf("%s: kemajuan berubah setelah selesai: %+v", tr.Map, st.Trial(tr.Map))
		}
		if err := st.Validate(); err != nil {
			t.Errorf("%s: state sah ditolak: %v", tr.Map, err)
		}
		// Wilayah lain tidak ikut berubah.
		for _, other := range Trials {
			if other.Map != tr.Map && st.Trial(other.Map) != (HutanProgress{}) {
				t.Errorf("%s ikut berubah saat bermain di %s: %+v", other.Map, tr.Map, st.Trial(other.Map))
			}
		}
	}
}

func TestTrialsOldPlayersAndValidation(t *testing.T) {
	s := NewState()
	s.Visited = []string{MapGunungBatu}
	if !s.Trial(MapGuaGoblin).Done() || s.Trial(MapGunungBatu).Done() {
		t.Errorf("pemain lama yang sudah sampai Gunung Batu: Gua Goblin lulus, Gunung belum: %+v %+v", s.Trial(MapGuaGoblin), s.Trial(MapGunungBatu))
	}
	// Kemajuan lama Hutan (tahap 1 dulu 100 binatang) tetap sah dan langsung membuka bos.
	s.Hutan = HutanProgress{Kills: 60}
	if s.Validate() != nil || !s.Hutan.BossReady() {
		t.Errorf("kemajuan lama hutan harus sah dan bos siap: %+v", s.Hutan)
	}
	for name, bad := range map[string]map[string]HutanProgress{
		"peta bukan ujian": {MapDesaAwal: {}},
		"hutan di trials":  {MapHutanLebat: {}},
		"tahap mustahil":   {MapGuaGoblin: {Wave: 5}},
		"kills mustahil":   {MapGunungBatu: {Kills: 101}},
	} {
		s := NewState()
		s.Trials = bad
		if s.Validate() == nil {
			t.Errorf("%s harus ditolak", name)
		}
	}
	for _, id := range []string{"kepala_goblin_1", "kepala_goblin_3", "ogre_gunung_1", "ogre_gunung_3"} {
		if e, ok := EnemyByID(id); !ok || !e.Boss || !IsHutanBossID(id) {
			t.Errorf("bos ujian %s salah: %+v", id, e)
		}
	}
	for _, m := range []string{MapGuaGoblin, MapGunungBatu} {
		for i := 0; i < 300; i++ {
			if e := PickEnemy(20, m, RandomSource{}); e.Boss {
				t.Fatalf("bos acak di %s: %s", m, e.ID)
			}
		}
	}
}

func TestHutanNotCountedElsewhereAndValidation(t *testing.T) {
	p := newPlayer()
	p.State.Map = MapPerbatasan
	kalahkan(t, p, "tikus_sawah")
	if p.State.Hutan != (HutanProgress{}) {
		t.Errorf("kemenangan di luar hutan tidak dihitung: %+v", p.State.Hutan)
	}
	p.State.Map, p.State.X, p.State.Y = MapHutanLebat, 10, 10
	if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrNoBoss) {
		t.Errorf("jauh dari singgasana harus ErrNoBoss: %v", err)
	}
	// Dekat singgasana (bos menyambut di dunia): sah bila binatang tahap ini sudah kalah.
	p.State.X, p.State.Y = HutanBossX+9, HutanBossY-6
	if _, err := StartHutanBossBattle(p, 0); !errors.Is(err, ErrBossNotReady) {
		t.Errorf("binatang belum habis harus ErrBossNotReady: %v", err)
	}
	p.State.Hutan.Kills = StageNeed(0)
	b, err := StartHutanBossBattle(p, 0)
	if err != nil || b.EnemyID != "goblin_hutan_1" {
		t.Errorf("bos menyambut dekat singgasana: %+v %v", b, err)
	}
	p.State.X = HutanBossX + HutanBossRadius + 1
	if _, err := StartHutanBossBattle(p, 0); !errors.Is(err, ErrNoBoss) {
		t.Errorf("di luar jangkauan harus ErrNoBoss: %v", err)
	}
	if !IsHutanBossID("goblin_hutan_3") || IsHutanBossID("goblin") {
		t.Error("IsHutanBossID salah")
	}
	for _, bad := range []HutanProgress{{Wave: 4}, {Wave: -1}, {Kills: 101}, {Kills: -1}} {
		s := NewState()
		s.Hutan = bad
		if s.Validate() == nil {
			t.Errorf("kemajuan %+v harus ditolak", bad)
		}
	}
}

func TestHutanEnemyPools(t *testing.T) {
	for i := 0; i < 800; i++ {
		for _, lv := range []int{1, 3, 6, 20} {
			if e := PickEnemy(lv, MapHutanLebat, RandomSource{}); e.Boss {
				t.Fatalf("bos acak di hutan: %s", e.ID)
			}
			if e := PickEnemy(lv, MapGuaGoblin, RandomSource{}); e.Boss {
				t.Fatalf("bos acak di gua goblin: %s", e.ID)
			}
		}
	}
	for _, id := range []string{"kancil_hutan", "rubah_hutan", "ular_belang", "babi_bertaring", "serigala_hitam", "beruang_hutan", "goblin_hutan_1", "goblin_hutan_2", "goblin_hutan_3", "goblin_penjaga"} {
		if _, ok := EnemyByID(id); !ok {
			t.Errorf("musuh %s hilang", id)
		}
	}
	for _, m := range []string{MapHutanLebat, MapGuaGoblin} {
		if _, ok := worldMaps[m]; !ok {
			t.Errorf("peta %s tidak terdaftar", m)
		}
	}
}

func TestBriefHutan(t *testing.T) {
	p := newPlayer()
	st := &p.State
	if st.Hutan.Started() {
		t.Fatal("pemain baru belum boleh bertarung di hutan")
	}
	st.Map, st.X, st.Y = MapHutanLebat, KaptenX, KaptenY
	if err := st.BriefHutan(); !errors.Is(err, ErrNoKapten) {
		t.Errorf("di hutan Kapten tidak terjangkau: %v", err)
	}
	st.Map, st.X, st.Y = MapPerbatasan, KaptenX+KaptenRadius+1, KaptenY
	if err := st.BriefHutan(); !errors.Is(err, ErrNoKapten) {
		t.Errorf("terlalu jauh: %v", err)
	}
	st.X = KaptenX
	if err := st.BriefHutan(); err != nil || !st.Hutan.Briefed || !st.Hutan.Started() || !st.hasRadar() {
		t.Fatalf("arahan gagal: %v %+v", err, st.Hutan)
	}
	if err := st.BriefHutan(); err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, it := range st.Inventory {
		if it.ID == RadarID {
			n += it.Qty
		}
	}
	if n != 1 {
		t.Errorf("radar harus satu, ada %d", n)
	}
	if def, ok := ItemByID(RadarID); !ok || def.SellPrice != 0 || def.BuyPrice != 0 {
		t.Errorf("radar tidak boleh diperjualbelikan: %+v", def)
	}
	// Ransel penuh: radar tidak bisa diberikan, arahan tidak tercatat.
	q := newPlayer()
	q.State.Map, q.State.X, q.State.Y = MapPerbatasan, KaptenX, KaptenY
	q.State.Inventory = nil
	for i := 0; i < MaxInventory; i++ {
		q.State.Inventory = append(q.State.Inventory, Item{ID: fmt.Sprintf("barang_%d", i), Qty: 1})
	}
	if err := q.State.BriefHutan(); !errors.Is(err, ErrInventoryFull) || q.State.Hutan.Briefed {
		t.Errorf("ransel penuh: %v %+v", err, q.State.Hutan)
	}
	// Pemain lama yang sudah punya kemajuan tidak terkunci.
	if !(HutanProgress{Kills: 3}).Started() || !(HutanProgress{Wave: 1}).Started() {
		t.Error("kemajuan lama harus dianggap sudah diarahkan")
	}
}

// v0.71.0: bos Gua Goblin makin kuat tiap tahap, menyerang lebih cepat, memburu pemain ke seluruh gua,
// dan diperkuat untuk pemain di atas level 6.
func TestGuaGoblinBossHunts(t *testing.T) {
	var prevHP, prevAtk int
	prevIv := int64(BossIntervalMs)
	for lv := 1; lv <= 3; lv++ {
		e, _ := EnemyByID(fmt.Sprintf("kepala_goblin_%d", lv))
		if e.HP <= prevHP || e.Attack <= prevAtk || enemyInterval(e) >= prevIv {
			t.Fatalf("Kepala Goblin Lv %d harus lebih kuat dan cepat dari tahap sebelumnya: %+v", lv, e)
		}
		prevHP, prevAtk, prevIv = e.HP, e.Attack, enemyInterval(e)
	}
	p := newPlayer()
	st := &p.State
	st.Map = MapGuaGoblin
	st.Level = 6
	st.setTrial(MapGuaGoblin, HutanProgress{Wave: 1, Kills: StageKills[1]})
	st.X, st.Y = 3, 5 // ujung lorong buntu, jauh dari singgasana
	b, err := StartHutanBossBattle(p, 0)
	if err != nil || b.EnemyID != "kepala_goblin_2" {
		t.Fatalf("bos gua harus bisa dilawan di mana saja di gua: %v %+v", err, b)
	}
	e2, _ := EnemyByID("kepala_goblin_2")
	if b.EnemyMaxHP != e2.HP {
		t.Fatalf("pemain level 6: HP bos belum diperkuat, dapat %d", b.EnemyMaxHP)
	}
	st.Level = 11
	b, _ = StartHutanBossBattle(p, 0)
	if b.EnemyMaxHP != e2.HP*(100+5*BossLevelHP)/100 || b.enemyAttack(e2) <= e2.Attack {
		t.Fatalf("pemain level 11: bos +5 level, dapat HP %d serangan %d", b.EnemyMaxHP, b.enemyAttack(e2))
	}
	st.Map = MapHutanLebat
	st.Level = 6
	st.setTrial(MapHutanLebat, HutanProgress{Wave: 0, Kills: StageKills[0], Briefed: true})
	st.X, st.Y = 3, 5
	if _, err := StartHutanBossBattle(p, 0); !errors.Is(err, ErrNoBoss) {
		t.Fatalf("bos hutan tetap hanya di dekat singgasana: %v", err)
	}
}

// v0.72.0: urutan musuh tiap peta bertumpuk (binatang hutan -> goblin -> orc batu -> naga) dan makin berat.
func TestMapOrderAndPower(t *testing.T) {
	has := func(m, id string) bool { e, _ := EnemyByID(id); return e.inZone(m) && !e.Boss }
	checks := map[string][]string{
		MapHutanLebat: {"rubah_hutan", "beruang_hutan"},
		MapGuaGoblin:  {"rubah_hutan", "goblin", "serigala_tulang", "beruang_tulang"},
		MapGunungBatu: {"beruang_hutan", "goblin_pemburu", "ogre_batu"},
		MapGuaBatu:    {"serigala_hitam", "goblin", "ogre_batu", "orc_gua"},
		MapIstana:     {"beruang_hutan", "goblin", "ogre_batu", "naga_bayangan", "naga_api"},
	}
	for m, ids := range checks {
		for _, id := range ids {
			if !has(m, id) {
				t.Errorf("%s harus punya musuh %s", m, id)
			}
		}
	}
	if has(MapHutanLebat, "goblin") || has(MapGuaGoblin, "ogre_batu") || has(MapGunungBatu, "naga_api") {
		t.Error("golongan musuh peta berikutnya tidak boleh muncul lebih awal")
	}
	// Serigala Hitam makin kuat di tiap peta berikutnya.
	e, _ := EnemyByID("serigala_hitam")
	prev := 0
	for _, m := range []string{MapHutanLebat, MapGuaGoblin, MapGunungBatu, MapGuaBatu, MapIstana} {
		st := State{Map: m, Level: 4}
		st.setTrial(m, HutanProgress{Wave: 0, Briefed: true})
		b := Battle{EnemyHP: e.HP, EnemyMaxHP: e.HP}
		b.strengthen(st, e)
		if b.EnemyMaxHP <= prev {
			t.Fatalf("%s: HP Serigala Hitam %d tidak lebih berat dari peta sebelumnya (%d)", m, b.EnemyMaxHP, prev)
		}
		prev = b.EnemyMaxHP
	}
	// Bos terakhir tiap peta makin kuat: Goblin Lv 3 < Raja Orc Batu < Induk Naga Lava < Panglima < Aldragor < Malzareth.
	prevHP := 0
	for _, id := range []string{"goblin_hutan_3", "kepala_goblin_3", "ogre_gunung_3", "raja_goblin", AldragorID, MalzarethID} {
		b, _ := EnemyByID(id)
		if b.HP <= prevHP {
			t.Fatalf("bos %s (HP %d) harus lebih kuat dari bos peta sebelumnya (%d)", id, b.HP, prevHP)
		}
		prevHP = b.HP
	}
}
