extends RefCounted
## Medan pulau bergaya kartun (paket visual 5.0): satu kisi tinggi 1 m untuk seluruh pulau.
## - Tinggi = bukit dari tata letak (rumus lama, tetap persis) + gelombang tanah lembut di alam liar
##   + alur sungai yang menurun + pantai yang melandai ke laut. Jalan, tempat, bangunan, benteng, ladang,
##   dermaga diratakan (gelombang = 0) supaya bangunan & penduduk tetap berdiri rata.
## - Peta campuran (splat) RGBA 3 piksel/meter: R jalan tanah, G pelataran batu, B lantai hutan,
##   A larangan rumput (bangunan, ladang, benteng, dermaga, sungai). Dibaca shader medan & penanam rumput.
## - Satu ArrayMesh medan (resolusi mengikuti profil grafis) + HeightMapShape3D 1 m untuk tabrakan.
## Semua dihitung sekali saat pulau dibangun; ground_y() hanya rumus bukit + interpolasi bilinear.

const PPM := 3  # piksel peta campuran per meter

var radius := 70.0
var extent := 80  # setengah lebar kisi (meter), bilangan bulat
var size := 161  # titik kisi per sisi (1 m)
var hills: Array = []
var off := PackedFloat32Array()  # tinggi tambahan per titik kisi
var hgt := PackedFloat32Array()  # tinggi total (bukit + tambahan) per titik kisi
var flat := PackedFloat32Array()  # 1 = rata (tanpa gelombang)
var sp := PackedByteArray()  # data RGBA peta campuran
var sp_w := 0
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var river: Dictionary = {}
var prof: Array = []  # waktu (ms) pengecatan & kisi, untuk uji kinerja


## d: {radius, hills, river, paths, places, footprints:[[x,z,r]], rects:[[x,z,hx,hz]], forest:{pos,radius}, seed}
func setup(d: Dictionary) -> void:
	radius = float(d.radius)
	extent = int(ceil(radius)) + 10
	size = extent * 2 + 1
	hills = d.get("hills", [])
	river = d.get("river", {})
	noise.seed = int(d.get("seed", 1))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	noise2.seed = int(d.get("seed", 1)) + 17
	noise2.frequency = 0.012
	flat.resize(size * size)
	flat.fill(0.0)
	off.resize(size * size)
	hgt.resize(size * size)
	sp_w = extent * 2 * PPM
	sp.resize(sp_w * sp_w * 4)
	sp.fill(0)
	var forest: Dictionary = d.get("forest", {})
	var t0 := Time.get_ticks_usec()
	# --- daerah rata & peta campuran ---
	for seg in d.get("paths", []):
		var a := Vector2(float(seg[0][0]), float(seg[0][1]))
		var b := Vector2(float(seg[1][0]), float(seg[1][1]))
		_flat_seg(a, b, 2.6, 3.0)
		_splat_seg(0, a, b, 1.15, 2.15)
	for pl in d.get("places", []):
		var c := Vector2(float(pl.pos[0]), float(pl.pos[1]))
		if not forest.is_empty() and c.distance_to(Vector2(float(forest.pos[0]), float(forest.pos[1]))) < 3.0:
			continue
		var pr := float(pl.radius)
		if pl.has("plaza"):
			_flat_circle(c, float(pl.plaza) + 2.0, 4.0)
			_splat_circle(1, c, float(pl.plaza) - 0.6, float(pl.plaza) + 0.5)
		_flat_circle(c, pr * 0.45, pr * 0.5)
	for f in d.get("footprints", []):
		_flat_circle(Vector2(f[0], f[1]), float(f[2]) + 1.5, 3.5)
		_splat_circle(3, Vector2(f[0], f[1]), float(f[2]) - 0.2, float(f[2]) + 0.6)
	for r in d.get("rects", []):
		var rc := Vector2(r[0], r[1])
		var rr := Vector2(r[2], r[3]).length()
		_flat_circle(rc, rr + 1.5, 4.0)
		_splat_rect(3, rc, Vector2(r[2], r[3]))
	if not forest.is_empty():
		_splat_circle(2, Vector2(float(forest.pos[0]), float(forest.pos[1])), float(forest.radius) - 8.0, float(forest.radius) + 3.0)
	if not river.is_empty():
		var rz := float(river.z)
		var hw := float(river.half_width)
		_splat_rect(3, Vector2(0, rz), Vector2(extent, hw + 0.8))
	var t1 := Time.get_ticks_usec()
	# --- tinggi tambahan per titik kisi ---
	var hw2 := float(river.get("half_width", 0.0))
	var rz2 := float(river.get("z", 0.0))
	for iz in size:
		var z := float(iz - extent)
		for ix in size:
			var x := float(ix - extent)
			var i := iz * size + ix
			var r := Vector2(x, z).length()
			if r > radius + 9.5:
				off[i] = -1.42  # dasar laut di luar pulau (tidak perlu derau)
				hgt[i] = -1.42
				continue
			var n := noise.get_noise_2d(x, z)
			var y := 0.0
			var wild := 1.0 - flat[i]
			if wild > 0.0:
				# Gelombang lembut + gundukan pasir/bukit kecil di tepi pulau (cakrawala tidak datar).
				var rim := smoothstep(radius - 26.0, radius - 9.0, r) * (1.0 - smoothstep(radius - 5.0, radius - 0.5, r))
				y = (n * 0.45 + rim * (0.8 + 0.9 * (noise2.get_noise_2d(x, z) * 0.5 + 0.5))) * wild
			if not river.is_empty():
				var dz := absf(z - rz2)
				y = lerpf(y, -0.55, 1.0 - smoothstep(hw2 - 0.9, hw2 + 0.7, dz))
			# Pantai: rumput -> pasir landai -> dasar laut (air laut di y = -0.55).
			var s := r - radius + n * 1.2
			if s > -1.0:
				y *= 1.0 - smoothstep(-1.0, 1.5, s)
				y -= 0.12 * smoothstep(0.0, 2.5, s) + 1.3 * smoothstep(2.0, 7.0, s)
			off[i] = y
			hgt[i] = y + (hills_y(x, z) if not hills.is_empty() else 0.0)

	prof = [(t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0]


func hills_y(x: float, z: float) -> float:
	var y := 0.0
	for h in hills:
		var d := Vector2(x - float(h.pos[0]), z - float(h.pos[1])).length()
		var top := float(h.top)
		var bottom := float(h.bottom)
		var hh := float(h.height)
		if d <= top:
			y = maxf(y, hh)
		elif d < bottom:
			y = maxf(y, hh * (bottom - d) / (bottom - top))
	return y


func height(x: float, z: float) -> float:
	var fx := clampf(x + extent, 0.0, size - 1.001)
	var fz := clampf(z + extent, 0.0, size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * size + ix
	var a := lerpf(hgt[i], hgt[i + 1], tx)
	var b := lerpf(hgt[i + size], hgt[i + size + 1], tx)
	return lerpf(a, b, tz)


## Nilai kanal peta campuran (0..1) di (x, z): 0 jalan, 1 pelataran, 2 hutan, 3 larangan rumput.
func splat(ch: int, x: float, z: float) -> float:
	var px := int((x + extent) * PPM)
	var pz := int((z + extent) * PPM)
	if px < 0 or pz < 0 or px >= sp_w or pz >= sp_w:
		return 0.0
	return sp[(pz * sp_w + px) * 4 + ch] / 255.0


## Boleh ditumbuhi rumput/bunga (bukan jalan, pelataran, bangunan, sungai, pantai).
func grass_ok(x: float, z: float) -> bool:
	var px := int((x + extent) * PPM)
	var pz := int((z + extent) * PPM)
	if px < 0 or pz < 0 or px >= sp_w or pz >= sp_w:
		return false
	var k := (pz * sp_w + px) * 4
	if sp[k] > 60 or sp[k + 1] > 60 or sp[k + 3] > 40:
		return false
	return Vector2(x, z).length() < radius - 2.0 and height(x, z) > -0.05


func splat_texture() -> ImageTexture:
	var img := Image.create_from_data(sp_w, sp_w, false, Image.FORMAT_RGBA8, sp)
	return ImageTexture.create_from_image(img)


func collision_shape() -> HeightMapShape3D:
	var hm := HeightMapShape3D.new()
	hm.map_width = size
	hm.map_depth = size
	hm.map_data = hgt
	return hm


## Mesh medan dengan langkah `step` meter (Hemat 2 m, Seimbang 1,5 m, Tinggi 1 m). Hanya lingkaran pulau.
func build_mesh(step: float) -> ArrayMesh:
	var n := int(ceil(extent * 2.0 / step)) + 1
	var h := PackedFloat32Array()
	if is_equal_approx(step, 1.0):
		h = hgt
	else:
		h.resize(n * n)
		for iz in n:
			for ix in n:
				h[iz * n + ix] = height(-extent + ix * step, -extent + iz * step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			verts[i] = Vector3(-extent + ix * step, h[i], -extent + iz * step)
			var hl := h[i - 1] if ix > 0 else h[i]
			var hr := h[i + 1] if ix < n - 1 else h[i]
			var hd := h[i - n] if iz > 0 else h[i]
			var hu := h[i + n] if iz < n - 1 else h[i]
			norms[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	var idx := PackedInt32Array()
	var lim := float(extent) - 0.5
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			var c := verts[i]
			if Vector2(c.x + step * 0.5, c.z + step * 0.5).length() > lim + step:
				continue
			idx.append_array([i, i + 1, i + n, i + 1, i + n + 1, i + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- pengecatan kisi rata (1 m) ---------------------------------------------------------------------

func _flat_circle(c: Vector2, r: float, feather: float) -> void:
	var R := r + feather
	for iz in range(maxi(0, int(c.y - R) + extent), mini(size, int(c.y + R) + extent + 2)):
		for ix in range(maxi(0, int(c.x - R) + extent), mini(size, int(c.x + R) + extent + 2)):
			var d := Vector2(ix - extent, iz - extent).distance_to(c)
			if d < R:
				var i := iz * size + ix
				flat[i] = maxf(flat[i], 1.0 - smoothstep(r, R, d))


func _flat_seg(a: Vector2, b: Vector2, r: float, feather: float) -> void:
	var R := r + feather
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(R, R)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(R, R)
	for iz in range(maxi(0, int(lo.y) + extent), mini(size, int(hi.y) + extent + 2)):
		for ix in range(maxi(0, int(lo.x) + extent), mini(size, int(hi.x) + extent + 2)):
			var d := _seg_dist(Vector2(ix - extent, iz - extent), a, b)
			if d < R:
				var i := iz * size + ix
				flat[i] = maxf(flat[i], 1.0 - smoothstep(r, R, d))


# --- pengecatan peta campuran (PPM piksel/meter) ----------------------------------------------------

func _put(px: int, pz: int, ch: int, v: float) -> void:
	var k := (pz * sp_w + px) * 4 + ch
	var b := int(clampf(v, 0.0, 1.0) * 255.0)
	if b > sp[k]:
		sp[k] = b


func _splat_circle(ch: int, c: Vector2, r0: float, r1: float) -> void:
	var p0 := Vector2i(maxi(0, int((c.x - r1 + extent) * PPM)), maxi(0, int((c.y - r1 + extent) * PPM)))
	var p1 := Vector2i(mini(sp_w, int((c.x + r1 + extent) * PPM) + 2), mini(sp_w, int((c.y + r1 + extent) * PPM) + 2))
	for pz in range(p0.y, p1.y):
		var z := (pz + 0.5) / PPM - extent
		for px in range(p0.x, p1.x):
			var d := Vector2((px + 0.5) / PPM - extent, z).distance_to(c)
			if d < r1:
				_put(px, pz, ch, 1.0 - smoothstep(r0, r1, d))


func _splat_rect(ch: int, c: Vector2, half: Vector2) -> void:
	var p0 := Vector2i(maxi(0, int((c.x - half.x + extent) * PPM)), maxi(0, int((c.y - half.y + extent) * PPM)))
	var p1 := Vector2i(mini(sp_w, int((c.x + half.x + extent) * PPM) + 1), mini(sp_w, int((c.y + half.y + extent) * PPM) + 1))
	for pz in range(p0.y, p1.y):
		for px in range(p0.x, p1.x):
			_put(px, pz, ch, 1.0)


## Jalan: per baris piksel hanya rentang x yang mungkin dekat ruas (hemat untuk ruas diagonal).
func _splat_seg(ch: int, a: Vector2, b: Vector2, r0: float, r1: float) -> void:
	var lo_z := maxi(0, int((minf(a.y, b.y) - r1 + extent) * PPM))
	var hi_z := mini(sp_w, int((maxf(a.y, b.y) + r1 + extent) * PPM) + 2)
	var dz := b.y - a.y
	for pz in range(lo_z, hi_z):
		var z := (pz + 0.5) / PPM - extent
		var t0 := 0.0
		var t1 := 1.0
		if absf(dz) > 0.001:
			t0 = clampf(minf((z - r1 - a.y) / dz, (z + r1 - a.y) / dz), 0.0, 1.0)
			t1 = clampf(maxf((z - r1 - a.y) / dz, (z + r1 - a.y) / dz), 0.0, 1.0)
		elif absf(z - a.y) > r1:
			continue
		var x0 := minf(a.x + (b.x - a.x) * t0, a.x + (b.x - a.x) * t1) - r1
		var x1 := maxf(a.x + (b.x - a.x) * t0, a.x + (b.x - a.x) * t1) + r1
		for px in range(maxi(0, int((x0 + extent) * PPM)), mini(sp_w, int((x1 + extent) * PPM) + 2)):
			var d := _seg_dist(Vector2((px + 0.5) / PPM - extent, z), a, b)
			if d < r1:
				_put(px, pz, ch, 1.0 - smoothstep(r0, r1, d))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
