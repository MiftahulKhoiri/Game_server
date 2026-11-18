extends Control
## Adegan pembuka The Last Dragon (paket adventure 1.3.0): empat potongan gambar 3D singkat sebelum layar prolog.
##
##   1. Senja damai: Aldragor terbang di atas desa.            "Dahulu Eldoria hidup damai ..."
##   2. Malam: monster dari hutan menyerbu, rumah terbakar.      "Semalam, Desa Awal diserang ..."
##   3. Malzareth mengangkat Elara dalam bola sihir ungu.        "... seorang penyihir menculik Elara"
##   4. Pahlawan berlari, penyihir lenyap dalam kabut hitam.     "Kamu berusaha melawan ..."
##
## Dunia adegan dibuat sendiri di SubViewport (World3D terpisah), jadi peta yang sedang dimuat tidak tersentuh.
## Semua dari model & bentuk yang sudah ada di paket (tanpa berkas baru). Tombol "Lewati" langsung mengakhiri.
## Selesai/lewati -> sinyal `selesai` (story.gd lalu menampilkan layar teks prolog seperti biasa).

signal selesai

const Models = preload("res://games/adventure/scripts/models.gd")
const Maps = preload("res://games/adventure/scripts/maps.gd")
const WorldBuild = preload("res://games/adventure/scripts/world_build.gd")
const Atmo = preload("res://games/adventure/scripts/atmosphere.gd")

const SHOT_TIME := 4.6
const CAPTIONS := [
	"Dahulu Eldoria hidup damai di bawah perlindungan Aldragor, naga terakhir.",
	"Semalam, monster datang dari arah hutan dan menyerbu Desa Awal.",
	"Di tengah kekacauan, penyihir Malzareth menculik Elara, putri Kepala Desa.",
	"Kamu berusaha melawan, tetapi penyihir itu menghilang dalam kabut hitam.",
]

var shot := -1                 # potongan yang sedang tampil (untuk uji)
var _vp: SubViewport
var _world: Node3D
var _env: Environment
var _cam: Camera3D
var _moon: DirectionalLight3D
var _caption: Label
var _fade: ColorRect
var _t := 0.0
var _done := false
var _dragon: Node3D
var _foes: Array = []           # [node, mulai, akhir]
var _fires: Array[OmniLight3D] = []
var _fire_nodes: Array[Node3D] = []    # api + bara: hanya saat malam
var _malz: Node3D
var _orb: Node3D
var _hero: Node3D
var _cam_from := Transform3D()
var _cam_to := Transform3D()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := SubViewportContainer.new()
	box.stretch = true
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	box.add_child(_vp)
	_build_world()
	# pita sinematik atas-bawah + teks
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 92)
		if not top:
			bar.offset_top = -150
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 32)
	_caption.add_theme_color_override("font_color", Color("f2ead8"))
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -146
	_caption.offset_left = 60
	_caption.offset_right = -60
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var skip := Button.new()
	skip.text = "Lewati"
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_size_override("font_size", 28)
	skip.custom_minimum_size = Vector2(170, 70)
	add_child(skip)
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -200
	skip.offset_top = 12
	skip.offset_right = -24
	skip.offset_bottom = 82
	skip.pressed.connect(finish)
	_go(0)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var k := clampf(_t / SHOT_TIME, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	_cam.global_transform = _cam_from.interpolate_with(_cam_to, e)
	_fade.color.a = clampf(1.0 - _t / 0.45, 0.0, 1.0) + clampf((_t - (SHOT_TIME - 0.45)) / 0.45, 0.0, 1.0)
	_animate(delta, k)
	if _t >= SHOT_TIME:
		if shot >= CAPTIONS.size() - 1:
			finish()
		else:
			_go(shot + 1)


func finish() -> void:
	if _done:
		return
	_done = true
	selesai.emit()
	queue_free()


## Mulai potongan `i`: atur suasana, aktor, kamera, dan teks.
func _go(i: int) -> void:
	shot = i
	_t = 0.0
	_caption.text = CAPTIONS[i]
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	var night := i > 0
	sky.sky_top_color = Color("101834") if night else Color("2e4f9e")
	sky.sky_horizon_color = Color("3a2a4a") if night else Color("f2a88a")
	sky.ground_horizon_color = sky.sky_horizon_color
	_env.ambient_light_color = Color("8a90c8") if night else Color("ffe0b8")
	_env.ambient_light_energy = 0.45 if night else 0.8
	_env.fog_light_color = sky.sky_horizon_color
	_moon.light_color = Color("a8b8ff") if night else Color("ffd8a0")
	_moon.light_energy = 0.35 if night else 1.0
	for f in _fire_nodes:
		f.visible = night
	_env.fog_density = 0.012 if night else 0.004
	_dragon.visible = i == 0
	for fe: Array in _foes:
		(fe[0] as Node3D).visible = i == 1
	_malz.visible = i >= 2
	_orb.visible = i >= 2
	_hero.visible = i == 3
	match i:
		0:
			_cam_from = _look(Vector3(-6, 2.2, 16), Vector3(0, 3.5, -4))
			_cam_to = _look(Vector3(4, 3.0, 15), Vector3(2, 4.5, -6))
		1:
			_cam_from = _look(Vector3(1.5, 3.4, 5.0), Vector3(0, 0.8, -12))
			_cam_to = _look(Vector3(0.5, 2.4, 2.5), Vector3(0, 0.8, -6))
		2:
			_malz.position = Vector3(1.0, 0, -1.0)
			_orb.position = Vector3(-0.6, 1.1, -1.0)
			_orb.scale = Vector3.ONE
			_cam_from = _look(Vector3(-1.5, 1.4, 4.2), Vector3(0.2, 1.3, -1.0))
			_cam_to = _look(Vector3(-0.5, 1.9, 3.0), Vector3(0.2, 1.7, -1.0))
		3:
			_hero.position = Vector3(-3.5, 0, 4.0)
			_cam_from = _look(Vector3(-5.2, 2.8, 6.4), Vector3(-0.6, 1.0, 0.0))
			_cam_to = _look(Vector3(-4.4, 3.0, 5.2), Vector3(0.0, 1.4, -0.6))


func _look(from: Vector3, to: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(to - from, Vector3.UP), from)


func _animate(delta: float, k: float) -> void:
	match shot:
		0:  # Aldragor melintas di langit senja
			_dragon.position = Vector3(-14.0 + 30.0 * k, 7.5 + sin(_t * 1.4) * 0.5, -6.0 + 3.0 * sin(k * PI))
			_dragon.rotation.y = PI * 0.5
		1:  # monster berlari dari hutan ke desa, api berkedip
			for fe: Array in _foes:
				var n := fe[0] as Node3D
				n.position = (fe[1] as Vector3).lerp(fe[2] as Vector3, k)
		2:  # bola sihir naik perlahan
			_orb.position.y = 1.1 + 1.4 * k
			_orb.rotation.y += delta * 1.5
		3:  # pahlawan berlari, penyihir & bola mengecil lalu lenyap
			_hero.position = Vector3(-3.5, 0, 4.0).lerp(Vector3(-1.2, 0, 1.2), minf(1.0, k * 1.4))
			var s := clampf(1.0 - (k - 0.35) / 0.4, 0.0, 1.0)
			_malz.scale = Vector3.ONE * maxf(0.001, s)
			_orb.scale = Vector3.ONE * maxf(0.001, s)
			_orb.position.y = 2.5 + (1.0 - s) * 1.5
	for f in _fires:
		f.light_energy = 2.2 + sin(_t * 13.0 + f.position.x) * 0.5 + sin(_t * 7.3) * 0.3


# --- dunia adegan ---

func _build_world() -> void:
	_world = Node3D.new()
	_vp.add_child(_world)
	_env = Environment.new()
	var sm := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sm
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.fog_enabled = true
	_env.fog_density = 0.02
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = _env
	_world.add_child(we)
	_moon = DirectionalLight3D.new()
	_moon.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	_moon.shadow_enabled = true
	sm.sun_angle_max = 6.0
	_world.add_child(_moon)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_world.add_child(_cam)
	_cam.make_current()
	# tanah, jalan desa, pepohonan hutan di utara
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	ground.mesh = pm
	ground.material_override = WorldBuild.mat(Color("3d6a34"))
	_world.add_child(ground)
	var jalan := MeshInstance3D.new()
	var jm := PlaneMesh.new()
	jm.size = Vector2(3.0, 40)
	jalan.mesh = jm
	jalan.material_override = WorldBuild.mat(Color("9a7a52"))
	jalan.position = Vector3(0, 0.01, -6)
	_world.add_child(jalan)
	var tree := WorldBuild._dekor_mesh(WorldBuild.TREE_SINGLE[0])
	for i in 26:
		var p := Vector3(-24.0 + i * 1.9, 0, -18.0 - 3.0 * sin(i * 1.7) - (i % 3))
		if absf(p.x) < 2.5:
			continue
		var t := MeshInstance3D.new()
		if tree != null:
			t.mesh = tree
			t.scale = Vector3.ONE * (1.6 + 0.4 * sin(i))
		else:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 1.0
			cm.height = 3.0
			t.mesh = cm
			t.material_override = WorldBuild.mat(Color("23502a"))
			t.position.y = 1.5
		t.position += p
		_world.add_child(t)
	# rumah-rumah desa (dua terbakar saat malam)
	var rumah := [Vector3(-6, 0, 0), Vector3(6, 0, -1), Vector3(-7, 0, -7), Vector3(7, 0, -8), Vector3(3.5, 0, -3.5)]
	for i in rumah.size():
		_house(rumah[i], i)
		if i == 0 or i == 3:
			_fire(rumah[i] + Vector3(0, 3.0, 0))
	# Aldragor
	_dragon = Models.create("aldragor")
	_dragon.scale *= 1.6
	_world.add_child(_dragon)
	_set_moving(_dragon, true, 3.0)
	# penyerbu dari hutan
	var kinds := ["goblin", "serigala_hutan", "goblin", "orc_penyerbu", "goblin_penyerbu", "serigala_hitam", "goblin"]
	for i in kinds.size():
		var m := Models.create(kinds[i])
		_world.add_child(m)
		var x := -4.0 + i * 1.3
		var start := Vector3(x, 0, -16.0 - (i % 3) * 1.5)
		var end := Vector3(x * 0.8, 0, -2.0 - (i % 3) * 1.2)
		m.position = start
		m.rotation.y = 0.0  # depan model = +Z (menuju desa)
		_set_moving(m, true, 3.2)
		_foes.append([m, start, end])
	# Malzareth dan Elara dalam bola sihir
	_malz = Models.create("malzareth")
	_malz.rotation.y = -PI * 0.5
	_world.add_child(_malz)
	_orb = Node3D.new()
	_world.add_child(_orb)
	var elara_def: Dictionary = {}
	for wd: Dictionary in Maps.WARGA:
		if str(wd.get("id", "")) == "elara":
			elara_def = wd
			break
	if not elara_def.is_empty():
		var el := Models.create_warga(elara_def)
		el.position = Vector3(0, -0.45, 0)
		el.rotation.y = PI * 0.15
		_orb.add_child(el)
	var bola := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.75
	sp.height = 1.5
	bola.mesh = sp
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.62, 0.3, 1.0, 0.28)
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.emission_enabled = true
	om.emission = Color("8a3aff")
	om.emission_energy_multiplier = 0.8
	om.cull_mode = BaseMaterial3D.CULL_DISABLED
	bola.material_override = om
	bola.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.add_child(bola)
	var ol := OmniLight3D.new()
	ol.light_color = Color("b070ff")
	ol.light_energy = 2.0
	ol.omni_range = 5.0
	_orb.add_child(ol)
	# pahlawan (penampilan pemain)
	var st: Dictionary = Session.player.get("state", {}) if Session.player is Dictionary else {}
	var hero_id := str(st.get("hero", "ksatria"))
	_hero = Models.create(hero_id if Models.is_hero(hero_id) else "ksatria")
	_hero.rotation.y = PI * 0.75
	_world.add_child(_hero)
	Models.dress_current(_hero)
	_set_moving(_hero, true, 3.5)


func _set_moving(n: Node, on: bool, speed: float) -> void:
	if "moving" in n:
		n.set("moving", on)
	if "move_speed" in n:
		n.set("move_speed", speed)


func _house(p: Vector3, i: int) -> void:
	var dinding := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(3.2, 2.2, 2.8)
	dinding.mesh = b
	dinding.material_override = WorldBuild.mat(Color("c8a878").darkened(0.06 * (i % 3)))
	dinding.position = p + Vector3(0, 1.1, 0)
	_world.add_child(dinding)
	var atap := MeshInstance3D.new()
	var pr := PrismMesh.new()
	pr.size = Vector3(3.8, 1.5, 3.2)
	atap.mesh = pr
	atap.material_override = WorldBuild.mat(Color("8a3a22"))
	atap.position = p + Vector3(0, 2.95, 0)
	_world.add_child(atap)
	var pintu := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.7, 1.3, 0.05)
	pintu.mesh = pb
	pintu.material_override = WorldBuild.mat(Color("5a3a1e"))
	pintu.position = p + Vector3(0, 0.65, 1.42)
	_world.add_child(pintu)


func _fire(p: Vector3) -> void:
	var grp := Node3D.new()
	_world.add_child(grp)
	_fire_nodes.append(grp)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("ffb040")
	fm.emission_enabled = true
	fm.emission = Color("ff6a10")
	fm.emission_energy_multiplier = 2.5
	for k in 4:
		var f := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.45 - k * 0.07
		s.height = s.radius * 2.6
		f.mesh = s
		f.material_override = fm
		f.position = p + Vector3((k - 1.5) * 0.45, 0.2 * (k % 2), 0)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grp.add_child(f)
	var l := OmniLight3D.new()
	l.light_color = Color("ff8a30")
	l.omni_range = 9.0
	l.position = p + Vector3(0, 0.5, 1.0)
	grp.add_child(l)
	_fires.append(l)
	var bara := Atmo.make_embers(Vector3(1.4, 0.6, 1.0), 40)
	bara.position = p
	grp.add_child(bara)
	bara.emitting = true  # setelah masuk pohon adegan (partikel dunia butuh transformasi global)
