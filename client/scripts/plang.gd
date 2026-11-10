extends RefCounted
## Plang (papan nama) dan ikon atap bangunan toko di Desa Awal: rumah makan (piza), toko ramuan (botol ramuan),
## toko peralatan (pedang dan kapak bersilang), rumah sehat (palang merah). Digambar dengan kotak, tabung, dan bola
## (tanpa aset luar). Ikon berdiri tegak di atap menghadap selatan (arah kamera); plang berdiri di depan bangunan,
## di sebelah jalan menuju pintu.

const FONT := "res://assets/fonts/LilitaOne-Regular.ttf"

## Tulisan plang depan dan warna papannya per jenis bangunan (kunci = jenis di world_build BANGUNAN_KHUSUS).
const PLANG := {
	"toko": {"teks": "TOKO\nRAMUAN", "papan": Color("3f5fa8")},
	"dapur": {"teks": "RUMAH\nMAKAN", "papan": Color("b5532a")},
	"peralatan": {"teks": "TOKO\nPERALATAN", "papan": Color("4d5058")},
	"rumah_sakit": {"teks": "RUMAH\nSEHAT", "papan": Color("2f8f86")},
	"aula": {"teks": "AULA\nPELATIHAN", "papan": Color("6a3fa0")},
	"pandai_besi": {"teks": "PANDAI\nBESI", "papan": Color("5a4a40")},
	"kuil": {"teks": "KUIL\nDESA", "papan": Color("c9a23a")},
	"bangsawan": {"teks": "RUMAH\nBANGSAWAN", "papan": Color("7a3fa0")},
	"lumbung": {"teks": "LUMBUNG\nDESA", "papan": Color("8a6a2a")},
	"markas": {"teks": "MARKAS\nPENJAGA", "papan": Color("8a2a2a")},
	"penginapan": {"teks": "PENGINAPAN", "papan": Color("2f6a8a")},
	"rumah_pemain": {"teks": "RUMAH\nPETUALANG", "papan": Color("3f7a3f")},
}

## Letak ikon atap per jenis: (tinggi sebagai bagian dari tinggi bangunan, geser z dari muka bangunan; negatif = masuk ke atap).
const IKON_POS := {
	"toko": Vector2(0.8, -0.8),
	"dapur": Vector2(0.6, 0.5),
	"peralatan": Vector2(0.58, 0.35),
	"rumah_sakit": Vector2(0.42, 0.35),
	"aula": Vector2(0.55, 0.35),
}

static var _mats: Dictionary = {}


static func ada(kind: String) -> bool:
	return PLANG.has(kind)


static func _mat(color: Color, rough := 0.7, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), rough, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


static func _put(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_deg := Vector3.ZERO, rough := 0.7, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, rough, glow)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(r: float, h: float, segs := 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func _ball(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


static func _label(parent: Node3D, text: String, pos: Vector3, size: int, pixel: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load(FONT)
	label.font_size = size
	label.pixel_size = pixel
	label.outline_size = 8
	label.modulate = color
	label.outline_modulate = Color("2a1606")
	label.position = pos
	parent.add_child(label)


## Pasang plang depan dan ikon atap. `info` dari WorldBuild._pasang_bangunan (cx, cz, front_z, half_w, height),
## `door` = petak pintu, `kind` = jenis bangunan.
static func pasang(root: Node3D, info: Dictionary, door: Vector2i, kind: String) -> void:
	if not PLANG.has(kind):
		return
	var dx := float(door.x) + 0.5
	var fz: float = float(info.front_z)
	var cfg: Dictionary = PLANG[kind]
	# Plang berdiri di kanan jalan menuju pintu (dari arah kamera), tiang kayu dan papan berwarna.
	var sx := dx + 1.5
	var sz := fz + 0.9
	var post := Color("5a3a1c")
	_put(root, _cyl(0.045, 1.05, 6), post, Vector3(sx, 0.525, sz))
	_put(root, _box(Vector3(1.24, 0.68, 0.07)), Color("2a1606"), Vector3(sx, 1.12, sz - 0.005))
	_put(root, _box(Vector3(1.16, 0.6, 0.08)), cfg.papan, Vector3(sx, 1.12, sz + 0.005))
	_label(root, str(cfg.teks), Vector3(sx, 1.12, sz + 0.055), 36, 0.0034, Color("fff1c2"))
	if not IKON_POS.has(kind):
		return  # bangunan tanpa ikon atap (cukup plang)
	# Ikon atap di depan atap, di atas pintu.
	var ikon := Node3D.new()
	ikon.name = "IkonAtap"
	var top: float = float(info.height)
	var pas: Vector2 = IKON_POS.get(kind, Vector2(0.8, 0.0))  # x = tinggi (bagian dari tinggi bangunan), y = geser z dari depan
	ikon.position = Vector3(float(info.cx), top * pas.x, fz + pas.y)
	ikon.set_meta("tiang", pas.y <= 0.0)  # di atas atap: berdiri di tiang; menempel di depan atap: tanpa tiang
	root.add_child(ikon)
	match kind:
		"dapur":
			_piza(ikon)
		"toko":
			_ramuan(ikon)
		"peralatan":
			_senjata(ikon)
		"rumah_sakit":
			_palang_merah(ikon)
		"aula":
			_perisai(ikon)


## Tiang pendek dari atap ke bawah ikon (ikon berpusat di atas titik ini).
static func _tiang(ikon: Node3D, tinggi: float) -> void:
	if not ikon.get_meta("tiang", true):
		return
	_put(ikon, _cyl(0.07, tinggi + 0.3, 6), Color("4a2f1a"), Vector3(0, tinggi / 2.0 - 0.2, 0))


static func _piza(ikon: Node3D) -> void:
	_tiang(ikon, 0.5)
	var c := Node3D.new()
	c.position = Vector3(0, 0.95, 0)
	c.rotation_degrees = Vector3(90, 0, 0)  # sumbu tabung menghadap kamera
	ikon.add_child(c)
	_put(c, _cyl(0.52, 0.1, 24), Color("d9a35a"), Vector3(0, 0.0, 0))
	_put(c, _cyl(0.43, 0.11, 24), Color("c8372d"), Vector3(0, 0.005, 0))
	_put(c, _cyl(0.39, 0.12, 24), Color("f2c14e"), Vector3(0, 0.01, 0))
	for i in 3:  # irisan
		var b := _put(c, _box(Vector3(0.78, 0.125, 0.018)), Color("c8952c"), Vector3(0, 0.012, 0))
		b.rotation_degrees.y = 60.0 * i
	var pep := [Vector2(-0.18, -0.14), Vector2(0.2, -0.16), Vector2(0.02, 0.0), Vector2(-0.2, 0.17), Vector2(0.19, 0.18), Vector2(0.02, 0.27)]
	for p: Vector2 in pep:
		_put(c, _cyl(0.07, 0.135, 12), Color("a3262a"), Vector3(p.x, 0.015, p.y))


static func _ramuan(ikon: Node3D) -> void:
	_tiang(ikon, 0.4)
	var biru := Color("3d8fe0")
	_put(ikon, _ball(0.34), biru, Vector3(0, 0.78, 0), Vector3.ZERO, 0.2, 0.35)
	_put(ikon, _cyl(0.11, 0.3, 12), biru.lightened(0.1), Vector3(0, 1.17, 0), Vector3.ZERO, 0.2, 0.3)
	_put(ikon, _cyl(0.15, 0.05, 12), Color("e9eef2"), Vector3(0, 1.33, 0))
	_put(ikon, _cyl(0.1, 0.13, 10), Color("b07a40"), Vector3(0, 1.43, 0))
	_put(ikon, _ball(0.08), Color("ffffff"), Vector3(-0.13, 0.9, 0.26), Vector3.ZERO, 0.3, 0.5)
	for g in [Vector3(0.14, 0.68, 0.3), Vector3(0.0, 0.58, 0.32), Vector3(-0.05, 0.75, 0.31)]:  # gelembung
		_put(ikon, _ball(0.04), Color("bfe3ff"), g, Vector3.ZERO, 0.2, 0.6)


## Satu pedang di Node3D: pangkalnya di gagang bawah, bilah ke atas sepanjang +y.
static func _pedang(parent: Node3D, rot_z: float) -> void:
	var n := Node3D.new()
	n.rotation_degrees.z = rot_z
	parent.add_child(n)
	_put(n, _box(Vector3(0.13, 0.86, 0.045)), Color("d5dce2"), Vector3(0, 0.55, 0), Vector3.ZERO, 0.25)
	_put(n, _box(Vector3(0.092, 0.092, 0.045)), Color("d5dce2"), Vector3(0, 1.0, 0), Vector3(0, 0, 45), 0.25)
	_put(n, _box(Vector3(0.4, 0.075, 0.08)), Color("d4a72c"), Vector3(0, 0.1, 0), Vector3.ZERO, 0.3)
	_put(n, _box(Vector3(0.07, 0.22, 0.07)), Color("5e3c20"), Vector3(0, -0.04, 0))
	_put(n, _ball(0.06), Color("d4a72c"), Vector3(0, -0.17, 0), Vector3.ZERO, 0.3)


static func _kapak(parent: Node3D, rot_z: float) -> void:
	var n := Node3D.new()
	n.rotation_degrees.z = rot_z
	parent.add_child(n)
	_put(n, _box(Vector3(0.075, 1.05, 0.06)), Color("7a4a26"), Vector3(0, 0.38, 0))
	_put(n, _box(Vector3(0.34, 0.3, 0.05)), Color("aeb6bd"), Vector3(0.14, 0.78, 0), Vector3.ZERO, 0.3)
	_put(n, _box(Vector3(0.12, 0.38, 0.05)), Color("d5dce2"), Vector3(0.33, 0.78, 0), Vector3.ZERO, 0.25)
	_put(n, _box(Vector3(0.12, 0.12, 0.05)), Color("aeb6bd"), Vector3(-0.07, 0.78, 0), Vector3(0, 0, 45), 0.3)


static func _senjata(ikon: Node3D) -> void:
	_tiang(ikon, 0.35)
	var c := Node3D.new()
	c.position = Vector3(0, 0.62, 0)
	ikon.add_child(c)
	_pedang(c, -35.0)
	_kapak(c, 35.0)
	_put(c, _cyl(0.1, 0.07, 14), Color("d4a72c"), Vector3(0, 0.3, 0.04), Vector3(90, 0, 0), 0.3)


static func _palang_merah(ikon: Node3D) -> void:
	_tiang(ikon, 0.4)
	var c := Node3D.new()
	c.position = Vector3(0, 0.88, 0)
	c.rotation_degrees = Vector3(90, 0, 0)
	ikon.add_child(c)
	_put(c, _cyl(0.45, 0.08, 24), Color("f4f4f4"), Vector3.ZERO, Vector3.ZERO, 0.5)
	_put(c, _box(Vector3(0.62, 0.1, 0.18)), Color("d83a3a"), Vector3(0, 0.01, 0))
	_put(c, _box(Vector3(0.18, 0.1, 0.62)), Color("d83a3a"), Vector3(0, 0.01, 0))


## Ikon Aula Pelatihan: perisai biru bulat dengan bintang emas, dan pedang tegak di belakangnya.
static func _perisai(ikon: Node3D) -> void:
	_tiang(ikon, 0.4)
	var c := Node3D.new()
	c.position = Vector3(0, 0.82, 0)
	ikon.add_child(c)
	_pedang(c, 0.0)
	var sh := Node3D.new()
	sh.position = Vector3(0, 0.1, 0.1)
	sh.rotation_degrees = Vector3(90, 0, 0)
	c.add_child(sh)
	_put(sh, _cyl(0.5, 0.08, 24), Color("d4a72c"), Vector3.ZERO, Vector3.ZERO, 0.3)
	_put(sh, _cyl(0.43, 0.1, 24), Color("2f5fa8"), Vector3(0, 0.005, 0), Vector3.ZERO, 0.4)
	for i in 5:  # bintang emas dari lima batang pendek
		var b := _put(sh, _box(Vector3(0.1, 0.11, 0.55)), Color("f2c14e"), Vector3(0, 0.012, 0), Vector3.ZERO, 0.3, 0.2)
		b.rotation_degrees.y = 36.0 * i
