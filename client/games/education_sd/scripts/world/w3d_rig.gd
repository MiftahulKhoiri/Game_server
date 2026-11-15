extends Node3D
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
	if _hips == null:
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
