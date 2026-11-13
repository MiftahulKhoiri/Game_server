package game

import (
	"bufio"
	"errors"
	"math"
	"os"
	"reflect"
	"regexp"
	"strconv"
	"testing"

	"github.com/MiftahulKhoiri/Game_server/internal/mapsrc"
)

func posed(mapID string, x, y int, poseMs int64) State {
	st := NewState()
	st.Map, st.X, st.Y = mapID, x, y
	st.PlaceAtTileCenter()
	st.PoseMs = poseMs
	return st
}

// near: pose di tengah petak yang bisa diinjak terdekat ke (x, y).
func near(mapID string, x, y int) Pose {
	nx, ny, ok := nearestWalkable(mapID, x, y, 40)
	if !ok {
		panic("tidak ada petak yang bisa diinjak di dekat sana")
	}
	return Pose{Map: mapID, X: nx, Y: ny, FX: float64(nx) + 0.5, FZ: float64(ny) + 0.5}
}

func pose(t *testing.T, mapID string, fx, fz float64) Pose {
	t.Helper()
	p, ok := NormalizePose(Pose{Map: mapID, X: int(math.Floor(fx)), Y: int(math.Floor(fz)), FX: fx, FZ: fz})
	if !ok {
		t.Fatalf("pose tidak sah: %s %.1f %.1f", mapID, fx, fz)
	}
	return p
}

func TestMoveToSpeedLimit(t *testing.T) {
	const start = 1_000_000
	cases := []struct {
		name    string
		to      Pose
		afterMs int64
		want    error
	}{
		{"diam di tempat", near(MapDesaAwal, 5, 5), 0, nil},
		{"langkah kecil tanpa jeda (dalam kelonggaran)", near(MapDesaAwal, 10, 5), 0, nil},
		{"berjalan 4,5 petak/detik selama 10 detik", near(MapDesaAwal, 50, 5), 10_000, nil},
		{"teleport 70 petak dalam 1 detik", near(MapDesaAwal, 75, 5), 1_000, ErrMoveTooFar},
		{"teleport ke ujung peta tanpa jeda", near(MapDesaAwal, 84, 49), 0, ErrMoveTooFar},
		{"jam mundur dianggap tanpa jeda", near(MapDesaAwal, 40, 5), -5_000, ErrMoveTooFar},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			st := posed(MapDesaAwal, 5, 5, start)
			before := st
			err := st.MoveTo(c.to, start+c.afterMs)
			if !errors.Is(err, c.want) {
				t.Fatalf("err = %v, mau %v", err, c.want)
			}
			if err != nil && (st.Map != before.Map || st.FX != before.FX || st.FZ != before.FZ || st.PoseMs != before.PoseMs) {
				t.Errorf("ditolak tetapi posisi berubah: %+v", st)
			}
			if err == nil && (st.FX != c.to.FX || st.PoseMs != start+c.afterMs) {
				t.Errorf("posisi/cap waktu tidak diperbarui: fx=%v pose_ms=%d", st.FX, st.PoseMs)
			}
		})
	}
}

func TestMoveToThroughDoors(t *testing.T) {
	const start = 5_000_000
	// Di depan gerbang selatan desa: menyeberang ke Perbatasan sah.
	st := posed(MapDesaAwal, 22, 48, start)
	if err := st.MoveTo(pose(t, MapPerbatasan, 22.5, 2.5), start+1_000); err != nil {
		t.Fatalf("lewat gerbang desa: %v", err)
	}
	if len(st.Visited) == 0 || st.Visited[len(st.Visited)-1] != MapPerbatasan {
		t.Errorf("kunjungan tidak tercatat: %v", st.Visited)
	}
	// Dari tengah desa langsung ke Perbatasan dalam sekejap: terlalu jauh.
	st = posed(MapDesaAwal, 5, 5, start)
	if err := st.MoveTo(pose(t, MapPerbatasan, 22.5, 2.5), start+500); !errors.Is(err, ErrMoveTooFar) {
		t.Fatalf("pindah peta dari jauh: %v", err)
	}
	// Peta yang tidak berpintu ke desa (Gua Batu): tetap tidak bisa dicapai walau sudah lama (gerbang terkunci).
	st = posed(MapDesaAwal, 5, 5, start)
	if err := st.MoveTo(pose(t, MapGuaBatu, 7.5, 14.5), start+3_600_000); !errors.Is(err, ErrMapLocked) {
		t.Fatalf("ke Benteng Orc lewat gerbang terkunci: %v", err)
	}
	// Banyak peta sekaligus (desa -> perbatasan -> hutan) sah bila waktunya cukup.
	st = posed(MapDesaAwal, 22, 47, start)
	if err := st.MoveTo(pose(t, MapHutanLebat, 22.5, 3.5), start+60_000); err != nil {
		t.Fatalf("desa ke hutan dalam semenit: %v", err)
	}
}

func TestMoveToLockedGates(t *testing.T) {
	const start = 9_000_000
	hour := int64(3_600_000)

	// Gerbang Gua Goblin terkunci sampai ketiga bos hutan kalah.
	st := posed(MapHutanLebat, 146, 48, start)
	if err := st.MoveTo(pose(t, MapGuaGoblin, 30.5, 1.5), start+hour); !errors.Is(err, ErrMapLocked) {
		t.Fatalf("gerbang gua sebelum bos kalah: %v", err)
	}
	st.Hutan.Wave = HutanWaves
	if err := st.MoveTo(pose(t, MapGuaGoblin, 30.5, 1.5), start+hour); err != nil {
		t.Fatalf("gerbang gua sesudah bos kalah: %v", err)
	}

	// Gerbang cerita ke Istana Kegelapan (langkah 9) dan Ruang Takhta (langkah 10).
	st = posed(MapGuaBatu, 7, 18, start)
	st.Story = 8
	if err := st.MoveTo(pose(t, MapIstana, 15.5, 1.5), start+hour); !errors.Is(err, ErrMapLocked) {
		t.Fatalf("istana sebelum langkah 9: %v", err)
	}
	st.Story = 9
	if err := st.MoveTo(pose(t, MapIstana, 15.5, 24.5), start+hour); err != nil {
		t.Fatalf("istana langkah 9: %v", err)
	}
	if err := st.MoveTo(pose(t, MapTakhta, 10.5, 1.5), start+2*hour); !errors.Is(err, ErrMapLocked) {
		t.Fatalf("ruang takhta sebelum langkah 10: %v", err)
	}
	// Pemain lama yang sudah pernah sampai di ruang takhta tidak dikunci setelah pembaruan.
	st.Visited = append(st.Visited, MapTakhta)
	if err := st.MoveTo(pose(t, MapTakhta, 10.5, 1.5), start+2*hour); err != nil {
		t.Fatalf("ruang takhta pemain lama: %v", err)
	}

	// Rumah pemain hanya untuk pemiliknya.
	st = posed(MapDesaAwal, 15, 40, start)
	if err := st.MoveTo(pose(t, MapRumahPemain, 4.5, 6.5), start+hour); !errors.Is(err, ErrHouseLocked) {
		t.Fatalf("rumah orang: %v", err)
	}
	st.House = true
	if err := st.MoveTo(pose(t, MapRumahPemain, 4.5, 6.5), start+hour); err != nil {
		t.Fatalf("rumah sendiri: %v", err)
	}
}

func TestMoveToLegacyOrBrokenState(t *testing.T) {
	// Posisi tersimpan rusak (peta tidak dikenal): dianggap dari titik awal desa.
	st := posed(MapDesaAwal, 5, 5, 1_000)
	st.Map = "peta_lama"
	if err := st.MoveTo(pose(t, MapDesaAwal, 6.5, 5.5), 1_000); err != nil {
		t.Fatalf("dekat titik awal: %v", err)
	}
	st = posed(MapDesaAwal, 5, 5, 1_000)
	st.Map = "peta_lama"
	if err := st.MoveTo(pose(t, MapDesaAwal, 80.5, 45.5), 1_000); !errors.Is(err, ErrMoveTooFar) {
		t.Fatalf("jauh dari titik awal: %v", err)
	}
}

// Setiap pintu harus berada di dalam petanya dan tujuannya di dalam peta tujuan (salah ketik = pemain terkunci).
func TestDoorsInsideMaps(t *testing.T) {
	for _, d := range Doors {
		if !ValidPosition(d.Map, d.X, d.Y) || !ValidPosition(d.To, d.AtX, d.AtY) {
			t.Errorf("pintu tidak sah: %+v", d)
		}
	}
	// Setiap peta yang dikenal bisa dicapai dari desa bila semua gerbang terbuka.
	st := NewState()
	st.House, st.Story, st.Hutan.Wave = true, StoryEnd, HutanWaves
	for _, tr := range Trials {
		st.setTrial(tr.Map, HutanProgress{Wave: HutanWaves})
	}
	for id, m := range worldMaps {
		x, y, ok := nearestWalkable(id, m.Width/2, m.Height/2, 60)
		if !ok {
			t.Errorf("peta %s tanpa petak yang bisa diinjak", id)
			continue
		}
		c := st.TravelCost(MapDesaAwal, 5.5, 5.5, id, float64(x)+0.5, float64(y)+0.5)
		if math.IsInf(c, 1) {
			t.Errorf("peta %s tidak terjangkau dari desa", id)
		}
	}
}

// Daftar pintu server harus sama persis dengan EXITS di klien; kalau tidak, pemain jujur bisa ditolak saat
// melewati pintu baru (atau pintu lama yang sudah dihapus masih bisa dipakai).
func TestDoorsMatchClient(t *testing.T) {
	f, err := os.Open("../../client/scripts/maps.gd")
	if err != nil {
		t.Skip("klien tidak ada:", err)
	}
	defer f.Close()
	head := regexp.MustCompile(`^\t"([a-z_]+)": \[`)
	exit := regexp.MustCompile(`\{"pos": Vector2i\((\d+), (\d+)\), "to": "([a-z_]+)", "at": Vector2i\((\d+), (\d+)\)\}`)
	var client []Door
	in, cur := false, ""
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case line == "const EXITS := {":
			in = true
		case in && line == "}":
			in = false
		case in:
			if m := head.FindStringSubmatch(line); m != nil {
				cur = m[1]
			}
			for _, m := range exit.FindAllStringSubmatch(line, -1) {
				n := func(i int) int { v, _ := strconv.Atoi(m[i]); return v }
				client = append(client, Door{Map: cur, X: n(1), Y: n(2), To: m[3], AtX: n(4), AtY: n(5)})
			}
		}
	}
	if len(client) == 0 {
		t.Fatal("EXITS di maps.gd tidak terbaca")
	}
	if len(client) != len(Doors) {
		t.Fatalf("jumlah pintu klien %d, server %d", len(client), len(Doors))
	}
	for i := range client {
		if client[i] != Doors[i] {
			t.Errorf("pintu ke-%d beda: klien %+v, server %+v", i, client[i], Doors[i])
		}
	}
}

// Celah tembus tembok (audit G-2): dua petak yang berdekatan secara garis lurus tetapi terpisah tembok/lava
// tidak bisa dilompati, padahal jarak lurusnya masih di bawah batas waktu.
func TestMoveToRespectsWalls(t *testing.T) {
	m := MapGunungBatu // banyak lorong buntu dan aliran lava
	rows := mapRows[m]
	var from, to Pose
	found := false
	for y := 0; y < len(rows) && !found; y++ {
		for x := 0; x < len(rows[0]) && !found; x++ {
			if !Walkable(m, x, y) {
				continue
			}
			f := distField(m, x, y)
			for dy := -4; dy <= 4 && !found; dy++ {
				for dx := -4; dx <= 4 && !found; dx++ {
					tx, ty := x+dx, y+dy
					if Walkable(m, tx, ty) && pathLen(m, f, tx, ty) > 60 {
						from, to = near(m, x, y), near(m, tx, ty)
						found = true
					}
				}
			}
		}
	}
	if !found {
		t.Fatal("tidak ada pasangan petak bertembok di peta uji")
	}
	st := posed(m, from.X, from.Y, 1_000_000)
	st.Hutan.Wave = HutanWaves
	// 3 detik: garis lurus (< 6 petak) jauh di bawah batas 35 petak, tetapi jalan memutar > 60 petak.
	if err := st.MoveTo(to, 1_003_000); !errors.Is(err, ErrMoveTooFar) {
		t.Fatalf("melompati tembok dari %v ke %v: %v", from, to, err)
	}
	// Berdiri di dalam tembok/air/lava ditolak.
	for y := range rows {
		for x := range rows[0] {
			if !Walkable(m, x, y) {
				st := posed(m, from.X, from.Y, 1_000_000)
				if err := st.MoveTo(Pose{Map: m, X: x, Y: y, FX: float64(x) + 0.5, FZ: float64(y) + 0.5}, 9_000_000); !errors.Is(err, ErrMoveBlocked) {
					t.Fatalf("petak terhalang (%d,%d): %v", x, y, err)
				}
				return
			}
		}
	}
}

// Setiap pintu bisa diinjak dan petak tujuannya punya tempat berdiri di dekatnya (data peta & pintu konsisten).
func TestDoorTilesWalkable(t *testing.T) {
	for _, d := range Doors {
		if !Walkable(d.Map, d.X, d.Y) {
			t.Errorf("petak pintu tidak bisa diinjak: %+v", d)
		}
		if _, _, ok := nearestWalkable(d.To, d.AtX, d.AtY, int(arriveSlack)); !ok {
			t.Errorf("tujuan pintu tanpa tempat berdiri: %+v", d)
		}
	}
	// Semua peta yang dikenal server punya data petak dengan ukuran yang sama.
	for id, info := range worldMaps {
		rows, ok := mapRows[id]
		if !ok || len(rows) != info.Height || len(rows[0]) != info.Width {
			t.Errorf("data petak %s tidak cocok dengan ukuran %dx%d", id, info.Width, info.Height)
		}
	}
}

// Data petak server (tiles_gen.go) harus sama dengan maps.gd; jalankan `make maps` setelah mengubah peta.
func TestTilesMatchClient(t *testing.T) {
	f, err := os.Open("../../client/scripts/maps.gd")
	if err != nil {
		t.Skip("klien tidak ada:", err)
	}
	defer f.Close()
	m, err := mapsrc.Parse(f)
	if err != nil {
		t.Fatal(err)
	}
	if m.Walkable != walkableTiles || !reflect.DeepEqual(m.Rows, mapRows) {
		t.Fatal("internal/game/tiles_gen.go tidak sama dengan client/scripts/maps.gd: jalankan `make maps`")
	}
}

func BenchmarkMoveToLongTrip(b *testing.B) {
	st := posed(MapDesaAwal, 22, 47, 1)
	st.Hutan.Wave = HutanWaves
	to := near(MapGuaGoblin, 30, 60)
	for range b.N {
		s := st
		if err := s.MoveTo(to, 3_600_000); err != nil {
			b.Fatal(err)
		}
	}
}
