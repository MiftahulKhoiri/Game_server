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
const QuestEngine := preload("res://games/education_sd/scripts/engine/quest_engine.gd")
const ChallengeView := preload("res://games/education_sd/scripts/ui/challenge_view.gd")
const RewardEngine := preload("res://games/education_sd/scripts/engine/reward_engine.gd")
const BagView := preload("res://games/education_sd/scripts/ui/bag_view.gd")
const BattleView := preload("res://games/education_sd/scripts/ui/battle_view.gd")
const ReportView := preload("res://games/education_sd/scripts/ui/report_view.gd")
const TitleScreen := preload("res://games/education_sd/scripts/ui/title_screen.gd")
const ProfileScreen := preload("res://games/education_sd/scripts/ui/profile_screen.gd")
const WorldMap := preload("res://games/education_sd/scripts/ui/world_map.gd")
const IslandScene := preload("res://games/education_sd/scripts/world/island_scene.gd")
const IslandWorld := preload("res://games/education_sd/scripts/world/w3d_world.gd")
const Hud3D := preload("res://games/education_sd/scripts/world/w3d_hud.gd")
const Rig3D := preload("res://games/education_sd/scripts/world/w3d_rig.gd")

const GAME_ID := "education_sd"
const VERSION := "3.6.0"
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
var quest := QuestEngine.new()  # misi pulau yang sedang dikunjungi
var _obj_t := 0.0
var rewards := RewardEngine.new()
var _toast_queue: Array = []
var _chip_lbl: Label
var monsters: Dictionary = {}  # data/monstersN.json pulau yang sedang dikunjungi
var battle_seed := -1  # uji: pertarungan dengan acak tetap
var foes_calm := 0.0  # uji: musuh diam selama n detik setelah pulau dibangun
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
	if not data.load_data() or not worlds.load_data() or not learning.setup(data) or not rewards.setup(data):
		_show_error("Data game tidak bisa dimuat:\n" + "\n".join((data.errors + worlds.errors + learning.errors + rewards.errors).slice(0, 5)))
		return
	_load_progress()
	rewards.level_check(p)  # catat level sekarang (tanpa hadiah) untuk deteksi naik level berikutnya
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
		"settings", "map", "report":
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
	t.report_pressed.connect(func() -> void:
		_sfx("klik")
		show_report_screen())
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
	_chip_lbl = null
	_update_chip()
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
	quest = QuestEngine.new()
	if str(isl.get("quests", "")) != "" and not quest.load_quests(str(isl.quests)):
		trail("misi pulau gagal: " + ", ".join(quest.errors.slice(0, 3)))
	QuestEngine._ensure(p)
	monsters = {}
	if str(isl.get("monsters", "")) != "":
		var mv = JSON.parse_string(FileAccess.get_file_as_string("res://games/education_sd/data/" + str(isl.monsters)))
		if typeof(mv) == TYPE_DICTIONARY:
			monsters = mv
	_make_3d("island", IslandScene.new(), {"island": isl, "layout": layout, "npc_engine": npc if not layout.is_empty() else null,
		"gfx": str(p.settings.gfx), "hero": hero_look(), "flags": p.world.flags, "pickups": quest.pickups(p, true),
		"quest_spots": quest.doc.get("spots", []), "foes": _foe_list()}, "Pulau %d · %s" % [int(isl.number), str(isl.name)],
		Color.from_string(str(isl.color), UI.PRIMARY))
	world.interacted.connect(_on_island_interact)
	world.place_changed.connect(_on_place)
	if foes_calm > 0.0:
		world.calm_foes(foes_calm)
	hud.missions_pressed.connect(show_explore)
	hud.set_hint("Selamat datang di %s! Jelajahi pulau dan sapa penduduknya. Perahu di dermaga membawamu kembali ke peta." % str(isl.name))
	_show_notes(quest.start_auto(p, _qctx()))
	_refresh_quest_ui()
	if at == "academy" and layout.has("academy_door"):
		var d: Array = layout.academy_door
		world.player.place(Vector3(float(d[0]), world.ground_y(float(d[0]), float(d[1]) + 2.0) + 0.3, float(d[1]) + 2.0), PI)
		hud.set_hint("Akademi Tunas. Kembali kapan saja untuk belajar lagi!")
	trail("pulau %s grafis %s" % [id, str(p.settings.gfx)])


func show_bag() -> void:
	_open_bag("tas")


func open_shop(shop_id: String) -> void:
	_open_bag("toko", shop_id)


## Tas Petualang / Toko di atas dunia 3D.
func _open_bag(mode: String, shop_id := "") -> void:
	if hud == null or world == null:
		return
	hud.close_dialog()
	hud.visible = false
	world.player.frozen = true
	world.player.move_input = Vector2.ZERO
	lesson = BagView.new()
	lesson.name = "Bag"
	_root.add_child(lesson)
	lesson.setup(rewards, p, quest.items, _rctx(), audio, mode, shop_id)
	lesson.closed.connect(close_class)
	lesson.changed.connect(func() -> void:
		_progress()
		save())
	lesson.look_changed.connect(func() -> void:
		if world != null and world.player != null:
			world.player.set_look(hero_look()))
	trail(("toko " + shop_id) if mode == "toko" else "tas")


func _rctx() -> Dictionary:
	return {"main_quests": quest.done_count(p, "main")}


## Setelah progres berubah: naik level & prestasi (pesan singkat berurutan).
func _progress() -> void:
	var notes: Array = rewards.after(p, _rctx())
	for n in notes:
		if str(n.kind) == "level":
			_sfx("bintang")
			toast("%s  %s" % [str(n.text), str(n.detail)])
		else:
			toast(str(n.text))
	if not notes.is_empty():
		save()
	_update_chip()


func _update_chip() -> void:
	if hud == null:
		return
	if _chip_lbl == null or not is_instance_valid(_chip_lbl):
		var c := UI.panel(Color("ffd166"), 18)
		c.name = "LevelChip"
		_chip_lbl = UI.label("", 22, UI.INK, false)
		c.add_child(_chip_lbl)
		hud.chips.add_child(c)
	_chip_lbl.text = "Lv %d · Koin %d" % [level(), int(p.rpg.coins)]


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
	lesson.exam_done.connect(func(_r: Dictionary) -> void:
		_progress()
		save())
	lesson.session_done.connect(func(r: Dictionary) -> void:
		for n in rewards.on_session(p, str(lesson.topic_id), r):
			toast(str(n.text))
		for n in quest.event(p, "learn", "", _qctx()):
			if str(n.kind) in ["step", "done", "start"]:
				toast(str(n.text))
		_progress()
		save())
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


## Laporan Belajar di akademi (tombol MISI), di atas dunia 3D.
func show_report() -> void:
	if hud == null or world == null:
		return
	hud.close_dialog()
	hud.visible = false
	world.player.frozen = true
	lesson = ReportView.new()
	lesson.name = "Report"
	_root.add_child(lesson)
	lesson.setup(learning.report(p))
	lesson.closed.connect(close_class)


## Laporan Belajar dari menu utama (untuk orang tua & guru).
func show_report_screen() -> void:
	var rv := ReportView.new()
	_show("report", rv)
	rv.setup(learning.report(p))
	rv.closed.connect(show_title)


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
		"pickup":
			_sfx("bintang")
			_show_notes(quest.event(p, "pickup", id, _qctx()))
		"clue", "boulder":
			var sa: Dictionary = quest.step_at(p, "", id if kind == "clue" else "boulder")
			if not sa.is_empty():
				open_challenge(str(sa.step.challenge))
			elif kind == "clue":
				hud.show_dialog("Batu Bertulis", "Huruf-huruf di batu tua ini bersinar samar. Sepertinya menyimpan petunjuk.")
			else:
				var sg: Dictionary = npc.layout.get("signs", {}).get("boulder", {})
				hud.show_dialog(str(sg.get("title", "")), str(sg.get("text", "")))
		"gate":
			if world.gate_open():
				hud.show_dialog("Gerbang Benteng", "Gerbang sudah terbuka. Raja Goblin Kecil menunggu di dalam.")
				return
			var sg2: Dictionary = quest.step_at(p, "", "gate")
			if not sg2.is_empty() and quest.count_item(p, str(sg2.step.get("item", ""))) > 0:
				var notes := quest.event(p, "use", "gate", _qctx())
				world.open_gate()
				_sfx("buka")
				_show_notes(notes)
			elif quest.count_item(p, "kunci_benteng") > 0:
				hud.show_dialog("Gerbang Benteng", "Kuncinya terlihat cocok... Tanyakan dulu pada Kak Laras, penjaga jembatan.")
			else:
				var sg: Dictionary = npc.layout.get("signs", {}).get("gate", {})
				hud.show_dialog(str(sg.get("title", "")), str(sg.get("text", "")))
		"boss":
			var bm: Dictionary = monsters.get("monsters", {}).get("raja_goblin", {})
			hud.show_dialog(str(bm.get("name", "Raja Goblin")), "\"%s\"\n\nPerisai Mahkota hanya bisa ditembus Jurus Ilmu. Siapkan Kue Manis dan Ramuan Ilmu!" % str(bm.get("taunt", "")),
				[["Bertarung!", start_battle.bind("raja_goblin", "boss"), Color("e05a4f")]])
		"foe":
			var fe: Dictionary = world.foe(id)
			if not fe.is_empty():
				start_battle(str(fe.monster), id)


## Percakapan dengan penduduk: satu kalimat per halaman, tombol Lanjut sampai habis.
## Urusan misi didahulukan: langkah "bicara/antar" diselesaikan, tantangan dibuka, atau misi baru ditawarkan.
func talk(id: String) -> void:
	var iid := str(p.world.island)
	var first := not (p.world.met as Dictionary).has(iid + "/" + id)
	var d: Dictionary = npc.talk(p, iid, id)
	if d.is_empty():
		return
	var title := "%s · %s" % [str(d.name), str(d.role)]
	var pages: Array = (d.lines as Array).duplicate() if first else []
	var meet_notes: Array = quest.event(p, "world", "", _qctx())
	save()
	var sa: Dictionary = quest.step_at(p, id)
	if not sa.is_empty() and str(sa.step.type) == "talk":
		var notes: Array = quest.event(p, "talk", id, _qctx())
		if notes.is_empty():
			var need: Array = []
			for it in (sa.step.get("take", {}) as Dictionary):
				need.append(str(quest.items.get(it, {}).get("name", it)))
			pages.append("Kamu belum membawa %s." % ", ".join(need))
			_pages(id, title, pages, [], meet_notes)
		else:
			_pages(id, title, pages, [], meet_notes + notes)
		return
	if not sa.is_empty() and str(sa.step.type) == "challenge":
		var ch: Dictionary = quest.challenges.get(str(sa.step.challenge), {})
		pages.append(str(ch.get("story", "")))
		_pages(id, title, pages, [["Mulai tantangan", open_challenge.bind(str(sa.step.challenge)), UI.GOOD]], meet_notes)
		return
	var offer: Dictionary = quest.offer_for(p, id)
	if not offer.is_empty():
		for l in offer.get("offer", []):
			pages.append(QuestEngine.fill(str(l), p))
		_pages(id, title, pages, [["Terima misi", accept_quest.bind(str(offer.id)), UI.GOOD]], meet_notes)
		return
	if pages.is_empty():
		pages = d.lines
	var shop_id := str(npc.npcs.get(id, {}).get("shop", ""))
	_pages(id, title, pages, [["Buka Toko", open_shop.bind(shop_id), UI.GOOD]] if shop_id != "" else [], meet_notes)


func accept_quest(qid: String) -> void:
	_sfx("buka")
	_show_notes(quest.start(p, qid, _qctx()))


## Halaman dialog berurutan. final: tombol di halaman terakhir. notes: catatan misi ditampilkan sesudahnya.
func _pages(id: String, title: String, pages: Array, final: Array, notes: Array = [], i := 0) -> void:
	if hud == null or world == null:
		return
	if pages.is_empty():
		_show_notes(notes)
		return
	if world.has_method("hold_talk"):
		world.hold_talk(id)
	if i < pages.size() - 1:
		hud.show_dialog(title, str(pages[i]), [["Lanjut", _pages.bind(id, title, pages, final, notes, i + 1), UI.PRIMARY]])
	elif not notes.is_empty() and final.is_empty():
		hud.show_dialog(title, str(pages[i]), [["Lanjut", _show_notes.bind(notes), UI.PRIMARY]])
	else:
		hud.show_dialog(title, str(pages[i]), final)
		if not notes.is_empty():
			_apply_notes_quiet(notes)


func _qctx() -> Dictionary:
	var iid := str(p.world.island)
	return {"found": npc.found_count(p, iid), "places": npc.places.size(), "met": npc.met_count(p, iid), "npcs": npc.npcs.size()}


## Tampilkan catatan misi: barang & misi baru sebagai pesan singkat; ucapan langkah & hadiah sebagai dialog.
func _show_notes(notes: Array) -> void:
	var say: Array = []
	var title := ""
	for n in notes:
		match str(n.kind):
			"item", "start":
				toast(str(n.text))
			"step":
				for l in n.get("say", []):
					say.append(str(l))
				if (n.get("say", []) as Array).is_empty():
					toast(str(n.text))
				title = str(n.title)
			"done":
				_sfx("bintang")
				say.append("")
				say.append("★ %s  Hadiah: %s" % [str(n.text), str(n.reward)])
				title = str(n.title)
	_apply_notes_quiet(notes)
	_progress()
	if not say.is_empty() and hud != null:
		hud.show_dialog(title, "\n".join(say).strip_edges())


## Akibat catatan pada dunia tanpa dialog: gua terbuka, barang baru muncul, tanda penduduk, tujuan.
func _apply_notes_quiet(_notes: Array) -> void:
	if world != null and world.has_method("open_cave"):
		if bool(p.world.flags.get("gua_terbuka", false)) and world.get("_boulder_nodes") != null and not (world._boulder_nodes as Array).is_empty():
			world.open_cave()
		for pk in quest.pickups(p, true):
			if not (world.pickups as Dictionary).has(str(pk.uid)):
				world.add_pickup(str(pk.uid), str(pk.item), pk.pos)
	save()
	_refresh_quest_ui()


func _refresh_quest_ui() -> void:
	if world == null or hud == null or not world.has_method("set_marks"):
		return
	world.set_marks(quest.marks(p))
	var o: Dictionary = quest.objective(p)
	var place_name := str(npc.places.get(world.place, {}).get("name", "")) if world.get("place") != null else ""
	var hint := ("Tempat: %s\n" % place_name if place_name != "" else "")
	hud.set_hint(hint + ("Misi: %s — %s" % [str(o.title), str(o.text)] if not o.is_empty() else "Jelajahi pulau dan sapa penduduknya."))
	hud.compass_target = objective_pos()


## Posisi tujuan misi aktif di dunia (untuk panah kompas), atau null.
func objective_pos():
	var o: Dictionary = quest.objective(p)
	if o.is_empty() or world == null or not world.has_method("set_marks"):
		return null
	var wh: Dictionary = o.get("where", {})
	if wh.has("npc"):
		var n: Node3D = world.npc_node(str(wh.npc))
		return n.position if n != null else null
	if wh.has("place") and npc.places.has(str(wh.place)):
		var pp: Array = npc.places[str(wh.place)].pos
		return Vector3(float(pp[0]), 0, float(pp[1]))
	if wh.has("spot"):
		var sid := str(wh.spot)
		var kind := sid if sid in ["boulder", "gate"] else "clue"
		var v: Vector3 = world.spot_pos(kind, "" if kind != "clue" else sid)
		return v if v != Vector3.ZERO else null
	if wh.has("pos"):
		return Vector3(float(wh.pos[0]), 0, float(wh.pos[1]))
	return null


func _process(delta: float) -> void:
	if screen != "island" or hud == null:
		return
	_obj_t -= delta
	if _obj_t <= 0.0:
		_obj_t = 0.5
		hud.compass_target = objective_pos()


# --- Pertarungan (Tahap 6) -------------------------------------------------------------------------------------

## Musuh berkeliaran pulau ini. Setelah Raja Goblin kalah, goblin pergi dari pulau.
func _foe_list() -> Array:
	var out: Array = []
	var defs: Dictionary = monsters.get("monsters", {})
	for sp in monsters.get("spawns", []):
		var m: Dictionary = defs.get(str(sp.monster), {})
		if m.is_empty() or (bool(p.world.flags.get("raja_kalah", false)) and str(sp.monster).begins_with("goblin")):
			continue
		out.append({"uid": str(sp.id), "monster": str(sp.monster), "model": str(m.model), "name": str(m.name), "level": int(m.get("level", 1)),
			"height": float(m.get("height", 1.0)), "pos": sp.pos})
	return out


func start_battle(monster_id: String, uid: String) -> void:
	var m: Dictionary = monsters.get("monsters", {}).get(monster_id, {})
	if m.is_empty() or hud == null or world == null or (lesson != null and is_instance_valid(lesson)):
		return
	hud.close_dialog()
	hud.visible = false
	world.player.frozen = true
	world.player.move_input = Vector2.ZERO
	lesson = BattleView.new()
	lesson.name = "Battle"
	_root.add_child(lesson)
	lesson.setup(learning, rewards, p, rng, audio, data.doc.get("type_names", {}), monster_id, m, uid, hero_look(), battle_seed)
	lesson.changed.connect(save)
	lesson.finished.connect(_on_battle_end)
	trail("tarung %s %s" % [monster_id, uid])


func _on_battle_end(res: Dictionary) -> void:
	close_class()
	if world == null:
		return
	if bool(res.won):
		if bool(res.boss):
			p.world.bosses[str(p.world.island)] = true
			world.boss_defeated()
		else:
			world.remove_foe(str(res.uid))
		var notes: Array = quest.event(p, "defeat", str(res.monster), _qctx())
		_show_notes(notes)
		if bool(res.boss):
			_island_saved()
	elif bool(res.fled):
		world.calm_foes(5.0)
	else:
		var desa: Dictionary = npc.places.get("desa", {})
		var dp: Array = desa.get("pos", [0, 40])
		world.player.place(Vector3(float(dp[0]), 0.3, float(dp[1]) + 4.0), 0.0)
		world.calm_foes(5.0)
		toast("Kamu bangun di desa. HP pulih penuh! Belajar lagi di akademi supaya jurus ilmumu makin kuat.")
	save()
	_progress()


## Akhir cerita pulau: bos kalah.
func _island_saved() -> void:
	var isl := worlds.island(str(p.world.island))
	var i: int = worlds.index_of(str(isl.id))
	var nxt: Dictionary = worlds.islands[i + 1] if i + 1 < worlds.islands.size() else {}
	var msg := "%s selamat dari Kabut Lupa! Kamu adalah pahlawan %s." % [str(isl.name), str(isl.name)]
	if not nxt.is_empty():
		msg += "\n\nPulau berikutnya: %s. %s" % [str(nxt.name), "Segera hadir!" if not bool(nxt.get("available", false)) else "Berlayarlah dari dermaga!"]
	modal("Pahlawan %s!" % str(isl.name), msg, [["Hore!", func() -> void: pass]])


# --- Tantangan misi (teka-teki belajar) ----------------------------------------------------------------

func open_challenge(cid: String) -> void:
	if hud == null or world == null:
		return
	var def: Dictionary = quest.challenges.get(cid, {})
	var topic: String = quest.challenge_topic(cid, data, grade())
	if def.is_empty() or topic == "":
		toast("Tantangan belum bisa dimulai.")
		return
	hud.close_dialog()
	hud.visible = false
	world.player.frozen = true
	world.player.move_input = Vector2.ZERO
	lesson = ChallengeView.new()
	lesson.name = "Challenge"
	_root.add_child(lesson)
	lesson.setup(learning, p, rng, audio, data.doc.get("type_names", {}), cid, def, topic)
	lesson.closed.connect(close_class)
	lesson.changed.connect(save)
	lesson.passed.connect(_on_challenge_passed)
	trail("tantangan " + cid)


func _on_challenge_passed(cid: String) -> void:
	close_class()
	_show_notes(quest.event(p, "challenge", cid, _qctx()))


func _on_place(id: String) -> void:
	if id == "" or hud == null:
		return
	var pl: Dictionary = npc.places.get(id, {})
	if _discover(id):
		toast("Tempat baru ditemukan: %s!" % str(pl.get("name", "")))
		_sfx("bintang")
		_show_notes(quest.event(p, "world", "", _qctx()))
	_refresh_quest_ui()


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
	if not quest.quests.is_empty():
		rows.append("MISI UTAMA (%d/%d selesai)" % [quest.done_count(p, "main"), quest.quests.filter(func(q): return str(q.kind) == "main").size()])
		for kind in ["main", "side"]:
			if kind == "side":
				rows.append("")
				rows.append("MISI SAMPINGAN")
			for q in quest.quests:
				if str(q.kind) != kind:
					continue
				var st: String = quest.state(p, str(q.id))
				if st == "done":
					rows.append("  ✓ " + str(q.title))
				elif st == "active":
					rows.append("  ▶ %s: %s" % [str(q.title), str(quest.step(p, str(q.id)).get("text", ""))])
				elif quest.requires_met(p, q) and str(q.get("giver", "")) != "":
					rows.append("  ! %s (tanya %s)" % [str(q.title), str(npc.npcs.get(str(q.giver), {}).get("name", q.giver))])
		rows.append("")
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
	# Di atas tengah layar: tidak menutupi joystick, tombol aksi, atau tombol pertarungan.
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 92
	_toast.offset_bottom = 170
	_toast.offset_left = -360
	_toast.offset_right = 360


## Pesan singkat di bawah layar. Beberapa pesan sekaligus ditampilkan bergantian (tidak saling menimpa).
func toast(text: String) -> void:
	_toast_queue.append(text)
	if _toast_queue.size() == 1:
		_show_toast()


func _show_toast() -> void:
	if _toast_queue.is_empty():
		_toast.visible = false
		return
	_toast_lbl.text = str(_toast_queue[0])
	_toast.visible = true
	_toast.modulate.a = 1.0
	move_child(_toast, get_child_count() - 1)
	var tw := _toast.create_tween()
	tw.tween_interval(2.0 if _toast_queue.size() > 1 else 2.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		_toast_queue.pop_front()
		_show_toast())


func last_toast() -> String:
	return _toast_lbl.text


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
