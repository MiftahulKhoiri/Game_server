extends RefCounted
## Bank Audit — pemeriksa kualitas bank soal SD (struktur + pedagogis + cakupan).
##
## Melengkapi SdData.validate_question (yang hanya memeriksa struktur satu soal dan dipakai saat game memuat
## data). Modul ini tidak dipakai saat bermain; dipakai uji (sd_test.gd) dan laporan (tests/sd_bank_report.gd).
##
## Dua tingkat temuan:
##  - GALAT      : data pasti rusak/salah (ID kembar, field wajib kosong, kunci hitungan salah, kelas di luar
##                 topik, mata pelajaran tidak cocok, pilihan kembar, ...). Bank yang terbit harus 0 galat.
##  - PERINGATAN : kualitas pedagogis yang perlu ditinjau manusia (cakupan tipis, tanpa kompetensi, penjelasan
##                 terlalu singkat, kalimat terlalu panjang untuk kelasnya, pilihan benar paling panjang, ...).
##                 Peringatan TIDAK berarti soal salah; ini daftar kerja untuk penyempurnaan materi.
##
## Pemeriksa ini tidak bisa memastikan kebenaran fakta non-hitungan atau kesesuaian kurikulum resmi; itu tetap
## harus ditinjau guru.

## Soal statis minimal per (topik, kelas) bila topik itu tidak punya pembuat soal otomatis. Latihan berisi 5 soal.
const MIN_PER_TOPIC_GRADE := 5
## Batas jumlah kata pertanyaan per kelas (di luar soal bacaan "Bacalah: ...").
const MAX_WORDS := {1: 15, 2: 18, 3: 30, 4: 35, 5: 45, 6: 45}
## Field yang wajib ada dan tidak kosong di setiap soal.
const REQUIRED := ["id", "topic", "grade", "subject", "type", "q", "explain", "difficulty"]
const OPTION_TYPES := ["mc", "logic", "fill", "pick_image"]

const KIND_TEXT := {
	# galat
	"data_tidak_lengkap": "data soal tidak lengkap",
	"struktur": "struktur soal tidak sah",
	"id_kembar": "ID soal kembar",
	"topik_tidak_dikenal": "topik tidak dikenal",
	"mapel_tidak_cocok": "mata pelajaran tidak cocok dengan topik",
	"kelas_di_luar_topik": "kelas soal di luar kelas topik",
	"kesulitan_tidak_sah": "tingkat kesulitan bukan 1–3",
	"pilihan_kembar": "pilihan jawaban kembar (beda spasi saja)",
	"kunci_salah": "kunci jawaban hitungan salah",
	# peringatan
	"cakupan_tipis": "soal per topik×kelas terlalu sedikit (tanpa pembuat soal)",
	"tanpa_kompetensi": "belum ada kompetensi yang dilatih",
	"petunjuk_kosong": "kolom petunjuk berisi teks kosong",
	"penjelasan_minim": "penjelasan terlalu singkat",
	"kalimat_panjang": "pertanyaan terlalu panjang untuk kelasnya",
	"kalimat_negatif": "kalimat negatif (bukan/kecuali) di kelas 1–2",
	"petunjuk_panjang": "jawaban benar jauh lebih panjang dari pengecoh",
	"pilihan_semua": "pilihan \"semua benar/salah\"",
	"soal_kembar": "isi soal kembar di topik×kelas yang sama",
	"benar_salah_timpang": "jawaban Benar/Salah tidak seimbang",
	"kesulitan_datar": "hampir semua soal di tingkat kesulitan 1",
}

static var _re_ab: RegEx
static var _re_blank_b: RegEx
static var _re_blank_a: RegEx


## Periksa sekumpulan soal mentah (mis. data.doc.questions). `data` = SdData yang sudah memuat topik.
## Hasil: {errors: [temuan], warnings: [temuan], counts: {jenis: n}, coverage: [{topic, grade, static, gen}],
##         checked: n, arithmetic: n}. Temuan = {level, kind, id, msg}.
static func audit(questions: Array, data) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var ids := {}
	var sigs := {}
	var per_tg := {}
	var arith := 0
	for q in questions:
		var issues := check_question(q, data)
		if typeof(q) == TYPE_DICTIONARY:
			var qid := str(q.get("id", ""))
			if qid != "":
				if ids.has(qid):
					issues.append(_issue("galat", "id_kembar", qid, "dipakai lebih dari sekali"))
				ids[qid] = true
			var tg := "%s/%d" % [str(q.get("topic", "")), int(q.get("grade", 0))]
			per_tg[tg] = int(per_tg.get(tg, 0)) + 1
			var sig := tg + "|" + _signature(q)
			if sigs.has(sig):
				issues.append(_issue("peringatan", "soal_kembar", qid, "isinya sama dengan " + str(sigs[sig])))
			else:
				sigs[sig] = qid
			if arithmetic_key(q) != "":
				arith += 1
		for it in issues:
			(errors if it.level == "galat" else warnings).append(it)
	# Cakupan per (topik, kelas): soal statis + ada/tidaknya pembuat soal.
	var coverage: Array = []
	for tid in data.topics:
		var t: Dictionary = data.topics[tid]
		var gens: Dictionary = t.get("gen", {})
		for g in t.get("grades", []):
			var gi := int(g)
			var n := int(per_tg.get("%s/%d" % [tid, gi], 0))
			var has_gen := gens.has(str(gi))
			coverage.append({"topic": str(tid), "grade": gi, "static": n, "gen": has_gen})
			if not has_gen and n < MIN_PER_TOPIC_GRADE:
				warnings.append(_issue("peringatan", "cakupan_tipis", "%s/%d" % [tid, gi],
					"%d soal (minimal %d)" % [n, MIN_PER_TOPIC_GRADE]))
	warnings.append_array(_subject_checks(questions))
	var counts := {}
	for it in errors + warnings:
		counts[it.kind] = int(counts.get(it.kind, 0)) + 1
	return {"errors": errors, "warnings": warnings, "counts": counts, "coverage": coverage,
		"checked": questions.size(), "arithmetic": arith}


## Temuan untuk satu soal (tanpa pemeriksaan antar-soal seperti ID kembar & cakupan).
static func check_question(q, data) -> Array:
	var out: Array = []
	if typeof(q) != TYPE_DICTIONARY:
		out.append(_issue("galat", "struktur", "?", "bukan objek"))
		return out
	var qid := str(q.get("id", "?"))
	var missing: Array = []
	for f in REQUIRED:
		if not q.has(f) or str(q[f]).strip_edges() == "":
			missing.append(f)
	if not missing.is_empty():
		out.append(_issue("galat", "data_tidak_lengkap", qid, "tanpa " + ", ".join(PackedStringArray(missing))))
	var why: String = data.validate_question(q)
	if why != "":
		out.append(_issue("galat", "struktur", qid, why))
	var t: Dictionary = data.topics.get(str(q.get("topic", "")), {})
	var grade := int(q.get("grade", 0))
	if t.is_empty():
		out.append(_issue("galat", "topik_tidak_dikenal", qid, str(q.get("topic", ""))))
	else:
		if q.has("subject") and str(q.subject) != str(t.get("region", "")):
			out.append(_issue("galat", "mapel_tidak_cocok", qid, "%s, topik milik %s" % [str(q.subject), str(t.get("region", ""))]))
		var in_grade := false
		for g in t.get("grades", []):
			if int(g) == grade:
				in_grade = true
		if not in_grade:
			out.append(_issue("galat", "kelas_di_luar_topik", qid, "kelas %d" % grade))
	if q.has("difficulty"):
		var dv = q.difficulty
		if not (typeof(dv) in [TYPE_INT, TYPE_FLOAT]) or int(dv) != float(dv) or int(dv) < 1 or int(dv) > 3:
			out.append(_issue("galat", "kesulitan_tidak_sah", qid, str(dv)))
	var type := str(q.get("type", ""))
	var opts: Array = q.get("options", []) if typeof(q.get("options")) == TYPE_ARRAY else []
	if type in OPTION_TYPES and opts.size() >= 2:
		var norm := {}
		for o in opts:
			norm[_squash(str(o))] = true  # peka huruf besar: soal huruf kapital membedakan "Adik" dan "adik"
		if norm.size() != opts.size():
			out.append(_issue("galat", "pilihan_kembar", qid, str(opts)))
	var key := arithmetic_key(q)
	if key != "" and type in OPTION_TYPES and opts.size() > int(q.get("answer", -1)) and int(q.get("answer", -1)) >= 0:
		var given := _num_text(str(opts[int(q.answer)]))
		if given != key:
			out.append(_issue("galat", "kunci_salah", qid, "%s → kunci %s, seharusnya %s" % [str(q.q), str(opts[int(q.answer)]), key]))
	# --- Peringatan pedagogis ---
	if str(q.get("competency", "")).strip_edges() == "":
		out.append(_issue("peringatan", "tanpa_kompetensi", qid, ""))
	if q.has("hint") and str(q.hint).strip_edges() == "":
		out.append(_issue("peringatan", "petunjuk_kosong", qid, ""))
	var ex := str(q.get("explain", "")).strip_edges()
	if ex != "" and (_words(ex) < 3 or ex.to_lower() in ["benar.", "salah.", "benar", "salah", "benar!", "salah!"]):
		out.append(_issue("peringatan", "penjelasan_minim", qid, "\"%s\"" % ex))
	var text := str(q.get("q", "")).strip_edges()
	if not text.to_lower().begins_with("bacalah") and MAX_WORDS.has(grade) and _words(text) > int(MAX_WORDS[grade]):
		out.append(_issue("peringatan", "kalimat_panjang", qid, "%d kata (maks %d untuk kelas %d)" % [_words(text), int(MAX_WORDS[grade]), grade]))
	if grade >= 1 and grade <= 2:
		var low := " " + text.to_lower() + " "
		if low.contains(" bukan ") or low.contains("kecuali"):
			out.append(_issue("peringatan", "kalimat_negatif", qid, text))
	if type in ["mc", "logic", "fill"] and opts.size() >= 2:
		var a := int(q.get("answer", -1))
		if a >= 0 and a < opts.size():
			var ca := str(opts[a]).length()
			var longest := 0
			for i in opts.size():
				if i != a:
					longest = maxi(longest, str(opts[i]).length())
			if ca >= 12 and ca > 1.5 * longest:
				out.append(_issue("peringatan", "petunjuk_panjang", qid, "\"%s\" (%d huruf, pengecoh terpanjang %d)" % [str(opts[a]), ca, longest]))
		for o in opts:
			var n := _norm(str(o))
			if n.begins_with("semua ") or n.begins_with("tidak ada yang"):
				out.append(_issue("peringatan", "pilihan_semua", qid, str(o)))
				break
	return out


## Kunci jawaban yang dihitung untuk soal hitungan sederhana, sebagai teks angka tanpa titik ribuan.
## Dikenali: "A op B = …", "A op ___ = C", "___ op B = C" (op: + − - × x : ÷; bilangan boleh negatif dalam
## kurung dan memakai titik ribuan). "" bila soal bukan bentuk itu atau hasil bagi tidak bulat.
static func arithmetic_key(q) -> String:
	if typeof(q) != TYPE_DICTIONARY or not (str(q.get("type", "")) in OPTION_TYPES):
		return ""
	_init_re()
	var text := str(q.get("q", "")).strip_edges()
	var m := _re_ab.search(text)
	if m != null:
		return _calc(_num(m.get_string(1)), m.get_string(2), _num(m.get_string(3)))
	m = _re_blank_b.search(text)  # A op ___ = C  -> B
	if m != null:
		var a := _num(m.get_string(1))
		var c := _num(m.get_string(3))
		match _op(m.get_string(2)):
			"+":
				return str(c - a)
			"-":
				return str(a - c)
			"*":
				return str(c / a) if a != 0 and c % a == 0 else ""
			"/":
				return str(a / c) if c != 0 and a % c == 0 else ""
	m = _re_blank_a.search(text)  # ___ op B = C  -> A
	if m != null:
		var b := _num(m.get_string(2))
		var c := _num(m.get_string(3))
		match _op(m.get_string(1)):
			"+":
				return str(c - b)
			"-":
				return str(c + b)
			"*":
				return str(c / b) if b != 0 and c % b == 0 else ""
			"/":
				return str(c * b)
	return ""


## Ringkasan teks untuk log uji / laporan.
static func summary_text(res: Dictionary, detail := false) -> String:
	var lines: PackedStringArray = []
	lines.append("Bank soal: %d soal diperiksa, %d soal hitungan dicek kuncinya" % [int(res.checked), int(res.arithmetic)])
	lines.append("Galat: %d · Peringatan: %d" % [(res.errors as Array).size(), (res.warnings as Array).size()])
	var kinds: Array = (res.counts as Dictionary).keys()
	kinds.sort()
	for k in kinds:
		lines.append("  %-20s %4d  %s" % [k, int(res.counts[k]), str(KIND_TEXT.get(k, ""))])
	if detail:
		for it in (res.errors as Array) + (res.warnings as Array):
			lines.append("  [%s] %s %s: %s" % [it.level, it.kind, it.id, it.msg])
	return "\n".join(lines)


# --- Pemeriksaan per mata pelajaran ---------------------------------------------------------------------------

static func _subject_checks(questions: Array) -> Array:
	var out: Array = []
	var tf := {}
	var diff := {}
	for q in questions:
		if typeof(q) != TYPE_DICTIONARY:
			continue
		var s := str(q.get("subject", ""))
		if str(q.get("type", "")) == "tf" and typeof(q.get("answer")) == TYPE_BOOL:
			var c: Array = tf.get(s, [0, 0])
			c[0 if q.answer else 1] += 1
			tf[s] = c
		var d: Array = diff.get(s, [0, 0])
		d[0] += 1
		if int(q.get("difficulty", 1)) <= 1:
			d[1] += 1
		diff[s] = d
	for s in tf:
		var c: Array = tf[s]
		var n: int = c[0] + c[1]
		if n >= 6 and mini(c[0], c[1]) < 0.25 * n:
			out.append(_issue("peringatan", "benar_salah_timpang", s, "Benar %d, Salah %d" % [c[0], c[1]]))
	for s in diff:
		var d: Array = diff[s]
		if d[0] >= 10 and d[1] > 0.9 * d[0]:
			out.append(_issue("peringatan", "kesulitan_datar", s, "%d dari %d soal kesulitan 1" % [d[1], d[0]]))
	return out


# --- Bantuan ----------------------------------------------------------------------------------------------------

static func _issue(level: String, kind: String, id: String, msg: String) -> Dictionary:
	return {"level": level, "kind": kind, "id": id, "msg": msg}


static func _norm(s: String) -> String:
	var parts := s.to_lower().strip_edges().split(" ", false)
	return " ".join(parts)


## Spasi dirapikan, huruf besar/kecil dipertahankan.
static func _squash(s: String) -> String:
	return " ".join(s.strip_edges().split(" ", false))


static func _words(s: String) -> int:
	return s.split(" ", false).size()


static func _signature(q: Dictionary) -> String:
	var parts: Array = [_norm(str(q.get("q", "")))]
	for f in ["options", "pairs", "items", "bins", "word", "shape", "count", "answer"]:
		if q.has(f):
			parts.append(JSON.stringify(q[f]))
	return "|".join(PackedStringArray(parts.map(func(x): return str(x))))


static func _init_re() -> void:
	if _re_ab != null:
		return
	var num := "(\\(?[-−]?[0-9][0-9.]*\\)?)"
	var op := "\\s*([+−×x:÷-])\\s*"
	var blank := "(?:_{2,}|…|\\.{3})"
	_re_ab = RegEx.create_from_string("^" + num + op + num + "\\s*=\\s*" + blank + "\\s*$")
	_re_blank_b = RegEx.create_from_string("^" + num + op + blank + "\\s*=\\s*" + num + "\\s*$")
	_re_blank_a = RegEx.create_from_string("^" + blank + op + num + "\\s*=\\s*" + num + "\\s*$")


static func _op(s: String) -> String:
	match s:
		"+":
			return "+"
		"−", "-":
			return "-"
		"×", "x":
			return "*"
		":", "÷":
			return "/"
	return ""


static func _num(s: String) -> int:
	return int(s.replace("(", "").replace(")", "").replace(".", "").replace("−", "-"))


static func _num_text(s: String) -> String:
	var t := s.strip_edges().replace(".", "").replace("−", "-").replace(" ", "")
	return t if t.is_valid_int() else "?"


static func _calc(a: int, op: String, b: int) -> String:
	match _op(op):
		"+":
			return str(a + b)
		"-":
			return str(a - b)
		"*":
			return str(a * b)
		"/":
			return str(a / b) if b != 0 and a % b == 0 else ""
	return ""
