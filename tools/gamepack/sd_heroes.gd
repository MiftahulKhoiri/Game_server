extends SceneTree
## Pembuat model pahlawan anak Petualangan Pulau Ilmu (Fase 9) — ASET BUATAN SENDIRI (CC0, lihat LISENSI.txt).
## Menghasilkan dua GLB glTF 2.0 berkerangka SAMA (anak laki-laki & perempuan, ±1,45 m, gaya semi-realistis
## low-poly) lengkap dengan 12 animasi, lalu disimpan di res://games/education_sd/assets/characters/hero/.
##
## Pakai (dari akar repo):
##   godot --headless --path client -s ../tools/gamepack/sd_heroes.gd
## lalu `godot --headless --path client --import` supaya Godot mengimpor GLB-nya.
##
## Kerangka (L = kiri anatomis, di +X karena karakter menghadap +Z): Root > Pelvis > Spine > Chest > Neck > Head; Chest > Shoulder_L/R > UpperArm > LowerArm > Hand;
## Pelvis > UpperLeg_L/R > LowerLeg > Foot. Bagian tubuh dikunci kaku ke satu tulang (low-poly), sendi ditutup
## bola (siku/lutut/bahu) supaya tidak bolong saat menekuk.

const OUT := "res://games/education_sd/assets/characters/hero/"

# nama, induk, posisi istirahat lokal
const BONES := [
	["Root", "", Vector3.ZERO],
	["Pelvis", "Root", Vector3(0, 0.72, 0)],
	["Spine", "Pelvis", Vector3(0, 0.09, 0)],
	["Chest", "Spine", Vector3(0, 0.15, 0)],
	["Neck", "Chest", Vector3(0, 0.19, 0)],
	["Head", "Neck", Vector3(0, 0.06, 0)],
	["Shoulder_R", "Chest", Vector3(-0.06, 0.15, 0)],
	["UpperArm_R", "Shoulder_R", Vector3(-0.1, 0, 0)],
	["LowerArm_R", "UpperArm_R", Vector3(0, -0.24, 0)],
	["Hand_R", "LowerArm_R", Vector3(0, -0.22, 0)],
	["Shoulder_L", "Chest", Vector3(0.06, 0.15, 0)],
	["UpperArm_L", "Shoulder_L", Vector3(0.1, 0, 0)],
	["LowerArm_L", "UpperArm_L", Vector3(0, -0.24, 0)],
	["Hand_L", "LowerArm_L", Vector3(0, -0.22, 0)],
	["UpperLeg_R", "Pelvis", Vector3(-0.08, -0.04, 0)],
	["LowerLeg_R", "UpperLeg_R", Vector3(0, -0.32, 0)],
	["Foot_R", "LowerLeg_R", Vector3(0, -0.31, 0)],
	["UpperLeg_L", "Pelvis", Vector3(0.08, -0.04, 0)],
	["LowerLeg_L", "UpperLeg_L", Vector3(0, -0.32, 0)],
	["Foot_L", "LowerLeg_L", Vector3(0, -0.31, 0)],
]

var skel: Skeleton3D
var surfaces: Dictionary = {}  # nama material -> {v, n, i, b, w}
var mats: Dictionary = {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "male"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "female"))
	var ok := _make("male", false) and _make("female", true)
	print("HERO GLB: ", "OK" if ok else "GAGAL")
	quit(0 if ok else 1)


func _gpos(bone: String) -> Vector3:
	var p := Vector3.ZERO
	var cur := bone
	while cur != "":
		for b in BONES:
			if b[0] == cur:
				p += b[2]
				cur = b[1]
				break
	return p


func _mat(name: String, c: Color, rough := 0.8) -> void:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = c
	m.roughness = rough
	mats[name] = m


func _add(mesh: PrimitiveMesh, mat: String, bone: String, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> void:
	var arr := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(rot) * Basis.from_scale(scl)
	var nb := basis.inverse().transposed()
	if not surfaces.has(mat):
		surfaces[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array(), "b": PackedInt32Array(), "w": PackedFloat32Array()}
	var s: Dictionary = surfaces[mat]
	var base: int = (s.v as PackedVector3Array).size()
	var bi := skel.find_bone(bone)
	for k in v.size():
		s.v.append(basis * v[k] + pos)
		s.n.append((nb * n[k]).normalized())
		s.b.append_array(PackedInt32Array([bi, 0, 0, 0]))
		s.w.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	for k in idx:
		s.i.append(base + k)


static func cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


static func sph(r: float, seg := 14) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(6, seg / 2)
	return m


static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func cyl(t: float, b: float, h: float, seg := 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = t
	m.bottom_radius = b
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _make(kind: String, girl: bool) -> bool:
	surfaces.clear()
	mats.clear()
	var root := Node3D.new()
	root.name = "Hero_" + kind
	skel = Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	for b in BONES:
		var i := skel.add_bone(b[0])
		if b[1] != "":
			skel.set_bone_parent(i, skel.find_bone(b[1]))
		skel.set_bone_rest(i, Transform3D(Basis(), b[2]))
		skel.set_bone_pose_position(i, b[2])
	_mat("Kulit", Color("e9b38a"), 0.7)
	_mat("Rambut", Color("3a2618") if not girl else Color("5a3220"), 0.6)
	_mat("Baju", Color("f4efe6"), 0.85)  # diwarnai ulang sesuai kostum (Fase 9 - integrasi kostum)
	_mat("Rompi", Color("4f7a5a") if not girl else Color("8a5aa8"), 0.9)
	_mat("Celana", Color("6b5a44") if not girl else Color("3f5f8a"), 0.9)
	_mat("Sepatu", Color("5a3a24"), 0.6)
	_mat("Tas", Color("a0622e"), 0.75)
	_mat("Mata", Color("fbfbf8"), 0.3)
	_mat("Pupil", Color("3a2a1c"), 0.2)
	_mat("Aksen", Color("d9b04a"), 0.4)
	_mat("Bibir", Color("c06a5a"), 0.6)
	var P := _gpos
	# --- badan
	_add(cyl(0.135, 0.145, 0.16), "Celana", "Pelvis", P.call("Pelvis") + Vector3(0, -0.01, 0), Vector3(1, 1, 0.78))
	_add(cyl(0.142, 0.148, 0.045), "Tas", "Pelvis", P.call("Pelvis") + Vector3(0, 0.07, 0), Vector3(1, 1, 0.8))
	_add(box(Vector3(0.05, 0.04, 0.02)), "Aksen", "Pelvis", P.call("Pelvis") + Vector3(0, 0.07, 0.118))
	_add(cap(0.125, 0.22), "Baju", "Spine", P.call("Spine") + Vector3(0, 0.03, 0), Vector3(1, 1, 0.76))
	_add(cap(0.148, 0.3), "Baju", "Chest", P.call("Chest") + Vector3(0, 0.04, 0), Vector3(1, 1, 0.74))
	_add(cap(0.152, 0.27), "Rompi", "Chest", P.call("Chest") + Vector3(0, 0.03, -0.006), Vector3(1.0, 1.0, 0.74))
	_add(box(Vector3(0.07, 0.24, 0.02)), "Baju", "Chest", P.call("Chest") + Vector3(0, 0.03, 0.112))
	for k in 3:
		_add(sph(0.008, 6), "Aksen", "Chest", P.call("Chest") + Vector3(0, 0.11 - k * 0.07, 0.123))
	var collar := TorusMesh.new()
	collar.inner_radius = 0.045
	collar.outer_radius = 0.07
	collar.rings = 12
	collar.ring_segments = 6
	_add(collar, "Baju", "Chest", P.call("Neck") + Vector3(0, -0.01, 0.005))
	_add(cyl(0.042, 0.047, 0.09), "Kulit", "Neck", P.call("Neck") + Vector3(0, 0.025, 0))
	# --- tas: laki-laki tas selempang di pinggul, perempuan ransel kecil
	if not girl:
		_add(box(Vector3(0.13, 0.11, 0.05)), "Tas", "Pelvis", P.call("Pelvis") + Vector3(-0.17, 0.02, 0.03))
		_add(box(Vector3(0.135, 0.04, 0.055)), "Rompi", "Pelvis", P.call("Pelvis") + Vector3(-0.17, 0.065, 0.03))
		_add(box(Vector3(0.025, 0.5, 0.012)), "Tas", "Chest", P.call("Chest") + Vector3(0.0, 0.0, 0.118), Vector3.ONE, Vector3(0, 0, 0.62))
		_add(box(Vector3(0.025, 0.5, 0.012)), "Tas", "Chest", P.call("Chest") + Vector3(0.0, 0.0, -0.118), Vector3.ONE, Vector3(0, 0, -0.62))
	else:
		_add(box(Vector3(0.17, 0.2, 0.08)), "Tas", "Chest", P.call("Chest") + Vector3(0, 0.02, -0.15))
		_add(box(Vector3(0.12, 0.08, 0.03)), "Rompi", "Chest", P.call("Chest") + Vector3(0, -0.02, -0.2))
	# --- kepala
	var hp: Vector3 = P.call("Head") + Vector3(0, 0.1, 0)
	_add(sph(0.112, 18), "Kulit", "Head", hp, Vector3(0.9, 1.06, 0.98))
	_add(sph(0.07, 12), "Kulit", "Head", hp + Vector3(0, -0.06, 0.03), Vector3(1.15, 0.85, 1.0))
	_add(sph(0.016, 8), "Kulit", "Head", hp + Vector3(0, -0.005, 0.11), Vector3(0.9, 1.1, 1.0))
	for side in [-1.0, 1.0]:
		_add(sph(0.021, 10), "Mata", "Head", hp + Vector3(0.039 * side, 0.012, 0.094), Vector3(1.15, 0.9, 0.6))
		_add(sph(0.012, 8), "Pupil", "Head", hp + Vector3(0.039 * side, 0.011, 0.104))
		_add(box(Vector3(0.038, 0.007, 0.01)), "Rambut", "Head", hp + Vector3(0.04 * side, 0.045, 0.1), Vector3.ONE, Vector3(0, 0, -0.12 * side))
		_add(sph(0.025, 8), "Kulit", "Head", hp + Vector3(0.102 * side, 0.0, -0.005), Vector3(0.45, 1.0, 0.75))
	_add(box(Vector3(0.036, 0.008, 0.01)), "Bibir", "Head", hp + Vector3(0, -0.052, 0.098))
	# rambut
	_add(sph(0.12, 16), "Rambut", "Head", hp + Vector3(0, 0.03, -0.012), Vector3(0.95, 0.9, 1.0))
	_add(box(Vector3(0.17, 0.035, 0.05)), "Rambut", "Head", hp + Vector3(0.01, 0.08, 0.075), Vector3.ONE, Vector3(0.35, 0, 0.12))
	if girl:
		_add(cap(0.085, 0.3), "Rambut", "Head", hp + Vector3(0, -0.1, -0.07), Vector3(1.2, 1.0, 0.6))
		_add(cap(0.04, 0.2), "Rambut", "Head", hp + Vector3(0.1, -0.06, 0.02), Vector3.ONE, Vector3(0, 0, 0.1))
		_add(cap(0.04, 0.2), "Rambut", "Head", hp + Vector3(-0.1, -0.06, 0.02), Vector3.ONE, Vector3(0, 0, -0.1))
		_add(sph(0.022, 8), "Aksen", "Head", hp + Vector3(0.075, 0.075, 0.06))
	else:
		for side in [-1.0, 1.0]:
			_add(box(Vector3(0.03, 0.07, 0.08)), "Rambut", "Head", hp + Vector3(0.105 * side, 0.03, -0.01))
	# --- lengan
	for sd in [["R", -1.0], ["L", 1.0]]:
		var s: String = sd[0]
		var x: float = sd[1]
		var ua: Vector3 = P.call("UpperArm_" + s)
		_add(sph(0.058, 10), "Baju", "UpperArm_" + s, ua + Vector3(0, -0.01, 0))
		_add(cap(0.052, 0.15), "Baju", "UpperArm_" + s, ua + Vector3(0, -0.06, 0))
		_add(cap(0.041, 0.22), "Kulit", "UpperArm_" + s, ua + Vector3(0, -0.13, 0))
		var la: Vector3 = P.call("LowerArm_" + s)
		_add(sph(0.04, 8), "Kulit", "LowerArm_" + s, la)
		_add(cap(0.036, 0.22), "Kulit", "LowerArm_" + s, la + Vector3(0, -0.1, 0))
		var hd: Vector3 = P.call("Hand_" + s)
		_add(sph(0.043, 10), "Kulit", "Hand_" + s, hd + Vector3(0, -0.035, 0.005), Vector3(0.75, 1.1, 0.55))
		_add(cap(0.014, 0.06), "Kulit", "Hand_" + s, hd + Vector3(-0.03 * x, -0.025, 0.025), Vector3.ONE, Vector3(0.5, 0, 0.6 * x))
		# --- tungkai
		var ul: Vector3 = P.call("UpperLeg_" + s)
		_add(cap(0.066, 0.36), "Celana", "UpperLeg_" + s, ul + Vector3(0, -0.15, 0))
		var ll: Vector3 = P.call("LowerLeg_" + s)
		_add(sph(0.058, 10), "Celana", "LowerLeg_" + s, ll)
		_add(cap(0.052, 0.3), "Celana", "LowerLeg_" + s, ll + Vector3(0, -0.13, 0))
		_add(cyl(0.058, 0.062, 0.13, 12), "Sepatu", "LowerLeg_" + s, ll + Vector3(0, -0.25, 0))
		var ft: Vector3 = P.call("Foot_" + s)
		_add(box(Vector3(0.095, 0.075, 0.2)), "Sepatu", "Foot_" + s, ft + Vector3(0, -0.012, 0.035))
		_add(box(Vector3(0.1, 0.02, 0.21)), "Pupil", "Foot_" + s, ft + Vector3(0, -0.047, 0.035))
	# --- mesh berkulit
	var am := ArrayMesh.new()
	for name in surfaces:
		var s: Dictionary = surfaces[name]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.n
		arrays[Mesh.ARRAY_INDEX] = s.i
		arrays[Mesh.ARRAY_BONES] = s.b
		arrays[Mesh.ARRAY_WEIGHTS] = s.w
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(am.get_surface_count() - 1, mats[name])
		am.surface_set_name(am.get_surface_count() - 1, name)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = am
	skel.add_child(mi)
	mi.skin = skel.create_skin_from_rest_transforms()
	mi.skeleton = NodePath("..")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	for a in _animations():
		lib.add_animation(a.resource_name, a)
	ap.add_animation_library("", lib)
	for n in root.get_children():
		n.owner = root
	mi.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT + "%s/hero_%s.glb" % [kind, kind]))
	print("  %s: %d permukaan, %d verteks, %d tulang, %d animasi -> %s" % [kind, am.get_surface_count(),
		_count_verts(), skel.get_bone_count(), lib.get_animation_list().size(), error_string(err)])
	root.free()
	return err == OK


func _count_verts() -> int:
	var n := 0
	for k in surfaces:
		n += (surfaces[k].v as PackedVector3Array).size()
	return n


# --- Animasi -----------------------------------------------------------------------------------------------
# Konvensi: karakter menghadap +Z, tulang menggantung ke -Y. Rotasi X negatif = ayun ke depan (paha/lengan),
# lutut menekuk = X positif, siku menekuk = X negatif. Lengan diangkat ke samping: Z negatif (kiri), Z positif (kanan).

func _q(x := 0.0, y := 0.0, z := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))


## keys: {tulang: [[waktu, Vector3 euler], ...]}, pelvis: [[waktu, Vector3 posisi]]
func _anim(name: String, length: float, loop: bool, keys: Dictionary, pelvis: Array = []) -> Animation:
	var a := Animation.new()
	a.resource_name = name
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for bone in keys:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, "Skeleton3D:" + bone)
		for k in keys[bone]:
			var e: Vector3 = k[1]
			a.rotation_track_insert_key(t, k[0], _q(e.x, e.y, e.z))
	if not pelvis.is_empty():
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, "Skeleton3D:Pelvis")
		for k in pelvis:
			a.position_track_insert_key(t, k[0], Vector3(0, 0.72, 0) + (k[1] as Vector3))
	return a


func _cycle(L: float, thigh: float, knee: float, arm: float, elbow: float, lean: float, bob: float) -> Array:
	var keys := {}
	var steps := 8
	var ul := []
	var ur := []
	var lll := []
	var llr := []
	var al := []
	var ar := []
	var pel := []
	for k in steps + 1:
		var t := L * k / steps
		var ph := TAU * k / steps
		ul.append([t, Vector3(-sin(ph) * thigh, 0, 0)])
		ur.append([t, Vector3(sin(ph) * thigh, 0, 0)])
		lll.append([t, Vector3(maxf(0.0, sin(ph - 0.6)) * knee + 0.05, 0, 0)])
		llr.append([t, Vector3(maxf(0.0, -sin(ph - 0.6)) * knee + 0.05, 0, 0)])
		al.append([t, Vector3(sin(ph) * arm, 0, -0.08)])
		ar.append([t, Vector3(-sin(ph) * arm, 0, 0.08)])
		pel.append([t, Vector3(0, -absf(cos(ph)) * bob, 0)])
	keys["UpperLeg_R"] = ul
	keys["UpperLeg_L"] = ur
	keys["LowerLeg_R"] = lll
	keys["LowerLeg_L"] = llr
	keys["UpperArm_R"] = al
	keys["UpperArm_L"] = ar
	keys["LowerArm_R"] = [[0.0, Vector3(-elbow, 0, 0)], [L, Vector3(-elbow, 0, 0)]]
	keys["LowerArm_L"] = [[0.0, Vector3(-elbow, 0, 0)], [L, Vector3(-elbow, 0, 0)]]
	keys["Spine"] = [[0.0, Vector3(lean, 0, 0)], [L, Vector3(lean, 0, 0)]]
	keys["Foot_R"] = [[0.0, Vector3(0, 0, 0)], [L, Vector3(0, 0, 0)]]
	return [keys, pel]


func _animations() -> Array:
	var out: Array = []
	var arms_down := {"UpperArm_R": Vector3(0, 0, -0.08), "UpperArm_L": Vector3(0, 0, 0.08), "LowerArm_R": Vector3(-0.15, 0, 0), "LowerArm_L": Vector3(-0.15, 0, 0)}
	var idle := {}
	for b in arms_down:
		idle[b] = [[0.0, arms_down[b]], [1.2, arms_down[b] + Vector3(-0.04, 0, 0)], [2.4, arms_down[b]]]
	idle["Chest"] = [[0.0, Vector3(0, 0, 0)], [1.2, Vector3(-0.03, 0, 0)], [2.4, Vector3(0, 0, 0)]]
	idle["Head"] = [[0.0, Vector3(0, 0, 0)], [0.8, Vector3(0, 0.15, 0)], [1.6, Vector3(0, -0.1, 0)], [2.4, Vector3(0, 0, 0)]]
	out.append(_anim("idle", 2.4, true, idle, [[0.0, Vector3.ZERO], [1.2, Vector3(0, -0.006, 0)], [2.4, Vector3.ZERO]]))
	var w: Array = _cycle(1.0, 0.45, 0.75, 0.38, 0.25, 0.04, 0.02)
	out.append(_anim("walk", 1.0, true, w[0], w[1]))
	var r: Array = _cycle(0.66, 0.75, 1.25, 0.7, 1.1, 0.2, 0.045)
	out.append(_anim("run", 0.66, true, r[0], r[1]))
	out.append(_anim("jump", 0.4, false, {
		"UpperLeg_R": [[0.0, Vector3(-0.5, 0, 0)], [0.15, Vector3(0.2, 0, 0)], [0.4, Vector3(-0.7, 0, 0)]],
		"UpperLeg_L": [[0.0, Vector3(-0.5, 0, 0)], [0.15, Vector3(0.15, 0, 0)], [0.4, Vector3(-0.3, 0, 0)]],
		"LowerLeg_R": [[0.0, Vector3(1.0, 0, 0)], [0.15, Vector3(0.1, 0, 0)], [0.4, Vector3(1.2, 0, 0)]],
		"LowerLeg_L": [[0.0, Vector3(1.0, 0, 0)], [0.15, Vector3(0.1, 0, 0)], [0.4, Vector3(0.7, 0, 0)]],
		"UpperArm_R": [[0.0, Vector3(0.4, 0, -0.1)], [0.4, Vector3(-2.4, 0, -0.3)]],
		"UpperArm_L": [[0.0, Vector3(0.4, 0, 0.1)], [0.4, Vector3(-2.4, 0, 0.3)]],
	}, [[0.0, Vector3(0, -0.12, 0)], [0.15, Vector3(0, 0, 0)], [0.4, Vector3(0, 0, 0)]]))
	out.append(_anim("fall", 0.8, true, {
		"UpperLeg_R": [[0.0, Vector3(-0.6, 0, 0)], [0.4, Vector3(-0.5, 0, 0)], [0.8, Vector3(-0.6, 0, 0)]],
		"UpperLeg_L": [[0.0, Vector3(-0.2, 0, 0)], [0.4, Vector3(-0.3, 0, 0)], [0.8, Vector3(-0.2, 0, 0)]],
		"LowerLeg_R": [[0.0, Vector3(0.9, 0, 0)], [0.8, Vector3(0.9, 0, 0)]],
		"LowerLeg_L": [[0.0, Vector3(0.5, 0, 0)], [0.8, Vector3(0.5, 0, 0)]],
		"UpperArm_R": [[0.0, Vector3(-0.3, 0, -1.2)], [0.4, Vector3(-0.3, 0, -1.4)], [0.8, Vector3(-0.3, 0, -1.2)]],
		"UpperArm_L": [[0.0, Vector3(-0.3, 0, 1.2)], [0.4, Vector3(-0.3, 0, 1.4)], [0.8, Vector3(-0.3, 0, 1.2)]],
	}))
	out.append(_anim("land", 0.35, false, {
		"UpperLeg_R": [[0.0, Vector3(-0.8, 0, 0)], [0.35, Vector3(0, 0, 0)]],
		"UpperLeg_L": [[0.0, Vector3(-0.8, 0, 0)], [0.35, Vector3(0, 0, 0)]],
		"LowerLeg_R": [[0.0, Vector3(1.4, 0, 0)], [0.35, Vector3(0.05, 0, 0)]],
		"LowerLeg_L": [[0.0, Vector3(1.4, 0, 0)], [0.35, Vector3(0.05, 0, 0)]],
		"Spine": [[0.0, Vector3(0.35, 0, 0)], [0.35, Vector3(0, 0, 0)]],
		"UpperArm_R": [[0.0, Vector3(-0.5, 0, -0.3)], [0.35, Vector3(0, 0, -0.08)]],
		"UpperArm_L": [[0.0, Vector3(-0.5, 0, 0.3)], [0.35, Vector3(0, 0, 0.08)]],
	}, [[0.0, Vector3(0, -0.17, 0)], [0.35, Vector3.ZERO]]))
	out.append(_anim("interact", 0.9, false, {
		"UpperArm_L": [[0.0, Vector3(0, 0, 0.08)], [0.35, Vector3(-1.3, 0, 0.1)], [0.6, Vector3(-1.3, 0, 0.1)], [0.9, Vector3(0, 0, 0.08)]],
		"LowerArm_L": [[0.0, Vector3(-0.15, 0, 0)], [0.35, Vector3(-0.3, 0, 0)], [0.9, Vector3(-0.15, 0, 0)]],
		"Spine": [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(0.15, 0, 0)], [0.9, Vector3(0, 0, 0)]],
		"Head": [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(0.2, 0, 0)], [0.9, Vector3(0, 0, 0)]],
	}))
	out.append(_anim("wave", 1.2, true, {
		"UpperArm_L": [[0.0, Vector3(-0.2, 0, 2.5)], [1.2, Vector3(-0.2, 0, 2.5)]],
		"LowerArm_L": [[0.0, Vector3(-0.9, 0, 0)], [0.3, Vector3(-0.4, 0, 0)], [0.6, Vector3(-0.9, 0, 0)], [0.9, Vector3(-0.4, 0, 0)], [1.2, Vector3(-0.9, 0, 0)]],
		"Head": [[0.0, Vector3(0, 0, 0.08)], [1.2, Vector3(0, 0, 0.08)]],
	}))
	out.append(_anim("celebrate", 0.9, true, {
		"UpperArm_R": [[0.0, Vector3(-0.2, 0, -2.6)], [0.45, Vector3(-0.2, 0, -2.9)], [0.9, Vector3(-0.2, 0, -2.6)]],
		"UpperArm_L": [[0.0, Vector3(-0.2, 0, 2.6)], [0.45, Vector3(-0.2, 0, 2.9)], [0.9, Vector3(-0.2, 0, 2.6)]],
		"LowerArm_R": [[0.0, Vector3(-0.3, 0, 0)], [0.9, Vector3(-0.3, 0, 0)]],
		"LowerArm_L": [[0.0, Vector3(-0.3, 0, 0)], [0.9, Vector3(-0.3, 0, 0)]],
		"UpperLeg_R": [[0.0, Vector3(-0.3, 0, 0)], [0.45, Vector3(0, 0, 0)], [0.9, Vector3(-0.3, 0, 0)]],
		"UpperLeg_L": [[0.0, Vector3(-0.3, 0, 0)], [0.45, Vector3(0, 0, 0)], [0.9, Vector3(-0.3, 0, 0)]],
		"LowerLeg_R": [[0.0, Vector3(0.6, 0, 0)], [0.45, Vector3(0.05, 0, 0)], [0.9, Vector3(0.6, 0, 0)]],
		"LowerLeg_L": [[0.0, Vector3(0.6, 0, 0)], [0.45, Vector3(0.05, 0, 0)], [0.9, Vector3(0.6, 0, 0)]],
	}, [[0.0, Vector3(0, -0.07, 0)], [0.45, Vector3(0, 0.12, 0)], [0.9, Vector3(0, -0.07, 0)]]))
	out.append(_anim("turn", 0.5, false, {
		"Spine": [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(0, 0.35, 0)], [0.5, Vector3(0, 0, 0)]],
		"Head": [[0.0, Vector3(0, 0, 0)], [0.2, Vector3(0, 0.45, 0)], [0.5, Vector3(0, 0, 0)]],
		"UpperLeg_R": [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(-0.3, 0, 0)], [0.5, Vector3(0, 0, 0)]],
		"LowerLeg_R": [[0.0, Vector3(0.05, 0, 0)], [0.25, Vector3(0.5, 0, 0)], [0.5, Vector3(0.05, 0, 0)]],
	}))
	out.append(_anim("hit", 0.45, false, {
		"Spine": [[0.0, Vector3(0, 0, 0)], [0.12, Vector3(-0.3, 0, 0)], [0.45, Vector3(0, 0, 0)]],
		"Head": [[0.0, Vector3(0, 0, 0)], [0.12, Vector3(-0.25, 0, 0)], [0.45, Vector3(0, 0, 0)]],
		"UpperArm_R": [[0.0, Vector3(0, 0, -0.08)], [0.12, Vector3(-0.4, 0, -0.9)], [0.45, Vector3(0, 0, -0.08)]],
		"UpperArm_L": [[0.0, Vector3(0, 0, 0.08)], [0.12, Vector3(-0.4, 0, 0.9)], [0.45, Vector3(0, 0, 0.08)]],
	}))
	out.append(_anim("equip", 0.9, false, {
		"UpperArm_L": [[0.0, Vector3(0, 0, 0.08)], [0.3, Vector3(0.3, 0, 0.5)], [0.6, Vector3(-1.4, 0, 0.2)], [0.9, Vector3(0, 0, 0.08)]],
		"LowerArm_L": [[0.0, Vector3(-0.15, 0, 0)], [0.3, Vector3(-1.2, 0, 0)], [0.6, Vector3(-1.0, 0, 0)], [0.9, Vector3(-0.15, 0, 0)]],
		"Head": [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(0.3, -0.3, 0)], [0.6, Vector3(0.15, 0, 0)], [0.9, Vector3(0, 0, 0)]],
	}))
	return out
