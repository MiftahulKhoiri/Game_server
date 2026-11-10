extends VBoxContainer
## Pengaturan kontrol layar sentuh (roadmap no. 217): ukuran joystick dan tombol aksi, serta mode tangan
## kiri. Dipakai di Pengaturan beranda (pengaturan_umum.gd) dan di Menu dalam permainan (game_menu.gd).

const NAMES := ["Kecil", "Normal", "Besar"]

var _size_buttons: Array[Button] = []
var _left: CheckButton


func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var head := Label.new()
	head.text = "Kontrol"
	head.add_theme_font_size_override("font_size", 32)
	head.add_theme_color_override("font_color", Color("ffd27a"))
	add_child(head)
	var l := Label.new()
	l.text = "Ukuran joystick dan tombol"
	l.add_theme_font_size_override("font_size", 26)
	add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var group := ButtonGroup.new()
	for i in NAMES.size():
		var b := Button.new()
		b.text = NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 76)
		b.add_theme_font_size_override("font_size", 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_size.bind(i))
		row.add_child(b)
		_size_buttons.append(b)
	_left = CheckButton.new()
	_left.text = "Tangan kiri (joystick di kanan)"
	_left.focus_mode = Control.FOCUS_NONE
	_left.add_theme_font_size_override("font_size", 26)
	_left.custom_minimum_size = Vector2(0, 64)
	_left.toggled.connect(_on_left)
	add_child(_left)
	_refresh()


func _on_size(i: int) -> void:
	Session.ui_size = i
	_changed()


func _on_left(on: bool) -> void:
	Session.left_hand = on
	_changed()


func _changed() -> void:
	Session.save_config()
	Session.ui_changed.emit()
	_refresh()


func _refresh() -> void:
	for i in _size_buttons.size():
		_size_buttons[i].set_pressed_no_signal(i == Session.ui_size)
	_left.set_pressed_no_signal(Session.left_hand)
