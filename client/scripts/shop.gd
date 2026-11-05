extends Control
## Toko desa. Harga dan hasil transaksi dihitung SERVER (docs/API.md);
## layar ini hanya menampilkan daftar dan mengirim permintaan beli/jual.
## Ikon barang dimuat dari res://assets/items/<id>.png bila ada, kalau tidak
## dipakai kotak berwarna sesuai jenis barang.

const WORLD_SCENE := "res://scenes/world.tscn"
const ITEM_ART_DIR := "res://assets/items/"
const KIND_COLORS := {
	"consumable": Color("c0504d"),
	"material": Color("8a7a55"),
	"treasure": Color("d4a72c"),
}

var _catalog: Array = []
var _gold_label: Label
var _message: Label
var _list: VBoxContainer
var _busy := false


func _ready() -> void:
	_build_ui()
	var res: Dictionary = await Api.shop_get()
	if not res.ok:
		_message.text = str(res.error)
		return
	_catalog = res.data.get("items", [])
	_rebuild()


func _owned(id: String) -> int:
	for item: Dictionary in Session.player.state.inventory:
		if item.id == id:
			return int(item.qty)
	return 0


func _rebuild() -> void:
	_gold_label.text = "Emas: %d" % int(Session.player.state.gold)
	for child in _list.get_children():
		child.queue_free()
	_add_header("Beli")
	for def: Dictionary in _catalog:
		if int(def.buy_price) > 0:
			_add_row(def, "Beli", int(def.buy_price), "buy",
				int(Session.player.state.gold) < int(def.buy_price))
	_add_header("Jual")
	var any_sale := false
	for def: Dictionary in _catalog:
		var owned := _owned(str(def.id))
		if int(def.sell_price) > 0 and owned > 0:
			any_sale = true
			_add_row(def, "Jual", int(def.sell_price), "sell", false, owned)
	if not any_sale:
		var empty := _make_label("Tidak ada yang bisa dijual.", 26)
		_list.add_child(empty)


func _on_trade(kind: String, id: String) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary
	if kind == "buy":
		res = await Api.shop_buy(id, 1)
	else:
		res = await Api.shop_sell(id, 1)
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_message.text = "Berhasil."
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


func _add_row(def: Dictionary, verb: String, price: int, kind: String, disabled: bool, owned := -1) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_icon_for(def))
	var name_text := str(def.name)
	if owned >= 0:
		name_text += "  x%d" % owned
	var label := _make_label("%s\n%d emas" % [name_text, price], 26)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := Button.new()
	button.text = verb
	button.disabled = disabled
	button.custom_minimum_size = Vector2(150, 80)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(_on_trade.bind(kind, str(def.id)))
	row.add_child(button)
	_list.add_child(row)


func _icon_for(def: Dictionary) -> Control:
	var path := ITEM_ART_DIR + str(def.id) + ".png"
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path) as Texture2D
		tex.custom_minimum_size = Vector2(72, 72)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var box := ColorRect.new()
	box.color = KIND_COLORS.get(str(def.kind), Color("777777"))
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

	box.add_child(_make_label("Toko Desa", 44))
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
