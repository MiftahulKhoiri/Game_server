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
	"desa_awal": [{"pos": Vector2i(7, 19), "to": "perbatasan", "at": Vector2i(7, 1)}],
	"perbatasan": [
		{"pos": Vector2i(7, 0), "to": "desa_awal", "at": Vector2i(7, 18)},
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

## Desa Awal (15x20): dua rumah di utara, alun-alun dengan sumur di tengah,
## sungai dengan jembatan, ladang di selatan, dan gerbang keluar di bawah
## (gerbang belum tersambung ke peta lain).
const DESA_AWAL: Array[String] = [
	"###############",
	"#..HHH...HHH..#",
	"#..HDH...HDH..#",
	"#..f=f...f=f..#",
	"#.#.=.....=.#.#",
	"#...=.....=...#",
	"#...=======...#",
	"#.....===.....#",
	"#.....=W=.....#",
	"#.#...===...#.#",
	"#......=......#",
	"#......=......#",
	"~~~~~~~B~~~~~~~",
	"~~~~~~~B~~~~~~~",
	"#......=......#",
	"#.TTT..=..TTT.#",
	"#.TTT..=..TTT.#",
	"#.FFF..=..FFF.#",
	"#......=......#",
	"#######=#######",
]


## NPC di peta. Kunci = id NPC (sama dengan id pemberi misi di server dan nama gambar
## di assets/characters/). NPC menghalangi jalan; bicara dari petak yang bersebelahan.
const NPCS := {
	"nenek_penjual": {"map": "desa_awal", "pos": Vector2i(3, 6), "name": "Nenek"},
	"petani": {"map": "desa_awal", "pos": Vector2i(11, 6), "name": "Petani"},
}


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
