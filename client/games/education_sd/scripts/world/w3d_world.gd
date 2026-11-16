extends Node3D
## Pulau 3D satu wilayah (Kerajaan Matematika / Hutan Bahasa / Laboratorium IPA / Negeri Penjelajah IPS).
## Dibangun dari data (ctx) yang disiapkan main.gd: topik kelas aktif, status area, ujian, peti, mini-game.
## Tata letak: alun-alun (portal, NPC, peti, kios mini-game, tempat rahasia) lalu jalan ke depan (-Z) yang
## dihalangi GERBANG / JEMBATAN RUSAK per area belajar, dan PENJAGA WILAYAH (ujian akhir) di ujung.
## Gerbang terbuka hanya bila area itu benar-benar selesai (SdProgress.area_rec(...).done) — tidak ada
## hadiah atau pintu yang terbuka hanya karena tombol ditekan. Interaksi memakai Area3D (deteksi pemain).

signal interacted(kind: String, id: String)
signal focus_changed(text: String)
signal zone_entered(kind: String, id: String)

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const Player := preload("res://games/education_sd/scripts/world/w3d_player.gd")
const Locations := preload("res://games/education_sd/scripts/world/w3d_locations.gd")
const Life := preload("res://games/education_sd/scripts/world/w3d_life.gd")
const Base := preload("res://games/education_sd/scripts/world/w3d_base.gd")
const Merge := preload("res://games/education_sd/scripts/world/w3d_merge.gd")
const Foes := preload("res://games/education_sd/scripts/world/w3d_foes.gd")

const PATH_HALF := 6.0
const HUB_HALF := 26.0
const HUB_FRONT := -7.0
const HUB_BACK := 34.0
const GATE_GAP := 13.0
const FIRST_GATE := -14.0
const PLAYER_LAYER := 2

## Profil grafis: skala render 3D, bayangan, MSAA, jumlah pohon, jarak gambar dekorasi.
const PROFILES := {
	"hemat": {"foes": 2, "rocks": 40, "grass": 120, "fog": false, "scale": 0.6, "shadow": false, "msaa": false, "trees": 60, "range": 38.0, "rain": 0, "animals": 2, "birds": 0, "fx": false, "cycle": true, "tufts": 4000, "grass_far": 18.0, "terrain_step": 2.0},
	"seimbang": {"foes": 3, "rocks": 80, "grass": 300, "fog": true, "scale": 0.8, "shadow": true, "msaa": false, "trees": 130, "range": 60.0, "rain": 250, "animals": 3, "birds": 3, "fx": true, "cycle": true, "tufts": 12000, "grass_far": 28.0, "terrain_step": 1.5},
	"tinggi": {"foes": 4, "rocks": 120, "grass": 600, "fog": true, "scale": 1.0, "shadow": true, "msaa": true, "trees": 220, "range": 95.0, "rain": 500, "animals": 5, "birds": 5, "fx": true, "cycle": true, "tufts": 20000, "grass_far": 40.0, "terrain_step": 1.0},
}

const THEMES := {
	"matematika": {"ground": "4f8a36", "path": "a07a4e", "trunk": "8a5a2b", "crown": "3f8f3f", "accent": "3f7fd8", "sky": "8cc8ff", "npc_extra": "mahkota", "boss": "Golem Angka"},
	"bahasa": {"ground": "4a8a3a", "path": "9a7a4a", "trunk": "7a4a22", "crown": "2f8f4a", "accent": "3fae63", "sky": "9ad8ff", "npc_extra": "telinga", "boss": "Burung Hantu Penjaga Kata"},
	"ipa": {"ground": "5a9a5a", "path": "7a8a96", "trunk": "6b5a4a", "crown": "4cc0a0", "accent": "2fb3a6", "sky": "a8e0ff", "npc_extra": "kacamata", "boss": "Robot Penjaga Lab"},
	"markas": {"ground": "5f9a3e", "path": "b08a5a", "trunk": "8a5a2b", "crown": "3fae63", "accent": "8a6bd8", "sky": "9ad8ff", "npc_extra": "", "boss": ""},
	"ips": {"ground": "7aa04a", "path": "a8764a", "trunk": "8a5a2b", "crown": "5aa84a", "accent": "e0813d", "sky": "ffd9a8", "npc_extra": "topi_kapten", "boss": "Penjaga Gerbang Nusantara"},
}

## Fase 5: model GLB berlisensi CC0 dari APK (KayKit) untuk NPC, warga, penjaga, dan hewan.
const NPC_GLB := {"matematika": ["ksatria", Color(1.0, 0.92, 0.65)], "bahasa": ["petani", Color(1.0, 0.85, 0.65)],
	"ipa": ["penyihir", Color(0.88, 0.82, 1.0)], "ips": ["pemanah", Color(0.75, 0.85, 1.0)]}
const VILLAGER_GLB := {"Pak Hitung": "petani", "Bu Rusa": "nenek_penjual", "Peneliti Ana": "anak_desa", "Mbok Sari": "nenek_penjual"}
const ANIMAL_GLB := [["anak_ayam", 0.55], ["babi_hutan", 0.85], ["tikus_sawah", 0.45]]
const BOSS_TINT := {"matematika": Color(0.75, 0.85, 1.0), "bahasa": Color(0.75, 1.0, 0.8), "ipa": Color(0.8, 1.0, 1.0), "ips": Color(1.0, 0.85, 0.7)}

var ctx: Dictionary = {}
var player: CharacterBody3D
var profile: Dictionary
var theme: Dictionary
var gates: Dictionary = {}  # topic_id -> {node, block: CollisionShape3D, bars: Node3D, kind}
var _near: Array[Area3D] = []
var _focus: Area3D
var _rng := RandomNumberGenerator.new()
var _end_z := 0.0
var _sun: DirectionalLight3D
var _env: Environment
var sky_day_top := Color.SKY_BLUE
var sky_day_horizon := Color.WHITE
var life: Node3D
var locs: Dictionary = {}  # loc_id -> {root, def}
var _talk_node: Node3D
var _animals := 0
var foes: Node3D
var flashlight: OmniLight3D


func build(c: Dictionary) -> void:
	ctx = c
	var rid := str(ctx.region.id)
	theme = THEMES.get(rid, THEMES.matematika)
	profile = PROFILES.get(str(ctx.get("gfx", "seimbang")), PROFILES.seimbang)
	_rng.seed = hash(rid)
	var n: int = (ctx.topics as Array).size()
	_end_z = FIRST_GATE - GATE_GAP * maxi(n - 1, 0) - 14.0
	life = Life.new()
	life.name = "Life"
	add_child(life)
	life.setup(self, profile, hash(rid))
	_environment()
	if ctx.has("base"):
		Base.build(self, ctx)
		_birds()
		_water_fx()
		_optimize()
		player = Player.new()
		player.name = "Player"
		add_child(player)
		player.setup(ctx.get("hero", {}))
		player.place(Vector3(0, 0.1, 9.0), 0.0)
		return
	_ground()
	_walls()
	_trees()
	_theme_props(rid)
	_hub()
	for i in n:
		_gate(i, ctx.topics[i])
	_boss()
	_locations()
	_items()
	_birds()
	_scatter()
	_env_props(rid)
	_landmark(rid)
	_foes()
	_water_fx()
	_optimize()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.setup(ctx.get("hero", {}))
	player.place(spawn_point(), 0.0)


# --- Lingkungan -----------------------------------------------------------------------------------

func _environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color.from_string(str(theme.sky), Color.SKY_BLUE).darkened(0.4)
	sky_mat.sky_horizon_color = Color.from_string(str(theme.sky), Color.SKY_BLUE).lightened(0.05)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color("4a90c8")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Gradasi warna petualangan (2.4.1): ACES, kontras & saturasi lebih kuat, cahaya ambien lebih rendah
	# sehingga warna tidak pucat/terlalu terang di layar HP.
	env.ambient_light_energy = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.95
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.1
	if bool(profile.get("fog", false)):
		env.fog_enabled = true
		env.fog_light_color = Color.from_string(str(theme.sky), Color.SKY_BLUE).lightened(0.4)
		env.fog_density = 0.004
		env.fog_sky_affect = 0.3
	_env = env
	sky_day_top = sky_mat.sky_top_color
	sky_day_horizon = sky_mat.sky_horizon_color
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	_sun.light_energy = 0.65
	_sun.light_color = Color(1.0, 0.93, 0.82)
	_sun.shadow_enabled = bool(profile.shadow)
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 32.0
	_sun.shadow_bias = 0.05
	add_child(_sun)


func _static_box(size: Vector3, pos: Vector3, color = null, visible_mesh := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	if visible_mesh and color != null:
		sb.add_child(Rig.part(Rig.box(size), color))
	add_child(sb)
	return sb


func _ground() -> void:
	var length := HUB_BACK - _end_z + 30.0
	var mid_z := (HUB_BACK + _end_z) / 2.0
	var g := _static_box(Vector3(100, 2, length), Vector3(0, -1, mid_z), Color.from_string(str(theme.ground), Color.GREEN))
	g.name = "Ground"
	(g.get_child(1) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sea := Rig.part(Rig.box(Vector3(300, 0.2, length + 160)), Color("4aa3df"), Vector3(0, -1.4, mid_z))
	sea.set_meta("water", true)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var path := Rig.part(Rig.box(Vector3(4.2, 0.04, HUB_FRONT - _end_z + 6.0)), Color.from_string(str(theme.path), Color.BEIGE),
		Vector3(0, 0.02, (HUB_FRONT + _end_z) / 2.0))
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(path)
	var plaza := Rig.part(Rig.cyl(7.5, 7.5, 0.04, 28), Color.from_string(str(theme.path), Color.BEIGE), Vector3(0, 0.02, 2.0))
	plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plaza)


## Pagar keliling: pemain tetap di alun-alun dan jalan; pagar terlihat sebagai semak/pagar kayu rendah.
func _walls() -> void:
	var fence := Color.from_string(str(theme.trunk), Color.SADDLE_BROWN).lightened(0.15)
	var path_len := HUB_FRONT - (_end_z - 6.0)
	var path_mid := (HUB_FRONT + _end_z - 6.0) / 2.0
	for side in [-1.0, 1.0]:
		_wall(Vector3(0.5, 3, path_len), Vector3(PATH_HALF * side, 1.5, path_mid), fence)
		_wall(Vector3(0.5, 3, HUB_BACK - HUB_FRONT), Vector3(HUB_HALF * side, 1.5, (HUB_BACK + HUB_FRONT) / 2.0), fence)
		_wall(Vector3(HUB_HALF - PATH_HALF, 3, 0.5), Vector3((HUB_HALF + PATH_HALF) / 2.0 * side, 1.5, HUB_FRONT), fence)
	_wall(Vector3(HUB_HALF * 2.0, 3, 0.5), Vector3(0, 1.5, HUB_BACK), fence)
	_wall(Vector3(PATH_HALF * 2.0, 3, 0.5), Vector3(0, 1.5, _end_z - 6.0), fence)


func _wall(size: Vector3, pos: Vector3, color: Color) -> void:
	_static_box(size, pos, null, false)
	# Tampilan: pagar rendah (0,9 m); tabrakan tetap setinggi 3 m supaya tidak bisa dilompati.
	# Semua tampilan pagar dikumpulkan di satu node supaya digabung jadi satu draw call (Fase 8).
	var fv := get_node_or_null("FenceVis") as Node3D
	if fv == null:
		fv = Node3D.new()
		fv.name = "FenceVis"
		add_child(fv)
	fv.add_child(Rig.part(Rig.box(Vector3(size.x, 0.9, size.z)), color, pos + Vector3(0, -1.05, 0)))


func _trees() -> void:
	var count := int(profile.trees)
	var trunk := MultiMesh.new()
	trunk.transform_format = MultiMesh.TRANSFORM_3D
	trunk.mesh = Rig.cyl(0.18, 0.26, 1.6, 7)
	var crown := MultiMesh.new()
	crown.transform_format = MultiMesh.TRANSFORM_3D
	crown.mesh = Rig.sphere(1.0) if str(ctx.region.id) != "ips" else Rig.cyl(0.0, 1.1, 2.2, 8)
	var xs: Array[Transform3D] = []
	var guard := 0
	while xs.size() < count and guard < count * 20:
		guard += 1
		var z := _rng.randf_range(_end_z - 10.0, HUB_BACK + 8.0)
		var inner := HUB_HALF if z > HUB_FRONT else PATH_HALF
		var x := _rng.randf_range(inner + 1.6, 46.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var s := _rng.randf_range(0.8, 1.5)
		xs.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, 0, z)))
	trunk.instance_count = xs.size()
	crown.instance_count = xs.size()
	for i in xs.size():
		var t := xs[i]
		trunk.set_instance_transform(i, t.translated_local(Vector3(0, 0.8, 0)))
		crown.set_instance_transform(i, t.translated_local(Vector3(0, 2.2, 0)))
	# Batang pohon dekat pagar diberi tabrakan statis supaya kamera (SpringArm3D) tidak menembusnya.
	for t in xs:
		var inner := HUB_HALF if t.origin.z > HUB_FRONT else PATH_HALF
		if absf(t.origin.x) < inner + 14.0:
			_static_cyl_at(self, 0.3 * t.basis.get_scale().x, 3.0, t.origin + Vector3(0, 1.5, 0))
	if _env_trees(xs):
		return
	for pair in [[trunk, theme.trunk], [crown, theme.crown]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = pair[0]
		mmi.material_override = Rig.mat(Color.from_string(str(pair[1]), Color.GREEN))
		if pair[0] == crown and bool(profile.fx):
			mmi.material_override = _sway_mat(Color.from_string(str(pair[1]), Color.GREEN))
		mmi.visibility_range_end = float(profile.range) + 30.0
		mmi.name = "Trees"
		add_child(mmi)


# --- Dekorasi tema per wilayah --------------------------------------------------------------------

func _deco(node: Node3D) -> Node3D:
	for c in node.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = float(profile.range)
	add_child(node)
	return node


func _label(text: String, size: int, color: Color, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = maxi(4, size / 6)
	l.modulate = color
	l.outline_modulate = Color("2b2440")
	l.pixel_size = 0.01
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	return l


func _block(ch: String, pos: Vector3, c: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = _rng.randf_range(-0.4, 0.4)
	n.add_child(Rig.part(Rig.box(Vector3(1, 1, 1)), c, Vector3(0, 0.5, 0)))
	var l := _label(ch, 72, Color.WHITE, true)
	l.position = Vector3(0, 1.45, 0)
	n.add_child(l)
	_deco(n)


func _theme_props(rid: String) -> void:
	var accent := Color.from_string(str(theme.accent), Color.BLUE)
	var palette := [Color("3f7fd8"), Color("e05a4f"), Color("f0b429"), Color("3fae63"), Color("8a6bd8")]
	match rid:
		"matematika":
			for i in 10:
				var z := _rng.randf_range(_end_z, HUB_FRONT)
				_block(str(_rng.randi_range(0, 9)), Vector3(_rng.randf_range(7.5, 12.0) * (1 if i % 2 == 0 else -1), 0, z), palette[i % palette.size()])
			_castle(Vector3(0, 0, _end_z - 16.0), accent)
		"bahasa":
			var letters := "ABCDEFGHIJKLMNOPRSTU"
			for i in 10:
				var z := _rng.randf_range(_end_z, HUB_FRONT)
				_block(letters[_rng.randi_range(0, letters.length() - 1)], Vector3(_rng.randf_range(7.5, 12.0) * (1 if i % 2 == 0 else -1), 0, z), palette[i % palette.size()])
			_treehouse(Vector3(32, 0, 12))
			_treehouse(Vector3(-16, 0, _end_z + 6.0))
		"ipa":
			for i in 3:
				var dome := Node3D.new()
				dome.position = Vector3(16.0 * (1 if i % 2 == 0 else -1), 0, -10.0 - i * 18.0)
				dome.add_child(Rig.part(Rig.cyl(4.0, 4.0, 2.0, 16), Color("e8eef5"), Vector3(0, 1, 0)))
				dome.add_child(Rig.part(Rig.sphere(4.0), Color("9fe3ff"), Vector3(0, 2, 0), Vector3(1, 0.7, 1)))
				_deco(dome)
			for i in 8:
				var fl := Node3D.new()
				fl.position = Vector3(_rng.randf_range(7.5, 12.0) * (1 if i % 2 == 0 else -1), 0, _rng.randf_range(_end_z, HUB_FRONT))
				fl.add_child(Rig.part(Rig.cyl(0.18, 0.18, 0.7, 8), Color("dfe8ef"), Vector3(0, 1.1, 0)))
				fl.add_child(Rig.part(Rig.sphere(0.5), palette[i % palette.size()].lightened(0.3), Vector3(0, 0.5, 0)))
				_deco(fl)
		"ips":
			for i in 6:
				var z := -6.0 - i * 14.0
				if z < _end_z:
					break
				_house(Vector3(13.0 * (1 if i % 2 == 0 else -1), 0, z - 8.0), palette[i % palette.size()])
			for i in 3:
				var boat := Node3D.new()
				boat.position = Vector3(-38.0 + i * 6.0, -1.3, 14.0 + i * 3.0)
				boat.add_child(Rig.part(Rig.box(Vector3(1.6, 0.6, 4.0)), Color("8a5a2b"), Vector3(0, 0.3, 0)))
				boat.add_child(Rig.part(Rig.cyl(0.06, 0.06, 3.0, 6), Color("5a3a1a"), Vector3(0, 1.8, 0)))
				boat.add_child(Rig.part(Rig.box(Vector3(0.05, 1.6, 1.6)), Color.WHITE, Vector3(0, 2.0, 0.2)))
				_deco(boat)


func _castle(at: Vector3, accent: Color) -> void:
	var c := Node3D.new()
	c.position = at
	c.add_child(Rig.part(Rig.box(Vector3(14, 6, 6)), Color("e8e2f2"), Vector3(0, 3, 0)))
	for x in [-7.0, 7.0, -2.5, 2.5]:
		var h := 9.0 if absf(x) > 5.0 else 11.0
		c.add_child(Rig.part(Rig.cyl(1.4, 1.4, h, 12), Color("f4efff"), Vector3(x, h / 2.0, 0)))
		c.add_child(Rig.part(Rig.cyl(0.0, 1.8, 2.6, 12), accent, Vector3(x, h + 1.3, 0)))
	# Fase 10: benteng bergerigi, gerbang lengkung, jendela, bendera.
	for k in 10:
		c.add_child(Rig.part(Rig.box(Vector3(0.8, 0.8, 6.2)), Color("e8e2f2"), Vector3(-6.3 + k * 1.4, 6.4, 0)))
	c.add_child(Rig.part(Rig.box(Vector3(3.0, 3.6, 0.3)), Color("6b4a2e"), Vector3(0, 1.8, 3.05)))
	c.add_child(Rig.part(Rig.cyl(1.5, 1.5, 0.3, 16), Color("6b4a2e"), Vector3(0, 3.6, 3.05)))
	for x in [-5.0, 5.0]:
		for y in [2.5, 4.6]:
			c.add_child(Rig.part(Rig.box(Vector3(0.8, 1.2, 0.2)), Color("8fd0ff"), Vector3(x, y, 3.05)))
	for x in [-7.0, 7.0]:
		c.add_child(Rig.part(Rig.cyl(0.05, 0.05, 2.4, 6), Color("5a3a1a"), Vector3(x, 12.6, 0)))
		c.add_child(Rig.part(Rig.box(Vector3(1.2, 0.7, 0.04)), accent, Vector3(x + 0.6, 13.4, 0)))
	var l := _label("ISTANA ANGKA", 160, Color("f0b429"))
	l.position = Vector3(0, 7.6, 3.2)
	c.add_child(l)
	add_child(c)
	_static_box_at(self, Vector3(14, 8, 6), at + Vector3(0, 4, 0), null)


func _treehouse(at: Vector3) -> void:
	var t := Node3D.new()
	t.position = at
	t.add_child(Rig.part(Rig.cyl(0.6, 0.9, 6.0, 10), Color("7a4a22"), Vector3(0, 3, 0)))
	t.add_child(Rig.part(Rig.box(Vector3(3.4, 2.2, 3.0)), Color("c98a4b"), Vector3(0, 6.2, 0)))
	var roof := PrismMesh.new()
	roof.size = Vector3(4.0, 1.6, 3.4)
	t.add_child(Rig.part(roof, Color("3fae63"), Vector3(0, 8.1, 0)))
	t.add_child(Rig.part(Rig.sphere(2.4), Color("2f8f4a"), Vector3(0, 9.5, -1.2)))
	_deco(t)


func _house(at: Vector3, c: Color) -> void:
	var h := Node3D.new()
	h.position = at
	h.add_child(Rig.part(Rig.box(Vector3(5.0, 0.6, 4.0)), Color("8a5a2b"), Vector3(0, 0.9, 0)))
	for cx in [-2.2, 2.2]:
		for cz in [-1.7, 1.7]:
			h.add_child(Rig.part(Rig.cyl(0.15, 0.15, 1.2, 6), Color("5a3a1a"), Vector3(cx, 0.6, cz)))
	h.add_child(Rig.part(Rig.box(Vector3(4.4, 2.2, 3.4)), c.lightened(0.35), Vector3(0, 2.3, 0)))
	var roof := PrismMesh.new()
	roof.size = Vector3(5.6, 2.6, 4.4)
	h.add_child(Rig.part(roof, Color("a0452e"), Vector3(0, 4.7, 0)))
	_deco(h)


# --- Alun-alun ---------------------------------------------------------------------------------------

func _hub() -> void:
	var r: Dictionary = ctx.region
	var accent := Color.from_string(str(theme.accent), Color.BLUE)
	# Portal antarwilayah
	var portal := Node3D.new()
	portal.position = Vector3(-8.5, 0, -1.0)
	portal.rotation.y = PI / 2.0
	var ring := TorusMesh.new()
	ring.inner_radius = 1.25
	ring.outer_radius = 1.6
	ring.rings = 24
	var rmi := Rig.part(ring, Color("8a6bd8"), Vector3(0, 1.8, 0))
	rmi.rotation.x = PI / 2.0
	portal.add_child(rmi)
	var glow := Rig.part(Rig.cyl(1.25, 1.25, 0.05, 20), Color("c9b2f0"), Vector3(0, 1.8, 0))
	glow.rotation.x = PI / 2.0
	portal.add_child(glow)
	var pl := _label("PORTAL PULAU", 48, Color.WHITE, true)
	pl.position = Vector3(0, 3.8, 0)
	portal.add_child(pl)
	add_child(portal)
	_interactable(portal, "portal", "", "Pindah pulau", 2.6)
	# NPC pemandu wilayah
	var npc := Node3D.new()
	npc.position = Vector3(3.5, 0, -2.5)
	npc.rotation.y = -2.6
	var rig := Rig.new()
	rig.shirt = Color.from_string(str(r.npc_color), Color.GOLD)
	rig.pants = Color.from_string(str(r.npc_color), Color.GOLD).darkened(0.4)
	rig.extra = str(theme.npc_extra)
	if str(r.id) == "bahasa":
		rig.skin = Color("c98a4b")
		rig.hair = Color("8a5a2b")
	rig.scale = Vector3.ONE * 1.15
	if NPC_GLB.has(str(r.id)):
		rig.glb_id = NPC_GLB[str(r.id)][0]
		rig.glb_tint = NPC_GLB[str(r.id)][1]
	npc.add_child(rig)
	rig.build()
	var nl := _label(str(r.npc), 64, Color.WHITE, true)
	nl.position = Vector3(0, 2.75, 0)
	npc.add_child(nl)
	add_child(npc)
	npc.set_meta("rig", rig)
	_interactable(npc, "npc", str(r.id), "Bicara dengan " + str(r.npc), 2.6)
	# Peti pengetahuan
	var chest := Node3D.new()
	chest.name = "Chest"
	chest.position = Vector3(-6.0, 0, -4.0)
	chest.rotation.y = 0.5
	chest.add_child(Rig.part(Rig.box(Vector3(1.4, 0.8, 0.9)), Color("a0622e"), Vector3(0, 0.4, 0)))
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.8, -0.45)
	lid.add_child(Rig.part(Rig.box(Vector3(1.44, 0.3, 0.94)), Color("c07a3a"), Vector3(0, 0.15, 0.45)))
	lid.add_child(Rig.part(Rig.box(Vector3(0.2, 0.22, 0.06)), Color("f0b429"), Vector3(0, 0.05, 0.93)))
	chest.add_child(lid)
	if bool(ctx.get("chest_opened", false)):
		lid.rotation.x = -1.6
		var sp := Rig.part(Rig.sphere(0.3), Color("ffe680"), Vector3(0, 1.0, 0))
		chest.add_child(sp)
	var cl := _label("PETI PENGETAHUAN", 48, Color("ffd166"), true)
	cl.position = Vector3(0, 1.9, 0)
	chest.add_child(cl)
	add_child(chest)
	_interactable(chest, "chest", str(r.id), "Buka peti", 2.2)
	# Kios mini-game
	var mg: Dictionary = ctx.get("minigame", {})
	if not mg.is_empty():
		var kiosk := Node3D.new()
		kiosk.position = Vector3(8.5, 0, 1.0)
		kiosk.rotation.y = -PI / 2.0
		kiosk.add_child(Rig.part(Rig.box(Vector3(2.6, 1.1, 1.2)), Color("e0813d"), Vector3(0, 0.55, 0)))
		for cx in [-1.2, 1.2]:
			kiosk.add_child(Rig.part(Rig.cyl(0.07, 0.07, 2.4, 6), Color("5a3a1a"), Vector3(cx, 1.2, 0.5)))
		kiosk.add_child(Rig.part(Rig.box(Vector3(3.0, 0.15, 1.6)), Color("ffd166"), Vector3(0, 2.45, 0.2)))
		var kl := _label("MINI-GAME\n" + str(mg.name), 40, Color.WHITE, true)
		kl.position = Vector3(0, 3.3, 0)
		kiosk.add_child(kl)
		add_child(kiosk)
		_interactable(kiosk, "minigame", str(mg.id), "Main " + str(mg.name), 2.4)
	# Papan petunjuk
	var sign := Node3D.new()
	sign.position = Vector3(4.6, 0, -5.4)
	sign.add_child(Rig.part(Rig.cyl(0.08, 0.08, 1.6, 6), Color("5a3a1a"), Vector3(0, 0.8, 0)))
	sign.add_child(Rig.part(Rig.box(Vector3(1.8, 0.9, 0.1)), Color("c98a4b"), Vector3(0, 1.7, 0)))
	var sl := _label(str(r.name).to_upper() + "\nKelas %d" % int(ctx.grade), 28, Color.WHITE)
	sl.position = Vector3(0, 1.7, 0.06)
	sign.add_child(sl)
	add_child(sign)
	# Tempat rahasia: di balik semak di pojok alun-alun (ada celah kecil).
	var secret := Node3D.new()
	secret.position = Vector3(-23.5, 0, 31.5)
	for i in 7:
		var a := PI * 0.25 + i * 0.22
		secret.add_child(Rig.part(Rig.sphere(0.9), Color.from_string(str(theme.crown), Color.GREEN).darkened(0.1),
			Vector3(cos(a) * 2.4, 0.6, -sin(a) * 2.4) + Vector3(1.6, 0, -1.6)))
	var star := Rig.part(Rig.sphere(0.25), Color("fff0a0"), Vector3(0, 0.7, 0))
	star.name = "Star"
	star.visible = not bool(ctx.get("found", false))
	secret.add_child(star)
	add_child(secret)
	_interactable(secret, "secret", str(r.id), "Periksa tempat tersembunyi", 1.6)


# --- Gerbang / jembatan per area ---------------------------------------------------------------------

func gate_z(i: int) -> float:
	return FIRST_GATE - GATE_GAP * i


func _gate(i: int, t: Dictionary) -> void:
	var z := gate_z(i)
	var kind := "jembatan" if i % 3 == 1 else "gerbang"
	var done: bool = t.get("done", false)
	var open: bool = t.get("open", false)
	var accent := Color.from_string(str(theme.accent), Color.BLUE)
	var root := Node3D.new()
	root.name = "Gate_" + str(t.id)
	root.position = Vector3(0, 0, z)
	add_child(root)
	var block := StaticBody3D.new()
	block.name = "Block"
	block.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(PATH_HALF * 2.0, 4.0, 0.8 if kind == "gerbang" else 3.6)
	cs.shape = bs
	cs.position.y = 2.0
	cs.disabled = done
	block.add_child(cs)
	root.add_child(block)
	var bars := Node3D.new()
	bars.name = "Bars"
	root.add_child(bars)
	if kind == "gerbang":
		for side in [-1.0, 1.0]:
			root.add_child(Rig.part(Rig.box(Vector3(1.0, 4.4, 1.0)), Color("e8e2f2"), Vector3(5.6 * side, 2.2, 0)))
			root.add_child(Rig.part(Rig.sphere(0.6), accent, Vector3(5.6 * side, 4.8, 0)))
		root.add_child(Rig.part(Rig.box(Vector3(12.2, 0.8, 1.0)), accent, Vector3(0, 4.6, 0)))
		for k in 9:
			bars.add_child(Rig.part(Rig.cyl(0.09, 0.09, 3.6, 6), Color("6b5f86"), Vector3(-4.4 + k * 1.1, 1.8, 0)))
		bars.position.y = -3.7 if done else 0.0
	else:
		var water := Rig.part(Rig.box(Vector3(PATH_HALF * 2.0 + 0.2, 0.06, 3.4)), Color("4aa3df"), Vector3(0, 0.05, 0))
		water.set_meta("water", true)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water)
		for k in 7:
			var plank := Rig.part(Rig.box(Vector3(4.2, 0.14, 0.42)), Color("b07a45"), Vector3(0, 0.18, -1.5 + k * 0.5))
			bars.add_child(plank)
		for side in [-1.0, 1.0]:
			root.add_child(Rig.part(Rig.cyl(0.12, 0.12, 1.4, 6), Color("7a4a22"), Vector3(2.3 * side, 0.7, 1.9)))
			root.add_child(Rig.part(Rig.cyl(0.12, 0.12, 1.4, 6), Color("7a4a22"), Vector3(2.3 * side, 0.7, -1.9)))
		# Jembatan rusak: papan berserakan sampai area diselesaikan.
		bars.visible = done
		if not done:
			for k in 3:
				var broken := Rig.part(Rig.box(Vector3(1.6, 0.12, 0.4)), Color("8a5a2b"), Vector3(-3.0 + k * 2.6, 0.12, 2.4 + (k % 2) * 0.4))
				broken.rotation.y = 0.5 * (k - 1)
				broken.name = "Broken%d" % k
				root.add_child(broken)
	var state_text := "SELESAI ★%d" % int(t.get("stars", 0)) if done else ("TERBUKA: jawab soal untuk membuka" if open else "TERKUNCI")
	var title := _label("%d. %s" % [i + 1, str(t.name)], 56, Color.WHITE)
	title.position = Vector3(0, 5.6 if kind == "gerbang" else 2.6, 0.55)
	root.add_child(title)
	var st := _label(state_text, 40, Color("ffd166") if open and not done else (Color("8ef0a8") if done else Color("cfc8dc")))
	st.name = "State"
	st.position = Vector3(0, 4.95 if kind == "gerbang" else 2.0, 0.55)
	root.add_child(st)
	Merge.merge(bars, [])  # jeruji/papan bergerak bersama -> satu mesh (Fase 8)
	gates[str(t.id)] = {"node": root, "block": cs, "bars": bars, "kind": kind, "done": done}
	var spot := Node3D.new()
	spot.position = Vector3(0, 0, z + (2.4 if kind == "gerbang" else 3.6))
	add_child(spot)
	_interactable(spot, "gate", str(t.id), ("Perbaiki jembatan" if kind == "jembatan" else "Buka gerbang") + ": " + str(t.name), 2.6)


## Animasi gerbang terbuka / jembatan diperbaiki (dipanggil untuk area yang baru saja selesai).
func celebrate_gate(id: String) -> void:
	if not gates.has(id):
		return
	var g: Dictionary = gates[id]
	var bars: Node3D = g.bars
	if str(g.kind) == "gerbang":
		bars.position.y = 0.0
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_property(bars, "position:y", -3.7, 1.6).set_trans(Tween.TRANS_SINE)
	else:
		bars.visible = true
		bars.scale = Vector3(1, 1, 0.01)
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_property(bars, "scale:z", 1.0, 1.2).set_trans(Tween.TRANS_BACK)
	if player != null:
		player.rig.play_once("sorak", 2.0)


func gate_blocked(id: String) -> bool:
	return gates.has(id) and not (gates[id].block as CollisionShape3D).disabled


# --- Penjaga wilayah (ujian akhir) ------------------------------------------------------------------

func _boss() -> void:
	var ex: Dictionary = ctx.get("exam", {})
	var b := Node3D.new()
	b.name = "Boss"
	b.position = Vector3(0, 0, _end_z - 2.0)
	var rig := Rig.new()
	var passed: bool = ex.get("passed", false)
	rig.shirt = Color("6b5f86") if not passed else Color("8ef0a8")
	rig.pants = Color("2b2440")
	rig.skin = Color("b9b3c9") if str(ctx.region.id) != "bahasa" else Color("c98a4b")
	rig.extra = "helm"
	rig.scale = Vector3.ONE * 1.9
	rig.glb_id = "ksatria"
	rig.glb_tint = BOSS_TINT.get(str(ctx.region.id), Color.WHITE) if not passed else Color(0.8, 1.0, 0.8)
	rig.glb_hide = ["Sword", "Badge"]
	b.add_child(rig)
	rig.build()
	if passed:
		rig.play_once("sorak", 9999.0)
	var l := _label(str(theme.boss) + ("\n(sudah kamu kalahkan!)" if passed else ("\nUJIAN AKHIR" if ex.get("open", false) else "\nselesaikan semua gerbang dulu")),
		56, Color.WHITE if not passed else Color("8ef0a8"), true)
	l.position = Vector3(0, 4.8, 0)
	b.add_child(l)
	add_child(b)
	b.set_meta("rig", rig)
	_interactable(b, "boss", str(ctx.region.id), "Tantang " + str(theme.boss), 3.6)


# --- Interaksi ------------------------------------------------------------------------------------

func _interactable(n: Node3D, kind: String, id: String, label: String, radius: float) -> Area3D:
	var a := Area3D.new()
	a.name = "Use_%s_%s" % [kind, id]
	a.collision_layer = 0
	a.collision_mask = PLAYER_LAYER
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	cs.shape = sp
	cs.position.y = 1.0
	a.add_child(cs)
	a.set_meta("kind", kind)
	a.set_meta("id", id)
	a.set_meta("label", label)
	n.add_child(a)
	a.body_entered.connect(func(b: Node3D) -> void:
		if b == player and not _near.has(a):
			_near.append(a)
			_refresh_focus())
	a.body_exited.connect(func(b: Node3D) -> void:
		if b == player:
			_near.erase(a)
			_refresh_focus())
	return a


func find_use(kind: String, id: String = "") -> Area3D:
	for a in find_children("Use_*", "Area3D", true, false):
		if str(a.get_meta("kind")) == kind and (id == "" or str(a.get_meta("id")) == id):
			return a
	return null


func _refresh_focus() -> void:
	var best: Area3D = null
	var best_d := INF
	for a in _near:
		if not is_instance_valid(a):
			continue
		var d := a.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best != _focus:
		_focus = best
		focus_changed.emit("" if best == null else str(best.get_meta("label")))


func focus_label() -> String:
	return "" if _focus == null else str(_focus.get_meta("label"))


## Tombol AKSI / tombol E: berinteraksi dengan objek terdekat.
func interact() -> bool:
	_refresh_focus()
	if _focus == null:
		return false
	var kind0 := str(_focus.get_meta("kind"))
	player.rig.play_once("lambai" if kind0 in ["npc", "villager"] else "interaksi", 1.0 if kind0 in ["npc", "villager"] else 0.7)
	var owner_node := _focus.get_parent()
	if owner_node.has_meta("rig"):
		(owner_node.get_meta("rig")).play_once("interaksi", 1.2)
	if str(_focus.get_meta("kind")) == "villager":
		_talk_node = owner_node as Node3D
		var to: Vector3 = player.global_position - (owner_node as Node3D).global_position
		(owner_node as Node3D).rotation.y = atan2(to.x, to.z)
	interacted.emit(str(_focus.get_meta("kind")), str(_focus.get_meta("id")))
	return true


## Titik muncul: di depan gerbang pertama yang belum selesai (atau di alun-alun bila belum ada yang selesai).
func spawn_point() -> Vector3:
	var topics: Array = ctx.topics
	var last_done := -1
	for i in topics.size():
		if topics[i].get("done", false):
			last_done = i
	if last_done < 0 or str(ctx.get("spawn", "")) == "hub":
		return Vector3(0, 0.1, 8.0)
	return Vector3(0, 0.1, gate_z(last_done) - 3.0)


func mark_secret_found() -> void:
	var s := find_use("secret")
	if s != null:
		var star := s.get_parent().get_node_or_null("Star")
		if star != null:
			var tw := create_tween()
			tw.tween_property(star, "position:y", 3.0, 0.8)
			tw.tween_callback(star.hide)
	player.rig.play_once("sorak", 1.5)


func open_chest_visual() -> void:
	var lid := get_node_or_null("Chest/Lid")
	if lid != null:
		create_tween().tween_property(lid, "rotation:x", -1.6, 0.8).set_trans(Tween.TRANS_BACK)


func is_talking_to(n: Node3D) -> bool:
	return n == _talk_node


func end_talk() -> void:
	_talk_node = null


# --- Fase 3: lokasi tambahan ----------------------------------------------------------------------

func _static_box_at(root: Node3D, size: Vector3, pos: Vector3, color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	if color != null:
		sb.add_child(Rig.part(Rig.box(size), color))
	root.add_child(sb)
	return sb


func _static_cyl_at(root: Node3D, r: float, h: float, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.position = pos
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	cs.shape = cy
	sb.add_child(cs)
	root.add_child(sb)
	return sb


func add_life(kind: String, node: Node3D, data: Dictionary = {}) -> void:
	life.add(kind, node, data)


func add_animal(root: Node3D, pos: Vector3, color: Color, radius: float) -> void:
	if _animals >= int(profile.animals):
		return
	var spec: Array = ANIMAL_GLB[_animals % ANIMAL_GLB.size()]
	_animals += 1
	var a: Node3D
	if Rig.has_model(spec[0]):
		var rig := Rig.new()
		rig.glb_id = spec[0]
		rig.glb_height = spec[1]
		rig.build()
		a = Node3D.new()
		a.add_child(rig)
		a.set_meta("rig", rig)
	else:
		a = Life.make_animal(color)
	a.position = pos
	root.add_child(a)
	life.add("animal", a, {"radius": radius})


func _birds() -> void:
	for i in int(profile.birds):
		var b: Node3D = Life.make_bird([Color("f4efe6"), Color("3f7fd8"), Color("e05a4f"), Color("f0b429"), Color("2b2440")][i % 5])
		b.position = Vector3(_rng.randf_range(-15, 15), 11.0 + i * 1.5, _rng.randf_range(-10, 20))
		add_child(b)
		life.add("bird", b, {"radius": _rng.randf_range(8.0, 16.0), "speed": _rng.randf_range(0.25, 0.45)})


func _locations() -> void:
	var rid := str(ctx.region.id)
	var defs: Array = Locations.for_region(rid)
	var accent := Color.from_string(str(theme.accent), Color.BLUE)
	var crown := Color.from_string(str(theme.crown), Color.GREEN)
	var status: Dictionary = ctx.get("locs", {})
	for i in mini(defs.size(), Locations.SLOTS.size()):
		var def: Dictionary = defs[i]
		var root := Node3D.new()
		root.name = "Loc_" + str(def.id)
		root.position = Locations.SLOTS[i]
		# Bangunan menghadap ke tengah alun-alun.
		var face := Vector3(0, 0, 8) - root.position
		root.rotation.y = atan2(face.x, face.z)
		add_child(root)
		var board: Vector3 = Locations.build(self, root, def, accent, crown)
		var done: bool = status.get(str(def.id), {}).get("done", false)
		var sign := Node3D.new()
		sign.position = board
		sign.add_child(Rig.part(Rig.cyl(0.07, 0.07, 1.3, 6), Color("5a3a1a"), Vector3(0, 0.65, 0)))
		sign.add_child(Rig.part(Rig.box(Vector3(1.1, 0.8, 0.12)), Color("8fe0a8") if done else Color("ffd166"), Vector3(0, 1.5, 0)))
		var q := _label("✓" if done else "?", 72, Color.WHITE)
		q.position = Vector3(0, 1.5, 0.08)
		sign.add_child(q)
		root.add_child(sign)
		var title := _label(str(def.name), 56, Color.WHITE, true)
		title.position = board + Vector3(0, 2.6, 0)
		root.add_child(title)
		_interactable(sign, "loc", str(def.id), str(def.name), 2.0)
		_zone(root, "visit", str(def.id), 7.5)
		if def.has("villager"):
			_villager(root, def, board)
		for c in root.find_children("*", "GeometryInstance3D", true, false):
			if (c as GeometryInstance3D).visibility_range_end == 0.0 and not c is Label3D:
				(c as GeometryInstance3D).visibility_range_end = float(profile.range) + 25.0
		locs[str(def.id)] = {"root": root, "def": def, "board": board}


func _villager(root: Node3D, def: Dictionary, board: Vector3) -> void:
	var v := Node3D.new()
	v.name = "Villager"
	v.position = board + Vector3(-2.0, 0, 0.5)
	var rig := Rig.new()
	rig.shirt = Color.from_string(str(theme.accent), Color.BLUE).lightened(0.3)
	rig.pants = Color("5a3a1a")
	rig.skin = Color("e0b08a")
	rig.hair = Color("2b2440")
	rig.long_hair = str(def.villager).begins_with("Bu") or str(def.villager).begins_with("Mbok") or str(def.villager).ends_with("Ana")
	rig.glb_id = VILLAGER_GLB.get(str(def.villager), "")
	rig.glb_height = 1.75
	v.add_child(rig)
	rig.build()
	var l := _label(str(def.villager), 48, Color("ffd166"), true)
	l.position.y = 2.5
	v.add_child(l)
	root.add_child(v)
	v.set_meta("rig", rig)
	_interactable(v, "villager", str(def.id), "Bicara dengan " + str(def.villager), 2.2)
	var pts := [v.position, v.position + Vector3(-3.0, 0, -1.5), v.position + Vector3(-1.0, 0, -3.5)]
	life.add("villager", v, {"rig": rig, "points": pts})


## Zona kunjungan / benda yang bisa diambil: terpicu saat pemain masuk (tidak perlu tombol).
func _zone(n: Node3D, kind: String, id: String, radius: float) -> Area3D:
	var a := Area3D.new()
	a.name = "Zone_%s_%s" % [kind, id]
	a.collision_layer = 0
	a.collision_mask = PLAYER_LAYER
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	cs.shape = sp
	cs.position.y = 1.0
	a.add_child(cs)
	n.add_child(a)
	a.body_entered.connect(func(b: Node3D) -> void:
		if b == player:
			zone_entered.emit(kind, id))
	return a


const ITEM_NAMES := {"matematika": "Bintang Angka", "bahasa": "Gulungan Huruf", "ipa": "Kristal Ilmu", "ips": "Artefak Kuno"}
const ITEM_SPOTS := [Vector3(12, 0, 13), Vector3(-10, 0, 22), Vector3(23, 0, -4), Vector3(-4.5, 0, -20.5), Vector3(9.0, 0, 31)]


func _items() -> void:
	var got: Array = ctx.get("items", [])
	var rid := str(ctx.region.id)
	for i in ITEM_SPOTS.size():
		var id := "%s_%d" % [rid, i]
		if got.has(id):
			continue
		var it := Node3D.new()
		it.name = "Item_" + id
		it.position = ITEM_SPOTS[i] + Vector3(0, 0.9, 0)
		match rid:
			"matematika":
				it.add_child(Rig.part(Rig.sphere(0.32), Color("f0b429"), Vector3.ZERO))
				var l := _label(str(i * 2 + 1), 48, Color.WHITE, true)
				it.add_child(l)
			"bahasa":
				var sc := Rig.part(Rig.cyl(0.18, 0.18, 0.8, 8), Color("fff3c4"), Vector3.ZERO)
				sc.rotation.z = PI / 2.0
				it.add_child(sc)
			"ipa":
				it.add_child(Rig.part(Rig.cyl(0.0, 0.3, 0.7, 6), Color("7ee0ff"), Vector3(0, 0.2, 0)))
				it.add_child(Rig.part(Rig.cyl(0.3, 0.0, 0.4, 6), Color("7ee0ff"), Vector3(0, -0.35, 0)))
			_:
				it.add_child(Rig.part(Rig.sphere(0.3), Color("c0703a"), Vector3.ZERO, Vector3(1, 1.2, 1)))
				it.add_child(Rig.part(Rig.cyl(0.12, 0.18, 0.3, 8), Color("c0703a"), Vector3(0, 0.4, 0)))
		add_child(it)
		life.add("bob", it)
		_zone(it, "item", id, 1.3)


func remove_item(id: String) -> void:
	var it := get_node_or_null("Item_" + id)
	if it != null:
		var tw := create_tween()
		tw.tween_property(it, "scale", Vector3.ONE * 0.01, 0.4)
		tw.tween_callback(it.queue_free)
	player.rig.play_once("sorak", 1.0)


func item_count() -> int:
	return find_children("Item_*", "Node3D", false, false).size()


func set_loc_done(id: String) -> void:
	if not locs.has(id):
		return
	player.rig.play_once("sorak", 1.5)


# --- Efek visual ringan (profil Seimbang/Tinggi) ----------------------------------------------------

func _sway_mat(c: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform vec4 albedo : source_color;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 1.3 + wp.x * 0.3 + wp.z * 0.2) * 0.07 * max(VERTEX.y + 0.5, 0.0);
	VERTEX.x += s;
	VERTEX.z += s * 0.5;
}
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", c)
	return m


func _water_mat(c: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform vec4 albedo : source_color;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float w = sin(wp.x * 0.9 + TIME * 1.6) * sin(wp.z * 0.7 - TIME * 1.2);
	ALBEDO = albedo.rgb + vec3(0.08, 0.1, 0.12) * smoothstep(0.55, 0.95, w);
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", c)
	return m


func _water_fx() -> void:
	if not bool(profile.fx):
		return
	var cache := {}
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("water"):
			var base: Color = (mi.material_override as StandardMaterial3D).albedo_color if mi.material_override is StandardMaterial3D else Color("4aa3df")
			if not cache.has(base):
				cache[base] = _water_mat(base)
			mi.material_override = cache[base]


## Fase 8: gabungkan mesh statis per bangunan/lokasi/gerbang (lihat w3d_merge.gd). Node yang dianimasikan
## oleh Life dilewati. merged_count dipakai uji & info kinerja.
var merged_count := 0


func _optimize() -> void:
	var skip: Array = []
	for e in life.entities:
		skip.append(e.node)
	for n in ["Chest/Lid", "Bars"]:
		pass
	for c in get_children():
		if c == life or c is WorldEnvironment or c is DirectionalLight3D or c == player:
			continue
		if not c is Node3D:
			continue
		var extra: Array = skip.duplicate()
		var lid := c.get_node_or_null("Lid")
		if lid != null:
			extra.append(lid)
		var bars := c.get_node_or_null("Bars")
		if bars != null:
			extra.append(bars)
		var star := c.get_node_or_null("Star")
		if star != null:
			extra.append(star)
		var rng_end := float(profile.range) + 25.0 if str(c.name).begins_with("Loc_") else 0.0
		merged_count += Merge.merge(c, extra, rng_end)


# --- 2.3.0: lingkungan lebih kaya, landmark, pengacau, alat ------------------------------------------

## Batu, rumpun rumput, dan bunga dengan MultiMesh (satu draw call per jenis), jumlah mengikuti profil.
func _scatter() -> void:
	var rock_mesh = env_mesh("rocks/rock_a")
	var specs := [
		["rocks", rock_mesh if rock_mesh != null else Rig.sphere(0.6), Color("9a948a"), Vector3.ONE * 0.8 if rock_mesh != null else Vector3(1.0, 0.55, 0.85), 0.0 if rock_mesh != null else 0.15],
		["grass", Rig.cyl(0.0, 0.12, 0.45, 5), Color.from_string(str(theme.crown), Color.GREEN).darkened(0.15), Vector3.ONE, 0.22],
		["grass", Rig.sphere(0.09), Color("ffd166"), Vector3.ONE, 0.35],
	]
	for i in specs.size():
		var spec: Array = specs[i]
		var count := int(profile.get(spec[0], 0)) / (2 if i == 2 else 1)
		if count <= 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[1]
		mm.instance_count = count
		for k in count:
			var z := _rng.randf_range(_end_z - 8.0, HUB_BACK - 1.0)
			var inner := HUB_HALF if z > HUB_FRONT else PATH_HALF
			var x := _rng.randf_range(-inner + 0.8, inner - 0.8) if _rng.randf() < 0.55 else _rng.randf_range(inner + 1.0, inner + 14.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			if absf(x) < 2.6 and z < HUB_FRONT:
				x = 3.4 * signf(x + 0.01)
			var s := _rng.randf_range(0.6, 1.4)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled((spec[3] as Vector3) * s)
			mm.set_instance_transform(k, Transform3D(b, Vector3(x, float(spec[4]) * s, z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter%d" % i
		mmi.multimesh = mm
		if not (spec[1] is ArrayMesh):
			mmi.material_override = Rig.mat(spec[2])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if i > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = float(profile.range)
		add_child(mmi)


## Landmark tinggi di ujung jalan (terlihat dari alun-alun) sebagai penunjuk arah ke Penjaga Wilayah.
func _landmark(rid: String) -> void:
	var at := Vector3(0, 0, _end_z - 16.0)
	var n := Node3D.new()
	n.name = "Landmark"
	n.position = at
	match rid:
		"bahasa":
			n.add_child(Rig.part(Rig.cyl(1.8, 2.8, 16.0, 12), Color("7a4a22"), Vector3(0, 8, 0)))
			for pt in [Vector3(0, 18, 0), Vector3(-4, 15.5, 1), Vector3(4, 16, -1), Vector3(0, 15, 3.5)]:
				n.add_child(Rig.part(Rig.sphere(5.0), Color.from_string(str(theme.crown), Color.GREEN), pt))
			var l := _label("POHON BAHASA RAKSASA", 140, Color("ffd166"), true)
			l.position.y = 24.0
			n.add_child(l)
		"ipa" when env_mesh("buildings/observatory") != null:
			var ob := MeshInstance3D.new()
			ob.mesh = env_mesh("buildings/observatory")
			n.add_child(ob)
			var l := _label("OBSERVATORIUM", 140, Color("ffd166"), true)
			l.position.y = 19.0
			n.add_child(l)
		"ips" when env_mesh("buildings/lighthouse") != null:
			var lh := MeshInstance3D.new()
			lh.mesh = env_mesh("buildings/lighthouse")
			n.add_child(lh)
			var l := _label("MERCUSUAR NUSANTARA", 140, Color("ffd166"), true)
			l.position.y = 23.5
			n.add_child(l)
		"ipa":
			n.add_child(Rig.part(Rig.cyl(3.0, 3.6, 12.0, 16), Color("e8eef5"), Vector3(0, 6, 0)))
			n.add_child(Rig.part(Rig.sphere(3.6), Color("9fe3ff"), Vector3(0, 12, 0)))
			var tele := Rig.part(Rig.cyl(0.5, 0.7, 5.0, 10), Color("6b5f86"), Vector3(1.5, 14.5, 0))
			tele.rotation.z = -0.8
			n.add_child(tele)
			var l := _label("OBSERVATORIUM", 140, Color("ffd166"), true)
			l.position.y = 19.0
			n.add_child(l)
		"ips":
			for k in 6:
				n.add_child(Rig.part(Rig.cyl(1.6 - k * 0.12, 1.72 - k * 0.12, 3.0, 14), Color("e05a4f") if k % 2 == 0 else Color.WHITE, Vector3(0, 1.5 + k * 3.0, 0)))
			var lamp := Rig.part(Rig.sphere(1.0), Color("ffd166"), Vector3(0, 19.3, 0))
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color("ffd166")
			lm.emission_enabled = true
			lm.emission = Color("ffb020")
			lamp.material_override = lm
			n.add_child(lamp)
			var l := _label("MERCUSUAR NUSANTARA", 140, Color("ffd166"), true)
			l.position.y = 22.0
			n.add_child(l)
		_:
			return  # Kerajaan Matematika sudah punya Istana Angka.
	add_child(n)


func _foes() -> void:
	foes = Foes.new()
	foes.name = "Foes"
	add_child(foes)
	foes.setup(self, hash(str(ctx.region.id)) + 7)
	var tint := Color.from_string(str(theme.accent), Color.BLUE).lightened(0.35)
	var spots := [Vector3(14, 0, 12), Vector3(-12, 0, 27), Vector3(0, 0, gate_z(0) - 6.0), Vector3(0, 0, gate_z(1) - 6.0)]
	for i in mini(int(profile.foes), spots.size()):
		if spots[i].z < _end_z + 4.0:
			continue
		foes.spawn(spots[i], Vector3(3.0, 0, 0) if i >= 2 else Vector3(2.5, 0, 2.0), tint)
	var ex: Dictionary = ctx.get("exam", {})
	var b := get_node_or_null("Boss")
	if b != null:
		foes.set_boss(b, b.get_meta("rig"), bool(ex.get("open", false)) and not bool(ex.get("passed", false)))


## Efek alat yang sedang dipakai (w3d_items.gd).
func apply_tool(id: String) -> void:
	match id:
		"senter":
			flashlight = OmniLight3D.new()
			flashlight.name = "Senter"
			flashlight.position = Vector3(0, 1.3, 0.4)
			flashlight.omni_range = 9.0
			flashlight.light_color = Color("fff3c4")
			flashlight.shadow_enabled = false
			player.add_child(flashlight)
		"kaca_pembesar":
			for it in find_children("Item_*", "Node3D", false, false):
				(it as Node3D).scale = Vector3.ONE * 1.8
				var glow: Label3D = _label("✦", 96, Color("ffe680"), true)
				glow.position.y = 0.8
				it.add_child(glow)
		"teropong":
			player.zoom_max = 12.0
		"sepatu":
			player.speed_bonus = 1.15


func _process(_delta: float) -> void:
	if flashlight != null and life != null:
		flashlight.light_energy = lerpf(1.6, 0.25, life.day_factor)


# --- Fase 10: aset lingkungan GLB buatan sendiri (tools/gamepack/sd_props.gd) --------------------------

const ENV_DIR := "res://games/education_sd/assets/environment/"
static var _env_cache: Dictionary = {}


## Mesh dari GLB lingkungan (dengan material bawaannya), atau null bila berkas tidak ada (pakai primitif).
static func env_mesh(name: String):
	if _env_cache.has(name):
		return _env_cache[name]
	var path := ENV_DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		path = ENV_DIR + name + ".gltf"  # aset KayKit (CC0): .gltf + .bin + satu atlas tekstur bersama
	var mesh = null
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		if mis.size() > 1:
			mesh = _merge_meshes(inst, mis)  # mis. kincir angin: badan + baling-baling jadi satu mesh
		elif mis.size() > 0:
			mesh = (mis[0] as MeshInstance3D).mesh
			for s in (mesh as Mesh).get_surface_count():
				var mat := (mesh as Mesh).surface_get_material(s) as BaseMaterial3D
				if mat != null and mat.metallic < 0.3:
					mat.metallic_specular = 0.12
		inst.free()
	_env_cache[name] = mesh
	return mesh


## Gabungkan beberapa MeshInstance3D (dengan transformasinya terhadap akar) menjadi satu ArrayMesh,
## satu permukaan per bahan.
static func _merge_meshes(root: Node, mis: Array) -> ArrayMesh:
	var by_mat := {}
	var mats := {}
	for mi: MeshInstance3D in mis:
		var xf := Transform3D()
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var key := mat.get_instance_id() if mat != null else 0
			if not by_mat.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[key] = st
				mats[key] = mat
			(by_mat[key] as SurfaceTool).append_from(mi.mesh, s, xf)
	var out := ArrayMesh.new()
	for key in by_mat:
		var st: SurfaceTool = by_mat[key]
		st.set_material(mats[key])
		out = st.commit(out)
	return out


const TREE_SETS := {"matematika": ["tree_round"], "bahasa": ["tree_round", "tree_pine"], "ipa": ["tree_round", "tree_pine"],
	"ips": ["tree_palm", "tree_pine"], "markas": ["tree_round"]}


## Pohon GLB per tema (MultiMesh per jenis). Daun tetap bergoyang (shader) di profil Seimbang/Tinggi.
func _env_trees(xs: Array[Transform3D]) -> bool:
	var kinds: Array = TREE_SETS.get(str(ctx.region.id), ["tree_round"])
	if str(ctx.get("gfx", "")) == "hemat":
		kinds = ["tree_palm"] if str(ctx.region.id) == "ips" else ["tree_pine"]
	var meshes: Array = []
	for k in kinds:
		var mesh = env_mesh("vegetation/" + k)
		if mesh == null:
			return false
		if bool(profile.fx):
			mesh = (mesh as ArrayMesh).duplicate()
			for s in (mesh as ArrayMesh).get_surface_count():
				var nm := (mesh as ArrayMesh).surface_get_name(s)
				if nm.begins_with("Daun"):
					var src := (mesh as ArrayMesh).surface_get_material(s) as BaseMaterial3D
					(mesh as ArrayMesh).surface_set_material(s, _sway_mat(src.albedo_color if src != null else Color.GREEN))
		meshes.append(mesh)
	var buckets: Array = []
	for k in meshes:
		buckets.append([])
	for i in xs.size():
		var t: Transform3D = xs[i]
		buckets[i % meshes.size()].append(Transform3D(t.basis.rotated(Vector3.UP, i * 1.7) * 0.85, t.origin))
	for b in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[b]
		mm.instance_count = buckets[b].size()
		for i in buckets[b].size():
			mm.set_instance_transform(i, buckets[b][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees"
		mmi.multimesh = mm
		mmi.visibility_range_end = float(profile.range) + 30.0
		add_child(mmi)
	return true


## Objek pendidikan & perabot: patung simbol matematika, buku besar, mikroskop, globe, papan informasi
## (berisi fakta kartu pengetahuan, bisa dibaca dengan AKSI), lampu jalan; semak & bunga MultiMesh;
## batu besar bertabrakan. Semua berkas GLB buatan sendiri; bila tidak ada, bagian itu dilewati.
func _env_props(rid: String) -> void:
	var cards: Array = ctx.get("facts", [])
	var edu := {"matematika": "educational/math_statue", "bahasa": "educational/big_book", "ipa": "educational/microscope", "ips": "educational/globe"}
	var edu_mesh = env_mesh(str(edu.get(rid, "")))
	var n: int = (ctx.topics as Array).size()
	var symbols := ["+", "−", "×", "÷", "=", "<", ">", "%", "√"]
	var path_props := Node3D.new()
	path_props.name = "PathProps"
	add_child(path_props)
	for i in n:
		var z := gate_z(i) + 4.5
		if edu_mesh != null:
			var e := MeshInstance3D.new()
			e.name = "Edu%d" % i
			e.mesh = edu_mesh
			e.position = Vector3(-4.6, 0, z)
			e.rotation.y = PI / 2.0
			path_props.add_child(e)
			_static_box_at(self, Vector3(1.0, 1.6, 1.0), Vector3(-4.6, 0.8, z), null)
			if rid == "matematika":
				var sl := _label(symbols[i % symbols.size()], 120, Color("d9a83a"), true)
				sl.position = Vector3(-4.6, 2.3, z)
				add_child(sl)
		var lamp = env_mesh("props/lamp_post")
		if lamp != null:
			for x in [-5.5, 5.5]:
				var lp := MeshInstance3D.new()
				lp.mesh = lamp
				lp.position = Vector3(x, 0, gate_z(i) + 9.0)
				path_props.add_child(lp)
	var board = env_mesh("educational/info_board")
	if board != null:
		var spots := [[Vector3(-3.5, 0, -5.8), 0.0], [Vector3(10.5, 0, 12.0), -PI / 2.0]]
		for i in spots.size():
			var b := Node3D.new()
			b.name = "Info%d" % i
			b.position = spots[i][0]
			b.rotation.y = spots[i][1]
			var bm := MeshInstance3D.new()
			bm.mesh = board
			b.add_child(bm)
			var fact: Dictionary = cards[i % cards.size()] if not cards.is_empty() else {"title": str(ctx.region.name), "fact": ""}
			var t := _label("%s\n%s" % [str(fact.title), str(fact.fact).left(90) + ("…" if str(fact.fact).length() > 90 else "")], 22, Color("2b2440"))
			t.outline_size = 0
			t.width = 270.0
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t.position = Vector3(0, 1.45, 0.06)
			t.pixel_size = 0.0055
			b.add_child(t)
			add_child(b)
			_static_box_at(self, Vector3(1.8, 2.2, 0.3), b.position + Vector3(0, 1.1, 0), null)
			_interactable(b, "info", str(i), "Baca papan: " + str(fact.title), 2.0)
	var bush = env_mesh("vegetation/bush")
	var flowers = env_mesh("vegetation/flowers")
	for pair in [[bush, int(profile.get("grass", 0)) / 8], [flowers, int(profile.get("grass", 0)) / 10 if bool(profile.fx) else 0]]:
		if pair[0] == null or int(pair[1]) <= 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = int(pair[1])
		for k in int(pair[1]):
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var z := _rng.randf_range(_end_z, HUB_BACK - 2.0)
			var inner := HUB_HALF if z > HUB_FRONT else PATH_HALF
			var x := (inner - _rng.randf_range(0.6, 1.4)) * side if _rng.randf() < 0.6 else _rng.randf_range(inner + 1.0, inner + 10.0) * side
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), Vector3(x, 0, z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Bushes" if pair[0] == bush else "Flowers"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = float(profile.range)
		add_child(mmi)
	var rock = env_mesh("rocks/rock_b")
	if rock != null:
		for k in 6:
			var side := 1.0 if k % 2 == 0 else -1.0
			var at := Vector3(side * _rng.randf_range(HUB_HALF + 2.0, HUB_HALF + 8.0), 0, _rng.randf_range(-4.0, HUB_BACK)) if k < 3 \
				else Vector3(side * _rng.randf_range(PATH_HALF + 2.0, PATH_HALF + 6.0), 0, _rng.randf_range(_end_z, HUB_FRONT))
			var s := _rng.randf_range(1.8, 2.8)
			var r := MeshInstance3D.new()
			r.name = "BigRock%d" % k
			r.mesh = rock
			r.position = at
			r.scale = Vector3.ONE * s
			r.rotation.y = _rng.randf() * TAU
			r.visibility_range_end = float(profile.range) + 20.0
			add_child(r)
			var sb := _static_cyl_at(self, 0.55 * s, 1.1 * s, at + Vector3(0, 0.55 * s, 0))
			sb.name = "BigRockBody%d" % k
