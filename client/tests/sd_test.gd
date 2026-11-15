extends SceneTree
## Uji Game Pembelajaran SD "Petualangan Pulau Ilmu" (headless, dari proyek sumber):
## data & validasi, pembuat soal, setiap tipe soal di setiap mode, sesi petualangan/latihan/kuis/ujian,
## adaptif, mini-game, hadiah/koleksi/prestasi, laporan, pengaturan, simpan-muat, dan migrasi skema 1 -> 2.
## Jalankan: GODOT=... scripts/sd-test.sh   (atau make sd-test)

const SdData := preload("res://games/education_sd/scripts/sd_data.gd")
const SdGen := preload("res://games/education_sd/scripts/sd_gen.gd")
const SdProgress := preload("res://games/education_sd/scripts/sd_progress.gd")
const SdQuestion := preload("res://games/education_sd/scripts/sd_question.gd")
const SdMini := preload("res://games/education_sd/scripts/sd_minigames.gd")
const SaveManager := preload("res://core/save_manager.gd")

const SCENE := "res://games/education_sd/main.tscn"

var _failed := false
var _checks := 0


func _initialize() -> void:
	await process_frame
	for f in ["save.json", "save.json.bak"]:
		DirAccess.remove_absolute(SaveManager.dir_for("education_sd") + "/" + f)
	await _data_tests()
	await _question_tests()
	await _app_tests()
	print("SD: %d pemeriksaan, %s" % [_checks, "GAGAL" if _failed else "LULUS"])
	print("HASIL: " + ("GAGAL" if _failed else "LULUS"))
	quit(1 if _failed else 0)


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
	_check(d.questions.size() >= 200, "bank soal >= 200 (%d)" % d.questions.size())
	_check(d.regions.size() == 4, "empat wilayah")
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
	var st := {"recent": [0, 0, 0, 1, 0, 0], "seen": []}
	var easy := d.pick("penjumlahan", 3, 5, st, rng)
	_check(easy.mode == "mudah" and int(easy.grade) == 2, "sering salah -> soal kelas lebih rendah, konsep sama (kelas %d)" % int(easy.grade))
	var good := d.pick("penjumlahan", 3, 5, {"recent": [1, 1, 1, 1, 1, 1], "seen": []}, rng)
	_check(good.mode == "tantang" and int(good.grade) == 3, "sering benar -> tetap kelas sendiri, soal sulit didahulukan")
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


# --- Aplikasi utuh ------------------------------------------------------------------------------------------------

func _scene() -> Node:
	return current_scene


func _open() -> Node:
	change_scene_to_file(SCENE)
	for i in 30:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == SCENE and current_scene.screen != "":
			break
	return current_scene


## Selesaikan sesi soal yang sedang tampil: semua benar (right=true) atau semua salah.
func _play_session(app: Node, right: bool) -> void:
	var guard := 0
	while app.screen == "session" and guard < 40:
		guard += 1
		var qv = app.current_question_view()
		_answer(qv, right)
		if not right and qv.mode == "latihan" and not qv._done:
			_answer(qv, true)
		await process_frame
		if app.screen == "session" and app.current_question_view() == qv:
			if qv._next.visible:
				qv._emit_finish()
			await process_frame


func _app_tests() -> void:
	print("== Aplikasi: pengenalan & beranda")
	var app := await _open()
	_check(app != null and app.screen == "onboarding", "pemain baru melihat layar pengenalan (nama + kelas)")
	app.set_player("Ani", 1)
	app.show_home()
	_check(app.screen == "home" and str(app.p.player.name) == "Ani" and app.grade() == 1, "nama dan kelas tersimpan, beranda tampil")
	var texts := _button_texts(app)
	for want in ["MULAI PETUALANGAN", "PILIH PELAJARAN", "KOLEKSI", "PRESTASI", "PENGATURAN", "KEMBALI KE LAUNCHER", "MINI-GAME", "LAPORAN BELAJAR"]:
		_check(texts.has(want), "beranda punya tombol " + want)

	print("== Mode petualangan: seluruh area Kerajaan Matematika kelas 1 + ujian akhir")
	app.show_map()
	_check(app.screen == "map", "peta pulau terbuka")
	app.show_region("matematika")
	_check(app.screen == "region", "wilayah Kerajaan Matematika terbuka (NPC + area)")
	var ts: Array = app.data.topics_for("matematika", 1)
	var exam_btn: Button = app.page().find_child("Exam", true, false)
	_check(exam_btn != null and exam_btn.disabled, "ujian akhir terkunci sebelum semua area selesai")
	var second: Button = app.page().find_child("Area_" + str(ts[1].id), true, false)
	_check(second != null and second.disabled, "area kedua terkunci sebelum area pertama selesai")
	var coins0 := int(app.p.coins)
	for t in ts:
		app.start_area("matematika", str(t.id))
		_check(app.screen == "session", "area %s dimulai" % t.id)
		await _play_session(app, true)
		_check(app.screen == "result" and int(SdProgress.area_rec(app.p, 1, "matematika", str(t.id)).stars) == 3, "area %s selesai: 3 bintang" % t.id)
	_check(int(app.p.coins) > coins0, "koin bertambah (%d -> %d)" % [coins0, int(app.p.coins)])
	_check((app.p.cards as Array).size() >= ts.size(), "kartu pengetahuan terkumpul (%d)" % (app.p.cards as Array).size())
	app.show_region("matematika")
	exam_btn = app.page().find_child("Exam", true, false)
	_check(not exam_btn.disabled, "ujian akhir terbuka setelah semua area selesai")
	app.start_exam("matematika")
	await _play_session(app, true)
	_check(bool(SdProgress.grade_rec(app.p, 1).exams.matematika.passed), "ujian akhir lulus")
	_check(app.p.badges.has("ujian_lulus") and app.p.badges.has("area_pertama") and app.p.badges.has("beruntun_5"), "lencana prestasi didapat")

	print("== Mode kuis & latihan")
	app.start_quiz("bahasa")
	await _play_session(app, true)
	_check(int(SdProgress.grade_rec(app.p, 1).quiz.bahasa.best) == 100 and app.p.badges.has("kuis_100"), "kuis Bahasa nilai 100 tersimpan + lencana")
	_check(app.page().find_child("Next", true, false) != null, "hasil kuis menampilkan pembahasan")
	app.start_practice("huruf")
	await _play_session(app, false)
	_check(app.screen == "result", "latihan dengan kesalahan tetap bisa diselesaikan (coba lagi)")
	_check(bool(app.p.get("retried", false)) and app.p.badges.has("tak_menyerah"), "mencoba lagi dihargai (lencana Pantang Menyerah)")
	var wrong_before := int(app.p.totals.wrong)
	app.start_quiz("ipa")
	await _play_session(app, false)
	_check(int(app.p.totals.wrong) > wrong_before and int(SdProgress.grade_rec(app.p, 1).quiz.ipa.last) < 100, "jawaban salah di kuis tercatat")
	app.start_area("bahasa", "huruf")
	app.leave_session()
	_check(app.screen == "region", "keluar di tengah sesi kembali ke wilayah")

	print("== Mini-game (satu per mata pelajaran)")
	for m in SdMini.LIST:
		app.start_minigame(str(m.id))
		_check(app.screen == "minigame", "mini-game %s terbuka" % m.name)
		var mg = app.current_question_view()
		match str(m.id):
			"kode":
				for i in 5:
					mg.type_and_submit(mg.current_answer())
					await _wait(0.5)
			"huruf":
				for i in 8:
					mg.pick(mg.current_answer())
					await _wait(1.25)
			"hewan":
				for i in 8:
					mg.put(mg.current_answer())
					await _wait(1.7)
			"pasangan":
				for i in mg.pair_count():
					mg.choose(i, mg.right_index_for(i))
		await process_frame
		var rec: Dictionary = app.p.minigames.get(str(m.id), {})
		_check(int(rec.get("plays", 0)) == 1 and int(rec.get("best", 0)) > 0, "mini-game %s selesai dan tercatat (skor %d)" % [m.name, int(rec.get("best", 0))])
	_check((app.p.animals as Array).size() >= 1, "koleksi hewan bertambah dari mini-game (%d)" % (app.p.animals as Array).size())

	print("== Koleksi, prestasi, laporan, pengaturan")
	app.p.coins = 45
	_check(app.shop_item("topi_petualang") and str(app.p.player.avatar.hat) == "topi_petualang" and int(app.p.coins) == 5, "beli & pakai topi dengan koin")
	_check(not app.shop_item("topi_mahkota") and not (app.p.owned as Array).has("topi_mahkota"), "koin kurang: tidak bisa membeli")
	_check(app.shop_item("warna_biru") and str(app.p.player.avatar.outfit) == "warna_biru", "ganti baju yang sudah dimiliki")
	for scr in ["show_collection", "show_badges", "show_report", "show_settings", "show_subjects", "show_minigames", "show_map", "show_home"]:
		app.call(scr)
		_check(app.page() != null and app.page().get_child_count() > 0, "layar %s terbuka" % scr)
	for tab in ["kartu", "hewan"]:
		app.show_collection(tab)
		_check(app.page().get_child_count() > 2, "koleksi tab %s" % tab)
	var music_before: bool = app.p.settings.music
	app.toggle_setting("music")
	app.toggle_setting("sfx")
	_check(bool(app.p.settings.music) != music_before and not bool(app.p.settings.sfx), "musik & efek suara bisa dimatikan")
	app.toggle_setting("sfx")
	app.change_grade(4)
	_check(app.grade() == 4 and int(SdProgress.area_rec(app.p, 1, "matematika", "penjumlahan").stars) == 3, "ganti ke kelas 4; progres kelas 1 tetap ada")
	app.start_area("matematika", str(app.data.topics_for("matematika", 4)[0].id))
	_check(int(app.session.questions[0].grade) >= 3, "soal kelas 4 dipakai setelah ganti kelas")
	app.leave_session()
	app.change_grade(1)

	print("== Simpan, buka ulang, dan migrasi")
	var coins := int(app.p.coins)
	var answered := int(app.p.totals.answered)
	await root.get_node("GameManager").exit_to_launcher()
	for i in 10:
		await process_frame
	var saved := SaveManager.load_progress("education_sd", 2)
	_check(int(saved.data.coins) == coins and int(saved.data.totals.answered) == answered, "progres tersimpan saat kembali ke launcher")
	app = await _open()
	_check(app.screen == "home" and str(app.p.player.name) == "Ani" and int(app.p.coins) == coins, "buka ulang: progres utuh (nama, koin)")
	# Data game SD lama (skema 1) di HP -> dimigrasikan saat dibuka.
	await root.get_node("GameManager").exit_to_launcher()
	for f in ["save.json", "save.json.bak"]:
		DirAccess.remove_absolute(SaveManager.dir_for("education_sd") + "/" + f)
	SaveManager.save("education_sd", {"levels": {"matematika/k12": {"best": 90, "attempts": 3}}, "history": [], "last_answers": []}, 1)
	app = await _open()
	_check(app.p.has("legacy") and int(app.p.schema) == 2 and int(app.p.coins) == 20, "save lama skema 1 dimigrasikan otomatis")
	var file := SaveManager.load_progress("education_sd", 2)
	_check(int(file.get("schema_version", 0)) == 2, "berkas save ditulis ulang dalam skema 2 (cadangan lama di .bak)")
	await root.get_node("GameManager").exit_to_launcher()
	for f in ["save.json", "save.json.bak"]:
		DirAccess.remove_absolute(SaveManager.dir_for("education_sd") + "/" + f)


func _button_texts(app: Node) -> Array:
	var out: Array = []
	for b in app.page().find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out
