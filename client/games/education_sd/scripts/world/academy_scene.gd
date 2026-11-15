extends Node3D
## Bagian dalam Akademi Tunas (3D): aula dengan ruang-ruang kelas per mata pelajaran. Setiap ruang punya
## karpet berwarna, papan tulis bernama, meja, dan guru. Ruang yang belum dibuka (Pancasila, Seni, PJOK)
## berupa pintu tertutup. Pintu selatan kembali ke pulau. Antarmuka sama dengan island_scene untuk HUD.

signal interacted(kind: String, id: String)
signal focus_changed(text: String)
signal place_changed(id: String)

const Player := preload("res://games/education_sd/scripts/world/w3d_player.gd")
const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const IslandWorld := preload("res://games/education_sd/scripts/world/w3d_world.gd")
const Learning := preload("res://games/education_sd/scripts/engine/learning_engine.gd")

const HX := 18.0  # setengah lebar aula (x)
const HZ := 14.0  # setengah panjang aula (z)
const WALL_H := 5.2
const FOCUS_RANGE := 2.9

## Letak ruang: posisi guru, arah papan (dinding), warna dari Learning.ROOMS.
const LAYOUT := {
	"matematika": {"pos": Vector3(-10, 0, -9), "board": "north"},
	"bahasa": {"pos": Vector3(10, 0, -9), "board": "north"},
	"ipas_alam": {"pos": Vector3(-13, 0, 4), "board": "west"},
	"ipas_sosial": {"pos": Vector3(13, 0, 4), "board": "east"},
	"pancasila": {"door": Vector3(-9, 0, HZ), "face": PI},
	"seni": {"door": Vector3(9, 0, HZ), "face": PI},
	"olahraga": {"door": Vector3(0, 0, -HZ), "face": 0.0},
}

var player: CharacterBody3D
var spots: Array = []
var teachers: Dictionary = {}  # room_id -> Node3D
var profile: Dictionary
var _focus := -1
var _talking := ""
var _release := -1.0


func build(c: Dictionary) -> void:
	profile = IslandWorld.PROFILES.get(str(c.get("gfx", "seimbang")), IslandWorld.PROFILES.seimbang)
	_environment()
	_hall()
	for r in Learning.ROOMS:
		var lay: Dictionary = LAYOUT.get(str(r.id), {})
		if lay.is_empty():
			continue
		if str(r.region) != "":
			_classroom(r, lay)
		else:
			_closed_door(r, lay)
	_exit_door()
	_decor()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.setup(c.get("hero", {}))
	player.zoom_max = 5.0
	player.place(spawn_point(), 0.0)


func spawn_point() -> Vector3:
	return Vector3(0, 0.15, HZ - 2.5)


func ground_y(_x: float, _z: float) -> float:
	return 0.0


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b2440")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff3e0")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.1, 0.4, 0)
	sun.light_energy = 0.55
	sun.shadow_enabled = bool(profile.get("shadow", false))
	add_child(sun)


func _mesh(mesh: Mesh, col: Color, pos: Vector3, rough := 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Rig.mat(col, rough)
	mi.position = pos
	add_child(mi)
	return mi


func _box_solid(size: Vector3, pos: Vector3, col: Color, rot_y := 0.0) -> MeshInstance3D:
	var mi := _mesh(Rig.box(size), col, pos)
	mi.rotation.y = rot_y
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.transform = Transform3D(Basis(Vector3.UP, rot_y), pos)
	add_child(body)
	return mi


func _label(text: String, size: int, col: Color, pos: Vector3, rot_y := 0.0, billboard := false, parent: Node = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 10
	l.modulate = col
	l.outline_modulate = Color("2b2440")
	l.pixel_size = 0.006
	l.position = pos
	l.rotation.y = rot_y
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	(parent if parent != null else self).add_child(l)
	return l


func _hall() -> void:
	var floor := _box_solid(Vector3(HX * 2.0, 0.4, HZ * 2.0), Vector3(0, -0.2, 0), Color("a8743f"))
	floor.name = "Floor"
	# Garis papan lantai.
	for i in range(-int(HX), int(HX) + 1, 2):
		_mesh(Rig.box(Vector3(0.05, 0.01, HZ * 2.0)), Color("a87a48"), Vector3(i, 0.005, 0))
	var wall_col := Color("e8c99a")
	_box_solid(Vector3(HX * 2.0, WALL_H, 0.5), Vector3(0, WALL_H / 2.0, -HZ - 0.25), wall_col).name = "WallN"
	_box_solid(Vector3(0.5, WALL_H, HZ * 2.0), Vector3(-HX - 0.25, WALL_H / 2.0, 0), wall_col)
	_box_solid(Vector3(0.5, WALL_H, HZ * 2.0), Vector3(HX + 0.25, WALL_H / 2.0, 0), wall_col)
	_box_solid(Vector3(HX * 2.0, WALL_H, 0.5), Vector3(0, WALL_H / 2.0, HZ + 0.25), wall_col)
	var ceil := _mesh(Rig.box(Vector3(HX * 2.0 + 1.0, 0.3, HZ * 2.0 + 1.0)), Color("fdf6e3"), Vector3(0, WALL_H + 0.15, 0))
	ceil.name = "Ceiling"
	ceil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lis bawah dinding & pilar.
	for x in [-HX + 0.4, HX - 0.4]:
		for z in [-HZ + 0.4, 0.0, HZ - 0.4]:
			_mesh(Rig.box(Vector3(0.7, WALL_H, 0.7)), Color("b5443a"), Vector3(x, WALL_H / 2.0, z))
	_label("AKADEMI TUNAS", 110, Color("ffd166"), Vector3(0, 4.3, -HZ + 0.05))


func _classroom(r: Dictionary, lay: Dictionary) -> void:
	var col := Color.from_string(str(r.color), Color.CORNFLOWER_BLUE)
	var base: Vector3 = lay.pos
	var carpet := _mesh(Rig.box(Vector3(7.5, 0.03, 6.5)), col.lightened(0.35), base + Vector3(0, 0.02, 0))
	carpet.name = "Carpet_" + str(r.id)
	var board_pos: Vector3
	var yaw := 0.0
	match str(lay.board):
		"north":
			board_pos = Vector3(base.x, 2.3, -HZ + 0.1)
			yaw = 0.0
		"west":
			board_pos = Vector3(-HX + 0.1, 2.3, base.z)
			yaw = PI / 2.0
		"east":
			board_pos = Vector3(HX - 0.1, 2.3, base.z)
			yaw = -PI / 2.0
	var frame := _mesh(Rig.box(Vector3(5.2, 2.6, 0.12)), Color("7a4a22"), board_pos)
	frame.rotation.y = yaw
	var board := _mesh(Rig.box(Vector3(4.8, 2.2, 0.14)), Color("2f5d46"), board_pos)
	board.rotation.y = yaw
	board.name = "Board_" + str(r.id)
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
	var title := _label(str(r.name), 64, Color.WHITE, board_pos + fwd * 0.09 + Vector3(0, 0.45, 0), yaw)
	title.outline_modulate = Color("1d3a2c")
	title.pixel_size = 0.0072
	var sub := _label(str(r.subject), 48, Color("ffd166"), board_pos + fwd * 0.09 + Vector3(0, -0.4, 0), yaw)
	sub.pixel_size = 0.0075
	# Meja murid.
	var desk_c := board_pos + fwd * 4.6
	desk_c.y = 0
	var side := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
	for k in [-1.6, 1.6]:
		var dp: Vector3 = desk_c + side * float(k)
		_box_solid(Vector3(1.6, 0.75, 0.9), dp + Vector3(0, 0.375, 0), Color("a0764a"), yaw)
	# Guru di depan papan, menghadap murid.
	var t := Node3D.new()
	t.name = "Teacher_" + str(r.id)
	var tp := board_pos + fwd * 1.6
	tp.y = 0
	t.position = tp
	t.rotation.y = yaw
	var rig := Rig.new()
	rig.glb_id = str(r.get("model", "warga_ibu"))
	rig.glb_height = 1.75
	t.add_child(rig)
	add_child(t)
	rig.build()
	t.set_meta("rig", rig)
	_label(str(r.teacher), 44, Color("ffd166"), Vector3(0, 2.3, 0), 0.0, true, t)
	_label("Guru " + str(r.subject), 30, Color.WHITE, Vector3(0, 2.0, 0), 0.0, true, t)
	teachers[str(r.id)] = t
	spots.append({"pos": tp + fwd * 0.8, "kind": "teacher", "id": str(r.id), "text": "AKSI: belajar dengan " + str(r.teacher), "node": t})


func _closed_door(r: Dictionary, lay: Dictionary) -> void:
	var p: Vector3 = lay.door
	var face := float(lay.face)
	var inward := Basis(Vector3.UP, face) * Vector3(0, 0, 1)
	var dp := p + inward * 0.2
	var door := _mesh(Rig.box(Vector3(2.2, 3.2, 0.2)), Color.from_string(str(r.color), Color.GRAY).darkened(0.25), dp + Vector3(0, 1.6, 0))
	door.rotation.y = face
	door.name = "Door_" + str(r.id)
	_mesh(Rig.sphere(0.12), Color("f0b429"), dp + inward * 0.15 + Vector3(0.7, 1.5, 0))
	_label(str(r.name), 40, Color.WHITE, dp + inward * 0.2 + Vector3(0, 3.6, 0), face).pixel_size = 0.009
	_label("Segera dibuka", 30, Color("ffd166"), dp + inward * 0.2 + Vector3(0, 2.2, 0), face).pixel_size = 0.009
	spots.append({"pos": p + inward * 1.2, "kind": "closed", "id": str(r.id), "text": "AKSI: lihat " + str(r.name)})


func _exit_door() -> void:
	var p := Vector3(0, 0, HZ)
	var door := _mesh(Rig.box(Vector3(2.8, 3.6, 0.2)), Color("7a4a22"), p + Vector3(0, 1.8, -0.2))
	door.name = "ExitDoor"
	_label("Keluar", 48, Color("ffd166"), p + Vector3(0, 4.0, -0.35), PI)
	spots.append({"pos": p + Vector3(0, 0, -1.4), "kind": "exit", "id": "pulau", "text": "AKSI: keluar ke pulau"})


func _decor() -> void:
	var items := [["educational/globe", Vector3(-4, 0, 6)], ["educational/big_book", Vector3(4, 0, 6)],
		["educational/math_statue", Vector3(-16, 0, -12)], ["educational/microscope", Vector3(-16, 0, 9)],
		["educational/info_board", Vector3(16, 0, 9.5)]]
	for it in items:
		var mesh = IslandWorld.env_mesh(str(it[0]))
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = it[1]
		add_child(mi)
	# Rak buku di dinding selatan.
	for x in [-15.0, -4.5, 4.5, 15.0]:
		_box_solid(Vector3(2.6, 2.2, 0.6), Vector3(x, 1.1, HZ - 0.35), Color("8a5a2b"))
		for k in 3:
			for b in 5:
				_mesh(Rig.box(Vector3(0.3, 0.5, 0.4)), Color.from_hsv(fmod(x * 0.13 + b * 0.19 + k * 0.07, 1.0), 0.55, 0.85),
					Vector3(x - 1.0 + b * 0.5, 0.45 + k * 0.7, HZ - 0.55))


func teacher_node(room_id: String) -> Node3D:
	return teachers.get(room_id)


func hold_talk(room_id: String) -> void:
	_talking = room_id
	_release = -1.0


func end_talk() -> void:
	_release = 0.3


func _physics_process(_delta: float) -> void:
	if player != null and player.global_position.y < -3.0:
		player.place(spawn_point(), 0.0)


func _process(delta: float) -> void:
	if player == null:
		return
	for id in teachers:
		var t: Node3D = teachers[id]
		var rig = t.get_meta("rig")
		if id == _talking:
			var to := player.global_position - t.position
			t.rotation.y = lerp_angle(t.rotation.y, atan2(to.x, to.z), minf(delta * 8.0, 1.0))
		if rig != null:
			rig.animate(delta, 0.0, true)
	if _release >= 0.0:
		_release -= delta
		if _release < 0.0:
			_talking = ""
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
	var s: Dictionary = spots[_focus]
	player.rig.play_once("lambai" if str(s.kind) == "teacher" else "interaksi", 0.8)
	if str(s.kind) == "teacher":
		hold_talk(str(s.id))
	interacted.emit(str(s.kind), str(s.id))
	return true


func spot_pos(kind: String, id := "") -> Vector3:
	for s in spots:
		if str(s.kind) == kind and (id == "" or str(s.id) == id):
			return s.pos
	return Vector3.ZERO
