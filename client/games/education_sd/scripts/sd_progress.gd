extends RefCounted
## Model progres Petualangan Pulau Ilmu (skema 2) + migrasi dari skema 1 (game kuis SD lama).
## Disimpan lewat GameManager.save_progress("education_sd", data, SCHEMA): lokal per game, .bak, dan
## sinkron ke server saat online. Semua fungsi statis dan hanya mengubah Dictionary progres.

const SCHEMA := 2
const MAX_HISTORY := 80
const MAX_SEEN := 30
const MAX_RECENT := 12
const MAX_DAYS := 30


static func default_data() -> Dictionary:
	return {
		"schema": SCHEMA,
		"player": {"name": "", "grade": 1, "avatar": {"outfit": "warna_merah", "hat": "", "acc": ""}},
		"coins": 0,
		"xp": 0,
		"grades": {},
		"topics": {},
		"totals": {"answered": 0, "correct": 0, "wrong": 0, "streak": 0, "best_streak": 0},
		"owned": ["warna_merah", "warna_biru"],
		"cards": [],
		"animals": [],
		"badges": {},
		"history": [],
		"daily": {},
		"minigames": {},
		"settings": {"music": true, "sfx": true, "hero": "laki", "gfx": "seimbang"},
		"world": {"region": "matematika", "chests": {}, "found": {}, "seen_done": {}},
		"seen_intro": {},
	}


## Lengkapi kunci yang hilang (data lama / data dari versi lain) tanpa membuang isi yang ada.
static func ensure(d: Dictionary) -> Dictionary:
	var base := default_data()
	for k in base:
		if not d.has(k) or not _same_kind(d[k], base[k]):
			d[k] = base[k]
	# JSON menyimpan semua angka sebagai float: kembalikan ke int.
	d.coins = int(d.coins)
	d.xp = int(d.xp)
	for k in base.player:
		if not d.player.has(k):
			d.player[k] = base.player[k]
	if typeof(d.player.get("avatar")) != TYPE_DICTIONARY:
		d.player.avatar = base.player.avatar.duplicate()
	d.player.grade = clampi(int(d.player.grade), 1, 6)
	for k in base.totals:
		if not d.totals.has(k):
			d.totals[k] = 0
	for k in base.settings:
		if not d.settings.has(k):
			d.settings[k] = base.settings[k]
	for k in base.world:
		if not d.world.has(k) or not _same_kind(d.world[k], base.world[k]):
			d.world[k] = base.world[k]
	d.schema = SCHEMA
	return d


static func _same_kind(a, b) -> bool:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in num and typeof(b) in num:
		return true
	return typeof(a) == typeof(b)


## Skema 1 (game kuis SD v1.0.0): {levels: {"mapel/kXX": {best, attempts, last}}, history: [...], last_answers}.
## Isi lama disimpan utuh di "legacy"; riwayat dipindah; usaha lama dihargai dengan koin.
static func migrate_v1(old: Dictionary) -> Dictionary:
	var d := default_data()
	d.legacy = old.duplicate(true)
	var passed := 0
	for key in (old.get("levels", {}) as Dictionary):
		if int(old.levels[key].get("best", 0)) >= 70:
			passed += 1
	d.coins = passed * 20
	for h in old.get("history", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		d.history.append({"at": str(h.get("at", "")), "mode": "kuis lama", "subject": str(h.get("subject", "")),
			"topic": str(h.get("level", "")), "grade": 0, "correct": int(h.get("correct", 0)),
			"total": int(h.get("total", 0)), "score": int(h.get("score", 0))})
		d.totals.answered += int(h.get("total", 0))
		d.totals.correct += int(h.get("correct", 0))
	d.totals.wrong = d.totals.answered - d.totals.correct
	d.history = d.history.slice(0, MAX_HISTORY)
	return d


## Ubah data apa pun (skema 1, 2, atau kosong) menjadi skema 2.
static func upgrade(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return default_data()
	if int(d.get("schema", 1)) < 2 and (d.has("levels") or d.has("last_answers") or not d.has("player")):
		return ensure(migrate_v1(d))
	return ensure(d)


static func grade_rec(d: Dictionary, grade: int) -> Dictionary:
	var k := str(grade)
	if not d.grades.has(k):
		d.grades[k] = {"areas": {}, "exams": {}, "quiz": {}}
	return d.grades[k]


static func topic_key(grade: int, topic: String) -> String:
	return "%d/%s" % [grade, topic]


static func topic_stats(d: Dictionary, grade: int, topic: String) -> Dictionary:
	var k := topic_key(grade, topic)
	if not d.topics.has(k):
		d.topics[k] = {"correct": 0, "wrong": 0, "recent": [], "seen": []}
	return d.topics[k]


static func level(d: Dictionary) -> int:
	return int(floor((1.0 + sqrt(1.0 + 8.0 * int(d.xp) / 100.0)) / 2.0))


## XP yang dibutuhkan untuk mencapai level `lv`.
static func xp_for(lv: int) -> int:
	return 100 * lv * (lv - 1) / 2


static func total_stars(d: Dictionary) -> int:
	var s := 0
	for g in d.grades:
		for a in d.grades[g].areas:
			s += int(d.grades[g].areas[a].get("stars", 0))
	return s


## Catat satu jawaban. first_try: benar pada percobaan pertama. Mengembalikan koin yang didapat.
static func record_answer(d: Dictionary, grade: int, q: Dictionary, correct: bool, first_try: bool) -> int:
	var st := topic_stats(d, int(q.get("grade", grade)), str(q.topic))
	if correct and first_try:
		st.correct = int(st.correct) + 1
	else:
		st.wrong = int(st.wrong) + 1
	(st.recent as Array).append(1 if correct and first_try else 0)
	st.recent = (st.recent as Array).slice(-MAX_RECENT)
	var qid := str(q.get("id", ""))
	if qid != "" and not (st.seen as Array).has(qid):
		(st.seen as Array).append(qid)
		st.seen = (st.seen as Array).slice(-MAX_SEEN)
	d.totals.answered = int(d.totals.answered) + 1
	var ok := correct and first_try
	if ok:
		d.totals.correct = int(d.totals.correct) + 1
		d.totals.streak = int(d.totals.streak) + 1
		d.totals.best_streak = maxi(int(d.totals.best_streak), int(d.totals.streak))
		d.xp = int(d.xp) + int(q.get("points", 10))
	else:
		d.totals.wrong = int(d.totals.wrong) + 1
		d.totals.streak = 0
		d.xp = int(d.xp) + 2  # usaha tetap dihargai
	var today := Time.get_date_string_from_system()
	var day: Array = d.daily.get(today, [0, 0])
	day[0] = int(day[0]) + (1 if ok else 0)
	day[1] = int(day[1]) + 1
	d.daily[today] = day
	var keys: Array = (d.daily as Dictionary).keys()
	keys.sort()
	while keys.size() > MAX_DAYS:
		d.daily.erase(keys.pop_front())
	var coins := 3 if ok else (2 if correct else 1)
	d.coins = int(d.coins) + coins
	return coins


static func add_history(d: Dictionary, mode: String, subject: String, topic: String, grade: int, correct: int, total: int) -> void:
	(d.history as Array).push_front({"at": Time.get_datetime_string_from_system(false, true), "mode": mode,
		"subject": subject, "topic": topic, "grade": grade, "correct": correct, "total": total,
		"score": int(round(100.0 * correct / maxf(1.0, total)))})
	d.history = (d.history as Array).slice(0, MAX_HISTORY)


static func stars_for(correct: int, total: int) -> int:
	var r := float(correct) / maxf(1.0, total)
	return 3 if r >= 0.9 else (2 if r >= 0.6 else 1)


## Area petualangan selesai. Mengembalikan {stars, coins, card, new_best}.
static func finish_area(d: Dictionary, grade: int, region: String, topic: Dictionary, correct: int, total: int) -> Dictionary:
	var g := grade_rec(d, grade)
	var key := "%s/%s" % [region, topic.id]
	var rec: Dictionary = g.areas.get(key, {"stars": 0, "done": false, "best": 0})
	var stars := stars_for(correct, total)
	var new_best := stars > int(rec.stars)
	var coins := 5 * stars + (10 if not rec.done else 0)
	rec.stars = maxi(int(rec.stars), stars)
	rec.best = maxi(int(rec.best), int(round(100.0 * correct / maxf(1.0, total))))
	rec.done = true
	g.areas[key] = rec
	d.coins = int(d.coins) + coins
	var card := ""
	if not (d.cards as Array).has(str(topic.id)):
		(d.cards as Array).append(str(topic.id))
		card = str(topic.id)
	return {"stars": stars, "coins": coins, "card": card, "new_best": new_best}


static func area_rec(d: Dictionary, grade: int, region: String, topic_id: String) -> Dictionary:
	return (grade_rec(d, grade).areas as Dictionary).get("%s/%s" % [region, topic_id], {})


## Ujian akhir wilayah. Lulus bila nilai >= 70. Mengembalikan {passed, coins}.
static func finish_exam(d: Dictionary, grade: int, region: String, score: int) -> Dictionary:
	var g := grade_rec(d, grade)
	var rec: Dictionary = g.exams.get(region, {"best": 0, "passed": false, "attempts": 0})
	var passed := score >= 70
	var coins := 10 + (50 if passed and not rec.passed else 0)
	rec.best = maxi(int(rec.best), score)
	rec.attempts = int(rec.attempts) + 1
	rec.passed = bool(rec.passed) or passed
	g.exams[region] = rec
	d.coins = int(d.coins) + coins
	return {"passed": passed, "coins": coins}


static func finish_quiz(d: Dictionary, grade: int, region: String, score: int) -> Dictionary:
	var g := grade_rec(d, grade)
	var rec: Dictionary = g.quiz.get(region, {"best": 0, "last": 0, "attempts": 0})
	var new_best := score > int(rec.best)
	rec.best = maxi(int(rec.best), score)
	rec.last = score
	rec.attempts = int(rec.attempts) + 1
	g.quiz[region] = rec
	var coins := 5 + score / 10
	d.coins = int(d.coins) + coins
	return {"coins": coins, "new_best": new_best}


static func finish_minigame(d: Dictionary, game_id: String, score: int, total: int) -> int:
	var rec: Dictionary = d.minigames.get(game_id, {"best": 0, "plays": 0})
	rec.best = maxi(int(rec.best), score)
	rec.plays = int(rec.plays) + 1
	d.minigames[game_id] = rec
	var coins := 5 + score
	d.coins = int(d.coins) + coins
	d.xp = int(d.xp) + score * 5
	return coins


## Periksa lencana; mengembalikan daftar id lencana BARU.
static func check_badges(d: Dictionary, data_doc: Dictionary, regions: Array) -> Array:
	var got: Array = []
	var c := int(d.totals.correct)
	var done_regions := {}
	var any_area := false
	var exam_pass := false
	for gk in d.grades:
		for a in d.grades[gk].areas:
			if d.grades[gk].areas[a].get("done", false):
				any_area = true
				done_regions[str(a).split("/")[0]] = true
		for r in d.grades[gk].exams:
			if d.grades[gk].exams[r].get("passed", false):
				exam_pass = true
	var quiz100 := false
	for gk in d.grades:
		for r in d.grades[gk].quiz:
			if int(d.grades[gk].quiz[r].get("best", 0)) >= 100:
				quiz100 = true
	var conds := {
		"langkah_pertama": int(d.totals.answered) >= 1,
		"rajin_10": c >= 10,
		"pintar_50": c >= 50,
		"jagoan_100": c >= 100,
		"beruntun_5": int(d.totals.best_streak) >= 5,
		"area_pertama": any_area,
		"empat_wilayah": done_regions.size() >= regions.size() and regions.size() > 0,
		"ujian_lulus": exam_pass,
		"mini_game": not (d.minigames as Dictionary).is_empty(),
		"kolektor": (d.cards as Array).size() >= 10,
		"tak_menyerah": bool(d.get("retried", false)),
		"kuis_100": quiz100,
	}
	for b in data_doc.get("badges", []):
		var id := str(b.id)
		if not d.badges.has(id) and bool(conds.get(id, false)):
			d.badges[id] = Time.get_date_string_from_system()
			got.append(id)
	return got


## Ringkasan laporan belajar. Kesimpulan per materi hanya dibuat bila datanya cukup (>= 5 jawaban).
static func report(d: Dictionary, data) -> Dictionary:
	var subjects := {}
	for r in data.regions:
		subjects[str(r.id)] = {"name": str(r.subject), "correct": 0, "total": 0}
	var mastered: Array = []
	var practice: Array = []
	var little: int = 0
	for key in d.topics:
		var st: Dictionary = d.topics[key]
		var parts := str(key).split("/")
		if parts.size() != 2 or not data.topics.has(parts[1]):
			continue
		var t: Dictionary = data.topics[parts[1]]
		var total := int(st.correct) + int(st.wrong)
		if subjects.has(str(t.region)):
			subjects[t.region].correct += int(st.correct)
			subjects[t.region].total += total
		var recent: Array = st.get("recent", [])
		var label := "%s (kelas %s)" % [str(t.name), parts[0]]
		if recent.size() < 5:
			little += 1
			continue
		var s := 0
		for v in recent:
			s += int(v)
		var rate := float(s) / recent.size()
		if rate >= 0.8:
			mastered.append(label)
		elif rate < 0.6:
			practice.append(label)
	var days: Array = (d.daily as Dictionary).keys()
	days.sort()
	var trend: Array = []
	for day in days.slice(-7):
		trend.append({"day": day, "correct": int(d.daily[day][0]), "total": int(d.daily[day][1])})
	return {"answered": int(d.totals.answered), "correct": int(d.totals.correct), "wrong": int(d.totals.wrong),
		"subjects": subjects, "mastered": mastered, "practice": practice, "little_data": little, "trend": trend,
		"history": (d.history as Array).slice(0, 20)}
