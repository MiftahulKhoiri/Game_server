extends Node3D
## Peti harta: badan kayu, tutup berengsel, pita dan kunci emas. Dibangun dari bentuk dasar.
## Warna pita menurut tingkat (1 kayu-emas, 2 perak, 3 biru, 4 ungu). Isi diundi server.

const WorldBuild = preload("res://scripts/world_build.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")

## Ukuran peti dibuat lebih kecil supaya pas di dunia (hitbox dan jangkauan buka tidak berubah).
const SIZE := 0.7
const BAND_COLORS := [Color("e0b13a"), Color("c9ced8"), Color("6aa7ff"), Color("c07bff")]

var chest_id := ""
var is_open := false

var _lid: Node3D
var _treasure: MeshInstance3D
var _sparkle: CPUParticles3D
var _label: Label3D


func build(id: String, tier: int) -> void:
	chest_id = id
	var band_col: Color = BAND_COLORS[clampi(tier, 1, 4) - 1]
	var wood := WorldBuild.mat(Color("7a4a24"), false, 0.85)
	var band := WorldBuild.mat(band_col, false, 0.35)

	_add_box(self, Vector3(0.78, 0.38, 0.52), Vector3(0, 0.19, 0), wood)
	for sx in [-0.26, 0.26]:
		_add_box(self, Vector3(0.07, 0.4, 0.55), Vector3(sx, 0.2, 0), band)

	_lid = Node3D.new()  # engsel di tepi belakang atas badan
	_lid.set_meta("no_merge", true)  # tutup berputar saat dibuka: digabung tersendiri
	_lid.position = Vector3(0, 0.38, -0.26)
	add_child(_lid)
	_add_box(_lid, Vector3(0.78, 0.12, 0.52), Vector3(0, 0.06, 0.26), wood)
	var arch := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.26
	cm.height = 0.78
	cm.radial_segments = 12
	arch.mesh = cm
	arch.material_override = wood
	arch.rotation.z = PI / 2.0
	arch.position = Vector3(0, 0.12, 0.26)
	arch.scale = Vector3(0.55, 1.0, 1.0)  # setengah lingkaran yang pipih
	_lid.add_child(arch)
	for sx in [-0.26, 0.26]:
		_add_box(_lid, Vector3(0.07, 0.2, 0.56), Vector3(sx, 0.1, 0.26), band)
	_add_box(self, Vector3(0.13, 0.15, 0.05), Vector3(0, 0.36, 0.27), band)  # kunci
	if tier >= 3:
		var gem := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		gem.mesh = sm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = band_col
		gm.emission_enabled = true
		gm.emission = band_col
		gm.emission_energy_multiplier = 1.6
		gem.material_override = gm
		gem.position = Vector3(0, 0.36, 0.3)
		add_child(gem)

	_treasure = MeshInstance3D.new()  # tumpukan emas yang terlihat saat terbuka
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.64, 0.4)
	_treasure.mesh = pm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("ffd24a")
	tm.emission_enabled = true
	tm.emission = Color("ffb800")
	tm.emission_energy_multiplier = 1.2
	_treasure.material_override = tm
	_treasure.position = Vector3(0, 0.37, 0)
	_treasure.visible = false
	add_child(_treasure)

	_sparkle = CPUParticles3D.new()  # kilau pelan saat masih tertutup
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color("fff0a0")
	q.material = qm
	_sparkle.mesh = q
	_sparkle.amount = 5
	_sparkle.lifetime = 1.4
	_sparkle.direction = Vector3.UP
	_sparkle.spread = 20.0
	_sparkle.initial_velocity_min = 0.2
	_sparkle.initial_velocity_max = 0.45
	_sparkle.gravity = Vector3.ZERO
	_sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparkle.emission_sphere_radius = 0.3
	_sparkle.position = Vector3(0, 0.4, 0)
	add_child(_sparkle)

	_label = Label3D.new()
	_label.text = "Peti Harta"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.006 / SIZE
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = band_col.lightened(0.3)
	_label.position = Vector3(0, 0.95, 0)
	_label.visible = false
	add_child(_label)
	MeshMerge.merge(self)   # badan: 7 bentuk -> 2 mesh (panggilan gambar lebih sedikit)
	MeshMerge.merge(_lid)
	scale = Vector3.ONE * SIZE


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)


## Buka / tutup tutupnya (animasi halus bila `animate`).
func set_open(on: bool, animate := true) -> void:
	is_open = on
	_sparkle.emitting = not on
	_treasure.visible = on
	var angle := deg_to_rad(-112.0) if on else 0.0
	if animate and is_inside_tree():
		create_tween().tween_property(_lid, "rotation:x", angle, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_lid.rotation.x = angle


## Nama peti muncul saat pemain dekat.
func set_hint(on: bool) -> void:
	_label.visible = on and not is_open
