extends RefCounted
## Gambar Pulau Ilmu yang dibuat dengan kode (2D ringan, tanpa berkas gambar): bangun datar/ruang untuk
## soal, avatar pemain, karakter NPC, dan peta pulau. Gaya: kartun ceria, garis tebal, warna cerah.

const INK := Color("2b2440")


## Ikon bentuk untuk soal "pilih gambar", "hitung gambar", dan "pasangkan".
class ShapeIcon extends Control:
	var shape := "lingkaran"
	var color := Color("f0b429")

	func _init(s: String = "lingkaran", c: Color = Color("f0b429")) -> void:
		shape = s
		color = c
		custom_minimum_size = Vector2(72, 72)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.4
		var c := size / 2.0
		var w := maxf(2.0, r * 0.08)
		var col := color
		var dark := col.darkened(0.35)
		match shape:
			"lingkaran", "bola":
				draw_circle(c, r, col)
				draw_arc(c, r, 0, TAU, 48, INK, w, true)
				if shape == "bola":
					draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.22, Color(1, 1, 1, 0.55))
			"persegi":
				_poly([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)], col, w)
			"persegi_panjang":
				_poly([c + Vector2(-r * 1.15, -r * 0.6), c + Vector2(r * 1.15, -r * 0.6), c + Vector2(r * 1.15, r * 0.6), c + Vector2(-r * 1.15, r * 0.6)], col, w)
			"segitiga":
				_poly([c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)], col, w)
			"belah_ketupat":
				_poly([c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)], col, w)
			"trapesium":
				_poly([c + Vector2(-r * 0.55, -r * 0.6), c + Vector2(r * 0.55, -r * 0.6), c + Vector2(r * 1.1, r * 0.6), c + Vector2(-r * 1.1, r * 0.6)], col, w)
			"jajar_genjang":
				_poly([c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 1.1, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), c + Vector2(-r * 1.1, r * 0.6)], col, w)
			"bintang":
				var pts := PackedVector2Array()
				for i in 10:
					var rr := r if i % 2 == 0 else r * 0.45
					var a := -PI / 2 + i * PI / 5
					pts.append(c + Vector2(cos(a), sin(a)) * rr)
				_poly(pts, col, w)
			"apel":
				draw_circle(c + Vector2(0, r * 0.1), r * 0.82, Color("e0453a"))
				draw_arc(c + Vector2(0, r * 0.1), r * 0.82, 0, TAU, 40, INK, w, true)
				draw_line(c + Vector2(0, -r * 0.65), c + Vector2(r * 0.1, -r), INK, w * 1.4)
				_poly([c + Vector2(r * 0.08, -r * 0.8), c + Vector2(r * 0.55, -r * 0.95), c + Vector2(r * 0.25, -r * 0.6)], Color("4caf50"), w * 0.6)
				draw_circle(c + Vector2(-r * 0.3, -r * 0.15), r * 0.15, Color(1, 1, 1, 0.5))
			"kubus", "balok":
				var hw := r * (0.6 if shape == "kubus" else 0.95)
				var hh := r * 0.6
				var d := Vector2(r * 0.4, -r * 0.4)
				var f := [c + Vector2(-hw, -hh) - d / 2, c + Vector2(hw, -hh) - d / 2, c + Vector2(hw, hh) - d / 2, c + Vector2(-hw, hh) - d / 2]
				_poly([f[0], f[0] + d, f[1] + d, f[1]], col.lightened(0.2), w)
				_poly([f[1], f[1] + d, f[2] + d, f[2]], dark, w)
				_poly(f, col, w)
			"tabung":
				var rx := r * 0.65
				var ry := r * 0.22
				draw_rect(Rect2(c.x - rx, c.y - r * 0.7, rx * 2, r * 1.4), col)
				_ellipse(c + Vector2(0, r * 0.7), rx, ry, col, w)
				draw_line(c + Vector2(-rx, -r * 0.7), c + Vector2(-rx, r * 0.7), INK, w)
				draw_line(c + Vector2(rx, -r * 0.7), c + Vector2(rx, r * 0.7), INK, w)
				_ellipse(c + Vector2(0, -r * 0.7), rx, ry, col.lightened(0.25), w)
			"kerucut":
				var rx := r * 0.7
				var base := c + Vector2(0, r * 0.65)
				_poly([c + Vector2(0, -r), base + Vector2(rx, 0), base + Vector2(-rx, 0)], col, w)
				_ellipse(base, rx, r * 0.22, col.darkened(0.15), w)
			"limas":
				var b0 := c + Vector2(-r * 0.8, r * 0.6)
				var b1 := c + Vector2(r * 0.5, r * 0.75)
				var b2 := c + Vector2(r * 0.9, r * 0.35)
				var top := c + Vector2(0, -r)
				_poly([b0, b1, top], col, w)
				_poly([b1, b2, top], dark, w)
			_:
				draw_circle(c, r, col)

	func _poly(pts, col: Color, w: float) -> void:
		var arr := PackedVector2Array(pts)
		draw_colored_polygon(arr, col)
		arr.append(arr[0])
		draw_polyline(arr, INK, w, true)

	func _ellipse(center: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, INK, w, true)


## Avatar pemain: anak penjelajah bulat yang bisa diberi baju, topi, dan aksesori.
class Avatar extends Control:
	var outfit := Color("e05a4f")
	var hat := ""
	var acc := ""
	var mood := "senang"  # "senang" / "kagum"

	func _init() -> void:
		custom_minimum_size = Vector2(120, 140)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_look(o: Color, h: String, a: String) -> void:
		outfit = o
		hat = h
		acc = a
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x / 120.0, size.y / 170.0)  # topi s/d 70 di atas kepala, badan s/d 92 di bawah
		var c := Vector2(size.x / 2.0, (size.y - 164.0 * s) / 2.0 + 72.0 * s)
		var skin := Color("f5c9a0")
		var w := 3.0 * s
		if acc == "ransel":
			draw_rect(Rect2(c + Vector2(-38, 30) * s, Vector2(76, 50) * s), Color("8a5a2b"))
		# badan
		var body := PackedVector2Array([c + Vector2(-34, 38) * s, c + Vector2(34, 38) * s, c + Vector2(42, 92) * s, c + Vector2(-42, 92) * s])
		draw_colored_polygon(body, outfit)
		body.append(body[0])
		draw_polyline(body, INK, w, true)
		# kepala
		draw_circle(c, 40 * s, skin)
		draw_arc(c, 40 * s, 0, TAU, 48, INK, w, true)
		# rambut
		draw_arc(c + Vector2(0, -6) * s, 38 * s, PI * 1.05, PI * 1.95, 24, Color("4a2f1f"), 14 * s)
		# mata & senyum
		for side in [-1, 1]:
			var e := c + Vector2(14 * side, -2) * s
			if mood == "kagum":
				draw_circle(e, 7 * s, Color.WHITE)
				draw_circle(e, 4 * s, INK)
			else:
				draw_arc(e + Vector2(0, 3) * s, 6 * s, PI * 1.1, PI * 1.9, 10, INK, w, true)
			draw_circle(c + Vector2(24 * side, 12) * s, 6 * s, Color(1, 0.5, 0.5, 0.45))
		draw_arc(c + Vector2(0, 10) * s, 13 * s, PI * 0.15, PI * 0.85, 16, INK, w, true)
		match acc:
			"kacamata":
				for side in [-1, 1]:
					draw_arc(c + Vector2(14 * side, 0) * s, 10 * s, 0, TAU, 20, INK, w, true)
				draw_line(c + Vector2(-4, 0) * s, c + Vector2(4, 0) * s, INK, w)
			"syal":
				draw_rect(Rect2(c + Vector2(-34, 30) * s, Vector2(68, 14) * s), Color("2fb3a6"))
				draw_rect(Rect2(c + Vector2(14, 40) * s, Vector2(14, 30) * s), Color("2fb3a6"))
		match hat:
			"petualang":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-56, -26) * s, c + Vector2(56, -26) * s, c + Vector2(40, -36) * s, c + Vector2(-40, -36) * s]), Color("c49a5a"))
				draw_rect(Rect2(c + Vector2(-30, -62) * s, Vector2(60, 28) * s), Color("c49a5a"))
				draw_rect(Rect2(c + Vector2(-30, -42) * s, Vector2(60, 7) * s), Color("6b4a2b"))
			"mahkota":
				var pts := PackedVector2Array([c + Vector2(-30, -30) * s, c + Vector2(-30, -62) * s, c + Vector2(-15, -45) * s, c + Vector2(0, -68) * s,
					c + Vector2(15, -45) * s, c + Vector2(30, -62) * s, c + Vector2(30, -30) * s])
				draw_colored_polygon(pts, Color("f0b429"))
				pts.append(pts[0])
				draw_polyline(pts, INK, w, true)
			"toga":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-50, -46) * s, c + Vector2(0, -62) * s, c + Vector2(50, -46) * s, c + Vector2(0, -32) * s]), INK)
				draw_rect(Rect2(c + Vector2(-24, -44) * s, Vector2(48, 14) * s), INK)
				draw_line(c + Vector2(40, -46) * s, c + Vector2(44, -20) * s, Color("f0b429"), w)
			"pita":
				draw_colored_polygon(PackedVector2Array([c + Vector2(18, -38) * s, c + Vector2(40, -52) * s, c + Vector2(40, -24) * s]), Color("ff6fa8"))
				draw_colored_polygon(PackedVector2Array([c + Vector2(18, -38) * s, c + Vector2(0, -52) * s, c + Vector2(0, -24) * s]), Color("ff6fa8"))
				draw_circle(c + Vector2(19, -38) * s, 6 * s, Color("e04a8a"))


## Karakter NPC wilayah: makhluk bulat ramah berwarna khas wilayah (Raja Angka, Kak Kancil, dll.).
class Mascot extends Control:
	var color := Color("8a6bd8")
	var kind := "raja"  # raja / kancil / profesor / nakhoda
	var talk := 0.0
	var _acc := 0.0

	func _init(c: Color = Color("8a6bd8"), k: String = "profesor") -> void:
		color = c
		kind = k
		custom_minimum_size = Vector2(130, 140)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		talk += delta
		_acc += delta
		if _acc >= 1.0 / 30.0:  # 30 gambar/detik cukup; hemat baterai
			_acc = 0.0
			queue_redraw()

	func _draw() -> void:
		var s := minf(size.x / 130.0, size.y / 140.0)
		var bob := sin(talk * 2.4) * 3.0 * s
		var c := Vector2(size.x / 2.0, size.y * 0.55 + bob)
		var w := 3.0 * s
		if kind == "kancil":
			for side in [-1, 1]:
				draw_colored_polygon(PackedVector2Array([c + Vector2(22 * side, -40) * s, c + Vector2(40 * side, -78) * s, c + Vector2(8 * side, -50) * s]), color.darkened(0.15))
		draw_circle(c, 46 * s, color)
		draw_arc(c, 46 * s, 0, TAU, 48, INK, w, true)
		draw_circle(c + Vector2(0, 14) * s, 28 * s, color.lightened(0.35))
		for side in [-1, 1]:
			draw_circle(c + Vector2(16 * side, -12) * s, 11 * s, Color.WHITE)
			draw_circle(c + Vector2(16 * side + 2, -11) * s, 6 * s, INK)
			draw_circle(c + Vector2(16 * side + 4, -14) * s, 2 * s, Color.WHITE)
		var mouth := 5.0 + absf(sin(talk * 6.0)) * 4.0
		draw_arc(c + Vector2(0, 8) * s, 10 * s, PI * 0.1, PI * 0.9, 12, INK, w, true)
		draw_circle(c + Vector2(0, 12 + mouth * 0.3) * s, 3 * s, Color("e0453a"))
		match kind:
			"raja":
				var pts := PackedVector2Array([c + Vector2(-26, -40) * s, c + Vector2(-26, -66) * s, c + Vector2(-13, -52) * s, c + Vector2(0, -72) * s,
					c + Vector2(13, -52) * s, c + Vector2(26, -66) * s, c + Vector2(26, -40) * s])
				draw_colored_polygon(pts, Color("f0b429"))
				pts.append(pts[0])
				draw_polyline(pts, INK, w, true)
			"profesor":
				for side in [-1, 1]:
					draw_arc(c + Vector2(16 * side, -12) * s, 14 * s, 0, TAU, 20, INK, w, true)
				draw_line(c + Vector2(-2, -12) * s, c + Vector2(2, -12) * s, INK, w)
			"nakhoda":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-40, -36) * s, c + Vector2(40, -36) * s, c + Vector2(30, -56) * s, c + Vector2(-30, -56) * s]), Color("1f2d50"))
				draw_rect(Rect2(c + Vector2(-42, -38) * s, Vector2(84, 6) * s), Color.WHITE)
				draw_circle(c + Vector2(0, -46) * s, 6 * s, Color("f0b429"))


## Peta Pulau Ilmu: laut + empat pulau berwarna wilayah. Tombol pulau dipasang oleh layar peta.
class WorldMap extends Control:
	var islands: Array = []  # [{pos: Vector2 (0..1), color: Color, done: float 0..1}]
	var wave := 0.0
	var _acc := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		wave += delta
		_acc += delta
		if _acc >= 1.0 / 20.0:
			_acc = 0.0
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("4fb3e8"))
		for i in 18:
			var y := fposmod(i * 61.0, size.y)
			var x := fposmod(i * 137.0 + wave * 18.0, size.x + 80) - 40
			draw_arc(Vector2(x, y), 14, PI * 1.1, PI * 1.9, 8, Color(1, 1, 1, 0.35), 3)
		for isl in islands:
			var c := Vector2(isl.pos.x * size.x, isl.pos.y * size.y)
			var r := minf(size.x, size.y) * 0.17
			_blob(c, r * 1.12, Color("f3dd9b"))
			_blob(c, r, isl.color)
			for k in 3:
				var tp := c + Vector2(-r * 0.4 + k * r * 0.4, -r * 0.25 + (k % 2) * r * 0.2)
				draw_circle(tp, r * 0.16, Color("2e8b57"))
				draw_rect(Rect2(tp + Vector2(-r * 0.03, r * 0.1), Vector2(r * 0.06, r * 0.18)), Color("7a4a2a"))
			if float(isl.get("done", 0.0)) > 0.0:
				draw_arc(c, r * 1.25, -PI / 2, -PI / 2 + TAU * float(isl.done), 40, Color("f0b429"), 8, true)

	func _blob(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			var rr := r * (1.0 + 0.08 * sin(a * 3.0) + 0.05 * cos(a * 5.0))
			pts.append(c + Vector2(cos(a) * rr * 1.25, sin(a) * rr * 0.85))
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, INK, 3, true)
