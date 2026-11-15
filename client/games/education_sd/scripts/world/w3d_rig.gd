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
var hat := ""  # dari toko kostum: petualang / mahkota / toga / pita
var acc := ""  # kacamata / syal / ransel
var _joints: Dictionary = {}  # pangkal lengan/tungkai -> sendi siku/lutut
var _cur: Dictionary = {}  # sudut sendi saat ini (transisi halus)

## Fase 5: model GLB berlisensi yang SUDAH ADA di APK (res://assets/models, KayKit CC0 — lihat
## assets/models/LISENSI_*.txt). Bila berkas tidak ada (APK lain/lebih lama), otomatis kembali ke model primitif.
var glb_id := ""
var glb_path := ""  # jalur GLB lengkap (pahlawan buatan sendiri, Fase 9); bila kosong: MODEL_DIR + glb_id
var glb_recolor: Dictionary = {}  # nama material -> warna (mis. "Baju" -> warna kostum)
var vy := 0.0  # kecepatan vertikal (diisi pemain) untuk memilih lompat/jatuh
var _air := 0.0
var _anims: PackedStringArray = []
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
## Versi semi-realistis (2.3.0): proporsi anak ±1,45 m (kepala ±1:6), leher, lengan & tungkai dua ruas
## (siku/lutut), tangan, sepatu, kerah, ikat pinggang, alis, hidung, telinga, rambut berponi.
func build() -> void:
	for c in get_children():
		c.queue_free()
	_glb = null
	_ap = null
	_hips = null
	_joints.clear()
	if (glb_id != "" or glb_path != "") and _build_glb():
		return
	var pants_c := pants
	_hips = Node3D.new()
	_hips.position = Vector3(0, HIP_Y, 0)
	add_child(_hips)
	_torso = Node3D.new()
	_hips.add_child(_torso)
	_torso.add_child(part(capsule(0.16, 0.5), shirt, Vector3(0, 0.25, 0), Vector3(1.0, 1.0, 0.72)))
	_torso.add_child(part(cyl(0.135, 0.15, 0.1), shirt.darkened(0.12), Vector3(0, 0.46, 0)))
	_torso.add_child(part(cyl(0.155, 0.16, 0.07), Color("4a3b30"), Vector3(0, 0.02, 0)))
	_torso.add_child(part(box(Vector3(0.06, 0.05, 0.02)), Color("d9b04a"), Vector3(0, 0.02, 0.125)))
	_torso.add_child(part(cyl(0.15, 0.16, 0.14), pants_c, Vector3(0, -0.06, 0), Vector3(1.0, 1.0, 0.78)))
	_torso.add_child(part(cyl(0.05, 0.055, 0.1), skin, Vector3(0, 0.53, 0)))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.68, 0)
	_torso.add_child(_head)
	_head.add_child(part(sphere(0.125), skin, Vector3.ZERO, Vector3(0.92, 1.12, 1.0)))
	_head.add_child(part(sphere(0.06), skin, Vector3(0, -0.07, 0.04), Vector3(1.2, 0.8, 1.0)))
	for side in [-1.0, 1.0]:
		_head.add_child(part(sphere(0.022), Color.WHITE, Vector3(0.045 * side, 0.015, 0.105), Vector3(1.2, 0.9, 0.6)))
		_head.add_child(part(sphere(0.013), Color("3a2a20"), Vector3(0.045 * side, 0.014, 0.117)))
		_head.add_child(part(box(Vector3(0.04, 0.008, 0.01)), hair.darkened(0.1), Vector3(0.045 * side, 0.05, 0.112)))
		_head.add_child(part(sphere(0.028), skin.darkened(0.06), Vector3(0.118 * side, 0.0, 0.0), Vector3(0.5, 1.0, 0.8)))
		_head.add_child(part(sphere(0.02), Color("f2a0a0"), Vector3(0.07 * side, -0.04, 0.095), Vector3(1.2, 0.7, 0.4)))
	_head.add_child(part(sphere(0.018), skin.darkened(0.05), Vector3(0, -0.01, 0.125), Vector3(0.9, 1.0, 1.0)))
	_head.add_child(part(box(Vector3(0.045, 0.01, 0.01)), Color("b0473a"), Vector3(0, -0.06, 0.112)))
	_head.add_child(part(sphere(0.132), hair, Vector3(0, 0.035, -0.012), Vector3(0.95, 0.95, 1.0)))
	_head.add_child(part(box(Vector3(0.2, 0.045, 0.06)), hair, Vector3(0, 0.085, 0.085)))
	if long_hair:
		_head.add_child(part(capsule(0.1, 0.36), hair, Vector3(0, -0.11, -0.08), Vector3(1.15, 1.0, 0.6)))
		_head.add_child(part(sphere(0.035), Color("ff7eb6"), Vector3(0.1, 0.09, 0.03)))
	_extras()
	_arm_l = _arm(-1.0)
	_arm_r = _arm(1.0)
	_torso.add_child(_arm_l)
	_torso.add_child(_arm_r)
	_leg_l = _leg(-1.0, pants_c)
	_leg_r = _leg(1.0, pants_c)
	_hips.add_child(_leg_l)
	_hips.add_child(_leg_r)
	# Fase 8: gabungkan bagian yang bergerak bersama -> sedikit draw call per karakter.
	Merge.merge(_head, [])
	Merge.merge(_torso, [_head, _arm_l, _arm_r])
	for limb in [_arm_l, _arm_r, _leg_l, _leg_r]:
		Merge.merge(limb, [_joints.get(limb, null)])
		if _joints.has(limb):
			Merge.merge(_joints[limb], [])


const HIP_Y := 0.74


## Lengan dua ruas: bahu -> siku -> tangan. Ruas bawah (siku) disimpan di _joints.
func _arm(side: float) -> Node3D:
	var sh := Node3D.new()
	sh.position = Vector3(0.2 * side, 0.43, 0)
	sh.add_child(part(capsule(0.052, 0.27), shirt, Vector3(0, -0.12, 0)))
	var el := Node3D.new()
	el.position = Vector3(0, -0.25, 0)
	el.add_child(part(capsule(0.044, 0.25), skin, Vector3(0, -0.11, 0)))
	el.add_child(part(sphere(0.05), skin, Vector3(0, -0.25, 0.01), Vector3(0.9, 1.1, 0.7)))
	sh.add_child(el)
	_joints[sh] = el
	return sh


## Tungkai dua ruas: pinggul -> lutut -> sepatu.
func _leg(side: float, c: Color) -> Node3D:
	var hp := Node3D.new()
	hp.position = Vector3(0.085 * side, -0.07, 0)
	hp.add_child(part(capsule(0.07, 0.36), c, Vector3(0, -0.17, 0)))
	var kn := Node3D.new()
	kn.position = Vector3(0, -0.34, 0)
	kn.add_child(part(capsule(0.058, 0.33), c.darkened(0.05), Vector3(0, -0.15, 0)))
	kn.add_child(part(box(Vector3(0.1, 0.07, 0.2)), Color("3a3040"), Vector3(0, -0.31, 0.035)))
	kn.add_child(part(box(Vector3(0.1, 0.02, 0.2)), Color("f4efe6"), Vector3(0, -0.345, 0.035)))
	hp.add_child(kn)
	_joints[hp] = kn
	return hp


## Topi/aksesori (toko kostum lama) dan ciri khas NPC cadangan.
func _extras() -> void:
	match hat:
		"petualang":
			_head.add_child(part(cyl(0.2, 0.2, 0.015, 16), Color("8a6b3a"), Vector3(0, 0.1, 0)))
			_head.add_child(part(cyl(0.11, 0.13, 0.1, 14), Color("a07c45"), Vector3(0, 0.15, 0)))
		"mahkota":
			_head.add_child(part(cyl(0.11, 0.12, 0.08, 8), Color("f0b429"), Vector3(0, 0.15, 0)))
		"toga":
			_head.add_child(part(cyl(0.12, 0.12, 0.06, 12), Color("2b2440"), Vector3(0, 0.13, 0)))
			_head.add_child(part(box(Vector3(0.3, 0.02, 0.3)), Color("2b2440"), Vector3(0, 0.17, 0)))
		"pita":
			_head.add_child(part(sphere(0.045), Color("ff7eb6"), Vector3(-0.06, 0.13, 0.03), Vector3(1.4, 0.8, 0.6)))
			_head.add_child(part(sphere(0.045), Color("ff7eb6"), Vector3(0.06, 0.13, 0.03), Vector3(1.4, 0.8, 0.6)))
	match acc:
		"kacamata":
			for side in [-1.0, 1.0]:
				var ring := TorusMesh.new()
				ring.inner_radius = 0.026
				ring.outer_radius = 0.034
				var rmi := part(ring, Color("2b2440"), Vector3(0.045 * side, 0.015, 0.118))
				rmi.rotation.x = PI / 2.0
				_head.add_child(rmi)
		"syal":
			var sc := TorusMesh.new()
			sc.inner_radius = 0.05
			sc.outer_radius = 0.1
			_torso.add_child(part(sc, Color("e05a4f"), Vector3(0, 0.5, 0)))
		"ransel":
			_torso.add_child(part(box(Vector3(0.24, 0.3, 0.12)), Color("8a5a2b"), Vector3(0, 0.25, -0.16)))
	match extra:
		"mahkota":
			_head.add_child(part(cyl(0.11, 0.12, 0.09, 8), Color("f0b429"), Vector3(0, 0.15, 0)))
		"kacamata":
			_head.add_child(part(box(Vector3(0.2, 0.02, 0.01)), Color("2b2440"), Vector3(0, 0.015, 0.122)))
		"topi_kapten":
			_head.add_child(part(cyl(0.13, 0.13, 0.06, 12), Color("1f2d50"), Vector3(0, 0.12, 0)))
			_head.add_child(part(box(Vector3(0.16, 0.012, 0.08)), Color("1f2d50"), Vector3(0, 0.1, 0.12)))
		"telinga":
			for side in [-1.0, 1.0]:
				var ear := part(capsule(0.03, 0.18), skin.darkened(0.15), Vector3(0.08 * side, 0.17, -0.02))
				ear.rotation.z = -0.4 * side
				_head.add_child(ear)
		"helm":
			_head.add_child(part(sphere(0.15), Color("cfe8ff"), Vector3(0, 0.01, 0)))


const MODEL_DIR := "res://assets/models/"


static func has_model(id: String) -> bool:
	return id != "" and ResourceLoader.exists(MODEL_DIR + id + ".glb")


## Pahlawan anak buatan sendiri (tools/gamepack/sd_heroes.gd): kerangka sama untuk laki-laki & perempuan.
const HERO_DIR := "res://games/education_sd/assets/characters/hero/"
## Animasi pahlawan: status rig -> nama animasi di GLB.
const HERO_ANIMS := {"idle": "idle", "jalan": "walk", "lari": "run", "interaksi": "interact", "sorak": "celebrate",
	"lambai": "wave", "kena": "hit", "pakai": "equip", "putar": "turn", "mendarat": "land"}
const LOOPED := ["idle", "walk", "run", "fall", "wave", "celebrate"]


static func hero_path(kind: String) -> String:
	return HERO_DIR + "%s/hero_%s.glb" % [kind, kind]


func _build_glb() -> bool:
	var path := glb_path if glb_path != "" else MODEL_DIR + glb_id + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
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
		if not glb_recolor.is_empty():
			var mesh0: Mesh = (mi as MeshInstance3D).mesh
			for s in mesh0.get_surface_count():
				var src0 := (mi as MeshInstance3D).get_active_material(s)
				if src0 != null and glb_recolor.has(src0.resource_name):
					var d0 := (src0 as BaseMaterial3D).duplicate() as BaseMaterial3D
					d0.albedo_color = glb_recolor[src0.resource_name]
					(mi as MeshInstance3D).set_surface_override_material(s, d0)
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
		_anims = _ap.get_animation_list()
		for an in LOOPED:
			if _ap.has_animation(an):
				_ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
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


## Kerangka GLB (untuk menempelkan topi/aksesori lewat BoneAttachment3D).
func skeleton() -> Skeleton3D:
	if _glb == null:
		return null
	var s := _glb.find_children("*", "Skeleton3D", true, false)
	return s[0] if s.size() > 0 else null


func full_hero() -> bool:
	return _anims.has("run") and _anims.has("jump") and _anims.has("land")


## Topi & aksesori toko kostum pada pahlawan GLB: ditempel ke tulang Head / Chest.
func attach_costume() -> void:
	var sk := skeleton()
	if sk == null or (hat == "" and acc == "" and extra == ""):
		return
	var k := 1.0 / maxf(0.001, _glb.scale.x)
	var head_at := BoneAttachment3D.new()
	head_at.bone_name = "Head"
	sk.add_child(head_at)
	var chest_at := BoneAttachment3D.new()
	chest_at.bone_name = "Chest"
	sk.add_child(chest_at)
	_head = Node3D.new()
	_head.name = "CostumeHead"
	_head.position = Vector3(0, 0.1, 0)
	_head.scale = Vector3.ONE * 0.92 * k
	head_at.add_child(_head)
	_torso = Node3D.new()
	_torso.name = "CostumeChest"
	_torso.position = Vector3(0, -0.29, 0)
	_torso.scale = Vector3.ONE * k
	chest_at.add_child(_torso)
	_extras()


## Animasi model GLB: idle/walk dari berkas (lari = walk dipercepat); lompat, interaksi, dan sorak
## ditambahkan secara prosedural (memantul/mengangguk) karena berkas tidak punya animasi itu.
func _animate_glb(delta: float, speed: float) -> void:
	if _ap != null and full_hero():
		var want := "idle"
		if state == "lompat":
			want = "jump" if vy > 0.5 else "fall"
		else:
			want = str(HERO_ANIMS.get(state, "idle"))
		if not _ap.has_animation(want):
			want = "idle"
		if _ap.current_animation != want:
			_ap.play(want, 0.18)
		_ap.speed_scale = clampf(speed / (2.4 if want == "walk" else 5.0), 0.7, 1.6) if want in ["walk", "run"] else 1.0
		return
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


## Animasi sekali-jalan: "interaksi" (melambai/menyentuh) atau "sorak" (menerima hadiah).
func play_once(anim: String, dur := 1.0) -> void:
	state = anim
	_act_t = dur


## speed: kecepatan horizontal (m/dtk); on_floor: menapak tanah.
var _dt := 0.016


func animate(delta: float, speed: float, on_floor: bool) -> void:
	if _hips == null and _glb == null:
		return
	_dt = delta
	_t += delta
	if not on_floor:
		_air += delta
	else:
		if _air > 0.3 and _act_t <= 0.0:
			play_once("mendarat", 0.3)
		_air = 0.0
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


## Pose prosedural dengan transisi halus: setiap sendi mengejar sudut target (peluruhan eksponensial),
## jadi perpindahan idle -> jalan -> lari -> lompat tidak patah.
func _pose(speed: float) -> void:
	var tg := {"hip": 0.0, "lean": 0.0, "ll": 0.0, "lr": 0.0, "kl": 0.0, "kr": 0.0, "al": 0.0, "ar": 0.0,
		"el": -0.15, "er": -0.15, "azl": -0.08, "azr": 0.08, "head": 0.0}
	match state:
		"idle":
			tg.hip = sin(_t * 2.0) * 0.008
			tg.head = sin(_t * 0.7) * 0.18
			tg.al = sin(_t * 2.0) * 0.03
			tg.ar = -tg.al
		"jalan", "lari":
			var run := state == "lari"
			var ph := _t * speed * (1.7 if run else 2.3)
			var amp := 0.75 if run else 0.5
			tg.ll = sin(ph) * amp
			tg.lr = -sin(ph) * amp
			tg.kl = maxf(0.0, -sin(ph - 0.6)) * (1.3 if run else 0.8)
			tg.kr = maxf(0.0, sin(ph - 0.6)) * (1.3 if run else 0.8)
			tg.al = -sin(ph) * amp * 0.8
			tg.ar = sin(ph) * amp * 0.8
			tg.el = -0.35 - (0.6 if run else 0.15)
			tg.er = tg.el
			tg.hip = absf(sin(ph)) * (0.06 if run else 0.03)
			tg.lean = 0.2 if run else 0.05
		"lompat":
			tg.ll = -0.7
			tg.lr = -0.2
			tg.kl = 1.2
			tg.kr = 0.6
			tg.al = -2.3
			tg.ar = -2.3
			tg.el = -0.3
			tg.er = -0.3
		"interaksi", "lambai":
			tg.ar = -1.7
			tg.er = -0.6 + sin(_t * 12.0) * 0.45
			tg.azr = 0.3
			tg.head = 0.1
		"sorak":
			tg.al = -2.8 + sin(_t * 14.0) * 0.2
			tg.ar = -2.8 - sin(_t * 14.0) * 0.2
			tg.el = -0.2
			tg.er = -0.2
			tg.hip = absf(sin(_t * 9.0)) * 0.18
			tg.kl = absf(sin(_t * 9.0)) * 0.6
			tg.kr = tg.kl
	var k := 1.0 - exp(-_dt * 14.0)
	for key in tg:
		_cur[key] = lerpf(float(_cur.get(key, tg[key])), float(tg[key]), k)
	_hips.position.y = HIP_Y + float(_cur.hip)
	_torso.rotation.x = float(_cur.lean)
	_leg_l.rotation.x = float(_cur.ll)
	_leg_r.rotation.x = float(_cur.lr)
	(_joints[_leg_l] as Node3D).rotation.x = float(_cur.kl)
	(_joints[_leg_r] as Node3D).rotation.x = float(_cur.kr)
	_arm_l.rotation.x = float(_cur.al)
	_arm_r.rotation.x = float(_cur.ar)
	_arm_l.rotation.z = float(_cur.azl)
	_arm_r.rotation.z = float(_cur.azr)
	(_joints[_arm_l] as Node3D).rotation.x = float(_cur.el)
	(_joints[_arm_r] as Node3D).rotation.x = float(_cur.er)
	_head.rotation.y = float(_cur.head)
