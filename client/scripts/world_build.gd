extends RefCounted
## Membangun medan 3D dari teks peta (scripts/maps.gd). Satu petak = 1 satuan dunia.
## Semuanya dirakit dari bentuk dasar; MultiMesh dipakai supaya ratusan pohon dan
## petak ringan di HP (hanya belasan draw call). Nanti bentuk-bentuk ini bisa diganti
## model/aset dari ilustrator tanpa mengubah aturan peta.

const Maps = preload("res://scripts/maps.gd")

const WALL_H := 1.5
const TREE_H := 2.0

## Model alam bergaya low-poly dari KayKit (CC0, Kay Lousberg) di assets/models/alam/.
## Bila berkasnya tidak ada, dipakai bentuk dasar seperti semula.
const Interior = preload("res://scripts/interior.gd")
const Plang = preload("res://scripts/plang.gd")
const ALAM_DIR := "res://assets/models/alam/"

## Model bangunan KayKit (CC0, atap merah-cokelat) untuk rumah-rumah di desa. Paket ini tidak punya
## model kandang, jadi kandang berpagar di Desa Awal diberi alas jerami (building_grain).
## Pengali ukuran model rumah terhadap petak H/D-nya (atap sedikit melebar ke rumput; tabrakan tetap sama).
const BANGUNAN_SKALA := 1.45

const BANGUNAN_MODEL := {
	"rumah_a": "building_home_A_red",
	"rumah_b": "building_home_B_red",
	"toko": "building_market_red",
	"peralatan": "building_home_B_red",
	"aula": "building_home_A_red",
	"dapur": "building_tavern_red",
	"rumah_sakit": "building_church_red",
	"kepala_suku": "building_castle_red",
}
const JERAMI_MODEL := "building_grain"
## Pusat alas jerami di dalam kandang berpagar, per peta.
const JERAMI_KANDANG := {"desa_awal": [Vector2(7.5, 12.5), Vector2(37.5, 12.5)]}
## Jenis bangunan khusus per peta; kunci = petak kiri-atas kelompok H/D. Sisanya rumah pribadi
## yang bergantian rumah_a / rumah_b.
const BANGUNAN_KHUSUS := {
	"desa_awal": {
		Vector2i(3, 1): "peralatan",
		Vector2i(15, 1): "toko",
		Vector2i(21, 1): "dapur",
		Vector2i(27, 1): "rumah_sakit",
		Vector2i(37, 19): "aula",
		Vector2i(38, 1): "kepala_suku",
	},
}
const TREE_SINGLE := ["tree_single_A", "tree_single_B"]
const TREE_GROVE := ["trees_A_small", "trees_A_medium", "trees_B_small", "trees_B_medium"]
const MOUNTAINS := ["mountain_A", "mountain_B", "mountain_C"]
const ROCKS := ["rock_single_C", "rock_single_E"]
const STUMPS := ["tree_single_A_cut", "tree_single_B_cut"]

## Goyang angin: pohon (bertekstur palet) dan rumput (warna per titik). Hanya menggeser titik
## bagian atas, jadi murah di HP.
const TREE_SHADER := """
shader_type spatial;
uniform sampler2D palet : source_color, filter_nearest;
uniform float goyang = 0.05;
uniform float tinggi = 1.2;
uniform float angin = 1.0;  // kekuatan angin (roadmap no. 107): naik saat hujan
void vertex() {
	float w = clamp(VERTEX.y / tinggi, 0.0, 1.0);
	w *= w;
	vec3 p = MODEL_MATRIX[3].xyz;
	float hembus = angin * (0.75 + 0.35 * sin(TIME * 0.35 + p.x * 0.05));  // embusan datang dan pergi
	float t = TIME * (1.0 + 0.3 * angin) + p.x * 0.8 + p.z * 0.6;
	VERTEX.x += (sin(t) + 0.4 * (angin - 1.0)) * goyang * hembus * w;
	VERTEX.z += cos(t * 0.9) * goyang * 0.6 * hembus * w;
}
void fragment() {
	ALBEDO = texture(palet, UV).rgb;
	ROUGHNESS = 0.9;
}
"""
const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float goyang = 0.07;
uniform float angin = 1.0;
void vertex() {
	float w = clamp(VERTEX.y / 0.35, 0.0, 1.0);
	vec3 p = MODEL_MATRIX[3].xyz;
	float hembus = angin * (0.75 + 0.35 * sin(TIME * 0.35 + p.x * 0.05));
	float t = TIME * (1.6 + 0.6 * angin) + p.x * 1.7 + p.z * 1.3;
	VERTEX.x += (sin(t) + 0.5 * (angin - 1.0)) * goyang * hembus * w;
	VERTEX.z += cos(t * 1.1) * goyang * 0.5 * hembus * w;
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));  // warna ditulis sRGB
	ROUGHNESS = 0.95;
}
"""

## Air hidup (roadmap no. 93-94): riak bergerak, kilau, dan sedikit naik-turun. Warna dalam/dangkal
## bergantian mengikuti pola gelombang; di malam hari ikut gelap karena tetap diterangi lampu biasa.
const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 dalam : source_color = vec4(0.13, 0.52, 0.80, 1.0);
uniform vec4 dangkal : source_color = vec4(0.30, 0.72, 0.92, 1.0);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.4 + wpos.x * 1.3 + wpos.z * 0.9) * 0.025;
}
void fragment() {
	float a = sin(wpos.x * 2.3 + TIME * 1.1) * cos(wpos.z * 1.9 - TIME * 0.8);
	float b = sin((wpos.x + wpos.z) * 3.7 - TIME * 1.6);
	float riak = 0.5 + 0.25 * a + 0.25 * b;
	ALBEDO = mix(dalam.rgb, dangkal.rgb, riak);
	float kilau = smoothstep(0.82, 1.0, riak);
	ALBEDO += vec3(kilau * 0.35);
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
"""

static var _water_mat: ShaderMaterial
static var _mats: Dictionary = {}
static var _dekor_cache: Dictionary = {}
static var _tree_mat: ShaderMaterial
static var _grass_mat: ShaderMaterial
static var _tuft_mesh_cache: ArrayMesh


static func mat(color: Color, vertex_colors := false, rough := 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), vertex_colors, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = vertex_colors  # warna per titik/instance ditulis sebagai warna layar (sRGB)
	_mats[key] = m
	return m


## Sedikit variasi warna yang tetap sama untuk petak yang sama (tanpa acak sungguhan).
static func _jitter(x: int, z: int, salt := 0) -> float:
	var h := (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	return float(h & 0xFFFF) / 65535.0


## Mesh pertama dari model alam (null bila tidak ada / gagal dimuat). Hasilnya di-cache.
static func _dekor_mesh(id: String) -> Mesh:
	if _dekor_cache.has(id):
		return _dekor_cache[id]
	var mesh: Mesh = null
	var path := ALAM_DIR + id + ".gltf"
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var inst := scene.instantiate()
			mesh = _first_mesh(inst)
			inst.free()
	_dekor_cache[id] = mesh
	return mesh


static func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


## Bahan pohon: palet warna KayKit + goyang angin.
static func _sway_material() -> Material:
	if _tree_mat == null:
		var mesh := _dekor_mesh(TREE_SINGLE[0])
		if mesh == null:
			return null
		var src := mesh.surface_get_material(0)
		var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
		if tex == null:
			return src
		var sh := Shader.new()
		sh.code = TREE_SHADER
		_tree_mat = ShaderMaterial.new()
		_tree_mat.shader = sh
		_tree_mat.set_shader_parameter("palet", tex)
	return _tree_mat


static func _water_material() -> Material:
	if _water_mat == null:
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = sh
	return _water_mat


## Kekuatan angin untuk pohon, rumput, dan ilalang (1 = biasa, ~2,5 = badai hujan). Roadmap no. 107.
static func set_wind(v: float) -> void:
	for m: ShaderMaterial in [_tree_mat, _grass_mat]:
		if m != null:
			m.set_shader_parameter("angin", v)


static func wind() -> float:
	return float(_grass_mat.get_shader_parameter("angin")) if _grass_mat != null else 1.0


static func _grass_material() -> Material:
	if _grass_mat == null:
		var sh := Shader.new()
		sh.code = GRASS_SHADER
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = sh
	return _grass_mat


## Rumpun rumput kecil: tujuh helai segitiga, gelap di pangkal dan terang di ujung.
static func _tuft_mesh() -> ArrayMesh:
	if _tuft_mesh_cache != null:
		return _tuft_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_c := Color("2f7a1c")
	var tip_c := Color("8fd04a")
	for i in 7:
		var a := float(i) / 7.0 * TAU
		var ca := cos(a)
		var sa := sin(a)
		var r := 0.05 + 0.04 * fmod(float(i) * 0.37, 1.0)
		var hgt := 0.22 + 0.14 * fmod(float(i) * 0.61, 1.0)
		var lean := 0.07 + 0.05 * fmod(float(i) * 0.23, 1.0)
		var bx := ca * r
		var bz := sa * r
		var tx := ca * (r + lean)
		var tz := sa * (r + lean)
		var wx := -sa * 0.035
		var wz := ca * 0.035
		st.set_color(base_c)
		st.add_vertex(Vector3(bx - wx, 0.0, bz - wz))
		st.set_color(base_c)
		st.add_vertex(Vector3(bx + wx, 0.0, bz + wz))
		st.set_color(tip_c)
		st.add_vertex(Vector3(tx, hgt, tz))
	_tuft_mesh_cache = st.commit()
	return _tuft_mesh_cache


## Ilalang tepi air (roadmap no. 100): helai tinggi kecokelatan, bergoyang seperti rumput.
static var _reed_mesh_cache: ArrayMesh

static func _reed_mesh() -> ArrayMesh:
	if _reed_mesh_cache != null:
		return _reed_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a := float(i) / 6.0 * TAU + 0.4
		var r := 0.03 + 0.03 * fmod(float(i) * 0.53, 1.0)
		var hgt := 0.55 + 0.25 * fmod(float(i) * 0.71, 1.0)
		var bx := cos(a) * r
		var bz := sin(a) * r
		var wx := -sin(a) * 0.022
		var wz := cos(a) * 0.022
		st.set_color(Color("4f6b2a"))
		st.add_vertex(Vector3(bx - wx, 0.0, bz - wz))
		st.set_color(Color("4f6b2a"))
		st.add_vertex(Vector3(bx + wx, 0.0, bz + wz))
		st.set_color(Color("c9b36a"))
		st.add_vertex(Vector3(bx * 2.0, hgt, bz * 2.0))
	_reed_mesh_cache = st.commit()
	return _reed_mesh_cache


## Petak (x, z) bersebelahan (8 arah) dengan air?
static func _dekat_air(rows: Array[String], x: int, z: int) -> bool:
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx != 0 or dz != 0) and _tile(rows, x + dx, z + dz) == "~":
				return true
	return false


## Petak (x, z) bersebelahan (4 arah) dengan pohon?
static func _dekat_pohon(rows: Array[String], x: int, z: int) -> bool:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if _tile(rows, x + d.x, z + d.y) == "#":
			return true
	return false


## Tambah satu instance model alam `id` ke kumpulan `dict` (id -> daftar transform).
## Alas model diletakkan tepat di tanah. Diabaikan bila modelnya tidak ada.
static func _tambah(dict: Dictionary, id: String, xf: Transform3D) -> void:
	var mesh := _dekor_mesh(id)
	if mesh == null:
		return
	xf.origin.y -= mesh.get_aabb().position.y * xf.basis.get_scale().y
	if not dict.has(id):
		var arr: Array[Transform3D] = []
		dict[id] = arr
	dict[id].append(xf)


## Ada petak jalan/jembatan/rumah/sumur/pagar di empat sisi petak (x, z)?
static func _dekat_bangunan(rows: Array[String], x: int, z: int) -> bool:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nz < 0 or nz >= rows.size() or nx < 0 or nx >= rows[nz].length():
			continue
		if "=BDHWF".contains(rows[nz][nx]):
			return true
	return false


## Hiasan di petak rumput: rumpun rumput di sekitar 30% petak, dan tunggul di ~3% petak
## yang jauh dari jalan, bangunan, titik awal, dan NPC. Hanya hiasan, tidak menghalangi.
static func _hias_rumput(tufts: Array[Transform3D], statics: Dictionary, map_id: String, rows: Array[String], x: int, z: int, c: Vector3) -> void:
	var r := _jitter(x, z, 70)
	if r < 0.30:
		var o := Vector3(_jitter(x, z, 72) - 0.5, 0.0, _jitter(x, z, 73) - 0.5) * 0.7
		tufts.append(_xf(c + o, Vector3.ONE * (0.9 + 0.7 * _jitter(x, z, 74)), _jitter(x, z, 75) * TAU))
	elif r > 0.97:
		if Vector2i(x, z) == Maps.SPAWN or Maps.npc_at(map_id, x, z) != "" or _dekat_bangunan(rows, x, z):
			return
		var o2 := Vector3(_jitter(x, z, 76) - 0.5, 0.0, _jitter(x, z, 77) - 0.5) * 0.4
		var id: String = STUMPS[int(_jitter(x, z, 78) * 1000.0) % STUMPS.size()]
		_tambah(statics, id, _xf(c + o2, Vector3.ONE * (2.0 + 0.8 * _jitter(x, z, 79)), _jitter(x, z, 80) * TAU))


## Sel pengelompokan MultiMesh (satuan dunia). Tiap sel jadi satu MultiMeshInstance3D sendiri
## supaya benda di luar layar / di luar jangkauan bayangan tidak ikut digambar.
const SEL_MULTI := 12.0
const MULTI_KECIL := 48  # jumlah di bawah ini tidak perlu dipecah


## `bayangan` false untuk benda kecil/rendah (rumput, kerikil, alas) agar lintasan bayangan ringan.
## `reg` + `kind`: bila diisi, tiap benda dicatat ({kind, model, mm, idx, xf}) agar bisa dihancurkan
## (lihat breakables.gd).
static func _multi(root: Node3D, mesh: Mesh, material: Material, xforms: Array[Transform3D], colors: Array[Color] = [], bayangan := true, reg: Array = [], kind := "", model_id := "") -> void:
	if xforms.is_empty():
		return
	var pakai_warna := not colors.is_empty()
	if xforms.size() <= MULTI_KECIL:
		_multi_satu(root, mesh, material, xforms, colors, bayangan, reg, kind, model_id)
		return
	var sel: Dictionary = {}  # Vector2i -> indeks benda
	for i in xforms.size():
		var o := xforms[i].origin
		var k := Vector2i(floori(o.x / SEL_MULTI), floori(o.z / SEL_MULTI))
		if not sel.has(k):
			sel[k] = []
		sel[k].append(i)
	for k: Vector2i in sel:
		var xs: Array[Transform3D] = []
		var cs: Array[Color] = []
		for i: int in sel[k]:
			xs.append(xforms[i])
			if pakai_warna:
				cs.append(colors[i])
		_multi_satu(root, mesh, material, xs, cs, bayangan, reg, kind, model_id)


static func _multi_satu(root: Node3D, mesh: Mesh, material: Material, xforms: Array[Transform3D], colors: Array[Color], bayangan: bool, reg: Array = [], kind := "", model_id := "") -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
		if kind != "":
			reg.append({"kind": kind, "model": model_id, "mm": mm, "idx": i, "xf": xforms[i]})
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	if not bayangan:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _xf(pos: Vector3, scale := Vector3.ONE, rot_y := 0.0) -> Transform3D:
	var b := Basis.from_euler(Vector3(0, rot_y, 0)).scaled(scale)
	return Transform3D(b, pos)


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _sphere(radius: float, segs := 10) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


static func _cyl(r_top: float, r_bottom: float, h: float, segs := 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


const SAND := Color("e2cf98")  # pasir tepi air


## Warna dasar tanah per jenis petak.
static func ground_color(tile: String) -> Color:
	match tile:
		"=": return Color("d9b97c")
		"T": return Color("86603a")
		"M": return Color("9d9285")
		"R": return Color("8a8175")
		"G": return Color("7d7165")
		"S": return Color("9a9aa3")
		"K": return Color("6a2020")
		"H", "D": return Color("b79c6c")
		"W": return Color("8fa07c")
	return Color("62b84c")  # rumput (juga di bawah pohon, pagar, bunga)


static func build(map_id: String) -> Node3D:
	if Maps.is_interior(map_id):
		return Interior.build(map_id)  # ruangan dalam bangunan (toko, rumah makan, rumah sehat)
	var root := Node3D.new()
	root.name = "Medan"
	var rows := Maps.rows(map_id)
	var w := Maps.width(map_id)
	var h := Maps.height(map_id)
	var cave := map_id == Maps.GUA or map_id == Maps.GUA_GOBLIN
	var mountain := map_id == Maps.GUNUNG or cave

	# Alas luas di bawah peta, supaya tidak ada ruang kosong di tepi layar.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(maxf(80.0, w + 40.0), 80)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = mat(Color("34302b") if mountain else Color("3f8f3a"))
	floor_node.position = Vector3(w / 2.0, -0.06, h / 2.0)
	root.add_child(floor_node)

	var ground_x: Array[Transform3D] = []
	var ground_c: Array[Color] = []
	var water_x: Array[Transform3D] = []
	var trunk_x: Array[Transform3D] = []
	var leaf_x: Array[Transform3D] = []
	var leaf_c: Array[Color] = []
	var rock_x: Array[Transform3D] = []
	var rock_c: Array[Color] = []
	var stone_x: Array[Transform3D] = []
	var plank_x: Array[Transform3D] = []
	var post_x: Array[Transform3D] = []
	var rail_x: Array[Transform3D] = []
	var furrow_x: Array[Transform3D] = []
	var pebble_x: Array[Transform3D] = []
	var flower_x: Array[Transform3D] = []
	var flower_c: Array[Color] = []
	var house_tiles: Array[Vector2i] = []
	var gate_tiles: Array[Vector2i] = []
	var pal_log_x: Array[Transform3D] = []   # pagar kayu besar: batang runcing
	var pal_log_c: Array[Color] = []
	var pal_tip_x: Array[Transform3D] = []
	var pal_tip_c: Array[Color] = []
	var pal_rail_x: Array[Transform3D] = []
	var wall_x: Array[Transform3D] = []      # tembok batu (Hutan Lebat): badan, tutup, dan gigi benteng
	var wall_c: Array[Color] = []
	var wall_cap_x: Array[Transform3D] = []
	var wall_top_x: Array[Transform3D] = []
	var use_trees := _dekor_mesh(TREE_SINGLE[0]) != null
	var use_rocks := _dekor_mesh(MOUNTAINS[0]) != null
	var sway_by: Dictionary = {}     # pohon: id model -> daftar transform (goyang angin)
	var static_by: Dictionary = {}   # batu, gunung, tunggul: id model -> daftar transform
	var tufts: Array[Transform3D] = []
	var kecil := {"J": [], "C": [], "A": [], "U": [], "Q": [], "Y": []}  # bangunan kecil (lihat _add_kecil)
	var reed_x: Array[Transform3D] = []   # ilalang tepi air
	var bush_x: Array[Transform3D] = []   # semak
	var bush_c: Array[Color] = []
	var stem_x: Array[Transform3D] = []   # jamur: batang
	var cap_x: Array[Transform3D] = []    # jamur: tudung
	var n_pasir := 0

	for z in rows.size():
		for x in rows[z].length():
			var t: String = rows[z][x]
			var c := Vector3(x + 0.5, 0.0, z + 0.5)
			var j := _jitter(x, z)
			if t != "~" and t != "B":
				var gc := ground_color(t)
				var tepi := (t == "." or t == "f") and not mountain and _dekat_air(rows, x, z)
				if tepi:  # tepi pasir di pinggir sungai/danau (roadmap no. 96)
					gc = SAND.lerp(gc, 0.25 * _jitter(x, z, 90))
					n_pasir += 1
				ground_x.append(_xf(c))
				ground_c.append(gc.lightened(0.025 * (j - 0.5) * 2.0) if t == "." or t == "f" else gc)
				if tepi and t == "." and _jitter(x, z, 91) < 0.45:  # ilalang di tepi air
					var oi := Vector3(_jitter(x, z, 92) - 0.5, 0.0, _jitter(x, z, 93) - 0.5) * 0.6
					reed_x.append(_xf(c + oi, Vector3.ONE * (0.8 + 0.5 * _jitter(x, z, 94)), _jitter(x, z, 95) * TAU))
				elif t == "." and not mountain and _dekat_pohon(rows, x, z) and not _dekat_bangunan(rows, x, z) \
						and Vector2i(x, z) != Maps.SPAWN and Maps.npc_at(map_id, x, z) == "":
					var rb := _jitter(x, z, 96)
					var ob := Vector3(_jitter(x, z, 97) - 0.5, 0.0, _jitter(x, z, 98) - 0.5) * 0.5
					if rb < 0.22:  # semak di tepi hutan (no. 102)
						var sb := 0.32 + 0.16 * _jitter(x, z, 99)
						var gcol := Color("2e6b26").lerp(Color("4f9a35"), _jitter(x, z, 100))
						bush_x.append(_xf(c + ob + Vector3(0, sb * 0.55, 0), Vector3(1.2, 0.85, 1.0) * sb))
						bush_c.append(gcol)
						bush_x.append(_xf(c + ob + Vector3(sb * 0.5, sb * 0.45, sb * 0.2), Vector3.ONE * sb * 0.75))
						bush_c.append(gcol.lightened(0.12))
					elif rb > 0.93 and (map_id == Maps.HUTAN or map_id == Maps.PERBATASAN):  # jamur hutan (no. 100)
						for k in 3:
							var om := ob + Vector3(_jitter(x, z, 101 + k) - 0.5, 0.0, _jitter(x, z, 104 + k) - 0.5) * 0.3
							var ms := 0.7 + 0.6 * _jitter(x, z, 107 + k)
							stem_x.append(_xf(c + om + Vector3(0, 0.05 * ms, 0), Vector3.ONE * ms))
							cap_x.append(_xf(c + om + Vector3(0, 0.1 * ms, 0), Vector3(1.0, 0.6, 1.0) * ms))
			match t:
				"~":
					water_x.append(_xf(c + Vector3(0, -0.035, 0)))  # di atas alas luas (-0,06), di bawah petak tanah (0)
				"B":
					water_x.append(_xf(c + Vector3(0, -0.035, 0)))  # di atas alas luas (-0,06), di bawah petak tanah (0)
					# Air di utara dan selatan petak jembatan = jalannya memanjang ke arah x (parit ladang); selain itu ke arah z.
					var sepanjang_x := _tile(rows, x, z - 1) == "~" and _tile(rows, x, z + 1) == "~"
					plank_x.append(_xf(c, Vector3.ONE, PI * 0.5 if sepanjang_x else 0.0))
					for sx in [-0.46, 0.46]:
						if sepanjang_x:
							post_x.append(_xf(c + Vector3(0, 0.2, sx), Vector3(0.08, 0.4, 0.08)))
							rail_x.append(_xf(c + Vector3(0, 0.38, sx), Vector3(1.0, 0.05, 0.05)))
						else:
							post_x.append(_xf(c + Vector3(sx, 0.2, 0), Vector3(0.08, 0.4, 0.08)))
							rail_x.append(_xf(c + Vector3(sx, 0.38, 0), Vector3(0.05, 0.05, 1.0)))
				"#":
					if use_trees:
						var rt := _jitter(x, z, 7)
						var tid: String
						var tsc: float
						if rt < 0.35:
							tid = TREE_SINGLE[0]
							tsc = 1.5 + 0.5 * j
						elif rt < 0.6:
							tid = TREE_SINGLE[1]
							tsc = 1.5 + 0.5 * j
						else:
							tid = TREE_GROVE[int(_jitter(x, z, 8) * 1000.0) % TREE_GROVE.size()]
							tsc = 1.0 + 0.3 * j
						_tambah(sway_by, tid, _xf(c, Vector3.ONE * tsc, _jitter(x, z, 9) * TAU))
					else:
						var s := 0.9 + 0.35 * j
						trunk_x.append(_xf(c + Vector3(0, 0.45 * s, 0), Vector3(1, s, 1)))
						var leaf := Color("1f5f24").lerp(Color("2f8a34"), j)
						leaf_x.append(_xf(c + Vector3(0, 1.2 * s, 0), Vector3(1.1, 1.15 * s, 1.1)))
						leaf_c.append(leaf)
						leaf_x.append(_xf(c + Vector3(0.05, 1.75 * s, 0), Vector3(0.72, 0.8 * s, 0.72)))
						leaf_c.append(leaf.lightened(0.12))
				"R":
					if use_rocks:
						var rr := _jitter(x, z, 9)
						if rr < 0.65:
							var mid: String = MOUNTAINS[int(_jitter(x, z, 11) * 1000.0) % MOUNTAINS.size()]
							_tambah(static_by, mid, _xf(c, Vector3.ONE * (0.85 + 0.45 * j), _jitter(x, z, 10) * TAU))
						else:
							var rid: String = ROCKS[int(_jitter(x, z, 12) * 1000.0) % ROCKS.size()]
							_tambah(static_by, rid, _xf(c, Vector3.ONE * (3.0 + 1.5 * j), _jitter(x, z, 10) * TAU))
					else:
						var s2 := 0.9 + 0.7 * j
						rock_x.append(_xf(c + Vector3(0, 0.35 * s2, 0), Vector3(1.0, 0.8 * s2, 1.0), j * 6.0))
						rock_c.append(Color("5d5852").lerp(Color("7a746b"), _jitter(x, z, 3)))
						rock_x.append(_xf(c + Vector3(0.18 * (j - 0.5), 0.95 * s2, 0.1), Vector3(0.55, 0.55 * s2, 0.55), j * 3.0))
						rock_c.append(Color("6b655d"))
				"S":
					stone_x.append(_xf(c + Vector3(0, 0.45, 0), Vector3(0.98, 0.9 - 0.25 * j, 0.98)))
				"F":
					_add_pagar_kandang(rows, x, z, c, post_x, rail_x)
				"T":
					for i in 3:
						furrow_x.append(_xf(c + Vector3(0, 0.04, -0.3 + i * 0.3), Vector3(1.0, 0.08, 0.1)))
				"G":
					for i in 3:
						var o := Vector3(_jitter(x, z, 10 + i) - 0.5, 0.05, _jitter(x, z, 20 + i) - 0.5) * 0.8
						pebble_x.append(_xf(c + o, Vector3.ONE * (0.6 + _jitter(x, z, 30 + i) * 0.7)))
				"f":
					for i in 3:
						var o2 := Vector3(_jitter(x, z, 40 + i) - 0.5, 0.0, _jitter(x, z, 50 + i) - 0.5) * 0.7
						tufts.append(_xf(c + o2, Vector3.ONE * (1.0 + 0.5 * _jitter(x, z, 55 + i)), _jitter(x, z, 58 + i) * TAU))
						flower_x.append(_xf(c + o2 + Vector3(0, 0.24, 0), Vector3.ONE * 1.35))
						flower_c.append([Color("ffd23a"), Color("ff6fa5"), Color("ffffff")][i])
				".":
					_hias_rumput(tufts, static_by, map_id, rows, x, z, c)
				"H", "D":
					house_tiles.append(Vector2i(x, z))
				"P":
					if map_id == Maps.HUTAN:
						_add_stone_wall_tile(x, z, c, wall_x, wall_c, wall_cap_x, wall_top_x)
					else:
						_add_palisade_tile(rows, x, z, w, h, c, pal_log_x, pal_log_c, pal_tip_x, pal_tip_c, pal_rail_x)
				"N":
					gate_tiles.append(Vector2i(x, z))
				"W":
					_add_well(root, c)
				"K":
					_add_throne(root, c)
				"J", "C", "A", "U", "Q", "Y":
					(kecil[t] as Array).append(Vector2i(x, z))

	# Alas (satu draw call, warna per petak)
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_multi(root, quad, mat(Color.WHITE, true), ground_x, ground_c, false)
	var water := PlaneMesh.new()
	water.size = Vector2(1.0, 1.0)
	_multi(root, water, _water_material(), water_x, [], false)
	_multi(root, _reed_mesh(), _grass_material(), reed_x, [], false)
	_multi(root, _sphere(0.5, 8), mat(Color.WHITE, true), bush_x, bush_c)
	_multi(root, _cyl(0.025, 0.035, 0.1, 6), mat(Color("efe6d2")), stem_x, [], false)
	_multi(root, _sphere(0.07, 7), mat(Color("c8352c")), cap_x, [], false)
	root.set_meta("hiasan", {"pasir": n_pasir, "ilalang": reed_x.size(), "semak": bush_x.size() / 2, "jamur": stem_x.size()})
	_multi(root, _cyl(0.12, 0.14, 0.9, 6), mat(Color("5b3b1e")), trunk_x)
	_multi(root, _sphere(0.5, 9), mat(Color.WHITE, true), leaf_x, leaf_c)
	_multi(root, _sphere(0.6, 7), mat(Color.WHITE, true, 1.0), rock_x, rock_c)
	var breakables: Array = []  # benda yang bisa dihancurkan (lihat breakables.gd)
	for id: String in sway_by:
		_multi(root, _dekor_mesh(id), _sway_material(), sway_by[id], [], true, breakables, "pohon", id)
	for id: String in static_by:
		var bk := "batu" if (id in ROCKS or id in MOUNTAINS) else ""
		_multi(root, _dekor_mesh(id), null, static_by[id], [], true, breakables, bk, id)
	_multi(root, _tuft_mesh(), _grass_material(), tufts, [], false, breakables, "rumput")
	root.set_meta("breakables", breakables)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("8d8d95")), stone_x)
	_multi(root, _box(Vector3(0.8, 0.07, 1.0)), mat(Color("9a6b3c")), plank_x, [], false)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("5b3b1e")), post_x)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("7a5530")), rail_x)
	_multi(root, _cyl(0.105, 0.125, 1.0, 7), mat(Color.WHITE, true), pal_log_x, pal_log_c)
	_multi(root, _cyl(0.0, 0.125, 0.3, 7), mat(Color.WHITE, true), pal_tip_x, pal_tip_c)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("4d3520")), pal_rail_x)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color.WHITE, true), wall_x, wall_c)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("77736b")), wall_cap_x)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("a7a398")), wall_top_x)
	if not gate_tiles.is_empty():
		_add_gate(root, gate_tiles, map_id)
	if map_id == Maps.DEFAULT_MAP:
		_add_outskirts(root, w, h)
	elif map_id == Maps.PERBATASAN:
		_add_outskirts(root, w, h, true)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("5e4326")), furrow_x, [], false)
	_multi(root, _sphere(0.08, 5), mat(Color("968a7c")), pebble_x, [], false)
	_multi(root, _sphere(0.07, 5), mat(Color.WHITE, true), flower_x, flower_c, false)
	_add_houses(root, house_tiles, rows, map_id)
	_add_kecil(root, kecil, map_id)
	_add_jerami(root, map_id)
	if map_id == Maps.HUTAN:
		_add_kunci_gerbang(root)
	if cave:
		_add_torches(root, rows)
	return root


## Satu petak pagar kandang ('F'): palang mengikuti tetangga pagar (sumbu x bila ada pagar di kiri/kanan,
## sumbu z bila ada di atas/bawah), tiang di tiap ujung petak, tiang sudut lebih tinggi di tikungan.
static func _add_pagar_kandang(rows: Array[String], x: int, z: int, c: Vector3, post_x: Array[Transform3D], rail_x: Array[Transform3D]) -> void:
	var kiri := _tile_f(rows, x - 1, z)
	var kanan := _tile_f(rows, x + 1, z)
	var atas := _tile_f(rows, x, z - 1)
	var bawah := _tile_f(rows, x, z + 1)
	var sx := kiri or kanan
	var sz := atas or bawah
	if not sx and not sz:
		sx = true
	var sudut := sx and sz
	if sx:
		for ry in [0.24, 0.46]:
			rail_x.append(_xf(c + Vector3(0, ry, 0), Vector3(1.0, 0.07, 0.07)))
	if sz:
		for ry in [0.24, 0.46]:
			rail_x.append(_xf(c + Vector3(0, ry, 0), Vector3(0.07, 0.07, 1.0)))
	# Tiang: di tepi petak (dipakai bersama petak tetangga) dan satu di tengah.
	if sx:
		for ox in [-0.5, 0.0, 0.5]:
			if ox == 0.5 and kanan:
				continue   # tiang tepi kanan digambar petak tetangga (sebagai tepi kirinya)
			post_x.append(_xf(c + Vector3(ox, 0.3, 0), Vector3(0.1, 0.6, 0.1)))
	if sz:
		for oz in [-0.5, 0.0, 0.5]:
			if oz == 0.5 and bawah:
				continue
			if oz == 0.0 and sx:
				continue
			if oz == -0.5 and sx:
				continue   # sudah ada tiang tepi dari palang sumbu x
			post_x.append(_xf(c + Vector3(0, 0.3, oz), Vector3(0.1, 0.6, 0.1)))
	if sudut:
		post_x.append(_xf(c + Vector3(0, 0.36, 0), Vector3(0.14, 0.72, 0.14)))


static func _tile_f(rows: Array[String], x: int, z: int) -> bool:
	return z >= 0 and z < rows.size() and x >= 0 and x < rows[z].length() and rows[z][x] == "F"


## Satu petak pagar kayu besar: empat batang runcing setinggi 1,6-2,0 dengan dua palang di sisi dalam.
## Pagar di tepi atas/bawah memanjang ke arah x, di tepi kiri/kanan ke arah z.
static func _add_palisade_tile(rows: Array[String], x: int, z: int, w: int, h: int, c: Vector3, log_x: Array[Transform3D], log_c: Array[Color], tip_x: Array[Transform3D], tip_c: Array[Color], rail_x: Array[Transform3D]) -> void:
	# Pagar tegak (kiri/kanan) bila tetangga kiri-kanannya bukan pagar/gapura; Desa Awal lebih lebar dari
	# pagarnya (wilayah timur), jadi tepi timur desa tidak lagi di x = w - 1.
	var vertical := z > 0 and z < h - 1 and not (_tile_pagar(rows, x - 1, z) or _tile_pagar(rows, x + 1, z))
	var inward := Vector3(1.0 if float(x) < float(w) * 0.25 else -1.0, 0, 0) if vertical else Vector3(0, 0, 1.0 if float(z) < float(h) * 0.5 else -1.0)
	var along := Vector3(0, 0, 1) if vertical else Vector3(1, 0, 0)
	for i in 4:
		var off := (float(i) - 1.5) * 0.25
		var j := _jitter(x * 4 + i, z, 71)
		var top := 1.55 + 0.5 * j
		var col := Color("805530").lerp(Color("b5824a"), _jitter(x * 4 + i, z, 72))
		var pos := c + along * off + Vector3(0, top * 0.5, 0)
		log_x.append(_xf(pos, Vector3(1.0, top, 1.0)))
		log_c.append(col)
		tip_x.append(_xf(c + along * off + Vector3(0, top + 0.12, 0)))
		tip_c.append(col.lightened(0.14))
	var rot := PI * 0.5 if vertical else 0.0
	for ry in [0.55, 1.15]:
		# Skala lokal (setelah putar): _xf menerapkan skala pada sumbu dunia, itu yang membuat palang
		# pagar kiri/kanan (diputar 90 derajat) pendek dan salah arah.
		rail_x.append(Transform3D(Basis.from_euler(Vector3(0, rot, 0)) * Basis.from_scale(Vector3(1.0, 0.11, 0.09)), c + inward * 0.17 + Vector3(0, ry, 0)))


## Satu petak tembok batu (pengganti pagar kayu di Hutan Lebat): badan batu abu setinggi sekitar 1,6 dengan
## tutup gelap dan dua gigi benteng, searah dengan gapura batu Gua Goblin.
static func _add_stone_wall_tile(x: int, z: int, c: Vector3, body_x: Array[Transform3D], body_c: Array[Color], cap_x: Array[Transform3D], top_x: Array[Transform3D]) -> void:
	var top := 1.5 + 0.22 * _jitter(x, z, 81)
	body_x.append(Transform3D(Basis.from_scale(Vector3(1.0, top, 0.62)), c + Vector3(0, top * 0.5, 0)))
	body_c.append(Color("8d8a82").lerp(Color("b3afa3"), _jitter(x, z, 82)))
	cap_x.append(Transform3D(Basis.from_scale(Vector3(1.02, 0.14, 0.8)), c + Vector3(0, top + 0.07, 0)))
	for sx in [-0.25, 0.25]:
		top_x.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.46)), c + Vector3(sx, top + 0.29, 0)))


## Palang kayu yang menutup gerbang Gua Goblin di Hutan Lebat sampai tiga Goblin kalah. Node "KunciGerbang"
## disembunyikan world3d.gd begitu misi selesai.
static func _add_kunci_gerbang(root: Node3D) -> void:
	var lock := Node3D.new()
	lock.name = "KunciGerbang"
	lock.position = Vector3(147.0, 0.0, 49.45)
	root.add_child(lock)
	var wood := mat(Color("6b4423"))
	var dark := mat(Color("3d2815"))
	for sx in [-0.95, 0.95]:
		_gate_part(lock, _box(Vector3(0.22, 2.3, 0.22)), dark, Vector3(sx, 1.15, 0))
	for yy in [0.45, 1.0, 1.55, 2.05]:
		_gate_part(lock, _box(Vector3(2.0, 0.16, 0.14)), wood, Vector3(0, yy, 0))
	_gate_part(lock, _box(Vector3(0.14, 2.2, 0.12)), wood, Vector3(0, 1.1, 0.02))
	_gate_part(lock, _box(Vector3(1.0, 0.4, 0.06)), mat(Color("8a1f1f")), Vector3(0, 1.3, -0.1))
	var label := Label3D.new()
	label.text = "TERKUNCI"
	label.font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	label.font_size = 40
	label.pixel_size = 0.0045
	label.outline_size = 8
	label.modulate = Color("ffe27a")
	label.outline_modulate = Color("3a1d05")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 2.7, -0.2)
	lock.add_child(label)


## Gapura desa: tiap dua petak 'N' yang bersebelahan menjadi menara batu beratap merah; bila di
## antara dua menara ada satu petak jalan, di atasnya dipasang jembatan batu + balok kayu + papan nama.
static func _add_gate(root: Node3D, tiles: Array[Vector2i], map_id: String = "") -> void:
	var tset := {}
	for t in tiles:
		tset[t] = true
	var lefts: Array[Vector2i] = []
	for t in tiles:
		if tset.has(t + Vector2i(1, 0)) and not tset.has(t + Vector2i(-1, 0)):
			lefts.append(t)
	var stone := _stone_mat(Color("c9c5b8"))
	var stone_dark := _stone_mat(Color("9b978c"))
	var wood := mat(Color("5b3b1e"))
	var roof_m := mat(Color("a33a3a"))
	var up := 1.2  # tambahan tinggi gapura: menara dan lengkungnya menjulang
	for t in lefts:
		var cx := float(t.x) + 1.0
		var cz := float(t.y) + 0.5
		# Gapura di tepi utara (Perbatasan, menuju desa) menghadap selatan; gapura desa menghadap utara.
		var sd := 1.0 if t.y == 0 else -1.0
		var nama := "GUA GOBLIN" if map_id == Maps.HUTAN else "DESA AWAL"
		var bh := 2.5 + up
		_gate_part(root, _box(Vector3(2.1, 0.5, 1.12)), stone_dark, Vector3(cx, 0.25, cz))
		_gate_part(root, _box(Vector3(2.0, bh, 1.05)), stone, Vector3(cx, bh / 2.0, cz))
		_gate_part(root, _box(Vector3(2.12, 0.18, 1.17)), stone_dark, Vector3(cx, bh + 0.08, cz))
		for sx in [-0.5, 0.5]:   # celah panah di sisi utara dan selatan
			for yy in [1.7, 1.7 + up * 0.8]:
				_gate_part(root, _box(Vector3(0.11, 0.5, 0.04)), mat(Color("23242a")), Vector3(cx + sx, yy, cz - 0.54))
				_gate_part(root, _box(Vector3(0.11, 0.5, 0.04)), mat(Color("23242a")), Vector3(cx + sx, yy, cz + 0.54))
		var roof := _gate_part(root, _cyl(0.0, 0.78, 1.0 + up * 0.35, 4), roof_m, Vector3(cx, 3.17 + up + up * 0.17, cz))
		roof.rotation.y = PI * 0.25
		roof.scale = Vector3(1.42, 1.0, 0.76)
		_gate_part(root, _cyl(0.025, 0.03, 0.7, 5), wood, Vector3(cx, 3.95 + up * 1.35, cz))
		_gate_part(root, _box(Vector3(0.42, 0.26, 0.03)), mat(Color("d93a3a")), Vector3(cx + 0.22, 4.1 + up * 1.35, cz))
		# Celah jalan di antara dua menara: bentang `gap` petak (1 = gapura lama, 3 = lebar).
		var gap := 0
		for g in range(1, 6):
			if tset.has(t + Vector2i(2 + g, 0)):
				gap = g
				break
			if tset.has(t + Vector2i(2 + g - 1, 0)):
				break
		if gap > 0:
			var gw := float(gap)
			var mx := float(t.x) + 2.0 + gw / 2.0   # tengah celah jalan
			_gate_part(root, _box(Vector3(gw + 0.04, 0.7 + up * 0.3, 1.05)), stone, Vector3(mx, 2.15 + up * 0.85, cz))
			_gate_part(root, _box(Vector3(gw + 0.06, 0.14, 1.17)), stone_dark, Vector3(mx, bh + 0.08, cz))
			_gate_part(root, _box(Vector3(gw + 0.04, 0.2, 0.9)), wood, Vector3(mx, 1.72 + up, cz))
			var nm := int(round(gw * 2.5))
			for k in nm:   # merlon di atas jembatan
				var mxk := mx - gw / 2.0 + (float(k) + 0.5) * gw / float(nm)
				_gate_part(root, _box(Vector3(0.22, 0.28, 0.2)), stone, Vector3(mxk, bh + 0.3, cz - 0.4))
				_gate_part(root, _box(Vector3(0.22, 0.28, 0.2)), stone, Vector3(mxk, bh + 0.3, cz + 0.4))
			for sx in [-1.0, 1.0]:  # dua daun pintu terbuka, menempel di dinding menara
				_gate_part(root, _box(Vector3(0.07, 1.6 + up, 0.48)), wood, Vector3(mx + sx * (gw / 2.0 - 0.04), 0.85 + up / 2.0, cz + sd * 0.3))
			var lampu_x: Array = [-0.36, 0.36] if gap == 1 else [-gw * 0.3, 0.0, gw * 0.3]
			for lx: float in lampu_x:   # lampu di atas gapura, menyala otomatis saat malam
				_gate_part(root, _cyl(0.02, 0.025, 0.42, 5), wood, Vector3(mx + lx, 2.88 + up, cz))
				var bulb := _gate_part(root, _sphere(0.15, 10), _lampu_mat(root), Vector3(mx + lx, 3.17 + up, cz))
				bulb.name = "LampuGapura"
				_lampu_cahaya(root, Vector3(mx + lx, 3.2 + up, cz + sd * 0.2), 8.0, 2.0)
			_glow_tanah(root, Vector3(mx, 0.07, cz + sd * 1.8), 5.0 + gw * 1.5)
			var bw := maxf(0.96, gw * 0.62)
			var sy := 2.15 + up * 0.85
			var sign_board := _gate_part(root, _box(Vector3(bw, 0.4 + (gw - 1.0) * 0.08, 0.05)), mat(Color("7a5530")), Vector3(mx, sy, cz + sd * 0.55))
			sign_board.name = "PapanGapura"
			var label := Label3D.new()
			label.text = nama
			label.font = load("res://assets/fonts/LilitaOne-Regular.ttf")
			label.font_size = 40 if gap == 1 else 52
			label.pixel_size = 0.0034
			label.outline_size = 9
			label.modulate = Color("ffe27a")
			label.outline_modulate = Color("3a1d05")
			label.rotation.y = PI if sd < 0.0 else 0.0
			label.position = Vector3(mx, sy, cz + sd * 0.585)
			root.add_child(label)


## Batu gapura: sedikit memancarkan cahaya agar sisi yang membelakangi matahari tidak gelap pekat.
static func _stone_mat(color: Color) -> StandardMaterial3D:
	var m := mat(color)
	m.emission_enabled = true
	m.emission = color.darkened(0.3)
	m.emission_energy_multiplier = 0.85
	return m


static func _gate_part(root: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	root.add_child(m)
	return m


## Di luar pagar Desa Awal: jalan tanah sambungan dari gapura dan deretan pohon sebagai latar
## (tanpa tabrakan, tidak bisa dihancurkan). Dibuat murah: beberapa ratus pohon dalam satu-dua draw call.
static func _add_outskirts(root: Node3D, w: int, h: int, utara: bool = false) -> void:
	var road_x: Array[Transform3D] = []
	var road_c: Array[Color] = []
	for k in range(0, 5):  # jalan lanjutan di luar gapura (selatan desa, atau utara Perbatasan)
		for rx in [21.5, 22.5, 23.5]:
			road_x.append(_xf(Vector3(rx, 0.0, (-0.5 - k) if utara else (float(h) + 0.5 + k))))
			road_c.append(ground_color("="))
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_multi(root, quad, mat(Color.WHITE, true), road_x, road_c, false)
	var ids: Array[String] = []
	for id: String in TREE_SINGLE + TREE_GROVE:
		if _dekor_mesh(id) != null:
			ids.append(id)
	if ids.is_empty():
		return
	var by: Dictionary = {}
	var margin := 5
	for z in range(-margin, h + margin):
		for x in range(-margin, w + margin):
			if x >= 0 and x < w and z >= 0 and z < h:
				continue
			if x >= 20 and x <= 24 and ((z < 0) if utara else (z >= h)):
				continue  # lorong jalan di luar gapura
			if _jitter(x + 300, z + 300, 81) > 0.42:
				continue
			var j := _jitter(x + 300, z + 300, 82)
			var o := Vector3(_jitter(x + 300, z + 300, 83) - 0.5, 0.0, _jitter(x + 300, z + 300, 84) - 0.5) * 0.9
			var id: String = ids[int(_jitter(x + 300, z + 300, 85) * 1000.0) % ids.size()]
			var sc := (1.3 + 0.5 * j) if id in TREE_SINGLE else (1.0 + 0.3 * j)
			_tambah(by, id, _xf(Vector3(x + 0.5, 0.0, z + 0.5) + o , Vector3.ONE * sc, _jitter(x + 300, z + 300, 86) * TAU))
	for id: String in by:
		_multi(root, _dekor_mesh(id), _sway_material(), by[id], [], false)


## Titik di sekeliling arena pertarungan (pusat 0,0,0; kamera di +Z; tokoh di x = -1 dan 1).
## i/n menentukan sudut di busur belakang-samping, `salt` mengacak jarak. Deterministik.
static func _arena_pos(i: int, n: int, r_min: float, r_max: float, salt: int) -> Vector3:
	var a := lerpf(-0.08, 1.08, (float(i) + _jitter(i, n, salt)) / float(n)) * PI
	var r := lerpf(r_min, r_max, _jitter(i, 7, salt + 1))
	return Vector3(cos(a) * r, 0.0, -sin(a) * r * 0.95 + 0.4)


## Arena pertarungan sesuai peta tempat pemain berada: tanah, pepohonan / gunung / batu sebagai
## latar (pakai model KayKit yang sama dengan dunia), rumput atau kerikil, dan obor di gua.
static func build_arena(map_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Arena"
	var tile := "."
	match map_id:
		Maps.GUNUNG: tile = "M"
		Maps.GUA, Maps.GUA_GOBLIN: tile = "G"
	var floor_color := ground_color(tile)
	if map_id == Maps.PERBATASAN or map_id == Maps.HUTAN:
		floor_color = floor_color.darkened(0.1)
	var disc := CylinderMesh.new()
	disc.top_radius = 18.0
	disc.bottom_radius = 18.0
	disc.height = 0.2
	var ground := MeshInstance3D.new()
	ground.mesh = disc
	ground.material_override = mat(floor_color, false, 1.0)
	ground.position = Vector3(0, -0.1, 0)
	root.add_child(ground)

	var sway_by: Dictionary = {}
	var static_by: Dictionary = {}
	var tufts: Array[Transform3D] = []
	var pebbles: Array[Transform3D] = []
	match map_id:
		Maps.GUNUNG:
			for i in 7:
				var mid: String = MOUNTAINS[i % MOUNTAINS.size()]
				var p := _arena_pos(i, 7, 8.5, 12.5, 11)
				p.z = minf(p.z, -3.0)
				_tambah(static_by, mid, _xf(p, Vector3.ONE * (3.4 + 1.6 * _jitter(i, 3, 12)), _jitter(i, 4, 13) * TAU))
			for i in 10:
				var rid: String = ROCKS[i % ROCKS.size()]
				_tambah(static_by, rid, _xf(_arena_pos(i, 10, 3.9, 7.5, 21), Vector3.ONE * (2.4 + 1.8 * _jitter(i, 5, 22)), _jitter(i, 6, 23) * TAU))
			for i in 60:
				var q := _arena_pos(i, 60, 1.2, 9.0, 31)
				pebbles.append(_xf(q + Vector3(0, 0.03, 0), Vector3.ONE * (0.5 + _jitter(i, 8, 32) * 0.9)))
		Maps.GUA, Maps.GUA_GOBLIN:
			for i in 10:
				var mid2: String = MOUNTAINS[i % MOUNTAINS.size()]
				_tambah(static_by, mid2, _xf(_arena_pos(i, 10, 5.5, 8.0, 41), Vector3.ONE * (3.0 + 1.2 * _jitter(i, 3, 42)), _jitter(i, 4, 43) * TAU))
			for i in 9:
				var rid2: String = ROCKS[i % ROCKS.size()]
				_tambah(static_by, rid2, _xf(_arena_pos(i, 9, 3.8, 6.0, 51), Vector3.ONE * (2.2 + 1.4 * _jitter(i, 5, 52)), _jitter(i, 6, 53) * TAU))
			for i in 40:
				pebbles.append(_xf(_arena_pos(i, 40, 1.2, 7.0, 61) + Vector3(0, 0.03, 0), Vector3.ONE * (0.5 + _jitter(i, 8, 62) * 0.9)))
			for sx in [-2.7, 2.7]:
				var torch := Node3D.new()
				torch.position = Vector3(sx, 0, -1.4)
				root.add_child(torch)
				var stick := MeshInstance3D.new()
				stick.mesh = _cyl(0.05, 0.06, 0.9, 6)
				stick.material_override = mat(Color("5b3b1e"))
				stick.position = Vector3(0, 0.45, 0)
				torch.add_child(stick)
				var flame := MeshInstance3D.new()
				flame.mesh = _sphere(0.13, 6)
				var fm := StandardMaterial3D.new()
				fm.albedo_color = Color("ffb040")
				fm.emission_enabled = true
				fm.emission = Color("ff8a20")
				fm.emission_energy_multiplier = 2.0
				flame.material_override = fm
				flame.position = Vector3(0, 0.98, 0)
				torch.add_child(flame)
				var light := OmniLight3D.new()
				light.light_color = Color("ffa050")
				light.light_energy = 1.8
				light.omni_range = 7.0
				light.position = Vector3(0, 1.2, 0.3)
				torch.add_child(light)
		Maps.PERBATASAN, Maps.HUTAN:  # hutan lebat
			for i in 16:
				var tid: String = TREE_SINGLE[i % TREE_SINGLE.size()]
				_tambah(sway_by, tid, _xf(_arena_pos(i, 16, 3.8, 8.0, 71), Vector3.ONE * (1.7 + 0.6 * _jitter(i, 3, 72)), _jitter(i, 4, 73) * TAU))
			for i in 9:
				var gid: String = TREE_GROVE[i % TREE_GROVE.size()]
				_tambah(sway_by, gid, _xf(_arena_pos(i, 9, 7.0, 11.0, 81), Vector3.ONE * (1.3 + 0.4 * _jitter(i, 3, 82)), _jitter(i, 4, 83) * TAU))
			for i in 4:
				var sid: String = STUMPS[i % STUMPS.size()]
				_tambah(static_by, sid, _xf(_arena_pos(i, 4, 3.6, 5.5, 91), Vector3.ONE * 1.6, _jitter(i, 4, 93) * TAU))
		_:  # desa awal: padang dengan pohon-pohon jarang
			for i in 9:
				var tid2: String = TREE_SINGLE[i % TREE_SINGLE.size()]
				_tambah(sway_by, tid2, _xf(_arena_pos(i, 9, 4.5, 9.0, 101), Vector3.ONE * (1.7 + 0.7 * _jitter(i, 3, 102)), _jitter(i, 4, 103) * TAU))
			for i in 3:
				var gid2: String = TREE_GROVE[i % TREE_GROVE.size()]
				_tambah(sway_by, gid2, _xf(_arena_pos(i, 3, 9.0, 12.0, 111), Vector3.ONE * 1.3, _jitter(i, 4, 113) * TAU))
			for i in 3:
				var rid3: String = ROCKS[i % ROCKS.size()]
				_tambah(static_by, rid3, _xf(_arena_pos(i, 3, 4.0, 6.0, 121), Vector3.ONE * 2.2, _jitter(i, 4, 123) * TAU))
	if map_id != Maps.GUNUNG and map_id != Maps.GUA and map_id != Maps.GUA_GOBLIN:
		for i in 150:
			var q2 := _arena_pos(i, 150, 0.9, 9.5, 131)
			if absf(q2.x) < 0.3 and q2.z > -0.3:
				continue
			if absf(q2.x) < 2.1 and absf(q2.z) < 1.3:
				continue  # tempat petarung berdiri: rumput tidak boleh menutupi musuh pendek (babi hutan, tikus)
			tufts.append(_xf(q2, Vector3.ONE * (1.0 + 0.6 * _jitter(i, 9, 132)), _jitter(i, 5, 133) * TAU))

	for id: String in sway_by:
		_multi(root, _dekor_mesh(id), _sway_material(), sway_by[id])
	for id: String in static_by:
		_multi(root, _dekor_mesh(id), null, static_by[id])
	_multi(root, _tuft_mesh(), _grass_material(), tufts, [], false)
	_multi(root, _sphere(0.08, 5), mat(Color("968a7c")), pebbles, [], false)
	return root


## Menara lampu besar di tengah alun-alun: tempat warga berkumpul. Menyala saat malam.
static func _add_well(root: Node3D, c: Vector3) -> void:
	var stone := _stone_mat(Color("c9c5b8"))
	var stone_dark := _stone_mat(Color("9b978c"))
	var wood := mat(Color("5b3b1e"))
	var wood_l := mat(Color("7a5530"))
	var red := mat(Color("a33a3a"))
	var lamp := _lampu_mat(root)
	# Lantai berkumpul: lingkaran batu rendah di sekeliling menara (bisa diinjak).
	var pad := _gate_part(root, _cyl(2.5, 2.5, 0.05, 28), mat(Color("8a8678")), c + Vector3(0, 0.025, 0))
	pad.name = "LantaiMenara"
	_gate_part(root, _cyl(1.9, 1.9, 0.07, 28), mat(Color("a8a496")), c + Vector3(0, 0.03, 0))
	# Alas batu menara (tetap di dalam satu petak agar tabrakan sama).
	_gate_part(root, _cyl(0.56, 0.62, 0.35, 8), stone_dark, c + Vector3(0, 0.175, 0))
	_gate_part(root, _cyl(0.46, 0.52, 0.9, 8), stone, c + Vector3(0, 0.8, 0))
	# Rangka kayu: empat tiang dan cincin pengikat tiap 1,4 m.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := _gate_part(root, _box(Vector3(0.1, 4.9, 0.1)), wood, c + Vector3(sx * 0.3, 3.35, sz * 0.3))
			leg.name = "TiangMenara"
	for k in 4:
		var y := 1.55 + float(k) * 1.4
		_gate_part(root, _box(Vector3(0.74, 0.08, 0.74)), wood_l, c + Vector3(0, y, 0))
		if k < 3:
			var tilt := atan(0.6 / 1.4)
			var diag_len := sqrt(0.6 * 0.6 + 1.4 * 1.4)
			for sgn in [-1.0, 1.0]:
				var dz := _gate_part(root, _box(Vector3(0.05, diag_len, 0.05)), wood_l, c + Vector3(0, y + 0.7, sgn * 0.3))
				dz.rotation.z = tilt * sgn
				var dx := _gate_part(root, _box(Vector3(0.05, diag_len, 0.05)), wood_l, c + Vector3(sgn * 0.3, y + 0.7, 0))
				dx.rotation.x = -tilt * sgn
	# Anjungan lampu di puncak.
	var deck := _gate_part(root, _box(Vector3(1.5, 0.14, 1.5)), wood, c + Vector3(0, 5.85, 0))
	deck.name = "AnjunganMenara"
	for sx in [-0.68, 0.68]:
		for sz in [-0.68, 0.68]:
			_gate_part(root, _box(Vector3(0.07, 0.5, 0.07)), wood, c + Vector3(sx, 6.15, sz))
	for sx in [-0.68, 0.68]:
		_gate_part(root, _box(Vector3(0.05, 0.05, 1.4)), wood, c + Vector3(sx, 6.4, 0))
		_gate_part(root, _box(Vector3(1.4, 0.05, 0.05)), wood, c + Vector3(0, 6.4, sx))
	# Lampu besar: bola bercahaya dalam sangkar, beratap merah.
	var glow := _gate_part(root, _sphere(0.5, 12), lamp, c + Vector3(0, 6.75, 0))
	glow.name = "LampuMenara"
	for sx in [-0.34, 0.34]:
		for sz in [-0.34, 0.34]:
			_gate_part(root, _box(Vector3(0.05, 1.0, 0.05)), wood, c + Vector3(sx, 6.75, sz))
	_gate_part(root, _box(Vector3(0.82, 0.06, 0.82)), wood, c + Vector3(0, 6.2, 0))
	var roof := _gate_part(root, _cyl(0.0, 0.85, 0.7, 4), red, c + Vector3(0, 7.58, 0))
	roof.rotation.y = PI * 0.25
	_gate_part(root, _cyl(0.025, 0.03, 0.45, 5), wood, c + Vector3(0, 8.1, 0))
	_lampu_cahaya(root, c + Vector3(0, 6.75, 0), 13.0, 1.5)
	_glow_tanah(root, c + Vector3(0, 0.09, 0), 6.0)


static func _add_throne(root: Node3D, c: Vector3) -> void:
	var seat := MeshInstance3D.new()
	seat.mesh = _box(Vector3(0.7, 0.45, 0.6))
	seat.material_override = mat(Color("8a1f1f"))
	seat.position = c + Vector3(0, 0.22, 0)
	root.add_child(seat)
	var back := MeshInstance3D.new()
	back.mesh = _box(Vector3(0.7, 1.1, 0.12))
	back.material_override = mat(Color("8a1f1f"))
	back.position = c + Vector3(0, 0.75, -0.3)
	root.add_child(back)
	var crown := MeshInstance3D.new()
	crown.mesh = _box(Vector3(0.5, 0.2, 0.14))
	crown.material_override = mat(Color("d4a72c"), false, 0.4)
	crown.position = c + Vector3(0, 1.35, -0.3)
	root.add_child(crown)


## Alas jerami pipih di dalam kandang berpagar (bisa diinjak ayam dan pemain).
static func _add_jerami(root: Node3D, map_id: String) -> void:
	var mesh := _dekor_mesh(JERAMI_MODEL)
	if mesh == null or not JERAMI_KANDANG.has(map_id):
		return
	var box := mesh.get_aabb()
	for c: Vector2 in JERAMI_KANDANG[map_id]:
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.scale = Vector3(2.4, 0.25, 2.4)
		inst.position = Vector3(c.x - (box.position.x + box.size.x / 2.0) * 2.4, -box.position.y * 0.25, c.y - (box.position.z + box.size.z / 2.0) * 2.4)
		root.add_child(inst)


## Jenis bangunan untuk kelompok H/D yang petak kiri-atasnya (x0, z0).
static func _jenis_bangunan(map_id: String, x0: int, z0: int) -> String:
	var khusus: Dictionary = BANGUNAN_KHUSUS.get(map_id, {})
	if khusus.has(Vector2i(x0, z0)):
		return khusus[Vector2i(x0, z0)]
	return "rumah_a" if _jitter(x0, z0, 5) < 0.5 else "rumah_b"


## Pasang model bangunan KayKit (pintu menghadap selatan, +Z) memenuhi kelompok petak w x d.
## false bila modelnya tidak ada, supaya rumah kotak lama dipakai sebagai cadangan.
static func _pasang_bangunan(root: Node3D, map_id: String, x0: int, z0: int, cx: float, cz: float, w: float, d: float) -> Dictionary:
	var mesh := _dekor_mesh(BANGUNAN_MODEL[_jenis_bangunan(map_id, x0, z0)])
	if mesh == null:
		return {}
	var box := mesh.get_aabb()
	var s := minf((w - 0.2) / box.size.x, (d - 0.2) / box.size.z) * BANGUNAN_SKALA
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.scale = Vector3(s, s, s)
	inst.position = Vector3(cx - (box.position.x + box.size.x / 2.0) * s, -box.position.y * s, cz - (box.position.z + box.size.z / 2.0) * s)
	root.add_child(inst)
	# Ukuran bangunan terpasang (untuk menempatkan lampu dan jendela di mukanya).
	return {"cx": cx, "cz": cz, "front_z": cz + box.size.z * s / 2.0, "half_w": box.size.x * s / 2.0, "height": box.size.y * s}


## Rumah: tiap kelompok petak H/D menjadi satu kotak dinding + atap pelana + pintu.
static func _add_houses(root: Node3D, tiles: Array[Vector2i], rows: Array[String], map_id: String = "") -> void:
	var seen: Dictionary = {}
	for start in tiles:
		if seen.has(start):
			continue
		var comp: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			comp.append(cur)
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n: Vector2i = cur + d
				if seen.has(n) or n.y < 0 or n.y >= rows.size() or n.x < 0 or n.x >= rows[n.y].length():
					continue
				if rows[n.y][n.x] == "H" or rows[n.y][n.x] == "D":
					seen[n] = true
					stack.append(n)
		var x0 := 999
		var z0 := 999
		var x1 := -1
		var z1 := -1
		for t: Vector2i in comp:
			x0 = mini(x0, t.x)
			z0 = mini(z0, t.y)
			x1 = maxi(x1, t.x)
			z1 = maxi(z1, t.y)
		var w := float(x1 - x0 + 1)
		var d := float(z1 - z0 + 1)
		var cx := x0 + w / 2.0
		var cz := z0 + d / 2.0
		var info := _pasang_bangunan(root, map_id, x0, z0, cx, cz, w, d)
		if not info.is_empty():
			var door := Vector2i(-1, -1)
			for t: Vector2i in comp:
				if rows[t.y][t.x] == "D":
					door = t
			if door.x >= 0:
				_lampu_rumah(root, info, door, _jenis_bangunan(map_id, x0, z0))
				Plang.pasang(root, info, door, _jenis_bangunan(map_id, x0, z0))
			continue
		var walls := MeshInstance3D.new()
		walls.mesh = _box(Vector3(w - 0.06, WALL_H, d - 0.06))
		walls.material_override = mat(Color("d9c8a0"))
		walls.position = Vector3(cx, WALL_H / 2.0, cz)
		root.add_child(walls)
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(d + 0.5, 0.9, w + 0.5)  # setelah diputar 90 derajat: lebar = w, punggung atap sejajar sumbu x
		roof.mesh = prism
		roof.material_override = mat(Color("a33a3a"))
		roof.rotation.y = PI / 2.0
		roof.position = Vector3(cx, WALL_H + 0.45, cz)
		root.add_child(roof)
		for t: Vector2i in comp:
			if rows[t.y][t.x] == "D":
				var door := MeshInstance3D.new()
				door.mesh = _box(Vector3(0.5, 0.95, 0.06))
				door.material_override = mat(Color("4a2f1a"))
				door.position = Vector3(t.x + 0.5, 0.48, t.y + 1.0 - 0.02)
				root.add_child(door)
			elif t.y == z1:
				var win := MeshInstance3D.new()
				win.mesh = _box(Vector3(0.34, 0.34, 0.05))
				win.material_override = mat(Color("9fd0ff"), false, 0.2)
				win.position = Vector3(t.x + 0.5, 0.95, t.y + 1.0 - 0.02)
				root.add_child(win)


# --- lampu malam ---
# Bahan bercahaya dan lampu dikumpulkan di meta "malam" pada akar peta; world3d memanggil set_night()
# dengan kekuatan malam 0..1 (lihat Atmosphere.night()), jadi semua menyala dan padam serempak.

const LAMP_OFF := Color("6b5a3a")
const LAMP_ON := Color("ffb040")


static func _malam(root: Node3D) -> Dictionary:
	if not root.has_meta("malam"):
		var lampu := StandardMaterial3D.new()
		lampu.albedo_color = LAMP_OFF
		lampu.roughness = 0.5
		lampu.emission_enabled = true
		lampu.emission = Color("ffa83a")
		lampu.emission_energy_multiplier = 0.0
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.75, 0.4, 1.0))
		grad.set_color(1, Color(1.0, 0.75, 0.4, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		glow.albedo_texture = tex
		glow.albedo_color = Color(1, 1, 1, 0.0)
		root.set_meta("malam", {"lampu": lampu, "glow": glow, "lights": []})
	return root.get_meta("malam")


static func _lampu_mat(root: Node3D) -> StandardMaterial3D:
	return _malam(root).lampu


## Lampu titik yang menyala saat malam (energi puncak `energy`).
static func _lampu_cahaya(root: Node3D, pos: Vector3, range_m: float, energy: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color("ffb35a")
	light.light_energy = 0.0
	light.omni_range = range_m
	light.shadow_enabled = false
	light.position = pos
	light.visible = false
	root.add_child(light)
	var reg := _malam(root)
	(reg.lights as Array).append({"node": light, "energy": energy})


## Pendar hangat di tanah (satu bidang datar bercahaya tambahan), terlihat hanya saat malam.
static func _glow_tanah(root: Node3D, pos: Vector3, size: float) -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(size, size)
	var m := MeshInstance3D.new()
	m.mesh = quad
	m.material_override = _malam(root).glow
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)


## Nyalakan/padamkan semua lampu peta: n = 0 siang, 1 malam penuh.
static func set_night(root: Node3D, n: float) -> void:
	if root == null or not root.has_meta("malam"):
		return
	var reg: Dictionary = root.get_meta("malam")
	var lampu: StandardMaterial3D = reg.lampu
	lampu.albedo_color = LAMP_OFF.lerp(LAMP_ON, n)
	lampu.emission_energy_multiplier = n * 1.5
	var glow: StandardMaterial3D = reg.glow
	glow.albedo_color = Color(1, 1, 1, n * 0.32)
	for e: Dictionary in reg.lights:
		var light := e.node as OmniLight3D
		if is_instance_valid(light):
			light.light_energy = n * float(e.energy)
			light.visible = n > 0.02


## Lampu rumah: lentera di kiri-kanan pintu, dua jendela hangat, dan pendar di tanah depan pintu.
## `info` dari _pasang_bangunan; `door` = petak pintu (D); `kind` = jenis bangunan.
static func _lampu_rumah(root: Node3D, info: Dictionary, door: Vector2i, kind: String) -> void:
	var lamp := _lampu_mat(root)
	var wood := mat(Color("4a2f1a"))
	var dx := float(door.x) + 0.5
	var fz: float = float(info.front_z)
	var hw: float = float(info.half_w)
	var h: float = float(info.height)
	var big := kind == "kepala_suku"
	var win_y := 0.34 * h
	var win_dx := hw * (0.6 if big else 0.55)
	for sx in [-1.0, 1.0]:
		if not big:  # jendela hangat di kiri-kanan pintu (istana kepala suku punya jendelanya sendiri)
			_gate_part(root, _box(Vector3(0.28, 0.34, 0.04)), lamp, Vector3(dx + sx * win_dx, win_y, fz + 0.02))
			_gate_part(root, _box(Vector3(0.36, 0.05, 0.05)), wood, Vector3(dx + sx * win_dx, win_y + 0.2, fz + 0.03))
			_gate_part(root, _box(Vector3(0.36, 0.05, 0.05)), wood, Vector3(dx + sx * win_dx, win_y - 0.2, fz + 0.03))
		# lentera di sisi pintu
		var lx := 0.9 if big else 0.68
		_gate_part(root, _cyl(0.015, 0.015, 0.3, 4), wood, Vector3(dx + sx * lx, 1.12, fz + 0.1))
		_gate_part(root, _box(Vector3(0.15, 0.2, 0.15)), lamp, Vector3(dx + sx * lx, 0.92, fz + 0.12))
	_glow_tanah(root, Vector3(dx, 0.07, fz + 1.2), 5.2 if big else 3.8)
	if big:
		_lampu_cahaya(root, Vector3(dx, 1.6, fz + 0.8), 7.5, 1.7)
		# Papan nama berdiri di depan rumah (tiang kayu + papan).
		var sx := dx - 2.1
		var sz := fz + 1.3
		_gate_part(root, _cyl(0.04, 0.05, 1.3, 6), wood, Vector3(sx, 0.65, sz))
		_gate_part(root, _box(Vector3(1.5, 0.42, 0.06)), mat(Color("7a5530")), Vector3(sx, 1.25, sz))
		var label := Label3D.new()
		label.text = "RUMAH\nKEPALA SUKU"
		label.font = load("res://assets/fonts/LilitaOne-Regular.ttf")
		label.font_size = 36
		label.pixel_size = 0.0033
		label.outline_size = 8
		label.modulate = Color("ffe27a")
		label.outline_modulate = Color("3a1d05")
		label.position = Vector3(sx, 1.25, sz + 0.04)
		root.add_child(label)
	else:
		_lampu_cahaya(root, Vector3(dx, 1.5, fz + 0.5), 4.2, 1.1)



static func _tile_pagar(rows: Array[String], x: int, z: int) -> bool:
	var t := _tile(rows, x, z)
	return t == "P" or t == "N"


static func _tile(rows: Array[String], x: int, z: int) -> String:
	if z < 0 or z >= rows.size() or x < 0 or x >= rows[z].length():
		return ""
	return rows[z][x]


# --- bangunan kecil: pos jaga (J), kandang ayam (C), tenda (A), api unggun (U), dummy latihan (Q), tiang panji (Y) ---

## Jalan utama desa (garis tengah x=22,5): pos jaga dan tenda basecamp menghadap ke sana.
const JALAN_UTAMA_X := 22.5


## Arah muka bangunan kecil (petak depan pintu = pintu + arah): pos jaga dan tenda menghadap jalan utama,
## yang lain (kandang ayam) menghadap selatan.
static func arah_kecil(ch: String, r: Dictionary) -> Vector2i:
	if ch == "J" or ch == "A":
		var cx := (float(r.x0) + float(r.x1) + 1.0) / 2.0
		return Vector2i(-1, 0) if cx > JALAN_UTAMA_X else Vector2i(1, 0)
	return Vector2i(0, 1)


## Petak pintu bangunan kecil berpetak banyak (pos jaga, kandang ayam): di sisi muka (`ar`), kolom/baris tengah
## (yang lebih kecil bila genap). Warga yang pulang ke sana (Maps.WARGA[].rumah) memakai petak ini.
static func pintu_kecil(r: Dictionary, ar := Vector2i(0, 1)) -> Vector2i:
	var w := int(r.x1) - int(r.x0) + 1
	var d := int(r.z1) - int(r.z0) + 1
	if ar.x != 0:
		return Vector2i(int(r.x0) if ar.x < 0 else int(r.x1), int(r.z0) + int(floor((d - 1) / 2.0)))
	return Vector2i(int(r.x0) + int(floor((w - 1) / 2.0)), int(r.z1) if ar.y > 0 else int(r.z0))


## Kelompok petak bertetangga (4 arah) -> daftar kotak pembatas {x0, z0, x1, z1}.
static func _kelompok(tiles: Array) -> Array:
	var seen := {}
	var out: Array = []
	for start: Vector2i in tiles:
		if seen.has(start):
			continue
		seen[start] = true
		var stack: Array[Vector2i] = [start]
		var box := {"x0": start.x, "z0": start.y, "x1": start.x, "z1": start.y}
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			box.x0 = mini(box.x0, cur.x)
			box.z0 = mini(box.z0, cur.y)
			box.x1 = maxi(box.x1, cur.x)
			box.z1 = maxi(box.z1, cur.y)
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n: Vector2i = cur + d
				if not seen.has(n) and tiles.has(n):
					seen[n] = true
					stack.append(n)
		out.append(box)
	return out


static func _add_kecil(root: Node3D, kecil: Dictionary, map_id: String = "") -> void:
	for r: Dictionary in _kelompok(kecil.J):
		_pos_jaga(root, r)
	for r: Dictionary in _kelompok(kecil.C):
		_kandang_ayam(root, r)
	var i := 0
	for r: Dictionary in _kelompok(kecil.A):
		_tenda(root, r, i)
		i += 1
	for t: Vector2i in kecil.U:
		_api_unggun(root, Vector3(t.x + 0.5, 0.0, t.y + 0.5))
	for t: Vector2i in kecil.Q:
		_dummy_latihan(root, Vector3(t.x + 0.5, 0.0, t.y + 0.5))
	for t: Vector2i in kecil.Y:
		_panji_basecamp(root, Vector3(t.x + 0.5, 0.0, t.y + 0.5), "KEM\nHUTAN" if Maps.KEM_ZONES.has(map_id) else "BASECAMP\nPAHLAWAN")


static func _label_kecil(root: Node3D, text: String, pos: Vector3, size: int, px: float, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	label.font_size = size
	label.pixel_size = px
	label.outline_size = 8
	label.modulate = Color("ffe27a")
	label.outline_modulate = Color("3a1d05")
	label.rotation.y = yaw
	label.position = pos
	root.add_child(label)


## Atap pelana dari prisma; punggung atap sejajar sumbu x (seperti atap rumah).
static func _atap(root: Node3D, w: float, d: float, tinggi: float, y: float, cx: float, cz: float, warna: Color) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(d, tinggi, w)
	var roof := _gate_part(root, prism, mat(warna), Vector3(cx, y, cz))
	roof.rotation.y = PI / 2.0


## Wadah bangunan kecil yang diputar mengikuti arah mukanya: di dalamnya muka bangunan = +z lokal.
static func _wadah(root: Node3D, cx: float, cz: float, ar: Vector2i) -> Node3D:
	var h := Node3D.new()
	h.position = Vector3(cx, 0.0, cz)
	h.rotation.y = atan2(float(ar.x), float(ar.y))
	root.add_child(h)
	return h


## Pos jaga di dekat gapura: bangunan terbuka, hanya atap merah, dinding belakang, dan empat tiang, menghadap
## jalan utama. Papan "POS JAGA" di balok depan dan lentera yang menyala saat malam. Penjaga berdiri di dalamnya
## saat malam (tetap terlihat).
static func _pos_jaga(root: Node3D, r: Dictionary) -> void:
	var tw := float(r.x1 - r.x0 + 1)
	var td := float(r.z1 - r.z0 + 1)
	var cx: float = r.x0 + tw / 2.0
	var cz: float = r.z0 + td / 2.0
	var ar := arah_kecil("J", r)
	var lebar := td if ar.x != 0 else tw    # sisi sejajar muka
	var dalam := tw if ar.x != 0 else td    # kedalaman (muka ke belakang)
	var h := _wadah(root, cx, cz, ar)
	var wood := mat(Color("8a5a2b"))
	var dark := mat(Color("3d2815"))
	var depan := dalam / 2.0
	_gate_part(h, _box(Vector3(lebar - 0.04, 0.18, dalam - 0.04)), _stone_mat(Color("b9b4a6")), Vector3(0, 0.09, 0))
	_gate_part(h, _box(Vector3(lebar - 0.1, 1.9, 0.14)), wood, Vector3(0, 1.13, -depan + 0.12))   # dinding belakang
	for sx in [-1.0, 1.0]:   # empat tiang: dua di muka, dua di belakang
		for sz in [-1.0, 1.0]:
			_gate_part(h, _box(Vector3(0.13, 2.05, 0.13)), dark, Vector3(sx * (lebar / 2.0 - 0.12), 1.2, sz * (depan - 0.12)))
	_gate_part(h, _box(Vector3(lebar - 0.1, 0.12, 0.12)), dark, Vector3(0, 2.15, depan - 0.12))    # balok depan
	_atap(h, lebar + 0.6, dalam + 0.7, 0.85, 2.6, 0.0, 0.0, Color("a33a3a"))
	_gate_part(h, _box(Vector3(lebar * 0.62, 0.28, 0.05)), mat(Color("7a5530")), Vector3(0, 1.93, depan - 0.04))
	_label_kecil(h, "POS JAGA", Vector3(0, 1.93, depan - 0.01), 30, 0.0034)
	var bangku := _gate_part(h, _box(Vector3(lebar - 0.5, 0.1, 0.32)), wood, Vector3(0, 0.55, -depan + 0.36))   # bangku di belakang
	bangku.name = "BangkuPos"
	_gate_part(h, _cyl(0.02, 0.02, 0.4, 4), dark, Vector3(0, 2.0, depan - 0.3))
	_gate_part(h, _sphere(0.13, 8), _lampu_mat(root), Vector3(0, 1.75, depan - 0.3))   # lentera gantung
	_gate_part(h, _cyl(0.025, 0.03, 0.8, 5), dark, Vector3(lebar / 2.0 - 0.1, 3.05, -depan + 0.15))
	_gate_part(h, _box(Vector3(0.03, 0.26, 0.4)), mat(Color("d93a3a")), Vector3(lebar / 2.0 - 0.1, 3.3, -depan + 0.35))
	var ke_depan := Vector3(float(ar.x), 0.0, float(ar.y))
	var lampu_dunia := Vector3(cx, 1.75, cz) + ke_depan * (depan - 0.3)
	_lampu_cahaya(root, lampu_dunia, 5.0, 1.2)
	_glow_tanah(root, Vector3(cx, 0.07, cz) + ke_depan * (depan + 0.7), 3.4)


## Kandang ayam: rumah kayu rendah di atas kaki, atap cokelat, pintu kecil dengan tangga papan, jendela hangat.
## Semua ayam masuk ke sini saat malam.
static func _kandang_ayam(root: Node3D, r: Dictionary) -> void:
	var w := float(r.x1 - r.x0 + 1)
	var d := float(r.z1 - r.z0 + 1)
	var cx: float = r.x0 + w / 2.0
	var cz: float = r.z0 + d / 2.0
	var dr := pintu_kecil(r)
	var dx := dr.x + 0.5
	var bw := w - 0.5
	var bd := d - 0.4
	var fz := cz + bd / 2.0
	var kayu := mat(Color("c58f52"))
	var gelap := mat(Color("4a2f1a"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_gate_part(root, _cyl(0.05, 0.06, 0.28, 5), gelap, Vector3(cx + sx * (bw / 2.0 - 0.1), 0.14, cz + sz * (bd / 2.0 - 0.1)))
	_gate_part(root, _box(Vector3(bw, 0.85, bd)), kayu, Vector3(cx, 0.7, cz))
	for k in range(-1, 2):   # papan tegak di dinding depan
		_gate_part(root, _box(Vector3(0.05, 0.85, 0.03)), mat(Color("a9783f")), Vector3(cx + k * 0.8, 0.7, fz + 0.01))
	_atap(root, bw + 0.35, bd + 0.35, 0.55, 1.4, cx, cz, Color("7a4a2a"))
	_gate_part(root, _box(Vector3(0.4, 0.5, 0.05)), gelap, Vector3(dx, 0.58, fz + 0.03))
	var tangga := _gate_part(root, _box(Vector3(0.34, 0.04, 0.7)), mat(Color("8a5a2b")), Vector3(dx, 0.17, fz + 0.33))
	tangga.rotation.x = 0.4
	var lamp := _lampu_mat(root)
	for sx in [-1.0, 1.0]:
		_gate_part(root, _box(Vector3(0.28, 0.24, 0.04)), lamp, Vector3(dx + sx * 0.85, 0.85, fz + 0.03))
	for k in 3:   # jerami di depan kandang
		_gate_part(root, _box(Vector3(0.34, 0.1, 0.26)), mat(Color("e0c060")), Vector3(dx + 0.75 + k * 0.1, 0.05, fz + 0.45 + k * 0.12))
	_lampu_cahaya(root, Vector3(dx, 1.0, fz + 0.5), 3.2, 0.8)
	_glow_tanah(root, Vector3(dx, 0.07, fz + 0.8), 2.4)


## Tenda basecamp: atap segitiga warna-warni; pintu gelap menghadap jalan utama / api unggun.
static func _tenda(root: Node3D, r: Dictionary, idx: int) -> void:
	var tw := float(r.x1 - r.x0 + 1)
	var td := float(r.z1 - r.z0 + 1)
	var cx: float = r.x0 + tw / 2.0
	var cz: float = r.z0 + td / 2.0
	var ar := arah_kecil("A", r)
	var warna: Color = [Color("c2503a"), Color("4f9a4a"), Color("d9a23a")][idx % 3]  # merah = pahlawan berkelas, hijau = prajurit biasa
	var h := _wadah(root, cx, cz, ar)
	var lebar := td if ar.x != 0 else tw
	var dalam := tw if ar.x != 0 else td
	var prism := PrismMesh.new()
	prism.size = Vector3(lebar + 0.1, 1.5, dalam + 0.1)
	_gate_part(h, prism, mat(warna), Vector3(0, 0.75, 0))
	var flap := PrismMesh.new()
	flap.size = Vector3(lebar * 0.5, 1.0, 0.05)
	_gate_part(h, flap, mat(Color("2b1d12")), Vector3(0, 0.5, (dalam + 0.1) / 2.0 + 0.005))
	_gate_part(h, _cyl(0.02, 0.02, 0.5, 4), mat(Color("4a2f1a")), Vector3(0, 1.7, 0))
	_gate_part(h, _sphere(0.06, 6), mat(Color("ffd23a")), Vector3(0, 1.97, 0))


## Api unggun: lingkaran batu, abu, tiga kayu bakar, nyala yang bergoyang; menerangi sekitar saat malam.
static func _api_unggun(root: Node3D, c: Vector3) -> void:
	_gate_part(root, _cyl(0.42, 0.42, 0.02, 10), mat(Color("2b2420")), c + Vector3(0, 0.01, 0))
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var st := _gate_part(root, _sphere(0.1, 6), mat(Color("77726a")), c + Vector3(cos(a) * 0.43, 0.06, sin(a) * 0.43))
		st.scale = Vector3(1.0, 0.7, 1.0)
	for i in 3:
		var kayu_bakar := _gate_part(root, _cyl(0.06, 0.06, 0.75, 6), mat(Color("5b3b1e")), c + Vector3(0, 0.12, 0))
		kayu_bakar.rotation = Vector3(0, float(i) / 3.0 * PI, PI / 2.0)
	var luar := _gate_part(root, _cyl(0.0, 0.2, 0.62, 8), _api_mat(Color("ff7a14")), c + Vector3(0, 0.42, 0))
	luar.name = "ApiUnggun"
	_gate_part(root, _cyl(0.0, 0.11, 0.4, 8), _api_mat(Color("ffd23a")), c + Vector3(0, 0.34, 0))
	_lampu_cahaya(root, c + Vector3(0, 0.9, 0), 7.5, 1.7)
	_glow_tanah(root, c + Vector3(0, 0.07, 0), 5.0)


static func _api_mat(warna: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform vec4 warna : source_color = vec4(1.0, 0.5, 0.1, 1.0);
void vertex() {
	float f = 1.0 + 0.14 * sin(TIME * 13.0) + 0.08 * sin(TIME * 23.0 + 1.7);
	VERTEX.y *= f;
	VERTEX.x += sin(TIME * 9.0 + VERTEX.y * 6.0) * 0.03 * (VERTEX.y + 0.3);
}
void fragment() {
	ALBEDO = warna.rgb * (0.88 + 0.12 * sin(TIME * 17.0));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("warna", warna)
	return m


## Dummy latihan: tiang, lengan silang, badan jerami, kepala karung, alas kayu.
static func _dummy_latihan(root: Node3D, c: Vector3) -> void:
	_gate_part(root, _box(Vector3(0.6, 0.08, 0.6)), mat(Color("5b3b1e")), c + Vector3(0, 0.04, 0))
	_gate_part(root, _cyl(0.06, 0.08, 1.4, 6), mat(Color("6b4a28")), c + Vector3(0, 0.75, 0))
	_gate_part(root, _box(Vector3(0.95, 0.09, 0.09)), mat(Color("6b4a28")), c + Vector3(0, 1.1, 0))
	_gate_part(root, _cyl(0.22, 0.27, 0.6, 8), mat(Color("d8c070")), c + Vector3(0, 0.85, 0))
	_gate_part(root, _sphere(0.15, 8), mat(Color("c9a96a")), c + Vector3(0, 1.42, 0))
	var sasaran := _gate_part(root, _cyl(0.13, 0.13, 0.02, 10), mat(Color("c43a3a")), c + Vector3(0, 0.88, 0.25))
	sasaran.rotation.x = PI / 2.0


## Tiang panji basecamp: bendera merah di puncak dan papan nama "BASECAMP PAHLAWAN" yang menghadap ke jalan (timur).
static func _panji_basecamp(root: Node3D, c: Vector3, teks: String = "BASECAMP\nPAHLAWAN") -> void:
	var kayu := mat(Color("5b3b1e"))
	_gate_part(root, _cyl(0.04, 0.05, 2.7, 6), kayu, c + Vector3(0, 1.35, 0))
	_gate_part(root, _sphere(0.07, 6), mat(Color("ffd23a")), c + Vector3(0, 2.74, 0))
	_gate_part(root, _box(Vector3(0.03, 0.5, 0.75)), mat(Color("b02a2a")), c + Vector3(0, 2.38, 0.42))
	_gate_part(root, _box(Vector3(0.07, 0.66, 1.3)), mat(Color("7a5530")), c + Vector3(0.07, 1.5, 0))
	_label_kecil(root, teks, c + Vector3(0.115, 1.5, 0), 40, 0.0036, PI / 2.0)


## Obor di dinding gua: tiang kecil dengan nyala (cahaya titik hanya beberapa, agar ringan).
static func _add_torches(root: Node3D, rows: Array[String]) -> void:
	var spots: Array[Vector3] = [Vector3(6.4, 0, 3.5), Vector3(8.6, 0, 3.5), Vector3(6.4, 0, 9.5), Vector3(8.6, 0, 9.5), Vector3(6.4, 0, 13.5), Vector3(8.6, 0, 13.5)]
	for i in spots.size():
		var p := spots[i]
		var stick := MeshInstance3D.new()
		stick.mesh = _cyl(0.04, 0.05, 0.7, 6)
		stick.material_override = mat(Color("5b3b1e"))
		stick.position = p + Vector3(0, 0.35, 0)
		root.add_child(stick)
		var flame := MeshInstance3D.new()
		flame.mesh = _sphere(0.1, 6)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color("ffb040")
		fm.emission_enabled = true
		fm.emission = Color("ff8a20")
		fm.emission_energy_multiplier = 2.0
		flame.material_override = fm
		flame.position = p + Vector3(0, 0.78, 0)
		root.add_child(flame)
		if i % 2 == 0:
			var light := OmniLight3D.new()
			light.light_color = Color("ffa050")
			light.light_energy = 1.4
			light.omni_range = 5.0
			light.position = p + Vector3(0.0, 1.0, 0.0)
			root.add_child(light)


## Suasana per peta: langit, kabut, dan cahaya. Langit prosedural + tonemap filmik + sedikit
## saturasi supaya warna lebih hidup dan segar.
static func environment_for(map_id: String) -> Environment:
	var env := Environment.new()
	var top := Color("2f7fd6")
	var horizon := Color("bfe3f7")
	var ground := Color("9bb98f")
	var ambient := 0.22
	var fog_c := Color("bfe3f7")
	var fog_d := 0.007
	if Maps.is_interior(map_id):  # ruangan: latar gelap hangat, cahaya dari lampu di dalam
		top = Color("1d1710")
		horizon = Color("1d1710")
		ground = Color("1d1710")
		ambient = 0.5
		fog_c = Color("1d1710")
		fog_d = 0.0
	match map_id:
		Maps.GUA, Maps.GUA_GOBLIN:
			top = Color("0b0908")
			horizon = Color("0b0908")
			ground = Color("0b0908")
			ambient = 0.35
			fog_c = Color("0b0908")
			fog_d = 0.04
		Maps.GUNUNG:
			top = Color("5f86b8")
			horizon = Color("c9d4e0")
			ground = Color("9a9488")
			ambient = 0.22
			fog_c = Color("c9d4e0")
			fog_d = 0.012
		Maps.PERBATASAN, Maps.HUTAN:
			top = Color("4a8fd0")
			horizon = Color("d2e6f0")
			ground = Color("9fb48c")
			ambient = 0.22
			fog_c = Color("d2e6f0")
			fog_d = 0.011
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = ground
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # warna langsung: terang-gelapnya bisa dikendalikan
	env.ambient_light_color = horizon.lerp(Color.WHITE, 0.25)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED  # tanpa pantulan langit (membuat tanah pucat)
	env.ambient_light_energy = ambient
	env.fog_enabled = true
	env.fog_light_color = fog_c
	env.fog_density = fog_d
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05 if map_id != Maps.GUA else 1.0
	env.adjustment_contrast = 1.04
	return env


## Cahaya matahari: hangat di luar ruangan, redup di gua.
static func light_energy_for(map_id: String) -> float:
	if Maps.is_interior(map_id):
		return 0.3
	return 0.3 if map_id == Maps.GUA else 0.42


static func light_color_for(map_id: String) -> Color:
	return Color("ffa86a") if map_id == Maps.GUA else Color("fff0d2")
