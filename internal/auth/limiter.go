package auth

import (
	"slices"
	"sync"
	"time"
)

// Limiter membatasi percobaan yang gagal (login, daftar, ganti sandi): setelah max kegagalan dalam window,
// kunci itu ditolak sampai kegagalan tertua lewat dari window. Hanya di memori; server restart
// mengosongkannya. Cukup untuk menghalangi tebak-sandi, bukan pertahanan penuh.
//
// Biaya terkendali (audit v0.77.0):
//   - tiap kunci menyimpan paling banyak max cap waktu (bukan daftar yang terus memanjang);
//   - pembersihan kunci kedaluwarsa berjalan paling sering sekali per sweepEvery, bukan pada setiap
//     kegagalan, jadi beban CPU tidak berulang walau jumlah kunci tetap tinggi;
//   - jumlah kunci dibatasi maxKeys; bila tetap penuh setelah dibersihkan, 10% kunci yang paling lama
//     tidak gagal dibuang sekaligus (biaya pengurutan dibagi ke banyak kegagalan berikutnya).
type Limiter struct {
	mu        sync.Mutex
	max       int
	window    time.Duration
	now       func() time.Time
	fails     map[string][]time.Time
	maxKeys   int
	lastSweep time.Time
}

// DefaultMaxKeys: batas jumlah kunci yang diingat satu pembatas (± beberapa MB paling banyak).
const DefaultMaxKeys = 20_000

// NewLimiter membuat pembatas: max kegagalan per window untuk tiap kunci.
func NewLimiter(max int, window time.Duration) *Limiter {
	return &Limiter{max: max, window: window, now: time.Now, fails: map[string][]time.Time{}, maxKeys: DefaultMaxKeys}
}

// SetClock mengganti jam (untuk tes).
func (l *Limiter) SetClock(now func() time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.now = now
}

// SetMaxKeys mengganti batas jumlah kunci (untuk tes).
func (l *Limiter) SetMaxKeys(n int) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.maxKeys = max(1, n)
}

// Len: jumlah kunci yang sedang diingat.
func (l *Limiter) Len() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.fails)
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
	now := l.now()
	recent := l.prune(key)
	if recent == nil {
		l.makeRoom(now)
	}
	recent = append(recent, now)
	if len(recent) > l.max { // yang lebih tua dari max kegagalan terakhir tidak memengaruhi blokir
		recent = slices.Clone(recent[len(recent)-l.max:])
	}
	l.fails[key] = recent
}

// Reset menghapus catatan kegagalan kunci (dipanggil saat login berhasil).
func (l *Limiter) Reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.fails, key)
}

// sweepEvery: jarak minimal antar-pembersihan menyeluruh.
func (l *Limiter) sweepEvery() time.Duration { return max(time.Second, l.window/4) }

// makeRoom dipanggil sebelum kunci BARU ditambahkan. Pemanggil memegang mutex.
func (l *Limiter) makeRoom(now time.Time) {
	if now.Sub(l.lastSweep) >= l.sweepEvery() {
		l.lastSweep = now
		cutoff := now.Add(-l.window)
		for k, ts := range l.fails {
			if !ts[len(ts)-1].After(cutoff) {
				delete(l.fails, k)
			}
		}
	}
	if len(l.fails) < l.maxKeys {
		return
	}
	// Masih penuh oleh kunci yang aktif: buang 10% yang kegagalan terakhirnya paling lama.
	type entry struct {
		k    string
		last time.Time
	}
	all := make([]entry, 0, len(l.fails))
	for k, ts := range l.fails {
		all = append(all, entry{k, ts[len(ts)-1]})
	}
	slices.SortFunc(all, func(a, b entry) int { return a.last.Compare(b.last) })
	drop := max(1, len(all)/10)
	for _, e := range all[:drop] {
		delete(l.fails, e.k)
	}
}

// prune membuang kegagalan yang sudah lewat window. Pemanggil memegang kunci mutex.
func (l *Limiter) prune(key string) []time.Time {
	old, ok := l.fails[key]
	if !ok {
		return nil
	}
	cutoff := l.now().Add(-l.window)
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
