extends RefCounted
## Hiasan Istana Kegelapan dan Ruang Takhta (Bab 4 The Last Dragon). Paket adventure 1.3.0.
##
## Hanya tampilan: petak peta, tabrakan, dan data server tidak berubah. Dipanggil world_build.gd setelah
## petak dasar dibuat. Semua bagian dirakit rakit.gd jadi beberapa mesh berwarna titik (padat/rata/pendar/logam),
## jadi seluruh hiasan hanya beberapa panggilan gambar; siluet di luar peta dan sangkar Elara punya mesh sendiri.
##
## Isi:
##   - Petak S tunggal (dikelilingi lantai) = pilar berukir (kristal ungu melayang di halaman, cincin rune di takhta).
##   - Petak S di tepi massa batu = tembok basal tinggi; halaman bergigi benteng, takhta berjendela ungu & panji.
##   - Petak P (halaman) = benteng gelap bergigi + panji berlambang mata Malzareth.
##   - Bibir batu di tepi kolam/parit lava, karpet merah-emas di jalan utama.
##   - Halaman: lingkar pemanggilan Aldragor (cincin rune + 4 kristal melayang) di petak K.
##   - Takhta: undakan, singgasana obsidian bertanduk dengan kristal, sangkar sihir Elara (hanya saat langkah 10).
##   - Halaman: siluet benteng utama, menara beratap runcing, jendela ungu di luar peta.

const Maps = preload("res://games/adventure/scripts/maps.gd")
const Rakit = preload("res://games/adventure/scripts/rakit.gd")

const BASAL := Color("2c2634")
const BASAL2 := Color("3a3344")
const TRIM := Color("4e4560")
const OBSIDIAN := Color("1b1622")
const EMAS := Color("c9a046")
const UNGU := Color("b066ff")
const KARPET := Color("5c1630")
const PANJI := Color("43105a")

static var _lampu: Array[OmniLight3D] = []


static func applies(map_id: String) -> bool:
	return map_id == Maps.ISTANA or map_id == Maps.TAKHTA


## Gaya bagian: warna + kelompok rakit (pendar = menyala, logam = emas berkilau, padat = biasa).
static func _m(_key: String, col: Color, glow := 0.0, _rough := 0.85, metal := 0.0) -> Dictionary:
	return {"c": col, "k": "pendar" if glow > 0.0 else ("logam" if metal > 0.0 else "padat")}


static func _part(r: Rakit, mesh: Mesh, gaya: Dictionary, pos: Vector3, rot := Vector3.ZERO, bayangan := true) -> void:
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


## Kristal: bola bersegi sedikit = bentuk berlian.
static func _crystal(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.6
	s.radial_segments = 4
	s.rings = 2
	return s


static func _ring(r: float, tebal: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - tebal
	t.outer_radius = r
	t.rings = 24
	t.ring_segments = 4
	return t


static func _j(x: int, z: int, salt := 0) -> float:
	var hsh := (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	return float(absi(hsh) % 1000) / 1000.0


static func _t(rows: Array[String], x: int, z: int) -> String:
	if z < 0 or z >= rows.size() or x < 0 or x >= rows[z].length():
		return "S"
	return rows[z][x]


static func _lantai(t: String) -> bool:
	return t == "O" or t == "K"


## Arah ke lantai terdekat (4 tetangga) atau nol bila tidak ada.
static func _arah_lantai(rows: Array[String], x: int, z: int) -> Vector2i:
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if _lantai(_t(rows, x + d.x, z + d.y)):
			return d
	return Vector2i.ZERO


static func _pilar_tunggal(rows: Array[String], x: int, z: int) -> bool:
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if _t(rows, x + d.x, z + d.y) in ["S", "P"]:
			return false
	return true


## Tepi massa batu: ada tetangga (8 arah) yang bukan batu.
static func _tepi(rows: Array[String], x: int, z: int) -> bool:
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx != 0 or dz != 0) and not (_t(rows, x + dx, z + dz) in ["S", "P"]):
				return true
	return false


static func build(root: Node3D, rows: Array[String], map_id: String) -> void:
	var halaman := map_id == Maps.ISTANA
	var throne := Vector3.ZERO
	var r := Rakit.new()
	_lampu.clear()
	for z in rows.size():
		for x in rows[z].length():
			var t: String = rows[z][x]
			var c := Vector3(x + 0.5, 0.0, z + 0.5)
			match t:
				"S":
					if _pilar_tunggal(rows, x, z):
						_pilar(r, c, halaman)
					elif _tepi(rows, x, z):
						_tembok(r, rows, x, z, c, halaman)
				"P":
					_benteng(r, rows, x, z, c)
				"L":
					_bibir_lava(r, rows, x, z, c)
				"K":
					throne = c
	if halaman:
		_karpet(r, rows, 15, throne, 2.6)
		if throne != Vector3.ZERO:
			_lingkar_naga(r, throne)
		_siluet(root, rows)
	else:
		_karpet(r, rows, 10, throne, 1.8)
		if throne != Vector3.ZERO:
			_singgasana(r, throne)
		if Session.story() == int(Maps.STORY_BOSS_STEP.get(Maps.TAKHTA, 10)):
			_sangkar_elara(root, Vector3(10.5, 0.0, 17.2))
	r.pasang(root, "Istana")
	root.set_meta("hiasan_istana", r.jumlah())
	for l in _lampu:
		root.add_child(l)


## Pilar: alas, tiang, kepala, lalu kristal melayang (halaman) atau cincin rune sampai langit-langit (takhta).
static func _pilar(r: Rakit, c: Vector3, halaman: bool) -> void:
	var batu := _m("pilar", BASAL2)
	var hias := _m("trim", TRIM)
	var tinggi := 2.7 if halaman else 3.8
	_part(r, _box(Vector3(0.96, 0.32, 0.96)), hias, c + Vector3(0, 0.16, 0))
	_part(r, _box(Vector3(0.78, 0.18, 0.78)), batu, c + Vector3(0, 0.41, 0))
	_part(r, _cyl(0.27, 0.33, tinggi, 10), batu, c + Vector3(0, 0.5 + tinggi * 0.5, 0))
	_part(r, _box(Vector3(0.84, 0.22, 0.84)), hias, c + Vector3(0, 0.6 + tinggi, 0))
	if halaman:
		_part(r, _box(Vector3(0.5, 0.18, 0.5)), batu, c + Vector3(0, 0.8 + tinggi, 0))
		_part(r, _crystal(0.2), _m("kristal", UNGU, 1.0, 0.3), c + Vector3(0, 1.35 + tinggi, 0), Vector3(0, PI * 0.25, 0), false)
	else:
		_part(r, _ring(0.36, 0.05), _m("rune", UNGU, 0.9, 0.4), c + Vector3(0, 1.9, 0), Vector3.ZERO, false)


## Tembok basal di tepi massa batu. Halaman: bergigi benteng. Takhta: lebih tinggi, jendela ungu dan panji.
static func _tembok(r: Rakit, rows: Array[String], x: int, z: int, c: Vector3, halaman: bool) -> void:
	var j := _j(x, z, 1)
	var tinggi := (3.3 + 0.9 * j) if halaman else 4.4
	var bahan := _m("basal", BASAL) if j < 0.5 else _m("basal2", BASAL2)
	_part(r, _box(Vector3(1.0, tinggi, 1.0)), bahan, c + Vector3(0, tinggi * 0.5, 0))
	_part(r, _box(Vector3(1.06, 0.16, 1.06)), _m("trim", TRIM), c + Vector3(0, tinggi + 0.08, 0))
	var arah := _arah_lantai(rows, x, z)
	if halaman:
		if (x + z) % 2 == 0:
			_part(r, _box(Vector3(0.42, 0.42, 0.42)), bahan, c + Vector3(0, tinggi + 0.37, 0))
		if arah != Vector2i.ZERO and (x * 3 + z) % 7 == 0:
			_panji(r, c, arah, 2.2)
		return
	if arah == Vector2i.ZERO:
		return
	if (x + z) % 3 == 0:  # jendela lengkung menyala ungu
		var muka := c + Vector3(arah.x, 0, arah.y) * 0.51
		var lebar := Vector3(0.05, 1.3, 0.42) if arah.x != 0 else Vector3(0.42, 1.3, 0.05)
		_part(r, _box(lebar), _m("jendela", Color("7a3cc8"), 1.0, 0.5), muka + Vector3(0, 2.5, 0), Vector3.ZERO, false)
		var kepala := Vector3(0.06, 0.12, 0.56) if arah.x != 0 else Vector3(0.56, 0.12, 0.06)
		_part(r, _box(kepala), _m("trim", TRIM), muka + Vector3(0, 3.22, 0))
	elif (x + z) % 5 == 1:
		_panji(r, c, arah, 3.0)


## Panji ungu berlambang mata Malzareth di muka tembok yang menghadap lantai.
static func _panji(r: Rakit, c: Vector3, arah: Vector2i, y_atas: float) -> void:
	var muka := c + Vector3(arah.x, 0, arah.y) * 0.53
	var sx := arah.x != 0
	var kain := Vector3(0.04, 1.5, 0.62) if sx else Vector3(0.62, 1.5, 0.04)
	_part(r, _box(kain), _m("panji", PANJI), muka + Vector3(0, y_atas - 0.85, 0))
	var batang := Vector3(0.06, 0.06, 0.8) if sx else Vector3(0.8, 0.06, 0.06)
	_part(r, _box(batang), _m("emas", EMAS, 0.0, 0.35, 0.6), muka + Vector3(0, y_atas - 0.08, 0))
	var tepi := Vector3(0.045, 0.08, 0.64) if sx else Vector3(0.64, 0.08, 0.045)
	_part(r, _box(tepi), _m("emas", EMAS, 0.0, 0.35, 0.6), muka + Vector3(0, y_atas - 1.58, 0))
	var mata := muka + Vector3(arah.x, 0, arah.y) * 0.03 + Vector3(0, y_atas - 0.75, 0)
	_part(r, _crystal(0.11), _m("mata", Color("ff5a2a"), 1.2, 0.3), mata, Vector3(0, 0, PI * 0.5), false)


## Benteng halaman (petak P): batu gelap penuh petak, gigi benteng, panji ke arah halaman.
static func _benteng(r: Rakit, rows: Array[String], x: int, z: int, c: Vector3) -> void:
	var j := _j(x, z, 2)
	var tinggi := 2.3 + 0.15 * j
	var bahan := _m("basal", BASAL) if j < 0.55 else _m("basal2", BASAL2)
	_part(r, _box(Vector3(1.0, tinggi, 1.0)), bahan, c + Vector3(0, tinggi * 0.5, 0))
	_part(r, _box(Vector3(1.08, 0.14, 1.08)), _m("trim", TRIM), c + Vector3(0, tinggi + 0.07, 0))
	if (x + z) % 2 == 0:
		_part(r, _box(Vector3(0.44, 0.4, 0.44)), bahan, c + Vector3(0, tinggi + 0.34, 0))
	var arah := _arah_lantai(rows, x, z)
	if arah != Vector2i.ZERO and (x + z) % 6 == 3:
		_panji(r, c, arah, 2.15)


## Bibir batu rendah di sisi kolam lava yang berbatasan dengan lantai.
static func _bibir_lava(r: Rakit, rows: Array[String], x: int, z: int, c: Vector3) -> void:
	var bahan := _m("bibir", Color("241e2a"))
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if not _lantai(_t(rows, x + d.x, z + d.y)):
			continue
		var s := Vector3(0.14, 0.16, 1.0) if d.x != 0 else Vector3(1.0, 0.16, 0.14)
		_part(r, _box(s), bahan, c + Vector3(d.x * 0.45, 0.08, d.y * 0.45))


## Karpet merah bertepi emas sepanjang kolom tengah `cx` (lebar 3 petak), berhenti di lingkar singgasana.
static func _karpet(r: Rakit, rows: Array[String], cx: int, throne: Vector3, jeda: float) -> void:
	var kain := _m("karpet", KARPET, 0.0, 0.95)
	var emas := _m("emas", EMAS, 0.0, 0.35, 0.6)
	for z in rows.size():
		if not _lantai(_t(rows, cx, z)):
			continue
		var c := Vector3(cx + 0.5, 0.0, z + 0.5)
		if throne != Vector3.ZERO and absf(c.z - throne.z) < jeda:
			continue
		var lebar := 2.6 if _lantai(_t(rows, cx - 1, z)) and _lantai(_t(rows, cx + 1, z)) else 0.9
		_part(r, _box(Vector3(lebar, 0.02, 1.0)), kain, c + Vector3(0, 0.012, 0), Vector3.ZERO, false)
		for sx in [-1.0, 1.0]:
			_part(r, _box(Vector3(0.09, 0.025, 1.0)), emas, c + Vector3(sx * (lebar * 0.5 - 0.06), 0.014, 0), Vector3.ZERO, false)


## Lingkar pemanggilan di tempat Aldragor menunggu: dua cakram batu, cincin rune, 4 kristal melayang + cahaya.
static func _lingkar_naga(r: Rakit, c: Vector3) -> void:
	_part(r, _cyl(2.6, 2.7, 0.06, 28), _m("trim", TRIM), c + Vector3(0, 0.03, 0), Vector3.ZERO, false)
	_part(r, _cyl(2.15, 2.2, 0.08, 28), _m("pilar", BASAL2), c + Vector3(0, 0.05, 0), Vector3.ZERO, false)
	_part(r, _ring(2.0, 0.07), _m("rune", UNGU, 0.9, 0.4), c + Vector3(0, 0.1, 0), Vector3.ZERO, false)
	_part(r, _ring(1.2, 0.05), _m("rune", UNGU, 0.9, 0.4), c + Vector3(0, 0.1, 0), Vector3.ZERO, false)
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var p := c + Vector3(cos(a), 0, sin(a)) * 2.3
		_part(r, _crystal(0.26), _m("kristal", UNGU, 1.0, 0.3), p + Vector3(0, 2.4, 0), Vector3(0, a, 0), false)
		_part(r, _cyl(0.0, 0.18, 0.3, 4), _m("rune", UNGU, 0.9, 0.4), p + Vector3(0, 0.25, 0), Vector3.ZERO, false)
	var cahaya := OmniLight3D.new()
	cahaya.light_color = Color("c48cff")
	cahaya.light_energy = 1.6
	cahaya.omni_range = 7.0
	cahaya.position = c + Vector3(0, 1.5, 0)
	_lampu.append(cahaya)


## Singgasana Malzareth: undakan dua tingkat, kursi obsidian bertanduk menghadap pintu (utara), kristal di puncak.
static func _singgasana(r: Rakit, c: Vector3) -> void:
	var obs := _m("obsidian", OBSIDIAN, 0.0, 0.4)
	var emas := _m("emas", EMAS, 0.0, 0.35, 0.6)
	var bantal := _m("bantal", Color("4a1a6a"), 0.0, 0.95)
	_part(r, _box(Vector3(5.0, 0.08, 3.6)), _m("trim", TRIM), c + Vector3(0, 0.04, 0.4))
	_part(r, _box(Vector3(3.6, 0.1, 2.6)), _m("pilar", BASAL2), c + Vector3(0, 0.12, 0.5))
	_part(r, _box(Vector3(3.62, 0.03, 0.08)), emas, c + Vector3(0, 0.17, -0.8))
	_part(r, _box(Vector3(1.3, 0.5, 1.0)), obs, c + Vector3(0, 0.42, 0.55))
	_part(r, _box(Vector3(1.1, 0.12, 0.85)), bantal, c + Vector3(0, 0.72, 0.5))
	_part(r, _box(Vector3(1.5, 3.0, 0.3)), obs, c + Vector3(0, 1.65, 1.05))
	_part(r, _box(Vector3(1.0, 1.8, 0.05)), bantal, c + Vector3(0, 1.55, 0.88))
	for sx in [-1.0, 1.0]:
		_part(r, _box(Vector3(0.24, 0.7, 1.0)), obs, c + Vector3(0.72 * sx, 0.72, 0.5))
		_part(r, _box(Vector3(0.28, 0.06, 1.04)), emas, c + Vector3(0.72 * sx, 1.09, 0.5))
		_part(r, _cyl(0.0, 0.14, 1.1, 6), obs, c + Vector3(0.62 * sx, 3.5, 1.05), Vector3(0, 0, -0.45 * sx))
		_part(r, _cyl(0.0, 0.16, 0.9, 4), obs, c + Vector3(0.75 * sx, 0.45, 1.05))  # duri di kaki sandaran
	_part(r, _box(Vector3(1.56, 0.08, 0.34)), emas, c + Vector3(0, 3.18, 1.05))
	_part(r, _crystal(0.3), _m("kristal", UNGU, 1.0, 0.3), c + Vector3(0, 3.65, 1.05), Vector3(0, PI * 0.25, 0), false)
	var cahaya := OmniLight3D.new()
	cahaya.light_color = Color("c48cff")
	cahaya.light_energy = 1.4
	cahaya.omni_range = 6.0
	cahaya.position = c + Vector3(0, 2.6, 0.2)
	_lampu.append(cahaya)


## Sangkar sihir yang mengurung Elara sampai Malzareth kalah (hanya dibuat pada langkah cerita 10).
static func _sangkar_elara(root: Node3D, c: Vector3) -> void:
	var sangkar := Node3D.new()
	sangkar.name = "SangkarElara"
	root.add_child(sangkar)
	var rs := Rakit.new()
	var jeruji := _m("jeruji", Color("2a2230"), 0.0, 0.5, 0.4)
	_part(rs, _cyl(0.95, 1.0, 0.12, 20), _m("pilar", BASAL2), c + Vector3(0, 0.06, 0))
	_part(rs, _ring(0.9, 0.05), _m("rune", UNGU, 0.9, 0.4), c + Vector3(0, 0.14, 0), Vector3.ZERO, false)
	for i in 10:
		var a := i * TAU / 10.0
		_part(rs, _cyl(0.025, 0.025, 2.2, 5), jeruji, c + Vector3(cos(a) * 0.86, 1.2, sin(a) * 0.86))
	_part(rs, _ring(0.9, 0.06), jeruji, c + Vector3(0, 2.3, 0))
	_part(rs, _cyl(0.0, 0.95, 0.5, 10), jeruji, c + Vector3(0, 2.55, 0))
	_part(rs, _crystal(0.12), _m("kristal", UNGU, 1.0, 0.3), c + Vector3(0, 2.95, 0), Vector3.ZERO, false)
	rs.pasang(sangkar, "Sangkar")


## Siluet benteng di luar halaman: menara-menara beratap runcing dan istana utama di selatan.
static func _siluet(root: Node3D, rows: Array[String]) -> void:
	var w := float(rows[0].length())
	var h := float(rows.size())
	var siluet := Node3D.new()
	siluet.name = "SiluetIstana"
	var rs := Rakit.new()
	var batu := _m("basal", BASAL)
	var atap := _m("atap", Color("2a1838"), 0.0, 0.6)
	var jendela := _m("jendela", Color("7a3cc8"), 1.0, 0.5)
	# Menara di keempat sudut halaman dan di sisi gerbang.
	var menara: Array[Vector3] = [Vector3(-1.5, 0, -1.5), Vector3(w + 1.5, 0, -1.5), Vector3(-1.5, 0, h + 1.5),
		Vector3(w + 1.5, 0, h + 1.5), Vector3(-3.0, 0, h * 0.5), Vector3(w + 3.0, 0, h * 0.5)]
	for i in menara.size():
		var p := menara[i]
		var tinggi := 9.0 + 2.0 * (i % 3)
		_part(rs, _cyl(1.5, 1.7, tinggi, 12), batu, p + Vector3(0, tinggi * 0.5, 0))
		_part(rs, _cyl(1.75, 1.75, 0.5, 12), _m("trim", TRIM), p + Vector3(0, tinggi + 0.25, 0))
		_part(rs, _cyl(0.0, 1.8, 3.6, 12), atap, p + Vector3(0, tinggi + 2.3, 0))
		for k in 3:
			var a := k * TAU / 3.0 + i
			_part(rs, _box(Vector3(0.3, 0.8, 0.3)), jendela, p + Vector3(cos(a) * 1.55, tinggi * (0.45 + 0.15 * k), sin(a) * 1.55), Vector3.ZERO, false)
	# Istana utama di balik gerbang selatan (ruang takhta) dan benteng belakang di utara.
	var pusat := Vector3(w * 0.5, 0, h + 7.0)
	_part(rs, _box(Vector3(16.0, 11.0, 7.0)), batu, pusat + Vector3(0, 5.5, 0))
	_part(rs, _box(Vector3(16.4, 0.5, 7.4)), _m("trim", TRIM), pusat + Vector3(0, 11.25, 0))
	_part(rs, _cyl(0.0, 5.5, 6.0, 4), atap, pusat + Vector3(0, 14.5, 0), Vector3(0, PI * 0.25, 0))
	for sx in [-1.0, 1.0]:
		var p2 := pusat + Vector3(7.5 * sx, 0, -1.5)
		_part(rs, _cyl(1.8, 2.0, 17.0, 12), batu, p2 + Vector3(0, 8.5, 0))
		_part(rs, _cyl(0.0, 2.1, 5.0, 12), atap, p2 + Vector3(0, 19.5, 0))
	_part(rs, _cyl(1.3, 1.5, 22.0, 12), batu, pusat + Vector3(0, 11.0, 2.0))
	_part(rs, _cyl(0.0, 1.6, 5.0, 12), atap, pusat + Vector3(0, 24.5, 2.0))
	_part(rs, _crystal(0.6), _m("kristal", UNGU, 1.0, 0.3), pusat + Vector3(0, 27.6, 2.0), Vector3.ZERO, false)
	for k in 7:
		_part(rs, _box(Vector3(0.5, 1.4, 0.2)), jendela, pusat + Vector3(-6.0 + k * 2.0, 6.5, -3.55), Vector3.ZERO, false)
	_part(rs, _box(Vector3(w + 8.0, 6.0, 3.0)), batu, Vector3(w * 0.5, 3.0, -5.0))
	rs.pasang(siluet, "Siluet")  # tanpa batas jarak: siluet tetap terlihat di cakrawala
	siluet.set_meta("no_merge", true)
	root.add_child(siluet)
