extends Control
## Kontrol & antarmuka dunia 3D.
## Android: joystick kiri (gerak), geser bagian kanan layar (kamera), tombol AKSI / LOMPAT / LARI (multisentuh).
## Desktop: WASD/panah (gerak), seret mouse (kamera), Spasi (lompat), E (aksi), Shift (lari).
## Dialog NPC dan pilihan pulau tampil di atas kontrol; selama dialog terbuka pemain berhenti.

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const Voice := preload("res://games/education_sd/scripts/voice.gd")
const Portrait := preload("res://games/education_sd/scripts/ui/speaker_portrait.gd")
## Pembaca pesan bila tidak ada penduduk yang berbicara (papan, misi, hadiah): Bu Guru.
const NARRATOR := {"model": "warga_ibu", "height": 1.7}

signal back_pressed
signal missions_pressed
signal bag_pressed
signal dialog_closed

var world: Node3D
var joy_vec := Vector2.ZERO
var _joy_center := Vector2.ZERO
var _joy_radius := 105.0
var _joy_index := -2
var _look_index := -2
var _pinch_index := -2  # jari kedua di sisi kanan: cubit untuk zoom kamera
var _touch_pos: Dictionary = {}
var _joy_draw: Control
var _btn_action: Control
var _btn_jump: Control
var _btn_run: Control
var _top: HBoxContainer
var _hint: Label
var _prompt: Label
var _dialog: PanelContainer
var _dialog_title: Label
var _dialog_text: RichTextLabel
var _dialog_plain := ""
var _listen: Button
var portrait: Control
## Penutur dialog berikutnya {model, tint, height}; kosong = Bu Guru. Dipakai sekali oleh show_dialog.
var next_speaker: Dictionary = {}
var _dialog_btns: HBoxContainer
var _dialog_scroll: ScrollContainer
var _list_mode := false
var _perf: Label
var perf_on := false
var _fps: Array = []
var _run_on := false
var chips: HBoxContainer
var compass_target = null  # Vector3 tujuan (alat Kompas) atau null
var _compass: Control


class Arrow extends Control:
	var angle := 0.0

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 34.0, Color(1, 1, 1, 0.75))
		var dir := Vector2(sin(angle), -cos(angle))
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([c + dir * 26.0, c - dir * 12.0 + side * 13.0, c - dir * 4.0, c - dir * 12.0 - side * 13.0]), Color("e05a4f"))


class RoundBtn extends Control:
	var text := ""
	var color := Color("3f7fd8")
	var active := false
	var radius := 60.0

	func _init(t: String, c: Color, r: float) -> void:
		text = t
		color = c
		radius = r
		custom_minimum_size = Vector2(r * 2.0, r * 2.0)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, radius, Color(0, 0, 0, 0.18))
		draw_circle(c - Vector2(0, 3), radius - 2.0, color.lightened(0.15) if active else Color(color, 0.85))
		var f := ThemeDB.fallback_font
		var fs := int(radius * 0.36)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(f, c + Vector2(-w / 2.0, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

	func hit(p: Vector2) -> bool:
		return visible and get_global_rect().get_center().distance_to(p) <= radius * 1.1


class JoyDraw extends Control:
	var hud: Control

	func _draw() -> void:
		var c: Vector2 = hud._joy_center - global_position
		var r: float = hud._joy_radius
		draw_circle(c, r, Color(1, 1, 1, 0.22))
		draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.6), 4.0, true)
		draw_circle(c + hud.joy_vec * Vector2(1, -1) * r, r * 0.42, Color(1, 1, 1, 0.75))


func setup(w: Node3D, title: String, color: Color) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_draw = JoyDraw.new()
	_joy_draw.hud = self
	_joy_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_joy_draw)
	_joy_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn_action = RoundBtn.new("AKSI", Color("3fae63"), 78.0)
	_btn_jump = RoundBtn.new("LOMPAT", Color("3f7fd8"), 58.0)
	_btn_run = RoundBtn.new("LARI", Color("e0813d"), 46.0)
	for b in [_btn_action, _btn_jump, _btn_run]:
		add_child(b)
	_top = UI.hbox(12)
	_top.position = Vector2(16, 12)
	add_child(_top)
	var back := UI.button("Kembali", func() -> void: back_pressed.emit(), Color("cfc8dc"), 22, 60)
	back.name = "Back"
	_top.add_child(back)
	var tp := UI.panel(Color(1, 1, 1, 0.85), 18)
	tp.add_child(UI.label(title, 26, color, false))
	_top.add_child(tp)
	chips = UI.hbox(8)
	_top.add_child(chips)
	var mb := UI.button("MISI", func() -> void: missions_pressed.emit(), Color("8a6bd8"), 22, 60)
	mb.name = "Missions"
	_top.add_child(mb)
	var bag := UI.button("TAS", func() -> void: bag_pressed.emit(), Color("c98a4b"), 22, 60)
	bag.name = "Bag"
	_top.add_child(bag)
	_hint = UI.label("", 20, UI.INK)
	var hp := UI.panel(Color(1, 1, 1, 0.8), 16)
	hp.name = "HintPanel"
	hp.add_child(_hint)
	hp.position = Vector2(16, 86)
	hp.custom_minimum_size = Vector2(520, 0)
	add_child(hp)
	_prompt = UI.label("", 22, Color.WHITE, false)
	_prompt.add_theme_color_override("font_outline_color", Color("2b2440"))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_prompt)
	_dialog = UI.panel(Color.WHITE, 26)
	_dialog.name = "Dialog"
	var dv := UI.vbox(10)
	_dialog_title = UI.label("", 28, UI.PRIMARY, false)
	_dialog_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_text = UI.rich("", 24, UI.INK)
	_dialog_btns = UI.hbox(12)
	_dialog_scroll = ScrollContainer.new()
	_dialog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialog_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_scroll.add_child(_dialog_text)
	var trow := UI.hbox(10)
	trow.add_child(_dialog_title)
	_listen = UI.listen_button(read_dialog)
	trow.add_child(_listen)
	dv.add_child(trow)
	dv.add_child(_dialog_scroll)
	dv.add_child(_dialog_btns)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dh := UI.hbox(14)
	portrait = Portrait.new()
	portrait.name = "Portrait"
	dh.add_child(portrait)
	dh.add_child(dv)
	_dialog.add_child(dh)
	_dialog.visible = false
	add_child(_dialog)
	w.focus_changed.connect(_on_focus)
	_on_focus("")
	_compass = Arrow.new()
	_compass.name = "Compass"
	_compass.size = Vector2(76, 76)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.visible = false
	add_child(_compass)
	_perf = UI.label("", 18, Color.WHITE, false)
	_perf.add_theme_color_override("font_outline_color", Color("2b2440"))
	_perf.add_theme_constant_override("outline_size", 6)
	_perf.visible = false
	add_child(_perf)
	resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	var s := size
	_joy_radius = clampf(s.y * 0.15, 80.0, 120.0)
	_joy_center = Vector2(_joy_radius + 70.0, s.y - _joy_radius - 50.0)
	_btn_action.position = Vector2(s.x - 200, s.y - 210)
	_btn_jump.position = Vector2(s.x - 340, s.y - 140)
	_btn_run.position = Vector2(s.x - 160, s.y - 330)
	_prompt.position = Vector2(s.x - 760, s.y - 255)
	_prompt.size = Vector2(540, 40)
	_dialog.position = Vector2(s.x * 0.18, s.y * (0.1 if _list_mode else 0.38))
	_dialog_scroll.custom_minimum_size = Vector2(0, s.y * 0.5 if _list_mode else 0.0)
	_dialog_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if _list_mode else ScrollContainer.SCROLL_MODE_DISABLED
	_dialog.custom_minimum_size = Vector2(s.x * 0.64, 0)
	var pw := 164.0 if portrait != null and portrait.visible else 0.0
	_dialog_text.custom_minimum_size.x = maxf(200.0, s.x * 0.64 - 60.0 - pw)
	_dialog.size = Vector2(s.x * 0.64, 0)
	_joy_draw.queue_redraw()


func set_hint(text: String) -> void:
	_hint.text = text
	_hint.get_parent().visible = text != ""


func _on_focus(text: String) -> void:
	_prompt.text = text
	(_btn_action as RoundBtn).active = text != ""
	_btn_action.queue_redraw()


func dialog_open() -> bool:
	return _dialog.visible


## buttons: [[teks, Callable, warna], ...]. Tombol "Tutup" selalu ditambahkan.
func show_list(title: String, rows: Array, buttons: Array = []) -> void:
	_list_mode = true
	_fill_dialog(title, "\n".join(rows), buttons)


func show_dialog(title: String, text: String, buttons: Array = []) -> void:
	_list_mode = false
	_fill_dialog(title, text, buttons)


func _fill_dialog(title: String, text: String, buttons: Array) -> void:
	_layout()
	_dialog_title.text = title
	_dialog_plain = text
	_dialog_text.text = UI.esc(text)
	var sp: Dictionary = next_speaker if not next_speaker.is_empty() else NARRATOR
	next_speaker = {}
	portrait.set_model(str(sp.get("model", "")), str(sp.get("tint", "")), float(sp.get("height", 1.7)))
	portrait.visible = not _list_mode and portrait.rig != null
	_layout()
	_listen.visible = Voice.listen_ok()
	_hook_voice()
	for c in _dialog_btns.get_children():
		c.queue_free()
	for b in buttons:
		var cb: Callable = b[1]
		var btn := UI.button(str(b[0]), func() -> void:
			close_dialog()
			cb.call(), b[2] if b.size() > 2 else UI.GOOD, 24, 70)
		UI.expand(btn)
		_dialog_btns.add_child(btn)
	var close := UI.button("Tutup", close_dialog, Color("cfc8dc"), 24, 70)
	close.name = "Close"
	UI.expand(close)
	_dialog_btns.add_child(close)
	_dialog.visible = true
	_set_frozen(true)
	if not _list_mode:
		Voice.say_auto(text)


## Bacakan isi dialog (tombol Dengar).
func read_dialog() -> void:
	Voice.say(_dialog_plain)


func dialog_plain() -> String:
	return _dialog_plain


func _hook_voice() -> void:
	var v: Node = Voice.shared
	if v != null and not v.word.is_connected(_on_word):
		v.word.connect(_on_word)
		v.ended.connect(_on_voice_end)


func _on_word(a: int, b: int) -> void:
	if _dialog.visible and Voice.shared != null and str(Voice.shared.text) == _dialog_plain:
		_dialog_text.text = UI.marked(_dialog_plain, a, b)


func _on_voice_end() -> void:
	if _dialog_text != null:
		_dialog_text.text = UI.esc(_dialog_plain)


func close_dialog() -> void:
	if _dialog.visible and Voice.shared != null and str(Voice.shared.text) == _dialog_plain:
		Voice.hush()
	_dialog.visible = false
	dialog_closed.emit()
	if world != null and world.has_method("end_talk"):
		world.end_talk()
	_set_frozen(false)


func _set_frozen(f: bool) -> void:
	if world != null and world.player != null:
		world.player.frozen = f
	joy_vec = Vector2.ZERO
	_joy_index = -2
	_look_index = -2
	_push_move()


func _push_move() -> void:
	if world != null and world.player != null:
		world.player.move_input = joy_vec
		world.player.run = _run_on
	_joy_draw.queue_redraw()


func _over_ui(p: Vector2) -> bool:
	if _dialog.visible:
		return true
	return _top.get_global_rect().has_point(p)


func _press(p: Vector2, index: int) -> bool:
	if (_btn_action as RoundBtn).hit(p):
		trigger_action()
		return true
	if (_btn_jump as RoundBtn).hit(p):
		world.player.jump()
		return true
	if (_btn_run as RoundBtn).hit(p):
		_run_on = not _run_on
		(_btn_run as RoundBtn).active = _run_on
		_btn_run.queue_redraw()
		_push_move()
		return true
	if p.distance_to(_joy_center) <= _joy_radius * 1.7 and p.x < size.x * 0.45:
		_joy_index = index
		_joy_move(p)
		return true
	if p.x > size.x * 0.4:
		if _look_index != -2 and _look_index != index and _pinch_index == -2:
			_pinch_index = index
		else:
			_look_index = index
		return true
	return false


func _joy_move(p: Vector2) -> void:
	var v := (p - _joy_center) / _joy_radius
	joy_vec = Vector2(v.x, -v.y).limit_length(1.0)
	_push_move()


func _release(index: int) -> void:
	if index == _joy_index:
		_joy_index = -2
		joy_vec = Vector2.ZERO
		_push_move()
	if index == _look_index:
		_look_index = _pinch_index
		_pinch_index = -2
	elif index == _pinch_index:
		_pinch_index = -2
	_touch_pos.erase(index)


func trigger_action() -> void:
	if world != null and not _dialog.visible:
		world.interact()


func _input(event: InputEvent) -> void:
	if world == null or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and not _dialog.visible:
		match event.physical_keycode:
			KEY_E, KEY_ENTER:
				trigger_action()
			KEY_SPACE:
				world.player.jump()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_pos[event.index] = event.position
			if not _over_ui(event.position):
				_press(event.position, event.index)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		var before: Vector2 = _touch_pos.get(event.index, event.position - event.relative)
		_touch_pos[event.index] = event.position
		if event.index == _joy_index:
			_joy_move(event.position)
		elif _pinch_index != -2 and (event.index == _look_index or event.index == _pinch_index):
			var other := _pinch_index if event.index == _look_index else _look_index
			var op: Vector2 = _touch_pos.get(other, event.position)
			var d_now: float = (event.position as Vector2).distance_to(op)
			var d_before: float = before.distance_to(op)
			world.player.zoom((d_before - d_now) * 0.02)
		elif event.index == _look_index:
			world.player.look(event.relative * 1.2)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		world.player.zoom(-0.5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.5)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _over_ui(event.position):
				_press(event.position, -1)
		else:
			_release(-1)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _joy_index == -1:
			_joy_move(event.position)
		elif _look_index == -1 or (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			world.player.look(event.relative)


## Info kinerja (Pengaturan → Info kinerja): FPS rata-rata/minimum 5 detik, draw call, objek tergambar, RAM, node.
func set_perf(on: bool) -> void:
	perf_on = on
	_perf.visible = on


func _process(delta: float) -> void:
	_compass.visible = compass_target != null and world != null and world.player != null
	if _compass.visible:
		var to: Vector3 = (compass_target as Vector3) - world.player.global_position
		var cam_fwd := Vector2(-sin(world.player.yaw), -cos(world.player.yaw))
		(_compass as Arrow).angle = cam_fwd.angle_to(Vector2(to.x, to.z))
		_compass.position = Vector2(size.x - 100, 96)
		_compass.queue_redraw()
	if not perf_on:
		return
	_fps.append(1.0 / maxf(delta, 0.0001))
	if _fps.size() > 300:
		_fps.pop_front()
	if Engine.get_process_frames() % 15 != 0:
		return
	var sum := 0.0
	var mn := 1000.0
	for f in _fps:
		sum += f
		mn = minf(mn, f)
	_perf.text = "FPS %d (rata2 %d, min %d)  draw %d  objek %d  RAM %d MB  node %d" % [Engine.get_frames_per_second(),
		int(sum / maxf(1, _fps.size())), int(mn), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		int(OS.get_static_memory_usage() / 1048576.0), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
	_perf.position = Vector2(560, 92)
