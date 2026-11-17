extends Control
## Layar pertarungan bergiliran: arena 3D kecil (pahlawan vs musuh), bar HP, catatan, dan tombol aksi
## Serang / Jurus Ilmu / Bertahan / Barang / Kabur. Jurus Ilmu membuka satu soal sesuai kelas anak
## (petunjuk & mencoba lagi tetap ada); benar tanpa salah = jurus paling kuat.

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const SdQuestion := preload("res://games/education_sd/scripts/sd_question.gd")
const Battle := preload("res://games/education_sd/scripts/engine/battle_engine.gd")
const Learning := preload("res://games/education_sd/scripts/engine/learning_engine.gd")

signal finished(result: Dictionary)
signal changed

const ROOM_OF := {"matematika": "matematika", "bahasa": "bahasa", "ipa": "ipas_alam", "ips": "ipas_sosial", "pancasila": "pancasila",
	"seni": "seni", "pjok": "olahraga"}

var engine := Battle.new()
var learning
var rewards
var p: Dictionary
var rng: RandomNumberGenerator
var audio: Node
var type_names: Dictionary
var monster_id := ""
var monster: Dictionary
var uid := ""
var phase := ""  # "pilih" | "soal" | "barang" | "selesai"
var qview: Node
var hero_rig: Node3D
var foe_rig: Node3D
var _hp_me: ProgressBar
var _hp_foe: ProgressBar
var _hp_me_lbl: Label
var _hp_foe_lbl: Label
var _log: Label
var _actions: Container
var _sheet: PanelContainer
var _sheet_box: VBoxContainer
var _ilmu_n := 0
var result: Dictionary = {}
var grade := 1


func setup(learning_engine, reward_engine, progress: Dictionary, random: RandomNumberGenerator, sound: Node, names: Dictionary,
		m_id: String, m_def: Dictionary, spawn_uid: String, hero_look: Dictionary, seed_value := -1, learn_grade := 0) -> void:
	grade = learn_grade if learn_grade > 0 else int(progress.profile.grade)
	learning = learning_engine
	rewards = reward_engine
	p = progress
	rng = random
	audio = sound
	type_names = names
	monster_id = m_id
	monster = m_def
	uid = spawn_uid
	var ease := int((p.world.get("battle_losses", {}) as Dictionary).get(m_id, 0))
	engine.start(rewards.stats(p), m_id, m_def, ease, seed_value)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var s := get_viewport_rect().size
	var bg := ColorRect.new()
	bg.color = Color("2b2440")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arena(hero_look, s)
	var top := UI.hbox(16)
	top.position = Vector2(20, 14)
	top.size = Vector2(s.x - 40, 0)
	add_child(top)
	var me := UI.vbox(2)
	UI.expand(me)
	_hp_me_lbl = UI.label("", 24, Color.WHITE, false)
	me.add_child(_hp_me_lbl)
	_hp_me = UI.progress(1, 1, UI.GOOD, 22)
	me.add_child(_hp_me)
	top.add_child(me)
	var foe := UI.vbox(2)
	UI.expand(foe)
	_hp_foe_lbl = UI.label("", 24, Color("ffd166"), false)
	_hp_foe_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foe.add_child(_hp_foe_lbl)
	_hp_foe = UI.progress(1, 1, Color("e05a4f"), 22)
	foe.add_child(_hp_foe)
	top.add_child(foe)
	var bottom := UI.panel(Color(1, 1, 1, 0.94), 24)
	bottom.position = Vector2(20, s.y * 0.62)
	bottom.size = Vector2(s.x - 40, s.y * 0.36)
	bottom.custom_minimum_size = bottom.size
	add_child(bottom)
	var bv := UI.vbox(10)
	bottom.add_child(bv)
	_log = UI.label("", 24, UI.INK)
	_log.name = "Log"
	_log.custom_minimum_size = Vector2(s.x - 90, 0)
	bv.add_child(_log)
	_actions = UI.hbox(10)
	bv.add_child(_actions)
	for a in [["Serang", "serang", Color("e0813d")], ["Jurus Ilmu", "ilmu", Color("8a6bd8")], ["Bertahan", "bertahan", UI.PRIMARY],
			["Barang", "barang", Color("c98a4b")], ["Kabur", "kabur", Color("cfc8dc")]]:
		var b := UI.button(str(a[0]), choose.bind(str(a[1])), a[2], 26, 76)
		b.name = "Act_" + str(a[1])
		UI.expand(b)
		if str(a[1]) == "kabur" and bool(monster.get("boss", false)):
			b.disabled = true
		_actions.add_child(b)
	_sheet = UI.panel(Color("fdf6e3"), 26)
	_sheet.name = "Sheet"
	_sheet.position = Vector2(s.x * 0.06, s.y * 0.04)
	_sheet.size = Vector2(s.x * 0.88, s.y * 0.92)
	_sheet.custom_minimum_size = _sheet.size
	_sheet.visible = false
	add_child(_sheet)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet.add_child(scroll)
	_sheet_box = UI.vbox(12)
	_sheet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sheet_box)
	phase = "pilih"
	_say(str(engine.history[0]) + ("\n" + _hint_text() if bool(monster.get("boss", false)) else ""))
	_refresh()


func _hint_text() -> String:
	return "Petunjuk: %s hanya bisa ditembus Jurus Ilmu!" % str(monster.get("shield", "Perisai"))


func _arena(hero_look: Dictionary, s: Vector2) -> void:
	var box := SubViewportContainer.new()
	box.name = "Arena"
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(0, s.y * 0.1)
	box.size = Vector2(s.x, s.y * 0.55)
	add_child(box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	box.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8cc8ff") if not bool(monster.get("boss", false)) else Color("6a4a7a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("fff3e0")
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = Rig.cyl(6.0, 6.0, 0.2, 40)
	ground.material_override = Rig.mat(Color("7cc95a") if not bool(monster.get("boss", false)) else Color("8a8174"))
	ground.position.y = -0.1
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.25, 3.7)
	cam.rotation.x = -0.12
	cam.fov = 45.0
	vp.add_child(cam)
	hero_rig = Rig.new()
	hero_rig.shirt = hero_look.get("shirt", Color("e05a4f"))
	hero_rig.long_hair = bool(hero_look.get("long_hair", false))
	hero_rig.hat = str(hero_look.get("hat", ""))
	hero_rig.acc = str(hero_look.get("acc", ""))
	if str(hero_look.get("model_path", "")) != "":
		hero_rig.glb_path = str(hero_look.model_path)
		hero_rig.glb_height = 1.47
		hero_rig.glb_recolor = {"Baju": hero_rig.shirt}
	hero_rig.position = Vector3(-1.25, 0, 0)
	hero_rig.rotation.y = PI / 2.0
	vp.add_child(hero_rig)
	hero_rig.build()
	if hero_rig.is_glb():
		hero_rig.attach_costume()
	foe_rig = Rig.new()
	foe_rig.glb_id = str(monster.get("model", "goblin"))
	foe_rig.glb_height = float(monster.get("height", 1.0)) * (1.15 if bool(monster.get("boss", false)) else 1.0)
	if str(monster.get("tint", "")) != "":
		foe_rig.glb_tint = Color.from_string(str(monster.tint), Color.WHITE)
	foe_rig.position = Vector3(1.3, 0, 0)
	foe_rig.rotation.y = -PI / 2.0
	vp.add_child(foe_rig)
	foe_rig.build()


func _process(delta: float) -> void:
	for r in [hero_rig, foe_rig]:
		if r != null and r.has_method("animate"):
			r.animate(delta, 0.0, true)


func _sfx(n: String) -> void:
	if audio != null:
		audio.play(n)


func _say(text: String) -> void:
	_log.text = text


func _refresh() -> void:
	_hp_me.max_value = int(engine.player.max)
	_hp_me.value = int(engine.player.hp)
	_hp_me_lbl.text = "%s  HP %d/%d" % [str(p.profile.name), int(engine.player.hp), int(engine.player.max)]
	_hp_foe.max_value = int(engine.enemy.max)
	_hp_foe.value = int(engine.enemy.hp)
	_hp_foe_lbl.text = "%s Lv%d  HP %d/%d%s" % [str(monster.name), int(monster.get("level", 1)), int(engine.enemy.hp), int(engine.enemy.max),
		"  [%s]" % str(monster.get("shield", "")) if engine.shield_up() else ""]
	var has_items := false
	for it in ["kue", "ramuan_ilmu", "perisai_daun"]:
		if int((p.rpg.get("items", {}) as Dictionary).get(it, 0)) > 0:
			has_items = true
	(_actions.get_node("Act_barang") as Button).disabled = not has_items


func choose(action: String) -> void:
	if engine.over or phase != "pilih":
		return
	match action:
		"ilmu":
			_open_question()
		"barang":
			_open_items()
		_:
			_apply(action, {})


func _apply(action: String, arg: Dictionary) -> void:
	var out: Dictionary = engine.act(action, arg)
	if int(out.enemy_dmg) > 0:
		hero_rig.play_once("interaksi", 0.6)
		foe_rig.play_once("kena", 0.5)
		_sfx("benar")
	if int(out.player_dmg) > 0:
		foe_rig.play_once("interaksi", 0.6)
		hero_rig.play_once("kena", 0.5)
	_say("\n".join(out.text))
	_refresh()
	if engine.over:
		_end()


# --- Jurus Ilmu: satu soal -------------------------------------------------------------------------------------

func _topic() -> String:
	var subj := str(monster.get("subject", "campur"))
	var regions: Array = ["matematika", "bahasa", "ipa", "ips", "pancasila", "seni", "pjok"]
	var region: String = str(regions[_ilmu_n % regions.size()]) if subj == "campur" else subj
	# Latihan penguatan: topik yang perlu dilatih lebih sering muncul (lihat Learning.pick_topic).
	var t: String = learning.pick_topic(p, str(ROOM_OF.get(region, "matematika")), grade, rng)
	if t == "":
		t = learning.pick_topic(p, "matematika", grade, rng)
	return t if t != "" else "penjumlahan"


func _open_question() -> void:
	phase = "soal"
	var ses: Dictionary = learning.start(p, _topic(), grade, rng, 1)
	_ilmu_n += 1
	if (ses.questions as Array).is_empty():
		phase = "pilih"
		return
	_sheet.set_meta("session", ses)
	for c in _sheet_box.get_children():
		_sheet_box.remove_child(c)
		c.queue_free()
	var t := UI.label("Jurus Ilmu! Jawab soal ini untuk menyerang %s." % str(monster.name), 28, Color("8a6bd8"))
	_sheet_box.add_child(t)
	qview = SdQuestion.new()
	qview.name = "Question"
	_sheet_box.add_child(qview)
	qview.setup(ses.questions[0], "latihan", rng, type_names, audio)
	qview.finished.connect(_on_answer)
	_sheet.visible = true
	UI.guard(250)


func current_question_view() -> Node:
	return qview


func _on_answer(res: Dictionary) -> void:
	var ses: Dictionary = _sheet.get_meta("session")
	Learning.answer(p, ses, res.question, bool(res.correct), bool(res.first_try), str(res.get("first_wrong", "")))
	changed.emit()
	_sheet.visible = false
	qview = null
	phase = "pilih"
	_apply("ilmu", {"correct": bool(res.correct), "first_try": bool(res.first_try)})


# --- Barang ------------------------------------------------------------------------------------------------------

func _open_items() -> void:
	phase = "barang"
	for c in _sheet_box.get_children():
		_sheet_box.remove_child(c)
		c.queue_free()
	var h := UI.hbox(10)
	var back := UI.button("Kembali", func() -> void:
		_sheet.visible = false
		phase = "pilih", Color("cfc8dc"), 22, 60)
	back.name = "ItemsBack"
	h.add_child(back)
	h.add_child(UI.label("Pakai barang", 30, UI.PRIMARY, false))
	_sheet_box.add_child(h)
	for it in ["kue", "ramuan_ilmu", "perisai_daun"]:
		var n := int((p.rpg.get("items", {}) as Dictionary).get(it, 0))
		if n <= 0:
			continue
		var inf: Dictionary = rewards.info(it)
		var b := UI.button("%s ×%d — %s" % [str(inf.name), n, str(inf.get("desc", ""))], use_item.bind(it), UI.GOOD, 22, 70)
		b.name = "Use_" + it
		_sheet_box.add_child(b)
	_sheet.visible = true
	UI.guard(250)


func use_item(it: String) -> void:
	var have := int((p.rpg.get("items", {}) as Dictionary).get(it, 0))
	if have <= 0:
		return
	if have == 1:
		(p.rpg.items as Dictionary).erase(it)
	else:
		p.rpg.items[it] = have - 1
	changed.emit()
	_sheet.visible = false
	phase = "pilih"
	var inf: Dictionary = rewards.info(it)
	_apply("barang", {"item": it, "use": str(inf.get("use", "")), "power": int(inf.get("power", 0)), "name": str(inf.name)})


# --- Akhir -------------------------------------------------------------------------------------------------------

func _end() -> void:
	phase = "selesai"
	for b in _actions.get_children():
		b.queue_free()
	if engine.won:
		result = engine.rewards()
		p.rpg.xp = int(p.rpg.xp) + int(result.xp)
		p.rpg.coins = int(p.rpg.coins) + int(result.coins)
		var extra := ""
		if str(result.drop) != "":
			if not p.rpg.has("items"):
				p.rpg["items"] = {}
			p.rpg.items[str(result.drop)] = int((p.rpg.items as Dictionary).get(str(result.drop), 0)) + 1
			extra = ", %s" % str(rewards.info(str(result.drop)).name)
		_sfx("bintang")
		hero_rig.play_once("sorak", 2.0)
		_log.text += "\n\nMenang! +%d XP, +%d koin%s." % [int(result.xp), int(result.coins), extra]
		if str(monster.get("defeat", "")) != "":
			_log.text += "\n%s: \"%s\"" % [str(monster.name), str(monster.defeat)]
	elif not engine.fled:
		var losses: Dictionary = p.world.get("battle_losses", {})
		losses[monster_id] = int(losses.get(monster_id, 0)) + 1
		p.world["battle_losses"] = losses
	changed.emit()
	var go := UI.button("Lanjutkan" if engine.won or engine.fled else "Bangun di desa", _finish, UI.GOOD, 28, 76)
	go.name = "Done"
	UI.expand(go)
	_actions.add_child(go)
	UI.guard(300)


func _finish() -> void:
	finished.emit({"won": engine.won, "fled": engine.fled, "monster": monster_id, "uid": uid, "boss": bool(monster.get("boss", false))})


func back() -> bool:
	if phase == "barang":
		_sheet.visible = false
		phase = "pilih"
		return true
	if phase == "pilih" and not bool(monster.get("boss", false)):
		choose("kabur")
		return true
	return true
