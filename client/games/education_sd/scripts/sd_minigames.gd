extends RefCounted
## Mini-game Pulau Ilmu (offline, satu per mata pelajaran). Setiap mini-game adalah VBoxContainer dengan
## setup(kelas, data, rng, audio) dan sinyal done(score, total, extra). extra berisi koleksi baru (hewan).

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")
const SdGen := preload("res://games/education_sd/scripts/sd_gen.gd")

const LIST := [
	{"id": "kode", "region": "matematika", "name": "Pintu Kode Angka",
	 "goal": "Tujuan belajar: berhitung dengan teliti. Ketik hasil hitungan untuk membuka 5 pintu kerajaan."},
	{"id": "huruf", "region": "bahasa", "name": "Huruf yang Hilang",
	 "goal": "Tujuan belajar: mengeja kata dengan benar. Pilih huruf yang hilang dari setiap kata."},
	{"id": "hewan", "region": "ipa", "name": "Kelompokkan Hewan",
	 "goal": "Tujuan belajar: mengenal jenis hewan menurut makanannya (herbivora, karnivora, omnivora)."},
	{"id": "pasangan", "region": "ips", "name": "Pasangan Nusantara",
	 "goal": "Tujuan belajar: mengenal pekerjaan dan alatnya, serta rumah adat dan daerahnya."},
]


static func create(id: String) -> VBoxContainer:
	match id:
		"kode":
			return KodePintu.new()
		"huruf":
			return HurufHilang.new()
		"hewan":
			return KelompokHewan.new()
		"pasangan":
			return PasanganNusantara.new()
	return null


static func info(id: String) -> Dictionary:
	for m in LIST:
		if m.id == id:
			return m
	return {}


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## --- Matematika: ketik kode angka (hasil hitungan) untuk membuka pintu ---------------------------------
class KodePintu extends VBoxContainer:
	signal done(score: int, total: int, extra: Dictionary)
	const ROUNDS := 5
	var grade := 1
	var rng: RandomNumberGenerator
	var audio: Node
	var round_i := 0
	var score := 0
	var tries := 0
	var answer := ""
	var typed := ""
	var door: PanelContainer
	var door_lbl: Label
	var code_lbl: Label
	var fb: Label
	var finished := false

	func setup(g: int, _doc: Dictionary, r: RandomNumberGenerator, a: Node) -> void:
		grade = g
		rng = r
		audio = a
		add_theme_constant_override("separation", 12)
		var row := UI.hbox(24)
		add_child(row)
		door = UI.panel(Color("8a5a2b"), 16)
		door.custom_minimum_size = Vector2(300, 300)
		door_lbl = UI.label("", 40, Color.WHITE)
		door_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		door_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		door.add_child(door_lbl)
		row.add_child(door)
		var right := UI.vbox(10)
		UI.expand(right)
		row.add_child(right)
		code_lbl = UI.label("", 48, UI.INK, false)
		code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var code_panel := UI.panel(Color("eef3ff"))
		code_panel.add_child(code_lbl)
		right.add_child(code_panel)
		var pad := UI.grid(4, 10)
		for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Hapus", "OK"]:
			var col := UI.GOOD if k == "OK" else (Color("cfc8dc") if k == "Hapus" else Color("ffd166"))
			var b := UI.button(k, _key.bind(k), col, 30, 72)
			UI.expand(b)
			pad.add_child(b)
		right.add_child(pad)
		fb = UI.label("", 24, UI.SOFT)
		add_child(fb)
		_next_round()

	func _spec() -> String:
		var by_grade := {1: ["add:1:10", "sub:1:20"], 2: ["add:10:50", "sub:10:99", "mul:1:5"], 3: ["mul:2:10", "div:2:10", "add:100:500"],
			4: ["mul2x1", "div:2:12", "sub:100:999"], 5: ["mul2x2", "div:5:25", "pow"], 6: ["pow", "mul2x2", "div:10:50"]}
		var specs: Array = by_grade.get(grade, by_grade[1])
		return str(specs[rng.randi_range(0, specs.size() - 1)])

	func _next_round() -> void:
		if round_i >= ROUNDS:
			finished = true
			fb.text = "Semua pintu sudah dicoba! %d dari %d pintu terbuka." % [score, ROUNDS]
			done.emit(score, ROUNDS, {})
			return
		var q := SdGen.make(_spec(), "kode", grade, rng)
		answer = str(q.options[int(q.answer)]).replace(".", "")
		door_lbl.text = "Pintu %d\n\n%s" % [round_i + 1, str(q.q).replace(" = …", " = ?")]
		door.modulate = Color.WHITE
		door.scale = Vector2.ONE
		typed = ""
		tries = 0
		code_lbl.text = "_"
		fb.text = "Ketik hasilnya, lalu tekan OK."

	func _key(k: String) -> void:
		if finished:
			return
		if audio != null:
			audio.play("klik")
		match k:
			"Hapus":
				typed = typed.substr(0, maxi(0, typed.length() - 1))
			"OK":
				_check()
				return
			_:
				if typed.length() < 7:
					typed += k
		code_lbl.text = typed if typed != "" else "_"

	func type_and_submit(text: String) -> void:  # dipakai uji otomatis
		typed = text
		_check()

	func current_answer() -> String:
		return answer

	func _check() -> void:
		if typed == "":
			return
		if typed == answer:
			score += 1
			if audio != null:
				audio.play("buka")
			fb.text = "Pintu terbuka!"
			door.pivot_offset = door.size / 2
			var tw := door.create_tween()
			tw.tween_property(door, "scale", Vector2(0.05, 1.0), 0.35)
			tw.tween_callback(func() -> void:
				round_i += 1
				_next_round())
		else:
			tries += 1
			if audio != null:
				audio.play("salah")
			UI.shake(door)
			if tries >= 2:
				fb.text = "Kodenya %s. Ayo ke pintu berikutnya!" % answer
				round_i += 1
				get_tree().create_timer(1.4).timeout.connect(_next_round)
			else:
				fb.text = "Belum tepat. Hitung sekali lagi pelan-pelan!"
				typed = ""
				code_lbl.text = "_"


## --- Bahasa: pilih huruf yang hilang -------------------------------------------------------------------
class HurufHilang extends VBoxContainer:
	signal done(score: int, total: int, extra: Dictionary)
	const ROUNDS := 8
	var rng: RandomNumberGenerator
	var audio: Node
	var words: Array = []
	var round_i := 0
	var score := 0
	var word := ""
	var missing := ""
	var word_lbl: Label
	var opts_box: HBoxContainer
	var fb: Label
	var finished := false
	var locked := false

	func setup(g: int, doc: Dictionary, r: RandomNumberGenerator, a: Node) -> void:
		rng = r
		audio = a
		add_theme_constant_override("separation", 16)
		words = (doc.get("minigames", {}).get("huruf_hilang", {}).get(str(g), []) as Array).duplicate()
		UI.shuffle(words, rng)
		var card := UI.panel(Color("fff3c4"))
		word_lbl = UI.label("", 64, UI.INK, false)
		word_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(word_lbl)
		add_child(card)
		opts_box = UI.hbox(16)
		add_child(opts_box)
		fb = UI.label("", 26, UI.SOFT)
		add_child(fb)
		_next_round()

	func _next_round() -> void:
		locked = false
		if round_i >= mini(ROUNDS, words.size()):
			finished = true
			done.emit(score, mini(ROUNDS, words.size()), {})
			fb.text = "Selesai! %d kata benar." % score
			return
		word = str(words[round_i])
		var idxs: Array = []
		for i in word.length():
			if word[i] != " ":
				idxs.append(i)
		var k: int = idxs[rng.randi_range(0, idxs.size() - 1)]
		missing = word[k]
		word_lbl.text = word.substr(0, k) + "_" + word.substr(k + 1)
		var letters := [missing]
		var abc := "ABCDEFGHIJKLMNOPRSTUWY"
		while letters.size() < 4:
			var l := abc[rng.randi_range(0, abc.length() - 1)]
			if not letters.has(l):
				letters.append(l)
		UI.shuffle(letters, rng)
		for c in opts_box.get_children():
			c.queue_free()
		for l in letters:
			var b := UI.button(l, _pick.bind(l), Color("7fb7f0"), 44, 110)
			UI.expand(b)
			opts_box.add_child(b)
		fb.text = "Kata %d dari %d: huruf apa yang hilang?" % [round_i + 1, mini(ROUNDS, words.size())]

	func current_answer() -> String:
		return missing

	func pick(l: String) -> void:  # dipakai uji otomatis
		_pick(l)

	func _pick(l: String) -> void:
		if finished or locked:
			return
		locked = true
		if l == missing:
			score += 1
			if audio != null:
				audio.play("benar")
			fb.text = "Benar! Kata lengkapnya: %s" % word
		else:
			if audio != null:
				audio.play("salah")
			fb.text = "Huruf yang hilang adalah %s. Kata lengkapnya: %s" % [missing, word]
		word_lbl.text = word
		round_i += 1
		get_tree().create_timer(1.1).timeout.connect(_next_round)


## --- IPA: kelompokkan hewan menurut makanannya --------------------------------------------------------
class KelompokHewan extends VBoxContainer:
	signal done(score: int, total: int, extra: Dictionary)
	const ROUNDS := 8
	var rng: RandomNumberGenerator
	var audio: Node
	var facts: Dictionary = {}
	var queue: Array = []  # [[hewan, kelompok]]
	var bins: Array = []
	var round_i := 0
	var score := 0
	var learned: Array = []
	var animal_lbl: Label
	var fb: Label
	var finished := false
	var locked := false

	func setup(g: int, doc: Dictionary, r: RandomNumberGenerator, a: Node) -> void:
		rng = r
		audio = a
		add_theme_constant_override("separation", 16)
		var groups: Dictionary = doc.get("minigames", {}).get("hewan", {})
		facts = doc.get("animal_facts", {})
		bins = ["herbivora", "karnivora"] if g <= 3 else ["herbivora", "karnivora", "omnivora"]
		for b in bins:
			for an in groups.get(b, []):
				queue.append([str(an), b])
		UI.shuffle(queue, rng)
		queue = queue.slice(0, ROUNDS)
		var card := UI.panel(Color("e3f7ef"))
		animal_lbl = UI.label("", 56, UI.INK, false)
		animal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(animal_lbl)
		add_child(card)
		var row := UI.hbox(16)
		var names := {"herbivora": "Herbivora\n(pemakan tumbuhan)", "karnivora": "Karnivora\n(pemakan daging)", "omnivora": "Omnivora\n(pemakan segala)"}
		var colors := [Color("9ad8a6"), Color("f5a26b"), Color("c9b2f0")]
		for i in bins.size():
			var b := UI.button(str(names[bins[i]]), _put.bind(bins[i]), colors[i], 24, 110)
			UI.expand(b)
			row.add_child(b)
		add_child(row)
		fb = UI.label("", 24, UI.SOFT)
		add_child(fb)
		_show()

	func _show() -> void:
		locked = false
		if round_i >= queue.size():
			finished = true
			fb.text = "Selesai! %d dari %d hewan dikelompokkan dengan tepat." % [score, queue.size()]
			done.emit(score, queue.size(), {"animals": learned})
			return
		animal_lbl.text = str(queue[round_i][0]).capitalize()
		UI.fade_in(animal_lbl)

	func current_answer() -> String:
		return str(queue[round_i][1]) if round_i < queue.size() else ""

	func put(b: String) -> void:  # dipakai uji otomatis
		_put(b)

	func _put(b: String) -> void:
		if finished or locked:
			return
		locked = true
		var an := str(queue[round_i][0])
		var want := str(queue[round_i][1])
		if b == want:
			score += 1
			learned.append(an)
			if audio != null:
				audio.play("benar")
			fb.text = "Tepat! %s" % str(facts.get(an, ""))
		else:
			if audio != null:
				audio.play("salah")
			fb.text = "%s termasuk %s. %s" % [an.capitalize(), want, str(facts.get(an, ""))]
		round_i += 1
		get_tree().create_timer(1.6).timeout.connect(_show)


## --- IPS: pasangkan pekerjaan–alat (dan rumah adat–daerah untuk kelas 4+) ------------------------------
class PasanganNusantara extends VBoxContainer:
	signal done(score: int, total: int, extra: Dictionary)
	var rng: RandomNumberGenerator
	var audio: Node
	var pairs: Array = []
	var right_vals: Array = []
	var left_btns: Array = []
	var right_btns: Array = []
	var sel := -1
	var matched := 0
	var mistakes := 0
	var fb: Label
	var finished := false

	func setup(g: int, doc: Dictionary, r: RandomNumberGenerator, a: Node) -> void:
		rng = r
		audio = a
		add_theme_constant_override("separation", 12)
		var src: Dictionary = doc.get("minigames", {}).get("pasangan_ips", {})
		var pool: Array = (src.get("pekerjaan", []) as Array).duplicate()
		UI.shuffle(pool, rng)
		pairs = pool.slice(0, 3 if g >= 4 else 5)
		if g >= 4:
			var adat: Array = (src.get("rumah_adat", []) as Array).duplicate()
			UI.shuffle(adat, rng)
			pairs.append_array(adat.slice(0, 3))
		for p in pairs:
			right_vals.append(str(p[1]))
		UI.shuffle(right_vals, rng)
		add_child(UI.label("Ketuk kiri, lalu pasangannya di kanan.", 22, UI.SOFT))
		var cols := UI.hbox(40)
		var lc := UI.vbox(8)
		var rc := UI.vbox(8)
		UI.expand(lc)
		UI.expand(rc)
		cols.add_child(lc)
		cols.add_child(rc)
		add_child(cols)
		for i in pairs.size():
			var b := UI.button(str(pairs[i][0]), _left.bind(i), Color("7fb7f0"), 24, 62)
			lc.add_child(b)
			left_btns.append(b)
		for i in right_vals.size():
			var b := UI.button(right_vals[i], _right.bind(i), Color("f5c26b"), 24, 62)
			rc.add_child(b)
			right_btns.append(b)
		fb = UI.label("", 24, UI.SOFT)
		add_child(fb)

	func pair_count() -> int:
		return pairs.size()

	func right_index_for(i: int) -> int:
		return right_vals.find(str(pairs[i][1]))

	func choose(l: int, r: int) -> void:  # dipakai uji otomatis
		_left(l)
		_right(r)

	func _left(i: int) -> void:
		if finished or left_btns[i].disabled:
			return
		sel = i
		for k in left_btns.size():
			if not left_btns[k].disabled:
				left_btns[k].add_theme_stylebox_override("normal", UI.box(Color("3f7fd8") if k == i else Color("7fb7f0")))

	func _right(i: int) -> void:
		if finished or sel < 0 or right_btns[i].disabled:
			return
		if right_vals[i] == str(pairs[sel][1]):
			for b in [left_btns[sel], right_btns[i]]:
				b.disabled = true
				b.add_theme_stylebox_override("disabled", UI.box(Color("9ad8a6")))
			matched += 1
			if audio != null:
				audio.play("benar")
			fb.text = "%s – %s. Tepat!" % [pairs[sel][0], pairs[sel][1]]
			sel = -1
			if matched == pairs.size():
				finished = true
				var score := maxi(0, pairs.size() - mistakes)
				fb.text = "Semua pasangan selesai! Nilai: %d dari %d." % [score, pairs.size()]
				done.emit(score, pairs.size(), {})
		else:
			mistakes += 1
			if audio != null:
				audio.play("salah")
			UI.shake(right_btns[i])
			fb.text = "Belum cocok, coba pasangan lain."
