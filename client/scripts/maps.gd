extends RefCounted
## Data peta. SEMENTARA ditulis di kode sebagai teks; nanti diganti TileMap dari
## gambar ilustrator. Saat server menjadi otoritatif, tabrakan dihitung di server.
##
## Lambang (daftar gambar yang perlu dibuat ada di assets/README.md):
##   .  rumput          =  jalan tanah        f  bunga (bisa dilewati)
##   T  ladang          B  jembatan           D  pintu rumah (bisa dilewati)
##   #  pohon           ~  air                H  tembok/atap rumah
##   F  pagar           W  sumur
## Yang bisa dilewati: . = f T B D   (sisanya menghalangi)

const DEFAULT_MAP := "desa_awal"
const SPAWN := Vector2i(5, 5)
const WALKABLE := ".=fTBD"

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


static func rows(map_id: String) -> Array[String]:
	if map_id == DEFAULT_MAP:
		return DESA_AWAL
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
