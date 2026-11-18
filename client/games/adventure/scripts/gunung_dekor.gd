extends RefCounted
## Tampilan Lereng Gunung Berapi (Bab 3 The Last Dragon). Paket adventure 1.3.0.
##
## Hanya tampilan: petak, tabrakan, musuh, dan data server tidak berubah. Dipanggil world_build.gd.
##   - Tanah abu vulkanik gelap (bukan pasir), jalan tanah kemerahan, tanah memerah di dekat lava.
##   - Batu KayKit digelapkan jadi batu basal hangus (bahan disalin sekali per model, tekstur tetap).
##   - Retakan lava menyala di lantai dan lubang asap kecil (dirakit rakit.gd: beberapa panggilan gambar saja).
##   - Di cakrawala: dua kerucut gunung berapi berkawah menyala dengan aliran lava dan gumpalan asap.

const Maps = preload("res://games/adventure/scripts/maps.gd")
const Rakit = preload("res://games/adventure/scripts/rakit.gd")

static var _rock_mats: Dictionary = {}


static func applies(map_id: String) -> bool:
	return map_id == Maps.GUNUNG


static func _j(x: int, z: int, salt := 0) -> float:
	var hsh := (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	return float(absi(hsh) % 1000) / 1000.0


static func _t(rows: Array[String], x: int, z: int) -> String:
	if z < 0 or z >= rows.size() or x < 0 or x >= rows[z].length():
		return "R"
	return rows[z][x]


static func _dekat_lava(rows: Array[String], x: int, z: int, r := 1) -> bool:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if _t(rows, x + dx, z + dz) == "L":
				return true
	return false


## Warna tanah petak `t` di lereng gunung berapi (menggantikan warna pasir/kerikil umum).
static func ground(t: String, gc: Color, rows: Array[String], x: int, z: int) -> Color:
	var j := _j(x, z, 3)
	var c := gc
	match t:
		"M", "X":
			c = Color("463a35").lerp(Color("5a4a40"), j)
		"G":
			c = Color("3a302c").lerp(Color("4a3c34"), j)
		"=":
			c = Color("6e4632").lerp(Color("7e5238"), j)
		"Z":
			c = Color("2e2624")
	if _dekat_lava(rows, x, z):
		c = c.lerp(Color("a2401a"), 0.35)
	return c


## Bahan batu yang digelapkan untuk model `mesh` (dibuat sekali, tekstur asli tetap dipakai).
static func rock_mat(mesh: Mesh) -> Material:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var key := mesh.get_rid().get_id()
	if _rock_mats.has(key):
		return _rock_mats[key]
	var src := mesh.surface_get_material(0)
	var m: StandardMaterial3D
	if src is StandardMaterial3D:
		m = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		m = StandardMaterial3D.new()
	m.albedo_color = m.albedo_color * Color(0.5, 0.42, 0.4)
	m.roughness = 0.95
	_rock_mats[key] = m
	return m


## Gaya bagian: warna + kelompok rakit (pendar = menyala/tanpa bayangan cahaya).
static func _m(_key: String, col: Color, glow := 0.0, unshaded := false) -> Dictionary:
	return {"c": col, "k": "pendar" if glow > 0.0 or unshaded else "padat"}


static func _part(r: Rakit, mesh: Mesh, gaya: Dictionary, pos: Vector3, rot := Vector3.ZERO, bayangan := false) -> void:
	var k: String = gaya.k
	if k == "padat" and not bayangan:
		k = "rata"
	r.bentuk(mesh, pos, gaya.c, k, rot)


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cyl(rt: float, rb: float, h: float, segs := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func build(root: Node3D, rows: Array[String]) -> void:
	var r := Rakit.new()
	var retak := _m("retak", Color("ff6a1a"), 1.3)
	var abu := _m("abu", Color("2c2422"))
	var n_retak := 0
	for z in rows.size():
		for x in rows[z].length():
			var t: String = rows[z][x]
			if t != "M" and t != "G":
				continue
			var c := Vector3(x + 0.5, 0.0, z + 0.5)
			var acak := _j(x, z, 5)
			if acak < 0.09:  # retakan lava: dua-tiga garis tipis menyala
				var a := _j(x, z, 6) * TAU
				for k in 2 + int(_j(x, z, 7) * 2.0):
					var len := 0.45 + 0.4 * _j(x, z, 8 + k)
					var off := Vector3(cos(a), 0, sin(a)) * (k - 1) * 0.28
					_part(r, _box(Vector3(len, 0.012, 0.045)), retak, c + off + Vector3(0, 0.008, 0), Vector3(0, a + (k - 1) * 0.7, 0))
					a += 0.9
				n_retak += 1
			elif acak > 0.985:  # lubang asap kecil: gundukan abu dengan mulut menyala
				_part(r, _cyl(0.18, 0.42, 0.22, 8), abu, c + Vector3(0, 0.11, 0), Vector3.ZERO, true)
				_part(r, _cyl(0.12, 0.12, 0.02, 8), retak, c + Vector3(0, 0.225, 0))
	r.pasang(root, "Gunung")
	root.set_meta("retak_lava", n_retak)
	_cakrawala(root, rows)


## Kerucut gunung berapi di cakrawala (di luar peta, tanpa batas jarak gambar).
static func _cakrawala(root: Node3D, rows: Array[String]) -> void:
	var w := float(rows[0].length())
	var h := float(rows.size())
	var jauh := Node3D.new()
	jauh.name = "GunungJauh"
	var rs := Rakit.new()
	var badan := _m("gunung_badan", Color("2a2220"))
	var lereng := _m("gunung_lereng", Color("3a2c26"))
	var kawah := _m("kawah", Color("ff7a24"), 2.0)
	var alir := _m("alir", Color("ff5a14"), 1.5)
	var asap := _m("asap", Color("5a4c48"), 0.0, true)
	var puncak: Array = [[Vector3(w * 0.42, 0, -26.0), 22.0, 28.0], [Vector3(w * 0.85, 0, -30.0), 16.0, 22.0], [Vector3(w * 0.18, 0, h + 26.0), 14.0, 18.0]]
	for p: Array in puncak:
		var pos: Vector3 = p[0]
		var r: float = p[1]
		var tinggi: float = p[2]
		_part(rs, _cyl(r * 0.18, r, tinggi, 20), badan, pos + Vector3(0, tinggi * 0.5, 0))
		_part(rs, _cyl(r * 0.5, r * 1.15, tinggi * 0.3, 20), lereng, pos + Vector3(0, tinggi * 0.15, 0))
		_part(rs, _cyl(r * 0.15, r * 0.15, 0.4, 16), kawah, pos + Vector3(0, tinggi + 0.1, 0))
		for k in 4:  # aliran lava menuruni lereng (kotak panjang sejajar lereng, dari kaki ke dekat kawah)
			var a := k * 1.7 + 0.4
			var luar := Vector3(cos(a), 0, sin(a))
			var kaki := pos + luar * r * 0.95
			var atas := pos + luar * r * 0.17 + Vector3(0, tinggi, 0)
			var yv := (atas - kaki).normalized()
			var xv := yv.cross(luar).normalized()
			var zv := xv.cross(yv)
			rs.tambah(_box(Vector3(0.7, (atas - kaki).length(), 0.25)), Transform3D(Basis(xv, yv, zv), (atas + kaki) * 0.5 + luar * 0.35), alir.c, "pendar")
		for k in 5:  # gumpalan asap di atas kawah
			var s := r * (0.25 + 0.09 * k)
			var bola := SphereMesh.new()
			bola.radius = s
			bola.height = s * 1.6
			bola.radial_segments = 10
			bola.rings = 5
			_part(rs, bola, asap, pos + Vector3(k * 1.6, tinggi + 2.0 + k * s * 0.9, -k * 0.8))
	rs.pasang(jauh, "Jauh")
	root.add_child(jauh)
