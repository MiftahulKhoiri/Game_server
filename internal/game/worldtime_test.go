package game

import (
	"errors"
	"math"
	"testing"
)

// at: detik Unix pada hari `day` jam `hour` permainan.
func at(day int64, hour float64) int64 {
	return day*DaySeconds + int64(hour/24*DaySeconds)
}

func withNow(t *testing.T, unix int64) {
	t.Helper()
	old := Now
	Now = func() int64 { return unix }
	t.Cleanup(func() { Now = old })
}

func TestWorldClock(t *testing.T) {
	if h := WorldHour(at(5, 13.5)); math.Abs(h-13.5) > 0.05 {
		t.Errorf("jam: %v", h)
	}
	if WorldDay(at(5, 23)) != 5 || IsNightAt(at(5, 12)) || !IsNightAt(at(5, 22)) || !IsNightAt(at(6, 3)) {
		t.Error("hari/malam salah")
	}
	rain := 0
	for b := int64(0); b < 2000; b++ {
		if RainingAt(b * WeatherBlockS) {
			rain++
		}
	}
	if rain < 450 || rain > 750 {
		t.Errorf("hujan harus sekitar 30%% blok: %d/2000", rain)
	}
}

func TestRaidAndMarketSchedule(t *testing.T) {
	// Malam hari ke-1 (dan dini hari ke-2) = serbuan; malam hari ke-0 bukan.
	if !RaidActive(at(1, 20)) || !RaidActive(at(2, 2)) || RaidActive(at(1, 12)) || RaidActive(at(0, 20)) || RaidActive(at(2, 20)) {
		t.Error("jadwal serbuan salah")
	}
	if RaidID(at(1, 20)) != RaidID(at(2, 2)) {
		t.Error("satu malam = satu serbuan")
	}
	if !MarketActive(at(2, 9)) || MarketActive(at(2, 18)) || MarketActive(at(3, 9)) {
		t.Error("jadwal Hari Pasar salah")
	}
	evs := Events(at(1, 12))
	if evs[0].Kind != EventRaid || evs[0].Active || evs[0].NextIn <= 0 || evs[0].NextIn > DaySeconds {
		t.Errorf("serbuan berikutnya: %+v", evs[0])
	}
	if ev := Events(at(1, 20))[0]; !ev.Active || ev.EndsIn <= 0 {
		t.Errorf("serbuan aktif: %+v", ev)
	}
}

func TestEnemyTimeAndRaidFilter(t *testing.T) {
	withNow(t, at(0, 12)) // siang biasa
	for range 200 {
		if e := PickEnemy(9, MapHutanLebat, RandomSource{}); e.ID == "serigala_hitam" {
			t.Fatal("Serigala Hitam hanya malam")
		}
	}
	if e := PickEnemyFor(9, MapDesaAwal, "goblin_penyerbu", RandomSource{}); e.ID == "goblin_penyerbu" {
		t.Fatal("penyerbu tidak ada di luar serbuan")
	}
	withNow(t, at(0, 22)) // malam biasa
	for range 200 {
		if e := PickEnemy(9, MapHutanLebat, RandomSource{}); e.ID == "kancil_hutan" {
			t.Fatal("Kancil Hutan hanya siang")
		}
	}
	withNow(t, at(1, 22)) // malam serbuan
	if e := PickEnemyFor(1, MapDesaAwal, "goblin_penyerbu", RandomSource{}); e.ID != "goblin_penyerbu" {
		t.Fatalf("saat serbuan penyerbu boleh dilawan: %s", e.ID)
	}
	// Kelonggaran 30 detik: klien yang memunculkan musuh sesaat sebelum pagi tetap diterima.
	withNow(t, at(1, 22))
	if !mustEnemy("serigala_hitam").timeAllows(at(2, NightTo) + 10) {
		t.Error("kelonggaran waktu")
	}
}

func TestNightBattleBonus(t *testing.T) {
	p := newPlayer()
	p.State.Map = MapPerbatasan
	withNow(t, at(0, 22))
	b := StartBattleWith(p, "babi_hutan", RandomSource{}, 0)
	if !b.Night {
		t.Fatal("malam di luar ruangan")
	}
	p.State.Map = MapGuaBatu
	if StartBattleWith(p, "orc_gua", RandomSource{}, 0).Night {
		t.Fatal("di gua tidak ada malam")
	}
	// Serangan malam lebih kuat dan XP lebih besar.
	hit := func(night bool) int {
		q := newPlayer()
		bb := battleVs("babi_hutan", 34)
		bb.Night = night
		hp := q.State.HP
		if _, err := bb.Sync(q, 1000, seq(20)); err != nil {
			t.Fatal(err)
		}
		return hp - q.State.HP
	}
	if hit(true) <= hit(false) {
		t.Errorf("malam: kerusakan musuh harus lebih besar (%d vs %d)", hit(true), hit(false))
	}
	q := newPlayer()
	bb := battleVs("tikus_sawah", 1)
	bb.Night = true
	res, _ := act(bb, q, ActionAttack, seq(20, 99, 99, 99))
	if res.Rewards == nil || res.Rewards.XP != mustEnemy("tikus_sawah").XP*NightXP/100 {
		t.Fatalf("bonus XP malam: %+v", res.Rewards)
	}
}

func TestRaidDefenseReward(t *testing.T) {
	night := at(1, 21)
	withNow(t, night)
	s := villager()
	if err := s.ClaimRaid(night); !errors.Is(err, ErrNoRaid) {
		t.Fatalf("belum ikut: %v", err)
	}
	for i := 0; i < RaidGoal-1; i++ {
		s.recordRaid(night)
	}
	if err := s.ClaimRaid(night); !errors.Is(err, ErrRaidGoal) {
		t.Fatalf("belum cukup: %v", err)
	}
	s.recordRaid(night)
	gold := s.Gold
	if err := s.ClaimRaid(night + 60); err != nil || s.Gold != gold+RaidRewardG || s.Defended != 1 {
		t.Fatalf("hadiah: %v emas %d", err, s.Gold)
	}
	if err := s.ClaimRaid(night + 60); !errors.Is(err, ErrRaidClaimed) {
		t.Fatalf("sekali saja: %v", err)
	}
	if !s.achieved("pembela_desa") {
		t.Error("pencapaian Pembela Desa")
	}
	// Serbuan berikutnya mulai dari nol.
	s.recordRaid(at(4, 21))
	if s.Raid.Kills != 1 || s.Raid.Claimed {
		t.Errorf("serbuan baru: %+v", s.Raid)
	}
	// Menang melawan penyerbu dalam pertarungan mencatat kemajuan.
	p := &Player{State: villager()}
	b := battleVs("goblin_penyerbu", 1)
	res, _ := act(b, p, ActionAttack, seq(20, 99, 99, 99))
	if p.State.Raid.Kills != 1 || res.Status != StatusWon {
		t.Fatalf("kemenangan penyerbu tercatat: %+v %v", p.State.Raid, res.Log)
	}
}

func TestSecretsAndExplore(t *testing.T) {
	s := villager()
	sec := Secrets[0]
	if _, err := s.FindSecret(sec.ID); !errors.Is(err, ErrSecretFar) {
		t.Fatalf("jauh: %v", err)
	}
	s.Map, s.X, s.Y = sec.Map, sec.X+1, sec.Y-1
	gold := s.Gold
	if _, err := s.FindSecret(sec.ID); err != nil || s.Gold != gold+sec.Gold || s.itemQty(sec.Item) != 1 {
		t.Fatalf("menemukan: %v", err)
	}
	if _, err := s.FindSecret(sec.ID); !errors.Is(err, ErrSecretFound) {
		t.Fatalf("sekali saja: %v", err)
	}
	if _, err := s.FindSecret("tidak_ada"); !errors.Is(err, ErrUnknownSecret) {
		t.Fatal(err)
	}
	for _, m := range ExploreMaps {
		s.Visit(m)
	}
	s.Visit(MapDesaAwal)
	s.Visit("toko_ramuan") // bangunan tidak dihitung
	if len(s.Visited) != len(ExploreMaps) || !s.achieved("penjelajah") {
		t.Fatalf("penjelajahan: %v", s.Visited)
	}
	if err := s.Validate(); err != nil {
		t.Fatal(err)
	}
	s.Secrets = append(s.Secrets, "palsu")
	if s.Validate() == nil {
		t.Error("tempat rahasia palsu harus ditolak")
	}
}

func TestMarketDiscount(t *testing.T) {
	withNow(t, at(2, 10))
	s := villager()
	s.Gold = 100
	if err := BuyAt(&s, ShopPotion, PotionID, 2); err != nil {
		t.Fatal(err)
	}
	if s.Gold != 100-30*(100-MarketPercent)/100 {
		t.Fatalf("Hari Pasar potongan %d%%: sisa %d", MarketPercent, s.Gold)
	}
}
