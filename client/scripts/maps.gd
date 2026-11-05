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
