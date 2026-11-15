extends Control
## Profil Petualang: nama, kelas 1–6, pahlawan (laki-laki/perempuan), warna baju dari koleksi.
## Pratinjau 3D pahlawan di kiri. "Siap Berpetualang!" -> saved(profile).

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const HeroPreview := preload("res://games/education_sd/scripts/ui/hero_preview.gd")

signal saved(prof: Dictionary)
signal back_pressed
signal message(text: String)

var prof: Dictionary
var outfits: Array = []  # [{id, color}]
var hats: Dictionary = {}  # id -> value (topi & aksesori dari koleksi)
var preview: SubViewportContainer
var name_edit: LineEdit
var _grade_btns: Array = []
var _hero_btns: Dictionary = {}
var _outfit_btns: Dictionary = {}
var _left: Control
var _right: VBoxContainer
var first_time := false


## prof: salinan p.profile; shop: daftar barang toko (pulau_ilmu.json); owned: id barang yang dimiliki.
func setup(profile: Dictionary, shop: Array, owned: Array, is_first: bool) -> void:
	prof = profile.duplicate(true)
	first_time = is_first
	for s in shop:
		var id := str(s.id)
		if id.begins_with("warna_") and owned.has(id):
			outfits.append({"id": id, "color": Color.from_string(str(s.value), Color.RED)})
		elif owned.has(id):
			hats[id] = str(s.value)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("fdf6e3")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left = Control.new()
	add_child(_left)
	preview = HeroPreview.new()
	preview.name = "Preview"
	_left.add_child(preview)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_right = UI.vbox(12)
	_right.name = "Form"
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_right)
	var head := UI.hbox(12)
	if not first_time:
		var back := UI.button("Kembali", func() -> void: back_pressed.emit(), Color("cfc8dc"), 22, 60)
		back.name = "Back"
		head.add_child(back)
	head.add_child(UI.label("Profil Petualang", 36, UI.PRIMARY, false))
	_right.add_child(head)
	_right.add_child(UI.label("Siapa namamu, petualang?", 24, UI.INK))
	name_edit = UI.line_edit(str(prof.name), "Tulis namamu")
	name_edit.name = "NameEdit"
	name_edit.max_length = 16
	name_edit.text_submitted.connect(func(_t: String) -> void: submit())
	_right.add_child(name_edit)
	_right.add_child(UI.label("Kamu kelas berapa?", 24, UI.INK))
	var g := UI.grid(6, 8)
	for k in range(1, 7):
		var b := UI.button(str(k), _set_grade.bind(k), Color("e8e2f2"), 28, 70)
		b.name = "Grade%d" % k
		UI.expand(b)
		_grade_btns.append(b)
		g.add_child(b)
	_right.add_child(g)
	_right.add_child(UI.label("Pilih pahlawanmu", 24, UI.INK))
	var hr := UI.hbox(10)
	for h in [["laki", "Petualang Laki-laki"], ["perempuan", "Petualang Perempuan"]]:
		var hb := UI.button(h[1], _set_hero.bind(h[0]), Color("e8e2f2"), 22, 66)
		hb.name = "Hero_" + h[0]
		UI.expand(hb)
		_hero_btns[h[0]] = hb
		hr.add_child(hb)
	_right.add_child(hr)
	_right.add_child(UI.label("Warna baju", 24, UI.INK))
	var orow := UI.hbox(10)
	for o in outfits:
		var ob := UI.button("", _set_outfit.bind(str(o.id)), o.color, 20, 60)
		ob.name = "Outfit_" + str(o.id)
		ob.custom_minimum_size.x = 70
		_outfit_btns[str(o.id)] = ob
		orow.add_child(ob)
	_right.add_child(orow)
	var go := UI.button("Siap Berpetualang!" if first_time else "Simpan", submit, UI.GOOD, 32, 88)
	go.name = "Save"
	_right.add_child(go)
	_refresh()
	resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	var lw := size.x * 0.36
	_left.position = Vector2(20, 20)
	_left.size = Vector2(lw, size.y - 40)
	preview.position = Vector2.ZERO
	preview.size = _left.size
	var scroll: ScrollContainer = get_node("Scroll")
	scroll.position = Vector2(lw + 40, 16)
	scroll.size = Vector2(size.x - lw - 70, size.y - 32)
	_right.custom_minimum_size.x = scroll.size.x - 10


func _set_grade(k: int) -> void:
	prof.grade = k
	_refresh()


func _set_hero(h: String) -> void:
	prof.hero = h
	_refresh()


func _set_outfit(id: String) -> void:
	prof.outfit = id
	_refresh()


func shirt_color() -> Color:
	for o in outfits:
		if str(o.id) == str(prof.outfit):
			return o.color
	return Color("e05a4f")


func _refresh() -> void:
	for i in _grade_btns.size():
		(_grade_btns[i] as Button).add_theme_stylebox_override("normal",
			UI.box(Color("ffd166") if i + 1 == int(prof.grade) else Color("e8e2f2")))
	for h in _hero_btns:
		(_hero_btns[h] as Button).add_theme_stylebox_override("normal",
			UI.box(Color("ffd166") if h == str(prof.hero) else Color("e8e2f2")))
	for id in _outfit_btns:
		(_outfit_btns[id] as Button).text = "✓" if id == str(prof.outfit) else ""
	preview.set_look({"hero": prof.hero, "shirt": shirt_color(), "hat": hats.get(str(prof.hat), ""),
		"acc": hats.get(str(prof.acc), "")})


func submit() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		message.emit("Tulis namamu dulu, ya.")
		return
	prof.name = n.substr(0, 16)
	saved.emit(prof)
