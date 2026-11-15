extends Control
## Launcher: halaman utama aplikasi. Menampilkan semua game (bawaan + katalog server + terpasang) dengan
## status, dan tombol MAINKAN / DOWNLOAD / UPDATE / BATAL / HAPUS. Bekerja penuh tanpa internet:
## game bawaan dan game terpasang tetap bisa dimainkan; katalog terakhir yang sah tetap tampil.
## Antarmuka dibangun lewat kode, sama seperti layar lain di proyek ini.

const GameRegistry := preload("res://core/game_registry.gd")
const State := GameRegistry.State

const BG := Color("141a24")
const PANEL := Color("1f2836")
const CARD := Color("263142")
const CARD_SEL := Color("33507a")
const ACCENT := Color("f0b429")
const OK_COL := Color("5ccf7a")
const ERR_COL := Color("ff7b6b")
const DIM := Color(1, 1, 1, 0.65)

const STATE_TEXT := {
	State.NOT_INSTALLED: "Belum terpasang",
	State.DOWNLOADING: "Mengunduh…",
	State.VERIFYING: "Memverifikasi…",
	State.INSTALLING: "Memasang…",
	State.INSTALLED: "Siap dimainkan",
	State.UPDATE_AVAILABLE: "Ada pembaruan",
	State.ERROR: "Gagal",
	State.DISABLED: "Tidak tersedia",
}

var _selected := ""
var _cards: Dictionary = {}       # id -> PanelContainer
var _progress: Dictionary = {}    # id -> [received, total]
var _grid: GridContainer
var _net_label: Label
var _refresh_btn: Button
var _msg: Label
var _d_cover: TextureRect
var _d_cover_bg: ColorRect
var _d_initials: Label
var _d_name: Label
var _d_meta: Label
var _d_state: Label
var _d_desc: Label
var _d_reason: Label
var _d_bar: ProgressBar
var _d_bar_label: Label
var _b_play: Button
var _b_download: Button
var _b_update: Button
var _b_cancel: Button
var _b_delete: Button
var _confirm: ConfirmationDialog


func _ready() -> void:
	var patcher = get_node_or_null("/root/Patcher")
	if patcher != null:
		patcher.confirm.call_deferred()  # patch (bila ada) berhasil sampai layar pertama
	get_tree().quit_on_go_back = true
	_build()
	GameManager.games_changed.connect(_reload)
	GameManager.download_progress.connect(_on_progress)
	GameManager.notice.connect(_on_notice)
	GameManager.online_changed.connect(func(_v: bool) -> void: _update_net())
	GameManager.exit_to_launcher.call_deferred(false)  # pastikan tidak ada game aktif / musik game
	_selected = GameManager.last_played()
	_reload()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 18)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# Kepala: judul, status koneksi, tombol muat ulang katalog.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var title := _label("Game Platform", 40)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_color_override("font_color", ACCENT)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_net_label = _label("", 20)
	_net_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_net_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_net_label)
	_refresh_btn = _button("Muat ulang katalog", 22)
	_refresh_btn.pressed.connect(_refresh)
	head.add_child(_refresh_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	# Kiri: daftar game.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.15
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 1  # satu kolom: nama game panjang tetap terbaca di layar HP
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)

	# Kanan: rincian game terpilih.
	var detail := PanelContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_stylebox_override("panel", _box(PANEL, 18))
	body.add_child(detail)
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(dscroll)
	var d := VBoxContainer.new()
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.add_theme_constant_override("separation", 8)
	dscroll.add_child(d)

	var cover_holder := Control.new()
	cover_holder.custom_minimum_size = Vector2(0, 170)
	cover_holder.clip_contents = true
	d.add_child(cover_holder)
	_d_cover_bg = ColorRect.new()
	cover_holder.add_child(_d_cover_bg)
	_d_cover_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_d_initials = _label("", 64)
	_d_initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_d_initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cover_holder.add_child(_d_initials)
	_d_initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_d_cover = TextureRect.new()
	_d_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_holder.add_child(_d_cover)
	_d_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_d_name = _label("", 32)
	d.add_child(_d_name)
	_d_meta = _label("", 18)
	_d_meta.modulate = DIM
	d.add_child(_d_meta)
	_d_state = _label("", 22)
	d.add_child(_d_state)
	_d_bar = ProgressBar.new()
	_d_bar.custom_minimum_size = Vector2(0, 22)
	_d_bar.show_percentage = false
	d.add_child(_d_bar)
	_d_bar_label = _label("", 18)
	d.add_child(_d_bar_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	d.add_child(buttons)
	_b_play = _button("MAINKAN", 26)
	_b_download = _button("DOWNLOAD", 24)
	_b_update = _button("UPDATE", 24)
	_b_cancel = _button("BATAL", 22)
	_b_delete = _button("HAPUS", 22)
	for b: Button in [_b_play, _b_download, _b_update, _b_cancel, _b_delete]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 62)
		buttons.add_child(b)
	_b_play.add_theme_stylebox_override("normal", _box(Color("2f7d46"), 12))
	_b_play.pressed.connect(func() -> void: GameManager.play(_selected))
	_b_download.pressed.connect(func() -> void: GameManager.install(_selected))
	_b_update.pressed.connect(func() -> void: GameManager.install(_selected))
	_b_cancel.pressed.connect(func() -> void: GameManager.cancel(_selected))
	_b_delete.pressed.connect(_ask_delete)

	_d_reason = _label("", 18)
	_d_reason.add_theme_color_override("font_color", ERR_COL)
	d.add_child(_d_reason)
	_d_desc = _label("", 20)
	d.add_child(_d_desc)

	_msg = _label("", 18)
	_msg.autowrap_mode = TextServer.AUTOWRAP_OFF
	_msg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_msg)

	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = "Hapus"
	_confirm.cancel_button_text = "Batal"
	_confirm.confirmed.connect(func() -> void: GameManager.uninstall(_selected))
	add_child(_confirm)


func _refresh() -> void:
	_refresh_btn.disabled = true
	_refresh_btn.text = "Memeriksa…"
	await GameManager.refresh_catalog()
	if is_inside_tree():
		_refresh_btn.disabled = false
		_refresh_btn.text = "Muat ulang katalog"
		_update_net()


func _update_net() -> void:
	var gen := str(GameManager.registry.catalog_meta.get("generated", ""))
	if GameManager.online:
		_net_label.text = "● Server tersambung"
		_net_label.add_theme_color_override("font_color", OK_COL)
	else:
		_net_label.text = "● Offline" + ("  (katalog %s)" % gen.substr(0, 10) if gen != "" else "")
		_net_label.add_theme_color_override("font_color", ERR_COL)


func _reload() -> void:
	var list := GameManager.games()
	var ids: Array = []
	for e: Dictionary in list:
		ids.append(e.id)
	for id in _cards.keys():
		if not ids.has(id):
			_cards[id].queue_free()
			_cards.erase(id)
	for e: Dictionary in list:
		if not _cards.has(e.id):
			_cards[e.id] = _make_card(e)
			_grid.add_child(_cards[e.id])
		_fill_card(_cards[e.id], e)
	if _selected == "" or not ids.has(_selected):
		_selected = ids[0] if not ids.is_empty() else ""
	_highlight()
	_show_detail()
	_update_net()


func _make_card(e: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 118)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(92, 92)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_box)
	var tile := ColorRect.new()
	tile.name = "Tile"
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(tile)
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ini := _label("", 34)
	ini.name = "Initials"
	ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_box.add_child(ini)
	ini.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	for n in ["Name", "Category", "State"]:
		var l := _label("", 24 if n == "Name" else 18)
		l.name = n
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(l)
	var id := str(e.id)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
				or (ev is InputEventScreenTouch and ev.pressed):
			_select(id))
	return card


func _fill_card(card: PanelContainer, e: Dictionary) -> void:
	var m: Dictionary = e.manifest
	var tile := card.find_child("Tile", true, false) as ColorRect
	tile.color = _game_color(m)
	(card.find_child("Initials", true, false) as Label).text = _initials(str(m.get("name", e.id)))
	var tex := _texture(str(m.get("icon", "")))
	(card.find_child("Icon", true, false) as TextureRect).texture = tex
	(card.find_child("Name", true, false) as Label).text = str(m.get("name", e.id))
	(card.find_child("Category", true, false) as Label).text = "%s · %s" % [str(m.get("category", "Game")),
		"Bawaan" if e.type == "builtin" else "Unduhan"]
	(card.find_child("Category", true, false) as Label).modulate = DIM
	var st := card.find_child("State", true, false) as Label
	st.text = _state_text(e)
	st.add_theme_color_override("font_color", _state_color(e.state))


func _select(id: String) -> void:
	_selected = id
	_highlight()
	_show_detail()


func _highlight() -> void:
	for id in _cards:
		(_cards[id] as PanelContainer).add_theme_stylebox_override("panel", _box(CARD_SEL if id == _selected else CARD, 14))


func _show_detail() -> void:
	if _selected == "":
		_d_name.text = "Belum ada game"
		for b: Button in [_b_play, _b_download, _b_update, _b_cancel, _b_delete]:
			b.visible = false
		return
	var e := GameManager.game(_selected)
	var m: Dictionary = e.manifest
	_d_name.text = str(m.get("name", e.id))
	var meta: PackedStringArray = [str(m.get("category", "Game")), "Bawaan APK" if e.type == "builtin" else "Game unduhan"]
	if e.installed_version != "":
		meta.append("Terpasang v" + e.installed_version)
	if e.latest_version != "" and e.latest_version != e.installed_version:
		meta.append("Terbaru v" + e.latest_version)
	if e.type == "download" and int(m.get("size", 0)) > 0:
		meta.append("Ukuran %.1f MB" % (int(m.size) / 1048576.0))
	_d_meta.text = "  ·  ".join(meta)
	_d_state.text = "Status: " + _state_text(e)
	_d_state.add_theme_color_override("font_color", _state_color(e.state))
	_d_desc.text = str(m.get("description", ""))
	var note := GameManager.restart_note(e.id)
	_d_reason.text = e.reason if e.reason != "" else note
	_d_reason.visible = _d_reason.text != ""
	_d_cover_bg.color = _game_color(m).darkened(0.2)
	_d_initials.text = _initials(str(m.get("name", e.id)))
	_d_cover.texture = _texture(str(m.get("cover", m.get("icon", ""))))

	var busy: bool = e.state in [State.DOWNLOADING, State.VERIFYING, State.INSTALLING]
	_b_play.visible = e.state in [State.INSTALLED, State.UPDATE_AVAILABLE]
	_b_download.visible = e.type == "download" and e.state in [State.NOT_INSTALLED, State.ERROR] \
		and e.installed_version == "" and GameManager.registry.catalog.has(e.id)
	_b_update.visible = e.state == State.UPDATE_AVAILABLE or (e.state == State.ERROR and e.installed_version != "" \
		and GameManager.registry.catalog.has(e.id))
	_b_cancel.visible = e.state == State.DOWNLOADING and GameManager.download_active(e.id)
	_b_delete.visible = e.type == "download" and not busy and GameManager.registry.installed.has(e.id)
	for b: Button in [_b_download, _b_update]:
		b.disabled = not GameManager.online
		b.tooltip_text = "" if GameManager.online else "Butuh koneksi ke server"
	_d_bar.visible = busy
	_d_bar_label.visible = busy
	if busy:
		var p: Array = _progress.get(e.id, [0, int(m.get("size", 0))])
		_d_bar.max_value = maxf(1.0, float(p[1]))
		_d_bar.value = float(p[0])
		if e.state == State.DOWNLOADING:
			_d_bar_label.text = "%.1f / %.1f MB" % [p[0] / 1048576.0, p[1] / 1048576.0]
		else:
			_d_bar_label.text = STATE_TEXT[e.state]


func _on_progress(id: String, received: int, total: int) -> void:
	_progress[id] = [received, total]
	if _cards.has(id):
		var st := _cards[id].find_child("State", true, false) as Label
		st.text = "Mengunduh %d%%" % int(100.0 * received / maxf(1.0, total))
	if id == _selected:
		_d_bar.max_value = maxf(1.0, float(total))
		_d_bar.value = float(received)
		_d_bar_label.text = "%.1f / %.1f MB" % [received / 1048576.0, total / 1048576.0]


func _on_notice(text: String, is_error: bool) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", ERR_COL if is_error else OK_COL)


func _ask_delete() -> void:
	var e := GameManager.game(_selected)
	_confirm.dialog_text = "Hapus %s dari HP?\nProgres belajar tetap tersimpan dan dipakai lagi bila game diunduh ulang." % str(e.manifest.get("name", e.id))
	_confirm.popup_centered(Vector2i(640, 220))


func _state_text(e: Dictionary) -> String:
	var t: String = STATE_TEXT[e.state]
	if e.state == State.INSTALLED and e.installed_version != "":
		t += " · v" + str(e.installed_version)
	elif e.state == State.UPDATE_AVAILABLE:
		t += " · v%s → v%s" % [e.installed_version, e.latest_version]
	return t


func _state_color(s: int) -> Color:
	match s:
		State.INSTALLED:
			return OK_COL
		State.UPDATE_AVAILABLE, State.DOWNLOADING, State.VERIFYING, State.INSTALLING:
			return ACCENT
		State.ERROR:
			return ERR_COL
	return DIM


func _game_color(m: Dictionary) -> Color:
	var c := str(m.get("icon_color", ""))
	return Color.from_string(c, Color("3a4b63")) if c != "" else Color("3a4b63")


static func _initials(name: String) -> String:
	var words := name.split(" ", false)
	# "Game Pembelajaran SD" -> "SD": singkatan di akhir nama lebih jelas daripada huruf depan.
	if words.size() > 1 and words[-1].length() <= 4 and words[-1] == words[-1].to_upper():
		return words[-1]
	var out := ""
	for w in name.split(" ", false):
		if out.length() < 2 and w.length() > 0 and w[0] != "(":
			out += w[0].to_upper()
	return out


## Tekstur dari res:// (hanya aset di dalam aplikasi atau paket game yang sudah dimuat).
static func _texture(path: String) -> Texture2D:
	if path == "" or not path.begins_with("res://") or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func _box(c: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s
