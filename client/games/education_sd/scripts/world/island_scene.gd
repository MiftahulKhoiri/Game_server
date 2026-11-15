extends Node3D
## Dunia 3D satu pulau (Dunia Enam Pulau). Tahap 1: pulau bulat dengan pantai, laut, pohon, dermaga, dan
## perahu untuk kembali ke peta; papan selamat datang. Tahap 2 mengisi Pulau 1 (desa, akademi, hutan,
## sungai, gua, benteng). Antarmuka yang dipakai HUD (w3d_hud.gd): player, interact(), focus_changed.

signal interacted(kind: String, id: String)
signal focus_changed(text: String)

const Player := preload("res://games/education_sd/scripts/world/w3d_player.gd")
const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const IslandWorld := preload("res://games/education_sd/scripts/world/w3d_world.gd")

const GROUND_R := 36.0
const BEACH_R := 41.0
const WALK_R := 40.0
const DOCK_Z0 := 39.0
const DOCK_Z1 := 50.0
const DOCK_HALF := 1.6
const FOCUS_RANGE := 2.8

var ctx: Dictionary
var island: Dictionary
var profile: Dictionary
var player: CharacterBody3D
var spots: Array = []  # [{pos: Vector3, kind, id, text}]
var _focus := -1
var _rng := RandomNumberGenerator.new()


## c: {island: {...dari islands.json}, gfx: "hemat|seimbang|tinggi", hero: look Dictionary}
func build(c: Dictionary) -> void:
	ctx = c
	island = c.island
	profile = IslandWorld.PROFILES.get(str(c.get("gfx", "seimbang")), IslandWorld.PROFILES.seimbang)
	_rng.seed = hash(str(island.id))
	_environment()
	_sea()
	_ground()
	_dock()
	_trees()
	_sign()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.setup(c.get("hero", {}))
	player.place(Vector3(0, 0.15, DOCK_Z0 + 2.0), 0.0)


func _environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2f6fb8")
	sky_mat.sky_horizon_color = Color("bfe6ff")
	sky_mat.ground_horizon_color = Color("bfe6ff")
	sky_mat.ground_bottom_color = Color("2a78b8")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.18
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.95
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.15
	if bool(profile.get("fog", false)):
		env.fog_enabled = true
		env.fog_light_color = Color("cfeaff")
		env.fog_density = 0.003
		env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 0.7
	sun.light_color = Color("fff1d6")
	sun.shadow_enabled = bool(profile.get("shadow", false))
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


func _mesh(mesh: Mesh, col: Color, pos := Vector3.ZERO, rough := 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Rig.mat(col, rough)
	mi.position = pos
	add_child(mi)
	return mi


func _static_box(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = pos
	add_child(body)


func _static_cyl(radius: float, height: float, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	add_child(body)


func _sea() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	var sea := MeshInstance3D.new()
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("1f78c0")
	sm.roughness = 0.35
	sm.metallic_specular = 0.25
	sea.material_override = sm
	sea.position = Vector3(0, -0.55, 0)
	add_child(sea)
	sea.name = "Sea"
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ground() -> void:
	var green := Color.from_string(str(island.get("color", "#7cc95a")), Color("7cc95a"))
	var sand := Color.from_string(str(island.get("sand", "#f3dfa2")), Color("f3dfa2"))
	var beach := _mesh(Rig.cyl(BEACH_R, BEACH_R + 3.0, 1.2, 64), sand.darkened(0.12), Vector3(0, -0.8, 0))
	beach.name = "Beach"
	var ground := _mesh(Rig.cyl(GROUND_R, GROUND_R + 2.0, 1.0, 64), green.darkened(0.15), Vector3(0, -0.5, 0))
	ground.name = "Ground"
	_static_cyl(BEACH_R + 1.0, 1.0, Vector3(0, -0.7, 0))
	_static_cyl(GROUND_R + 1.0, 1.0, Vector3(0, -0.5, 0))
	# Bukit kecil di tengah pulau (tempat Tahap 2 meletakkan akademi).
	var hill := _mesh(Rig.cyl(7.0, 12.0, 1.4, 40), green, Vector3(0, -0.2, -10))
	hill.name = "Hill"
	_static_cyl(10.0, 1.4, Vector3(0, -0.2, -10))


func _dock() -> void:
	var len := DOCK_Z1 - DOCK_Z0 + 4.0
	var zc := (DOCK_Z0 + DOCK_Z1) / 2.0 - 2.0
	var deck := _mesh(Rig.box(Vector3(DOCK_HALF * 2.0, 0.25, len)), Color("a0764a"), Vector3(0, -0.02, zc))
	deck.name = "Dock"
	_static_box(Vector3(DOCK_HALF * 2.0, 0.3, len), Vector3(0, -0.05, zc))
	for z in range(int(DOCK_Z0), int(DOCK_Z1) + 1, 3):
		for x in [-DOCK_HALF, DOCK_HALF]:
			_mesh(Rig.cyl(0.14, 0.14, 1.4, 8), Color("6b4a2a"), Vector3(x, -0.6, z))
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.position = Vector3(2.6, -0.45, DOCK_Z1 - 1.5)
	add_child(boat)
	var hull := MeshInstance3D.new()
	hull.mesh = Rig.box(Vector3(1.8, 0.7, 4.2))
	hull.material_override = Rig.mat(Color("8a5a2b"))
	hull.position.y = 0.25
	boat.add_child(hull)
	var mast := MeshInstance3D.new()
	mast.mesh = Rig.cyl(0.07, 0.07, 3.4, 8)
	mast.material_override = Rig.mat(Color("5a3a1a"))
	mast.position.y = 2.2
	boat.add_child(mast)
	var sail := MeshInstance3D.new()
	sail.mesh = Rig.box(Vector3(0.05, 2.2, 1.8))
	sail.material_override = Rig.mat(Color("fdf6e3"))
	sail.position = Vector3(0, 2.4, 0.4)
	boat.add_child(sail)
	spots.append({"pos": Vector3(0, 0, DOCK_Z1 - 1.0), "kind": "dock", "id": "perahu",
		"text": "AKSI: naik perahu ke Peta Dunia"})


func _trees() -> void:
	var kinds := ["vegetation/tree_round", "vegetation/tree_pine", "vegetation/bush"]
	var n := clampi(int(profile.get("trees", 130)) / 3, 20, 70)
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 6:
		tries += 1
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(14.0, GROUND_R - 2.0)
		var pos := Vector3(cos(a) * d, 0, sin(a) * d)
		if absf(pos.x) < 5.0 and pos.z > 8.0:  # jalan dari dermaga tetap lapang
			continue
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var mesh = IslandWorld.env_mesh(kind)
		var mi := MeshInstance3D.new()
		if mesh != null:
			mi.mesh = mesh
			mi.scale = Vector3.ONE * _rng.randf_range(0.9, 1.3)
		else:
			mi.mesh = Rig.sphere(1.2)
			mi.material_override = Rig.mat(Color("3f8f3f"))
			pos.y = 1.4
		mi.position = pos
		mi.rotation.y = _rng.randf() * TAU
		mi.name = "Tree%d" % placed
		add_child(mi)
		if kind != "vegetation/bush":
			_static_cyl(0.35, 2.0, pos + Vector3(0, 1.0, 0))
		placed += 1


func _sign() -> void:
	var sp := Vector3(-2.4, 0, DOCK_Z0 - 5.0)
	var post := _mesh(Rig.cyl(0.1, 0.1, 1.6, 8), Color("6b4a2a"), sp + Vector3(0, 0.8, 0))
	post.name = "SignPost"
	_mesh(Rig.box(Vector3(1.6, 0.9, 0.12)), Color("e8c88a"), sp + Vector3(0, 1.6, 0))
	var lbl := Label3D.new()
	lbl.text = "Pulau %d\n%s" % [int(island.number), str(island.name)]
	lbl.font_size = 44
	lbl.outline_size = 10
	lbl.modulate = Color("2b2440")
	lbl.outline_modulate = Color("fdf6e3")
	lbl.position = sp + Vector3(0, 1.62, 0.08)
	lbl.pixel_size = 0.006
	add_child(lbl)
	spots.append({"pos": sp, "kind": "sign", "id": "selamat_datang", "text": "AKSI: baca papan"})


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	# Batas pulau: pemain tidak bisa berjalan ke laut, kecuali di atas dermaga.
	var p := player.global_position
	var on_dock := absf(p.x) <= DOCK_HALF + 0.2 and p.z >= DOCK_Z0 - 2.0 and p.z <= DOCK_Z1 + 1.0
	var flat := Vector2(p.x, p.z)
	if not on_dock and flat.length() > WALK_R:
		flat = flat.normalized() * WALK_R
		player.global_position = Vector3(flat.x, p.y, flat.y)
	if on_dock:
		player.global_position.z = minf(p.z, DOCK_Z1 - 0.6)
	if p.y < -3.0:
		player.place(Vector3(0, 0.15, DOCK_Z0 + 2.0), 0.0)


func _process(_delta: float) -> void:
	if player == null:
		return
	var best := -1
	var best_d := FOCUS_RANGE
	for i in spots.size():
		var d: float = Vector2(player.global_position.x - spots[i].pos.x, player.global_position.z - spots[i].pos.z).length()
		if d < best_d:
			best_d = d
			best = i
	if best != _focus:
		_focus = best
		focus_changed.emit(str(spots[best].text) if best >= 0 else "")


func focus_kind() -> String:
	return str(spots[_focus].kind) if _focus >= 0 else ""


func interact() -> bool:
	if _focus < 0:
		return false
	player.rig.play_once("interaksi", 0.7)
	interacted.emit(str(spots[_focus].kind), str(spots[_focus].id))
	return true


## Pindahkan pemain ke dekat titik interaksi `kind` (dipakai uji & tombol bantuan).
func spot_pos(kind: String) -> Vector3:
	for s in spots:
		if str(s.kind) == kind:
			return s.pos
	return Vector3.ZERO
