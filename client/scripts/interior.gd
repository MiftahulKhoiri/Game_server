extends RefCounted
## Ruangan di dalam bangunan Desa Awal (toko ramuan, rumah makan, rumah sehat). Digambar dengan kotak dan
## tabung sederhana (tanpa aset luar). Bentuk ruangan dari Maps.rows(): H dinding, = lantai, D pintu keluar,
## S meja kasir, x lantai di belakang meja (tempat penjaga), R rak (ranjang di rumah sehat),
## F tong (toko ramuan) / meja makan (rumah makan) / tanaman (rumah sehat).
## Dinding depan dibuat rendah dan tanpa atap, supaya kamera dari atas-belakang tetap melihat isi ruangan.

const Maps = preload("res://scripts/maps.gd")

const WALL_H := 1.7
const COUNTER_H := 0.46  # tinggi meja kasir: rendah supaya penjaga di belakangnya kelihatan dari kamera
const FRONT_H := 0.42  # dinding depan (baris terakhir) rendah supaya tidak menutupi pemain

## Warna per ruangan: dinding, lantai (dua nada), meja kasir, karpet.
const LOOK := {
	"toko_ramuan": {"wall": Color("a8764a"), "trim": Color("6b4426"), "floor_a": Color("c9a066"), "floor_b": Color("bd9459"), "counter": Color("7a4a26"), "top": Color("c28a4c"), "rug": Color("8e3a2c"), "sign": "TOKO RAMUAN"},
	"rumah_makan": {"wall": Color("b98552"), "trim": Color("6e4527"), "floor_a": Color("c4985c"), "floor_b": Color("b78b50"), "counter": Color("6e4326"), "top": Color("d49a58"), "rug": Color("3a5a8e"), "sign": "RUMAH MAKAN"},
	"toko_peralatan": {"wall": Color("8a7f74"), "trim": Color("4f4a46"), "floor_a": Color("a89d8c"), "floor_b": Color("9b9080"), "counter": Color("4d5058"), "top": Color("8a6a44"), "rug": Color("7a2f2f"), "sign": "TOKO PERALATAN"},
	"aula_pelatihan": {"wall": Color("7a7390"), "trim": Color("3f3a58"), "floor_a": Color("b3a68c"), "floor_b": Color("a69a80"), "counter": Color("4d5058"), "top": Color("8a6a44"), "rug": Color("3a5a8e"), "sign": "AULA PELATIHAN"},
	"penginapan": {"wall": Color("b07a4e"), "trim": Color("5e3a22"), "floor_a": Color("b88a5a"), "floor_b": Color("aa7e50"), "counter": Color("6a4024"), "top": Color("c88e52"), "rug": Color("7a3a5a"), "sign": "PENGINAPAN"},
	"rumah_pemain": {"wall": Color("c9a77a"), "trim": Color("6b4a2c"), "floor_a": Color("a87a4c"), "floor_b": Color("9c7046"), "counter": Color("6a4024"), "top": Color("c88e52"), "rug": Color("3a6a4a"), "sign": "RUMAHKU"},
	"rumah_sehat": {"wall": Color("d2dcdf"), "trim": Color("93a8ae"), "floor_a": Color("b9c8cd"), "floor_b": Color("aebec4"), "counter": Color("9fb4ba"), "top": Color("dfe9ec"), "rug": Color("4aa3a0"), "sign": "RUMAH SEHAT"},
}

static var _mats: Dictionary = {}


static func _mat(color: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	_mats[key] = m
	return m


static func _put(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_y := 0.0, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, rough)
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(r_top: float, r_bottom: float, h: float, segs := 14) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func _ball(r: float, flat := 1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 * flat
	m.radial_segments = 12
	m.rings = 6
	return m


static func _is(rows: Array[String], x: int, z: int, ch: String) -> bool:
	return z >= 0 and z < rows.size() and x >= 0 and x < rows[z].length() and rows[z][x] == ch


static func build(map_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Medan"
	root.set_meta("breakables", [])  # ruangan tidak punya benda yang bisa dihancurkan
	var look: Dictionary = LOOK.get(map_id, LOOK["toko_ramuan"])
	var rows := Maps.rows(map_id)
	var h := rows.size()
	var w := rows[0].length()
	# Lantai di bawah dan di luar ruangan: gelap, supaya tepi layar tidak kosong.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = _mat(Color("1d1710"))
	ground.position = Vector3(w / 2.0, -0.05, h / 2.0)
	root.add_child(ground)

	for z in h:
		for x in w:
			var t: String = rows[z][x]
			var c := Vector3(x + 0.5, 0.0, z + 0.5)
			if t == "H":
				_wall(root, look, rows, x, z, c)
				continue
			var fa: Color = look.floor_a if (x + z) % 2 == 0 else look.floor_b
			_put(root, _box(Vector3(1.0, 0.1, 1.0)), fa, c + Vector3(0, -0.05, 0), 0.0, 0.95)
			match t:
				"D":
					_door(root, look, c)
				"S":
					_counter(root, map_id, look, rows, x, z, c)
				"R":
					if map_id == Maps.RUMAH_SEHAT or map_id == Maps.PENGINAPAN or map_id == Maps.RUMAH_PEMAIN:
						_bed(root, c)
					else:
						_shelf(root, map_id, c)
				"L":  # lemari / rak (no. 124)
					_cupboard(root, c)
				"P":  # perapian
					_fireplace(root, c)
				"Q":  # tanaman pot
					_plant(root, c)
				"F":
					match map_id:
						Maps.TOKO_RAMUAN:
							_barrel(root, c)
						Maps.RUMAH_MAKAN, Maps.PENGINAPAN, Maps.RUMAH_PEMAIN:
							_dining_table(root, c)
						Maps.TOKO_ALAT:
							_armor_stand(root, c)
						Maps.AULA:
							_dummy(root, c)
						_:
							_plant(root, c)
	if map_id == Maps.AULA:  # dua panggung pelatih: kiri pahlawan (merah), kanan prajurit (hijau)
		_dais(root, Vector3(4.0, 0.0, 2.6), Color("a33a3a"))
		_dais(root, Vector3(7.0, 0.0, 2.6), Color("4f9a4a"))
	_rug(root, look, w, h)
	_sign(root, look, w)
	_lights(root, map_id, w, h)
	return root


static func _wall(root: Node3D, look: Dictionary, rows: Array[String], x: int, z: int, c: Vector3) -> void:
	var front := z == rows.size() - 1 and not _is(rows, x, z, "D")
	var hh := FRONT_H if front else WALL_H
	_put(root, _box(Vector3(1.0, hh, 1.0)), look.wall, c + Vector3(0, hh / 2.0, 0))
	_put(root, _box(Vector3(1.06, 0.1, 1.06)), look.trim, c + Vector3(0, hh + 0.02, 0))  # tepi atas
	if not front:
		_put(root, _box(Vector3(1.02, 0.18, 1.02)), look.trim, c + Vector3(0, 0.09, 0))  # papan bawah


static func _door(root: Node3D, look: Dictionary, c: Vector3) -> void:
	# Pintu keluar di dinding depan: keset terang di lantai dengan tulisan "Keluar" (rendah, tidak menutupi pemain).
	_put(root, _box(Vector3(0.9, 0.05, 0.9)), Color("e8d49a"), c + Vector3(0, 0.02, 0))
	_put(root, _box(Vector3(1.1, 0.12, 0.12)), look.trim, c + Vector3(0, 0.06, 0.5))
	var label := Label3D.new()
	label.text = "Keluar"
	label.font_size = 40
	label.pixel_size = 0.0045
	label.outline_size = 6
	label.modulate = Color("5a3a14")
	label.outline_modulate = Color(1, 1, 1, 0.0)
	label.rotation_degrees = Vector3(-90, 0, 0)  # tertulis di lantai, terbaca dari kamera
	label.position = c + Vector3(0, 0.07, -0.05)
	root.add_child(label)


static func _counter(root: Node3D, map_id: String, look: Dictionary, rows: Array[String], x: int, z: int, c: Vector3) -> void:
	_put(root, _box(Vector3(1.0, COUNTER_H, 0.8)), look.counter, c + Vector3(0, COUNTER_H / 2.0, 0.04))
	_put(root, _box(Vector3(1.04, 0.07, 0.9)), look.top, c + Vector3(0, COUNTER_H + 0.035, 0.04))
	var ci := c + Vector3(0, COUNTER_H - 0.82, 0)  # barang di meja ikut turun sesuai tinggi meja
	var first := x == 1
	var mid := x == 4
	if map_id == Maps.TOKO_RAMUAN:
		if x == 2 or x == 6:  # botol di atas meja
			_bottle(root, ci + Vector3(-0.15, 0.89, 0.0), Color("d6423a"))
			_bottle(root, ci + Vector3(0.15, 0.89, 0.05), Color("3d8fe0"))
		if mid:  # timbangan sederhana
			_put(root, _cyl(0.02, 0.02, 0.3, 8), Color("5a5a60"), ci + Vector3(0, 1.04, 0.0))
			_put(root, _box(Vector3(0.5, 0.03, 0.04)), Color("5a5a60"), ci + Vector3(0, 1.19, 0.0))
	elif map_id == Maps.TOKO_ALAT:
		if x == 2 or x == 6:  # pedang tergeletak di atas meja
			_put(root, _box(Vector3(0.5, 0.025, 0.07)), Color("cfd6dc"), ci + Vector3(0, 0.9, 0.0), 0.0, 0.3)
			_put(root, _box(Vector3(0.05, 0.04, 0.2)), Color("d4a72c"), ci + Vector3(-0.17, 0.91, 0.0))
			_put(root, _box(Vector3(0.14, 0.035, 0.05)), Color("5e3c20"), ci + Vector3(-0.3, 0.91, 0.0))
		if mid:  # landasan tempa
			_put(root, _box(Vector3(0.4, 0.14, 0.22)), Color("3a3d44"), ci + Vector3(0, 0.97, 0.0))
			_put(root, _box(Vector3(0.2, 0.12, 0.14)), Color("2e3036"), ci + Vector3(0, 0.87, 0.0))
	elif map_id == Maps.RUMAH_MAKAN:
		if x == 2 or x == 6:  # roti di piring
			_put(root, _cyl(0.2, 0.2, 0.025, 14), Color("f4f0e6"), ci + Vector3(0, 0.9, 0.0))
			_put(root, _ball(0.13, 0.7), Color("d99c4a"), ci + Vector3(-0.05, 0.98, 0.0))
			_put(root, _ball(0.1, 0.7), Color("e8b266"), ci + Vector3(0.1, 0.96, 0.05))
		if mid:  # panci sup
			_put(root, _cyl(0.2, 0.17, 0.26, 14), Color("4a4a52"), ci + Vector3(0, 1.0, 0.0))
			_put(root, _cyl(0.17, 0.17, 0.02, 14), Color("e0902c"), ci + Vector3(0, 1.12, 0.0))
	else:
		if x == 2 or x == 6:  # kotak P3K
			_put(root, _box(Vector3(0.3, 0.2, 0.2)), Color("f4f4f4"), ci + Vector3(0, 0.99, 0.0))
			_put(root, _box(Vector3(0.1, 0.04, 0.21)), Color("d83a3a"), ci + Vector3(0, 1.0, 0.0))
			_put(root, _box(Vector3(0.04, 0.1, 0.21)), Color("d83a3a"), ci + Vector3(0, 1.0, 0.0))
	if first or x == 7:  # ujung meja sedikit lebih tinggi (tepi)
		_put(root, _box(Vector3(0.1, 0.12, 0.95)), look.trim, ci + Vector3(-0.45 if first else 0.45, 0.9, 0.02))


static func _bottle(root: Node3D, p: Vector3, color: Color) -> void:
	_put(root, _cyl(0.07, 0.08, 0.18, 10), color, p + Vector3(0, 0.09, 0), 0.0, 0.3)
	_put(root, _cyl(0.03, 0.03, 0.08, 8), color.lightened(0.15), p + Vector3(0, 0.22, 0), 0.0, 0.3)
	_put(root, _cyl(0.035, 0.035, 0.03, 8), Color("c79a5a"), p + Vector3(0, 0.275, 0))


static func _shelf(root: Node3D, map_id: String, c: Vector3) -> void:
	# Rak menempel di dinding belakang: badan, tiga papan, dan barang dagangan.
	var back := c + Vector3(0, 0, -0.28)
	_put(root, _box(Vector3(0.98, 1.4, 0.4)), Color("5e3c20"), back + Vector3(0, 0.7, 0))
	for i in 3:
		var y := 0.28 + i * 0.4
		_put(root, _box(Vector3(0.94, 0.04, 0.42)), Color("8a5a30"), back + Vector3(0, y, 0.02))
	var seed_i := int(c.x * 7.0) % 5
	var palette := [Color("d6423a"), Color("e8902c"), Color("3d8fe0"), Color("46b850"), Color("a05ad8")]
	for i in 3:
		var y2 := 0.3 + i * 0.4
		for k in 3:
			var px := -0.3 + k * 0.3
			var col: Color = palette[(seed_i + i * 2 + k) % palette.size()]
			if map_id == Maps.TOKO_RAMUAN:
				_bottle(root, back + Vector3(px, y2, 0.05), col)
			elif map_id == Maps.TOKO_ALAT or map_id == Maps.AULA:
				_gear_item(root, back + Vector3(px, y2, 0.05), (i + k) % 3)
			else:
				if (i + k) % 2 == 0:  # toples
					_put(root, _cyl(0.1, 0.1, 0.2, 10), Color("e8d8a8"), back + Vector3(px, y2 + 0.11, 0.05), 0.0, 0.3)
					_put(root, _cyl(0.105, 0.105, 0.04, 10), Color("8a5a30"), back + Vector3(px, y2 + 0.22, 0.05))
				else:  # roti
					_put(root, _ball(0.12, 0.75), Color("d99c4a").lerp(col, 0.15), back + Vector3(px, y2 + 0.08, 0.05))


## Barang di rak toko peralatan: 0 pedang berdiri, 1 perisai bulat, 2 helm.
static func _gear_item(root: Node3D, p: Vector3, kind: int) -> void:
	match kind:
		0:
			_put(root, _box(Vector3(0.06, 0.3, 0.02)), Color("cfd6dc"), p + Vector3(0, 0.2, 0), 0.0, 0.3)
			_put(root, _box(Vector3(0.18, 0.03, 0.04)), Color("d4a72c"), p + Vector3(0, 0.05, 0))
			_put(root, _box(Vector3(0.035, 0.07, 0.035)), Color("5e3c20"), p + Vector3(0, 0.0, 0))
		1:
			var sh := _put(root, _cyl(0.13, 0.13, 0.03, 14), Color("2f5fa8"), p + Vector3(0, 0.15, 0.04))
			sh.rotation_degrees.x = 90.0
			var bo := _put(root, _cyl(0.04, 0.04, 0.04, 8), Color("d4a72c"), p + Vector3(0, 0.15, 0.06))
			bo.rotation_degrees.x = 90.0
		_:
			_put(root, _ball(0.12, 0.9), Color("a9b1b8"), p + Vector3(0, 0.12, 0), 0.0, 0.35)
			_put(root, _box(Vector3(0.2, 0.03, 0.1)), Color("6c737a"), p + Vector3(0, 0.07, 0.07))


static func _armor_stand(root: Node3D, c: Vector3) -> void:
	_put(root, _cyl(0.03, 0.03, 0.9, 8), Color("5e3c20"), c + Vector3(0, 0.45, 0))
	_put(root, _cyl(0.22, 0.26, 0.3, 4), Color("2a2c30"), c + Vector3(0, 0.03, 0))
	_put(root, _box(Vector3(0.42, 0.5, 0.24)), Color("8d949b"), c + Vector3(0, 0.95, 0), 0.0, 0.4)
	_put(root, _box(Vector3(0.12, 0.4, 0.26)), Color("8d949b"), c + Vector3(-0.27, 0.95, 0), 0.0, 0.4)
	_put(root, _box(Vector3(0.12, 0.4, 0.26)), Color("8d949b"), c + Vector3(0.27, 0.95, 0), 0.0, 0.4)
	_put(root, _ball(0.14, 0.95), Color("a9b1b8"), c + Vector3(0, 1.35, 0), 0.0, 0.35)
	_put(root, _box(Vector3(0.05, 0.1, 0.28)), Color("b23a3a"), c + Vector3(0, 1.5, 0))


## Panggung kecil tempat pelatih berdiri.
static func _dais(root: Node3D, c: Vector3, color: Color) -> void:
	_put(root, _box(Vector3(1.8, 0.04, 1.6)), color.darkened(0.3), c + Vector3(0, 0.02, 0))
	_put(root, _box(Vector3(1.6, 0.05, 1.4)), color, c + Vector3(0, 0.03, 0))


## Boneka latihan: tiang kayu, badan jerami, dan lingkaran sasaran.
static func _dummy(root: Node3D, c: Vector3) -> void:
	_put(root, _cyl(0.05, 0.06, 1.1, 8), Color("5e3c20"), c + Vector3(0, 0.55, 0))
	_put(root, _box(Vector3(0.7, 0.1, 0.1)), Color("5e3c20"), c + Vector3(0, 0.85, 0))
	_put(root, _cyl(0.25, 0.28, 0.5, 10), Color("c9a86a"), c + Vector3(0, 0.82, 0))
	_put(root, _ball(0.17, 0.95), Color("d6b87a"), c + Vector3(0, 1.28, 0))
	var tp := _put(root, _cyl(0.2, 0.2, 0.02, 14), Color("b23a3a"), c + Vector3(0, 0.84, 0.27))
	tp.rotation_degrees.x = 90.0
	var tp2 := _put(root, _cyl(0.1, 0.1, 0.03, 14), Color("f2e6c4"), c + Vector3(0, 0.84, 0.275))
	tp2.rotation_degrees.x = 90.0
	_put(root, _cyl(0.3, 0.34, 0.06, 10), Color("3a3a40"), c + Vector3(0, 0.03, 0))


static func _barrel(root: Node3D, c: Vector3) -> void:
	_put(root, _cyl(0.33, 0.38, 0.72, 14), Color("8a5a2e"), c + Vector3(0, 0.36, 0))
	for y in [0.18, 0.54]:
		_put(root, _cyl(0.385, 0.385, 0.05, 14), Color("3a3a40"), c + Vector3(0, y, 0))
	_put(root, _cyl(0.3, 0.3, 0.02, 14), Color("b07a40"), c + Vector3(0, 0.73, 0))


static func _dining_table(root: Node3D, c: Vector3) -> void:
	_put(root, _cyl(0.32, 0.32, 0.06, 16), Color("b97a40"), c + Vector3(0, 0.66, 0))
	_put(root, _cyl(0.07, 0.1, 0.62, 10), Color("6e4326"), c + Vector3(0, 0.33, 0))
	_put(root, _cyl(0.13, 0.13, 0.02, 12), Color("f4f0e6"), c + Vector3(0.05, 0.7, 0.03))
	_put(root, _ball(0.08, 0.7), Color("d99c4a"), c + Vector3(0.05, 0.75, 0.03))
	for sz in [-0.4, 0.4]:  # dua bangku di depan dan belakang meja
		_put(root, _cyl(0.1, 0.09, 0.05, 10), Color("7a4a26"), c + Vector3(0, 0.34, sz))
		_put(root, _cyl(0.04, 0.05, 0.32, 8), Color("5e3c20"), c + Vector3(0, 0.16, sz))


static func _bed(root: Node3D, c: Vector3) -> void:
	_put(root, _box(Vector3(0.9, 0.26, 0.95)), Color("8a6a4a"), c + Vector3(0, 0.2, 0))
	_put(root, _box(Vector3(0.82, 0.14, 0.88)), Color("f6f8f8"), c + Vector3(0, 0.38, 0))
	_put(root, _box(Vector3(0.84, 0.06, 0.5)), Color("4a8fd0"), c + Vector3(0, 0.46, 0.2))
	_put(root, _box(Vector3(0.5, 0.1, 0.22)), Color("ffffff"), c + Vector3(0, 0.5, -0.32))


## Lemari kayu dua pintu dengan gagang (roadmap no. 124).
static func _cupboard(root: Node3D, c: Vector3) -> void:
	_put(root, _box(Vector3(0.9, 1.25, 0.5)), Color("7a4e2c"), c + Vector3(0, 0.625, -0.2))
	_put(root, _box(Vector3(0.02, 1.1, 0.02)), Color("4a2e18"), c + Vector3(0, 0.62, 0.06))
	for gx in [-0.08, 0.08]:
		_put(root, _ball(0.03), Color("e0c060"), c + Vector3(gx, 0.7, 0.07))
	_put(root, _box(Vector3(0.96, 0.06, 0.56)), Color("5e3a20"), c + Vector3(0, 1.28, -0.2))


## Perapian batu dengan api menyala dan cahaya hangat.
static func _fireplace(root: Node3D, c: Vector3) -> void:
	_put(root, _box(Vector3(1.0, 1.1, 0.5)), Color("8a8478"), c + Vector3(0, 0.55, -0.22))
	_put(root, _box(Vector3(0.6, 0.5, 0.1)), Color("2a2420"), c + Vector3(0, 0.3, 0.04))
	_put(root, _box(Vector3(1.1, 0.08, 0.6)), Color("6b655d"), c + Vector3(0, 1.12, -0.2))
	var api := _put(root, _ball(0.14, 1.4), Color("ff9a3a"), c + Vector3(0, 0.22, 0.02))
	var fm := (api.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D  # bahan sendiri (bahan _mat dibagi)
	fm.emission_enabled = true
	fm.emission = Color("ff7a1a")
	api.material_override = fm
	var o := OmniLight3D.new()
	o.light_color = Color("ffa050")
	o.light_energy = 0.7
	o.omni_range = 3.5
	o.position = c + Vector3(0, 0.5, 0.3)
	root.add_child(o)


static func _plant(root: Node3D, c: Vector3) -> void:
	_put(root, _cyl(0.22, 0.17, 0.3, 12), Color("b86a3a"), c + Vector3(0, 0.15, 0))
	_put(root, _ball(0.3), Color("3f9a4a"), c + Vector3(0, 0.55, 0))
	_put(root, _ball(0.2), Color("55b560"), c + Vector3(0.1, 0.8, 0.05))


static func _rug(root: Node3D, look: Dictionary, w: int, h: int) -> void:
	var cx := w / 2.0
	var cz := h - 2.6
	_put(root, _box(Vector3(3.0, 0.02, 1.6)), (look.rug as Color).darkened(0.25), Vector3(cx, 0.015, cz))
	_put(root, _box(Vector3(2.7, 0.025, 1.3)), look.rug, Vector3(cx, 0.02, cz))


static func _sign(root: Node3D, look: Dictionary, w: int) -> void:
	# Papan nama di dinding belakang, di atas rak.
	_put(root, _box(Vector3(2.6, 0.34, 0.06)), Color("3a2514"), Vector3(w / 2.0, 1.52, 1.02))
	var label := Label3D.new()
	label.text = str(look.sign)
	label.font_size = 44
	label.pixel_size = 0.0055
	label.outline_size = 10
	label.modulate = Color("ffe08a")
	label.position = Vector3(w / 2.0, 1.52, 1.06)
	root.add_child(label)


static func _lights(root: Node3D, map_id: String, w: int, h: int) -> void:
	var warm := Color("ffd9a0") if map_id != Maps.RUMAH_SEHAT else Color("f2fbff")
	for p: Vector3 in [Vector3(w / 2.0, 1.55, 2.4), Vector3(w / 2.0, 1.55, h - 2.6)]:
		var o := OmniLight3D.new()
		o.light_color = warm
		o.light_energy = 0.85
		o.omni_range = 7.0
		o.position = p
		root.add_child(o)
