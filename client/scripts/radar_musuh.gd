extends Control
## Radar Musuh (pemberian Kapten Rimba) di layar Hutan Lebat: lingkaran kecil dengan pemain di tengah dan satu
## titik merah per musuh di sekitarnya. Atas layar radar = arah pandang kamera, sama dengan panah di papan misi.
## Musuh yang lebih jauh dari RANGE petak digambar pudar di tepi lingkaran supaya arahnya tetap terbaca.
## v0.69.1: rute jalan (petak "=") ikut tergambar, besar titik mengikuti besar musuh (kecil / sedang /
## besar), dan bos tampil sebagai tengkorak merah.

const SIZE := 150.0  # layar mendatar (v0.68.2): di kiri, di antara status dan joystick
const RANGE := 26.0                         # jangkauan radar (petak)
const ROAD_TILE := "="
const DOT_R := [2.6, 4.0, 5.8]              # jari-jari titik musuh kecil / sedang / besar
const ROAD_C := Color(0.93, 0.8, 0.52, 0.5)
const SKULL_C := Color(1.0, 0.16, 0.12)

var player := Vector2.ZERO
var cam_yaw := 0.0
var dots: Array[Vector2] = []               # posisi dunia (petak) tiap musuh biasa
var sizes: Array[int] = []                  # kelas ukuran tiap titik: 0 kecil, 1 sedang, 2 besar
var boss := Vector2(-1, -1)                 # posisi Goblin bos; (-1, -1) = tidak ada
var roads := PackedVector2Array()           # pusat petak jalan di peta ini
var _road_map := ""


func _init() -> void:
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Kelas ukuran musuh dari sisi terpanjang badannya (m): 0 kecil (kancil, rubah, kelelawar),
## 1 sedang (ular, babi, serigala, goblin), 2 besar (beruang, orc, kepala goblin).
const SMALL_MAX := 1.4
const MEDIUM_MAX := 2.3

static func size_class(bulk: float) -> int:
	if bulk < SMALL_MAX:
		return 0
	if bulk < MEDIUM_MAX:
		return 1
	return 2


## Menyimpan pusat semua petak jalan sebuah peta (sekali per peta).
func set_roads(map_id: String, rows: Array[String]) -> void:
	if map_id == _road_map:
		return
	_road_map = map_id
	roads = PackedVector2Array()
	for y in rows.size():
		var row := rows[y]
		for x in row.length():
			if row[x] == ROAD_TILE:
				roads.append(Vector2(x + 0.5, y + 0.5))


func update_view(p: Vector2, yaw: float, enemies: Array[Vector2], boss_at := Vector2(-1, -1), enemy_sizes: Array[int] = []) -> void:
	player = p
	cam_yaw = yaw
	dots = enemies
	sizes = enemy_sizes
	boss = boss_at
	queue_redraw()


## Letak titik pada radar (piksel dari tengah) untuk titik dunia `target`; `clamped` = di luar jangkauan.
static func blip(from: Vector2, target: Vector2, yaw: float, radius: float) -> Dictionary:
	var d := target - from
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var v := Vector2(d.dot(right), -d.dot(fwd)) * (radius / RANGE)
	var out := v.length() > radius - 5.0
	if out:
		v = v.normalized() * (radius - 5.0)
	return {"at": v, "clamped": out}


func _draw() -> void:
	var c := Vector2(SIZE, SIZE) / 2.0
	var r := SIZE / 2.0 - 3.0
	draw_circle(c, r, Color(0.03, 0.12, 0.05, 0.72))
	_draw_roads(c, r)
	for k in [0.33, 0.66, 1.0]:
		draw_arc(c, r * k, 0.0, TAU, 48, Color(0.35, 0.9, 0.45, 0.5 if k == 1.0 else 0.28), 2.0, true)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(0.35, 0.9, 0.45, 0.2), 1.5)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(0.35, 0.9, 0.45, 0.2), 1.5)
	# musuh besar digambar dulu supaya titik kecil di dekatnya tetap terlihat
	for cls in [2, 1, 0]:
		for i in dots.size():
			if _size_of(i) != cls:
				continue
			var b := blip(player, dots[i], cam_yaw, r)
			var rad: float = DOT_R[cls] * (0.75 if b.clamped else 1.0)
			var col := Color(1.0, 0.25, 0.2, 0.45 if b.clamped else 1.0)
			draw_circle(c + (b.at as Vector2), rad, col)
			if cls == 2:
				draw_arc(c + (b.at as Vector2), rad, 0.0, TAU, 16, Color(0.25, 0.0, 0.0, 0.9), 1.5, true)
	if boss.x >= 0.0:
		var bb := blip(player, boss, cam_yaw, r)
		_draw_skull(c + (bb.at as Vector2), 0.95 if bb.clamped else 1.2)
	# pemain: segitiga putih menghadap atas
	var tri := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)])
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.9), 1.5)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(c.x - 30, SIZE - 2), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(c.x - 30, SIZE - 2), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("9bf0a8"))


func _size_of(i: int) -> int:
	return sizes[i] if i < sizes.size() else 1


## Rute jalan: tiap petak jalan dalam jangkauan jadi bintik krem; bersama-sama membentuk garis jalan.
func _draw_roads(c: Vector2, r: float) -> void:
	if roads.is_empty():
		return
	var k := r / RANGE
	var lim := (r - 2.0) / k
	var lim2 := lim * lim
	var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
	var dot_r := maxf(1.5, k * 0.65)
	for t in roads:
		var d := t - player
		if d.length_squared() > lim2:
			continue
		draw_circle(c + Vector2(d.dot(right), -d.dot(fwd)) * k, dot_r, ROAD_C)


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
