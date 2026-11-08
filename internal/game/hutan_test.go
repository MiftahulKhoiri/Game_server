package game

import (
	"errors"
	"strings"
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

func TestHutanProgression(t *testing.T) {
	p := newPlayer()
	st := &p.State
	st.Map, st.X, st.Y = MapHutanLebat, 22, 5
	for wave := 0; wave < HutanWaves; wave++ {
		// Belum 100 binatang: singgasana belum membuka bos.
		st.X, st.Y = HutanBossX, HutanBossY
		if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrBossNotReady) {
			t.Fatalf("wave %d: bos terlalu cepat muncul: %v", wave, err)
		}
		for i := 0; i < HutanBeasts; i++ {
			kalahkan(t, p, "kancil_hutan")
		}
		if st.Hutan.Wave != wave || st.Hutan.Kills != HutanBeasts || !st.Hutan.BossReady() {
			t.Fatalf("wave %d: kemajuan salah %+v", wave, st.Hutan)
		}
		// Binatang tambahan tidak melewati 100.
		kalahkan(t, p, "kancil_hutan")
		if st.Hutan.Kills != HutanBeasts {
			t.Fatalf("kills melewati batas: %+v", st.Hutan)
		}
		b, err := StartBossBattle(p, 0)
		if err != nil || !strings.HasPrefix(b.EnemyID, "goblin_hutan_") || b.EnemyID != st.Hutan.BossID() {
			t.Fatalf("wave %d: bos salah: %+v %v", wave, b, err)
		}
		res := kalahkan(t, p, b.EnemyID)
		if st.Hutan.Wave != wave+1 || st.Hutan.Kills != 0 {
			t.Fatalf("setelah bos %d: %+v", wave+1, st.Hutan)
		}
		if len(res.Log) == 0 {
			t.Error("kemenangan bos harus ada log")
		}
	}
	if !st.Hutan.Done() {
		t.Fatalf("harus selesai: %+v", st.Hutan)
	}
	if _, err := StartBossBattle(p, 0); !errors.Is(err, ErrBossNotReady) {
		t.Errorf("setelah selesai tidak ada bos lagi: %v", err)
	}
	// Binatang setelah selesai tidak mengubah kemajuan.
	kalahkan(t, p, "kancil_hutan")
	if st.Hutan != (HutanProgress{Wave: HutanWaves}) {
		t.Errorf("kemajuan berubah setelah selesai: %+v", st.Hutan)
	}
	if err := st.Validate(); err != nil {
		t.Errorf("state sah ditolak: %v", err)
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
