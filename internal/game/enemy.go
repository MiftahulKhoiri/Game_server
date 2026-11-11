package game

import "slices"

// Enemy adalah jenis musuh. Tema: monster yang menyerang desa kerajaan.
type Enemy struct {
	ID          string
	Name        string
	HP          int
	Attack      int
	Defense     int
	XP          int
	Gold        int
	Zones       []string // peta tempat muncul (kosong = di mana saja)
	Boss        bool     // bos: tidak muncul acak, hanya lewat petak bos
	MinLevel    int      // baru muncul bila level pemain >= ini
	DropID      string   // barang yang mungkin dijatuhkan ("" = tidak ada)
	DropPercent int      // peluang jatuh, 0-100
	// Kemampuan khusus (roadmap no. 85-86): jenis (lihat Special*) dan nama yang tampil di layar.
	Special     string
	SpecialName string
	// Roadmap no. 188, 190: Time = "malam"/"siang" (hanya muncul pada waktu itu; "" = kapan saja);
	// Raid = penyerbu desa, hanya ada saat Serbuan Goblin.
	Time string
	Raid bool
	// IntervalMs: jeda serangan khusus musuh ini (0 = bawaan: EnemyIntervalMs / BossIntervalMs).
	IntervalMs int64
}

// Jenis kemampuan khusus musuh. Dipakai pada setiap serangan ke-SpecialEvery (bos: ke-BossSpecialEvery).
const (
	SpecialTerkam    = "terkam"     // serangan kuat: kerusakan x1,6
	SpecialRacun     = "racun"      // racun: kerusakan + seperempat serangan musuh
	SpecialBatu      = "kulit_batu" // memulihkan 8% HP maksimum sambil menyerang
	SpecialGempa     = "gempa"      // bos: hantaman x1,8; di bawah separuh HP bos mengamuk (menyerang lebih cepat)
	SpecialEvery     = 4
	BossSpecialEvery = 3
)

// ZoneRetired menandai musuh yang tidak muncul di peta mana pun.
const ZoneRetired = "pensiun"

var enemies = []Enemy{
	// Hutan Perbatasan (sejak v0.32.0 desa aman dari musuh): hewan kecil yang paling mudah dikalahkan.
	{ID: "tikus_sawah", Zones: []string{MapPerbatasan}, Name: "Ayam Liar", HP: 10, Attack: 3, Defense: 0, XP: 6, Gold: 2, MinLevel: 1, DropID: PotionID, DropPercent: 10, Time: TimeDay},
	// Serbuan Goblin ke Desa Awal (roadmap no. 190): hanya saat kejadian berlangsung.
	{ID: "goblin_penyerbu", Zones: []string{MapDesaAwal}, Name: "Goblin Penyerbu", HP: 28, Attack: 7, Defense: 2, XP: 22, Gold: 9, MinLevel: 1, DropID: PotionID, DropPercent: 25, Raid: true, Time: TimeNight},
	{ID: "orc_penyerbu", Zones: []string{MapDesaAwal}, Name: "Orc Penyerbu", HP: 52, Attack: 11, Defense: 4, XP: 40, Gold: 16, MinLevel: 4, DropID: "taring_goblin", DropPercent: 35, Raid: true, Time: TimeNight, Special: SpecialTerkam, SpecialName: "Hantaman Orc"},
	{ID: "belalang_raksasa", Zones: []string{MapPerbatasan}, Name: "Kucing Liar", HP: 14, Attack: 4, Defense: 1, XP: 8, Gold: 3, MinLevel: 1, DropID: PotionID, DropPercent: 10},
	{ID: "ular_sawah", Zones: []string{MapPerbatasan}, Name: "Rubah Sawah", HP: 20, Attack: 6, Defense: 1, XP: 12, Gold: 5, MinLevel: 2, DropID: PotionID, DropPercent: 15},
	{ID: "babi_hutan", Zones: []string{MapPerbatasan}, Name: "Babi Hutan", HP: 34, Attack: 8, Defense: 3, XP: 22, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 25, Special: SpecialTerkam, SpecialName: "Serudukan"},
	// Perbatasan (hutan): binatang buas.
	{ID: "ular_hutan", Zones: []string{MapPerbatasan}, Name: "Ular Hutan", HP: 18, Attack: 6, Defense: 1, XP: 11, Gold: 5, MinLevel: 1, DropID: PotionID, DropPercent: 10, Special: SpecialRacun, SpecialName: "Gigitan Racun"},
	{ID: "serigala_hutan", Zones: []string{MapPerbatasan}, Name: "Serigala Hutan", HP: 32, Attack: 9, Defense: 2, XP: 20, Gold: 9, MinLevel: 2, DropID: PotionID, DropPercent: 20, Special: SpecialTerkam, SpecialName: "Terkaman"},
	{ID: "serigala_alfa", Zones: []string{MapPerbatasan}, Name: "Serigala Alfa", HP: 55, Attack: 12, Defense: 4, XP: 38, Gold: 16, MinLevel: 5, DropID: PotionID, DropPercent: 30, Special: SpecialTerkam, SpecialName: "Terkaman Alfa"},
	// Gunung Batu: goblin, dan Monster Batu sebagai penjaga.
	// Hutan Lebat (v0.46.0): binatang hutan, 25/75/100 per tahap (v0.65.0); bos Goblin Level 1..3 hanya lewat singgasana (hutan.go).
	{ID: "kancil_hutan", Zones: []string{MapHutanLebat}, Name: "Kancil Hutan", HP: 24, Attack: 6, Defense: 1, XP: 7, Gold: 3, MinLevel: 1, DropID: PotionID, DropPercent: 8, Time: TimeDay},
	{ID: "rubah_hutan", Zones: []string{MapHutanLebat, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Rubah Hutan", HP: 32, Attack: 8, Defense: 2, XP: 10, Gold: 4, MinLevel: 2, DropID: PotionID, DropPercent: 10},
	{ID: "ular_belang", Zones: []string{MapHutanLebat, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Ular Belang", HP: 38, Attack: 11, Defense: 2, XP: 13, Gold: 5, MinLevel: 3, DropID: PotionID, DropPercent: 10, Special: SpecialRacun, SpecialName: "Gigitan Racun"},
	{ID: "babi_bertaring", Zones: []string{MapHutanLebat, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Babi Bertaring", HP: 48, Attack: 10, Defense: 3, XP: 14, Gold: 6, MinLevel: 3, DropID: PotionID, DropPercent: 12, Special: SpecialTerkam, SpecialName: "Serudukan"},
	{ID: "serigala_hitam", Zones: []string{MapHutanLebat, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Serigala Hitam", HP: 54, Attack: 12, Defense: 3, XP: 17, Gold: 7, MinLevel: 4, DropID: PotionID, DropPercent: 15, Special: SpecialTerkam, SpecialName: "Terkaman", Time: TimeNight},
	{ID: "beruang_hutan", Zones: []string{MapHutanLebat, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Beruang Hutan", HP: 82, Attack: 14, Defense: 5, XP: 26, Gold: 10, MinLevel: 6, DropID: PotionID, DropPercent: 20, Special: SpecialTerkam, SpecialName: "Cakaran Beruang"},
	// Bab 1 cerita: kelelawar terkutuk yang memburu siapa pun di Hutan Binatang (model kelelawar Quaternius CC0).
	{ID: "kelelawar_hutan", Zones: []string{MapHutanLebat, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Kelelawar Terkutuk", HP: 44, Attack: 11, Defense: 2, XP: 14, Gold: 6, MinLevel: 3, DropID: PotionID, DropPercent: 12, Special: SpecialRacun, SpecialName: "Gigitan Kelelawar"},
	{ID: "goblin_hutan_1", Zones: []string{MapHutanLebat}, Boss: true, Name: "Goblin Level 1", HP: 340, Attack: 28, Defense: 6, XP: 135, Gold: 60, MinLevel: 1, DropID: "taring_goblin", DropPercent: 100, Special: SpecialGempa, SpecialName: "Hantaman Goblin"},
	{ID: "goblin_hutan_2", Zones: []string{MapHutanLebat}, Boss: true, Name: "Goblin Level 2", HP: 600, Attack: 38, Defense: 9, XP: 270, Gold: 120, MinLevel: 1, DropID: "taring_goblin", DropPercent: 100, Special: SpecialGempa, SpecialName: "Hantaman Goblin"},
	{ID: "goblin_hutan_3", Zones: []string{MapHutanLebat}, Boss: true, Name: "Goblin Level 3", HP: 1040, Attack: 50, Defense: 12, XP: 480, Gold: 225, MinLevel: 1, DropID: "permata_merah", DropPercent: 100, Special: SpecialGempa, SpecialName: "Hantaman Goblin"},
	// v0.66.0: semua bos ujian 2x HP dan serangan (Goblin Level 1 terasa terlalu mudah), hadiah 1,5x.
	// Bos ujian Gua Goblin dan Gunung Batu (v0.65.0): muncul setelah 25/75/100 musuh kalah di peta itu (hutan.go).
	// v0.71.0: bos Gua Goblin jauh lebih kuat, menyerang lebih cepat (IntervalMs), dan memburu pemain ke seluruh gua.
	{ID: "kepala_goblin_1", Zones: []string{MapGuaGoblin}, Boss: true, Name: "Orc Batu Lv 1", HP: 1100, Attack: 46, Defense: 9, XP: 360, Gold: 160, IntervalMs: 1450, MinLevel: 1, DropID: "taring_goblin", DropPercent: 100, Special: SpecialGempa, SpecialName: "Hantaman Orc Batu"},
	{ID: "kepala_goblin_2", Zones: []string{MapGuaGoblin}, Boss: true, Name: "Orc Batu Lv 2", HP: 2000, Attack: 62, Defense: 13, XP: 600, Gold: 260, IntervalMs: 1250, MinLevel: 1, DropID: "taring_goblin", DropPercent: 100, Special: SpecialGempa, SpecialName: "Hantaman Orc Batu"},
	{ID: "kepala_goblin_3", Zones: []string{MapGuaGoblin}, Boss: true, Name: "Raja Orc Batu", HP: 2800, Attack: 76, Defense: 17, XP: 950, Gold: 420, IntervalMs: 1100, MinLevel: 1, DropID: "permata_merah", DropPercent: 100, Special: SpecialGempa, SpecialName: "Hantaman Orc Batu"},
	// v0.72.0: bos Gunung Berapi = Naga Lava (id lama ogre_gunung_N dipertahankan); semuanya di atas bos Gua Goblin.
	{ID: "ogre_gunung_1", Zones: []string{MapGunungBatu}, Boss: true, Name: "Naga Lava Lv 1", HP: 3600, Attack: 86, Defense: 20, XP: 1300, Gold: 560, IntervalMs: 1400, MinLevel: 1, DropID: "koin_kuno", DropPercent: 100, Special: SpecialGempa, SpecialName: "Semburan Lava"},
	{ID: "ogre_gunung_2", Zones: []string{MapGunungBatu}, Boss: true, Name: "Naga Lava Lv 2", HP: 4800, Attack: 98, Defense: 23, XP: 1700, Gold: 720, IntervalMs: 1250, MinLevel: 1, DropID: "koin_kuno", DropPercent: 100, Special: SpecialGempa, SpecialName: "Semburan Lava"},
	{ID: "ogre_gunung_3", Zones: []string{MapGunungBatu}, Boss: true, Name: "Induk Naga Lava", HP: 6200, Attack: 112, Defense: 26, XP: 2200, Gold: 900, IntervalMs: 1100, MinLevel: 1, DropID: "permata_merah", DropPercent: 100, Special: SpecialGempa, SpecialName: "Semburan Lava"},
	// Gua Goblin (peta 3, v0.46.0): penjaga gua selain goblin biasa.
	{ID: "goblin_penjaga", Zones: []string{MapGuaGoblin, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Goblin Penjaga", HP: 66, Attack: 12, Defense: 4, XP: 38, Gold: 16, MinLevel: 5, DropID: "taring_goblin", DropPercent: 40},
	{ID: "goblin", Zones: []string{MapGuaGoblin, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Goblin Gunung", HP: 34, Attack: 9, Defense: 2, XP: 24, Gold: 10, MinLevel: 2, DropID: "taring_goblin", DropPercent: 35},
	{ID: "goblin_pemburu", Zones: []string{MapGuaGoblin, MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Goblin Pemburu", HP: 48, Attack: 11, Defense: 3, XP: 32, Gold: 14, MinLevel: 4, DropID: "taring_goblin", DropPercent: 40, Special: SpecialTerkam, SpecialName: "Tusukan Licik"},
	{ID: "ogre_rawa", Zones: []string{MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Ogre Rawa", HP: 60, Attack: 11, Defense: 4, XP: 38, Gold: 18, MinLevel: 4, DropID: "koin_kuno", DropPercent: 25, Special: SpecialTerkam, SpecialName: "Pukulan Gada"},
	{ID: "ogre_batu", Zones: []string{MapGunungBatu, MapGuaBatu, MapIstana}, Name: "Prajurit Orc Batu", HP: 70, Attack: 12, Defense: 5, XP: 45, Gold: 25, MinLevel: 5, DropID: "permata_merah", DropPercent: 30, Special: SpecialBatu, SpecialName: "Kulit Batu"},
	// Gua Batu: sarang orc dan Raja Iblis, dalang serangan monster.
	{ID: "orc_gua", Zones: []string{MapGuaBatu}, Name: "Orc Gua", HP: 56, Attack: 12, Defense: 5, XP: 34, Gold: 15, MinLevel: 5, DropID: "koin_kuno", DropPercent: 25},
	{ID: "orc_penjaga", Zones: []string{MapGuaBatu}, Name: "Orc Penjaga", HP: 68, Attack: 13, Defense: 6, XP: 42, Gold: 18, MinLevel: 6, DropID: "permata_merah", DropPercent: 20},
	{ID: "orc_buas", Zones: []string{MapGuaBatu}, Name: "Orc Buas", HP: 80, Attack: 15, Defense: 6, XP: 52, Gold: 22, MinLevel: 7, DropID: "permata_merah", DropPercent: 25, Special: SpecialTerkam, SpecialName: "Amukan Orc"},
	// Panglima Orc Batu (id lama "raja_goblin", dulu "Raja Iblis"): bos Benteng Orc, Bab 3 cerita The Last Dragon.
	{ID: "raja_goblin", Zones: []string{MapGuaBatu}, Boss: true, Name: "Panglima Orc Batu", HP: 7500, Attack: 120, Defense: 28, XP: 2800, Gold: 1100, IntervalMs: 1200, MinLevel: 1, DropID: "permata_merah", DropPercent: 100, Special: SpecialGempa, SpecialName: "Hantaman Gada Batu"},
	// Bab 4: Aldragor (naga terakhir yang dikendalikan) dan Malzareth (penyihir kegelapan, tiga fase; lihat story.go).
	{ID: AldragorID, Zones: []string{MapIstana}, Boss: true, Name: "Aldragor", HP: 9000, Attack: 130, Defense: 30, XP: 3600, Gold: 1400, IntervalMs: 1150, MinLevel: 1, DropID: "permata_merah", DropPercent: 100, Special: SpecialGempa, SpecialName: "Semburan Api Naga"},
	{ID: MalzarethID, Zones: []string{MapTakhta}, Boss: true, Name: "Malzareth", HP: 11000, Attack: 140, Defense: 32, XP: 5000, Gold: 2000, IntervalMs: 1100, MinLevel: 1, DropID: DiamondID, DropPercent: 100, Special: SpecialGempa, SpecialName: "Sihir Hitam"},
	// v0.72.0: binatang tulang (kerangka binatang yang dibangkitkan kutukan) di Gua Goblin.
	// v0.73.0: Gua Goblin tanpa binatang hutan biasa; diganti binatang tulang (kerangka binatang hutan yang dibangkitkan).
	{ID: "rubah_tulang", Zones: []string{MapGuaGoblin}, Name: "Rubah Tulang", HP: 36, Attack: 9, Defense: 2, XP: 16, Gold: 6, MinLevel: 2, DropID: PotionID, DropPercent: 12},
	{ID: "ular_tulang", Zones: []string{MapGuaGoblin}, Name: "Ular Tulang", HP: 42, Attack: 11, Defense: 2, XP: 19, Gold: 7, MinLevel: 3, DropID: PotionID, DropPercent: 12, Special: SpecialRacun, SpecialName: "Taring Tulang"},
	{ID: "babi_tulang", Zones: []string{MapGuaGoblin}, Name: "Babi Tulang", HP: 52, Attack: 11, Defense: 3, XP: 21, Gold: 8, MinLevel: 3, DropID: PotionID, DropPercent: 15, Special: SpecialTerkam, SpecialName: "Serudukan Tulang"},
	{ID: "serigala_tulang", Zones: []string{MapGuaGoblin}, Name: "Serigala Tulang", HP: 58, Attack: 13, Defense: 3, XP: 30, Gold: 12, MinLevel: 3, DropID: PotionID, DropPercent: 20, Special: SpecialTerkam, SpecialName: "Gigitan Tulang"},
	{ID: "beruang_tulang", Zones: []string{MapGuaGoblin}, Name: "Beruang Tulang", HP: 92, Attack: 15, Defense: 5, XP: 44, Gold: 18, MinLevel: 5, DropID: "taring_goblin", DropPercent: 30, Special: SpecialTerkam, SpecialName: "Cakaran Tulang"},
	// v0.72.0: dua jenis naga kecil berkeliaran di halaman Istana Kegelapan.
	{ID: "naga_bayangan", Zones: []string{MapIstana}, Name: "Naga Bayangan", HP: 260, Attack: 34, Defense: 14, XP: 150, Gold: 55, MinLevel: 12, DropID: "permata_merah", DropPercent: 30, Special: SpecialRacun, SpecialName: "Napas Bayangan"},
	{ID: "naga_api", Zones: []string{MapIstana}, Name: "Naga Api Muda", HP: 300, Attack: 37, Defense: 15, XP: 170, Gold: 60, MinLevel: 13, DropID: "permata_merah", DropPercent: 35, Special: SpecialTerkam, SpecialName: "Semburan Api"},
	// Halaman Istana Kegelapan: sisa pasukan terkutuk penjaga istana.
	{ID: "kelelawar_istana", Zones: []string{MapIstana}, Name: "Kelelawar Kegelapan", HP: 95, Attack: 22, Defense: 6, XP: 60, Gold: 22, MinLevel: 10, DropID: PotionID, DropPercent: 30, Special: SpecialRacun, SpecialName: "Gigitan Kegelapan"},
	{ID: "prajurit_kutukan", Zones: []string{MapIstana}, Name: "Prajurit Terkutuk", HP: 130, Attack: 24, Defense: 9, XP: 75, Gold: 28, MinLevel: 10, DropID: "koin_kuno", DropPercent: 30},
	{ID: "orc_kegelapan", Zones: []string{MapIstana}, Name: "Orc Kegelapan", HP: 170, Attack: 27, Defense: 11, XP: 95, Gold: 34, MinLevel: 11, DropID: "permata_merah", DropPercent: 20, Special: SpecialTerkam, SpecialName: "Amukan Kegelapan"},
	{ID: "iblis_bayangan", Zones: []string{MapIstana}, Name: "Iblis Bayangan", HP: 210, Attack: 30, Defense: 13, XP: 120, Gold: 42, MinLevel: 12, DropID: "permata_merah", DropPercent: 25, Special: SpecialRacun, SpecialName: "Kabut Bayangan"},
	// Pensiun (v0.29.0): tidak lagi muncul. Tetap terdaftar agar pertarungan lama yang masih berjalan bisa selesai.
	// Aktif lagi (v0.53.0, roadmap no. 71): Kerangka Gua di Gua Goblin, Iblis Lava di Gua Batu.
	{ID: "kelelawar_gua", Zones: []string{MapGuaGoblin}, Name: "Kerangka Gua", HP: 30, Attack: 9, Defense: 2, XP: 20, Gold: 9, MinLevel: 3, DropID: PotionID, DropPercent: 20, Special: SpecialRacun, SpecialName: "Kutukan Tulang"},
	{ID: "golem_kerikil", Zones: []string{ZoneRetired}, Name: "Kerangka Pejuang", HP: 50, Attack: 10, Defense: 6, XP: 32, Gold: 14, MinLevel: 4, DropID: "koin_kuno", DropPercent: 25},
	{ID: "goblin_penjaga", Zones: []string{ZoneRetired}, Name: "Kerangka Penjaga", HP: 45, Attack: 11, Defense: 4, XP: 28, Gold: 12, MinLevel: 5, DropID: "taring_goblin", DropPercent: 50},
	{ID: "golem_lava", Zones: []string{MapGuaBatu}, Name: "Iblis Lava", HP: 62, Attack: 13, Defense: 6, XP: 40, Gold: 18, MinLevel: 6, DropID: "permata_merah", DropPercent: 20, Special: SpecialBatu, SpecialName: "Kobaran Lava"},
}

// EnemyByID mencari musuh berdasarkan id.
func EnemyByID(id string) (Enemy, bool) {
	for _, e := range enemies {
		if e.ID == id {
			return e, true
		}
	}
	return Enemy{}, false
}

// inZone: apakah musuh muncul di peta ini.
func (e Enemy) inZone(mapID string) bool {
	return len(e.Zones) == 0 || slices.Contains(e.Zones, mapID)
}

// PickEnemy memilih musuh acak yang cocok untuk level pemain dan peta tempat ia berada.
// Bila pemain terlalu rendah levelnya untuk peta itu, ia tetap bertemu musuh terlemah
// di peta itu (masuk wilayah berbahaya terlalu dini memang berisiko).
func PickEnemy(level int, mapID string, rng Rand) Enemy {
	var eligible, inMap []Enemy
	now := Now()
	for _, e := range enemies {
		if e.Boss || !e.inZone(mapID) || !e.timeAllows(now) {
			continue
		}
		inMap = append(inMap, e)
		if e.MinLevel <= level {
			eligible = append(eligible, e)
		}
	}
	if len(eligible) == 0 {
		if len(inMap) == 0 {
			for _, e := range enemies { // peta tak dikenal: semua musuh biasa
				if !e.Boss && !e.Raid {
					inMap = append(inMap, e)
				}
			}
		}
		weakest := inMap[0]
		for _, e := range inMap {
			if e.MinLevel < weakest.MinLevel {
				weakest = e
			}
		}
		return weakest
	}
	return eligible[rng.Intn(len(eligible))]
}

// PickEnemyFor memilih musuh untuk pertarungan yang dimulai pemain dengan menyentuh musuh
// berkeliaran di peta. `want` dipakai bila musuh itu memang boleh muncul di peta dan level
// pemain ini (sama seperti pilihan acak); selain itu server memilih sendiri.
func PickEnemyFor(level int, mapID, want string, rng Rand) Enemy {
	if want != "" {
		if e, ok := EnemyByID(want); ok && !e.Boss && e.inZone(mapID) && e.timeAllows(Now()) &&
			(e.MinLevel <= level || e.MinLevel == weakestMinLevel(mapID)) {
			return e
		}
	}
	return PickEnemy(level, mapID, rng)
}

// weakestMinLevel adalah MinLevel terkecil di antara musuh biasa di peta itu.
func weakestMinLevel(mapID string) int {
	lowest := -1
	for _, e := range enemies {
		if e.Boss || !e.inZone(mapID) {
			continue
		}
		if lowest < 0 || e.MinLevel < lowest {
			lowest = e.MinLevel
		}
	}
	return lowest
}
