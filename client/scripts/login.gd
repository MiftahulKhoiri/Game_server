extends Control
## Layar awal: atur alamat server, daftar pemain baru, atau lanjutkan.
## Seluruh antarmuka dibuat lewat kode agar mudah ditinjau di Pull Request.

const WORLD_SCENE := "res://scenes/world.tscn"

var _url_edit: LineEdit
var _name_edit: LineEdit
var _status: Label
var _btn_start: Button
var _btn_continue: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1b2a1f")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title := _make_label("Game Petualang", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_make_label("Alamat server", 26))
	_url_edit = _make_edit(Api.base_url, "http://192.168.x.x:8090")
	box.add_child(_url_edit)

	box.add_child(_make_label("Nama petualang (3-20 huruf/angka/_)", 26))
	_name_edit = _make_edit("", "Nama baru")
	_name_edit.max_length = 20
	box.add_child(_name_edit)

	_btn_start = _make_button("Mulai petualangan baru")
	_btn_start.pressed.connect(_on_start)
	box.add_child(_btn_start)

	_btn_continue = _make_button("Lanjutkan petualangan")
	_btn_continue.pressed.connect(_on_continue)
	_btn_continue.visible = Api.token != ""
	box.add_child(_btn_continue)

	_status = _make_label("", 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)


func _on_start() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name.length() < 3:
		_status.text = "Isi nama dulu (minimal 3 karakter)."
		return
	_set_busy(true, "Mendaftar...")
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.register(player_name)
	if not res.ok:
		_set_busy(false, str(res.error))
		return
	Api.token = str(res.data.token)
	Session.offline = false
	Session.set_player(res.data.player)
	Session.save_config()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_continue() -> void:
	_set_busy(true, "Menghubungkan...")
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.get_me()
	if not res.ok:
		if res.status == 401:
			Api.token = ""
			Session.save_config()
			_btn_continue.visible = false
			_set_busy(false, "Token tidak berlaku lagi. Mulai petualangan baru.")
		else:
			_set_busy(false, str(res.error))
		return
	Session.offline = false
	Session.set_player(res.data)
	Session.save_config()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _set_busy(busy: bool, message: String) -> void:
	_btn_start.disabled = busy
	_btn_continue.disabled = busy
	_status.text = message


func _clean_url(text: String) -> String:
	var url := text.strip_edges().rstrip("/")
	if url != "" and not url.contains("://"):
		url = "http://" + url
	return url


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_edit(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", 30)
	edit.custom_minimum_size = Vector2(0, 80)
	return edit


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 30)
	button.custom_minimum_size = Vector2(0, 90)
	return button
