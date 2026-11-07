extends RefCounted
## Data peta. SEMENTARA ditulis di kode sebagai teks; nanti diganti TileMap dari
## gambar ilustrator. Saat server menjadi otoritatif, tabrakan dihitung di server.
##
## Lambang (daftar gambar yang perlu dibuat ada di assets/README.md):
##   .  rumput          =  jalan tanah        f  bunga (bisa dilewati)
##   T  ladang          B  jembatan           D  pintu rumah (bisa dilewati)
##   #  pohon           ~  air                H  tembok/atap rumah
##   F  pagar           W  sumur              S  tembok batu (reruntuhan)
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
	"desa_awal": [{"pos": Vector2i(22, 49), "to": "perbatasan", "at": Vector2i(7, 1)}],
	"perbatasan": [
		{"pos": Vector2i(7, 0), "to": "desa_awal", "at": Vector2i(22, 48)},
		{"pos": Vector2i(7, 19), "to": "gunung_batu", "at": Vector2i(7, 1)},
	],
	"gunung_batu": [
		{"pos": Vector2i(7, 0), "to": "perbatasan", "at": Vector2i(7, 18)},
		{"pos": Vector2i(7, 19), "to": "gua_batu", "at": Vector2i(7, 1)},
	],
	"gua_batu": [{"pos": Vector2i(7, 0), "to": "gunung_batu", "at": Vector2i(7, 18)}],
}
const SPAWN := Vector2i(5, 5)
const WALKABLE := ".=fTBDMGK"
## Petak bos: menginjaknya memulai pertarungan bos di server (posisi harus sama dengan BossSpot di internal/game/world.go).
const BOSS_TILE := "K"
const ENCOUNTER_TILES := "TG"

## Desa Awal (45x50): tujuh rumah di utara, jalan raya timur-barat, alun-alun dengan sumur
## di tengah, dua kandang berpagar di kiri-kanan alun-alun, empat rumah di tengah desa, sungai
## dengan jembatan, empat ladang berpagar dan empat pondok tani di selatan, dua kolam, dan
## gerbang keluar di bawah (menuju Perbatasan).
const DESA_AWAL: Array[String] = [
	"#############################################",
	"#..HHH...HHH...HHH...HHH...HHH...HHH...HHH..#",
	"#..HDH...HDH...HDH...HDH...HDH...HDH...HDH..#",
	"#..f=f...f=f...f=f...f=f...f=f...f=f...f=f..#",
	"#...=.....=.....=.....=.....=.....=.....=...#",
	"#...=.....=.....=.....=.....=.....=.....=...#",
	"#..=======================================..#",
	"#..=======================================..#",
	"#..f....f........===========.....f....f.....#",
	"#..FFFFFFFFF..#..===========.#.#fFFFFFFFFF..#",
	"#..F.f..f..F.....===========.....F..f..f.F..#",
	"#..F..f....F...#.===========...#.F.......F..#",
	"#..F......fF.#...===========f#..fF......fF..#",
	"#..F..f....f...#.=====W=====...#....ff..fF..#",
	"#..F.f.....F.f...===========.....F.......F..#",
	"#..F...f...F.#.#f===========f#.#.F.......F..#",
	"#..FFFFFFFFF..f..===========.....FFFFFFFFF..#",
	"#............f#..===========..#.............#",
	"#..#..........f..===========.......#.....#..#",
	"#....HHH..#.HHH.......=.......HHHf...HHH....#",
	"#...fHDH....HDH.......=.......HDH.#..HDH.#..#",
	"#..#.f=f..#ff=ff#.#...=...#.#.f=f....f=f....#",
	"#.....=...f..=........=........=..#f..=..#..#",
	"#.........f...........=.......f..........ff.#",
	"~~~~~~~~~~~~~~~~~~~~~~B~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~B~~~~~~~~~~~~~~~~~~~~~~",
	"#.......f....f........=...................f.#",
	"#..FFFFFFFF..#.#.#.#..=.f...#.#.#.FFFFFFFF..#",
	"#..FTTTTTTF.......f...=...#.......FTTTTTTF..#",
	"#..FTTTTTT..#.HHH..#..=.....HHH.#..TTTTTTF..#",
	"#..FTTTTTTF...HDH.....=..#..HDH...FTTTTTTF..#",
	"#..FTTTTTTF.#.f=f..#..=..f..f=f.#.FTTTTTTF..#",
	"#..FFFFFFFF...f=......=...#.f=....FFFFFFFF..#",
	"#.......ff..#f...f.#..=...f.............f...#",
	"#.....ff......#..#ff..=..#.#...#............#",
	"#..FFFFFFFF.#......#..=......#....FFFFFFFF..#",
	"#..FTTTTTTF....#.#....=..#.#...#..FTTTTTTF..#",
	"#..FTTTTTT..#......#..=.......f....TTTTTTF..#",
	"#..FTTTTTTF...HHH.....=.....HHH...FTTTTTTF..#",
	"#..FTTTTTTF...HDH.#...=..#..HDH.#.FTTTTTTF..#",
	"###FFFFFFFF.#.f=f.....=.....f=f...FFFFFFFF###",
	"###............=..#.f.=..f#..=..#.........###",
	"###........#.#........=...................###",
	"###~~~~~~.......#.#...=..#....f.f#..~~~~~~###",
	"###~~~~~~..#..#.......=....#.#.#f...~~~~~~###",
	"###~~~~~~.f....f..#...=..#f.......f.~~~~~~###",
	"###~~~~~~.......#f....=....#...#f#..~~~~~~###",
	"###........#f.#....#..=..#...#f..........f###",
	"###...................=...................###",
	"######################=######################",
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
const WARGA := [
	{"id": "bu_sari", "model": "warga_ibu", "name": "Bu Sari", "map": "desa_awal", "pos": Vector2(15.5, 9.5), "radius": 5.0, "speed": 0.7},
	{"id": "mbak_dewi", "model": "warga_ibu2", "name": "Mbak Dewi", "map": "desa_awal", "pos": Vector2(29.5, 10.5), "radius": 5.0, "speed": 0.75},
	{"id": "pak_joko", "model": "warga_bapak", "name": "Pak Joko", "map": "desa_awal", "pos": Vector2(22.5, 17.5), "radius": 6.0, "speed": 0.7},
	{"id": "pak_budi", "model": "warga_bapak2", "name": "Pak Budi", "map": "desa_awal", "pos": Vector2(22.5, 40.5), "radius": 7.0, "speed": 0.8},
	{"id": "rina", "model": "anak_desa", "name": "Rina", "map": "desa_awal", "pos": Vector2(19.5, 12.5), "radius": 5.0, "speed": 1.1},
	{"id": "dika", "model": "anak_desa", "name": "Dika", "map": "desa_awal", "pos": Vector2(25.5, 14.5), "radius": 5.0, "speed": 1.2},
	{"id": "penjaga", "model": "pendekar_tombak", "name": "Penjaga", "map": "desa_awal", "pos": Vector2(22.5, 46.5), "radius": 3.5, "speed": 0.6},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(5.5, 12.5), "radius": 2.2, "speed": 0.6},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(8.5, 11.5), "radius": 2.2, "speed": 0.7},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(36.5, 12.5), "radius": 2.2, "speed": 0.6},
	{"id": "ayam", "model": "tikus_sawah", "name": "Ayam", "map": "desa_awal", "pos": Vector2(39.5, 11.5), "radius": 2.2, "speed": 0.7},
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


## Perbatasan Kerajaan (15x20): jalan raja dari gerbang desa di utara, ladang yang
## dirusak monster, dan reruntuhan benteng di tengah. Jalan di selatan naik ke Gunung Batu.
const PERBATASAN_ROWS: Array[String] = [
	"#######=#######",
	"#......=......#",
	"#.TT...=...TT.#",
	"#.TT...=...TT.#",
	"#......=......#",
	"#.##...=...##.#",
	"#.##...=...##.#",
	"#......=......#",
	"#..SSS.=.SSS..#",
	"#..S.......S..#",
	"#..S..TTT..S..#",
	"#..S..TTT..S..#",
	"#..SSS.=.SSS..#",
	"#......=......#",
	"#.TT...=...TT.#",
	"#.TT...=...TT.#",
	"#......=......#",
	"#......=......#",
	"#......=......#",
	"#######=#######",
]


## Gunung Batu (15x20): lereng berbatu, sarang Monster Batu. Satu-satunya jalan masuk
## dari utara; kerikil (G) adalah tempat monster berkeliaran.
const GUNUNG_ROWS: Array[String] = [
	"RRRRRRRMRRRRRRR",
	"RMMMMMMMMMMMMMR",
	"RMGGMMMMMMGGGMR",
	"RMGGMRRMMRGGGMR",
	"RMMMMRRMMRMMMMR",
	"RMMMMMMMMMMMMMR",
	"RRRMMGGGGGMMRRR",
	"RRRMMGGGGGMMRRR",
	"RMMMMMMMMMMMMMR",
	"RMGGMRRMMRGGGMR",
	"RMGGMRRMMRGGGMR",
	"RMMMMMMMMMMMMMR",
	"RRMMMGGGGGMMMRR",
	"RRMMMGGGGGMMMRR",
	"RRRMMMMMMMMMRRR",
	"RRRRMMMGMMMRRRR",
	"RRRRRMGGGMRRRRR",
	"RRRRRMGGGMRRRRR",
	"RRRRRMMMMMRRRRR",
	"RRRRRRRMRRRRRRR",
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
