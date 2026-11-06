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
const ALAM_DIR := "res://assets/models/alam/"
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
void vertex() {
	float w = clamp(VERTEX.y / tinggi, 0.0, 1.0);
	w *= w;
	vec3 p = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.3 + p.x * 0.8 + p.z * 0.6;
	VERTEX.x += sin(t) * goyang * w;
	VERTEX.z += cos(t * 0.9) * goyang * 0.6 * w;
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
void vertex() {
	float w = clamp(VERTEX.y / 0.35, 0.0, 1.0);
	vec3 p = MODEL_MATRIX[3].xyz;
	float t = TIME * 2.0 + p.x * 1.7 + p.z * 1.3;
	VERTEX.x += sin(t) * goyang * w;
	VERTEX.z += cos(t * 1.1) * goyang * 0.5 * w;
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));  // warna ditulis sRGB
	ROUGHNESS = 0.95;
}
"""

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


static func _multi(root: Node3D, mesh: Mesh, material: Material, xforms: Array[Transform3D], colors: Array[Color] = []) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
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
	var root := Node3D.new()
	root.name = "Medan"
	var rows := Maps.rows(map_id)
	var w := Maps.width(map_id)
	var h := Maps.height(map_id)
	var cave := map_id == Maps.GUA
	var mountain := map_id == Maps.GUNUNG or cave

	# Alas luas di bawah peta, supaya tidak ada ruang kosong di tepi layar.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(80, 80)
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
	var use_trees := _dekor_mesh(TREE_SINGLE[0]) != null
	var use_rocks := _dekor_mesh(MOUNTAINS[0]) != null
	var sway_by: Dictionary = {}     # pohon: id model -> daftar transform (goyang angin)
	var static_by: Dictionary = {}   # batu, gunung, tunggul: id model -> daftar transform
	var tufts: Array[Transform3D] = []

	for z in rows.size():
		for x in rows[z].length():
			var t: String = rows[z][x]
			var c := Vector3(x + 0.5, 0.0, z + 0.5)
			var j := _jitter(x, z)
			if t != "~" and t != "B":
				var gc := ground_color(t)
				ground_x.append(_xf(c))
				ground_c.append(gc.lightened(0.025 * (j - 0.5) * 2.0) if t == "." or t == "f" else gc)
			match t:
				"~":
					water_x.append(_xf(c + Vector3(0, -0.14, 0)))
				"B":
					water_x.append(_xf(c + Vector3(0, -0.14, 0)))
					plank_x.append(_xf(c + Vector3(0, 0.0, 0), Vector3(1, 1, 1)))
					for sx in [-0.46, 0.46]:
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
					for sx2 in [-0.4, 0.0, 0.4]:
						post_x.append(_xf(c + Vector3(sx2, 0.28, 0), Vector3(0.09, 0.56, 0.09)))
					rail_x.append(_xf(c + Vector3(0, 0.22, 0), Vector3(1.0, 0.06, 0.06)))
					rail_x.append(_xf(c + Vector3(0, 0.42, 0), Vector3(1.0, 0.06, 0.06)))
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
				"W":
					_add_well(root, c)
				"K":
					_add_throne(root, c)

	# Alas (satu draw call, warna per petak)
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_multi(root, quad, mat(Color.WHITE, true), ground_x, ground_c)
	var water := PlaneMesh.new()
	water.size = Vector2(1.0, 1.0)
	_multi(root, water, mat(Color("2fa3ea"), false, 0.18), water_x)
	_multi(root, _cyl(0.12, 0.14, 0.9, 6), mat(Color("5b3b1e")), trunk_x)
	_multi(root, _sphere(0.5, 9), mat(Color.WHITE, true), leaf_x, leaf_c)
	_multi(root, _sphere(0.6, 7), mat(Color.WHITE, true, 1.0), rock_x, rock_c)
	for id: String in sway_by:
		_multi(root, _dekor_mesh(id), _sway_material(), sway_by[id])
	for id: String in static_by:
		_multi(root, _dekor_mesh(id), null, static_by[id])
	_multi(root, _tuft_mesh(), _grass_material(), tufts)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("8d8d95")), stone_x)
	_multi(root, _box(Vector3(0.8, 0.07, 1.0)), mat(Color("9a6b3c")), plank_x)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("5b3b1e")), post_x)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("7a5530")), rail_x)
	_multi(root, _box(Vector3(1, 1, 1)), mat(Color("5e4326")), furrow_x)
	_multi(root, _sphere(0.08, 5), mat(Color("968a7c")), pebble_x)
	_multi(root, _sphere(0.07, 5), mat(Color.WHITE, true), flower_x, flower_c)
	_add_houses(root, house_tiles, rows)
	if cave:
		_add_torches(root, rows)
	return root


static func _add_well(root: Node3D, c: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _cyl(0.42, 0.45, 0.5, 14)
	ring.material_override = mat(Color("7d7d85"))
	ring.position = c + Vector3(0, 0.25, 0)
	root.add_child(ring)
	var water := MeshInstance3D.new()
	water.mesh = _cyl(0.33, 0.33, 0.02, 14)
	water.material_override = mat(Color("2a4f8a"), false, 0.2)
	water.position = c + Vector3(0, 0.5, 0)
	root.add_child(water)
	for sx in [-0.4, 0.4]:
		var post := MeshInstance3D.new()
		post.mesh = _box(Vector3(0.07, 0.9, 0.07))
		post.material_override = mat(Color("5b3b1e"))
		post.position = c + Vector3(sx, 0.7, 0)
		root.add_child(post)
	var roof := MeshInstance3D.new()
	roof.mesh = _box(Vector3(1.0, 0.07, 0.6))
	roof.material_override = mat(Color("a33a3a"))
	roof.position = c + Vector3(0, 1.18, 0)
	root.add_child(roof)


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


## Rumah: tiap kelompok petak H/D menjadi satu kotak dinding + atap pelana + pintu.
static func _add_houses(root: Node3D, tiles: Array[Vector2i], rows: Array[String]) -> void:
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
	match map_id:
		Maps.GUA:
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
		Maps.PERBATASAN:
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
	return 0.3 if map_id == Maps.GUA else 0.42


static func light_color_for(map_id: String) -> Color:
	return Color("ffa86a") if map_id == Maps.GUA else Color("fff0d2")
