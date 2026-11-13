package game

import (
	"container/heap"
	"math"
	"strings"
	"sync"
)

// Jarak jalan kaki di dalam peta (v0.77.0, sisa audit G-2): server kini mengenal bentuk petak (tiles_gen.go, dibuat
// dari maps.gd), jadi jarak gerakan dihitung menyusuri petak yang bisa diinjak, bukan garis lurus yang menembus
// tembok, air, atau lava. Jalur 8 arah (diagonal = √2) dan boleh memotong sudut, jadi selalu sedikit lebih
// pendek atau sama dengan jalan pemain sungguhan (aman untuk pemain jujur). NPC dan peti tidak dihitung
// sebagai penghalang.

// Walkable: petak (x, y) di peta bisa diinjak? false untuk peta tanpa data petak atau di luar peta.
func Walkable(mapID string, x, y int) bool {
	rows, ok := mapRows[mapID]
	if !ok || y < 0 || y >= len(rows) || x < 0 || x >= len(rows[y]) {
		return false
	}
	return strings.IndexByte(walkableTiles, rows[y][x]) >= 0
}

var inf32 = float32(math.Inf(1))

// distField: jarak jalan terpendek dari petak (sx, sy) ke setiap petak di peta (indeks y*lebar+x); +Inf bila tidak
// terjangkau. nil bila peta tidak punya data petak atau petak awal tidak bisa diinjak.
func distField(mapID string, sx, sy int) []float32 {
	rows, ok := mapRows[mapID]
	if !ok || !Walkable(mapID, sx, sy) {
		return nil
	}
	h, w := len(rows), len(rows[0])
	d := make([]float32, w*h)
	for i := range d {
		d[i] = inf32
	}
	start := sy*w + sx
	d[start] = 0
	pq := &nodeHeap{{start, 0}}
	for pq.Len() > 0 {
		n := heap.Pop(pq).(node)
		if n.d > d[n.i] {
			continue
		}
		x, y := n.i%w, n.i/w
		for _, s := range steps8 {
			nx, ny := x+s.dx, y+s.dy
			if !Walkable(mapID, nx, ny) {
				continue
			}
			j := ny*w + nx
			if nd := n.d + s.cost; nd < d[j] {
				d[j] = nd
				heap.Push(pq, node{j, nd})
			}
		}
	}
	return d
}

var steps8 = []struct {
	dx, dy int
	cost   float32
}{{1, 0, 1}, {-1, 0, 1}, {0, 1, 1}, {0, -1, 1}, {1, 1, math.Sqrt2}, {1, -1, math.Sqrt2}, {-1, 1, math.Sqrt2}, {-1, -1, math.Sqrt2}}

type node struct {
	i int
	d float32
}

type nodeHeap []node

func (h nodeHeap) Len() int           { return len(h) }
func (h nodeHeap) Less(i, j int) bool { return h[i].d < h[j].d }
func (h nodeHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *nodeHeap) Push(x any)        { *h = append(*h, x.(node)) }
func (h *nodeHeap) Pop() any {
	old := *h
	n := old[len(old)-1]
	*h = old[:len(old)-1]
	return n
}

// fieldCache: medan jarak dari petak tujuan pintu (selalu sama), dihitung sekali per petak.
var fieldCache sync.Map // kunci "peta|x|y" -> []float32

func cachedField(mapID string, x, y int) []float32 {
	key := mapID + "|" + itoa(x) + "|" + itoa(y)
	if v, ok := fieldCache.Load(key); ok {
		return v.([]float32)
	}
	f := distField(mapID, x, y)
	fieldCache.Store(key, f)
	return f
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	neg := n < 0
	if neg {
		n = -n
	}
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

// nearestWalkable: petak yang bisa diinjak paling dekat ke (x, y) dalam jarak r petak (posisi tersimpan lama
// mungkin berada di petak yang kini terhalang). ok=false bila tidak ada.
func nearestWalkable(mapID string, x, y, r int) (int, int, bool) {
	if Walkable(mapID, x, y) {
		return x, y, true
	}
	for k := 1; k <= r; k++ {
		for dy := -k; dy <= k; dy++ {
			for dx := -k; dx <= k; dx++ {
				if max(abs(dx), abs(dy)) == k && Walkable(mapID, x+dx, y+dy) {
					return x + dx, y + dy, true
				}
			}
		}
	}
	return 0, 0, false
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

// pathLen: jarak jalan dari medan f ke petak (x, y) di peta; +Inf bila tidak terjangkau.
func pathLen(mapID string, f []float32, x, y int) float64 {
	rows := mapRows[mapID]
	if f == nil || y < 0 || y >= len(rows) || x < 0 || x >= len(rows[0]) {
		return math.Inf(1)
	}
	return float64(f[y*len(rows[0])+x])
}
