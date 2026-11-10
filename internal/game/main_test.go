package game

import (
	"os"
	"testing"
)

// DayUnix: detik Unix yang pasti siang biasa (jam 10, bukan Serbuan Goblin, bukan Hari Pasar), dipakai tes
// supaya hasil tidak bergantung jam berapa tes dijalankan.
const DayUnix = 3*DaySeconds + DaySeconds*10/24

func TestMain(m *testing.M) {
	Now = func() int64 { return DayUnix }
	os.Exit(m.Run())
}
