extends Control
## Menu utama Petualangan Ilmu: laut dan enam pulau di cakrawala, perahu berlayar, judul besar.
## Petualang baru: "Mulai Petualangan". Petualang lama: "Lanjutkan Petualangan" + Ganti Petualang.

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const Art := preload("res://games/education_sd/scripts/ui/sea_art.gd")

signal start_pressed
signal continue_pressed
signal profile_pressed
signal settings_pressed
signal exit_pressed
signal report_pressed

var _t := 0.0
var islands: Array = []
var _box: VBoxContainer


## info: {has_profile, name, level, coins, version}
func setup(info: Dictionary, island_list: Array) -> void:
	islands = island_list
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box = UI.vbox(14)
	_box.name = "Menu"
	add_child(_box)
	if bool(info.get("has_profile", false)):
		var c := UI.button("Lanjutkan Petualangan", func() -> void: continue_pressed.emit(), UI.GOOD, 34, 92)
		c.name = "Continue"
		_box.add_child(c)
		var who := UI.panel(Color(1, 1, 1, 0.85), 18)
		who.add_child(UI.label("%s · Level %d · Koin %d" % [str(info.name), int(info.level), int(info.coins)], 22, UI.INK, false))
		_box.add_child(who)
		var row := UI.hbox(12)
		var pb := UI.button("Ganti Petualang", func() -> void: profile_pressed.emit(), Color("ffd166"), 24, 70)
		pb.name = "Profile"
		UI.expand(pb)
		row.add_child(pb)
		var sb := UI.button("Pengaturan", func() -> void: settings_pressed.emit(), Color("cfc8dc"), 24, 70)
		sb.name = "Settings"
		UI.expand(sb)
		row.add_child(sb)
		_box.add_child(row)
		var rb := UI.button("Laporan Belajar (orang tua & guru)", func() -> void: report_pressed.emit(), Color("e8f4ff"), 22, 60)
		rb.name = "Report"
		_box.add_child(rb)
	else:
		var s := UI.button("Mulai Petualangan", func() -> void: start_pressed.emit(), UI.GOOD, 36, 100)
		s.name = "Start"
		_box.add_child(s)
		var sb2 := UI.button("Pengaturan", func() -> void: settings_pressed.emit(), Color("cfc8dc"), 24, 70)
		sb2.name = "Settings"
		_box.add_child(sb2)
	var ex := UI.button("Keluar ke daftar game", func() -> void: exit_pressed.emit(), Color("e8e2f2"), 22, 60)
	ex.name = "Exit"
	_box.add_child(ex)
	var ver := UI.label("versi " + str(info.get("version", "")), 18, Color(1, 1, 1, 0.8), false)
	ver.name = "Version"
	add_child(ver)
	resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	var w := clampf(size.x * 0.36, 380.0, 560.0)
	_box.custom_minimum_size = Vector2(w, 0)
	_box.size = Vector2(w, 0)
	_box.position = Vector2((size.x - w) / 2.0, size.y * 0.36)
	var ver: Control = get_node("Version")
	ver.position = Vector2(16, size.y - 34)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var sea_y := size.y * 0.5
	Art.sky(self, Rect2(0, 0, size.x, sea_y), Color("6cc3ff"), Color("e3f6ff"))
	draw_circle(Vector2(size.x * 0.82, size.y * 0.16), 54.0, Color("ffe08a"))
	draw_circle(Vector2(size.x * 0.82, size.y * 0.16), 70.0, Color(1, 0.9, 0.5, 0.25))
	Art.cloud(self, Vector2(size.x * 0.18 + fmod(_t * 8.0, size.x * 0.3), size.y * 0.14), 1.1)
	Art.cloud(self, Vector2(size.x * 0.55 + fmod(_t * 5.0, size.x * 0.2), size.y * 0.24), 0.8)
	var sea := Rect2(0, sea_y, size.x, size.y - sea_y)
	Art.sky(self, sea, Color("3aa0e0"), Color("1d5f9e"))
	Art.waves(self, sea, _t)
	for i in islands.size():
		var isl: Dictionary = islands[i]
		var x := size.x * (0.08 + 0.168 * i)
		var r := 38.0 + (i % 3) * 7.0
		Art.island(self, Vector2(x, size.y * (0.88 + (i % 2) * 0.04)), r, Color.from_string(str(isl.color), Color.GREEN),
			Color.from_string(str(isl.get("sand", "#f3dfa2")), Color.WHEAT), 100 + i * 17)
	var bx := fmod(_t * 40.0, size.x + 200.0) - 100.0
	Art.boat(self, Vector2(bx, size.y * 0.62 + sin(_t * 2.0) * 4.0), 1.4)
	var f := ThemeDB.fallback_font
	var title := "Petualangan Ilmu"
	var fs := int(clampf(size.x * 0.06, 54.0, 96.0))
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2((size.x - tw) / 2.0, size.y * 0.2)
	draw_string_outline(f, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color("2b2440"))
	draw_string(f, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffd166"))
	var sub := "Dunia Enam Pulau"
	var ss := int(fs * 0.45)
	var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	var sp := Vector2((size.x - sw) / 2.0, size.y * 0.2 + ss * 1.6)
	draw_string_outline(f, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, 10, Color("2b2440"))
	draw_string(f, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color.WHITE)
