package auth

import (
	"sync"
	"time"
)

// Limiter membatasi percobaan login yang gagal: setelah max kegagalan dalam window,
// kunci itu ditolak sampai kegagalan tertua lewat dari window. Hanya di memori; server
// restart mengosongkannya. Cukup untuk menghalangi tebak-sandi, bukan pertahanan penuh.
type Limiter struct {
	mu     sync.Mutex
	max    int
	window time.Duration
	now    func() time.Time
	fails  map[string][]time.Time
}

// NewLimiter membuat pembatas: max kegagalan per window untuk tiap kunci.
func NewLimiter(max int, window time.Duration) *Limiter {
	return &Limiter{max: max, window: window, now: time.Now, fails: map[string][]time.Time{}}
}

// SetClock mengganti jam (untuk tes).
func (l *Limiter) SetClock(now func() time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.now = now
}

// Blocked melaporkan apakah kunci sedang diblokir, dan berapa lama lagi harus menunggu.
func (l *Limiter) Blocked(key string) (time.Duration, bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	recent := l.prune(key)
	if len(recent) < l.max {
		return 0, false
	}
	wait := recent[0].Add(l.window).Sub(l.now())
	if wait < time.Second {
		wait = time.Second
	}
	return wait, true
}

// Fail mencatat satu kegagalan untuk kunci.
func (l *Limiter) Fail(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	recent := l.prune(key)
	l.fails[key] = append(recent, l.now())
	if len(l.fails) > 10_000 { // cegah memori membengkak
		for k := range l.fails {
			if len(l.prune(k)) == 0 {
				delete(l.fails, k)
			}
		}
	}
}

// Reset menghapus catatan kegagalan kunci (dipanggil saat login berhasil).
func (l *Limiter) Reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.fails, key)
}

// prune membuang kegagalan yang sudah lewat window. Pemanggil memegang kunci mutex.
func (l *Limiter) prune(key string) []time.Time {
	cutoff := l.now().Add(-l.window)
	old := l.fails[key]
	i := 0
	for i < len(old) && !old[i].After(cutoff) {
		i++
	}
	recent := old[i:]
	if len(recent) == 0 {
		delete(l.fails, key)
		return nil
	}
	l.fails[key] = recent
	return recent
}
