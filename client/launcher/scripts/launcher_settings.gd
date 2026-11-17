extends Control
## Pengaturan launcher (berlaku untuk semua game di aplikasi):
##   Akun              : masuk / daftar / keluar. Satu akun untuk semua game (The Last Dragon, SD, SMP);
##                       token disimpan Session seperti layar masuk The Last Dragon, kata sandi tidak disimpan.
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
const TAB_ON := Color("33507a")
const TAB_OFF := Color("263142")
const MIN_PASSWORD := 8
const KB_MARGIN := 28.0

# Akun
var account_status: Label
var account_msg: Label
var tab_row: HBoxContainer
var tab_login: Button
var tab_register: Button
var login_box: VBoxContainer
var register_box: VBoxContainer
var logged_box: VBoxContainer
var login_name: LineEdit
var login_pass: LineEdit
var reg_name: LineEdit
var reg_email: LineEdit
var reg_pass: LineEdit
var reg_pass2: LineEdit
var btn_login: Button
var btn_register: Button
var btn_logout: Button
var account_tab := "login"
var _acc_busy := false
var _scroll: ScrollContainer
var _kb_spacer: Control
var _kb_px := -1

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
	_scroll = sc
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

	_build_account(v)

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
	_kb_spacer = Control.new()  # ruang papan ketik layar HP supaya isian tidak tertutup
	v.add_child(_kb_spacer)

	_updater = Updater.new()
	add_child(_updater)
	_updater.status.connect(func(t: String) -> void: _msg(update_msg, t, Color.WHITE))
	_updater.progress.connect(func(r: int, t: int) -> void:
		if t > 0:
			progress.value = 100.0 * r / t
			_msg(update_msg, "Mengunduh... %.1f / %.1f MB" % [r / 1048576.0, t / 1048576.0], Color.WHITE))
	check_update()
	refresh_account()
	_check_session()


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


# --- Akun: masuk / daftar / keluar --------------------------------------------------------

func _build_account(v: VBoxContainer) -> void:
	v.add_child(_panel_title("Akun"))
	account_status = _label("", 22, true)
	account_status.name = "AccountStatus"
	v.add_child(account_status)

	tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 10)
	tab_login = _button("Masuk", 24)
	tab_login.name = "TabLogin"
	tab_register = _button("Daftar", 24)
	tab_register.name = "TabRegister"
	for b: Button in [tab_login, tab_register]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 62)
		tab_row.add_child(b)
	tab_login.pressed.connect(func() -> void: show_account_tab("login"))
	tab_register.pressed.connect(func() -> void: show_account_tab("register"))
	v.add_child(tab_row)

	# Masuk
	login_box = _vbox()
	login_name = _edit("Nama atau email", false)
	login_name.text = str(Session.saved_name)
	login_name.max_length = 254
	login_pass = _edit("Kata sandi", true)
	login_box.add_child(login_name)
	login_box.add_child(login_pass)
	login_box.add_child(_show_pass([login_pass]))
	btn_login = _button("Masuk", 24)
	btn_login.name = "DoLogin"
	btn_login.custom_minimum_size = Vector2(0, 66)
	btn_login.add_theme_stylebox_override("normal", _box(Color("2f7d46")))
	btn_login.pressed.connect(do_login)
	login_box.add_child(btn_login)
	login_name.text_submitted.connect(func(_t: String) -> void: login_pass.grab_focus())
	login_pass.text_submitted.connect(func(_t: String) -> void:
		login_pass.release_focus()
		do_login())
	v.add_child(login_box)

	# Daftar
	register_box = _vbox()
	reg_name = _edit("Nama petualang (3-20 huruf/angka/_)", false)
	reg_name.max_length = 20
	reg_email = _edit("Email, mis. nama@contoh.com", false)
	reg_email.max_length = 254
	reg_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	reg_pass = _edit("Kata sandi (minimal %d karakter)" % MIN_PASSWORD, true)
	reg_pass2 = _edit("Ulangi kata sandi", true)
	for e: LineEdit in [reg_name, reg_email, reg_pass, reg_pass2]:
		register_box.add_child(e)
	register_box.add_child(_show_pass([reg_pass, reg_pass2]))
	btn_register = _button("Daftar akun baru", 24)
	btn_register.name = "DoRegister"
	btn_register.custom_minimum_size = Vector2(0, 66)
	btn_register.add_theme_stylebox_override("normal", _box(Color("2f7d46")))
	btn_register.pressed.connect(do_register)
	register_box.add_child(btn_register)
	reg_name.text_submitted.connect(func(_t: String) -> void: reg_email.grab_focus())
	reg_email.text_submitted.connect(func(_t: String) -> void: reg_pass.grab_focus())
	reg_pass.text_submitted.connect(func(_t: String) -> void: reg_pass2.grab_focus())
	reg_pass2.text_submitted.connect(func(_t: String) -> void:
		reg_pass2.release_focus()
		do_register())
	v.add_child(register_box)

	# Sudah masuk
	logged_box = _vbox()
	btn_logout = _button("Keluar dari akun ini", 22)
	btn_logout.name = "DoLogout"
	btn_logout.custom_minimum_size = Vector2(0, 62)
	btn_logout.pressed.connect(do_logout)
	logged_box.add_child(btn_logout)
	v.add_child(logged_box)

	account_msg = _label("", 20, true)
	account_msg.name = "AccountMsg"
	v.add_child(account_msg)


func logged_in() -> bool:
	return str(Api.token) != ""


## Tampilkan bagian akun sesuai keadaan: sudah masuk (nama + tombol keluar) atau belum (Masuk/Daftar).
func refresh_account() -> void:
	var on := logged_in()
	if on:
		var nm := str(Session.saved_name)
		account_status.text = ("Masuk sebagai %s." % nm if nm != "" else "Sudah masuk di HP ini.") \
			+ " Progres semua game tersimpan di server."
		account_status.add_theme_color_override("font_color", OK_COL)
	else:
		account_status.text = "Belum masuk. Masuk atau daftar supaya progres semua game tersimpan di server dan bisa dipulihkan di HP lain."
		account_status.add_theme_color_override("font_color", Color.WHITE)
	tab_row.visible = not on
	logged_box.visible = on
	login_box.visible = not on and account_tab == "login"
	register_box.visible = not on and account_tab == "register"
	tab_login.add_theme_stylebox_override("normal", _box(TAB_ON if account_tab == "login" else TAB_OFF))
	tab_register.add_theme_stylebox_override("normal", _box(TAB_ON if account_tab == "register" else TAB_OFF))


func show_account_tab(tab: String) -> void:
	account_tab = tab
	account_msg.text = ""
	for e: LineEdit in [login_pass, reg_pass, reg_pass2]:
		e.text = ""  # kata sandi tidak terbawa antar tab
	refresh_account()


## Saat dibuka: pastikan token tersimpan masih berlaku (dicabut dari HP lain / kedaluwarsa -> keluar).
func _check_session() -> void:
	if not logged_in():
		return
	var res: Dictionary = await Api.get_me()
	if not is_inside_tree() or _acc_busy:
		return
	if res.ok:
		Session.saved_name = str(res.data.get("name", Session.saved_name))
		refresh_account()
	elif int(res.get("status", 0)) == 401:
		_forget_session()
		_msg(account_msg, "Sesi sudah berakhir. Masuk lagi dengan nama dan kata sandimu.", ERR_COL)


func do_login() -> void:
	if _acc_busy:
		return
	var n := login_name.text.strip_edges()
	if n == "" or login_pass.text == "":
		_msg(account_msg, "Isi nama (atau email) dan kata sandi.", ERR_COL)
		return
	_set_acc_busy(true, "Masuk...")
	var res: Dictionary = await Api.login(n, login_pass.text)
	if not is_inside_tree():
		return
	_set_acc_busy(false, "")
	if not res.ok:
		# 401 = nama/email atau kata sandi salah; 429 = terlalu banyak percobaan; 0 = server tidak terjangkau.
		_msg(account_msg, str(res.error), ERR_COL)
		return
	_signed_in(res.data, "Berhasil masuk")


func do_register() -> void:
	if _acc_busy:
		return
	var nm := reg_name.text.strip_edges()
	var em := reg_email.text.strip_edges()
	if RegEx.create_from_string("^[A-Za-z0-9_]{3,20}$").search(nm) == null:
		_msg(account_msg, "Nama 3-20 karakter: huruf, angka, atau _ (tanpa spasi).", ERR_COL)
		return
	if RegEx.create_from_string("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").search(em) == null:
		_msg(account_msg, "Isi email yang benar, mis. nama@contoh.com.", ERR_COL)
		return
	if reg_pass.text.length() < MIN_PASSWORD:
		_msg(account_msg, "Kata sandi minimal %d karakter." % MIN_PASSWORD, ERR_COL)
		return
	if reg_pass.text != reg_pass2.text:
		_msg(account_msg, "Kata sandi dan ulangannya tidak sama.", ERR_COL)
		return
	_set_acc_busy(true, "Mendaftar...")
	var res: Dictionary = await Api.register(nm, em, reg_pass.text)
	if not is_inside_tree():
		return
	_set_acc_busy(false, "")
	if not res.ok:
		_msg(account_msg, str(res.error), ERR_COL)
		return
	_signed_in(res.data, "Akun dibuat")


## Simpan sesi dari jawaban daftar/masuk ({"player", "token"}), sama seperti layar masuk The Last Dragon.
func _signed_in(data: Dictionary, what: String) -> void:
	Api.token = str(data.get("token", ""))
	Session.offline = false
	var p: Dictionary = data.get("player", {}) if typeof(data.get("player")) == TYPE_DICTIONARY else {}
	if not p.is_empty():
		Session.set_player(p)
	Session.saved_name = str(p.get("name", login_name.text.strip_edges()))
	Session.save_config()
	for e: LineEdit in [login_pass, reg_name, reg_email, reg_pass, reg_pass2]:
		e.text = ""
	login_name.text = Session.saved_name
	refresh_account()
	_msg(account_msg, "%s: %s. Progres game akan disinkronkan ke server." % [what, Session.saved_name], OK_COL)
	# Progres yang tersimpan saat belum masuk langsung dikirim ke server.
	if GameManager.has_method("_flush_sync"):
		GameManager._flush_sync.call_deferred()


func do_logout() -> void:
	if _acc_busy:
		return
	_set_acc_busy(true, "Keluar...")
	await Api.logout()  # gagal terhubung pun tidak apa: token di HP tetap dihapus
	if not is_inside_tree():
		return
	_set_acc_busy(false, "")
	_forget_session()
	_msg(account_msg, "Kamu sudah keluar. Progres tetap tersimpan di server.", OK_COL)


func _forget_session() -> void:
	Api.token = ""
	Session.saved_name = ""
	Session.player = {}
	Session.save_config()
	account_tab = "login"
	refresh_account()


func _set_acc_busy(on: bool, text: String) -> void:
	_acc_busy = on
	for b: Button in [btn_login, btn_register, btn_logout, tab_login, tab_register]:
		b.disabled = on
	if text != "":
		_msg(account_msg, text, Color.WHITE)


# --- Papan ketik layar HP ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	var kb := DisplayServer.virtual_keyboard_get_height()
	if kb == _kb_px:
		return
	_kb_px = kb
	var view := get_viewport().get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var k := minf(win.x / view.x, win.y / view.y)
	_kb_spacer.custom_minimum_size.y = maxf(0.0, kb / k) if kb > 0 else 0.0
	_scroll_to_focus()


func _scroll_to_focus() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var f := get_viewport().gui_get_focus_owner()
	if not (f is LineEdit) or not is_inside_tree():
		return
	var limit := get_viewport().get_visible_rect().size.y - _kb_spacer.custom_minimum_size.y - KB_MARGIN
	var r := (f as Control).get_global_rect()
	if r.end.y > limit:
		_scroll.scroll_vertical += int(ceil(r.end.y - limit))
	elif r.position.y < KB_MARGIN:
		_scroll.scroll_vertical -= int(ceil(KB_MARGIN - r.position.y))


func _vbox() -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 10)
	return b


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.max_length = 128
	e.custom_minimum_size = Vector2(0, 62)
	e.add_theme_font_size_override("font_size", 24)
	e.focus_entered.connect(_scroll_to_focus)
	return e


func _show_pass(edits: Array) -> CheckBox:
	var c := CheckBox.new()
	c.text = "Tampilkan kata sandi"
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 20)
	c.toggled.connect(func(on: bool) -> void:
		for e: LineEdit in edits:
			e.secret = not on)
	return c


static func _box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(12)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


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
