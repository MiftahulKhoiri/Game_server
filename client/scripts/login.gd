extends Control
## Layar awal: atur alamat server, daftar pemain baru, atau lanjutkan.
## Seluruh antarmuka dibuat lewat kode agar mudah ditinjau di Pull Request.

const Version = preload("res://scripts/version.gd")
const Updater = preload("res://scripts/updater.gd")
const WORLD_SCENE := "res://scenes/world.tscn"

var _url_edit: LineEdit
var _name_edit: LineEdit
var _status: Label
var _btn_start: Button
var _btn_continue: Button
var _btn_update: Button
var _version_label: Label
var _update_url := ""
var _updater: Node
var _progress: ProgressBar
var _updating := false
var _open_web := false  # pasang otomatis gagal/tidak ada: tombol membuka halaman unduhan


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

	_check_version()


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
	var res: Dictionary = await _updater.run(_update_url)
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
	var player_name := _name_edit.text.strip_edges()
	if player_name.length() < 3:
		_status.text = "Isi nama dulu (minimal 3 karakter)."
		return
	_set_busy(true, "Mendaftar...")
	Api.base_url = _clean_url(_url_edit.text)
	var res: Dictionary = await Api.register(player_name)
	if not res.ok:
		_set_busy(false, str(res.error))
		_handle_upgrade_required(res)
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
		if res.status == 426:
			_set_busy(false, str(res.error))
			_handle_upgrade_required(res)
		elif res.status == 401:
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


## Server menolak versi aplikasi ini (426): kunci tombol dan tawarkan update.
func _handle_upgrade_required(res: Dictionary) -> void:
	if res.status != 426:
		return
	_update_url = str(res.data.get("update_url", _update_url))
	_require_update(str(res.error))


func _set_busy(busy: bool, message: String) -> void:
	_btn_start.disabled = busy
	_btn_continue.disabled = busy
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
