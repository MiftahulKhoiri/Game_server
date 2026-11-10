extends Control
## Aula Pelatihan: tempat kiri melatih pahlawan pembantu berkelas (per pahlawan), tempat kanan melatih
## pasukan prajurit biasa (satu level bersama). Tiap latihan memakai emas, 1 Kartu Keahlian, dan energi
## (dibayar di awal) lalu berjalan menurut jam server, juga saat game ditutup; hasilnya diambil di sini.
## Dibuka dengan mengajak bicara pelatih (Session.train_kind = "pahlawan" / "prajurit").

const Heroes = preload("res://scripts/heroes.gd")
const Models = preload("res://scripts/models.gd")
const WORLD_SCENE := "res://scenes/world3d.tscn"
const KARTU := "kartu_keahlian"

var _list: VBoxContainer
var _head_label: Label
var _message: Label
var _busy := false
var _kind := "pahlawan"
var _offset := 0  # jam server dikurangi jam HP (detik)
var _timers: Array = []  # [{label, ready_at}] diperbarui tiap detik
var _tick := 0.0


func _ready() -> void:
	_kind = Session.train_kind if Session.train_kind in ["pahlawan", "prajurit"] else "pahlawan"
	_build_ui()
	_rebuild()
	var t: Dictionary = await Api.server_time()
	if t.ok and is_inside_tree():
		_offset = int(t.data.get("unix", 0)) - int(Time.get_unix_time_from_system())
		_rebuild()


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	for tm: Dictionary in _timers:
		var lab: Label = tm.label
		if is_instance_valid(lab):
			lab.text = _remaining_text(int(tm.ready_at))


func _state() -> Dictionary:
	return Session.player.state


func _now() -> int:
	return int(Time.get_unix_time_from_system()) + _offset


func _cards() -> int:
	var n := 0
	for it: Dictionary in _state().get("inventory", []):
		if str(it.id) == KARTU:
			n += int(it.qty)
	return n


## Teks lama (detik) yang mudah dibaca: "1 jam 5 mnt", "12 mnt 30 dtk".
static func duration_text(sec: int) -> String:
	sec = maxi(0, sec)
	@warning_ignore("integer_division")
	var h := sec / 3600
	@warning_ignore("integer_division")
	var m := (sec % 3600) / 60
	var s := sec % 60
	if h > 0:
		return "%d jam %d mnt" % [h, m]
	if m > 0:
		return "%d mnt %d dtk" % [m, s] if s > 0 else "%d mnt" % m
	return "%d dtk" % s


func _remaining_text(ready_at: int) -> String:
	var left := ready_at - _now()
	if left <= 0:
		return "Selesai!"
	return "Sisa " + duration_text(left)


func _rebuild() -> void:
	var st := _state()
	_timers.clear()
	_head_label.text = "Emas: %d    Kartu Keahlian: %d    Energi: %d" % [int(st.gold), _cards(), Session.energy()]
	for child in _list.get_children():
		child.queue_free()
	var job: Dictionary = Session.train_job(_kind)
	var cfg: Dictionary = Session.TRAIN[_kind]
	if _kind == "pahlawan":
		var allies: Array = st.get("allies", [])
		if allies.is_empty():
			_list.add_child(_note("Kamu belum punya pahlawan pembantu. Rekrut dulu di Basecamp (tenda merah)."))
		for hero: Dictionary in Heroes.LIST:
			if allies.has(str(hero.id)):
				_add_row(str(hero.id), str(hero.name), Session.hero_level(str(hero.id)), job, str(hero.id), cfg)
		_list.add_child(_note("Pahlawan yang lebih tinggi levelnya menyerang lebih kuat saat membantu bertarung."))
	else:
		var n := int(st.get("soldiers", 0))
		if n < 1:
			_list.add_child(_note("Kamu belum punya prajurit. Beli dulu di Basecamp (tenda hijau)."))
		else:
			_add_row("prajurit", "Pasukan Prajurit (%d orang)" % n, Session.squad_level(), job, "", cfg)
			_list.add_child(_note("Semua prajurit dilatih bersama: satu level untuk seluruh pasukan."))


## Satu baris latihan: potret, nama + level, biaya (atau sisa waktu), dan tombol.
func _add_row(model_id: String, title: String, level: int, job: Dictionary, target: String, cfg: Dictionary) -> void:
	var st := _state()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_portrait(model_id))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_make_label("%s  (Lv %d)" % [title, level], 26))
	var info := _make_label("", 22)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", Color("b8c4b0"))
	col.add_child(info)
	var button := Button.new()
	button.custom_minimum_size = Vector2(190, 90)
	button.add_theme_font_size_override("font_size", 26)
	row.add_child(button)
	var mine: bool = not job.is_empty() and str(job.get("target", "")) == target
	if mine:
		var ready_at := int(job.ready_at)
		info.text = "Berlatih ke Lv %d. " % int(job.to_level) + _remaining_text(ready_at)
		_timers.append({"label": info, "ready_at": ready_at})
		button.text = "Ambil"
		button.disabled = _busy or ready_at > _now()
		button.pressed.connect(_on_claim)
	elif level >= Session.MAX_TRAIN_LEVEL:
		info.text = "Sudah mencapai level tertinggi."
		button.text = "Maks"
		button.disabled = true
	else:
		var gold: int = int(cfg.gold) * level
		var sec: int = int(cfg.sec) * level
		var energy: int = int(cfg.energy)
		info.text = "Ke Lv %d: %d emas, 1 Kartu Keahlian, %d energi, lama %s" % [level + 1, gold, energy, duration_text(sec)]
		button.text = "Latih"
		button.disabled = _busy or not job.is_empty() or int(st.gold) < gold or _cards() < 1 or Session.energy() < energy
		button.pressed.connect(_on_start.bind(target))
	_list.add_child(row)


func _on_start(target: String) -> void:
	await _act(Api.train_start.bind(_kind, target), "Latihan dimulai! Kembali lagi nanti untuk mengambil hasilnya.")


func _on_claim() -> void:
	await _act(Api.train_claim.bind(_kind), "Latihan selesai, level naik!")


func _act(call: Callable, ok_text: String) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await call.call()
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_message.text = ok_text
	else:
		_message.text = str(res.error)
	if is_inside_tree():
		_rebuild()


func _on_back() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- tampilan ---

func _note(text: String) -> Label:
	var l := _make_label(text, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("b8c4b0"))
	return l


## Potret kecil: model 3D di SubViewport.
func _portrait(model_id: String) -> Control:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(120, 140)
	holder.stretch = true
	var vp := SubViewport.new()
	vp.size = Vector2i(120, 140)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	holder.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 35.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.75, 2.6), Vector3(0, 0.55, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	vp.add_child(light)
	var rig: Node3D = Models.create(model_id)
	rig.rotation.y = 0.35
	vp.add_child(rig)
	return holder


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1f2418") if _kind == "prajurit" else Color("2a1a18")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preload("res://scripts/layar.gd").kolom(margin, 1100.0)  # layar mendatar: isi di kolom tengah

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := "Latihan Prajurit Biasa" if _kind == "prajurit" else "Latihan Pahlawan Berkelas"
	if Session.shop_keeper != "":
		title += "\n" + Session.shop_keeper
	box.add_child(_make_label(title, 36))
	_head_label = _make_label("", 26)
	_head_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_head_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	_message = _make_label("", 24)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)

	var back := Button.new()
	back.text = "Kembali"
	back.custom_minimum_size = Vector2(0, 100)
	back.add_theme_font_size_override("font_size", 34)
	back.pressed.connect(_on_back)
	box.add_child(back)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
