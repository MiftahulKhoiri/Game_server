extends Node3D
## Pulau 3D satu wilayah (Kerajaan Matematika / Hutan Bahasa / Laboratorium IPA / Negeri Penjelajah IPS).
## Dibangun dari data (ctx) yang disiapkan main.gd: topik kelas aktif, status area, ujian, peti, mini-game.
## Tata letak: alun-alun (portal, NPC, peti, kios mini-game, tempat rahasia) lalu jalan ke depan (-Z) yang
## dihalangi GERBANG / JEMBATAN RUSAK per area belajar, dan PENJAGA WILAYAH (ujian akhir) di ujung.
## Gerbang terbuka hanya bila area itu benar-benar selesai (SdProgress.area_rec(...).done) — tidak ada
## hadiah atau pintu yang terbuka hanya karena tombol ditekan. Interaksi memakai Area3D (deteksi pemain).

signal interacted(kind: String, id: String)
signal focus_changed(text: String)

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const Player := preload("res://games/education_sd/scripts/world/w3d_player.gd")

const PATH_HALF := 6.0
const HUB_HALF := 11.0
const HUB_FRONT := -7.0
const HUB_BACK := 11.0
const GATE_GAP := 13.0
const FIRST_GATE := -14.0
const PLAYER_LAYER := 2

## Profil grafis: skala render 3D, bayangan, MSAA, jumlah pohon, jarak gambar dekorasi.
const PROFILES := {
	"hemat": {"scale": 0.6, "shadow": false, "msaa": false, "trees": 50, "range": 38.0},
	"seimbang": {"scale": 0.8, "shadow": true, "msaa": false, "trees": 110, "range": 60.0},
	"tinggi": {"scale": 1.0, "shadow": true, "msaa": true, "trees": 180, "range": 95.0},
}

const THEMES := {
	"matematika": {"ground": "8fd16a", "path": "e9c47e", "trunk": "8a5a2b", "crown": "3fae63", "accent": "3f7fd8", "sky": "8cc8ff", "npc_extra": "mahkota", "boss": "Golem Angka"},
	"bahasa": {"ground": "6fbf5a", "path": "c9a46a", "trunk": "7a4a22", "crown": "2f8f4a", "accent": "3fae63", "sky": "9ad8ff", "npc_extra": "telinga", "boss": "Burung Hantu Penjaga Kata"},
	"ipa": {"ground": "9ad99a", "path": "b9cfe0", "trunk": "6b5a4a", "crown": "4cc0a0", "accent": "2fb3a6", "sky": "a8e0ff", "npc_extra": "kacamata", "boss": "Robot Penjaga Lab"},
	"ips": {"ground": "a7d46f", "path": "d9a46a", "trunk": "8a5a2b", "crown": "5aa84a", "accent": "e0813d", "sky": "ffd9a8", "npc_extra": "topi_kapten", "boss": "Penjaga Gerbang Nusantara"},
}

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


func build(c: Dictionary) -> void:
	ctx = c
	var rid := str(ctx.region.id)
	theme = THEMES.get(rid, THEMES.matematika)
	profile = PROFILES.get(str(ctx.get("gfx", "seimbang")), PROFILES.seimbang)
	_rng.seed = hash(rid)
	var n: int = (ctx.topics as Array).size()
	_end_z = FIRST_GATE - GATE_GAP * maxi(n - 1, 0) - 14.0
	_environment()
	_ground()
	_walls()
	_trees()
	_theme_props(rid)
	_hub()
	for i in n:
		_gate(i, ctx.topics[i])
	_boss()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.setup(ctx.get("hero", {}))
	player.place(spawn_point(), 0.0)


# --- Lingkungan -----------------------------------------------------------------------------------

func _environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color.from_string(str(theme.sky), Color.SKY_BLUE).darkened(0.15)
	sky_mat.sky_horizon_color = Color.from_string(str(theme.sky), Color.SKY_BLUE).lightened(0.35)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color("4a90c8")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	_sun.light_energy = 0.95
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
	var g := _static_box(Vector3(70, 2, length), Vector3(0, -1, mid_z), Color.from_string(str(theme.ground), Color.GREEN))
	g.name = "Ground"
	(g.get_child(1) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sea := Rig.part(Rig.box(Vector3(260, 0.2, length + 160)), Color("4aa3df"), Vector3(0, -1.4, mid_z))
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
	var sb := _static_box(size, pos, null, false)
	# Tampilan: pagar rendah (0,9 m); tabrakan tetap setinggi 3 m supaya tidak bisa dilompati.
	var vis := Rig.part(Rig.box(Vector3(size.x, 0.9, size.z)), color, Vector3(0, -1.05, 0))
	sb.add_child(vis)


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
		var x := _rng.randf_range(inner + 1.6, 30.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var s := _rng.randf_range(0.8, 1.5)
		xs.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, 0, z)))
	trunk.instance_count = xs.size()
	crown.instance_count = xs.size()
	for i in xs.size():
		var t := xs[i]
		trunk.set_instance_transform(i, t.translated_local(Vector3(0, 0.8, 0)))
		crown.set_instance_transform(i, t.translated_local(Vector3(0, 2.2, 0)))
	for pair in [[trunk, theme.trunk], [crown, theme.crown]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = pair[0]
		mmi.material_override = Rig.mat(Color.from_string(str(pair[1]), Color.GREEN))
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
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	return l


func _block(ch: String, pos: Vector3, c: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = _rng.randf_range(-0.4, 0.4)
	n.add_child(Rig.part(Rig.box(Vector3(1, 1, 1)), c, Vector3(0, 0.5, 0)))
	for f in [0.0, PI]:
		var l := _label(ch, 72, Color.WHITE)
		l.position = Vector3(0, 0.5, 0.51 * (1.0 if f == 0.0 else -1.0))
		l.rotation.y = f
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
			_treehouse(Vector3(15, 0, 3))
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
			var lake := Rig.part(Rig.cyl(9.0, 9.0, 0.06, 24), Color("5ab8e8"), Vector3(-20, 0.03, 6))
			add_child(lake)
		"ips":
			for i in 6:
				var z := -6.0 - i * 14.0
				if z < _end_z:
					break
				_house(Vector3(13.0 * (1 if i % 2 == 0 else -1), 0, z), palette[i % palette.size()])
			for i in 3:
				var boat := Node3D.new()
				boat.position = Vector3(-38.0 + i * 6.0, -1.3, 14.0 + i * 3.0)
				boat.add_child(Rig.part(Rig.box(Vector3(1.6, 0.6, 4.0)), Color("8a5a2b"), Vector3(0, 0.3, 0)))
				boat.add_child(Rig.part(Rig.cyl(0.06, 0.06, 3.0, 6), Color("5a3a1a"), Vector3(0, 1.8, 0)))
				boat.add_child(Rig.part(Rig.box(Vector3(0.05, 1.6, 1.6)), Color.WHITE, Vector3(0, 2.0, 0.2)))
				_deco(boat)
			for i in 3:
				var stall := Node3D.new()
				stall.position = Vector3(16.0, 0, 8.0 - i * 4.0)
				stall.add_child(Rig.part(Rig.box(Vector3(2.6, 1.0, 1.4)), Color("c98a4b"), Vector3(0, 0.5, 0)))
				stall.add_child(Rig.part(Rig.box(Vector3(3.0, 0.12, 1.8)), palette[i], Vector3(0, 2.2, 0)))
				for cx in [-1.3, 1.3]:
					stall.add_child(Rig.part(Rig.cyl(0.06, 0.06, 2.2, 6), Color("5a3a1a"), Vector3(cx, 1.1, 0.6)))
				_deco(stall)


func _castle(at: Vector3, accent: Color) -> void:
	var c := Node3D.new()
	c.position = at
	c.add_child(Rig.part(Rig.box(Vector3(14, 6, 6)), Color("e8e2f2"), Vector3(0, 3, 0)))
	for x in [-7.0, 7.0, -2.5, 2.5]:
		var h := 9.0 if absf(x) > 5.0 else 11.0
		c.add_child(Rig.part(Rig.cyl(1.4, 1.4, h, 12), Color("f4efff"), Vector3(x, h / 2.0, 0)))
		c.add_child(Rig.part(Rig.cyl(0.0, 1.8, 2.6, 12), accent, Vector3(x, h + 1.3, 0)))
	var l := _label("ISTANA ANGKA", 160, Color("f0b429"))
	l.position = Vector3(0, 7.2, 3.1)
	c.add_child(l)
	add_child(c)


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
	secret.position = Vector3(-9.3, 0, 9.3)
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
	player.rig.play_once("interaksi", 0.7)
	var owner_node := _focus.get_parent()
	if owner_node.has_meta("rig"):
		(owner_node.get_meta("rig")).play_once("interaksi", 1.2)
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
