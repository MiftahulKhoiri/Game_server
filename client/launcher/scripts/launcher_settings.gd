extends Control
## Pengaturan launcher (berlaku untuk semua game di aplikasi):
##   Server            : alamat server Raspberry Pi + tombol tes. Dipakai bersama oleh semua game
##                       (sebelumnya ada di Pengaturan The Last Dragon).
##   Pembaruan aplikasi: versi terpasang, versi terbaru dari server, unduh & pasang APK baru
##                       (alur Updater yang sama dengan The Last Dragon; bukan Android: buka halaman unduhan).

signal closed
signal update_state(available: bool)

const Version := preload("res://scripts/version.gd")
const Updater := preload("res://scripts/updater.gd")
const ApiScript := preload("res://scripts/api.gd")

const BG := Color("141a24")
const PANEL := Color("1f2836")
const ACCENT := Color("f0b429")
const OK_COL := Color("5ccf7a")
const ERR_COL := Color("ff7b6b")
const YELLOW := Color("f0d040")

var url_edit: LineEdit
var server_msg: Label
var update_msg: Label
var version_label: Label
var btn_test: Button
var btn_check: Button
var btn_update: Button
var progress: ProgressBar
var update_url := ""
var latest := ""
var update_available := false
var update_required := false
var _updater: Node
var _busy := false
var _open_web := false


func _ready() -> void:
	get_tree().quit_on_go_back = false  # tombol kembali Android menutup Pengaturan, bukan aplikasi
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mg := MarginContainer.new()
	mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + side, 80)
	mg.add_theme_constant_override("margin_top", 20)
	mg.add_theme_constant_override("margin_bottom", 40)
	sc.add_child(mg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	mg.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var back := _button("Kembali", 24)
	back.name = "Back"
	back.custom_minimum_size = Vector2(170, 62)
	back.pressed.connect(close)
	head.add_child(back)
	var title := _label("Pengaturan", 38)
	title.add_theme_color_override("font_color", ACCENT)
	head.add_child(title)
	v.add_child(head)

	v.add_child(_panel_title("Server (untuk semua game)"))
	v.add_child(_label("Alamat server Raspberry Pi. Dipakai untuk katalog game, akun, dan menyimpan progres.", 20, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	url_edit = LineEdit.new()
	url_edit.name = "Url"
	url_edit.text = _api_base()
	url_edit.placeholder_text = _default_url()
	url_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	url_edit.add_theme_font_size_override("font_size", 24)
	url_edit.custom_minimum_size = Vector2(0, 62)
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_edit.text_submitted.connect(func(_t: String) -> void: test_server())
	row.add_child(url_edit)
	btn_test = _button("Tes & simpan", 22)
	btn_test.name = "TestServer"
	btn_test.custom_minimum_size = Vector2(200, 62)
	btn_test.pressed.connect(test_server)
	row.add_child(btn_test)
	v.add_child(row)
	server_msg = _label("", 20, true)
	server_msg.name = "ServerMsg"
	v.add_child(server_msg)

	v.add_child(_panel_title("Pembaruan aplikasi"))
	version_label = _label("Aplikasi terpasang: v%s" % Version.app_version(), 22)
	version_label.name = "AppVersion"
	v.add_child(version_label)
	update_msg = _label("", 22, true)
	update_msg.name = "UpdateMsg"
	v.add_child(update_msg)
	var urow := HBoxContainer.new()
	urow.add_theme_constant_override("separation", 10)
	btn_check = _button("Periksa pembaruan", 22)
	btn_check.name = "CheckUpdate"
	btn_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_check.custom_minimum_size = Vector2(0, 62)
	btn_check.pressed.connect(check_update)
	urow.add_child(btn_check)
	btn_update = _button("Unduh dan pasang", 22)
	btn_update.name = "DoUpdate"
	btn_update.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_update.custom_minimum_size = Vector2(0, 62)
	btn_update.visible = false
	btn_update.pressed.connect(_on_update)
	urow.add_child(btn_update)
	v.add_child(urow)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 24)
	progress.visible = false
	v.add_child(progress)
	v.add_child(_label("Game unduhan (mis. Petualangan Ilmu SD) diperbarui dari halaman utama launcher (tombol UPDATE).", 18, true))

	_updater = Updater.new()
	add_child(_updater)
	_updater.status.connect(func(t: String) -> void: _msg(update_msg, t, Color.WHITE))
	_updater.progress.connect(func(r: int, t: int) -> void:
		if t > 0:
			progress.value = 100.0 * r / t
			_msg(update_msg, "Mengunduh... %.1f / %.1f MB" % [r / 1048576.0, t / 1048576.0], Color.WHITE))
	check_update()


func close() -> void:
	if _busy:
		return
	get_tree().quit_on_go_back = true
	closed.emit()
	queue_free()


## Tombol kembali Android saat Pengaturan terbuka: tutup Pengaturan saja.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		close()


func _api() -> Node:
	return get_node_or_null("/root/Api")


func _api_base() -> String:
	return str(GameManager.api.base_url())


func _default_url() -> String:
	return ApiScript.DEFAULT_URL


static func clean_url(text: String) -> String:
	var url := text.strip_edges().rstrip("/")
	if url != "" and not url.contains("://"):
		url = "http://" + url
	return url


## GET /v1/version lewat alamat server yang dipakai launcher. {ok, data, error}
func _version() -> Dictionary:
	var r: Dictionary = await GameManager.api.get_bytes("/v1/version", 6.0)
	if not r.ok:
		return {"ok": false, "data": {}, "error": str(r.error)}
	var d = JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())
	return {"ok": typeof(d) == TYPE_DICTIONARY, "data": d if typeof(d) == TYPE_DICTIONARY else {}, "error": "jawaban tidak sah"}


## Tes alamat server; bila terjangkau, alamat disimpan (dipakai semua game) dan katalog dimuat ulang.
func test_server() -> void:
	if _busy:
		return
	var url := clean_url(url_edit.text)
	if url == "":
		_msg(server_msg, "Isi alamat server dulu.", ERR_COL)
		return
	url_edit.text = url
	var api := _api()
	var old := ""
	if api != null:
		old = str(api.base_url)
		api.base_url = url
	var old_override: String = GameManager.api.base_url_override
	if old_override != "":
		GameManager.api.base_url_override = url
	_busy = true
	btn_test.disabled = true
	_msg(server_msg, "Mengecek server...", Color.WHITE)
	var res := await _version()
	_busy = false
	btn_test.disabled = false
	if not res.ok:
		if api != null:
			api.base_url = old
		GameManager.api.base_url_override = old_override
		_msg(server_msg, "Server tidak terjangkau: %s. Alamat lama tetap dipakai." % str(res.error), ERR_COL)
		return
	var session := get_node_or_null("/root/Session")
	if session != null and session.has_method("save_config"):
		session.save_config()
	_msg(server_msg, "Server tersambung: %s  (server v%s)" % [url, str(res.data.get("server", "?"))], OK_COL)
	_apply(res.data)
	GameManager.refresh_catalog()


func check_update() -> void:
	btn_check.disabled = true
	_msg(update_msg, "Memeriksa pembaruan...", Color.WHITE)
	var res := await _version()
	if not is_inside_tree():
		return
	btn_check.disabled = false
	if not res.ok:
		_msg(update_msg, "Tidak bisa memeriksa pembaruan (server tidak terjangkau).", ERR_COL)
		return
	_apply(res.data)


## Bandingkan versi aplikasi dengan jawaban server.
func _apply(info: Dictionary) -> void:
	update_url = str(info.get("update_url", ""))
	latest = str(info.get("latest_client", "0.0.0"))
	var mine := Version.app_version()
	update_required = Version.compare(mine, str(info.get("min_client", "0.0.0"))) < 0
	update_available = update_required or Version.compare(mine, latest) < 0
	if update_required:
		_msg(update_msg, "Aplikasi v%s terlalu lama. WAJIB update ke v%s." % [mine, latest], ERR_COL)
	elif update_available:
		_msg(update_msg, "Versi baru tersedia: v%s (terpasang v%s)." % [latest, mine], YELLOW)
	else:
		_msg(update_msg, "Aplikasi sudah versi terbaru (v%s)." % mine, OK_COL)
	btn_update.text = "Unduh dan pasang v%s" % latest
	btn_update.visible = update_available and update_url != ""
	update_state.emit(update_available)


func _on_update() -> void:
	if _busy or update_url == "":
		return
	if _open_web or not Updater.supported():
		OS.shell_open(update_url)
		return
	_busy = true
	btn_update.disabled = true
	progress.value = 0
	progress.visible = true
	var res_v: Variant = await _updater.run(update_url)
	var res: Dictionary = res_v if res_v is Dictionary else {"ok": false, "web": true, "message": "Pembaruan terhenti."}
	_busy = false
	btn_update.disabled = false
	progress.visible = false
	_msg(update_msg, str(res.get("message", "")), OK_COL if bool(res.get("ok", false)) else ERR_COL)
	if res.get("web", false):
		_open_web = true
		btn_update.text = "Buka halaman unduhan"


func _msg(l: Label, text: String, c: Color) -> void:
	l.text = text
	l.add_theme_color_override("font_color", c)


func _panel_title(text: String) -> Label:
	var l := _label(text, 28)
	l.add_theme_color_override("font_color", ACCENT)
	return l


func _label(text: String, size: int, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	return b
