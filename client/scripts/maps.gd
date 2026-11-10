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
const HUTAN := "hutan_lebat"
const GUA_GOBLIN := "gua_goblin"
## Ruangan di dalam bangunan Desa Awal (v0.40.0): pintu bangunan di desa = jalan masuk, pintu di bawah ruangan = keluar.
const TOKO_RAMUAN := "toko_ramuan"
const RUMAH_MAKAN := "rumah_makan"
const RUMAH_SEHAT := "rumah_sehat"
const TOKO_ALAT := "toko_peralatan"
const AULA := "aula_pelatihan"
const INTERIORS := ["toko_ramuan", "rumah_makan", "rumah_sehat", "toko_peralatan", "aula_pelatihan"]

## Nama peta untuk ditampilkan.
const NAMES := {"desa_awal": "Desa Awal", "perbatasan": "Perbatasan Kerajaan", "gunung_batu": "Gunung Batu", "gua_batu": "Gua Batu", "hutan_lebat": "Hutan Lebat", "gua_goblin": "Gua Goblin", "toko_ramuan": "Toko Ramuan", "rumah_makan": "Rumah Makan", "rumah_sehat": "Rumah Sehat", "toko_peralatan": "Toko Peralatan", "aula_pelatihan": "Aula Pelatihan"}

## Pintu antar-peta. Menginjak petak `pos` memindahkan pemain ke `to` di petak `at`
## (petak tujuan bukan pintu, agar tidak bolak-balik terus).
const EXITS := {
	"desa_awal": [
		{"pos": Vector2i(21, 49), "to": "perbatasan", "at": Vector2i(21, 1)},
		{"pos": Vector2i(22, 49), "to": "perbatasan", "at": Vector2i(22, 1)},
		{"pos": Vector2i(23, 49), "to": "perbatasan", "at": Vector2i(23, 1)},
		{"pos": Vector2i(4, 2), "to": "toko_peralatan", "at": Vector2i(4, 6)},
		{"pos": Vector2i(38, 20), "to": "aula_pelatihan", "at": Vector2i(5, 6)},
		{"pos": Vector2i(16, 2), "to": "toko_ramuan", "at": Vector2i(4, 6)},
		{"pos": Vector2i(22, 2), "to": "rumah_makan", "at": Vector2i(4, 6)},
		{"pos": Vector2i(28, 2), "to": "rumah_sehat", "at": Vector2i(4, 6)},
	],
	"toko_peralatan": [{"pos": Vector2i(4, 7), "to": "desa_awal", "at": Vector2i(4, 3)}],
	"aula_pelatihan": [{"pos": Vector2i(5, 7), "to": "desa_awal", "at": Vector2i(38, 21)}],
	"toko_ramuan": [{"pos": Vector2i(4, 7), "to": "desa_awal", "at": Vector2i(16, 3)}],
	"rumah_makan": [{"pos": Vector2i(4, 7), "to": "desa_awal", "at": Vector2i(22, 3)}],
	"rumah_sehat": [{"pos": Vector2i(4, 7), "to": "desa_awal", "at": Vector2i(28, 3)}],
	"perbatasan": [
		{"pos": Vector2i(21, 0), "to": "desa_awal", "at": Vector2i(21, 48)},
		{"pos": Vector2i(22, 0), "to": "desa_awal", "at": Vector2i(22, 48)},
		{"pos": Vector2i(23, 0), "to": "desa_awal", "at": Vector2i(23, 48)},
		{"pos": Vector2i(22, 49), "to": "hutan_lebat", "at": Vector2i(22, 1)},
	],
	"hutan_lebat": [
		{"pos": Vector2i(22, 0), "to": "perbatasan", "at": Vector2i(22, 48)},
		# Gerbang Gua Goblin: terkunci sampai tiga Goblin kalah (lihat exit_locked).
		{"pos": Vector2i(146, 49), "to": "gua_goblin", "at": Vector2i(11, 1)},
		{"pos": Vector2i(147, 49), "to": "gua_goblin", "at": Vector2i(12, 1)},
	],
	"gua_goblin": [
		{"pos": Vector2i(11, 0), "to": "hutan_lebat", "at": Vector2i(146, 48)},
		{"pos": Vector2i(12, 0), "to": "hutan_lebat", "at": Vector2i(147, 48)},
		{"pos": Vector2i(13, 0), "to": "hutan_lebat", "at": Vector2i(147, 48)},
		{"pos": Vector2i(11, 29), "to": "gunung_batu", "at": Vector2i(22, 1)},
		{"pos": Vector2i(12, 29), "to": "gunung_batu", "at": Vector2i(22, 1)},
		{"pos": Vector2i(13, 29), "to": "gunung_batu", "at": Vector2i(22, 1)},
	],
	"gunung_batu": [
		{"pos": Vector2i(22, 0), "to": "gua_goblin", "at": Vector2i(12, 28)},
		{"pos": Vector2i(22, 49), "to": "gua_batu", "at": Vector2i(7, 1)},
	],
	"gua_batu": [{"pos": Vector2i(7, 0), "to": "gunung_batu", "at": Vector2i(22, 48)}],
}
const SPAWN := Vector2i(5, 5)
const WALKABLE := ".=fTBDMGK"
## Petak bos: menginjaknya memulai pertarungan bos di server (posisi harus sama dengan BossSpot di internal/game/world.go).
const BOSS_TILE := "K"
## Singgasana bos Goblin di Hutan Lebat (sama dengan HutanBossX/Y di internal/game/hutan.go).
const HUTAN_BOSS := Vector2i(142, 47)
## Kem Kapten Rimba (api unggun, tenda, panji) tepat di bawah gapura desa di Perbatasan: zona aman per peta, binatang tidak masuk.
const KEM_ZONES := {"perbatasan": Rect2i(23, 1, 7, 6)}  # x 23..29, y 1..6
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
	"PPPPPPPPPPPPPPPPPPPNN===NNPPPPPPPPPPPPPPPPPPP##############R#####R###############R###",
]


## NPC di peta. Kunci = id NPC (sama dengan id pemberi misi di server dan nama gambar
## di assets/characters/). NPC menghalangi jalan; bicara dari petak yang bersebelahan.
const NPCS := {
	"nenek_penjual": {"map": "desa_awal", "pos": Vector2i(3, 6), "name": "Nenek", "peran": "Penjual Sayur"},
	"petani": {"map": "desa_awal", "pos": Vector2i(11, 6), "name": "Petani", "peran": "Pemilik Ladang"},
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
	{"id": "bu_sari", "model": "warga_ibu", "name": "Bu Sari", "peran": "Juru Masak", "baju": Color("ffb0a0"), "map": "desa_awal", "pos": Vector2(15.5, 9.5), "radius": 5.0, "speed": 0.7, "rumah": Vector2i(10, 2), "jadwal": [{"dari": 10.0, "sampai": 12.5, "pos": Vector2(18.5, 11.75), "kerja": "bicara", "hadap": 180.0, "kata": ["Kain biru ini berapa, Dik?", "Wah, mahal juga. Kurang sedikit, ya?"]}]},
	{"id": "mbak_dewi", "model": "warga_ibu2", "name": "Mbak Dewi", "peran": "Pedagang Kain", "baju": Color("f0a8e0"), "map": "desa_awal", "pos": Vector2(29.5, 10.5), "radius": 5.0, "speed": 0.75, "rumah": Vector2i(34, 2), "jadwal": [{"dari": 8.0, "sampai": 16.0, "pos": Vector2(18.5, 10.5), "kerja": "bicara", "hadap": 0.0, "alat": "lapak", "kata": ["Kain, kain! Kain halus dari kota!", "Mari, Bu, dilihat dulu kainnya.", "Untuk pahlawan, harga teman!"]}]},
	{"id": "pak_joko", "model": "warga_bapak", "name": "Pak Joko", "peran": "Mantan Prajurit", "baju": Color("b8c4a0"), "map": "desa_awal", "pos": Vector2(22.5, 17.5), "radius": 6.0, "speed": 0.7, "rumah": Vector2i(13, 20), "jadwal": [{"dari": 13.0, "sampai": 15.5, "pos": Vector2(19.4, 11.75), "kerja": "bicara", "hadap": 180.0, "kata": ["Ada kain untuk ikat kepala prajurit?", "Dulu di istana kainnya lebih tebal, lho."]}]},
	{"id": "pak_budi", "model": "warga_bapak2", "name": "Pak Budi", "peran": "Petani Ladang", "baju": Color("d8c890"), "kulit": Color("e8cfb0"), "map": "desa_awal", "pos": Vector2(22.5, 40.5), "radius": 7.0, "speed": 0.8, "rumah": Vector2i(29, 39), "jadwal": [{"dari": 6.0, "sampai": 15.0, "pos": Vector2(12.5, 28.5), "kerja": "cangkul", "hadap": 270.0, "kata": ["Hup! Tanahnya keras sekali.", "Semoga panen tahun ini melimpah.", "Rumput liar ini tumbuh terus..."]}]},
	{"id": "rina", "model": "anak_desa", "name": "Rina", "peran": "Anak Desa", "baju": Color("ffa8c8"), "kulit": Color("fff0e0"), "map": "desa_awal", "pos": Vector2(19.5, 12.5), "radius": 5.0, "speed": 1.1, "rumah": Vector2i(10, 2)},
	{"id": "dika", "model": "anak_desa", "name": "Dika", "peran": "Anak Desa", "baju": Color("a8c8ff"), "kulit": Color("e0c0a0"), "map": "desa_awal", "pos": Vector2(25.5, 14.5), "radius": 5.0, "speed": 1.2, "rumah": Vector2i(34, 2)},
	{"id": "kepala_suku", "model": "pendekar_kapak", "name": "Kepala Suku", "peran": "Kepala Desa", "map": "desa_awal", "pos": Vector2(40.5, 8.5), "radius": 4.5, "speed": 0.55, "rumah": Vector2i(40, 3)},
	{"id": "penjaga", "model": "pendekar_tombak", "name": "Penjaga", "peran": "Penjaga Gerbang", "map": "desa_awal", "pos": Vector2(22.5, 46.5), "radius": 3.5, "speed": 0.6, "rumah": Vector2i(24, 45), "arah": Vector2i(-1, 0), "terlihat": true},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(5.5, 12.5), "radius": 2.2, "speed": 0.6, "rumah": Vector2i(5, 11)},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(8.5, 11.5), "radius": 2.2, "speed": 0.7, "rumah": Vector2i(5, 11)},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(36.5, 12.5), "radius": 2.2, "speed": 0.6, "rumah": Vector2i(39, 11)},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(39.5, 13.5), "radius": 2.2, "speed": 0.7, "rumah": Vector2i(39, 11)},
	# Penjaga toko: berdiri di belakang meja kasir di dalam ruangannya, siang dan malam (`diam`). Mengajak
	# bicara penjaga = berbelanja (`toko` = "toko" ramuan, "makan" rumah makan; "peralatan" = toko peralatan, "rawat" = rumah sehat, pulih gratis).
	# Roadmap no. 22-30, 35-38: warga dengan pekerjaan. `kerja` = gerakan berulang di tempat ("palu" menempa,
	# "duduk"), `malam` = pose saat malam bagi yang tidak punya rumah ("tidur"), `hadap` = arah muka awal
	# (derajat, 0 = selatan/+z), `alat` = benda di depannya ("landasan" pandai besi, "batu" tempat duduk),
	# `baju` / `kulit` = warna pakaian dan kulit (variasi NPC, no. 31-32), `ukuran` = pengali tinggi.
	{"id": "mpu_karta", "model": "warga_bapak2", "name": "Mpu Karta", "peran": "Pandai Besi", "map": "desa_awal", "pos": Vector2(13.5, 4.5), "radius": 0.0, "speed": 0.0, "diam": true, "kerja": "palu", "rumah": Vector2i(6, 20), "hadap": 0.0, "alat": "landasan", "baju": Color("8c7c6c"), "kulit": Color("ecd2b8"), "ukuran": 1.08},
	{"id": "tuan_wira", "model": "warga_bapak", "name": "Tuan Wiranata", "peran": "Bangsawan Kerajaan", "map": "desa_awal", "pos": Vector2(25.5, 15.5), "radius": 3.0, "speed": 0.45, "rumah": Vector2i(31, 20), "baju": Color("b890ff"), "kulit": Color("fff0e0"), "ukuran": 1.04},
	{"id": "prajurit_damar", "model": "prajurit", "name": "Damar", "peran": "Prajurit Kerajaan", "map": "desa_awal", "pos": Vector2(30.5, 23.5), "radius": 8.0, "speed": 0.9},
	{"id": "laras", "model": "pemanah", "name": "Laras", "peran": "Pemanah Penjaga", "map": "desa_awal", "pos": Vector2(27.5, 47.5), "radius": 0.0, "speed": 0.0, "diam": true, "hadap": 180.0, "baju": Color("c8e0a0")},
	{"id": "nyai_sekar", "model": "warga_ibu2", "name": "Nyai Sekar", "peran": "Penyihir Desa", "map": "desa_awal", "pos": Vector2(40.5, 17.5), "radius": 0.0, "speed": 0.0, "diam": true, "kerja": "duduk", "malam": "tidur", "hadap": 270.0, "alat": "batu", "baju": Color("a070e0")},
	# Pedagang keliling di Perbatasan (roadmap no. 53-57): takut dan lari bila binatang buas mendekat.
	{"id": "pak_ujang", "model": "warga_bapak", "name": "Pak Ujang", "peran": "Pedagang Keliling", "map": "perbatasan", "pos": Vector2(8.5, 6.5), "radius": 4.0, "speed": 0.7, "baju": Color("e0b070"), "kulit": Color("e0c0a0")},
	{"id": "penjaga_toko", "model": "warga_bapak", "name": "Pak Darman", "peran": "Penjaga Toko Ramuan", "baju": Color("c0e0b0"), "kulit": Color("e8d0b8"), "map": "toko_ramuan", "pos": Vector2(4.5, 2.5), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "toko"},
	{"id": "penjaga_makan", "model": "warga_ibu2", "name": "Bu Wati", "peran": "Penjaga Rumah Makan", "baju": Color("ffd890"), "map": "rumah_makan", "pos": Vector2(4.5, 2.5), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "makan"},
	{"id": "penjaga_alat", "model": "warga_bapak2", "name": "Pak Hasan", "peran": "Penjaga Toko Peralatan", "baju": Color("a8b8d0"), "kulit": Color("dcb898"), "map": "toko_peralatan", "pos": Vector2(4.5, 2.5), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "peralatan"},
	{"id": "kapten_kem", "model": "pendekar_kapak", "name": "Kapten Rimba", "peran": "Penjaga Kem Hutan", "map": "perbatasan", "pos": Vector2(23.5, 4.5), "radius": 0.0, "speed": 0.0, "diam": true},
	# Perekrut di basecamp pahlawan (barat gerbang): tenda merah = pahlawan berkelas, tenda hijau = prajurit biasa.
	{"id": "rekrut_pahlawan", "model": "ksatria", "name": "Komandan Raka", "peran": "Perekrut Pahlawan (tenda merah)", "map": "desa_awal", "pos": Vector2(14.3, 43.9), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "rekrut_pahlawan"},
	{"id": "rekrut_prajurit", "model": "pendekar_tombak", "name": "Sersan Joni", "peran": "Perekrut Prajurit (tenda hijau)", "map": "desa_awal", "pos": Vector2(14.3, 46.9), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "rekrut_prajurit"},
	# Pelatih di Aula Pelatihan: kiri melatih pahlawan pembantu berkelas, kanan melatih prajurit biasa.
	{"id": "latih_pahlawan", "model": "pendekar_kapak", "name": "Guru Bima", "peran": "Pelatih Pahlawan", "map": "aula_pelatihan", "pos": Vector2(4.0, 2.6), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "latih_pahlawan"},
	{"id": "latih_prajurit", "model": "pendekar_tombak", "name": "Sersan Anton", "peran": "Pelatih Prajurit", "map": "aula_pelatihan", "pos": Vector2(7.0, 2.6), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "latih_prajurit"},
	{"id": "penjaga_rawat", "model": "warga_ibu", "name": "Suster Mira", "peran": "Penjaga Rumah Sehat", "baju": Color("e8f4ff"), "map": "rumah_sehat", "pos": Vector2(4.5, 2.5), "radius": 0.0, "speed": 0.0, "diam": true, "toko": "rawat"},
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
	# Hutan Lebat: 100 binatang per tahap (server menghitung), yang hidup bersamaan dibatasi `n`.
	"hutan_lebat": {"n": 22, "tiles": ".f", "min_y": 3, "kinds": [
		{"id": "kancil_hutan", "name": "Kancil Hutan", "lv": 1},
		{"id": "rubah_hutan", "name": "Rubah Hutan", "lv": 2},
		{"id": "ular_belang", "name": "Ular Belang", "lv": 3},
		{"id": "babi_bertaring", "name": "Babi Bertaring", "lv": 3},
		{"id": "serigala_hitam", "name": "Serigala Hitam", "lv": 4},
		{"id": "beruang_hutan", "name": "Beruang Hutan", "lv": 6},
	]},
	"gua_goblin": {"n": 9, "tiles": "MG", "min_y": 3, "kinds": [
		{"id": "goblin", "name": "Goblin Gunung", "lv": 2},
		{"id": "goblin_pemburu", "name": "Goblin Pemburu", "lv": 4},
		{"id": "goblin_penjaga", "name": "Goblin Penjaga", "lv": 5},
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
		if KEM_ZONES.has(map_id) and (KEM_ZONES[map_id] as Rect2i).has_point(Vector2i(tx, ty)):
			return false  # kem: zona aman
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
	{"id": "hutan_1", "map": "hutan_lebat", "pos": Vector2i(38, 6), "tier": 2},
	{"id": "hutan_2", "map": "hutan_lebat", "pos": Vector2i(43, 30), "tier": 2},
	{"id": "hutan_3", "map": "hutan_lebat", "pos": Vector2i(127, 42), "tier": 2},
	{"id": "hutan_4", "map": "hutan_lebat", "pos": Vector2i(80, 15), "tier": 3},
	{"id": "hutan_5", "map": "hutan_lebat", "pos": Vector2i(25, 26), "tier": 2},
	{"id": "hutan_6", "map": "hutan_lebat", "pos": Vector2i(144, 21), "tier": 3},
	{"id": "gua_gob_1", "map": "gua_goblin", "pos": Vector2i(11, 20), "tier": 3},
	{"id": "gua_gob_2", "map": "gua_goblin", "pos": Vector2i(18, 20), "tier": 3},
	{"id": "gua_gob_3", "map": "gua_goblin", "pos": Vector2i(12, 7), "tier": 3},
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
	"##############PPPPPNN===NNPPPPP##############",
	"#..###...........f....=....AA##.............#",
	"#......TTTTTT....##..Y=....AA####....#......#",
	"#....f.TTTTTT..#####..=..U...####.........f.#",
	"#........f....#######f=....AA####...........#",
	"#.............#######.=....AA.##...........f#",
	"#.....=====================.......f.f.......#",
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


## Hutan Lebat (170x50): dua kali lebar Desa Awal. Pintu masuk dari Perbatasan di (22,0); jalan selebar 2 petak bercabang tiga (utara, tengah, selatan) dan semuanya bertemu di satu persimpangan tepat di depan gerbang Gua Goblin (146..147, 44..45). Singgasana bos K ada di dekat gerbang itu, dan tembok gerbang dari batu.
const HUTAN_ROWS: Array[String] = [
	"######################=###################################################################################################################################################",
	"###.#####..##....f....==........#..#########.........#####################...########......###########..................#####.......#############..................#######",
	"##....#......f........==.............####............R##########......#####..####...........##########.................#####...f.......######.......................######",
	"##....................==f..........f...R..............#########........#########............##########....f.###.......######...........#####...........####...........####",
	"##....................==...............f.............##########.........#######.............##########.....####......########.........###...f...........###...........####",
	"##........f...........==.................##...f.....###########..........#####...............#########....#####....R.#.######..f.....###.................##..R..##....####",
	"##....................==........##.f.....##.........###########..........####.................#######....#####.....f......###f.......###....~f.........f.......###...#####",
	"##.....##............#==........###................###########..........#####..........ff......#####....#####.........f....#f.........##..~~~~~...##...........###...#####",
	"###...###...#......f..==...f....###................#######...f........########..................###.....####.............................~~~~~~~..###..........f#.....####",
	"###...###..##.........==........###......f.........######.......f..###############........###............##.............f.................~~~~~f.####.................####",
	"###...###...###.......==........##....##...........######...~f.....################.......###.......................f.................#.....~....#####...##............###",
	"####..###f..###.......==============================================================================================================================================....##",
	"#########....#......##==============================================================================================================================================....##",
	"########..............==...#..f.......####..#.#f#.#......##.....#..f#...#...f#....ff...#..#.###.###.f....#.....##...#f.#.....##....######.........#####.........f.==....##",
	"#.....#...............==#......f.....####......##...f.#.....~.............####...........###.........####............f..#.f..##...##########.......####...........==...###",
	"#....f.#.............#==##R.....#########................f...............######..........###......................f....##....#...############......f###f..........==.#####",
	"##....###..........##.==###....##########..........f.....................######...##.....###.....#..............#...........##....###..######........##...f.......==######",
	"##...####.........###.==#################R...............................#####......f.#...##.........f.......f.###.f.....#.##..........######........###..........==######",
	"##...###f.........####==#################.....f...........................####.............#....................###.f....###...........######.......#####.........==.#####",
	"#...####....####...###==.################....#..........................f.####....f.##.....f............................#f.............######.....f.#####.........==....##",
	"#..##############.....==.######.....####...f###..f.........................###......#.#.ff.............................#................#####.......#####.........==.....#",
	"################......==.######......f.......#.......................#.....##.....f.##f......f.f.........................................####.....f..###..........==.....#",
	"###############......f==.######..............f.f............##....#####.....#.....Rf#f..R..........##.......###.................................................##==.....#",
	"#############.........==.#######.............R.............############..............#.......f....######...#####.......#..##..........f.........................##==.....#",
	"############..........==============================================================================================================================.....f...R.f##==...f.#",
	"############..........==============================================================================================================================...f.f......##==#....#",
	"############..........==....###...................###..###....#####................f...#.f#.#.#...f.#.....#.##.f#f#.###...............#f.#...f...#==...........###==##..##",
	"#####...####...####...==....###....................................f......#...........#.......#####.......##############f.########.R.######.......==........######==######",
	"#.......###...######..==..ff##..f...f...f............f...................###...ff.R.##..R.....#####.....###############..f#######.....####......f.==........f#####==######",
	"#.......##...#######..==......f.....................R.............##...f####..f......#........#######f.###########...##...######.......###.....##.==........######==######",
	"#.......##.R.#######..==....................f........##.......#######...####..f...........f..########..###########.R..##f.#####.........#......##.==#...f...####..==.#####",
	"##.....##...########.#==.#......f....................###.R...########...###ff...............###..####.....####.###.........###.........R.......##.==#f..f.f.###...==.#####",
	"##.....##...########..==###.....f.................f...###...f#######....###................###.............########.....##..##....................==#......###....==.#####",
	"##.....##....#######.f==###......#...............f.....###...######.....##.......f..#......###.f...........########.........##......f.f........f..==...........f..==.#####",
	"##.....##.......#####.==###.....###........##...........##...######....###....f.....##......##.....f......##########........###f.....#............==..............==.#####",
	"#.....###........####.==###......#........##..........f..#....####R...####..........#......###...........###########..f......###.....f............==#.##..........==.#####",
	"#....#####..R....####.==##...f..........~..#....f........##..####....f###...........#f########...........##########....f#.....###............#####==####..........==######",
	"#....######.....#####f==##.....#.#.#..#.#.#..##..ff..###.####.#.#.f....#.##.....#.#.#f########...........#####R..#.............#............######==.###..f.......==###..#",
	"##..#################.==.#.##f###..#f.#...#.....###...#....#.#.##...##f....#...#f.##.#..######...........##..............#...f............f.######==f###..........==###..#",
	"#####################.==#...#f.#...f...#..#.f#...#......#.#......##.#......f#f.#f...##..######f.......................~..##.###.###.####.f...##f..==.##...........==######",
	"#####################f==................~.......f..........########.........##......##.######........................~~.#.f#..##f.#.f.f....#.#f.#.==##............==######",
	"####################..==..............f...........f........#########........##........######..........................~~#...##...#..##..#.#.##...f==...ff...#.....==######",
	"################......==...###...............f.f......f.....###..####.......###.......#####................f.........f..~...........ff.......f....==#.##...###....==.#####",
	"###..##########.......==f..###...............................#...#####......####......##....f......................ff....f.f..........ff.R........==......####....==..####",
	"##.....#######......##==============================================================================================================================================...###",
	"##.........###...f####==============================================================================================================================================...###",
	"#...........###..########.####....................................f....###....###...###..................####.f....f........###.........##........==......###...#####...##",
	"##.##..f...###################.........f..............####.............###....###...###..f...............####........###....##..........###.f.Kf..==..f...####.######..###",
	"######....####################......................#######..........f#####..####.f#####..###...........######.......###...............####.......==......###########..###",
	"#PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPNN==NNPPPPPPPPPPPPPPPPPPP#",
]

## Gua Goblin (25x30): peta 3, terbuka setelah tiga Goblin di Hutan Lebat kalah.
const GUA_GOBLIN_ROWS: Array[String] = [
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRMMMMMMMMMMMMMMMMMRRRR",
	"RRRRMGGGGMMMMMMMGGGGMRRRR",
	"RRRRMGGGGMGGGGGMGGGGMRRRR",
	"RRRRMGGGGMGGGGGMGGGGMRRRR",
	"RRRRMMMMMMGGGGGMMMMMRRRRR",
	"RRRRMMRMMMMMMMMMMMMMMRRRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRMMMMMMMMMMMRMMMMMMMMMRR",
	"RRMGGGGMMMMMMRMMMGGGGMMRR",
	"RRMGGGGMMMMMMRMMMGGGGRMRR",
	"RRMGGGGMMMMMMRMMMGGGGMMRR",
	"RRMGGGGMMMMMMRMMMGGGGMMRR",
	"RRMMMMMMMMMMMRMMMMMMRMMRR",
	"RRMMMMMMRMMMMRMMMMMMMMMRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRRRRRRRRRMMMMMRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
	"RRRRRRRRRRRMMMRRRRRRRRRRR",
]


## Ruangan dalam bangunan (9x8). H = dinding, = = lantai, D = pintu keluar, S = meja kasir, x = lantai di belakang meja
## (tempat penjaga; tak terjangkau pemain), R = rak (toko ramuan, rumah makan) / ranjang (rumah sehat),
## F = tong (toko ramuan) / meja makan (rumah makan) / tanaman (rumah sehat). Bentuknya digambar interior.gd.
const TOKO_ROWS: Array[String] = [
	"HHHHHHHHH",
	"HRRRRRRRH",
	"HxxxxxxxH",
	"HSSSSSSSH",
	"H=======H",
	"HF=====FH",
	"H=======H",
	"HHHHDHHHH",
]
const MAKAN_ROWS: Array[String] = [
	"HHHHHHHHH",
	"HRRRRRRRH",
	"HxxxxxxxH",
	"HSSSSSSSH",
	"H=======H",
	"H=FF=FF=H",
	"H=======H",
	"HHHHDHHHH",
]
const ALAT_ROWS: Array[String] = [
	"HHHHHHHHH",
	"HRRRRRRRH",
	"HxxxxxxxH",
	"HSSSSSSSH",
	"H=======H",
	"HF=====FH",
	"H=======H",
	"HHHHDHHHH",
]
const AULA_ROWS: Array[String] = [
	"HHHHHHHHHHH",
	"HRRRRRRRRRH",
	"H=========H",
	"H=========H",
	"HF=======FH",
	"H=========H",
	"H=========H",
	"HHHHHDHHHHH",
]
const SEHAT_ROWS: Array[String] = [
	"HHHHHHHHH",
	"HRRxxxRRH",
	"HxxxxxxxH",
	"HSSSSSSSH",
	"H=======H",
	"HF=====FH",
	"H=======H",
	"HHHHDHHHH",
]


static func is_interior(map_id: String) -> bool:
	return INTERIORS.has(map_id)


## Pintu di (x, y) berupa {pos, to, at}, atau {} bila bukan pintu.
static func exit_at(map_id: String, x: int, y: int) -> Dictionary:
	for e: Dictionary in EXITS.get(map_id, []):
		if e.pos == Vector2i(x, y):
			return e
	return {}


## Gerbang Gua Goblin di Hutan Lebat terkunci sampai tiga Goblin kalah (`hutan_wave` dari Session.player.state.hutan).
static func exit_locked(map_id: String, x: int, y: int, hutan_wave: int) -> bool:
	return map_id == HUTAN and y == 49 and x >= 146 and x <= 147 and hutan_wave < 3


static func rows(map_id: String) -> Array[String]:
	match map_id:
		DEFAULT_MAP:
			return DESA_AWAL
		PERBATASAN:
			return PERBATASAN_ROWS
		HUTAN:
			return HUTAN_ROWS
		GUA_GOBLIN:
			return GUA_GOBLIN_ROWS
		GUNUNG:
			return GUNUNG_ROWS
		GUA:
			return GUA_ROWS
		TOKO_RAMUAN:
			return TOKO_ROWS
		RUMAH_MAKAN:
			return MAKAN_ROWS
		RUMAH_SEHAT:
			return SEHAT_ROWS
		TOKO_ALAT:
			return ALAT_ROWS
		AULA:
			return AULA_ROWS
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
