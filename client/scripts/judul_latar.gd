extends SubViewportContainer
## Latar layar awal: diorama 3D senja. Pahlawan berjubah berdiri di atas batu, pemanah di
## sampingnya, monster mengepung dari kiri-kanan, dan istana jauh di balik bukit.
## Hanya hiasan; tidak memengaruhi permainan. Dirender hanya saat Beranda tampil (hemat baterai).

const Models = preload("res://scripts/models.gd")
const ALAM_DIR := "res://assets/models/alam/"

## id model, posisi (x, z), skala, putaran Y (derajat). Arah depan model = +Z (menghadap kamera).
const CAST := [
	{"id": "serigala_hutan", "x": -1.0, "z": -4.2, "s": 2.4, "r": 12.0},
	{"id": "golem_lava", "x": 1.1, "z": -4.0, "s": 1.9, "r": -12.0},
	{"id": "ogre_batu", "x": -1.3, "z": -2.0, "s": 1.6, "r": 22.0},
	{"id": "iblis_biru", "x": 1.3, "z": -2.0, "s": 1.3, "r": -22.0},
	{"id": "pemanah", "x": -0.85, "z": -0.9, "s": 1.6, "r": 10.0},
	{"id": "ksatria", "x": 0.15, "z": 0.0, "s": 1.75, "r": 180.0},
	{"id": "goblin", "x": -1.15, "z": 1.7, "s": 1.5, "r": 28.0},
	{"id": "goblin_penjaga", "x": 1.15, "z": 1.6, "s": 1.3, "r": -28.0},
]

var _vp: SubViewport
var _cam: Camera3D
var _t := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var root := Node3D.new()
	_vp.add_child(root)
	_bangun_langit(root)
	_bangun_tanah(root)
	_bangun_istana(root)
	for c: Dictionary in CAST:
		var m := Models.create(c.id)
		m.position = Vector3(c.x, 0.55 if c.id == "ksatria" else 0.0, c.z)
		if c.id == "pemanah":
			m.position.y = 0.3
		m.scale = m.scale * float(c.s)  # skala bawaan (pahlawan 0,42) dikali pembesaran adegan
		m.rotation.y = deg_to_rad(float(c.r))
		root.add_child(m)
	_cam = Camera3D.new()
	_cam.fov = 46.0
	_cam.current = true
	root.add_child(_cam)
	_arahkan(0.0)


func set_aktif(on: bool) -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	_t += delta
	_arahkan(sin(_t * 0.35) * 0.05)


## Kamera berayun pelan di depan adegan, selalu memandang pahlawan.
func _arahkan(sway: float) -> void:
	if _cam == null or not _cam.is_inside_tree():
		return
	_cam.look_at_from_position(Vector3(sway * 6.0, 1.9, 7.4), Vector3(0.0, 1.45, 0.0))


func _bangun_langit(root: Node3D) -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("3a4a98")
	sky.sky_horizon_color = Color("ffb27a")
	sky.ground_horizon_color = Color("e08a68")
	sky.ground_bottom_color = Color("3b2b3a")
	sky.sky_curve = 0.18
	var s := Sky.new()
	s.sky_material = sky
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffd9b8")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color("ffc79a")
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()  # cahaya hangat dari depan-kiri
	sun.light_color = Color("ffd8a8")
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-32.0, -28.0, 0.0)
	root.add_child(sun)
	var rim := DirectionalLight3D.new()  # cahaya senja dari belakang-kanan, memberi tepi terang
	rim.light_color = Color("ff9a60")
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	root.add_child(rim)


func _bangun_tanah(root: Node3D) -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = _bahan(Color("4a5a3a"))
	ground.position = Vector3(0, -0.02, -8)
	root.add_child(ground)
	var rock := MeshInstance3D.new()  # batu tempat pahlawan berdiri
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 1.15
	cm.height = 0.55
	cm.radial_segments = 8
	rock.mesh = cm
	rock.material_override = _bahan(Color("55555e"))
	rock.position = Vector3(0.15, 0.27, 0.0)
	root.add_child(rock)
	var moss := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.72
	mm.bottom_radius = 0.76
	mm.height = 0.06
	mm.radial_segments = 8
	moss.mesh = mm
	moss.material_override = _bahan(Color("5f8f3f"))
	moss.position = Vector3(0.15, 0.55, 0.0)
	root.add_child(moss)


## Istana di kejauhan (KayKit, CC0), dibesarkan supaya terlihat di atas bukit kecil.
func _bangun_istana(root: Node3D) -> void:
	var path := ALAM_DIR + "building_castle_red.gltf"
	var hill := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 6.0
	sm.height = 6.0
	hill.mesh = sm
	hill.material_override = _bahan(Color("6d6f86"))
	hill.position = Vector3(0.5, -2.0, -24.0)
	root.add_child(hill)
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var castle := scene.instantiate() as Node3D
			castle.position = Vector3(0.5, 0.5, -24.0)
			castle.scale = Vector3.ONE * 2.6
			root.add_child(castle)


func _bahan(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m
