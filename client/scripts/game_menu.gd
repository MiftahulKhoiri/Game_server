extends CanvasLayer
## Menu dalam game (dibuka tombol "Menu" atau tombol kembali Android):
## Lanjutkan, Pengaturan (kualitas grafis, sensitivitas kamera), Ke Beranda,
## Keluar akun, Tutup game. Tindakan yang berisiko (keluar akun, tutup game) minta
## ketukan kedua dalam 3 detik. Pemilik menu (world3d.gd) yang melakukan tindakannya.

signal resumed
signal profile_requested
signal inventory_requested
signal atribut_requested
signal go_home
signal logout
signal quit_game
signal settings_changed

const QUALITY_NAMES := ["Hemat", "Normal", "Tinggi"]
const QUALITY_HINTS := [
	"Hemat: tanpa bayangan. Paling ringan, cocok untuk HP lama.",
	"Normal: bayangan di sekitar pemain.",
	"Tinggi: bayangan lebih jauh dan tepi gambar lebih halus.",
]

var is_open := false

var _main: VBoxContainer
var _settings: VBoxContainer
var _settings_scroll: ScrollContainer
var _toggle_npc: CheckButton
var _toggle_music: CheckButton
var _vol_npc_value: Label
var _vol_music_value: Label
var _quality_buttons: Array[Button] = []
var _quality_hint: Label
var _sens_value: Label
var _btn_logout: Button
var _btn_tas: Button
var _btn_atribut: Button
var _confirm_key := ""
var _confirm_btn: Button
var _confirm_text := ""
var _confirm_timer: Timer


func _init() -> void:
	layer = 10
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1d2b22")
	sb.border_color = Color("5fb35a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var holder := VBoxContainer.new()
	panel.add_child(holder)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 14)
	holder.add_child(_main)
	_main.add_child(_title("Menu"))
	_main.add_child(_button("Lanjutkan", func() -> void: resumed.emit()))
	_btn_tas = _button("Ransel", func() -> void: inventory_requested.emit())
	_main.add_child(_btn_tas)
	_btn_atribut = _button("Atribut", func() -> void: atribut_requested.emit())
	_main.add_child(_btn_atribut)
	_main.add_child(_button("Profil dan pahlawan", func() -> void: profile_requested.emit()))
	_main.add_child(_button("Pengaturan", func() -> void: _show_page(false)))
	_main.add_child(_button("Ke Beranda", func() -> void: go_home.emit()))
	_btn_logout = _button("Keluar akun", Callable())
	_btn_logout.pressed.connect(func() -> void: _ask(_btn_logout, "logout", "Yakin? Ketuk lagi", func() -> void: logout.emit()))
	_main.add_child(_btn_logout)
	var btn_quit := _button("Tutup game", Callable())
	btn_quit.pressed.connect(func() -> void: _ask(btn_quit, "quit", "Yakin? Ketuk lagi", func() -> void: quit_game.emit()))
	_main.add_child(btn_quit)

	_settings_scroll = ScrollContainer.new()
	_settings_scroll.custom_minimum_size = Vector2(0, 980)
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.visible = false
	holder.add_child(_settings_scroll)
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 14)
	_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.add_child(_settings)
	_settings.add_child(_title("Pengaturan"))
	_settings.add_child(_label("Kualitas grafis"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_settings.add_child(row)
	var group := ButtonGroup.new()
	for i in QUALITY_NAMES.size():
		var b := _button(QUALITY_NAMES[i], Callable())
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_quality.bind(i))
		row.add_child(b)
		_quality_buttons.append(b)
	_quality_hint = _label("")
	_quality_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quality_hint.add_theme_font_size_override("font_size", 22)
	_quality_hint.add_theme_color_override("font_color", Color("b9c9bd"))
	_settings.add_child(_quality_hint)
	_settings.add_child(_label("Kecepatan putar kamera"))
	var slider := HSlider.new()
	slider.min_value = 0.5
	slider.max_value = 2.0
	slider.step = 0.1
	slider.custom_minimum_size = Vector2(0, 56)
	slider.value = Session.cam_sens
	slider.value_changed.connect(_on_sens)
	_settings.add_child(slider)
	_sens_value = _label("")
	_settings.add_child(_sens_value)

	_settings.add_child(_section("Suara"))
	_toggle_npc = _toggle("Suara orang (NPC)", _on_toggle_npc)
	_settings.add_child(_toggle_npc)
	_toggle_music = _toggle("Musik", _on_toggle_music)
	_settings.add_child(_toggle_music)
	_settings.add_child(_label("Volume suara NPC"))
	_settings.add_child(_volume_slider(Session.vol_npc, _on_vol_npc))
	_vol_npc_value = _label("")
	_settings.add_child(_vol_npc_value)
	_settings.add_child(_label("Volume musik"))
	_settings.add_child(_volume_slider(Session.vol_music, _on_vol_music))
	_vol_music_value = _label("")
	_settings.add_child(_vol_music_value)
	_settings.add_child(_button("Kembali", func() -> void: _show_page(true)))

	_confirm_timer = Timer.new()
	_confirm_timer.one_shot = true
	_confirm_timer.timeout.connect(_reset_confirm)
	add_child(_confirm_timer)
	_refresh_settings()


func open() -> void:
	_reset_confirm()
	_show_page(true)
	_btn_logout.disabled = Session.offline
	_btn_tas.disabled = Session.offline  # tas butuh server
	_btn_atribut.disabled = Session.offline
	visible = true
	is_open = true


func close() -> void:
	_reset_confirm()
	visible = false
	is_open = false


## Tombol kembali Android / Esc: dari Pengaturan balik ke menu, dari menu utama menutup.
func back() -> void:
	if _settings_scroll.visible:
		_show_page(true)
	else:
		resumed.emit()


func _show_page(main: bool) -> void:
	_reset_confirm()
	_main.visible = main
	_settings_scroll.visible = not main


func _on_quality(i: int) -> void:
	Session.quality = i
	Session.save_config()
	_refresh_settings()
	settings_changed.emit()


func _on_sens(v: float) -> void:
	Session.cam_sens = v
	Session.save_config()
	_refresh_settings()


func _on_toggle_npc(on: bool) -> void:
	Session.snd_npc = on
	_sound_changed()


func _on_toggle_music(on: bool) -> void:
	Session.snd_music = on
	_sound_changed()


func _on_vol_npc(v: float) -> void:
	Session.vol_npc = v
	_sound_changed()


func _on_vol_music(v: float) -> void:
	Session.vol_music = v
	_sound_changed()


func _sound_changed() -> void:
	Session.save_config()
	Sound.apply_settings()
	_refresh_settings()


func _refresh_settings() -> void:
	_toggle_npc.set_pressed_no_signal(Session.snd_npc)
	_toggle_music.set_pressed_no_signal(Session.snd_music)
	_vol_npc_value.text = "%d%%" % roundi(Session.vol_npc * 100.0)
	_vol_music_value.text = "%d%%" % roundi(Session.vol_music * 100.0)
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == Session.quality)
	_quality_hint.text = QUALITY_HINTS[clampi(Session.quality, 0, 2)]
	_sens_value.text = "%.1fx" % Session.cam_sens


func _ask(btn: Button, key: String, text_confirm: String, action: Callable) -> void:
	if _confirm_key == key:
		_reset_confirm()
		action.call()
		return
	_reset_confirm()
	_confirm_key = key
	_confirm_btn = btn
	_confirm_text = btn.text
	btn.text = text_confirm
	_confirm_timer.start(3.0)


func _reset_confirm() -> void:
	if _confirm_btn != null:
		_confirm_btn.text = _confirm_text
	_confirm_btn = null
	_confirm_key = ""
	if _confirm_timer != null:
		_confirm_timer.stop()


func _section(text: String) -> Label:
	var l := _label(text)
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color("e0c070"))
	return l


func _toggle(text: String, cb: Callable) -> CheckButton:
	var t := CheckButton.new()
	t.text = text
	t.custom_minimum_size = Vector2(0, 76)
	t.focus_mode = Control.FOCUS_NONE
	t.add_theme_font_size_override("font_size", 30)
	t.toggled.connect(cb)
	return t


func _volume_slider(value: float, cb: Callable) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.custom_minimum_size = Vector2(0, 56)
	sl.value = value
	sl.value_changed.connect(cb)
	return sl


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 44)
	l.add_theme_color_override("font_color", Color("d8f0c8"))
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b
