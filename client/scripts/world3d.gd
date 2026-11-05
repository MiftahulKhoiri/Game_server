extends Node3D
## Dunia 3D: jalan bebas dengan joystick layar, kamera di belakang pemain (geser layar
## untuk memutar). Peta, pintu, pertemuan musuh, NPC, dan penyimpanan memakai aturan
## yang sama dengan peta petak lama; posisi halus (fx, fz, yaw) ikut disimpan ke server.

const Maps = preload("res://scripts/maps.gd")
const Movement = preload("res://scripts/movement.gd")
const WorldBuild = preload("res://scripts/world_build.gd")
const Models = preload("res://scripts/models.gd")
const Joystick = preload("res://scripts/joystick.gd")

const SPEED := 3.3  # petak per detik
const SAVE_DELAY := 1.5
const RETRY_DELAY := 5.0
const ENCOUNTER_CHANCE := 0.18  # peluang bertemu musuh tiap "langkah" (1 petak jalan) di ladang
const TALK_RANGE := 1.5
const CAM_DIST := 6.4
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const INVENTORY_SCENE := "res://scenes/inventory.tscn"
const DIALOG_SCENE := "res://scenes/dialog.tscn"

var _map_id := Maps.DEFAULT_MAP
var _pos := Vector2(5.5, 5.5)  # (x, z) di dunia
var _yaw := 0.0  # arah hadap pemain
var _cam_yaw := 0.0
var _cam_pitch := 0.62
var _tile := Vector2i(-1, -1)
var _step_acc := 0.0
var _unsaved := false
var _saving := false
var _locked := false  # sedang pindah layar (pertarungan, toko, dialog)

var _terrain: Node3D
var _npc_root: Node3D
var _player: Node3D
var _camera: Camera3D
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _save_timer: Timer

var _joy: Control
var _cam_finger := -1
var _hud: Label
var _status: Label
var _toast: Label
var _talk_button: Button
var _buttons: Array[Button] = []


func _ready() -> void:
	if Session.player.is_empty():
		Session.use_offline_player()  # dijalankan langsung dari editor

	_env = WorldEnvironment.new()
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.far = 90.0
	add_child(_camera)
	_camera.current = true

	_player = Models.create("ksatria")
	add_child(_player)
	_add_shadow(_player, 0.3)

	var st: Dictionary = Session.player.state
	var map_id := str(st.map)
	if Maps.rows(map_id).is_empty():
		map_id = Maps.DEFAULT_MAP
		st.x = Maps.SPAWN.x
		st.y = Maps.SPAWN.y
		st.fx = 0.0
		st.fz = 0.0
	_load_map(map_id)
	var start := Vector2(float(st.fx), float(st.fz))
	if start == Vector2.ZERO or Movement.tile_of(start) != Vector2i(int(st.x), int(st.y)):
		start = Vector2(int(st.x), int(st.y)) + Vector2(0.5, 0.5)
	if Movement.collides(_map_id, start):
		start = Movement.safe_spot(_map_id, Movement.tile_of(start))
	_pos = start
	_yaw = float(st.yaw)
	_tile = Movement.tile_of(_pos)
	_sync_state()

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)

	_build_ui()
	_refresh_hud()
	_apply_transform()
	_set_status("Mode uji (tidak disimpan)" if Session.offline else "Tersimpan")
	if not Session.offline:
		_resume_battle_if_any()  # mis. aplikasi ditutup di tengah pertarungan


func _notification(what: int) -> void:
	# Simpan seketika saat aplikasi dijeda atau ditutup (best-effort).
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _unsaved and not _saving:
			_save()


# --- peta ---

func _load_map(map_id: String) -> void:
	_map_id = map_id
	if _terrain != null:
		_terrain.queue_free()
	if _npc_root != null:
		_npc_root.queue_free()
	_terrain = WorldBuild.build(map_id)
	add_child(_terrain)
	_npc_root = Node3D.new()
	_npc_root.name = "NPC"
	add_child(_npc_root)
	for id: String in Maps.NPCS:
		var n: Dictionary = Maps.NPCS[id]
		if n.map != map_id:
			continue
		var model := Models.create(id)
		model.position = Vector3(n.pos.x + 0.5, 0.0, n.pos.y + 0.5)
		_npc_root.add_child(model)
		_add_shadow(model, 0.3)
		var label := Label3D.new()
		label.text = str(n.name)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.006
		label.font_size = 40
		label.outline_size = 10
		label.position = model.position + Vector3(0, 1.25, 0)
		_npc_root.add_child(label)
	_env.environment = WorldBuild.environment_for(map_id)
	_sun.light_energy = WorldBuild.light_energy_for(map_id)


func _add_shadow(parent: Node3D, radius: float) -> void:
	var disc := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.01
	m.radial_segments = 12
	disc.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0, 0.32)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.position.y = 0.02
	disc.scale = Vector3.ONE / parent.scale.x  # model sudah diskalakan; bayangan tetap berukuran dunia
	parent.add_child(disc)


## Pindah ke peta lain; posisi baru disimpan seperti gerakan biasa.
func _go_to_map(map_id: String, at: Vector2i) -> void:
	var st: Dictionary = Session.player.state
	st.map = map_id
	_load_map(map_id)
	_pos = Movement.safe_spot(map_id, at)
	_tile = Movement.tile_of(_pos)
	_step_acc = 0.0
	_sync_state()
	_mark_dirty()
	_apply_transform()
	_update_talk_button()
	_show_toast(str(Maps.NAMES.get(map_id, map_id)))
	_set_status("Memasuki %s" % Maps.NAMES.get(map_id, map_id))


# --- per bingkai ---

func _process(delta: float) -> void:
	var rig := _player as Node
	if _locked:
		_set_moving(false)
		return
	var input := _input_vector()
	var moved := 0.0
	if input.length() > 0.08:
		var fwd := Vector2(-sin(_cam_yaw), -cos(_cam_yaw))
		var right := Vector2(cos(_cam_yaw), -sin(_cam_yaw))
		var dir := fwd * input.y + right * input.x
		if dir.length() > 1.0:
			dir = dir.normalized()
		var np := Movement.move(_map_id, _pos, dir * SPEED * delta)
		moved = (np - _pos).length()
		_pos = np
		if dir.length() > 0.05:
			_yaw = lerp_angle(_yaw, atan2(dir.x, dir.y), minf(1.0, delta * 14.0))
	_set_moving(moved > 0.0001)
	if rig != null:
		_apply_transform()
	if moved > 0.0001:
		_sync_state()
		_mark_dirty()
		_after_step(moved)


func _set_moving(v: bool) -> void:
	if "moving" in _player:
		_player.moving = v


func _apply_transform() -> void:
	_player.position = Vector3(_pos.x, 0.0, _pos.y)
	_player.rotation.y = _yaw
	var target := Vector3(_pos.x, 0.8, _pos.y)
	var offset := Vector3(sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch)) * CAM_DIST
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)
	_update_talk_button()


## Menyalin posisi ke data pemain (yang dikirim ke server saat menyimpan).
func _sync_state() -> void:
	var st: Dictionary = Session.player.state
	var t := Movement.tile_of(_pos)
	st.map = _map_id
	st.x = t.x
	st.y = t.y
	st.fx = _pos.x
	st.fz = _pos.y
	st.yaw = _yaw


func _mark_dirty() -> void:
	_unsaved = true
	if _save_timer != null:
		_save_timer.start(SAVE_DELAY)


## Dipanggil tiap kali pemain bergerak sejauh `moved` petak.
func _after_step(moved: float) -> void:
	var t := Movement.tile_of(_pos)
	if t != _tile:
		_tile = t
		var ex := Maps.exit_at(_map_id, t.x, t.y)
		if not ex.is_empty():
			_go_to_map(str(ex.to), ex.at)
			return
		if not Session.offline and Maps.tile_at(_map_id, t.x, t.y) == Maps.BOSS_TILE:
			_start_encounter(true)
			return
	if Session.offline or _locked:
		return
	var tile := Maps.tile_at(_map_id, _tile.x, _tile.y)
	if tile == "" or not Maps.ENCOUNTER_TILES.contains(tile):
		return  # pertemuan hanya terjadi di ladang / kerikil
	_step_acc += moved
	while _step_acc >= 1.0:
		_step_acc -= 1.0
		if Session.safe_steps > 0:
			Session.safe_steps -= 1
		elif randf() < ENCOUNTER_CHANCE:
			_start_encounter()
			return


# --- masukan ---

func _input_vector() -> Vector2:
	var v := Vector2.ZERO
	if _joy != null:
		v = _joy.vec  # x kanan, y bawah layar
		v.y = -v.y  # y positif = maju
	var k := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)))
	if k != Vector2.ZERO:
		v = k
	if Input.is_physical_key_pressed(KEY_Q):
		_cam_yaw -= 0.03
	if Input.is_physical_key_pressed(KEY_E):
		_cam_yaw += 0.03
	return v


func _input(event: InputEvent) -> void:
	if _locked:
		return
	# Geser layar (di luar joystick dan tombol) untuk memutar kamera.
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			if _cam_finger < 0 and not _on_ui(te.position):
				_cam_finger = te.index
		elif te.index == _cam_finger:
			_cam_finger = -1
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == _cam_finger:
			_rotate_camera(de.relative)
	elif event is InputEventMouseMotion:
		var me := event as InputEventMouseMotion
		if me.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_rotate_camera(me.relative)


func _rotate_camera(rel: Vector2) -> void:
	_cam_yaw -= rel.x * 0.008
	_cam_pitch = clampf(_cam_pitch + rel.y * 0.004, 0.3, 1.15)


func _on_ui(p: Vector2) -> bool:
	if _joy != null and _joy.get_global_rect().has_point(p):
		return true
	for b in _buttons:
		if b.get_global_rect().has_point(p):
			return true
	return false


# --- pertarungan, NPC, layar lain ---

func _start_encounter(boss := false) -> void:
	_locked = true
	_set_status("Sesuatu menyambutmu di singgasana..." if boss else "Sesuatu bergerak di sekitarmu...")
	await _flush_save()  # posisi harus tersimpan dulu; server tidak ikut gerak kita
	var res: Dictionary = await Api.battle_start(boss)
	if res.ok:
		_enter_battle(res.data)
	elif res.status == 409:
		# Sudah ada pertarungan di server: lanjutkan yang itu.
		if not await _resume_battle_if_any():
			_locked = false
	else:
		_locked = false
		_set_status(str(res.error))


## Mengembalikan true bila ada pertarungan berjalan dan layar pindah ke sana.
func _resume_battle_if_any() -> bool:
	var res: Dictionary = await Api.battle_get()
	if not res.ok:
		return false
	_locked = true
	_enter_battle(res.data)
	return true


func _enter_battle(data: Dictionary) -> void:
	Session.merge_server_player(data.player)
	var battle: Variant = data.get("battle")
	Session.battle = battle if battle is Dictionary else {}
	get_tree().change_scene_to_file(BATTLE_SCENE)


## id NPC terdekat dalam jangkauan bicara, atau "".
func _npc_in_range() -> String:
	var best := ""
	var best_d := TALK_RANGE
	for id: String in Maps.NPCS:
		var n: Dictionary = Maps.NPCS[id]
		if n.map != _map_id:
			continue
		var d := _pos.distance_to(Vector2(n.pos) + Vector2(0.5, 0.5))
		if d <= best_d:
			best_d = d
			best = id
	return best


func _update_talk_button() -> void:
	if _talk_button != null:
		_talk_button.disabled = Session.offline or _npc_in_range() == ""


func _talk() -> void:
	var npc := _npc_in_range()
	if npc == "" or _locked:
		return
	_locked = true
	Session.talk_npc = npc
	await _flush_save()  # versi pemain harus sinkron sebelum hadiah diambil
	get_tree().change_scene_to_file(DIALOG_SCENE)


## Pindah ke layar lain (toko, tas) setelah menyimpan posisi: versi pemain harus
## sinkron dengan server sebelum bertransaksi.
func _open_screen(scene: String) -> void:
	if _locked:
		return
	_locked = true
	await _flush_save()
	get_tree().change_scene_to_file(scene)


func _flush_save() -> void:
	_save_timer.stop()
	while _saving:
		await get_tree().process_frame
	if _unsaved:
		await _save()


# --- simpan ke server ---

func _save() -> void:
	if Session.offline:
		return
	if _saving:
		_save_timer.start(SAVE_DELAY)
		return
	_saving = true
	_unsaved = false
	_set_status("Menyimpan...")

	var res: Dictionary = await Api.save(Session.player.version, Session.player.state)
	if not res.ok and res.status == 409:
		# Versi di server berbeda (mis. main dari perangkat lain): ikuti versi server,
		# lalu simpan ulang keadaan lokal.
		var me: Dictionary = await Api.get_me()
		if me.ok:
			Session.player.version = int(me.data.version)
			res = await Api.save(Session.player.version, Session.player.state)

	_saving = false
	if res.ok:
		Session.player.version = int(res.data.version)
		_set_status("Tersimpan")
		if _unsaved:  # ada gerakan baru saat menyimpan
			_save_timer.start(SAVE_DELAY)
	elif res.status == 426:
		# Aplikasi terlalu lama untuk server: percuma mengulang, pemain harus update.
		_unsaved = true
		_set_status(str(res.error))
	else:
		_unsaved = true
		_set_status("Gagal menyimpan: %s (coba lagi...)" % res.error)
		_save_timer.start(RETRY_DELAY)


# --- tampilan ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_hud = Label.new()
	_hud.position = Vector2(20, 16)
	_hud.add_theme_font_size_override("font_size", 28)
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 8)
	layer.add_child(_hud)

	_status = Label.new()
	_status.position = Vector2(20, 130)
	_status.size = Vector2(420, 60)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_status.add_theme_constant_override("outline_size", 6)
	layer.add_child(_status)

	_toast = Label.new()
	_toast.position = Vector2(0, 260)
	_toast.size = Vector2(720, 80)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 44)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 12)
	_toast.modulate.a = 0.0
	layer.add_child(_toast)

	_joy = Joystick.new()
	_joy.position = Vector2(20, 880)
	_joy.size = Vector2(420, 380)
	layer.add_child(_joy)

	_talk_button = _add_button(layer, "Bicara", 0, _talk)
	_add_button(layer, "Tas", 1, _open_screen.bind(INVENTORY_SCENE)).disabled = Session.offline
	_add_button(layer, "Toko", 2, _open_screen.bind(SHOP_SCENE)).disabled = Session.offline
	_update_talk_button()


func _add_button(layer: CanvasLayer, text: String, slot: int, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(548, 940 + slot * 100)
	b.size = Vector2(152, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(callback)
	layer.add_child(b)
	_buttons.append(b)
	return b


func _refresh_hud() -> void:
	var st: Dictionary = Session.player.state
	var potions := 0
	for item: Dictionary in st.inventory:
		if item.id == "ramuan":
			potions = int(item.qty)
	_hud.text = "%s  Lv %d\nHP %d/%d  Emas %d\nRamuan %d  XP %d/%d" % [
		Session.player.name, st.level, st.hp, st.max_hp, st.gold,
		potions, st.xp, 20 * int(st.level),
	]


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)
