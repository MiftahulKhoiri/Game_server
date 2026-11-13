package auth

import (
	"fmt"
	"sync"
	"testing"
	"time"
)

func TestBucketBurstAndRefill(t *testing.T) {
	c := &fakeClock{t: time.Unix(1_700_000_000, 0)}
	b := NewBucket(10, 20)
	b.SetClock(c.now)
	for i := range 20 {
		if _, ok := b.Allow("ip"); !ok {
			t.Fatalf("permintaan ke-%d dalam burst ditolak", i+1)
		}
	}
	wait, ok := b.Allow("ip")
	if ok || wait <= 0 || wait > 200*time.Millisecond {
		t.Fatalf("melebihi burst: ok=%v tunggu=%v", ok, wait)
	}
	c.add(500 * time.Millisecond) // terisi 5 token
	n := 0
	for {
		if _, ok := b.Allow("ip"); !ok {
			break
		}
		n++
	}
	if n != 5 {
		t.Fatalf("setelah 0,5 detik harus 5 token, dapat %d", n)
	}
	// Kunci lain tidak terpengaruh.
	if _, ok := b.Allow("ip-lain"); !ok {
		t.Fatal("kunci lain ikut diblokir")
	}
}

func TestBucketSteadyNormalUseNeverLimited(t *testing.T) {
	c := &fakeClock{t: time.Unix(1_700_000_000, 0)}
	b := NewBucket(20, 60)
	b.SetClock(c.now)
	for i := range 10_000 { // 5 permintaan/detik selama 2.000 detik
		if _, ok := b.Allow("pemain"); !ok {
			t.Fatalf("pemakaian normal ditolak pada permintaan %d", i)
		}
		c.add(200 * time.Millisecond)
	}
}

func TestBucketBoundedKeysAndSweep(t *testing.T) {
	c := &fakeClock{t: time.Unix(1_700_000_000, 0)}
	b := NewBucket(10, 20)
	b.SetClock(c.now)
	b.SetMaxKeys(500)
	for i := range 20_000 {
		b.Allow(fmt.Sprintf("ip-%d", i))
	}
	if b.Len() > 500 {
		t.Fatalf("jumlah kunci harus dibatasi: %d", b.Len())
	}
	c.add(time.Minute) // semua ember penuh lagi -> boleh dibuang
	b.Allow("baru")
	if b.Len() != 1 {
		t.Fatalf("kunci tidak aktif harus dibersihkan, sisa %d", b.Len())
	}
}

func TestBucketConcurrent(t *testing.T) {
	b := NewBucket(1000, 100)
	var wg sync.WaitGroup
	var mu sync.Mutex
	allowed := 0
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range 100 {
				if _, ok := b.Allow("sama"); ok {
					mu.Lock()
					allowed++
					mu.Unlock()
				}
			}
		}()
	}
	wg.Wait()
	if allowed < 100 || allowed > 800 {
		t.Fatalf("jumlah lolos tidak masuk akal: %d", allowed)
	}
}
