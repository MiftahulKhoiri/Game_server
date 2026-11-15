extends SceneTree
## Pembuat aset lingkungan Petualangan Pulau Ilmu (Fase 10) — ASET BUATAN SENDIRI (CC0, lihat LISENSI.txt).
## Menghasilkan GLB statis low-poly semi-realistis (banyak material warna, tanpa tekstur) di
## res://games/education_sd/assets/environment/<kelompok>/. Skala mengikuti pemain ±1,45 m.
## Pakai: godot --headless --path client -s ../tools/gamepack/sd_props.gd  lalu  --import

const OUT := "res://games/education_sd/assets/environment/"

var surfaces: Dictionary = {}
var mats: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 2026
	var ok := true
	for spec in [
		["vegetation", "tree_round", _tree_round], ["vegetation", "tree_pine", _tree_pine], ["vegetation", "tree_palm", _tree_palm],
		["vegetation", "bush", _bush], ["vegetation", "flowers", _flowers],
		["rocks", "rock_a", _rock.bind(0)], ["rocks", "rock_b", _rock.bind(1)],
		["educational", "math_statue", _math_statue], ["educational", "big_book", _big_book], ["educational", "microscope", _microscope],
		["educational", "globe", _globe], ["educational", "info_board", _info_board], ["props", "lamp_post", _lamp_post],
		["buildings", "cave", _cave], ["buildings", "math_tower", _math_tower], ["buildings", "library", _library],
		["buildings", "museum", _museum], ["buildings", "lab_dome", _lab_dome], ["buildings", "market_stall", _market_stall],
		["buildings", "rumah_gadang", _rumah_gadang], ["buildings", "joglo", _joglo], ["buildings", "tongkonan", _tongkonan],
		["buildings", "lighthouse", _lighthouse], ["buildings", "observatory", _observatory],
	]:
		ok = _save(spec[0], spec[1], spec[2]) and ok
	print("PROPS GLB: ", "OK" if ok else "GAGAL")
	quit(0 if ok else 1)


func _mat(name: String, c: Color, rough := 0.85, metal := 0.0) -> void:
	if mats.has(name):
		return
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	mats[name] = m


## Tambah bagian. jitter > 0 mengacak verteks (batu/daun lebih alami).
func _add(mesh: PrimitiveMesh, mat: String, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO, jitter := 0.0) -> void:
	var arr := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(rot) * Basis.from_scale(scl)
	var nb := basis.inverse().transposed()
	if not surfaces.has(mat):
		surfaces[mat] = SurfaceTool.new()
		(surfaces[mat] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
	var st: SurfaceTool = surfaces[mat]
	var seen := {}
	for k in idx:
		var p := v[k]
		if jitter > 0.0:
			var key := p.snapped(Vector3.ONE * 0.001)
			if not seen.has(key):
				seen[key] = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
			p += seen[key]
		st.set_normal((nb * n[k]).normalized())
		st.add_vertex(basis * p + pos)


func _save(group: String, name: String, build: Callable) -> bool:
	surfaces.clear()
	build.call()
	var am := ArrayMesh.new()
	for mname in surfaces:
		var st: SurfaceTool = surfaces[mname]
		if mats.has(mname) and (mname in ["Batu", "Daun", "Daun2", "Semak", "Tebing"]):
			st.generate_normals()
		st.index()  # verteks kembar digabung: jauh lebih ringan untuk MultiMesh
		st.set_material(mats[mname])
		st.commit(am)
		am.surface_set_name(am.get_surface_count() - 1, mname)
	var root := Node3D.new()
	root.name = name
	var mi := MeshInstance3D.new()
	mi.name = name + "_mesh"
	mi.mesh = am
	root.add_child(mi)
	mi.owner = root
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + group))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT + "%s/%s.glb" % [group, name]))
	var verts := 0
	for s in am.get_surface_count():
		verts += (am.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var tris := 0
	for s in am.get_surface_count():
		tris += (am.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	verts = tris  # laporkan jumlah segitiga
	print("  %s/%s: %d material, %d segitiga -> %s" % [group, name, am.get_surface_count(), verts, error_string(err)])
	root.free()
	return err == OK


static func cyl(t: float, b: float, h: float, seg := 10, rings := 1) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = t
	m.bottom_radius = b
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m


static func sph(r: float, seg := 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(5, seg / 2)
	return m


static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


# --- Vegetasi (pohon ±4-7 m; titik pangkal di tanah) ---------------------------------------------------

func _tree_round() -> void:
	_mat("Kayu", Color("6b4a2e"), 0.95)
	_mat("Daun", Color("4f9a45"), 0.9)
	_mat("Daun2", Color("6bb85a"), 0.9)
	_add(cyl(0.16, 0.3, 2.6, 9, 3), "Kayu", Vector3(0, 1.3, 0), Vector3.ONE, Vector3.ZERO, 0.03)
	_add(cyl(0.06, 0.1, 1.1, 6), "Kayu", Vector3(0.35, 2.3, 0), Vector3.ONE, Vector3(0, 0, -0.8))
	_add(cyl(0.05, 0.09, 1.0, 6), "Kayu", Vector3(-0.3, 2.5, 0.1), Vector3.ONE, Vector3(0.2, 0, 0.9))
	for p in [Vector3(0, 3.6, 0), Vector3(0.75, 3.2, 0.2), Vector3(-0.7, 3.3, -0.2), Vector3(0.1, 3.1, 0.75), Vector3(-0.1, 4.2, -0.3)]:
		_add(sph(0.95, 8), "Daun" if p.y < 3.5 else "Daun2", p, Vector3(1.0, 0.85, 1.0), Vector3.ZERO, 0.12)


func _tree_pine() -> void:
	_mat("Kayu", Color("5a3d26"), 0.95)
	_mat("Daun", Color("2f6e48"), 0.9)
	_add(cyl(0.12, 0.24, 2.0, 8), "Kayu", Vector3(0, 1.0, 0))
	for k in 4:
		_add(cyl(0.0, 1.5 - k * 0.3, 1.6, 10), "Daun", Vector3(0, 1.8 + k * 1.0, 0), Vector3.ONE, Vector3(0, k * 0.4, 0), 0.06)


func _tree_palm() -> void:
	_mat("Kayu", Color("8a6a44"), 0.95)
	_mat("Daun", Color("3f8f3f"), 0.85)
	_mat("Kelapa", Color("6b4a2e"), 0.8)
	for k in 6:
		_add(cyl(0.16 - k * 0.012, 0.18 - k * 0.012, 0.85, 8), "Kayu", Vector3(k * 0.06, 0.42 + k * 0.8, 0), Vector3.ONE, Vector3(0, 0, -0.06))
	var top := Vector3(0.36, 4.9, 0)
	for k in 7:
		var a := TAU * k / 7.0
		_add(box(Vector3(0.35, 0.04, 2.2)), "Daun", top + Vector3(cos(a) * 0.9, -0.3, sin(a) * 0.9), Vector3.ONE, Vector3(0.45, -a + PI / 2.0, 0), 0.0)
	for k in 3:
		_add(sph(0.14, 8), "Kelapa", top + Vector3(cos(k * 2.1) * 0.2, -0.25, sin(k * 2.1) * 0.2))


func _bush() -> void:
	_mat("Semak", Color("4a8f3f"), 0.95)
	for p in [Vector3(0, 0.45, 0), Vector3(0.45, 0.35, 0.1), Vector3(-0.4, 0.38, -0.1), Vector3(0.05, 0.35, 0.42)]:
		_add(sph(0.5, 9), "Semak", p, Vector3(1, 0.8, 1), Vector3.ZERO, 0.07)


func _flowers() -> void:
	_mat("Batang", Color("4f8a3a"), 0.9)
	_mat("Kelopak", Color("ffd166"), 0.7)
	_mat("Kelopak2", Color("ff7eb6"), 0.7)
	for k in 7:
		var p := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var h := rng.randf_range(0.2, 0.38)
		_add(cyl(0.008, 0.01, h, 4), "Batang", p + Vector3(0, h / 2.0, 0))
		_add(sph(0.045, 6), "Kelopak" if k % 2 == 0 else "Kelopak2", p + Vector3(0, h, 0), Vector3(1, 0.5, 1))


func _rock(kind: int) -> void:
	_mat("Batu", Color("8f8a80") if kind == 0 else Color("a39b8c"), 0.95)
	_mat("Lumut", Color("6f8f4a"), 0.95)
	if kind == 0:
		_add(sph(0.7, 9), "Batu", Vector3(0, 0.35, 0), Vector3(1.2, 0.75, 1.0), Vector3.ZERO, 0.12)
		_add(sph(0.35, 7), "Batu", Vector3(0.7, 0.18, 0.2), Vector3(1.0, 0.7, 0.9), Vector3.ZERO, 0.06)
		_add(sph(0.3, 7), "Lumut", Vector3(-0.1, 0.78, 0.0), Vector3(1.3, 0.3, 1.0), Vector3.ZERO, 0.04)
	else:
		_add(sph(0.55, 8), "Batu", Vector3(0, 0.45, 0), Vector3(0.9, 1.2, 0.85), Vector3.ZERO, 0.1)
		_add(sph(0.3, 7), "Batu", Vector3(-0.5, 0.15, 0.25), Vector3(1.0, 0.6, 1.0), Vector3.ZERO, 0.05)


# --- Objek pendidikan ------------------------------------------------------------------------------------

## Patung simbol matematika di atas alas (+, −, ×, =): tinggi ±2 m.
func _math_statue() -> void:
	_mat("Alas", Color("d8d2c4"), 0.9)
	_mat("Emas", Color("d9a83a"), 0.35, 0.6)
	_add(box(Vector3(1.0, 0.5, 1.0)), "Alas", Vector3(0, 0.25, 0))
	_add(box(Vector3(0.8, 0.12, 0.8)), "Alas", Vector3(0, 0.56, 0))
	_add(box(Vector3(0.18, 0.9, 0.18)), "Emas", Vector3(0, 1.25, 0))
	_add(box(Vector3(0.9, 0.18, 0.18)), "Emas", Vector3(0, 1.25, 0))
	_add(sph(0.12, 8), "Emas", Vector3(0, 1.85, 0))


func _big_book() -> void:
	_mat("Sampul", Color("8a3a3a"), 0.8)
	_mat("Kertas", Color("f4efe0"), 0.9)
	_mat("Kayu", Color("6b4a2e"), 0.9)
	_add(box(Vector3(0.9, 0.7, 0.9)), "Kayu", Vector3(0, 0.35, 0))
	for side in [-1.0, 1.0]:
		_add(box(Vector3(0.62, 0.06, 0.85)), "Sampul", Vector3(0.31 * side, 0.78, 0), Vector3.ONE, Vector3(0, 0, -0.18 * side))
		_add(box(Vector3(0.56, 0.08, 0.78)), "Kertas", Vector3(0.29 * side, 0.83, 0), Vector3.ONE, Vector3(0, 0, -0.16 * side))


func _microscope() -> void:
	_mat("Logam", Color("cfd6de"), 0.3, 0.7)
	_mat("Hitam", Color("2b2b33"), 0.5)
	_mat("Meja", Color("e8eef5"), 0.6)
	_add(box(Vector3(1.2, 0.06, 0.7)), "Meja", Vector3(0, 0.75, 0))
	for x in [-0.5, 0.5]:
		for z in [-0.28, 0.28]:
			_add(cyl(0.03, 0.03, 0.72, 6), "Logam", Vector3(x, 0.36, z))
	_add(box(Vector3(0.22, 0.04, 0.28)), "Hitam", Vector3(0, 0.8, 0))
	_add(box(Vector3(0.06, 0.32, 0.06)), "Hitam", Vector3(0, 0.98, -0.1), Vector3.ONE, Vector3(-0.3, 0, 0))
	_add(cyl(0.035, 0.04, 0.24, 10), "Logam", Vector3(0, 1.12, 0.0), Vector3.ONE, Vector3(0.45, 0, 0))
	_add(box(Vector3(0.14, 0.02, 0.14)), "Hitam", Vector3(0, 0.88, 0.05))
	for k in 3:
		_add(cyl(0.025, 0.025, 0.16, 8), "Logam", Vector3(0.35 + k * 0.07, 0.86, 0.15))


func _globe() -> void:
	_mat("Laut", Color("3f7fd8"), 0.5)
	_mat("Darat", Color("5aa84a"), 0.7)
	_mat("Kayu", Color("6b4a2e"), 0.9)
	_mat("Emas", Color("d9a83a"), 0.35, 0.6)
	_add(cyl(0.25, 0.35, 0.12, 12), "Kayu", Vector3(0, 0.06, 0))
	_add(cyl(0.04, 0.05, 0.8, 8), "Kayu", Vector3(0, 0.5, 0))
	_add(sph(0.42, 16), "Laut", Vector3(0, 1.25, 0))
	for p in [Vector3(0.25, 0.18, 0.25), Vector3(-0.3, 0.05, 0.2), Vector3(0.05, -0.2, -0.36), Vector3(-0.15, 0.3, -0.2)]:
		_add(sph(0.16, 8), "Darat", Vector3(0, 1.25, 0) + p, Vector3(1, 0.6, 1), Vector3.ZERO, 0.03)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.49
	ring.rings = 24
	ring.ring_segments = 6
	_add(ring, "Emas", Vector3(0, 1.25, 0), Vector3.ONE, Vector3(PI / 2.0, 0, 0.4))


## Papan informasi bertiang (teks ditambahkan di game dengan Label3D).
func _info_board() -> void:
	_mat("Kayu", Color("7a5230"), 0.9)
	_mat("Papan", Color("f4e6c4"), 0.85)
	_mat("Atap", Color("a0452e"), 0.8)
	for x in [-0.8, 0.8]:
		_add(cyl(0.06, 0.07, 2.2, 8), "Kayu", Vector3(x, 1.1, 0))
	_add(box(Vector3(1.7, 1.0, 0.08)), "Kayu", Vector3(0, 1.45, 0))
	_add(box(Vector3(1.55, 0.86, 0.02)), "Papan", Vector3(0, 1.45, 0.045))
	_add(box(Vector3(1.95, 0.08, 0.5)), "Atap", Vector3(0, 2.25, 0), Vector3.ONE, Vector3(0.0, 0, 0))


func _lamp_post() -> void:
	_mat("Besi", Color("2f3640"), 0.5, 0.5)
	_mat("Lampu", Color("ffe8a0"), 0.3)
	_add(cyl(0.12, 0.16, 0.25, 8), "Besi", Vector3(0, 0.12, 0))
	_add(cyl(0.04, 0.05, 2.6, 8), "Besi", Vector3(0, 1.5, 0))
	_add(cyl(0.18, 0.12, 0.32, 6), "Lampu", Vector3(0, 2.9, 0))
	_add(cyl(0.0, 0.24, 0.18, 6), "Besi", Vector3(0, 3.15, 0))



# --- Bangunan (Fase 10 lanjutan). Ukuran mengikuti tata letak & tabrakan lokasi yang sudah ada. -----------

static func pyr(top: float, bottom: float, h: float) -> CylinderMesh:
	return cyl(top, bottom, h, 4)  # limas segi empat (diputar 45° saat dipakai)


func _cave() -> void:
	_mat("Tebing", Color("6e6559"), 0.95)
	_mat("Gelap", Color("1c1a22"), 1.0)
	_mat("Kristal", Color("5fd0e8"), 0.2, 0.2)
	_mat("Lumut", Color("4f6f3a"), 0.95)
	_add(sph(5.0, 14), "Tebing", Vector3(0, 0, -1.5), Vector3(1.3, 0.85, 1.0), Vector3.ZERO, 0.35)
	_add(sph(1.9, 12), "Gelap", Vector3(0, 0.7, 2.9), Vector3(1.05, 1.15, 0.55))
	for k in 7:
		var a := -1.2 + k * 0.4
		_add(sph(0.8, 8), "Tebing", Vector3(sin(a) * 2.6, 0.25 + absf(cos(a)) * 1.6, 3.0 + cos(a) * 0.4), Vector3(1, 0.9, 0.8), Vector3.ZERO, 0.12)
	for k in 5:
		_add(cyl(0.0, 0.18, 0.8, 5), "Kristal", Vector3(-2.2 + k * 1.1, 0.35, 3.9 + (k % 2) * 0.4), Vector3.ONE, Vector3(0.2 * (k - 2), 0, 0))
	_add(sph(3.0, 10), "Lumut", Vector3(0, 3.7, -1.5), Vector3(1.6, 0.25, 1.2), Vector3.ZERO, 0.15)


func _math_tower() -> void:
	_mat("Batu", Color("cfc6b4"), 0.9)
	_mat("Batu2", Color("b3a891"), 0.9)
	_mat("Atap", Color("2f5fa8"), 0.7)
	_mat("Kaca", Color("8fd0ff"), 0.2)
	_mat("Kayu", Color("6b4a2e"), 0.85)
	_mat("Emas", Color("d9a83a"), 0.35, 0.6)
	for k in 6:
		_add(cyl(2.55 - k * 0.04, 2.7 - k * 0.04, 2.0, 16), "Batu" if k % 2 == 0 else "Batu2", Vector3(0, 1.0 + k * 2.0, 0))
	_add(cyl(3.7, 3.7, 0.2, 20), "Batu2", Vector3(0, 4.0, 0))  # balkon (bisa dinaiki lewat tangga)
	for k in 20:
		var a := TAU * k / 20.0
		_add(cyl(0.05, 0.05, 0.8, 5), "Kayu", Vector3(cos(a) * 3.55, 4.5, sin(a) * 3.55))
	var rail := TorusMesh.new()
	rail.inner_radius = 3.5
	rail.outer_radius = 3.6
	rail.rings = 24
	rail.ring_segments = 4
	_add(rail, "Kayu", Vector3(0, 4.9, 0))
	_add(cyl(0.0, 3.3, 3.8, 16), "Atap", Vector3(0, 13.9, 0))
	_add(sph(0.35, 8), "Emas", Vector3(0, 16.0, 0))
	for k in 4:
		for j in 4:
			var a := TAU * j / 4.0 + k * 0.4
			_add(box(Vector3(0.7, 1.1, 0.2)), "Kaca", Vector3(cos(a) * 2.6, 6.0 + k * 1.7, sin(a) * 2.6), Vector3.ONE, Vector3(0, -a + PI / 2.0, 0))
	_add(box(Vector3(1.4, 2.1, 0.25)), "Kayu", Vector3(0, 1.05, 2.62))


func _library() -> void:
	_mat("Kayu", Color("7a5230"), 0.9)
	_mat("Kayu2", Color("5a3a24"), 0.9)
	_mat("Daun", Color("3f7f3a"), 0.9)
	_mat("Buku", Color("c0503a"), 0.8)
	_mat("Buku2", Color("3f6fb0"), 0.8)
	_mat("Buku3", Color("d9a83a"), 0.8)
	_add(box(Vector3(10, 0.4, 7)), "Kayu2", Vector3(0, 0.2, -1))
	_add(box(Vector3(10, 4.5, 0.4)), "Kayu", Vector3(0, 2.6, -4.3))
	for x in [-4.6, -1.5, 1.5, 4.6]:
		_add(cyl(0.3, 0.42, 4.6, 8), "Kayu2", Vector3(x, 2.5, 2.0), Vector3.ONE, Vector3.ZERO, 0.04)
	_add(box(Vector3(11, 0.4, 7.6)), "Kayu2", Vector3(0, 5.0, -1))
	_add(sph(4.2, 12), "Daun", Vector3(0, 6.0, -1), Vector3(1.45, 0.45, 1.05), Vector3.ZERO, 0.25)
	for row in 3:
		_add(box(Vector3(9.0, 0.08, 0.5)), "Kayu2", Vector3(0, 0.9 + row * 1.1, -3.85))
		for k in 22:
			var c: String = ["Buku", "Buku2", "Buku3"][(k + row) % 3]
			_add(box(Vector3(0.14, 0.7 + (k % 3) * 0.1, 0.4)), c, Vector3(-4.2 + k * 0.4, 1.3 + row * 1.1, -3.85))


func _museum() -> void:
	_mat("Marmer", Color("e9e4d8"), 0.6)
	_mat("Marmer2", Color("cfc8b8"), 0.6)
	_mat("Atap", Color("8a3a2e"), 0.8)
	_mat("Emas", Color("d9a83a"), 0.35, 0.6)
	_mat("Lukisan", Color("3f6fb0"), 0.8)
	_mat("Lukisan2", Color("c98a3a"), 0.8)
	for k in 3:
		_add(box(Vector3(10.8 - k * 0.4, 0.15, 7.6 - k * 0.3)), "Marmer2", Vector3(0, 0.075 + k * 0.15, -1 + k * 0.15))
	_add(box(Vector3(10, 4.5, 0.4)), "Marmer", Vector3(0, 2.7, -4.3))
	for x in [-4.4, -2.2, 0.0, 2.2, 4.4]:
		_add(cyl(0.3, 0.34, 4.3, 12), "Marmer", Vector3(x, 2.6, 2.0))
		_add(box(Vector3(0.8, 0.2, 0.8)), "Marmer2", Vector3(x, 4.85, 2.0))
	_add(box(Vector3(11, 0.5, 7.6)), "Marmer2", Vector3(0, 5.2, -1))
	var tri := PrismMesh.new()
	tri.size = Vector3(11, 1.8, 7.6)
	_add(tri, "Atap", Vector3(0, 6.35, -1))
	_add(sph(0.35, 8), "Emas", Vector3(0, 6.6, 2.85), Vector3(1, 1, 0.3))
	for k in 6:
		_add(box(Vector3(1.2, 1.5, 0.06)), "Lukisan" if k % 2 == 0 else "Lukisan2", Vector3(-3.75 + k * 1.5, 2.6, -4.07))


func _lab_dome() -> void:
	_mat("Dinding", Color("e3e9f0"), 0.5)
	_mat("Kaca", Color("7fd4f0"), 0.15, 0.1)
	_mat("Biru", Color("2f6fb0"), 0.6)
	_mat("Logam", Color("aab4be"), 0.3, 0.7)
	_mat("Panel", Color("1f2f4a"), 0.3, 0.3)
	_add(cyl(4.5, 4.6, 3.4, 24), "Dinding", Vector3(0, 1.7, -2))
	_add(cyl(4.62, 4.62, 0.3, 24), "Biru", Vector3(0, 1.2, -2))
	_add(sph(4.4, 20), "Kaca", Vector3(0, 3.3, -2), Vector3(1, 0.62, 1))
	_add(box(Vector3(1.6, 2.4, 0.4)), "Biru", Vector3(0, 1.2, 2.5))
	_add(cyl(0.06, 0.06, 2.5, 6), "Logam", Vector3(2.5, 6.4, -2.5))
	_add(sph(0.18, 8), "Biru", Vector3(2.5, 7.7, -2.5))
	for k in 3:
		_add(box(Vector3(1.6, 0.06, 1.0)), "Panel", Vector3(-3.2 + k * 1.7, 0.6, -6.8), Vector3.ONE, Vector3(-0.5, 0, 0))
	_add(box(Vector3(4.0, 0.9, 1.2)), "Dinding", Vector3(0, 0.45, 3.0))


func _market_stall() -> void:
	_mat("Kayu", Color("8a5a30"), 0.9)
	_mat("Kain", Color("c0503a"), 0.85)
	_mat("Kain2", Color("f4e6c4"), 0.85)
	_mat("Keranjang", Color("b08a50"), 0.95)
	_mat("Buah", Color("e0a020"), 0.6)
	_mat("Buah2", Color("5aa84a"), 0.6)
	_add(box(Vector3(2.6, 0.9, 1.3)), "Kayu", Vector3(0, 0.45, 0))
	for x in [-1.25, 1.25]:
		for z in [-0.6, 0.6]:
			_add(cyl(0.05, 0.06, 2.4, 6), "Kayu", Vector3(x, 1.2, z))
	for k in 6:
		_add(box(Vector3(0.45, 0.04, 1.7)), "Kain" if k % 2 == 0 else "Kain2", Vector3(-1.13 + k * 0.45, 2.4, 0.1), Vector3.ONE, Vector3(0.18, 0, 0))
	for k in 3:
		_add(cyl(0.28, 0.22, 0.18, 10), "Keranjang", Vector3(-0.8 + k * 0.8, 1.0, 0))
		for j in 4:
			_add(sph(0.09, 6), "Buah" if k != 1 else "Buah2", Vector3(-0.8 + k * 0.8 + (j % 2) * 0.12 - 0.06, 1.13, (j / 2) * 0.12 - 0.06))


## Rumah Gadang (Minangkabau, Sumatera Barat): rumah panggung memanjang, atap bergonjong melengkung ke atas.
func _rumah_gadang() -> void:
	_mat("Kayu", Color("6b3a24"), 0.85)
	_mat("Ukiran", Color("b0302a"), 0.8)
	_mat("Ijuk", Color("2a2622"), 0.95)
	_mat("Emas", Color("d9a83a"), 0.4, 0.5)
	for x in [-1.6, -0.5, 0.5, 1.6]:
		for z in [-1.1, 1.1]:
			_add(cyl(0.1, 0.12, 1.0, 6), "Kayu", Vector3(x, 0.5, z))
	_add(box(Vector3(3.8, 1.6, 2.6)), "Ukiran", Vector3(0, 1.8, 0))
	_add(box(Vector3(3.9, 0.15, 2.7)), "Emas", Vector3(0, 1.05, 0))
	for side in [-1.0, 1.0]:
		_add(box(Vector3(4.6, 0.12, 1.8)), "Ijuk", Vector3(0, 3.1, 0.75 * side), Vector3.ONE, Vector3(0.6 * side, 0, 0))
	for x in [-2.2, -1.1, 1.1, 2.2]:
		_add(cyl(0.0, 0.22, 1.4, 6), "Ijuk", Vector3(x, 3.95 + absf(x) * 0.25, 0), Vector3.ONE, Vector3(0, 0, -0.55 * signf(x)))


## Joglo (Jawa Tengah / Yogyakarta): pendopo kayu terbuka, atap limas bertingkat menjulang di tengah.
func _joglo() -> void:
	_mat("Kayu", Color("7a4a26"), 0.85)
	_mat("Genteng", Color("9a4a2e"), 0.8)
	_mat("Lantai", Color("c9b28a"), 0.9)
	_add(box(Vector3(3.8, 0.35, 3.4)), "Lantai", Vector3(0, 0.18, 0))
	for x in [-1.5, -0.5, 0.5, 1.5]:
		for z in [-1.3, 1.3]:
			_add(cyl(0.09, 0.1, 2.2, 6), "Kayu", Vector3(x, 1.45, z))
	_add(box(Vector3(2.4, 1.8, 0.12)), "Kayu", Vector3(0, 1.3, -1.25))
	_add(pyr(1.6, 3.0, 0.7), "Genteng", Vector3(0, 2.9, 0), Vector3(1.0, 1, 0.9), Vector3(0, PI / 4.0, 0))
	_add(pyr(0.25, 1.6, 1.5), "Genteng", Vector3(0, 4.0, 0), Vector3(1.0, 1, 0.9), Vector3(0, PI / 4.0, 0))


## Tongkonan (Toraja, Sulawesi Selatan): rumah panggung, atap pelana berbentuk perahu melengkung tinggi di ujung.
func _tongkonan() -> void:
	_mat("Kayu", Color("5a3020"), 0.85)
	_mat("Ukiran", Color("8a2a20"), 0.8)
	_mat("Hitam", Color("1f1a18"), 0.9)
	_mat("Kuning", Color("d9b04a"), 0.7)
	for x in [-1.2, 0, 1.2]:
		for z in [-0.9, 0.9]:
			_add(cyl(0.12, 0.14, 1.3, 6), "Kayu", Vector3(x, 0.65, z))
	_add(box(Vector3(3.0, 1.3, 2.0)), "Ukiran", Vector3(0, 1.95, 0))
	for k in 4:
		_add(box(Vector3(3.0, 0.08, 0.04)), "Kuning", Vector3(0, 1.5 + k * 0.3, 1.02))
	for k in 9:
		var t := (k - 4) / 4.0
		var y := 3.0 + t * t * 1.4
		_add(box(Vector3(0.62, 0.15, 2.6)), "Hitam", Vector3(t * 2.4, y, 0), Vector3.ONE, Vector3(0, 0, -t * 0.55))
	_add(cyl(0.08, 0.08, 1.6, 6), "Kayu", Vector3(2.4, 3.1, 0), Vector3.ONE, Vector3(0, 0, 0.0))
	_add(cyl(0.08, 0.08, 1.6, 6), "Kayu", Vector3(-2.4, 3.1, 0))


func _lighthouse() -> void:
	_mat("Merah", Color("b8352a"), 0.7)
	_mat("Putih", Color("f2efe8"), 0.7)
	_mat("Besi", Color("2f3640"), 0.5, 0.5)
	_mat("Kaca", Color("ffe08a"), 0.2)
	_mat("Batu", Color("8f8a80"), 0.95)
	_add(cyl(2.4, 2.8, 1.2, 16), "Batu", Vector3(0, 0.6, 0))
	for k in 6:
		_add(cyl(1.6 - k * 0.12, 1.72 - k * 0.12, 3.0, 16), "Merah" if k % 2 == 0 else "Putih", Vector3(0, 2.7 + k * 3.0, 0))
	_add(cyl(1.6, 1.6, 0.25, 16), "Besi", Vector3(0, 19.4, 0))
	for k in 16:
		var a := TAU * k / 16.0
		_add(cyl(0.03, 0.03, 0.7, 4), "Besi", Vector3(cos(a) * 1.5, 19.85, sin(a) * 1.5))
	_add(cyl(0.8, 0.8, 1.2, 12), "Kaca", Vector3(0, 20.2, 0))
	_add(cyl(0.0, 1.0, 0.9, 12), "Merah", Vector3(0, 21.25, 0))
	_add(box(Vector3(0.9, 1.8, 0.2)), "Besi", Vector3(0, 2.0, 1.72))


func _observatory() -> void:
	_mat("Dinding", Color("e3e9f0"), 0.5)
	_mat("Kubah", Color("b8c4d0"), 0.3, 0.6)
	_mat("Celah", Color("1f2f4a"), 0.4)
	_mat("Logam", Color("6b5f86"), 0.4, 0.5)
	_add(cyl(3.0, 3.6, 12.0, 20), "Dinding", Vector3(0, 6, 0))
	for k in 3:
		_add(cyl(3.05, 3.05, 0.3, 20), "Logam", Vector3(0, 3.0 + k * 3.5, 0))
	_add(sph(3.6, 20), "Kubah", Vector3(0, 12, 0), Vector3(1, 0.9, 1))
	_add(box(Vector3(1.0, 3.0, 0.4)), "Celah", Vector3(0, 13.4, 2.8), Vector3.ONE, Vector3(-0.5, 0, 0))
	_add(cyl(0.45, 0.65, 4.5, 12), "Logam", Vector3(0, 14.3, 2.2), Vector3.ONE, Vector3(-0.9, 0, 0))
