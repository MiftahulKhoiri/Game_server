extends Control
## Layar awal: atur alamat server, daftar akun baru, masuk ke akun, atau lanjutkan.
## Seluruh antarmuka dibuat lewat kode agar mudah ditinjau di Pull Request.
## Kata sandi TIDAK pernah disimpan di HP; yang disimpan hanya token sesi (lihat Session).

const Version = preload("res://scripts/version.gd")
const Updater = preload("res://scripts/updater.gd")
const WORLD_SCENE := "res://scenes/world3d.tscn"
const MIN_PASSWORD := 8

var _url_edit: LineEdit
var _login_edit: LineEdit  # mode masuk: nama atau email
var _name_edit: LineEdit  # mode daftar
var _email_edit: LineEdit  # mode daftar
var _pass_edit: LineEdit
var _pass2_edit: LineEdit  # mode daftar: ulangi kata sandi
var _login_box: VBoxContainer
var _register_box: VBoxContainer
var _pass2_box: VBoxContainer
var _tab_login: Button
var _tab_register: Button
var _show_pass: CheckBox
var _status: Label
var _btn_start: Button
var _btn_continue: Button
var _btn_logout: Button
var _btn_update: Button
var _version_label: Label
var _update_url := ""
var _updater: Node
var _progress: ProgressBar
var _updating := false
var _register_mode := false
var _open_web := false  # pasang otomatis gagal/tidak ada: tombol membuka halaman unduhan


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1b2a1f")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var scroll := ScrollContainer.new()  # layar kecil / papan ketik terbuka: isi bisa digulir
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	scroll.add_child(margin)

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

	_btn_continue = _make_button("Lanjutkan petualangan")
	_btn_continue.pressed.connect(_on_continue)
	_btn_continue.visible = Api.token != ""
	if Session.saved_name != "":
		_btn_continue.text = "Lanjutkan sebagai %s" % Session.saved_name
	box.add_child(_btn_continue)

	_btn_logout = _make_button("Keluar dari akun ini")
	_btn_logout.pressed.connect(_on_logout)
	_btn_logout.visible = Api.token != ""
	box.add_child(_btn_logout)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	_tab_login = _make_button("Masuk")
	_tab_register = _make_button("Daftar")
	_tab_login.toggle_mode = true
	_tab_register.toggle_mode = true
	_tab_login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_register.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_login.pressed.connect(func() -> void: _set_mode(false))
	_tab_register.pressed.connect(func() -> void: _set_mode(true))
	tabs.add_child(_tab_login)
	tabs.add_child(_tab_register)
	box.add_child(tabs)

	# Mode masuk
	_login_box = VBoxContainer.new()
	_login_box.add_child(_make_label("Nama atau email", 26))
	_login_edit = _make_edit(Session.saved_name, "Nama atau email")
	_login_edit.max_length = 254
	_login_box.add_child(_login_edit)
	box.add_child(_login_box)

	# Mode daftar
	_register_box = VBoxContainer.new()
	_register_box.add_child(_make_label("Nama petualang (3-20 huruf/angka/_)", 26))
	_name_edit = _make_edit("", "Nama baru")
	_name_edit.max_length = 20
	_register_box.add_child(_name_edit)
	_register_box.add_child(_make_label("Email (untuk akunmu)", 26))
	_email_edit = _make_edit("", "nama@contoh.com")
	_email_edit.max_length = 254
	_email_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_register_box.add_child(_email_edit)
	box.add_child(_register_box)

	box.add_child(_make_label("Kata sandi (minimal %d karakter)" % MIN_PASSWORD, 26))
	_pass_edit = _make_edit("", "Kata sandi")
	_pass_edit.secret = true
	_pass_edit.max_length = 128
	box.add_child(_pass_edit)

	_pass2_box = VBoxContainer.new()
	_pass2_box.add_child(_make_label("Ulangi kata sandi", 26))
	_pass2_edit = _make_edit("", "Ulangi kata sandi")
	_pass2_edit.secret = true
	_pass2_edit.max_length = 128
	_pass2_box.add_child(_pass2_edit)
	box.add_child(_pass2_box)

	_show_pass = CheckBox.new()
	_show_pass.text = "Tampilkan kata sandi"
	_show_pass.add_theme_font_size_override("font_size", 26)
	_show_pass.toggled.connect(func(on: bool) -> void:
		_pass_edit.secret = not on
		_pass2_edit.secret = not on)
	box.add_child(_show_pass)

	_btn_start = _make_button("Masuk")
	_btn_start.pressed.connect(_on_start)
	box.add_child(_btn_start)

	_status = _make_label("", 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_btn_update = _make_button("Buka halaman unduhan")
	_btn_update.visible = false
	_btn_update.pressed.connect(_on_update)
	box.add_child(_btn_update)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 28)
	_progress.visible = false
	box.add_child(_progress)

	_updater = Updater.new()
	add_child(_updater)
	_updater.status.connect(func(text: String) -> void: _status.text = text)
	_updater.progress.connect(_on_update_progress)
	Updater.cleanup()  # sisa unduhan dari pembaruan sebelumnya

	_version_label = _make_label("Aplikasi " + Version.app_label(), 20)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_version_label)

	# Baru pertama dipakai (belum ada akun di HP): tampilkan Daftar; selain itu Masuk.
	_set_mode(Session.saved_name == "" and Api.token == "")
	_check_version()


## Ganti antara layar Masuk dan Daftar. Isian kata sandi dikosongkan agar tidak terbawa.
func _set_mode(register: bool) -> void:
	_register_mode = register
	_tab_login.button_pressed = not register
	_tab_register.button_pressed = register
	_login_box.visible = not register
	_register_box.visible = register
	_pass2_box.visible = register
	_btn_start.text = "Daftar dan mulai" if register else "Masuk"
	_pass_edit.text = ""
	_pass2_edit.text = ""
	_status.text = ""
	_status.modulate = Color.WHITE


## Menanyakan versi ke server: tampilkan versi server, ajak update bila ada versi
## baru, dan kunci tombol bila versi aplikasi di bawah batas minimum.
func _check_version() -> void:
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.version_info()
	if not res.ok:
		return  # server belum terjangkau; kesalahan akan terlihat saat masuk
	var info: Dictionary = res.data
	_version_label.text = "Aplikasi %s  |  Server v%s" % [Version.app_label(), str(info.get("server", "?"))]
	_update_url = str(info.get("update_url", ""))

	var mine := Version.app_version()
	var min_client := str(info.get("min_client", "0.0.0"))
	var latest := str(info.get("latest_client", "0.0.0"))
	if Version.compare(mine, min_client) < 0:
		_require_update("Aplikasimu v%s terlalu lama. Wajib update ke v%s atau lebih baru." % [mine, latest])
	elif Version.compare(mine, latest) < 0:
		_status.text = "Versi baru tersedia: v%s (kamu v%s)." % [latest, mine]
		_status.modulate = Color("f0d040")
		_btn_update.text = "Unduh versi baru"
		_btn_update.visible = _update_url != ""


func _require_update(message: String) -> void:
	_status.text = message
	_status.modulate = Color("ff6b6b")
	_btn_start.disabled = true
	_btn_continue.disabled = true
	_btn_logout.disabled = true
	_btn_update.text = "Update sekarang"
	_btn_update.visible = _update_url != ""


## Tombol update: unduh dan pasang langsung di dalam aplikasi. Bila tidak bisa
## (bukan Android / ada langkah gagal), tombol berubah menjadi pembuka halaman unduhan.
func _on_update() -> void:
	if _updating or _update_url == "":
		return
	if _open_web or not Updater.supported():
		OS.shell_open(_update_url)
		return
	_updating = true
	_btn_update.disabled = true
	_progress.value = 0
	_progress.visible = true
	_status.modulate = Color.WHITE
	var res_v: Variant = await _updater.run(_update_url)
	var res: Dictionary = res_v if res_v is Dictionary else {
		"ok": false, "web": true,
		"message": "Pembaruan terhenti di langkah \"%s\"." % _updater._step,
	}
	_updating = false
	_btn_update.disabled = false
	_progress.visible = false
	_status.text = str(res.message)
	_status.modulate = Color("8fe388") if res.ok else Color("ff6b6b")
	if res.get("web", false):
		_open_web = true
		_btn_update.text = "Buka halaman unduhan"


func _on_update_progress(received: int, total: int) -> void:
	if total > 0:
		_progress.value = 100.0 * received / total
		_status.text = "Mengunduh... %.1f / %.1f MB" % [received / 1048576.0, total / 1048576.0]


func _on_start() -> void:
	if _register_mode:
		await _do_register()
	else:
		await _do_login()


func _do_register() -> void:
	var player_name := _name_edit.text.strip_edges()
	var email := _email_edit.text.strip_edges()
	var password := _pass_edit.text
	if player_name.length() < 3:
		_fail("Isi nama dulu (minimal 3 karakter).")
		return
	if not _looks_like_email(email):
		_fail("Isi email yang benar, mis. nama@contoh.com.")
		return
	if password.length() < MIN_PASSWORD:
		_fail("Kata sandi minimal %d karakter." % MIN_PASSWORD)
		return
	if password != _pass2_edit.text:
		_fail("Kata sandi dan ulangannya tidak sama.")
		return
	_set_busy(true, "Mendaftar...")
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.register(player_name, email, password)
	if not res.ok:
		_set_busy(false, str(res.error))
		_handle_upgrade_required(res)
		return
	_enter_world(res.data)


func _do_login() -> void:
	var login := _login_edit.text.strip_edges()
	var password := _pass_edit.text
	if login == "" or password == "":
		_fail("Isi nama (atau email) dan kata sandi.")
		return
	_set_busy(true, "Masuk...")
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.login(login, password)
	if not res.ok:
		# 401: nama/email atau kata sandi salah. 429: terlalu banyak percobaan (pesan memuat lama tunggu).
		_set_busy(false, str(res.error))
		_handle_upgrade_required(res)
		return
	_enter_world(res.data)


## Simpan sesi dari jawaban daftar/login ({"player", "token"}) lalu masuk ke dunia game.
func _enter_world(data: Dictionary) -> void:
	Api.token = str(data.token)
	Session.offline = false
	Session.set_player(data.player)
	Session.save_config()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_continue() -> void:
	_set_busy(true, "Menghubungkan...")
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.get_me()
	if not res.ok:
		if res.status == 426:
			_set_busy(false, str(res.error))
			_handle_upgrade_required(res)
		elif res.status == 401:
			_forget_session()
			_set_mode(false)
			_set_busy(false, "Sesi sudah berakhir. Masuk lagi dengan nama dan kata sandimu.")
		else:
			_set_busy(false, str(res.error))
		return
	Session.offline = false
	Session.set_player(res.data)
	Session.save_config()
	get_tree().change_scene_to_file(WORLD_SCENE)


## Keluar dari akun di HP ini: token dicabut di server (bila terjangkau) dan dihapus dari HP.
## Progress aman di server; masuk lagi dengan nama + kata sandi.
func _on_logout() -> void:
	_set_busy(true, "Keluar...")
	Api.base_url = _clean_url(_url_edit.text)
	await Api.logout()  # gagal terhubung pun tidak masalah: token lokal tetap dihapus
	_forget_session()
	_set_mode(false)
	_set_busy(false, "Kamu sudah keluar. Progress tersimpan di server.")


func _forget_session() -> void:
	Api.token = ""
	Session.saved_name = ""
	Session.player = {}
	Session.save_config()
	_btn_continue.visible = false
	_btn_logout.visible = false
	_login_edit.text = ""


func _fail(message: String) -> void:
	_status.text = message
	_status.modulate = Color("ff6b6b")


## Pemeriksaan ringan di HP (yang menentukan tetap server): ada satu @, ada titik di domain, tanpa spasi.
static func _looks_like_email(email: String) -> bool:
	var parts := email.split("@")
	return parts.size() == 2 and parts[0] != "" and parts[1].contains(".") \
			and not parts[1].begins_with(".") and not parts[1].ends_with(".") and not email.contains(" ")


## Server menolak versi aplikasi ini (426): kunci tombol dan tawarkan update.
func _handle_upgrade_required(res: Dictionary) -> void:
	if res.status != 426:
		return
	_update_url = str(res.data.get("update_url", _update_url))
	_require_update(str(res.error))


func _set_busy(busy: bool, message: String) -> void:
	_btn_start.disabled = busy
	_btn_continue.disabled = busy
	_btn_logout.disabled = busy
	_status.text = message
	_status.modulate = Color.WHITE


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
