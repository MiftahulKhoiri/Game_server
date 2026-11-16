extends Control
## Tantangan belajar di dalam misi (teka-teki di penduduk, batu bertulis, batu besar gua).
## Pembuka cerita -> beberapa soal sesuai kelas anak (boleh petunjuk & mencoba lagi, ada pembahasan) ->
## lulus bila cukup banyak yang akhirnya benar. Gagal tidak dihukum: boleh langsung mencoba lagi dengan soal
## lain, atau belajar dulu di akademi. Jawaban ikut tercatat di statistik belajar (Learning Engine).

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const Voice := preload("res://games/education_sd/scripts/voice.gd")
const SdQuestion := preload("res://games/education_sd/scripts/sd_question.gd")
const Learning := preload("res://games/education_sd/scripts/engine/learning_engine.gd")

signal passed(id: String)
signal closed
signal changed

var learning
var p: Dictionary
var rng: RandomNumberGenerator
var audio: Node
var type_names: Dictionary
var id := ""
var def: Dictionary
var topic := ""
var phase := ""
var grade := 1
var session: Dictionary = {}
var qview: Node
var _panel: PanelContainer
var _box: VBoxContainer


func setup(engine, progress: Dictionary, random: RandomNumberGenerator, sound: Node, names: Dictionary, challenge_id: String,
		challenge: Dictionary, topic_id: String, learn_grade := 0) -> void:
	grade = learn_grade if learn_grade > 0 else int(progress.profile.grade)
	learning = engine
	p = progress
	rng = random
	audio = sound
	type_names = names
	id = challenge_id
	def = challenge
	topic = topic_id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UI.panel(Color("fff4d6"), 28)
	_panel.name = "Panel"
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(UI.DRAG_CANCEL_PX)
	_panel.add_child(scroll)
	_box = UI.vbox(14)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	var s := get_viewport_rect().size
	_panel.position = Vector2(s.x * 0.06, s.y * 0.05)
	_panel.size = Vector2(s.x * 0.88, s.y * 0.9)
	_panel.custom_minimum_size = _panel.size
	show_intro()


func _clear(ph: String) -> void:
	Voice.hush()
	phase = ph
	UI.guard(300)
	qview = null
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func _head(title: String, back_text: String, back: Callable) -> void:
	var h := UI.hbox(12)
	var b := UI.button(back_text, back, Color("cfc8dc"), 22, 60)
	b.name = "Back"
	h.add_child(b)
	var t := UI.label(title, 34, Color("b5443a"), false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	_box.add_child(h)


func show_intro() -> void:
	_clear("pembuka")
	_head(str(def.get("title", "Tantangan")), "Nanti saja", func() -> void: closed.emit())
	var story := str(def.get("story", ""))
	var rule := "Jawab %d soal. Kamu lulus bila %d soal terjawab benar. Boleh pakai petunjuk!" % [int(def.get("n", 3)), int(def.get("pass", 2))]
	var sh := UI.hbox(12)
	var sl := UI.label(story, 28, UI.INK)
	UI.expand(sl)
	sh.add_child(sl)
	if Voice.listen_ok():
		sh.add_child(UI.listen_button(func() -> void: Voice.say(story + "\n" + rule)))
	_box.add_child(sh)
	_box.add_child(UI.label(rule, 24, UI.SOFT))
	Voice.say_auto(story + "\n" + rule)
	var go := UI.button("Mulai Tantangan", start, UI.GOOD, 30, 84)
	go.name = "Start"
	_box.add_child(go)


func start() -> void:
	session = learning.start(p, topic, grade, rng, int(def.get("n", 3)))
	if (session.questions as Array).is_empty():
		closed.emit()
		return
	_show_q()


func _show_q() -> void:
	_clear("soal")
	var qs: Array = session.questions
	_head("%s · %d/%d" % [str(def.get("title", "")), int(session.i) + 1, qs.size()], "Berhenti", func() -> void: closed.emit())
	_box.add_child(UI.progress(int(session.i), qs.size(), Color("b5443a")))
	qview = SdQuestion.new()
	qview.name = "Question"
	_box.add_child(qview)
	qview.setup(qs[int(session.i)], "latihan", rng, type_names, audio)
	qview.finished.connect(_on_answer)


func current_question_view() -> Node:
	return qview


func _on_answer(res: Dictionary) -> void:
	Learning.answer(p, session, res.question, bool(res.correct), bool(res.first_try))
	changed.emit()
	if int(session.i) >= (session.questions as Array).size():
		_result()
	else:
		_show_q()


func is_passed() -> bool:
	return int(session.get("correct", 0)) >= int(def.get("pass", 2))


func _result() -> void:
	var ok := is_passed()
	_clear("hasil")
	_head("Berhasil!" if ok else "Hampir berhasil!", "Tutup", _close_result)
	if audio != null:
		audio.play("bintang" if ok else "klik")
	_box.add_child(UI.label("Benar %d dari %d." % [int(session.correct), (session.questions as Array).size()], 30, UI.GOOD if ok else UI.SOFT_BAD))
	if ok:
		_box.add_child(UI.label("Ilmumu menyelesaikan teka-teki ini!", 26, UI.INK))
		var c := UI.button("Lanjutkan petualangan", _close_result, UI.GOOD, 28, 80)
		c.name = "Continue"
		_box.add_child(c)
	else:
		_box.add_child(UI.label("Tidak apa-apa! Coba lagi dengan soal lain, atau belajar dulu di Akademi Tunas.", 26, UI.INK))
		var r := UI.button("Coba lagi", start, UI.GOOD, 28, 80)
		r.name = "Retry"
		_box.add_child(r)


func _close_result() -> void:
	if phase == "hasil" and is_passed():
		passed.emit(id)
	else:
		closed.emit()


func back() -> bool:
	if phase == "hasil":
		_close_result()
		return true
	return false
