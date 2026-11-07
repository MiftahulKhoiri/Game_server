extends Control
## Layar awal berupa beberapa halaman dalam satu adegan:
##   Beranda    : hanya tombol Masuk, Daftar, Pengaturan (+ Lanjutkan bila ada sesi tersimpan).
##   Masuk      : isian nama/email + kata sandi.
##   Daftar     : isian nama, email, kata sandi.
##   Pengaturan : alamat server (tes, menciut dengan tanda centang hijau bila terjangkau),
##                keluar dari akun, dan info pembaruan APK (unduh dan pasang bila ada versi baru).
## Seluruh antarmuka dibuat lewat kode agar mudah ditinjau di Pull Request.
## Kata sandi TIDAK pernah disimpan di HP; yang disimpan hanya token sesi (lihat Session).

const Version = preload("res://scripts/version.gd")
const Updater = preload("res://scripts/updater.gd")
const JudulLatar = preload("res://scripts/judul_latar.gd")
const WORLD_SCENE := "res://scenes/world3d.tscn"
const MIN_PASSWORD := 8
const KB_MARGIN := 28.0  # jarak isian dari tepi atas papan ketik
const GREEN := Color("8fe388")
const RED := Color("ff6b6b")
const YELLOW := Color("f0d040")

var _latar: SubViewportContainer  # diorama 3D di belakang Beranda
var _dim: ColorRect                # menggelapkan diorama di halaman selain Beranda
var _scroll: ScrollContainer
var _box: VBoxContainer
var _kb_spacer: Control  # ruang kosong di dasar isi setinggi papan ketik, supaya isian bisa digulir naik
var _kb_px := 0
var _pages := {}
var _page := "home"

# Beranda
var _btn_continue: Button
var _btn_settings: Button
var _home_status: Label

# Masuk
var _login_edit: LineEdit
var _pass_edit: LineEdit
var _btn_login: Button
var _login_status: Label

# Daftar
var _name_edit: LineEdit
var _email_edit: LineEdit
var _rpass_edit: LineEdit
var _rpass2_edit: LineEdit
var _btn_register: Button
var _register_status: Label

# Pengaturan
var _url_edit: LineEdit
var _btn_test: Button
var _server_box: VBoxContainer  # label + isian alamat + tombol tes
var _server_msg: Label
var _server_row: HBoxContainer  # ringkasan setelah server terjangkau
var _server_label: Label
var _account_box: VBoxContainer
var _btn_logout: Button
var _account_status: Label
var _update_status: Label
var _btn_update: Button
var _progress: ProgressBar
var _version_label: Label

var _server_ok := false
var _testing := false
var _update_required := false
var _update_url := ""
var _updater: Node
var _updating := false
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
	_latar = JudulLatar.new()
	add_child(_latar)
	_latar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.04, 0.08, 0.82)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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

	_box = VBoxContainer.new()
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_box)

	_build_home()
	_build_login()
	_build_register()
	_build_settings()

	_kb_spacer = Control.new()  # tinggi disesuaikan dengan papan ketik (lihat _process)
	_box.add_child(_kb_spacer)

	for e: LineEdit in [_url_edit, _login_edit, _pass_edit, _name_edit, _email_edit, _rpass_edit, _rpass2_edit]:
		e.focus_entered.connect(_scroll_to_focus)

	_updater = Updater.new()
	add_child(_updater)
	_updater.status.connect(func(text: String) -> void: _show_update_msg(text, Color.WHITE))
	_updater.progress.connect(_on_update_progress)
	Updater.cleanup()  # sisa unduhan dari pembaruan sebelumnya

	_show_page("home")
	_test_server()


func _exit_tree() -> void:
	if is_inside_tree():
		get_tree().quit_on_go_back = true


## Tombol kembali Android: dari halaman dalam kembali ke Beranda (di Beranda keluar dari aplikasi).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _page != "home":
		_show_page("home")


# --- Membangun halaman -------------------------------------------------------------------

func _new_page(id: String, title: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 18)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.visible = false
	if title != "":
		var t := _make_label(title, 46)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(t)
	_box.add_child(p)
	_pages[id] = p
	return p


func _add_back(p: VBoxContainer) -> void:
	var back := _make_button("Kembali")
	back.pressed.connect(func() -> void: _show_page("home"))
	p.add_child(back)


func _make_status() -> Label:
	var l := _make_label("", 24)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _filler() -> Control:
	var f := Control.new()
	f.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return f


func _build_home() -> void:
	var p := _new_page("home", "")
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 24)
	p.add_child(top)
	p.add_child(_title_label("PETUALANGAN", 78, 14))
	p.add_child(_ribbon("MEMBERANTAS MONSTER"))
	p.add_child(_filler())  # diorama 3D tampil di ruang ini

	_btn_continue = _make_button("Lanjutkan petualangan")
	_btn_continue.pressed.connect(_on_continue)
	_btn_continue.visible = Api.token != ""
	if Session.saved_name != "":
		_btn_continue.text = "Lanjutkan sebagai %s" % Session.saved_name
	p.add_child(_btn_continue)

	var b_login := _make_button("Masuk")
	b_login.pressed.connect(func() -> void: _open_form("login"))
	p.add_child(b_login)
	var b_reg := _make_button("Daftar")
	b_reg.pressed.connect(func() -> void: _open_form("register"))
	p.add_child(b_reg)
	_btn_settings = _make_button("Pengaturan")
	_btn_settings.pressed.connect(func() -> void: _show_page("settings"))
	p.add_child(_btn_settings)
	for b: Button in [_btn_continue, b_login, b_reg, _btn_settings]:
		_style_home_button(b)

	_home_status = _make_status()
	_home_status.add_theme_color_override("font_outline_color", Color("1a0d05"))
	_home_status.add_theme_constant_override("outline_size", 6)
	p.add_child(_home_status)


## Judul emas bertepi cokelat tua dengan bayangan, ala logo RPG.
func _title_label(text: String, size: int, outline: int) -> Label:
	var l := _make_label(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color("ffc933"))
	l.add_theme_color_override("font_outline_color", Color("4a2308"))
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 8)
	return l


## Pita merah bertepi emas berisi teks krem.
func _ribbon(text: String) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("b3202a")
	sb.border_color = Color("e8b53a")
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _make_label(text, 36)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color("fff1d0"))
	l.add_theme_color_override("font_outline_color", Color("4a0d12"))
	l.add_theme_constant_override("outline_size", 6)
	pc.add_child(l)
	return pc


## Tombol Beranda: kayu gelap berbingkai emas, supaya serasi dengan judul.
func _style_home_button(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.17, 0.09, 0.05, 0.88)
		if state == "pressed":
			sb.bg_color = Color(0.32, 0.15, 0.08, 0.95)
		elif state == "hover":
			sb.bg_color = Color(0.24, 0.12, 0.07, 0.92)
		sb.border_color = Color("e8b53a")
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(14)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color("ffe9b0"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("ffc933"))


func _build_login() -> void:
	var p := _new_page("login", "Masuk")
	p.add_child(_make_label("Nama atau email", 26))
	_login_edit = _make_edit(Session.saved_name, "Nama atau email")
	_login_edit.max_length = 254
	p.add_child(_login_edit)
	p.add_child(_make_label("Kata sandi", 26))
	_pass_edit = _make_edit("", "Kata sandi")
	_pass_edit.secret = true
	_pass_edit.max_length = 128
	p.add_child(_pass_edit)
	p.add_child(_make_show_pass([_pass_edit]))
	_btn_login = _make_button("Masuk")
	_btn_login.pressed.connect(_do_login)
	p.add_child(_btn_login)
	_login_status = _make_status()
	p.add_child(_login_status)
	p.add_child(_filler())
	_add_back(p)

	# Tombol "Enter" di papan ketik: pindah ke isian berikutnya; di isian terakhir = kirim.
	_login_edit.text_submitted.connect(func(_t: String) -> void: _pass_edit.grab_focus())
	_pass_edit.text_submitted.connect(func(_t: String) -> void:
		_pass_edit.release_focus()
		_do_login())


func _build_register() -> void:
	var p := _new_page("register", "Daftar")
	p.add_child(_make_label("Nama petualang (3-20 huruf/angka/_)", 26))
	_name_edit = _make_edit("", "Nama baru")
	_name_edit.max_length = 20
	p.add_child(_name_edit)
	p.add_child(_make_label("Email (untuk akunmu)", 26))
	_email_edit = _make_edit("", "nama@contoh.com")
	_email_edit.max_length = 254
	_email_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	p.add_child(_email_edit)
	p.add_child(_make_label("Kata sandi (minimal %d karakter)" % MIN_PASSWORD, 26))
	_rpass_edit = _make_edit("", "Kata sandi")
	_rpass_edit.secret = true
	_rpass_edit.max_length = 128
	p.add_child(_rpass_edit)
	p.add_child(_make_label("Ulangi kata sandi", 26))
	_rpass2_edit = _make_edit("", "Ulangi kata sandi")
	_rpass2_edit.secret = true
	_rpass2_edit.max_length = 128
	p.add_child(_rpass2_edit)
	p.add_child(_make_show_pass([_rpass_edit, _rpass2_edit]))
	_btn_register = _make_button("Daftar dan mulai")
	_btn_register.pressed.connect(_do_register)
	p.add_child(_btn_register)
	_register_status = _make_status()
	p.add_child(_register_status)
	p.add_child(_filler())
	_add_back(p)

	_name_edit.text_submitted.connect(func(_t: String) -> void: _email_edit.grab_focus())
	_email_edit.text_submitted.connect(func(_t: String) -> void: _rpass_edit.grab_focus())
	_rpass_edit.text_submitted.connect(func(_t: String) -> void: _rpass2_edit.grab_focus())
	_rpass2_edit.text_submitted.connect(func(_t: String) -> void:
		_rpass2_edit.release_focus()
		_do_register())


func _build_settings() -> void:
	var p := _new_page("settings", "Pengaturan")

	# Server
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
	p.add_child(_server_box)

	_server_msg = _make_status()
	p.add_child(_server_msg)

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
	p.add_child(_server_row)

	# Akun (hanya bila ada sesi tersimpan di HP ini)
	_account_box = VBoxContainer.new()
	_account_box.add_theme_constant_override("separation", 12)
	_account_box.visible = Api.token != ""
	_btn_logout = _make_button("Keluar dari akun ini")
	_btn_logout.pressed.connect(_on_logout)
	_account_box.add_child(_btn_logout)
	_account_status = _make_status()
	_account_box.add_child(_account_status)
	p.add_child(_account_box)

	p.add_child(_filler())

	# Pembaruan APK (paling bawah)
	var update_box := VBoxContainer.new()
	update_box.add_theme_constant_override("separation", 12)
	p.add_child(update_box)
	_update_status = _make_status()
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
	_version_label = _make_label("Aplikasi " + Version.app_label(), 22)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_label.modulate = Color(1, 1, 1, 0.65)
	update_box.add_child(_version_label)

	_add_back(p)


# --- Halaman -----------------------------------------------------------------------------

func _show_page(id: String) -> void:
	_page = id
	if _dim != null:
		_dim.visible = id != "home"
		_latar.set_aktif(id == "home")
	for k: String in _pages:
		(_pages[k] as Control).visible = (k == id)
	_scroll.scroll_vertical = 0
	if is_inside_tree():
		get_tree().quit_on_go_back = (id == "home")
	for e: LineEdit in [_pass_edit, _rpass_edit, _rpass2_edit]:
		e.text = ""  # kata sandi tidak terbawa antar halaman
	_login_status.text = ""
	_register_status.text = ""
	_account_status.text = ""


## Masuk/Daftar hanya bisa dibuka bila server terjangkau dan aplikasi tidak kedaluwarsa.
func _open_form(id: String) -> void:
	if _gate():
		_show_page(id)


func _gate() -> bool:
	if _testing:
		_home_msg("Mengecek server... coba lagi sebentar.", Color.WHITE)
		return false
	if not _server_ok:
		_home_msg("Server belum terhubung. Buka Pengaturan untuk mengecek alamat server.", RED)
		return false
	if _update_required:
		_home_msg("Aplikasi terlalu lama. Update lewat Pengaturan.", RED)
		return false
	return true


func _home_msg(text: String, color: Color) -> void:
	_home_status.text = text
	_home_status.modulate = color


## Label pesan milik halaman yang sedang tampil.
func _cur_status() -> Label:
	match _page:
		"login":
			return _login_status
		"register":
			return _register_status
		"settings":
			return _account_status
	return _home_status


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

## Tes server (otomatis saat dibuka, atau lewat Pengaturan). Bila terjangkau, bagian alamat
## menciut dengan tanda centang hijau dan info pembaruan diperbarui. Bila gagal, alamat tetap terbuka.
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
	_home_msg("Mengecek server...", Color.WHITE)
	var res: Dictionary = await Api.version_info()
	_testing = false
	_btn_test.disabled = false
	if not res.ok:
		_set_server_ok(false)
		_server_msg.text = "Server tidak terjangkau: %s" % str(res.error)
		_server_msg.modulate = RED
		_home_msg("Server belum terhubung. Buka Pengaturan.", RED)
		return
	var info: Dictionary = res.data
	Session.save_config()  # alamat yang terbukti benar dipakai lagi lain kali
	_server_label.text = "Server tersambung\n%s  |  v%s" % [Api.base_url, str(info.get("server", "?"))]
	_set_server_ok(true)
	_home_msg("Server tersambung", GREEN)
	_apply_version_info(info)


func _set_server_ok(ok: bool) -> void:
	_server_ok = ok
	_server_box.visible = not ok
	_server_msg.visible = not ok
	_server_row.visible = ok


func _on_change_server() -> void:
	_set_server_ok(false)
	_server_msg.text = ""
	_url_edit.grab_focus()


# --- Pembaruan ---------------------------------------------------------------------------

## Bandingkan versi aplikasi dengan jawaban server: ajak update bila ada versi baru dan kunci
## Masuk/Daftar bila versi aplikasi di bawah batas minimum. Tanpa pembaruan, hanya versi yang tampil.
func _apply_version_info(info: Dictionary) -> void:
	_update_url = str(info.get("update_url", ""))
	var mine := Version.app_version()
	var min_client := str(info.get("min_client", "0.0.0"))
	var latest := str(info.get("latest_client", "0.0.0"))
	_update_required = false
	_btn_settings.text = "Pengaturan"
	if Version.compare(mine, min_client) < 0:
		_require_update("Aplikasimu v%s terlalu lama. Wajib update ke v%s atau lebih baru." % [mine, latest])
	elif Version.compare(mine, latest) < 0:
		_show_update_msg("Versi baru tersedia: v%s (kamu v%s)." % [latest, mine], YELLOW)
		_btn_update.text = "Unduh dan pasang v%s" % latest
		_btn_update.visible = _update_url != ""
		_btn_settings.text = "Pengaturan  (ada update)"
	else:
		_update_status.visible = false
		_btn_update.visible = false


func _show_update_msg(text: String, color: Color) -> void:
	_update_status.text = text
	_update_status.modulate = color
	_update_status.visible = text != ""


func _require_update(message: String) -> void:
	_update_required = true
	_show_update_msg(message, RED)
	_btn_update.text = "Unduh dan pasang update"
	_btn_update.visible = _update_url != ""
	_btn_settings.text = "Pengaturan  (WAJIB update)"
	_home_msg("Aplikasi terlalu lama. Update lewat Pengaturan.", RED)


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
	_show_update_msg(str(res.message), GREEN if res.ok else RED)
	if res.get("web", false):
		_open_web = true
		_btn_update.text = "Buka halaman unduhan"


func _on_update_progress(received: int, total: int) -> void:
	if total > 0:
		_progress.value = 100.0 * received / total
		_show_update_msg("Mengunduh... %.1f / %.1f MB" % [received / 1048576.0, total / 1048576.0], Color.WHITE)


# --- Daftar / Masuk ----------------------------------------------------------------------

func _do_register() -> void:
	var player_name := _name_edit.text.strip_edges()
	var email := _email_edit.text.strip_edges()
	var password := _rpass_edit.text
	if player_name.length() < 3:
		_fail("Isi nama dulu (minimal 3 karakter).")
		return
	if not _looks_like_email(email):
		_fail("Isi email yang benar, mis. nama@contoh.com.")
		return
	if password.length() < MIN_PASSWORD:
		_fail("Kata sandi minimal %d karakter." % MIN_PASSWORD)
		return
	if password != _rpass2_edit.text:
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
	if not _gate():
		return
	_set_busy(true, "Menghubungkan...")
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.get_me()
	if not res.ok:
		if res.status == 426:
			_set_busy(false, str(res.error))
			_handle_upgrade_required(res)
		elif res.status == 401:
			_forget_session()
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
	_show_page("home")
	_set_busy(false, "Kamu sudah keluar. Progress tersimpan di server.")


func _forget_session() -> void:
	Api.token = ""
	Session.saved_name = ""
	Session.player = {}
	Session.save_config()
	_btn_continue.visible = false
	_account_box.visible = false
	_login_edit.text = ""


func _fail(message: String) -> void:
	var s := _cur_status()
	s.text = message
	s.modulate = RED


## Pemeriksaan ringan di HP (yang menentukan tetap server): ada satu @, ada titik di domain, tanpa spasi.
static func _looks_like_email(email: String) -> bool:
	var parts := email.split("@")
	return parts.size() == 2 and parts[0] != "" and parts[1].contains(".") \
			and not parts[1].begins_with(".") and not parts[1].ends_with(".") and not email.contains(" ")


## Server menolak versi aplikasi ini (426): kunci Masuk/Daftar dan tawarkan update.
func _handle_upgrade_required(res: Dictionary) -> void:
	if res.status != 426:
		return
	_update_url = str(res.data.get("update_url", _update_url))
	_require_update(str(res.error))


func _set_busy(busy: bool, message: String) -> void:
	_btn_login.disabled = busy
	_btn_register.disabled = busy
	_btn_continue.disabled = busy
	_btn_logout.disabled = busy
	var s := _cur_status()
	s.text = message
	s.modulate = Color.WHITE


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


func _make_show_pass(edits: Array) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = "Tampilkan kata sandi"
	cb.add_theme_font_size_override("font_size", 26)
	cb.toggled.connect(func(on: bool) -> void:
		for e: LineEdit in edits:
			e.secret = not on)
	return cb


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 30)
	button.custom_minimum_size = Vector2(0, 90)
	return button
