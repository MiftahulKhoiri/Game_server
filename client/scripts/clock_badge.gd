class_name ClockBadge
extends Control
## Jam di tengah atas layar (antara nama pemain dan tombol Menu): lencana pil gelap berisi ikon
## matahari (siang), bulan (malam), atau gua, lalu tulisan waktu, mis. "Siang 13:37".
## Digambar dengan kode; lebarnya menyesuaikan tulisan dan tetap berpusat di `center_x`.

const FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const H := 44.0
const PAD := 14.0
const ICON_W := 38.0
const FONT_SIZE := 24
const MAX_TEXT_W := 170.0

var center_x := 440.0
var _kind := "sun"
var _text := ""
var _fs := FONT_SIZE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(150.0, H)


## kind: "sun" | "moon" | "cave".
func set_info(kind: String, text: String) -> void:
	if kind == _kind and text == _text:
		return
	_kind = kind
	_text = text
	# Tulisan panjang (mis. "Malam 22:17, hujan") diperkecil supaya tidak menabrak tombol Menu.
	_fs = FONT_SIZE
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	while w > MAX_TEXT_W and _fs > 16:
		_fs -= 2
		w = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	size = Vector2(PAD + ICON_W + w + PAD, H)
	position.x = center_x - size.x / 2.0
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var pts := MenuBubble.pill(r, 12)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 3))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	draw_colored_polygon(pts, Color(0.07, 0.1, 0.16, 0.78))
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_polyline(edge, Color(1, 1, 1, 0.28), 2.0, true)
	var c := Vector2(PAD + ICON_W * 0.5 - 2.0, H * 0.5)
	match _kind:
		"moon":
			_draw_moon(c)
		"cave":
			_draw_cave(c)
		_:
			_draw_sun(c)
	var ty := H * 0.5 + float(_fs) * 0.34
	var tx := PAD + ICON_W
	draw_string_outline(FONT, Vector2(tx, ty), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, 6, Color(0, 0, 0, 0.8))
	draw_string(FONT, Vector2(tx, ty), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Color("ffe9b0"))


func _draw_sun(c: Vector2) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * 11.0, c + d * 16.0, Color("ffb92e"), 3.0, true)
	draw_circle(c, 9.5, Color("c97a10"))
	draw_circle(c, 8.0, Color("ffd23c"))
	draw_circle(c + Vector2(-2.5, -2.5), 3.0, Color("fff4b0"))


func _draw_moon(c: Vector2) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		outer.append(c + Vector2(cos(a), sin(a)) * 12.5)
		inner.append(c + Vector2(6.5, -4.5) + Vector2(cos(a), sin(a)) * 10.5)
	var shapes := Geometry2D.clip_polygons(outer, inner)
	for poly: PackedVector2Array in shapes:
		if Geometry2D.is_polygon_clockwise(poly) and poly.size() > 2:
			continue
		draw_colored_polygon(poly, Color("e8eeff"))
	draw_circle(c + Vector2(9.0, -10.0), 1.6, Color("ffffff"))
	draw_circle(c + Vector2(13.0, 3.0), 1.3, Color("dfe8ff"))


func _draw_cave(c: Vector2) -> void:
	var arch := PackedVector2Array()
	arch.append(c + Vector2(-13, 11))
	arch.append(c + Vector2(-13, -1))
	for i in range(1, 12):
		var a := PI + PI * float(i) / 12.0
		arch.append(c + Vector2(cos(a) * 13.0, -1.0 + sin(a) * 12.0))
	arch.append(c + Vector2(13, -1))
	arch.append(c + Vector2(13, 11))
	draw_colored_polygon(arch, Color("8d949c"))
	var hole := PackedVector2Array()
	hole.append(c + Vector2(-6, 11))
	hole.append(c + Vector2(-6, 1))
	for i in range(1, 8):
		var a2 := PI + PI * float(i) / 8.0
		hole.append(c + Vector2(cos(a2) * 6.0, 1.0 + sin(a2) * 6.0))
	hole.append(c + Vector2(6, 1))
	hole.append(c + Vector2(6, 11))
	draw_colored_polygon(hole, Color("1a1d22"))
