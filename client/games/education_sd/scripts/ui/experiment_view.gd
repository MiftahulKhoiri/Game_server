extends VBoxContainer
## Tampilan satu percobaan Laboratorium Eksperimen IPA. Alur: masalah -> percobaan -> penjelasan -> evaluasi.
## Semua aturan ada di Experiment Engine; berkas ini hanya tampilan. Dipasang di dalam layar kelas (lesson_view).
## Sinyal done({check_ok, check_total}) saat pertanyaan evaluasi terakhir selesai.

signal done(result: Dictionary)

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const Voice := preload("res://games/education_sd/scripts/voice.gd")
const SdQuestion := preload("res://games/education_sd/scripts/sd_question.gd")

var lab  # ExperimentEngine
var spec: Dictionary
var state: Dictionary
var rng: RandomNumberGenerator
var audio: Node
var type_names: Dictionary = {}
var teacher := "Profesor Kiko"
var phase := ""
var qview: Node
var check_i := 0
var check_ok := 0
var _sel_item := -1
var _choice: Array = []
var _fb: Label
var _tank: Tank
var _item_btns: Array = []
var _guess_row: HBoxContainer
var _pool_box: HFlowContainer
var _placed_lbl: Label
var _var_btns: Array = []
var _count_lbl: Label
var _to_science: Button


func setup(engine, id: String, random: RandomNumberGenerator, sound: Node, names: Dictionary, teacher_name := "Profesor Kiko") -> void:
	lab = engine
	spec = lab.by_id[id]
	state = lab.start(id)
	rng = random
	audio = sound
	type_names = names
	teacher = teacher_name
	add_theme_constant_override("separation", 14)
	show_problem()


func _clear(id: String) -> void:
	Voice.hush()
	phase = id
	qview = null
	for c in get_children():
		remove_child(c)
		c.queue_free()


func _sfx(n: String) -> void:
	if audio != null:
		audio.play(n)


func _say(text: String, good := true) -> void:
	_fb.visible = true
	_fb.text = text
	_fb.add_theme_color_override("font_color", UI.GOOD if good else UI.SOFT_BAD)
	Voice.say_auto(text)


# --- 1. Masalah & instruksi ---------------------------------------------------------------------------------------

func show_problem() -> void:
	_clear("masalah")
	var pp := UI.panel(Color("e8f4ff"), 20)
	pp.add_child(UI.label("%s: \"%s\"" % [teacher, str(spec.problem)], 26, Color("1f4f8a")))
	add_child(pp)
	add_child(UI.label("Cara melakukan percobaan: " + str(spec.instruction), 24, UI.INK))
	if Voice.listen_ok():
		add_child(UI.listen_button(func() -> void: Voice.say(str(spec.problem) + "\n" + str(spec.instruction))))
	var b := UI.button("Mulai Percobaan", start, UI.GOOD, 30, 84)
	b.name = "Start"
	add_child(b)
	Voice.say_auto(str(spec.problem) + "\n" + str(spec.instruction))


# --- 2–5. Percobaan ----------------------------------------------------------------------------------------------

func start() -> void:
	_sfx("klik")
	_clear("coba")
	add_child(UI.label(str(spec.instruction), 22, UI.SOFT))
	match str(spec.kind):
		"uji":
			_build_uji()
		"susun":
			_build_susun()
		"kondisi":
			_build_kondisi()
	_fb = UI.label("", 24, UI.GOOD)
	_fb.visible = false
	add_child(_fb)
	_to_science = UI.button("Lihat Penjelasan", show_science, UI.PRIMARY, 28, 76)
	_to_science.name = "ToScience"
	_to_science.visible = false
	add_child(_to_science)


func _build_uji() -> void:
	if str(spec.get("visual", "")) == "tangki":
		_tank = Tank.new()
		_tank.custom_minimum_size = Vector2(0, 190)
		add_child(_tank)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_item_btns.clear()
	for i in (spec.items as Array).size():
		var b := UI.button(str(spec.items[i].name), choose_item.bind(i), Color("ffd166"), 24, 64)
		b.name = "Item_%d" % i
		_item_btns.append(b)
		flow.add_child(b)
	add_child(flow)
	_guess_row = UI.hbox(12)
	_guess_row.visible = false
	_guess_row.add_child(UI.label("Tebakanmu:", 24, UI.INK, false))
	for g in 2:
		var gb := UI.button(str(spec.labels[g]), guess.bind(g), UI.PRIMARY, 24, 64)
		gb.name = "Guess_%d" % g
		UI.expand(gb)
		_guess_row.add_child(gb)
	add_child(_guess_row)


func choose_item(i: int) -> void:
	if state.tested.has(i):
		return
	_sfx("klik")
	_sel_item = i
	_guess_row.visible = true
	_fb.visible = true
	_fb.add_theme_color_override("font_color", UI.SOFT)
	_fb.text = "Kamu memilih %s. Menurutmu apa yang terjadi?" % str(spec.items[i].name)
	if _tank != null:
		_tank.prepare(str(spec.items[i].name))


func guess(g: int) -> void:
	if _sel_item < 0:
		return
	var r: Dictionary = lab.test(state, _sel_item, g)
	if r.is_empty():
		return
	_sfx("benar" if bool(r.ok) else "klik")
	if _tank != null:
		_tank.drop(int(r.result) == 0)
	var b: Button = _item_btns[_sel_item]
	b.disabled = true
	b.text = "%s: %s" % [str(spec.items[_sel_item].name), str(r.label)]
	var head := "Tebakanmu tepat! " if bool(r.ok) else "Ternyata hasilnya berbeda dari tebakanmu, dan itu tidak apa-apa. "
	_say("%sHasil: %s. %s" % [head, str(r.label).to_lower(), str(r.why)], true)
	_sel_item = -1
	_guess_row.visible = false
	_after_step()


func _build_susun() -> void:
	add_child(UI.label(str(spec.order_label) + ":", 24, UI.INK, false))
	var pp := UI.panel(Color.WHITE, 18)
	_placed_lbl = UI.label("(belum ada)", 26, UI.INK)
	_placed_lbl.name = "Placed"
	pp.add_child(_placed_lbl)
	add_child(pp)
	_pool_box = HFlowContainer.new()
	_pool_box.add_theme_constant_override("h_separation", 10)
	_pool_box.add_theme_constant_override("v_separation", 10)
	var names: Array = (spec.items as Array).duplicate()
	UI.shuffle(names, rng)
	for n in names:
		var b := UI.button(str(n), place.bind(str(n)), Color("ffd166"), 24, 64)
		b.name = "Piece_" + str(n)
		_pool_box.add_child(b)
	add_child(_pool_box)


func place(n: String) -> void:
	var r: Dictionary = lab.place(state, n)
	if r.is_empty():
		return
	if not bool(r.ok):
		_sfx("salah")
		_say(str(r.hint), false)
		return
	_sfx("benar")
	var b := _pool_box.get_node_or_null("Piece_" + n) as Button
	if b != null:
		b.disabled = true
	var parts: Array = []
	for i in (r.placed as Array).size():
		parts.append("%d. %s" % [i + 1, str(r.placed[i])])
	_placed_lbl.text = "   ".join(PackedStringArray(parts))
	if bool(r.done):
		_say("Susunanmu benar! " + str(r.hint))
	else:
		_say("Tepat! Sekarang urutan ke-%d." % ((r.placed as Array).size() + 1))
	_after_step()


func _build_kondisi() -> void:
	_choice.clear()
	_var_btns.clear()
	for vi in (spec.vars as Array).size():
		var v: Dictionary = spec.vars[vi]
		_choice.append(0)
		add_child(UI.label(str(v.name) + ":", 24, UI.INK, false))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 8)
		var row: Array = []
		for oi in (v.options as Array).size():
			var b := UI.button(str(v.options[oi]), select.bind(vi, oi), Color("cfc8dc"), 22, 60)
			b.name = "Var_%d_%d" % [vi, oi]
			row.append(b)
			flow.add_child(b)
		_var_btns.append(row)
		add_child(flow)
	var run_b := UI.button("Coba", run_combo, UI.GOOD, 28, 72)
	run_b.name = "Run"
	add_child(run_b)
	_count_lbl = UI.label("", 22, UI.SOFT, false)
	add_child(_count_lbl)
	_paint_choice()


func select(vi: int, oi: int) -> void:
	_sfx("klik")
	_choice[vi] = oi
	_paint_choice()


func _paint_choice() -> void:
	for vi in _var_btns.size():
		for oi in (_var_btns[vi] as Array).size():
			var b: Button = _var_btns[vi][oi]
			b.add_theme_stylebox_override("normal", UI.box(Color("ffd166") if int(_choice[vi]) == oi else Color("e6e1ee")))
	_count_lbl.text = "Percobaan berbeda yang sudah dicoba: %d dari %d" % [(state.tried as Dictionary).size(), int(spec.need)]


func run_combo() -> void:
	var r: Dictionary = lab.run(state, _choice)
	if r.is_empty():
		return
	_sfx("benar" if bool(r.new) else "klik")
	_say("Hasil: %s %s" % [str(r.result), str(r.why)])
	_paint_choice()
	_after_step()


func _after_step() -> void:
	if bool(state.ready):
		_to_science.visible = true
		_sfx("bintang")


# --- 6. Penjelasan ilmiah ----------------------------------------------------------------------------------------

func show_science() -> void:
	if not bool(state.ready):
		return
	_sfx("klik")
	_clear("sains")
	add_child(UI.label("Mengapa begitu?", 30, UI.PRIMARY, false))
	var sp := UI.panel(Color("eaf7ea"), 20)
	sp.add_child(UI.label(str(spec.science), 26, Color("2c6b3a")))
	add_child(sp)
	if Voice.listen_ok():
		add_child(UI.listen_button(func() -> void: Voice.say(str(spec.science))))
	var b := UI.button("Lanjut: %d pertanyaan" % (spec.check as Array).size(), show_check, UI.GOOD, 28, 80)
	b.name = "ToCheck"
	add_child(b)
	Voice.say_auto(str(spec.science))


# --- 7. Evaluasi pemahaman ---------------------------------------------------------------------------------------

func show_check() -> void:
	_clear("cek")
	add_child(UI.label("Pertanyaan %d dari %d" % [check_i + 1, (spec.check as Array).size()], 24, UI.SOFT, false))
	qview = SdQuestion.new()
	qview.name = "Question"
	add_child(qview)
	qview.setup(spec.check[check_i], "latihan", rng, type_names, audio)
	qview.finished.connect(_on_answer)


func _on_answer(res: Dictionary) -> void:
	if bool(res.correct) and bool(res.first_try):
		check_ok += 1
	check_i += 1
	if check_i < (spec.check as Array).size():
		show_check()
	else:
		phase = "selesai"
		done.emit({"check_ok": check_ok, "check_total": (spec.check as Array).size()})


## Bak air sederhana: benda dijatuhkan lalu terapung di permukaan atau tenggelam ke dasar.
class Tank extends Control:
	var item := ""
	var y := -1.0  # 0 = di atas air, 1 = dasar; < 0 = belum ada benda
	var _tw: Tween

	func prepare(n: String) -> void:
		item = n
		y = 0.0
		queue_redraw()

	func drop(floats: bool) -> void:
		if _tw != null:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_method(_set_y, 0.0, 0.32 if floats else 0.9, 0.7).set_trans(Tween.TRANS_SINE)

	func _set_y(v: float) -> void:
		y = v
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var top := h * 0.3
		draw_rect(Rect2(0, top, w, h - top), Color("8fd3f4"))
		draw_rect(Rect2(0, top, w, 4), Color("4aa3d8"))
		draw_rect(Rect2(0, h - 8, w, 8), Color("c9a66b"))
		if y < 0.0:
			return
		var c := Vector2(w * 0.5, 22.0 + y * (h - 50.0))
		draw_circle(c, 18.0, Color("7a5230"))
		var f := ThemeDB.fallback_font
		draw_string(f, c + Vector2(26, 7), item, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("2a2a3a"))
