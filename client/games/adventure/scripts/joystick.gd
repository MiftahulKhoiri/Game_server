extends Control
## Joystick layar mengambang: muncul di tempat jari menyentuh (di dalam area ini),
## mendukung multi-sentuh (kamera diputar dengan jari lain). Di desktop dipakai mouse.
## `vec` = arah (x kanan, y bawah layar), panjang 0..1.

const RADIUS := 95.0

var vec := Vector2.ZERO

var _finger := -1  # -1 tidak ada, -2 mouse
var _origin := Vector2.ZERO  # pusat dasar joystick (koordinat lokal)
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_origin = Vector2(150, size.y - 150)
	_knob = _origin


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed and _finger == -1 and get_global_rect().has_point(te.position):
			_begin(te.index, te.position)
		elif not te.pressed and te.index == _finger:
			_end()
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == _finger:
			_update(de.position)
	elif event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		if me.button_index == MOUSE_BUTTON_LEFT:
			if me.pressed and _finger == -1 and get_global_rect().has_point(me.position):
				_begin(-2, me.position)
			elif not me.pressed and _finger == -2:
				_end()
	elif event is InputEventMouseMotion and _finger == -2:
		_update((event as InputEventMouseMotion).position)


func _begin(index: int, global_pos: Vector2) -> void:
	_finger = index
	_origin = global_pos - global_position
	_update(global_pos)


func _update(global_pos: Vector2) -> void:
	var d := (global_pos - global_position) - _origin
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	_knob = _origin + d
	vec = d / RADIUS
	queue_redraw()


func _end() -> void:
	_finger = -1
	vec = Vector2.ZERO
	_origin = Vector2(150, size.y - 150)
	_knob = _origin
	queue_redraw()


func _draw() -> void:
	var active := _finger != -1
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.14 if active else 0.08))
	draw_arc(_origin, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45 if active else 0.25), 3.0)
	draw_circle(_knob, 38.0, Color(1, 1, 1, 0.55 if active else 0.3))
