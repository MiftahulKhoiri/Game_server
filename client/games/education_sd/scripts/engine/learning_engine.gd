extends RefCounted
## Learning Engine — belajar di akademi: ruang kelas per mata pelajaran, materi singkat, latihan interaktif,
## penilaian, dan adaptasi kesulitan. Memakai bank soal + pembuat soal yang sudah ada (SdData.pick, adaptif
## dari statistik jawaban — kecepatan menjawab TIDAK dipakai) dan tampilan 11 tipe soal (sd_question.gd).
## Progres disimpan di p.learning (statistik, riwayat) dan p.academy (bintang & penguasaan per materi).
## Murni data: bisa diuji tanpa layar.

const Adaptive := preload("res://games/education_sd/scripts/engine/adaptive.gd")
const LESSONS := "res://games/education_sd/data/lessons.json"
const SESSION := 5
const MAX_RECENT := 12
const MAX_SEEN := 30
const MAX_HISTORY := 80
const MAX_DAYS := 30
## Penguasaan dinilai dari cukup banyak jawaban, bukan satu-dua soal.
const MASTER_MIN := 8
const MASTER_RATE := 0.8
const WEAK_MIN := 6
const WEAK_RATE := 0.5

## Ruang kelas akademi -> wilayah bank soal. Ruang tanpa wilayah = segera dibuka.
const ROOMS := [
	{"id": "matematika", "name": "Ruang Matematika", "subject": "Matematika", "region": "matematika", "color": "#3f7fd8",
		"teacher": "Bu Guru Sinta", "model": "warga_ibu"},
	{"id": "bahasa", "name": "Perpustakaan Bahasa", "subject": "Bahasa Indonesia", "region": "bahasa", "color": "#3fae63",
		"teacher": "Pak Guru Bayu", "model": "warga_bapak"},
	{"id": "ipas_alam", "name": "Laboratorium IPAS", "subject": "IPAS · Alam", "region": "ipa", "color": "#2fb3a6",
		"teacher": "Profesor Kiko", "model": "penyihir"},
	{"id": "ipas_sosial", "name": "Balai Pengetahuan Sosial", "subject": "IPAS · Sosial", "region": "ips", "color": "#e0813d",
		"teacher": "Bu Guru Ratna", "model": "warga_ibu2"},
	{"id": "pancasila", "name": "Aula Pendidikan Pancasila", "subject": "Pendidikan Pancasila", "region": "pancasila", "color": "#c0392b",
		"teacher": "Pak Guru Rahmat", "model": "warga_bapak2"},
	{"id": "seni", "name": "Sanggar Seni", "subject": "Seni", "region": "seni", "color": "#8a6bd8",
		"teacher": "Kak Sekar", "model": "pemanah"},
	{"id": "olahraga", "name": "Lapangan Olahraga", "subject": "PJOK", "region": "pjok", "color": "#d89a12",
		"teacher": "Pak Bima", "model": "ksatria"},
]

var data  # SdData (bank soal)
var lessons: Dictionary = {}
var errors: Array[String] = []


func setup(sd_data) -> bool:
	data = sd_data
	errors.clear()
	var v = JSON.parse_string(FileAccess.get_file_as_string(LESSONS)) if FileAccess.file_exists(LESSONS) else null
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("lessons")) != TYPE_DICTIONARY:
		errors.append("lessons.json tidak bisa dibaca")
		return false
	lessons = v.lessons
	for t in data.topics:
		if not lessons.has(t):
			errors.append("materi untuk topik %s belum ada" % t)
	return errors.is_empty()


static func room(id: String) -> Dictionary:
	for r in ROOMS:
		if str(r.id) == id:
			return r
	return {}


static func band(grade: int) -> String:
	return "1-2" if grade <= 2 else ("3-4" if grade <= 4 else "5-6")


## Materi singkat topik untuk kelas `grade` (pita kelas terdekat bila tidak ada yang persis).
func lesson(topic_id: String, grade: int) -> Dictionary:
	var by: Dictionary = lessons.get(topic_id, {})
	if by.is_empty():
		return {}
	var want := band(grade)
	if by.has(want):
		return by[want]
	var order := ["1-2", "3-4", "5-6"]
	var i := order.find(want)
	for d in [-1, 1, -2, 2]:
		var j: int = i + d
		if j >= 0 and j < order.size() and by.has(order[j]):
			return by[order[j]]
	return by.values()[0]


## Topik yang bisa dipelajari di ruang `room_id` untuk kelas `grade`, dengan status kemajuan.
func topics(room_id: String, grade: int, p: Dictionary) -> Array:
	var r := room(room_id)
	var out: Array = []
	if str(r.get("region", "")) == "":
		return out
	for t in data.topics_for(str(r.region), grade):
		if not data.has_content(str(t.id), grade) and data.easier_grade(str(t.id), grade) == 0:
			continue
		var rec := topic_rec(p, grade, str(t.id))
		out.append({"id": str(t.id), "name": str(t.name), "stars": int(rec.get("stars", 0)), "status": status(p, grade, str(t.id)),
			"sessions": int(rec.get("sessions", 0))})
	return out


static func _key(grade: int, topic_id: String) -> String:
	return "%d/%s" % [grade, topic_id]


static func topic_rec(p: Dictionary, grade: int, topic_id: String) -> Dictionary:
	return (p.academy as Dictionary).get(_key(grade, topic_id), {})


static func stats(p: Dictionary, grade: int, topic_id: String) -> Dictionary:
	var k := _key(grade, topic_id)
	if not p.learning.topics.has(k):
		p.learning.topics[k] = {"correct": 0, "wrong": 0, "recent": [], "recent_own": [], "seen": []}
	return p.learning.topics[k]


static func _rate(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0
	for v in arr:
		s += int(v)
	return float(s) / arr.size()


## "baru" | "belajar" | "perlu_latihan" | "kuasai" — dari cukup banyak jawaban terakhir.
## Memakai recent_own: hanya jawaban atas soal KELAS ITU SENDIRI, sehingga soal kelas lebih rendah (mode "mudah")
## tidak membuat materi kelas ini tampak dikuasai. Data lama tanpa recent_own memakai recent seperti dulu.
static func status(p: Dictionary, grade: int, topic_id: String) -> String:
	var st: Dictionary = (p.learning.topics as Dictionary).get(_key(grade, topic_id), {})
	var recent: Array = st.get("recent_own", st.get("recent", []))
	var n := int(st.get("correct", 0)) + int(st.get("wrong", 0))
	if n == 0:
		return "baru"
	if recent.size() >= MASTER_MIN and _rate(recent.slice(-10)) >= MASTER_RATE:
		return "kuasai"
	if recent.size() >= WEAK_MIN and _rate(recent.slice(-8)) < WEAK_RATE:
		return "perlu_latihan"
	return "belajar"


const STATUS_TEXT := {"baru": "Belum dipelajari", "belajar": "Sedang dipelajari", "perlu_latihan": "Perlu latihan lagi",
	"kuasai": "Sudah dikuasai"}


## Mulai latihan: pilih soal adaptif. Mengembalikan sesi {topic, grade, questions, mode, i, correct, ...}.
## Keputusan adaptif (Adaptive.decide) disimpan ke statistik topik lalu dipakai memilih soal.
func start(p: Dictionary, topic_id: String, grade: int, rng: RandomNumberGenerator, n := SESSION) -> Dictionary:
	var st := stats(p, grade, topic_id)
	Adaptive.ensure(st)
	var dec := Adaptive.decide(st)
	Adaptive.apply(st, dec)
	var picked: Dictionary = data.pick(topic_id, grade, n, st, rng, dec)
	return {"topic": topic_id, "grade": grade, "questions": picked.questions, "mode": str(picked.mode),
		"q_grade": int(picked.grade), "level": int(dec.level), "changed": bool(dec.changed), "reason": str(dec.reason),
		"tip": Adaptive.tip(st), "i": 0, "correct": 0, "first_try": 0, "xp": 0, "coins": 0, "answers": []}


## Latihan penguatan: pilih topik ruang `room_id` dengan bobot — topik yang perlu dilatih lebih sering muncul
## (perlu latihan 4, sedang dipelajari 3, belum dipelajari 2, sudah dikuasai 1). "" bila ruang tanpa topik.
func pick_topic(p: Dictionary, room_id: String, grade: int, rng: RandomNumberGenerator) -> String:
	var ts := topics(room_id, grade, p)
	var w: Array = ts.map(func(t): return int(Adaptive.TOPIC_WEIGHT.get(str(t.status), 2)))
	var i := Adaptive.pick_weighted(ts, w, rng)
	return str(ts[i].id) if i >= 0 else ""


static func adapt_note(session: Dictionary) -> String:
	var note := ""
	match str(session.get("mode", "normal")):
		"mudah":
			note = "Soal dibuat sedikit lebih mudah dulu, supaya kamu makin paham."
		"tantang":
			note = "Kamu hebat! Soal kali ini lebih menantang, ada satu soal pengayaan."
		_:
			if bool(session.get("changed", false)) and int(session.get("level", 1)) > 1:
				note = "Kamu makin lancar! Soal dibuat sedikit lebih menantang."
	var tip := str(session.get("tip", ""))
	if tip != "":
		note = (note + "\n" if note != "" else "") + "Saran: " + tip
	return note


## Catat satu jawaban. correct = akhirnya benar; first_try = benar tanpa salah. Usaha tetap dihargai.
## first_wrong = jawaban salah PERTAMA anak (untuk mengenali jenis kesalahan); "" bila tidak ada.
static func answer(p: Dictionary, session: Dictionary, q: Dictionary, correct: bool, first_try: bool, first_wrong := "") -> Dictionary:
	var grade := int(session.grade)
	var st := stats(p, grade, str(session.topic))
	var ok := correct and first_try
	if ok:
		st.correct = int(st.correct) + 1
	else:
		st.wrong = int(st.wrong) + 1
	# Data lama (sebelum recent_own ada): kelas soal tidak tercatat, jadi riwayat lama dianggap kelas ini.
	if not st.has("recent_own"):
		st["recent_own"] = (st.recent as Array).duplicate()
	# recent = semua jawaban di sesi kelas ini (untuk adaptasi: kapan soal dipermudah/diperberat).
	(st.recent as Array).append(1 if ok else 0)
	st.recent = (st.recent as Array).slice(-MAX_RECENT)
	# recent_own = hanya soal yang memang kelas ini (untuk status penguasaan & laporan).
	if int(q.get("grade", grade)) == grade:
		(st.recent_own as Array).append(1 if ok else 0)
		st.recent_own = (st.recent_own as Array).slice(-MAX_RECENT)
	Adaptive.record(st, q, ok, first_wrong)
	var qid := str(q.get("id", ""))
	if qid != "" and not (st.seen as Array).has(qid):
		(st.seen as Array).append(qid)
		st.seen = (st.seen as Array).slice(-MAX_SEEN)
	var t: Dictionary = p.learning.totals
	t.answered = int(t.answered) + 1
	if ok:
		t.correct = int(t.correct) + 1
		t.streak = int(t.streak) + 1
		t.best_streak = maxi(int(t.best_streak), int(t.streak))
	else:
		t.wrong = int(t.wrong) + 1
		t.streak = 0
	var xp := int(q.get("points", 10)) if ok else (5 if correct else 2)
	var coins := 3 if ok else (2 if correct else 1)
	p.rpg.xp = int(p.rpg.xp) + xp
	p.rpg.coins = int(p.rpg.coins) + coins
	var today := Time.get_date_string_from_system()
	var day: Array = (p.learning.daily as Dictionary).get(today, [0, 0])
	day[0] = int(day[0]) + (1 if ok else 0)
	day[1] = int(day[1]) + 1
	p.learning.daily[today] = day
	var keys: Array = (p.learning.daily as Dictionary).keys()
	keys.sort()
	while keys.size() > MAX_DAYS:
		p.learning.daily.erase(keys.pop_front())
	session.i = int(session.i) + 1
	session.correct = int(session.correct) + (1 if correct else 0)
	session.first_try = int(session.first_try) + (1 if ok else 0)
	session.xp = int(session.xp) + xp
	session.coins = int(session.coins) + coins
	(session.answers as Array).append({"id": qid, "correct": correct, "first_try": first_try})
	return {"xp": xp, "coins": coins}


static func stars_for(first_try: int, total: int) -> int:
	var r := float(first_try) / maxf(1.0, total)
	return 3 if r >= 0.9 else (2 if r >= 0.6 else 1)


## Latihan selesai: bintang (benar tanpa salah), bonus pertama kali, riwayat, status penguasaan.
static func finish(p: Dictionary, session: Dictionary, subject: String) -> Dictionary:
	var grade := int(session.grade)
	var total := (session.questions as Array).size()
	var stars := stars_for(int(session.first_try), total)
	var k := _key(grade, str(session.topic))
	var rec: Dictionary = (p.academy as Dictionary).get(k, {"stars": 0, "best": 0, "sessions": 0})
	var first := int(rec.get("sessions", 0)) == 0
	var new_best := stars > int(rec.stars)
	var bonus := 5 * stars + (10 if first else 0)
	rec.stars = maxi(int(rec.stars), stars)
	rec.best = maxi(int(rec.best), int(round(100.0 * int(session.first_try) / maxf(1.0, total))))
	rec.sessions = int(rec.sessions) + 1
	p.academy[k] = rec
	p.rpg.coins = int(p.rpg.coins) + bonus
	(p.learning.history as Array).push_front({"at": Time.get_datetime_string_from_system(false, true), "mode": "akademi",
		"subject": subject, "topic": str(session.topic), "grade": grade, "correct": int(session.first_try), "total": total,
		"score": int(round(100.0 * int(session.first_try) / maxf(1.0, total)))})
	p.learning.history = (p.learning.history as Array).slice(0, MAX_HISTORY)
	var st := status(p, grade, str(session.topic))
	return {"stars": stars, "new_best": new_best, "first": first, "bonus": bonus, "xp": int(session.xp),
		"coins": int(session.coins) + bonus, "correct": int(session.correct), "first_try": int(session.first_try),
		"total": total, "status": st, "message": message(int(session.first_try), total, st)}


## Kalimat positif untuk anak (dan orang tua): menghargai usaha, bukan hanya jawaban benar.
static func message(first_try: int, total: int, st: String) -> String:
	if st == "kuasai":
		return "Luar biasa! Kamu sudah menguasai materi ini."
	var r := float(first_try) / maxf(1.0, total)
	if first_try >= total and total > 0:
		return "Sempurna! Semua benar sejak percobaan pertama."
	if r >= 0.9:
		return "Hebat sekali! Hampir semua benar sejak percobaan pertama."
	if r >= 0.6:
		return "Bagus! Kamu makin paham. Latihan sekali lagi supaya makin mahir."
	return "Terima kasih sudah berusaha! Baca lagi materinya, lalu coba latihan sekali lagi. Pasti bisa!"


## Ringkasan per ruang (rapor kecil): {room_id: {stars, max, mastered, topics}}
func room_summary(p: Dictionary, grade: int) -> Dictionary:
	var out := {}
	for r in ROOMS:
		if str(r.region) == "":
			continue
		var ts := topics(str(r.id), grade, p)
		var s := 0
		var m := 0
		for t in ts:
			s += int(t.stars)
			if str(t.status) == "kuasai":
				m += 1
		out[str(r.id)] = {"stars": s, "max": ts.size() * 3, "mastered": m, "topics": ts.size()}
	return out


# --- Ujian ruang kelas (Tahap 7) -----------------------------------------------------------------------------------

const EXAM_N := 10
const EXAM_PASS := 70


static func _exam_key(grade: int, room_id: String) -> String:
	return "ujian/%d/%s" % [grade, room_id]


static func exam_rec(p: Dictionary, grade: int, room_id: String) -> Dictionary:
	return (p.academy as Dictionary).get(_exam_key(grade, room_id), {})


## Ujian: 10 soal campuran dari semua materi ruang ini untuk kelas `grade` (tanpa petunjuk).
func exam_start(p: Dictionary, room_id: String, grade: int, rng: RandomNumberGenerator) -> Dictionary:
	var r := room(room_id)
	var qs: Array = data.pick_mixed(str(r.get("region", "")), grade, EXAM_N, p.learning.topics, rng)
	return {"exam": true, "room": room_id, "topic": "", "grade": grade, "questions": qs, "mode": "ujian", "q_grade": grade, "i": 0,
		"correct": 0, "first_try": 0, "xp": 0, "coins": 0, "answers": [], "wrong_topics": {}}


static func exam_answer(p: Dictionary, session: Dictionary, q: Dictionary, correct: bool) -> void:
	session.topic = str(q.get("topic", ""))
	answer(p, session, q, correct, correct)
	if not correct:
		session.wrong_topics[session.topic] = int(session.wrong_topics.get(session.topic, 0)) + 1


## Nilai ujian (0–100). Lulus >= 70. Lulus pertama kali: 50 koin. Saran materi untuk dilatih lagi.
func exam_finish(p: Dictionary, session: Dictionary) -> Dictionary:
	var total := (session.questions as Array).size()
	var score := int(round(100.0 * int(session.correct) / maxf(1.0, total)))
	var k := _exam_key(int(session.grade), str(session.room))
	var rec: Dictionary = (p.academy as Dictionary).get(k, {"best": 0, "passed": false, "attempts": 0})
	var passed := score >= EXAM_PASS
	var first_pass := passed and not bool(rec.passed)
	rec.best = maxi(int(rec.best), score)
	rec.passed = bool(rec.passed) or passed
	rec.attempts = int(rec.attempts) + 1
	p.academy[k] = rec
	var bonus := 50 if first_pass else 0
	p.rpg.coins = int(p.rpg.coins) + bonus
	var practice: Array = []
	for t in session.wrong_topics:
		practice.append(str(data.topics.get(t, {}).get("name", t)))
	(p.learning.history as Array).push_front({"at": Time.get_datetime_string_from_system(false, true), "mode": "ujian",
		"subject": str(room(str(session.room)).get("subject", "")), "topic": "", "grade": int(session.grade), "correct": int(session.correct),
		"total": total, "score": score})
	p.learning.history = (p.learning.history as Array).slice(0, MAX_HISTORY)
	var msg := "Nilaimu %d. Sedikit lagi! Latih lagi materinya, lalu coba ujian lagi." % score
	if passed:
		msg = "Selamat! Kamu lulus ujian %s dengan nilai %d." % [str(room(str(session.room)).get("name", "")), score]
	return {"score": score, "passed": passed, "first_pass": first_pass, "bonus": bonus, "practice": practice, "message": msg,
		"correct": int(session.correct), "total": total, "xp": int(session.xp), "coins": int(session.coins) + bonus}


# --- Laporan belajar (untuk anak, orang tua, guru) ------------------------------------------------------------------

## Ringkasan belajar: per mata pelajaran (akurasi, materi dikuasai/perlu latihan, ujian), aktivitas 7 hari,
## riwayat terakhir, dan kesimpulan dengan bahasa positif. Hanya menyimpulkan bila jawaban cukup banyak.
func report(p: Dictionary) -> Dictionary:
	var grade := int(p.profile.grade)
	var rooms_out: Array = []
	var best := ""
	var best_rate := -1.0
	var weak := ""
	var weak_rate := 2.0
	for r in ROOMS:
		var region := str(r.get("region", ""))
		if region == "":
			continue
		var c := 0
		var w := 0
		var mastered: Array = []
		var practice: Array = []
		for key in (p.learning.topics as Dictionary):
			var parts := str(key).split("/")
			if parts.size() != 2:
				continue
			var t: Dictionary = data.topics.get(parts[1], {})
			if str(t.get("region", "")) != region:
				continue
			var st: Dictionary = p.learning.topics[key]
			c += int(st.get("correct", 0))
			w += int(st.get("wrong", 0))
			match status(p, int(parts[0]), parts[1]):
				"kuasai":
					mastered.append(str(t.name))
				"perlu_latihan":
					practice.append(str(t.name))
		var n := c + w
		var rate := float(c) / n if n > 0 else 0.0
		var ex := exam_rec(p, grade, str(r.id))
		rooms_out.append({"id": str(r.id), "name": str(r.subject), "answered": n, "rate": rate, "mastered": mastered, "practice": practice,
			"exam": ex, "enough": n >= 5})
		if n >= 5 and rate > best_rate:
			best_rate = rate
			best = str(r.subject)
		if n >= 5 and rate < weak_rate:
			weak_rate = rate
			weak = str(r.subject)
	var days: Array = []
	var keys: Array = (p.learning.daily as Dictionary).keys()
	keys.sort()
	for k in keys.slice(-7):
		days.append({"date": str(k), "correct": int(p.learning.daily[k][0]), "total": int(p.learning.daily[k][1])})
	var t: Dictionary = p.learning.totals
	var summary := ""
	if int(t.answered) < 10:
		summary = "%s baru mulai belajar. Ayo kerjakan lebih banyak latihan supaya kemajuannya terlihat!" % str(p.profile.name)
	else:
		summary = "%s sudah menjawab %d soal dengan %d%% benar sejak percobaan pertama." % [str(p.profile.name), int(t.answered),
			int(round(100.0 * int(t.correct) / maxf(1.0, int(t.answered))))]
		if best != "":
			summary += " Paling kuat di %s." % best
		if weak != "" and weak != best:
			summary += " %s bisa dilatih lagi supaya makin mahir." % weak
	return {"name": str(p.profile.name), "grade": grade, "answered": int(t.answered), "correct": int(t.correct), "best_streak": int(t.best_streak),
		"rooms": rooms_out, "days": days, "history": (p.learning.history as Array).slice(0, 6), "summary": summary}
