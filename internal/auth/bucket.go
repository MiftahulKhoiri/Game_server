package auth

import (
	"slices"
	"sync"
	"time"
)

// Bucket adalah pembatas laju "ember token" per kunci (IP atau pemain): tiap kunci boleh `burst` permintaan
// sekaligus, lalu terisi lagi `rate` permintaan per detik. Hanya di memori. Dipakai untuk menahan spam
// permintaan (audit v0.77.0 no. 20); batasnya jauh di atas pemakaian klien normal (±1-3 permintaan/detik).
//
// Biaya terkendali seperti Limiter: kunci yang sudah penuh lagi (tidak aktif) dibuang saat pembersihan
// berkala, dan jumlah kunci dibatasi maxKeys.
type Bucket struct {
	mu        sync.Mutex
	rate      float64 // token per detik
	burst     float64
	now       func() time.Time
	keys      map[string]*bucketState
	maxKeys   int
	lastSweep time.Time
}

type bucketState struct {
	tokens float64
	last   time.Time
}

// NewBucket membuat pembatas: rate permintaan/detik, paling banyak burst sekaligus.
func NewBucket(rate float64, burst int) *Bucket {
	return &Bucket{rate: rate, burst: float64(burst), now: time.Now, keys: map[string]*bucketState{}, maxKeys: DefaultMaxKeys}
}

// SetClock mengganti jam (untuk tes).
func (b *Bucket) SetClock(now func() time.Time) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.now = now
}

// SetMaxKeys mengganti batas jumlah kunci (untuk tes).
func (b *Bucket) SetMaxKeys(n int) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.maxKeys = max(1, n)
}

// Len: jumlah kunci yang sedang diingat.
func (b *Bucket) Len() int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.keys)
}

// Allow mengambil satu token untuk kunci. false berarti terlalu cepat; wait = perkiraan lama menunggu.
func (b *Bucket) Allow(key string) (wait time.Duration, ok bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := b.now()
	st, found := b.keys[key]
	if !found {
		b.makeRoom(now)
		st = &bucketState{tokens: b.burst, last: now}
		b.keys[key] = st
	}
	if el := now.Sub(st.last).Seconds(); el > 0 {
		st.tokens = min(b.burst, st.tokens+el*b.rate)
	}
	st.last = now
	if st.tokens >= 1 {
		st.tokens--
		return 0, true
	}
	return time.Duration((1 - st.tokens) / b.rate * float64(time.Second)), false
}

// fullAfter: lama ember kosong terisi penuh lagi (kunci yang tidak aktif selama ini boleh dibuang).
func (b *Bucket) fullAfter() time.Duration {
	return time.Duration(b.burst/b.rate*float64(time.Second)) + time.Second
}

// makeRoom dipanggil sebelum kunci BARU ditambahkan. Pemanggil memegang mutex.
func (b *Bucket) makeRoom(now time.Time) {
	if every := max(time.Second, b.fullAfter()); now.Sub(b.lastSweep) >= every {
		b.lastSweep = now
		for k, st := range b.keys {
			if now.Sub(st.last) >= b.fullAfter() {
				delete(b.keys, k)
			}
		}
	}
	if len(b.keys) < b.maxKeys {
		return
	}
	type entry struct {
		k    string
		last time.Time
	}
	all := make([]entry, 0, len(b.keys))
	for k, st := range b.keys {
		all = append(all, entry{k, st.last})
	}
	slices.SortFunc(all, func(x, y entry) int { return x.last.Compare(y.last) })
	for _, e := range all[:max(1, len(all)/10)] {
		delete(b.keys, e.k)
	}
}
