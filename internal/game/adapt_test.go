package game

import (
	"encoding/json"
	"strings"
	"testing"
)

// Adaptive difficulty (adapt.go, v0.78.0).

func adaptEnemy(t *testing.T, id string) Enemy {
	t.Helper()
	e, ok := EnemyByID(id)
	if !ok {
		t.Fatalf("musuh %s tidak ada", id)
	}
	return e
}

// feed mencatat rangkaian hasil dan mengembalikan faktor setelah tiap hasil.
func feed(st *State, e Enemy, outcomes string) []int {
	var out []int
	for i := 0; i < len(outcomes); i++ {
		st.recordAdapt(e, outcomes[i])
		out = append(out, st.AdaptFactor())
	}
	return out
}

func adaptedBattle(st State, e Enemy) Battle {
	b := newBattle(e, 0)
	b.strengthen(st, e)
	b.adapt(st, e)
	return b
}

func TestAdaptNewPlayerIsNeutral(t *testing.T) {
	p := newPlayer()
	if f := p.State.AdaptFactor(); f != AdaptNeutral {
		t.Fatalf("pemain baru: faktor %d", f)
	}
	e := adaptEnemy(t, "tikus_sawah")
	b := adaptedBattle(p.State, e)
	if b.Adapt != 0 || b.EnemyMaxHP != e.HP || b.enemyAttack(e) != e.Attack {
		t.Fatalf("pemain baru tidak boleh mengubah musuh: %+v", b)
	}
}

// Pemain lama (JSON tanpa "adapt") tetap sah dan netral; State baru tanpa catatan tidak menulis kunci "adapt".
func TestAdaptOldPlayerCompatible(t *testing.T) {
	raw, _ := json.Marshal(NewState())
	if strings.Contains(string(raw), `"adapt"`) {
		t.Fatalf("state netral menulis adapt: %s", raw)
	}
	var st State
	if err := json.Unmarshal(raw, &st); err != nil {
		t.Fatal(err)
	}
	if err := st.Validate(); err != nil {
		t.Fatalf("state lama tidak sah: %v", err)
	}
	if st.AdaptFactor() != AdaptNeutral {
		t.Fatal("state lama harus netral")
	}
}

func TestAdaptNeedsHistory(t *testing.T) {
	st := NewState()
	e := adaptEnemy(t, "tikus_sawah")
	got := feed(&st, e, "EEEE")
	for i, f := range got {
		if f != AdaptNeutral {
			t.Fatalf("hasil ke-%d sudah menggeser faktor (%d) sebelum %d pertarungan", i+1, f, AdaptMinHistory)
		}
	}
	if f := feed(&st, e, "E")[0]; f != AdaptNeutral+AdaptStepUp {
		t.Fatalf("pertarungan ke-5: faktor %d", f)
	}
}

func TestAdaptVeryStrongPlayerCapped(t *testing.T) {
	st := NewState()
	e := adaptEnemy(t, "tikus_sawah")
	prev := AdaptNeutral
	for _, f := range feed(&st, e, strings.Repeat("E", 60)) {
		if f > AdaptMax || f-prev > AdaptStepUp {
			t.Fatalf("faktor melompat/kelewat batas: %d -> %d", prev, f)
		}
		prev = f
	}
	if prev != AdaptMax {
		t.Fatalf("pemain sangat kuat: faktor %d, mau %d", prev, AdaptMax)
	}
}

func TestAdaptVeryWeakPlayerFloored(t *testing.T) {
	st := NewState()
	e := adaptEnemy(t, "tikus_sawah")
	prev := AdaptNeutral
	for _, f := range feed(&st, e, strings.Repeat("L", 40)) {
		if f < AdaptMin || prev-f > AdaptStepDown {
			t.Fatalf("faktor melompat/kelewat batas: %d -> %d", prev, f)
		}
		prev = f
	}
	if prev != AdaptMin {
		t.Fatalf("pemain sangat lemah: faktor %d, mau %d", prev, AdaptMin)
	}
	b := adaptedBattle(st, e)
	if b.EnemyMaxHP < 1 || b.enemyAttack(e) < 1 {
		t.Fatalf("musuh terlemah tetap harus hidup dan menyerang: %+v", b)
	}
}

// Pemain stabil (menang dengan susah payah): faktor tetap netral, dan faktor yang tadinya naik kembali pelan.
func TestAdaptStablePlayer(t *testing.T) {
	st := NewState()
	e := adaptEnemy(t, "tikus_sawah")
	for _, f := range feed(&st, e, strings.Repeat("W", 20)) {
		if f != AdaptNeutral {
			t.Fatalf("pemain stabil: faktor %d", f)
		}
	}
	st.Adapt = &Adapt{Factor: 1100}
	got := feed(&st, e, strings.Repeat("W", 30))
	if got[len(got)-1] != AdaptNeutral {
		t.Fatalf("faktor tidak kembali ke netral: %v", got)
	}
}

// Menang-kalah bergantian tidak membuat faktor berayun.
func TestAdaptAlternatingResults(t *testing.T) {
	for _, pattern := range []string{"EL", "WL", "EW", "EF"} {
		st := NewState()
		e := adaptEnemy(t, "tikus_sawah")
		for _, f := range feed(&st, e, strings.Repeat(pattern, 15)) {
			if f != AdaptNeutral {
				t.Fatalf("pola %s: faktor %d", pattern, f)
			}
		}
	}
}

// Celah: kabur gratis berkali-kali tidak boleh melemahkan musuh.
func TestAdaptFleeingIsNotAnExploit(t *testing.T) {
	st := NewState()
	e := adaptEnemy(t, "tikus_sawah")
	for _, f := range feed(&st, e, strings.Repeat("F", 30)) {
		if f < AdaptNeutral {
			t.Fatalf("kabur menurunkan kesulitan: %d", f)
		}
	}
}

// Bos, raid, dan sasaran cerita tidak pernah disesuaikan maupun dicatat.
func TestAdaptSkipsBossRaidStory(t *testing.T) {
	st := NewState()
	st.Adapt = &Adapt{Factor: AdaptMax}
	for _, e := range enemies {
		if !e.Boss && !e.Raid {
			continue
		}
		b := adaptedBattle(st, e)
		if b.Adapt != 0 {
			t.Errorf("%s ikut disesuaikan", e.ID)
		}
		before := *st.Adapt
		st.recordAdapt(e, OutcomeLose)
		if *st.Adapt != before {
			t.Errorf("%s ikut dicatat", e.ID)
		}
	}
	if s, ok := st.StoryNow(); ok && s.Kind == StoryKill {
		e := adaptEnemy(t, s.Enemy)
		if b := adaptedBattle(st, e); b.Adapt != 0 {
			t.Errorf("sasaran cerita %s ikut disesuaikan", e.ID)
		}
	}
}

// Hanya HP dan serangan musuh yang berubah; XP dan emas tetap sama persis.
func TestAdaptKeepsRewards(t *testing.T) {
	e := adaptEnemy(t, "tikus_sawah")
	e.DropPercent = 0
	none := RandFunc(func(int) int { return 99 })
	var got []Rewards
	for _, f := range []int{AdaptMin, 0, AdaptMax} {
		p := newPlayer()
		if f != 0 {
			p.State.Adapt = &Adapt{Factor: f}
		}
		b := adaptedBattle(p.State, e)
		if f == AdaptMax && (b.EnemyMaxHP <= e.HP && e.HP >= 10) {
			t.Fatalf("faktor %d tidak menaikkan HP: %d", f, b.EnemyMaxHP)
		}
		var res Result
		b.win(p, e, none, &res)
		got = append(got, *res.Rewards)
	}
	if got[0].XP != got[1].XP || got[1].XP != got[2].XP || got[0].Gold != got[1].Gold || got[1].Gold != got[2].Gold {
		t.Fatalf("hadiah ikut berubah: %+v", got)
	}
}

// Faktor bekerja sama untuk pemain tanpa pendamping maupun dengan party penuh dan prajurit maksimal.
func TestAdaptSamePartyOrSolo(t *testing.T) {
	e := adaptEnemy(t, "beruang_hutan")
	solo := NewState()
	solo.Adapt = &Adapt{Factor: 1100}
	full := solo
	full.Party = []string{"ksatria", "pemanah", "penyihir"}[:MaxParty]
	full.Soldiers = MaxSoldiers
	a, b := adaptedBattle(solo, e), adaptedBattle(full, e)
	if a.EnemyMaxHP != b.EnemyMaxHP || a.AtkPct != b.AtkPct {
		t.Fatalf("solo %+v vs party %+v", a, b)
	}
	if a.EnemyMaxHP != e.HP*1100/1000 || a.AtkPct != 110 {
		t.Fatalf("faktor 1100: HP %d (asli %d), serangan %d%%", a.EnemyMaxHP, e.HP, a.AtkPct)
	}
}

func TestAdaptValidate(t *testing.T) {
	for _, a := range []*Adapt{{Factor: 2000}, {Factor: 100}, {Recent: "EEEEEEEEE"}, {Recent: "X"}} {
		st := NewState()
		st.Adapt = a
		if st.Validate() == nil {
			t.Errorf("%+v dianggap sah", *a)
		}
	}
	st := NewState()
	st.Adapt = &Adapt{Factor: 950, Recent: "EWLF"}
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
}

// Kemenangan/kekalahan nyata dari pertarungan ikut tercatat.
func TestAdaptRecordedFromBattles(t *testing.T) {
	p := newPlayer()
	p.State.HP, p.State.MaxHP = 1000, 1000
	b := battleVs("tikus_sawah", 1)
	if _, err := act(b, p, ActionAttack, seq(0, 0, 99, 99)); err != nil {
		t.Fatal(err)
	}
	if p.State.Adapt == nil || p.State.Adapt.Recent != "E" {
		t.Fatalf("kemenangan tidak tercatat: %+v", p.State.Adapt)
	}
}
