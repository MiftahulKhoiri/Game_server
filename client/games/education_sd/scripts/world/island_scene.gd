extends Node3D
## Dunia 3D satu pulau (Dunia Enam Pulau), dibangun dari data tata letak (data/islandN.json):
## tanah + bukit (landai, bisa didaki), pantai, laut, sungai + jembatan, jalan setapak, bangunan GLB,
## ladang, hutan, benteng bos, batu penutup gua, papan nama tempat, penduduk yang berjalan-jalan,
## dermaga + perahu kembali ke peta. Pulau tanpa tata letak memakai pulau bulat sederhana (Tahap 1).
## Antarmuka untuk HUD (w3d_hud.gd): player, interact(), end_talk(), sinyal focus_changed.

signal interacted(kind: String, id: String)
signal focus_changed(text: String)
signal place_changed(id: String)

const Player := preload("res://games/education_sd/scripts/world/w3d_player.gd")
const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const IslandWorld := preload("res://games/education_sd/scripts/world/w3d_world.gd")
const Terrain := preload("res://games/education_sd/scripts/world/w3d_terrain.gd")
const Nature := preload("res://games/education_sd/scripts/world/w3d_nature.gd")

const FOCUS_RANGE := 2.8
const NPC_SPEED := 1.1
const NPC_ACTIVE := 40.0
const C_PATH := Color("c9a26b")
const C_TRAIL := Color("b98e5c")  # jalan tanah yang dicat di medan (5.0)
const C_PLAZA := Color("b9ab90")  # pelataran batu
const C_STONE := Color("8a8174")
const C_WOOD := Color("8a5a2b")

var ctx: Dictionary
var island: Dictionary
var layout: Dictionary
var npc_engine  # NpcEngine (place_at)
var profile: Dictionary
var player: CharacterBody3D
var radius := 36.0
var spots: Array = []  # [{pos: Vector3, kind, id, text, node}]
var npcs: Array = []  # [{id, node, rig, home, wander, target, wait, talking}]
var hills: Array = []
var terrain  # w3d_terrain.gd (pulau dengan tata letak); null = pulau bulat sederhana
var flower_spots: Array = []
var build_prof: Dictionary = {}  # waktu bangun per bagian (ms), untuk uji kinerja
var place := ""
var dock_z0 := 0.0
var dock_z1 := 0.0
var _focus := -1
var _talk: Dictionary = {}
var _talk_release := -1.0
var _place_t := 0.0
var _rng := RandomNumberGenerator.new()
var _river: Dictionary = {}
var flags: Dictionary = {}
var pickups: Dictionary = {}  # uid -> Node3D
const PICK_RANGE := 1.5
var _gate_body: StaticBody3D
var _gate_mesh: MeshInstance3D
var _boulder_nodes: Array = []
var foes: Array = []  # [{uid, monster, node, rig, home, target, wait, rest}]
const FOE_CHASE := 6.0
const FOE_TOUCH := 1.5
const FOE_SPEED := 1.3

const DOCK_HALF := 1.6


## Nama bendera dunia per pulau (dari tata letak; bawaan = nama Pulau 1).
func flag_boulder() -> String:
	return str(layout.get("boulder", {}).get("flag", "gua_terbuka"))


func flag_gate() -> String:
	return str(layout.get("fort", {}).get("flag", "gerbang_terbuka"))


func flag_boss() -> String:
	return str(layout.get("boss", {}).get("flag", "raja_kalah"))


func _col(key: String, fallback: Color) -> Color:
	return Color.from_string(str(layout.get("colors", {}).get(key, "")), fallback)


## c: {island, layout (Dictionary, boleh kosong), npc_engine, gfx, hero}
func build(c: Dictionary) -> void:
	ctx = c
	island = c.island
	layout = c.get("layout", {})
	npc_engine = c.get("npc_engine")
	profile = IslandWorld.PROFILES.get(str(c.get("gfx", "seimbang")), IslandWorld.PROFILES.seimbang)
	_rng.seed = hash(str(island.id))
	radius = float(layout.get("radius", 36.0))
	hills = layout.get("hills", [])
	_river = layout.get("river", {})
	flags = c.get("flags", {})
	dock_z0 = radius + 3.0
	dock_z1 = radius + 14.0
	if not layout.is_empty():
		var tp := Time.get_ticks_usec()
		_terrain_setup()
		build_prof["terrain"] = (Time.get_ticks_usec() - tp) / 1000.0
	_environment()
	_sea()
	var tg := Time.get_ticks_usec()
	_ground()
	build_prof["ground"] = (Time.get_ticks_usec() - tg) / 1000.0
	_dock()
	if layout.is_empty():
		_trees_simple()
		_signpost(Vector3(-2.4, 0, dock_z0 - 5.0), "Pulau %d\n%s" % [int(island.number), str(island.name)], "sign", "selamat_datang", "AKSI: baca papan")
	else:
		_river_and_bridge()
		_shapes()
		_paths()
		_places()
		_objects()
		_farm()
		_fort()
		_boulder()
		_academy_door()
		var tf := Time.get_ticks_usec()
		_forest()
		build_prof["forest"] = (Time.get_ticks_usec() - tf) / 1000.0
		_npcs()
		for qs in c.get("quest_spots", []):
			_clue(qs)
		for pk in c.get("pickups", []):
			add_pickup(str(pk.uid), str(pk.item), pk.pos)
		for f in c.get("foes", []):
			add_foe(f)
		var tn := Time.get_ticks_usec()
		_nature()
		build_prof["nature"] = (Time.get_ticks_usec() - tn) / 1000.0
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.setup(c.get("hero", {}))
	player.place(spawn_point(), 0.0)
	if terrain != null and bool(profile.get("fx", false)):
		Nature.motes(player, Color("fff4c8"))


func spawn_point() -> Vector3:
	return Vector3(0, 0.25, dock_z0 + 2.0)


# --- Tanah & ketinggian -------------------------------------------------------------------------------------

## Tinggi tanah di (x, z): 0 di dataran, naik landai di bukit.
func ground_y(x: float, z: float) -> float:
	if terrain != null:
		return terrain.height(x, z)
	var y := 0.0
	for h in hills:
		var d := Vector2(x - float(h.pos[0]), z - float(h.pos[1])).length()
		var top := float(h.top)
		var bottom := float(h.bottom)
		var hh := float(h.height)
		if d <= top:
			y = maxf(y, hh)
		elif d < bottom:
			y = maxf(y, hh * (bottom - d) / (bottom - top))
	return y


func _v(xz, extra_y := 0.0) -> Vector3:
	var x := float(xz[0])
	var z := float(xz[1])
	return Vector3(x, ground_y(x, z) + extra_y, z)


func _environment() -> void:
	# Paket visual 5.0: langit cerah bergradasi, cahaya ambien dari langit lebih tinggi (sisi bayangan tidak
	# hitam), matahari hangat + cahaya isi kebiruan tanpa bayangan, kabut tipis warna cakrawala.
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var top := _col("sky_top", Color("3a7fd5"))
	var hor := _col("sky_horizon", Color("cfeaff"))
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.sky_curve = 0.11
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = Color("3f6e55")
	sky_mat.ground_curve = 0.04
	sky_mat.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.14
	if bool(profile.get("fog", false)):
		env.fog_enabled = true
		env.fog_light_color = hor.lerp(Color.WHITE, 0.2)
		env.fog_density = 0.0028
		env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(-0.85, 0.65, 0)
	sun.light_energy = 0.95
	sun.light_color = Color("fff0d6")
	sun.shadow_enabled = bool(profile.get("shadow", false))
	sun.shadow_opacity = 0.82
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 42.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation = Vector3(-0.5, 0.65 + PI, 0)
	fill.light_energy = 0.14
	fill.light_color = hor.lerp(Color("9cc8ff"), 0.5)
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	add_child(fill)


func _mesh(mesh: Mesh, col: Color, pos := Vector3.ZERO, rough := 0.9, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Rig.mat(col, rough)
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _body(shape: Shape3D, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = xf
	add_child(body)
	return body


func _static_box(size: Vector3, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var bs := BoxShape3D.new()
	bs.size = size
	return _body(bs, Transform3D(Basis(Vector3.UP, rot_y), pos))


func _static_cyl(r: float, height: float, pos: Vector3) -> StaticBody3D:
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = height
	return _body(shape, Transform3D(Basis(), pos))


func _far(n: GeometryInstance3D, extra := 25.0) -> void:
	n.visibility_range_end = float(profile.get("range", 60.0)) + extra


func _sea() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	var sea := MeshInstance3D.new()
	sea.mesh = pm
	var sm := Nature.smat("sea")
	sm.set_shader_parameter("shore_r", radius + (3.9 if terrain != null else 6.0))
	sm.set_shader_parameter("move", 1.0 if bool(profile.get("fx", false)) else 0.0)
	if layout.get("colors", {}).has("sea"):
		sm.set_shader_parameter("deep", _col("sea", Color("0d55a0")))
	sea.material_override = sm
	sea.position = Vector3(0, -0.55, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	sea.name = "Sea"


func _ground() -> void:
	var green := _col("ground", Color.from_string(str(island.get("color", "#7cc95a")), Color("7cc95a")))
	var sand := Color.from_string(str(island.get("sand", "#f3dfa2")), Color("f3dfa2"))
	if terrain != null:
		_terrain_ground(green, sand)
		return
	var beach := _mesh(Rig.cyl(radius + 5.0, radius + 8.0, 1.2, 72), sand.darkened(0.12), Vector3(0, -0.62, 0))
	beach.name = "Beach"
	var ground := _mesh(Rig.cyl(radius, radius + 1.5, 1.0, 72), green.darkened(0.15), Vector3(0, -0.5, 0))
	ground.name = "Ground"
	# Satu permukaan rata y=0 untuk rumput + pantai: tidak ada anak tangga yang menahan pemain.
	_static_cyl(radius + 6.0, 1.0, Vector3(0, -0.5, 0))
	for h in hills:
		var hm := Rig.cyl(float(h.top), float(h.bottom), float(h.height), 48)
		var mi := _mesh(hm, green, Vector3(float(h.pos[0]), float(h.height) / 2.0, float(h.pos[1])))
		mi.name = "Hill_" + str(h.get("id", ""))
		_body(hm.create_trimesh_shape(), Transform3D(Basis(), mi.position))
	if layout.is_empty():
		var hill := _mesh(Rig.cyl(7.0, 12.0, 1.4, 40), green, Vector3(0, -0.2, -10))
		hill.name = "Hill"


func _dock() -> void:
	var len := dock_z1 - dock_z0 + 6.0
	var zc := (dock_z0 + dock_z1) / 2.0 - 3.0
	var deck := _mesh(Rig.box(Vector3(DOCK_HALF * 2.0, 0.25, len)), Color("a0764a"), Vector3(0, -0.07, zc))
	deck.name = "Dock"
	_static_box(Vector3(DOCK_HALF * 2.0, 0.3, len), Vector3(0, -0.1, zc))
	for z in range(int(dock_z0), int(dock_z1) + 1, 3):
		for x in [-DOCK_HALF, DOCK_HALF]:
			_mesh(Rig.cyl(0.14, 0.14, 1.4, 8), Color("6b4a2a"), Vector3(x, -0.6, z))
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.position = Vector3(2.6, -0.45, dock_z1 - 1.5)
	add_child(boat)
	_mesh(Rig.box(Vector3(1.8, 0.7, 4.2)), C_WOOD, Vector3(0, 0.25, 0), 0.9, boat)
	_mesh(Rig.cyl(0.07, 0.07, 3.4, 8), Color("5a3a1a"), Vector3(0, 2.2, 0), 0.9, boat)
	_mesh(Rig.box(Vector3(0.05, 2.2, 1.8)), Color("fdf6e3"), Vector3(0, 2.4, 0.4), 0.9, boat)
	spots.append({"pos": Vector3(0, 0, dock_z1 - 1.0), "kind": "dock", "id": "perahu",
		"text": "AKSI: naik perahu ke Peta Dunia"})


func _label3d(text: String, size: int, col: Color, pos: Vector3, parent: Node = null, billboard := true) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = size
	lbl.outline_size = 10
	lbl.modulate = col
	lbl.outline_modulate = Color("2b2440")
	lbl.pixel_size = 0.006
	lbl.position = pos
	if billboard:
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.visibility_range_end = 22.0
	(parent if parent != null else self).add_child(lbl)
	return lbl


func _signpost(pos: Vector3, text: String, kind: String, id: String, prompt: String) -> void:
	var post := _mesh(Rig.cyl(0.1, 0.1, 1.6, 8), Color("6b4a2a"), pos + Vector3(0, 0.8, 0))
	post.name = "Sign_" + id
	_far(post)
	_mesh(Rig.box(Vector3(1.9, 0.9, 0.12)), Color("e8c88a"), pos + Vector3(0, 1.6, 0))
	var lbl := _label3d(text, 40, Color("2b2440"), pos + Vector3(0, 1.62, 0.08), null, false)
	lbl.outline_modulate = Color("fdf6e3")
	lbl.visibility_range_end = 30.0
	spots.append({"pos": pos, "kind": kind, "id": id, "text": prompt})


func _trees_simple() -> void:
	var kinds := ["vegetation/tree_round", "vegetation/tree_pine", "vegetation/bush"]
	var n := clampi(int(profile.get("trees", 130)) / 3, 20, 70)
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 6:
		tries += 1
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(14.0, radius - 2.0)
		var pos := Vector3(cos(a) * d, 0, sin(a) * d)
		if absf(pos.x) < 5.0 and pos.z > 8.0:
			continue
		_tree_node(kinds[_rng.randi() % kinds.size()], pos, "Tree%d" % placed)
		placed += 1


func _tree_node(kind: String, pos: Vector3, name_: String) -> void:
	var mesh = IslandWorld.env_mesh(kind)
	var mi := MeshInstance3D.new()
	if mesh != null:
		mi.mesh = mesh
		mi.scale = Vector3.ONE * _rng.randf_range(0.9, 1.3)
	else:
		mi.mesh = Rig.sphere(1.2)
		mi.material_override = Rig.mat(Color("3f8f3f"))
		pos.y += 1.4
	mi.position = pos
	mi.rotation.y = _rng.randf() * TAU
	mi.name = name_
	_far(mi)
	add_child(mi)
	if kind != "vegetation/bush":
		_static_cyl(0.35, 2.0, pos + Vector3(0, 1.0, 0))


# --- Sungai, jalan, tempat ---------------------------------------------------------------------------------

func _river_and_bridge() -> void:
	if _river.is_empty():
		return
	var z := float(_river.z)
	var hw := float(_river.half_width)
	var bh := float(_river.bridge_half)
	var span := (radius + 8.0) * 2.0
	if terrain != null:
		_river_terrain(z, hw, bh, span)
		return
	var water := MeshInstance3D.new()
	water.name = "River"
	water.mesh = Rig.box(Vector3(span, 0.06, hw * 2.0))
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("2a8fd8")
	wm.roughness = 0.2
	wm.metallic_specular = 0.4
	water.material_override = wm
	water.position = Vector3(0, 0.03, z)
	add_child(water)
	for side in [-1.0, 1.0]:
		var bank := _mesh(Rig.box(Vector3(span, 0.08, 0.7)), Color("b39b6a"), Vector3(0, 0.04, z + side * (hw + 0.3)))
		bank.name = "Bank"
		# Dinding tak terlihat di tepi sungai (kecuali jembatan): pemain tidak tercebur.
		var seg := (span / 2.0) - bh
		for sx in [-1.0, 1.0]:
			_static_box(Vector3(seg, 2.0, 0.4), Vector3(sx * (bh + seg / 2.0), 1.0, z + side * (hw + 0.2)))
	var deck := _mesh(Rig.box(Vector3(bh * 2.0, 0.12, hw * 2.0 + 2.0)), Color("a0764a"), Vector3(0, 0.08, z))
	deck.name = "Bridge"
	for sx in [-1.0, 1.0]:
		_mesh(Rig.box(Vector3(0.18, 0.9, hw * 2.0 + 2.0)), Color("7a4a22"), Vector3(sx * (bh - 0.1), 0.55, z))
		_static_box(Vector3(0.25, 2.0, hw * 2.0 + 2.0), Vector3(sx * (bh - 0.1), 1.0, z))
		for k in [-1.0, 0.0, 1.0]:
			_mesh(Rig.cyl(0.12, 0.12, 1.2, 8), Color("6b4a2a"), Vector3(sx * (bh - 0.1), 0.6, z + k * hw))


## Bentuk alam besar dari data: gunung (kerucut), bukit batu, kawah. {type: cone, pos, r, top, h, color, solid}
func _shapes() -> void:
	var i := 0
	for sh in layout.get("shapes", []):
		i += 1
		var p := _v(sh.pos)
		var h := float(sh.get("h", 8.0))
		var mesh := Rig.cyl(float(sh.get("top", 0.0)), float(sh.r), h, 32)
		var mi := _mesh(mesh, Color.from_string(str(sh.get("color", "#6b6355")), Color.DIM_GRAY), p + Vector3(0, h / 2.0, 0), 0.95)
		mi.name = "Shape%d" % i
		_far(mi, 80.0)
		if bool(sh.get("solid", true)):
			_body(mesh.create_trimesh_shape(), Transform3D(Basis(), mi.position))
		if str(sh.get("glow", "")) != "":
			var g := _mesh(Rig.cyl(float(sh.get("top", 0.0)) * 0.9, float(sh.get("top", 0.0)) * 0.9, 0.2, 24), Color(str(sh.glow)), p + Vector3(0, h + 0.05, 0), 0.5)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(str(sh.glow))
			gm.emission_enabled = true
			gm.emission = Color(str(sh.glow))
			gm.emission_energy_multiplier = 1.5
			g.material_override = gm


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _paths() -> void:
	if terrain != null:
		_path_stones()
		return
	for seg in layout.get("paths", []):
		var a := Vector2(float(seg[0][0]), float(seg[0][1]))
		var b := Vector2(float(seg[1][0]), float(seg[1][1]))
		var a3 := Vector3(a.x, ground_y(a.x, a.y) + 0.03, a.y)
		var b3 := Vector3(b.x, ground_y(b.x, b.y) + 0.03, b.y)
		var len := a3.distance_to(b3)
		var mi := _mesh(Rig.box(Vector3(3.0, 0.03, len + (3.0 if is_equal_approx(a3.y, b3.y) else 0.4))), C_PATH, (a3 + b3) / 2.0)
		# Jalan di lereng bukit ikut miring (sumbu Z lokal = arah jalan).
		mi.rotation = Vector3(-asin((b3.y - a3.y) / maxf(len, 0.001)), atan2(b.x - a.x, b.y - a.y), 0)
		mi.name = "Path"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func near_path(x: float, z: float, margin: float) -> bool:
	for seg in layout.get("paths", []):
		if _seg_dist(Vector2(x, z), Vector2(float(seg[0][0]), float(seg[0][1])), Vector2(float(seg[1][0]), float(seg[1][1]))) < margin:
			return true
	return false


func _places() -> void:
	for pl in layout.get("places", []):
		if pl.has("plaza") and terrain == null:
			var plaza := _mesh(Rig.cyl(float(pl.plaza), float(pl.plaza), 0.04, 40), C_PATH.lightened(0.1), _v(pl.pos, 0.02))
			plaza.name = "Plaza_" + str(pl.id)
		if pl.has("sign"):
			_signpost(_v(pl.sign), str(pl.name), "sign", str(pl.id), "AKSI: baca papan " + str(pl.name))


func _objects() -> void:
	var i := 0
	for o in layout.get("objects", []):
		i += 1
		var mesh = IslandWorld.env_mesh(str(o.asset))
		if mesh == null:
			continue
		var scl := float(o.get("scale", 1.0))
		var rot := deg_to_rad(float(o.get("rot", 0.0)))
		var mi := MeshInstance3D.new()
		mi.name = "Obj%d_%s" % [i, str(o.asset).get_file()]
		mi.mesh = mesh
		mi.position = _v(o.pos)
		if o.has("y"):  # benda di air (mis. teratai di permukaan sungai)
			mi.position.y = float(o.y)
		mi.rotation.y = rot
		mi.scale = Vector3.ONE * scl
		_far(mi, 45.0)
		add_child(mi)
		if not bool(o.get("solid", true)):
			continue
		if o.has("radius"):
			_static_cyl(float(o.radius), 4.0, mi.position + Vector3(0, 2.0, 0))
			continue
		var bb: AABB = (mesh as Mesh).get_aabb()
		var c := bb.get_center() * scl
		c = Basis(Vector3.UP, rot) * Vector3(c.x, 0, c.z)
		var h := maxf(bb.size.y * scl, 1.5)
		_static_box(Vector3(bb.size.x * scl * 0.92, h, bb.size.z * scl * 0.92), mi.position + c + Vector3(0, h / 2.0, 0), rot)


func _farm() -> void:
	var f: Dictionary = layout.get("farm", {})
	if f.is_empty():
		return
	var c := _v(f.pos)
	var sx := float(f.size[0])
	var sz := float(f.size[1])
	var soil := _mesh(Rig.box(Vector3(sx, 0.06, sz)), Color("7a5232"), c + Vector3(0, 0.03, 0))
	soil.name = "Farm"
	var rows := int(f.get("rows", 5))
	var bush = IslandWorld.env_mesh("vegetation/bush")
	for r in rows:
		var z := c.z - sz / 2.0 + sz * (r + 0.5) / rows
		_mesh(Rig.box(Vector3(sx - 1.0, 0.18, 0.6)), Color("5e3d22"), Vector3(c.x, 0.1, z))
		var k := 0
		var x := c.x - sx / 2.0 + 1.0
		while x < c.x + sx / 2.0 - 0.8:
			if (r + k) % 3 != 1:  # sebagian bibit hilang dicuri goblin
				var plant := MeshInstance3D.new()
				if bush != null:
					plant.mesh = bush
					plant.scale = Vector3(0.35, 0.6, 0.35)
				else:
					plant.mesh = Rig.cyl(0.05, 0.25, 0.6, 6)
					plant.material_override = Rig.mat(Color("3f9a3f"))
				plant.position = Vector3(x, 0.15, z)
				_far(plant)
				add_child(plant)
			x += 1.5
			k += 1
	for side in [-1.0, 1.0]:
		_mesh(Rig.box(Vector3(sx + 1.0, 0.12, 0.12)), Color("8a6a3a"), Vector3(c.x, 0.7, c.z + side * (sz / 2.0 + 0.5)))
		_mesh(Rig.box(Vector3(0.12, 0.12, sz + 1.0)), Color("8a6a3a"), Vector3(c.x + side * (sx / 2.0 + 0.5), 0.7, c.z))


func _fort() -> void:
	var f: Dictionary = layout.get("fort", {})
	if f.is_empty():
		return
	var c := _v(f.pos)
	var hf := float(f.half)
	var wh := float(f.wall_h)
	var gh := float(f.gate_half)
	var root := Node3D.new()
	root.name = "Fort"
	add_child(root)
	var walls := [
		[Vector3(0, wh / 2.0, -hf), Vector3(hf * 2.0, wh, 1.2)],
		[Vector3(-hf, wh / 2.0, 0), Vector3(1.2, wh, hf * 2.0)],
		[Vector3(hf, wh / 2.0, 0), Vector3(1.2, wh, hf * 2.0)],
		[Vector3(-(hf + gh) / 2.0, wh / 2.0, hf), Vector3(hf - gh, wh, 1.2)],
		[Vector3((hf + gh) / 2.0, wh / 2.0, hf), Vector3(hf - gh, wh, 1.2)],
	]
	for w in walls:
		var m := _mesh(Rig.box(w[1]), _col("wall", C_STONE), c + w[0], 0.95, root)
		_far(m, 45.0)
		_static_box(w[1], c + w[0])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var tp := c + Vector3(sx * hf, 0, sz * hf)
			_far(_mesh(Rig.cyl(1.8, 2.0, wh + 2.2, 16), _col("wall", C_STONE).darkened(0.1), tp + Vector3(0, (wh + 2.2) / 2.0, 0), 0.95, root), 45.0)
			_far(_mesh(Rig.cyl(0.0, 2.3, 2.0, 16), _col("roof", Color("b5443a")), tp + Vector3(0, wh + 3.2, 0), 0.9, root), 45.0)
			_static_cyl(1.9, wh + 2.2, tp + Vector3(0, (wh + 2.2) / 2.0, 0))
	var gate := _mesh(Rig.box(Vector3(gh * 2.0, wh - 0.4, 0.5)), C_WOOD.darkened(0.15), c + Vector3(0, (wh - 0.4) / 2.0, hf), 0.9, root)
	gate.name = "Gate"
	_gate_mesh = gate
	_gate_body = _static_box(Vector3(gh * 2.0, wh, 0.6), c + Vector3(0, wh / 2.0, hf))
	for k in [-1.0, 1.0]:
		_mesh(Rig.box(Vector3(0.15, wh - 0.6, 0.6)), Color("5a5a66"), c + Vector3(k * gh * 0.5, (wh - 0.4) / 2.0, hf + 0.05), 0.5, root)
	var flag := _mesh(Rig.box(Vector3(1.4, 0.9, 0.05)), _col("flag", Color("6b8f2a")), c + Vector3(0, wh + 1.6, hf), 0.9, root)
	flag.name = "GoblinFlag"
	spots.append({"pos": c + Vector3(0, 0, hf + 1.4), "kind": "gate", "id": "benteng", "text": "AKSI: periksa gerbang benteng"})
	var b: Dictionary = layout.get("boss", {})
	if bool(flags.get(flag_boss(), false)):
		flag.material_override = Rig.mat(Color("3fae63"))
		b = {}
	if not b.is_empty():
		var bp := _v(b.pos)
		_mesh(Rig.box(Vector3(2.4, 0.8, 1.6)), Color("6b4a2a"), bp + Vector3(0, 0.4, -0.4), 0.9, root)
		_mesh(Rig.box(Vector3(2.4, 2.4, 0.4)), _col("roof", Color("b5443a")), bp + Vector3(0, 1.6, -1.1), 0.9, root)
		var boss := _figure(str(b.model), 1.7 * float(b.get("scale", 1.0)), bp + Vector3(0, 0.8, 0), 0.0, root, str(b.get("tint", "")))
		boss.name = "Boss"
		_label3d(str(b.name), 56, Color("ff8a6a"), Vector3(0, 3.2, 0), boss)
		spots.append({"pos": bp + Vector3(0, 0, 2.2 * float(b.get("scale", 1.0))), "kind": "boss", "id": str(b.get("monster", b.get("model", "boss"))),
			"text": "AKSI: hadapi " + str(b.name)})
	if bool(flags.get(flag_gate(), false)):
		open_gate(false)
	for g in ([] if bool(flags.get(flag_boss(), false)) else layout.get("guards", [])):
		var gn := _figure(str(g.model), float(g.get("height", 1.15)), _v(g.pos), 0.0, root, str(g.get("tint", "")))
		gn.name = "Guard"
		_label3d(str(g.name), 40, Color("ffd166"), Vector3(0, 1.9, 0), gn)


## Model berangka dari APK (res://assets/models) di posisi pos, menghadap yaw.
func _figure(model: String, height: float, pos: Vector3, yaw: float, parent: Node = null, tint := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	var rig := Rig.new()
	rig.glb_id = model
	rig.glb_height = height
	if tint != "":
		rig.glb_tint = Color.from_string(tint, Color.WHITE)
	n.add_child(rig)
	(parent if parent != null else self).add_child(n)
	rig.build()
	n.set_meta("rig", rig)
	return n


func _boulder() -> void:
	var b: Dictionary = layout.get("boulder", {})
	if b.is_empty():
		return
	var p := _v(b.pos)
	if bool(flags.get(flag_boulder(), false)):
		_rubble(p)
		return
	var mesh = IslandWorld.env_mesh("rocks/rock_a")
	var mi := MeshInstance3D.new()
	mi.name = "Boulder"
	mi.mesh = mesh if mesh != null else Rig.sphere(1.0)
	if mesh == null:
		mi.material_override = Rig.mat(C_STONE)
	mi.scale = Vector3.ONE * float(b.get("scale", 2.5))
	mi.position = p
	add_child(mi)
	var body := _static_cyl(1.0 * float(b.get("scale", 2.5)), 3.0, p + Vector3(0, 1.5, 0))
	_boulder_nodes = [mi, body]
	var to_center := Vector3(-p.x, 0, -p.z).normalized()
	spots.append({"pos": p + to_center * (1.2 * float(b.get("scale", 2.5))), "kind": "boulder", "id": "gua", "text": "AKSI: periksa batu besar"})


## Batu besar menggelinding ke samping: pintu gua terbuka (dipanggil saat teka-teki batu terpecahkan).
func open_cave() -> void:
	flags[flag_boulder()] = true
	var b: Dictionary = layout.get("boulder", {})
	for n in _boulder_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_boulder_nodes.clear()
	for i in range(spots.size() - 1, -1, -1):
		if str(spots[i].kind) == "boulder":
			spots.remove_at(i)
	_focus = -1
	if not b.is_empty():
		_rubble(_v(b.pos))


func _rubble(p: Vector3) -> void:
	var to_center := Vector3(-p.x, 0, -p.z).normalized()
	var side := to_center.cross(Vector3.UP).normalized()
	var mesh = IslandWorld.env_mesh("rocks/rock_a")
	var mi := MeshInstance3D.new()
	mi.name = "BoulderMoved"
	mi.mesh = mesh if mesh != null else Rig.sphere(1.0)
	mi.scale = Vector3.ONE * 2.0
	mi.position = p + side * 4.0
	add_child(mi)
	_static_cyl(2.0, 3.0, mi.position + Vector3(0, 1.5, 0))
	var glow := _mesh(Rig.cyl(1.4, 1.4, 0.05, 24), Color("2b2440"), p + Vector3(0, 0.03, 0), 0.9)
	glow.name = "CaveMouth"


## Gerbang benteng terbuka (kunci dipakai). animate=false saat dibangun ulang dari bendera tersimpan.
func open_gate(animate := true) -> void:
	flags[flag_gate()] = true
	if _gate_body != null and is_instance_valid(_gate_body):
		_gate_body.queue_free()
	_gate_body = null
	if _gate_mesh != null and is_instance_valid(_gate_mesh):
		var f: Dictionary = layout.fort
		# Gerbang turun masuk ke tanah (seperti pintu benteng yang diturunkan).
		var target := _gate_mesh.position - Vector3(0, float(f.wall_h), 0)
		if animate:
			var tw := create_tween()
			tw.tween_property(_gate_mesh, "position", target, 1.2)
		else:
			_gate_mesh.position = target
	for sp in spots:
		if str(sp.kind) == "gate":
			sp.text = "Gerbang terbuka"


func gate_open() -> bool:
	return _gate_body == null


func _clue(qs: Dictionary) -> void:
	var p := _v(qs.pos)
	var mesh = IslandWorld.env_mesh("rocks/rock_b")
	var mi := MeshInstance3D.new()
	mi.name = "Clue_" + str(qs.id)
	mi.mesh = mesh if mesh != null else Rig.sphere(0.8)
	mi.scale = Vector3.ONE * 1.4
	mi.position = p
	add_child(mi)
	_static_cyl(0.9, 2.0, p + Vector3(0, 1.0, 0))
	var l := _label3d("A  B  C", 64, Color("7fe0ff"), Vector3(0, 1.9, 0), mi)
	l.name = "Runes"
	_label3d(str(qs.name), 40, Color("ffd166"), Vector3(0, 2.4, 0), mi)
	spots.append({"pos": p + Vector3(0, 0, 1.4), "kind": "clue", "id": str(qs.id), "text": "AKSI: baca " + str(qs.name)})


const ITEM_COLORS := {"bibit": Color("e8c25a"), "keranjang": Color("b5743a"), "kerang": Color("ffb3c7"), "kunci_benteng": Color("f0b429")}


## Barang yang bisa dipungut: berputar & melayang, terpungut otomatis saat didekati.
func add_pickup(uid: String, item: String, pos) -> void:
	var n := Node3D.new()
	n.name = "Pickup_" + uid.replace("/", "_")
	n.position = _v(pos, 0.6)
	n.scale = Vector3.ONE * 1.6
	add_child(n)
	var col: Color = ITEM_COLORS.get(item, Color("ffd166"))
	var body: Mesh = Rig.sphere(0.22)
	match item:
		"keranjang":
			body = Rig.cyl(0.32, 0.24, 0.3, 12)
		"kunci_benteng":
			body = Rig.box(Vector3(0.14, 0.5, 0.06))
		"bibit":
			body = Rig.sphere(0.16)
	var mi := MeshInstance3D.new()
	mi.mesh = body
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.6
	mi.material_override = m
	n.add_child(mi)
	var ring := MeshInstance3D.new()
	ring.mesh = Rig.cyl(0.55, 0.55, 0.02, 24)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1, 0.9, 0.4, 0.45)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position.y = -0.55
	n.add_child(ring)
	n.set_meta("item", item)
	n.set_meta("uid", uid)
	pickups[uid] = n


func remove_pickup(uid: String) -> void:
	var n: Node3D = pickups.get(uid)
	if n != null and is_instance_valid(n):
		n.queue_free()
	pickups.erase(uid)


## Tanda di atas kepala penduduk: "!" misi baru, "?" ada urusan misi.
func set_marks(marks: Dictionary) -> void:
	for e in npcs:
		var n: Node3D = e.node
		var old := n.get_node_or_null("Mark")
		if old != null:
			old.queue_free()
			n.remove_child(old)
		var m := str(marks.get(str(e.id), ""))
		if m == "":
			continue
		var l := _label3d(m, 180, Color("ffd166") if m == "!" else Color("7fe0ff"), Vector3(0, 2.9, 0), n)
		l.outline_size = 18
		l.no_depth_test = true
		l.modulate = Color("ffcc00") if m == "!" else Color("33ccff")
		l.name = "Mark"
		l.visibility_range_end = 45.0


# --- Musuh berkeliaran (Tahap 6) -----------------------------------------------------------------------------

## f: {uid, monster, model, name, level, height, pos}
func add_foe(f: Dictionary) -> void:
	var home := _v(f.pos)
	var n := _figure(str(f.model), float(f.get("height", 1.0)), home, _rng.randf() * TAU, null, str(f.get("tint", "")))
	n.name = "Foe_" + str(f.uid)
	_label3d("%s Lv%d" % [str(f.name), int(f.get("level", 1))], 38, Color("ff8a6a"), Vector3(0, float(f.get("height", 1.0)) + 0.5, 0), n)
	foes.append({"uid": str(f.uid), "monster": str(f.monster), "node": n, "rig": n.get_meta("rig"), "home": home, "target": home,
		"wait": _rng.randf_range(0.5, 2.0), "rest": 0.0})


func foe(uid: String) -> Dictionary:
	for e in foes:
		if str(e.uid) == uid:
			return e
	return {}


func remove_foe(uid: String) -> void:
	for i in range(foes.size() - 1, -1, -1):
		if str(foes[i].uid) == uid:
			(foes[i].node as Node3D).queue_free()
			foes.remove_at(i)


## Musuh kembali ke rumahnya dan diam sebentar (setelah kabur/kalah) supaya tidak langsung menyerang lagi.
func calm_foes(sec := 5.0) -> void:
	for e in foes:
		e.rest = sec
		(e.node as Node3D).position = e.home
		e.target = e.home


func _update_foes(delta: float) -> void:
	var pp := player.global_position
	for e in foes:
		var n: Node3D = e.node
		var d := Vector2(pp.x - n.position.x, pp.z - n.position.z).length()
		var far := d > NPC_ACTIVE
		n.visible = not far
		if far:
			continue
		var speed := 0.0
		if float(e.rest) > 0.0:
			e.rest = float(e.rest) - delta
		elif not player.frozen and d < FOE_TOUCH:
			e.rest = 3.0
			interacted.emit("foe", str(e.uid))
			continue
		var tgt: Vector3 = e.target
		var h: Vector3 = e.home
		if float(e.rest) <= 0.0 and d < FOE_CHASE and Vector2(pp.x - h.x, pp.z - h.z).length() < FOE_CHASE + 4.0:
			tgt = Vector3(pp.x, 0, pp.z)
		var flat := Vector3(tgt.x - n.position.x, 0, tgt.z - n.position.z)
		if flat.length() < 0.2:
			e.wait = float(e.wait) - delta
			if float(e.wait) <= 0.0:
				var a := _rng.randf() * TAU
				e.target = Vector3(h.x + cos(a) * 3.0, 0, h.z + sin(a) * 3.0)
				e.wait = _rng.randf_range(1.5, 4.0)
		else:
			var step := minf(FOE_SPEED * delta, flat.length())
			n.position += flat.normalized() * step
			n.rotation.y = lerp_angle(n.rotation.y, atan2(flat.x, flat.z), minf(delta * 6.0, 1.0))
			speed = FOE_SPEED
		n.position.y = ground_y(n.position.x, n.position.z)
		if e.rig != null:
			e.rig.animate(delta, speed, true)


func boss_defeated() -> void:
	flags[flag_boss()] = true
	var b := find_child("Boss", true, false)
	if b != null:
		b.queue_free()
	for g in find_children("Guard", "", true, false):
		g.queue_free()
	var fl := find_child("GoblinFlag", true, false)
	if fl != null:
		(fl as MeshInstance3D).material_override = Rig.mat(Color("3fae63"))
	for i in range(spots.size() - 1, -1, -1):
		if str(spots[i].kind) == "boss":
			spots.remove_at(i)
	_focus = -1


func _academy_door() -> void:
	if not layout.has("academy_door"):
		return
	var p := _v(layout.academy_door)
	spots.append({"pos": p, "kind": "academy", "id": "akademi", "text": "AKSI: masuk Akademi Tunas"})
	var lbl := _label3d(str(layout.get("academy_name", "Akademi Tunas")), 64, Color("ffd166"), p + Vector3(0, 6.2, -2.0))
	lbl.visibility_range_end = 60.0


func _blocked(x: float, z: float, forest_ok: bool) -> bool:
	if Vector2(x, z).length() > radius - 2.5:
		return true
	if near_path(x, z, 3.5):
		return true
	if not _river.is_empty() and absf(z - float(_river.z)) < float(_river.half_width) + 2.5:
		return true
	for h in hills:
		if Vector2(x - float(h.pos[0]), z - float(h.pos[1])).length() < float(h.bottom) + 1.0:
			return true
	for sh in layout.get("shapes", []):
		if Vector2(x - float(sh.pos[0]), z - float(sh.pos[1])).length() < float(sh.r) + 2.0:
			return true
	var f: Dictionary = layout.get("fort", {})
	if not f.is_empty() and Vector2(x - float(f.pos[0]), z - float(f.pos[1])).length() < float(f.half) * 1.6 + 3.0:
		return true
	for pl in layout.get("places", []):
		if str(pl.id) == "hutan" and forest_ok:
			continue
		if Vector2(x - float(pl.pos[0]), z - float(pl.pos[1])).length() < float(pl.radius) + 1.0:
			return true
	if absf(x) < 4.0 and z > radius - 4.0:
		return true
	return false


## Hutan lebat + pohon jarang di seluruh pulau. MultiMesh per jenis (hemat draw call), batang bertabrakan.
func _forest() -> void:
	var f: Dictionary = layout.get("forest", {})
	var dense := clampi(int(int(profile.get("trees", 130)) * 0.6), 30, 130)
	var sparse := clampi(int(int(profile.get("trees", 130)) * 0.3), 15, 70)
	# [pohon hutan 1, pohon hutan 2, semak, bunga]; bisa diganti per pulau (mis. palem di pulau tropis).
	var kinds: Array = layout.get("tree_kinds", ["vegetation/tree_round", "vegetation/tree_pine", "vegetation/bush", "vegetation/flowers"])
	var xfs := {}
	for k in kinds:
		xfs[k] = []
	var trunks := 0
	var tries := 0
	var placed := 0
	var fc := Vector2(float(f.pos[0]), float(f.pos[1])) if not f.is_empty() else Vector2.ZERO
	var fr := float(f.get("radius", 0.0))
	while placed < dense + sparse and tries < (dense + sparse) * 8:
		tries += 1
		var in_forest := placed < dense and fr > 0.0
		var pt: Vector2
		if in_forest:
			var a := _rng.randf() * TAU
			pt = fc + Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * fr
		else:
			var a2 := _rng.randf() * TAU
			pt = Vector2(cos(a2), sin(a2)) * sqrt(_rng.randf()) * (radius - 3.0)
		if _blocked(pt.x, pt.y, in_forest):
			continue
		var r := _rng.randf()
		var kind: String = (kinds[1] if r < 0.55 else kinds[0]) if in_forest else (kinds[0] if r < 0.5 else (kinds[2] if r < 0.8 else kinds[3]))
		if in_forest and _rng.randf() < 0.25:
			kind = kinds[2]
		var s := _rng.randf_range(0.85, 1.4)
		var y := ground_y(pt.x, pt.y) - 0.05
		var sc := Vector3(s, s * _rng.randf_range(0.88, 1.18), s)
		(xfs[kind] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(sc), Vector3(pt.x, y, pt.y)))
		if kind in [kinds[0], kinds[1]]:
			_static_cyl(0.35, 2.0, Vector3(pt.x, y + 1.0, pt.y))
			trunks += 1
		placed += 1
	for k in xfs.keys():
		var arr: Array = xfs[k]
		var mesh = _tree_mesh(k)
		if arr.is_empty() or mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
			mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf() if _rng.randf() < 0.3 else 0.0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_" + k.get_file()
		mmi.multimesh = mm
		add_child(mmi)
	set_meta("trunks", trunks)


func tree_count() -> int:
	var n := 0
	for c in get_children():
		if c is MultiMeshInstance3D and str(c.name).begins_with("Trees_tree"):
			n += (c as MultiMeshInstance3D).multimesh.instance_count
		elif str(c.name).begins_with("Tree"):
			n += 1
	return n


# --- Penduduk -----------------------------------------------------------------------------------------------

func _npcs() -> void:
	for d in layout.get("npcs", []):
		var home := _v(d.pos)
		var n := _figure(str(d.model), float(d.get("height", 1.75)), home, _rng.randf() * TAU)
		n.name = "Npc_" + str(d.id)
		_label3d(str(d.name), 44, Color("ffd166"), Vector3(0, float(d.get("height", 1.75)) + 0.55, 0), n)
		_label3d(str(d.role), 30, Color.WHITE, Vector3(0, float(d.get("height", 1.75)) + 0.25, 0), n)
		npcs.append({"id": str(d.id), "node": n, "rig": n.get_meta("rig"), "home": home, "wander": float(d.get("wander", 0.0)),
			"target": home, "wait": _rng.randf_range(0.3, 1.5), "talking": false})
		spots.append({"pos": home, "kind": "npc", "id": str(d.id), "text": "AKSI: bicara dengan " + str(d.name), "node": n})


func npc_node(id: String) -> Node3D:
	for e in npcs:
		if str(e.id) == id:
			return e.node
	return null


func _update_npcs(delta: float) -> void:
	var pp := player.global_position
	for e in npcs:
		var n: Node3D = e.node
		var far := n.position.distance_to(pp) > NPC_ACTIVE
		n.visible = not far
		if far:
			continue
		var rig = e.rig
		var speed := 0.0
		if bool(e.talking):
			var to := pp - n.position
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(delta * 8.0, 1.0))
		elif float(e.wander) > 0.0:
			var t: Vector3 = e.target
			var flat := Vector3(t.x - n.position.x, 0, t.z - n.position.z)
			if flat.length() < 0.2:
				e.wait = float(e.wait) - delta
				if float(e.wait) <= 0.0:
					var a := _rng.randf() * TAU
					var rr := _rng.randf() * float(e.wander)
					var h: Vector3 = e.home
					e.target = Vector3(h.x + cos(a) * rr, 0, h.z + sin(a) * rr)
					e.wait = _rng.randf_range(2.0, 5.0)
			else:
				var step := minf(NPC_SPEED * delta, flat.length())
				n.position += flat.normalized() * step
				n.rotation.y = lerp_angle(n.rotation.y, atan2(flat.x, flat.z), minf(delta * 6.0, 1.0))
				speed = NPC_SPEED
			n.position.y = ground_y(n.position.x, n.position.z)
		if rig != null:
			rig.animate(delta, speed, true)
	for s in spots:
		if s.has("node"):
			s.pos = (s.node as Node3D).position


func end_talk() -> void:
	_talk_release = 0.3


## Penduduk `id` berhenti dan menghadap pemain (dipanggil saat dialog dimulai/berlanjut).
func hold_talk(id: String) -> void:
	_talk_release = -1.0
	for e in npcs:
		e.talking = str(e.id) == id


# --- Tiap bingkai ---------------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var p := player.global_position
	var on_dock := absf(p.x) <= DOCK_HALF + 0.2 and p.z >= dock_z0 - 3.0 and p.z <= dock_z1 + 1.0
	var flat := Vector2(p.x, p.z)
	var limit := radius + 4.0
	if not on_dock and flat.length() > limit:
		flat = flat.normalized() * limit
		player.global_position = Vector3(flat.x, p.y, flat.y)
	if on_dock:
		player.global_position.z = minf(p.z, dock_z1 - 0.6)
	if p.y < -3.0:
		player.place(spawn_point(), 0.0)


func _process(delta: float) -> void:
	if player == null:
		return
	if not npcs.is_empty():
		_update_npcs(delta)
	if not foes.is_empty():
		_update_foes(delta)
	if _talk_release >= 0.0:
		_talk_release -= delta
		if _talk_release < 0.0:
			for e in npcs:
				e.talking = false
	var pp3 := player.global_position
	for uid in pickups.keys():
		var pn: Node3D = pickups[uid]
		if not is_instance_valid(pn):
			continue
		pn.rotation.y += delta * 2.0
		pn.position.y = ground_y(pn.position.x, pn.position.z) + 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.1
		if Vector2(pp3.x - pn.position.x, pp3.z - pn.position.z).length() < PICK_RANGE:
			remove_pickup(uid)
			interacted.emit("pickup", uid)
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
	_place_t -= delta
	if _place_t <= 0.0 and npc_engine != null:
		_place_t = 0.4
		var now: String = npc_engine.place_at(player.global_position.x, player.global_position.z)
		if now != place:
			place = now
			place_changed.emit(now)


func focus_kind() -> String:
	return str(spots[_focus].kind) if _focus >= 0 else ""


func interact() -> bool:
	if _focus < 0:
		return false
	var s: Dictionary = spots[_focus]
	player.rig.play_once("lambai" if str(s.kind) == "npc" else "interaksi", 0.8)
	if str(s.kind) == "npc":
		hold_talk(str(s.id))
		var rig = (s.node as Node3D).get_meta("rig")
		if rig != null:
			rig.play_once("interaksi", 1.0)
	interacted.emit(str(s.kind), str(s.id))
	return true


func spot_pos(kind: String, id := "") -> Vector3:
	for s in spots:
		if str(s.kind) == kind and (id == "" or str(s.id) == id):
			return s.pos
	return Vector3.ZERO


# --- Paket visual 5.0: medan, air, jembatan, flora, suasana ------------------------------------------------

func _terrain_setup() -> void:
	var fps := []
	for o in layout.get("objects", []):
		var mesh = IslandWorld.env_mesh(str(o.asset))
		if mesh == null:
			continue
		var bb: AABB = (mesh as Mesh).get_aabb()
		var r := float(o.radius) if o.has("radius") else maxf(bb.size.x, bb.size.z) * 0.5 * float(o.get("scale", 1.0))
		fps.append([float(o.pos[0]), float(o.pos[1]), r])
	var rects := []
	var f: Dictionary = layout.get("farm", {})
	if not f.is_empty():
		rects.append([float(f.pos[0]), float(f.pos[1]), float(f.size[0]) / 2.0 + 0.8, float(f.size[1]) / 2.0 + 0.8])
	var ft: Dictionary = layout.get("fort", {})
	if not ft.is_empty():
		rects.append([float(ft.pos[0]), float(ft.pos[1]), float(ft.half) + 2.6, float(ft.half) + 2.6])
	rects.append([0.0, (dock_z0 + dock_z1) / 2.0, DOCK_HALF + 1.0, (dock_z1 - dock_z0) / 2.0 + 4.0])
	var b: Dictionary = layout.get("boulder", {})
	if not b.is_empty():
		fps.append([float(b.pos[0]), float(b.pos[1]), 1.2 * float(b.get("scale", 2.5)) + 4.5])
	for sh in layout.get("shapes", []):
		fps.append([float(sh.pos[0]), float(sh.pos[1]), float(sh.r) + 1.0])
	if layout.has("academy_door"):
		fps.append([float(layout.academy_door[0]), float(layout.academy_door[1]), 2.0])
	terrain = Terrain.new()
	terrain.setup({"radius": radius, "hills": hills, "river": _river, "paths": layout.get("paths", []),
		"places": layout.get("places", []), "footprints": fps, "rects": rects, "forest": layout.get("forest", {}),
		"seed": hash(str(island.id))})


func _terrain_ground(green: Color, sand: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = terrain.build_mesh(float(profile.get("terrain_step", 1.5)))
	mi.material_override = Nature.terrain_mat(terrain, green, sand, _col("path", C_TRAIL), _col("plaza", C_PLAZA))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = terrain.collision_shape()
	body.add_child(cs)
	add_child(body)
	var beach := Node3D.new()  # pantai kini bagian dari medan (pasir landai); simpul penanda untuk uji
	beach.name = "Beach"
	add_child(beach)
	for h in hills:
		var hn := Node3D.new()
		hn.name = "Hill_" + str(h.get("id", ""))
		hn.position = Vector3(float(h.pos[0]), float(h.height), float(h.pos[1]))
		add_child(hn)


## Sungai di alur yang menurun (medan), air beranimasi, jembatan papan dengan pagar & tiang.
func _river_terrain(z: float, hw: float, bh: float, span: float) -> void:
	var water := MeshInstance3D.new()
	water.name = "River"
	var pm := PlaneMesh.new()
	pm.size = Vector2(span, hw * 2.0 + 1.6)
	water.mesh = pm
	var wm := Nature.smat("river")
	wm.set_shader_parameter("move", 1.0 if bool(profile.get("fx", false)) else 0.0)
	water.material_override = wm
	water.position = Vector3(0, -0.2, z)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	for side in [-1.0, 1.0]:
		# Dinding tak terlihat di tepi sungai (kecuali jembatan): pemain tidak tercebur.
		var seg := (span / 2.0) - bh
		for sx in [-1.0, 1.0]:
			_static_box(Vector3(seg, 2.0, 0.4), Vector3(sx * (bh + seg / 2.0), 1.0, z + side * (hw + 0.2)))
	var L := hw * 2.0 + 2.4
	var bridge := Node3D.new()
	bridge.name = "Bridge"
	add_child(bridge)
	var n := int(L / 0.42)
	var plank := MultiMesh.new()
	plank.transform_format = MultiMesh.TRANSFORM_3D
	plank.use_colors = true
	plank.mesh = Rig.box(Vector3(bh * 2.0 + 0.3, 0.1, L / n - 0.05))
	plank.instance_count = n
	for k in n:
		var t := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.03, 0.03)), Vector3(0, 0.1 + _rng.randf_range(-0.01, 0.01), z - L / 2.0 + (k + 0.5) * L / n))
		plank.set_instance_transform(k, t)
		plank.set_instance_color(k, Color.WHITE * _rng.randf_range(0.85, 1.08))
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = plank
	var pmat: StandardMaterial3D = Rig.mat(Color("a8784a"), 0.9).duplicate()
	pmat.vertex_color_use_as_albedo = true
	pmi.material_override = pmat
	bridge.add_child(pmi)
	for sx in [-1.0, 1.0]:
		_mesh(Rig.box(Vector3(0.28, 0.3, L + 0.4)), Color("6b4a2a"), Vector3(sx * (bh - 0.2), -0.08, z), 0.9, bridge)
		_mesh(Rig.box(Vector3(0.12, 0.12, L)), Color("8a5a2b"), Vector3(sx * (bh + 0.05), 1.0, z), 0.9, bridge)
		_mesh(Rig.box(Vector3(0.08, 0.08, L)), Color("8a5a2b"), Vector3(sx * (bh + 0.05), 0.6, z), 0.9, bridge)
		for k in 5:
			var pz := z - L / 2.0 + 0.2 + k * (L - 0.4) / 4.0
			_mesh(Rig.cyl(0.09, 0.11, 1.25, 8), Color("6b4a2a"), Vector3(sx * (bh + 0.05), 0.55, pz), 0.9, bridge)
			_mesh(Rig.sphere(0.12), Color("7a5232"), Vector3(sx * (bh + 0.05), 1.18, pz), 0.9, bridge)
		_static_box(Vector3(0.25, 2.0, L), Vector3(sx * (bh + 0.05), 1.0, z))
	# Lantai jembatan setinggi tepi sungai (y = 0) supaya pemain tidak tersandung.
	_static_box(Vector3(bh * 2.0, 0.4, L), Vector3(0, -0.2, z))
	# Batu-batu sungai.
	var rock = IslandWorld.env_mesh("rocks/rock_b")
	if rock != null:
		for i in 10:
			var rx := _rng.randf_range(bh + 3.0, radius - 6.0) * (1.0 if i % 2 == 0 else -1.0)
			var rzz := z + _rng.randf_range(-hw * 0.8, hw * 0.8)
			var mi := MeshInstance3D.new()
			mi.mesh = rock
			mi.position = Vector3(rx, -0.45, rzz)
			mi.scale = Vector3.ONE * _rng.randf_range(0.35, 0.7)
			mi.rotation.y = _rng.randf() * TAU
			_far(mi)
			add_child(mi)


## Batu kecil di tepi jalan tanah (satu MultiMesh).
func _path_stones() -> void:
	var rock = IslandWorld.env_mesh("rocks/rock_a")
	if rock == null:
		return
	var xs: Array = []
	for seg in layout.get("paths", []):
		var a := Vector2(float(seg[0][0]), float(seg[0][1]))
		var b := Vector2(float(seg[1][0]), float(seg[1][1]))
		var len := a.distance_to(b)
		var dir := (b - a) / maxf(len, 0.001)
		var nrm := Vector2(-dir.y, dir.x)
		var d := 1.0
		while d < len - 1.0:
			d += _rng.randf_range(2.5, 6.0)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var p := a + dir * d + nrm * side * _rng.randf_range(1.9, 2.5)
			if terrain.splat(0, p.x, p.y) > 0.6 or terrain.splat(1, p.x, p.y) > 0.3 or terrain.splat(3, p.x, p.y) > 0.3:
				continue
			var s := _rng.randf_range(0.12, 0.28)
			xs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s)), Vector3(p.x, ground_y(p.x, p.y) - 0.04, p.y)))
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PathStones"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


static var _tree_meshes: Dictionary = {}


## Mesh pohon GLB dengan bahan shader: daun bergoyang (bila efek aktif) + variasi warna per pohon.
func _tree_mesh(k: String):
	var sway := bool(profile.get("fx", false))
	var key := k + ("|s" if sway else "")
	if _tree_meshes.has(key):
		return _tree_meshes[key]
	var src = IslandWorld.env_mesh(k)
	if src == null:
		return null
	var m: ArrayMesh = (src as ArrayMesh).duplicate()
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		var col := (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color.GREEN
		var leafy := m.surface_get_name(i).begins_with("Daun") or (col.g > col.r * 1.08 and col.g > col.b)
		m.surface_set_material(i, Nature.leaf_mat(mat, sway) if leafy else Nature.bark_mat(mat))
	_tree_meshes[key] = m
	return m


func _nature() -> void:
	if terrain == null:
		return
	var green := _col("ground", Color.from_string(str(island.get("color", "#7cc95a")), Color("7cc95a")))
	flower_spots = await Nature.plant_grass(self, terrain, green, int(profile.get("tufts", 3000)), float(profile.get("grass_far", 28.0)),
		bool(profile.get("fx", false)), hash(str(island.id)) + 5)
	if not is_inside_tree():
		return
	Nature.ambience(self, radius, profile, _col("sky_top", Color("3a7fd5")), flower_spots, hash(str(island.id)) + 9)
