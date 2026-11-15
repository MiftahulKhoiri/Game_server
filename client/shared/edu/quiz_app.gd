extends Control
## Mesin game pembelajaran bersama (ikut APK launcher sejak v0.84.0). Game unduhan (education_sd,
## education_smp, ...) cukup mewarisi skrip ini dan mengisi `game_id` + `course_path`; isi pelajarannya
## ada di course.json milik game itu sendiri (res://games/<id>/data/course.json).
##
## Fitur: pilih mata pelajaran -> level (kelas) -> Latihan (pembahasan tiap soal) atau Kuis (nilai di akhir),
## nilai terbaik per level, level berikutnya terbuka bila nilai >= pass_score, riwayat latihan, jawaban
## sesi terakhir. Progres disimpan lokal per game (SaveManager) dan disinkronkan ke server saat online.

const QuestionGen := preload("res://shared/edu/question_gen.gd")

const SCHEMA := 1
const MAX_HISTORY := 30
const BG := Color("13202b")
const CARD := Color("1f3242")
const GOOD := Color("5ccf7a")
const BAD := Color("ff7b6b")
const ACCENT := Color("f0b429")

## Diisi skrip turunan.
var game_id := ""
var course_path := ""

var course: Dictionary = {}
var progress: Dictionary = {}
var rng := RandomNumberGenerator.new()

var _page: VBoxContainer
var _screen := ""
var _subject: Dictionary = {}
var _level: Dictionary = {}
var _mode := "latihan"
var _questions: Array = []
var _index := 0
var _answers: Array = []   # [{q, chosen, answer, correct}]
var _answered := false
var _error := ""
var _opts_grid: GridContainer
var _feedback: Label
var _next_btn: Button


func _ready() -> void:
	rng.randomize()
	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	scroll.add_child(margin)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 12)
	margin.add_child(_page)
	get_tree().quit_on_go_back = false

	_error = _load_course()
	_load_progress()
	if _error != "":
		_show_error()
		return
	_show_home()
	if progress.is_empty() or (progress.get("levels", {}) as Dictionary).is_empty():
		_try_restore()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match _screen:
			"home", "error":
				_exit()
			"subject", "history":
				_show_home()
			"question":
				_show_subject(_subject)
			"result":
				_show_subject(_subject)
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_save()


## Dipanggil GameManager sebelum kembali ke launcher.
func platform_before_exit() -> void:
	_save()


# --- Data ---------------------------------------------------------------------------------------

func _load_course() -> String:
	if not FileAccess.file_exists(course_path):
		return "Data pelajaran tidak ditemukan: " + course_path
	var v = JSON.parse_string(FileAccess.get_file_as_string(course_path))
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("subjects")) != TYPE_ARRAY:
		return "Data pelajaran rusak"
	var subjects: Array = []
	for s in v.subjects:
		if typeof(s) != TYPE_DICTIONARY or typeof(s.get("levels")) != TYPE_ARRAY:
			continue
		var levels: Array = []
		for l in s.levels:
			if typeof(l) != TYPE_DICTIONARY:
				continue
			if l.has("generator") and typeof(l.generator) == TYPE_DICTIONARY:
				levels.append(l)
				continue
			var qs: Array = []
			for q in l.get("questions", []):
				if _valid_question(q):
					qs.append(q)
			if not qs.is_empty():
				var copy: Dictionary = l.duplicate()
				copy.questions = qs
				levels.append(copy)
		if not levels.is_empty():
			var sc: Dictionary = s.duplicate()
			sc.levels = levels
			subjects.append(sc)
	if subjects.is_empty():
		return "Belum ada soal yang sah"
	course = v
	course.subjects = subjects
	return ""


static func _valid_question(q) -> bool:
	if typeof(q) != TYPE_DICTIONARY or typeof(q.get("q")) != TYPE_STRING or typeof(q.get("options")) != TYPE_ARRAY:
		return false
	var n: int = q.options.size()
	var a := int(q.get("answer", -1))
	return n >= 2 and n <= 5 and a >= 0 and a < n


func _load_progress() -> void:
	var gm = _gm()
	var res: Dictionary = gm.load_progress(game_id, SCHEMA) if gm != null else {}
	progress = res.get("data", {})
	if not progress.has("levels"):
		progress["levels"] = {}
	if not progress.has("history"):
		progress["history"] = []


func _try_restore() -> void:
	var gm = _gm()
	if gm == null:
		return
	var data: Dictionary = await gm.restore_progress_from_server(game_id, SCHEMA)
	if not data.is_empty() and is_inside_tree():
		progress = data
		if _screen == "home":
			_show_home()


func _save() -> void:
	var gm = _gm()
	if gm != null and _error == "":
		gm.save_progress(game_id, progress, SCHEMA)


func _gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _key(s: Dictionary, l: Dictionary) -> String:
	return "%s/%s" % [s.id, l.id]


func _level_rec(s: Dictionary, l: Dictionary) -> Dictionary:
	return (progress.levels as Dictionary).get(_key(s, l), {})


func _unlocked(s: Dictionary, idx: int) -> bool:
	if idx == 0:
		return true
	var prev: Dictionary = s.levels[idx - 1]
	return int(_level_rec(s, prev).get("best", 0)) >= int(course.get("pass_score", 70))


# --- Layar --------------------------------------------------------------------------------------

func _clear(screen: String) -> void:
	_screen = screen
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()


func _show_error() -> void:
	_clear("error")
	_page.add_child(_label(_error, 26, BAD))
	_page.add_child(_btn("Kembali ke daftar game", _exit))


func _show_home() -> void:
	_clear("home")
	var head := HBoxContainer.new()
	_page.add_child(head)
	var t := _label(str(course.get("title", "Belajar")), 42, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_btn("Riwayat", _show_history))
	head.add_child(_btn("◀ Semua Game", _exit))
	_page.add_child(_label(str(course.get("subtitle", "")), 22, Color(1, 1, 1, 0.7)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_page.add_child(grid)
	for s: Dictionary in course.subjects:
		var done := 0
		var stars := 0
		for l: Dictionary in s.levels:
			var best := int(_level_rec(s, l).get("best", -1))
			if best >= 0:
				done += 1
			if best >= int(course.get("pass_score", 70)):
				stars += 1
		var b := _btn("%s\n%d/%d level lulus" % [str(s.name), stars, s.levels.size()], _show_subject.bind(s), 28)
		b.custom_minimum_size = Vector2(0, 130)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", _box(Color.from_string(str(s.get("color", "#2b4a66")), CARD)))
		grid.add_child(b)


func _show_subject(s: Dictionary) -> void:
	_subject = s
	_clear("subject")
	var head := HBoxContainer.new()
	_page.add_child(head)
	var t := _label(str(s.name), 38, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_btn("◀ Mata pelajaran", _show_home))
	var pass_score := int(course.get("pass_score", 70))
	_page.add_child(_label("Nilai minimal %d untuk membuka level berikutnya." % pass_score, 20, Color(1, 1, 1, 0.7)))
	for i in s.levels.size():
		var l: Dictionary = s.levels[i]
		var rec := _level_rec(s, l)
		var open := _unlocked(s, i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_page.add_child(row)
		var info := "%s — %s" % [str(l.name), ("nilai terbaik %d (%d kali)" % [int(rec.best), int(rec.get("attempts", 0))]) if rec.has("best") else "belum dicoba"]
		if not open:
			info = "%s — terkunci" % str(l.name)
		var lab := _label(info, 24, Color.WHITE if open else Color(1, 1, 1, 0.45))
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var b1 := _btn("Latihan", _start.bind(s, l, "latihan"))
		var b2 := _btn("Kuis", _start.bind(s, l, "kuis"))
		b1.disabled = not open
		b2.disabled = not open
		row.add_child(b1)
		row.add_child(b2)


func _start(s: Dictionary, l: Dictionary, mode: String) -> void:
	_subject = s
	_level = l
	_mode = mode
	var per := int(course.get("questions_per_session", 8))
	if l.has("generator"):
		var cfg: Dictionary = (l.generator as Dictionary).duplicate()
		cfg["count"] = int(cfg.get("count", per))
		_questions = QuestionGen.generate(cfg, rng)
	else:
		var pool: Array = (l.questions as Array).duplicate()
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		_questions = []
		for q in pool.slice(0, mini(per, pool.size())):
			_questions.append(_shuffle_options(q))
	_index = 0
	_answers = []
	_show_question()


## Salinan soal dengan urutan pilihan diacak (jawaban benar tetap ditandai dengan benar).
func _shuffle_options(q: Dictionary) -> Dictionary:
	var opts: Array = (q.options as Array).duplicate()
	var correct = opts[int(q.answer)]
	for i in range(opts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = opts[i]
		opts[i] = opts[j]
		opts[j] = t
	var c: Dictionary = q.duplicate()
	c.options = opts
	c.answer = opts.find(correct)
	return c


func _show_question() -> void:
	_clear("question")
	_answered = false
	var q: Dictionary = _questions[_index]
	var head := HBoxContainer.new()
	_page.add_child(head)
	var t := _label("%s · %s · %s" % [str(_subject.name), str(_level.name), "Latihan" if _mode == "latihan" else "Kuis"], 22, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var counter := _label("Soal %d / %d" % [_index + 1, _questions.size()], 22, Color.WHITE)
	counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(counter)
	var bar := ProgressBar.new()
	bar.max_value = _questions.size()
	bar.value = _index
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	_page.add_child(bar)
	_page.add_child(_label(str(q.q), 34, Color.WHITE))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_page.add_child(grid)
	_opts_grid = grid
	var letters := ["A", "B", "C", "D", "E"]
	for i in (q.options as Array).size():
		var b := _btn("%s.  %s" % [letters[i], str(q.options[i])], _choose.bind(i), 28)
		b.name = "Opt%d" % i
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 88)
		grid.add_child(b)
	_feedback = _label("", 24, Color.WHITE)
	_page.add_child(_feedback)
	_next_btn = _btn("Lanjut ▶", _next, 26)
	_next_btn.visible = false
	_page.add_child(_next_btn)


func _choose(i: int) -> void:
	if _answered:
		return
	_answered = true
	var q: Dictionary = _questions[_index]
	var ans := int(q.answer)
	var correct := i == ans
	_answers.append({"q": str(q.q), "chosen": str(q.options[i]), "answer": str(q.options[ans]), "correct": correct,
		"explain": str(q.get("explain", ""))})
	var grid := _opts_grid
	for b: Button in grid.get_children():
		b.disabled = true
	if _mode == "latihan":
		(grid.get_node("Opt%d" % ans) as Button).add_theme_stylebox_override("disabled", _box(GOOD.darkened(0.3)))
		if not correct:
			(grid.get_node("Opt%d" % i) as Button).add_theme_stylebox_override("disabled", _box(BAD.darkened(0.3)))
		var fb := _feedback
		fb.text = ("Benar! " if correct else "Belum tepat. Jawaban: %s. " % str(q.options[ans])) + str(q.get("explain", ""))
		fb.add_theme_color_override("font_color", GOOD if correct else BAD)
		_next_btn.visible = true
	else:
		(grid.get_node("Opt%d" % i) as Button).add_theme_stylebox_override("disabled", _box(ACCENT.darkened(0.4)))
		await get_tree().create_timer(0.35).timeout
		if is_inside_tree() and _screen == "question":
			_next()


func _next() -> void:
	_index += 1
	if _index >= _questions.size():
		_finish()
	else:
		_show_question()


func _finish() -> void:
	var correct := 0
	for a: Dictionary in _answers:
		if a.correct:
			correct += 1
	var total := _answers.size()
	var score := int(round(100.0 * correct / maxf(1.0, total)))
	var key := _key(_subject, _level)
	var rec: Dictionary = (progress.levels as Dictionary).get(key, {})
	var was_best := int(rec.get("best", -1))
	rec["best"] = maxi(was_best, score)
	rec["last"] = score
	rec["attempts"] = int(rec.get("attempts", 0)) + 1
	progress.levels[key] = rec
	var hist: Array = progress.history
	hist.push_front({"at": Time.get_datetime_string_from_system(false, true), "subject": str(_subject.name),
		"level": str(_level.name), "mode": _mode, "score": score, "correct": correct, "total": total})
	progress.history = hist.slice(0, MAX_HISTORY)
	progress["last_answers"] = _answers
	_save()
	_show_result(score, correct, total, score > was_best and was_best >= 0)


func _show_result(score: int, correct: int, total: int, new_best: bool) -> void:
	_clear("result")
	var pass_score := int(course.get("pass_score", 70))
	_page.add_child(_label("Nilai: %d" % score, 56, GOOD if score >= pass_score else BAD))
	_page.add_child(_label("%d dari %d jawaban benar%s" % [correct, total, " · rekor baru!" if new_best else ""], 26, Color.WHITE))
	var idx: int = (_subject.levels as Array).find(_level)
	if score >= pass_score and idx >= 0 and idx + 1 < _subject.levels.size():
		_page.add_child(_label("Level berikutnya terbuka: " + str(_subject.levels[idx + 1].name), 24, ACCENT))
	elif score < pass_score:
		_page.add_child(_label("Butuh nilai %d untuk lulus level ini. Coba lagi!" % pass_score, 24, Color(1, 1, 1, 0.8)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_page.add_child(row)
	row.add_child(_btn("Ulangi", _start.bind(_subject, _level, _mode)))
	row.add_child(_btn("Pilih level", _show_subject.bind(_subject)))
	row.add_child(_btn("Mata pelajaran", _show_home))
	_page.add_child(_label("Pembahasan jawaban:", 24, ACCENT))
	for a: Dictionary in _answers:
		var line := "%s %s\n   Jawabanmu: %s%s" % ["✓" if a.correct else "✗", a.q, a.chosen,
			"" if a.correct else "   ·   Benar: " + str(a.answer)]
		if str(a.get("explain", "")) != "" and not a.correct:
			line += "\n   " + str(a.explain)
		_page.add_child(_label(line, 20, GOOD if a.correct else BAD))


func _show_history() -> void:
	_clear("history")
	var head := HBoxContainer.new()
	_page.add_child(head)
	var t := _label("Riwayat latihan", 38, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_btn("◀ Kembali", _show_home))
	var hist: Array = progress.get("history", [])
	if hist.is_empty():
		_page.add_child(_label("Belum ada latihan.", 24, Color(1, 1, 1, 0.7)))
	for h: Dictionary in hist:
		_page.add_child(_label("%s  ·  %s %s (%s)  ·  nilai %d (%d/%d)" % [str(h.at), str(h.subject), str(h.level),
			str(h.mode), int(h.score), int(h.correct), int(h.total)], 22, Color.WHITE))


func _exit() -> void:
	_save()
	var gm = _gm()
	if gm != null:
		gm.exit_to_launcher()
	else:
		get_tree().quit()


# --- Bantuan UI ---------------------------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _btn(text: String, cb: Callable, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_stylebox_override("normal", _box(CARD))
	b.add_theme_stylebox_override("hover", _box(CARD.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _box(CARD.lightened(0.2)))
	b.add_theme_stylebox_override("disabled", _box(CARD.darkened(0.2)))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.75))
	b.pressed.connect(cb)
	return b


static func _box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(14)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s
