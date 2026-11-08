extends RefCounted
## Model 3D karakter, NPC, dan musuh.
##
## Bila ada assets/models/<id>.glb, itu yang dipakai (id = id NPC/musuh/ksatria). Bila tidak,
## model dirakit dari bentuk dasar (placeholder) sehingga game tetap jalan sampai model
## asli datang. Arah depan semua model = +Z, tinggi kira-kira 1 petak.

const Rig = preload("res://scripts/model_rig.gd")
const WB = preload("res://scripts/world_build.gd")

const MODEL_DIR := "res://assets/models/"

## Tinggi akhir (satuan petak) untuk model GLB buatan AI/unduhan selain ksatria. Ukuran asli
## GLB tidak dipercaya: model diukur lalu diskalakan ke tinggi ini, kaki di tanah, di tengah.
const HEIGHTS := {"golem_lava": 1.4, "golem_kerikil": 1.15, "ogre_batu": 1.3, "raja_goblin": 1.65, "goblin": 1.05, "goblin_penjaga": 1.15, "nenek_penjual": 0.85, "petani": 0.95, "warga_ibu": 0.88, "warga_ibu2": 0.86, "warga_bapak": 0.98, "warga_bapak2": 0.96, "anak_desa": 0.62, "babi_hutan": 0.75, "tikus_sawah": 0.5,
	"serigala_hutan": 0.8, "kelelawar_gua": 0.95, "ular_sawah": 0.6, "belalang_raksasa": 0.55}
const DEFAULT_HEIGHT := 1.0

## Pahlawan yang bisa dipilih pemain (semua dari KayKit, berangka + animasi sendiri). Urutan = urutan di layar profil.
const HEROES := ["ksatria", "pendekar_kapak", "pemanah", "pendekar_tombak"]


static func is_hero(id: String) -> bool:
	return HEROES.has(id)


## Skala akhir model terhadap petak (disetel supaya tinggi mendekati 1 petak).
const SCALES := {
	"ksatria": 0.42, "pendekar_kapak": 0.44, "pemanah": 0.42, "pendekar_tombak": 0.42, "nenek_penjual": 0.66, "petani": 0.74,
	"goblin": 0.58, "goblin_penjaga": 0.68, "raja_goblin": 0.95, "ogre_batu": 1.1,
	"golem_kerikil": 1.0, "golem_lava": 1.1,
	"tikus_sawah": 0.8, "babi_hutan": 0.95, "serigala_hutan": 0.95,
	"ular_sawah": 1.0, "belalang_raksasa": 0.95, "kelelawar_gua": 1.0,
}


## Musuh yang memakai model musuh lain dengan ukuran (kali lipat) dan warna (pengali) berbeda,
## supaya satu model bisa jadi goblin kecil, orc besar, atau serigala alfa tanpa berkas baru.
const VARIANTS := {
	"goblin_pemburu": {"base": "goblin", "size": 1.2, "tint": Color("9fd8d0")},
	"orc_gua": {"base": "goblin", "size": 1.55, "tint": Color("b8a070")},
	"orc_penjaga": {"base": "goblin", "size": 1.8, "tint": Color("d9906a")},
	"orc_buas": {"base": "goblin", "size": 2.05, "tint": Color("cc6a62")},
	"ular_hutan": {"base": "ular_sawah", "size": 1.2, "tint": Color("86b890")},
	"serigala_alfa": {"base": "serigala_hutan", "size": 1.25, "tint": Color("6a6f7c")},
	# Prajurit biasa (pasukan dari tenda hijau): pendekar tombak yang lebih kecil dan kehijauan.
	"prajurit": {"base": "pendekar_tombak", "size": 0.88, "tint": Color("b6d8a4")},
}


## Mengalikan warna semua bahan model (hanya bahan hasil _fix_materials / bentuk dasar).
static func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var mo := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			mo.albedo_color = mo.albedo_color * c
			mi.material_override = mo
		elif mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m is StandardMaterial3D:
					var sm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.albedo_color = sm.albedo_color * c
					mi.set_surface_override_material(i, sm)
	for ch in n.get_children():
		_tint(ch, c)


## Membuat model untuk id. Selalu mengembalikan node (placeholder bila tidak dikenal).
static func create(id: String) -> Node3D:
	if VARIANTS.has(id):
		var v: Dictionary = VARIANTS[id]
		var base := create(str(v.base))
		base.scale = base.scale * float(v.size)
		_tint(base, v.tint)
		base.name = id
		return base
	var path := MODEL_DIR + id + ".glb"
	var node: Node3D = null
	var from_glb := false
	if ResourceLoader.exists(path):
		node = _from_glb(id, path)
		from_glb = node != null
	if node == null:
		node = build_placeholder(id)
	if from_glb and not is_hero(id):
		node.scale = Vector3.ONE  # sudah dinormalkan di _from_glb
	else:
		node.scale = Vector3.ONE * float(SCALES.get(id, 0.7))
	node.name = id
	return node


static func has_glb(id: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + id + ".glb")


# --- GLB pengganti ---

static func _from_glb(id: String, path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	if not is_hero(id):
		_fix_materials(inst)
		_normalize(inst, float(HEIGHTS.get(id, DEFAULT_HEIGHT)))
	var rig := Rig.new()
	var holder := Node3D.new()  # badan utuh: digerakkan rig untuk model tanpa rangka
	holder.name = "body"
	if is_hero(id):
		rig.add_child(inst)
	else:
		holder.add_child(inst)
		rig.add_child(holder)
	var ap := _find_animation_player(inst)
	if ap != null and not ap.get_animation_list().is_empty():
		rig.setup("biped", {} if is_hero(id) else {"body": holder})
		rig.use_animation_player(ap)
	elif id == "ksatria":
		rig.setup("biped", _paladin_pivots(inst))
	else:
		rig.setup("static", {"body": holder})  # tanpa sendi: badan utuh bergoyang
	return rig


## Warna per titik (hasil gambar-ke-3D) dipakai sebagai warna dasar; dua sisi terlihat.
static func _fix_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var sm: StandardMaterial3D = (m.duplicate() as StandardMaterial3D) if m is StandardMaterial3D else StandardMaterial3D.new()
			if sm.albedo_texture == null:
				sm.vertex_color_use_as_albedo = true
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			# beberapa glb (babi hutan) membawa alpha 0 + mode MASK -> model tak terlihat sama sekali
			sm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			sm.albedo_color = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, 1.0)
			sm.roughness = 0.9
			sm.metallic = 0.0
			mi.set_surface_override_material(i, sm)
	for c in n.get_children():
		_fix_materials(c)


static func _aabb_of(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var has := false
	if n is MeshInstance3D:
		box = xf * (n as MeshInstance3D).get_aabb()
		has = true
	for c in n.get_children():
		if c is Node3D:
			var sub := _aabb_of(c, xf * (c as Node3D).transform)
			if sub.size != Vector3.ZERO:
				box = sub if not has else box.merge(sub)
				has = true
	return box


## Skala ke tinggi h, kaki di y=0, pusat di x=z=0.
static func _normalize(inst: Node3D, h: float) -> void:
	var box := _aabb_of(inst, Transform3D.IDENTITY)
	if box.size.y <= 0.0001:
		return
	var k := h / box.size.y
	inst.scale = Vector3.ONE * k
	var c := box.get_center()
	inst.position = Vector3(-c.x * k, -box.position.y * k, -c.z * k)


static func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_animation_player(c)
		if f != null:
			return f
	return null


## Paladin dari Blender/trimesh: potongan mesh terpisah tanpa Skeleton, jadi kelompok
## potongan dipasang ke pivot supaya bisa diayun (animasi prosedural).
static func _paladin_pivots(hero: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var defs := {
		"leg_l": [Vector3(-0.17, 0.96, 0.0), ["L_boot", "L_toe", "L_greave", "L_knee", "L_thigh", "L_thigh_armor"]],
		"leg_r": [Vector3(0.17, 0.96, 0.0), ["R_boot", "R_toe", "R_greave", "R_knee", "R_thigh", "R_thigh_armor"]],
		"arm_l": [Vector3(-0.40, 1.45, 0.0), [
			"L_pauldron", "L_pauldron_shell", "L_upperarm", "L_vambrace", "L_bracer_trim", "L_glove",
			"sword_grip", "sword_grip_wrap_1.08", "sword_grip_wrap_1.135", "sword_grip_wrap_1.19",
			"sword_grip_wrap_1.245", "sword_grip_wrap_1.3", "sword_guard", "rune_sword_blade",
			"sword_blade_edge", "rune_0", "rune_1", "rune_2", "rune_3"]],
		"arm_r": [Vector3(0.40, 1.45, 0.0), [
			"R_pauldron", "R_pauldron_shell", "R_upperarm", "R_vambrace", "R_bracer_trim", "R_glove",
			"lion_shield", "shield_gold_face", "shield_silver_inset", "lion_mane", "lion_face", "lion_muzzle",
			"lion_eye_0.62", "lion_eye_0.68", "lion_mane_tuft_0", "lion_mane_tuft_1", "lion_mane_tuft_2",
			"lion_mane_tuft_3", "lion_mane_tuft_4", "lion_mane_tuft_5", "lion_mane_tuft_6", "lion_mane_tuft_7"]],
		"tail": [Vector3(0.0, 1.50, -0.15), ["red_cape"]],
		"head": [Vector3(0.0, 1.68, 0.0), [
			"neck", "head", "ear_-0.17", "ear_0.17", "hair_cap", "hair_lock_0", "hair_lock_1", "hair_lock_2",
			"hair_lock_3", "hair_lock_4", "eye_white_-0.065", "eye_white_0.065", "eye_iris_-0.065",
			"eye_iris_0.065", "brow_L", "brow_R", "nose", "mouth"]],
	}
	var frame := hero.find_child("world", true, false) as Node3D  # induk semua potongan
	if frame == null:
		frame = hero
	for pname: String in defs:
		var pivot := Node3D.new()
		pivot.name = pname
		frame.add_child(pivot)
		pivot.position = defs[pname][0]
		pv[pname] = pivot
		for mesh_name: String in defs[pname][1]:
			var m := hero.find_child(mesh_name, true, false) as Node3D
			if m != null and m != pivot:
				# Model belum ada di pohon adegan, jadi pakai rumus: posisi lokal dikurangi posisi pivot.
				m.owner = null  # hindari peringatan pemilik adegan
				m.reparent(pivot, false)
				m.position -= pivot.position
	return pv


# --- bentuk dasar ---

static func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot := Vector3.ZERO, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if glow:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.6
		mi.material_override = m
	else:
		mi.material_override = WB.mat(color)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO, glow := false) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mi(parent, m, pos, color, rot, glow)


static func ball(parent: Node3D, r: float, pos: Vector3, color: Color, scl := Vector3.ONE, glow := false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 6
	var mi := _mi(parent, m, pos, color, Vector3.ZERO, glow)
	mi.scale = scl
	return mi


static func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	return _mi(parent, m, pos, color, rot)


## Kerucut dengan ujung di +Y (diputar lewat rot).
static func cone(parent: Node3D, r: float, h: float, pos: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	return cyl(parent, 0.0, r, h, pos, color, rot)


static func pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


static func _eyes(head: Node3D, hr: float, color := Color("1a1a1a"), glow := false, z := 0.85, spread := 0.38) -> void:
	for s in [-1.0, 1.0]:
		ball(head, hr * 0.13, Vector3(s * hr * spread, hr * 1.05, hr * z), color, Vector3.ONE, glow)


# --- perakit ---

static func build_placeholder(id: String) -> Node3D:
	var rig := Rig.new()
	var pv: Dictionary = {}
	var kind := "biped"
	match id:
		"ksatria":
			pv = _humanoid(rig, {"skin": Color("e8b890"), "shirt": Color("b8c0cc"), "pants": Color("7d8794"), "shoes": Color("5a4630"), "hair": Color("3a2414"), "metal": true})
			box(pv.body, Vector3(0.4, 0.62, 0.05), Vector3(0, 0.78, -0.15), Color("8b1a1a"))  # jubah
			var sword := box(pv.arm_l, Vector3(0.05, 0.62, 0.02), Vector3(0, -0.62, 0.08), Color("c8d4e0"))
			sword.rotation.x = 0.0
			cyl(pv.arm_r, 0.17, 0.17, 0.04, Vector3(0, -0.34, 0.1), Color("a8b4c0"), Vector3(PI / 2.0, 0, 0))  # perisai
		"nenek_penjual":
			pv = _humanoid(rig, {"skin": Color("e8c9a5"), "shirt": Color("6a4a8a"), "pants": Color("6a4a8a"), "shoes": Color("4a3a2a"), "hair": Color("d8d8d8"), "head_r": 0.18, "bulk": 0.9})
			cyl(pv.body, 0.19, 0.34, 0.5, Vector3(0, 0.3, 0), Color("6a4a8a"))  # rok panjang
			box(pv.body, Vector3(0.26, 0.4, 0.04), Vector3(0, 0.68, 0.12), Color("f0e6cc"))  # celemek
			ball(pv.head, 0.09, Vector3(0, 0.4, -0.12), Color("d8d8d8"))  # sanggul
		"petani":
			pv = _humanoid(rig, {"skin": Color("d9a878"), "shirt": Color("c8b070"), "pants": Color("3a5a8a"), "shoes": Color("4a3a2a"), "hair": Color("5a3a1a")})
			cyl(pv.head, 0.3, 0.3, 0.03, Vector3(0, 0.3, 0), Color("e0c060"))  # topi jerami
			cyl(pv.head, 0.16, 0.18, 0.14, Vector3(0, 0.36, 0), Color("e0c060"))
		"goblin", "goblin_penjaga", "raja_goblin":
			pv = _goblin(rig, id)
		"ogre_batu":
			pv = _humanoid(rig, {"skin": Color("8a8068"), "shirt": Color("5a4a3a"), "pants": Color("4a3a2a"), "shoes": Color("3a2a1a"), "head_r": 0.2, "bulk": 1.5, "torso_w": 0.5, "torso_d": 0.32, "torso_h": 0.5, "arm_len": 0.48})
			ball(pv.body, 0.28, Vector3(0, 0.68, 0.1), Color("8a8068"), Vector3(1.2, 1.0, 0.9))  # perut
			for s in [-1.0, 1.0]:
				cone(pv.head, 0.035, 0.12, Vector3(s * 0.08, 0.04, 0.2), Color("e8e0c0"), Vector3(0.0, 0.0, 0.0))  # taring
			cyl(pv.arm_r, 0.1, 0.17, 0.75, Vector3(0, -0.5, 0.25), Color("6a4a2a"), Vector3(-PI / 3.0, 0, 0))  # gada
			kind = "golem"
		"golem_kerikil":
			pv = _golem(rig, Color("6f6f68"), Color("55554e"), Color("4a7a3a"), false)
			kind = "golem"
		"golem_lava":
			pv = _golem(rig, Color("4a4540"), Color("38342f"), Color("ff7a1a"), true)
			kind = "golem"
		"tikus_sawah":
			pv = _quad(rig, {"body": Color("8a6a4a"), "belly": Color("d8c8a8"), "len": 0.22, "wid": 0.13, "hgt": 0.13, "leg_len": 0.08, "snout": "cone", "ears": "round", "tail": "thin", "head_r": 0.1})
			kind = "quad"
		"babi_hutan":
			pv = _quad(rig, {"body": Color("5a3a28"), "belly": Color("7a5a44"), "len": 0.38, "wid": 0.24, "hgt": 0.24, "leg_len": 0.17, "snout": "boar", "ears": "pointy", "tail": "curl", "head_r": 0.17})
			kind = "quad"
		"serigala_hutan":
			pv = _quad(rig, {"body": Color("7d8088"), "belly": Color("b8bcc4"), "len": 0.4, "wid": 0.19, "hgt": 0.22, "leg_len": 0.26, "snout": "long", "ears": "pointy", "tail": "bushy", "head_r": 0.15})
			kind = "quad"
		"ular_sawah":
			pv = _snake(rig)
			kind = "snake"
		"belalang_raksasa":
			pv = _hopper(rig)
			kind = "hopper"
		"kelelawar_gua":
			pv = _bat(rig)
			kind = "bat"
		_:
			pv = _humanoid(rig, {"skin": Color("c8a878"), "shirt": Color("8a5a3c"), "pants": Color("4a3a2a"), "shoes": Color("3a2a1a")})
	rig.setup(kind, pv)
	return rig


static func _humanoid(root: Node3D, o: Dictionary) -> Dictionary:
	var skin: Color = o.get("skin", Color("e8b890"))
	var shirt: Color = o.get("shirt", Color("808080"))
	var pants: Color = o.get("pants", Color("404040"))
	var shoes: Color = o.get("shoes", Color("3a2a1a"))
	var bulk := float(o.get("bulk", 1.0))
	var leg_len := float(o.get("leg_len", 0.42))
	var th := float(o.get("torso_h", 0.46))
	var tw := float(o.get("torso_w", 0.36))
	var td := float(o.get("torso_d", 0.22))
	var hr := float(o.get("head_r", 0.17))
	var al := float(o.get("arm_len", 0.40))
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var hip_y := leg_len + 0.03
	for side in [-1.0, 1.0]:
		var nm := "leg_l" if side < 0.0 else "leg_r"
		var leg := pivot(body, nm, Vector3(side * tw * 0.28, hip_y, 0))
		pv[nm] = leg
		box(leg, Vector3(0.14 * bulk, leg_len, 0.15 * bulk), Vector3(0, -leg_len / 2.0, 0), pants)
		box(leg, Vector3(0.16 * bulk, 0.07, 0.25 * bulk), Vector3(0, -leg_len + 0.035, 0.04), shoes)
	box(body, Vector3(tw, th, td), Vector3(0, hip_y + th / 2.0, 0), shirt)
	var shoulder_y := hip_y + th - 0.05
	for side2 in [-1.0, 1.0]:
		var an := "arm_l" if side2 < 0.0 else "arm_r"
		var arm := pivot(body, an, Vector3(side2 * (tw / 2.0 + 0.07 * bulk), shoulder_y, 0))
		pv[an] = arm
		box(arm, Vector3(0.1 * bulk, al, 0.1 * bulk), Vector3(0, -al / 2.0, 0), shirt if not o.get("metal", false) else Color("a0a8b4"))
		ball(arm, 0.06 * bulk, Vector3(0, -al - 0.02, 0), skin)
	var head := pivot(body, "head", Vector3(0, hip_y + th, 0))
	pv["head"] = head
	ball(head, hr, Vector3(0, hr * 0.95, 0), skin)
	_eyes(head, hr)
	if o.has("hair"):
		ball(head, hr * 1.06, Vector3(0, hr * 1.18, -hr * 0.12), o.hair, Vector3(1.0, 0.8, 1.0))
	if o.get("metal", false):
		ball(body, 0.13 * bulk, Vector3(-0.22, shoulder_y + 0.02, 0), Color("c8a040"), Vector3(1.0, 0.7, 1.0))  # bahu zirah
		ball(body, 0.13 * bulk, Vector3(0.22, shoulder_y + 0.02, 0), Color("c8a040"), Vector3(1.0, 0.7, 1.0))
	return pv


static func _goblin(root: Node3D, id: String) -> Dictionary:
	var skin := Color("6aa84a")
	var big := id == "raja_goblin"
	var guard := id == "goblin_penjaga"
	if guard:
		skin = Color("56883e")
	if big:
		skin = Color("4a7a3a")
	var pv := _humanoid(root, {"skin": skin, "shirt": Color("7a5a3a") if not big else Color("6a2a6a"), "pants": Color("5a4028"), "shoes": Color("3a2a1a"), "head_r": 0.2, "bulk": 1.1 if big else 1.0, "torso_w": 0.34, "arm_len": 0.38})
	var head: Node3D = pv.head
	for s in [-1.0, 1.0]:  # telinga lancip
		cone(head, 0.06, 0.3, Vector3(s * 0.26, 0.2, 0.0), skin, Vector3(0, 0, -s * PI / 2.0 * 1.15))
	cone(head, 0.04, 0.12, Vector3(0, 0.17, 0.2), Color("8ab860"), Vector3(PI / 2.0, 0, 0))  # hidung
	if guard:
		var helm := ball(head, 0.22, Vector3(0, 0.26, 0), Color("8a8e96"), Vector3(1.0, 0.7, 1.0))
		helm.position.y = 0.3
		cyl(pv.arm_r, 0.015, 0.015, 0.9, Vector3(0, -0.2, 0.2), Color("6a4a2a"), Vector3(PI / 2.0, 0, 0))  # tombak
		cone(pv.arm_r, 0.04, 0.16, Vector3(0, -0.2, 0.7), Color("c8d0d8"), Vector3(PI / 2.0, 0, 0))
	else:
		box(pv.arm_r, Vector3(0.035, 0.28, 0.015), Vector3(0, -0.5, 0.06), Color("c8d4e0"), Vector3(0.3, 0, 0))  # belati
	if big:
		cyl(head, 0.16, 0.2, 0.12, Vector3(0, 0.46, 0), Color("e0b830"))  # mahkota
		for i in 5:
			var a := TAU * i / 5.0
			cone(head, 0.03, 0.1, Vector3(cos(a) * 0.17, 0.56, sin(a) * 0.17), Color("e0b830"))
		box(pv.body, Vector3(0.5, 0.7, 0.05), Vector3(0, 0.78, -0.16), Color("8a1f1f"))  # jubah
	return pv


static func _golem(root: Node3D, rock: Color, rock2: Color, accent: Color, lava: bool) -> Dictionary:
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	for side in [-1.0, 1.0]:
		var nm := "leg_l" if side < 0.0 else "leg_r"
		var leg := pivot(body, nm, Vector3(side * 0.2, 0.5, 0))
		pv[nm] = leg
		box(leg, Vector3(0.3, 0.5, 0.32), Vector3(0, -0.25, 0), rock2, Vector3(0, side * 0.1, 0))
		box(leg, Vector3(0.34, 0.12, 0.42), Vector3(0, -0.46, 0.03), rock)
	box(body, Vector3(0.78, 0.72, 0.5), Vector3(0, 0.88, 0), rock, Vector3(0, 0.05, 0))
	box(body, Vector3(0.62, 0.3, 0.42), Vector3(0, 0.55, 0), rock2)
	for side2 in [-1.0, 1.0]:
		var an := "arm_l" if side2 < 0.0 else "arm_r"
		var arm := pivot(body, an, Vector3(side2 * 0.55, 1.15, 0))
		pv[an] = arm
		box(arm, Vector3(0.28, 0.62, 0.28), Vector3(0, -0.32, 0), rock2, Vector3(0, 0, side2 * 0.08))
		box(arm, Vector3(0.38, 0.34, 0.38), Vector3(0, -0.72, 0), rock)
		box(arm, Vector3(0.34, 0.14, 0.34), Vector3(0, 0.0, 0), rock)  # bahu
	var head := pivot(body, "head", Vector3(0, 1.28, 0.05))
	pv["head"] = head
	box(head, Vector3(0.4, 0.34, 0.36), Vector3(0, 0.17, 0), rock, Vector3(0.0, 0.06, 0.0))
	_eyes(head, 0.17, accent if lava else Color("e8e8d0"), lava, 1.0, 0.45)
	if lava:
		for i in 5:  # retakan menyala di dada
			var a := -0.5 + i * 0.25
			box(body, Vector3(0.05, 0.4, 0.02), Vector3(a, 0.88, 0.26), accent, Vector3(0, 0, a * 0.9), true)
		box(body, Vector3(0.7, 0.04, 0.02), Vector3(0, 0.9, 0.26), accent, Vector3.ZERO, true)
	else:
		for i in 6:  # lumut di bahu dan kepala
			var a2 := (i - 2.5) * 0.14
			box(body, Vector3(0.14, 0.04, 0.14), Vector3(a2, 1.25 - 0.02 * i, 0.12 * ((i % 3) - 1)), accent)
		box(head, Vector3(0.22, 0.04, 0.2), Vector3(0.05, 0.36, 0.0), accent)
	return pv


static func _quad(root: Node3D, o: Dictionary) -> Dictionary:
	var c: Color = o.body
	var belly: Color = o.belly
	var len := float(o.len)
	var wid := float(o.wid)
	var hgt := float(o.hgt)
	var leg_len := float(o.leg_len)
	var hr := float(o.head_r)
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var by := leg_len + hgt * 0.8
	ball(body, 1.0, Vector3(0, by, 0), c, Vector3(wid, hgt, len))
	ball(body, 1.0, Vector3(0, by - hgt * 0.35, 0.02), belly, Vector3(wid * 0.9, hgt * 0.7, len * 0.9))
	var head := pivot(body, "head", Vector3(0, by + hgt * 0.35, len * 0.85))
	pv["head"] = head
	ball(head, hr, Vector3(0, 0, 0), c)
	_eyes(head, hr * 0.9, Color("1a1a1a"), false, 0.75, 0.55)
	match str(o.snout):
		"cone":
			cone(head, hr * 0.7, hr * 1.6, Vector3(0, -hr * 0.1, hr * 1.0), c, Vector3(PI / 2.0, 0, 0))
		"long":
			box(head, Vector3(hr * 0.9, hr * 0.8, hr * 2.0), Vector3(0, -hr * 0.2, hr * 1.5), belly)
			ball(head, hr * 0.18, Vector3(0, -hr * 0.05, hr * 2.5), Color("202020"))
		"boar":
			cyl(head, hr * 0.55, hr * 0.65, hr * 1.0, Vector3(0, -hr * 0.2, hr * 1.2), Color("8a6a5a"), Vector3(PI / 2.0, 0, 0))
			for s in [-1.0, 1.0]:
				cone(head, hr * 0.14, hr * 1.0, Vector3(s * hr * 0.55, -hr * 0.45, hr * 1.35), Color("f0e8d0"), Vector3(0.4, 0, s * 0.2))
	for s2 in [-1.0, 1.0]:
		if str(o.ears) == "round":
			ball(head, hr * 0.55, Vector3(s2 * hr * 0.75, hr * 0.85, -hr * 0.2), belly, Vector3(1.0, 1.0, 0.3))
		else:
			cone(head, hr * 0.35, hr * 1.0, Vector3(s2 * hr * 0.6, hr * 1.1, -hr * 0.2), c)
	var tail := pivot(body, "tail", Vector3(0, by + hgt * 0.2, -len * 0.95))
	pv["tail"] = tail
	match str(o.tail):
		"thin":
			cyl(tail, 0.012, 0.025, 0.5, Vector3(0, 0, -0.25), Color("d8a898"), Vector3(PI / 2.0 + 0.2, 0, 0))
		"bushy":
			ball(tail, 0.1, Vector3(0, -0.02, -0.18), c, Vector3(0.8, 0.8, 2.2))
		"curl":
			ball(tail, 0.05, Vector3(0, 0.06, -0.05), Color("7a5a44"))
	var legs := {"leg_fl": Vector2(-1, 1), "leg_fr": Vector2(1, 1), "leg_bl": Vector2(-1, -1), "leg_br": Vector2(1, -1)}
	for nm: String in legs:
		var d: Vector2 = legs[nm]
		var leg := pivot(body, nm, Vector3(d.x * wid * 0.6, leg_len + hgt * 0.2, d.y * len * 0.55))
		pv[nm] = leg
		box(leg, Vector3(0.07 + wid * 0.12, leg_len + hgt * 0.2, 0.07 + wid * 0.12), Vector3(0, -(leg_len + hgt * 0.2) / 2.0, 0), c.darkened(0.15))
	return pv


static func _snake(root: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var parent: Node3D = body
	var green := Color("6a9a3a")
	for i in 10:
		var seg := pivot(parent, "seg_%d" % i, Vector3(0, 0.12, 0.5) if i == 0 else Vector3(0, 0, -0.17))
		pv["seg_%d" % i] = seg
		var r := 0.12 - i * 0.008
		ball(seg, r, Vector3.ZERO, green.lerp(Color("c8b838"), 0.0 if i % 2 == 0 else 0.35), Vector3(1.0, 0.9, 1.3))
		parent = seg
	var head: Node3D = pv.seg_0
	ball(head, 0.14, Vector3(0, 0.02, 0.1), green.darkened(0.1), Vector3(1.0, 0.8, 1.3))
	_eyes(head, 0.14, Color("f0d020"), false, 1.2, 0.8)
	box(head, Vector3(0.02, 0.01, 0.12), Vector3(0, -0.02, 0.32), Color("d02020"))  # lidah
	return pv


static func _hopper(root: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var green := Color("7ab83a")
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	ball(body, 1.0, Vector3(0, 0.34, 0), green, Vector3(0.14, 0.14, 0.4))
	ball(body, 0.13, Vector3(0, 0.4, 0.42), green.lightened(0.1))
	for s in [-1.0, 1.0]:
		ball(body, 0.07, Vector3(s * 0.1, 0.5, 0.48), Color("e8e8c0"))  # mata besar
		ball(body, 0.03, Vector3(s * 0.11, 0.5, 0.54), Color("101010"))
		box(body, Vector3(0.015, 0.015, 0.4), Vector3(s * 0.05, 0.62, 0.62), Color("5a7a2a"), Vector3(-0.5, 0, s * 0.2))  # sungut
		box(body, Vector3(0.14, 0.015, 0.45), Vector3(s * 0.09, 0.46, -0.05), Color("a8d868"), Vector3(0, s * 0.1, 0))  # sayap
		var nm := "leg_l" if s < 0.0 else "leg_r"
		var leg := pivot(body, nm, Vector3(s * 0.12, 0.3, -0.15))
		pv[nm] = leg
		box(leg, Vector3(0.05, 0.4, 0.06), Vector3(0, 0.1, -0.12), green.darkened(0.1), Vector3(0.9, 0, 0))
		box(leg, Vector3(0.04, 0.34, 0.05), Vector3(0, -0.18, -0.3), green.darkened(0.2), Vector3(-0.3, 0, 0))
		for k in [-0.1, 0.1]:  # kaki depan kecil
			box(body, Vector3(0.035, 0.25, 0.035), Vector3(s * 0.1, 0.2, 0.3 + k), green.darkened(0.2))
	return pv


static func _bat(root: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var fur := Color("3a2f45")
	var body := pivot(root, "body", Vector3(0, 0.7, 0))
	pv["body"] = body
	ball(body, 0.14, Vector3.ZERO, fur, Vector3(1.0, 1.0, 1.3))
	var head := pivot(body, "head", Vector3(0, 0.08, 0.18))
	pv["head"] = head
	ball(head, 0.1, Vector3.ZERO, fur.lightened(0.05))
	_eyes(head, 0.1, Color("ff3030"), true, 0.9, 0.5)
	for s in [-1.0, 1.0]:
		cone(head, 0.04, 0.12, Vector3(s * 0.06, 0.12, -0.02), fur)
		var nm := "wing_l" if s < 0.0 else "wing_r"
		var wing := pivot(body, nm, Vector3(s * 0.1, 0.03, 0))
		pv[nm] = wing
		box(wing, Vector3(0.4, 0.015, 0.26), Vector3(s * 0.22, 0, -0.02), Color("55406a"))
		box(wing, Vector3(0.25, 0.012, 0.2), Vector3(s * 0.5, 0, -0.04), Color("55406a"), Vector3(0, s * 0.3, 0))
		box(wing, Vector3(0.5, 0.02, 0.03), Vector3(s * 0.28, 0.01, 0.1), fur)
	return pv
