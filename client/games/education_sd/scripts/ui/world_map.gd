extends Control
## Peta Dunia Enam Pulau. Laut digambar, pulau di posisi data/islands.json (map_pos 0..1), jalur
## pelayaran putus-putus antarpulau, perahu pemain di pulau tempatnya berada.
## Ketuk pulau -> panel info (tema, materi, bos, status). "Berlayar" -> perahu berlayar -> sailed(id).

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const Art := preload("res://games/education_sd/scripts/ui/sea_art.gd")

signal back_pressed
signal sailed(id: String)
signal island_selected(id: String)

var engine  # WorldEngine
var p: Dictionary
var selected := ""
var sailing := false
var _t := 0.0
var _boat_pos := Vector2.ZERO
var _boat_from := Vector2.ZERO
var _boat_to := Vector2.ZERO
var _sail_t := -1.0
var _sail_target := ""
var _panel: PanelContainer
var _p_title: Label
var _p_body: Label
var _p_status: Label
var _p_go: Button
var sail_seconds := 1.6


func setup(world_engine, progress: Dictionary, title_chip: String) -> void:
	engine = world_engine
	p = progress
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var top := UI.hbox(12)
	top.name = "Top"
	top.position = Vector2(18, 14)
	add_child(top)
	var back := UI.button("Kembali", func() -> void: back_pressed.emit(), Color("cfc8dc"), 22, 60)
	back.name = "Back"
	top.add_child(back)
	var tp := UI.panel(Color(1, 1, 1, 0.88), 18)
	tp.add_child(UI.label("Peta Dunia Enam Pulau", 28, UI.PRIMARY, false))
	top.add_child(tp)
	var chip := UI.panel(Color("ffd166"), 18)
	chip.add_child(UI.label(title_chip, 22, UI.INK, false))
	top.add_child(chip)
	_panel = UI.panel(Color(1, 1, 1, 0.95), 24)
	_panel.name = "Info"
	var v := UI.vbox(8)
	_p_title = UI.label("", 30, UI.PRIMARY)
	_p_status = UI.label("", 22, UI.SOFT)
	_p_body = UI.label("", 21, UI.INK)
	v.add_child(_p_title)
	v.add_child(_p_status)
	v.add_child(_p_body)
	_p_go = UI.button("Berlayar ke sini", func() -> void: sail(selected), UI.GOOD, 26, 72)
	_p_go.name = "Sail"
	v.add_child(_p_go)
	_panel.add_child(v)
	_panel.visible = false
	add_child(_panel)
	resized.connect(_layout)
	_layout.call_deferred()
	_boat_pos = _boat_at(str(p.world.island))


func _layout() -> void:
	var w := size.x * 0.4
	var sel: Dictionary = engine.island(selected) if selected != "" else {}
	var on_right := sel.is_empty() or float(sel.map_pos[0]) < 0.55
	_panel.custom_minimum_size = Vector2(w, 0)
	_panel.size = Vector2(w, 0)
	_panel.position = Vector2(size.x - w - 24 if on_right else 24, size.y * 0.15)
	for l in [_p_title, _p_status, _p_body]:
		l.custom_minimum_size.x = w - 50
	_panel.reset_size.call_deferred()
	if not sailing:
		_boat_pos = _boat_at(str(p.world.island))
	queue_redraw()


func island_center(isl: Dictionary) -> Vector2:
	var mp: Array = isl.map_pos
	var area := Rect2(Vector2(40, 100), size - Vector2(80, 130))
	return area.position + Vector2(float(mp[0]), float(mp[1])) * area.size


func island_radius(isl: Dictionary) -> float:
	return float(isl.get("map_size", 0.11)) * minf(size.x * 0.5, size.y * 0.85)


func _boat_at(id: String) -> Vector2:
	var isl: Dictionary = engine.island(id)
	if isl.is_empty():
		return size / 2.0
	return island_center(isl) + Vector2(island_radius(isl) * 0.95, island_radius(isl) * 0.55)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	Art.sky(self, r, Color("4fb0e8"), Color("1f6aa8"))
	Art.waves(self, r, _t)
	Art.cloud(self, Vector2(size.x * 0.12, size.y * 0.2), 0.8, Color(1, 1, 1, 0.5))
	Art.cloud(self, Vector2(size.x * 0.55, size.y * 0.12), 0.7, Color(1, 1, 1, 0.45))
	var isl_list: Array = engine.islands
	for i in range(1, isl_list.size()):
		var a := island_center(isl_list[i - 1])
		var b := island_center(isl_list[i])
		var n := int(a.distance_to(b) / 22.0)
		for k in n:
			if k % 2 == 0:
				draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(1, 1, 1, 0.6), 3.0)
	var f := ThemeDB.fallback_font
	for isl in isl_list:
		var c := island_center(isl)
		var rad := island_radius(isl)
		var st: String = engine.status(str(isl.id), p)
		Art.island(self, c, rad, Color.from_string(str(isl.color), Color.GREEN), Color.from_string(str(isl.get("sand", "#f3dfa2")), Color.WHEAT),
			int(isl.number) * 31, st != "open")
		if str(isl.id) == selected:
			draw_arc(c, rad * 1.18, 0, TAU, 48, Color("ffd166"), 5.0, true)
		draw_circle(c + Vector2(-rad * 0.75, -rad * 0.55), 22.0, Color("2b2440"))
		var num := str(int(isl.number))
		draw_string(f, c + Vector2(-rad * 0.75 - 7, -rad * 0.55 + 9), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		var name := str(isl.name)
		var fs := 22
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := c + Vector2(-w / 2.0, rad * 0.95 + 26)
		draw_rect(Rect2(lp + Vector2(-10, -24), Vector2(w + 20, 32)), Color(1, 1, 1, 0.85))
		draw_string(f, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2b2440"))
		var sub := "Kelas %d" % int(isl.grade) + ("" if st == "open" else (" · Segera hadir" if st == "soon" else " · Terkunci"))
		var w2 := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(f, c + Vector2(-w2 / 2.0, rad * 0.95 + 50), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		if st != "open":
			Art.lock(self, c, 1.6)
	Art.boat(self, _boat_pos + Vector2(0, sin(_t * 2.2) * 3.0), 1.0, Color("fdf6e3"), _boat_to.x < _boat_from.x and sailing)


func _process(delta: float) -> void:
	_t += delta
	if sailing:
		_sail_t += delta / sail_seconds
		var k := clampf(_sail_t, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		_boat_pos = _boat_from.lerp(_boat_to, e) + Vector2(0, -sin(k * PI) * 40.0)
		if _sail_t >= 1.0:
			sailing = false
			sailed.emit(_sail_target)
	queue_redraw()


func island_at(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for isl in engine.islands:
		var d := island_center(isl).distance_to(pos)
		if d < island_radius(isl) * 1.2 and d < best_d:
			best_d = d
			best = str(isl.id)
	return best


func _gui_input(event: InputEvent) -> void:
	if sailing:
		return
	var pos = null
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos == null:
		return
	if _panel.visible and _panel.get_rect().has_point(pos):
		return
	var id := island_at(pos)
	if id != "":
		select(id)
	elif _panel.visible:
		_panel.visible = false
		selected = ""


func select(id: String) -> void:
	var isl: Dictionary = engine.island(id)
	if isl.is_empty():
		return
	selected = id
	var st: String = engine.status(id, p)
	_p_title.text = "Pulau %d — %s" % [int(isl.number), str(isl.name)]
	var here := str(p.world.island) == id
	_p_status.text = "Kelas %d · %s%s" % [int(isl.grade), str(isl.theme), "  (kamu di sini)" if here else ""]
	var body := str(isl.intro) + "\n\nBelajar: " + ", ".join(isl.learn) + "\nBos penjaga: " + str(isl.boss.name)
	if st != "open":
		body += "\n\n" + str(engine.lock_reason(id, p))
	_p_body.text = body
	_p_go.visible = st == "open"
	_p_go.text = "Masuk pulau" if here else "Berlayar ke sini"
	_panel.visible = true
	_layout()
	island_selected.emit(id)


## Mulai berlayar ke pulau `id` (harus terbuka). Pulau yang sama: langsung masuk.
func sail(id: String) -> bool:
	if sailing or engine.status(id, p) != "open":
		return false
	_panel.visible = false
	_sail_target = id
	_boat_from = _boat_pos
	_boat_to = _boat_at(id)
	if str(p.world.island) == id:
		sailed.emit(id)
		return true
	_sail_t = 0.0
	sailing = true
	return true
