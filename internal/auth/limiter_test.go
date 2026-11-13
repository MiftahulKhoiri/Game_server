package auth

import (
	"fmt"
	"sync"
	"testing"
	"time"
)

// Pembatas percobaan (audit v0.77.0): biaya dan memori terkendali, aman dipakai bersamaan.

type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *fakeClock) add(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

func newTestLimiter(max int, window time.Duration) (*Limiter, *fakeClock) {
	c := &fakeClock{t: time.Unix(1_700_000_000, 0)}
	l := NewLimiter(max, window)
	l.SetClock(c.now)
	return l, c
}

func TestLimiterManyFailuresKeepBoundedHistory(t *testing.T) {
	l, _ := newTestLimiter(5, time.Minute)
	for range 10_000 {
		l.Fail("penebak")
	}
	if _, blocked := l.Blocked("penebak"); !blocked {
		t.Fatal("harus diblokir")
	}
	l.mu.Lock()
	n := len(l.fails["penebak"])
	l.mu.Unlock()
	if n > 5 {
		t.Errorf("riwayat satu kunci harus paling banyak max (5), dapat %d", n)
	}
}

func TestLimiterRecoversAfterWindow(t *testing.T) {
	l, c := newTestLimiter(3, time.Minute)
	for range 3 {
		l.Fail("a")
	}
	wait, blocked := l.Blocked("a")
	if !blocked || wait > time.Minute || wait < time.Second {
		t.Fatalf("diblokir %v, tunggu %v", blocked, wait)
	}
	c.add(61 * time.Second)
	if _, blocked := l.Blocked("a"); blocked {
		t.Fatal("harus pulih setelah window lewat")
	}
	if l.Len() != 0 {
		t.Errorf("kunci kedaluwarsa harus terhapus, sisa %d", l.Len())
	}
}

func TestLimiterManyIdentitiesBoundedMemory(t *testing.T) {
	l, c := newTestLimiter(5, time.Minute)
	l.SetMaxKeys(1000)
	for i := range 50_000 {
		l.Fail(fmt.Sprintf("akun-%d", i))
		if i%5000 == 0 {
			c.add(time.Millisecond)
		}
	}
	if n := l.Len(); n > 1000 {
		t.Fatalf("jumlah kunci harus dibatasi 1000, dapat %d", n)
	}
	// Kunci yang baru saja diblokir tidak ikut terbuang oleh banjir kunci baru selama masih ada yang lebih tua.
	for range 5 {
		l.Fail("korban")
	}
	if _, blocked := l.Blocked("korban"); !blocked {
		t.Fatal("kunci terbaru harus tetap diblokir")
	}
}

func TestLimiterSweepsExpiredEntriesPeriodically(t *testing.T) {
	l, c := newTestLimiter(5, time.Minute)
	for i := range 500 {
		l.Fail(fmt.Sprintf("lama-%d", i))
	}
	c.add(2 * time.Minute) // semuanya kedaluwarsa
	l.Fail("baru")         // kunci baru memicu pembersihan berkala
	if n := l.Len(); n != 1 {
		t.Fatalf("setelah pembersihan harus tinggal 1 kunci, dapat %d", n)
	}
}

func TestLimiterConcurrentAccess(t *testing.T) {
	l, c := newTestLimiter(10, time.Minute)
	var wg sync.WaitGroup
	for g := range 16 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range 500 {
				key := fmt.Sprintf("k-%d", (g*500+i)%300)
				l.Fail(key)
				l.Blocked(key)
				if i%50 == 0 {
					l.Reset(key)
					c.add(time.Millisecond)
				}
			}
		}()
	}
	wg.Wait()
	if l.Len() > 300 {
		t.Errorf("kunci tak terduga: %d", l.Len())
	}
}

func BenchmarkLimiterFailManyLiveKeys(b *testing.B) {
	l := NewLimiter(5, time.Hour)
	for i := range DefaultMaxKeys {
		l.Fail(fmt.Sprintf("hidup-%d", i))
	}
	b.ResetTimer()
	for i := range b.N {
		l.Fail(fmt.Sprintf("baru-%d", i))
	}
}
