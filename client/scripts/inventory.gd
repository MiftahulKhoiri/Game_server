extends Control
## Ransel: lihat barang, pakai ramuan, pasang/lepas perlengkapan, dan istirahat di desa.
## Semua aturan dijalankan SERVER (docs/API.md); layar ini hanya mengirim permintaan.

const WORLD_SCENE := "res://scenes/world3d.tscn"
const ITEM_ART_DIR := "res://assets/items/"
const KIND_COLORS := {
	"consumable": Color("c0504d"),
	"material": Color("8a7a55"),
	"treasure": Color("d4a72c"),
	"equipment": Color("5a7fb0"),
	"food": Color("c98a3c"),
}
const SLOTS := [["weapon", "Senjata"], ["armor", "Pelindung"]]

var _catalog: Dictionary = {}  # id -> definisi dari server
var _summary: Label
var _message: Label
var _list: VBoxContainer
var _busy := false


func _ready() -> void:
	_build_ui()
	var res: Dictionary = await Api.item_catalog()  # katalog semua barang
	if not res.ok:
		_message.text = str(res.error)
		return
	for def: Dictionary in res.data.get("items", []):
		_catalog[str(def.id)] = def
	_rebuild()


func _equipment() -> Dictionary:
	return Session.player.state.get("equipment", {"weapon": "", "armor": ""})


func _name_of(id: String) -> String:
	return str(_catalog.get(id, {}).get("name", id))


func _rebuild() -> void:
	var st: Dictionary = Session.player.state
	_summary.text = "%s  Lv %d\nHP %d/%d   Energi %d/%d   Emas %d" % [
		Session.player.name, st.level, st.hp, st.max_hp, Session.energy(), Session.MAX_ENERGY, st.gold]
	for child in _list.get_children():
		child.queue_free()

	_add_header("Dipakai")
	var bonus_atk := 0
	var bonus_def := 0
	for slot: Array in SLOTS:
		var id := str(_equipment().get(slot[0], ""))
		var row := HBoxContainer.new()
		var label := _make_label("%s: %s" % [slot[1], _name_of(id) if id != "" else "-"], 26)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if id != "":
			bonus_atk += int(_catalog.get(id, {}).get("attack", 0))
			bonus_def += int(_catalog.get(id, {}).get("defense", 0))
			row.add_child(_make_button("Lepas", _on_unequip.bind(str(slot[0])), false, 130))
		_list.add_child(row)
	_list.add_child(_make_label("Bonus: serang +%d, tahan +%d" % [bonus_atk, bonus_def], 24))

	_add_header("Barang")
	if st.inventory.is_empty():
		_list.add_child(_make_label("Ransel kosong.", 26))
	for item: Dictionary in st.inventory:
		_add_item_row(str(item.id), int(item.qty))


func _add_item_row(id: String, qty: int) -> void:
	var def: Dictionary = _catalog.get(id, {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_icon_for(id, str(def.get("kind", ""))))
	var detail := ""
	if int(def.get("attack", 0)) > 0:
		detail = "\nSerang +%d" % int(def.attack)
	elif int(def.get("defense", 0)) > 0:
		detail = "\nTahan +%d" % int(def.defense)
	elif int(def.get("heal", 0)) > 0:
		detail = "\nHP +%d" % int(def.heal)
	var label := _make_label("%s  x%d%s" % [_name_of(id), qty, detail], 26)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var kind := str(def.get("kind", ""))
	if id == "ramuan":
		var full := int(Session.player.state.hp) >= int(Session.player.state.max_hp)
		row.add_child(_make_button("Pakai", _on_use.bind(id), full, 130))
	elif id == "ramuan_kekuatan":
		row.add_child(_make_button("Minum", _on_use.bind(id), false, 130))
	elif kind == "food":
		var full_hp := int(Session.player.state.hp) >= int(Session.player.state.max_hp)
		row.add_child(_make_button("Makan", _on_use.bind(id), full_hp, 130))
	elif kind == "equipment":
		var worn := _is_worn(id)
		row.add_child(_make_button("Dipakai" if worn else "Pakai", _on_equip.bind(id), worn, 150))
	_list.add_child(row)


func _is_worn(id: String) -> bool:
	var eq := _equipment()
	return str(eq.get("weapon", "")) == id or str(eq.get("armor", "")) == id


# --- aksi ---

func _on_use(id: String) -> void:
	var text := "Ramuan diminum."
	if id == "ramuan_kekuatan":
		text = "Energi terisi dan kekuatan naik untuk 3 pertarungan berikutnya."
	elif str(_catalog.get(id, {}).get("kind", "")) == "food":
		text = "%s dimakan: +%d HP." % [_name_of(id), int(_catalog.get(id, {}).get("heal", 0))]
	await _act(Api.inventory_use.bind(id), text)


func _on_equip(id: String) -> void:
	await _act(Api.inventory_equip.bind(id), "%s dipakai." % _name_of(id))


func _on_unequip(slot: String) -> void:
	await _act(Api.inventory_unequip.bind(slot), "Perlengkapan dilepas.")


func _on_rest() -> void:
	await _act(Api.rest, "Kamu beristirahat. HP dan energi pulih penuh.")


## Menjalankan permintaan ke server, lalu menggabungkan pemain dari server.
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
	_rebuild()


func _on_back() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- tampilan ---

func _add_header(text: String) -> void:
	var label := _make_label(text, 34)
	label.add_theme_color_override("font_color", Color("e0c070"))
	_list.add_child(label)


func _icon_for(id: String, kind: String) -> Control:
	var path := ITEM_ART_DIR + id + ".png"
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path) as Texture2D
		tex.custom_minimum_size = Vector2(72, 72)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var box := ColorRect.new()
	box.color = KIND_COLORS.get(kind, Color("777777"))
	box.custom_minimum_size = Vector2(72, 72)
	return box


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a2420")
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

	box.add_child(_make_label("Ransel", 44))
	_summary = _make_label("", 28)
	box.add_child(_summary)

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

	box.add_child(_make_button("Istirahat (gratis, di desa)", _on_rest, false, 0, 90))
	box.add_child(_make_button("Kembali", _on_back, false, 0, 100))


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, callback: Callable, disabled := false, width := 0, height := 80) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.custom_minimum_size = Vector2(width, height)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(callback)
	return button
