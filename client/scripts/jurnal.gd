extends CanvasLayer
## Jurnal petualang (roadmap no. 212, 213, 216): tiga tab di Menu.
##   Misi  : semua misi dari server (GET /v1/quests): status, kemajuan, hadiah, pemberi.
##   Peta  : peta wilayah sekarang digambar dari petak (Maps.rows), posisi pemain, pintu keluar, toko,
##           dan tempat rahasia yang sudah ditemukan; daftar wilayah yang pernah dikunjungi.
##   Kabar : pemberitahuan terakhir (Session.notices): tawaran dagang, kejadian dunia, hadiah.

signal closed

const Maps = preload("res://scripts/maps.gd")
const TABS := ["Misi", "Peta", "Kabar"]
const STATUS_TEXT := {"locked": "Terkunci", "available": "Bisa diterima", "active": "Sedang dikerjakan", "done": "Selesai — ambil hadiah", "claimed": "Tuntas"}
const STATUS_COLOR := {"locked": Color("8a8a8a"), "available": Color("9fd8ff"), "active": Color("ffd27a"), "done": Color("9fe6a0"), "claimed": Color("b9b9b0")}
const GIVERS := {"nenek_penjual": "Nenek (Penjual Sayur)", "petani": "Petani", "kapten_kem": "Kapten Rimba"}
const MAP_W := 660.0
## Warna petak pada peta.
const TILE_COLOR := {
	".": Color("5fae4a"), "f": Color("6dbb55"), "=": Color("d9b97c"), "~": Color("3d7fc4"), "#": Color("2f5e2a"),
	"P": Color("6b4a2a"), "H": Color("a0523d"), "D": Color("e0a050"), "F": Color("8a6a3a"), "T": Color("86603a"),
	"R": Color("6f6a62"), "M": Color("a59a8a"), "G": Color("8d8170"), "S": Color("9a9aa3"), "B": Color("b08850"),
	"N": Color("e0a050"), "W": Color("6fa0c0"),
}

var is_open := false
var tab := 0
var quests: Array = []          # dari server (untuk uji bisa diisi langsung)
var map_texture: ImageTexture   # gambar peta terakhir (untuk uji)

var _tabs: Array[Button] = []
var _body: VBoxContainer
var _status: Label


func _init() -> void:
	layer = 11
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c2430")
	sb.border_color = Color("8fb4d8")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := _button(TABS[i], _show_tab.bind(i), 76)
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		_tabs.append(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)
	_status = _label("", 22)
	_status.add_theme_color_override("font_color", Color("ffd27a"))
	box.add_child(_status)
	box.add_child(_button("Tutup", func() -> void: closed.emit(), 84))


func open(p_tab := 0) -> void:
	visible = true
	is_open = true
	_show_tab(p_tab)
	if p_tab == 0 and not Session.offline:
		_status.text = "Memuat misi..."
		var res: Dictionary = await Api.quests_get()
		_status.text = "" if res.ok else str(res.error)
		if res.ok:
			quests = res.data.get("quests", [])
		if tab == 0:
			_show_tab(0)


func close() -> void:
	visible = false
	is_open = false


func _show_tab(i: int) -> void:
	tab = i
	for k in _tabs.size():
		_tabs[k].set_pressed_no_signal(k == i)
	if _body == null:
		return
	for c in _body.get_children():
		c.queue_free()
	match i:
		0: _build_quests()
		1: _build_map()
		2: _build_notices()


# --- Misi (no. 212) ---

func _build_quests() -> void:
	if quests.is_empty():
		_body.add_child(_label("Belum ada misi. Bicaralah dengan warga desa (Nenek, Petani) dan Kapten Rimba.", 24))
		return
	var order := ["done", "active", "available", "locked", "claimed"]
	var sorted := quests.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order.find(str(a.status)) < order.find(str(b.status)))
	for q: Dictionary in sorted:
		var st := str(q.get("status", ""))
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("26303e")
		sb.border_color = STATUS_COLOR.get(st, Color.WHITE)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(14)
		card.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		var t := _label(str(q.get("title", q.get("id", ""))), 28)
		t.add_theme_color_override("font_color", STATUS_COLOR.get(st, Color.WHITE))
		v.add_child(t)
		v.add_child(_label(STATUS_TEXT.get(st, st), 22))
		var desc := _label(str(q.get("description", "")), 22)
		v.add_child(desc)
		var count := int(q.get("target_count", 0))
		if count > 0 and (st == "active" or st == "done"):
			var bar := ProgressBar.new()
			bar.max_value = count
			bar.value = mini(int(q.get("progress", 0)), count)
			bar.custom_minimum_size = Vector2(0, 26)
			bar.show_percentage = false
			v.add_child(bar)
			v.add_child(_label("Kemajuan %d/%d" % [mini(int(q.get("progress", 0)), count), count], 20))
		var giver := str(q.get("giver", ""))
		var reward := str(q.get("reward_text", ""))
		if reward == "":
			reward = "%d emas" % int(q.get("reward_gold", 0))
		v.add_child(_label("Pemberi: %s   Hadiah: %s" % [GIVERS.get(giver, giver.capitalize()), reward], 20))
		_body.add_child(card)


# --- Peta (no. 213) ---

## Gambar peta wilayah: satu piksel per petak, lalu diperbesar tanpa dihaluskan.
func make_map_image(map_id: String, player: Vector2) -> Image:
	var rows := Maps.rows(map_id)
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, r.length())
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	for y in h:
		for x in rows[y].length():
			img.set_pixel(x, y, TILE_COLOR.get(rows[y][x], Color("5fae4a")))
	for ex: Dictionary in Maps.EXITS.get(map_id, []):
		var p: Vector2i = ex.pos
		if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h:
			img.set_pixel(p.x, p.y, Color("ffe14a"))
	var found: Array = Session.player.state.get("secrets", [])
	for s: Dictionary in Maps.RAHASIA:
		if s.map == map_id and found.has(s.id):
			img.set_pixel(s.pos.x, s.pos.y, Color("ff6fd8"))
	var px := clampi(int(player.x), 0, w - 1)
	var py := clampi(int(player.y), 0, h - 1)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var qx := px + ox
			var qy := py + oy
			if qx >= 0 and qy >= 0 and qx < w and qy < h:
				img.set_pixel(qx, qy, Color("ffffff") if (ox == 0 and oy == 0) else Color("e8302a"))
	return img


func _build_map() -> void:
	var st: Dictionary = Session.player.state
	var map_id := str(st.get("map", Maps.DEFAULT_MAP))
	var pos := Vector2(float(st.get("fx", 0.0)), float(st.get("fz", 0.0)))
	if pos == Vector2.ZERO:
		pos = Vector2(int(st.get("x", 0)), int(st.get("y", 0)))
	var head := _label(str(Maps.NAMES.get(map_id, map_id)), 32)
	head.add_theme_color_override("font_color", Color("ffe08a"))
	_body.add_child(head)
	if Maps.ZONA.has(map_id):
		var z: Array = Maps.ZONA[map_id]
		_body.add_child(_label("Wilayah %s — level disarankan %d+" % [str(z[0]), int(z[1])], 22))
	var img := make_map_image(map_id, pos)
	map_texture = ImageTexture.create_from_image(img)
	var tex := TextureRect.new()
	tex.texture = map_texture
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var aspect := float(img.get_height()) / float(maxi(1, img.get_width()))
	tex.custom_minimum_size = Vector2(MAP_W, clampf(MAP_W * aspect, 160.0, 720.0))
	_body.add_child(tex)
	_body.add_child(_label("Putih/merah = kamu   Kuning = jalan keluar   Merah muda = tempat rahasia yang ditemukan", 20))
	var exits: Array[String] = []
	for ex: Dictionary in Maps.EXITS.get(map_id, []):
		var nama := str(Maps.NAMES.get(str(ex.to), str(ex.to)))
		if not exits.has(nama):
			exits.append(nama)
	if not exits.is_empty():
		_body.add_child(_label("Jalan ke: " + ", ".join(exits), 22))
	var visited: Array = st.get("visited", [])
	var names: Array[String] = []
	for m: String in Maps.ZONA:
		names.append(("✓ " if visited.has(m) else "· ") + str(Maps.NAMES.get(m, m)))
	_body.add_child(_label("Penjelajahan %d/%d" % [visited.size(), Maps.ZONA.size()], 26))
	var l := _label("\n".join(names), 22)
	_body.add_child(l)


# --- Kabar (no. 216) ---

func _build_notices() -> void:
	if Session.notices.is_empty():
		_body.add_child(_label("Belum ada kabar.", 24))
	for i in range(Session.notices.size() - 1, -1, -1):
		var n: Dictionary = Session.notices[i]
		var when := Time.get_datetime_string_from_unix_time(int(n.at) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true).substr(11, 5)
		var l := _label("%s  %s" % [when, str(n.text)], 22)
		l.add_theme_color_override("font_color", {"dagang": Color("ffd27a"), "kejadian": Color("ff9c8c"), "hadiah": Color("9fe6a0")}.get(str(n.kind), Color("e8e8e0")) if not bool(n.read) else Color("a8a8a0"))
		_body.add_child(l)
		n.read = true


func _label(text: String, size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, h := 80) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 26)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b
