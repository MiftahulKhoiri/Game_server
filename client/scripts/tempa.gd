extends CanvasLayer
## Layar Tempa di pandai besi (roadmap no. 145-146): ubah bahan alam (kayu, bongkah batu, serat rumput
## dari memukul pohon, batu, dan rumput) menjadi barang. Resep dan aturannya di server (GET /v1/progress,
## POST /v1/craft); layar ini hanya menampilkan dan mengirim permintaan.

signal closed

const ITEM_ART_DIR := "res://assets/items/"
const MATERIAL_NAMES := {"kayu": "Kayu", "bongkah_batu": "Bongkah Batu", "serat": "Serat Rumput", "taring_goblin": "Taring Goblin"}

var is_open := false
var keeper := "Mpu Karta"

var _list: VBoxContainer
var _status: Label
var _bahan: Label
var _recipes: Array = []
var _catalog: Dictionary = {}
var _busy := false


func _init() -> void:
	layer = 11
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
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
	sb.bg_color = Color("2a211b")
	sb.border_color = Color("c9823a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := _label("Tempa", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("ffd9a0"))
	box.add_child(title)
	var sub := _label("Pukul pohon, batu, dan rumput untuk mengumpulkan bahan.", 22)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", Color("cdb89a"))
	box.add_child(sub)
	_bahan = _label("", 26)
	_bahan.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_bahan)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_status = _label("", 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("ffd27a"))
	box.add_child(_status)
	box.add_child(_button("Tutup", func() -> void: closed.emit(), 84))


func open() -> void:
	visible = true
	is_open = true
	_status.text = "%s: Bawakan bahannya, akan kutempa untukmu." % keeper
	if _recipes.is_empty():
		var res: Dictionary = await Api.progress_get()
		if res.ok:
			_recipes = res.data.get("recipes", [])
		var shop: Dictionary = await Api.shop_get()
		if shop.ok:
			for d: Dictionary in shop.data.get("items", []):
				_catalog[str(d.id)] = d
	_rebuild()


func close() -> void:
	visible = false
	is_open = false


func _qty(id: String) -> int:
	for it: Dictionary in Session.player.state.inventory:
		if str(it.id) == id:
			return int(it.qty)
	return 0


func _name_of(id: String) -> String:
	return str(_catalog.get(id, {}).get("name", MATERIAL_NAMES.get(id, id)))


func _rebuild() -> void:
	_bahan.text = "Bahanmu: Kayu %d   Bongkah Batu %d   Serat %d   Taring %d" % [
		_qty("kayu"), _qty("bongkah_batu"), _qty("serat"), _qty("taring_goblin")]
	for c in _list.get_children():
		c.queue_free()
	if _recipes.is_empty():
		_list.add_child(_label("Daftar resep belum termuat (server tidak terjangkau).", 24))
		return
	for r: Dictionary in _recipes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var id := str(r.id)
		var icon_path := ITEM_ART_DIR + id + ".png"
		if ResourceLoader.exists(icon_path):
			var tex := TextureRect.new()
			tex.texture = load(icon_path) as Texture2D
			tex.custom_minimum_size = Vector2(72, 72)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(tex)
		var parts: Array[String] = []
		var can := true
		for n: Dictionary in r.needs:
			var have := _qty(str(n.id))
			parts.append("%s %d/%d" % [_name_of(str(n.id)), have, int(n.qty)])
			can = can and have >= int(n.qty)
		var label := _label("%s\n%s" % [_name_of(id), ", ".join(parts)], 23)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var b := _button("Tempa", _on_craft.bind(id), 76)
		b.custom_minimum_size.x = 140
		b.disabled = not can or _busy
		row.add_child(b)
		_list.add_child(row)


func _on_craft(id: String) -> void:
	if _busy:
		return
	_busy = true
	_rebuild()
	var res: Dictionary = await Api.craft(id, 1)
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = "Dentang! %s selesai ditempa dan masuk ransel." % _name_of(id)
	else:
		_status.text = str(res.error)
	_rebuild()


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, h := 80) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	return b
