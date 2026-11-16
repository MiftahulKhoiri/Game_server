extends Control
## Tas Petualang (tab Status, Barang, Kostum, Koleksi, Prestasi) dan Toko penduduk.
## Kostum dipakai langsung dengan pratinjau 3D; toko menjual barang pertarungan & kostum dengan koin.

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const HeroPreview := preload("res://games/education_sd/scripts/ui/hero_preview.gd")

signal closed
signal changed  # progres berubah (simpan)
signal look_changed  # kostum berganti (perbarui model pemain)

var rewards  # RewardEngine
var p: Dictionary
var quest_items: Dictionary = {}
var ctx: Dictionary = {}
var audio: Node
var mode := "tas"  # "tas" | "toko"
var shop_id := ""
var tab := ""
var preview: SubViewportContainer
var _panel: PanelContainer
var _tabs: HBoxContainer
var _box: VBoxContainer
var _coins: Label
var _right: Control


func setup(engine, progress: Dictionary, items_extra: Dictionary, context: Dictionary, sound: Node, open_mode := "tas", shop := "") -> void:
	rewards = engine
	p = progress
	quest_items = items_extra
	ctx = context
	audio = sound
	mode = open_mode
	shop_id = shop
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s := get_viewport_rect().size
	_panel = UI.panel(Color("fdf6e3"), 28)
	_panel.name = "Panel"
	_panel.position = Vector2(s.x * 0.04, s.y * 0.04)
	_panel.size = Vector2(s.x * 0.92, s.y * 0.92)
	_panel.custom_minimum_size = _panel.size
	add_child(_panel)
	var v := UI.vbox(10)
	_panel.add_child(v)
	var head := UI.hbox(10)
	var close := UI.button("Tutup", func() -> void: closed.emit(), Color("cfc8dc"), 22, 58)
	close.name = "Close"
	head.add_child(close)
	var title := UI.label(str(rewards.shop(shop_id).get("title", "Toko")) if mode == "toko" else "Tas Petualang", 32, UI.PRIMARY, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var chip := UI.panel(Color("ffd166"), 18)
	_coins = UI.label("", 22, UI.INK, false)
	chip.add_child(_coins)
	head.add_child(chip)
	v.add_child(head)
	_tabs = UI.hbox(8)
	v.add_child(_tabs)
	var body := UI.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(UI.DRAG_CANCEL_PX)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_box = UI.vbox(10)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	preview = HeroPreview.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(s.x * 0.24, 0)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview)
	_refresh_preview()
	var names := ["Toko", "Kostum"] if mode == "toko" else ["Status", "Barang", "Kostum", "Koleksi", "Prestasi"]
	for n in names:
		var b := UI.button(n, show_tab.bind(n), Color("e8e2f2"), 22, 56)
		b.name = "Tab_" + n
		UI.expand(b)
		_tabs.add_child(b)
	show_tab(names[0])


func _sfx(n: String) -> void:
	if audio != null:
		audio.play(n)


func _refresh_preview() -> void:
	var shirt := Color("e05a4f")
	var hat := ""
	var acc := ""
	for c in rewards.owned_costumes(p):
		if not bool(c.worn):
			continue
		match str(c.slot):
			"outfit":
				shirt = Color.from_string(str(c.value), shirt)
			"hat":
				hat = str(c.value)
			"acc":
				acc = str(c.value)
	preview.set_look({"hero": str(p.profile.hero), "shirt": shirt, "hat": hat, "acc": acc})


func show_tab(name: String) -> void:
	tab = name
	UI.guard(250)
	_coins.text = "Koin %d" % int(p.rpg.coins)
	for b in _tabs.get_children():
		(b as Button).add_theme_stylebox_override("normal", UI.box(Color("ffd166") if (b as Button).text == name else Color("e8e2f2")))
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	match name:
		"Status":
			_status()
		"Barang":
			_items()
		"Kostum":
			_wardrobe()
		"Koleksi":
			_cards()
		"Prestasi":
			_achievements()
		"Toko":
			_shop()


func _row(left: Control, btn: Button = null, color := Color.WHITE) -> void:
	var row := UI.panel(color, 18)
	var h := UI.hbox(10)
	UI.expand(left)
	h.add_child(left)
	if btn != null:
		h.add_child(btn)
	row.add_child(h)
	_box.add_child(row)


func _two(a: String, b: String, ca := UI.INK) -> VBoxContainer:
	var v := UI.vbox(2)
	v.add_child(UI.label(a, 26, ca, false))
	if b != "":
		v.add_child(UI.label(b, 20, UI.SOFT))
	return v


func _status() -> void:
	var st: Dictionary = rewards.stats(p)
	_box.add_child(UI.label("%s · Kelas %d" % [str(p.profile.name), int(p.profile.grade)], 30, UI.PRIMARY, false))
	_box.add_child(UI.label("Level %d" % int(st.level), 40, UI.GOLD, false))
	var span := maxi(1, int(st.xp_next) - int(st.xp_from))
	_box.add_child(UI.progress(int(st.xp) - int(st.xp_from), span, UI.GOOD))
	_box.add_child(UI.label("XP %d / %d" % [int(st.xp), int(st.xp_next)], 22, UI.SOFT, false))
	for r in [["HP (nyawa)", st.hp, "Bertambah setiap naik level"], ["Serang", st.atk, "Kekuatan serangan fisik"],
			["Pertahanan", st.def, "Mengurangi serangan musuh"], ["Ilmu", st.ilmu, "Kekuatan jurus ilmu: bertambah dari materi dikuasai (%d) dan kartu (%d)" % [int(st.mastered), int(st.cards)]]]:
		_row(_two("%s: %d" % [str(r[0]), int(r[1])], str(r[2])))


func _items() -> void:
	var its: Dictionary = p.rpg.get("items", {})
	if its.is_empty():
		_box.add_child(UI.label("Tas masih kosong. Selesaikan misi atau belanja di toko desa!", 24, UI.SOFT))
	for id in its:
		var inf: Dictionary = rewards.info(str(id), quest_items)
		_row(_two("%s ×%d" % [str(inf.name), int(its[id])], str(inf.get("desc", ""))))


func _wardrobe() -> void:
	_box.add_child(UI.label("Ketuk kostum untuk memakai. Ketuk topi/aksesori yang sedang dipakai untuk melepas.", 22, UI.SOFT))
	for slot in [["outfit", "Baju"], ["hat", "Topi"], ["acc", "Aksesori"]]:
		var list: Array = rewards.owned_costumes(p).filter(func(c): return str(c.slot) == slot[0])
		if list.is_empty():
			continue
		_box.add_child(UI.label(str(slot[1]), 26, UI.PRIMARY, false))
		var g := UI.grid(3, 8)
		for c in list:
			var b := UI.button(("✓ " if bool(c.worn) else "") + str(c.name), _wear.bind(str(c.id)),
				Color("9ad8a6") if bool(c.worn) else Color("e8e2f2"), 22, 62)
			b.name = "Wear_" + str(c.id)
			UI.expand(b)
			g.add_child(b)
		_box.add_child(g)


func _wear(id: String) -> void:
	if rewards.equip(p, id):
		_sfx("klik")
		_refresh_preview()
		changed.emit()
		look_changed.emit()
	show_tab("Kostum")


func _cards() -> void:
	var cs: Array = p.learning.cards
	_box.add_child(UI.label("Kartu Pengetahuan: %d dari %d" % [cs.size(), rewards.cards_total()], 28, UI.PRIMARY, false))
	_box.add_child(UI.label("Dapatkan kartu dengan latihan sempurna (3 bintang) atau menguasai materi.", 20, UI.SOFT))
	if cs.is_empty():
		_box.add_child(UI.label("Belum ada kartu. Ayo belajar di Akademi Tunas!", 24, UI.SOFT))
	for t in cs:
		var c: Dictionary = rewards.card(str(t))
		if c.is_empty():
			continue
		_row(_two(str(c.get("title", "")), str(c.get("fact", "")), Color("1f4f8a")), null, Color("e8f4ff"))


func _achievements() -> void:
	var list: Array = rewards.achievements(p, ctx)
	var done := list.filter(func(a): return bool(a.done)).size()
	_box.add_child(UI.label("Prestasi: %d dari %d" % [done, list.size()], 28, UI.PRIMARY, false))
	for a in list:
		var left := _two(("★ " if bool(a.done) else "☆ ") + str(a.name), "%s  (%d/%d) · hadiah %d koin" % [str(a.desc), int(a.value), int(a.goal), int(a.coins)],
			UI.GOOD if bool(a.done) else UI.INK)
		_row(left, null, Color("eef9ee") if bool(a.done) else Color.WHITE)


func _shop() -> void:
	_box.add_child(UI.label(str(rewards.shop(shop_id).get("greet", "")).replace("{name}", str(p.profile.name)), 24, UI.INK))
	for e in rewards.stock(p, shop_id):
		var label := "Sudah punya" if bool(e.owned) else "%d koin" % int(e.price)
		var b := UI.button(label, _buy.bind(str(e.id)), Color("cfc8dc") if bool(e.owned) else UI.GOOD, 22, 60)
		b.name = "Buy_" + str(e.id)
		b.disabled = bool(e.owned)
		var extra := (" (punya %d)" % int(e.have)) if str(e.kind) == "item" and int(e.have) > 0 else ""
		_row(_two(str(e.name) + extra, str(e.desc)), b)


func _buy(id: String) -> void:
	var why: String = rewards.buy(p, shop_id, id)
	var msg := UI.label("", 24, UI.GOOD)
	if why == "":
		_sfx("bintang")
		changed.emit()
		show_tab("Toko")
		msg.text = "Terima kasih! %s masuk ke tasmu." % str(rewards.info(id).name)
	else:
		_sfx("salah")
		show_tab("Toko")
		msg.text = why
		msg.add_theme_color_override("font_color", UI.SOFT_BAD)
	msg.name = "ShopMsg"
	_box.add_child(msg)
	_box.move_child(msg, 0)


func back() -> bool:
	return false
