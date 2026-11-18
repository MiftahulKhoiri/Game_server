extends RefCounted
## Kamera tidak menembus bangunan (paket adventure 1.3.0, dari review: di Desa kamera bisa masuk ke dinding
## rumah sehingga separuh layar gelap). Murah: berjalan di petak peta dari titik pandang ke arah kamera dan
## berhenti sebelum petak tinggi (rumah, tembok, pilar istana). Pohon dan batu tidak dihitung supaya kamera
## tidak terus maju-mundur di hutan dan lereng gunung.

const Maps = preload("res://games/adventure/scripts/maps.gd")

const STEP := 0.25        # langkah periksa (petak)
const MIN_DIST := 1.7     # sedekat-dekatnya kamera ke pahlawan
const MARGIN := 0.45      # jarak aman sebelum dinding


## Tinggi penghalang petak `t` di peta `map_id` (0 = tidak menghalangi kamera).
static func tinggi(t: String, map_id: String) -> float:
	match t:
		"H", "D":
			return 3.4
		"J", "C", "A", "U", "Q", "Y":
			return 2.2
		"S":
			if map_id == Maps.TAKHTA:
				return 4.6
			if map_id == Maps.ISTANA:
				return 3.6
			return 0.0
		"P":
			return 2.6 if map_id == Maps.ISTANA else 0.0
	return 0.0


## Jarak kamera terjauh (<= `dist`) dari `target` ke arah `dir` (satuan) yang tidak terhalang.
static func jarak(map_id: String, target: Vector3, dir: Vector3, dist: float) -> float:
	if Maps.is_interior(map_id):
		return dist
	var rows: Array = Maps.rows(map_id)
	if rows.is_empty():
		return dist
	var s := MIN_DIST
	while s <= dist:
		var p := target + dir * s
		var x := int(floor(p.x))
		var z := int(floor(p.z))
		if z >= 0 and z < rows.size() and x >= 0 and x < str(rows[z]).length():
			var h := tinggi(str(rows[z])[x], map_id)
			if h > 0.0 and p.y < h:
				return maxf(MIN_DIST, s - MARGIN)
		s += STEP
	return dist
