extends Control
## Tombol aksi bulat di dunia 3D (Tangan, Kaki, Perisai, Boost, Lompat). Ikonnya digambar dengan kode.
## Memakai sentuhan mentah seperti joystick, jadi bisa ditekan sambil jari lain menggerakkan joystick.
## `pressed` saat disentuh, `released(held)` saat dilepas (held = lama ditahan, detik).

signal pressed
signal released(held: float)

enum Icon { TANGAN, KAKI, PERISAI, BOOST, LOMPAT }

var icon := Icon.TANGAN
var title := ""
var tint := Color("ffd25a")
var cooldown := 0.0   # 0..1: sisa isi ulang (1 = baru dipakai)
var charge := 0.0     # 0..1: isi (tenaga Boost, atau lama menahan)
var glow := false     # menyala saat siap dipakai (Boost penuh)
var active := false   # sedang berlaku (bertahan, mode Boost)

var _finger := -1  # -1 tidak ada, -2 mouse
var _held := 0.0

const BG := Color(0.05, 0.07, 0.1, 0.55)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_held() -> bool:
	return _finger != -1


func held_time() -> float:
	return _held


func _center() -> Vector2:
	return size / 2.0


func _radius() -> float:
	return minf(size.x, size.y) / 2.0


func _hit(p: Vector2) -> bool:
	return is_visible_in_tree() and (p - (global_position + _center())).length() <= _radius() + 6.0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed and _finger == -1 and _hit(te.position):
			_begin(te.index)
		elif not te.pressed and te.index == _finger:
			_end()
	elif event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		if me.button_index == MOUSE_BUTTON_LEFT:
			if me.pressed and _finger == -1 and _hit(me.position):
				_begin(-2)
			elif not me.pressed and _finger == -2:
				_end()


func _begin(index: int) -> void:
	_finger = index
	_held = 0.0
	queue_redraw()
	pressed.emit()


func _end() -> void:
	var h := _held
	_finger = -1
	_held = 0.0
	queue_redraw()
	released.emit(h)


func _process(delta: float) -> void:
	if _finger != -1:
		_held += delta
		queue_redraw()
	elif cooldown > 0.0 or glow or active:
		queue_redraw()


func _draw() -> void:
	var c := _center()
	var r := _radius()
	var down := _finger != -1
	draw_circle(c, r, BG.lightened(0.18) if down else BG)
	var ring := tint
	ring.a = 1.0 if (down or glow or active) else 0.75
	draw_arc(c, r - 2.0, 0.0, TAU, 56, ring, 5.0 if (down or glow or active) else 3.5, true)
	if glow:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		draw_arc(c, r + 2.0, 0.0, TAU, 56, Color(tint, 0.25 + 0.35 * pulse), 7.0, true)
	if charge > 0.0 and charge < 1.0:
		draw_arc(c, r - 9.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 48, Color(tint, 0.9), 6.0, true)
	var k := r / 70.0
	_draw_icon(c + Vector2(0, -8.0 * k), k)
	var font := ThemeDB.fallback_font
	var fs := int(clampf(20.0 * k, 16.0, 24.0))
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, c + Vector2(-w / 2.0, r * 0.72), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
	draw_string(font, c + Vector2(-w / 2.0, r * 0.72), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("fff4d8"))
	if cooldown > 0.0:  # sektor gelap yang menyusut searah jarum jam
		var pts := PackedVector2Array([c])
		var a0 := -PI / 2.0
		var a1 := a0 + TAU * cooldown
		var n := maxi(3, int(40.0 * cooldown))
		for i in n + 1:
			var a := lerpf(a0, a1, float(i) / float(n))
			pts.append(c + Vector2(cos(a), sin(a)) * (r - 3.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.5))


func _draw_icon(c: Vector2, k: float) -> void:
	var line := Color("20160e")
	var fill := Color("fff1cf")
	match icon:
		Icon.TANGAN:  # kepalan: telapak, empat buku jari, ibu jari
			draw_rect(Rect2(c + Vector2(-20, -6) * k, Vector2(40, 30) * k), fill)
			for i in 4:
				draw_circle(c + Vector2(-15 + i * 10, -8) * k, 6.5 * k, fill)
			draw_circle(c + Vector2(-23, 10) * k, 7.0 * k, fill)
			for i in 3:
				draw_line(c + Vector2(-10 + i * 10, -8) * k, c + Vector2(-10 + i * 10, 8) * k, line, 1.6 * k)
			draw_rect(Rect2(c + Vector2(-20, -6) * k, Vector2(40, 30) * k), line, false, 1.6 * k)
		Icon.KAKI:  # sepatu bot
			var boot := PackedVector2Array([Vector2(-12, -28), Vector2(8, -28), Vector2(8, 4), Vector2(28, 12), Vector2(28, 26), Vector2(-14, 26), Vector2(-14, 8)])
			var pts := PackedVector2Array()
			for p in boot:
				pts.append(c + p * k)
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, line, 1.8 * k)
			draw_line(c + Vector2(-14, 20) * k, c + Vector2(28, 20) * k, line, 2.0 * k)
		Icon.PERISAI:
			var sh := PackedVector2Array([Vector2(-24, -26), Vector2(24, -26), Vector2(24, 0), Vector2(0, 30), Vector2(-24, 0)])
			var pts2 := PackedVector2Array()
			for p in sh:
				pts2.append(c + p * k)
			draw_colored_polygon(pts2, fill)
			pts2.append(pts2[0])
			draw_polyline(pts2, line, 1.8 * k)
			draw_line(c + Vector2(0, -26) * k, c + Vector2(0, 30) * k, line, 1.6 * k)
			draw_line(c + Vector2(-24, -4) * k, c + Vector2(24, -4) * k, line, 1.6 * k)
		Icon.LOMPAT:  # panah ke atas di atas alas
			var up := PackedVector2Array([Vector2(0, -32), Vector2(24, -6), Vector2(9, -6), Vector2(9, 14), Vector2(-9, 14), Vector2(-9, -6), Vector2(-24, -6)])
			var pts4 := PackedVector2Array()
			for p in up:
				pts4.append(c + p * k)
			draw_colored_polygon(pts4, fill)
			pts4.append(pts4[0])
			draw_polyline(pts4, line, 1.8 * k)
			draw_line(c + Vector2(-20, 26) * k, c + Vector2(20, 26) * k, line, 3.0 * k)
		Icon.BOOST:  # petir
			var bolt := PackedVector2Array([Vector2(8, -32), Vector2(-18, 4), Vector2(-3, 4), Vector2(-10, 32), Vector2(20, -8), Vector2(4, -8)])
			var pts3 := PackedVector2Array()
			for p in bolt:
				pts3.append(c + p * k)
			draw_colored_polygon(pts3, Color("ffe14a") if glow else fill)
			pts3.append(pts3[0])
			draw_polyline(pts3, line, 1.8 * k)
