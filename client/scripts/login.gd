extends Control
## Layar awal. Dari atas ke bawah:
##   1. Alamat server + tes. Bila server terjangkau, bagian ini menciut jadi baris dengan
##      tanda centang hijau (tombol "Ubah" membukanya lagi).
##   2. Di tengah: tombol Daftar / Masuk (dan Lanjutkan / Keluar bila ada sesi tersimpan),
##      lalu isian sesuai tombol yang dipilih.
##   3. Paling bawah: info pembaruan APK. Ada versi baru -> tombol unduh dan pasang;
##      tidak ada -> hanya versi aplikasi sekarang.
## Seluruh antarmuka dibuat lewat kode agar mudah ditinjau di Pull Request.
## Kata sandi TIDAK pernah disimpan di HP; yang disimpan hanya token sesi (lihat Session).

const Version = preload("res://scripts/version.gd")
const Updater = preload("res://scripts/updater.gd")
const WORLD_SCENE := "res://scenes/world3d.tscn"
const MIN_PASSWORD := 8
const KB_MARGIN := 28.0  # jarak isian dari tepi atas papan ketik

var _scroll: ScrollContainer
var _kb_spacer: Control  # ruang kosong di dasar isi setinggi papan ketik, supaya isian bisa digulir naik
var _kb_px := 0
var _url_edit: LineEdit
var _btn_test: Button
var _server_box: VBoxContainer  # label + isian alamat + tombol tes
var _server_msg: Label
var _server_row: HBoxContainer  # ringkasan setelah server terjangkau
var _server_label: Label
var _server_ok := false
var _testing := false
var _main_box: VBoxContainer  # tombol tengah + isian; tampil setelah server terjangkau
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
var _status: Label  # pesan daftar/masuk
var _btn_start: Button
var _btn_continue: Button
var _btn_logout: Button
var _update_status: Label  # pesan pembaruan
var _btn_update: Button
var _version_label: Label
var _update_url := ""
var _updater: Node
var _progress: ProgressBar
var _updating := false
var _register_mode := false
var _open_web := false  # pasang otomatis gagal/tidak ada: tombol membuka halaman unduhan


## Lingkaran hijau bertanda centang (digambar sendiri, tidak bergantung pada huruf/font).
class CheckMark extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(56, 56)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 26.0, Color("2e9e4f"))
		draw_polyline(PackedVector2Array([c + Vector2(-12, 1), c + Vector2(-3, 11), c + Vector2(13, -10)]),
				Color.WHITE, 5.0, true)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1b2a1f")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_scroll = ScrollContainer.new()  # layar kecil / papan ketik terbuka: isi bisa digulir
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	_scroll.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title := _make_label("Game Petualang", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# --- 1. Server
	_server_box = VBoxContainer.new()
	_server_box.add_theme_constant_override("separation", 12)
	_server_box.add_child(_make_label("Alamat server", 26))
	_url_edit = _make_edit(Api.base_url, "http://192.168.x.x:8090")
	_url_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_url_edit.text_submitted.connect(func(_t: String) -> void:
		_url_edit.release_focus()
		_test_server())
	_server_box.add_child(_url_edit)
	_btn_test = _make_button("Tes server")
	_btn_test.pressed.connect(_test_server)
	_server_box.add_child(_btn_test)
	box.add_child(_server_box)

	_server_msg = _make_label("", 24)
	_server_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_server_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_server_msg)

	_server_row = HBoxContainer.new()
	_server_row.add_theme_constant_override("separation", 16)
	_server_row.visible = false
	_server_row.add_child(CheckMark.new())
	_server_label = _make_label("", 24)
	_server_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_server_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_server_row.add_child(_server_label)
	var btn_change := _make_button("Ubah")
	btn_change.custom_minimum_size = Vector2(140, 70)
	btn_change.add_theme_font_size_override("font_size", 26)
	btn_change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_change.pressed.connect(_on_change_server)
	_server_row.add_child(btn_change)
	box.add_child(_server_row)

	# --- 2. Tengah: Daftar / Masuk
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 18)
	_main_box.visible = false
	box.add_child(_main_box)

	_btn_continue = _make_button("Lanjutkan petualangan")
	_btn_continue.pressed.connect(_on_continue)
	_btn_continue.visible = Api.token != ""
	if Session.saved_name != "":
		_btn_continue.text = "Lanjutkan sebagai %s" % Session.saved_name
	_main_box.add_child(_btn_continue)

	_btn_logout = _make_button("Keluar dari akun ini")
	_btn_logout.pressed.connect(_on_logout)
	_btn_logout.visible = Api.token != ""
	_main_box.add_child(_btn_logout)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	_tab_register = _make_button("Daftar")
	_tab_login = _make_button("Masuk")
	_tab_register.toggle_mode = true
	_tab_login.toggle_mode = true
	_tab_register.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_register.pressed.connect(func() -> void: _set_mode(true))
	_tab_login.pressed.connect(func() -> void: _set_mode(false))
	tabs.add_child(_tab_register)
	tabs.add_child(_tab_login)
	_main_box.add_child(tabs)

	# Mode masuk
	_login_box = VBoxContainer.new()
	_login_box.add_child(_make_label("Nama atau email", 26))
	_login_edit = _make_edit(Session.saved_name, "Nama atau email")
	_login_edit.max_length = 254
	_login_box.add_child(_login_edit)
	_main_box.add_child(_login_box)

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
	_main_box.add_child(_register_box)

	_main_box.add_child(_make_label("Kata sandi (minimal %d karakter)" % MIN_PASSWORD, 26))
	_pass_edit = _make_edit("", "Kata sandi")
	_pass_edit.secret = true
	_pass_edit.max_length = 128
	_main_box.add_child(_pass_edit)

	_pass2_box = VBoxContainer.new()
	_pass2_box.add_child(_make_label("Ulangi kata sandi", 26))
	_pass2_edit = _make_edit("", "Ulangi kata sandi")
	_pass2_edit.secret = true
	_pass2_edit.max_length = 128
	_pass2_box.add_child(_pass2_edit)
	_main_box.add_child(_pass2_box)

	_show_pass = CheckBox.new()
	_show_pass.text = "Tampilkan kata sandi"
	_show_pass.add_theme_font_size_override("font_size", 26)
	_show_pass.toggled.connect(func(on: bool) -> void:
		_pass_edit.secret = not on
		_pass2_edit.secret = not on)
	_main_box.add_child(_show_pass)

	_btn_start = _make_button("Masuk")
	_btn_start.pressed.connect(_on_start)
	_main_box.add_child(_btn_start)

	_status = _make_label("", 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_box.add_child(_status)

	# Tombol "Enter" di papan ketik: pindah ke isian berikutnya; di isian terakhir = kirim.
	_name_edit.text_submitted.connect(func(_t: String) -> void: _email_edit.grab_focus())
	_email_edit.text_submitted.connect(func(_t: String) -> void: _pass_edit.grab_focus())
	_login_edit.text_submitted.connect(func(_t: String) -> void: _pass_edit.grab_focus())
	_pass_edit.text_submitted.connect(func(_t: String) -> void:
		if _register_mode:
			_pass2_edit.grab_focus()
		else:
			_pass_edit.release_focus()
			_on_start())
	_pass2_edit.text_submitted.connect(func(_t: String) -> void:
		_pass2_edit.release_focus()
		_on_start())
	for e: LineEdit in [_url_edit, _login_edit, _name_edit, _email_edit, _pass_edit, _pass2_edit]:
		e.focus_entered.connect(_scroll_to_focus)

	# Pendorong: info pembaruan selalu menempel di dasar layar.
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)

	# --- 3. Bawah: info pembaruan APK
	var update_box := VBoxContainer.new()
	update_box.add_theme_constant_override("separation", 12)
	box.add_child(update_box)

	_update_status = _make_label("", 24)
	_update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_status.visible = false
	update_box.add_child(_update_status)

	_btn_update = _make_button("Unduh dan pasang pembaruan")
	_btn_update.visible = false
	_btn_update.pressed.connect(_on_update)
	update_box.add_child(_btn_update)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 28)
	_progress.visible = false
	update_box.add_child(_progress)

	_updater = Updater.new()
	add_child(_updater)
	_updater.status.connect(func(text: String) -> void: _show_update_msg(text, Color.WHITE))
	_updater.progress.connect(_on_update_progress)
	Updater.cleanup()  # sisa unduhan dari pembaruan sebelumnya

	_version_label = _make_label("Aplikasi " + Version.app_label(), 22)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_label.modulate = Color(1, 1, 1, 0.65)
	update_box.add_child(_version_label)

	_kb_spacer = Control.new()  # tinggi disesuaikan dengan papan ketik (lihat _process)
	box.add_child(_kb_spacer)

	# Baru pertama dipakai (belum ada akun di HP): tampilkan Daftar; selain itu Masuk.
	_set_mode(Session.saved_name == "" and Api.token == "")
	_test_server()


# --- Papan ketik -------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return  # komputer / uji otomatis: tanpa papan ketik layar
	var kb := DisplayServer.virtual_keyboard_get_height()
	if kb == _kb_px:
		return
	_kb_px = kb
	_kb_spacer.custom_minimum_size.y = _keyboard_overlap(kb)
	_scroll_to_focus()


## Tinggi papan ketik (piksel layar) -> tinggi yang menutupi area permainan (satuan viewport).
## Layar yang lebih tinggi dari 9:16 punya pita hitam di atas/bawah; pita itu tidak ikut dihitung.
func _keyboard_overlap(kb_px: int) -> float:
	if kb_px <= 0:
		return 0.0
	var win := Vector2(DisplayServer.window_get_size())
	var view := get_viewport().get_visible_rect().size
	var k := minf(win.x / view.x, win.y / view.y)
	var bar := (win.y - view.y * k) / 2.0
	return maxf(0.0, (float(kb_px) - bar) / k)


## Gulirkan isi supaya isian yang sedang diketik berada di atas papan ketik.
func _scroll_to_focus() -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # tunggu tata letak (ruang papan ketik) selesai dihitung
	var f := get_viewport().gui_get_focus_owner()
	if not (f is LineEdit) or not is_inside_tree():
		return
	var view_h := get_viewport().get_visible_rect().size.y
	var limit := view_h - _kb_spacer.custom_minimum_size.y - KB_MARGIN
	var r := (f as Control).get_global_rect()
	if r.end.y > limit:
		_scroll.scroll_vertical += int(ceil(r.end.y - limit))
	elif r.position.y < KB_MARGIN:
		_scroll.scroll_vertical -= int(ceil(KB_MARGIN - r.position.y))


# --- Server ------------------------------------------------------------------------------

## Tes server: bila terjangkau, bagian alamat menciut dengan tanda centang hijau, layar
## Daftar/Masuk muncul, dan info pembaruan diperbarui. Bila gagal, alamat tetap terbuka.
func _test_server() -> void:
	if _testing:
		return
	_testing = true
	Api.base_url = _clean_url(_url_edit.text)
	_url_edit.text = Api.base_url
	_btn_test.disabled = true
	_server_msg.visible = true
	_server_msg.text = "Mengecek server..."
	_server_msg.modulate = Color.WHITE
	var res: Dictionary = await Api.version_info()
	_testing = false
	_btn_test.disabled = false
	if not res.ok:
		_set_server_ok(false)
		_server_msg.text = "Server tidak terjangkau: %s" % str(res.error)
		_server_msg.modulate = Color("ff6b6b")
		return
	var info: Dictionary = res.data
	Session.save_config()  # alamat yang terbukti benar dipakai lagi lain kali
	_server_label.text = "Server tersambung\n%s  |  v%s" % [Api.base_url, str(info.get("server", "?"))]
	_set_server_ok(true)
	_apply_version_info(info)


func _set_server_ok(ok: bool) -> void:
	_server_ok = ok
	_server_box.visible = not ok
	_server_msg.visible = not ok
	_server_row.visible = ok
	_main_box.visible = ok


func _on_change_server() -> void:
	_set_server_ok(false)
	_server_msg.text = ""
	_url_edit.grab_focus()


# --- Pembaruan ---------------------------------------------------------------------------

## Bandingkan versi aplikasi dengan jawaban server: ajak update bila ada versi baru dan kunci
## tombol bila versi aplikasi di bawah batas minimum. Tanpa pembaruan, hanya versi yang tampil.
func _apply_version_info(info: Dictionary) -> void:
	_update_url = str(info.get("update_url", ""))
	var mine := Version.app_version()
	var min_client := str(info.get("min_client", "0.0.0"))
	var latest := str(info.get("latest_client", "0.0.0"))
	_btn_start.disabled = false
	_btn_continue.disabled = false
	_btn_logout.disabled = false
	if Version.compare(mine, min_client) < 0:
		_require_update("Aplikasimu v%s terlalu lama. Wajib update ke v%s atau lebih baru." % [mine, latest])
	elif Version.compare(mine, latest) < 0:
		_show_update_msg("Versi baru tersedia: v%s (kamu v%s)." % [latest, mine], Color("f0d040"))
		_btn_update.text = "Unduh dan pasang v%s" % latest
		_btn_update.visible = _update_url != ""
	else:
		_update_status.visible = false
		_btn_update.visible = false


func _show_update_msg(text: String, color: Color) -> void:
	_update_status.text = text
	_update_status.modulate = color
	_update_status.visible = text != ""


func _require_update(message: String) -> void:
	_show_update_msg(message, Color("ff6b6b"))
	_status.text = "Update aplikasi dulu (lihat bagian bawah)."
	_status.modulate = Color("ff6b6b")
	_btn_start.disabled = true
	_btn_continue.disabled = true
	_btn_logout.disabled = true
	_btn_update.text = "Unduh dan pasang update"
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
	var res_v: Variant = await _updater.run(_update_url)
	var res: Dictionary = res_v if res_v is Dictionary else {
		"ok": false, "web": true,
		"message": "Pembaruan terhenti di langkah \"%s\"." % _updater._step,
	}
	_updating = false
	_btn_update.disabled = false
	_progress.visible = false
	_show_update_msg(str(res.message), Color("8fe388") if res.ok else Color("ff6b6b"))
	if res.get("web", false):
		_open_web = true
		_btn_update.text = "Buka halaman unduhan"


func _on_update_progress(received: int, total: int) -> void:
	if total > 0:
		_progress.value = 100.0 * received / total
		_show_update_msg("Mengunduh... %.1f / %.1f MB" % [received / 1048576.0, total / 1048576.0], Color.WHITE)


# --- Daftar / Masuk ----------------------------------------------------------------------

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
