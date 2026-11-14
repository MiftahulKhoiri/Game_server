extends CanvasLayer
## Character Creator, perlengkapan, inventaris, dan toko (v0.82.0).
##
## Kiri: pratinjau 3D pahlawan yang besar (geser untuk memutar 360 derajat, tombol Depan/Samping/Belakang,
## perbesar/perkecil, animasi diam berjalan). Kanan: tab Karakter, Penampilan, Perlengkapan, Senjata,
## Inventaris, Toko. Setiap pilihan langsung terlihat di model. Penampilan disimpan ke server
## (POST /v1/players/me/look) lewat tombol Simpan atau otomatis saat menutup; perlengkapan tempur dipakai/
## dilepas lewat server (equip/unequip); pembelian lewat server dengan id permintaan (tidak ganda).
## Klien hanya mengirim id: harga, level, saldo, dan kepemilikan diperiksa server.

signal closed
signal look_changed

const Models = preload("res://scripts/models.gd")
const Heroes = preload("res://scripts/heroes.gd")
const LookBuild = preload("res://scripts/look_build.gd")

const TABS := ["Karakter", "Penampilan", "Perlengkapan", "Senjata", "Inventaris", "Toko"]
const SUBTABS := {
	"Penampilan": ["Rambut", "Warna Rambut", "Wajah", "Mata", "Kulit", "Tubuh"],
	"Perlengkapan": ["Pakaian", "Celana", "Sarung Tangan", "Jubah", "Topi", "Skin", "Aksesori", "Zirah", "Helm", "Sepatu", "Perisai"],
	"Inventaris": ["Skin", "Rambut", "Pakaian", "Armor", "Helm", "Sepatu", "Senjata", "Aksesori"],
	"Toko": ["Skin", "Rambut", "Pakaian", "Armor", "Helm & Topi", "Jubah", "Sepatu", "Senjata", "Aksesori"],
}
## Sub-tab -> sumber barang: [["cos", kategori] | ["gear", slot], ...]
const SOURCES := {
	"Rambut": [["cos", "rambut"]], "Skin": [["cos", "skin"]], "Pakaian": [["cos", "pakaian"], ["cos", "celana"], ["cos", "sarung"]],
	"Celana": [["cos", "celana"]], "Sarung Tangan": [["cos", "sarung"]], "Jubah": [["cos", "jubah"]], "Topi": [["cos", "topi"]],
	"Aksesori": [["cos", "aksesori"]], "Zirah": [["gear", "armor"]], "Armor": [["gear", "armor"]], "Helm": [["gear", "helmet"], ["cos", "topi"]],
	"Helm & Topi": [["gear", "helmet"], ["cos", "topi"]], "Sepatu": [["gear", "boots"]], "Perisai": [["gear", "offhand"]],
	"Senjata": [["gear", "weapon"], ["gear", "offhand"]],
}
## Kategori kosmetik -> kolom penampilan.
const COS_FIELD := {"skin": "skin", "rambut": "hair", "pakaian": "clothes", "celana": "pants", "sarung": "gloves", "topi": "hat", "jubah": "cape"}
const TIER_NAME := {"common": "Biasa", "uncommon": "Tidak Biasa", "rare": "Langka", "epic": "Epik", "legendary": "Legendaris", "mythic": "Mitos"}
const TIER_COLOR := {"common": Color("c8d0d8"), "uncommon": Color("7fdc7f"), "rare": Color("7fc8ff"), "epic": Color("d79bff"), "legendary": Color("ffcc4a"), "mythic": Color("ff7a5a")}
const SLOT_NAME := {"weapon": "Senjata", "armor": "Zirah", "helmet": "Helm", "boots": "Sepatu", "offhand": "Perisai"}
const STYLE_NAME := {"pedang": "Pedang", "kapak": "Kapak", "tombak": "Tombak", "busur": "Busur", "sihir": "Sihir"}
const FACE_PARTS := [["face", "Bentuk wajah"], ["nose", "Hidung"], ["mouth", "Mulut"], ["brow", "Alis"], ["beard", "Jenggot dan kumis"]]
const BODY_SLIDERS := [["height", "Tinggi"], ["width", "Lebar badan"], ["muscle", "Otot"], ["head", "Ukuran kepala"], ["torso", "Proporsi badan"]]
const CAM_MIN := 1.4
const CAM_MAX := 3.6

var is_open := false

var _draft: Dictionary = {}       # penampilan yang sedang diubah (belum tentu tersimpan)
var _dirty := false
var _busy := false
var _saving := false              # permintaan simpan penampilan sedang berjalan (tidak dikirim ganda)
var _closing := false
var _last_error := ""
var _draft_timer: Timer
var _tab := "Penampilan"
var _sub := "Rambut"
var _selected: Dictionary = {}    # barang yang dipilih (untuk rincian, pratinjau, beli/pakai)
var _confirm_req := ""            # id permintaan beli yang sedang dikonfirmasi (dipakai ulang bila diulang)
var _items: Dictionary = {}       # id -> definisi barang (seluruh katalog)
var _welcome := false

var _yaw := 0.0
var _cam_dist := 2.5
var _auto_spin := false
var _rig: Node3D
var _holder: Node3D
var _cam: Camera3D
var _tab_row: HBoxContainer
var _sub_row: HFlowContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _detail: Label
var _btn_buy: Button
var _btn_use: Button
var _btn_save: Button
var _status: Label
var _gold: Label
var _confirm: PanelContainer
var _confirm_label: Label
var _confirm_row: HBoxContainer


func _init() -> void:
	layer = 12
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preload("res://scripts/layar.gd").kolom(margin, 1500.0, 16, 12)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1a1f2e")
	sb.border_color = Color("c8a24a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	panel.add_child(cols)

	# --- kiri: pratinjau 3D ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.85
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var title := _label("Karakter", 32)
	title.add_theme_color_override("font_color", Color("ffd27a"))
	left.add_child(title)
	var vc := SubViewportContainer.new()
	vc.stretch = true
	vc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vc.custom_minimum_size = Vector2(360, 300)
	vc.gui_input.connect(_on_preview_input)
	left.add_child(vc)
	vc.add_child(_build_viewport())
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 6)
	left.add_child(vrow)
	for pair: Array in [["Depan", 0.0], ["Samping", PI / 2.0], ["Belakang", PI]]:
		var yaw: float = pair[1]
		vrow.add_child(_button(str(pair[0]), func() -> void:
			_auto_spin = false
			_yaw = yaw, 22, true))
	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 6)
	left.add_child(zrow)
	zrow.add_child(_button("Perbesar +", func() -> void: _zoom(-0.3), 22, true))
	zrow.add_child(_button("Perkecil -", func() -> void: _zoom(0.3), 22, true))
	zrow.add_child(_button("Putar 360", func() -> void: _auto_spin = not _auto_spin, 22, true))

	# --- kanan: tab ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	var top := HBoxContainer.new()
	right.add_child(top)
	_gold = _label("", 26)
	_gold.add_theme_color_override("font_color", Color("ffd25a"))
	_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_gold)
	top.add_child(_button("Tutup", request_close, 24))
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	right.add_child(_tab_row)
	for t: String in TABS:
		var b := _button(t, _set_tab.bind(t), 22, true)
		b.toggle_mode = true
		_tab_row.add_child(b)
	_sub_row = HFlowContainer.new()
	_sub_row.add_theme_constant_override("h_separation", 4)
	_sub_row.add_theme_constant_override("v_separation", 4)
	right.add_child(_sub_row)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	_detail = _label("", 21)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0, 54)
	right.add_child(_detail)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	right.add_child(brow)
	_btn_use = _button("Pakai", _on_use, 24, true)
	brow.add_child(_btn_use)
	_btn_buy = _button("Beli", _on_buy, 24, true)
	brow.add_child(_btn_buy)
	_btn_save = _button("Simpan Penampilan", func() -> void: _save(), 24, true)
	brow.add_child(_btn_save)
	_status = _label("", 21)
	_status.add_theme_color_override("font_color", Color("ffd27a"))
	right.add_child(_status)
	_build_confirm()
	_draft_timer = Timer.new()
	_draft_timer.one_shot = true
	_draft_timer.wait_time = 0.4
	_draft_timer.timeout.connect(_write_draft_now)
	add_child(_draft_timer)


# --- buka / tutup ---

## Buka layar. welcome = pemain baru (belum pernah membuat karakter): mulai di Penampilan > Rambut.
## Draf yang belum sempat tersimpan (mis. jaringan putus) dipulihkan; data server tetap acuan sampai disimpan.
func open(tab := "Penampilan", welcome := false) -> void:
	_welcome = welcome
	_draft = Session.look_of(Session.player.state.get("look", {}))
	_dirty = false
	_busy = false
	_saving = false
	_selected = {}
	_status.text = "Selamat datang! Buat penampilan pahlawanmu, lalu ketuk Simpan." if welcome else ""
	visible = true
	is_open = true
	_make_rig()
	_set_tab(tab)
	if _items.is_empty() and not Session.offline:
		var res: Dictionary = await Api.item_catalog()
		if res.ok:
			for d: Dictionary in res.data.get("items", []):
				_items[str(d.id)] = d
	if Session.cosmetics.is_empty():
		await Session.ensure_wardrobe()
	_redress()
	_refresh_all()
	_offer_draft()


## Draf dari sesi sebelumnya (gagal simpan / aplikasi ditutup paksa) milik akun ini: tanya dulu, jangan diterapkan
## atau dikirim tanpa pilihan pemain. Draf yang sama dengan data server dibuang diam-diam.
func _offer_draft() -> void:
	var pending := Session.load_look_draft()
	if pending.is_empty() or not is_open:
		return
	var server_look := Session.look_of(Session.player.state.get("look", {}))
	if _same_look(pending.look, server_look):
		Session.clear_look_draft()
		return
	var note := ""
	if not _same_look(pending.base, server_look):
		note = "\nPenampilan di server sudah berubah sejak itu."
	_ask("Ada perubahan penampilan yang belum tersimpan.%s\nPulihkan perubahan itu?" % note, [
		["Pulihkan", func() -> void:
			_draft = pending.look
			_dirty = true
			_status.text = "Perubahan dipulihkan; ketuk Simpan untuk menyimpannya."
			_redress()
			_refresh_all()],
		["Buang", func() -> void:
			Session.clear_look_draft()
			_status.text = "Perubahan lama dibuang."],
	])


static func _same_look(a: Dictionary, b: Dictionary) -> bool:
	var x := a.duplicate(true)
	var y := b.duplicate(true)
	x.erase("made")
	y.erase("made")
	return x == y


## Penampilan draf berubah oleh pemain: tandai belum tersimpan dan tulis draf ke HP (ditunda sebentar supaya
## geser penggeser tidak menulis berkas di setiap langkah).
func _touch() -> void:
	_dirty = true
	if _draft_timer != null:
		_draft_timer.start()


func _write_draft_now() -> void:
	if _dirty and is_open:
		Session.save_look_draft(_draft)


## Tutup layar (dipanggil pemilik setelah sinyal `closed`). Draf yang belum tersimpan sudah disimpan di HP.
func close() -> void:
	visible = false
	is_open = false
	_confirm.visible = false
	_closing = false
	if _rig != null:
		_rig.queue_free()
		_rig = null


## Tombol Tutup / kembali. Penampilan yang belum tersimpan disimpan dulu; layar baru ditutup setelah server
## menerimanya. Bila gagal, layar tetap terbuka, draf tetap ada, dan pemain memilih Coba Lagi / Tutup (draf
## disimpan di HP untuk lain kali) / Kembali.
func request_close() -> void:
	if _confirm.visible:
		_confirm.visible = false
		return
	if _closing:
		return
	if _saving:
		_status.text = "Tunggu, penampilan sedang disimpan..."
		return
	if _dirty:
		_closing = true
		var ok := await _save()
		_closing = false
		if not ok:
			_ask("Penampilan belum tersimpan:\n%s\nPerubahanmu tidak hilang." % _last_error, [
				["Coba Lagi", request_close],
				["Tutup, simpan nanti", func() -> void:
					Session.save_look_draft(_draft)
					closed.emit()],
				["Kembali", func() -> void: pass],
			])
			return
	closed.emit()


# --- pratinjau 3D ---

func _build_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(560, 640)
	vp.msaa_3d = Viewport.MSAA_2X
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2a3346")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d0d8e8")
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-25), 0)
	vp.add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation = Vector3(deg_to_rad(-20), deg_to_rad(160), 0)
	back.light_energy = 0.45
	vp.add_child(back)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.85
	cyl.height = 0.08
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("3a4a5a")
	disc.material_override = dm
	disc.position.y = -0.04
	vp.add_child(disc)
	_holder = Node3D.new()
	vp.add_child(_holder)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	vp.add_child(_cam)
	_cam.current = true
	_place_cam()
	return vp


func _place_cam() -> void:
	if _cam == null:
		return
	var h := 0.55 + (CAM_MAX - _cam_dist) * 0.06
	_cam.look_at_from_position(Vector3(0, h + 0.15, _cam_dist), Vector3(0, h, 0))


func _zoom(d: float) -> void:
	_cam_dist = clampf(_cam_dist + d, CAM_MIN, CAM_MAX)
	_place_cam()


func _on_preview_input(ev: InputEvent) -> void:
	if ev is InputEventScreenDrag:
		_yaw += (ev as InputEventScreenDrag).relative.x * 0.012
		_auto_spin = false
	elif ev is InputEventMouseMotion and ((ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_yaw += (ev as InputEventMouseMotion).relative.x * 0.012
		_auto_spin = false
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-0.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.15)
	elif ev is InputEventMagnifyGesture:
		_zoom((1.0 - (ev as InputEventMagnifyGesture).factor) * 2.0)


func _process(delta: float) -> void:
	if not is_open or _rig == null:
		return
	if _auto_spin:
		_yaw += delta * 0.9
	_rig.rotation.y = lerp_angle(_rig.rotation.y, _yaw, minf(1.0, delta * 10.0))


func _make_rig() -> void:
	if _rig != null:
		_rig.queue_free()
	_rig = Models.create(str(Heroes.current().id))
	_holder.add_child(_rig)
	_redress()


## Model memakai penampilan draf + barang yang sedang dilihat (belum tentu dimiliki).
func _redress() -> void:
	if _rig == null:
		return
	var st: Dictionary = Session.player.state
	var look := _draft.duplicate(true)
	var eq: Dictionary = (st.get("equipment", {}) as Dictionary).duplicate()
	if not _selected.is_empty():
		if _selected.kind == "cos":
			_apply_cos(look, _selected, true)
		elif not _selected.get("slot", "").is_empty():
			eq[str(_selected.slot)] = str(_selected.id)
	Models.dress(_rig, int(st.get("outfit", 0)), eq, look)


# --- data barang ---

func _cos_list(cat: String) -> Array:
	var out: Array = []
	for c: Variant in Session.wardrobe_catalog.get("cosmetics", []):
		if c is Dictionary and str(c.category) == cat:
			var e: Dictionary = (c as Dictionary).duplicate()
			e["kind"] = "cos"
			out.append(e)
	return out


func _gear_list(slot: String, owned_only: bool) -> Array:
	var out: Array = []
	var seen := {}
	for g: Variant in Session.wardrobe_catalog.get("gear", []):
		if g is Dictionary and str(g.get("slot", "")) == slot:
			seen[str(g.id)] = true
			out.append(_gear_entry(g))
	for it: Dictionary in Session.player.state.get("inventory", []):  # barang dimiliki yang tidak dijual (hadiah misi)
		var d: Dictionary = _items.get(str(it.id), {})
		if not seen.has(str(it.id)) and str(d.get("slot", "")) == slot:
			out.append(_gear_entry(d))
	if owned_only:
		out = out.filter(func(e: Dictionary) -> bool: return _owned(e))
	return out


func _gear_entry(d: Dictionary) -> Dictionary:
	var e := d.duplicate()
	e["kind"] = "gear"
	e["price"] = int(d.get("buy_price", 0))
	if not e.has("tier"):
		e["tier"] = "common"
	return e


func _entries(sub: String, owned_only: bool) -> Array:
	var out: Array = []
	for src: Array in SOURCES.get(sub, []):
		if src[0] == "cos":
			for e: Dictionary in _cos_list(str(src[1])):
				if not owned_only or _owned(e):
					out.append(e)
		else:
			out.append_array(_gear_list(str(src[1]), owned_only))
	return out


func _owned(e: Dictionary) -> bool:
	if e.kind == "cos":
		return int(e.get("price", 0)) == 0 or (Session.player.state.get("wardrobe", []) as Array).has(str(e.id))
	return Session.item_count(str(e.id)) > 0


func _in_use(e: Dictionary) -> bool:
	if e.kind == "cos":
		if str(e.category) == "aksesori":
			return (_draft.get("accessories", []) as Array).has(str(e.id))
		return str(_draft.get(COS_FIELD.get(str(e.category), ""), "")) == str(e.id)
	return str((Session.player.state.get("equipment", {}) as Dictionary).get(str(e.get("slot", "")), "")) == str(e.id)


## Pasang/lepas kosmetik pada kamus penampilan `look`. force = selalu pasang (pratinjau).
func _apply_cos(look: Dictionary, e: Dictionary, force := false) -> void:
	var cat := str(e.category)
	if cat == "aksesori":
		var acc: Array = (look.get("accessories", []) as Array).duplicate()
		if acc.has(str(e.id)):
			if not force:
				acc.erase(str(e.id))
		else:
			if acc.size() >= int(Session.wardrobe_catalog.get("max_acc", 4)):
				acc.pop_front()
			acc.append(str(e.id))
		look["accessories"] = acc
		return
	var field: String = COS_FIELD.get(cat, "")
	if field == "":
		return
	look[field] = "" if (str(look.get(field, "")) == str(e.id) and not force) else str(e.id)


# --- tampilan ---

func _set_tab(t: String) -> void:
	_tab = t
	var subs: Array = SUBTABS.get(t, [])
	if not subs.has(_sub):
		_sub = subs[0] if not subs.is_empty() else ""
	if t == "Senjata":
		_sub = "Senjata"
	_selected = {}
	_redress()
	_refresh_all()


func _set_sub(s: String) -> void:
	_sub = s
	_selected = {}
	_redress()
	_refresh_all()


func _refresh_all() -> void:
	if not is_open:
		return
	var st: Dictionary = Session.player.state
	_gold.text = "Emas: %d    Lv %d" % [int(st.get("gold", 0)), int(st.get("level", 1))]
	for b: Node in _tab_row.get_children():
		(b as Button).set_pressed_no_signal((b as Button).text == _tab)
	for c in _sub_row.get_children():
		c.queue_free()
	for s: String in SUBTABS.get(_tab, []):
		var sb := _button(s, _set_sub.bind(s), 18)
		sb.toggle_mode = true
		sb.custom_minimum_size = Vector2(0, 46)
		sb.set_pressed_no_signal(s == _sub)
		_sub_row.add_child(sb)
	for c in _content.get_children():
		c.queue_free()
	match _tab:
		"Karakter":
			_show_karakter()
		"Penampilan":
			_show_penampilan()
		"Perlengkapan", "Senjata", "Inventaris":
			_show_items(_entries(_sub, _tab == "Inventaris"))
		"Toko":
			_show_items(_entries(_sub, false), true)
	_btn_save.text = "Simpan Penampilan" + (" *" if _dirty else "")
	_btn_save.disabled = _busy or not _dirty
	_show_detail()


func _show_karakter() -> void:
	var st: Dictionary = Session.player.state
	var eq: Dictionary = st.get("equipment", {})
	var lines: Array = ["%s — %s" % [Session.player.get("name", ""), Heroes.current().name], ""]
	for slot: String in ["weapon", "offhand", "armor", "helmet", "boots"]:
		var id := str(eq.get(slot, ""))
		lines.append("%s: %s" % [SLOT_NAME[slot], _name_of(id) if id != "" else "-"])
	lines.append("")
	var parts: Array = []
	for f: String in ["hair", "clothes", "cape", "hat"]:
		var id := str(_draft.get(f, ""))
		if id != "":
			parts.append(str(LookBuild.cosm(id).get("name", id)))
	lines.append("Penampilan: " + (", ".join(parts) if not parts.is_empty() else "bawaan pahlawan"))
	lines.append("Aksesori: %d dari %d" % [(_draft.get("accessories", []) as Array).size(), int(Session.wardrobe_catalog.get("max_acc", 4))])
	var info := _label("\n".join(lines), 24)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	row.add_child(_button("Acak Penampilan", _randomize, 22, true))
	row.add_child(_button("Kembali ke Asli", func() -> void:
		_draft = {}
		_touch()
		_redress()
		_refresh_all(), 22, true))


func _show_penampilan() -> void:
	var cat: Dictionary = Session.wardrobe_catalog
	match _sub:
		"Rambut":
			_show_items(_cos_list("rambut"))
		"Warna Rambut":
			_swatches("Warna rambut", "hair_color", cat.get("hair_colors", []))
		"Kulit":
			_swatches("Warna kulit", "skin_color", cat.get("skin_colors", []))
		"Mata":
			_options("Bentuk mata", "eyes")
			_swatches("Warna mata", "eye_color", cat.get("eye_colors", []))
		"Wajah":
			for p: Array in FACE_PARTS:
				_options(str(p[1]), str(p[0]))
		"Tubuh":
			_options("Bentuk tubuh", "body")
			for p: Array in BODY_SLIDERS:
				_slider(str(p[1]), str(p[0]))
			var note := _label("Ukuran tubuh hanya tampilan: rangka, animasi, dan aturan pertarungan tetap sama.", 18)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.add_theme_color_override("font_color", Color("9aa8b8"))
			_content.add_child(note)


func _options(title: String, field: String) -> void:
	_content.add_child(_label(title, 22))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_content.add_child(flow)
	var opts: Array = (Session.wardrobe_catalog.get("options", {}) as Dictionary).get(field, [])
	for o: Dictionary in opts:
		var id := str(o.id)
		var b := _button(str(o.name), _set_field.bind(field, id), 20)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(130, 54)
		var cur := str(_draft.get(field, ""))
		b.set_pressed_no_signal(cur == id or (cur == "" and opts.find(o) == 0 and field != "beard"))
		flow.add_child(b)


func _swatches(title: String, field: String, colors: Array) -> void:
	_content.add_child(_label(title, 22))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	_content.add_child(flow)
	for hx: Variant in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(str(hx))
		sb.set_corner_radius_all(32)
		var chosen := str(_draft.get(field, "")) == str(hx)
		sb.border_color = Color("ffd25a") if chosen else Color(1, 1, 1, 0.3)
		sb.set_border_width_all(5 if chosen else 2)
		for state: String in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_set_field.bind(field, str(hx)))
		flow.add_child(b)


func _slider(title: String, field: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	var l := _label(title, 21)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = int(Session.wardrobe_catalog.get("body_min", -3))
	s.max_value = int(Session.wardrobe_catalog.get("body_max", 3))
	s.step = 1
	s.value = int(_draft.get(field, 0))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 48)
	s.focus_mode = Control.FOCUS_NONE
	var val := _label("%+d" % int(s.value), 21)
	val.custom_minimum_size = Vector2(46, 0)
	s.value_changed.connect(func(v: float) -> void:
		_draft[field] = int(v)
		val.text = "%+d" % int(v)
		_touch()
		_btn_save.disabled = false
		_btn_save.text = "Simpan Penampilan *"
		_redress())
	row.add_child(s)
	row.add_child(val)


func _set_field(field: String, value: String) -> void:
	_draft[field] = value
	_touch()
	_redress()
	_refresh_all()


## Daftar barang berikon. shop = tampilkan harga dan status kepemilikan.
func _show_items(list: Array, shop := false) -> void:
	if list.is_empty():
		var empty := _label("Belum ada barang di sini." if _tab == "Inventaris" else "Memuat daftar...", 22)
		_content.add_child(empty)
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_content.add_child(grid)
	for e: Dictionary in list:
		grid.add_child(_item_button(e, shop))


func _item_button(e: Dictionary, shop: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 92)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 64)
	var icon_path := "res://assets/items/%s.png" % e.id
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
	var owned := _owned(e)
	var tag := ""
	if _in_use(e):
		tag = "Dipakai"
	elif owned:
		tag = "Dimiliki"
	elif shop or int(e.get("price", 0)) > 0:
		tag = "%d emas" % int(e.get("price", 0))
	if not owned and int(e.get("level", 0)) > int(Session.player.state.get("level", 1)):
		tag += "  Lv %d" % int(e.level)
	b.text = "%s\n%s" % [str(e.name), tag]
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 19)
	var tc: Color = TIER_COLOR.get(str(e.get("tier", "common")), Color.WHITE)
	b.add_theme_color_override("font_color", tc)
	b.add_theme_color_override("font_pressed_color", tc)
	b.add_theme_color_override("font_hover_color", tc.lightened(0.2))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("26304a") if str(_selected.get("id", "")) != str(e.id) else Color("3a4a70")
	sb.border_color = tc if _in_use(e) else tc.darkened(0.5)
	sb.set_border_width_all(3 if _in_use(e) else 2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(6)
	for state: String in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(_select.bind(e))
	return b


func _select(e: Dictionary) -> void:
	_selected = e
	_confirm_req = ""
	if _tab != "Toko" and _owned(e) and e.kind == "cos":
		_use_selected()  # di Penampilan/Perlengkapan/Inventaris: ketuk = langsung pakai/lepas
		return
	_redress()
	_refresh_all()


func _show_detail() -> void:
	_btn_buy.visible = false
	_btn_use.visible = false
	if _selected.is_empty():
		_detail.text = "Ketuk barang untuk melihatnya di model." if _tab not in ["Karakter", "Penampilan"] or _sub in ["Rambut"] else ""
		return
	var e := _selected
	var lines: Array = ["%s  [%s]" % [e.name, TIER_NAME.get(str(e.get("tier", "common")), "")]]
	if str(e.get("desc", "")) != "":
		lines.append(str(e.desc))
	var stats: Array = []
	if int(e.get("attack", 0)) > 0:
		stats.append("Serangan +%d" % int(e.attack))
	if int(e.get("defense", 0)) > 0:
		stats.append("Pertahanan +%d" % int(e.defense))
	if int(e.get("speed_pct", 0)) > 0 and int(e.speed_pct) != 100:
		stats.append("Kecepatan %s" % ("cepat" if int(e.speed_pct) < 100 else "lambat"))
	if int(e.get("crit", 0)) > 0:
		stats.append("Kritis +%d%%" % int(e.crit))
	if str(e.get("style", "")) != "":
		stats.append("Untuk gaya %s" % STYLE_NAME.get(str(e.style), str(e.style)))
	if int(e.get("level", 0)) > 1:
		stats.append("Butuh Lv %d" % int(e.level))
	var owned := _owned(e)
	if not owned and int(e.get("price", 0)) > 0:
		stats.append("Harga %d emas" % int(e.price))
	if not stats.is_empty():
		lines.append("  •  ".join(stats))
	_detail.text = "\n".join(lines)
	_detail.add_theme_color_override("font_color", TIER_COLOR.get(str(e.get("tier", "common")), Color.WHITE))
	if owned:
		_btn_use.visible = true
		_btn_use.text = "Lepas" if _in_use(e) else "Pakai"
		_btn_use.disabled = _busy
	elif int(e.get("price", 0)) > 0:
		_btn_buy.visible = true
		_btn_buy.text = "Beli %d emas" % int(e.price)
		_btn_buy.disabled = _busy


# --- tindakan ---

func _on_use() -> void:
	if not _selected.is_empty():
		_use_selected()


func _use_selected() -> void:
	var e := _selected
	if e.kind == "cos":
		_apply_cos(_draft, e)
		_touch()
		_redress()
		_refresh_all()
		return
	if _busy:
		return
	_busy = true
	_refresh_all()
	var res: Dictionary = {"ok": false, "error": "Butuh server"}
	if Session.offline:
		pass
	elif _in_use(e):
		res = await Api.inventory_unequip(str(e.slot))
	else:
		res = await Api.inventory_equip(str(e.id))
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = "%s %s." % [e.name, "dipakai" if _in_use(e) else "dilepas"]
		look_changed.emit()
	else:
		_status.text = str(res.error)
	_redress()
	_refresh_all()


func _on_buy() -> void:
	if _selected.is_empty() or _busy:
		return
	var e := _selected
	var gold := int(Session.player.state.get("gold", 0))
	var price := int(e.get("price", 0))
	if _confirm_req == "":
		_confirm_req = Api.new_request_id()
	if int(e.get("level", 0)) > int(Session.player.state.get("level", 1)):
		_ask("%s butuh level %d (levelmu %d)." % [e.name, int(e.level), int(Session.player.state.get("level", 1))], [["Tutup", func() -> void: pass]])
		return
	if gold < price:
		_ask("Emas tidak cukup untuk %s.\nHarga %d, saldo %d." % [e.name, price, gold], [["Tutup", func() -> void: pass]])
		return
	_ask("Beli %s seharga %d emas?\nSaldo: %d  ->  %d" % [e.name, price, gold, gold - price], [["Ya, beli", _confirm_buy], ["Batal", func() -> void: pass]])


func _confirm_buy() -> void:
	_confirm.visible = false
	if _selected.is_empty() or _busy:  # ketukan ganda: permintaan kedua tidak dikirim
		return
	var e := _selected
	_busy = true
	_status.text = "Membeli..."
	_refresh_all()
	var res: Dictionary
	if Session.offline:
		res = {"ok": false, "error": "Pembelian butuh server"}
	elif e.kind == "cos":
		res = await Api.wardrobe_buy(str(e.id), _confirm_req)
	else:
		res = await Api.shop_buy(str(e.id), 1, str(Session.wardrobe_catalog.get("gear_shop", "peralatan")), _confirm_req)
	_busy = false
	if res.ok:
		_confirm_req = ""
		Session.merge_server_player(res.data)
		_status.text = "%s dibeli! Ketuk Pakai untuk memakainya." % e.name
	else:
		_status.text = str(res.error)
	_refresh_all()


## Simpan penampilan ke server. true = tersimpan (atau tidak ada perubahan). Hanya satu permintaan berjalan;
## gagal = draf tetap, pesan ditampilkan, pemain bisa mengetuk Simpan lagi (tidak dicoba otomatis berulang).
func _save() -> bool:
	if not _dirty:
		return true
	if _saving:
		return false
	if Session.offline:
		Session.player.state["look"] = _draft.duplicate(true)
		_dirty = false
		look_changed.emit()
		_refresh_all()
		return true
	_saving = true
	_busy = true
	_status.text = "Menyimpan..."
	_refresh_all()
	var sent := Session.look_of(_draft)
	var body := sent.duplicate(true)
	body.erase("made")
	var res: Dictionary = await Api.set_look(body)
	_saving = false
	_busy = false
	if not res.ok:
		_last_error = str(res.error) if str(res.get("error", "")) != "" else "jaringan terputus"
		Session.save_look_draft(_draft)  # tidak hilang walau aplikasi ditutup
		_status.text = "Gagal menyimpan: %s. Perubahan tetap ada; ketuk Simpan untuk mencoba lagi." % _last_error
		_refresh_all()
		return false
	Session.merge_server_player(res.data)  # server sumber kebenaran
	var server_look := Session.look_of(Session.player.state.get("look", {}))
	var changed_meanwhile := Session.look_of(_draft) != sent
	if changed_meanwhile:
		Session.save_look_draft(_draft)  # pemain masih mengubah saat menyimpan: perubahan baru belum tersimpan
	else:
		_draft = server_look
		_dirty = false
		Session.clear_look_draft()
	_status.text = "Penampilan tersimpan di server." if not changed_meanwhile else "Tersimpan; ada perubahan baru yang belum disimpan."
	look_changed.emit()
	_redress()
	_refresh_all()
	return not changed_meanwhile


## Penampilan acak dari pilihan gratis dan kosmetik yang dimiliki.
func _randomize() -> void:
	var cat: Dictionary = Session.wardrobe_catalog
	var d := {}
	for field: String in ["face", "eyes", "nose", "mouth", "brow", "beard", "body"]:
		var opts: Array = (cat.get("options", {}) as Dictionary).get(field, [])
		if not opts.is_empty():
			d[field] = str(opts.pick_random().id)
	for pair: Array in [["hair_color", "hair_colors"], ["skin_color", "skin_colors"], ["eye_color", "eye_colors"]]:
		var cl: Array = cat.get(pair[1], [])
		if not cl.is_empty():
			d[pair[0]] = str(cl.pick_random())
	var hairs := _cos_list("rambut").filter(func(e: Dictionary) -> bool: return _owned(e))
	if not hairs.is_empty():
		d["hair"] = str(hairs.pick_random().id)
	for f: String in ["height", "width", "muscle", "head", "torso"]:
		d[f] = randi_range(-2, 2)
	for f: String in ["clothes", "pants", "gloves", "hat", "cape", "skin", "accessories"]:  # pakaian tetap
		if _draft.has(f):
			d[f] = _draft[f]
	_draft = d
	_touch()
	_redress()
	_refresh_all()


func _name_of(id: String) -> String:
	return str(_items.get(id, {}).get("name", id.replace("_", " ").capitalize()))


# --- dialog konfirmasi ---

func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("101624")
	sb.border_color = Color("ffd25a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(24)
	_confirm.add_theme_stylebox_override("panel", sb)
	_confirm.visible = false
	add_child(_confirm)
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_confirm.add_child(box)
	_confirm_label = _label("", 26)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_confirm_label)
	_confirm_row = HBoxContainer.new()
	_confirm_row.add_theme_constant_override("separation", 12)
	box.add_child(_confirm_row)


## Dialog dengan pesan dan tombol [[teks, aksi], ...]; setiap tombol menutup dialog lalu menjalankan aksinya.
func _ask(text: String, buttons: Array) -> void:
	_confirm_label.text = text
	for c in _confirm_row.get_children():
		_confirm_row.remove_child(c)
		c.queue_free()
	for pair: Array in buttons:
		var act: Callable = pair[1]
		_confirm_row.add_child(_button(str(pair[0]), func() -> void:
			_confirm.visible = false
			act.call(), 24, true))
	_confirm.visible = true


# --- pembuat kontrol ---

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, size := 24, expand := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b
