extends RefCounted
## Data Petualangan Pulau Ilmu: memuat dan MEMVALIDASI data/pulau_ilmu.json (dibuat
## tools/gamepack/make_sd_bank.py), lalu memilih soal secara adaptif per topik dan kelas.

const SdGen := preload("res://games/education_sd/scripts/sd_gen.gd")

const PATH := "res://games/education_sd/data/pulau_ilmu.json"
const TYPES := ["mc", "tf", "fill", "match", "order_letters", "order_words", "sort_numbers", "count", "pick_image",
	"classify", "logic"]
const SHAPES := ["lingkaran", "persegi", "persegi_panjang", "segitiga", "bintang", "belah_ketupat", "trapesium",
	"jajar_genjang", "kubus", "balok", "tabung", "kerucut", "bola", "limas", "apel"]

var doc: Dictionary = {}
var regions: Array = []
var topics: Dictionary = {}       # id -> topik
var questions: Array = []         # soal yang lolos validasi
var by_topic_grade: Dictionary = {}  # "topik/kelas" -> [soal]
var errors: Array[String] = []


func load_data(path: String = PATH) -> bool:
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("Data tidak ditemukan: " + path)
		return false
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("Data rusak (bukan JSON objek)")
		return false
	doc = v
	regions = doc.get("regions", [])
	topics.clear()
	for t in doc.get("topics", []):
		topics[str(t.id)] = t
	questions.clear()
	by_topic_grade.clear()
	var seen := {}
	for q in doc.get("questions", []):
		var why := validate_question(q)
		if why == "" and seen.has(str(q.id)):
			why = "ID kembar"
		if why != "":
			errors.append("%s: %s" % [str(q.get("id", "?")), why])
			continue
		seen[str(q.id)] = true
		questions.append(q)
		var key := "%s/%d" % [q.topic, int(q.grade)]
		if not by_topic_grade.has(key):
			by_topic_grade[key] = []
		by_topic_grade[key].append(q)
	return errors.is_empty()


## "" bila soal sah. Dipakai juga untuk soal buatan pembuat soal.
func validate_question(q) -> String:
	if typeof(q) != TYPE_DICTIONARY:
		return "bukan objek"
	if str(q.get("id", "")) == "":
		return "tanpa ID"
	var t := str(q.get("type", ""))
	if not TYPES.has(t):
		return "tipe tidak dikenal: " + t
	if str(q.get("q", "")).strip_edges() == "":
		return "tanpa pertanyaan"
	if str(q.get("explain", "")).strip_edges() == "":
		return "tanpa penjelasan"
	var g := int(q.get("grade", 0))
	if g < 1 or g > 6:
		return "kelas di luar 1–6"
	if not topics.has(str(q.get("topic", ""))):
		return "topik tidak dikenal"
	match t:
		"mc", "logic", "fill", "pick_image":
			var opts = q.get("options")
			if typeof(opts) != TYPE_ARRAY or opts.size() < 2:
				return "pilihan kurang"
			var uniq := {}
			for o in opts:
				if str(o).strip_edges() == "":
					return "pilihan kosong"
				uniq[str(o)] = true
				if t == "pick_image" and not SHAPES.has(str(o)):
					return "gambar tidak dikenal: " + str(o)
			if uniq.size() != opts.size():
				return "pilihan kembar"
			var a := int(q.get("answer", -1))
			if a < 0 or a >= opts.size():
				return "jawaban di luar indeks"
		"tf":
			if typeof(q.get("answer")) != TYPE_BOOL:
				return "jawaban benar/salah tidak sah"
		"match":
			var pairs = q.get("pairs")
			if typeof(pairs) != TYPE_ARRAY or pairs.size() < 2:
				return "pasangan kurang"
			var l := {}
			var r := {}
			for p in pairs:
				if typeof(p) != TYPE_ARRAY or p.size() != 2:
					return "pasangan rusak"
				l[str(p[0])] = true
				r[str(p[1])] = true
			if l.size() != pairs.size() or r.size() != pairs.size():
				return "pasangan kembar"
		"order_letters":
			if str(q.get("word", "")).length() < 3:
				return "kata terlalu pendek"
		"order_words":
			var it = q.get("items")
			if typeof(it) != TYPE_ARRAY or it.size() < 3:
				return "susunan kurang"
		"sort_numbers":
			var n = q.get("numbers")
			if typeof(n) != TYPE_ARRAY or n.size() < 3:
				return "angka kurang"
			var u := {}
			for x in n:
				u[int(x)] = true
			if u.size() != n.size():
				return "angka kembar"
		"count":
			if not SHAPES.has(str(q.get("shape", ""))) or int(q.get("count", 0)) < 1 or int(q.get("count", 0)) > 20:
				return "gambar/jumlah tidak sah"
		"classify":
			var bins = q.get("bins")
			var items = q.get("items")
			if typeof(bins) != TYPE_ARRAY or bins.size() < 2 or typeof(items) != TYPE_ARRAY or items.size() < 3:
				return "kelompok tidak sah"
			for i in items:
				if typeof(i) != TYPE_ARRAY or i.size() != 2 or int(i[1]) < 0 or int(i[1]) >= bins.size():
					return "benda tidak sah"
	return ""


func region(id: String) -> Dictionary:
	for r in regions:
		if str(r.id) == id:
			return r
	return {}


## Topik wilayah `region_id` yang tersedia untuk kelas `grade`, urut sesuai data.
func topics_for(region_id: String, grade: int) -> Array:
	var out: Array = []
	for t in doc.get("topics", []):
		if str(t.region) == region_id and _has_grade(t, grade):
			out.append(t)
	return out


func has_content(topic_id: String, grade: int) -> bool:
	var t: Dictionary = topics.get(topic_id, {})
	return by_topic_grade.has("%s/%d" % [topic_id, grade]) or (t.get("gen", {}) as Dictionary).has(str(grade))


## Kelas terdekat (ke bawah dulu) yang punya soal untuk topik itu; 0 bila tidak ada.
func easier_grade(topic_id: String, grade: int) -> int:
	for g in range(grade - 1, 0, -1):
		if has_content(topic_id, g):
			return g
	return 0


## Pilih `n` soal untuk topik/kelas. stats = statistik topik dari progres ({recent, seen}).
## Adaptif: bila anak sering salah (>= 4 percobaan terakhir, benar < 50%), soal diambil dari kelas lebih
## rendah dengan konsep sama dan tingkat kesulitan rendah. Bila sangat baik (>= 5, benar >= 80%), soal
## sulit didahulukan. Kecepatan menjawab TIDAK dipakai.
func pick(topic_id: String, grade: int, n: int, stats: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var recent: Array = stats.get("recent", [])
	var seen: Array = stats.get("seen", [])
	var mode := "normal"
	if recent.size() >= 4 and _rate(recent.slice(-6)) < 0.5:
		mode = "mudah"
	elif recent.size() >= 5 and _rate(recent.slice(-8)) >= 0.8:
		mode = "tantang"
	var g := grade
	if mode == "mudah":
		var eg := easier_grade(topic_id, grade)
		if eg > 0:
			g = eg
	var pool: Array = (by_topic_grade.get("%s/%d" % [topic_id, g], []) as Array).duplicate()
	if mode == "mudah":
		var easy := pool.filter(func(q): return int(q.get("difficulty", 1)) <= 1)
		if easy.size() >= mini(n, 2):
			pool = easy
	_shuffle(pool, rng)
	# Soal yang belum pernah dilihat lebih dulu.
	pool.sort_custom(func(x, y): return int(seen.has(str(x.id))) < int(seen.has(str(y.id))))
	if mode == "tantang":
		pool.sort_custom(func(x, y): return int(x.get("difficulty", 1)) > int(y.get("difficulty", 1)))
	var out: Array = pool.slice(0, n)
	var specs: Array = (topics.get(topic_id, {}).get("gen", {}) as Dictionary).get(str(g), [])
	var guard := 0
	var used := {}
	for q in out:
		used[str(q.q)] = true
	while out.size() < n and not specs.is_empty() and guard < n * 10:
		guard += 1
		var q := SdGen.make(str(specs[rng.randi_range(0, specs.size() - 1)]), topic_id, g, rng)
		if q.is_empty() or used.has(str(q.q)) or validate_question(q) != "":
			continue
		used[str(q.q)] = true
		out.append(q)
	# Bank kelas ini sedikit dan tanpa pembuat soal: lengkapi dari kelas terdekat topik yang sama (konsep sama),
	# tanpa mengulang soal. Bila tetap kurang, sesi menjadi lebih pendek daripada menampilkan soal kembar.
	if out.size() < n:
		var ids := {}
		for q in out:
			ids[str(q.id)] = true
		for dg in [-1, 1, -2, 2]:
			var extra: Array = (by_topic_grade.get("%s/%d" % [topic_id, g + dg], []) as Array).duplicate()
			_shuffle(extra, rng)
			for q in extra:
				if out.size() >= n:
					break
				if not ids.has(str(q.id)):
					ids[str(q.id)] = true
					out.append(q)
	_shuffle(out, rng)
	return {"questions": out, "mode": mode, "grade": g}


## Soal campuran untuk ujian akhir wilayah / mode kuis: beberapa dari setiap topik kelas itu.
func pick_mixed(region_id: String, grade: int, n: int, progress_topics: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ts := topics_for(region_id, grade)
	var out: Array = []
	if ts.is_empty():
		return out
	var per := ceili(float(n) / ts.size())
	for t in ts:
		var st: Dictionary = progress_topics.get("%d/%s" % [grade, t.id], {})
		var picked: Dictionary = pick(str(t.id), grade, per, {"seen": st.get("seen", [])}, rng)
		out.append_array(picked.questions)
	_shuffle(out, rng)
	return out.slice(0, n)


## JSON menyimpan angka sebagai float; bandingkan sebagai int.
static func _has_grade(t: Dictionary, grade: int) -> bool:
	for g in t.get("grades", []):
		if int(g) == grade:
			return true
	return false


static func _rate(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0
	for v in arr:
		s += int(v)
	return float(s) / arr.size()


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
