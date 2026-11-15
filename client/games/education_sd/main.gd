extends Control
## Game Pembelajaran SD — "Petualangan Pulau Ilmu" (v2.4.3, paket unduhan).
## Semua berkas ada di res://games/education_sd/ (namespace game ini). Kontrak platform yang dipakai:
## GameManager.load_progress / save_progress / restore_progress_from_server / exit_to_launcher dan
## platform_before_exit(). Mesin kuis bersama (res://shared/edu/quiz_app.gd, dipakai SMP) tidak diubah.

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const SdArt := preload("res://games/education_sd/scripts/sd_art.gd")
const SdData := preload("res://games/education_sd/scripts/sd_data.gd")
const SdProgress := preload("res://games/education_sd/scripts/sd_progress.gd")
const SdAudio := preload("res://games/education_sd/scripts/sd_audio.gd")
const SdQuestion := preload("res://games/education_sd/scripts/sd_question.gd")
const SdMini := preload("res://games/education_sd/scripts/sd_minigames.gd")
const IslandWorld := preload("res://games/education_sd/scripts/world/w3d_world.gd")
const Hud3D := preload("res://games/education_sd/scripts/world/w3d_hud.gd")
const Locations := preload("res://games/education_sd/scripts/world/w3d_locations.gd")
const Missions := preload("res://games/education_sd/scripts/world/w3d_missions.gd")
const Items := preload("res://games/education_sd/scripts/world/w3d_items.gd")
const Rig3D := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const LOC_QUESTIONS := 3
const LOC_PASS := 2

const GAME_ID := "education_sd"
const AREA_QUESTIONS := 5
const QUIZ_QUESTIONS := 10
const EXAM_QUESTIONS := 10
const PRACTICE_QUESTIONS := 6
const VERSION := "2.4.3"
## Jejak langkah (breadcrumb) di HP: setiap layar/tombol ditulis dan di-flush ke berkas. Bila aplikasi
## tertutup paksa (crash), jejak tidak berakhir dengan END; saat game dibuka lagi, 30 langkah terakhir
## dikirim ke server bersama progres (p["crash"]) supaya penyebabnya bisa dilacak tanpa kabel.
const TRAIL_PATH := "user://education_sd_trail.txt"
const BASE_ID := "markas"
const ICON := "res://games/education_sd/assets/icon/sd_icon_512.png"


## Ikon game (gambar dari pengguna) untuk beranda & layar pengenalan.
func _icon(size: float) -> TextureRect:
	var t := TextureRect.new()
	t.name = "GameIcon"
	t.texture = load(ICON) if ResourceLoader.exists(ICON) else null
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	return t
const CHEST_SCORE := 70  # nilai kuis minimal untuk membuka peti pengetahuan di dunia 3D
const NPC_KIND := {"matematika": "raja", "bahasa": "kancil", "ipa": "profesor", "ips": "nakhoda"}

var game_id := GAME_ID  # dibaca uji platform
var data := SdData.new()
var p: Dictionary = {}
var rng := RandomNumberGenerator.new()
var audio: Node

var screen := ""
var _root: Control
var _toast: PanelContainer
var _toast_lbl: Label
var session: Dictionary = {}
var _qview: Node
var _back_target := "home"
var _exit_dialog: ConfirmationDialog
var _exit_noted := false
var _touch_start := {}  # indeks jari -> posisi awal sentuhan
var _trail: FileAccess
var _press_index := -1
var world: Node3D  # dunia 3D yang sedang tampil (null di layar lain)
var hud: Control
var _world_return := ""  # wilayah 3D tujuan kembali setelah sesi/mini-game yang dimulai dari dunia 3D
var _frames := 0
var _anim := true  # animasi gambar (maskot, peta); dimatikan otomatis bila game crash berulang


## Catatan diagnosis (ikut tersinkron ke server): kapan dan dari layar mana game ditutup.
func _note_exit(reason: String) -> void:
	_note_event(reason)
	_exit_noted = true


func _start_audio() -> void:
	trail("audio: mulai (musik %s, efek %s)" % [p.settings.music, p.settings.sfx])
	audio.apply(bool(p.settings.music), bool(p.settings.sfx))
	trail("audio: berjalan")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames in [1, 10, 60, 180, 600]:
		trail("frame %d" % _frames)


## Mode aman bertahap setelah crash berulang: tingkat 1 musik dimatikan, tingkat 2 animasi gambar juga.
func _freeze_anim(n: Node) -> void:
	if n is Control and n.has_method("_process") and n.get_script() != null and n != self:
		n.set_process.call_deferred(false)


## Mode aman 2.0.4 dipasang karena musik crash; 2.0.5 memperbaikinya, jadi musik & animasi dinyalakan lagi
## satu kali saat versi baru pertama dibuka.
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
	var last := str(tail[-1])
	var kind := "crash"
	var lvl := mini(int(p.get("safe_level", 0)) + 1, 2)
	p["safe_level"] = lvl
	if lvl >= 1:
		p.settings.music = false
	p["crash"] = {"found_at": Time.get_datetime_string_from_system(false, true), "kind": kind, "trail": tail,
		"safe_level": lvl}
	_note_event("tertutup tidak normal (%s), langkah terakhir: %s; mode aman %d" % [kind, last, lvl])
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


func _note_event(reason: String) -> void:
	if p.is_empty():
		return
	var diag: Array = p.get("diag", [])
	diag.append({"at": Time.get_datetime_string_from_system(false, true), "reason": reason, "screen": screen,
			"ver": VERSION})
	p["diag"] = diag.slice(-10)


func _ready() -> void:
	rng.randomize()
	get_tree().quit_on_go_back = false
	var bg := ColorRect.new()
	bg.color = UI.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio = SdAudio.new()
	audio.name = "Audio"
	add_child(audio)
	_build_toast()
	if not data.load_data():
		_show_error("Data pelajaran tidak bisa dimuat:\n" + "\n".join(data.errors.slice(0, 5)))
		return
	_load_progress()
	_reset_safe_mode()
	_check_last_trail()
	_open_trail()
	_note_event("dibuka")
	_anim = int(p.get("safe_level", 0)) < 2
	if not _anim:
		get_tree().node_added.connect(_freeze_anim)
	_start_audio.call_deferred()
	if str(p.player.name) == "":
		show_onboarding()
	else:
		show_home()
	if int(p.totals.answered) == 0:
		_try_restore()


## Lacak geseran jari: tombol yang dilepas setelah layar digulir tidak dianggap ditekan.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start[event.index] = event.position
			_press_index = event.index
			UI.touch_dragged = false
		else:
			_touch_start.erase(event.index)
	elif event is InputEventScreenDrag:
		var s: Vector2 = _touch_start.get(event.index, event.position)
		if event.index == _press_index and event.position.distance_to(s) > UI.DRAG_CANCEL_PX:
			UI.touch_dragged = true


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
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		trail("END")
	elif what == NOTIFICATION_PREDELETE:
		trail("END")
		UI.on_press = Callable()


## Dipanggil GameManager sebelum kembali ke launcher.
func platform_before_exit() -> void:
	trail("keluar ke launcher END")
	if not _exit_noted:
		_note_exit("ditutup platform")
	save()
	if audio != null:
		audio.stop_all()


# --- Progres -----------------------------------------------------------------------------------------

func _gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _migrations() -> Dictionary:
	return {1: func(d: Dictionary) -> Dictionary: return SdProgress.upgrade(d)}


func _load_progress() -> void:
	var gm := _gm()
	var res: Dictionary = gm.load_progress(GAME_ID, SdProgress.SCHEMA, _migrations()) if gm != null else {}
	p = SdProgress.upgrade(res.get("data", {}))


func _try_restore() -> void:
	var gm := _gm()
	if gm == null:
		return
	var restored: Dictionary = await gm.restore_progress_from_server(GAME_ID, SdProgress.SCHEMA)
	if restored.is_empty() or not is_inside_tree():
		return
	p = SdProgress.upgrade(restored)
	save()
	toast("Progres belajarmu dipulihkan dari server.")
	if screen == "home" or screen == "onboarding":
		if str(p.player.name) != "":
			show_home()
		else:
			show_onboarding()


func save() -> void:
	if p.is_empty():
		return
	var gm := _gm()
	if gm != null:
		gm.save_progress(GAME_ID, p, SdProgress.SCHEMA)


func grade() -> int:
	return int(p.player.grade)


# --- Kerangka layar ------------------------------------------------------------------------------------

func _clear_raw(id: String) -> void:
	if screen == "world" and id != "world" and audio != null:
		audio.ambient(false)
	screen = id
	trail("layar " + id)
	UI.guard(350)
	_qview = null
	world = null
	hud = null
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()


func _clear(id: String) -> VBoxContainer:
	_clear_raw(id)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(UI.DRAG_CANCEL_PX)
	_root.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 36)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(m)
	var v := UI.vbox(16)
	v.name = "Page"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return v


func page() -> VBoxContainer:
	return _root.get_node_or_null("Scroll").get_child(0).get_node("Page") if _root.get_child_count() > 0 else null


func _header(v: VBoxContainer, title: String, back: String = "home", color := UI.PRIMARY) -> HBoxContainer:
	_back_target = back
	var h := UI.hbox(14)
	if back != "":
		h.add_child(UI.button("Kembali", go_back, Color("cfc8dc"), 24, 64))
	var t := UI.label(title, 38, color, false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(t)
	h.add_child(_chip("Bintang %d" % SdProgress.total_stars(p), UI.GOLD))
	h.add_child(_chip("Koin %d" % int(p.coins), Color("ffd166")))
	v.add_child(h)
	return h


func _chip(text: String, color: Color) -> PanelContainer:
	var c := UI.panel(color, 30)
	c.add_child(UI.label(text, 22, UI.INK, false))
	return c


## Tombol kembali Android / tombol Kembali. Dari beranda dan layar pengenalan TIDAK langsung keluar:
## sinyal kembali Android bisa terkirim tanpa sengaja (menutup papan ketik, usap dari tepi layar),
## jadi pemain ditanya dulu.
func go_back() -> void:
	if audio != null:
		audio.play("klik")
	match screen:
		"error":
			_exit_to_launcher("kembali dari layar galat")
		"home":
			_confirm_exit("back Android di beranda")
		"onboarding":
			if str(p.player.name) != "":
				show_home()
			else:
				_confirm_exit("back Android di pengenalan")
		"world":
			show_home()
		"session":
			_confirm_leave_session()
		"region":
			show_map()
		"minigame":
			_back_from_minigame()
		_:
			match _back_target:
				"map":
					show_map()
				"region":
					show_region(str(session.get("region", "matematika")))
				"subjects":
					show_subjects()
				"world":
					show_world(_world_return)
				_:
					show_home()


func _confirm_exit(source: String = "kembali") -> void:
	if _exit_dialog != null and is_instance_valid(_exit_dialog) and _exit_dialog.visible:
		return
	if _exit_dialog != null and is_instance_valid(_exit_dialog):
		_exit_dialog.queue_free()
	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.dialog_text = "Kembali ke daftar game?\nProgres belajarmu sudah tersimpan."
	_exit_dialog.ok_button_text = "Ya, kembali"
	_exit_dialog.cancel_button_text = "Tetap bermain"
	add_child(_exit_dialog)
	_exit_dialog.confirmed.connect(_exit_to_launcher.bind(source + " (dikonfirmasi)"))
	_exit_dialog.popup_centered(Vector2i(640, 220))


func _exit_to_launcher(reason: String = "tombol kembali ke launcher") -> void:
	_note_exit(reason)
	save()
	var gm := _gm()
	if gm != null:
		gm.exit_to_launcher()
	else:
		get_tree().quit()


func _show_error(text: String) -> void:
	var v := _clear("error")
	v.add_child(UI.label(text, 28, UI.SOFT_BAD))
	v.add_child(UI.button("Kembali ke daftar game", _exit_to_launcher, UI.PRIMARY))


# --- Pengenalan pertama --------------------------------------------------------------------------------

func show_onboarding() -> void:
	var v := _clear("onboarding")
	var row := UI.hbox(30)
	v.add_child(row)
	row.add_child(_icon(220))
	var m := SdArt.Mascot.new(Color("8a6bd8"), "profesor")
	m.custom_minimum_size = Vector2(200, 220)
	row.add_child(m)
	var col := UI.vbox(14)
	UI.expand(col)
	row.add_child(col)
	col.add_child(UI.label("Selamat datang di Petualangan Pulau Ilmu!", 40, UI.PRIMARY))
	col.add_child(UI.label("Aku Profesor Kiko. Siapa namamu, dan kamu kelas berapa?", 28, UI.INK))
	var name_edit := UI.line_edit(str(p.player.name), "Tulis namamu")
	name_edit.name = "NameEdit"
	col.add_child(name_edit)
	var g := UI.grid(6, 10)
	var chosen := [grade()]
	var btns: Array = []
	for k in range(1, 7):
		var b := UI.button("Kelas %d" % k, Callable(), Color("ffd166") if k == chosen[0] else Color("e8e2f2"), 26, 80)
		UI.expand(b)
		btns.append(b)
		g.add_child(b)
	for k in range(1, 7):
		btns[k - 1].pressed.connect(func() -> void:
			chosen[0] = k
			for j in btns.size():
				btns[j].add_theme_stylebox_override("normal", UI.box(Color("ffd166") if j + 1 == k else Color("e8e2f2")))
			audio.play("klik"))
	col.add_child(g)
	var start := func() -> void:
		var n := name_edit.text.strip_edges()
		if n == "":
			toast("Tulis namamu dulu, ya.")
			return
		set_player(n, chosen[0])
		show_home()
	name_edit.text_submitted.connect(func(_t: String) -> void: start.call())
	var go := UI.button("Mulai!", start, UI.GOOD, 34, 90)
	go.name = "Start"
	col.add_child(go)


## Ubah nama/kelas pemain (dipakai layar pengenalan dan pengaturan). Progres kelas lain tetap tersimpan.
func set_player(n: String, g: int) -> void:
	p.player.name = n.substr(0, 16)
	p.player.grade = clampi(g, 1, 6)
	save()


# --- Beranda ---------------------------------------------------------------------------------------------

func show_home() -> void:
	var v := _clear("home")
	var top := UI.hbox(24)
	v.add_child(top)
	top.add_child(_icon(170))
	var av := SdArt.Avatar.new()
	av.custom_minimum_size = Vector2(150, 170)
	_apply_look(av)
	top.add_child(av)
	var info := UI.vbox(6)
	UI.expand(info)
	top.add_child(info)
	info.add_child(UI.label("Petualangan Pulau Ilmu", 46, UI.PRIMARY, false))
	info.add_child(UI.label("%s  ·  Kelas %d  ·  Level %d" % [str(p.player.name), grade(), SdProgress.level(p)], 30, UI.INK, false))
	var lv := SdProgress.level(p)
	var bar := UI.progress(int(p.xp) - SdProgress.xp_for(lv), SdProgress.xp_for(lv + 1) - SdProgress.xp_for(lv), UI.PRIMARY)
	info.add_child(bar)
	info.add_child(UI.label("%d XP lagi menuju level %d" % [SdProgress.xp_for(lv + 1) - int(p.xp), lv + 1], 18, UI.SOFT, false))
	var chips := UI.hbox(12)
	chips.add_child(_chip("Bintang %d" % SdProgress.total_stars(p), UI.GOLD))
	chips.add_child(_chip("Koin %d" % int(p.coins), Color("ffd166")))
	chips.add_child(_chip("Lencana %d" % (p.badges as Dictionary).size(), Color("c9b2f0")))
	info.add_child(chips)
	var prog := UI.grid(4, 12)
	for r in data.regions:
		var ts := data.topics_for(str(r.id), grade())
		var done := 0
		for t in ts:
			if SdProgress.area_rec(p, grade(), str(r.id), str(t.id)).get("done", false):
				done += 1
		var card := UI.panel(Color.from_string(str(r.color), UI.PRIMARY).lightened(0.55))
		var cv := UI.vbox(4)
		cv.add_child(UI.label(str(r.subject), 22, UI.INK, false))
		cv.add_child(UI.progress(done, ts.size(), Color.from_string(str(r.color), UI.PRIMARY), 14))
		cv.add_child(UI.label("%d/%d area" % [done, ts.size()], 18, UI.SOFT, false))
		card.add_child(cv)
		UI.expand(card)
		prog.add_child(card)
	v.add_child(prog)
	_world_return = ""
	var big := UI.hbox(16)
	var w3d := UI.button("JELAJAHI PULAU 3D", show_world.bind(""), Color("8a6bd8"), 34, 110)
	w3d.name = "IslandWorld"
	UI.expand(w3d)
	big.add_child(w3d)
	var start := UI.button("MULAI PETUALANGAN", show_map, UI.GOOD, 30, 110)
	UI.expand(start)
	big.add_child(start)
	var pick := UI.button("PILIH PELAJARAN", show_subjects, UI.PRIMARY, 30, 110)
	UI.expand(pick)
	big.add_child(pick)
	v.add_child(big)
	var g := UI.grid(3, 14)
	for item in [["MINI-GAME", show_minigames, Color("e0813d")], ["KOLEKSI", show_collection.bind("kostum"), Color("8a6bd8")],
			["PRESTASI", show_badges, UI.GOLD], ["LAPORAN BELAJAR", show_report, Color("2fb3a6")],
			["PENGATURAN", show_settings, Color("8a9bb8")], ["KEMBALI KE LAUNCHER", _confirm_exit.bind("tombol beranda"), Color("cfc8dc")]]:
		var b := UI.button(item[0], item[1], item[2], 24, 84)
		UI.expand(b)
		g.add_child(b)
	v.add_child(g)


func _apply_look(av) -> void:
	var outfit := Color("e05a4f")
	var hat := ""
	var acc := ""
	for s in data.doc.get("shop", []):
		if str(s.id) == str(p.player.avatar.get("outfit", "")):
			outfit = Color.from_string(str(s.value), outfit)
		if str(s.id) == str(p.player.avatar.get("hat", "")):
			hat = str(s.value)
		if str(s.id) == str(p.player.avatar.get("acc", "")):
			acc = str(s.value)
	av.set_look(outfit, hat, acc)


# --- Dunia 3D --------------------------------------------------------------------------------------------
# Mode petualangan 3D: pulau per wilayah dengan gerbang/jembatan per area. Semua aktivitas belajar memakai
# sesi soal, kuis, ujian, dan mini-game yang sama dengan mode 2D (hadiah dari SdProgress, tidak digandakan).

func _wkey(region_id: String) -> String:
	return "k%d/%s" % [grade(), region_id]


func _world_ctx(region_id: String) -> Dictionary:
	var r := data.region(region_id)
	var ts := data.topics_for(region_id, grade())
	var topics: Array = []
	var all_done := true
	for i in ts.size():
		var t: Dictionary = ts[i]
		var rec := SdProgress.area_rec(p, grade(), region_id, str(t.id))
		var open: bool = i == 0 or SdProgress.area_rec(p, grade(), region_id, str(ts[i - 1].id)).get("done", false)
		if not rec.get("done", false):
			all_done = false
		topics.append({"id": str(t.id), "name": str(t.name), "done": bool(rec.get("done", false)),
			"stars": int(rec.get("stars", 0)), "open": open})
	var ex: Dictionary = SdProgress.grade_rec(p, grade()).exams.get(region_id, {})
	var outfit := Color("e05a4f")
	for s in data.doc.get("shop", []):
		if str(s.id) == str(p.player.avatar.get("outfit", "")):
			outfit = Color.from_string(str(s.value), outfit)
	return {"region": r, "grade": grade(), "topics": topics,
		"exam": {"open": all_done and not ts.is_empty(), "passed": bool(ex.get("passed", false))},
		"chest_opened": bool((p.world.chests as Dictionary).get(_wkey(region_id), false)),
		"found": bool((p.world.found as Dictionary).get(_wkey(region_id), false)),
		"locs": _loc_status(region_id), "items": (p.world.items as Dictionary).get(region_id, []),
		"facts": ts.map(func(t): return {"title": str(t.card.title), "fact": str(t.card.fact)}) if not ts.is_empty() else [],
		"minigame": _minigame_for(region_id), "gfx": str(p.settings.gfx),
		"hero": {"shirt": outfit, "long_hair": str(p.settings.hero) == "perempuan", "model": "anak_desa" if str(p.settings.hero) == "petualang" else "",
			"model_path": _hero_path(),
			"hat": _shop_value(str(p.player.avatar.get("hat", ""))), "acc": _shop_value(str(p.player.avatar.get("acc", "")))}}


## Model pahlawan anak (Fase 9): laki-laki / perempuan dari GLB buatan sendiri bila ada, kalau tidak "" (rig primitif).
func _hero_path() -> String:
	var kind: String = {"laki": "male", "perempuan": "female"}.get(str(p.settings.hero), "")
	if kind == "":
		return ""
	var path: String = Rig3D.hero_path(kind)
	return path if ResourceLoader.exists(path) else ""


func _shop_value(id: String) -> String:
	for s in data.doc.get("shop", []):
		if str(s.id) == id:
			return str(s.value)
	return ""


func show_world(region_id: String = "") -> void:
	if region_id == "":
		region_id = str(p.world.region)
	var in_base := region_id == BASE_ID
	if not in_base and data.region(region_id).is_empty():
		region_id = "matematika"
	if not in_base:
		p.world.region = region_id
	_world_return = ""
	_clear_raw("world")
	var ctx := _base_ctx() if in_base else _world_ctx(region_id)
	var prof: Dictionary = IslandWorld.PROFILES.get(str(ctx.gfx), IslandWorld.PROFILES.seimbang)
	var box := SubViewportContainer.new()
	box.name = "View3D"
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.scaling_3d_scale = float(prof.scale)
	vp.msaa_3d = Viewport.MSAA_2X if bool(prof.msaa) else Viewport.MSAA_DISABLED
	vp.handle_input_locally = false
	box.add_child(vp)
	world = IslandWorld.new()
	world.name = "World"
	vp.add_child(world)
	world.build(ctx)
	world.interacted.connect(_on_world_interact)
	world.zone_entered.connect(_on_world_zone)
	world.life.rain_changed.connect(func(on: bool) -> void:
		if audio != null and audio.has_method("rain"):
			audio.rain(on))
	hud = Hud3D.new()
	hud.name = "Hud"
	_root.add_child(hud)
	var r: Dictionary = ctx.region
	hud.setup(world, "%s · Kelas %d" % [str(r.name), grade()], Color.from_string(str(r.color), UI.PRIMARY))
	hud.back_pressed.connect(go_back)
	hud.missions_pressed.connect(show_missions)
	hud.bag_pressed.connect(show_bag)
	hud.dialog_closed.connect(func() -> void: _foe_cancel.call_deferred())
	if world.foes != null:
		world.foes.foe_touched.connect(_on_foe)
	var tool := Items.equipped(p)
	if tool != "":
		world.apply_tool(tool)
		if tool == "kompas":
			hud.compass_target = _objective_pos()
	hud.set_perf(bool(p.settings.get("perf", false)))
	hud.chips.add_child(_chip("Bintang %d" % SdProgress.total_stars(p), UI.GOLD))
	hud.chips.add_child(_chip("Koin %d" % int(p.coins), Color("ffd166")))
	hud.set_hint(_world_hint(ctx))
	trail("dunia 3D %s grafis %s" % [region_id, str(ctx.gfx)])
	if in_base:
		hud.set_hint("Markas %s: lemari kostum, cermin karakter, Buku Petualangan, piala, museum kartu, dan galeri hewan." % str(p.player.name))
		if audio != null:
			audio.ambient(true)
		save()
		return
	(p.world.islands as Dictionary)[region_id] = true
	_check_missions()
	if audio != null:
		audio.ambient(true)
	# Gerbang yang baru selesai sejak kunjungan terakhir: animasi terbuka + sorak.
	var seen: Dictionary = p.world.seen_done
	for t in ctx.topics:
		var k := _wkey(region_id) + "/" + str(t.id)
		if t.done and not seen.has(k):
			seen[k] = true
			world.celebrate_gate(str(t.id))
			if audio != null:
				audio.play("buka")
	save()


func _world_hint(ctx: Dictionary) -> String:
	for i in (ctx.topics as Array).size():
		var t: Dictionary = ctx.topics[i]
		if not t.done:
			return "Tujuan: %s %d \"%s\" di jalan depan. Dekati lalu tekan AKSI." % [
				"perbaiki jembatan" if i % 3 == 1 else "buka gerbang", i + 1, str(t.name)]
	if not ctx.exam.passed:
		return "Semua gerbang terbuka! Tantang Penjaga Wilayah di ujung jalan (ujian akhir)."
	if not ctx.chest_opened:
		return "Wilayah ditaklukkan! Buka Peti Pengetahuan di alun-alun, atau pindah pulau lewat portal."
	return "Hebat! Jelajahi pulau lain lewat portal, cari tempat rahasia, atau main mini-game."


func _from_world(cb: Callable) -> void:
	var rid := str(p.world.region)
	cb.call()
	if screen in ["session", "minigame"]:
		_world_return = rid


func _on_world_interact(kind: String, id: String) -> void:
	trail("3D aksi %s %s" % [kind, id])
	if audio != null:
		audio.play("klik")
	var rid := str(p.world.region)
	var r := data.region(rid)
	var ctx := _world_ctx(rid)
	match kind:
		"npc":
			var next := ""
			for t in ctx.topics:
				if not t.done:
					next = str(t.id)
					break
			var intro := str(r.intro) if not p.seen_intro.has(rid) else "Halo lagi, %s!" % str(p.player.name)
			p.seen_intro[rid] = true
			var btns: Array = []
			if next != "":
				btns.append(["Latihan dulu", _from_world.bind(start_practice.bind(next)), UI.PRIMARY])
			hud.show_dialog(str(r.npc), intro + "\n" + _world_hint(ctx), btns)
		"gate":
			var idx := -1
			for i in (ctx.topics as Array).size():
				if str(ctx.topics[i].id) == id:
					idx = i
			if idx < 0:
				return
			var t: Dictionary = ctx.topics[idx]
			var topic: Dictionary = data.topics[id]
			if t.done:
				hud.show_dialog(str(t.name), "Sudah terbuka dengan %d bintang. Mau mengulang untuk bintang lebih banyak?" % int(t.stars),
					[["Ulangi", _from_world.bind(start_area.bind(rid, id)), UI.PRIMARY]])
			elif not t.open:
				hud.show_dialog(str(t.name), "Masih terkunci. Selesaikan dulu \"%s\"." % str(ctx.topics[idx - 1].name))
			else:
				hud.show_dialog(str(t.name), str(topic.story) + "\nJawab %d soal untuk membukanya!" % AREA_QUESTIONS,
					[["Mulai!", _from_world.bind(start_area.bind(rid, id)), UI.GOOD]])
		"boss":
			if ctx.exam.open and not ctx.exam.passed and not world.foes.boss_tired():
				hud.show_dialog("Penjaga Wilayah", "Awas, ia sedang berjaga dan bisa menghentak! Tunggu sampai ia lelah (duduk membungkuk), lalu tantang dia.")
			elif ctx.exam.open:
				hud.show_dialog(str(IslandWorld.THEMES.get(rid, {}).get("boss", "Penjaga Wilayah")),
					"Kalahkan aku dengan ujian akhir: %d soal, nilai 70 ke atas berarti menang!" % EXAM_QUESTIONS,
					[["Mulai ujian", _from_world.bind(start_exam.bind(rid)), UI.GOLD]])
			else:
				hud.show_dialog("Penjaga Wilayah", "Buka semua gerbang di wilayah ini dulu, baru tantang aku!")
		"chest":
			var txt := "Peti ini terkunci teka-teki. Jawab kuis %s (%d soal) dengan nilai %d ke atas untuk membukanya." % [
				str(r.subject), QUIZ_QUESTIONS, CHEST_SCORE]
			if ctx.chest_opened:
				txt = "Peti sudah terbuka! Kamu tetap boleh main kuis lagi untuk mengumpulkan koin."
			hud.show_dialog("Peti Pengetahuan", txt, [["Mulai kuis", _from_world.bind(start_quiz.bind(rid)), UI.GOLD]])
		"minigame":
			_from_world(start_minigame.bind(id))
		"portal":
			var here := str(world.ctx.region.id)
			var btns: Array = []
			for reg in data.regions:
				if str(reg.id) != here:
					btns.append([str(reg.name), show_world.bind(str(reg.id)), Color.from_string(str(reg.color), UI.PRIMARY)])
			if here != BASE_ID:
				btns.append(["Markas Pemain", show_world.bind(BASE_ID), Color("8a6bd8")])
			hud.show_dialog("Portal Pulau", "Mau pergi ke mana?", btns)
		"wardrobe":
			var btns: Array = []
			for o in _owned_outfits():
				btns.append(["Pakai " + str(o.name), _wear.bind(str(o.id)), o.color])
			hud.show_dialog("Lemari Kostum", "Kostum yang sudah kamu miliki. Kostum baru bisa dibeli dengan koin di menu Koleksi.", btns)
		"mirror":
			hud.show_dialog("Cermin Karakter", "Pilih karakter petualangmu.", [
				["Laki-laki", _pick_hero.bind("laki"), UI.PRIMARY], ["Perempuan", _pick_hero.bind("perempuan"), Color("e05a8f")],
				["Petualang", _pick_hero.bind("petualang"), Color("3fae63")]])
		"book":
			hud.show_list("Buku Petualangan · Kelas %d" % grade(), _book_rows())
		"cards":
			var rows: Array = []
			for reg in data.regions:
				var n := 0
				for cid in p.cards:
					if data.topics.has(str(cid)) and str(data.topics[str(cid)].region) == str(reg.id):
						n += 1
						rows.append("★ [%s] %s — %s" % [str(reg.subject), str(data.topics[str(cid)].card.title), str(data.topics[str(cid)].card.fact)])
			if rows.is_empty():
				rows.append("Belum ada kartu. Selesaikan area di gerbang pulau untuk mendapatkannya!")
			hud.show_list("Museum Kartu (%d kartu)" % (p.cards as Array).size(), rows)
		"trophies":
			var rows: Array = []
			for b in data.doc.get("badges", []):
				if (p.badges as Dictionary).has(str(b.id)):
					rows.append("🏆 %s — %s" % [str(b.name), str(b.desc)])
			if rows.is_empty():
				rows.append("Belum ada piala. Terus belajar untuk mendapatkan lencana prestasi!")
			hud.show_list("Piala Prestasi", rows)
		"animal":
			if id == "":
				hud.show_dialog("Galeri Hewan", "Belum ada hewan. Main mini-game Kelompokkan Hewan untuk mengumpulkannya!")
			else:
				hud.show_dialog(id.capitalize(), str(data.doc.get("animal_facts", {}).get(id, "")))
		"loc":
			_loc_dialog(rid, id)
		"info":
			var facts: Array = world.ctx.get("facts", [])
			if not facts.is_empty():
				var f: Dictionary = facts[int(id) % facts.size()]
				hud.show_dialog("Papan Informasi: " + str(f.title), str(f.fact))
		"villager":
			var d := Locations.find(rid, id)
			var st: Dictionary = _loc_status(rid).get(id, {})
			if st.get("done", false):
				hud.show_dialog(str(d.villager), "Terima kasih sudah membantuku, %s! Mau membantu lagi?" % str(p.player.name),
					[["Bantu lagi", _from_world.bind(start_loc.bind(rid, id)), UI.PRIMARY]])
			else:
				hud.show_dialog(str(d.villager), str(d.desc) + "\nMaukah kamu membantuku? Jawab minimal %d dari %d soal dengan benar." % [LOC_PASS, LOC_QUESTIONS],
					[["Ya, aku bantu!", _from_world.bind(start_loc.bind(rid, id)), UI.GOOD]])
		"secret":
			var fact := "Kamu menemukan tempat rahasia!"
			for t in data.topics_for(rid, grade()):
				if t.has("card"):
					fact += "\nTahukah kamu? %s: %s" % [str(t.card.title), str(t.card.fact)]
					break
			if not (p.world.found as Dictionary).has(_wkey(rid)):
				(p.world.found as Dictionary)[_wkey(rid)] = true
				world.mark_secret_found()
				save()
			hud.show_dialog("Tempat Rahasia", fact)
			_check_missions()


# --- Dunia 3D: lokasi, benda, misi (Fase 3–4) -----------------------------------------------------------

func _loc_status(region_id: String) -> Dictionary:
	var out := {}
	var visited: Dictionary = (p.world.visited as Dictionary).get(region_id, {})
	for d in Locations.for_region(region_id):
		var lid := str(d.id)
		out[lid] = {"done": bool((p.world.locs as Dictionary).get(_wkey(region_id) + "/" + lid, {}).get("done", false)),
			"visited": visited.has(lid)}
	return out


## Teka-teki lokasi: 3 soal dari topik wilayah (kelas aktif), topik berputar sesuai urutan lokasi.
func _loc_topic(region_id: String, loc_id: String) -> Dictionary:
	var ts := data.topics_for(region_id, grade())
	var i := Locations.index_of(region_id, loc_id)
	if ts.is_empty() or i < 0:
		return {}
	return ts[i % ts.size()]


func start_loc(region_id: String, loc_id: String) -> void:
	var d := Locations.find(region_id, loc_id)
	var t := _loc_topic(region_id, loc_id)
	if d.is_empty() or t.is_empty():
		toast("Belum ada teka-teki di sini untuk kelasmu.")
		return
	var st := SdProgress.topic_stats(p, grade(), str(t.id))
	var picked := data.pick(str(t.id), grade(), LOC_QUESTIONS, st, rng)
	_start_session({"kind": "lokasi", "mode": "petualangan", "region": region_id, "topic": str(t.id), "loc": loc_id,
		"questions": picked.questions, "adapt": picked.mode, "title": str(d.name), "story": str(d.desc)})


func _loc_dialog(rid: String, id: String) -> void:
	var d := Locations.find(rid, id)
	var t := _loc_topic(rid, id)
	var st: Dictionary = _loc_status(rid).get(id, {})
	var txt := "%s\nTeka-teki: %s (%d soal, minimal %d benar)." % [str(d.desc), str(t.get("name", "-")), LOC_QUESTIONS, LOC_PASS]
	if st.get("done", false):
		txt += "\nSudah kamu selesaikan. Boleh dicoba lagi untuk latihan."
	var btns: Array = [["Pecahkan teka-teki", _from_world.bind(start_loc.bind(rid, id)), UI.GOOD]]
	match str(d.get("extra", "")):
		"museum":
			btns.append(["Lihat kartu", _show_cards.bind(rid), UI.PRIMARY])
		"hewan":
			btns.append(["Lihat hewan", _show_animals, UI.PRIMARY])
		"minigame":
			var mg := _minigame_for(rid)
			if not mg.is_empty():
				btns.append(["Main " + str(mg.name), _from_world.bind(start_minigame.bind(str(mg.id))), Color("e0813d")])
	hud.show_dialog(str(d.name), txt, btns)


func _show_cards(rid: String) -> void:
	var rows: Array = []
	for cid in p.cards:
		if data.topics.has(str(cid)) and str(data.topics[str(cid)].region) == rid:
			var c: Dictionary = data.topics[str(cid)].card
			rows.append("★ %s\n    %s" % [str(c.title), str(c.fact)])
	if rows.is_empty():
		rows.append("Belum ada kartu dari wilayah ini. Selesaikan area di gerbang untuk mendapatkannya!")
	hud.show_list("Kartu Pengetahuan · %s" % str(data.region(rid).subject), rows)


func _show_animals() -> void:
	var facts: Dictionary = data.doc.get("animal_facts", {})
	var rows: Array = []
	for an in p.animals:
		rows.append("• %s: %s" % [str(an).capitalize(), str(facts.get(str(an), ""))])
	if rows.is_empty():
		rows.append("Koleksi hewanmu masih kosong. Main mini-game Kelompokkan Hewan untuk mengumpulkannya!")
	hud.show_list("Koleksi Hewan (%d/%d)" % [(p.animals as Array).size(), facts.size()], rows)


func _on_world_zone(kind: String, id: String) -> void:
	var rid := str(p.world.region)
	match kind:
		"visit":
			var v: Dictionary = (p.world.visited as Dictionary).get(rid, {})
			if not v.has(id):
				v[id] = true
				p.world.visited[rid] = v
				var d := Locations.find(rid, id)
				toast("Lokasi baru: %s (%d/%d)" % [str(d.get("name", id)), v.size(), Locations.for_region(rid).size()])
				trail("3D kunjungi " + id)
				_check_missions()
		"item":
			var items: Array = (p.world.items as Dictionary).get(rid, [])
			if items.has(id):
				return
			items.append(id)
			p.world.items[rid] = items
			if world != null:
				world.remove_item(id)
			if audio != null:
				audio.play("bintang")
			toast("Kamu menemukan %s! (%d/%d)" % [str(world.ITEM_NAMES.get(rid, "benda")), items.size(), Missions.ITEMS_PER_ISLAND])
			trail("3D benda " + id)
			_check_missions()


func world_missions() -> Array:
	return Missions.build(p, data, grade(), str(p.world.region), Time.get_date_string_from_system())


## Hitung misi dari progres sah lalu beri hadiah yang belum diterima (sekali per misi).
func _check_missions() -> void:
	var got := Missions.award(p, world_missions(), Time.get_date_string_from_system())
	for m in got:
		toast("Misi selesai: %s! +%d koin, +%d XP%s" % [str(m.name), int(m.reward.coins), int(m.reward.xp),
			(", alat baru: " + Items.tool_name(str(m.item))) if str(m.get("item", "")) != "" else ""])
		trail("misi " + str(m.key))
	if not got.is_empty():
		_announce_badges()
		if audio != null:
			audio.play("bintang")
		if hud != null:
			for c in hud.chips.get_children():
				c.queue_free()
			hud.chips.add_child(_chip("Bintang %d" % SdProgress.total_stars(p), UI.GOLD))
			hud.chips.add_child(_chip("Koin %d" % int(p.coins), Color("ffd166")))
	save()


func show_missions() -> void:
	if hud == null:
		return
	var ms := world_missions()
	var done := 0
	for m in ms:
		if m.done:
			done += 1
	hud.show_list("Buku Petualangan · %s (%d/%d misi)" % [str(data.region(str(p.world.region)).name), done, ms.size()], Missions.lines(ms))


# --- Markas Pemain (Fase 7) --------------------------------------------------------------------------------

func _owned_outfits() -> Array:
	var out: Array = []
	for s in data.doc.get("shop", []):
		if str(s.get("slot", "")) == "outfit" and (p.owned as Array).has(str(s.id)):
			out.append({"id": str(s.id), "name": str(s.name), "color": Color.from_string(str(s.value), Color.WHITE)})
	return out


func _base_ctx() -> Dictionary:
	var ctx := _world_ctx(str(p.world.region))
	var animals: Array = []
	var pal := [Color("c98a4b"), Color("f4efe6"), Color("8a8174"), Color("e0a060"), Color("6b5a4a"), Color("f0d890")]
	for an in p.animals:
		animals.append({"id": str(an), "name": str(an).capitalize(), "color": pal[absi(hash(str(an))) % pal.size()]})
	var cards: Array = []
	for cid in p.cards:
		if data.topics.has(str(cid)):
			cards.append({"title": str(data.topics[str(cid)].card.title),
				"color": Color.from_string(str(data.region(str(data.topics[str(cid)].region)).get("color", "#3f7fd8")), UI.PRIMARY).lightened(0.3)})
	var badges: Array = []
	for b in data.doc.get("badges", []):
		if (p.badges as Dictionary).has(str(b.id)):
			badges.append(str(b.name))
	ctx.region = {"id": BASE_ID, "name": "Markas Pemain", "color": "#8a6bd8", "npc": "", "npc_color": "#8a6bd8", "intro": ""}
	ctx.topics = []
	ctx.base = {"name": str(p.player.name), "outfits": _owned_outfits(), "animals": animals, "cards": cards, "badges": badges}
	return ctx


func _wear(id: String) -> void:
	for o in _owned_outfits():
		if str(o.id) == id:
			p.player.avatar.outfit = id
			save()
			toast("Kostum dipakai: " + str(o.name))
			show_world(BASE_ID)
			return


func _pick_hero(h: String) -> void:
	set_setting("hero", h)
	show_world(BASE_ID)


func _book_rows() -> Array:
	var rows: Array = []
	var today := Time.get_date_string_from_system()
	for reg in data.regions:
		var ms := Missions.build(p, data, grade(), str(reg.id), today)
		var done := 0
		for m in ms:
			if m.done:
				done += 1
		rows.append("%s: %d/%d misi selesai" % [str(reg.name), done, ms.size()])
		for m in ms:
			if m.type == "utama":
				rows.append("    %s %s (%d/%d)" % ["✓" if m.done else "•", str(m.name), int(m.progress), int(m.goal)])
	rows.append("Benda ditemukan: %d · Lokasi selesai: %d · Pulau dikunjungi: %d/4" % [_count_items(), _count_locs(), (p.world.islands as Dictionary).size()])
	return rows


func _count_items() -> int:
	var n := 0
	for k in p.world.items:
		n += (p.world.items[k] as Array).size()
	return n


func _count_locs() -> int:
	var n := 0
	for k in p.world.locs:
		if bool(p.world.locs[k].get("done", false)):
			n += 1
	return n


# --- 2.3.0: tas, alat, pengacau ---------------------------------------------------------------------------

## Posisi tujuan berikutnya (untuk Kompas): gerbang pertama yang belum selesai, lalu penjaga wilayah.
func _objective_pos():
	if world == null or not world.ctx.has("topics"):
		return null
	for t in world.ctx.topics:
		if not t.done and world.gates.has(str(t.id)):
			return (world.gates[str(t.id)].node as Node3D).global_position
	var b := world.get_node_or_null("Boss")
	return b.global_position if b != null else null


func show_bag() -> void:
	if hud == null:
		return
	var btns: Array = []
	var rows: Array = ["ALAT PETUALANGAN (pakai satu):"]
	var cur := Items.equipped(p)
	for id in Items.TOOLS:
		var t: Dictionary = Items.TOOLS[id]
		if (p.world.inventory as Dictionary).has(id):
			rows.append("%s %s — %s" % ["▶" if id == cur else "•", str(t.name), str(t.desc)])
			if id != cur:
				btns.append(["Pakai " + str(t.name), _equip_tool.bind(id), UI.PRIMARY])
		else:
			rows.append("🔒 %s — didapat dari: %s" % [str(t.name), str(t.from)])
	rows.append("")
	rows.append("KOSTUM & AKSESORI (beli di menu Koleksi dengan koin):")
	for s in data.doc.get("shop", []):
		if (p.owned as Array).has(str(s.id)) and str(s.slot) in ["hat", "acc"]:
			var on := str(p.player.avatar.get(str(s.slot), "")) == str(s.id)
			rows.append("%s %s" % ["▶" if on else "•", str(s.name)])
			btns.append([("Lepas " if on else "Pakai ") + str(s.name), _wear_extra.bind(str(s.slot), "" if on else str(s.id)), Color("c98a4b")])
	rows.append("")
	rows.append("Pengacau dijinakkan: %d · Benda ditemukan: %d" % [int(p.world.get("tamed", 0)), _count_items()])
	hud.show_list("Tas Petualangan", rows, btns.slice(0, 4))


func _equip_tool(id: String) -> void:
	if (p.world.inventory as Dictionary).has(id):
		p.world.equip["alat"] = id
		save()
		toast("Alat dipakai: " + Items.tool_name(id))
		show_world(str(world.ctx.region.id) if world != null else "")
		if world != null:
			world.player.rig.play_once("pakai", 0.9)


func _wear_extra(slot: String, id: String) -> void:
	if id != "" and not (p.owned as Array).has(id):
		return
	p.player.avatar[slot] = id
	save()
	show_world(str(world.ctx.region.id) if world != null else "")


## Pengacau Lupa menyentuh pemain: soal cepat (pilihan ganda / benar-salah) dari topik wilayah kelas aktif.
var _foe: Node3D
var _foe_q: Dictionary = {}


func _quick_question(rid: String) -> Dictionary:
	var ts := data.topics_for(rid, grade())
	ts.shuffle()
	for t in ts:
		var picked := data.pick(str(t.id), grade(), 6, SdProgress.topic_stats(p, grade(), str(t.id)), rng)
		for q in picked.questions:
			if str(q.type) in ["mc", "tf"]:
				return q
	return {}


func _on_foe(n: Node3D) -> void:
	if hud == null or hud.dialog_open():
		world.foes.retreat(n)
		return
	var q := _quick_question(str(world.ctx.region.id))
	if q.is_empty():
		world.foes.tame(n)
		return
	_foe = n
	_foe_q = q
	world.foes.paused = true
	trail("3D pengacau " + str(q.get("id", "")))
	var opts: Array = []
	var right := 0
	if str(q.type) == "tf":
		opts = ["Benar", "Salah"]
		right = 0 if bool(q.answer) else 1
	else:
		opts = (q.options as Array).duplicate()
		right = int(q.answer)
	var order: Array = range(opts.size())
	if Items.equipped(p) == "jaring" and opts.size() > 2:
		var wrong: Array = order.filter(func(i): return i != right)
		order.erase(wrong[rng.randi_range(0, wrong.size() - 1)])
	var btns: Array = []
	for i in order:
		btns.append([str(opts[i]), _foe_answer.bind(i == right), UI.PRIMARY])
	hud.show_dialog("Pengacau Lupa!", "Ia mengacak ingatanmu! Jawab dengan benar untuk menjinakkannya:\n" + str(q.q), btns)


## Dialog ditutup tanpa menjawab: pengacau mundur (tanpa hadiah, tanpa catatan jawaban).
func _foe_cancel() -> void:
	if _foe != null and is_instance_valid(_foe) and world != null:
		world.foes.paused = false
		world.foes.retreat(_foe)
	_foe = null


func _foe_answer(correct: bool) -> void:
	if _foe == null or not is_instance_valid(_foe):
		return
	SdProgress.record_answer(p, grade(), _foe_q, correct, true)
	world.foes.paused = false
	if correct:
		p.world.tamed = int(p.world.get("tamed", 0)) + 1
		world.foes.tame(_foe)
		toast("Pengacau jinak! (%d dijinakkan)" % int(p.world.tamed))
		if audio != null:
			audio.play("benar")
	else:
		world.foes.retreat(_foe)
		toast("Belum tepat. %s" % str(_foe_q.get("explain", "Coba lagi nanti!")))
		if audio != null:
			audio.play("salah")
	_foe = null
	_announce_badges()
	_check_missions()


# --- Peta & wilayah --------------------------------------------------------------------------------------

func show_map() -> void:
	_world_return = ""
	var v := _clear("map")
	_header(v, "Peta Pulau Ilmu · Kelas %d" % grade())
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 520)
	v.add_child(holder)
	var map := SdArt.WorldMap.new()
	holder.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pos := [Vector2(0.2, 0.3), Vector2(0.72, 0.28), Vector2(0.28, 0.75), Vector2(0.78, 0.74)]
	for i in data.regions.size():
		var r: Dictionary = data.regions[i]
		var ts := data.topics_for(str(r.id), grade())
		var done := 0
		for t in ts:
			if SdProgress.area_rec(p, grade(), str(r.id), str(t.id)).get("done", false):
				done += 1
		map.islands.append({"pos": pos[i], "color": Color.from_string(str(r.color), UI.PRIMARY), "done": float(done) / maxf(1.0, ts.size())})
		var b := UI.button("%s\n%d/%d area" % [str(r.name), done, ts.size()], show_region.bind(str(r.id)), Color(1, 1, 1, 0.88), 24, 90)
		holder.add_child(b)
		b.anchor_left = pos[i].x
		b.anchor_right = pos[i].x
		b.anchor_top = pos[i].y
		b.anchor_bottom = pos[i].y
		b.offset_left = -150
		b.offset_right = 150
		b.offset_top = 10
		b.offset_bottom = 100


func show_region(region_id: String) -> void:
	var r := data.region(region_id)
	session = {"region": region_id}
	var v := _clear("region")
	_header(v, str(r.name), "map", Color.from_string(str(r.color), UI.PRIMARY))
	var row := UI.hbox(20)
	v.add_child(row)
	var npc := SdArt.Mascot.new(Color.from_string(str(r.npc_color), UI.GOLD), str(NPC_KIND.get(region_id, "profesor")))
	npc.custom_minimum_size = Vector2(150, 160)
	row.add_child(npc)
	var bubble := UI.panel(Color.WHITE)
	UI.expand(bubble)
	var intro := str(r.intro)
	if p.seen_intro.has(region_id):
		intro = "Halo lagi, %s! Pilih area yang ingin kamu jelajahi." % str(p.player.name)
	p.seen_intro[region_id] = true
	bubble.add_child(UI.label("%s:\n%s" % [str(r.npc), intro], 26, UI.INK))
	row.add_child(bubble)
	var ts := data.topics_for(region_id, grade())
	var path := UI.grid(3, 14)
	v.add_child(path)
	var all_done := true
	for i in ts.size():
		var t: Dictionary = ts[i]
		var rec := SdProgress.area_rec(p, grade(), region_id, str(t.id))
		var open: bool = i == 0 or SdProgress.area_rec(p, grade(), region_id, str(ts[i - 1].id)).get("done", false)
		var stars := int(rec.get("stars", 0))
		if not rec.get("done", false):
			all_done = false
		var state := "Terkunci"
		if rec.get("done", false):
			state = "★".repeat(stars) + "☆".repeat(3 - stars)
		elif open:
			state = "Terbuka"
		var b := UI.button("%d. %s\n%s" % [i + 1, str(t.name), state], start_area.bind(region_id, str(t.id)),
			Color.from_string(str(r.color), UI.PRIMARY).lightened(0.35) if open else Color("e8e2f2"), 24, 104)
		b.name = "Area_" + str(t.id)
		b.disabled = not open
		UI.expand(b)
		path.add_child(b)
	var ex_rec: Dictionary = SdProgress.grade_rec(p, grade()).exams.get(region_id, {})
	var bottom := UI.hbox(14)
	var exam_btn := UI.button("UJIAN AKHIR WILAYAH%s" % ((" (lulus, nilai %d)" % int(ex_rec.best)) if ex_rec.get("passed", false) else ""),
		start_exam.bind(region_id), UI.GOLD, 26, 90)
	exam_btn.name = "Exam"
	exam_btn.disabled = not all_done
	if not all_done:
		exam_btn.text = "Ujian akhir terbuka setelah semua area selesai"
	UI.expand(exam_btn)
	bottom.add_child(exam_btn)
	var mg := _minigame_for(region_id)
	if not mg.is_empty():
		var mb := UI.button("Mini-game: %s" % str(mg.name), start_minigame.bind(str(mg.id)), Color("e0813d"), 24, 90)
		UI.expand(mb)
		bottom.add_child(mb)
	v.add_child(bottom)


func _minigame_for(region_id: String) -> Dictionary:
	for m in SdMini.LIST:
		if str(m.region) == region_id:
			return m
	return {}


# --- Sesi soal (petualangan / latihan / kuis / ujian) -----------------------------------------------------

func start_area(region_id: String, topic_id: String) -> void:
	var st := SdProgress.topic_stats(p, grade(), topic_id)
	var picked := data.pick(topic_id, grade(), AREA_QUESTIONS, st, rng)
	_start_session({"kind": "petualangan", "mode": "petualangan", "region": region_id, "topic": topic_id,
		"questions": picked.questions, "adapt": picked.mode, "title": str(data.topics[topic_id].name),
		"story": str(data.topics[topic_id].story)})


func start_practice(topic_id: String) -> void:
	var st := SdProgress.topic_stats(p, grade(), topic_id)
	var picked := data.pick(topic_id, grade(), PRACTICE_QUESTIONS, st, rng)
	_start_session({"kind": "latihan", "mode": "latihan", "region": str(data.topics[topic_id].region), "topic": topic_id,
		"questions": picked.questions, "adapt": picked.mode, "title": "Latihan: " + str(data.topics[topic_id].name), "story": ""})


func start_quiz(region_id: String) -> void:
	var qs := data.pick_mixed(region_id, grade(), QUIZ_QUESTIONS, p.topics, rng)
	_start_session({"kind": "kuis", "mode": "kuis", "region": region_id, "topic": "", "questions": qs, "adapt": "normal",
		"title": "Kuis %s" % str(data.region(region_id).subject), "story": ""})


func start_exam(region_id: String) -> void:
	var qs := data.pick_mixed(region_id, grade(), EXAM_QUESTIONS, p.topics, rng)
	_start_session({"kind": "ujian", "mode": "kuis", "region": region_id, "topic": "", "questions": qs, "adapt": "normal",
		"title": "Ujian Akhir %s" % str(data.region(region_id).name), "story": "Jawab semua soal. Nilai 70 ke atas berarti lulus!"})


func _start_session(s: Dictionary) -> void:
	trail("sesi %s %s %s" % [str(s.get("mode", "")), str(s.get("region", "")), str(s.get("topic", ""))])
	session = s
	session.index = 0
	session.results = []
	session.coins = 0
	if (session.questions as Array).is_empty():
		toast("Belum ada soal untuk bagian ini.")
		show_home()
		return
	_show_question()


func _show_question() -> void:
	var v := _clear("session")
	var r := data.region(str(session.region))
	var h := UI.hbox(14)
	h.add_child(UI.button("Keluar", go_back, Color("cfc8dc"), 22, 60))
	var t := UI.label(str(session.title), 30, Color.from_string(str(r.get("color", "#3f7fd8")), UI.PRIMARY), false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(t)
	h.add_child(_chip("Soal %d/%d" % [int(session.index) + 1, (session.questions as Array).size()], Color("e8e2f2")))
	v.add_child(h)
	# Jalan petualangan: setiap jawaban benar menyalakan satu langkah hijau.
	var path := UI.hbox(8)
	var res: Array = session.results
	for i in (session.questions as Array).size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(40, 14)
		dot.color = Color("e8e2f2")
		if i < res.size():
			dot.color = UI.GOOD if res[i].first_try else Color("f5c26b")
		elif i == res.size():
			dot.color = UI.PRIMARY
		path.add_child(dot)
	v.add_child(path)
	if int(session.index) == 0 and str(session.story) != "":
		var sp := UI.panel(Color("fff3c4"))
		sp.add_child(UI.label(str(session.story), 24, UI.INK))
		v.add_child(sp)
	if int(session.index) == 0 and str(session.get("adapt", "")) == "mudah":
		v.add_child(UI.label("Kita latihan soal yang sedikit lebih mudah dulu, ya. Pelan-pelan saja!", 22, UI.SOFT))
	var card := UI.panel(Color.WHITE)
	v.add_child(card)
	var qv: VBoxContainer = SdQuestion.new()
	card.add_child(qv)
	qv.setup(session.questions[int(session.index)], str(session.mode), rng, data.doc.get("type_names", {}), audio)
	qv.finished.connect(_on_answer)
	_qview = qv


func current_question_view() -> Node:
	return _qview


func _on_answer(res: Dictionary) -> void:
	var q: Dictionary = res.question
	var coins := SdProgress.record_answer(p, grade(), q, bool(res.correct), bool(res.first_try))
	if bool(res.retried):
		p.retried = true
	(session.results as Array).append(res)
	session.coins = int(session.get("coins", 0)) + coins
	session.index = int(session.index) + 1
	_announce_badges()
	if int(session.index) >= (session.questions as Array).size():
		_finish_session()
	else:
		_show_question()


func _finish_session() -> void:
	var res: Array = session.results
	var correct := 0
	for r in res:
		if r.first_try:
			correct += 1
	var total := res.size()
	var score := int(round(100.0 * correct / maxf(1.0, total)))
	var region := str(session.region)
	var subject := str(data.region(region).subject)
	var reward := {}
	match str(session.kind):
		"petualangan":
			reward = SdProgress.finish_area(p, grade(), region, data.topics[str(session.topic)], correct, total)
			SdProgress.add_history(p, "petualangan", subject, str(data.topics[str(session.topic)].name), grade(), correct, total)
		"latihan":
			SdProgress.add_history(p, "latihan", subject, str(data.topics[str(session.topic)].name), grade(), correct, total)
		"kuis":
			reward = SdProgress.finish_quiz(p, grade(), region, score)
			if _world_return != "" and score >= CHEST_SCORE:
				(p.world.chests as Dictionary)[_wkey(region)] = true
			SdProgress.add_history(p, "kuis", subject, "Kuis", grade(), correct, total)
		"lokasi":
			var ld := Locations.find(region, str(session.loc))
			SdProgress.add_history(p, "lokasi", subject, str(ld.get("name", "Lokasi")), grade(), correct, total)
			if correct >= LOC_PASS:
				var lk := _wkey(region) + "/" + str(session.loc)
				var first := not bool((p.world.locs as Dictionary).get(lk, {}).get("done", false))
				(p.world.locs as Dictionary)[lk] = {"done": true}
				var today := Time.get_date_string_from_system()
				p.world.daily_locs[today] = int((p.world.daily_locs as Dictionary).get(today, 0)) + 1
				reward = {"loc_done": true, "first": first}
			else:
				reward = {"loc_done": false}
		"ujian":
			reward = SdProgress.finish_exam(p, grade(), region, score)
			SdProgress.add_history(p, "ujian", subject, "Ujian akhir", grade(), correct, total)
	session.score = score
	session.reward = reward
	_announce_badges()
	save()
	_show_result(correct, total, score, reward)


func _show_result(correct: int, total: int, score: int, reward: Dictionary) -> void:
	var kind := str(session.kind)
	var back := "region" if kind in ["petualangan", "ujian"] else "subjects"
	if _world_return != "":
		back = "world"
	var v := _clear("result")
	_header(v, "Hasil " + str(session.title), back)
	var row := UI.hbox(24)
	v.add_child(row)
	var av := SdArt.Avatar.new()
	av.mood = "kagum"
	_apply_look(av)
	row.add_child(av)
	var col := UI.vbox(8)
	UI.expand(col)
	row.add_child(col)
	var head := "Luar biasa!" if score >= 90 else ("Kerja bagus!" if score >= 60 else "Terima kasih sudah berusaha! Ayo coba lagi.")
	col.add_child(UI.label(head, 44, UI.GOOD if score >= 60 else UI.PRIMARY))
	col.add_child(UI.label("%d dari %d benar pada percobaan pertama  ·  nilai %d" % [correct, total, score], 28, UI.INK))
	var coins := int(session.get("coins", 0)) + int(reward.get("coins", 0))
	var lines: PackedStringArray = ["+%d koin" % coins]
	if reward.has("stars"):
		lines.append("%s (%d bintang)" % ["★".repeat(int(reward.stars)) + "☆".repeat(3 - int(reward.stars)), int(reward.stars)])
	if str(reward.get("card", "")) != "":
		lines.append("Kartu baru: %s" % str(data.topics[str(reward.card)].card.title))
	if kind == "ujian":
		lines.append("LULUS UJIAN!" if reward.get("passed", false) else "Belum lulus (butuh nilai 70). Coba lagi, ya!")
	if kind == "lokasi":
		lines.append("Lokasi selesai!" if reward.get("loc_done", false) else "Butuh %d jawaban benar. Coba lagi, ya!" % LOC_PASS)
	var reward_lbl := UI.label("   ".join(lines), 30, UI.INK)
	col.add_child(reward_lbl)
	if audio != null and (int(reward.get("stars", 0)) > 0 or reward.get("passed", false)):
		audio.play("bintang")
	UI.pop.call_deferred(reward_lbl)
	var btns := UI.hbox(14)
	var again := UI.button("Coba lagi", _repeat_session, UI.PRIMARY, 26, 84)
	UI.expand(again)
	btns.add_child(again)
	var nxt := UI.button("Lanjut", go_back, UI.GOOD, 26, 84)
	nxt.name = "Next"
	UI.expand(nxt)
	btns.add_child(nxt)
	v.add_child(btns)
	v.add_child(UI.label("Pembahasan", 30, UI.PRIMARY))
	for res in session.results:
		var ok: bool = res.first_try
		var text := "%s %s\nJawabanmu: %s%s\n%s" % ["✓" if ok else "•", str(res.question.q), str(res.given),
			"" if ok else "   ·   Jawaban tepat: %s" % str(res.answer), str(res.explain)]
		var pnl := UI.panel(Color("eaf7ee") if ok else Color("fff1e6"))
		pnl.add_child(UI.label(text, 20, UI.INK))
		v.add_child(pnl)


func _repeat_session() -> void:
	match str(session.kind):
		"petualangan":
			start_area(str(session.region), str(session.topic))
		"latihan":
			start_practice(str(session.topic))
		"kuis":
			start_quiz(str(session.region))
		"ujian":
			start_exam(str(session.region))
		"lokasi":
			start_loc(str(session.region), str(session.loc))


func _confirm_leave_session() -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = "Keluar dari sesi ini? Jawaban yang sudah dikerjakan tetap tercatat."
	d.ok_button_text = "Keluar"
	d.cancel_button_text = "Lanjut belajar"
	add_child(d)
	d.confirmed.connect(leave_session)
	d.popup_centered(Vector2i(620, 220))


func leave_session() -> void:
	save()
	if _world_return != "":
		show_world(_world_return)
		return
	if str(session.get("kind", "")) in ["petualangan", "ujian"]:
		show_region(str(session.region))
	else:
		show_subjects()


# --- Pilih pelajaran (latihan & kuis) ----------------------------------------------------------------------

func show_subjects() -> void:
	_world_return = ""
	var v := _clear("subjects")
	_header(v, "Pilih Pelajaran · Kelas %d" % grade())
	v.add_child(UI.label("Latihan: tanpa batas waktu, boleh mencoba lagi, ada petunjuk. Kuis: 10 soal, nilai, pembahasan di akhir.", 22, UI.SOFT))
	for r in data.regions:
		var pnl := UI.panel(Color.from_string(str(r.color), UI.PRIMARY).lightened(0.62))
		var col := UI.vbox(10)
		pnl.add_child(col)
		var head := UI.hbox()
		var t := UI.label(str(r.subject), 32, UI.INK, false)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var qrec: Dictionary = SdProgress.grade_rec(p, grade()).quiz.get(str(r.id), {})
		head.add_child(UI.button("Kuis%s" % ((" (terbaik %d)" % int(qrec.best)) if qrec.has("best") else ""), start_quiz.bind(str(r.id)), UI.GOLD, 24, 64))
		col.add_child(head)
		var g := UI.grid(3, 10)
		for tp in data.topics_for(str(r.id), grade()):
			var b := UI.button("Latihan: %s" % _short(str(tp.name)), start_practice.bind(str(tp.id)), Color.WHITE, 22, 70)
			UI.expand(b)
			g.add_child(b)
		col.add_child(g)
		v.add_child(pnl)


static func _short(name: String) -> String:
	for w in ["Lembah ", "Jembatan ", "Gua ", "Menara ", "Pasar ", "Taman ", "Bengkel ", "Lapangan ", "Gudang ", "Gerbang ",
			"Pohon ", "Jalan Setapak ", "Sungai ", "Danau ", "Perpustakaan ", "Panggung ", "Gubuk ", "Ruang ", "Kebun ", "Rumah ",
			"Meja Percobaan ", "Akuarium ", "Teropong ", "Desa ", "Alun-alun ", "Pelabuhan ", "Bukit ", "Museum ", "Pulau "]:
		if name.begins_with(w):
			return name.substr(w.length())
	return name


# --- Mini-game ---------------------------------------------------------------------------------------------

func show_minigames() -> void:
	_world_return = ""
	var v := _clear("minigames")
	_header(v, "Mini-game")
	var g := UI.grid(2, 16)
	v.add_child(g)
	for m in SdMini.LIST:
		var r := data.region(str(m.region))
		var rec: Dictionary = p.minigames.get(str(m.id), {})
		var b := UI.button("%s\n%s%s" % [str(m.name), str(r.subject), ("  ·  terbaik %d" % int(rec.best)) if rec.has("best") else ""],
			start_minigame.bind(str(m.id)), Color.from_string(str(r.color), UI.PRIMARY), 26, 130)
		UI.expand(b)
		g.add_child(b)


func start_minigame(id: String) -> void:
	trail("mini-game " + id)
	var info := SdMini.info(id)
	var from := screen if screen in ["region", "minigames", "minigame", "world"] else "minigames"
	if from == "minigame":
		from = str(session.get("from", "minigames"))
	session = {"kind": "minigame", "region": str(info.region), "mg": id, "from": from}
	var v := _clear("minigame")
	_header(v, str(info.name), "home")
	v.add_child(UI.label(str(info.goal), 24, UI.SOFT))
	var card := UI.panel(Color.WHITE)
	v.add_child(card)
	var mg := SdMini.create(id)
	card.add_child(mg)
	mg.setup(grade(), data.doc, rng, audio)
	mg.done.connect(_on_minigame_done.bind(id))
	_qview = mg


func _on_minigame_done(score: int, total: int, extra: Dictionary, id: String) -> void:
	var coins := SdProgress.finish_minigame(p, id, score, total)
	for an in extra.get("animals", []):
		if not (p.animals as Array).has(an):
			(p.animals as Array).append(an)
	SdProgress.add_history(p, "mini-game", str(data.region(str(session.region)).subject), str(SdMini.info(id).name), grade(), score, total)
	_announce_badges()
	save()
	toast("Mini-game selesai! +%d koin" % coins)
	if audio != null:
		audio.play("bintang")
	if screen == "minigame" and page() != null:
		var row := UI.hbox(14)
		var again := UI.button("Main lagi", start_minigame.bind(id), UI.PRIMARY, 26, 80)
		UI.expand(again)
		row.add_child(again)
		var back := UI.button("Selesai", _back_from_minigame, UI.GOOD, 26, 80)
		UI.expand(back)
		row.add_child(back)
		page().add_child(row)


func _back_from_minigame() -> void:
	if str(session.get("from", "")) == "world":
		show_world(str(session.region))
	elif str(session.get("from", "")) == "region":
		show_region(str(session.region))
	else:
		show_minigames()


# --- Koleksi, prestasi, laporan, pengaturan ----------------------------------------------------------------

func show_collection(tab: String = "kostum") -> void:
	var v := _clear("collection")
	_header(v, "Koleksi")
	var tabs := UI.hbox(12)
	for t in [["kostum", "Kostum"], ["kartu", "Kartu Pengetahuan"], ["hewan", "Koleksi Hewan"]]:
		var b := UI.button(t[1], show_collection.bind(t[0]), UI.PRIMARY if t[0] == tab else Color("e8e2f2"), 24, 64)
		UI.expand(b)
		tabs.add_child(b)
	v.add_child(tabs)
	match tab:
		"kostum":
			var row := UI.hbox(24)
			var av := SdArt.Avatar.new()
			av.custom_minimum_size = Vector2(180, 210)
			_apply_look(av)
			row.add_child(av)
			var g := UI.grid(3, 12)
			UI.expand(g)
			for s in data.doc.get("shop", []):
				var owned := (p.owned as Array).has(str(s.id))
				var worn := str(p.player.avatar.get(str(s.slot), "")) == str(s.id)
				var label := "%s\n%s" % [str(s.name), "Dipakai" if worn else ("Pakai" if owned else "%d koin" % int(s.price))]
				var b := UI.button(label, shop_item.bind(str(s.id)), UI.GOOD if worn else (Color("9ad8a6") if owned else Color("ffd166")), 22, 84)
				UI.expand(b)
				g.add_child(b)
			row.add_child(g)
			v.add_child(row)
			v.add_child(UI.label("Koin didapat dari belajar dan bermain. Tidak ada pembelian dengan uang sungguhan.", 20, UI.SOFT))
		"kartu":
			var cards: Array = p.cards
			v.add_child(UI.label("%d dari %d kartu terkumpul. Selesaikan area petualangan untuk mendapat kartu." % [cards.size(), data.topics.size()], 22, UI.SOFT))
			var g := UI.grid(3, 12)
			for id in data.topics:
				var t: Dictionary = data.topics[id]
				var have := cards.has(str(id))
				var pnl := UI.panel(Color("fff3c4") if have else Color("ece8f2"))
				UI.expand(pnl)
				pnl.add_child(UI.label(("%s\n%s" % [str(t.card.title), str(t.card.fact)]) if have else "???\n(%s)" % str(t.name), 20, UI.INK if have else UI.SOFT))
				g.add_child(pnl)
			v.add_child(g)
		"hewan":
			var animals: Array = p.animals
			var facts: Dictionary = data.doc.get("animal_facts", {})
			v.add_child(UI.label("%d dari %d hewan. Mainkan mini-game Kelompokkan Hewan untuk mengumpulkannya." % [animals.size(), facts.size()], 22, UI.SOFT))
			var g := UI.grid(3, 12)
			for an in facts:
				var have := animals.has(an)
				var pnl := UI.panel(Color("e3f7ef") if have else Color("ece8f2"))
				UI.expand(pnl)
				pnl.add_child(UI.label(("%s\n%s" % [str(an).capitalize(), str(facts[an])]) if have else "???", 20, UI.INK if have else UI.SOFT))
				g.add_child(pnl)
			v.add_child(g)


## Beli (dengan koin) atau pakai/lepas kostum. Mengembalikan true bila berhasil.
func shop_item(id: String) -> bool:
	for s in data.doc.get("shop", []):
		if str(s.id) != id:
			continue
		if not (p.owned as Array).has(id):
			if int(p.coins) < int(s.price):
				toast("Koin belum cukup. Ayo belajar lagi untuk mengumpulkan koin!")
				return false
			p.coins = int(p.coins) - int(s.price)
			(p.owned as Array).append(id)
			if audio != null:
				audio.play("bintang")
		var slot := str(s.slot)
		p.player.avatar[slot] = "" if str(p.player.avatar.get(slot, "")) == id and slot != "outfit" else id
		save()
		if screen == "collection":
			show_collection("kostum")
		return true
	return false


func show_badges() -> void:
	var v := _clear("badges")
	_header(v, "Prestasi")
	var g := UI.grid(3, 12)
	for b in data.doc.get("badges", []):
		var have: bool = p.badges.has(str(b.id))
		var pnl := UI.panel(Color("fff3c4") if have else Color("ece8f2"))
		UI.expand(pnl)
		pnl.add_child(UI.label("%s %s\n%s%s" % ["★" if have else "☆", str(b.name), str(b.desc), ("\nDidapat %s" % str(p.badges[str(b.id)])) if have else ""],
			22, UI.INK if have else UI.SOFT))
		g.add_child(pnl)
	v.add_child(g)


func show_report() -> void:
	var v := _clear("report")
	_header(v, "Laporan Belajar %s" % str(p.player.name))
	var rep := SdProgress.report(p, data)
	var top := UI.grid(3, 12)
	for item in [["Soal dikerjakan", rep.answered], ["Benar pada percobaan pertama", rep.correct], ["Sedang dilatih", rep.wrong]]:
		var pnl := UI.panel(Color.WHITE)
		UI.expand(pnl)
		pnl.add_child(UI.label("%s\n%d" % [item[0], int(item[1])], 26, UI.INK))
		top.add_child(pnl)
	v.add_child(top)
	v.add_child(UI.label("Nilai per mata pelajaran", 28, UI.PRIMARY))
	for rid in rep.subjects:
		var s: Dictionary = rep.subjects[rid]
		var row := UI.hbox(12)
		var l := UI.label(str(s.name), 24, UI.INK, false)
		l.custom_minimum_size = Vector2(260, 0)
		row.add_child(l)
		var pb := UI.progress(100.0 * int(s.correct) / maxf(1.0, int(s.total)), 100, UI.GOOD, 26)
		UI.expand(pb)
		row.add_child(pb)
		row.add_child(UI.label(("%d/%d" % [int(s.correct), int(s.total)]) if int(s.total) > 0 else "belum ada", 22, UI.SOFT, false))
		v.add_child(row)
	var mastered: Array = rep.mastered
	var practice: Array = rep.practice
	v.add_child(UI.label("Sudah dikuasai", 28, UI.GOOD))
	v.add_child(UI.label(", ".join(PackedStringArray(mastered)) if not mastered.is_empty() else "Terus berlatih! Materi ditandai dikuasai setelah cukup sering dikerjakan dengan baik.", 22, UI.INK))
	v.add_child(UI.label("Ayo dilatih lagi", 28, Color("e0813d")))
	v.add_child(UI.label(", ".join(PackedStringArray(practice)) if not practice.is_empty() else "Belum ada. Hebat!", 22, UI.INK))
	if int(rep.little_data) > 0:
		v.add_child(UI.label("%d materi baru sedikit dikerjakan, jadi belum dinilai. Itu wajar!" % int(rep.little_data), 20, UI.SOFT))
	v.add_child(UI.label("Perkembangan 7 hari terakhir", 28, UI.PRIMARY))
	var chart := UI.hbox(10)
	chart.custom_minimum_size = Vector2(0, 170)
	for d in rep.trend:
		var col := UI.vbox(4)
		col.alignment = BoxContainer.ALIGNMENT_END
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var bar := ColorRect.new()
		var rate := float(d.correct) / maxf(1.0, d.total)
		bar.custom_minimum_size = Vector2(60, 20 + 110 * rate)
		bar.color = UI.GOOD.lerp(UI.GOLD, 1.0 - rate)
		col.add_child(bar)
		col.add_child(UI.label("%s\n%d/%d" % [str(d.day).substr(5), int(d.correct), int(d.total)], 16, UI.SOFT, false))
		chart.add_child(col)
	if (rep.trend as Array).is_empty():
		chart.add_child(UI.label("Belum ada data.", 22, UI.SOFT))
	v.add_child(chart)
	v.add_child(UI.label("Riwayat latihan", 28, UI.PRIMARY))
	for h in rep.history:
		v.add_child(UI.label("%s · %s · %s %s · %d/%d" % [str(h.at), str(h.mode), str(h.subject), str(h.topic), int(h.correct), int(h.total)], 20, UI.INK))


func show_settings() -> void:
	var v := _clear("settings")
	_header(v, "Pengaturan")
	var name_edit := UI.line_edit(str(p.player.name), "Tulis namamu", 30)
	var nrow := UI.hbox(12)
	nrow.add_child(UI.label("Nama", 26, UI.INK, false))
	UI.expand(name_edit)
	nrow.add_child(name_edit)
	nrow.add_child(UI.button("Simpan", func() -> void:
		if name_edit.text.strip_edges() != "":
			set_player(name_edit.text.strip_edges(), grade())
			toast("Nama disimpan."), UI.GOOD, 24, 70))
	v.add_child(nrow)
	v.add_child(UI.label("Kelas aktif (progres kelas lain tetap tersimpan)", 26, UI.INK))
	var g := UI.grid(6, 10)
	for k in range(1, 7):
		var b := UI.button("Kelas %d" % k, change_grade.bind(k), UI.GOLD if k == grade() else Color("e8e2f2"), 26, 80)
		UI.expand(b)
		g.add_child(b)
	v.add_child(g)
	var arow := UI.hbox(12)
	for item in [["music", "Musik"], ["sfx", "Efek suara"]]:
		var on: bool = p.settings[item[0]]
		var b := UI.button("%s: %s" % [item[1], "NYALA" if on else "MATI"], toggle_setting.bind(item[0]), UI.GOOD if on else Color("cfc8dc"), 26, 80)
		UI.expand(b)
		arow.add_child(b)
	v.add_child(arow)
	v.add_child(UI.label("Dunia 3D", 26, UI.INK))
	var hrow := UI.hbox(12)
	for h in [["laki", "Karakter: Laki-laki"], ["perempuan", "Karakter: Perempuan"], ["petualang", "Karakter: Petualang (model 3D)"]]:
		var b := UI.button(h[1], set_setting.bind("hero", h[0]), UI.GOLD if str(p.settings.hero) == h[0] else Color("e8e2f2"), 24, 76)
		UI.expand(b)
		hrow.add_child(b)
	v.add_child(hrow)
	var grow := UI.hbox(12)
	for gp in [["hemat", "Grafis: Hemat"], ["seimbang", "Grafis: Seimbang"], ["tinggi", "Grafis: Tinggi"]]:
		var b := UI.button(gp[1], set_setting.bind("gfx", gp[0]), UI.GOLD if str(p.settings.gfx) == gp[0] else Color("e8e2f2"), 24, 76)
		UI.expand(b)
		grow.add_child(b)
	v.add_child(grow)
	var perf_on := bool(p.settings.get("perf", false))
	v.add_child(UI.button("Info kinerja di dunia 3D (FPS, draw call, RAM): %s" % ("NYALA" if perf_on else "MATI"), toggle_setting.bind("perf"),
		UI.GOOD if perf_on else Color("cfc8dc"), 22, 70))
	v.add_child(UI.label("Hemat: untuk HP ringan (tanpa bayangan, resolusi 3D lebih rendah). Tinggi: tampilan terbaik.", 20, UI.SOFT))
	v.add_child(UI.button("Kembali ke Launcher", _confirm_exit.bind("tombol pengaturan"), Color("8a9bb8"), 26, 80))


func change_grade(k: int) -> void:
	set_player(str(p.player.name), k)
	if screen == "settings":
		show_settings()
	toast("Sekarang belajar materi kelas %d." % k)


func set_setting(key: String, value: String) -> void:
	p.settings[key] = value
	save()
	if screen == "settings":
		show_settings()


func toggle_setting(key: String) -> void:
	p.settings[key] = not bool(p.settings[key])
	audio.apply(bool(p.settings.music), bool(p.settings.sfx))
	save()
	if screen == "settings":
		show_settings()


# --- Umpan balik ---------------------------------------------------------------------------------------------

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


func _announce_badges() -> void:
	var got := SdProgress.check_badges(p, data.doc, data.regions)
	for id in got:
		for b in data.doc.get("badges", []):
			if str(b.id) == id:
				toast("Lencana baru: %s!" % str(b.name))
				if audio != null:
					audio.play("bintang")
