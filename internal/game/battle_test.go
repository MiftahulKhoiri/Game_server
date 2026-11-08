package game

import (
	"errors"
	"math"
	"testing"
)

// seq mengembalikan Rand yang memberi angka berurutan (diambil modulo n).
// Urutan panggilan dalam satu ronde:
//
//	serang  : variasi(41), kritis(100), [musuh: variasi(41)], [menang: drop(100)]
//	bertahan: [musuh: variasi(41)]
//	ramuan  : [musuh: variasi(41)]
//	kabur   : peluang(100), [gagal -> musuh: variasi(41)]
//
// Variasi 20 = 100% kerusakan; kritis 99 = tidak kritis; drop 99 = tidak jatuh.
func seq(vals ...int) Rand {
	i := 0
	return RandFunc(func(n int) int {
		if i >= len(vals) {
			panic("seq habis: tes memanggil Rand lebih banyak dari yang disiapkan")
		}
		v := vals[i] % n
		i++
		return v
	})
}

func newPlayer() *Player { return &Player{State: NewState()} }

func battleVs(enemyID string, hp int) *Battle {
	e, _ := EnemyByID(enemyID)
	return &Battle{EnemyID: e.ID, EnemyName: e.Name, EnemyHP: hp, EnemyMaxHP: e.HP, Round: 1, NextEnemyMs: 1000}
}

// act menjalankan aksi tepat saat serangan musuh jatuh tempo, dengan semua cooldown siap:
// sama seperti satu "ronde" lama (aksi pemain lalu satu serangan musuh).
func act(b *Battle, p *Player, action string, rng Rand) (Result, error) {
	b.Ready = nil
	return b.Act(p, action, b.NextEnemyMs, rng)
}

func TestAttackKillsAndRewards(t *testing.T) {
	p := newPlayer()
	b := battleVs("tikus_sawah", 5)
	res, err := act(b, p, ActionAttack, seq(20, 99, 99, 99))
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != StatusWon || b.EnemyHP != 0 {
		t.Fatalf("harus menang: %+v, hp musuh %d", res, b.EnemyHP)
	}
	if p.State.XP != 6 || p.State.Gold != 2 || p.State.Level != 1 {
		t.Errorf("hadiah salah: %+v", p.State)
	}
	if res.Rewards == nil || res.Rewards.XP != 6 || res.Rewards.LeveledUp {
		t.Errorf("rewards salah: %+v", res.Rewards)
	}
}

func TestLevelUp(t *testing.T) {
	p := newPlayer()
	p.State.XP = 18
	b := battleVs("tikus_sawah", 1)
	res, err := act(b, p, ActionAttack, seq(20, 99, 99, 99))
	if err != nil {
		t.Fatal(err)
	}
	if !res.Rewards.LeveledUp || res.Rewards.NewLevel != 2 {
		t.Fatalf("harus naik level: %+v", res.Rewards)
	}
	if p.State.Level != 2 || p.State.XP != 4 || p.State.MaxHP != 38 || p.State.HP != 38 {
		t.Errorf("state setelah naik level salah: %+v", p.State)
	}
	if err := p.State.Validate(); err != nil {
		t.Errorf("state tidak valid: %v", err)
	}
}

func TestDropAddsItem(t *testing.T) {
	p := newPlayer() // mulai dengan 2 ramuan
	b := battleVs("tikus_sawah", 1)
	res, _ := act(b, p, ActionAttack, seq(20, 99, 0, 99)) // drop 0 < 10%
	if res.Rewards.Drop != PotionID || p.State.Inventory[0].Qty != 3 {
		t.Errorf("harus dapat ramuan: %+v %+v", res.Rewards, p.State.Inventory)
	}
}

func TestEnemyRetaliates(t *testing.T) {
	p := newPlayer()
	b := battleVs("tikus_sawah", 10)
	res, err := act(b, p, ActionAttack, seq(20, 99, 20, 99))
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != StatusOngoing || b.EnemyHP != 4 || p.State.HP != 29 || b.Round != 2 {
		t.Errorf("ronde salah: status=%s hp musuh=%d hp pemain=%d ronde=%d", res.Status, b.EnemyHP, p.State.HP, b.Round)
	}
	if len(res.Log) != 2 {
		t.Errorf("log harus 2 baris: %v", res.Log)
	}
}

func TestDefendHalvesDamage(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 34) // serang 8 - bertahan 2 = 6, dibagi 2 = 3
	// Bertahan ditekan 800 ms sebelum serangan musuh: di dalam jendela tetapi lewat batas tangkisan sempurna.
	if _, err := b.Act(p, ActionDefend, 200, seq()); err != nil {
		t.Fatal(err)
	}
	res, err := b.Sync(p, 1000, seq(20))
	if err != nil {
		t.Fatal(err)
	}
	if p.State.HP != 27 || len(res.Events) != 1 || res.Events[0].Kind != "guard" {
		t.Errorf("HP = %d; mau 27 (%+v)", p.State.HP, res.Events)
	}
}

func TestPerfectGuardBlocksAndDelays(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 34)
	// Bertahan ditekan 200 ms sebelum serangan: tangkisan sempurna.
	if _, err := b.Act(p, ActionDefend, 800, seq()); err != nil {
		t.Fatal(err)
	}
	res, _ := b.Sync(p, 1000, seq(20))
	if p.State.HP != 30 || res.Events[0].Kind != "perfect" {
		t.Errorf("harus tertangkis penuh: hp=%d %+v", p.State.HP, res.Events)
	}
	if want := int64(1000 + EnemyIntervalMs + PerfectDelayMs); b.NextEnemyMs != want {
		t.Errorf("serangan berikutnya harus tertunda: %d; mau %d", b.NextEnemyMs, want)
	}
	// Setelah jendela habis, serangan berikutnya kena penuh.
	b.GuardUntil = 0
	b.Sync(p, b.NextEnemyMs, seq(20))
	if p.State.HP != 30-6 {
		t.Errorf("serangan tanpa bertahan: hp=%d", p.State.HP)
	}
}

func TestGuardLateNetworkStillCounts(t *testing.T) {
	// Tombol ditekan sedikit sebelum serangan, tetapi paketnya tiba sedikit sesudahnya.
	p := newPlayer()
	b := battleVs("babi_hutan", 34)
	b.NextEnemyMs = 1000
	if _, err := b.Act(p, ActionDefend, 1100, seq(20)); err != nil { // tiba 100 ms terlambat
		t.Fatal(err)
	}
	if p.State.HP != 30 {
		t.Errorf("kelonggaran jaringan harus menolong: hp=%d", p.State.HP)
	}
}

func TestCooldownEnforced(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 34)
	b.NextEnemyMs = 10_000
	if _, err := b.Act(p, ActionAttack, 0, seq(20, 99)); err != nil {
		t.Fatal(err)
	}
	if _, err := b.Act(p, ActionAttack, CooldownMs[ActionAttack]-1, seq()); !errors.Is(err, ErrCooldown) {
		t.Errorf("harus ErrCooldown, dapat %v", err)
	}
	if _, err := b.Act(p, ActionAttack, CooldownMs[ActionAttack], seq(20, 99)); err != nil {
		t.Errorf("setelah cooldown harus bisa: %v", err)
	}
	// Aksi lain tidak ikut terkunci.
	if _, err := b.Act(p, ActionSkill1, CooldownMs[ActionAttack], seq(20, 99)); err != nil {
		t.Errorf("skill harus tetap bisa: %v", err)
	}
	v := b.View(CooldownMs[ActionAttack])
	if v.Cooldowns[ActionSkill1] != CooldownMs[ActionSkill1] || v.CooldownMax[ActionSkill2] != CooldownMs[ActionSkill2] {
		t.Errorf("tampilan cooldown salah: %+v", v)
	}
}

func TestSkill1DealsMore(t *testing.T) {
	hp := func(action string) int {
		p := newPlayer()
		b := battleVs("babi_hutan", 34)
		b.NextEnemyMs = 10_000
		if _, err := b.Act(p, action, 0, seq(20, 99)); err != nil {
			t.Fatal(err)
		}
		return b.EnemyHP
	}
	if a, s := hp(ActionAttack), hp(ActionSkill1); s >= a {
		t.Errorf("skill 1 harus lebih kuat: serang sisa %d, skill sisa %d", a, s)
	}
}

func TestSkill2HealsAndShields(t *testing.T) {
	p := newPlayer()
	p.State.HP = 10
	b := battleVs("babi_hutan", 34)
	b.NextEnemyMs = 1500
	if _, err := b.Act(p, ActionSkill2, 1000, seq()); err != nil {
		t.Fatal(err)
	}
	want := 10 + p.State.MaxHP*Skill2HealPercent/100
	if p.State.HP != want {
		t.Fatalf("HP = %d; mau %d", p.State.HP, want)
	}
	b.Sync(p, 1500, seq(20)) // serangan 6 -> 30% = 1
	if p.State.HP != want-max(1, 6*ShieldPercent/100) {
		t.Errorf("perisai harus meredam: hp=%d", p.State.HP)
	}
}

func TestEnemyAttacksWithoutPlayer(t *testing.T) {
	p := newPlayer()
	b := battleVs("babi_hutan", 34)
	res, err := b.Sync(p, 999, seq())
	if err != nil || len(res.Events) != 0 || p.State.HP != 30 {
		t.Fatalf("belum jatuh tempo: %v %+v hp=%d", err, res, p.State.HP)
	}
	res, _ = b.Sync(p, 1000, seq(20))
	if len(res.Events) != 1 || p.State.HP != 24 || b.NextEnemyMs != 1000+EnemyIntervalMs {
		t.Errorf("musuh harus menyerang sendiri: %+v hp=%d next=%d", res.Events, p.State.HP, b.NextEnemyMs)
	}
}

func TestCatchUpIsCapped(t *testing.T) {
	// App ditutup lama: tidak boleh menumpuk puluhan serangan.
	p := newPlayer()
	b := battleVs("tikus_sawah", 10)
	res, _ := b.Sync(p, 10*60*1000, RandomSource{})
	if n := len(res.Events); n > maxCatchUpHits+1 {
		t.Errorf("serangan susulan terlalu banyak: %d", n)
	}
}

func TestLegacyBattleGetsSchedule(t *testing.T) {
	p := newPlayer()
	b := &Battle{EnemyID: "tikus_sawah", EnemyName: "Tikus", EnemyHP: 10, EnemyMaxHP: 10, Round: 1}
	res, err := b.Sync(p, 5000, seq())
	if err != nil || len(res.Events) != 0 || b.NextEnemyMs != 5000+FirstHitDelayMs {
		t.Errorf("pertarungan lama harus dijadwalkan: %v %+v next=%d", err, res, b.NextEnemyMs)
	}
}

func TestDeathDuringSync(t *testing.T) {
	p := newPlayer()
	p.State.HP = 1
	b := battleVs("babi_hutan", 34)
	res, _ := b.Sync(p, 1000, seq(20))
	if res.Status != StatusLost || p.State.Map != SpawnMap {
		t.Errorf("harus kalah dan pulang: %+v", res)
	}
}

func TestPotion(t *testing.T) {
	p := newPlayer()
	p.State.HP = 10
	b := battleVs("tikus_sawah", 10)
	if _, err := act(b, p, ActionPotion, seq(20)); err != nil {
		t.Fatal(err)
	}
	if p.State.HP != 24 { // 10 + 15 - 1 serangan tikus
		t.Errorf("HP = %d; mau 24", p.State.HP)
	}
	if p.State.Inventory[0].Qty != 1 {
		t.Errorf("ramuan harus tersisa 1: %+v", p.State.Inventory)
	}
}

func TestPotionRejected(t *testing.T) {
	p := newPlayer() // HP penuh
	b := battleVs("tikus_sawah", 10)
	if _, err := act(b, p, ActionPotion, seq()); !errors.Is(err, ErrFullHP) {
		t.Errorf("HP penuh harus ErrFullHP, dapat %v", err)
	}
	if p.State.Inventory[0].Qty != 2 {
		t.Error("ramuan tidak boleh terpakai saat ditolak")
	}

	p.State.HP = 5
	p.State.Inventory = []Item{}
	if _, err := act(b, p, ActionPotion, seq()); !errors.Is(err, ErrNoPotion) {
		t.Errorf("tanpa ramuan harus ErrNoPotion, dapat %v", err)
	}
}

func TestFlee(t *testing.T) {
	p := newPlayer()
	b := battleVs("tikus_sawah", 10)
	res, _ := act(b, p, ActionFlee, seq(0))
	if res.Status != StatusFled || p.State.HP != 30 {
		t.Errorf("kabur berhasil: status=%s hp=%d", res.Status, p.State.HP)
	}

	res, _ = act(b, p, ActionFlee, seq(99, 20))
	if res.Status != StatusOngoing || p.State.HP != 29 {
		t.Errorf("kabur gagal harus kena serang: status=%s hp=%d", res.Status, p.State.HP)
	}
}

func TestLoseRespawns(t *testing.T) {
	p := newPlayer()
	p.State.HP, p.State.Gold = 1, 11
	p.State.Map, p.State.X, p.State.Y = "peta_lain", 9, 9
	b := battleVs("tikus_sawah", 10)
	res, _ := act(b, p, ActionFlee, seq(99, 20))
	if res.Status != StatusLost {
		t.Fatalf("harus kalah: %+v", res)
	}
	s := p.State
	if s.HP != 15 || s.Gold != 6 || s.Map != SpawnMap || s.X != SpawnX || s.Y != SpawnY {
		t.Errorf("pemulangan salah: %+v", s)
	}
}

func TestBadAction(t *testing.T) {
	b := battleVs("tikus_sawah", 10)
	if _, err := act(b, newPlayer(), "teleport", seq()); !errors.Is(err, ErrBadAction) {
		t.Errorf("harus ErrBadAction, dapat %v", err)
	}
}

func TestPickEnemyRespectsLevelAndZone(t *testing.T) {
	for i := 0; i < 300; i++ {
		// Sejak v0.32.0 desa aman: tak ada musuh yang berzona di sana, jadi server cadangkan musuh terlemah.
		if e := PickEnemy(1, MapDesaAwal, RandomSource{}); e.MinLevel > 1 {
			t.Fatalf("level 1 di desa bertemu %s", e.ID)
		}
		if e := PickEnemy(1, MapPerbatasan, RandomSource{}); !e.inZone(MapPerbatasan) || e.MinLevel > 1 {
			t.Fatalf("level 1 di perbatasan bertemu %s", e.ID)
		}
	}
	for _, zone := range []string{MapPerbatasan, MapGunungBatu, MapGuaBatu} {
		seen := map[string]bool{}
		want := 0
		for _, e := range enemies {
			if e.inZone(zone) && !e.Boss {
				want++
			}
		}
		for i := 0; i < 1500; i++ {
			seen[PickEnemy(10, zone, RandomSource{}).ID] = true
		}
		if len(seen) != want {
			t.Errorf("%s level 10 harus bisa bertemu %d musuh, dapat %v", zone, want, seen)
		}
	}
	// Terlalu rendah untuk wilayahnya: tetap bertemu musuh terlemah di sana, bukan musuh peta lain.
	if e := PickEnemy(1, MapGunungBatu, RandomSource{}); !e.inZone(MapGunungBatu) || e.MinLevel != 2 {
		t.Errorf("level 1 di gunung harus bertemu musuh terlemah gunung, dapat %s", e.ID)
	}
	// Peta tak dikenal tidak boleh membuat server panik.
	if e := PickEnemy(1, "tidak_ada", RandomSource{}); e.ID == "" {
		t.Error("harus tetap memilih musuh")
	}
}

func TestOgreOnlyInGunung(t *testing.T) {
	e, ok := EnemyByID("ogre_batu")
	if !ok || e.inZone(MapDesaAwal) || e.inZone(MapPerbatasan) || !e.inZone(MapGunungBatu) {
		t.Errorf("ogre hanya boleh di gunung: %+v", e)
	}
}

func TestValidPosition(t *testing.T) {
	ok := []struct {
		m    string
		x, y int
	}{{MapDesaAwal, 0, 0}, {MapDesaAwal, 84, 49}, {MapPerbatasan, 7, 1}, {MapGunungBatu, 7, 1}, {MapGuaBatu, 7, 14}}
	for _, c := range ok {
		if !ValidPosition(c.m, c.x, c.y) {
			t.Errorf("%v harus valid", c)
		}
	}
	bad := []struct {
		m    string
		x, y int
	}{{MapDesaAwal, 85, 0}, {MapDesaAwal, 0, 50}, {MapDesaAwal, -1, 0}, {"neraka", 1, 1}, {"", 0, 0}}
	for _, c := range bad {
		if ValidPosition(c.m, c.x, c.y) {
			t.Errorf("%v harus ditolak", c)
		}
	}
}

func TestInventoryHelpers(t *testing.T) {
	var s State
	if !s.AddItem("a", 5) || !s.AddItem("a", 3) || s.Inventory[0].Qty != 8 {
		t.Fatalf("AddItem salah: %+v", s.Inventory)
	}
	if !s.AddItem("a", MaxStack) || s.Inventory[0].Qty != MaxStack {
		t.Errorf("harus dibatasi MaxStack: %+v", s.Inventory)
	}
	if s.RemoveItem("a", MaxStack+1) {
		t.Error("tidak boleh mengurangi lebih dari yang ada")
	}
	if !s.RemoveItem("a", MaxStack) || len(s.Inventory) != 0 {
		t.Errorf("tumpukan kosong harus hilang: %+v", s.Inventory)
	}
	if s.RemoveItem("tidak_ada", 1) {
		t.Error("barang tidak ada harus false")
	}
}

func TestBalanceFirstFightsAreWinnable(t *testing.T) {
	// Pemain level 1 yang hanya menyerang harus bisa mengalahkan musuh level 1 tanpa mati.
	for _, id := range []string{"tikus_sawah", "belalang_raksasa"} {
		p := newPlayer()
		b := battleVs(id, mustEnemy(id).HP)
		for round := 0; round < 50 && p.State.HP > 0; round++ {
			res, err := act(b, p, ActionAttack, RandomSource{})
			if err != nil {
				t.Fatal(err)
			}
			if res.Status != StatusOngoing {
				if res.Status != StatusWon {
					t.Errorf("%s: pemain level 1 kalah", id)
				}
				break
			}
		}
	}
}

func mustEnemy(id string) Enemy {
	e, ok := EnemyByID(id)
	if !ok {
		panic("musuh tidak ada: " + id)
	}
	return e
}

func TestBossNeverRandomAndOnlyAtSpot(t *testing.T) {
	for _, zone := range []string{MapDesaAwal, MapPerbatasan, MapGunungBatu, MapGuaBatu, "tidak_ada"} {
		for i := 0; i < 500; i++ {
			if e := PickEnemy(100, zone, RandomSource{}); e.Boss {
				t.Fatalf("bos %s muncul acak di %s", e.ID, zone)
			}
		}
	}
	if e := PickEnemy(1, MapGuaBatu, RandomSource{}); e.Boss || e.ID != "orc_gua" {
		t.Errorf("level rendah di gua harus bertemu musuh terlemah gua non-bos, dapat %s", e.ID)
	}

	p := newPlayer()
	if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrNoBoss) {
		t.Errorf("jauh dari bos harus ErrNoBoss, dapat %v", err)
	}
	p.State.Map, p.State.X, p.State.Y = MapGuaBatu, 7, 14
	b, err := StartBossBattle(p, 0)
	if err != nil || b.EnemyID != "raja_goblin" || b.EnemyHP != 120 {
		t.Fatalf("bos: %+v %v", b, err)
	}
	p.State.X = 8
	if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrNoBoss) {
		t.Error("bergeser satu petak harus ErrNoBoss")
	}
}

func TestNormalizePose(t *testing.T) {
	ok, valid := NormalizePose(Pose{Map: MapDesaAwal, X: 3, Y: 4, FX: 3.25, FZ: 4.75, Yaw: 1})
	if !valid || ok.FX != 3.25 || ok.FZ != 4.75 || ok.Yaw != 1 {
		t.Errorf("pose sah berubah: %+v valid=%v", ok, valid)
	}
	// Klien lama: tanpa posisi halus -> tengah petak.
	old, valid := NormalizePose(Pose{Map: MapDesaAwal, X: 3, Y: 4})
	if !valid || old.FX != 3.5 || old.FZ != 4.5 {
		t.Errorf("klien lama harus di tengah petak: %+v", old)
	}
	// Posisi halus di luar petak -> tengah petak (petak yang jadi acuan).
	off, _ := NormalizePose(Pose{Map: MapDesaAwal, X: 3, Y: 4, FX: 9.9, FZ: 0.1})
	if off.FX != 3.5 || off.FZ != 4.5 {
		t.Errorf("posisi tidak cocok petak harus diperbaiki: %+v", off)
	}
	// Batas atas petak (FX == X+1) bukan bagian petak itu.
	edge, _ := NormalizePose(Pose{Map: MapDesaAwal, X: 3, Y: 4, FX: 4.0, FZ: 4.5})
	if edge.FX != 3.5 {
		t.Errorf("FX == X+1 harus dianggap di luar petak: %+v", edge)
	}
	// Arah dibulatkan ke -pi..pi.
	spin, _ := NormalizePose(Pose{Map: MapDesaAwal, X: 3, Y: 4, FX: 3.5, FZ: 4.5, Yaw: 7})
	if spin.Yaw < -3.1416 || spin.Yaw > 3.1416 {
		t.Errorf("yaw di luar -pi..pi: %v", spin.Yaw)
	}
	for name, p := range map[string]Pose{
		"peta asing":  {Map: "neraka", X: 1, Y: 1},
		"luar peta":   {Map: MapDesaAwal, X: 85, Y: 1},
		"NaN":         {Map: MapDesaAwal, X: 1, Y: 1, FX: math.NaN()},
		"tak hingga":  {Map: MapDesaAwal, X: 1, Y: 1, FZ: math.Inf(1)},
		"yaw tak sah": {Map: MapDesaAwal, X: 1, Y: 1, Yaw: math.Inf(-1)},
	} {
		if _, valid := NormalizePose(p); valid {
			t.Errorf("%s harus ditolak", name)
		}
	}
	if s := NewState(); s.FX != float64(SpawnX)+0.5 || s.FZ != float64(SpawnY)+0.5 {
		t.Errorf("pemain baru harus di tengah petak awal: %+v", s)
	}
}

func TestPickEnemyForUsesVisibleEnemyOnlyWhenAllowed(t *testing.T) {
	rng := RandomSource{}
	// Musuh yang sah di peta dan levelnya dipakai apa adanya.
	if e := PickEnemyFor(3, MapPerbatasan, "serigala_hutan", rng); e.ID != "serigala_hutan" {
		t.Errorf("serigala hutan sah di hutan level 3, dapat %s", e.ID)
	}
	// Musuh peta lain, bos, dan id ngawur diabaikan: server memilih sendiri di peta pemain.
	for _, want := range []string{"orc_gua", "raja_goblin", "tidak_ada"} {
		for i := 0; i < 100; i++ {
			if e := PickEnemyFor(10, MapPerbatasan, want, rng); !e.inZone(MapPerbatasan) || e.Boss {
				t.Fatalf("%q di hutan menghasilkan %s", want, e.ID)
			}
		}
	}
	// Terlalu kuat untuk levelnya: ditolak, kecuali musuh terlemah di peta itu.
	for i := 0; i < 100; i++ {
		if e := PickEnemyFor(1, MapPerbatasan, "serigala_alfa", rng); e.MinLevel > 1 {
			t.Fatalf("serigala alfa tidak boleh muncul untuk level 1, dapat %s", e.ID)
		}
	}
	if e := PickEnemyFor(1, MapGunungBatu, "goblin", rng); e.ID != "goblin" {
		t.Errorf("goblin adalah musuh terlemah gunung, boleh dipilih level 1: %s", e.ID)
	}
	// Zona tiap peta: hutan hewan, gunung goblin, gua orc.
	for zone, ids := range map[string][]string{
		MapPerbatasan: {"ular_hutan", "serigala_hutan", "babi_hutan", "serigala_alfa"},
		MapGunungBatu: {"goblin", "goblin_pemburu", "ogre_batu"},
		MapGuaBatu:    {"orc_gua", "orc_penjaga", "orc_buas"},
	} {
		for _, id := range ids {
			if e, ok := EnemyByID(id); !ok || !e.inZone(zone) {
				t.Errorf("%s harus muncul di %s", id, zone)
			}
		}
	}
	for _, id := range []string{"kelelawar_gua", "golem_kerikil", "goblin_penjaga", "golem_lava"} {
		for _, zone := range []string{MapDesaAwal, MapPerbatasan, MapGunungBatu, MapGuaBatu} {
			if e, _ := EnemyByID(id); e.inZone(zone) {
				t.Errorf("%s sudah pensiun tetapi masih muncul di %s", id, zone)
			}
		}
	}
}
