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
	await _question_tests()
	await _app_tests()
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
	# Sinyal kembali Android (mis. saat menutup papan ketik) tidak boleh langsung menutup game.
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(current_scene == app and app.screen == "onboarding" and app._exit_dialog != null and app._exit_dialog.visible,
		"kembali di layar pengenalan: game TIDAK tertutup, pemain ditanya dulu")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(current_scene == app, "kembali dua kali tetap tidak menutup game tanpa konfirmasi")
	app._exit_dialog.hide()
	var ne: LineEdit = app.page().find_child("NameEdit", true, false)
	ne.text = "Budi"
	ne.text_submitted.emit("Budi")
	_check(app.screen == "home" and str(app.p.player.name) == "Budi", "Enter pada kolom nama = Mulai")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(current_scene == app and app._exit_dialog.visible, "kembali di beranda: ditanya dulu")
	app._exit_dialog.hide()
	app.set_player("Ani", 1)
	app.show_home()
	_check(app.screen == "home" and str(app.p.player.name) == "Ani" and app.grade() == 1, "nama dan kelas tersimpan, beranda tampil")
	var texts := _button_texts(app)
	for want in ["MULAI PETUALANGAN", "PILIH PELAJARAN", "KOLEKSI", "PRESTASI", "PENGATURAN", "KEMBALI KE LAUNCHER", "MINI-GAME", "LAPORAN BELAJAR"]:
		_check(texts.has(want), "beranda punya tombol " + want)
	# Pengaman sentuhan HP (2.0.2): tombol keluar di beranda bertanya dulu; sentuhan nyasar dan geseran
	# (menggulir) tidak boleh menekan tombol.
	app.show_home()
	var exit_btn := _find_button(app, "KEMBALI KE LAUNCHER")
	exit_btn.pressed.emit()
	_check(current_scene == app and (app._exit_dialog == null or not app._exit_dialog.visible),
		"sentuhan nyasar sesaat setelah layar dibangun diabaikan")
	SdUI.guard_until_ms = 0
	SdUI.touch_dragged = true
	exit_btn.pressed.emit()
	_check(current_scene == app and (app._exit_dialog == null or not app._exit_dialog.visible),
		"tombol yang dilepas setelah layar digulir tidak ditekan")
	SdUI.touch_dragged = false
	exit_btn.pressed.emit()
	await process_frame
	_check(current_scene == app and app._exit_dialog.visible, "tombol KEMBALI KE LAUNCHER di beranda bertanya dulu")
	app._exit_dialog.hide()
	var diag: Array = app.p.get("diag", [])
	_check(diag.size() > 0 and str(diag[0].reason) == "dibuka", "catatan diagnosis mencatat game dibuka")

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

	await _world_tests(app)
	await _world_tests2(app)
	_check(int((app.p.world.chests as Dictionary).size()) >= 1, "progres dunia 3D ikut tersimpan")
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
	_check(not app.p.has("crash"), "keluar normal tidak dianggap crash")
	# Jejak langkah: tertutup paksa (tanpa END) -> saat dibuka lagi jejak terakhir dikirim bersama progres.
	var tf := FileAccess.open("user://education_sd_trail.txt", FileAccess.WRITE)
	tf.store_line("10:00:00 BUKA v-uji")
	tf.store_line("10:00:05 layar map")
	tf.store_line("10:00:07 tombol Kerajaan Matematika")
	tf.close()
	current_scene.free()
	app = await _open()
	_check(app.p.has("crash") and str(app.p.crash.kind) == "crash" and str(app.p.crash.trail[-1]).ends_with("Kerajaan Matematika"),
		"crash terdeteksi saat dibuka lagi: jejak langkah terakhir tersimpan untuk server")
	_check(str(app.p.diag[-2].reason).begins_with("tertutup tidak normal"), "catatan diagnosis mencatat penutupan tidak normal")
	_check(int(app.p.safe_level) == 1 and not bool(app.p.settings.music), "mode aman 1 setelah crash: musik dimatikan")
	var mus: AudioStreamWAV = app.audio._build_music()
	_check(mus.loop_mode == AudioStreamWAV.LOOP_DISABLED and app.audio._music.finished.is_connected(app.audio._on_music_finished),
		"musik diulang lewat sinyal finished, bukan loop WAV (penyebab crash di Samsung A18)")
	app.p.erase("crash")
	app.p.erase("safe_level")
	app.p.settings.music = true
	# Data game SD lama (skema 1) di HP -> dimigrasikan saat dibuka.
	await root.get_node("GameManager").exit_to_launcher()
	for f in ["save.json", "save.json.bak"]:
		DirAccess.remove_absolute(SaveManager.dir_for("education_sd") + "/" + f)
	SaveManager.save("education_sd", {"levels": {"matematika/k12": {"best": 90, "attempts": 3}}, "history": [], "last_answers": []}, 1)
	app = await _open()
	_check(app.p.has("legacy") and int(app.p.schema) == 2 and int(app.p.coins) == 20, "save lama skema 1 dimigrasikan otomatis")
	_check(app.p.has("world") and str(app.p.settings.gfx) == "seimbang" and str(app.p.world.region) == "matematika",
		"data lama mendapat bagian dunia 3D & pengaturan grafis bawaan tanpa kehilangan isi")
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


func _dialog_press(app: Node, text: String) -> bool:
	SdUI.guard_until_ms = 0
	SdUI.touch_dragged = false
	for b in app.hud.find_children("*", "Button", true, false):
		if (b as Button).text == text and b.is_visible_in_tree():
			(b as Button).pressed.emit()
			return true
	return false


func _dialog_text(app: Node) -> String:
	return str(app.hud._dialog_title.text) + " | " + str(app.hud._dialog_text.text)


func _steps(n: int) -> void:
	for i in n:
		await physics_frame


func _go_to(app: Node, kind: String, id: String = "") -> bool:
	var a: Area3D = app.world.find_use(kind, id)
	if a == null:
		return false
	app.world.player.place(a.global_position - Vector3(0, 1.0, 0) + Vector3(0, 0.1, 0.6), 0.0)
	await _steps(4)
	return app.world.focus_label() != ""


func _world_tests(app: Node) -> void:
	print("== Dunia 3D: gerak, tabrakan, interaksi, belajar, hadiah, simpan")
	app.set_player("Ani", 2)
	app.show_world("matematika")
	await process_frame
	var w: Node3D = app.world
	_check(app.screen == "world" and w != null and w.player != null, "dunia 3D Kerajaan Matematika terbuka dengan pemain")
	var ts: Array = app.data.topics_for("matematika", 2)
	_check(w.gates.size() == ts.size(), "satu gerbang/jembatan per area kelas 2 (%d)" % ts.size())
	_check(w.find_use("npc") != null and w.find_use("chest") != null and w.find_use("boss") != null and w.find_use("portal") != null
		and w.find_use("minigame") != null and w.find_use("secret") != null, "alun-alun: NPC, peti, kios mini-game, portal, tempat rahasia, penjaga wilayah")
	var z0: float = w.player.global_position.z
	w.player.move_input = Vector2(0, 1)
	await _steps(60)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.z < z0 - 2.0, "joystick maju menggerakkan karakter (%.1f m)" % (z0 - w.player.global_position.z))
	w.player.place(Vector3(0, 0.1, -10.0), 0.0)
	w.player.move_input = Vector2(1, 0)
	await _steps(120)
	w.player.move_input = Vector2.ZERO
	_check(w.player.global_position.x < w.PATH_HALF, "pagar menahan karakter di jalan (x=%.1f)" % w.player.global_position.x)
	w.player.place(Vector3(0, 0.1, w.gate_z(0) + 2.5), 0.0)
	w.player.move_input = Vector2(0, 1)
	await _steps(120)
	w.player.move_input = Vector2.ZERO
	var first := str(ts[0].id)
	_check(w.gate_blocked(first) and w.player.global_position.z > w.gate_z(0), "gerbang terkunci menghalangi jalan sebelum soal dijawab")
	w.player.place(Vector3(0, 0.1, 0.0), 0.0)
	w.player.jump()
	await _steps(8)
	_check(w.player.global_position.y > 0.5, "tombol lompat membuat karakter melompat")
	await _steps(60)
	_check(await _go_to(app, "npc") and w.focus_label().begins_with("Bicara"), "mendekati NPC memunculkan ajakan bicara (Area3D)")
	_check(w.interact() and app.hud.dialog_open() and _dialog_text(app).contains("Raja Angka"), "AKSI: berbicara dengan Raja Angka")
	_check(w.player.frozen, "pemain berhenti selama dialog terbuka")
	app.hud.close_dialog()
	# Gerbang kedua masih terkunci
	await _go_to(app, "gate", str(ts[1].id))
	w.interact()
	_check(_dialog_text(app).contains("terkunci"), "gerbang/jembatan berikutnya terkunci sebelum area sebelumnya selesai")
	app.hud.close_dialog()
	await _go_to(app, "boss")
	w.interact()
	_check(not _dialog_press(app, "Mulai ujian") and _dialog_text(app).contains("Buka semua gerbang"), "penjaga wilayah (ujian akhir) terkunci")
	app.hud.close_dialog()
	# Gerbang pertama: soal -> gerbang terbuka
	var coins0 := int(app.p.coins)
	await _go_to(app, "gate", first)
	w.interact()
	_check(_dialog_press(app, "Mulai!") and app.screen == "session" and app._world_return == "matematika", "gerbang 1: sesi soal dimulai dari dunia 3D")
	await _play_session(app, true)
	_check(app.screen == "result", "sesi selesai -> hasil + pembahasan")
	app.go_back()
	w = app.world
	_check(app.screen == "world" and w != null, "Lanjut dari hasil kembali ke dunia 3D")
	_check(not w.gate_blocked(first) and bool(SdProgress.area_rec(app.p, 2, "matematika", first).done), "gerbang 1 terbuka setelah area selesai")
	_check(int(app.p.coins) > coins0, "hadiah koin dari hasil soal (%d -> %d)" % [coins0, int(app.p.coins)])
	_check((app.p.world.seen_done as Dictionary).has("k2/matematika/" + first), "animasi gerbang terbuka diputar sekali (tercatat)")
	_check(w.spawn_point().z < w.gate_z(0), "pemain muncul di balik gerbang yang sudah terbuka")
	# Jembatan (gerbang ke-2): tinggalkan sesi di tengah -> kembali ke dunia, jembatan tetap rusak
	await _go_to(app, "gate", str(ts[1].id))
	w.interact()
	_check(_dialog_text(app).contains("Jawab") and _dialog_press(app, "Mulai!"), "jembatan rusak: mulai soal untuk memperbaikinya")
	app.leave_session()
	w = app.world
	_check(app.screen == "world" and w.gate_blocked(str(ts[1].id)), "keluar dari sesi: kembali ke dunia, jembatan tetap rusak (tanpa hadiah)")
	# Peti pengetahuan: kuis nilai >= 70
	await _go_to(app, "chest")
	w.interact()
	_check(_dialog_press(app, "Mulai kuis") and app.screen == "session", "peti pengetahuan: kuis dimulai")
	await _play_session(app, false)
	app.go_back()
	_check(app.screen == "world" and not bool(app._world_ctx("matematika").chest_opened), "kuis gagal: peti tetap tertutup")
	await _go_to(app, "chest")
	app.world.interact()
	_dialog_press(app, "Mulai kuis")
	await _play_session(app, true)
	app.go_back()
	_check(bool(app._world_ctx("matematika").chest_opened), "kuis nilai >= 70: peti pengetahuan terbuka")
	# Tempat rahasia
	w = app.world
	_check(await _go_to(app, "secret"), "tempat rahasia bisa ditemukan")
	w.interact()
	_check(bool((app.p.world.found as Dictionary).get("k2/matematika", false)) and _dialog_text(app).contains("Tahukah kamu"), "tempat rahasia: fakta pengetahuan + tercatat")
	app.hud.close_dialog()
	# Mini-game dari kios
	await _go_to(app, "minigame")
	w.interact()
	_check(app.screen == "minigame" and str(app.session.from) == "world", "kios mini-game membuka mini-game wilayah")
	app._back_from_minigame()
	_check(app.screen == "world", "selesai mini-game kembali ke dunia 3D")
	# Portal ke pulau lain
	w = app.world
	await _go_to(app, "portal")
	w.interact()
	_check(_dialog_press(app, "Hutan Bahasa") and app.screen == "world" and str(app.world.ctx.region.id) == "bahasa", "portal: pindah ke Hutan Bahasa")
	_check(str(app.p.world.region) == "bahasa", "pulau terakhir tersimpan")
	# Kontrol layar sentuh (joystick HUD)
	app.hud._layout()
	app.hud._press(app.hud._joy_center + Vector2(0, -60), 3)
	_check(app.world.player.move_input.y > 0.4, "joystick layar: geser ke atas = maju")
	app.hud._release(3)
	_check(app.world.player.move_input == Vector2.ZERO, "lepas joystick: berhenti")
	var yaw0: float = app.world.player.yaw
	app.hud._press(Vector2(app.hud.size.x * 0.6, app.hud.size.y * 0.3), 4)
	app.hud._input(_drag(4, Vector2(80, 0)))
	_check(absf(app.world.player.yaw - yaw0) > 0.1, "geser layar kanan memutar kamera")
	app.hud._release(4)
	# Profil grafis
	app.set_setting("gfx", "hemat")
	app.show_world("ipa")
	var vp: SubViewport = app.world.get_viewport()
	_check(is_equal_approx(vp.scaling_3d_scale, 0.6) and not app.world._sun.shadow_enabled, "profil Hemat: resolusi 3D 60%, tanpa bayangan")
	app.set_setting("gfx", "tinggi")
	app.show_world("ips")
	vp = app.world.get_viewport()
	_check(is_equal_approx(vp.scaling_3d_scale, 1.0) and app.world._sun.shadow_enabled and vp.msaa_3d == Viewport.MSAA_2X, "profil Tinggi: resolusi penuh, bayangan, MSAA")
	app.set_setting("hero", "perempuan")
	app.show_world("ips")
	_check(app.world.player.rig.long_hair, "pilihan karakter perempuan dipakai di dunia 3D")
	app.set_setting("gfx", "seimbang")
	app.set_setting("hero", "laki")
	app.go_back()
	_check(app.screen == "home", "Kembali dari dunia 3D -> beranda")
	app.set_player("Ani", 1)
	app.show_home()


func _drag(index: int, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.relative = rel
	e.position = Vector2(900, 300)
	return e


func _walk_to(app: Node, target: Vector3, max_steps := 400) -> bool:
	var pl: CharacterBody3D = app.world.player
	for i in max_steps:
		var to := target - pl.global_position
		to.y = 0
		if to.length() < 0.45:
			pl.move_input = Vector2.ZERO
			return true
		# move_input relatif kamera (yaw): maju = (-sin yaw, -cos yaw)
		var fwd := Vector3(-sin(pl.yaw), 0, -cos(pl.yaw))
		var right := Vector3(cos(pl.yaw), 0, -sin(pl.yaw))
		var d := to.normalized()
		pl.move_input = Vector2(d.dot(right), d.dot(fwd)).limit_length(1.0)
		await physics_frame
	pl.move_input = Vector2.ZERO
	return false


func _world_tests2(app: Node) -> void:
	print("== Dunia 3D Fase 3–8: lokasi, misi, dunia hidup, kinerja")
	app.set_player("Ani", 3)
	var total_locs := 0
	for rid in ["matematika", "bahasa", "ipa", "ips"]:
		app.show_world(rid)
		await process_frame
		var w: Node3D = app.world
		var ok: bool = w.locs.size() == 5
		for lid in w.locs:
			ok = ok and w.find_use("loc", lid) != null and w.get_node_or_null("Loc_%s/Zone_visit_%s" % [lid, lid]) != null
			total_locs += 1
		_check(ok, "%s: 5 lokasi dengan papan aktivitas + zona kunjungan" % rid)
		_check(w.item_count() == 5, "%s: 5 benda tersembunyi" % rid)
	_check(total_locs == 20, "total 20 lokasi tambahan di 4 pulau")
	# --- Labirin bisa dilalui sampai tengah (tabrakan dinding nyata)
	app.show_world("matematika")
	await process_frame
	var w: Node3D = app.world
	var maze: Node3D = w.locs.labirin.root
	var path := [Vector3(7.5, 0, -3.9), Vector3(3.9, 0, -3.9), Vector3(-3.9, 0, -3.9), Vector3(-3.9, 0, 3.9), Vector3(1.3, 0, 3.9), Vector3(1.3, 0, 1.3), Vector3(-1.0, 0, 1.0)]
	w.player.place(maze.to_global(path[0]) + Vector3(0, 0.1, 0), 0.0)
	await _steps(3)
	var walked := true
	for pt in path.slice(1):
		walked = walked and await _walk_to(app, maze.to_global(pt))
	_check(walked, "labirin matematika bisa dilalui dari pintu masuk sampai tengah")
	await _steps(4)
	_check(w.focus_label() == "Labirin Matematika", "papan teka-teki di tengah labirin bisa dipakai")
	w.player.place(maze.to_global(Vector3(-3.9, 0, -3.9)) + Vector3(0, 0.1, 0), 0.0)
	await _steps(3)
	var blocked := not await _walk_to(app, maze.to_global(Vector3(-1.3, 0, -1.3)), 150)
	_check(blocked, "dinding labirin tidak bisa ditembus")
	# --- Kunjungan lokasi tercatat
	w.player.place(w.locs.menara.root.global_position + Vector3(0, 0.1, 0) + w.locs.menara.root.global_transform.basis * Vector3(0, 0, 5), 0.0)
	await _steps(6)
	_check((app.p.world.visited.matematika as Dictionary).has("menara"), "masuk area lokasi: kunjungan tercatat")
	# --- Teka-teki lokasi: gagal -> tidak selesai; berhasil -> selesai + misi sekali
	await _go_to(app, "loc", "menara")
	w.interact()
	_check(_dialog_press(app, "Pecahkan teka-teki") and app.screen == "session" and str(app.session.kind) == "lokasi"
		and (app.session.questions as Array).size() == 3, "lokasi: teka-teki 3 soal dari topik wilayah kelas aktif")
	var qtopic := str(app.session.topic)
	_check(app.data.topics.has(qtopic) and str(app.data.topics[qtopic].region) == "matematika" and (app.data.topics[qtopic].grades as Array).has(3.0) or (app.data.topics[qtopic].grades as Array).has(3),
		"topik teka-teki sesuai wilayah & kelas")
	await _play_session(app, false)
	app.go_back()
	_check(app.screen == "world" and not bool(app._loc_status("matematika").menara.done), "teka-teki gagal: lokasi belum selesai")
	var coins0 := int(app.p.coins)
	await _go_to(app, "loc", "menara")
	app.world.interact()
	_dialog_press(app, "Pecahkan teka-teki")
	await _play_session(app, true)
	app.go_back()
	_check(bool(app._loc_status("matematika").menara.done), "teka-teki berhasil: lokasi selesai")
	_check((app.p.world.claimed as Dictionary).has("k3/matematika/lokasi_menara"), "misi lokasi diberi hadiah")
	var coins1 := int(app.p.coins)
	_check(coins1 > coins0, "hadiah koin dari jawaban + misi (%d -> %d)" % [coins0, coins1])
	app._check_missions()
	app.show_world("matematika")
	_check(int(app.p.coins) == coins1, "memuat ulang dunia / cek ulang misi tidak memberi hadiah dua kali")
	await _go_to(app, "loc", "menara")
	app.world.interact()
	_dialog_press(app, "Pecahkan teka-teki")
	await _play_session(app, true)
	var coins_after_answers := int(app.p.coins)
	app.go_back()
	_check(int(app.p.coins) == coins_after_answers, "mengulang teka-teki: hanya koin jawaban, misi tidak dibayar lagi")
	# --- Warga (misi NPC)
	w = app.world
	var vil: Node3D = w.locs.desa_angka.root.get_node("Villager")
	_check(w.life.count("villager") >= 1, "warga desa berjalan berpatroli (dunia hidup)")
	var vpos0 := vil.position
	for i in 240:
		await process_frame
	_check(vil.position.distance_to(vpos0) > 0.3 or w.life.entities.any(func(e): return e.kind == "villager" and float(e.data.get("wait", 0)) > 0), "warga bergerak di antara titik rute")
	w.player.place(vil.global_position + Vector3(0, 0.1, 1.5), 0.0)
	await _steps(4)
	w.interact()
	_check(_dialog_text(app).contains("Pak Hitung") and w.is_talking_to(vil), "bicara dengan warga: warga berhenti dan meminta bantuan")
	_check(_dialog_press(app, "Ya, aku bantu!") and str(app.session.loc) == "desa_angka", "misi warga dimulai")
	await _play_session(app, true)
	app.go_back()
	_check((app.p.world.claimed as Dictionary).has("k3/matematika/lokasi_desa_angka"), "misi warga selesai")
	# --- Benda tersembunyi
	w = app.world
	var before := int(app.p.coins)
	for i in 5:
		var id := "matematika_%d" % i
		var it: Node3D = w.get_node_or_null("Item_" + id)
		if it != null:
			w.player.place(it.global_position - Vector3(0, 0.8, 0), 0.0)
			await _steps(5)
	_check(((app.p.world.items as Dictionary).get("matematika", []) as Array).size() == 5, "5 benda ditemukan dengan berjalan ke tempatnya")
	_check((app.p.world.claimed as Dictionary).has("matematika/benda") and int(app.p.coins) >= before + 20, "misi cari benda selesai (+20 koin)")
	app.show_world("matematika")
	_check(app.world.item_count() == 0, "benda yang sudah diambil tidak muncul lagi")
	# --- Daftar misi & jenisnya
	var ms: Array = app.world_missions()
	var types := {}
	for m in ms:
		types[m.type] = true
		_check(m.has("id") and m.has("name") and m.has("desc") and m.has("goal") and m.has("reward") and m.has("done"), "misi %s punya id/nama/deskripsi/tujuan/hadiah/status" % m.id) if m.id in ["gerbang", "soal_harian"] else null
	_check(types.size() == 7, "7 jenis misi: utama, sampingan, teka-teki, npc, eksplorasi, benda, harian (%s)" % ", ".join(types.keys()))
	app.show_missions()
	_check(app.hud.dialog_open() and _dialog_text(app).contains("Buku Petualangan"), "tombol MISI membuka Buku Petualangan")
	app.hud.close_dialog()
	var today := Time.get_date_string_from_system()
	_check(int((app.p.daily as Dictionary).get(today, [0, 0])[1]) >= 10 and (app.p.world.claimed as Dictionary).has("harian/%s/soal" % today), "misi harian 10 soal selesai dari jawaban hari ini")
	# --- Museum kartu / hewan
	app.show_world("bahasa")
	await _go_to(app, "loc", "perpustakaan")
	app.world.interact()
	_check(_dialog_press(app, "Lihat kartu") and _dialog_text(app).contains("Kartu Pengetahuan"), "perpustakaan alam menampilkan kartu pengetahuan wilayah")
	app.hud.close_dialog()
	# --- Dunia hidup & kinerja
	var lf: Node3D = app.world.life
	_check(lf.count("bird") == 3 and lf.count("animal") <= 3, "profil Seimbang: 3 burung, maks. 3 hewan")
	lf.set_rain(true)
	_check(lf.raining and lf._rain != null and lf._rain.emitting, "cuaca hujan: partikel hujan aktif")
	lf.set_rain(false)
	var f0: float = lf.day_factor
	lf.cycle = 0.8
	lf._sky(0.1)
	_check(lf.day_factor < f0 and lf.is_night(), "siklus siang-malam: senja/malam lebih gelap")
	app.world.player.place(Vector3(0, 0.1, app.world._end_z), 0.0)
	lf._check_t = 0.0
	await process_frame
	await process_frame
	var any_far := false
	for e in lf.entities:
		if e.kind == "villager" and not e.active:
			any_far = true
	_check(any_far, "makhluk jauh dari pemain tidak dianimasikan (aktivasi berdasarkan jarak)")
	app.set_setting("gfx", "hemat")
	app.show_world("ipa")
	_check(app.world.life.count("bird") == 0 and app.world.life.count("animal") <= 2 and app.world.life.rain_amount == 0, "profil Hemat: tanpa burung & hujan, hewan maks. 2")
	app.set_setting("gfx", "seimbang")
	app.toggle_setting("perf")
	app.show_world("ipa")
	_check(app.hud._perf.visible, "info kinerja (FPS/draw call/RAM) bisa dinyalakan")
	app.toggle_setting("perf")
	app.go_back()
	app.set_player("Ani", 1)
	app.show_home()
