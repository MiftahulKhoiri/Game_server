extends VBoxContainer
## Tampilan SATU soal untuk semua tipe Pulau Ilmu. Jawaban benar tidak pernah ditampilkan sebelum
## pemain menjawab. Mode:
##   latihan     : boleh mencoba lagi, petunjuk tersedia, penjelasan muncul setelah menjawab
##   petualangan : satu kesempatan, penjelasan langsung, jawaban benar membuka jalan
##   kuis        : tanpa umpan balik; pembahasan di akhir sesi
## Sinyal finished(result) dipancarkan saat pemain lanjut ke soal berikutnya:
##   {correct: bool, first_try: bool, given: String, answer: String, retried: bool}

signal finished(result: Dictionary)
signal feedback(correct: bool)

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const SdArt := preload("res://games/education_sd/scripts/sd_art.gd")
const Voice := preload("res://games/education_sd/scripts/voice.gd")

const MAX_TRIES := 3

var q: Dictionary
var mode := "latihan"
var rng: RandomNumberGenerator
var type_names: Dictionary = {}
var audio: Node

var _tries := 0
var _mistakes := 0
var _done := false
var _given := ""
var _options: Array = []      # pilihan teks (sudah diacak) untuk tipe pilihan
var _answer := -1
var _opt_buttons: Array = []
var _fb: Label
var _next: Button
var _hint_btn: Button
var _body: VBoxContainer
var _q_text := ""
# susun (huruf/kata/angka)
var _pool: Array = []
var _placed: Array = []
var _target: Array = []
var _pool_box: HFlowContainer
var _ans_box: HFlowContainer
# pasangkan
var _sel_left := -1
var _left_btns: Array = []
var _right_btns: Array = []
var _right_vals: Array = []
var _matched := 0
# kelompokkan
var _items: Array = []
var _item_i := 0
var _item_lbl: Label
var _bin_btns: Array = []
# hitung
var _count_icons: Array = []


func setup(question: Dictionary, play_mode: String, random: RandomNumberGenerator, names: Dictionary, sound: Node) -> void:
	q = question
	mode = play_mode
	rng = random
	type_names = names
	audio = sound
	add_theme_constant_override("separation", 14)
	var head := UI.hbox()
	var tag := UI.label(str(type_names.get(q.type, q.type)), 20, UI.SOFT, false)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tag)
	if Voice.listen_ok():
		head.add_child(UI.listen_button(func() -> void: Voice.say(read_text())))
	if mode != "kuis":
		_hint_btn = UI.button("Petunjuk", _hint, Color("ffe08a"), 22, 56)
		head.add_child(_hint_btn)
	add_child(head)
	var question_text := str(q.q)
	if q.type == "tf":
		question_text = "Benar atau salah?\n" + question_text
	_q_text = question_text
	add_child(UI.label(question_text, 32, UI.INK))
	_body = UI.vbox(12)
	add_child(_body)
	match str(q.type):
		"mc", "logic", "fill":
			_build_choice(false)
		"pick_image":
			_build_choice(true)
		"tf":
			_options = ["Benar", "Salah"]
			_answer = 0 if bool(q.answer) else 1
			_build_option_buttons(false)
		"count":
			_build_count()
		"order_letters":
			var w := str(q.word)
			_target = []
			for ch in w:
				_target.append(ch)
			_build_order(" ")
		"order_words":
			_target = (q.items as Array).duplicate()
			_build_order(" ")
		"sort_numbers":
			var nums: Array = (q.numbers as Array).duplicate()
			nums.sort()
			if bool(q.get("desc", false)):
				nums.reverse()
			_target = nums.map(func(x): return str(int(x)))
			_build_order(" ")
		"match":
			_build_match()
		"classify":
			_build_classify()
	_fb = UI.label("", 26, UI.INK)
	_fb.visible = false
	add_child(_fb)
	_next = UI.button("Lanjut", _emit_finish, UI.PRIMARY, 30, 80)
	_next.visible = false
	add_child(_next)
	Voice.say_auto(read_text())


## Teks yang dibacakan suara pembaca: soal + pilihan jawaban (urutan seperti di layar).
func read_text() -> String:
	var t := _q_text
	if str(q.type) in ["mc", "logic", "fill", "pick_image", "count"] and not _options.is_empty():
		var opts: Array = _options.map(func(o): return str(o).replace("_", " "))
		t += "\nPilihannya: " + ", ".join(opts) + "."
	elif str(q.type) == "classify" and not _items.is_empty() and _item_i < _items.size():
		t += "\n" + str(_items[_item_i][0])
	return t


# --- Pilihan (pilihan ganda, isian, logika, gambar, benar/salah, hitung) -------------------------------

func _build_choice(images: bool) -> void:
	var opts: Array = (q.options as Array).duplicate()
	var correct = opts[int(q.answer)]
	for i in range(opts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = opts[i]
		opts[i] = opts[j]
		opts[j] = t
	_options = opts
	_answer = opts.find(correct)
	_build_option_buttons(images)


func _build_option_buttons(images: bool) -> void:
	var g := UI.grid(4 if images else 2)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(g)
	var colors := [Color("7fb7f0"), Color("9ad8a6"), Color("f5c26b"), Color("e9a6d8")]
	_opt_buttons.clear()
	for i in _options.size():
		var b: Button
		if images:
			b = UI.button("", _choose.bind(i), colors[i % 4], 20, 170)
			var icon := SdArt.ShapeIcon.new(str(_options[i]), Color("ffd166"))
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 12
			icon.offset_top = 12
			icon.offset_right = -12
			icon.offset_bottom = -12
			b.add_child(icon)
			b.tooltip_text = str(_options[i]).replace("_", " ")
		else:
			b = UI.button(str(_options[i]), _choose.bind(i), colors[i % 4], 30 if str(_options[i]).length() < 18 else 24, 96)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
		_opt_buttons.append(b)


func _build_count() -> void:
	var n := int(q.count)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	var colors := [Color("ffd166"), Color("7fb7f0"), Color("9ad8a6")]
	for i in n:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(64, 64)
		var ic := SdArt.ShapeIcon.new(str(q.shape), colors[i % 3])
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(ic)
		var num := UI.label(str(i + 1), 20, UI.INK, false)
		num.visible = false
		num.position = Vector2(0, -6)
		holder.add_child(num)
		_count_icons.append(num)
		flow.add_child(holder)
	_body.add_child(flow)
	var opts: Array = [n]
	var guard := 0
	while opts.size() < 4 and guard < 40:
		guard += 1
		var w := n + rng.randi_range(-3, 3)
		if w > 0 and not opts.has(w):
			opts.append(w)
	opts.sort()
	_options = opts.map(func(x): return str(x))
	_answer = opts.find(n)
	_build_option_buttons(false)


func _choose(i: int) -> void:
	if _done:
		return
	_given = str(_options[i])
	var ok := i == _answer
	if ok:
		_resolve(true, _opt_buttons[i])
	else:
		_mistake(_opt_buttons[i])
		if mode == "latihan" and _tries < MAX_TRIES:
			_opt_buttons[i].disabled = true
		else:
			_resolve(false, _opt_buttons[i])


# --- Susun (huruf, kata/urutan, angka) -----------------------------------------------------------------

func _build_order(_sep: String) -> void:
	_pool = _target.duplicate()
	var guard := 0
	while _pool == _target and guard < 10:
		guard += 1
		for i in range(_pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = _pool[i]
			_pool[i] = _pool[j]
			_pool[j] = t
	var ans_panel := UI.panel(Color("eef3ff"))
	_ans_box = HFlowContainer.new()
	_ans_box.custom_minimum_size = Vector2(0, 80)
	_ans_box.add_theme_constant_override("h_separation", 10)
	ans_panel.add_child(_ans_box)
	_body.add_child(UI.label("Ketuk sesuai urutan:", 22, UI.SOFT, false))
	_body.add_child(ans_panel)
	_pool_box = HFlowContainer.new()
	_pool_box.add_theme_constant_override("h_separation", 10)
	_pool_box.add_theme_constant_override("v_separation", 10)
	_body.add_child(_pool_box)
	var row := UI.hbox()
	row.add_child(UI.button("Ulangi susunan", _reset_order, Color("cfc8dc"), 22, 60))
	_body.add_child(row)
	_redraw_order()


func _redraw_order() -> void:
	for c in _pool_box.get_children():
		c.queue_free()
	for c in _ans_box.get_children():
		c.queue_free()
	for i in _pool.size():
		var b := UI.button(str(_pool[i]), _place.bind(i), Color("ffd166"), 30, 72)
		b.custom_minimum_size.x = 72
		_pool_box.add_child(b)
	for v in _placed:
		var l := UI.button(str(v), Callable(), Color("9ad8a6"), 30, 72)
		l.custom_minimum_size.x = 72
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ans_box.add_child(l)


func _place(i: int) -> void:
	if _done or i >= _pool.size():
		return
	if audio != null:
		audio.play("klik")
	_placed.append(_pool[i])
	_pool.remove_at(i)
	_redraw_order()
	if _pool.is_empty():
		_given = " ".join(PackedStringArray(_placed.map(func(x): return str(x))))
		if _placed == _target:
			_resolve(true, _ans_box)
		else:
			_mistake(_ans_box)
			if mode == "latihan" and _tries < MAX_TRIES:
				_reset_order()
			else:
				_resolve(false, _ans_box)


func _reset_order() -> void:
	if _done:
		return
	_pool.append_array(_placed)
	_placed.clear()
	_redraw_order()


# --- Pasangkan --------------------------------------------------------------------------------------

func _build_match() -> void:
	var pairs: Array = q.pairs
	var lefts: Array = []
	_right_vals = []
	for p in pairs:
		lefts.append(str(p[0]))
		_right_vals.append(str(p[1]))
	for i in range(_right_vals.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = _right_vals[i]
		_right_vals[i] = _right_vals[j]
		_right_vals[j] = t
	_body.add_child(UI.label("Ketuk satu kata di kiri, lalu pasangannya di kanan.", 22, UI.SOFT))
	var cols := UI.hbox(40)
	var lc := UI.vbox(10)
	var rc := UI.vbox(10)
	UI.expand(lc)
	UI.expand(rc)
	cols.add_child(lc)
	cols.add_child(rc)
	_body.add_child(cols)
	for i in lefts.size():
		var b := UI.button(lefts[i], _pick_left.bind(i), Color("7fb7f0"), 26, 70)
		lc.add_child(b)
		_left_btns.append(b)
	for i in _right_vals.size():
		var b := UI.button(_right_vals[i], _pick_right.bind(i), Color("f5c26b"), 26, 70)
		rc.add_child(b)
		_right_btns.append(b)


func _pick_left(i: int) -> void:
	if _done:
		return
	_sel_left = i
	for k in _left_btns.size():
		if not _left_btns[k].disabled:
			_left_btns[k].add_theme_stylebox_override("normal", UI.box(Color("3f7fd8") if k == i else Color("7fb7f0")))
	if audio != null:
		audio.play("klik")


func _pick_right(i: int) -> void:
	if _done or _sel_left < 0:
		return
	var pairs: Array = q.pairs
	var want := str(pairs[_sel_left][1])
	if _right_vals[i] == want:
		for b in [_left_btns[_sel_left], _right_btns[i]]:
			b.disabled = true
			b.add_theme_stylebox_override("disabled", UI.box(Color("9ad8a6")))
		_matched += 1
		if audio != null:
			audio.play("benar")
		UI.pop(_right_btns[i])
		_sel_left = -1
		if _matched == pairs.size():
			_given = "semua pasangan tepat"
			_resolve(_mistakes == 0, _body, true)
	else:
		_mistake(_right_btns[i])
		if mode == "kuis" and _mistakes >= 2:
			_given = "%d pasangan salah" % _mistakes
			_resolve(false, _body)


# --- Kelompokkan -------------------------------------------------------------------------------------

func _build_classify() -> void:
	_items = (q.items as Array).duplicate()
	for i in range(_items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = _items[i]
		_items[i] = _items[j]
		_items[j] = t
	var card := UI.panel(Color("fff3c4"))
	_item_lbl = UI.label("", 40, UI.INK)
	_item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_item_lbl)
	_body.add_child(card)
	var row := UI.hbox()
	var colors := [Color("7fb7f0"), Color("f5c26b"), Color("9ad8a6")]
	for i in (q.bins as Array).size():
		var b := UI.button(str(q.bins[i]), _put.bind(i), colors[i % 3], 28, 90)
		UI.expand(b)
		row.add_child(b)
		_bin_btns.append(b)
	_body.add_child(row)
	_show_item()


func _show_item() -> void:
	_item_lbl.text = "%s   (%d/%d)" % [str(_items[_item_i][0]), _item_i + 1, _items.size()]
	UI.fade_in(_item_lbl)


func _put(b: int) -> void:
	if _done:
		return
	var want := int(_items[_item_i][1])
	if b == want:
		if audio != null:
			audio.play("benar")
		UI.pop(_bin_btns[b])
	else:
		_mistake(_bin_btns[b])
		_fb.visible = mode != "kuis"
		_fb.text = "%s termasuk kelompok %s." % [str(_items[_item_i][0]), str(q.bins[want])]
	_item_i += 1
	if _item_i >= _items.size():
		_given = "%d dari %d tepat" % [_items.size() - _mistakes, _items.size()]
		_resolve(_mistakes == 0 or (mode == "latihan" and _mistakes <= 1), _body, true)
	else:
		_show_item()


# --- Hasil -----------------------------------------------------------------------------------------

func _mistake(node: Control) -> void:
	_tries += 1
	_mistakes += 1
	feedback.emit(false)
	if mode == "kuis":
		return
	if audio != null:
		audio.play("salah")
	UI.shake(node)
	if mode == "latihan" and not _done:
		_fb.visible = true
		_fb.text = "Belum tepat, coba lagi ya! Kamu pasti bisa."
		_fb.add_theme_color_override("font_color", UI.SOFT_BAD)
		Voice.say_auto(_fb.text)


## Soal selesai. ok = jawaban akhirnya benar. partial = tipe bertahap (pasangkan/kelompokkan) yang
## diselesaikan sampai habis.
func _resolve(ok: bool, node: Control, partial := false) -> void:
	if _done:
		return
	_done = true
	for b in _opt_buttons:
		b.disabled = true
	if _hint_btn != null:
		_hint_btn.disabled = true
	if ok:
		feedback.emit(true)
	var answer_text := _answer_text()
	if mode == "kuis":
		_emit_finish.call_deferred()
		return
	if ok:
		if audio != null:
			audio.play("benar")
		UI.pop(node)
	if _answer >= 0 and _answer < _opt_buttons.size():
		_opt_buttons[_answer].add_theme_stylebox_override("disabled", UI.box(Color("9ad8a6")))
	_fb.visible = true
	var head := "Hebat, benar!" if ok and _mistakes == 0 else ("Bagus, akhirnya tepat!" if ok else "Jawaban yang tepat: %s." % answer_text)
	if partial and not ok:
		head = "Sudah selesai! Perhatikan pembahasannya."
	_fb.text = head + "\n" + str(q.explain)
	_fb.add_theme_color_override("font_color", UI.GOOD if ok else UI.SOFT_BAD)
	_next.visible = true
	UI.fade_in(_fb)
	Voice.say_auto(_fb.text)


func _answer_text() -> String:
	match str(q.type):
		"mc", "logic", "fill", "pick_image", "tf", "count":
			return str(_options[_answer]).replace("_", " ") if _answer >= 0 else ""
		"order_letters":
			return str(q.word)
		"order_words", "sort_numbers":
			return " ".join(PackedStringArray(_target.map(func(x): return str(x))))
		"match":
			return ", ".join(PackedStringArray((q.pairs as Array).map(func(p): return "%s–%s" % [p[0], p[1]])))
		"classify":
			return "lihat pembahasan"
	return ""


func _emit_finish() -> void:
	Voice.hush()
	var correct := _is_correct()
	finished.emit({"correct": correct, "first_try": correct and _mistakes == 0, "given": _given.replace("_", " "),
		"answer": _answer_text(), "retried": _mistakes > 0 and correct, "question": q, "explain": str(q.explain)})


func _is_correct() -> bool:
	match str(q.type):
		"mc", "logic", "fill", "pick_image", "tf", "count":
			return _given.replace("_", " ") == _answer_text()
		"order_letters", "order_words", "sort_numbers":
			return _placed == _target
		"match":
			return _matched == (q.pairs as Array).size()
		"classify":
			return _item_i >= _items.size() and (_mistakes == 0 or (mode == "latihan" and _mistakes <= 1))
	return false


# --- Petunjuk ----------------------------------------------------------------------------------------

func _hint() -> void:
	if _done:
		return
	if audio != null:
		audio.play("klik")
	match str(q.type):
		"mc", "logic", "fill", "pick_image":
			var wrong: Array = []
			for i in _opt_buttons.size():
				if i != _answer and not _opt_buttons[i].disabled:
					wrong.append(i)
			if wrong.size() > 1:
				_opt_buttons[wrong[rng.randi_range(0, wrong.size() - 1)]].disabled = true
				_say("Satu jawaban yang kurang tepat sudah disembunyikan.")
			else:
				_say(str(q.get("hint", "Baca soalnya pelan-pelan sekali lagi.")))
		"tf":
			_say(str(q.get("hint", "Baca kalimatnya pelan-pelan. Apakah semuanya sesuai kenyataan?")))
		"count":
			for l in _count_icons:
				l.visible = true
			_say("Setiap gambar sudah diberi nomor. Lihat nomor terakhir!")
		"order_letters", "order_words", "sort_numbers":
			var nxt = _target[_placed.size()] if _placed.size() < _target.size() else null
			if _placed != _target.slice(0, _placed.size()):
				_reset_order()
				nxt = _target[0]
			if nxt != null:
				_place(_pool.find(nxt))
				_say("Satu bagian sudah dipasang di tempat yang benar.")
		"match":
			for i in _left_btns.size():
				if not _left_btns[i].disabled:
					_pick_left(i)
					_pick_right(_right_vals.find(str(q.pairs[i][1])))
					_say("Satu pasangan sudah dibantu.")
					break
		"classify":
			var want := int(_items[_item_i][1])
			UI.pop(_bin_btns[want])
			_say("%s termasuk kelompok %s." % [str(_items[_item_i][0]), str(q.bins[want])])


func _say(text: String) -> void:
	_fb.visible = true
	_fb.text = text
	_fb.add_theme_color_override("font_color", UI.SOFT)
