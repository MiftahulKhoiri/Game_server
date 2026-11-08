extends Control
## Basecamp pahlawan: tenda merah merekrut pahlawan berkelas (4 jenis, masing-masing satu), tenda hijau merekrut
## prajurit biasa (satu per satu, maks Session.MAX_SOLDIERS). Dibuka dengan mengajak bicara perekrut di depan tenda
## (Session.recruit_kind = "pahlawan" / "prajurit"). Memasang pahlawan ke barisan tetap di layar Atribut.

const Heroes = preload("res://scripts/heroes.gd")
const Models = preload("res://scripts/models.gd")
const WORLD_SCENE := "res://scenes/world3d.tscn"

var _list: VBoxContainer
var _gold_label: Label
var _message: Label
var _busy := false
var _kind := "pahlawan"


func _ready() -> void:
	_kind = Session.recruit_kind if Session.recruit_kind in ["pahlawan", "prajurit"] else "pahlawan"
	_build_ui()
	_rebuild()


func _state() -> Dictionary:
	return Session.player.state


func _rebuild() -> void:
	var st := _state()
	_gold_label.text = "Emas: %d" % int(st.gold)
	for child in _list.get_children():
		child.queue_free()
	if _kind == "pahlawan":
		var allies: Array = st.get("allies", [])
		for hero: Dictionary in Heroes.LIST:
			var owned := allies.has(str(hero.id))
			var info := "%s\nSkill: %s, %s" % [hero.weapon, hero.skill1, hero.skill2]
			var btn := "Dibeli" if owned else "Beli %d" % int(hero.price)
			_add_row(str(hero.id), str(hero.name), info, btn, owned or int(st.gold) < int(hero.price) or _busy, _on_buy_hero.bind(str(hero.id)))
		_list.add_child(_note("Pahlawan yang dibeli dipasang di barisan lewat Menu > Atribut (maks %d sekaligus)." % Heroes.MAX_PARTY))
	else:
		var n := int(st.get("soldiers", 0))
		var full := n >= Session.MAX_SOLDIERS
		var info := "Prajurit biasa: serangannya lemah tapi semuanya ikut bertarung.\nPasukanmu: %d/%d" % [n, Session.MAX_SOLDIERS]
		var btn := "Penuh" if full else "Beli %d" % Session.SOLDIER_PRICE
		_add_row("prajurit_1", "Prajurit", info, btn, full or int(st.gold) < Session.SOLDIER_PRICE or _busy, _on_buy_soldier)
		_list.add_child(_note("Setiap prajurit dibeli satu per satu dan langsung ikut denganmu."))


func _on_buy_hero(id: String) -> void:
	await _act(Api.buy_ally.bind(id), "Pahlawan bergabung! Pasang di Menu > Atribut.")


func _on_buy_soldier() -> void:
	await _act(Api.buy_soldier, "Prajurit bergabung dengan pasukanmu!")


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
	_rebuild()


func _on_back() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- tampilan ---

func _note(text: String) -> Label:
	var l := _make_label(text, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("b8c4b0"))
	return l


func _add_row(model_id: String, title: String, info: String, button_text: String, disabled: bool, on_press: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_portrait(model_id))
	var label := _make_label("%s\n%s" % [title, info], 24)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var button := Button.new()
	button.text = button_text
	button.disabled = disabled
	button.custom_minimum_size = Vector2(170, 90)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(on_press)
	row.add_child(button)
	_list.add_child(row)


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

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := "Tenda Hijau: Prajurit Biasa" if _kind == "prajurit" else "Tenda Merah: Pahlawan Berkelas"
	if Session.shop_keeper != "":
		title += "\n" + Session.shop_keeper
	box.add_child(_make_label(title, 36))
	_gold_label = _make_label("", 30)
	box.add_child(_gold_label)

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
