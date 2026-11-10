package game

import "errors"

// Keakraban warga (roadmap no. 58-59): server mengingat berapa kali pemain bicara dengan tiap warga
// dan poin keakraban. Poin naik saat bicara (paling sering sekali per RepTalkCooldownSec), saat
// menyelesaikan misi dari warga itu, dan saat berbelanja di tokonya. Keakraban tinggi memberi
// potongan harga di toko penjaganya.

// WargaIDs adalah warga yang bisa diajak bicara (sama dengan id di client/scripts/maps.gd).
var WargaIDs = []string{
	"nenek_penjual", "petani", "bu_sari", "mbak_dewi", "pak_joko", "pak_budi", "rina", "dika",
	"kepala_suku", "penjaga", "ayam", "mpu_karta", "tuan_wira", "prajurit_damar", "laras", "nyai_sekar",
	"kapten_kem", "pak_ujang", "penjaga_toko", "penjaga_makan", "penjaga_alat", "penjaga_rawat",
	"rekrut_pahlawan", "rekrut_prajurit", "latih_pahlawan", "latih_prajurit", "penjaga_inap", "pak_saleh",
	// Tokoh cerita The Last Dragon (story.go).
	PenjagaHutan, OrcTuaID, "elara",
}

// Aturan keakraban.
const (
	RepMax             = 100
	RepTalkCooldownSec = 600 // ±1 hari permainan (12 menit nyata)
	RepQuestBonus      = 5   // menyelesaikan misi dari warga ini
	RepFriend          = 3   // mulai "Teman"
	RepBestFriend      = 10  // mulai "Sahabat": potongan harga di tokonya
	RepDiscountPercent = 10
)

// Penjaga tiap toko (untuk potongan harga dan keakraban saat belanja).
var shopKeepers = map[string]string{ShopPotion: "penjaga_toko", ShopFood: "penjaga_makan", ShopGear: "penjaga_alat"}

// ErrUnknownWarga berarti id warga tidak dikenal.
var ErrUnknownWarga = errors.New("warga tidak dikenal")

// Rep adalah ingatan satu warga tentang pemain.
type Rep struct {
	Points int   `json:"p"` // poin keakraban 0..RepMax
	Talks  int   `json:"t"` // berapa kali diajak bicara
	Last   int64 `json:"l"` // detik Unix terakhir poin bicara bertambah
}

func knownWarga(id string) bool {
	for _, w := range WargaIDs {
		if w == id {
			return true
		}
	}
	return false
}

func (s *State) addRep(id string, pts int) {
	if !knownWarga(id) {
		return
	}
	if s.Reputation == nil {
		s.Reputation = map[string]Rep{}
	}
	r := s.Reputation[id]
	r.Points = min(RepMax, r.Points+pts)
	s.Reputation[id] = r
}

// TalkTo mencatat pembicaraan dengan warga `id` pada waktu `now` (detik Unix).
func (s *State) TalkTo(id string, now int64) error {
	if !knownWarga(id) {
		return ErrUnknownWarga
	}
	if s.Reputation == nil {
		s.Reputation = map[string]Rep{}
	}
	r := s.Reputation[id]
	r.Talks++
	if r.Last == 0 || now-r.Last >= RepTalkCooldownSec {
		r.Points = min(RepMax, r.Points+1)
		r.Last = now
	}
	s.Reputation[id] = r
	s.checkAchievements()
	return nil
}

// ShopDiscount adalah potongan harga (persen) di toko `shop` menurut keakraban dengan penjaganya.
func (s State) ShopDiscount(shop string) int {
	d := 0
	if k, ok := shopKeepers[shop]; ok && s.Reputation[k].Points >= RepBestFriend {
		d = RepDiscountPercent
	}
	if MarketActive(Now()) {
		d += MarketPercent // Hari Pasar (roadmap no. 189, 200)
	}
	return d
}

func (s State) validReputation() bool {
	if len(s.Reputation) > len(WargaIDs) {
		return false
	}
	for id, r := range s.Reputation {
		if !knownWarga(id) || r.Points < 0 || r.Points > RepMax || r.Talks < 0 {
			return false
		}
	}
	return true
}
