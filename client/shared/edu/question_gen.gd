extends RefCounted
## Pembuat soal matematika acak (bukan bank soal tetap), dipakai game pembelajaran lewat konfigurasi
## level di course.json, contoh: {"type": "arith", "ops": ["+", "-"], "min": 1, "max": 20, "count": 10}
## Setiap soal: {q, options: [4 teks], answer: indeks benar, explain}. Semua jawaban dihitung, bukan ditebak.

const TYPES := ["arith", "linear", "power", "fraction_compare"]


static func generate(cfg: Dictionary, rng: RandomNumberGenerator) -> Array:
	var n := clampi(int(cfg.get("count", 10)), 1, 30)
	var out: Array = []
	var seen := {}
	var guard := 0
	while out.size() < n and guard < n * 20:
		guard += 1
		var q: Dictionary
		match str(cfg.get("type", "arith")):
			"linear":
				q = _linear(cfg, rng)
			"power":
				q = _power(cfg, rng)
			"fraction_compare":
				q = _fraction_compare(cfg, rng)
			_:
				q = _arith(cfg, rng)
		if q.is_empty() or seen.has(q.q):
			continue
		seen[q.q] = true
		out.append(q)
	return out


static func _arith(cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ops: Array = cfg.get("ops", ["+"])
	var lo := int(cfg.get("min", 1))
	var hi := int(cfg.get("max", 10))
	var allow_neg := bool(cfg.get("negative", false))
	var op := str(ops[rng.randi_range(0, ops.size() - 1)])
	var a := rng.randi_range(lo, hi)
	var b := rng.randi_range(lo, hi)
	var ans := 0
	var sym := op
	match op:
		"+":
			ans = a + b
		"-":
			if not allow_neg and b > a:
				var t := a
				a = b
				b = t
			ans = a - b
		"x", "*":
			sym = "×"
			ans = a * b
		"/", ":":
			sym = ":"
			if b == 0:
				b = 1
			ans = a
			a = a * b  # pembagian selalu habis
		_:
			return {}
	var bt := "(%d)" % b if b < 0 else str(b)
	var text := "%d %s %s = ?" % [a, sym, bt]
	return _with_options(text, ans, rng, "%d %s %s = %d" % [a, sym, bt, ans], maxi(3, absi(ans) / 5))


static func _linear(cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# a·x + b = c dengan x bulat.
	var lo := int(cfg.get("min", -10))
	var hi := int(cfg.get("max", 10))
	var x := rng.randi_range(lo, hi)
	var a := rng.randi_range(2, 9) * (1 if rng.randf() < 0.75 else -1)
	var b := rng.randi_range(-20, 20)
	var c := a * x + b
	var bs := ("+ %d" % b) if b >= 0 else ("- %d" % -b)
	var text := "Jika %dx %s = %d, maka x = ?" % [a, bs, c]
	var ex := "%dx = %d %s %d = %d, jadi x = %d : %d = %d" % [a, c, "-" if b >= 0 else "+", absi(b), c - b, c - b, a, x]
	return _with_options(text, x, rng, ex, 4)


static func _power(cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var kind := rng.randi_range(0, 2)
	match kind:
		0:
			var a := rng.randi_range(2, int(cfg.get("max", 15)))
			return _with_options("%d² = ?" % a, a * a, rng, "%d × %d = %d" % [a, a, a * a], maxi(4, a))
		1:
			var r := rng.randi_range(2, int(cfg.get("max", 15)))
			return _with_options("√%d = ?" % (r * r), r, rng, "%d × %d = %d, jadi √%d = %d" % [r, r, r * r, r * r, r], 3)
		_:
			var triples := [[3, 4, 5], [6, 8, 10], [5, 12, 13], [8, 15, 17], [9, 12, 15], [7, 24, 25], [12, 16, 20]]
			var t: Array = triples[rng.randi_range(0, triples.size() - 1)]
			var text := "Segitiga siku-siku dengan sisi tegak %d dan %d. Panjang sisi miringnya?" % [t[0], t[1]]
			var ex := "√(%d² + %d²) = √(%d + %d) = √%d = %d" % [t[0], t[1], t[0] * t[0], t[1] * t[1], t[2] * t[2], t[2]]
			return _with_options(text, int(t[2]), rng, ex, 4)


static func _fraction_compare(_cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var a := rng.randi_range(1, 8)
	var b := rng.randi_range(a + 1, 10)
	var c := rng.randi_range(1, 8)
	var d := rng.randi_range(c + 1, 10)
	var left := a * d
	var right := c * b
	var sign := "=" if left == right else (">" if left > right else "<")
	var text := "Tanda yang tepat: %d/%d … %d/%d" % [a, b, c, d]
	var opts := ["<", ">", "="]
	var ex := "Kali silang: %d × %d = %d dan %d × %d = %d" % [a, d, left, c, b, right]
	return {"q": text, "options": opts, "answer": opts.find(sign), "explain": ex}


## Empat pilihan: satu benar, tiga pengecoh berbeda di sekitar jawaban.
static func _with_options(text: String, ans: int, rng: RandomNumberGenerator, explain: String, spread: int) -> Dictionary:
	var opts := [ans]
	var guard := 0
	while opts.size() < 4 and guard < 50:
		guard += 1
		var delta := rng.randi_range(1, maxi(2, spread)) * (1 if rng.randf() < 0.5 else -1)
		var wrong := ans + delta
		if not opts.has(wrong):
			opts.append(wrong)
	while opts.size() < 4:
		opts.append(ans + opts.size() * 7)
	# acak urutan
	for i in range(opts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = opts[i]
		opts[i] = opts[j]
		opts[j] = t
	var labels: Array = []
	for o in opts:
		labels.append(str(o))
	return {"q": text, "options": labels, "answer": opts.find(ans), "explain": explain}
