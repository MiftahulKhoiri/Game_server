extends Control
## Belajar di ruang kelas akademi (di atas dunia 3D):
##   kelas   — guru menyapa, daftar materi kelas ini (bintang + status penguasaan)
##   materi  — penjelasan singkat + contoh, tombol Mulai Latihan
##   latihan — soal satu per satu (11 tipe soal; petunjuk; boleh mencoba lagi; pembahasan setiap soal)
##   hasil   — bintang, XP, koin, pesan positif, status penguasaan; Ulangi / Baca materi / Kembali
## Semua aturan & catatan lewat Learning Engine; layar ini hanya tampilan.

const Voice := preload("res://games/education_sd/scripts/voice.gd")
const Portrait := preload("res://games/education_sd/scripts/ui/speaker_portrait.gd")
const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const SdQuestion := preload("res://games/education_sd/scripts/sd_question.gd")
const Learning := preload("res://games/education_sd/scripts/engine/learning_engine.gd")
const SdMini := preload("res://games/education_sd/scripts/sd_minigames.gd")
const ExperimentEngine := preload("res://games/education_sd/scripts/engine/experiment_engine.gd")
const ExperimentView := preload("res://games/education_sd/scripts/ui/experiment_view.gd")

signal closed
signal changed  # progres berubah: simpan
signal session_done(result: Dictionary)  # satu latihan selesai (untuk misi)
signal exam_done(result: Dictionary)

var learning  # LearningEngine
var p: Dictionary
var rng: RandomNumberGenerator
var audio: Node
var type_names: Dictionary = {}
var room: Dictionary
var grade := 1
var phase := ""
var topic_id := ""
var session: Dictionary = {}
var result: Dictionary = {}
var qview: Node
var lab  # ExperimentEngine (hanya di Laboratorium IPAS)
var mini: Node
var expview: Node
var _panel: PanelContainer
var _box: VBoxContainer


func setup(engine, progress: Dictionary, random: RandomNumberGenerator, sound: Node, names: Dictionary, room_id: String, learn_grade := 0) -> void:
	learning = engine
	p = progress
	rng = random
	audio = sound
	type_names = names
	room = Learning.room(room_id)
	grade = learn_grade if learn_grade > 0 else int(p.profile.grade)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UI.panel(Color("fdf6e3"), 28)
	_panel.name = "Panel"
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(UI.DRAG_CANCEL_PX)
	_panel.add_child(scroll)
	_box = UI.vbox(14)
	_box.name = "Box"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	resized.connect(_layout)
	_layout()
	show_class()


func _layout() -> void:
	var s := size if size.x > 0 else get_viewport_rect().size
	_panel.position = Vector2(s.x * 0.06, s.y * 0.05)
	_panel.size = Vector2(s.x * 0.88, s.y * 0.9)
	_panel.custom_minimum_size = _panel.size


func _clear(id: String) -> void:
	Voice.hush()
	phase = id
	UI.guard(300)
	qview = null
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	(_panel.get_node("Scroll") as ScrollContainer).scroll_vertical = 0


func _head(title: String, back_text: String, back: Callable) -> void:
	var h := UI.hbox(12)
	var b := UI.button(back_text, back, Color("cfc8dc"), 22, 60)
	b.name = "Back"
	h.add_child(b)
	var t := UI.label(title, 34, Color.from_string(str(room.color), UI.PRIMARY), false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(t)
	var chip := UI.panel(Color("ffd166"), 18)
	chip.add_child(UI.label("Kelas %d" % grade, 22, UI.INK, false))
	h.add_child(chip)
	_box.add_child(h)


func _sfx(n: String) -> void:
	if audio != null:
		audio.play(n)


## Guru (potret 3D yang membacakan) + teks + tombol Dengar. read: teks yang dibacakan (bawaan = text).
func _teacher_row(text: String, read := "") -> Control:
	var h := UI.hbox(12)
	var pt := Portrait.new()
	pt.name = "Teacher"
	pt.custom_minimum_size = Vector2(120, 136)
	pt.set_model(str(room.get("model", "")))
	h.add_child(pt)
	var l := UI.label(text, 26, UI.INK)
	UI.expand(l)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	if Voice.listen_ok():
		var say := read if read != "" else text
		var lb := UI.listen_button(func() -> void: Voice.say(say))
		lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lb)
	return h


# --- Kelas: daftar materi -----------------------------------------------------------------------------------

func show_class() -> void:
	_clear("kelas")
	_head(str(room.name), "Tutup", func() -> void: closed.emit())
	var ts: Array = learning.topics(str(room.id), grade, p)
	var greet := "Halo, %s! Aku %s. Pilih materi yang ingin kamu pelajari hari ini." % [str(p.profile.name), str(room.teacher)]
	if ts.is_empty():
		greet = "Halo, %s! Materi untuk kelas %d di ruang ini sedang disiapkan." % [str(p.profile.name), grade]
	_box.add_child(_teacher_row(greet))
	Voice.say_auto(greet)
	if not ts.is_empty():
		var ex: Dictionary = Learning.exam_rec(p, grade, str(room.id))
		var er := UI.panel(Color("fff4d6"), 20)
		var eh := UI.hbox(12)
		var ev := UI.vbox(2)
		UI.expand(ev)
		ev.add_child(UI.label("Ujian %s" % str(room.subject), 28, Color("b5443a"), false))
		var etxt := "%d soal campuran tanpa petunjuk. Lulus bila nilai %d atau lebih." % [Learning.EXAM_N, Learning.EXAM_PASS]
		if not ex.is_empty():
			etxt = ("LULUS · " if bool(ex.passed) else "Belum lulus · ") + "nilai terbaik %d (%d kali)" % [int(ex.best), int(ex.attempts)]
		ev.add_child(UI.label(etxt, 20, UI.GOOD if bool(ex.get("passed", false)) else UI.SOFT))
		eh.add_child(ev)
		var eb := UI.button("Ujian", start_exam, Color("b5443a"), 24, 66)
		eb.name = "Exam"
		eh.add_child(eb)
		er.add_child(eh)
		_box.add_child(er)
	_activity_rows()
	for t in ts:
		var row := UI.panel(Color.WHITE, 20)
		var h := UI.hbox(12)
		var v := UI.vbox(4)
		UI.expand(v)
		v.add_child(UI.label(str(t.name), 28, UI.INK, false))
		var st_col := UI.GOOD if str(t.status) == "kuasai" else (UI.SOFT_BAD if str(t.status) == "perlu_latihan" else UI.SOFT)
		v.add_child(UI.label("%s   %s" % ["★".repeat(int(t.stars)) + "☆".repeat(3 - int(t.stars)), str(Learning.STATUS_TEXT.get(str(t.status), ""))],
			22, st_col, false))
		h.add_child(v)
		var b := UI.button("Belajar", show_lesson.bind(str(t.id)), Color.from_string(str(room.color), UI.PRIMARY), 24, 66)
		b.name = "Topic_" + str(t.id)
		h.add_child(b)
		row.add_child(h)
		_box.add_child(row)


# --- Kegiatan interaktif: mini-game & Laboratorium Eksperimen ----------------------------------------------------

func _mini_info() -> Dictionary:
	for m in SdMini.LIST:
		if str(m.region) == str(room.get("region", "")):
			return m
	return {}


func _activity_row(title: String, text: String, btn: String, btn_name: String, cb: Callable, col: Color) -> void:
	var pn := UI.panel(Color("eef7ff"), 20)
	var h := UI.hbox(12)
	var v := UI.vbox(2)
	UI.expand(v)
	v.add_child(UI.label(title, 28, col, false))
	v.add_child(UI.label(text, 20, UI.SOFT))
	h.add_child(v)
	var b := UI.button(btn, cb, col, 24, 66)
	b.name = btn_name
	h.add_child(b)
	pn.add_child(h)
	_box.add_child(pn)


func _activity_rows() -> void:
	if str(room.id) == "ipas_alam":
		if lab == null:
			lab = ExperimentEngine.new()
			lab.load_data()
		var exps: Array = lab.for_grade(p, grade)
		if not exps.is_empty():
			var n_done := exps.filter(func(e): return bool(e.done)).size()
			_activity_row("Laboratorium Eksperimen", "Lakukan percobaan sendiri: tebak, coba, lalu lihat hasilnya. Selesai %d dari %d." % [n_done, exps.size()],
				"Eksperimen", "Lab", show_lab, Color("2a8f86"))
	var m := _mini_info()
	if not m.is_empty():
		var r: Dictionary = (p.academy as Dictionary).get("mini/" + str(m.id), {})
		var txt := str(m.goal)
		if not r.is_empty():
			txt += " Nilai terbaik %d (%d kali main)." % [int(r.get("best", 0)), int(r.get("plays", 0))]
		_activity_row("Permainan: " + str(m.name), txt, "Main", "Mini", start_mini, Color("7a5bd0"))


func start_mini() -> void:
	var m := _mini_info()
	if m.is_empty():
		return
	_sfx("klik")
	_clear("permainan")
	_head(str(m.name), "Kelas", show_class)
	_box.add_child(UI.label(str(m.goal), 22, UI.SOFT))
	mini = SdMini.create(str(m.id))
	mini.name = "MiniGame"
	_box.add_child(mini)
	mini.setup(grade, learning.data.doc, rng, audio)
	mini.done.connect(_on_mini_done.bind(str(m.id)))


func _on_mini_done(score: int, total: int, extra: Dictionary, id: String) -> void:
	var res := Learning.minigame_finish(p, id, str(room.subject), score, total, extra)
	changed.emit()
	_sfx("bintang")
	var pn := UI.panel(Color("fff4d6"), 20)
	pn.name = "MiniResult"
	var v := UI.vbox(8)
	var msg := "Kamu menjawab %d dari %d dengan benar. +%d XP · +%d koin." % [score, total, int(res.xp), int(res.coins)]
	if bool(res.new_best):
		msg += " Nilai terbaik baru!"
	v.add_child(UI.label(msg, 24, UI.INK))
	var row := UI.hbox(12)
	for b in [["Main lagi", start_mini, UI.GOOD, "MiniAgain"], ["Kembali ke kelas", show_class, Color("cfc8dc"), "ToClass"]]:
		var btn := UI.button(str(b[0]), b[1], b[2], 24, 70)
		btn.name = str(b[3])
		UI.expand(btn)
		row.add_child(btn)
	v.add_child(row)
	pn.add_child(v)
	_box.add_child(pn)


func show_lab() -> void:
	_sfx("klik")
	_clear("lab")
	_head("Laboratorium Eksperimen", "Kelas", show_class)
	var greet := "Di laboratorium, kita mencari jawaban dengan mencoba sendiri. Pilih satu percobaan!"
	_box.add_child(_teacher_row(greet))
	Voice.say_auto(greet)
	for e in lab.for_grade(p, grade):
		var row := UI.panel(Color.WHITE, 20)
		var h := UI.hbox(12)
		var v := UI.vbox(4)
		UI.expand(v)
		v.add_child(UI.label(str(e.title), 28, UI.INK, false))
		v.add_child(UI.label("Sudah dicoba %d kali" % int(e.plays) if bool(e.done) else "Belum dicoba", 22, UI.GOOD if bool(e.done) else UI.SOFT, false))
		h.add_child(v)
		var b := UI.button("Ulangi" if bool(e.done) else "Mulai", start_experiment.bind(str(e.id)), Color("2a8f86"), 24, 66)
		b.name = "Exp_" + str(e.id)
		h.add_child(b)
		row.add_child(h)
		_box.add_child(row)


func start_experiment(id: String) -> void:
	_sfx("klik")
	_clear("eksperimen")
	_head(str(lab.by_id[id].title), "Laboratorium", show_lab)
	expview = ExperimentView.new()
	expview.name = "Experiment"
	_box.add_child(expview)
	expview.setup(lab, id, rng, audio, type_names, str(room.teacher))
	expview.done.connect(_on_experiment_done)


func _on_experiment_done(r: Dictionary) -> void:
	var res: Dictionary = lab.finish(p, expview.state, int(r.check_ok), int(r.check_total))
	changed.emit()
	_sfx("bintang")
	_clear("hasil_eksperimen")
	_head("Percobaan selesai!", "Laboratorium", show_lab)
	_box.add_child(UI.label(str(res.message), 28, UI.INK))
	_box.add_child(UI.label("Pertanyaan benar: %d dari %d   ·   +%d XP   ·   +%d koin" % [int(res.check_ok), int(res.check_total), int(res.xp),
		int(res.coins)], 24, UI.SOFT))
	var row := UI.hbox(12)
	for b in [["Percobaan lain", show_lab, UI.GOOD, "ToLab"], ["Kembali ke kelas", show_class, Color("cfc8dc"), "ToClass"]]:
		var btn := UI.button(str(b[0]), b[1], b[2], 24, 70)
		btn.name = str(b[3])
		UI.expand(btn)
		row.add_child(btn)
	_box.add_child(row)
	Voice.say_auto(str(res.message))


# --- Materi singkat ------------------------------------------------------------------------------------------

func show_lesson(id: String) -> void:
	_sfx("klik")
	topic_id = id
	_clear("materi")
	var les: Dictionary = learning.lesson(id, grade)
	_head(str(les.get("title", id)), "Daftar materi", show_class)
	var read: Array = ["%s menjelaskan." % str(room.teacher)]
	for line in les.get("text", []):
		read.append(str(line))
	if str(les.get("example", "")) != "":
		read.append("Contoh: " + str(les.example))
	_box.add_child(_teacher_row("%s menjelaskan:" % str(room.teacher), "\n".join(read)))
	for line in les.get("text", []):
		_box.add_child(UI.label("• " + str(line), 28, UI.INK))
	Voice.say_auto("\n".join(read))
	if str(les.get("example", "")) != "":
		var ex := UI.panel(Color("e8f4ff"), 18)
		ex.add_child(UI.label("Contoh: " + str(les.example), 26, Color("1f4f8a")))
		_box.add_child(ex)
	var go := UI.button("Mulai Latihan (%d soal)" % Learning.SESSION, start_practice, UI.GOOD, 30, 84)
	go.name = "StartPractice"
	_box.add_child(go)


# --- Latihan ----------------------------------------------------------------------------------------------------

func start_practice() -> void:
	_sfx("klik")
	session = learning.start(p, topic_id, grade, rng)
	if (session.questions as Array).is_empty():
		show_class()
		return
	_show_question()


func _show_question() -> void:
	_clear("latihan")
	var qs: Array = session.questions
	var i := int(session.i)
	_head("Latihan %d dari %d" % [i + 1, qs.size()], "Berhenti", _confirm_stop)
	_box.add_child(UI.progress(i, qs.size(), Color.from_string(str(room.color), UI.PRIMARY)))
	var note := Learning.adapt_note(session)
	if note != "" and i == 0:
		_box.add_child(UI.label(note, 22, UI.SOFT))
	qview = SdQuestion.new()
	qview.name = "Question"
	_box.add_child(qview)
	qview.setup(qs[i], "latihan", rng, type_names, audio)
	qview.finished.connect(_on_answer)


func current_question_view() -> Node:
	if phase == "eksperimen" and expview != null and is_instance_valid(expview):
		return expview.qview
	return qview


func _on_answer(res: Dictionary) -> void:
	Learning.answer(p, session, res.question, bool(res.correct), bool(res.first_try), str(res.get("first_wrong", "")))
	changed.emit()
	if int(session.i) >= (session.questions as Array).size():
		_finish()
	else:
		_show_question()


func _confirm_stop() -> void:
	_clear("berhenti")
	_head("Berhenti latihan?", "Lanjutkan", _show_question)
	_box.add_child(UI.label("Jawaban yang sudah kamu kerjakan tetap tercatat.", 26, UI.INK))
	var b := UI.button("Ya, kembali ke daftar materi", show_class, UI.SOFT_BAD, 26, 76)
	b.name = "StopYes"
	_box.add_child(b)


func _finish() -> void:
	result = Learning.finish(p, session, str(room.subject))
	changed.emit()
	session_done.emit(result)
	_sfx("bintang")
	_clear("hasil")
	_head("Latihan selesai!", "Daftar materi", show_class)
	var stars := UI.label("★".repeat(int(result.stars)) + "☆".repeat(3 - int(result.stars)), 72, UI.GOLD, false)
	stars.name = "Stars"
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(stars)
	UI.pop(stars)
	_box.add_child(UI.label(str(result.message), 28, UI.INK))
	_box.add_child(UI.label("Benar tanpa salah: %d dari %d   ·   +%d XP   ·   +%d koin" % [int(result.first_try), int(result.total),
		int(result.xp), int(result.coins)], 24, UI.SOFT))
	_box.add_child(UI.label("Status: " + str(Learning.STATUS_TEXT.get(str(result.status), "")), 24,
		UI.GOOD if str(result.status) == "kuasai" else UI.SOFT))
	var row := UI.hbox(12)
	for b in [["Ulangi latihan", start_practice, UI.GOOD, "Again"], ["Baca materi lagi", show_lesson.bind(topic_id), UI.PRIMARY, "Reread"],
			["Kembali ke kelas", show_class, Color("cfc8dc"), "ToClass"]]:
		var btn := UI.button(str(b[0]), b[1], b[2], 24, 70)
		btn.name = str(b[3])
		UI.expand(btn)
		row.add_child(btn)
	_box.add_child(row)


# --- Ujian ---------------------------------------------------------------------------------------------------------

func start_exam() -> void:
	_sfx("klik")
	session = learning.exam_start(p, str(room.id), grade, rng)
	if (session.questions as Array).is_empty():
		show_class()
		return
	_show_exam_q()


func _show_exam_q() -> void:
	_clear("ujian")
	var qs: Array = session.questions
	var i := int(session.i)
	_head("Ujian %d dari %d" % [i + 1, qs.size()], "Berhenti", _confirm_stop_exam)
	_box.add_child(UI.progress(i, qs.size(), Color("b5443a")))
	qview = SdQuestion.new()
	qview.name = "Question"
	_box.add_child(qview)
	qview.setup(qs[i], "kuis", rng, type_names, audio)
	qview.finished.connect(_on_exam_answer)


func _on_exam_answer(res: Dictionary) -> void:
	Learning.exam_answer(p, session, res.question, bool(res.correct))
	changed.emit()
	if int(session.i) >= (session.questions as Array).size():
		_finish_exam()
	else:
		_show_exam_q.call_deferred()


func _confirm_stop_exam() -> void:
	_clear("berhenti_ujian")
	_head("Berhenti ujian?", "Lanjutkan", _show_exam_q)
	_box.add_child(UI.label("Ujian yang dihentikan tidak dinilai. Jawaban latihanmu tetap tercatat.", 26, UI.INK))
	var b := UI.button("Ya, kembali ke daftar materi", show_class, UI.SOFT_BAD, 26, 76)
	b.name = "StopYes"
	_box.add_child(b)


func _finish_exam() -> void:
	result = learning.exam_finish(p, session)
	changed.emit()
	exam_done.emit(result)
	_sfx("bintang" if bool(result.passed) else "klik")
	_clear("ujian_hasil")
	_head("Hasil Ujian", "Daftar materi", show_class)
	var sc := UI.label(str(int(result.score)), 96, UI.GOOD if bool(result.passed) else UI.SOFT_BAD, false)
	sc.name = "Score"
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sc)
	UI.pop(sc)
	_box.add_child(UI.label(str(result.message), 28, UI.INK))
	_box.add_child(UI.label("Benar %d dari %d · +%d XP · +%d koin" % [int(result.correct), int(result.total), int(result.xp), int(result.coins)], 24, UI.SOFT))
	if not (result.practice as Array).is_empty():
		_box.add_child(UI.label("Materi yang bisa dilatih lagi: " + ", ".join(result.practice), 24, Color("1f4f8a")))
	var row := UI.hbox(12)
	var again := UI.button("Ujian lagi", start_exam, Color("b5443a"), 24, 70)
	again.name = "ExamAgain"
	UI.expand(again)
	row.add_child(again)
	var back := UI.button("Kembali ke kelas", show_class, Color("cfc8dc"), 24, 70)
	back.name = "ToClass"
	UI.expand(back)
	row.add_child(back)
	_box.add_child(row)


## Tombol kembali Android: mundur satu langkah. true bila ditangani (layar tetap terbuka).
func back() -> bool:
	match phase:
		"latihan":
			_confirm_stop()
		"berhenti":
			_show_question()
		"ujian":
			_confirm_stop_exam()
		"berhenti_ujian":
			_show_exam_q()
		"materi", "hasil", "ujian_hasil":
			show_class()
		_:
			return false
	return true
