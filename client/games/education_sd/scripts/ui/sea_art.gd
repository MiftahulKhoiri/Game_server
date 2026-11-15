extends RefCounted
## Gambar 2D bersama untuk menu utama dan peta enam pulau: laut, pulau, perahu, awan, ombak.
## Semua fungsi statis; dipanggil dari _draw() sebuah Control (ci).


static func sky(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	var steps := 24
	for i in steps:
		var t := float(i) / steps
		var r := Rect2(rect.position.x, rect.position.y + rect.size.y * t, rect.size.x, rect.size.y / steps + 1.0)
		ci.draw_rect(r, top.lerp(bottom, t))


static func waves(ci: CanvasItem, rect: Rect2, time: float, color := Color(1, 1, 1, 0.35)) -> void:
	var rows := 7
	for row in rows:
		var y := rect.position.y + rect.size.y * (row + 0.5) / rows
		var off := fmod(time * (14.0 + row * 3.0) + row * 37.0, 90.0)
		var x := rect.position.x - 90.0 + off
		while x < rect.end.x:
			var pts := PackedVector2Array()
			for k in 7:
				pts.append(Vector2(x + k * 6.0, y + sin(k * 0.9) * 3.0))
			ci.draw_polyline(pts, color, 2.0, true)
			x += 90.0 + float((row * 13) % 40)


static func cloud(ci: CanvasItem, c: Vector2, s: float, col := Color(1, 1, 1, 0.9)) -> void:
	ci.draw_circle(c, 22.0 * s, col)
	ci.draw_circle(c + Vector2(-26, 6) * s, 16.0 * s, col)
	ci.draw_circle(c + Vector2(26, 6) * s, 18.0 * s, col)
	ci.draw_circle(c + Vector2(10, -10) * s, 16.0 * s, col)


## Pulau bergaya kartun: bayangan air, pasir, rumput, pohon kecil. dim = pulau terkunci/segera hadir.
static func island(ci: CanvasItem, c: Vector2, r: float, green: Color, sand: Color, seed: int, dim := false) -> void:
	if dim:
		green = green.lerp(Color("8a8f99"), 0.65)
		sand = sand.lerp(Color("b5b5b5"), 0.6)
	ci.draw_colored_polygon(_blob(c + Vector2(0, r * 0.1), r * 1.14, seed, 0.12), Color(0.05, 0.25, 0.45, 0.3))
	ci.draw_colored_polygon(_blob(c, r * 1.05, seed, 0.12), sand)
	ci.draw_colored_polygon(_blob(c + Vector2(0, -r * 0.06), r * 0.86, seed + 7, 0.16), green)
	ci.draw_colored_polygon(_blob(c + Vector2(-r * 0.15, -r * 0.2), r * 0.38, seed + 3, 0.2), green.lightened(0.15))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 5:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.15, 0.6) * r
		var p := c + Vector2(cos(a), sin(a) * 0.7) * d
		tree(ci, p, r * 0.13, green.darkened(0.25))


static func tree(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(p + Vector2(-s * 0.15, 0), Vector2(s * 0.3, s * 0.7)), Color("7a4a22"))
	ci.draw_circle(p, s * 0.75, col)
	ci.draw_circle(p + Vector2(-s * 0.25, -s * 0.25), s * 0.35, col.lightened(0.2))


static func _blob(c: Vector2, r: float, seed: int, wobble: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := PackedVector2Array()
	var n := 22
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	for i in n:
		var a := TAU * i / n
		var k := 1.0 + wobble * (sin(a * 3.0 + ph) * 0.6 + sin(a * 5.0 + ph2) * 0.4)
		pts.append(c + Vector2(cos(a) * r * k, sin(a) * r * k * 0.72))
	return pts


static func boat(ci: CanvasItem, p: Vector2, s: float, sail := Color("fdf6e3"), flip := false) -> void:
	var f := -1.0 if flip else 1.0
	var hull := PackedVector2Array([p + Vector2(-30 * f, -4) * s, p + Vector2(32 * f, -4) * s, p + Vector2(20 * f, 10) * s,
		p + Vector2(-20 * f, 10) * s])
	ci.draw_colored_polygon(hull, Color("8a5a2b"))
	ci.draw_line(p + Vector2(0, -4) * s, p + Vector2(0, -46) * s, Color("5a3a1a"), 3.0 * s)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(2 * f, -44) * s, p + Vector2(26 * f, -10) * s,
		p + Vector2(2 * f, -10) * s]), sail)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -46) * s, p + Vector2(-14 * f, -42) * s,
		p + Vector2(0, -38) * s]), Color("e05a4f"))


static func lock(ci: CanvasItem, p: Vector2, s: float) -> void:
	ci.draw_arc(p + Vector2(0, -6) * s, 9.0 * s, PI, TAU, 16, Color("5a5a66"), 4.0 * s, true)
	ci.draw_rect(Rect2(p + Vector2(-13, -6) * s, Vector2(26, 20) * s), Color("f0b429"))
	ci.draw_circle(p + Vector2(0, 3) * s, 3.0 * s, Color("5a3a1a"))
