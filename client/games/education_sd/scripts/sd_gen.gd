extends RefCounted
## Pembuat soal matematika SD per kelas (Petualangan Pulau Ilmu). Semua kunci jawaban DIHITUNG.
## Spesifikasi berasal dari data/pulau_ilmu.json -> topics[].gen["<kelas>"], mis. "add:10:50", "pattern:3".
## Pecahan memakai ulang pembuat soal bersama res://shared/edu/question_gen.gd (ikut APK).

const QuestionGen := preload("res://shared/edu/question_gen.gd")

const COUNT_SHAPES := ["apel", "bintang", "lingkaran"]


## Satu soal dari spesifikasi `spec` untuk topik `topic` dan kelas `grade`. {} bila spesifikasi tidak dikenal.
static func make(spec: String, topic: String, grade: int, rng: RandomNumberGenerator) -> Dictionary:
	var p := spec.split(":")
	var kind := p[0]
	var a := int(p[1]) if p.size() > 1 else 0
	var b := int(p[2]) if p.size() > 2 else 0
	var q: Dictionary = {}
	match kind:
		"count":
			var n := rng.randi_range(a, b)
			var shape: String = COUNT_SHAPES[rng.randi_range(0, COUNT_SHAPES.size() - 1)]
			q = {"type": "count", "shape": shape, "count": n, "q": "Ada berapa %s?" % _shape_word(shape),
				"explain": "Hitung satu per satu. Jumlahnya %d." % n}
		"sort":
			var nums := _distinct(rng, a, b, 4 if grade <= 1 else 5)
			var desc := grade >= 2 and rng.randf() < 0.5
			q = {"type": "sort_numbers", "numbers": nums, "desc": desc,
				"q": "Urutkan dari yang %s:" % ("terbesar" if desc else "terkecil"),
				"explain": "Bandingkan angka mulai dari nilai tempat yang paling besar."}
		"add":
			var x := rng.randi_range(a, b)
			var y := rng.randi_range(a, b)
			q = _mc("%s + %s = …" % [_n(x), _n(y)], x + y, rng, "%s + %s = %s." % [_n(x), _n(y), _n(x + y)],
				[x + y - _carry(x, y), absi(x - y)])
		"addneg":
			var x := rng.randi_range(a, b)
			var y := rng.randi_range(a, b)
			q = _mc("%d + %s = …" % [x, _paren(y)], x + y, rng, "Pada garis bilangan, mulai dari %d lalu %s %d langkah. Hasilnya %d." % [x, "maju" if y >= 0 else "mundur", absi(y), x + y])
		"sub":
			var x := rng.randi_range(a, b)
			var y := rng.randi_range(a, b)
			if y == x:
				x += 1
			if y > x:
				var t := x
				x = y
				y = t
			q = _mc("%s − %s = …" % [_n(x), _n(y)], x - y, rng, "%s − %s = %s. Periksa: %s + %s = %s." % [_n(x), _n(y), _n(x - y), _n(x - y), _n(y), _n(x)],
				[x - y + _borrow(x, y), x + y])
		"subneg":
			var x := rng.randi_range(a, b)
			var y := rng.randi_range(a, b)
			q = _mc("%d − %s = …" % [x, _paren(y)], x - y, rng, "Mengurangi sama dengan menambah lawannya: %d + (%d) = %d." % [x, -y, x - y])
		"mul":
			var x := rng.randi_range(a, b)
			var y := rng.randi_range(1, 10)
			q = _mc("%d × %d = …" % [x, y], x * y, rng, "%d × %d artinya %d dijumlahkan %d kali = %d." % [x, y, y, x, x * y], [x + y])
		"mul2x1":
			var x := rng.randi_range(11, 99)
			var y := rng.randi_range(2, 9)
			q = _mc("%d × %d = …" % [x, y], x * y, rng, "%d × %d = (%d × %d) + (%d × %d) = %d." % [x, y, x / 10 * 10, y, x % 10, y, x * y])
		"mul2x2":
			var x := rng.randi_range(11, 30)
			var y := rng.randi_range(11, 20)
			q = _mc("%d × %d = …" % [x, y], x * y, rng, "%d × %d = %d." % [x, y, x * y])
		"pow":
			if rng.randf() < 0.6:
				var x := rng.randi_range(2, 15)
				q = _mc("%d² = …" % x, x * x, rng, "%d² = %d × %d = %d." % [x, x, x, x * x])
			else:
				var x := rng.randi_range(2, 6)
				q = _mc("%d³ = …" % x, x * x * x, rng, "%d³ = %d × %d × %d = %d." % [x, x, x, x, x * x * x])
		"div":
			var y := rng.randi_range(a, b)
			var r := rng.randi_range(2, 10 if grade <= 4 else 20)
			var x := y * r
			q = _mc("%s : %d = …" % [_n(x), y], r, rng, "%d × %d = %s, jadi %s : %d = %d." % [y, r, _n(x), _n(x), y, r])
		"frac_cmp":
			var g: Dictionary = QuestionGen.generate({"type": "fraction_compare", "count": 1}, rng)[0]
			q = {"type": "mc", "q": str(g.q), "options": g.options, "answer": int(g.answer), "explain": str(g.explain)}
		"frac_eq":
			var num := rng.randi_range(1, 4)
			var den := rng.randi_range(num + 1, 6)
			var k := rng.randi_range(2, 5)
			q = _mc("%d/%d = …/%d" % [num, den, den * k], num * k, rng, "Penyebut dikali %d, maka pembilang juga dikali %d: %d × %d = %d." % [k, k, num, k, num * k])
		"story_add":
			var x := rng.randi_range(a, b)
			var y := rng.randi_range(a, b)
			var who: String = NAMES[rng.randi_range(0, NAMES.size() - 1)]
			var item: String = ITEMS[rng.randi_range(0, ITEMS.size() - 1)]
			q = _mc("%s punya %s %s. Ia mendapat %s %s lagi. Berapa %s %s sekarang?" % [who, _n(x), item, _n(y), item, item, who], x + y, rng,
				"Mendapat lagi berarti ditambah: %s + %s = %s." % [_n(x), _n(y), _n(x + y)], [absi(x - y), x + y - _carry(x, y)])
			q["story"] = true
		"story_sub":
			var x := rng.randi_range(a, b)
			var y := rng.randi_range(a, b)
			if y == x:
				x += 1
			if y > x:
				var t := x
				x = y
				y = t
			var who: String = NAMES[rng.randi_range(0, NAMES.size() - 1)]
			var item: String = ITEMS[rng.randi_range(0, ITEMS.size() - 1)]
			q = _mc("%s punya %s %s. Ia memberikan %s %s kepada temannya. Berapa sisa %s %s?" % [who, _n(x), item, _n(y), item, item, who], x - y, rng,
				"Memberikan berarti dikurangi: %s − %s = %s." % [_n(x), _n(y), _n(x - y)], [x + y, x - y + _borrow(x, y)])
			q["story"] = true
		"money":
			# Uang kembalian. Tingkat 1: harga ribuan bulat; tingkat 2: harga kelipatan 500 dan beberapa barang.
			var thing: Array = GOODS[rng.randi_range(0, GOODS.size() - 1)]
			var n := 1 if a <= 1 else rng.randi_range(2, 4)
			var price: int = int(thing[1]) if a <= 1 else int(thing[1]) + 500 * rng.randi_range(0, 1)
			var total := price * n
			var pay := 0
			for note in [2000, 5000, 10000, 20000, 50000, 100000]:
				if note > total:
					pay = note
					break
			var text := "Harga %s Rp%s. %s membayar dengan uang Rp%s. Berapa kembaliannya?" % [str(thing[0]), _n(price),
				NAMES[rng.randi_range(0, NAMES.size() - 1)], _n(pay)]
			var ex := "Kembalian = uang yang dibayar − harga = Rp%s − Rp%s = Rp%s." % [_n(pay), _n(total), _n(pay - total)]
			if n > 1:
				text = "Harga satu %s Rp%s. %s membeli %d dan membayar Rp%s. Berapa kembaliannya?" % [str(thing[0]), _n(price),
					NAMES[rng.randi_range(0, NAMES.size() - 1)], n, _n(pay)]
				ex = "Harga semua = %d × Rp%s = Rp%s. Kembalian = Rp%s − Rp%s = Rp%s." % [n, _n(price), _n(total), _n(pay), _n(total), _n(pay - total)]
			q = _mc(text, pay - total, rng, ex, [pay - price if n > 1 else pay + total, total, pay - total + 1000])
			q.options = (q.options as Array).map(func(o): return "Rp" + str(o))
			q["story"] = true
		"clock":
			var h := rng.randi_range(6, 15)
			var dur := rng.randi_range(1, 4)
			if a <= 1:
				q = _mc("Sekarang pukul %s. Pukul berapa %d jam lagi?" % [_hour(h), dur], h + dur, rng,
					"%d + %d = %d, jadi pukul %s." % [h, dur, h + dur, _hour(h + dur)], [h - dur, h + dur + 1])
				q.options = (q.options as Array).map(func(o): return _hour(int(o)))
			else:
				q = _mc("%s belajar dari pukul %s sampai pukul %s. Berapa jam lamanya?" % [NAMES[rng.randi_range(0, NAMES.size() - 1)],
					_hour(h), _hour(h + dur)], dur, rng, "Lama waktu = %d − %d = %d jam." % [h + dur, h, dur], [dur + 1, h + dur])
				q.options = (q.options as Array).map(func(o): return str(o) + " jam")
			q["story"] = true
		"fpb", "kpk":
			var pairs := [[4, 6], [6, 8], [6, 9], [8, 12], [9, 12], [10, 15], [12, 18], [12, 16], [15, 20], [6, 10], [4, 10], [8, 10]]
			var pr: Array = pairs[rng.randi_range(0, pairs.size() - 1)]
			var g := _gcd(int(pr[0]), int(pr[1]))
			var l := int(pr[0]) * int(pr[1]) / g
			if kind == "fpb":
				q = _mc("FPB dari %d dan %d adalah …" % [pr[0], pr[1]], g, rng,
					"FPB adalah faktor persekutuan terbesar: bilangan terbesar yang dapat membagi habis %d dan %d, yaitu %d." % [pr[0], pr[1], g], [l, 1])
			else:
				q = _mc("KPK dari %d dan %d adalah …" % [pr[0], pr[1]], l, rng,
					"KPK adalah kelipatan persekutuan terkecil: bilangan terkecil yang merupakan kelipatan %d dan %d, yaitu %d." % [pr[0], pr[1], l],
					[g, int(pr[0]) * int(pr[1]) if int(pr[0]) * int(pr[1]) != l else l * 2])
			q["story"] = true
		"mixed":
			var x := rng.randi_range(2, 20)
			var y := rng.randi_range(2, 9)
			var z := rng.randi_range(2, 9)
			q = _mc("%d + %d × %d = …" % [x, y, z], x + y * z, rng,
				"Perkalian dikerjakan lebih dulu: %d × %d = %d, lalu %d + %d = %d." % [y, z, y * z, x, y * z, x + y * z], [(x + y) * z])
			q["story"] = true
		"conv":
			q = _conv(str(p[1]) if p.size() > 1 else "m_cm", rng)
		"pattern":
			q = _pattern(a, rng)
		_:
			return {}
	if q.is_empty():
		return {}
	if not q.has("type"):
		q["type"] = "mc"
	q["topic"] = topic
	q["grade"] = grade
	q["generated"] = true
	q["id"] = "gen-%s-%d-%s" % [topic, grade, str(q.q).md5_text().substr(0, 8)]
	var diff := 3 if q.type == "logic" else (2 if q.type == "sort_numbers" or q.has("story") else 1 + int(grade >= 4))
	q.erase("story")
	q["difficulty"] = diff
	q["points"] = 10 * diff
	return q


static func _conv(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var table := {
		"m_cm": ["m", "cm", 100, "1 m = 100 cm"],
		"km_m": ["km", "m", 1000, "1 km = 1.000 m"],
		"kg_g": ["kg", "g", 1000, "1 kg = 1.000 g"],
		"l_ml": ["liter", "mL", 1000, "1 liter = 1.000 mL"],
		"jam_menit": ["jam", "menit", 60, "1 jam = 60 menit"],
	}
	if not table.has(kind):
		return {}
	var t: Array = table[kind]
	var v := rng.randi_range(2, 9)
	var ans: int = v * int(t[2])
	return _mc("%d %s = … %s" % [v, t[0], t[1]], ans, rng, "%s, jadi %d %s = %d × %s = %s %s." % [t[3], v, t[0], v, _n(int(t[2])), _n(ans), t[1]])


static func _pattern(level: int, rng: RandomNumberGenerator) -> Dictionary:
	var seq: Array = []
	var rule := ""
	match level:
		1:
			var s := rng.randi_range(1, 5)
			var d := rng.randi_range(1, 2)
			for i in 4:
				seq.append(s + i * d)
			rule = "selalu ditambah %d" % d
		2:
			var d: int = [2, 5, 10][rng.randi_range(0, 2)]
			var s := rng.randi_range(0, 5) * d
			for i in 4:
				seq.append(s + i * d)
			rule = "selalu ditambah %d" % d
		3:
			var d := rng.randi_range(3, 9)
			if rng.randf() < 0.5:
				var s := rng.randi_range(1, 10)
				for i in 4:
					seq.append(s + i * d)
				rule = "selalu ditambah %d" % d
			else:
				var s := rng.randi_range(5 * d, 10 * d)
				for i in 4:
					seq.append(s - i * d)
				rule = "selalu dikurangi %d" % d
		4:
			var s := rng.randi_range(1, 5)
			for i in 4:
				seq.append(s * int(pow(2, i)))
			rule = "selalu dikali 2"
		5:
			var s := rng.randi_range(1, 5)
			for i in 4:
				seq.append((s + i) * (s + i))
			rule = "bilangan kuadrat (%d², %d², %d², ...)" % [s, s + 1, s + 2]
		_:
			if rng.randf() < 0.5:
				var s := rng.randi_range(1, 3)
				for i in 4:
					seq.append(int(pow(s + i, 3)))
				rule = "bilangan pangkat tiga"
			else:
				var s := rng.randi_range(1, 4)
				var m := 3
				for i in 4:
					seq.append(s * int(pow(m, i)))
				rule = "selalu dikali 3"
	var nxt: int
	match level:
		4:
			nxt = int(seq[3]) * 2
		5:
			nxt = int(round(sqrt(float(seq[3])))) + 1
			nxt = nxt * nxt
		6:
			if rule == "selalu dikali 3":
				nxt = int(seq[3]) * 3
			else:
				nxt = int(round(pow(float(seq[3]), 1.0 / 3.0))) + 1
				nxt = nxt * nxt * nxt
		_:
			nxt = int(seq[3]) + (int(seq[1]) - int(seq[0]))
	var text := "%s, … Bilangan berikutnya adalah?" % ", ".join(PackedStringArray(seq.map(func(x): return str(x))))
	var q := _mc(text, nxt, rng, "Polanya %s, jadi berikutnya %d." % [rule, nxt])
	q["type"] = "logic"
	return q


const NAMES := ["Dina", "Budi", "Siti", "Rafi", "Wayan", "Meli"]
const ITEMS := ["kelereng", "pensil", "stiker", "buku", "permen", "manik-manik"]
const GOODS := [["pensil", 2000], ["buku tulis", 3000], ["penghapus", 1000], ["roti", 4000], ["susu kotak", 5000], ["penggaris", 3000]]


static func _hour(h: int) -> String:
	return "%02d.00" % (((h % 24) + 24) % 24)


static func _gcd(x: int, y: int) -> int:
	while y != 0:
		var t := x % y
		x = y
		y = t
	return x


## traps = pengecoh diagnostik (kesalahan umum: lupa menyimpan/meminjam, operasi tertukar). Dipakai lebih dulu bila
## sah (berbeda dari kunci, tidak negatif bila kunci tidak negatif); sisanya pengecoh acak di sekitar kunci.
static func _mc(text: String, ans: int, rng: RandomNumberGenerator, explain: String, traps: Array = []) -> Dictionary:
	var opts: Array = [ans]
	for t in traps:
		var w := int(t)
		if opts.size() < 4 and w != ans and not opts.has(w) and (w >= 0 or ans < 0):
			opts.append(w)
	var spread := maxi(2, absi(ans) / 8)
	var guard := 0
	while opts.size() < 4 and guard < 60:
		guard += 1
		var w := ans + rng.randi_range(1, spread) * (1 if rng.randf() < 0.5 else -1)
		if not opts.has(w) and (w >= 0 or ans < 0):
			opts.append(w)
	var extra := 1
	while opts.size() < 4:
		if not opts.has(ans + spread + extra):
			opts.append(ans + spread + extra)
		extra += 1
	var labels: Array = []
	for o in opts:
		labels.append(_n(int(o)))
	return {"type": "mc", "q": text, "options": labels, "answer": 0, "explain": explain}


## Angka dengan pemisah ribuan titik (gaya Indonesia), mis. 12.500.
## Selisih bila anak lupa menyimpan: tiap kolom hanya ditulis satuannya, kolom paling kiri ditulis utuh
## (27 + 15 -> 32, 59 + 44 -> 93). Mengembalikan jawaban benar dikurangi jawaban salah itu (0 bila tanpa simpanan).
static func _carry(x: int, y: int) -> int:
	var a := absi(x)
	var b := absi(y)
	var wrong := 0
	var place := 1
	while a >= 10 or b >= 10:
		wrong += ((a % 10 + b % 10) % 10) * place
		a /= 10
		b /= 10
		place *= 10
	wrong += (a + b) * place
	return absi(x) + absi(y) - wrong


## Kesalahan meminjam yang khas: kolom yang perlu meminjam dihitung "angka besar dikurang angka kecil".
## Mengembalikan selisih jawaban salah itu terhadap jawaban benar (0 bila tidak perlu meminjam).
static func _borrow(x: int, y: int) -> int:
	if x < 0 or y < 0 or y > x:
		return 0
	var wrong := 0
	var place := 1
	var a := x
	var b := y
	while a > 0 or b > 0:
		wrong += absi(a % 10 - b % 10) * place
		a /= 10
		b /= 10
		place *= 10
	return wrong - (x - y)


static func _n(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


static func _paren(v: int) -> String:
	return "(%d)" % v if v < 0 else str(v)


static func _distinct(rng: RandomNumberGenerator, lo: int, hi: int, n: int) -> Array:
	var out: Array = []
	var guard := 0
	while out.size() < n and guard < 200:
		guard += 1
		var v := rng.randi_range(lo, hi)
		if not out.has(v):
			out.append(v)
	return out


static func _shape_word(shape: String) -> String:
	return {"apel": "apel", "bintang": "bintang", "lingkaran": "bola"}.get(shape, "benda")
