extends RefCounted
## Experiment Engine — Laboratorium Eksperimen IPA (murni data, bisa diuji tanpa layar).
## Data: data/experiments.json (dibuat tools/gamepack/make_sd_experiments.py). Tiga jenis percobaan:
##   uji      pilih benda -> tebak -> hasil + alasan; selesai bila semua benda sudah dicoba
##   susun    susun urutan; awalan yang sudah benar dipertahankan saat salah; selesai bila urutan benar
##   kondisi  atur variabel -> hasil; selesai bila sudah mencoba `need` kombinasi berbeda
## Setelah percobaan: penjelasan ilmiah, lalu pertanyaan evaluasi. Tebakan salah TIDAK dihukum: menebak lalu
## melihat hasil adalah cara belajarnya. Hadiah diberikan untuk menyelesaikan percobaan dan menjawab evaluasi.

const PATH := "res://games/education_sd/data/experiments.json"
const MAX_HISTORY := 80

var list: Array = []
var by_id: Dictionary = {}
var errors: Array[String] = []


func load_data(path: String = PATH) -> bool:
	errors.clear()
	list.clear()
	by_id.clear()
	var v = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("experiments")) != TYPE_ARRAY:
		errors.append("experiments.json tidak bisa dibaca")
		return false
	for e in v.experiments:
		var why := validate(e)
		if why == "" and by_id.has(str(e.id)):
			why = "id kembar"
		if why != "":
			errors.append("%s: %s" % [str(e.get("id", "?")) if typeof(e) == TYPE_DICTIONARY else "?", why])
			continue
		list.append(e)
		by_id[str(e.id)] = e
	return errors.is_empty()


## "" bila percobaan sah.
static func validate(e) -> String:
	if typeof(e) != TYPE_DICTIONARY:
		return "bukan objek"
	for f in ["id", "title", "problem", "instruction", "science"]:
		if str(e.get(f, "")).strip_edges() == "":
			return "tanpa " + f
	if typeof(e.get("grades")) != TYPE_ARRAY or (e.grades as Array).is_empty():
		return "tanpa kelas"
	match str(e.get("kind", "")):
		"uji":
			if typeof(e.get("labels")) != TYPE_ARRAY or (e.labels as Array).size() != 2:
				return "uji butuh 2 label"
			if typeof(e.get("items")) != TYPE_ARRAY or (e.items as Array).size() < 2:
				return "benda kurang"
			for it in e.items:
				if not (int(it.get("result", -1)) in [0, 1]) or str(it.get("why", "")) == "" or str(it.get("name", "")) == "":
					return "benda tidak lengkap"
		"susun":
			if typeof(e.get("items")) != TYPE_ARRAY or (e.items as Array).size() < 3 or str(e.get("why", "")) == "":
				return "susunan tidak sah"
			var seen := {}
			for it in e.items:
				seen[str(it)] = true
			if seen.size() != (e.items as Array).size():
				return "bahan kembar"
		"kondisi":
			if typeof(e.get("vars")) != TYPE_ARRAY or (e.vars as Array).is_empty() or typeof(e.get("outcomes")) != TYPE_DICTIONARY:
				return "variabel tidak sah"
			for key in combos(e):
				var o = e.outcomes.get(key)
				if typeof(o) != TYPE_DICTIONARY or str(o.get("result", "")) == "" or str(o.get("why", "")) == "":
					return "hasil kombinasi %s tidak ada" % key
			if int(e.get("need", 0)) < 1 or int(e.need) > combos(e).size():
				return "need tidak sah"
		_:
			return "jenis tidak dikenal"
	if typeof(e.get("check")) != TYPE_ARRAY or (e.check as Array).size() < 2:
		return "pertanyaan evaluasi kurang"
	for q in e.check:
		if str(q.get("q", "")) == "" or str(q.get("explain", "")) == "":
			return "pertanyaan tidak lengkap"
		match str(q.get("type", "")):
			"mc":
				if typeof(q.get("options")) != TYPE_ARRAY or (q.options as Array).size() < 3 or int(q.get("answer", -1)) < 0 \
						or int(q.answer) >= (q.options as Array).size():
					return "pilihan tidak sah"
			"tf":
				if typeof(q.get("answer")) != TYPE_BOOL:
					return "benar/salah tidak sah"
			_:
				return "tipe pertanyaan tidak didukung"
	return ""


## Semua kunci kombinasi percobaan "kondisi", mis. ["0,0", "0,1", ...].
static func combos(e: Dictionary) -> Array:
	var out: Array = [""]
	for v in e.get("vars", []):
		var nxt: Array = []
		for pre in out:
			for i in (v.options as Array).size():
				nxt.append(str(i) if pre == "" else "%s,%d" % [pre, i])
		out = nxt
	return out


static func has_grade(e: Dictionary, grade: int) -> bool:
	for g in e.get("grades", []):
		if int(g) == grade:
			return true
	return false


## Percobaan untuk kelas `grade`, dengan catatan anak: [{id, title, done, plays}].
func for_grade(p: Dictionary, grade: int) -> Array:
	var out: Array = []
	for e in list:
		if has_grade(e, grade):
			var r := rec(p, str(e.id))
			out.append({"id": str(e.id), "title": str(e.title), "done": bool(r.get("done", false)), "plays": int(r.get("plays", 0))})
	return out


static func _key(id: String) -> String:
	return "eksperimen/" + id


static func rec(p: Dictionary, id: String) -> Dictionary:
	return (p.academy as Dictionary).get(_key(id), {})


func start(id: String) -> Dictionary:
	var e: Dictionary = by_id.get(id, {})
	if e.is_empty():
		return {}
	return {"id": id, "kind": str(e.kind), "tested": {}, "guess_ok": 0, "attempts": 0, "placed": [], "tried": {}, "ready": false}


# --- uji ---------------------------------------------------------------------------------------------------------

## Tebak lalu uji satu benda. Hasil: {ok (tebakan tepat), result (0/1), label, why, repeat (sudah pernah dicoba)}.
func test(state: Dictionary, item: int, guess: int) -> Dictionary:
	var e: Dictionary = by_id[state.id]
	if str(e.kind) != "uji" or item < 0 or item >= (e.items as Array).size():
		return {}
	var it: Dictionary = e.items[item]
	var repeat: bool = state.tested.has(item)
	var ok := guess == int(it.result)
	if not repeat:
		state.tested[item] = ok
		state.attempts = int(state.attempts) + 1
		if ok:
			state.guess_ok = int(state.guess_ok) + 1
	state.ready = (state.tested as Dictionary).size() >= (e.items as Array).size()
	return {"ok": ok, "result": int(it.result), "label": str(e.labels[int(it.result)]), "why": str(it.why), "repeat": repeat}


# --- susun -------------------------------------------------------------------------------------------------------

## Pasang satu bahan di posisi berikutnya. Hasil: {ok, placed, done, hint}. Bahan salah tidak dipasang.
func place(state: Dictionary, name: String) -> Dictionary:
	var e: Dictionary = by_id[state.id]
	if str(e.kind) != "susun" or bool(state.ready):
		return {}
	var i := (state.placed as Array).size()
	state.attempts = int(state.attempts) + 1
	if str(e.items[i]) != name:
		return {"ok": false, "placed": state.placed, "done": false,
			"hint": "Belum tepat untuk urutan ke-%d. Pikirkan lagi, lalu coba bahan lain." % (i + 1)}
	(state.placed as Array).append(name)
	state.ready = (state.placed as Array).size() >= (e.items as Array).size()
	return {"ok": true, "placed": state.placed, "done": bool(state.ready), "hint": str(e.why) if bool(state.ready) else ""}


# --- kondisi -----------------------------------------------------------------------------------------------------

## Jalankan satu kombinasi variabel (indeks pilihan tiap variabel). Hasil: {result, why, tried, need, new}.
func run(state: Dictionary, choice: Array) -> Dictionary:
	var e: Dictionary = by_id[state.id]
	if str(e.kind) != "kondisi" or choice.size() != (e.vars as Array).size():
		return {}
	var key := ",".join(PackedStringArray(choice.map(func(x): return str(int(x)))))
	if not (e.outcomes as Dictionary).has(key):
		return {}
	var fresh: bool = not state.tried.has(key)
	state.tried[key] = true
	state.attempts = int(state.attempts) + 1
	state.ready = (state.tried as Dictionary).size() >= int(e.need)
	var o: Dictionary = e.outcomes[key]
	return {"result": str(o.result), "why": str(o.why), "tried": (state.tried as Dictionary).size(), "need": int(e.need), "new": fresh}


# --- selesai -----------------------------------------------------------------------------------------------------

## Catat percobaan selesai + hadiah. check_ok = jawaban evaluasi yang benar sejak percobaan pertama.
## Hadiah: 15 XP + 10 koin untuk menyelesaikan, +5 XP/+3 koin per jawaban evaluasi benar, +10 koin pertama kali.
func finish(p: Dictionary, state: Dictionary, check_ok: int, check_total: int) -> Dictionary:
	if not bool(state.get("ready", false)):
		return {}
	var e: Dictionary = by_id[state.id]
	var k := _key(str(state.id))
	var r: Dictionary = (p.academy as Dictionary).get(k, {"done": false, "plays": 0, "best": 0})
	var first := not bool(r.get("done", false))
	var score := int(round(100.0 * check_ok / maxf(1.0, check_total)))
	r.done = true
	r.plays = int(r.get("plays", 0)) + 1
	r.best = maxi(int(r.get("best", 0)), score)
	p.academy[k] = r
	var xp := 15 + 5 * check_ok
	var coins := 10 + 3 * check_ok + (10 if first else 0)
	p.rpg.xp = int(p.rpg.xp) + xp
	p.rpg.coins = int(p.rpg.coins) + coins
	(p.learning.history as Array).push_front({"at": Time.get_datetime_string_from_system(false, true), "mode": "eksperimen",
		"subject": str(e.title), "topic": "", "grade": int(p.profile.grade), "correct": check_ok, "total": check_total, "score": score})
	p.learning.history = (p.learning.history as Array).slice(0, MAX_HISTORY)
	var msg := "Hebat! Kamu menyelesaikan percobaan dan memahami penjelasannya."
	if check_ok < check_total:
		msg = "Percobaan selesai! Baca lagi penjelasannya, lalu ulangi percobaan kapan saja."
	return {"xp": xp, "coins": coins, "first": first, "score": score, "check_ok": check_ok, "check_total": check_total, "message": msg}


## Jumlah percobaan yang sudah diselesaikan anak (untuk laporan).
func done_count(p: Dictionary) -> int:
	var n := 0
	for e in list:
		if bool(rec(p, str(e.id)).get("done", false)):
			n += 1
	return n
