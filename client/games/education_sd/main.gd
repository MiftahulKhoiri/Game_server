extends Control
## Petualangan Ilmu — Dunia Enam Pulau (paket education_sd 3.x). RPG petualangan edukasi SD kelas 1–6.
## main.gd hanya mengatur layar: menu utama -> profil petualang -> peta enam pulau -> dunia 3D pulau.
## Aturan permainan ada di scripts/engine/ (bisa diuji tanpa layar). Rancangan: docs/SD_ENAM_PULAU.md.
## Kontrak platform: GameManager.load_progress / save_progress / restore_progress_from_server /
## exit_to_launcher dan platform_before_exit(). Mesin soal bersama (res://shared/edu) tidak diubah.

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const SdData := preload("res://games/education_sd/scripts/sd_data.gd")
const SdAudio := preload("res://games/education_sd/scripts/sd_audio.gd")
const SaveEngine := preload("res://games/education_sd/scripts/engine/save_engine.gd")
const WorldEngine := preload("res://games/education_sd/scripts/engine/world_engine.gd")
const NpcEngine := preload("res://games/education_sd/scripts/engine/npc_engine.gd")
const LearningEngine := preload("res://games/education_sd/scripts/engine/learning_engine.gd")
const AcademyScene := preload("res://games/education_sd/scripts/world/academy_scene.gd")
const LessonView := preload("res://games/education_sd/scripts/ui/lesson_view.gd")
const TitleScreen := preload("res://games/education_sd/scripts/ui/title_screen.gd")
const ProfileScreen := preload("res://games/education_sd/scripts/ui/profile_screen.gd")
const WorldMap := preload("res://games/education_sd/scripts/ui/world_map.gd")
const IslandScene := preload("res://games/education_sd/scripts/world/island_scene.gd")
const IslandWorld := preload("res://games/education_sd/scripts/world/w3d_world.gd")
const Hud3D := preload("res://games/education_sd/scripts/world/w3d_hud.gd")
const Rig3D := preload("res://games/education_sd/scripts/world/w3d_rig.gd")

const GAME_ID := "education_sd"
const VERSION := "3.2.0"
## Jejak langkah di HP: setiap layar/tombol ditulis ke berkas. Bila aplikasi tertutup paksa, jejak tidak
## berakhir dengan END; saat dibuka lagi 30 langkah terakhir ikut tersimpan di progres (p.crash).
const TRAIL_PATH := "user://education_sd_trail.txt"

var game_id := GAME_ID  # dibaca uji platform
var data := SdData.new()  # bank soal & toko (dipakai Learning Engine di tahap berikutnya)
var worlds := WorldEngine.new()
var npc := NpcEngine.new()  # isi pulau yang sedang dikunjungi (penduduk, tempat, papan)
var learning := LearningEngine.new()
var lesson: Control  # ruang kelas yang sedang terbuka di akademi (null bila tidak ada)
var rng := RandomNumberGenerator.new()
var p: Dictionary = {}
var audio: Node
var screen := ""
var current: Control  # layar yang sedang tampil
var world: Node3D  # dunia 3D pulau (null di layar lain)
var hud: Control
var _root: Control
var _toast: PanelContainer
var _toast_lbl: Label
var _modal: Control
var _exit_dialog: ConfirmationDialog
var _exit_noted := false
var _trail: FileAccess


# --- Siklus hidup ------------------------------------------------------------------------------------------

func _ready() -> void:
	get_tree().quit_on_go_back = false
	var bg := ColorRect.new()
	bg.color = UI.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = Control.new()
	_root.name = "Root"
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio = SdAudio.new()
	audio.name = "Audio"
	add_child(audio)
	_build_toast()
	rng.randomize()
	if not data.load_data() or not worlds.load_data() or not learning.setup(data):
		_show_error("Data game tidak bisa dimuat:\n" + "\n".join((data.errors + worlds.errors + learning.errors).slice(0, 5)))
		return
	_load_progress()
	_reset_safe_mode()
	_check_last_trail()
	_open_trail()
	_note_event("dibuka")
	_start_audio.call_deferred()
	show_title()
	if not SaveEngine.has_profile(p) and int(p.learning.totals.answered) == 0:
		_try_restore()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		trail("back Android")
		go_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		trail("PAUSE")
		save()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		trail("lanjut")
	elif what == NOTIFICATION_OS_MEMORY_WARNING:
		trail("peringatan memori")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		trail("END")
		if what == NOTIFICATION_PREDELETE:
			UI.on_press = Callable()


## Dipanggil GameManager sebelum kembali ke launcher.
func platform_before_exit() -> void:
	trail("keluar ke launcher END")
	if not _exit_noted:
		_note_exit("ditutup platform")
	save()
	if audio != null:
		audio.stop_all()


func _start_audio() -> void:
	audio.apply(bool(p.settings.music), bool(p.settings.sfx))


func _sfx(name: String) -> void:
	if audio != null:
		audio.play(name)


# --- Progres ---------------------------------------------------------------------------------------------------

func _gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _load_progress() -> void:
	var gm := _gm()
	var res: Dictionary = gm.load_progress(GAME_ID, SaveEngine.SCHEMA, SaveEngine.migrations()) if gm != null else {}
	p = SaveEngine.upgrade(res.get("data", {}))
	if int(p.migrated_from) == 2 and not bool(p.seen_intro.get("migrated", false)):
		trail("progres lama dipindahkan ke 3.x")


func _try_restore() -> void:
	var gm := _gm()
	if gm == null:
		return
	var restored: Dictionary = await gm.restore_progress_from_server(GAME_ID, SaveEngine.SCHEMA)
	if restored.is_empty() or not is_inside_tree():
		return
	p = SaveEngine.upgrade(restored)
	save()
	toast("Progres petualanganmu dipulihkan dari server.")
	if screen == "title":
		show_title()


func save() -> void:
	if p.is_empty():
		return
	var gm := _gm()
	if gm != null:
		gm.save_progress(GAME_ID, p, SaveEngine.SCHEMA)


func grade() -> int:
	return int(p.profile.grade)


func level() -> int:
	return SaveEngine.level(p)


# --- Kerangka layar --------------------------------------------------------------------------------------------

func _clear(id: String) -> void:
	if screen in ["island", "academy"] and not id in ["island", "academy"] and audio != null:
		audio.ambient(false)
	lesson = null
	screen = id
	trail("layar " + id)
	UI.guard(350)
	close_modal()
	current = null
	world = null
	hud = null
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()


func _show(id: String, node: Control) -> void:
	_clear(id)
	node.name = id.capitalize().replace(" ", "")
	current = node
	_root.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Tombol kembali Android / tombol Kembali di layar.
func go_back() -> void:
	_sfx("klik")
	if _modal != null:
		close_modal()
		return
	if lesson != null and is_instance_valid(lesson):
		if not lesson.back():
			close_class()
		return
	match screen:
		"error":
			_exit_to_launcher("kembali dari layar galat")
		"title":
			_confirm_exit("back Android di menu utama")
		"profile":
			if SaveEngine.has_profile(p):
				show_title()
			else:
				show_title()
		"settings", "map":
			show_title()
		"island":
			leave_island()
		"academy":
			leave_academy()
		_:
			show_title()


func _confirm_exit(source: String) -> void:
	if _exit_dialog != null and is_instance_valid(_exit_dialog) and _exit_dialog.visible:
		return
	if _exit_dialog != null and is_instance_valid(_exit_dialog):
		_exit_dialog.queue_free()
	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.dialog_text = "Kembali ke daftar game?\nPetualanganmu sudah tersimpan."
	_exit_dialog.ok_button_text = "Ya, kembali"
	_exit_dialog.cancel_button_text = "Tetap bermain"
	add_child(_exit_dialog)
	_exit_dialog.confirmed.connect(_exit_to_launcher.bind(source + " (dikonfirmasi)"))
	_exit_dialog.popup_centered(Vector2i(640, 220))


func _exit_to_launcher(reason: String = "tombol keluar") -> void:
	_note_exit(reason)
	save()
	var gm := _gm()
	if gm != null:
		gm.exit_to_launcher()
	else:
		get_tree().quit()


func _show_error(text: String) -> void:
	_clear("error")
	var v := UI.vbox(16)
	v.name = "Error"
	_root.add_child(v)
	v.position = Vector2(40, 40)
	v.add_child(UI.label(text, 28, UI.SOFT_BAD))
	v.add_child(UI.button("Kembali ke daftar game", _exit_to_launcher, UI.PRIMARY))


## Panel di tengah layar (cerita, pesan). buttons: [[teks, Callable, warna], ...]
func modal(title: String, text: String, buttons: Array) -> void:
	close_modal()
	var shade := ColorRect.new()
	shade.name = "Modal"
	shade.color = Color(0, 0, 0, 0.45)
	shade.z_index = 5
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := UI.panel(Color("fdf6e3"), 28)
	var v := UI.vbox(14)
	v.add_child(UI.label(title, 36, UI.PRIMARY))
	var body := UI.label(text, 26, UI.INK)
	body.name = "Body"
	v.add_child(body)
	var row := UI.hbox(12)
	for b in buttons:
		var cb: Callable = b[1]
		var btn := UI.button(str(b[0]), func() -> void:
			close_modal()
			cb.call(), b[2] if b.size() > 2 else UI.GOOD, 28, 80)
		btn.name = "ModalBtn"
		UI.expand(btn)
		row.add_child(btn)
	v.add_child(row)
	panel.add_child(v)
	shade.add_child(panel)
	panel.custom_minimum_size = Vector2(760, 0)
	body.custom_minimum_size = Vector2(700, 0)
	panel.position = Vector2((get_viewport_rect().size.x - 760) / 2.0, get_viewport_rect().size.y * 0.16)
	panel.reset_size.call_deferred()
	_modal = shade


func close_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null


func modal_open() -> bool:
	return _modal != null and is_instance_valid(_modal)


# --- Menu utama ---------------------------------------------------------------------------------------------------

func show_title() -> void:
	var t := TitleScreen.new()
	_show("title", t)
	t.setup({"has_profile": SaveEngine.has_profile(p), "name": p.profile.name, "level": level(),
		"coins": int(p.rpg.coins), "version": VERSION}, worlds.islands)
	t.start_pressed.connect(func() -> void:
		_sfx("klik")
		show_profile())
	t.continue_pressed.connect(func() -> void:
		_sfx("klik")
		show_map())
	t.profile_pressed.connect(func() -> void:
		_sfx("klik")
		show_profile())
	t.settings_pressed.connect(func() -> void:
		_sfx("klik")
		show_settings())
	t.exit_pressed.connect(func() -> void: _confirm_exit("tombol keluar di menu utama"))
	if int(p.migrated_from) == 2 and SaveEngine.has_profile(p) and not bool(p.seen_intro.get("migrated", false)):
		p.seen_intro["migrated"] = true
		save()
		modal("Petualangan Baru!", "Halo %s! Pulau Ilmu sudah berubah menjadi Dunia Enam Pulau.\nKoin, kostum, dan catatan belajarmu ikut terbawa. Ayo berlayar!" % str(p.profile.name),
			[["Ayo!", func() -> void: pass]])


# --- Profil petualang -----------------------------------------------------------------------------------------------

func show_profile() -> void:
	var first := not SaveEngine.has_profile(p)
	var ps := ProfileScreen.new()
	_show("profile", ps)
	ps.setup(p.profile, data.doc.get("shop", []), p.rpg.owned, first)
	ps.back_pressed.connect(go_back)
	ps.message.connect(toast)
	ps.saved.connect(func(prof: Dictionary) -> void: set_profile(prof))


## Simpan profil (nama, kelas, pahlawan, baju). Petualang baru: cerita pembuka lalu peta.
func set_profile(prof: Dictionary) -> void:
	var first := not SaveEngine.has_profile(p)
	var grade_changed := int(prof.get("grade", 1)) != int(p.profile.grade)
	for k in ["name", "grade", "hero", "outfit", "hat", "acc"]:
		if prof.has(k):
			p.profile[k] = prof[k]
	if str(p.profile.created) == "":
		p.profile.created = Time.get_datetime_string_from_system(false, true)
	p = SaveEngine.ensure(p)
	if first or grade_changed:
		p.world.island = worlds.start_island(p)
	save()
	_sfx("bintang")
	if first or not bool(p.seen_intro.get("story", false)):
		show_story()
	else:
		toast("Profil tersimpan.")
		show_title()


func show_story() -> void:
	show_map()
	p.seen_intro["story"] = true
	save()
	modal("Kabut Lupa!", str(worlds.doc.get("story", "")) + "\n\nPerahumu siap di %s. Ketuk pulaunya lalu tekan Masuk pulau." %
		str(worlds.island(str(p.world.island)).get("name", "")), [["Ayo berangkat!", func() -> void: pass]])


# --- Pengaturan ------------------------------------------------------------------------------------------------

func show_settings() -> void:
	var page := Control.new()
	_show("settings", page)
	var v := UI.vbox(14)
	v.name = "Page"
	page.add_child(v)
	v.position = Vector2(60, 30)
	v.custom_minimum_size = Vector2(get_viewport_rect().size.x - 120, 0)
	var h := UI.hbox(12)
	h.add_child(UI.button("Kembali", go_back, Color("cfc8dc"), 24, 64))
	h.add_child(UI.label("Pengaturan", 38, UI.PRIMARY, false))
	v.add_child(h)
	var rows := [
		["Musik", "music", [true, false], {true: "Nyala", false: "Mati"}],
		["Efek suara", "sfx", [true, false], {true: "Nyala", false: "Mati"}],
		["Grafis dunia 3D", "gfx", ["hemat", "seimbang", "tinggi"], {"hemat": "Hemat (HP lama)", "seimbang": "Seimbang", "tinggi": "Tinggi"}],
		["Tampilkan FPS", "perf", [true, false], {true: "Nyala", false: "Mati"}],
	]
	for r in rows:
		var row := UI.hbox(12)
		var lbl := UI.label(str(r[0]), 28, UI.INK, false)
		lbl.custom_minimum_size.x = 320
		row.add_child(lbl)
		for opt in r[2]:
			var on: bool = p.settings[r[1]] == opt
			var key: String = r[1]
			var b := UI.button(str(r[3][opt]), func() -> void:
				p.settings[key] = opt
				save()
				_start_audio()
				show_settings(), Color("ffd166") if on else Color("e8e2f2"), 24, 66)
			b.name = "%s_%s" % [key, str(opt)]
			UI.expand(b)
			row.add_child(b)
		v.add_child(row)


# --- Peta dunia enam pulau --------------------------------------------------------------------------------------

func show_map() -> void:
	var m := WorldMap.new()
	_show("map", m)
	m.setup(worlds, p, "%s · Lv %d · Koin %d" % [str(p.profile.name), level(), int(p.rpg.coins)])
	m.back_pressed.connect(go_back)
	m.island_selected.connect(func(_id: String) -> void: _sfx("klik"))
	m.sailed.connect(arrive)


## Tiba di pulau setelah berlayar di peta.
func arrive(id: String) -> void:
	var why: String = worlds.travel(p, id)
	if why != "":
		toast(why)
		return
	save()
	show_island(id)


# --- Dunia 3D pulau ------------------------------------------------------------------------------------------------

func hero_look() -> Dictionary:
	var shirt := Color("e05a4f")
	var hat := ""
	var acc := ""
	for s in data.doc.get("shop", []):
		var sid := str(s.id)
		if sid == str(p.profile.outfit):
			shirt = Color.from_string(str(s.value), shirt)
		elif sid == str(p.profile.hat):
			hat = str(s.value)
		elif sid == str(p.profile.acc):
			acc = str(s.value)
	var kind := "female" if str(p.profile.hero) == "perempuan" else "male"
	var path: String = Rig3D.hero_path(kind)
	return {"shirt": shirt, "long_hair": kind == "female", "hat": hat, "acc": acc,
		"model_path": path if ResourceLoader.exists(path) else ""}


## Wadah 3D bersama untuk pulau & akademi: SubViewport + adegan + HUD.
func _make_3d(id: String, scene: Node3D, ctx: Dictionary, title: String, color: Color) -> void:
	var box := SubViewportContainer.new()
	_show(id, box)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prof: Dictionary = IslandWorld.PROFILES.get(str(p.settings.gfx), IslandWorld.PROFILES.seimbang)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.scaling_3d_scale = float(prof.scale)
	vp.msaa_3d = Viewport.MSAA_2X if bool(prof.msaa) else Viewport.MSAA_DISABLED
	vp.handle_input_locally = false
	box.add_child(vp)
	world = scene
	world.name = "World"
	vp.add_child(world)
	world.build(ctx)
	hud = Hud3D.new()
	hud.name = "Hud"
	_root.add_child(hud)
	hud.setup(world, title, color)
	hud.back_pressed.connect(go_back)
	hud.bag_pressed.connect(show_bag)
	hud.set_perf(bool(p.settings.perf))
	if audio != null:
		audio.ambient(true)


## at: "" (dermaga) atau "academy" (keluar dari pintu akademi).
func show_island(id: String, at := "") -> void:
	var isl := worlds.island(id)
	if isl.is_empty() or worlds.status(id, p) != "open":
		show_map()
		return
	var layout := {}
	if str(isl.get("layout", "")) != "":
		if npc.load_layout(str(isl.layout)):
			layout = npc.layout
		else:
			trail("tata letak pulau gagal: " + ", ".join(npc.errors.slice(0, 3)))
	_make_3d("island", IslandScene.new(), {"island": isl, "layout": layout, "npc_engine": npc if not layout.is_empty() else null,
		"gfx": str(p.settings.gfx), "hero": hero_look()}, "Pulau %d · %s" % [int(isl.number), str(isl.name)],
		Color.from_string(str(isl.color), UI.PRIMARY))
	world.interacted.connect(_on_island_interact)
	world.place_changed.connect(_on_place)
	hud.missions_pressed.connect(show_explore)
	hud.set_hint("Selamat datang di %s! Jelajahi pulau dan sapa penduduknya. Perahu di dermaga membawamu kembali ke peta." % str(isl.name))
	if at == "academy" and layout.has("academy_door"):
		var d: Array = layout.academy_door
		world.player.place(Vector3(float(d[0]), world.ground_y(float(d[0]), float(d[1]) + 2.0) + 0.3, float(d[1]) + 2.0), PI)
		hud.set_hint("Akademi Tunas. Kembali kapan saja untuk belajar lagi!")
	trail("pulau %s grafis %s" % [id, str(p.settings.gfx)])


func show_bag() -> void:
	if hud == null:
		return
	var lv := level()
	var t: Dictionary = p.learning.totals
	hud.show_dialog("Tas Petualang", "Level %d  (XP %d / %d)\nKoin: %d\nJawaban benar: %d dari %d" % [lv, int(p.rpg.xp),
		SaveEngine.xp_for(lv + 1), int(p.rpg.coins), int(t.correct), int(t.answered)])


# --- Akademi (Tahap 3) ------------------------------------------------------------------------------------------

func enter_academy() -> void:
	_sfx("buka")
	_make_3d("academy", AcademyScene.new(), {"gfx": str(p.settings.gfx), "hero": hero_look()}, "Akademi Tunas", Color("b5443a"))
	world.interacted.connect(_on_academy_interact)
	hud.missions_pressed.connect(show_report)
	hud.set_hint("Selamat datang di Akademi Tunas! Datangi guru di setiap ruang kelas untuk belajar.")
	trail("akademi")


func leave_academy() -> void:
	save()
	show_island(str(p.world.island), "academy")


func _on_academy_interact(kind: String, id: String) -> void:
	trail("akademi %s/%s" % [kind, id])
	_sfx("klik")
	match kind:
		"teacher":
			open_class(id)
		"closed":
			var r := LearningEngine.room(id)
			hud.show_dialog(str(r.get("name", "")), "Ruang %s segera dibuka. Sementara itu, belajarlah di ruang lain dulu, ya!" % str(r.get("name", "")))
		"exit":
			leave_academy()


func open_class(room_id: String) -> void:
	if hud == null or world == null:
		return
	hud.visible = false
	world.player.frozen = true
	world.player.move_input = Vector2.ZERO
	lesson = LessonView.new()
	lesson.name = "Lesson"
	_root.add_child(lesson)
	lesson.setup(learning, p, rng, audio, data.doc.get("type_names", {}), room_id)
	lesson.closed.connect(close_class)
	lesson.changed.connect(save)
	trail("kelas " + room_id)


func close_class() -> void:
	if lesson != null and is_instance_valid(lesson):
		lesson.queue_free()
	lesson = null
	save()
	if hud != null:
		hud.visible = true
	if world != null:
		world.player.frozen = false
		world.end_talk()


## Rapor kecil (tombol MISI di akademi): bintang & materi dikuasai per ruang kelas.
func show_report() -> void:
	var sm: Dictionary = learning.room_summary(p, grade())
	var rows: Array = ["Kelas %d — %s" % [grade(), str(p.profile.name)], ""]
	for r in LearningEngine.ROOMS:
		if not sm.has(str(r.id)):
			continue
		var e: Dictionary = sm[str(r.id)]
		rows.append("%s: %d/%d bintang, %d dari %d materi dikuasai" % [str(r.name), int(e.stars), int(e.max), int(e.mastered), int(e.topics)])
	rows.append("")
	rows.append("Materi dikuasai bila banyak jawaban terakhir benar sejak percobaan pertama.")
	hud.show_list("Rapor Belajar", rows)


func _on_island_interact(kind: String, id: String) -> void:
	trail("aksi %s/%s" % [kind, id])
	_sfx("klik")
	var isl := worlds.island(str(p.world.island))
	match kind:
		"dock":
			hud.show_dialog("Perahu", "Mau berlayar ke pulau lain?", [["Buka Peta Dunia", leave_island, UI.PRIMARY]])
		"sign":
			if npc.places.has(id):
				_discover(id)
				var pl: Dictionary = npc.places[id]
				hud.show_dialog(str(pl.name), "Kamu berada di %s, %s." % [str(pl.name), str(isl.name)])
			else:
				hud.show_dialog("Pulau %d — %s" % [int(isl.number), str(isl.name)],
					str(isl.intro) + "\n\nTempat di pulau ini: " + ", ".join(isl.get("places", [])))
		"npc":
			talk(id)
		"academy":
			enter_academy()
		"gate", "boulder":
			var sg: Dictionary = npc.layout.get("signs", {}).get(kind, {})
			hud.show_dialog(str(sg.get("title", "")), str(sg.get("text", "")))


## Percakapan dengan penduduk: satu kalimat per halaman, tombol Lanjut sampai habis.
func talk(id: String) -> void:
	var d: Dictionary = npc.talk(p, str(p.world.island), id)
	if d.is_empty():
		return
	save()
	_talk_page(id, d, 0)


func _talk_page(id: String, d: Dictionary, i: int) -> void:
	if hud == null or world == null:
		return
	world.hold_talk(id)
	var lines: Array = d.lines
	var title := "%s · %s" % [str(d.name), str(d.role)]
	if i < lines.size() - 1:
		hud.show_dialog(title, str(lines[i]), [["Lanjut", _talk_page.bind(id, d, i + 1), UI.PRIMARY]])
	else:
		hud.show_dialog(title, str(lines[i]))


func _on_place(id: String) -> void:
	if id == "" or hud == null:
		return
	var pl: Dictionary = npc.places.get(id, {})
	hud.set_hint("Tempat: %s" % str(pl.get("name", "")))
	if _discover(id):
		toast("Tempat baru ditemukan: %s!" % str(pl.get("name", "")))
		_sfx("bintang")


func _discover(id: String) -> bool:
	var fresh: bool = npc.discover(p, str(p.world.island), id)
	if fresh:
		trail("temukan " + id)
		save()
	return fresh


## Catatan jelajah pulau (tombol MISI): tempat yang sudah ditemukan dan penduduk yang sudah dikenal.
func show_explore() -> void:
	var iid := str(p.world.island)
	var rows: Array = []
	if npc.places.is_empty():
		rows.append("Pulau ini masih sepi. Jelajahi pantainya!")
	else:
		rows.append("TEMPAT (%d/%d)" % [npc.found_count(p, iid), npc.places.size()])
		for pid in npc.places:
			var got := (p.world.found as Dictionary).has(iid + "/" + pid)
			rows.append(("  ✓ " if got else "  ? ") + (str(npc.places[pid].name) if got else "belum ditemukan"))
		rows.append("")
		rows.append("PENDUDUK (%d/%d)" % [npc.met_count(p, iid), npc.npcs.size()])
		for nid in npc.npcs:
			var met := (p.world.met as Dictionary).has(iid + "/" + nid)
			var n: Dictionary = npc.npcs[nid]
			rows.append(("  ✓ %s (%s)" % [str(n.name), str(n.role)]) if met else "  ? belum dikenal")
	hud.show_list("Jelajah %s" % str(worlds.island(iid).get("name", "")), rows)


func leave_island() -> void:
	save()
	show_map()


# --- Pesan singkat ------------------------------------------------------------------------------------------------

func _build_toast() -> void:
	_toast = UI.panel(Color("2b2440"), 30)
	_toast_lbl = UI.label("", 24, Color.WHITE)
	_toast.add_child(_toast_lbl)
	_toast.visible = false
	_toast.z_index = 10
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -120
	_toast.offset_bottom = -30
	_toast.offset_left = -360
	_toast.offset_right = 360


func toast(text: String) -> void:
	_toast_lbl.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	move_child(_toast, get_child_count() - 1)
	var tw := _toast.create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: _toast.visible = false)


# --- Diagnosis (jejak langkah & mode aman) ---------------------------------------------------------------------

func _note_exit(reason: String) -> void:
	_note_event(reason)
	_exit_noted = true


func _note_event(reason: String) -> void:
	if p.is_empty():
		return
	var diag: Array = p.get("diag", [])
	diag.append({"at": Time.get_datetime_string_from_system(false, true), "reason": reason, "screen": screen, "ver": VERSION})
	p["diag"] = diag.slice(-10)


func _reset_safe_mode() -> void:
	if int(p.get("safe_level", 0)) > 0 and str(p.get("safe_reset", "")) != VERSION:
		p["safe_level"] = 0
		p["safe_reset"] = VERSION
		p.settings.music = true
		save()


func _check_last_trail() -> void:
	if not FileAccess.file_exists(TRAIL_PATH):
		return
	var lines := FileAccess.get_file_as_string(TRAIL_PATH).strip_edges().split("\n")
	if lines.is_empty() or lines[-1].ends_with(" END") or lines[-1].ends_with(" PAUSE"):
		return
	var tail := Array(lines.slice(-30))
	var lvl := mini(int(p.get("safe_level", 0)) + 1, 2)
	p["safe_level"] = lvl
	p.settings.music = false
	p["crash"] = {"found_at": Time.get_datetime_string_from_system(false, true), "kind": "crash", "trail": tail,
		"safe_level": lvl}
	_note_event("tertutup tidak normal, langkah terakhir: %s; mode aman %d" % [str(tail[-1]), lvl])
	save()


func _open_trail() -> void:
	_trail = FileAccess.open(TRAIL_PATH, FileAccess.WRITE)
	UI.on_press = func(text: String) -> void: trail("tombol " + text)
	trail("BUKA v%s | %s | Android %s | %s | layar %s | mode aman %d" % [VERSION, OS.get_model_name(), OS.get_version(),
		RenderingServer.get_video_adapter_name(), str(get_viewport().get_visible_rect().size), int(p.get("safe_level", 0))])


func trail(text: String) -> void:
	if _trail == null:
		return
	_trail.store_line("%s %s" % [Time.get_time_string_from_system(), text])
	_trail.flush()
