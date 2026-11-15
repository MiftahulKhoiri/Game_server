extends Node3D
const Merge := preload("res://games/education_sd/scripts/world/w3d_merge.gd")
## Karakter 3D bergaya kartun yang dipakai bersama oleh pemain dan NPC (satu sistem karakter).
## Model dibuat dari mesh primitif low-poly (placeholder yang benar-benar bisa dimainkan; belum ada aset GLB
## berlisensi). Animasi prosedural berbasis status: idle, jalan, lari, lompat, interaksi, sorak (hadiah).
## Menambah animasi baru = menambah cabang di _pose().

var shirt := Color("e05a4f")
var pants := Color("3b5b9a")
var skin := Color("f5c9a0")
var hair := Color("3a2a20")
var long_hair := false
var extra := ""  # "" / "mahkota" / "kacamata" / "topi_kapten" / "telinga" / "helm"

## Fase 5: model GLB berlisensi yang SUDAH ADA di APK (res://assets/models, KayKit CC0 — lihat
## assets/models/LISENSI_*.txt). Bila berkas tidak ada (APK lain/lebih lama), otomatis kembali ke model primitif.
var glb_id := ""
var glb_height := 1.9
var glb_tint := Color.WHITE
var glb_hide: Array = ["Sword", "Crossbow", "Axe", "Shield", "Badge", "Bow", "Dagger", "Staff"]
var _glb: Node3D
var _ap: AnimationPlayer
var _base_y := 0.0

var state := "idle"  # idle / jalan / lari / lompat / interaksi / sorak
var _t := 0.0
var _act_t := 0.0  # sisa waktu animasi sekali-jalan (interaksi/sorak)
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D

static var _mats: Dictionary = {}


static func mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "%s/%.2f" % [c.to_html(), rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


static func part(mesh: Mesh, c: Color, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	mi.scale = scl
	return mi


static func capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 4
	return m


static func sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 7
	return m


static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func cyl(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


## Bangun ulang model dari properti warna/gaya saat ini.
func build() -> void:
	for c in get_children():
		c.queue_free()
	_glb = null
	_ap = null
	_hips = null
	if glb_id != "" and _build_glb():
		return
	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.78, 0)
	add_child(_hips)
	_torso = Node3D.new()
	_hips.add_child(_torso)
	_torso.add_child(part(capsule(0.27, 0.78), shirt, Vector3(0, 0.3, 0)))
	_torso.add_child(part(cyl(0.2, 0.29, 0.22), pants, Vector3(0, -0.02, 0)))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.88, 0)
	_torso.add_child(_head)
	_head.add_child(part(sphere(0.3), skin))
	for side in [-1.0, 1.0]:
		_head.add_child(part(sphere(0.055), Color("2b2440"), Vector3(0.11 * side, 0.03, 0.26)))
		_head.add_child(part(sphere(0.022), Color.WHITE, Vector3(0.11 * side + 0.02, 0.05, 0.305)))
		_head.add_child(part(sphere(0.05), Color("f29c9c"), Vector3(0.18 * side, -0.08, 0.22), Vector3(1, 0.6, 0.4)))
	_head.add_child(part(box(Vector3(0.12, 0.03, 0.03)), Color("b0473a"), Vector3(0, -0.12, 0.27)))
	# rambut: topi rambut + (opsional) rambut panjang di belakang
	_head.add_child(part(sphere(0.315), hair, Vector3(0, 0.07, -0.03), Vector3(1.0, 0.85, 1.0)))
	if long_hair:
		_head.add_child(part(capsule(0.2, 0.62), hair, Vector3(0, -0.2, -0.17), Vector3(1.35, 1, 0.7)))
		_head.add_child(part(sphere(0.07), Color("ff7eb6"), Vector3(0.22, 0.2, 0.05)))
	match extra:
		"mahkota":
			_head.add_child(part(cyl(0.2, 0.23, 0.16, 8), Color("f0b429"), Vector3(0, 0.33, 0)))
			for i in 5:
				var a := TAU * i / 5.0
				_head.add_child(part(sphere(0.045), Color("e0453a"), Vector3(cos(a) * 0.21, 0.42, sin(a) * 0.21)))
		"kacamata":
			for side in [-1.0, 1.0]:
				var ring := TorusMesh.new()
				ring.inner_radius = 0.06
				ring.outer_radius = 0.085
				var rmi := part(ring, Color("2b2440"), Vector3(0.11 * side, 0.03, 0.29))
				rmi.rotation.x = PI / 2.0
				_head.add_child(rmi)
			_head.add_child(part(capsule(0.12, 0.5), Color.WHITE, Vector3(0, -1.15, 0.05), Vector3(2.4, 1.4, 1.4)))
		"topi_kapten":
			_head.add_child(part(cyl(0.3, 0.3, 0.12), Color("1f2d50"), Vector3(0, 0.26, 0)))
			_head.add_child(part(box(Vector3(0.36, 0.03, 0.18)), Color("1f2d50"), Vector3(0, 0.21, 0.27)))
			_head.add_child(part(sphere(0.05), Color("f0b429"), Vector3(0, 0.3, 0.29)))
		"telinga":
			for side in [-1.0, 1.0]:
				var ear := part(capsule(0.07, 0.4), skin.darkened(0.15), Vector3(0.17 * side, 0.38, -0.05))
				ear.rotation.z = -0.4 * side
				_head.add_child(ear)
		"helm":
			_head.add_child(part(sphere(0.34), Color("cfe8ff"), Vector3(0, 0.02, 0), Vector3(1, 1, 1)))
	_arm_l = _limb(Vector3(-0.36, 0.56, 0), 0.085, 0.58, shirt, skin)
	_arm_r = _limb(Vector3(0.36, 0.56, 0), 0.085, 0.58, shirt, skin)
	_torso.add_child(_arm_l)
	_torso.add_child(_arm_r)
	_leg_l = _limb(Vector3(-0.13, -0.05, 0), 0.1, 0.72, pants, Color("4a3b30"))
	_leg_r = _limb(Vector3(0.13, -0.05, 0), 0.1, 0.72, pants, Color("4a3b30"))
	_hips.add_child(_leg_l)
	_hips.add_child(_leg_r)
	# Fase 8: gabungkan bagian yang bergerak bersama (kepala, badan, tiap tungkai) -> ±8 draw call per karakter.
	Merge.merge(_head, [])
	Merge.merge(_torso, [_head, _arm_l, _arm_r])
	for limb in [_arm_l, _arm_r, _leg_l, _leg_r]:
		Merge.merge(limb, [])


const MODEL_DIR := "res://assets/models/"


static func has_model(id: String) -> bool:
	return id != "" and ResourceLoader.exists(MODEL_DIR + id + ".glb")


func _build_glb() -> bool:
	if not has_model(glb_id):
		return false
	var ps := load(MODEL_DIR + glb_id + ".glb") as PackedScene
	if ps == null:
		return false
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return false
	var aabb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var hide := false
		for w in glb_hide:
			if str(mi.name).contains(w):
				hide = true
		if hide:
			(mi as MeshInstance3D).visible = false
			continue
		var xf := _xf_to(inst, mi)
		var box: AABB = xf * (mi as MeshInstance3D).get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		if glb_tint != Color.WHITE:
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var src := (mi as MeshInstance3D).get_active_material(s)
				if src is BaseMaterial3D:
					var dup := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
					dup.albedo_color = dup.albedo_color * glb_tint
					(mi as MeshInstance3D).set_surface_override_material(s, dup)
	if first or aabb.size.y <= 0.01:
		inst.free()
		return false
	var k := glb_height / aabb.size.y
	_glb = Node3D.new()
	_glb.name = "Model"
	_glb.scale = Vector3.ONE * k
	_base_y = -aabb.position.y * k
	_glb.position = Vector3(-aabb.get_center().x * k, _base_y, -aabb.get_center().z * k)
	_glb.add_child(inst)
	add_child(_glb)
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		_ap = aps[0]
		if _ap.has_animation("idle"):
			_ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			_ap.play("idle")
		if _ap.has_animation("walk"):
			_ap.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
	return true


static func _xf_to(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D()
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func is_glb() -> bool:
	return _glb != null


## Animasi model GLB: idle/walk dari berkas (lari = walk dipercepat); lompat, interaksi, dan sorak
## ditambahkan secara prosedural (memantul/mengangguk) karena berkas tidak punya animasi itu.
func _animate_glb(delta: float, speed: float) -> void:
	if _ap != null:
		var want := "walk" if state in ["jalan", "lari"] else "idle"
		if _ap.has_animation(want) and _ap.current_animation != want:
			_ap.play(want, 0.2)
		_ap.speed_scale = clampf(speed / 2.6, 0.8, 2.2) if want == "walk" else 1.0
	var bob := 0.0
	var tilt := 0.0
	match state:
		"sorak":
			bob = absf(sin(_t * 9.0)) * 0.3
		"interaksi":
			tilt = sin(_t * 10.0) * 0.12
		"lompat":
			tilt = -0.1
	_glb.position.y = _base_y + bob
	_glb.rotation.x = tilt


func _limb(at: Vector3, r: float, length: float, c: Color, tip: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	pivot.add_child(part(capsule(r, length), c, Vector3(0, -length * 0.45, 0)))
	pivot.add_child(part(sphere(r * 1.15), tip, Vector3(0, -length * 0.88, 0.02)))
	return pivot


## Animasi sekali-jalan: "interaksi" (melambai/menyentuh) atau "sorak" (menerima hadiah).
func play_once(anim: String, dur := 1.0) -> void:
	state = anim
	_act_t = dur


## speed: kecepatan horizontal (m/dtk); on_floor: menapak tanah.
func animate(delta: float, speed: float, on_floor: bool) -> void:
	if _hips == null and _glb == null:
		return
	_t += delta
	if _act_t > 0.0:
		_act_t -= delta
	elif not on_floor:
		state = "lompat"
	elif speed > 5.5:
		state = "lari"
	elif speed > 0.4:
		state = "jalan"
	else:
		state = "idle"
	if _glb != null:
		_animate_glb(delta, speed)
		return
	_pose(speed)


func _pose(speed: float) -> void:
	var sw := 0.0
	var bob := 0.0
	var arm_up_l := 0.0
	var arm_up_r := 0.0
	var lean := 0.0
	match state:
		"idle":
			bob = sin(_t * 2.2) * 0.015
			sw = sin(_t * 1.1) * 0.05
		"jalan":
			sw = sin(_t * speed * 2.4) * 0.6
			bob = absf(sin(_t * speed * 2.4)) * 0.05
		"lari":
			sw = sin(_t * speed * 1.9) * 0.95
			bob = absf(sin(_t * speed * 1.9)) * 0.09
			lean = 0.18
		"lompat":
			sw = 0.0
			arm_up_l = 2.4
			arm_up_r = 2.4
		"interaksi":
			arm_up_r = 1.6 + sin(_t * 12.0) * 0.4
		"sorak":
			arm_up_l = 2.8 + sin(_t * 14.0) * 0.3
			arm_up_r = 2.8 - sin(_t * 14.0) * 0.3
			bob = absf(sin(_t * 9.0)) * 0.22
	_hips.position.y = 0.78 + bob
	_torso.rotation.x = lean
	_leg_l.rotation.x = sw
	_leg_r.rotation.x = -sw
	if state == "lompat":
		_leg_l.rotation.x = -0.5
		_leg_r.rotation.x = 0.3
	_arm_l.rotation.x = -sw * 0.8 if arm_up_l == 0.0 else -arm_up_l
	_arm_r.rotation.x = sw * 0.8 if arm_up_r == 0.0 else -arm_up_r
	_arm_l.rotation.z = -0.12 - (0.25 if arm_up_l > 0.0 else 0.0)
	_arm_r.rotation.z = 0.12 + (0.25 if arm_up_r > 0.0 else 0.0)
	_head.rotation.y = sin(_t * 0.7) * 0.15 if state == "idle" else 0.0
