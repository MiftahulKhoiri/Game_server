extends CanvasLayer
## Layar Profil pemain: data ringkas dan pilihan pahlawan (pratinjau 3D berputar).
## Pilihan disimpan di server (POST /v1/players/me/hero); pemilik layar (world3d.gd)
## mengganti model di dunia lewat sinyal hero_changed.

signal closed
signal hero_changed

const Heroes = preload("res://scripts/heroes.gd")
const Models = preload("res://scripts/models.gd")

var is_open := false

var _info: Label
var _preview_holder: Node3D
var _preview_rig: Node3D
var _name: Label
var _story: Label
var _detail: Label
var _use_btn: Button
var _status: Label
var _tabs: Array[Button] = []
var _selected := 0
var _busy := false
var _outfit_label: Label


func _init() -> void:
	layer = 11
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1d2b22")
	sb.border_color = Color("5fb35a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := _label("Profil", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("d8f0c8"))
	box.add_child(title)

	_info = _label("", 28)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)

	box.add_child(_label("Pilih pahlawan", 30))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var group := ButtonGroup.new()
	for i in Heroes.LIST.size():
		var b := Button.new()
		b.text = str(Heroes.LIST[i].short)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_select.bind(i))
		row.add_child(b)
		_tabs.append(b)

	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(0, 300)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.stretch = true
	box.add_child(holder)
	holder.add_child(_build_preview())

	_name = _label("", 38)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name)
	_story = _label("", 24)
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story.add_theme_color_override("font_color", Color("b9c9bd"))
	box.add_child(_story)
	_detail = _label("", 26)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)

	_status = _label("", 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("ffd27a"))
	box.add_child(_status)

	_use_btn = _button("Pakai pahlawan ini", _on_use)
	box.add_child(_use_btn)
	# Variasi pakaian (roadmap no. 14): gratis, langsung disimpan di server.
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 10)
	box.add_child(orow)
	var prev := _button("<", _on_outfit.bind(-1))
	prev.custom_minimum_size = Vector2(110, 76)
	orow.add_child(prev)
	_outfit_label = _label("", 28)
	_outfit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outfit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orow.add_child(_outfit_label)
	var nxt := _button(">", _on_outfit.bind(1))
	nxt.custom_minimum_size = Vector2(110, 76)
	orow.add_child(nxt)
	box.add_child(_button("Tutup", func() -> void: closed.emit()))


func open() -> void:
	_selected = Heroes.ids().find(str(Heroes.current().id))
	_status.text = ""
	_busy = false
	_refresh()
	visible = true
	is_open = true


func close() -> void:
	visible = false
	is_open = false


func _process(delta: float) -> void:
	if is_open and _preview_rig != null:
		_preview_rig.rotation.y += delta * 0.9


func _select(i: int) -> void:
	_selected = i
	_status.text = ""
	_refresh()


func _on_use() -> void:
	if _busy:
		return
	var hero: Dictionary = Heroes.LIST[_selected]
	if str(hero.id) == str(Heroes.current().id):
		return
	_busy = true
	_refresh()
	if Session.offline:
		Session.player.state.hero = hero.id
	else:
		var res: Dictionary = await Api.set_hero(str(hero.id))
		if not res.ok:
			_busy = false
			_status.text = str(res.error)
			_refresh()
			return
		Session.merge_server_player(res.data)
	_busy = false
	_status.text = "%s dipakai." % hero.name
	_refresh()
	hero_changed.emit()


func _outfit() -> int:
	return int(Session.player.state.get("outfit", 0))


func _on_outfit(step: int) -> void:
	if _busy:
		return
	var n := posmod(_outfit() + step, Models.OUTFIT_NAMES.size())
	_busy = true
	if Session.offline:
		Session.player.state.outfit = n
	else:
		var res: Dictionary = await Api.set_outfit(n)
		if not res.ok:
			_busy = false
			_status.text = str(res.error)
			_refresh()
			return
		Session.merge_server_player(res.data)
	_busy = false
	_status.text = "Pakaian: %s" % Models.OUTFIT_NAMES[n]
	_refresh()
	hero_changed.emit()


func _refresh() -> void:
	var st: Dictionary = Session.player.state
	var cur := Heroes.current()
	_info.text = "%s   Lv %d   XP %d\nHP %d/%d   Emas %d   Pahlawan: %s" % [
		Session.player.name, st.level, st.xp, st.hp, st.max_hp, st.gold, cur.name,
	]
	for i in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == _selected)
	var hero: Dictionary = Heroes.LIST[_selected]
	_name.text = str(hero.name)
	_story.text = str(hero.story)
	_detail.text = "Senjata: %s\nSkill 1: %s\nSkill 2: %s" % [hero.weapon, hero.skill1, hero.skill2]
	_show_model(str(hero.id))
	var is_current: bool = str(hero.id) == str(cur.id)
	_use_btn.disabled = is_current or _busy
	_use_btn.text = "Sedang dipakai" if is_current else "Pakai pahlawan ini"
	_outfit_label.text = "Pakaian: %s" % Models.OUTFIT_NAMES[clampi(_outfit(), 0, Models.OUTFIT_NAMES.size() - 1)]


func _show_model(id: String) -> void:
	if _preview_rig != null and _preview_rig.name == id:
		Models.dress_current(_preview_rig)
		return
	if _preview_rig != null:
		_preview_rig.queue_free()
	_preview_rig = Models.create(id)
	Models.dress_current(_preview_rig)
	_preview_rig.position = Vector3(0, 0, 0)
	_preview_holder.add_child(_preview_rig)


func _build_preview() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(600, 420)
	vp.msaa_3d = Viewport.MSAA_2X
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b3a33")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4d2c8")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	sun.light_energy = 1.0
	vp.add_child(sun)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.75
	cyl.height = 0.08
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("5b7a4a")
	disc.material_override = dm
	disc.position.y = -0.04
	vp.add_child(disc)
	_preview_holder = Node3D.new()
	vp.add_child(_preview_holder)
	var cam := Camera3D.new()
	cam.fov = 34.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.65, 2.35), Vector3(0, 0.5, 0))
	cam.current = true
	return vp


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	b.pressed.connect(cb)
	return b
