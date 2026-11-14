package game

import (
	"math"
	"testing"
)

// TestDistFieldDoesNotCutBlockedCorners memastikan gerakan diagonal tidak dapat melewati sudut tembok.
func TestDistFieldDoesNotCutBlockedCorners(t *testing.T) {
	const id = "test_pathing_corner"
	t.Cleanup(func() { delete(mapRows, id) })

	t.Run("satu sisi sudut terhalang memakai jalur ortogonal", func(t *testing.T) {
		mapRows[id] = []string{
			".#",
			"..",
		}
		d := distField(id, 0, 0)
		got := float64(d[1*2+1])
		if got != 2 {
			t.Fatalf("jarak diagonal melewati sudut terhalang = %v, ingin 2 melalui petak terbuka", got)
		}
	})

	t.Run("dua sisi sudut terhalang tidak terhubung", func(t *testing.T) {
		mapRows[id] = []string{
			".#",
			"#.",
		}
		d := distField(id, 0, 0)
		if !math.IsInf(float64(d[1*2+1]), 1) {
			t.Fatalf("petak di balik sudut tembok seharusnya tidak terjangkau, jarak = %v", d[3])
		}
	})

	t.Run("diagonal di ruang terbuka tetap diizinkan", func(t *testing.T) {
		mapRows[id] = []string{
			"..",
			"..",
		}
		d := distField(id, 0, 0)
		if got := float64(d[3]); math.Abs(got-math.Sqrt2) > 1e-6 {
			t.Fatalf("jarak diagonal ruang terbuka = %v, ingin sqrt(2)", got)
		}
	})
}
