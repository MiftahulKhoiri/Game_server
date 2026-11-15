extends SceneTree
## Uji game SD "Petualangan Ilmu — Dunia Enam Pulau" (headless, dari proyek sumber):
## bank soal & pembuat soal, setiap tipe soal, progres belajar lama (skema 1-2), lalu 3.x: data enam pulau,
## aturan buka/pindah pulau, Save Engine skema 3 + migrasi dari 2.x, menu utama, profil petualang, peta,
## berlayar, dunia 3D pulau (gerak, batas pulau, interaksi), pengaturan, simpan & buka ulang.
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
	await _v3_engine_tests()
	await _v3_npc_tests()
	await _v3_app_tests()
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



# --- 3.x Dunia Enam Pulau: engine -----------------------------------------------------------------------------

const SaveEngine := preload("res://games/education_sd/scripts/engine/save_engine.gd")
const WorldEngine := preload("res://games/education_sd/scripts/engine/world_engine.gd")
const NpcEngine := preload("res://games/education_sd/scripts/engine/npc_engine.gd")
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
	_check(bool(w.island("pulau1").available) and not bool(w.island("pulau2").available), "percontohan: Pulau 1 tersedia, Pulau 2–6 segera hadir")
	_check(w.validate({"id": "x"}) != "", "pulau tanpa kolom wajib ditolak")

	print("== 3.x Aturan buka & pindah pulau")
	var p1 := _prof(1)
	_check(w.status("pulau1", p1) == "open" and w.status("pulau2", p1) == "soon", "kelas 1: Pulau 1 terbuka, Pulau 2 segera hadir")
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
	_check(w.start_island(p4) == "pulau1", "percontohan: semua kelas mulai di Pulau 1")

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
	_check(n.npcs.size() == 8 and n.places.size() == 8, "8 penduduk, 8 tempat")
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
	_press(ps, "Grade2")
	_press(ps, "Hero_perempuan")
	_press(ps, "Outfit_warna_biru")
	_check(not ps.preview.rig.is_glb() or ps.preview.rig.long_hair, "pratinjau berganti ke pahlawan perempuan")
	_press(ps, "Save")
	await _frames(2)
	_check(app.screen == "map" and app.modal_open(), "profil disimpan -> peta + cerita pembuka (Kabut Lupa)")
	_check(str(app.p.profile.name) == "Ana" and int(app.p.profile.grade) == 2 and str(app.p.profile.hero) == "perempuan"
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
	_check(not _btn(m, "Sail").visible, "Pulau 2 (segera hadir): tidak ada tombol berlayar")
	_check(not m.sail("pulau2"), "berlayar ke pulau segera hadir ditolak")
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
	_check(w.npcs.size() == 8 and app.npc.npcs.size() == 8, "8 penduduk dengan model berangka")
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
	_check(pages == 3 and str(app.hud._dialog_text.text).contains("Akademi Tunas"), "dialog 3 halaman dengan tombol Lanjut")
	_check(w.npcs[0].talking, "penduduk tetap menghadap pemain di antara halaman")
	app.hud.close_dialog()
	await _frames(30)
	_check(not w.npcs[0].talking, "selesai bicara: penduduk berjalan lagi")
	_check(app.p.world.met.has("pulau1/pak_lurah"), "pertemuan dicatat")
	app.hud.trigger_action()
	await _frames(2)
	_check(str(app.hud._dialog_text.text).contains("Akademi Tunas ada di bukit"), "bicara lagi: kalimat berbeda (tidak mengulang perkenalan)")
	app.hud.close_dialog()
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

	print("== 3.x Berlayar antarpulau (Pulau 2 dibuka sementara untuk uji)")
	app.worlds.island("pulau2").available = true
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
	app.worlds.load_data()
	app.p.world.island = "pulau1"
	app.save()

	print("== 3.x Pengaturan, simpan, buka ulang")
	app.go_back()
	await _frames(2)
	_check(app.screen == "title" and _btn(app.current, "Continue") != null, "peta -> menu utama dengan Lanjutkan Petualangan")
	_press(app.current, "Settings")
	await _frames(2)
	_press(app.current, "gfx_hemat")
	await _frames(2)
	_check(str(app.p.settings.gfx) == "hemat" and app.screen == "settings", "grafis Hemat dipilih")
	var saved := SaveManager.load_progress("education_sd", 3)
	_check(int(saved.get("schema_version", 0)) == 3 and str(saved.data.profile.name) == "Ana" and str(saved.data.settings.gfx) == "hemat",
		"progres tersimpan di skema 3")
	app = await _open()
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
	_check(int(app.p.migrated_from) == 2 and str(app.p.profile.name) == "Budi" and int(app.p.rpg.coins) == 77, "save 2.x dimigrasikan lewat GameManager")
	_check(app.screen == "title" and app.modal_open(), "pemain lama disambut pesan Petualangan Baru")
	_check(int(SaveManager.load_progress("education_sd", 3).get("schema_version", 0)) == 3, "berkas save ditulis ulang dalam skema 3")
	_clear_save()
