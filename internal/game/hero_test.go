package game

import (
	"errors"
	"strings"
	"testing"
)

func TestHeroDefaults(t *testing.T) {
	st := NewState()
	if st.Hero != DefaultHero || st.HeroDef().ID != "ksatria" {
		t.Errorf("pemain baru harus Ksatria: %+v", st.Hero)
	}
	var old State // akun lama tanpa pilihan
	if old.HeroDef().ID != DefaultHero {
		t.Error("akun lama harus memakai pahlawan bawaan")
	}
	seen := map[string]bool{}
	for _, h := range Heroes {
		if h.ID == "" || h.Name == "" || h.Skill1 == "" || h.Skill2 == "" || seen[h.ID] {
			t.Errorf("definisi pahlawan salah: %+v", h)
		}
		seen[h.ID] = true
	}
	if len(Heroes) != 4 {
		t.Errorf("harus ada 4 pahlawan, dapat %d", len(Heroes))
	}
}

func TestSetHero(t *testing.T) {
	st := NewState()
	if err := st.SetHero("pemanah"); err != nil || st.Hero != "pemanah" {
		t.Fatalf("ganti pahlawan: %v %q", err, st.Hero)
	}
	for _, bad := range []string{"", "naga", "KSATRIA"} {
		if err := st.SetHero(bad); !errors.Is(err, ErrUnknownHero) {
			t.Errorf("%q harus ErrUnknownHero, dapat %v", bad, err)
		}
	}
	if st.Hero != "pemanah" {
		t.Error("pilihan gagal tidak boleh mengubah pahlawan")
	}
	st.Hero = "naga"
	if err := st.Validate(); !errors.Is(err, ErrUnknownHero) {
		t.Errorf("Validate harus menolak pahlawan asing, dapat %v", err)
	}
}

func TestSkillNamesFollowHero(t *testing.T) {
	p := newPlayer()
	_ = p.State.SetHero("pendekar_tombak")
	b := battleVs("babi_hutan", 100)
	b.NextEnemyMs = 100_000
	res, err := b.Act(p, ActionSkill1, 0, seq(20, 99))
	if err != nil || !strings.Contains(strings.Join(res.Log, "|"), "Tusukan Kilat") {
		t.Errorf("log skill harus memakai nama pahlawan: %v %v", err, res.Log)
	}
	res, _ = b.Act(p, ActionSkill2, 0, seq())
	if !strings.Contains(strings.Join(res.Log, "|"), "Putaran Tombak") {
		t.Errorf("log skill 2: %v", res.Log)
	}
}
