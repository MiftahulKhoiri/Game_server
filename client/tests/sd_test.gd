extends SceneTree
## Uji game SD "Petualangan Ilmu — Dunia Enam Pulau" (headless, dari proyek sumber):
## bank soal & pembuat soal, setiap tipe soal, progres belajar lama (skema 1-2), lalu 3.x: data enam pulau,
## aturan buka/pindah pulau, Save Engine skema 3 + migrasi dari 2.x, menu utama, profil petualang, peta,
## berlayar, dunia 3D pulau (gerak, batas pulau, interaksi), pengaturan, simpan & buka ulang.
## Jalankan: GODOT=... scripts/sd-test.sh   (atau make sd-test)

const SdData := preload("res://games/education_sd/scripts/sd_data.gd")
const SdGen := preload("res://games/education_sd/scripts/sd_gen.gd")
const BankAudit := preload("res://games/education_sd/scripts/engine/bank_audit.gd")
const Adaptive := preload("res://games/education_sd/scripts/engine/adaptive.gd")
const SdProgress := preload("res://games/education_sd/scripts/sd_progress.gd")
const SdQuestion := preload("res://games/education_sd/scripts/sd_question.gd")
const SdMini := preload("res://games/education_sd/scripts/sd_minigames.gd")
const SdUI := preload("res://games/education_sd/scripts/sd_ui.gd")
const SaveManager := preload("res://core/save_manager.gd")

const SCENE := "res://games/education_sd/main.tscn"

var _failed := false
var _checks := 0


func _initialize() -> void:
	await process_frame
	for f in ["save.json", "save.json.bak"]:
		DirAccess.remove_absolute(SaveManager.dir_for("education_sd") + "/" + f)
	await _data_tests()
	await _bank_audit_tests()
	await _question_tests()
	await _v3_engine_tests()
	await _v3_npc_tests()
	await _v3_learning_tests()
	await _p3_bugfix_tests()
	await _p4_adaptive_tests()
	await _v3_quest_tests()
	await _v3_reward_tests()
	await _v3_battle_tests()
	await _v4_data_tests()
	await _v3_app_tests()
	await _v5_voice_unit_tests()
	await _v5_voice_app_tests()
	await _v6_settings_tests()
	print("SD: %d pemeriksaan, %s" % [_checks, "GAGAL" if _failed else "LULUS"])
	print("HASIL: " + ("GAGAL" if _failed else "LULUS"))
	quit(1 if _failed else 0)


func _find_button(app: Node, text: String) -> Button:
	for b in app.page().find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _check(cond: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if cond else "  GAGAL ") + label)
	if not cond:
		_failed = true


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


# --- Data, validasi, pembuat soal --------------------------------------------------------------------------

func _data_tests() -> void:
	print("== Data & validasi")
	var d := SdData.new()
	_check(d.load_data(), "data/pulau_ilmu.json termuat")
	_check(d.errors.is_empty(), "semua soal bank lolos validasi (%d galat)" % d.errors.size())
	_check(d.questions.size() >= 300, "bank soal >= 300 (%d)" % d.questions.size())
	_check(d.regions.size() == 7, "tujuh mata pelajaran (Matematika, Bahasa, IPA, IPS, Pancasila, Seni, PJOK)")
	var types := {}
	for q in d.questions:
		types[q.type] = true
	_check(types.size() >= 9, "tipe soal di bank: %d (urutkan angka & logika dibuat otomatis)" % types.size())
	var missing: Array = []
	for g in range(1, 7):
		for r in d.regions:
			var ts := d.topics_for(str(r.id), g)
			if ts.size() < 1:
				missing.append("%s kelas %d" % [r.id, g])
			for t in ts:
				if not d.has_content(str(t.id), g):
					missing.append("%s/%d" % [t.id, g])
	_check(missing.is_empty(), "setiap wilayah punya area dan soal di kelas 1–6 " + str(missing))
	var dup := {}
	var dup_found := false
	for q in d.questions:
		if dup.has(q.id):
			dup_found = true
		dup[q.id] = true
	_check(not dup_found, "ID soal unik")
	var base: Dictionary = d.questions[0].duplicate(true)
	var bad := {
		"jawaban di luar indeks": {"type": "mc", "options": ["a", "b"], "answer": 5},
		"tanpa pertanyaan": {"q": "  "},
		"tanpa penjelasan": {"explain": ""},
		"pilihan kosong": {"type": "mc", "options": ["a", ""], "answer": 0},
		"pilihan kembar": {"type": "mc", "options": ["a", "a"], "answer": 0},
		"tipe asing": {"type": "esai"},
		"kelas 7": {"grade": 7},
		"benar/salah bukan boolean": {"type": "tf", "answer": 1},
		"gambar tidak dikenal": {"type": "pick_image", "options": ["naga", "lingkaran"], "answer": 0},
		"pasangan kembar": {"type": "match", "pairs": [["a", "x"], ["b", "x"]]},
		"kelompok tidak sah": {"type": "classify", "bins": ["A", "B"], "items": [["x", 0], ["y", 3], ["z", 1]]},
	}
	for label in bad:
		var q := base.duplicate(true)
		q.merge(bad[label], true)
		_check(d.validate_question(q) != "", "validasi menolak: " + label)

	print("== Pembuat soal (kunci jawaban dihitung)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var gen_ok := true
	var arith_ok := true
	var n := 0
	for id in d.topics:
		var gens: Dictionary = d.topics[id].get("gen", {})
		for g in gens:
			for spec in gens[g]:
				for i in 25:
					var q := SdGen.make(str(spec), str(id), int(g), rng)
					n += 1
					if q.is_empty() or d.validate_question(q) != "":
						gen_ok = false
						print("    soal buatan tidak sah: ", spec, " ", d.validate_question(q))
						continue
					if q.type == "mc" and str(q.q).ends_with("= …") and not str(q.q).contains("²") and not str(q.q).contains("³"):
						var expr := str(q.q).replace(" = …", "").replace("×", "*").replace("−", "-").replace(":", "/").replace(".", "")
						var e := Expression.new()
						if e.parse(expr) == OK:
							var want := str(e.execute()).replace(".0", "")
							if want != str(q.options[int(q.answer)]).replace(".", ""):
								arith_ok = false
								print("    kunci salah: ", q.q, " -> ", q.options[int(q.answer)], " seharusnya ", want)
	_check(gen_ok, "%d soal buatan semuanya sah" % n)
	_check(arith_ok, "kunci jawaban hitungan = hasil Expression")
	var pw := SdGen.make("pow", "perkalian", 6, rng)
	_check(pw.options[int(pw.answer)] != "", "soal pangkat punya kunci")

	print("== Adaptif")
	# Aturan adaptif Prioritas 4 (scripts/engine/adaptive.gd): turun kelas baru setelah >= 8 jawaban di level 1.
	var few := d.pick("penjumlahan", 3, 5, {"at_level": [0, 0, 0, 1, 0, 0], "level": 1, "seen": []}, rng)
	_check(few.mode == "normal" and int(few.grade) == 3, "6 jawaban (5 salah) belum cukup untuk turun kelas")
	var easy := d.pick("penjumlahan", 3, 5, {"at_level": [0, 0, 0, 1, 0, 0, 0, 0], "level": 1, "seen": []}, rng)
	_check(easy.mode == "mudah" and int(easy.grade) == 2, "8 jawaban, sering salah di level 1 -> soal kelas lebih rendah, konsep sama (kelas %d)" % int(easy.grade))
	var rise := d.pick("penjumlahan", 3, 5, {"at_level": [1, 1, 1, 1, 1, 1], "level": 1, "seen": []}, rng)
	_check(rise.mode == "normal" and int(rise.level) == 2 and int(rise.grade) == 3, "sering benar di level 1 -> naik ke level 2 dulu (bertahap)")
	var good := d.pick("penjumlahan", 3, 5, {"at_level": [1, 1, 1, 1, 1, 1, 1, 1], "level": 3, "seen": []}, rng)
	_check(good.mode == "tantang" and int(good.grade) == 3, "level 3 & sangat lancar -> tantang, tetap kelas sendiri")
	var normal := d.pick("bacaan", 4, 5, {"recent": [1, 0], "seen": []}, rng)
	_check(normal.mode == "normal" and (normal.questions as Array).size() == 5, "data sedikit -> tidak disimpulkan, 5 soal")
	var seen_ids: Array = []
	for q in d.by_topic_grade["bacaan/4"]:
		seen_ids.append(q.id)
	var fresh := d.pick("bacaan", 4, 2, {"recent": [], "seen": seen_ids.slice(0, seen_ids.size() - 2)}, rng)
	var fresh_ok := true
	for q in fresh.questions:
		if seen_ids.slice(0, seen_ids.size() - 2).has(q.id):
			fresh_ok = false
	_check(fresh_ok, "soal yang belum dilihat didahulukan")

	print("== Progres & migrasi")
	var v1 := {"levels": {"matematika/k12": {"best": 80, "attempts": 2}, "ipa/k12": {"best": 40, "attempts": 1}},
		"history": [{"at": "2026-11-14 10:00", "subject": "IPA", "level": "Kelas 1–2", "mode": "kuis", "score": 50, "correct": 4, "total": 8}],
		"last_answers": []}
	var up := SdProgress.upgrade(v1.duplicate(true))
	_check(int(up.schema) == 2 and up.has("legacy") and int(up.coins) == 20, "skema 1 -> 2: data lama disimpan di legacy, usaha dihargai koin")
	_check((up.history as Array).size() == 1 and int(up.totals.correct) == 4, "riwayat lama ikut pindah")
	var again := SdProgress.upgrade(up.duplicate(true))
	_check(int(again.coins) == 20 and again.legacy == up.legacy, "upgrade data skema 2 tidak mengubah isi")
	var round_trip := SdProgress.upgrade(JSON.parse_string(JSON.stringify(up)))
	_check(int(round_trip.coins) == 20 and int(round_trip.totals.correct) == 4, "simpan-muat lewat JSON tidak mereset koin/nilai")
	var pp := SdProgress.default_data()
	var fq: Dictionary = d.questions[0]
	SdProgress.record_answer(pp, 1, fq, true, true)
	SdProgress.record_answer(pp, 1, fq, false, false)
	_check(int(pp.totals.answered) == 2 and int(pp.totals.correct) == 1 and int(pp.coins) == 4, "jawaban dicatat; usaha salah tetap dapat koin")
	var area := SdProgress.finish_area(pp, 1, "matematika", d.topics["penjumlahan"], 5, 5)
	_check(int(area.stars) == 3 and str(area.card) == "penjumlahan", "area sempurna: 3 bintang + kartu pengetahuan")
	var area2 := SdProgress.finish_area(pp, 1, "matematika", d.topics["penjumlahan"], 2, 5)
	_check(int(SdProgress.area_rec(pp, 1, "matematika", "penjumlahan").stars) == 3 and str(area2.card) == "", "bintang terbaik dipertahankan, kartu tidak ganda")
	var rep := SdProgress.report(pp, d)
	_check((rep.mastered as Array).is_empty() and int(rep.little_data) >= 1, "laporan tidak menyimpulkan dari 2 jawaban")


# --- Pemeriksa kualitas bank soal (Prioritas 1: struktur + pedagogis + cakupan) -------------------------------

func _audit_has(res: Dictionary, kind: String, id: String) -> bool:
	for it in (res.errors as Array) + (res.warnings as Array):
		if str(it.kind) == kind and str(it.id) == id:
			return true
	return false


func _bank_audit_tests() -> void:
	print("== Pemeriksa kualitas bank soal")
	var d := SdData.new()
	d.load_data()
	var raw: Array = d.doc.get("questions", [])
	var res := BankAudit.audit(raw, d)
	_check(int(res.checked) == raw.size() and raw.size() > 0, "semua %d soal bank diperiksa" % raw.size())
	_check((res.errors as Array).is_empty(), "bank soal terbit: 0 galat (%d)" % (res.errors as Array).size())
	for it in (res.errors as Array).slice(0, 10):
		print("    galat: %s %s %s" % [it.kind, it.id, it.msg])
	var n_tg := 0
	for t in d.topics.values():
		n_tg += (t.get("grades", []) as Array).size()
	_check((res.coverage as Array).size() == n_tg, "cakupan dihitung untuk setiap topik×kelas (%d)" % n_tg)
	for line in BankAudit.summary_text(res).split("\n"):
		print("    " + line)
	# Prioritas 2: peringatan pedagogis ini sudah dibereskan di bank, jadi kini WAJIB 0 agar tidak muncul lagi.
	# (Peringatan heuristik lain — kalimat panjang, jawaban terpanjang, "semua benar" — tetap dicetak sebagai saran.)
	for kind in ["cakupan_tipis", "tanpa_kompetensi", "petunjuk_kosong", "penjelasan_minim", "benar_salah_timpang",
			"kesulitan_datar", "soal_kembar", "kalimat_negatif"]:
		_check(int((res.counts as Dictionary).get(kind, 0)) == 0, "bank soal: 0 \"%s\" (%d)" % [str(BankAudit.KIND_TEXT[kind]),
			int((res.counts as Dictionary).get(kind, 0))])
	var thin := 0
	for c in res.coverage:
		if not bool(c.gen) and int(c.static) < BankAudit.MIN_PER_TOPIC_GRADE:
			thin += 1
	_check(thin == 0, "setiap topik×kelas tanpa pembuat soal punya >= %d soal" % BankAudit.MIN_PER_TOPIC_GRADE)
	var lvl := {}
	for q in raw:
		lvl[int(q.get("difficulty", 1))] = true
	_check(lvl.has(1) and lvl.has(2) and lvl.has(3), "bank memakai tingkat kesulitan 1, 2, dan 3")

	# Setiap jenis GALAT terdeteksi pada soal rusak buatan.
	var base: Dictionary = {}
	for q in raw:
		if str(q.type) == "mc" and str(q.topic) == "sila_pancasila" and int(q.grade) == 1:
			base = q.duplicate(true)
			break
	_check(not base.is_empty(), "soal contoh untuk uji pemeriksa tersedia")
	var bad := {
		"data_tidak_lengkap": {"subject": ""},
		"struktur": {"answer": 9},
		"topik_tidak_dikenal": {"topic": "astrologi"},
		"mapel_tidak_cocok": {"subject": "matematika"},
		"kelas_di_luar_topik": {"topic": "tata_surya", "subject": "ipa"},
		"kesulitan_tidak_sah": {"difficulty": 5},
		"pilihan_kembar": {"options": ["apel", " apel  ", "jeruk", "mangga"], "answer": 2},
		"kunci_salah": {"topic": "berhitung", "subject": "matematika", "q": "7 + 5 = …", "options": ["13", "12", "11", "14"], "answer": 0},
	}
	for kind in bad:
		var q := base.duplicate(true)
		q.merge(bad[kind], true)
		q.id = "uji-" + kind
		var r := BankAudit.audit([q], d)
		_check(_audit_has(r, kind, q.id), "pemeriksa mendeteksi galat: " + str(BankAudit.KIND_TEXT[kind]))
	var twin := base.duplicate(true)
	var r2 := BankAudit.audit([base, twin], d)
	_check(_audit_has(r2, "id_kembar", str(base.id)), "pemeriksa mendeteksi galat: ID soal kembar")

	# Setiap jenis PERINGATAN pedagogis terdeteksi.
	var good := base.duplicate(true)
	good.id = "uji-baik"
	good.competency = "menyebutkan jumlah sila Pancasila"
	good.hint = "Hitung lambang di perisai Garuda."
	good.explain = "Pancasila punya lima sila, masing-masing punya lambang."
	var clean := BankAudit.check_question(good, d)
	_check(clean.is_empty(), "soal lengkap & baik tidak diberi temuan " + str(clean))
	var warn := {
		"tanpa_kompetensi": {"competency": ""},
		"petunjuk_kosong": {"hint": ""},
		"penjelasan_minim": {"explain": "Benar."},
		"kalimat_panjang": {"q": "Pada suatu pagi yang cerah di desa yang sangat ramai itu ada berapa banyak sila yang ada pada Pancasila kita?"},
		"kalimat_negatif": {"q": "Manakah yang bukan lambang sila Pancasila?"},
		"petunjuk_panjang": {"options": ["bintang emas bersinar terang", "rantai", "padi", "kapas"], "answer": 0},
		"pilihan_semua": {"options": ["bintang", "rantai", "padi", "semua benar"], "answer": 0},
	}
	for kind in warn:
		var q := good.duplicate(true)
		q.merge(warn[kind], true)
		q.id = "uji-" + kind
		_check(_audit_has(BankAudit.audit([q], d), kind, q.id), "pemeriksa memperingatkan: " + str(BankAudit.KIND_TEXT[kind]))
	var copy := good.duplicate(true)
	copy.id = "uji-salinan"
	_check(_audit_has(BankAudit.audit([good, copy], d), "soal_kembar", "uji-salinan"), "pemeriksa memperingatkan: isi soal kembar")
	_check(_audit_has(BankAudit.audit([good], d), "cakupan_tipis", "sila_pancasila/1"), "pemeriksa memperingatkan: cakupan topik×kelas tipis")
	var tfs: Array = []
	var flat: Array = []
	for i in 10:
		var t := good.duplicate(true)
		t.id = "uji-bs-%d" % i
		t.type = "tf"
		t.erase("options")
		t.answer = true
		t.q = "Pernyataan benar nomor %d." % i
		tfs.append(t)
		var f := good.duplicate(true)
		f.id = "uji-datar-%d" % i
		f.q = "Soal mudah nomor %d?" % i
		flat.append(f)
	_check(_audit_has(BankAudit.audit(tfs, d), "benar_salah_timpang", "pancasila"), "pemeriksa memperingatkan: jawaban Benar/Salah tidak seimbang")
	_check(_audit_has(BankAudit.audit(flat, d), "kesulitan_datar", "pancasila"), "pemeriksa memperingatkan: kesulitan datar")

	# Kunci hitungan dihitung sendiri (bilangan ribuan, negatif, isian kosong, bagi tidak bulat).
	var cases := {"12 + 7 = …": "19", "1.250 + 750 = …": "2000", "15.000 − 2.500 = …": "12500", "6 × 7 = …": "42",
		"45 : 9 = …": "5", "-5 + (-3) = …": "-8", "-4 − (-6) = …": "2", "5 + ___ = 12": "7", "20 − ___ = 8": "12",
		"___ × 4 = 20": "5", "___ : 3 = 6": "18", "7 : 2 = …": "", "Pukul 07.00 ditambah 2 jam menjadi pukul …": "",
		"1/2 = …/6": ""}
	var arith_ok := true
	for text in cases:
		var got := BankAudit.arithmetic_key({"type": "mc", "q": text})
		if got != cases[text]:
			arith_ok = false
			print("    hitungan salah: ", text, " -> ", got, " seharusnya ", cases[text])
	_check(arith_ok, "kunci hitungan dihitung benar untuk %d bentuk soal" % cases.size())

	# Soal buatan pembuat soal juga lolos pemeriksa, dan kuncinya cocok dengan hitungan pemeriksa.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var gen: Array = []
	for id in d.topics:
		var gens: Dictionary = d.topics[id].get("gen", {})
		for g in gens:
			for spec in gens[g]:
				for i in 20:
					var q := SdGen.make(str(spec), str(id), int(g), rng)
					if not q.is_empty():
						q.subject = str(d.topics[id].region)
						gen.append(q)
	var gr := BankAudit.audit(gen, d)
	var gen_err: Array = (gr.errors as Array).filter(func(it): return str(it.kind) != "id_kembar")
	for it in gen_err.slice(0, 5):
		print("    galat soal buatan: %s %s %s" % [it.kind, it.id, it.msg])
	_check(gen_err.is_empty(), "%d soal buatan: 0 galat pemeriksa" % gen.size())
	_check(int(gr.arithmetic) >= 300, "kunci %d soal hitungan buatan dicek ulang oleh pemeriksa" % int(gr.arithmetic))


# --- Setiap tipe soal di setiap mode --------------------------------------------------------------------------

func _question_tests() -> void:
	print("== Tipe soal x mode")
	var d := SdData.new()
	d.load_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var samples := {}
	for q in d.questions:
		if not samples.has(q.type):
			samples[q.type] = q
	for spec in ["sort:1:20", "pattern:3", "count:1:10"]:
		var g := SdGen.make(spec, "berhitung" if spec != "pattern:3" else "logika", 1 if spec != "pattern:3" else 3, rng)
		if not samples.has(g.type):
			samples[g.type] = g
	_check(samples.size() == 11, "contoh untuk 11 tipe soal (%s)" % str(samples.keys()))
	var holder := Control.new()
	root.add_child(holder)
	for t in samples:
		for mode in ["latihan", "petualangan", "kuis"]:
			for right in [true, false]:
				var qv: VBoxContainer = SdQuestion.new()
				holder.add_child(qv)
				qv.setup(samples[t], mode, rng, d.doc.type_names, null)
				var hidden: bool = not qv._fb.visible and not qv._next.visible
				var got := []
				qv.finished.connect(func(r: Dictionary) -> void: got.append(r))
				if not right:
					_answer(qv, false)
					if mode == "latihan" and not qv._done:
						_answer(qv, true)
				else:
					_answer(qv, true)
				if not got.is_empty():
					pass
				elif qv._next.visible:
					qv._emit_finish()
				await process_frame
				var ok := not got.is_empty()
				var res: Dictionary = got[0] if ok else {}
				var label := "%s / %s / %s" % [t, mode, "benar" if right else "salah dulu"]
				_check(hidden, label + ": jawaban & penjelasan belum tampil sebelum menjawab")
				_check(ok, label + ": selesai")
				if ok:
					_check(bool(res.first_try) == right, label + ": percobaan pertama = %s" % str(right))
					if right:
						_check(bool(res.correct), label + ": dinilai benar")
					_check(str(res.explain) != "", label + ": ada penjelasan")
				qv.queue_free()
	# Petunjuk berfungsi di setiap tipe (latihan) dan tidak ada di kuis.
	for t in samples:
		var qv: VBoxContainer = SdQuestion.new()
		holder.add_child(qv)
		qv.setup(samples[t], "latihan", rng, d.doc.type_names, null)
		qv._hint()
		_check(qv._fb.visible or qv._done, "petunjuk %s menampilkan bantuan" % t)
		qv.queue_free()
	var qk: VBoxContainer = SdQuestion.new()
	holder.add_child(qk)
	qk.setup(samples["mc"], "kuis", rng, d.doc.type_names, null)
	_check(qk._hint_btn == null, "mode kuis tanpa petunjuk")
	holder.queue_free()
	await process_frame


## Jawab soal pada tampilan qv. right=false: buat satu kesalahan.
func _answer(qv, right: bool) -> void:
	var t := str(qv.q.type)
	match t:
		"mc", "logic", "fill", "pick_image", "tf", "count":
			if right:
				qv._choose(qv._answer)
			else:
				for i in qv._options.size():
					if i != qv._answer and not qv._opt_buttons[i].disabled:
						qv._choose(i)
						return
		"order_letters", "order_words", "sort_numbers":
			qv._reset_order()
			var seq: Array = qv._target.duplicate()
			if not right:
				var tmp = seq[0]
				seq[0] = seq[seq.size() - 1]
				seq[seq.size() - 1] = tmp
				if seq == qv._target:
					seq.reverse()
			for x in seq:
				if qv._done:
					return
				qv._place(qv._pool.find(x))
		"match":
			var pairs: Array = qv.q.pairs
			if not right:
				qv._pick_left(0)
				qv._pick_right(qv._right_vals.find(str(pairs[1][1])))
				if qv._done:
					return
			for i in pairs.size():
				if qv._done:
					return
				if not qv._left_btns[i].disabled:
					qv._pick_left(i)
					qv._pick_right(qv._right_vals.find(str(pairs[i][1])))
		"classify":
			var first := true
			while not qv._done:
				var want := int(qv._items[qv._item_i][1])
				qv._put((want + 1) % (qv.q.bins as Array).size() if (first and not right) else want)
				first = false



# --- 3.x Dunia Enam Pulau: engine -----------------------------------------------------------------------------

const SaveEngine := preload("res://games/education_sd/scripts/engine/save_engine.gd")
const WorldEngine := preload("res://games/education_sd/scripts/engine/world_engine.gd")
const NpcEngine := preload("res://games/education_sd/scripts/engine/npc_engine.gd")
const LearningEngine := preload("res://games/education_sd/scripts/engine/learning_engine.gd")
const QuestEngine := preload("res://games/education_sd/scripts/engine/quest_engine.gd")
const RewardEngine := preload("res://games/education_sd/scripts/engine/reward_engine.gd")
const BattleEngine := preload("res://games/education_sd/scripts/engine/battle_engine.gd")
const MODEL_DIR := "res://assets/models/"


func _prof(grade: int, bosses: Dictionary = {}) -> Dictionary:
	var d := SaveEngine.default_data()
	d.profile.name = "Uji"
	d.profile.grade = grade
	d.world.bosses = bosses
	return d


func _v2_sample() -> Dictionary:
	var v2 := SdProgress.default_data()
	v2.player.name = "Budi"
	v2.player.grade = 3
	v2.player.avatar.outfit = "warna_hijau"
	v2.player.avatar.hat = "topi_pita"
	v2.coins = 77
	v2.xp = 450
	(v2.owned as Array).append("warna_hijau")
	v2.settings.hero = "perempuan"
	v2.settings.gfx = "hemat"
	v2.settings.music = false
	v2.totals.answered = 12
	v2.totals.correct = 9
	(v2.history as Array).append({"at": "2026-11-14 10:00", "subject": "IPA", "mode": "kuis", "correct": 4, "total": 5})
	(v2.cards as Array).append("penjumlahan")
	v2.world.chests["k3/matematika"] = true
	return v2


func _v3_engine_tests() -> void:
	print("== 3.x Data enam pulau")
	var w := WorldEngine.new()
	_check(w.load_data(), "islands.json termuat tanpa galat %s" % str(w.errors))
	_check(w.islands.size() == 6, "ada 6 pulau")
	var grades_ok := true
	var models_ok := true
	for i in w.islands.size():
		if int(w.islands[i].grade) != i + 1 or int(w.islands[i].number) != i + 1:
			grades_ok = false
		if not ResourceLoader.exists(MODEL_DIR + str(w.islands[i].boss.model) + ".glb"):
			models_ok = false
			print("    model bos tidak ada: " + str(w.islands[i].boss.model))
	_check(grades_ok, "pulau 1–6 berurutan = kelas 1–6")
	_check(models_ok, "model keenam bos sudah ada di APK (tanpa aset baru)")
	_check(w.islands.all(func(i): return bool(i.available)), "keenam pulau tersedia (Tahap 8)")
	_check(w.validate({"id": "x"}) != "", "pulau tanpa kolom wajib ditolak")

	print("== 3.x Aturan buka & pindah pulau")
	var p1 := _prof(1)
	_check(w.status("pulau1", p1) == "open" and w.status("pulau2", p1) == "locked", "kelas 1: Pulau 1 terbuka, Pulau 2 terkunci")
	_check(w.travel(p1, "pulau2") != "" and str(p1.world.island) == "pulau1", "tidak bisa berlayar ke pulau yang belum ada")
	for isl in w.islands:
		isl.available = true
	_check(w.status("pulau2", p1) == "locked" and w.lock_reason("pulau2", p1).contains("Raja Goblin Kecil"), "Pulau 2 terkunci sampai Raja Goblin Kecil kalah")
	var pb := _prof(1, {"pulau1": true})
	_check(w.status("pulau2", pb) == "open" and w.status("pulau3", pb) == "locked", "bos Pulau 1 kalah -> Pulau 2 terbuka, Pulau 3 belum")
	var p4 := _prof(4)
	_check(w.status("pulau3", p4) == "open" and w.status("pulau5", p4) == "locked", "kelas 4: pulau kelas 1–4 terbuka, kelas 5 terkunci")
	_check(w.start_island(p4) == "pulau4" and w.start_island(_prof(1)) == "pulau1", "pulau awal mengikuti kelas")
	_check(w.travel(p4, "pulau2") == "" and str(p4.world.island) == "pulau2" and int(p4.world.sailed) == 1 and p4.world.visited.has("pulau2"),
		"berlayar ke pulau terbuka: posisi, jumlah pelayaran, dan kunjungan dicatat")
	_check(w.travel(p4, "pulau2") == "" and int(p4.world.sailed) == 1, "masuk pulau yang sama tidak dihitung berlayar")
	_check(w.travel(p4, "pulau6") != "" and str(p4.world.island) == "pulau2", "pulau terkunci menolak tanpa mengubah posisi")
	w.load_data()
	_check(w.start_island(_prof(4)) == "pulau4" and w.start_island(_prof(6)) == "pulau6", "kelas 4/6 mulai di pulau kelasnya")

	print("== 3.x Save Engine skema 3 + migrasi")
	var d0 := SaveEngine.upgrade({})
	_check(int(d0.schema) == 3 and not SaveEngine.has_profile(d0) and str(d0.world.island) == "pulau1", "data kosong -> skema 3 bawaan, tanpa profil")
	var v2 := _v2_sample()
	var lv2 := SdProgress.level(v2)
	var m := SaveEngine.upgrade(v2.duplicate(true))
	_check(str(m.profile.name) == "Budi" and int(m.profile.grade) == 3 and str(m.profile.hero) == "perempuan", "2.x -> 3: nama, kelas, pahlawan terbawa")
	_check(str(m.profile.outfit) == "warna_hijau" and str(m.profile.hat) == "topi_pita" and (m.rpg.owned as Array).has("warna_hijau"), "kostum & koleksi terbawa")
	_check(int(m.rpg.coins) == 77 and int(m.rpg.xp) == 450 and SaveEngine.level(m) == lv2, "koin, XP, dan level tidak berubah")
	_check(int(m.learning.totals.answered) == 12 and (m.learning.history as Array).size() == 1 and (m.learning.cards as Array).has("penjumlahan"),
		"catatan belajar (statistik, riwayat, kartu) terbawa")
	_check(str(m.settings.gfx) == "hemat" and not bool(m.settings.music), "pengaturan terbawa")
	_check(int(m.migrated_from) == 2 and bool(m.legacy.world_v2.chests.get("k3/matematika", false)), "dunia lama disimpan di legacy")
	var again := SaveEngine.upgrade(m.duplicate(true))
	_check(again == m, "upgrade data skema 3 tidak mengubah isi")
	var rt: Dictionary = SaveEngine.upgrade(JSON.parse_string(JSON.stringify(m)))
	_check(typeof(rt.rpg.coins) == TYPE_INT and int(rt.rpg.coins) == 77 and typeof(rt.profile.grade) == TYPE_INT, "simpan-muat JSON: angka tetap bulat")
	var chain := SaveEngine.migrations()
	var v1 := {"levels": {"matematika/k12": {"best": 80, "attempts": 2}}, "history": [], "last_answers": []}
	var via: Dictionary = (chain[2] as Callable).call((chain[1] as Callable).call(v1))
	_check(int(SaveEngine.ensure(via).schema) == 3 and int(via.rpg.coins) == 20, "rantai migrasi 1 -> 2 -> 3 (koin usaha lama tetap)")
	var bad: Dictionary = SaveEngine.upgrade({"profile": {"name": "Nama Yang Sangat Panjang Sekali", "grade": 9, "hero": "naga"}, "rpg": {"coins": -5}, "settings": {"gfx": "ultra"}})
	_check(int(bad.profile.grade) == 6 and str(bad.profile.hero) == "laki" and int(bad.rpg.coins) == 0 and str(bad.settings.gfx) == "seimbang"
		and str(bad.profile.name).length() <= 16, "data aneh dirapikan (kelas, pahlawan, koin, grafis, nama)")


func _v3_npc_tests() -> void:
	print("== 3.x NPC Engine (tata letak Pulau 1)")
	var n := NpcEngine.new()
	_check(n.load_layout("island1.json"), "island1.json termuat tanpa galat %s" % str(n.errors))
	_check(n.npcs.size() == 9 and n.places.size() == 8, "9 penduduk (termasuk pedagang), 8 tempat")
	_check(not n.load_layout("tidak_ada.json") and n.load_layout("island1.json"), "tata letak yang tidak ada ditolak")
	var d := _prof(1)
	d.profile.name = "Sari"
	var t1: Dictionary = n.talk(d, "pulau1", "pak_lurah")
	_check(t1.first and (t1.lines as Array).size() == 3 and str(t1.lines[0]).contains("Sari"), "perkenalan pertama: 3 kalimat, nama pemain diisi")
	var t2: Dictionary = n.talk(d, "pulau1", "pak_lurah")
	_check(not t2.first and str(t2.lines[0]) != str(t1.lines[0]) and int(d.world.met["pulau1/pak_lurah"]) == 2, "bicara lagi: kalimat lain, pertemuan dihitung")
	_check(n.talk(d, "pulau1", "tidak_ada").is_empty(), "penduduk tak dikenal: tidak ada dialog")
	_check(n.place_at(0, 72) == "dermaga" and n.place_at(0, 42) == "desa" and n.place_at(-38, -38) == "hutan" and n.place_at(60, 10) == "",
		"tempat dikenali dari posisi")
	_check(n.place_at(0, -21) == "sungai" and n.place_at(0, 5) == "akademi", "Sungai Jernih & Akademi Tunas dikenali")
	_check(n.discover(d, "pulau1", "hutan") and not n.discover(d, "pulau1", "hutan") and n.found_count(d, "pulau1") == 1, "penemuan tempat hanya sekali")
	_check(not n.discover(d, "pulau1", "tidak_ada"), "tempat tak dikenal tidak dicatat")
	var models_ok := true
	for id in n.npcs:
		if not ResourceLoader.exists(MODEL_DIR + str(n.npcs[id].model) + ".glb"):
			models_ok = false
	_check(models_ok, "model semua penduduk ada di APK")


func _v3_learning_tests() -> void:
	print("== 3.x Learning Engine (materi, latihan, penilaian, adaptasi)")
	var d := SdData.new()
	d.load_data()
	var le := LearningEngine.new()
	_check(le.setup(d), "materi singkat ada untuk semua %d topik %s" % [d.topics.size(), str(le.errors)])
	_check(LearningEngine.band(1) == "1-2" and LearningEngine.band(4) == "3-4" and LearningEngine.band(6) == "5-6", "pita kelas 1-2 / 3-4 / 5-6")
	_check(str(le.lesson("penjumlahan", 1).title) != str(le.lesson("penjumlahan", 5).title), "materi penjumlahan kelas 1 berbeda dengan kelas 5")
	_check(not le.lesson("sinonim_antonim", 3).is_empty(), "pita yang tidak ada memakai materi terdekat")
	var p := _prof(2)
	var rooms_ok := true
	for g in range(1, 7):
		for r in ["matematika", "bahasa", "ipas_alam", "ipas_sosial", "pancasila", "seni", "olahraga"]:
			if le.topics(r, g, p).is_empty():
				rooms_ok = false
	_check(rooms_ok, "7 ruang kelas punya materi di setiap kelas 1–6")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ses: Dictionary = le.start(p, "penjumlahan", 2, rng)
	_check((ses.questions as Array).size() == 5 and str(ses.mode) == "normal", "latihan 5 soal, mode normal")
	var coins0 := int(p.rpg.coins)
	for q in ses.questions:
		LearningEngine.answer(p, ses, q, true, true)
	var res: Dictionary = LearningEngine.finish(p, ses, "Matematika")
	_check(int(res.stars) == 3 and int(res.bonus) == 25 and bool(res.first), "semua benar: 3 bintang, bonus pertama kali")
	_check(int(p.rpg.coins) == coins0 + 15 + 25 and int(p.rpg.xp) > 0 and int(p.learning.totals.answered) == 5, "koin, XP, dan total jawaban dicatat")
	_check(str(LearningEngine.status(p, 2, "penjumlahan")) == "belajar", "5 jawaban belum cukup untuk dinyatakan menguasai")
	var ses2: Dictionary = le.start(p, "penjumlahan", 2, rng)
	for q in ses2.questions:
		LearningEngine.answer(p, ses2, q, false, false)
	var res2: Dictionary = LearningEngine.finish(p, ses2, "Matematika")
	_check(int(res2.stars) == 1 and int(p.academy["2/penjumlahan"].stars) == 3 and int(p.academy["2/penjumlahan"].sessions) == 2,
		"latihan buruk: 1 bintang, bintang terbaik tetap 3")
	_check(int(res2.coins) > 0 and str(res2.message).contains("berusaha"), "usaha tetap dihargai, pesan positif")
	# Setelah 5 benar kesulitan naik ke level 2; 5 salah di level 2 belum cukup (butuh 6) untuk mengubah apa pun.
	var ses3: Dictionary = le.start(p, "penjumlahan", 2, rng)
	_check(str(ses3.mode) == "normal" and int(ses3.level) == 2 and int(ses3.q_grade) == 2, "5 salah setelah naik level: belum ada perubahan (data belum cukup)")
	LearningEngine.answer(p, ses3, ses3.questions[0], false, false)
	var ses4: Dictionary = le.start(p, "penjumlahan", 2, rng)
	_check(str(ses4.mode) == "normal" and int(ses4.level) == 1 and int(ses4.q_grade) == 2, "6 salah di level 2: kesulitan turun ke level 1, KELAS tetap")
	for i in 8:
		LearningEngine.answer(p, ses4, ses4.questions[i % (ses4.questions as Array).size()], false, false)
	var ses5: Dictionary = le.start(p, "penjumlahan", 2, rng)
	_check(str(ses5.mode) == "mudah" and int(ses5.q_grade) == 1 and LearningEngine.adapt_note(ses5) != "", "8 salah di level 1: soal dari kelas lebih rendah + catatan")
	var p2 := _prof(2)
	var st := LearningEngine.stats(p2, 2, "pengurangan")
	st.recent = [1, 1, 1, 1, 1, 1, 1, 1, 1]
	st.recent_own = st.recent.duplicate()  # jawaban atas soal kelas 2 sendiri
	st.correct = 9
	_check(LearningEngine.status(p2, 2, "pengurangan") == "kuasai", "banyak jawaban benar terakhir: dikuasai")
	var adv: Dictionary = le.start(p2, "pengurangan", 2, rng)
	_check(str(adv.mode) == "normal" and int(adv.level) == 2, "sudah mahir: kesulitan naik bertahap ke level 2 (tidak melompat)")
	st.recent = [0, 0, 1, 0, 0, 0, 0]
	st.recent_own = st.recent.duplicate()
	_check(LearningEngine.status(p2, 2, "pengurangan") == "perlu_latihan", "sering salah: perlu latihan lagi")
	var sm: Dictionary = le.room_summary(p, 2)
	_check(sm.size() == 7 and int(sm.matematika.stars) >= 3, "ringkasan rapor per ruang")
	var ex: Dictionary = le.exam_start(p, "pancasila", 3, rng)
	_check((ex.questions as Array).size() >= 8, "ujian Pancasila kelas 3: %d soal campuran" % (ex.questions as Array).size())
	var coins_e := int(p.rpg.coins)
	for q in ex.questions:
		LearningEngine.exam_answer(p, ex, q, true)
	var er: Dictionary = le.exam_finish(p, ex)
	_check(int(er.score) == 100 and bool(er.passed) and int(er.bonus) == 50 and int(p.rpg.coins) > coins_e + 49, "semua benar: nilai 100, lulus, bonus pertama 50 koin")
	var ex2: Dictionary = le.exam_start(p, "pancasila", 3, rng)
	for q in ex2.questions:
		LearningEngine.exam_answer(p, ex2, q, false)
	var er2: Dictionary = le.exam_finish(p, ex2)
	_check(int(er2.score) == 0 and not bool(er2.passed) and int(er2.bonus) == 0 and not (er2.practice as Array).is_empty(), "gagal: tanpa bonus, saran materi untuk dilatih")
	var rec: Dictionary = LearningEngine.exam_rec(p, 3, "pancasila")
	_check(bool(rec.passed) and int(rec.best) == 100 and int(rec.attempts) == 2, "status lulus & nilai terbaik tetap tersimpan")
	var rep: Dictionary = le.report(p)
	_check((rep.rooms as Array).size() == 7 and str(rep.summary).contains(str(p.profile.name)), "laporan belajar: 7 mata pelajaran + ringkasan")
	var mat: Dictionary = (rep.rooms as Array).filter(func(x): return str(x.id) == "matematika")[0]
	_check(bool(mat.enough) and int(mat.answered) >= 10, "laporan hanya menilai bila jawaban cukup (Matematika %d jawaban)" % int(mat.answered))
	var p0 := _prof(1)
	_check(str(le.report(p0).summary).contains("baru mulai"), "laporan anak baru: bahasa positif, tanpa kesimpulan")


# --- Prioritas 3: perbaikan bug Learning Engine ----------------------------------------------------------------

func _p3_bugfix_tests() -> void:
	print("== Prioritas 3: perbaikan bug Learning Engine")
	var d := SdData.new()
	d.load_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	# 1) Petunjuk: kolom hint kosong ("" dari data lama) tidak boleh menghasilkan pesan kosong.
	var holder := Control.new()
	root.add_child(holder)
	var tfq := {"id": "uji-tf", "type": "tf", "q": "Ikan hidup di air.", "answer": true, "explain": "Benar.", "hint": "", "topic": "hewan", "grade": 1}
	var qv: VBoxContainer = SdQuestion.new()
	holder.add_child(qv)
	qv.setup(tfq, "latihan", rng, d.doc.type_names, null)
	qv._hint()
	_check(qv._fb.visible and str(qv._fb.text).strip_edges() != "", "petunjuk B/S dengan hint \"\" memakai kalimat bawaan (\"%s\")" % str(qv._fb.text))
	var mcq := {"id": "uji-mc", "type": "mc", "q": "2 + 2 = …", "options": ["4", "3", "5", "6"], "answer": 0, "explain": "2 + 2 = 4.",
		"hint": "", "topic": "penjumlahan", "grade": 1}
	var qm: VBoxContainer = SdQuestion.new()
	holder.add_child(qm)
	qm.setup(mcq, "latihan", rng, d.doc.type_names, null)
	for i in 3:
		qm._hint()
	_check(str(qm._fb.text).strip_edges() != "", "petunjuk ganda ke-3 (pengecoh habis) tidak kosong (\"%s\")" % str(qm._fb.text))
	var hq := tfq.duplicate()
	hq.hint = "Ingat tempat tinggal ikan."
	var qh: VBoxContainer = SdQuestion.new()
	holder.add_child(qh)
	qh.setup(hq, "latihan", rng, d.doc.type_names, null)
	qh._hint()
	_check(str(qh._fb.text) == "Ingat tempat tinggal ikan.", "petunjuk teks dari data tetap dipakai bila ada")
	holder.queue_free()
	await process_frame

	# 2) Mode "tantang": soal yang belum dilihat tetap didahulukan, baru soal sulit.
	var pool: Array = d.by_topic_grade.get("bangun_datar/4", [])
	var hard: Array = []
	var easy: Array = []
	for q in pool:
		(hard if int(q.difficulty) >= 2 else easy).append(str(q.id))
	_check(hard.size() >= 2 and easy.size() >= 2, "contoh uji: bangun datar kelas 4 punya soal mudah (%d) & sulit (%d)" % [easy.size(), hard.size()])
	var unseen_ok := true
	var hard_ok := true
	for s in 25:
		rng.seed = 100 + s
		var pk := d.pick("bangun_datar", 4, easy.size(), {"at_level": [1, 1, 1, 1, 1, 1, 1, 1], "level": 3, "seen": hard}, rng)
		if str(pk.mode) != "tantang":
			unseen_ok = false
		for q in pk.questions:
			if hard.has(str(q.id)):
				unseen_ok = false
		var pk2 := d.pick("bangun_datar", 4, 1, {"at_level": [1, 1, 1, 1, 1, 1, 1, 1], "level": 3, "seen": []}, rng)
		if int(pk2.questions[0].difficulty) < 2:
			hard_ok = false
	_check(unseen_ok, "mode tantang: soal yang sudah dilihat tidak didahulukan (25 acakan)")
	_check(hard_ok, "mode tantang tanpa riwayat: soal sulit tetap didahulukan (25 acakan)")

	# 3) Penguasaan hanya dari soal kelas itu sendiri.
	var le := LearningEngine.new()
	le.setup(d)
	var p := _prof(3)
	var ses: Dictionary = le.start(p, "bangun_datar", 3, rng)
	var low := {"id": "uji-k2", "grade": 2, "points": 10}
	for i in 10:
		LearningEngine.answer(p, ses, low, true, true)
	var st: Dictionary = p.learning.topics["3/bangun_datar"]
	_check((st.recent as Array).size() == 10 and (st.recent_own as Array).is_empty(), "10 jawaban soal kelas 2 dicatat untuk adaptasi, bukan penguasaan kelas 3")
	_check(LearningEngine.status(p, 3, "bangun_datar") != "kuasai", "materi kelas 3 TIDAK dinyatakan dikuasai dari soal kelas 2 (status: %s)" % LearningEngine.status(p, 3, "bangun_datar"))
	_check(str(le.start(p, "bangun_datar", 3, rng).mode) != "mudah", "setelah lancar di soal lebih mudah, adaptasi tidak macet di mode mudah")
	var own := {"id": "uji-k3", "grade": 3, "points": 10}
	for i in 8:
		LearningEngine.answer(p, ses, own, true, true)
	_check(LearningEngine.status(p, 3, "bangun_datar") == "kuasai", "8 jawaban benar soal kelas 3 sendiri: dikuasai")
	# Data lama (tanpa recent_own): riwayat lama tetap dihitung, tidak tiba-tiba hilang.
	var p2 := _prof(2)
	var st2 := LearningEngine.stats(p2, 2, "pengurangan")
	st2.erase("recent_own")
	st2.recent = [1, 1, 1, 1, 1, 1, 1, 1, 1]
	st2.correct = 9
	_check(LearningEngine.status(p2, 2, "pengurangan") == "kuasai", "save lama tanpa recent_own: status lama dipertahankan")
	var ses2: Dictionary = le.start(p2, "pengurangan", 2, rng)
	LearningEngine.answer(p2, ses2, {"id": "uji-k2b", "grade": 2, "points": 10}, false, false)
	_check((st2.recent_own as Array).size() == 10 and LearningEngine.status(p2, 2, "pengurangan") == "kuasai",
		"jawaban pertama setelah pembaruan: riwayat lama ikut disalin, satu salah tidak menghapus penguasaan")
	var js: Dictionary = JSON.parse_string(JSON.stringify(p))
	_check((js.learning.topics["3/bangun_datar"].recent_own as Array).size() == 8, "recent_own ikut tersimpan lewat JSON")

# --- Prioritas 4: sistem pembelajaran adaptif -------------------------------------------------------------------

func _dec(at_level: Array, level := 1, mode := "normal") -> Dictionary:
	return Adaptive.decide({"at_level": at_level, "level": level, "mode": mode})


## Simulasi anak dengan peluang benar `pc` selama `n` latihan pada satu topik. Mengembalikan jejak keputusan.
func _simulate(d, pc: float, n: int, seed: int, topic := "bangun_datar", grade := 3) -> Dictionary:
	var le := LearningEngine.new()
	le.setup(d)
	var p := _prof(grade)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var levels: Array = []
	var modes: Array = []
	var answers := 0
	var first_drop := -1
	for s in n:
		var ses: Dictionary = le.start(p, topic, grade, rng)
		levels.append(int(ses.level))
		modes.append(str(ses.mode))
		if str(ses.mode) == "mudah" and first_drop < 0:
			first_drop = answers
		for q in ses.questions:
			var ok := rng.randf() < pc
			LearningEngine.answer(p, ses, q, ok, ok, "" if ok else "x")
			answers += 1
	return {"levels": levels, "modes": modes, "first_drop": first_drop, "p": p}


func _p4_adaptive_tests() -> void:
	print("== Prioritas 4: sistem adaptif (scripts/engine/adaptive.gd)")
	var d := SdData.new()
	d.load_data()
	# Aturan satu per satu, termasuk batas jumlah data.
	_check(str(_dec([0, 0, 0, 0]).reason).contains("belum cukup") and int(_dec([0, 0, 0, 0]).level) == 1, "B: 4 jawaban salah -> data belum cukup, tidak berubah")
	_check(str(_dec([0, 0, 0, 0, 0, 0, 0]).mode) == "normal", "F: 7 jawaban salah di level 1 -> BELUM turun kelas")
	_check(str(_dec([0, 0, 0, 0, 0, 0, 0, 0]).mode) == "mudah", "F: 8 jawaban, < 40% benar di level 1 -> soal kelas lebih rendah")
	_check(str(_dec([1, 0, 1, 0, 1, 0, 0, 1]).mode) == "normal", "F: 4 dari 8 benar (50%) -> tidak turun kelas")
	_check(int(_dec([1, 1, 1, 1, 0]).level) == 2, "D: 4 dari 5 benar -> naik ke level 2")
	_check(int(_dec([1, 1, 1, 0, 0]).level) == 1, "D: 3 dari 5 benar -> tetap level 1")
	_check(int(_dec([1, 1, 1, 1, 1], 2).level) == 3 and int(_dec([1, 1, 1, 1, 1], 3).level) == 3, "D: naik satu langkah, maksimal level 3")
	_check(str(_dec([1, 1, 1, 1, 1, 1, 1, 1], 3).mode) == "tantang" and str(_dec([1, 1, 1, 1, 1, 1, 0], 3).mode) != "tantang",
		"C: tantang butuh level 3 dan >= 8 jawaban lancar")
	_check(int(_dec([0, 0, 0, 0, 0], 2).level) == 2 and int(_dec([0, 0, 1, 0, 0, 0], 2).level) == 1, "E: turun level butuh >= 6 jawaban; kelas tetap")
	_check(str(_dec([0, 1, 0, 0, 0, 1], 2).mode) == "normal", "E: di level 2 tidak pernah langsung turun kelas")
	_check(str(_dec([1, 1, 0], 1, "mudah").mode) == "mudah" and str(_dec([1, 1, 0, 1, 0], 1, "mudah").mode) == "normal",
		"A: keluar dari mode mudah setelah >= 5 jawaban dan 3 dari 5 benar")
	var one_wrong := true
	for k in 12:
		var h: Array = []
		for i in 12:
			h.append(0 if i == k else 1)
		for lv in [1, 2, 3]:
			if str(_dec(h.slice(0, maxi(1, k + 1)), lv).mode) == "mudah":
				one_wrong = false
	_check(one_wrong, "satu jawaban salah tidak pernah menurunkan kelas (semua posisi, semua level)")
	var st := {"at_level": [1, 1, 1, 1, 1], "level": 1, "mode": "normal"}
	var dec := Adaptive.decide(st)
	Adaptive.apply(st, dec)
	_check(int(st.level) == 2 and (st.at_level as Array).is_empty(), "apply: level berubah -> riwayat level dikosongkan (tidak naik dua kali dari data sama)")
	var st2 := {"at_level": [1, 0], "level": 2, "mode": "normal"}
	Adaptive.apply(st2, Adaptive.decide(st2))
	_check((st2.at_level as Array).size() == 2, "apply: tanpa perubahan -> riwayat dipertahankan")
	var legacy := {"correct": 6, "wrong": 0, "recent": [1, 1, 1, 1, 1, 1], "seen": []}
	Adaptive.ensure(legacy)
	_check(int(legacy.level) == 1 and (legacy.at_level as Array).size() == 6 and str(legacy.mode) == "normal", "save lama: field adaptif dilengkapi, riwayat lama dipakai")

	# Simulasi anak (bank soal sungguhan, 10 latihan x 5 soal, 12 acakan per tipe anak).
	var steps_ok := true
	var strong_top := 0
	var weak_drop := 0
	var drop_late := true
	var mid_own := 0
	var mid_total := 0
	for s in 12:
		var strong := _simulate(d, 0.95, 10, 500 + s)
		for i in range(1, (strong.levels as Array).size()):
			if absi(int(strong.levels[i]) - int(strong.levels[i - 1])) > 1:
				steps_ok = false
		if (strong.levels as Array).has(3):
			strong_top += 1
		var weak := _simulate(d, 0.15, 10, 700 + s)
		if int(weak.first_drop) >= 0:
			weak_drop += 1
			if int(weak.first_drop) < Adaptive.DROP_N:
				drop_late = false
		var mid := _simulate(d, 0.7, 10, 900 + s)
		for m in mid.modes:
			mid_total += 1
			if str(m) != "mudah":
				mid_own += 1
	_check(steps_ok, "simulasi anak pintar: level naik bertahap 1 -> 2 -> 3, tidak melompat")
	_check(strong_top >= 10, "simulasi anak pintar (95%% benar): mencapai level 3 di %d/12 acakan" % strong_top)
	_check(weak_drop >= 10 and drop_late, "simulasi anak kesulitan (15%% benar): dibantu soal lebih mudah di %d/12 acakan, tidak pernah sebelum 8 jawaban" % weak_drop)
	_check(mid_own >= int(0.85 * mid_total), "simulasi anak rata-rata (70%% benar): %d dari %d latihan tetap di soal kelasnya" % [mid_own, mid_total])

	# Jenis kesalahan.
	var add := {"type": "mc", "q": "27 + 15 = …"}
	var sub := {"type": "mc", "q": "42 − 15 = …"}
	var kinds := {
		"lupa menyimpan (27+15 -> 32)": [Adaptive.error_kind(add, "32"), "nilai_tempat"],
		"operasi tertukar (27+15 -> 12)": [Adaptive.error_kind(add, "12"), "operasi_tertukar"],
		"meleset sedikit (27+15 -> 43)": [Adaptive.error_kind(add, "43"), "hitung_meleset"],
		"hitung lain (27+15 -> 50)": [Adaptive.error_kind(add, "50"), "hitung_lain"],
		"salah meminjam (42-15 -> 33)": [Adaptive.error_kind(sub, "33"), "nilai_tempat"],
		"operasi tertukar (42-15 -> 57)": [Adaptive.error_kind(sub, "57"), "operasi_tertukar"],
		"benar/salah": [Adaptive.error_kind({"type": "tf", "q": "x"}, "Benar"), "benar_salah"],
		"soal fakta": [Adaptive.error_kind({"type": "mc", "q": "Ibu kota Jawa Barat adalah …"}, "Semarang"), "konsep"],
	}
	for label in kinds:
		_check(str(kinds[label][0]) == str(kinds[label][1]), "jenis kesalahan: %s = %s" % [label, str(kinds[label][0])])
	var ms := {}
	Adaptive.record(ms, add, false, "32")
	_check(Adaptive.main_error(ms) == "" and Adaptive.tip(ms) == "", "satu kesalahan belum cukup untuk menyebut jenis kesalahan")
	Adaptive.record(ms, {"type": "mc", "q": "38 + 45 = …"}, false, "73")
	_check(Adaptive.main_error(ms) == "nilai_tempat" and Adaptive.tip(ms).contains("menyimpan"), "dua kesalahan sejenis: saran tentang nilai tempat")
	Adaptive.record(ms, add, true, "")
	_check((ms.mistakes as Array).size() == 2 and (ms.at_level as Array).size() == 3, "jawaban benar tidak dicatat sebagai kesalahan")

	# Pengecoh diagnostik pembuat soal.
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var carry_n := 0
	var carry_hit := 0
	var borrow_n := 0
	var borrow_hit := 0
	for i in 200:
		var qa := SdGen.make("add:10:99", "penjumlahan", 2, rng)
		var parts: PackedStringArray = str(qa.q).replace(" = …", "").split(" + ")
		var x := int(parts[0])
		var y := int(parts[1])
		if SdGen._carry(x, y) != 0:
			carry_n += 1
			if (qa.options as Array).has(str(x + y - SdGen._carry(x, y))):
				carry_hit += 1
		var qs := SdGen.make("sub:10:99", "pengurangan", 2, rng)
		var ps: PackedStringArray = str(qs.q).replace(" = …", "").split(" − ")
		var a := int(ps[0])
		var b := int(ps[1])
		if SdGen._borrow(a, b) != 0:
			borrow_n += 1
			if (qs.options as Array).has(str(a - b + SdGen._borrow(a, b))):
				borrow_hit += 1
	_check(carry_n > 20 and carry_hit == carry_n, "penjumlahan bersimpan: pengecoh \"lupa menyimpan\" selalu ada (%d/%d)" % [carry_hit, carry_n])
	_check(borrow_n > 20 and borrow_hit == borrow_n, "pengurangan meminjam: pengecoh \"salah meminjam\" selalu ada (%d/%d)" % [borrow_hit, borrow_n])

	# Jawaban salah pertama dikirim tampilan soal.
	var holder := Control.new()
	root.add_child(holder)
	var qv: VBoxContainer = SdQuestion.new()
	holder.add_child(qv)
	qv.setup({"id": "uji-fw", "type": "mc", "q": "27 + 15 = …", "options": ["42", "32", "12", "43"], "answer": 0, "explain": "27 + 15 = 42.",
		"topic": "penjumlahan", "grade": 2}, "latihan", rng, d.doc.type_names, null)
	var got: Array = []
	qv.finished.connect(func(r: Dictionary) -> void: got.append(r))
	qv._choose((qv._options as Array).find("32"))
	qv._choose((qv._options as Array).find("43"))
	qv._choose(qv._answer)
	qv._emit_finish()
	_check(got.size() == 1 and str(got[0].first_wrong) == "32" and bool(got[0].correct) and not bool(got[0].first_try),
		"tampilan soal mengirim jawaban salah PERTAMA (%s)" % (str(got[0].first_wrong) if got.size() > 0 else "-"))
	holder.queue_free()
	await process_frame

	# Pengayaan: mode tantang memuat tepat satu soal kelas berikutnya, tidak dihitung untuk penguasaan kelas ini.
	var le := LearningEngine.new()
	le.setup(d)
	var p := _prof(3)
	var stt := LearningEngine.stats(p, 3, "bangun_datar")
	stt.at_level = [1, 1, 1, 1, 1, 1, 1, 1]
	stt.level = 3
	var ses: Dictionary = le.start(p, "bangun_datar", 3, rng)
	var enr: Array = (ses.questions as Array).filter(func(q): return bool(q.get("pengayaan", false)))
	_check(str(ses.mode) == "tantang" and enr.size() == 1 and int(enr[0].grade) == 4, "tantang: 1 soal pengayaan kelas 4 dalam latihan kelas 3")
	_check(LearningEngine.adapt_note(ses).contains("pengayaan"), "catatan untuk anak menyebut soal pengayaan")
	var own_before := (stt.recent_own as Array).size()
	LearningEngine.answer(p, ses, enr[0], true, true)
	_check((stt.recent_own as Array).size() == own_before, "jawaban soal pengayaan tidak dihitung untuk penguasaan kelas 3")

	# Latihan penguatan: topik yang perlu dilatih lebih sering dipilih Jurus Ilmu.
	var pt := _prof(3)
	var ts: Array = le.topics("matematika", 3, pt)
	for t in ts:
		var sx := LearningEngine.stats(pt, 3, str(t.id))
		sx.correct = 10
		sx.recent = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
		sx.recent_own = sx.recent.duplicate()
	var weak_id := str(ts[0].id)
	var sw := LearningEngine.stats(pt, 3, weak_id)
	sw.recent_own = [0, 0, 1, 0, 0, 0, 0, 0]
	_check(LearningEngine.status(pt, 3, weak_id) == "perlu_latihan", "contoh: satu topik perlu latihan, lainnya dikuasai")
	var hits := 0
	for i in 600:
		if le.pick_topic(pt, "matematika", 3, rng) == weak_id:
			hits += 1
	var fair := 600.0 / ts.size()
	_check(hits > 2.0 * fair, "Jurus Ilmu memilih topik lemah lebih sering (%d kali vs rata-rata %d)" % [hits, int(fair)])
	_check(le.pick_topic(pt, "tidak_ada", 3, rng) == "", "ruang tanpa topik: tidak memilih apa pun")

func _v3_quest_tests() -> void:
	print("== 3.x Quest Engine (data misi Pulau 1)")
	var q := QuestEngine.new()
	_check(q.load_quests("quests1.json"), "quests1.json termuat %s" % str(q.errors))
	_check(q.quests.size() == 11 and q.quests.filter(func(x): return str(x.kind) == "main").size() == 6, "6 misi utama + 5 sampingan")
	var n := NpcEngine.new()
	n.load_layout("island1.json")
	var giver_ok := true
	for x in q.quests:
		if str(x.get("giver", "")) != "" and not n.npcs.has(str(x.giver)):
			giver_ok = false
	_check(giver_ok, "setiap pemberi misi ada di pulau")
	var d := _prof(1)
	_check(q.offer_for(d, "pak_lurah").get("id", "") == "petualang_baru" and q.offer_for(d, "pak_budi").is_empty(), "misi berurutan: Pak Budi menunggu Petualang Baru")
	q.start(d, "petualang_baru")
	q.event(d, "talk", "pak_lurah")
	_check(q.state(d, "petualang_baru") == "active", "belum belajar: bicara dengan Pak Lurah belum menyelesaikan misi")
	q.event(d, "learn")
	var notes := q.event(d, "talk", "pak_lurah")
	_check(q.state(d, "petualang_baru") == "done" and notes.filter(func(x): return str(x.kind) == "done").size() == 1 and int(d.rpg.coins) == 30,
		"belajar lalu lapor: misi selesai + hadiah")
	q.start(d, "bibit_hilang")
	_check(q.pickups(d, true).size() == 5, "5 bibit tampil saat misinya aktif")
	var pks := q.pickups(d, true)
	q.event(d, "pickup", str(pks[0].uid))
	q.event(d, "pickup", str(pks[0].uid))
	_check(q.count_item(d, "bibit") == 1 and q.pickups(d, true).size() == 4, "bibit yang sama tidak bisa dipungut dua kali")
	for e in pks:
		q.event(d, "pickup", str(e.uid))
	_check(q.step(d, "bibit_hilang").get("type", "") == "challenge" and q.objective(d).text.contains("menghitung"), "terkumpul -> tujuan berikutnya")
	var sd := SdData.new()
	sd.load_data()
	_check(q.challenge_topic("hitung_bibit", sd, 1) == "berhitung" and q.challenge_topic("hitung_bibit", sd, 4) == "penjumlahan"
		and q.challenge_topic("batu_ajaib", sd, 4) == "tumbuhan", "topik tantangan mengikuti kelas anak")
	q.event(d, "challenge", "hitung_bibit")
	_check(q.state(d, "bibit_hilang") == "done" and q.count_item(d, "sekop") == 1, "tantangan lulus: misi selesai")
	_check(q.marks(d).get("nenek_ijah", "") == "!", "tanda misi baru di Nenek Ijah")
	q.event(d, "world", "", {"found": 8, "places": 8, "met": 1, "npcs": 8})
	_check(q.state(d, "jelajah_pulau") == "done" and q.state(d, "kenal_warga") == "active", "misi jelajah otomatis selesai bila semua tempat sudah ditemukan")
	q.event(d, "world", "", {"found": 8, "places": 8, "met": 8, "npcs": 8})
	_check(q.state(d, "kenal_warga") == "done", "kenal semua warga: misi selesai")
	q.start(d, "kerang_pantai")
	for e in q.pickups(d, true).slice(0, 3):
		q.event(d, "pickup", str(e.uid))
	_check(q.event(d, "talk", "pak_udin").is_empty() and q.state(d, "kerang_pantai") == "active", "kerang belum cukup: belum bisa diantar")


func _v3_reward_tests() -> void:
	print("== 3.x Reward Engine (level, kartu, prestasi, toko, kostum)")
	var d := SdData.new()
	d.load_data()
	var rw := RewardEngine.new()
	_check(rw.setup(d), "rpg.json & toko termuat %s" % str(rw.errors))
	var p := _prof(2)
	var s1: Dictionary = rw.stats(p)
	_check(int(s1.level) == 1 and int(s1.hp) == 48 and int(s1.atk) == 8, "level 1: HP 48, Serang 8")
	_check(rw.level_check(p).is_empty() and int(p.rpg.level_seen) == 1, "level awal dicatat tanpa hadiah")
	p.rpg.xp = 320
	var lv: Array = rw.level_check(p)
	_check(lv.size() == 2 and int(lv[1].level) == 3 and int(p.rpg.coins) == 50, "XP 320: naik ke level 2 lalu 3, hadiah 20 + 30 koin")
	_check(int(rw.stats(p).hp) > int(s1.hp) and int(rw.stats(p).atk) > int(s1.atk), "naik level menambah HP & serang")
	_check(rw.on_session(p, "penjumlahan", {"stars": 2, "status": "belajar"}).is_empty(), "2 bintang: belum dapat kartu")
	_check(rw.on_session(p, "penjumlahan", {"stars": 3}).size() == 1 and rw.on_session(p, "penjumlahan", {"stars": 3}).is_empty(),
		"3 bintang: kartu sekali saja")
	_check(rw.cards_total() == d.topics.size(), "%d kartu pengetahuan (satu per topik)" % rw.cards_total())
	var a: Array = rw.check_achievements(p, {"main_quests": 0})
	_check(a.is_empty(), "belum ada prestasi")
	p.quests = {"x": {"state": "done"}}
	var a2: Array = rw.check_achievements(p, {"main_quests": 1})
	_check(a2.size() == 1 and str(a2[0].id) == "misi_pertama" and rw.check_achievements(p).is_empty(), "prestasi didapat sekali")
	p.rpg.coins = 100
	_check(rw.buy(p, "pak_darto", "topi_pita") == "" and int(p.rpg.coins) == 60 and (p.rpg.owned as Array).has("topi_pita"), "beli topi pita")
	_check(rw.buy(p, "pak_darto", "topi_pita") != "", "tidak bisa membeli kostum yang sama dua kali")
	_check(rw.buy(p, "pak_darto", "warna_emas") != "" and int(p.rpg.coins) == 60, "koin kurang: ditolak, koin tetap")
	_check(rw.buy(p, "pak_darto", "tidak_ada") != "", "barang yang tidak dijual ditolak")
	_check(rw.buy(p, "pak_darto", "kue") == "" and rw.buy(p, "pak_darto", "kue") == "" and int(p.rpg.items.kue) == 2, "barang pakai bisa dibeli berkali-kali")
	_check(rw.equip(p, "topi_pita") and str(p.profile.hat) == "topi_pita", "pakai topi")
	_check(rw.equip(p, "topi_pita") and str(p.profile.hat) == "", "pakai lagi = lepas topi")
	_check(not rw.equip(p, "warna_emas"), "kostum yang belum dimiliki tidak bisa dipakai")
	_check(rw.equip(p, "warna_biru") and str(p.profile.outfit) == "warna_biru", "ganti baju")


func _v3_battle_tests() -> void:
	print("== 3.x Battle Engine (bergiliran, perisai bos, ramah anak, keseimbangan)")
	var mv = JSON.parse_string(FileAccess.get_file_as_string("res://games/education_sd/data/monsters1.json"))
	_check(typeof(mv) == TYPE_DICTIONARY and (mv.monsters as Dictionary).size() == 4 and (mv.spawns as Array).size() == 8, "monsters1.json: 4 jenis, 8 tempat muncul")
	var models_ok := true
	for id in mv.monsters:
		if not ResourceLoader.exists(MODEL_DIR + str(mv.monsters[id].model) + ".glb"):
			models_ok = false
	_check(models_ok, "model semua musuh ada di APK")
	var st1 := {"hp": 48, "atk": 8, "def": 3, "ilmu": 12}
	var b := BattleEngine.new()
	b.start(st1, "goblin_nakal", mv.monsters.goblin_nakal, 0, 3)
	var o: Dictionary = b.act("serang")
	_check(int(o.enemy_dmg) >= 5 and int(o.player_dmg) >= 1 and b.turn == 1, "serang: musuh kena, musuh membalas")
	var hp0 := int(b.enemy.hp)
	var o2: Dictionary = b.act("ilmu", {"correct": false, "first_try": false})
	_check(int(o2.enemy_dmg) == 0 and int(b.enemy.hp) == hp0 and str(o2.text[0]).contains("Tidak apa-apa"), "jurus salah: gagal saja, pesan lembut")
	var o3: Dictionary = b.act("ilmu", {"correct": true, "first_try": true})
	_check(int(o3.enemy_dmg) >= 15, "jurus ilmu sempurna lebih kuat dari serangan fisik (%d)" % int(o3.enemy_dmg))
	var bb := BattleEngine.new()
	bb.start(st1, "goblin_nakal", mv.monsters.goblin_nakal, 0, 5)
	var g1: Dictionary = bb.act("bertahan")
	var bb2 := BattleEngine.new()
	bb2.start(st1, "goblin_nakal", mv.monsters.goblin_nakal, 0, 5)
	var g2: Dictionary = bb2.act("ilmu", {"correct": false})
	_check(int(g1.player_dmg) < int(g2.player_dmg) and int(g1.healed) > 0, "bertahan: kerusakan berkurang + pulih sedikit")
	var bk := BattleEngine.new()
	bk.start(st1, "tikus_sawah", mv.monsters.tikus_sawah, 0, 1)
	bk.act("kabur")
	_check(bk.over and bk.fled and bk.rewards().is_empty(), "kabur dari musuh biasa")
	var bs := BattleEngine.new()
	bs.start({"hp": 64, "atk": 12, "def": 5, "ilmu": 16}, "raja_goblin", mv.monsters.raja_goblin, 0, 2)
	bs.act("kabur")
	_check(not bs.over, "tidak bisa kabur dari bos")
	_check(bs.shield_up() and bs.phys_base() < 4.0, "Perisai Mahkota menahan serangan fisik")
	bs.act("ilmu", {"correct": true, "first_try": true})
	_check(not bs.shield_up(), "jurus ilmu benar menghancurkan perisai")
	_check(bs.heavy_next, "bos memberi aba-aba sebelum pukulan berat (giliran ke-3)")
	var bh := int(bs.player.hp)
	var oh: Dictionary = bs.act("bertahan")
	_check(not bs.heavy_next and int(oh.player_dmg) <= int(round((10 - 5 * 0.5) * 1.6 * 0.5 * 1.15)) + 1 and int(bs.player.hp) <= bh + 4, "bertahan saat pukulan berat")
	var be := BattleEngine.new()
	be.start(st1, "goblin_nakal", mv.monsters.goblin_nakal, 3, 1)
	_check(int(be.enemy.atk) < int(mv.monsters.goblin_nakal.atk), "kalah berkali-kali: serangan musuh dikurangi (adaptif)")
	var bl := BattleEngine.new()
	bl.start({"hp": 5, "atk": 8, "def": 3, "ilmu": 12}, "goblin_nakal", mv.monsters.goblin_nakal, 0, 1)
	bl.act("bertahan")
	bl.act("bertahan")
	_check(bl.over and not bl.won and bl.rewards().is_empty(), "HP habis: kalah, tanpa hadiah (tanpa hukuman)")
	# Simulasi keseimbangan: anak level 3, Jurus Ilmu benar 70% (setengahnya sejak percobaan pertama), Bertahan saat aba-aba.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var wins := 0
	var turns := 0
	var N := 200
	for i in N:
		var sim := BattleEngine.new()
		sim.start({"hp": 64, "atk": 12, "def": 5, "ilmu": 16}, "raja_goblin", mv.monsters.raja_goblin, 0, 1000 + i)
		while not sim.over and sim.turn < 60:
			if sim.heavy_next:
				sim.act("bertahan")
			elif int(sim.player.hp) < 22 and rng.randf() < 0.5:
				sim.act("barang", {"use": "heal", "power": 30})
			else:
				var ok := rng.randf() < 0.7
				sim.act("ilmu", {"correct": ok, "first_try": ok and rng.randf() < 0.5})
		if sim.won:
			wins += 1
		turns += sim.turn
	var rate := float(wins) / N
	print("    simulasi bos: menang %d%%, rata-rata %.1f giliran" % [int(rate * 100), float(turns) / N])
	_check(rate >= 0.6 and rate < 1.0, "Raja Goblin menantang tapi bisa dikalahkan anak level 3 (%d%% menang)" % int(rate * 100))
	var wins2 := 0
	for i in 100:
		var sim2 := BattleEngine.new()
		sim2.start({"hp": 48, "atk": 8, "def": 3, "ilmu": 12}, "goblin_nakal", mv.monsters.goblin_nakal, 0, 2000 + i)
		while not sim2.over:
			sim2.act("serang")
		if sim2.won:
			wins2 += 1
	_check(wins2 >= 90, "goblin nakal bisa dikalahkan anak level 1 hanya dengan serangan (%d%%)" % wins2)


# --- 3.x Dunia Enam Pulau: aplikasi utuh --------------------------------------------------------------------------

func _open() -> Node:
	change_scene_to_file(SCENE)
	for i in 40:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == SCENE and current_scene.screen != "":
			break
	SdUI.guard_until_ms = 0
	return current_scene


func _btn(root: Node, name: String) -> Button:
	if root == null:
		return null
	return root.find_child(name, true, false) as Button


func _press(root: Node, name: String) -> bool:
	SdUI.guard_until_ms = 0
	var b := _btn(root, name)
	if b == null:
		return false
	b.pressed.emit()
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _clear_save() -> void:
	for f in ["save.json", "save.json.bak"]:
		DirAccess.remove_absolute(SaveManager.dir_for("education_sd") + "/" + f)


func _v3_app_tests() -> void:
	print("== 3.x Menu utama & profil petualang (pemain baru)")
	_clear_save()
	var app := await _open()
	app.foes_calm = 99999.0
	_check(app != null and app.screen == "title", "game dibuka di menu utama, bukan menu soal")
	_check(_btn(app, "Start") != null and _btn(app, "Continue") == null, "pemain baru: tombol Mulai Petualangan")
	_check(str(app.get("game_id")) == "education_sd" and app.worlds.islands.size() == 6 and app.data.questions.size() >= 200,
		"enam pulau + bank soal (%d soal) termuat" % app.data.questions.size())
	_press(app, "Start")
	await _frames(2)
	_check(app.screen == "profile", "Mulai -> profil petualang")
	var ps: Node = app.current
	_check(ps.preview != null and ps.preview.rig != null and ps.preview.rig.is_glb(), "pratinjau 3D pahlawan (GLB) tampil")
	ps.name_edit.text = "   "
	ps.submit()
	await _frames(1)
	_check(app.screen == "profile" and not SaveEngine.has_profile(app.p), "nama kosong ditolak")
	ps.name_edit.text = "Ana"
	_press(ps, "Grade1")
	_press(ps, "Hero_perempuan")
	_press(ps, "Outfit_warna_biru")
	_check(not ps.preview.rig.is_glb() or ps.preview.rig.long_hair, "pratinjau berganti ke pahlawan perempuan")
	_press(ps, "Save")
	await _frames(2)
	_check(app.screen == "map" and app.modal_open(), "profil disimpan -> peta + cerita pembuka (Kabut Lupa)")
	_check(str(app.p.profile.name) == "Ana" and int(app.p.profile.grade) == 1 and str(app.p.profile.hero) == "perempuan"
		and str(app.p.profile.outfit) == "warna_biru" and str(app.p.world.island) == "pulau1", "profil tercatat, mulai di Pulau 1")
	_check(bool(app.p.seen_intro.story), "cerita pembuka hanya sekali")
	app.go_back()
	await _frames(1)
	_check(app.screen == "map" and not app.modal_open(), "tombol kembali menutup cerita dulu")

	print("== 3.x Peta enam pulau")
	var m: Node = app.current
	await _frames(2)
	var c2: Vector2 = m.island_center(app.worlds.island("pulau2"))
	_check(m.island_at(c2) == "pulau2", "ketuk pulau di peta mengenali pulaunya")
	m.select("pulau2")
	_check(not _btn(m, "Sail").visible, "Pulau 2 terkunci (bos Pulau 1 belum kalah): tidak ada tombol berlayar")
	_check(not m.sail("pulau2"), "berlayar ke pulau terkunci ditolak")
	m.select("pulau1")
	_check(_btn(m, "Sail").visible and _btn(m, "Sail").text == "Masuk pulau", "Pulau 1: Masuk pulau")
	_press(m, "Sail")
	await _frames(3)
	_check(app.screen == "island" and app.world != null and app.hud != null, "masuk dunia 3D Pulau 1")

	print("== 3.x Pulau 1: dunia 3D dari tata letak")
	var w: Node3D = app.world
	_check(w.player != null and w.player.rig.is_glb() and w.player.rig.long_hair, "pahlawan perempuan (GLB) di pulau")
	for nm in ["Sea", "Beach", "Ground", "Dock", "Boat", "River", "Bridge", "Farm", "Fort", "Boulder", "Hill_bukit_akademi"]:
		_check(w.find_child(nm, true, false) != null, "ada " + nm)
	var objs := 0
	for ch in w.get_children():
		if str(ch.name).begins_with("Obj"):
			objs += 1
	_check(objs >= 20, "bangunan & benda GLB desa, akademi, gua terpasang (%d)" % objs)
	_check(w.tree_count() >= 40, "hutan + pohon tersebar (MultiMesh, %d pohon)" % w.tree_count())
	_check(w.npcs.size() == 9 and app.npc.npcs.size() == 9, "9 penduduk dengan model berangka")
	var npc_glb := true
	for e in w.npcs:
		if e.rig == null or not e.rig.is_glb():
			npc_glb = false
	_check(npc_glb, "semua penduduk memakai model GLB dari APK")
	_check(w.find_child("Boss", true, false) != null and w.find_child("Guard", true, false) != null, "Raja Goblin Kecil di benteng + goblin penjaga di gerbang")
	_check(absf(w.ground_y(0, 5) - 2.2) < 0.01 and w.ground_y(0, 40) == 0.0 and w.ground_y(0, 23) > 0.0 and w.ground_y(0, 23) < 2.2,
		"bukit akademi: puncak 2,2 m, lereng landai, desa datar")
	await _frames(10)
	var start: Vector3 = w.player.global_position
	_check(absf(start.y) < 0.6, "pemain berdiri di dermaga (y=%.2f)" % start.y)
	w.player.move_input = Vector2(0, 1)
	await _frames(40)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.z < start.z - 1.5, "joystick maju: berjalan dari dermaga ke desa")
	await _frames(15)
	_check(app.p.world.found.has("pulau1/dermaga") and w.place == "dermaga", "masuk wilayah Dermaga: tempat ditemukan otomatis")

	print("== 3.x Pulau 1: mendaki bukit, jembatan, sungai, batas pulau")
	w.player.place(Vector3(0, 0.3, 30), 0.0)
	w.player.move_input = Vector2(0, 1)
	await _frames(240)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.y > 1.8 and w.player.global_position.z < 20.0, "berjalan mendaki lereng sampai puncak bukit akademi (y=%.2f)" % w.player.global_position.y)
	await _frames(15)
	_check(app.p.world.found.has("pulau1/akademi"), "Akademi Tunas ditemukan")
	w.player.place(Vector3(0, 0.3, -15), 0.0)
	w.player.move_input = Vector2(0, 1)
	await _frames(240)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.z < -27.0 and w.player.global_position.y > -0.3, "menyeberang lewat jembatan (z=%.1f)" % w.player.global_position.z)
	w.player.place(Vector3(20, 0.3, -14), 0.0)
	w.player.move_input = Vector2(0, 1)
	await _frames(120)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.z > -17.6, "tepi sungai tidak bisa diterobos (z=%.1f)" % w.player.global_position.z)
	w.player.place(Vector3(120, 0.3, 0), 0.0)
	await _frames(4)
	_check(Vector2(w.player.global_position.x, w.player.global_position.z).length() <= w.radius + 4.5, "batas pulau: tidak bisa masuk laut")
	var fortz: float = w.layout.fort.pos[1] + w.layout.fort.half
	w.player.place(Vector3(0, 0.3, fortz + 4.0), 0.0)
	w.player.move_input = Vector2(0, 1)
	await _frames(90)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.z > fortz, "gerbang benteng menahan pemain (masih terkunci)")

	print("== 3.x Pulau 1: penduduk & dialog")
	var lurah: Node3D = w.npc_node("pak_lurah")
	w.player.place(lurah.position + Vector3(1.2, 0.3, 0), 0.0)
	await _frames(3)
	_check(w.focus_kind() == "npc", "dekat Pak Lurah: tombol AKSI menyala")
	app.hud.trigger_action()
	await _frames(2)
	_check(app.hud.dialog_open() and str(app.hud._dialog_title.text).begins_with("Pak Lurah Darmo") and str(app.hud._dialog_text.text).contains("Ana"),
		"dialog perkenalan menyebut nama pemain")
	_check(w.npcs[0].talking, "Pak Lurah berhenti dan menghadap pemain")
	var pages := 1
	while true:
		var nb: Button = null
		for b in app.hud.find_children("*", "Button", true, false):
			if (b as Button).text == "Lanjut" and b.is_visible_in_tree():
				nb = b
		if nb == null:
			break
		SdUI.guard_until_ms = 0
		nb.pressed.emit()
		await _frames(1)
		pages += 1
	_check(pages == 5 and str(app.hud._dialog_text.text).contains("Akademi Tunas") and _hud_btn(app, "Terima misi") != null,
		"perkenalan 3 halaman + tawaran misi 2 halaman, tombol Terima misi")
	_check(w.npcs[0].talking, "penduduk tetap menghadap pemain di antara halaman")
	app.hud.close_dialog()
	await _frames(30)
	_check(not w.npcs[0].talking, "selesai bicara: penduduk berjalan lagi")
	_check(app.p.world.met.has("pulau1/pak_lurah"), "pertemuan dicatat")
	app.hud.trigger_action()
	await _frames(2)
	_check(str(app.hud._dialog_text.text).contains("maukah kamu membantu"), "bicara lagi: langsung tawaran misi (tidak mengulang perkenalan)")
	await _next_pages(app)
	_press_hud(app, "Terima misi")
	await _frames(2)
	_check(app.quest.state(app.p, "petualang_baru") == "active", "misi Petualang Baru diterima")
	_check(str(app.hud._hint.text).contains("Misi: Petualang Baru"), "tujuan misi tampil di layar")
	_check(app.hud.compass_target != null, "panah kompas menunjuk tujuan misi")
	var moved := false
	var e_d: Dictionary = {}
	for e in w.npcs:
		if str(e.id) == "dodi":
			e_d = e
	var d0: Vector3 = e_d.node.position
	w.player.place(d0 + Vector3(6, 0.3, 0), 0.0)
	for i in 16:
		await _wait(0.5)
		if (e_d.node as Node3D).position.distance_to(d0) > 0.3:
			moved = true
			break
	_check(moved, "Dodi berjalan-jalan di sekitar rumahnya")
	w.player.place(w.spot_pos("gate") + Vector3(0, 0.3, 0.5), 0.0)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(1)
	_check(app.hud.dialog_open() and str(app.hud._dialog_text.text).contains("Raja Goblin"), "gerbang benteng: pesan terkunci")
	app.hud.close_dialog()
	w.player.place(w.spot_pos("boulder") + Vector3(0, 0.3, 0), 0.0)
	await _frames(3)
	_check(w.focus_kind() == "boulder", "batu besar di pintu gua bisa diperiksa")
	app.hud.close_dialog()
	app.show_explore()
	await _frames(1)
	_check(str(app.hud._dialog_text.text).contains("TEMPAT (") and str(app.hud._dialog_text.text).contains("Pak Lurah Darmo"), "MISI: catatan jelajah tempat & penduduk")
	app.hud.close_dialog()
	print("== 3.x Akademi Tunas: masuk, ruang kelas, materi, latihan, hasil")
	w.player.place(w.spot_pos("academy") + Vector3(0, 0.3, 0.6), PI)
	await _frames(3)
	_check(w.focus_kind() == "academy", "di depan pintu akademi: AKSI menyala")
	app.hud.trigger_action()
	await _frames(3)
	_check(app.screen == "academy" and app.world != null and app.world.teachers.size() == 7, "masuk Akademi Tunas: 7 ruang kelas dengan guru")
	var aw: Node3D = app.world
	var tglb := true
	for id in aw.teachers:
		var tr = aw.teachers[id].get_meta("rig")
		if tr == null or not tr.is_glb():
			tglb = false
	_check(tglb, "guru memakai model GLB")
	aw.player.move_input = Vector2(0, 1)
	await _frames(30)
	aw.player.move_input = Vector2.ZERO
	_check(aw.player.global_position.z < aw.spawn_point().z - 1.0 and absf(aw.player.global_position.y) < 0.5, "berjalan di dalam aula")
	aw.player.place(aw.spot_pos("teacher", "seni") + Vector3(0, 0.2, 0), 0.0)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(2)
	_check(app.lesson != null and app.lesson.find_children("Topic_*", "Button", true, false).size() >= 1, "Sanggar Seni terbuka dengan materi")
	app.close_class()
	await _frames(1)
	aw.player.place(aw.spot_pos("teacher", "matematika") + Vector3(0, 0.2, 0), 0.0)
	await _frames(3)
	_check(aw.focus_kind() == "teacher", "dekat Bu Guru Sinta: AKSI menyala")
	app.hud.trigger_action()
	await _frames(2)
	var lv: Control = app.lesson
	_check(lv != null and lv.phase == "kelas" and not app.hud.visible and aw.player.frozen, "ruang kelas terbuka, HUD disembunyikan, pemain berhenti")
	var tbtns := lv.find_children("Topic_*", "Button", true, false)
	_check(tbtns.size() >= 3, "daftar materi kelas 1 Matematika (%d materi)" % tbtns.size())
	var tname := str(tbtns[0].name).trim_prefix("Topic_")
	SdUI.guard_until_ms = 0
	tbtns[0].pressed.emit()
	await _frames(1)
	_check(lv.phase == "materi" and _btn(lv, "StartPractice") != null, "materi singkat + tombol Mulai Latihan")
	_press(lv, "StartPractice")
	await _frames(1)
	_check(lv.phase == "latihan" and lv.current_question_view() != null and (lv.session.questions as Array).size() == 5, "latihan 5 soal dimulai")
	var xp0 := int(app.p.rpg.xp)
	var guard := 0
	while lv.phase == "latihan" and guard < 12:
		guard += 1
		var qv = lv.current_question_view()
		_answer(qv, true)
		await _frames(1)
		if lv.phase == "latihan" and lv.current_question_view() == qv:
			qv._emit_finish()
		await _frames(1)
	_check(lv.phase == "hasil" and int(lv.result.stars) == 3, "semua benar: 3 bintang")
	_check(int(app.p.rpg.xp) > xp0 and int(app.p.academy["1/" + tname].stars) == 3 and int(app.p.academy["1/" + tname].sessions) == 1,
		"XP bertambah, bintang & jumlah latihan tercatat")
	_check(str((app.p.learning.history as Array)[0].mode) == "akademi", "riwayat belajar tercatat")
	var sv := SaveManager.load_progress("education_sd", 3)
	_check(sv.data.academy.has("1/" + tname), "hasil latihan tersimpan")
	_press(lv, "Again")
	await _frames(1)
	_check(lv.phase == "latihan", "Ulangi latihan")
	app.go_back()
	await _frames(1)
	_check(lv.phase == "berhenti", "kembali saat latihan: tanya dulu")
	app.go_back()
	await _frames(1)
	_check(lv.phase == "latihan", "batal berhenti: lanjut latihan")
	var qv2 = lv.current_question_view()
	_answer(qv2, false)
	await _frames(1)
	_check(str(qv2._fb.text) != "" and qv2._fb.visible, "salah: umpan balik lembut / pembahasan tampil")
	_press(lv, "Back")
	await _frames(1)
	_press(lv, "StopYes")
	await _frames(1)
	_check(lv.phase == "kelas", "berhenti -> daftar materi")
	_press(lv, "Back")
	await _frames(2)
	_check(app.lesson == null and app.hud.visible and not aw.player.frozen, "ruang kelas ditutup, kembali berjalan di aula")
	aw.player.place(aw.spot_pos("teacher", "matematika") + Vector3(0, 0.2, 0), 0.0)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(2)
	lv = app.lesson
	_press(lv, "Exam")
	await _frames(1)
	_check(lv.phase == "ujian" and lv.current_question_view() != null and str(lv.current_question_view().mode) == "kuis", "Ujian Matematika: soal tanpa petunjuk")
	var eg := 0
	while lv.phase == "ujian" and eg < 14:
		eg += 1
		_answer(lv.current_question_view(), true)
		await _frames(2)
	_check(lv.phase == "ujian_hasil" and int(lv.result.score) == 100 and bool(lv.result.passed), "ujian selesai: nilai 100, lulus")
	_check(bool(app.p.academy["ujian/1/matematika"].passed), "kelulusan ujian tersimpan")
	_press(lv, "ToClass")
	await _frames(1)
	_check(_label_has(lv, "LULUS"), "daftar materi menampilkan status ujian")
	_press(lv, "Back")
	await _frames(2)
	app.show_report()
	await _frames(2)
	_check(app.lesson != null and _label_has(app.lesson, "Laporan Belajar") and _label_has(app.lesson, "Ujian: LULUS"), "Laporan Belajar di akademi (ujian lulus tercatat)")
	_press(app.lesson, "Back")
	await _frames(2)
	aw.player.place(aw.spot_pos("exit") + Vector3(0, 0.2, 0), PI)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(3)
	_check(app.screen == "island" and app.world.player.global_position.distance_to(app.world.spot_pos("academy")) < 4.0,
		"keluar akademi: kembali di depan pintu akademi")
	w = app.world

	print("== 3.x Misi Pulau 1: dimainkan dari awal sampai gerbang benteng")
	var Q = app.quest
	_check(Q.step(app.p, "petualang_baru").get("type", "") == "talk", "latihan di akademi menyelesaikan langkah belajar")
	await _talk_to(app, "pak_lurah")
	_check(Q.state(app.p, "petualang_baru") == "done" and Q.count_item(app.p, "lencana_petualang") == 1, "Petualang Baru selesai: Lencana Petualang")
	_check(str(app.hud._dialog_text.text).contains("Hadiah"), "dialog hadiah misi tampil")
	_check(w.npc_node("pak_budi").get_node_or_null("Mark") != null and str(w.npc_node("pak_budi").get_node("Mark").text) == "!",
		"tanda ! di atas Pak Budi (misi baru)")
	await _talk_to(app, "pak_budi")
	_press_hud(app, "Terima misi")
	await _frames(2)
	_check(Q.state(app.p, "bibit_hilang") == "active" and w.pickups.size() == 5, "Bibit yang Hilang: 5 bibit muncul di dunia")
	_check(app.objective_pos() != null and absf(app.objective_pos().z + 34.0) < 1.0, "kompas menunjuk jalan ke Hutan Kecil")
	await _collect_all(app)
	await _frames(2)
	_check(Q.count_item(app.p, "bibit") == 5 and Q.step(app.p, "bibit_hilang").get("type", "") == "challenge", "5 bibit terkumpul -> langkah menghitung")
	await _talk_to(app, "pak_budi")
	_check(_hud_btn(app, "Mulai tantangan") != null, "Pak Budi menawarkan tantangan menghitung")
	_press_hud(app, "Mulai tantangan")
	await _frames(2)
	_check(app.lesson != null and not app.hud.visible, "tantangan terbuka di atas dunia")
	var tq := int(app.p.learning.totals.answered)
	_check(await _do_challenge(app), "tantangan lulus (semua benar)")
	_check(int(app.p.learning.totals.answered) == tq + 3, "jawaban tantangan ikut tercatat di statistik belajar")
	_check(Q.state(app.p, "bibit_hilang") == "done" and Q.count_item(app.p, "sekop") == 1 and app.hud.visible, "Bibit yang Hilang selesai: Sekop Kecil")
	await _talk_to(app, "nenek_ijah")
	_press_hud(app, "Terima misi")
	await _frames(2)
	await _go_spot(app, "clue", "clue_hutan")
	_check(app.lesson != null, "Batu Bertulis membuka tantangan kata")
	app.go_back()
	await _frames(2)
	_check(app.lesson == null and Q.step(app.p, "keranjang_nenek").get("type", "") == "challenge", "tantangan boleh ditunda (Nanti saja)")
	await _go_spot(app, "clue", "clue_hutan")
	var cv = app.lesson
	_press(cv, "Start")
	await _frames(1)
	var g2 := 0
	while cv.phase == "soal" and g2 < 10:
		g2 += 1
		var qv3 = cv.current_question_view()
		_answer(qv3, false)
		await _frames(1)
		if cv.phase == "soal" and cv.current_question_view() == qv3:
			qv3._emit_finish()
		await _frames(1)
	var failed_ok: bool = cv.phase == "hasil"
	_check(failed_ok and (_btn(cv, "Retry") != null or cv.is_passed()), "gagal tantangan: boleh coba lagi tanpa hukuman")
	if _btn(cv, "Retry") != null:
		_press(cv, "Retry")
		await _frames(1)
		var g3 := 0
		while cv.phase == "soal" and g3 < 10:
			g3 += 1
			var qv4 = cv.current_question_view()
			_answer(qv4, true)
			await _frames(1)
			if cv.phase == "soal" and cv.current_question_view() == qv4:
				qv4._emit_finish()
			await _frames(1)
	_press(cv, "Continue")
	await _frames(2)
	_check(Q.step(app.p, "keranjang_nenek").get("item", "") == "keranjang" and w.pickups.size() == 1, "teka-teki terpecahkan -> keranjang muncul di hutan")
	await _collect_all(app)
	await _talk_to(app, "nenek_ijah")
	_check(Q.state(app.p, "keranjang_nenek") == "done" and Q.count_item(app.p, "keranjang") == 0 and Q.count_item(app.p, "kue") == 3,
		"keranjang dikembalikan, hadiah 3 Kue Manis")
	await _talk_to(app, "dodi")
	_press_hud(app, "Terima misi")
	await _frames(2)
	_check(Q.state(app.p, "pintu_gua") == "active", "Rahasia Gua Goblin dimulai (setelah dua misi selesai)")
	var bz: Vector3 = w.spot_pos("boulder")
	await _go_spot(app, "boulder")
	_check(await _do_challenge(app), "teka-teki batu besar lulus")
	await _frames(3)
	_check(bool(app.p.world.flags.get("gua_terbuka", false)) and w.find_child("Boulder", true, false) == null and w.find_child("BoulderMoved", true, false) != null,
		"batu besar bergeser: pintu gua terbuka")
	_check(w.pickups.size() == 1, "harta goblin muncul di mulut gua")
	await _collect_all(app)
	_check(Q.state(app.p, "pintu_gua") == "done" and Q.count_item(app.p, "kunci_benteng") == 1, "Kunci Benteng ditemukan")
	await _go_spot(app, "gate")
	_check(not w.gate_open() and str(app.hud._dialog_text.text).contains("Kak Laras"), "gerbang: tanya Kak Laras dulu")
	await _talk_to(app, "kak_laras")
	_press_hud(app, "Terima misi")
	await _frames(2)
	await _go_spot(app, "gate")
	await _frames(2)
	_check(w.gate_open() and bool(app.p.world.flags.get("gerbang_terbuka", false)) and Q.state(app.p, "gerbang_benteng") == "done",
		"kunci dipakai: gerbang benteng terbuka")
	_check(Q.count_item(app.p, "kunci_benteng") == 0 and Q.done_count(app.p, "main") == 5, "5 misi utama selesai")
	app.hud.close_dialog()
	var fz: float = w.layout.fort.pos[1] + w.layout.fort.half
	w.player.place(Vector3(0, 0.3, fz + 3.0), 0.0)
	w.player.move_input = Vector2(0, 1)
	await _frames(80)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.z < fz - 1.0, "masuk benteng lewat gerbang yang terbuka")
	_check(Q.state(app.p, "jelajah_pulau") != "" and Q.state(app.p, "kenal_warga") != "", "misi jelajah & kenalan berjalan otomatis (%s, %s)" % [Q.state(app.p, "jelajah_pulau"), Q.state(app.p, "kenal_warga")])
	await _talk_to(app, "pak_udin")
	_press_hud(app, "Terima misi")
	await _frames(2)
	_check(w.pickups.size() == 5, "Kerang Pantai: 5 kerang di pantai")
	await _collect_all(app)
	await _talk_to(app, "pak_udin")
	_check(Q.state(app.p, "kerang_pantai") == "done" and (app.p.rpg.owned as Array).has("warna_hijau"), "kerang diantar: baju hijau terbuka")
	app.show_explore()
	await _frames(1)
	_check(str(app.hud._dialog_text.text).contains("MISI UTAMA (5/6") and str(app.hud._dialog_text.text).contains("✓ Kerang Pantai"), "jurnal misi")
	app.hud.close_dialog()
	print("== 3.x Sistem RPG: tas, status, kostum, toko, koleksi, prestasi, naik level")
	_check(int(app.p.rpg.level_seen) == app.level() and app.level() >= 2, "naik level tercatat selama misi (level %d)" % app.level())
	_check((app.p.rpg.achievements as Dictionary).has("misi_pertama") and (app.p.rpg.achievements as Dictionary).has("penolong_desa"),
		"prestasi Langkah Pertama & Penolong Desa didapat otomatis")
	_check(str(app._chip_lbl.text).begins_with("Lv %d" % app.level()), "level & koin tampil di layar")
	app.show_bag()
	await _frames(2)
	var bag: Control = app.lesson
	_check(bag != null and bag.tab == "Status" and not app.hud.visible, "TAS membuka Tas Petualang (Status)")
	_press(bag, "Tab_Barang")
	await _frames(1)
	_check(_label_has(bag, "Kue Manis ×3"), "tab Barang berisi hadiah misi")
	_press(bag, "Tab_Kostum")
	await _frames(1)
	_check(_btn(bag, "Wear_warna_hijau") != null, "tab Kostum: baju hijau dari misi kerang")
	_press(bag, "Wear_warna_hijau")
	await _frames(2)
	_check(str(app.p.profile.outfit) == "warna_hijau", "baju hijau dipakai")
	_check(app.world.player.rig.shirt.is_equal_approx(Color("#3fae63")), "model pemain di dunia ikut berganti baju")
	_press(bag, "Tab_Koleksi")
	await _frames(1)
	_check((app.p.learning.cards as Array).size() >= 1 and _label_has(bag, "Kartu Pengetahuan: %d" % (app.p.learning.cards as Array).size()),
		"latihan sempurna memberi kartu pengetahuan")
	_press(bag, "Tab_Prestasi")
	await _frames(1)
	_check(_label_has(bag, "Penolong Desa"), "tab Prestasi")
	_press(bag, "Close")
	await _frames(2)
	_check(app.lesson == null and app.hud.visible, "tas ditutup")
	await _talk_to(app, "pak_darto")
	_check(_hud_btn(app, "Buka Toko") != null, "Pak Darto menawarkan toko")
	_press_hud(app, "Buka Toko")
	await _frames(2)
	var shop: Control = app.lesson
	_check(shop != null and shop.mode == "toko" and _btn(shop, "Buy_topi_petualang") != null, "Toko Pak Darto terbuka")
	var c0 := int(app.p.rpg.coins)
	_press(shop, "Buy_topi_petualang")
	await _frames(1)
	_check((app.p.rpg.owned as Array).has("topi_petualang") and int(app.p.rpg.coins) == c0 - 40, "beli Topi Petualang (40 koin)")
	_check(_btn(shop, "Buy_topi_petualang").disabled, "kostum yang sudah dimiliki tidak bisa dibeli lagi")
	_press(shop, "Buy_kue")
	await _frames(1)
	_check(int(app.p.rpg.items.kue) == 4, "beli Kue Manis masuk tas")
	app.p.rpg.coins = 5
	_press(shop, "Buy_warna_emas")
	await _frames(1)
	_check(not (app.p.rpg.owned as Array).has("warna_emas") and int(app.p.rpg.coins) == 5 and _label_has(shop, "belum cukup"), "koin kurang: ditolak dengan pesan ramah")
	_press(shop, "Tab_Kostum")
	await _frames(1)
	_press(shop, "Wear_topi_petualang")
	await _frames(2)
	_check(str(app.p.profile.hat) == "topi_petualang" and str(app.world.player.rig.hat) == "petualang", "topi dipakai langsung dari toko")
	_press(shop, "Close")
	await _frames(2)
	app.save()
	app.show_island("pulau1")
	await _frames(3)
	w = app.world
	_check(w.find_child("Boulder", true, false) == null and w.gate_open() and w.pickups.is_empty(), "masuk ulang: gua & gerbang tetap terbuka, barang tidak muncul lagi")

	print("== 3.x Pertarungan bergiliran: goblin, kalah, kabur, barang, Raja Goblin Kecil")
	app.battle_seed = 11
	_check(Q.state(app.p, "raja_goblin") == "active" and str(Q.objective(app.p).text).contains("Raja Goblin"), "misi Raja Goblin Kecil aktif setelah gerbang terbuka")
	_check(w.foes.size() == 8, "8 musuh berkeliaran (tikus, goblin, kelelawar)")
	var fg: Dictionary = w.foe("goblin_1")
	fg.rest = 0.0
	w.player.place((fg.node as Node3D).position + Vector3(0.6, 0.3, 0), 0.0)
	await _frames(3)
	var bv: Control = app.lesson
	_check(bv != null and bv.monster_id == "goblin_nakal" and not app.hud.visible, "menyentuh goblin: pertarungan dimulai")
	var xp_b := int(app.p.rpg.xp)
	_check(await _battle_win(app), "goblin dikalahkan dengan serangan & jurus ilmu")
	_check(w.foe("goblin_1").is_empty() and app.lesson == null and app.hud.visible, "goblin hilang dari dunia, kembali menjelajah")
	_check(int(app.p.rpg.xp) > xp_b, "menang: XP bertambah")
	app.start_battle("tikus_sawah", "tikus_1")
	await _frames(2)
	bv = app.lesson
	bv.engine.player.hp = 1
	_press(bv, "Act_serang")
	await _frames(2)
	_check(bv.engine.over and not bv.engine.won and _btn(bv, "Done").text == "Bangun di desa", "HP habis: pingsan")
	_press(bv, "Done")
	await _frames(3)
	_check(app.lesson == null and w.player.global_position.distance_to(Vector3(0, 0, 46)) < 3.0, "bangun di desa")
	_check(int(app.p.world.battle_losses.tikus_sawah) == 1 and Q.count_item(app.p, "lencana_petualang") == 1, "kalah tidak menghilangkan barang; kesulitan tikus diturunkan")
	app.start_battle("kelelawar_gua", "kelelawar_1")
	await _frames(2)
	bv = app.lesson
	var kue0 := int(app.p.rpg.items.get("kue", 0))
	bv.engine.player.hp = 10
	_press(bv, "Act_barang")
	await _frames(1)
	_press(bv, "Use_kue")
	await _frames(2)
	_check(int(app.p.rpg.items.get("kue", 0)) == kue0 - 1 and bv.engine.history.any(func(t): return str(t).contains("Kue Manis")), "Kue Manis dipakai dalam pertarungan")
	_press(bv, "Act_kabur")
	await _frames(1)
	_check(bv.engine.fled, "kabur dari kelelawar")
	_press(bv, "Done")
	await _frames(2)
	_check(app.lesson == null and not w.foe("kelelawar_1").is_empty(), "kabur: kelelawar tetap ada")
	app.p.rpg.items["ramuan_ilmu"] = 1
	w.player.place(w.spot_pos("boss") + Vector3(0, 0.3, 0.4), PI)
	await _frames(3)
	_check(w.focus_kind() == "boss", "di depan Raja Goblin Kecil: AKSI menyala")
	app.hud.trigger_action()
	await _frames(1)
	_press_hud(app, "Bertarung!")
	await _frames(2)
	bv = app.lesson
	_check(bv != null and bool(bv.engine.enemy.boss) and _btn(bv, "Act_kabur").disabled, "pertarungan bos dimulai, tidak bisa kabur")
	_check(bv.engine.shield_up(), "Perisai Mahkota aktif")
	var hp_b := int(bv.engine.enemy.hp)
	_press(bv, "Act_serang")
	await _frames(1)
	_check(hp_b - int(bv.engine.enemy.hp) <= 4, "serangan fisik tertahan perisai (%d)" % (hp_b - int(bv.engine.enemy.hp)))
	_press(bv, "Act_barang")
	await _frames(1)
	_press(bv, "Use_ramuan_ilmu")
	await _frames(1)
	_check(float(bv.engine.player.boost) > 1.0, "Ramuan Ilmu menguatkan jurus berikutnya")
	_press(bv, "Act_ilmu")
	await _frames(1)
	var bq = bv.current_question_view()
	_answer(bq, true)
	await _frames(1)
	if bv.current_question_view() == bq:
		bq._emit_finish()
	await _frames(1)
	_check(not bv.engine.shield_up() and int(bv.engine.enemy.hp) < hp_b - 20, "jurus ilmu benar menembus perisai")
	_check(await _battle_win(app), "Raja Goblin Kecil dikalahkan")
	await _frames(2)
	_check(bool(app.p.world.bosses.get("pulau1", false)) and Q.state(app.p, "raja_goblin") == "done" and Q.count_item(app.p, "mahkota_goblin") == 1,
		"bos kalah: misi selesai, Mahkota Goblin, pulau tercatat")
	_check(w.find_child("Boss", true, false) == null and app.modal_open(), "Raja hilang dari singgasana, perayaan pahlawan pulau")
	app.close_modal()
	app.hud.close_dialog()
	app.show_island("pulau1")
	await _frames(3)
	w = app.world
	_check(w.find_child("Boss", true, false) == null and w.foes.filter(func(e): return str(e.monster).begins_with("goblin")).is_empty(),
		"masuk ulang: Raja & goblin sudah pergi dari pulau")

	w.player.place(w.spot_pos("dock") + Vector3(0, 0.2, -0.8), 0.0)
	await _frames(3)
	_check(w.focus_kind() == "dock", "dekat perahu: tombol AKSI menyala")
	app.hud.trigger_action()
	await _frames(1)
	var sail_btn: Button = null
	for b in app.hud.find_children("*", "Button", true, false):
		if (b as Button).text == "Buka Peta Dunia":
			sail_btn = b
	_check(sail_btn != null, "perahu menawarkan Buka Peta Dunia")
	if sail_btn != null:
		SdUI.guard_until_ms = 0
		sail_btn.pressed.emit()
	await _frames(2)
	_check(app.screen == "map", "naik perahu -> kembali ke peta")

	print("== 3.x Berlayar antarpulau (Pulau 2 terbuka setelah Raja Goblin kalah)")
	app.show_map()
	await _frames(2)
	m = app.current
	m.sail_seconds = 0.3
	_check(m.sail("pulau2") and m.sailing, "perahu mulai berlayar ke Pulau 2 (kelas 2)")
	await _wait(0.6)
	await _frames(3)
	_check(app.screen == "island" and str(app.p.world.island) == "pulau2" and int(app.p.world.sailed) == 1, "tiba di Pulau 2, pelayaran dicatat")
	app.go_back()
	await _frames(2)
	_check(app.screen == "map", "kembali dari pulau ke peta")
	app.p.world.island = "pulau1"
	app.save()
	await _v4_islands_play(app)

	print("== 3.x Pengaturan, simpan, buka ulang")
	app.go_back()
	await _frames(2)
	_check(app.screen == "title" and _btn(app.current, "Continue") != null, "peta -> menu utama dengan Lanjutkan Petualangan")
	_check(_btn(app.current, "Report") != null, "menu utama: tombol Laporan Belajar")
	_press(app.current, "Report")
	await _frames(2)
	_check(app.screen == "report" and _label_has(app.current, "Mata Pelajaran"), "Laporan Belajar dari menu utama")
	app.go_back()
	await _frames(2)
	_press(app.current, "Settings")
	await _frames(2)
	_press(app.current, "gfx_hemat")
	await _frames(2)
	_check(str(app.p.settings.gfx) == "hemat" and app.screen == "settings", "grafis Hemat dipilih")
	var saved := SaveManager.load_progress("education_sd", 3)
	_check(int(saved.get("schema_version", 0)) == 3 and str(saved.data.profile.name) == "Ana" and str(saved.data.settings.gfx) == "hemat",
		"progres tersimpan di skema 3")
	app = await _open()
	app.foes_calm = 99999.0
	_check(app.screen == "title" and _btn(app.current, "Continue") != null and str(app.p.profile.name) == "Ana", "buka ulang: petualang dikenali")
	_press(app.current, "Continue")
	await _frames(2)
	_check(app.screen == "map" and not app.modal_open(), "Lanjutkan -> peta tanpa cerita pembuka lagi")
	app.go_back()
	await _frames(1)
	app.go_back()
	await _frames(1)
	_check(app._exit_dialog != null and app._exit_dialog.visible, "kembali di menu utama: tanya dulu sebelum keluar")
	app._exit_dialog.hide()

	print("== 3.x Save 2.x di HP pemain dipindahkan saat game dibuka")
	_clear_save()
	SaveManager.save("education_sd", _v2_sample(), 2)
	app = await _open()
	app.foes_calm = 99999.0
	_check(int(app.p.migrated_from) == 2 and str(app.p.profile.name) == "Budi" and int(app.p.rpg.coins) == 77, "save 2.x dimigrasikan lewat GameManager")
	_check(app.screen == "title" and app.modal_open(), "pemain lama disambut pesan Petualangan Baru")
	_check(int(SaveManager.load_progress("education_sd", 3).get("schema_version", 0)) == 3, "berkas save ditulis ulang dalam skema 3")
	_clear_save()


func _hud_btn(app: Node, text: String) -> Button:
	for b in app.hud.find_children("*", "Button", true, false):
		if (b as Button).text == text and b.is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


func _press_hud(app: Node, text: String) -> bool:
	var b := _hud_btn(app, text)
	if b == null:
		return false
	SdUI.guard_until_ms = 0
	b.pressed.emit()
	return true


func _next_pages(app: Node) -> void:
	for i in 12:
		if not _press_hud(app, "Lanjut"):
			return
		await _frames(1)


## Dekati penduduk lalu tekan AKSI; lewati halaman Lanjut.
func _talk_to(app: Node, id: String) -> void:
	var n: Node3D = app.world.npc_node(id)
	app.hud.close_dialog()
	app.world.player.place(n.position + Vector3(1.0, 0.3, 0.3), 0.0)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(2)
	await _next_pages(app)


func _go_spot(app: Node, kind: String, id := "") -> void:
	app.hud.close_dialog()
	var sp: Vector3 = app.world.spot_pos(kind, id)
	app.world.player.place(sp + Vector3(0, app.world.ground_y(sp.x, sp.z) + 0.3, 0), 0.0)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(2)
	await _next_pages(app)


## Selesaikan tantangan misi yang sedang terbuka (semua benar).
func _do_challenge(app: Node) -> bool:
	var cv = app.lesson
	if cv == null or not cv.has_method("is_passed"):
		return false
	_press(cv, "Start")
	await _frames(1)
	var guard := 0
	while cv.phase == "soal" and guard < 10:
		guard += 1
		var qv = cv.current_question_view()
		_answer(qv, true)
		await _frames(1)
		if cv.phase == "soal" and cv.current_question_view() == qv:
			qv._emit_finish()
		await _frames(1)
	var ok: bool = cv.phase == "hasil" and cv.is_passed()
	_press(cv, "Continue")
	await _frames(2)
	return ok


func _collect_all(app: Node) -> int:
	var n := 0
	for uid in app.world.pickups.keys():
		var pn: Node3D = app.world.pickups[uid]
		app.world.player.place(Vector3(pn.position.x, app.world.ground_y(pn.position.x, pn.position.z) + 0.3, pn.position.z), 0.0)
		await _frames(3)
		n += 1
	app.hud.close_dialog()
	return n


func _label_has(root: Node, text: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if str((l as Label).text).contains(text) and not l.is_queued_for_deletion():
			return true
	return false


## Menangkan pertarungan yang sedang terbuka: Jurus Ilmu benar terus; Bertahan saat bos bersiap memukul.
func _battle_win(app: Node) -> bool:
	var bv = app.lesson
	if bv == null or not bv.has_method("choose"):
		return false
	var guard := 0
	while not bv.engine.over and guard < 40:
		guard += 1
		if bv.engine.heavy_next:
			_press(bv, "Act_bertahan")
			await _frames(1)
			continue
		_press(bv, "Act_ilmu")
		await _frames(1)
		var q = bv.current_question_view()
		if q == null:
			_press(bv, "Act_serang")
			await _frames(1)
			continue
		_answer(q, true)
		await _frames(1)
		if bv.current_question_view() == q:
			q._emit_finish()
		await _frames(1)
		bv.engine.player.hp = maxi(int(bv.engine.player.hp), 20)
	var won: bool = bv.engine.won
	_press(bv, "Done")
	await _frames(3)
	return won


# --- 4.x Pulau 2–6 (Tahap 8) -------------------------------------------------------------------------------------

func _v4_data_tests() -> void:
	print("== 4.x Data Pulau 1–6: tata letak, misi, musuh, toko")
	var worlds := WorldEngine.new()
	worlds.load_data()
	_check(worlds.islands.size() == 6 and worlds.islands.all(func(i): return bool(i.get("available", false))), "keenam pulau tersedia")
	var rpg = JSON.parse_string(FileAccess.get_file_as_string("res://games/education_sd/data/rpg.json"))
	var bank := SdData.new()
	bank.load_data()
	for isl in worlds.islands:
		var n := int(isl.number)
		var ne := NpcEngine.new()
		var qe := QuestEngine.new()
		var ok_l := ne.load_layout(str(isl.layout))
		var ok_q := qe.load_quests(str(isl.quests))
		_check(ok_l and ok_q, "Pulau %d: tata letak & misi valid %s" % [n, str(ne.errors + qe.errors).left(120)])
		var mv = JSON.parse_string(FileAccess.get_file_as_string("res://games/education_sd/data/" + str(isl.monsters)))
		_check(typeof(mv) == TYPE_DICTIONARY and (mv.spawns as Array).size() == 8, "Pulau %d: musuh & 8 tempat muncul" % n)
		var models := true
		for id in mv.monsters:
			if not ResourceLoader.exists(MODEL_DIR + str(mv.monsters[id].model) + ".glb"):
				models = false
		for e in ne.npcs.values():
			if not ResourceLoader.exists(MODEL_DIR + str(e.model) + ".glb"):
				models = false
		for o in ne.layout.get("objects", []):
			var env_base := "res://games/education_sd/assets/environment/" + str(o.asset)
			if not ResourceLoader.exists(env_base + ".glb") and not ResourceLoader.exists(env_base + ".gltf"):
				models = false
		_check(models, "Pulau %d: semua model penduduk, musuh, bangunan ada di APK" % n)
		var boss_id := str(ne.layout.boss.get("monster", "raja_goblin"))
		_check(mv.monsters.has(boss_id) and bool(mv.monsters[boss_id].get("boss", false)), "Pulau %d: bos %s" % [n, str(isl.boss.name)])
		var mains := qe.quests.filter(func(q): return str(q.kind) == "main")
		_check(mains.size() == 6 and qe.quests.size() >= 10, "Pulau %d: 6 misi utama + misi sampingan (%d)" % [n, qe.quests.size()])
		var topics_ok := true
		for cid in qe.challenges:
			if qe.challenge_topic(cid, bank, n) == "":
				topics_ok = false
		_check(topics_ok, "Pulau %d: semua tantangan punya soal kelas %d" % [n, n])
		for nid in ne.npcs:
			var sid := str(ne.npcs[nid].get("shop", ""))
			if sid != "":
				_check(rpg.shop.has(sid), "Pulau %d: toko %s ada" % [n, sid])
	print("== 4.x Keseimbangan bos Pulau 2–6 (anak di level wajar, Jurus Ilmu benar 70%)")
	_check(is_equal_approx(BattleEngine.level_factor(1, 11), 4.0 / 11.0) and BattleEngine.level_factor(10, 5) == 1.0
		and BattleEngine.level_factor(1, 30) == 0.35, "musuh menyesuaikan level pemain (0,35–1,0)")
	for n in range(2, 7):
		var mv2 = JSON.parse_string(FileAccess.get_file_as_string("res://games/education_sd/data/monsters%d.json" % n))
		var bid := ""
		for id in mv2.monsters:
			if bool(mv2.monsters[id].get("boss", false)):
				bid = id
		# Level wajar saat sampai di bos: 2n+1 (kartu & topik kuasai bertambah seiring pulau).
		var lv := 2 * n + 1
		var st := {"level": lv, "hp": 40 + 8 * lv, "atk": 6 + 2 * lv, "def": 2 + lv, "ilmu": 10 + 3 * (2 * n) + 2 * n}
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 + n
		var wins := 0
		var N := 150
		for i in N:
			var sim := BattleEngine.new()
			sim.start(st, bid, mv2.monsters[bid], 0, 3000 + i)
			while not sim.over and sim.turn < 60:
				if sim.heavy_next:
					sim.act("bertahan")
				elif int(sim.player.hp) < int(st.hp) / 3 and rng.randf() < 0.5:
					sim.act("barang", {"use": "heal", "power": 30})
				else:
					var ok := rng.randf() < 0.7
					sim.act("ilmu", {"correct": ok, "first_try": ok and rng.randf() < 0.5})
			if sim.won:
				wins += 1
		var rate := float(wins) / N
		_check(rate >= 0.6 and rate < 1.0, "Pulau %d: %s menantang tapi bisa dikalahkan (lv %d, %d%% menang)" % [n, str(mv2.monsters[bid].name), lv, int(rate * 100)])
		# Anak kelas n yang baru mulai (level 1) tetap punya peluang karena penyesuaian level.
		var weak := BattleEngine.new()
		weak.start({"level": 1, "hp": 48, "atk": 8, "def": 3, "ilmu": 12}, bid, mv2.monsters[bid], 0, 5)
		_check(int(weak.enemy.max) <= int(mv2.monsters[bid].hp) * 0.6, "Pulau %d: bos melunak untuk pemain level 1 (HP %d)" % [n, int(weak.enemy.max)])


## Mainkan seluruh misi satu pulau lewat UI (bicara, kumpulkan, tantangan, gerbang, musuh, bos).
func _v4_play_island(app: Node, n: int) -> void:
	var id := "pulau%d" % n
	_check(app.worlds.status(id, app.p) == "open", "Pulau %d terbuka setelah bos pulau sebelumnya kalah" % n)
	app.show_island(id)
	await _frames(4)
	var w: Node3D = app.world
	var Q = app.quest
	_check(app.screen == "island" and w != null and w.npcs.size() == 9 and w.find_child("Boss", true, false) != null
		and w.find_child("Fort", true, false) != null and w.foes.size() == 8, "Pulau %d: dunia 3D, 9 penduduk, benteng, bos, 8 musuh" % n)
	_check(app.learn_grade() == n, "Pulau %d: soal mengikuti kelas pulau" % n)
	var order: Array = Q.quests.filter(func(q): return not bool(q.get("auto", false)))
	order.append_array(Q.quests.filter(func(q): return bool(q.get("auto", false))))
	var stuck := ""
	for q in order:
		var qid := str(q.id)
		var guard := 0
		while Q.state(app.p, qid) != "done" and guard < 12:
			guard += 1
			if Q.state(app.p, qid) == "":
				if bool(q.get("auto", false)):
					break
				await _talk_to(app, str(q.giver))
				_press_hud(app, "Terima misi")
				await _frames(2)
				continue
			var s: Dictionary = Q.step(app.p, qid)
			match str(s.get("type", "")):
				"learn":
					app.quest.event(app.p, "learn", "", app._qctx())
				"talk":
					await _talk_to(app, str(s.npc))
				"collect":
					await _collect_all(app)
					await _frames(2)
				"challenge":
					if s.has("npc"):
						await _talk_to(app, str(s.npc))
						_press_hud(app, "Mulai tantangan")
						await _frames(2)
					elif str(s.get("spot", "")) == "boulder":
						await _go_spot(app, "boulder")
					else:
						await _go_spot(app, "clue", str(s.spot))
					await _do_challenge(app)
					await _frames(2)
				"use":
					await _go_spot(app, "gate")
					await _frames(2)
				"defeat":
					var target := str(s.target)
					if bool(app.monsters.monsters.get(target, {}).get("boss", false)):
						app.hud.close_dialog()
						w.player.place(w.spot_pos("boss") + Vector3(0, 0.3, 0.4), PI)
						await _frames(3)
						app.hud.trigger_action()
						await _frames(1)
						_press_hud(app, "Bertarung!")
						await _frames(2)
						await _battle_win(app)
						await _frames(2)
						app.close_modal()
					else:
						for f in w.foes.duplicate():
							if str(f.monster) == target and Q.state(app.p, qid) == "active" and str(Q.step(app.p, qid).get("type", "")) == "defeat":
								app.start_battle(target, str(f.uid))
								await _frames(2)
								await _battle_win(app)
				_:
					break
			app.hud.close_dialog()
		if Q.state(app.p, qid) != "done" and not (bool(q.get("auto", false)) and str(q.steps[0].type) in ["places_all", "meet_all"]):
			stuck += "%s(%s) " % [qid, str(Q.step(app.p, qid).get("type", "?"))]
	_check(stuck == "", "Pulau %d: semua misi selesai dimainkan %s" % [n, stuck])
	_check(Q.done_count(app.p, "main") == 6 and bool(app.p.world.bosses.get(id, false)), "Pulau %d: 6 misi utama, bos kalah" % n)
	_check(w.gate_open() and w.find_child("Boss", true, false) == null, "Pulau %d: gerbang terbuka, bos pergi" % n)
	app.close_modal()
	app.hud.close_dialog()


func _v4_islands_play(app: Node) -> void:
	print("== 4.x Pulau 2–6 dimainkan berurutan sampai tamat")
	app.battle_seed = 21
	for n in range(2, 7):
		await _v4_play_island(app, n)
	_check(app.all_bosses_down(), "keenam bos kalah")
	var coins := int(app.p.rpg.coins)
	app._final_ending()
	await _frames(1)
	_check(app.modal_open() and bool(app.p.world.flags.get("tamat", false)) and int(app.p.rpg.coins) == coins + 500, "akhir cerita: Kabut Lupa lenyap, hadiah 500 koin")
	app._final_ending()
	_check(int(app.p.rpg.coins) == coins + 500, "hadiah tamat hanya sekali")
	app.close_modal()
	app.show_bag()
	await _frames(2)
	_press(app.lesson, "Tab_Barang")
	await _frames(1)
	_check(_label_has(app.lesson, "Piala"), "tas menampilkan piala dari pulau lain")
	_press(app.lesson, "Close")
	await _frames(2)
	app.p.world.island = "pulau1"
	app.save()
	app.show_map()
	await _frames(2)


# --- 4.1 Suara pembaca untuk kelas 1–2 ---------------------------------------------------------------------------

const VoiceT := preload("res://games/education_sd/scripts/voice.gd")


func _v5_voice_unit_tests() -> void:
	print("== 4.1 Suara pembaca (TTS): teks, sorot kata, mode")
	var v := VoiceT.new()
	root.add_child(v)
	_check(not VoiceT.engine_on() and not v.available() and v.status() != "", "headless: mesin suara mati, ada pesan penjelasan")
	v.fake = true
	v.grade = 1
	_check(v.available() and v.auto_read() and v.listen_enabled(), "kelas 1, mode otomatis: dibacakan otomatis")
	v.grade = 3
	_check(not v.auto_read() and v.listen_enabled(), "kelas 3, mode otomatis: hanya lewat tombol Dengar")
	v.mode = "on"
	_check(v.auto_read(), "mode Selalu: semua kelas dibacakan")
	v.mode = "off"
	_check(not v.auto_read() and not v.listen_enabled(), "mode Mati: tidak dibacakan, tombol Dengar disembunyikan")
	v.mode = "auto"
	v.grade = 1
	v._build("3 + 4 = ?")
	_check(v._spoken.contains("tambah") and v._spoken.contains("sama dengan") and v._spoken.contains("berapa"), "simbol soal dibaca: tambah, sama dengan, berapa (%s)" % v._spoken.strip_edges())
	v._build("8 - 3 adalah teka-teki ×2 ★")
	_check(v._spoken.contains("kurang") and v._spoken.contains("teka-teki") and v._spoken.contains("kali") and not v._spoken.contains("★"),
		"kurang vs tanda hubung, kali, hiasan dilewati")
	var words: Array = []
	v.word.connect(func(a: int, b: int) -> void: words.append(v.text.substr(a, b - a)))
	var done := [false]
	v.ended.connect(func() -> void: done[0] = true)
	v.speak("Halo Ana, ayo belajar!")
	for i in 60:
		await process_frame
		if done[0]:
			break
	_check(words == ["Halo", "Ana,", "ayo", "belajar!"] and done[0] and not v.speaking, "kata disorot berurutan lalu selesai (%s)" % str(words))
	v.speak("Satu dua tiga empat lima")
	v.stop()
	_check(not v.speaking, "berhenti membaca")
	_check(SdUI.marked("a [b] c", 3, 6).contains("[bgcolor=#ffe08a]") and SdUI.marked("a [b] c", 3, 6).begins_with("a [lb]"), "sorot kata aman untuk tanda kurung")
	v.queue_free()
	await process_frame


func _v5_voice_app_tests() -> void:
	print("== 4.1 Suara pembaca di game: dialog dibacakan Bu Guru/penduduk, soal & pilihan dibacakan")
	_clear_save()
	var app := await _open()
	app.foes_calm = 99999.0
	app.voice.fake = true
	app.voice.fake_step = 0.02
	app.set_profile({"name": "Ana", "grade": 1, "hero": "perempuan", "outfit": "warna_biru"})
	await _frames(2)
	_check(app.modal_open() and str(app.voice.history.back()).contains("Kabut"), "cerita pembuka dibacakan untuk kelas 1")
	_check(_btn(app._modal, "Listen") != null, "tombol Dengar di cerita pembuka")
	app.close_modal()
	_check(not app.voice.speaking, "menutup cerita menghentikan suara")
	app.arrive("pulau1")
	await _frames(4)
	await _talk_to(app, "pak_lurah")
	app.hud.close_dialog()
	var n: Node3D = app.world.npc_node("pak_lurah")
	app.world.player.place(n.position + Vector3(1.0, 0.3, 0.3), 0.0)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(2)
	var hud = app.hud
	_check(hud.dialog_open() and app.voice.speaking and str(app.voice.text) == hud.dialog_plain(), "dialog penduduk langsung dibacakan")
	_check(hud.portrait.visible and str(hud.portrait.model) == str(app.npc.npcs.pak_lurah.model), "potret 3D Pak Lurah membacakan pesannya")
	_check(hud._listen.visible, "tombol Dengar di dialog")
	var marked := false
	for i in 20:
		await _frames(1)
		if str(hud._dialog_text.text).contains("[bgcolor"):
			marked = true
			break
	_check(marked and hud.portrait.talking, "kata yang sedang dibaca disorot, tokoh bergerak berbicara")
	hud.close_dialog()
	await _frames(1)
	_check(not app.voice.speaking and not str(hud._dialog_text.text).contains("[bgcolor"), "tutup dialog: suara berhenti")
	app.world.player.place(app.world.spot_pos("dock") + Vector3(0, 0.2, -0.8), 0.0)
	await _frames(3)
	app.hud.trigger_action()
	await _frames(2)
	_check(str(hud.portrait.model) == "warga_ibu" and app.voice.speaking, "pesan tanpa penduduk dibacakan Bu Guru")
	hud.close_dialog()
	# Soal: dibacakan beserta pilihan jawabannya.
	app.open_challenge(str(app.quest.challenges.keys()[0]))
	await _frames(2)
	var cv = app.lesson
	_check(cv != null and app.voice.speaking and _btn(cv, "Listen") != null, "tantangan: cerita dibacakan + tombol Dengar")
	_press(cv, "Start")
	await _frames(2)
	var qv = cv.current_question_view()
	_check(qv != null and str(app.voice.text) == qv.read_text() and _btn(qv, "Listen") != null, "soal dibacakan otomatis + tombol Dengar")
	if str(qv.q.type) in ["mc", "logic", "fill"]:
		_check(qv.read_text().contains("Pilihannya:") and qv.read_text().contains(str(qv._options[0])), "pilihan jawaban ikut dibacakan")
	app.go_back()
	await _frames(1)
	app.close_class()
	await _frames(1)
	# Kelas 3 (mode otomatis): tidak dibacakan sendiri, tetapi tombol Dengar ada.
	app.p.profile.grade = 3
	app.save()
	await _talk_to(app, "pak_lurah")
	app.hud.close_dialog()
	app.world.player.place(n.position + Vector3(1.0, 0.3, 0.3), 0.0)
	await _frames(3)
	app.voice.history.clear()
	app.hud.trigger_action()
	await _frames(2)
	_check(hud.dialog_open() and app.voice.history.is_empty() and hud._listen.visible, "kelas 3: tidak dibacakan otomatis, tombol Dengar tersedia")
	SdUI.guard_until_ms = 0
	hud._listen.pressed.emit()
	await _frames(1)
	_check(app.voice.speaking and str(app.voice.text) == hud.dialog_plain(), "tekan Dengar: dibacakan")
	hud.close_dialog()
	app.go_back()
	await _frames(2)
	app.show_settings()
	await _frames(2)
	_check(_btn(app.current, "voice_auto") != null and _btn(app.current, "voice_off") != null and _btn(app.current, "VoiceTry") != null,
		"Pengaturan: Suara pembaca (Otomatis kelas 1–2 / Selalu / Mati) + Coba suara")
	_press(app.current, "voice_off")
	await _frames(2)
	_check(str(app.p.settings.voice) == "off" and str(app.voice.mode) == "off", "suara pembaca dimatikan dan tersimpan")
	app.voice.fake = false
	_clear_save()


# --- 4.2 Pengaturan orang tua: suara pembaca, lagu anak, resolusi 3D --------------------------------------------

func _v6_settings_tests() -> void:
	print("== 4.2 Pengaturan: pilihan suara pembaca, lagu, resolusi 3D")
	_clear_save()
	var app := await _open()
	app.foes_calm = 99999.0
	app.voice.fake = true
	app.set_profile({"name": "Ana", "grade": 1, "hero": "perempuan", "outfit": "warna_biru"})
	app.close_modal()
	_check(str(app.p.settings.voice_rate) == "sedang" and str(app.p.settings.voice_pitch) == "normal" and str(app.p.settings.song) == "acak"
		and str(app.p.settings.res) == "sedang", "bawaan: suara sedang/normal, lagu acak, resolusi sedang")
	app.show_settings()
	await _frames(2)
	var page: Node = app.current
	for nm in ["voice_rate_pelan", "voice_rate_cepat", "voice_pitch_tinggi", "voice_id_next", "song_next", "res_rendah", "res_tinggi", "gfx_hemat", "VoiceTry"]:
		_check(_btn(page, nm) != null, "Pengaturan punya " + nm)
	_press(page, "voice_rate_pelan")
	await _frames(1)
	_press(app.current, "voice_pitch_tinggi")
	await _frames(1)
	_check(str(app.voice.rate) == "pelan" and str(app.voice.pitch) == "tinggi" and app.screen == "settings", "kecepatan Pelan & nada Tinggi diterapkan ke suara pembaca")
	_check(is_equal_approx(float(VoiceT.RATES[app.voice.rate]), 0.7) and is_equal_approx(float(VoiceT.PITCHES[app.voice.pitch]), 1.25), "nilai TTS: kecepatan 0,7, nada 1,25")
	_check(app.audio.songs().size() == 7, "7 pilihan lagu (%d)" % app.audio.songs().size())
	_press(app.current, "song_next")
	await _frames(1)
	var s1 := str(app.p.settings.song)
	_check(s1 != "acak" and str(app.audio.song) == s1 and _label_has(app.current, str(app.audio.songs()[0][1])), "ganti lagu: %s" % s1)
	_press(app.current, "song_prev")
	await _frames(1)
	_check(str(app.p.settings.song) == "acak", "kembali ke Acak (semua lagu)")
	var Aud := preload("res://games/education_sd/scripts/sd_audio.gd")
	for id in ["bintang", "ombak"]:
		var st: AudioStreamWAV = Aud._build_song(Aud._song_def(id))
		var sec := st.data.size() / 2.0 / Aud.RATE
		_check(sec > 15.0 and sec < 40.0, "lagu %s dibuat dengan kode (%.1f detik)" % [id, sec])
	_press(app.current, "res_rendah")
	await _frames(1)
	app.arrive("pulau1")
	await _frames(3)
	var box: SubViewportContainer = app.current.find_child("View3D", true, false)
	var vp: SubViewport = box.get_child(0)
	var low := vp.scaling_3d_scale
	_check((box.size * box.scale).distance_to(app.current.size) < 1.0, "dunia 3D memenuhi layar pada piksel layar sungguhan")
	var phys := box.size.y
	app.go_back()
	await _frames(2)
	app.p.settings.res = "tinggi"
	app.arrive("pulau1")
	await _frames(3)
	vp = app.current.find_child("View3D", true, false).get_child(0)
	_check(is_equal_approx(low, clampf(540.0 / phys, 0.25, 1.0)) and is_equal_approx(vp.scaling_3d_scale, clampf(1080.0 / phys, 0.25, 1.0)),
		"Resolusi Rendah/Tinggi: 3D setinggi 540/1080 piksel (skala %.2f / %.2f, layar %d)" % [low, vp.scaling_3d_scale, int(phys)])
	app.voice.fake = false
	_clear_save()
