extends Control
## Atribut: (1) ganti perlengkapan yang dipakai dan lihat serangan/pertahanan, (2) beli pahlawan
## pendamping lalu pasang (maks 3) di belakang pemain; pendamping ikut menyerang saat bertarung.
## Semua aturan dijalankan SERVER (docs/API.md); layar ini hanya menampilkan dan mengirim permintaan.

const WORLD_SCENE := "res://scenes/world3d.tscn"
const ITEM_ART_DIR := "res://assets/items/"
const Heroes = preload("res://scripts/heroes.gd")
const Models = preload("res://scripts/models.gd")
const SLOTS := [["weapon", "Senjata"], ["armor", "Pelindung"], ["helmet", "Helm"]]
const KIND_COLOR := Color("5a7fb0")

var _catalog: Dictionary = {}  # id -> definisi barang dari server
var _info: Label
var _message: Label
var _tab_buttons: Array[Button] = []
var _page_equip: ScrollContainer
var _equip_list: VBoxContainer
var _page_ally: VBoxContainer
var _hero_tabs: Array[Button] = []
var _preview_holder: Node3D
var _preview_rig: Node3D
var _hero_name: Label
var _hero_detail: Label
var _party_label: Label
var _ally_btn: Button
var _sol_row: HBoxContainer      # pengatur jumlah prajurit yang dipasang: [-] n / total [+]
var _sol_minus: Button
var _sol_plus: Button
var _sol_count: Label
var _sol_btn: Button
var _sol_pick := -1              # jumlah yang sedang dipilih (belum dikirim ke server); -1 = ikut yang terpasang
var _selected := 0
var _busy := false
var _page := 0
var _page_prog: ScrollContainer   # halaman Kemampuan / Pencapaian (roadmap no. 139, 150)
var _prog_list: VBoxContainer
var _talents: Array = []
var _achievements: Array = []


func _ready() -> void:
	_build_ui()
	_show_page(0)
	var res: Dictionary = await Api.shop_get()  # katalog semua barang
	if not res.ok:
		_message.text = str(res.error)
		return
	for def: Dictionary in res.data.get("items", []):
		_catalog[str(def.id)] = def
	_selected = maxi(0, Heroes.ids().find(str(Heroes.current().id)))
	_refresh()
	var pr: Dictionary = await Api.progress_get()  # daftar kemampuan dan pencapaian (halaman 3 dan 4)
	if pr.ok:
		_talents = pr.data.get("talents", [])
		_achievements = pr.data.get("achievements", [])
		if _page >= 2:
			_refresh()


func _process(delta: float) -> void:
	if _preview_rig != null and _page == 1:
		_preview_rig.rotation.y += delta * 0.9


# --- data ---

func _state() -> Dictionary:
	return Session.player.state


func _equipment() -> Dictionary:
	return _state().get("equipment", {"weapon": "", "armor": "", "helmet": ""})


func _def(id: String) -> Dictionary:
	return _catalog.get(id, {})


func _name_of(id: String) -> String:
	return str(_def(id).get("name", id))


func _bonus_text(def: Dictionary) -> String:
	if int(def.get("attack", 0)) > 0:
		return "Serang +%d" % int(def.attack)
	if int(def.get("defense", 0)) > 0:
		return "Tahan +%d" % int(def.defense)
	return ""


func _owned(id: String) -> int:
	for item: Dictionary in _state().inventory:
		if str(item.id) == id:
			return int(item.qty)
	return 0


# --- aksi ---

func _act(request: Callable, ok_text: String) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await request.call()
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_message.text = ok_text
	else:
		_message.text = str(res.error)
	_refresh()


func _on_equip(id: String) -> void:
	await _act(Api.inventory_equip.bind(id), "%s dipakai." % _name_of(id))


func _on_unequip(slot: String) -> void:
	await _act(Api.inventory_unequip.bind(slot), "Perlengkapan dilepas.")


func _on_ally_pressed() -> void:
	var hero: Dictionary = Heroes.LIST[_selected]
	var id := str(hero.id)
	var allies: Array = _state().get("allies", [])
	var party: Array = _state().get("party", [])
	if not allies.has(id):
		_message.text = "Pahlawan direkrut di Basecamp (tenda merah)."
		return
	elif party.has(id):
		var rest := party.duplicate()
		rest.erase(id)
		await _act(Api.set_party.bind(rest), "%s dilepas dari barisan." % hero.name)
	else:
		var next := party.duplicate()
		next.append(id)
		await _act(Api.set_party.bind(next), "%s berbaris di belakangmu." % hero.name)


## Pilih jumlah prajurit yang dipasang (belum dikirim); tombol Pasang mengirimnya ke server.
func _on_sol_step(delta: int) -> void:
	var total := int(_state().get("soldiers", 0))
	_sol_pick = clampi(_sol_pick + delta, 0, total)
	_refresh_ally()


func _on_sol_deploy() -> void:
	var n := _sol_pick
	await _act(Api.deploy_soldiers.bind(n), "%d prajurit dipasang di belakangmu." % n if n > 0 else "Semua prajurit menunggu di kem.")


func _on_back() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- tampilan ---

func _show_page(i: int) -> void:
	_page = i
	_page_equip.visible = i == 0
	_page_ally.visible = i == 1
	_page_prog.visible = i >= 2
	for k in _tab_buttons.size():
		_tab_buttons[k].set_pressed_no_signal(k == i)
	if i >= 1:
		_refresh()


func _refresh() -> void:
	var st := _state()
	_info.text = "%s  Lv %d\nHP %d/%d   Emas %d" % [Session.player.name, st.level, st.hp, st.max_hp, st.gold]
	if _page == 0:
		_rebuild_equipment()
	elif _page == 1:
		_refresh_ally()
	elif _page == 2:
		_rebuild_talents()
	else:
		_rebuild_achievements()


func _rebuild_equipment() -> void:
	for child in _equip_list.get_children():
		child.queue_free()
	var st := _state()
	var bonus_atk := 0
	var bonus_def := 0
	for slot: Array in SLOTS:
		var wid := str(_equipment().get(slot[0], ""))
		bonus_atk += int(_def(wid).get("attack", 0)) if wid != "" else 0
		bonus_def += int(_def(wid).get("defense", 0)) if wid != "" else 0
	var atk := 4 + 2 * int(st.level) + bonus_atk
	var dfn := 1 + int(st.level) + bonus_def
	var stats := _label("Serangan  %d  (dasar %d, perlengkapan +%d)\nPertahanan  %d  (dasar %d, perlengkapan +%d)" % [
		atk, atk - bonus_atk, bonus_atk, dfn, dfn - bonus_def, bonus_def], 26)
	_equip_list.add_child(stats)
	for slot: Array in SLOTS:
		_equip_list.add_child(_header(str(slot[1])))
		var worn := str(_equipment().get(slot[0], ""))
		var row := _item_row(worn, "Dipakai" if worn != "" else "-", "Lepas" if worn != "" else "", _on_unequip.bind(str(slot[0])))
		_equip_list.add_child(row)
		var any := false
		for item: Dictionary in st.inventory:
			var id := str(item.id)
			var def := _def(id)
			if str(def.get("slot", "")) != str(slot[0]) or id == worn:
				continue
			any = true
			_equip_list.add_child(_item_row(id, _bonus_text(def), "Pakai", _on_equip.bind(id)))
		if not any:
			var hint := _label("Tidak ada pilihan lain di ransel. Beli di Toko.", 22)
			hint.add_theme_color_override("font_color", Color("b9c9bd"))
			_equip_list.add_child(hint)


func _item_row(id: String, sub: String, verb: String, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_icon(id))
	var text := "-" if id == "" else "%s\n%s" % [_name_of(id), sub]
	var label := _label(text, 26)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	if verb != "":
		var b := _button(verb, cb, 150, 76)
		row.add_child(b)
	return row


func _icon(id: String) -> Control:
	var path := ITEM_ART_DIR + id + ".png"
	if id != "" and ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path) as Texture2D
		tex.custom_minimum_size = Vector2(76, 76)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var box := ColorRect.new()
	box.color = Color(1, 1, 1, 0.08) if id == "" else KIND_COLOR
	box.custom_minimum_size = Vector2(76, 76)
	return box


func _refresh_ally() -> void:
	var st := _state()
	var allies: Array = st.get("allies", [])
	var party: Array = st.get("party", [])
	for i in _hero_tabs.size():
		var id := str(Heroes.LIST[i].id)
		_hero_tabs[i].set_pressed_no_signal(i == _selected)
		_hero_tabs[i].modulate = Color("ffd878") if party.has(id) else (Color("a8f0a0") if allies.has(id) else Color.WHITE)
	var hero: Dictionary = Heroes.LIST[_selected]
	var hid := str(hero.id)
	_hero_name.text = str(hero.name)
	var status := "Belum direkrut: %d emas di Basecamp (tenda merah)" % int(hero.price)
	if party.has(hid):
		status = "Berbaris di belakangmu (Lv %d)" % Session.hero_level(hid)
	elif allies.has(hid):
		status = "Sudah dibeli, belum dipasang (Lv %d)" % Session.hero_level(hid)
	_hero_detail.text = "%s\nSkill: %s, %s\n%s" % [hero.weapon, hero.skill1, hero.skill2, status]
	var names: PackedStringArray = []
	for id: String in party:
		names.append(str(Heroes.get_hero(id).short))
	_party_label.text = "Pendamping terpasang: %d/%d%s\nPasukan prajurit: %d/%d, Lv %d (HP %d tiap prajurit), dipasang %d\nPrajurit yang gugur dalam pertarungan tidak kembali. Pasukan menyerang sendiri musuh yang terlihat." % [party.size(), Heroes.MAX_PARTY, ("  (" + ", ".join(names) + ")") if not names.is_empty() else "", int(st.get("soldiers", 0)), Session.MAX_SOLDIERS, Session.squad_level(), Session.soldier_max_hp(), Session.active_soldiers()]
	var total := int(st.get("soldiers", 0))
	var active := Session.active_soldiers()
	if _sol_pick < 0 or _sol_pick > total:
		_sol_pick = active
	_sol_row.visible = total > 0
	_sol_btn.visible = total > 0
	_sol_count.text = "%d / %d" % [_sol_pick, total]
	_sol_minus.disabled = _sol_pick <= 0 or _busy
	_sol_plus.disabled = _sol_pick >= total or _busy
	_sol_btn.text = "Prajurit terpasang: %d" % active if _sol_pick == active else "Pasang %d prajurit" % _sol_pick
	_sol_btn.disabled = _sol_pick == active or _busy
	if not allies.has(hid):
		_ally_btn.text = "Rekrut di Basecamp (%d emas)" % int(hero.price)
		_ally_btn.disabled = true
	elif party.has(hid):
		_ally_btn.text = "Lepas dari barisan"
		_ally_btn.disabled = _busy
	else:
		_ally_btn.text = "Pasang di belakangku"
		_ally_btn.disabled = party.size() >= Heroes.MAX_PARTY or _busy
	if _preview_rig == null or _preview_rig.name != hid:
		if _preview_rig != null:
			_preview_rig.queue_free()
		_preview_rig = Models.create(hid)
		_preview_rig.name = hid
		_preview_holder.add_child(_preview_rig)


func _select_hero(i: int) -> void:
	_selected = i
	_message.text = ""
	_refresh_ally()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a2420")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preload("res://scripts/layar.gd").kolom(margin, 1100.0)  # layar mendatar: isi di kolom tengah

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := _label("Atribut", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("d8f0c8"))
	box.add_child(title)
	_info = _label("", 28)
	box.add_child(_info)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	for i in 4:
		var b := _button(["Perlengkapan", "Pendamping", "Kemampuan", "Pencapaian"][i], _show_page.bind(i), 0, 64)
		b.add_theme_font_size_override("font_size", 22)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons.append(b)

	_message = _label("", 24)
	_message.add_theme_color_override("font_color", Color("ffd27a"))
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)

	_page_equip = ScrollContainer.new()
	_page_equip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_equip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_page_equip)
	_equip_list = VBoxContainer.new()
	_equip_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_list.add_theme_constant_override("separation", 12)
	_page_equip.add_child(_equip_list)

	_page_prog = ScrollContainer.new()
	_page_prog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_prog.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_prog.visible = false
	box.add_child(_page_prog)
	_prog_list = VBoxContainer.new()
	_prog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prog_list.add_theme_constant_override("separation", 12)
	_page_prog.add_child(_prog_list)

	_page_ally = VBoxContainer.new()
	_page_ally.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_ally.add_theme_constant_override("separation", 10)
	box.add_child(_page_ally)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_page_ally.add_child(row)
	for i in Heroes.LIST.size():
		var hb := _button(str(Heroes.LIST[i].short), _select_hero.bind(i), 0, 60)
		hb.toggle_mode = true
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_theme_font_size_override("font_size", 24 if Heroes.LIST.size() <= 4 else 20)
		hb.clip_text = true
		row.add_child(hb)
		_hero_tabs.append(hb)
	# Layar mendatar (v0.68.0): pratinjau 3D di kiri, rincian dan tombol pendamping di kanan (bisa digulir).
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_ally.add_child(cols)
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(340, 0)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_stretch_ratio = 0.75
	holder.stretch = true
	cols.add_child(holder)
	holder.add_child(_build_preview())
	var ally_scroll := ScrollContainer.new()
	ally_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ally_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(ally_scroll)
	var ally_box := VBoxContainer.new()
	ally_box.add_theme_constant_override("separation", 8)
	ally_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ally_scroll.add_child(ally_box)
	_hero_name = _label("", 32)
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ally_box.add_child(_hero_name)
	_hero_detail = _label("", 24)
	_hero_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ally_box.add_child(_hero_detail)
	_party_label = _label("", 26)
	_party_label.add_theme_color_override("font_color", Color("e0c070"))
	_party_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ally_box.add_child(_party_label)
	_ally_btn = _button("", _on_ally_pressed, 0, 70)
	ally_box.add_child(_ally_btn)
	_sol_row = HBoxContainer.new()
	_sol_row.add_theme_constant_override("separation", 10)
	ally_box.add_child(_sol_row)
	var sol_title := _label("Prajurit dipasang:", 26)
	sol_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sol_row.add_child(sol_title)
	_sol_minus = _button("-", _on_sol_step.bind(-1), 84, 72)
	_sol_row.add_child(_sol_minus)
	_sol_count = _label("0 / 0", 32)
	_sol_count.custom_minimum_size = Vector2(120, 0)
	_sol_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sol_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sol_row.add_child(_sol_count)
	_sol_plus = _button("+", _on_sol_step.bind(1), 84, 72)
	_sol_row.add_child(_sol_plus)
	_sol_btn = _button("", _on_sol_deploy, 0, 68)
	ally_box.add_child(_sol_btn)

	box.add_child(_button("Kembali", _on_back, 0, 68))


func _build_preview() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(600, 380)
	vp.msaa_3d = Viewport.MSAA_2X
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b3a33")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4d2c8")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	vp.add_child(sun)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.75
	cyl.height = 0.08
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("5b7a4a")
	disc.material_override = dm
	disc.position.y = -0.04
	vp.add_child(disc)
	_preview_holder = Node3D.new()
	vp.add_child(_preview_holder)
	var cam := Camera3D.new()
	cam.fov = 34.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.65, 2.35), Vector3(0, 0.5, 0))
	cam.current = true
	return vp


# --- Kemampuan (pohon kemampuan, no. 139) ---

const TALENT_INFO := {
	"tajam": "Serangan +%d", "kulit_tebal": "Pertahanan +%d", "vitalitas": "HP maksimum +%d",
	"mata_elang": "Peluang kritis +%d%%", "hemat_tenaga": "Biaya jurus -%d energi", "benteng": "HP +%d dan pertahanan +1",
}


func _rebuild_talents() -> void:
	for c in _prog_list.get_children():
		c.queue_free()
	var pts := Session.talent_points()
	_prog_list.add_child(_label("Poin kemampuan: %d   (dapat 1 poin tiap naik level)" % pts, 26))
	if _talents.is_empty():
		_prog_list.add_child(_label("Daftar kemampuan belum termuat.", 24))
		return
	var ranks: Dictionary = _state().get("talent", {})
	for t: Dictionary in _talents:
		var id := str(t.id)
		var rk := int(ranks.get(id, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var needs := str(t.get("needs", ""))
		var locked := needs != "" and int(ranks.get(needs, 0)) < int(t.get("need_rank", 0))
		var pre := "   " if needs != "" else ""  # cabang digeser ke kanan: terlihat seperti pohon
		var desc: String = str(TALENT_INFO.get(id, "%d")) % (int(t.per) * maxi(1, rk))
		var sub := ("Butuh %s %d" % [_talent_name(needs), int(t.need_rank)]) if locked else desc
		var label := _label("%s%s  %d/%d\n%s%s" % [pre, str(t.name), rk, int(t.max), pre, sub], 24)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if locked:
			label.add_theme_color_override("font_color", Color("8a9a8e"))
		row.add_child(label)
		var b := _button("+", _on_learn.bind(id), 90, 72)
		b.disabled = _busy or pts < 1 or locked or rk >= int(t.max)
		row.add_child(b)
		_prog_list.add_child(row)


func _talent_name(id: String) -> String:
	for t: Dictionary in _talents:
		if str(t.id) == id:
			return str(t.name)
	return id


func _on_learn(id: String) -> void:
	await _act(Api.learn_talent.bind(id), "%s naik peringkat." % _talent_name(id))


# --- Pencapaian (no. 150) ---

func _rebuild_achievements() -> void:
	for c in _prog_list.get_children():
		c.queue_free()
	var done: Array = _state().get("achievements", [])
	var taken: Array = _state().get("achievements_taken", [])
	_prog_list.add_child(_label("Terbuka %d dari %d   Kemenangan: %d" % [done.size(), _achievements.size(), int(_state().get("wins", 0))], 26))
	for a: Dictionary in _achievements:
		var id := str(a.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var open := done.has(id)
		var label := _label("%s %s\nHadiah %d emas" % ["★" if open else "☆", str(a.name), int(a.gold)], 23)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color("ffe08a") if open else Color("8a9a8e"))
		row.add_child(label)
		if open:
			var got := taken.has(id)
			var b := _button("Diambil" if got else "Ambil", _on_claim.bind(id), 150, 72)
			b.disabled = got or _busy
			row.add_child(b)
		_prog_list.add_child(row)


func _on_claim(id: String) -> void:
	await _act(Api.claim_achievement.bind(id), "Hadiah pencapaian diambil.")


func _header(text: String) -> Label:
	var l := _label(text, 34)
	l.add_theme_color_override("font_color", Color("e0c070"))
	return l


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, width := 0, height := 80) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, height)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	return b
