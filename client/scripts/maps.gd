extends RefCounted
## Data peta. SEMENTARA ditulis di kode sebagai teks; nanti diganti TileMap dari
## gambar ilustrator. Saat server menjadi otoritatif, tabrakan dihitung di server.
##
## Lambang (daftar gambar yang perlu dibuat ada di assets/README.md):
##   .  rumput          =  jalan tanah        f  bunga (bisa dilewati)
##   T  ladang          B  jembatan           D  pintu rumah (bisa dilewati)
##   #  pohon           ~  air                H  tembok/atap rumah
##   F  pagar           W  menara lampu (tempat berkumpul)              S  tembok batu (reruntuhan)
##   P  pagar kayu besar keliling desa        N  menara gapura (dua petak di kiri dan kanan jalan keluar; juga di tepi utara Perbatasan menuju desa)
##   J  pos jaga   C  kandang ayam   A  tenda   U  api unggun   Q  dummy latihan   Y  tiang panji (basecamp)
##   K  singgasana bos (bisa dilewati; menginjaknya memanggil bos)
##   M  tanah gunung    G  kerikil (ladang monster, bisa dilewati)    R  batu besar
## Yang bisa dilewati: . = f T B D M G   (sisanya menghalangi)
## Pertemuan musuh terjadi di petak ENCOUNTER_TILES (T dan G).

const DEFAULT_MAP := "desa_awal"
const PERBATASAN := "perbatasan"
const GUNUNG := "gunung_batu"
const GUA := "gua_batu"

## Nama peta untuk ditampilkan.
const NAMES := {"desa_awal": "Desa Awal", "perbatasan": "Perbatasan Kerajaan", "gunung_batu": "Gunung Batu", "gua_batu": "Gua Batu"}

## Pintu antar-peta. Menginjak petak `pos` memindahkan pemain ke `to` di petak `at`
## (petak tujuan bukan pintu, agar tidak bolak-balik terus).
const EXITS := {
	"desa_awal": [{"pos": Vector2i(22, 49), "to": "perbatasan", "at": Vector2i(22, 1)}],
	"perbatasan": [
		{"pos": Vector2i(22, 0), "to": "desa_awal", "at": Vector2i(22, 48)},
		{"pos": Vector2i(22, 49), "to": "gunung_batu", "at": Vector2i(22, 1)},
	],
	"gunung_batu": [
		{"pos": Vector2i(22, 0), "to": "perbatasan", "at": Vector2i(22, 48)},
		{"pos": Vector2i(22, 49), "to": "gua_batu", "at": Vector2i(7, 1)},
	],
	"gua_batu": [{"pos": Vector2i(7, 0), "to": "gunung_batu", "at": Vector2i(22, 48)}],
}
const SPAWN := Vector2i(5, 5)
const WALKABLE := ".=fTBDMGK"
## Petak bos: menginjaknya memulai pertarungan bos di server (posisi harus sama dengan BossSpot di internal/game/world.go).
const BOSS_TILE := "K"
const ENCOUNTER_TILES := "TG"

## Desa Awal (85x50): desa di barat (x 0..44, dipagari) dan wilayah jelajah di timur (x 45..84, lewat celah
## pagar di z=22..24): hutan lebat di utara, kolam, reruntuhan benteng, padang bunga dengan kolam, kebun
## buah berjajar, hutan selatan, tambang batu di tenggara, dan enam peti harta (timur_1..6); semua
## pohon dan batu di sana bisa ditebang/dihancurkan untuk emas dan hadiah. Desanya: tujuh rumah di utara, jalan raya timur-barat, alun-alun dengan menara lampu
## di tengah, dua kandang berpagar (masing-masing dengan kandang ayam) di kiri-kanan alun-alun, empat
## rumah di tengah desa, empat ladang berpagar yang masing-masing dikelilingi parit berjembatan
## (sungai tidak membelah desa), empat pondok tani di selatan, dua kolam, basecamp pahlawan (tenda,
## api unggun, dummy latihan) di barat gerbang, pos jaga di timur gerbang, dan gerbang keluar di
## bawah (menuju Perbatasan). Desa dikelilingi pagar kayu besar (P) dan di pintu keluarnya berdiri
## gapura bermenara (N).
const DESA_AWAL: Array[String] = [
	"PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP#R#################R#########R#R########",
	"P..HHH...HHH...HHH...HHH...HHH...HHH..HHHHH.P################RR##############R#######",
	"P..HDH...HDH...HDH...HDH...HDH...HDH..HHHHH.P###################..###################",
	"P..f=f...f=f...f=f...f=f...f=f...f=f..HHDHH.P###############.####..##################",
	"P...=.....=.....=.....=.....=.....=.....=...P##############..###=....####SSSSSSSS###R",
	"P...=.....=.....=.....=.....=.....=.....=...P###############.###=...#####S......S####",
	"P..=======================================..P##############.....=.#.####.S.....RS####",
	"P..=======================================..P#################..=.#f.#...S......S####",
	"P..f....f........===========.....f....f.....P####.###########...==============..S###R",
	"P..FFFFFFFFF..#..===========.#.#fFFFFFFFFF..P##....f~~~~~f####.#=#..#..#.S..==..S####",
	"P..FCCC.f..F.....===========.....F..f.CCCF..P####..==============..#...#.SSS==SSS####",
	"P..FCCC....F...#.===========...#.F....CCCF..P###...~~~~~~~###.#.=##..###.f##f.#######",
	"P..F......fF.#...===========f#..fF......fF..P###.#.~~~~~~~###.##=##.#..#.#......####R",
	"P..F..f....f...#.=====W=====...#....ff..fF..P#####..~~~~~#######=#..##..##.#.f.#f####",
	"P..F.f.....F.f...===========.....F.......F..P###....############=#####.####.#..#...##",
	"P..F...f...F.#.#f===========f#.#.F.......F..P##.##f...##.#.#####=#####......#.###.###",
	"P..FFFFFFFFF..f..===========.....FFFFFFFFF..P#..#....#.#..f####.=.#####.f##.#...#..R#",
	"P............f#..===========..#.............P#....f....f#.f..f..=.....ff.#ff.......##",
	"P..#..........f..===========.......#.....#..P##.#.....#....f.#..=...f.......#.....f##",
	"P....HHH..#.HHH.......=.......HHHf...HHH....P##......#..........=..f........#......##",
	"P...fHDH....HDH.......=.......HDH.#..HDH.#..P#..........f.#.fff.=.f..ff...#........##",
	"P..#.f=f..#ff=ff#.#...=...#.#.f=f....f=f....S...f...f........=======......f#......f##",
	"P.....=...f..=........=........=..#f..=..#.........ff...f....=======..f......f.....##",
	"P.....============================================================================.##",
	"P.......f.............=..............f........f.f....f.......=======....##f..#ff.f.##",
	"P....f.......f........=.......f.............S........#.......=======f.~~~~~........##",
	"P.~~~~~~~~~~.f........=..........~~~~~~~~~~.Pf.f..#....f......f.=ff..~~~~~~~f......##",
	"P.~FFFFFFFF~.#.#.#.#..=.f...#.#.#~FFFFFFFF~.P..#......##...f....=f...~~~~~~~f..f...##",
	"P.~FTTTTTTF~......f...=...#......~FTTTTTTF~.P#......f...........=f...~~~~~~~f......##",
	"P.~FTTTTTT.B..HHH..#..=.....HHH..B.TTTTTTF~.P#...f..f.ff.f.....f=f..##~~~~~........##",
	"P.~FTTTTTTF~..HDH.....=..#..HDH..~FTTTTTTF~.P#..#.#.#.#.#.#.#.##=#...#.#.##.......f##",
	"P.~FTTTTTTF~#.f=f..#..=..f..f=f.#~FTTTTTTF~.P#.................#=....R.....R...R..R##",
	"P.~FFFFFFFF~..f=......=...#.f=...~FFFFFFFF~.P#.##.#.#.#.#....#..=..R.RR.....R.....R##",
	"P.~~~~~~~~~~#f.===============...~~~~~~~~~~.P##................#=#R.........R..R...#R",
	"P.~~~~~~~~~~..#..#ff..=..#.#...#.~~~~~~~~~~.P#.##.#.#.#.#.......=...R.RR.....R.RRR.##",
	"P.~FFFFFFFF~#......#..=......#...~FFFFFFFF~.P#..................=#.......R.R.......##",
	"P.~FTTTTTTF~...#.#....=..#.#...#.~FTTTTTTF~.P#.##.#.#.#.#.#======fR....RR#RRR...RR.##",
	"P.~FTTTTTT.B.......#..=.......f..B.TTTTTTF~.P#....#.#..##.#=..#.=.RR.R.RRRR.RR..R..##",
	"P.~FTTTTTTF~..HHH.....=.....HHH..~FTTTTTTF~.P#.####...#.#.#=.##.=.....R.......R..R.##",
	"P.~FTTTTTTF~..HDH.#...=..#..HDH.#~FTTTTTTF~.P#.##....#....#=###.=.R.R.R...R.RR.....##",
	"P#~FFFFFFFF~#.f=f.....=.....f=f..~FFFFFFFF~#P..##~~~.##.#.#=###.================R..##",
	"P#~~~~~~~~~~...=..#.f.=..f#..=..#~~~~~~~~~~#P#..~~~~~.#....#.###=..RR............R.##",
	"P##............===============............##P#...~~~..##.#.#...#=.....R..R.R...RR..##",
	"P##~~~~~~..AA.........=..#....f.f#..~~~~~~##P#..#..==============..RRR..R..RR.R....##",
	"P##~~~~~~..AA.........=....#.#.#f...~~~~~~##Pf.###...#.....##.##=...........R.R....##",
	"P##~~~~~~......U=======.JJf.......f.~~~~~~##P#..#.....#.##.#..#.=#RR.R.RR...RRR....#R",
	"P##~~~~~~..AA......Y..=.JJ.#...#f#..~~~~~~##P#.#...#.#####...#.#........R..R.....R.##",
	"P##........AA....Q....=......#f..........f##P#####..########....#.......#.#..#..#..##",
	"P##...................=...................##P########R#########RR#################R##",
	"PPPPPPPPPPPPPPPPPPPPNN=NNPPPPPPPPPPPPPPPPPPPP##############R#####R###############R###",
]


## NPC di peta. Kunci = id NPC (sama dengan id pemberi misi di server dan nama gambar
## di assets/characters/). NPC menghalangi jalan; bicara dari petak yang bersebelahan.
const NPCS := {
	"nenek_penjual": {"map": "desa_awal", "pos": Vector2i(3, 6), "name": "Nenek"},
	"petani": {"map": "desa_awal", "pos": Vector2i(11, 6), "name": "Petani"},
}


## Warga desa: pemanis tanpa misi, berjalan bebas di sekitar titik asalnya (`pos`, petak) dalam
## jari-jari `radius` petak, hanya di petak jalan/rumput/bunga. `model` = id model 3D;
## `speed` = petak per detik; `id` = kunci dialognya di warga_dialog.gd. Tidak menghalangi pemain,
## berhenti dan menoleh bila pemain mendekat, dan bisa diajak bicara (tombol Bicara).
## `rumah` = petak pintu rumahnya (D rumah, J pos jaga, atau C kandang ayam): saat malam warga berjalan
## pulang ke sana dan menghilang ke dalam, paginya keluar lagi. `arah` = arah muka bangunan (petak depan
## pintu = rumah + arah; bawaan selatan). `terlihat` = tetap terlihat di dalam: penjaga gerbang berdiri
## di pos jaga yang terbuka (hanya atap dan dinding belakang) menghadap jalan utama. Ayam masuk ke
## kandang ayam. Warga tanpa `rumah` tetap di luar.
const WARGA := [
	{"id": "bu_sari", "model": "warga_ibu", "name": "Bu Sari", "map": "desa_awal", "pos": Vector2(15.5, 9.5), "radius": 5.0, "speed": 0.7, "rumah": Vector2i(10, 2)},
	{"id": "mbak_dewi", "model": "warga_ibu2", "name": "Mbak Dewi", "map": "desa_awal", "pos": Vector2(29.5, 10.5), "radius": 5.0, "speed": 0.75, "rumah": Vector2i(34, 2)},
	{"id": "pak_joko", "model": "warga_bapak", "name": "Pak Joko", "map": "desa_awal", "pos": Vector2(22.5, 17.5), "radius": 6.0, "speed": 0.7, "rumah": Vector2i(13, 20)},
	{"id": "pak_budi", "model": "warga_bapak2", "name": "Pak Budi", "map": "desa_awal", "pos": Vector2(22.5, 40.5), "radius": 7.0, "speed": 0.8, "rumah": Vector2i(29, 39)},
	{"id": "rina", "model": "anak_desa", "name": "Rina", "map": "desa_awal", "pos": Vector2(19.5, 12.5), "radius": 5.0, "speed": 1.1, "rumah": Vector2i(10, 2)},
	{"id": "dika", "model": "anak_desa", "name": "Dika", "map": "desa_awal", "pos": Vector2(25.5, 14.5), "radius": 5.0, "speed": 1.2, "rumah": Vector2i(34, 2)},
	{"id": "kepala_suku", "model": "pendekar_kapak", "name": "Kepala Suku", "map": "desa_awal", "pos": Vector2(40.5, 8.5), "radius": 4.5, "speed": 0.55, "rumah": Vector2i(40, 3)},
	{"id": "penjaga", "model": "pendekar_tombak", "name": "Penjaga", "map": "desa_awal", "pos": Vector2(22.5, 46.5), "radius": 3.5, "speed": 0.6, "rumah": Vector2i(24, 45), "arah": Vector2i(-1, 0), "terlihat": true},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(5.5, 12.5), "radius": 2.2, "speed": 0.6, "rumah": Vector2i(5, 11)},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(8.5, 11.5), "radius": 2.2, "speed": 0.7, "rumah": Vector2i(5, 11)},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(36.5, 12.5), "radius": 2.2, "speed": 0.6, "rumah": Vector2i(39, 11)},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(39.5, 13.5), "radius": 2.2, "speed": 0.7, "rumah": Vector2i(39, 11)},
]

## Petak yang boleh diinjak warga: jalan, rumput, bunga (bukan ladang, jembatan, pintu).
const WARGA_TILES := ".=f"


## Apakah titik (x, z) bebas dilalui warga: petaknya jalan/rumput/bunga, bukan petak NPC
## misi, dan keempat sudut badan (jari-jari 0,22) juga begitu.
static func warga_free(map_id: String, p: Vector2) -> bool:
	for o: Vector2 in [Vector2.ZERO, Vector2(0.22, 0.22), Vector2(-0.22, 0.22), Vector2(0.22, -0.22), Vector2(-0.22, -0.22)]:
		var q := p + o
		var tx := int(floor(q.x))
		var ty := int(floor(q.y))
		var t := tile_at(map_id, tx, ty)
		if t == "" or not WARGA_TILES.contains(t) or npc_at(map_id, tx, ty) != "":
			return false
	return true


## Apakah ruas lurus a -> b bebas dilalui warga (diperiksa tiap 0,2 petak).
static func warga_path_free(map_id: String, a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, int(ceil(a.distance_to(b) / 0.2)))
	for i in range(1, n + 1):
		if not warga_free(map_id, a.lerp(b, float(i) / float(n))):
			return false
	return true


## Musuh yang berkeliaran di tiap peta. Desa Awal sengaja tanpa musuh: pertemuan pertama ada di hutan Perbatasan. `id` harus musuh di internal/game/enemy.go yang memang muncul
## di peta itu; `lv` = MinLevel-nya (musuh yang terlalu kuat untuk level pemain tidak dimunculkan,
## kecuali tidak ada yang lain). `n` = jumlah di peta, `tiles` = jenis petak tempat mereka muncul,
## `min_y` = batas utara (desa: menjauh dari rumah-rumah). Server tetap yang menentukan lawan sebenarnya.
const ROAMERS := {
	"perbatasan": {"n": 16, "tiles": ".fT", "min_y": 3, "kinds": [
		{"id": "tikus_sawah", "name": "Ayam Liar", "lv": 1},
		{"id": "belalang_raksasa", "name": "Kucing Liar", "lv": 1},
		{"id": "ular_sawah", "name": "Rubah Sawah", "lv": 2},
		{"id": "ular_hutan", "name": "Ular Hutan", "lv": 1},
		{"id": "serigala_hutan", "name": "Serigala Hutan", "lv": 2},
		{"id": "babi_hutan", "name": "Babi Hutan", "lv": 3},
		{"id": "serigala_alfa", "name": "Serigala Alfa", "lv": 5},
	]},
	"gunung_batu": {"n": 14, "tiles": "MG", "min_y": 3, "kinds": [
		{"id": "goblin", "name": "Goblin Gunung", "lv": 2},
		{"id": "goblin_pemburu", "name": "Goblin Pemburu", "lv": 4},
		{"id": "ogre_batu", "name": "Monster Batu", "lv": 5},
	]},
	"gua_batu": {"n": 7, "tiles": "MG", "min_y": 3, "kinds": [
		{"id": "orc_gua", "name": "Orc Gua", "lv": 5},
		{"id": "orc_penjaga", "name": "Orc Penjaga", "lv": 6},
		{"id": "orc_buas", "name": "Orc Buas", "lv": 7},
	]},
}

## Petak yang boleh diinjak musuh berkeliaran: seperti bisa dilewati pemain, tetapi bukan pintu
## rumah, pintu antar-peta, singgasana bos, petak NPC, atau peti.
const ROAM_TILES := ".=fTBMG"


## Apakah titik (x, z) bebas dilalui musuh berkeliaran (keempat sudut badan jari-jari 0,25 juga).
static func roam_free(map_id: String, p: Vector2) -> bool:
	for o: Vector2 in [Vector2.ZERO, Vector2(0.25, 0.25), Vector2(-0.25, 0.25), Vector2(0.25, -0.25), Vector2(-0.25, -0.25)]:
		var q := p + o
		var tx := int(floor(q.x))
		var ty := int(floor(q.y))
		var t := tile_at(map_id, tx, ty)
		if t == "" or not ROAM_TILES.contains(t) or npc_at(map_id, tx, ty) != "" or chest_at(map_id, tx, ty) != "" or not exit_at(map_id, tx, ty).is_empty():
			return false
	return true


## Apakah ruas lurus a -> b bebas dilalui musuh berkeliaran (diperiksa tiap 0,25 petak).
static func roam_path_free(map_id: String, a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, int(ceil(a.distance_to(b) / 0.25)))
	for i in range(1, n + 1):
		if not roam_free(map_id, a.lerp(b, float(i) / float(n))):
			return false
	return true


## Peti harta. Id dan petak HARUS sama dengan chests di internal/game/loot.go (server yang
## mengundi isinya). `tier` hanya untuk warna peti; besar hadiah ditentukan server.
const CHESTS := [
	{"id": "desa_1", "map": "desa_awal", "pos": Vector2i(43, 8), "tier": 1},
	{"id": "desa_2", "map": "desa_awal", "pos": Vector2i(2, 22), "tier": 1},
	{"id": "desa_3", "map": "desa_awal", "pos": Vector2i(20, 44), "tier": 1},
	{"id": "timur_1", "map": "desa_awal", "pos": Vector2i(50, 10), "tier": 1},
	{"id": "timur_2", "map": "desa_awal", "pos": Vector2i(77, 7), "tier": 2},
	{"id": "timur_3", "map": "desa_awal", "pos": Vector2i(81, 22), "tier": 2},
	{"id": "timur_4", "map": "desa_awal", "pos": Vector2i(59, 33), "tier": 1},
	{"id": "timur_5", "map": "desa_awal", "pos": Vector2i(80, 44), "tier": 3},
	{"id": "timur_6", "map": "desa_awal", "pos": Vector2i(51, 44), "tier": 2},
	{"id": "perbatasan_1", "map": "perbatasan", "pos": Vector2i(3, 3), "tier": 2},
	{"id": "perbatasan_2", "map": "perbatasan", "pos": Vector2i(30, 17), "tier": 2},
	{"id": "perbatasan_3", "map": "perbatasan", "pos": Vector2i(40, 24), "tier": 2},
	{"id": "perbatasan_4", "map": "perbatasan", "pos": Vector2i(6, 45), "tier": 2},
	{"id": "perbatasan_5", "map": "perbatasan", "pos": Vector2i(40, 45), "tier": 2},
	{"id": "gunung_1", "map": "gunung_batu", "pos": Vector2i(40, 7), "tier": 3},
	{"id": "gunung_2", "map": "gunung_batu", "pos": Vector2i(3, 28), "tier": 3},
	{"id": "gunung_3", "map": "gunung_batu", "pos": Vector2i(42, 32), "tier": 3},
	{"id": "gunung_4", "map": "gunung_batu", "pos": Vector2i(5, 45), "tier": 3},
	{"id": "gunung_5", "map": "gunung_batu", "pos": Vector2i(39, 45), "tier": 3},
	{"id": "gua_1", "map": "gua_batu", "pos": Vector2i(1, 1), "tier": 4},
	{"id": "gua_2", "map": "gua_batu", "pos": Vector2i(13, 1), "tier": 4},
]


## Peti di peta ini.
static func chests_in(map_id: String) -> Array:
	var out: Array = []
	for c: Dictionary in CHESTS:
		if c.map == map_id:
			out.append(c)
	return out


## id peti di petak (x, y), atau "".
static func chest_at(map_id: String, x: int, y: int) -> String:
	for c: Dictionary in CHESTS:
		if c.map == map_id and c.pos == Vector2i(x, y):
			return str(c.id)
	return ""


## Semua petak berlambang `ch` di peta (untuk menguji dan membangun bangunan kecil).
static func tiles_of(map_id: String, ch: String) -> Array:
	var out: Array = []
	var baris := rows(map_id)
	for z in baris.size():
		for x in baris[z].length():
			if baris[z][x] == ch:
				out.append(Vector2i(x, z))
	return out


## id NPC di petak (x, y), atau "" bila tidak ada.
static func npc_at(map_id: String, x: int, y: int) -> String:
	for id: String in NPCS:
		var n: Dictionary = NPCS[id]
		if n.map == map_id and n.pos == Vector2i(x, y):
			return id
	return ""


## id NPC yang bersebelahan dengan (x, y) (atas/bawah/kiri/kanan), atau "".
static func npc_near(map_id: String, x: int, y: int) -> String:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var id := npc_at(map_id, x + d.x, y + d.y)
		if id != "":
			return id
	return ""


## Perbatasan Kerajaan (45x50): hutan lebat dengan jalan raja berkelok dari gerbang desa di utara,
## tujuh bukaan (ladang monster), dua reruntuhan benteng, dua kolam, dan lima peti harta.
## Jalan di selatan naik ke Gunung Batu.
const PERBATASAN_ROWS: Array[String] = [
	"##############PPPPPPNN=NNPPPPPP##############",
	"#..###...........f....=.......#.............#",
	"#......TTTTTT....##...=......####....#......#",
	"#....f.TTTTTT..#####...=.....####.........f.#",
	"#........f....#######f.=.....####...........#",
	"#.............#######...=.....##...........f#",
	"#.....====================........f.f.......#",
	"#............##########..==============.....#",
	"#......f.....##########...=...##.........f..#",
	"#.............##########..=..####...........#",
	"#.........##..##########..=.f####...........#",
	"#..###.#####...#########..=..######.......###",
	"###########....~########..=..#####.....######",
	"########......~~~#######..=..######..########",
	"#######......~~~~~#####...SS.SSSSSS...#######",
	"#######.......~~~..####..=STTTTTTTS...#######",
	"########.......~..#####..=STTTTTTTS...#######",
	"########....##...#####...======TTT....#######",
	"#######...############..=.STTTTTTTS...#######",
	"######...f###########...=.STTTTTTTS..########",
	"####..ff...##########..=..SSSS.SSSS.....#####",
	"###.........########...=f.#########.......###",
	"##...........######.......########.........##",
	"##...........#####.........######...TTTT....#",
	"#.............####.........######.f.TTTT....#",
	"#......===========..===.....####............#",
	"#.............###.........=============.f...#",
	"##...........####.f=.......#####.........f..#",
	"##...........####..=......####.##...........#",
	"###.........####...=..#######...............#",
	"####.......#####..=..f#########.............#",
	"#####.f...######..=..###########.##.......#.#",
	"######...fSSSS.SSSS..################...#####",
	"#####.....STTTTTTTS..################..######",
	"#####....#STTTTTTTS..########################",
	"######..##.TTT=====f.########################",
	"#######..#STTTTTTTS...#######################",
	"########.#STTTTTTTS=..#######################",
	"#######.##SSSS.SSSS=..########~#######.######",
	"####.......######..=...######~~~###.......###",
	"##...........####...=..#####~~~~~.......f...#",
	"##..........f#####..=...#####~~~#.......f...#",
	"#.............####...=..######~#............#",
	"#......================================.....#",
	"#.............#####...=..#######............#",
	"##...........#######..=...#######...........#",
	"#............#######...=..#######..f........#",
	"#...f......########....=..#..######.........#",
	"#.......f.########....=......#########f.....#",
	"######################=######################",
]


## Gunung Batu (45x50): lereng berbatu luas, sarang Monster Batu. Jalur utama berkelok dari utara
## ke selatan, tujuh dataran di kiri-kanan jalur (kerikil G = tempat monster berkeliaran), dan lima peti harta.
const GUNUNG_ROWS: Array[String] = [
	"RRRRRRRRRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRMMMMRRRRRRRRRRRRRRRRRRRR",
	"RRRRRRRMRRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRRR",
	"RRRRMMMMMMMRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRR",
	"RRRMMMRMMMMMRRRRRRRRRRRRMMMRRRRRRRRRRMRRRRRRR",
	"RRMMMMMMMMMMMRRRRRRRRRRRRRMMMRRRRRMMMMMMMRRRR",
	"RRMMMMMMGMMMMRRRRRRRRRRRRRMMMRRRRMMMMRMMMMRRR",
	"RMMMMMGGGGGMMMMMMMMMMMMMMMMMMMRRMMMMMMMMMMMRR",
	"RRMMMGGGGGGGMMMMMMMMMMMMMMMMGGGRMMMMGMMMMMMRR",
	"RRMMMMGGGGGMMRRRRRRRRRRRRRRRGGGMMMGGGGGMMMMMR",
	"RRRMMMMMGMMMRRRRRRRRRRRRRRRRMMMMMGGGGGGGMMMRR",
	"RRRRMMMMMMMRRRRRRRRRRRRRRRRRMMMRMMGGGGGMMMMRR",
	"RRRRRRRMRRRRRRRRRRRRRRRRRRRRMMMRRMMMGMMMMMRRR",
	"RRRRRRRRRRRRRRRRRRRRRRRRRRRRMMMRRRMMMMMMMRRRR",
	"RRRRRRRRRRRRRRRRRRRRRRRRRRRRMMMRRRRRRMRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRRRRRRGGGMRRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRRRRRRGGGRRRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRR",
	"RRRRRRMRRRRRRRRRRRRRRRMRRMMMRRRRRRRRRRRRRRRRR",
	"RRRRMMMMMRRRRRRRRRMMMMMMMMMRRRRRRRRRRRRRRRRRR",
	"RRRMMMMMMMRRRRRRRMMMMMMMMMMMRRRRRRRRRRMRRRRRR",
	"RRMMMMMMMMMRRRRRMMMMMMMMMMMMMRRRRRRRMMMMMRRRR",
	"RRMMMMMGMMMRRRRRMMMMMGMMMMMMMRRRRRRMMMMMMMRRR",
	"RRMMMMGGGMMRRRRMMMGGGGGGGMMMMMRRRRMMMMMMMMMRR",
	"RRMMMMGGGMMRRRRRMGGGGGGGGGMMMRRRRRMMMGMMMMMRR",
	"RMMMMMGGGMMMMMMMMMGGGGGGGMMMMRRRRRMMGGGMRMMRR",
	"RRMMMGGGGGMMMMMMMMMMMGMMMMMMRRRRRRMMGGGMMMMRR",
	"RRMMMMGGGMMRRRRRRRMMMMMMMMMMMMMMMMMMGGGMMMMMR",
	"RRMMMMGGGMMRRRRRRMMMMMMMMMMMMMMMMMMGGGGGMMMRR",
	"RRMMMMGGGMMRRRRRMMMRRRRRRRRRRRRRRRMMGGGMMMMRR",
	"RRRMMMMGMMRRRRRRMMMRRRRRRRRRRRRRRRMMGGGMMMMMR",
	"RRRRMMMMMRRRRRRGGGRRRRRRRRRRRRRRRRMMGGGMMMMRR",
	"RRRRRRMRRRRRRRRGGGRRRRRRRRRRRRRRRRRMMGMMMMRRR",
	"RRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRRMMMMMRRRR",
	"RRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRRRRMRRRRRR",
	"RRRRRRRRRMRRRRMMMRRRRRRRRRRRRRRRRRRRMRRRRRRRR",
	"RRRRRRMMMMMMMRMMMRRRRRRRRRRRRRRRRMMMMMMMRRRRR",
	"RRRRRMMMMMMMMMMMMRRRRRRRRRRRRRRRMMRMMMMMMRRRR",
	"RRRRMMMMMMMMMMMMMRRRRRRRRRRRRRRMMMMMMMMMMMRRR",
	"RRRRMMMMMMGMMMMMMMRRRRRRRRRRRRRMMMMGMMMMMMRRR",
	"RRRMMMMMGGGGGMMMMMMMMMMMMMMMMMMMMGGGGGMMMMMRR",
	"RRRRMMMGGGGGGGMMMMMMMMMMMMMMMMMMGGGGGGGMMMRRR",
	"RRRRMMMMGGGGGMMRRMMMRRRRRRRRRRRMMGGGGGMMMMRRR",
	"RRRRMMMMMMGMMMRRRRMGGGRRRRRRRRRRMMMGMMMMMRRRR",
	"RRRRRMMMMMMMMRRRRRRGGGRRRRRRRRRRRMMMMMMMRRRRR",
	"RRRRRRRRRMRRRRRRRRRRMMMMRRRRRRRRRRRRMRRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRRRRRRRRMMMRRRRRRRRRRRRRRRRRRRRR",
]

## Gua Batu (15x20): sarang Raja Iblis, dalang serangan monster. Singgasananya (K)
## ada di ujung lorong selatan.
const GUA_ROWS: Array[String] = [
	"RRRRRRRMRRRRRRR",
	"RMMMMMMMMMMMMMR",
	"RMGGGMMMMMGGGMR",
	"RMGGGMRRRMGGGMR",
	"RMMMMMRRRMMMMMR",
	"RRMMMMMMMMMMMRR",
	"RRMGGGMMMGGGMRR",
	"RRMGGGMMMGGGMRR",
	"RRMMMMMMMMMMMRR",
	"RRRRMMMMMMMRRRR",
	"RRRRRMGGGMRRRRR",
	"RRRRRMGGGMRRRRR",
	"RRRRRMMMMMRRRRR",
	"RRRRRRMMMRRRRRR",
	"RRRRRRMKMRRRRRR",
	"RRRRRRMMMRRRRRR",
	"RRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRR",
	"RRRRRRRRRRRRRRR",
]


## Pintu di (x, y) berupa {pos, to, at}, atau {} bila bukan pintu.
static func exit_at(map_id: String, x: int, y: int) -> Dictionary:
	for e: Dictionary in EXITS.get(map_id, []):
		if e.pos == Vector2i(x, y):
			return e
	return {}


static func rows(map_id: String) -> Array[String]:
	match map_id:
		DEFAULT_MAP:
			return DESA_AWAL
		PERBATASAN:
			return PERBATASAN_ROWS
		GUNUNG:
			return GUNUNG_ROWS
		GUA:
			return GUA_ROWS
	return []


static func width(map_id: String) -> int:
	var r := rows(map_id)
	return 0 if r.is_empty() else r[0].length()


static func height(map_id: String) -> int:
	return rows(map_id).size()


## Karakter petak di (x, y), atau "" bila di luar peta.
static func tile_at(map_id: String, x: int, y: int) -> String:
	var r := rows(map_id)
	if y < 0 or y >= r.size() or x < 0 or x >= r[y].length():
		return ""
	return r[y][x]


static func walkable(map_id: String, x: int, y: int) -> bool:
	var t := tile_at(map_id, x, y)
	return t != "" and WALKABLE.contains(t)
