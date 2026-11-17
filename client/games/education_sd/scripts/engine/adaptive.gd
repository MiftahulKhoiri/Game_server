extends RefCounted
## Adaptive — aturan pembelajaran adaptif Petualangan Ilmu SD. Murni data (tanpa layar), transparan, dan diuji
## di sd_test.gd. Learning Engine memanggil decide()/apply() saat latihan dimulai dan record() saat menjawab.
##
## Data per (kelas, topik) di p.learning.topics["kelas/topik"]:
##   recent      1/0 semua jawaban terakhir (maks 12)                      — dipakai Learning Engine
##   recent_own  1/0 jawaban atas soal kelas itu sendiri (penguasaan)      — dipakai Learning Engine
##   level       tingkat kesulitan sasaran di kelas itu: 1, 2, atau 3 (bawaan 1)
##   at_level    1/0 jawaban sejak level/mode terakhir berubah (maks 12)
##   mode        "normal" | "mudah" (soal kelas lebih rendah) | "tantang" (+ soal pengayaan)
##   mistakes    kesalahan pertama terakhir {id, given, kind} (maks 10)
## Kecepatan menjawab TIDAK dipakai.
##
## ATURAN — diperiksa berurutan, setiap aturan menyebut jumlah data minimalnya:
##   A. Sedang mode "mudah": setelah >= 5 jawaban dan >= 3 dari 5 terakhir benar -> kembali ke soal kelasnya
##      sendiri di level 1. Selain itu tetap "mudah".
##   B. Kurang dari 5 jawaban sejak perubahan terakhir -> tidak ada perubahan ("data belum cukup").
##   C. Level 3, >= 8 jawaban, >= 85% dari 8 terakhir benar -> mode "tantang": soal sulit + 1 soal pengayaan
##      dari kelas berikutnya (tidak dihitung untuk penguasaan kelas ini).
##   D. >= 5 jawaban, >= 4 dari 5 terakhir benar -> level naik 1 (maksimal 3). Naik satu langkah, tidak melompat.
##   E. Level > 1, >= 6 jawaban, < 40% dari 6 terakhir benar -> level turun 1; KELAS tetap.
##   F. Level 1, >= 8 jawaban, < 40% dari 8 terakhir benar -> mode "mudah": soal kelas lebih rendah, konsep sama.
##   Jadi satu–tiga jawaban salah tidak pernah menurunkan kelas; turun kelas butuh minimal 8 jawaban di level 1.

const SdGen := preload("res://games/education_sd/scripts/sd_gen.gd")

const MAX_HIST := 12
const MAX_MISTAKES := 10
const MIN_DATA := 5
const UP_RATE := 0.8            # >= 4 dari 5
const DOWN_N := 6
const DOWN_RATE := 0.4          # < 40% (paling banyak 2 dari 6)
const DROP_N := 8               # turun kelas butuh minimal 8 jawaban
const DROP_RATE := 0.4          # < 40% (paling banyak 3 dari 8)
const TANTANG_N := 8
const TANTANG_RATE := 0.85      # >= 7 dari 8
const RECOVER_RATE := 0.6       # >= 3 dari 5 untuk keluar dari mode mudah

## Jenis kesalahan dan saran singkat untuk anak (bahasa positif).
const TIPS := {
	"nilai_tempat": "Perhatikan nilai tempat: jangan lupa menyimpan atau meminjam puluhan dan ratusan.",
	"operasi_tertukar": "Lihat tanda hitungnya dulu: tambah, kurang, kali, atau bagi?",
	"hitung_meleset": "Hampir benar! Hitung sekali lagi pelan-pelan, boleh pakai coretan.",
	"hitung_lain": "Coba kerjakan langkah demi langkah di kertas coretan.",
	"benar_salah": "Baca seluruh kalimat dengan teliti; satu kata bisa membuat pernyataan menjadi salah.",
	"konsep": "Baca lagi materi singkatnya, lalu coba latihan sekali lagi.",
}
const MIN_SAME_ERROR := 2  # jenis kesalahan baru disebut bila muncul minimal 2 kali


## Lengkapi field adaptif pada statistik lama tanpa membuang isinya.
static func ensure(st: Dictionary) -> void:
	if not st.has("level"):
		st["level"] = 1
	if not st.has("mode"):
		st["mode"] = "normal"
	if not st.has("at_level"):
		st["at_level"] = (st.get("recent", []) as Array).duplicate()  # save lama: riwayat dipakai sebagai awal
	if not st.has("mistakes"):
		st["mistakes"] = []


## Keputusan untuk latihan berikutnya: {mode, level, changed, reason}. Tidak mengubah st.
static func decide(st: Dictionary) -> Dictionary:
	var level := clampi(int(st.get("level", 1)), 1, 3)
	var mode := str(st.get("mode", "normal"))
	var h: Array = st.get("at_level", st.get("recent", []))
	var n := h.size()
	if mode == "mudah":
		if n >= MIN_DATA and _rate(h.slice(-5)) >= RECOVER_RATE:
			return _d("normal", 1, true, "sudah lancar di soal yang lebih mudah: kembali ke soal kelasnya, level 1")
		return _d("mudah", 1, false, "masih berlatih dengan soal yang lebih mudah")
	if n < MIN_DATA:
		return _d("normal", level, false, "data belum cukup (%d dari %d jawaban)" % [n, MIN_DATA])
	if level == 3 and n >= TANTANG_N and _rate(h.slice(-TANTANG_N)) >= TANTANG_RATE:
		return _d("tantang", 3, mode != "tantang", "sangat lancar di level 3: tantangan + soal pengayaan")
	if level < 3 and _rate(h.slice(-5)) >= UP_RATE:
		return _d("normal", level + 1, true, "4 dari 5 jawaban terakhir benar: kesulitan naik ke level %d" % (level + 1))
	if level > 1 and n >= DOWN_N and _rate(h.slice(-DOWN_N)) < DOWN_RATE:
		return _d("normal", level - 1, true, "sering salah di level %d: kesulitan turun ke level %d (kelas tetap)" % [level, level - 1])
	if level == 1 and n >= DROP_N and _rate(h.slice(-DROP_N)) < DROP_RATE:
		return _d("mudah", 1, true, "sering salah di level 1 (%d jawaban): soal kelas lebih rendah dulu" % DROP_N)
	if mode == "tantang" and _rate(h.slice(-5)) < UP_RATE:
		return _d("normal", 3, true, "kembali ke soal level 3 biasa")
	return _d(mode, level, false, "tetap")


## Simpan keputusan ke st. Riwayat level dikosongkan bila level/mode berubah, agar keputusan berikutnya
## memakai jawaban baru saja (tidak naik/turun dua kali dari data yang sama).
static func apply(st: Dictionary, dec: Dictionary) -> void:
	ensure(st)
	st.level = int(dec.level)
	st.mode = str(dec.mode)
	if bool(dec.changed):
		st.at_level = []


## Catat satu jawaban: hasil di level ini dan (bila salah) jenis kesalahannya.
static func record(st: Dictionary, q: Dictionary, ok: bool, first_wrong: String) -> void:
	ensure(st)
	(st.at_level as Array).append(1 if ok else 0)
	st.at_level = (st.at_level as Array).slice(-MAX_HIST)
	if not ok:
		var kind := error_kind(q, first_wrong)
		(st.mistakes as Array).append({"id": str(q.get("id", "")), "given": first_wrong.substr(0, 60), "kind": kind})
		st.mistakes = (st.mistakes as Array).slice(-MAX_MISTAKES)


## Jenis kesalahan dari jawaban salah pertama. Hitungan sederhana dikenali dari bentuk "A op B = …".
static func error_kind(q: Dictionary, given: String) -> String:
	var t := str(q.get("type", ""))
	if t == "tf":
		return "benar_salah"
	var parts := _arith(str(q.get("q", "")))
	var g := given.strip_edges().replace(".", "").replace("−", "-")
	if parts.is_empty() or not g.is_valid_int():
		return "konsep"
	var a: int = parts[0]
	var op: String = parts[1]
	var b: int = parts[2]
	var c: Variant = _calc(a, op, b)
	if c == null:
		return "konsep"
	var gi := int(g)
	var others := []
	for o in ["+", "-", "*", "/"]:
		if o != op:
			var v: Variant = _calc(a, o, b)
			if v != null:
				others.append(int(v))
	if others.has(gi) or (op == "+" and gi == absi(a - b)):
		return "operasi_tertukar"
	# Lupa menyimpan (penjumlahan) / meminjam dengan "angka besar dikurang angka kecil" (pengurangan).
	if op == "+" and SdGen._carry(a, b) != 0 and gi == int(c) - SdGen._carry(a, b):
		return "nilai_tempat"
	if op == "-" and SdGen._borrow(a, b) != 0 and gi == int(c) + SdGen._borrow(a, b):
		return "nilai_tempat"
	var diff := absi(gi - int(c))
	if absi(int(c)) >= 10 and diff in [10, 100, 1000, 10000]:
		return "nilai_tempat"
	if diff <= 2:
		return "hitung_meleset"
	return "hitung_lain"


## Jenis kesalahan yang paling sering dari beberapa kesalahan terakhir; "" bila belum cukup data.
static func main_error(st: Dictionary) -> String:
	var count := {}
	for m in st.get("mistakes", []).slice(-6):
		count[str(m.kind)] = int(count.get(str(m.kind), 0)) + 1
	var best := ""
	var bn := 0
	for k in count:
		if int(count[k]) > bn:
			best = str(k)
			bn = int(count[k])
	return best if bn >= MIN_SAME_ERROR else ""


static func tip(st: Dictionary) -> String:
	return str(TIPS.get(main_error(st), ""))


## Bobot topik untuk latihan penguatan (Jurus Ilmu dsb.): topik yang perlu dilatih lebih sering muncul.
const TOPIC_WEIGHT := {"perlu_latihan": 4, "belajar": 3, "baru": 2, "kuasai": 1}


static func pick_weighted(items: Array, weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	if items.is_empty() or total <= 0:
		return -1
	var r := rng.randi_range(1, total)
	for i in items.size():
		r -= int(weights[i])
		if r <= 0:
			return i
	return items.size() - 1


# --- Bantuan ----------------------------------------------------------------------------------------------------

static func _d(mode: String, level: int, changed: bool, reason: String) -> Dictionary:
	return {"mode": mode, "level": level, "changed": changed, "reason": reason}


static func _rate(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0
	for v in arr:
		s += int(v)
	return float(s) / arr.size()


static var _re: RegEx


static func _arith(text: String) -> Array:
	if _re == null:
		_re = RegEx.create_from_string("^\\s*\\(?([-−]?[0-9][0-9.]*)\\)?\\s*([+−×x:÷-])\\s*\\(?([-−]?[0-9][0-9.]*)\\)?\\s*=\\s*(?:…|_{2,}|\\.{3})\\s*$")
	var m := _re.search(text)
	if m == null:
		return []
	var op: String = {"+": "+", "−": "-", "-": "-", "×": "*", "x": "*", ":": "/", "÷": "/"}.get(m.get_string(2), "")
	return [int(m.get_string(1).replace(".", "").replace("−", "-")), op, int(m.get_string(3).replace(".", "").replace("−", "-"))]


static func _calc(a: int, op: String, b: int):
	match op:
		"+":
			return a + b
		"-":
			return a - b
		"*":
			return a * b
		"/":
			return a / b if b != 0 and a % b == 0 else null
	return null
