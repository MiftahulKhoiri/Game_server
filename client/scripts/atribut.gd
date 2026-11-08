extends Control
## Atribut: (1) ganti perlengkapan yang dipakai dan lihat serangan/pertahanan, (2) beli pahlawan
## pendamping lalu pasang (maks 3) di belakang pemain; pendamping ikut menyerang saat bertarung.
## Semua aturan dijalankan SERVER (docs/API.md); layar ini hanya menampilkan dan mengirim permintaan.

const WORLD_SCENE := "res://scenes/world3d.tscn"
const ITEM_ART_DIR := "res://assets/items/"
const Heroes = preload("res://scripts/heroes.gd")
const Models = preload("res://scripts/models.gd")
const SLOTS := [["weapon", "Senjata"], ["armor", "Pelindung"]]
const KIND_COLOR := Color("5a7fb0")

var _catalog: Dictionary = {}  # id -> definisi barang dari server
var _info: Label
var _message: Label
var _tab_buttons: Array[Button] = []
var _page_equip: ScrollContainer
var _equip_list: VBoxContainer
var _page_ally: VBoxContainer
var _hero_tabs: Array[Button] = []
var _preview_holder: Node3D
var _preview_rig: Node3D
var _hero_name: Label
var _hero_detail: Label
var _party_label: Label
var _ally_btn: Button
var _selected := 0
var _busy := false
var _page := 0


func _ready() -> void:
	_build_ui()
	_show_page(0)
	var res: Dictionary = await Api.shop_get()  # katalog semua barang
	if not res.ok:
		_message.text = str(res.error)
		return
	for def: Dictionary in res.data.get("items", []):
		_catalog[str(def.id)] = def
	_selected = maxi(0, Heroes.ids().find(str(Heroes.current().id)))
	_refresh()


func _process(delta: float) -> void:
	if _preview_rig != null and _page == 1:
		_preview_rig.rotation.y += delta * 0.9


# --- data ---

func _state() -> Dictionary:
	return Session.player.state


func _equipment() -> Dictionary:
	return _state().get("equipment", {"weapon": "", "armor": ""})


func _def(id: String) -> Dictionary:
	return _catalog.get(id, {})


func _name_of(id: String) -> String:
	return str(_def(id).get("name", id))


func _bonus_text(def: Dictionary) -> String:
	if int(def.get("attack", 0)) > 0:
		return "Serang +%d" % int(def.attack)
	if int(def.get("defense", 0)) > 0:
		return "Tahan +%d" % int(def.defense)
	return ""


func _owned(id: String) -> int:
	for item: Dictionary in _state().inventory:
		if str(item.id) == id:
			return int(item.qty)
	return 0


# --- aksi ---

func _act(request: Callable, ok_text: String) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await request.call()
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_message.text = ok_text
	else:
		_message.text = str(res.error)
	_refresh()


func _on_equip(id: String) -> void:
	await _act(Api.inventory_equip.bind(id), "%s dipakai." % _name_of(id))


func _on_unequip(slot: String) -> void:
	await _act(Api.inventory_unequip.bind(slot), "Perlengkapan dilepas.")


func _on_ally_pressed() -> void:
	var hero: Dictionary = Heroes.LIST[_selected]
	var id := str(hero.id)
	var allies: Array = _state().get("allies", [])
	var party: Array = _state().get("party", [])
	if not allies.has(id):
		await _act(Api.buy_ally.bind(id), "%s bergabung! Bayar %d emas." % [hero.name, int(hero.price)])
	elif party.has(id):
		var rest := party.duplicate()
		rest.erase(id)
		await _act(Api.set_party.bind(rest), "%s dilepas dari barisan." % hero.name)
	else:
		var next := party.duplicate()
		next.append(id)
		await _act(Api.set_party.bind(next), "%s berbaris di belakangmu." % hero.name)


func _on_back() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- tampilan ---

func _show_page(i: int) -> void:
	_page = i
	_page_equip.visible = i == 0
	_page_ally.visible = i == 1
	for k in _tab_buttons.size():
		_tab_buttons[k].set_pressed_no_signal(k == i)
	if i == 1:
		_refresh()


func _refresh() -> void:
	var st := _state()
	_info.text = "%s  Lv %d\nHP %d/%d   Emas %d" % [Session.player.name, st.level, st.hp, st.max_hp, st.gold]
	if _page == 0:
		_rebuild_equipment()
	else:
		_refresh_ally()


func _rebuild_equipment() -> void:
	for child in _equip_list.get_children():
		child.queue_free()
	var st := _state()
	var bonus_atk := 0
	var bonus_def := 0
	for slot: Array in SLOTS:
		var wid := str(_equipment().get(slot[0], ""))
		bonus_atk += int(_def(wid).get("attack", 0)) if wid != "" else 0
		bonus_def += int(_def(wid).get("defense", 0)) if wid != "" else 0
	var atk := 4 + 2 * int(st.level) + bonus_atk
	var dfn := 1 + int(st.level) + bonus_def
	var stats := _label("Serangan  %d  (dasar %d, perlengkapan +%d)\nPertahanan  %d  (dasar %d, perlengkapan +%d)" % [
		atk, atk - bonus_atk, bonus_atk, dfn, dfn - bonus_def, bonus_def], 26)
	_equip_list.add_child(stats)
	for slot: Array in SLOTS:
		_equip_list.add_child(_header(str(slot[1])))
		var worn := str(_equipment().get(slot[0], ""))
		var row := _item_row(worn, "Dipakai" if worn != "" else "-", "Lepas" if worn != "" else "", _on_unequip.bind(str(slot[0])))
		_equip_list.add_child(row)
		var any := false
		for item: Dictionary in st.inventory:
			var id := str(item.id)
			var def := _def(id)
			if str(def.get("slot", "")) != str(slot[0]) or id == worn:
				continue
			any = true
			_equip_list.add_child(_item_row(id, _bonus_text(def), "Pakai", _on_equip.bind(id)))
		if not any:
			var hint := _label("Tidak ada pilihan lain di ransel. Beli di Toko.", 22)
			hint.add_theme_color_override("font_color", Color("b9c9bd"))
			_equip_list.add_child(hint)


func _item_row(id: String, sub: String, verb: String, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_icon(id))
	var text := "-" if id == "" else "%s\n%s" % [_name_of(id), sub]
	var label := _label(text, 26)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	if verb != "":
		var b := _button(verb, cb, 150, 76)
		row.add_child(b)
	return row


func _icon(id: String) -> Control:
	var path := ITEM_ART_DIR + id + ".png"
	if id != "" and ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path) as Texture2D
		tex.custom_minimum_size = Vector2(76, 76)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var box := ColorRect.new()
	box.color = Color(1, 1, 1, 0.08) if id == "" else KIND_COLOR
	box.custom_minimum_size = Vector2(76, 76)
	return box


func _refresh_ally() -> void:
	var st := _state()
	var allies: Array = st.get("allies", [])
	var party: Array = st.get("party", [])
	for i in _hero_tabs.size():
		var id := str(Heroes.LIST[i].id)
		_hero_tabs[i].set_pressed_no_signal(i == _selected)
		_hero_tabs[i].modulate = Color("ffd878") if party.has(id) else (Color("a8f0a0") if allies.has(id) else Color.WHITE)
	var hero: Dictionary = Heroes.LIST[_selected]
	var hid := str(hero.id)
	_hero_name.text = str(hero.name)
	var status := "Belum dibeli: %d emas" % int(hero.price)
	if party.has(hid):
		status = "Berbaris di belakangmu"
	elif allies.has(hid):
		status = "Sudah dibeli, belum dipasang"
	_hero_detail.text = "%s\nSkill: %s, %s\n%s" % [hero.weapon, hero.skill1, hero.skill2, status]
	var names: PackedStringArray = []
	for id: String in party:
		names.append(str(Heroes.get_hero(id).short))
	_party_label.text = "Pendamping terpasang: %d/%d%s" % [party.size(), Heroes.MAX_PARTY, ("  (" + ", ".join(names) + ")") if not names.is_empty() else ""]
	if not allies.has(hid):
		_ally_btn.text = "Beli (%d emas)" % int(hero.price)
		_ally_btn.disabled = int(st.gold) < int(hero.price) or _busy
	elif party.has(hid):
		_ally_btn.text = "Lepas dari barisan"
		_ally_btn.disabled = _busy
	else:
		_ally_btn.text = "Pasang di belakangku"
		_ally_btn.disabled = party.size() >= Heroes.MAX_PARTY or _busy
	if _preview_rig == null or _preview_rig.name != hid:
		if _preview_rig != null:
			_preview_rig.queue_free()
		_preview_rig = Models.create(hid)
		_preview_rig.name = hid
		_preview_holder.add_child(_preview_rig)


func _select_hero(i: int) -> void:
	_selected = i
	_message.text = ""
	_refresh_ally()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a2420")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := _label("Atribut", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("d8f0c8"))
	box.add_child(title)
	_info = _label("", 28)
	box.add_child(_info)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	for i in 2:
		var b := _button(["Perlengkapan", "Pendamping"][i], _show_page.bind(i), 0, 76)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons.append(b)

	_message = _label("", 24)
	_message.add_theme_color_override("font_color", Color("ffd27a"))
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)

	_page_equip = ScrollContainer.new()
	_page_equip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_equip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_page_equip)
	_equip_list = VBoxContainer.new()
	_equip_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_list.add_theme_constant_override("separation", 12)
	_page_equip.add_child(_equip_list)

	_page_ally = VBoxContainer.new()
	_page_ally.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_ally.add_theme_constant_override("separation", 10)
	box.add_child(_page_ally)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_page_ally.add_child(row)
	for i in Heroes.LIST.size():
		var hb := _button(str(Heroes.LIST[i].short), _select_hero.bind(i), 0, 72)
		hb.toggle_mode = true
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_theme_font_size_override("font_size", 24)
		row.add_child(hb)
		_hero_tabs.append(hb)
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(0, 380)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.stretch = true
	_page_ally.add_child(holder)
	holder.add_child(_build_preview())
	_hero_name = _label("", 38)
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_ally.add_child(_hero_name)
	_hero_detail = _label("", 24)
	_hero_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_ally.add_child(_hero_detail)
	_party_label = _label("", 26)
	_party_label.add_theme_color_override("font_color", Color("e0c070"))
	_party_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_ally.add_child(_party_label)
	_ally_btn = _button("", _on_ally_pressed, 0, 84)
	_page_ally.add_child(_ally_btn)

	box.add_child(_button("Kembali", _on_back, 0, 84))


func _build_preview() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(600, 380)
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


func _header(text: String) -> Label:
	var l := _label(text, 34)
	l.add_theme_color_override("font_color", Color("e0c070"))
	return l


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, width := 0, height := 80) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, height)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	return b
