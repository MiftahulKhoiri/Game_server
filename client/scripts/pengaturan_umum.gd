extends VBoxContainer
## Bagian "Layar" dan "Suara" pada halaman Pengaturan beranda: kualitas grafis, kecepatan putar kamera,
## layar tetap menyala, nyala/mati dan volume suara NPC serta musik. Semua tersimpan di HP lewat Session.
## (Menu dalam game punya versinya sendiri di game_menu.gd dengan isi yang sama.)

const QUALITY_NAMES := ["Hemat", "Normal", "Tinggi"]
const QUALITY_HINTS := [
	"Hemat: tanpa bayangan. Paling ringan, cocok untuk HP lama.",
	"Normal: bayangan di sekitar pemain.",
	"Tinggi: bayangan lebih jauh dan tepi gambar lebih halus.",
]

var _quality_buttons: Array[Button] = []
var _quality_hint: Label
var _sens_value: Label
var _toggle_keep: CheckButton
var _toggle_npc: CheckButton
var _toggle_music: CheckButton
var _toggle_blood: CheckButton
var _vol_npc_value: Label
var _vol_music_value: Label


func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	add_child(_section("Layar"))
	add_child(_label("Kualitas grafis"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var group := ButtonGroup.new()
	for i in QUALITY_NAMES.size():
		var b := Button.new()
		b.text = QUALITY_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 80)
		b.add_theme_font_size_override("font_size", 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_quality.bind(i))
		row.add_child(b)
		_quality_buttons.append(b)
	_quality_hint = _label("", 22)
	_quality_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quality_hint.modulate = Color(1, 1, 1, 0.7)
	add_child(_quality_hint)
	add_child(_label("Kecepatan putar kamera"))
	add_child(_slider(0.5, 2.0, 0.1, Session.cam_sens, _on_sens))
	_sens_value = _label("", 24)
	add_child(_sens_value)
	_toggle_keep = _toggle("Layar tetap menyala", _on_keep)
	add_child(_toggle_keep)
	_toggle_blood = _toggle("Percikan darah saat memukul", _on_blood)
	add_child(_toggle_blood)

	add_child(_section("Suara"))
	_toggle_npc = _toggle("Suara orang (NPC)", _on_npc)
	add_child(_toggle_npc)
	_toggle_music = _toggle("Musik", _on_music)
	add_child(_toggle_music)
	add_child(_label("Volume suara NPC"))
	add_child(_slider(0.0, 1.0, 0.05, Session.vol_npc, _on_vol_npc))
	_vol_npc_value = _label("", 24)
	add_child(_vol_npc_value)
	add_child(_label("Volume musik"))
	add_child(_slider(0.0, 1.0, 0.05, Session.vol_music, _on_vol_music))
	_vol_music_value = _label("", 24)
	add_child(_vol_music_value)
	_refresh()


func _on_quality(i: int) -> void:
	Session.quality = i
	_simpan()


func _on_sens(v: float) -> void:
	Session.cam_sens = v
	_simpan()


func _on_keep(on: bool) -> void:
	Session.keep_on = on
	Session.apply_display()
	_simpan()


func _on_blood(on: bool) -> void:
	Session.fx_blood = on
	_simpan()


func _on_npc(on: bool) -> void:
	Session.snd_npc = on
	_simpan_suara()


func _on_music(on: bool) -> void:
	Session.snd_music = on
	_simpan_suara()


func _on_vol_npc(v: float) -> void:
	Session.vol_npc = v
	_simpan_suara()


func _on_vol_music(v: float) -> void:
	Session.vol_music = v
	_simpan_suara()


func _simpan_suara() -> void:
	Sound.apply_settings()
	_simpan()


func _simpan() -> void:
	Session.save_config()
	_refresh()


func _refresh() -> void:
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == Session.quality)
	_quality_hint.text = QUALITY_HINTS[clampi(Session.quality, 0, 2)]
	_sens_value.text = "%.1fx" % Session.cam_sens
	_toggle_keep.set_pressed_no_signal(Session.keep_on)
	_toggle_blood.set_pressed_no_signal(Session.fx_blood)
	_toggle_npc.set_pressed_no_signal(Session.snd_npc)
	_toggle_music.set_pressed_no_signal(Session.snd_music)
	_vol_npc_value.text = "%d%%" % roundi(Session.vol_npc * 100.0)
	_vol_music_value.text = "%d%%" % roundi(Session.vol_music * 100.0)


func _section(text: String) -> Label:
	var l := _label(text, 34)
	l.add_theme_color_override("font_color", Color("e0c070"))
	return l


func _label(text: String, size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _toggle(text: String, cb: Callable) -> CheckButton:
	var t := CheckButton.new()
	t.text = text
	t.custom_minimum_size = Vector2(0, 76)
	t.focus_mode = Control.FOCUS_NONE
	t.add_theme_font_size_override("font_size", 28)
	t.toggled.connect(cb)
	return t


func _slider(lo: float, hi: float, step: float, value: float, cb: Callable) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.custom_minimum_size = Vector2(0, 56)
	sl.value = value
	sl.value_changed.connect(cb)
	return sl
