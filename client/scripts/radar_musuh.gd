extends Control
## Radar Musuh (pemberian Kapten Rimba) di layar wilayah ujian: pemain di tengah, satu titik merah per musuh di
## sekitarnya. Atas layar radar = arah pandang kamera, sama dengan panah di papan misi. Musuh di luar jangkauan
## digambar pudar di tepi supaya arahnya tetap terbaca.
## v0.69.1: rute jalan (petak "=") ikut tergambar, besar titik mengikuti besar musuh (kecil / sedang / besar),
## bos tampil sebagai tengkorak merah.
## v0.70.0: radar persegi panjang yang lebih lebar. Di peta berdinding batu (Gua Goblin, Gunung Batu) lantai
## lorong, sungai, dan jembatan ikut digambar seperti peta kecil, supaya lorong buntu terlihat dari jauh.

const W := 220.0                            # lebar radar (piksel, layar mendatar)
const H := 150.0
const SIZE := H                             # (nama lama) tinggi radar, dipakai tata letak lain
const RANGE := 26.0                         # jangkauan (petak) untuk blip() lama; radar persegi memakai PX
const PX := 3.0                             # piksel per petak di radar persegi
const ROAD_TILE := "="
const FLOOR_TILES := "MGBX="                # lantai yang digambar di peta berdinding batu
const DOT_R := [2.6, 4.0, 5.8]              # jari-jari titik musuh kecil / sedang / besar
const ROAD_C := Color(0.93, 0.8, 0.52, 0.6)
const FLOOR_C := Color(0.62, 0.58, 0.5, 0.42)
const WATER_C := Color(0.25, 0.55, 0.85, 0.7)
const BRIDGE_C := Color(0.72, 0.5, 0.28, 0.9)
const SKULL_C := Color(1.0, 0.16, 0.12)
## Kelas ukuran musuh dari sisi terpanjang badannya (m): 0 kecil (kancil, rubah, kelelawar),
## 1 sedang (ular, babi, serigala, goblin), 2 besar (beruang, orc, kepala goblin).
const SMALL_MAX := 1.4
const MEDIUM_MAX := 2.3

var player := Vector2.ZERO
var cam_yaw := 0.0
var dots: Array[Vector2] = []               # posisi dunia (petak) tiap musuh biasa
var sizes: Array[int] = []                  # kelas ukuran tiap titik: 0 kecil, 1 sedang, 2 besar
var boss := Vector2(-1, -1)                 # posisi bos; (-1, -1) = tidak ada
var roads := PackedVector2Array()           # petak jalan (pojok kiri-atas) di peta ini
var floors := PackedVector2Array()          # petak lantai lorong (hanya peta berdinding batu)
var waters := PackedVector2Array()
var bridges := PackedVector2Array()
var _road_map := ""


func _init() -> void:
	size = Vector2(W, H)
	clip_contents = true  # peta kecil yang berputar dipotong rapi di tepi kotak
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func size_class(bulk: float) -> int:
	if bulk < SMALL_MAX:
		return 0
	if bulk < MEDIUM_MAX:
		return 1
	return 2


## Menyimpan petak jalan, lantai, air, dan jembatan sebuah peta (sekali per peta).
func set_roads(map_id: String, rows: Array[String]) -> void:
	if map_id == _road_map:
		return
	_road_map = map_id
	roads = PackedVector2Array()
	floors = PackedVector2Array()
	waters = PackedVector2Array()
	bridges = PackedVector2Array()
	var walled := false
	for row in rows:
		if row.contains("R"):
			walled = true
			break
	for y in rows.size():
		var row := rows[y]
		for x in row.length():
			var t := row[x]
			var p := Vector2(x, y)
			if t == ROAD_TILE:
				roads.append(p)
			elif t == "~":
				waters.append(p)
			elif t == "B":
				bridges.append(p)
			elif walled and FLOOR_TILES.contains(t):
				floors.append(p)


func update_view(p: Vector2, yaw: float, enemies: Array[Vector2], boss_at := Vector2(-1, -1), enemy_sizes: Array[int] = []) -> void:
	player = p
	cam_yaw = yaw
	dots = enemies
	sizes = enemy_sizes
	boss = boss_at
	queue_redraw()


## Letak titik pada radar bundar lama (piksel dari tengah) untuk titik dunia `target`; `clamped` = di luar jangkauan.
static func blip(from: Vector2, target: Vector2, yaw: float, radius: float) -> Dictionary:
	var d := target - from
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var v := Vector2(d.dot(right), -d.dot(fwd)) * (radius / RANGE)
	var out := v.length() > radius - 5.0
	if out:
		v = v.normalized() * (radius - 5.0)
	return {"at": v, "clamped": out}


## Letak titik pada radar persegi (piksel dari tengah); dijepit ke tepi kotak bila di luar jangkauan.
static func blip_rect(from: Vector2, target: Vector2, yaw: float) -> Dictionary:
	var d := target - from
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var v := Vector2(d.dot(right), -d.dot(fwd)) * PX
	var half := Vector2(W, H) * 0.5 - Vector2(6, 6)
	var k := maxf(absf(v.x) / half.x, absf(v.y) / half.y)
	var out := k > 1.0
	if out:
		v /= k
	return {"at": v, "clamped": out}


func _draw() -> void:
	var c := Vector2(W, H) / 2.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.1, 0.05, 0.75)
	box.set_corner_radius_all(10)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	_draw_map(c)
	draw_set_transform(Vector2.ZERO)
	for k in [0.33, 0.66]:
		draw_arc(c, H * 0.5 * k, 0.0, TAU, 40, Color(0.35, 0.9, 0.45, 0.2), 1.5, true)
	draw_line(Vector2(0, c.y), Vector2(W, c.y), Color(0.35, 0.9, 0.45, 0.16), 1.5)
	draw_line(Vector2(c.x, 0), Vector2(c.x, H), Color(0.35, 0.9, 0.45, 0.16), 1.5)
	# musuh besar digambar dulu supaya titik kecil di dekatnya tetap terlihat
	for cls in [2, 1, 0]:
		for i in dots.size():
			if _size_of(i) != cls:
				continue
			var b := blip_rect(player, dots[i], cam_yaw)
			var rad: float = DOT_R[cls] * (0.75 if b.clamped else 1.0)
			var col := Color(1.0, 0.25, 0.2, 0.45 if b.clamped else 1.0)
			draw_circle(c + (b.at as Vector2), rad, col)
			if cls == 2:
				draw_arc(c + (b.at as Vector2), rad, 0.0, TAU, 16, Color(0.25, 0.0, 0.0, 0.9), 1.5, true)
	if boss.x >= 0.0:
		var bb := blip_rect(player, boss, cam_yaw)
		_draw_skull(c + (bb.at as Vector2), 0.95 if bb.clamped else 1.2)
	# pemain: segitiga putih menghadap atas
	var tri := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)])
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.9), 1.5)
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.border_color = Color(0.35, 0.9, 0.45, 0.6)
	edge.set_border_width_all(2)
	edge.set_corner_radius_all(10)
	draw_style_box(edge, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(8, 16), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(8, 16), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("9bf0a8"))


func _size_of(i: int) -> int:
	return sizes[i] if i < sizes.size() else 1


## Peta kecil di bawah titik musuh: tiap petak digambar sebagai kotak 1x1 dalam koordinat dunia yang diputar
## mengikuti kamera (rotasi = cam_yaw, sama dengan rumus blip), lalu dipotong tepi kotak radar.
func _draw_map(c: Vector2) -> void:
	draw_set_transform(c, cam_yaw, Vector2(PX, PX))
	var reach := Vector2(W, H).length() * 0.5 / PX + 1.0
	var r2 := reach * reach
	var one := Vector2(1.02, 1.02)
	for arr: Array in [[floors, FLOOR_C], [waters, WATER_C], [bridges, BRIDGE_C], [roads, ROAD_C]]:
		var tiles: PackedVector2Array = arr[0]
		var col: Color = arr[1]
		for t in tiles:
			var d := t - player
			if d.length_squared() > r2:
				continue
			draw_rect(Rect2(d, one), col)


## Tengkorak merah untuk bos: tempurung, rahang bergigi, dua rongga mata dan hidung.
func _draw_skull(p: Vector2, k: float) -> void:
	var dark := Color(0.12, 0.0, 0.0, 0.95)
	draw_circle(p + Vector2(0, -1.5) * k, 9.5 * k, dark)  # tepi gelap agar terbaca di atas titik lain
	draw_rect(Rect2(p + Vector2(-6.5, 2.5) * k, Vector2(13, 8) * k), dark)
	draw_circle(p + Vector2(0, -1.5) * k, 8.0 * k, SKULL_C)
	draw_rect(Rect2(p + Vector2(-5, 3) * k, Vector2(10, 6) * k), SKULL_C)
	draw_circle(p + Vector2(-3.3, -1.5) * k, 2.4 * k, dark)
	draw_circle(p + Vector2(3.3, -1.5) * k, 2.4 * k, dark)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, 1.2) * k, p + Vector2(-1.4, 3.6) * k, p + Vector2(1.4, 3.6) * k]), dark)
	for x in [-2.5, 0.0, 2.5]:
		draw_line(p + Vector2(x, 6) * k, p + Vector2(x, 9) * k, dark, 1.2)
