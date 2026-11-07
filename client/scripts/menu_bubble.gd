class_name MenuBubble
extends Button
## Tombol Menu bergaya "gelembung": pil biru mengilap dengan kilau di atas, tepi gelap-terang,
## ikon tiga garis dan tulisan "Menu" berfont game. Digambar dengan kode; saat ditekan
## warnanya menggelap dan isinya turun sedikit. Tetap sebuah Button biasa (sinyal pressed).

const FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const TOP := Color("7fd0ff")
const BOTTOM := Color("1f66d6")
const EDGE := Color("12336e")
const LABEL := "Menu"


func _init() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


## Titik-titik pil (persegi panjang bulat penuh) searah jarum jam.
static func pill(rect: Rect2, segs := 10) -> PackedVector2Array:
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var pts := PackedVector2Array()
	var cl := Vector2(rect.position.x + r, rect.position.y + r)
	var cr := Vector2(rect.end.x - r, rect.position.y + r)
	for i in range(segs + 1):  # setengah lingkaran kiri, dari bawah ke atas
		var a := PI * 0.5 + PI * float(i) / float(segs)
		pts.append(cl + Vector2(cos(a), sin(a)) * r)
	for i in range(segs + 1):  # setengah lingkaran kanan, dari atas ke bawah
		var a2 := -PI * 0.5 + PI * float(i) / float(segs)
		pts.append(cr + Vector2(cos(a2), sin(a2)) * r)
	return pts


static func _gradient(pts: PackedVector2Array, y0: float, y1: float, c0: Color, c1: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	for p in pts:
		cols.append(c0.lerp(c1, clampf((p.y - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)))
	return cols


func _draw() -> void:
	var down := get_draw_mode() == BaseButton.DRAW_PRESSED or get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED
	var sz := size
	var lift := 3.0 if not down else 0.0
	var body := Rect2(2.0, 2.0 + (3.0 - lift), sz.x - 4.0, sz.y - 8.0)
	var top := TOP.darkened(0.2) if down else TOP
	var bottom := BOTTOM.darkened(0.25) if down else BOTTOM
	# bayangan
	var sh := pill(Rect2(body.position + Vector2(0, 4.0), body.size))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
	# tepi gelap lalu badan bergradasi
	draw_colored_polygon(pill(body.grow(2.0)), EDGE)
	var bp := pill(body)
	draw_polygon(bp, _gradient(bp, body.position.y, body.end.y, top, bottom))
	# kilau gelembung di bagian atas
	var gl := Rect2(body.position.x + 8.0, body.position.y + 3.0, body.size.x - 16.0, body.size.y * 0.42)
	var gp := pill(gl)
	draw_polygon(gp, _gradient(gp, gl.position.y, gl.end.y, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.08)))
	# garis terang tipis di tepi dalam
	var line := pill(body.grow(-1.0))
	line.append(line[0])
	draw_polyline(line, Color(1, 1, 1, 0.45), 1.5, true)
	# ikon tiga garis
	var dy := 1.0 if down else 0.0
	var ix := body.position.x + 20.0
	var cy := body.position.y + body.size.y * 0.5 + dy
	for k in range(-1, 2):
		var bar := Rect2(ix - 8.0, cy + k * 7.0 - 2.0, 16.0, 4.0)
		draw_rect(bar.grow(1.5), EDGE.lightened(0.05))
		draw_rect(bar, Color("fffbe8"))
	# tulisan
	var fs := 26
	var tw := FONT.get_string_size(LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(body.end.x - 14.0 - tw, cy + fs * 0.36)
	draw_string_outline(FONT, base, LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, EDGE)
	draw_string(FONT, base, LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
