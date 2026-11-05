extends RefCounted
## Data peta. SEMENTARA ditulis di kode sebagai teks; nanti diganti TileMap dari
## gambar ilustrator. Saat server menjadi otoritatif, tabrakan dihitung di server.
##
## Lambang:  .  rumput   #  pohon (halangan)   ~  air (halangan)
##           =  jalan    H  rumah (halangan)

const DEFAULT_MAP := "desa_awal"
const SPAWN := Vector2i(5, 5)

const DESA_AWAL: Array[String] = [
	"###############",
	"#.............#",
	"#..HHH....~~..#",
	"#..HHH....~~..#",
	"#..H=H........#",
	"#...=.........#",
	"#...=====.....#",
	"#.........#...#",
	"#.........#...#",
	"#..~~.....#...#",
	"#..~~.........#",
	"#.............#",
	"#....###......#",
	"#....###......#",
	"#.............#",
	"#.......~~~...#",
	"#.......~~~...#",
	"#.............#",
	"#.............#",
	"###############",
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
	return t == "." or t == "="
