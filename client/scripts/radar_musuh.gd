extends Control
## Radar Musuh (pemberian Kapten Rimba) di layar Hutan Lebat: lingkaran kecil dengan pemain di tengah dan satu
## titik merah per musuh di sekitarnya. Atas layar radar = arah pandang kamera, sama dengan panah di papan misi.
## Musuh yang lebih jauh dari RANGE petak digambar pudar di tepi lingkaran supaya arahnya tetap terbaca.

const SIZE := 176.0
const RANGE := 26.0                         # jangkauan radar (petak)

var player := Vector2.ZERO
var cam_yaw := 0.0
var dots: Array[Vector2] = []               # posisi dunia (petak) tiap musuh biasa
var boss := Vector2(-1, -1)                 # posisi Goblin bos; (-1, -1) = tidak ada


func _init() -> void:
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_view(p: Vector2, yaw: float, enemies: Array[Vector2], boss_at := Vector2(-1, -1)) -> void:
	player = p
	cam_yaw = yaw
	dots = enemies
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
	for k in [0.33, 0.66, 1.0]:
		draw_arc(c, r * k, 0.0, TAU, 48, Color(0.35, 0.9, 0.45, 0.5 if k == 1.0 else 0.28), 2.0, true)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(0.35, 0.9, 0.45, 0.2), 1.5)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(0.35, 0.9, 0.45, 0.2), 1.5)
	for e: Vector2 in dots:
		var b := blip(player, e, cam_yaw, r)
		var col := Color(1.0, 0.25, 0.2, 0.45 if b.clamped else 1.0)
		draw_circle(c + (b.at as Vector2), 4.0 if not b.clamped else 3.0, col)
	if boss.x >= 0.0:
		var bb := blip(player, boss, cam_yaw, r)
		draw_circle(c + (bb.at as Vector2), 7.0, Color(1.0, 0.62, 0.15, 1.0))
		draw_arc(c + (bb.at as Vector2), 7.0, 0.0, TAU, 16, Color(0, 0, 0, 0.9), 2.0, true)
	# pemain: segitiga putih menghadap atas
	var tri := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)])
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.9), 1.5)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(c.x - 30, SIZE - 2), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(c.x - 30, SIZE - 2), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("9bf0a8"))
