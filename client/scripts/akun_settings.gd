extends VBoxContainer
## Pengaturan akun di Menu > Pengaturan (roadmap no. 221-222): lihat jumlah perangkat yang masuk,
## keluarkan akun dari perangkat lain, dan ganti kata sandi (sesi di perangkat lain ikut dicabut).

var _devices: Label
var _status: Label
var _old: LineEdit
var _new: LineEdit
var _busy := false


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var head := _label("Akun", 32)
	head.add_theme_color_override("font_color", Color("ffd27a"))
	add_child(head)
	_devices = _label("", 24)
	add_child(_devices)
	add_child(_button("Keluar dari perangkat lain", _on_logout_others))
	add_child(_label("Ganti kata sandi", 26))
	_old = _edit("Kata sandi sekarang")
	add_child(_old)
	_new = _edit("Kata sandi baru (minimal 8)")
	add_child(_new)
	add_child(_button("Simpan kata sandi baru", _on_change))
	_status = _label("", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	visibility_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_visible_in_tree() or Session.offline or _devices == null:
		return
	var res: Dictionary = await Api.sessions_get()
	if res.ok:
		var n: int = (res.data.get("sessions", []) as Array).size()
		_devices.text = "Masuk di %d perangkat (sesi berakhir bila %d hari tidak dipakai)" % [n, int(res.data.get("idle_days", 30))]


func _on_logout_others() -> void:
	if _busy or Session.offline:
		return
	_busy = true
	var res: Dictionary = await Api.logout_others()
	_busy = false
	_status.text = ("Akun dikeluarkan dari %d perangkat lain." % int(res.data.get("revoked", 0))) if res.ok else str(res.error)
	refresh()


func _on_change() -> void:
	if _busy or Session.offline:
		return
	if _new.text.length() < 8:
		_status.text = "Kata sandi baru minimal 8 karakter."
		return
	_busy = true
	var res: Dictionary = await Api.change_password(_old.text, _new.text)
	_busy = false
	if res.ok:
		_status.text = "Kata sandi diganti. Perangkat lain harus masuk lagi."
		_old.text = ""
		_new.text = ""
		refresh()
	else:
		_status.text = str(res.error)


func _edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = true
	e.max_length = 128
	e.custom_minimum_size = Vector2(0, 68)
	e.add_theme_font_size_override("font_size", 24)
	return e


func _label(text: String, size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 72)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	return b
