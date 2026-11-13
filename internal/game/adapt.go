package game

// Adaptive difficulty (v0.78.0, Fase 5 AI hybrid): musuh biasa sedikit menyesuaikan diri dengan hasil
// pertarungan pemain akhir-akhir ini. Hanya HP dan serangan musuh yang berubah, dalam rentang sempit
// (AdaptMin..AdaptMax permil); hadiah (XP, emas, jarahan) TIDAK pernah ikut berubah. Bos, musuh raid, dan
// musuh sasaran cerita tidak pernah disesuaikan, dan tidak ada kemenangan/kekalahan otomatis.
//
// Data tersimpan di State.Adapt (opsional): pemain lama tanpa data mulai dari faktor netral 1000.

const (
	AdaptNeutral    = 1000 // faktor netral (permil): musuh persis seperti data aslinya
	AdaptMin        = 900  // batas bawah: musuh paling lemah 90%
	AdaptMax        = 1150 // batas atas: musuh paling kuat 115%
	AdaptStepUp     = 10   // naik pelan saat pemain terus menang mudah
	AdaptStepDown   = 20   // turun lebih cepat saat pemain sering kalah/kabur
	AdaptDrift      = 5    // tanpa pola jelas, faktor kembali pelan ke netral
	AdaptWindow     = 8    // jumlah hasil terakhir yang diingat
	AdaptMinHistory = 5    // penyesuaian baru dimulai setelah sekian pertarungan
	AdaptEasyHPPct  = 70   // menang dengan HP tersisa >= sekian persen = menang mudah
	AdaptEasyPct    = 75   // naik bila >= sekian persen hasil terakhir menang mudah (dan tanpa kalah/kabur)
	AdaptHardPct    = 50   // turun bila LEBIH DARI sekian persen hasil terakhir kalah (pingsan)
)

// Hasil pertarungan yang dicatat.
const (
	OutcomeEasy = 'E' // menang, HP tersisa banyak
	OutcomeWin  = 'W' // menang dengan susah payah
	OutcomeLose = 'L' // pingsan
	OutcomeFlee = 'F' // kabur (memutus rentetan menang mudah, tetapi tidak menurunkan kesulitan)
)

// Adapt: catatan adaptive difficulty pemain.
type Adapt struct {
	Factor int    `json:"factor,omitempty"` // permil; 0 = netral (AdaptNeutral)
	Recent string `json:"recent,omitempty"` // hasil terakhir (paling lama di depan), maks AdaptWindow huruf
}

// AdaptFactor: faktor kesulitan pemain saat ini (permil), selalu di dalam AdaptMin..AdaptMax.
func (s *State) AdaptFactor() int {
	if s.Adapt == nil || s.Adapt.Factor == 0 {
		return AdaptNeutral
	}
	return min(AdaptMax, max(AdaptMin, s.Adapt.Factor))
}

// adaptive: apakah musuh ini boleh disesuaikan untuk pemain (bukan bos, raid, atau sasaran cerita).
func (s *State) adaptive(e Enemy) bool {
	if e.Boss || e.Raid {
		return false
	}
	if st, ok := s.StoryNow(); ok && st.Kind == StoryKill && st.Enemy == e.ID {
		return false
	}
	return true
}

// adapt menerapkan faktor kesulitan pada HP dan serangan musuh (setelah penguatan tahap/peta).
func (b *Battle) adapt(st State, e Enemy) {
	if !st.adaptive(e) {
		return
	}
	f := st.AdaptFactor()
	if f == AdaptNeutral {
		return
	}
	hp := max(1, b.EnemyMaxHP*f/1000)
	b.EnemyHP, b.EnemyMaxHP = hp, hp
	atk := b.AtkPct
	if atk <= 0 {
		atk = 100
	}
	b.AtkPct = max(1, atk*f/1000)
	b.Adapt = f
}

// recordAdapt mencatat hasil pertarungan melawan e dan menggeser faktor kesulitan sedikit demi sedikit.
func (s *State) recordAdapt(e Enemy, outcome byte) {
	if !s.adaptive(e) {
		return
	}
	if s.Adapt == nil {
		s.Adapt = &Adapt{}
	}
	a := s.Adapt
	a.Recent += string(outcome)
	if len(a.Recent) > AdaptWindow {
		a.Recent = a.Recent[len(a.Recent)-AdaptWindow:]
	}
	f := s.AdaptFactor()
	n := len(a.Recent)
	if n >= AdaptMinHistory {
		easy, hard := 0, 0
		for i := 0; i < n; i++ {
			switch a.Recent[i] {
			case OutcomeEasy:
				easy++
			case OutcomeLose: // kabur TIDAK dihitung: kabur gratis, jadi tidak bisa dipakai untuk melemahkan musuh
				hard++
			}
		}
		switch {
		case hard*100 > n*AdaptHardPct:
			f -= AdaptStepDown
		case hard == 0 && easy*100 >= n*AdaptEasyPct:
			f += AdaptStepUp
		case f > AdaptNeutral:
			f = max(AdaptNeutral, f-AdaptDrift)
		case f < AdaptNeutral:
			f = min(AdaptNeutral, f+AdaptDrift)
		}
	}
	f = min(AdaptMax, max(AdaptMin, f))
	if f == AdaptNeutral {
		a.Factor = 0
	} else {
		a.Factor = f
	}
}

// winOutcome: menang mudah atau susah, dilihat dari HP pemain yang tersisa.
func winOutcome(st *State) byte {
	if st.MaxHP > 0 && st.HP*100 >= st.MaxHP*AdaptEasyHPPct {
		return OutcomeEasy
	}
	return OutcomeWin
}

// valid: data adaptive difficulty yang tersimpan masuk akal (nil = belum ada, sah).
func (a *Adapt) valid() bool {
	if a == nil {
		return true
	}
	if a.Factor != 0 && (a.Factor < AdaptMin || a.Factor > AdaptMax) || len(a.Recent) > AdaptWindow {
		return false
	}
	for i := 0; i < len(a.Recent); i++ {
		switch a.Recent[i] {
		case OutcomeEasy, OutcomeWin, OutcomeLose, OutcomeFlee:
		default:
			return false
		}
	}
	return true
}
