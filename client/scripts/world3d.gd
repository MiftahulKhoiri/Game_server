extends Node3D
## Dunia 3D: jalan bebas dengan joystick layar, kamera di belakang pemain (geser layar
## untuk memutar). Peta, pintu, pertemuan musuh, NPC, dan penyimpanan memakai aturan
## yang sama dengan peta petak lama; posisi halus (fx, fz, yaw) ikut disimpan ke server.

const Maps = preload("res://scripts/maps.gd")
const Movement = preload("res://scripts/movement.gd")
const WorldBuild = preload("res://scripts/world_build.gd")
const Models = preload("res://scripts/models.gd")
const Joystick = preload("res://scripts/joystick.gd")
const GameMenu = preload("res://scripts/game_menu.gd")
const Companions = preload("res://scripts/companions.gd")
const ProfileScreen = preload("res://scripts/profile.gd")
const Heroes = preload("res://scripts/heroes.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const Warga = preload("res://scripts/warga.gd")
const Breakables = preload("res://scripts/breakables.gd")
const ActionButton = preload("res://scripts/action_button.gd")
const Chest = preload("res://scripts/chest.gd")
const HeroFx = preload("res://scripts/hero_fx.gd")
const Roamer = preload("res://scripts/roamer.gd")
const WorldFight = preload("res://scripts/world_fight.gd")
const HudBars = preload("res://scripts/hud_bars.gd")

const SPEED := 3.3  # petak per detik
const SAVE_DELAY := 1.5
const RETRY_DELAY := 5.0
const ENCOUNTER_CHANCE := 0.18  # peluang bertemu musuh tiap "langkah" (1 petak jalan) di ladang
const TALK_RANGE := 1.5
const KEEPER_RANGE := 2.3  # penjaga toko berdiri di balik meja kasir
const CAM_DIST := 6.4
const ATMO_STEP := 0.4        # detik antar pembaruan langit/cahaya (cukup halus, hemat tenaga)
const NPC_NOTICE := 3.5       # jarak (petak) NPC mulai menoleh ke pemain
const NPC_WANDER := 0.22      # NPC berjalan pelan di dalam petaknya sendiri (jangkauan, petak)
const NPC_SPEED := 0.5        # petak per detik
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const TRAIN_SCENE := "res://scenes/train.tscn"
const RECRUIT_SCENE := "res://scenes/recruit.tscn"
const INVENTORY_SCENE := "res://scenes/inventory.tscn"
const ATRIBUT_SCENE := "res://scenes/atribut.tscn"
const DIALOG_SCENE := "res://scenes/dialog.tscn"
const LOGIN_SCENE := "res://scenes/login.tscn"

# Aksi dunia (sejak v0.37.0):
#   Tangan: 1x tinju dobel, 2x tebas dobel, 3x tusuk (kombo; kembali ke tinju setelah jeda).
#   Kaki: 1x tendang, 2x tendangan dobel (dua kali menendang).
#   Perisai: 1x angkat perisai (tetap di tempat), 2x cepat = menghindar (berguling).
#   Lompat: melompat. Boost: isi dari memukul, lalu ledakan + mode Boost.
# `hits` = detik setelah tombol ditekan saat tiap pukulan/tendangan mengenai (selaras dengan gerakan tubuh).
const COMBO_WINDOW := 1.1
const COMBO := [
	{"nama": "Tinju dobel", "anim": "tinju", "reach": 1.5, "cos": 0.25, "dmg": 1.0, "solid": 1, "grass": 2, "cd": 0.62, "len": 0.9, "roll": 0.0, "dash": 0.16, "hits": [0.14, 0.4]},
	{"nama": "Tebas dobel", "anim": "tebas", "reach": 2.0, "cos": -0.3, "dmg": 1.6, "solid": 2, "grass": 5, "cd": 0.8, "len": 1.5, "roll": 0.8, "dash": 0.2, "hits": [0.27, 0.65]},
	{"nama": "Tusuk", "anim": "tusuk", "reach": 2.7, "cos": 0.55, "dmg": 3.0, "solid": 2, "grass": 4, "cd": 0.62, "len": 2.2, "roll": 0.0, "dash": 0.5, "hits": [0.27]},
]
const KICKS := [
	{"nama": "Tendang", "anim": "tendang", "reach": 1.55, "cos": 0.1, "dmg": 1.5, "solid": 1, "grass": 3, "cd": 0.5, "hits": [0.15], "dash": 0.2},
	{"nama": "Tendangan dobel", "anim": "tendang2", "reach": 1.7, "cos": 0.0, "dmg": 1.7, "solid": 2, "grass": 4, "cd": 0.95, "hits": [0.14, 0.62], "dash": 0.3},
]
const KICK_WINDOW := 1.0
const DOUBLE_TAP := 0.4        # dua ketukan Perisai secepat ini = menghindar
const GUARD_TIME := 1.6        # sekali ketuk Perisai: perisai terangkat selama ini (tetap di tempat)
const JUMP_TIME := 0.75
const JUMP_HEIGHT := 1.0
const BOOST_TIME := 8.0
const BOOST_SPEED := 1.35
const ENERGY_PER_HIT := 5.0
const ENERGY_PER_BREAK := 9.0
const BREAK_FLUSH := 0.25      # kumpulkan benda hancur sebentar lalu lapor ke server sekaligus
const CHEST_RANGE := 1.9
const ROAM_GRACE := 3.0        # detik setelah masuk peta: musuh berkeliaran belum mengejar
const ROAM_NEAR := 6.5         # jarak (petak) nama musuh mulai tampil
const ITEM_NAMES := {"ramuan": "Ramuan", "berlian": "Berlian", "ramuan_kekuatan": "Ramuan Kekuatan", "kartu_keahlian": "Kartu Keahlian", "koin_kuno": "Koin Kuno", "permata_merah": "Permata Merah"}

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

var _atmo_base: Dictionary = {}   # suasana dasar peta ini (sebelum waktu/cuaca)
var _atmo_acc := 0.0
var _rain: CPUParticles3D
var _clock: ClockBadge
var _companions: Companions
var _npc_models: Dictionary = {}  # id NPC -> model 3D
var _npc_time := 0.0
var _warga: Array[Warga] = []        # warga desa yang berjalan bebas
var _roamers: Array[Roamer] = []     # musuh yang berkeliaran di peta
var _roam_cfg: Dictionary = {}       # pengaturan musuh peta ini (Maps.ROAMERS), untuk memunculkan pengganti
var _roam_kinds: Array = []
var _fight: WorldFight               # pertarungan langsung di dunia
var _roam_grace := 0.0
var _bars: HudBars

var _joy: Control
var _cam_finger := -1
var _status: Label
var _toast: Label
var _talk_button: Button
var _buttons: Array[Button] = []
var _menu: CanvasLayer
var _profile: CanvasLayer

var _breakables: Breakables
var _chest_nodes: Dictionary = {}   # id peti -> Chest
var _chest_open: Dictionary = {}    # id peti -> true (sudah dibuka, belum terisi lagi)
var _chest_busy := false
var _act_buttons: Array = []
var _btn_tangan: ActionButton
var _btn_kaki: ActionButton
var _btn_perisai: ActionButton
var _btn_boost: ActionButton
var _btn_lompat: ActionButton
var _cd := {"tangan": 0.0, "kaki": 0.0, "hindar": 0.0, "lompat": 0.0}
var _cd_len := {"tangan": 0.3, "kaki": 0.5, "hindar": 0.9, "lompat": 0.85}
var _combo := 0
var _combo_t := 0.0
var _kick := 0           # urutan tendangan (1 = tendang, 2 = dobel)
var _kick_t := 0.0
var _guard_t := 0.0      # sisa waktu perisai terangkat
var _tap_t := -10.0      # kapan Perisai terakhir diketuk (detik, jam lokal)
var _jump_t := 0.0       # sisa waktu lompat (0 = di tanah)
var _shadow_disc: MeshInstance3D
var _energy := 0.0
var _boost_t := 0.0
var _guard := false
var _dash_vel := Vector2.ZERO
var _dash_t := 0.0
var _shake := 0.0
var _hint_t := 0.0
var _aura_guard: MeshInstance3D
var _aura_boost: MeshInstance3D
var _pending: Array = []
var _breaking := false
var _flush_timer: Timer


func _ready() -> void:
	if Session.player.is_empty():
		Session.use_offline_player()  # dijalankan langsung dari editor

	_env = WorldEnvironment.new()
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	add_child(_sun)
	_apply_quality()
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.far = 90.0
	add_child(_camera)
	_camera.current = true
	_rain = Atmosphere.make_rain(Vector3(6, 0.2, 6), Atmosphere.rain_amount(Session.quality))
	add_child(_rain)

	_make_player()

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
	_spawn_roamers(_map_id)
	_sync_state()

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)

	_build_ui()
	_fight = WorldFight.new()
	add_child(_fight)
	_fight.setup(self)
	_companions = Companions.new()
	add_child(_companions)
	_companions.setup(self)
	_refresh_hud()
	_update_clock()
	_apply_transform()
	_set_status("Mode uji (tidak disimpan)" if Session.offline else "Tersimpan")
	if not Session.offline:
		_fight.resume()  # mis. aplikasi ditutup di tengah pertarungan: musuhnya muncul lagi di dekat pemain


func _notification(what: int) -> void:
	# Simpan seketika saat aplikasi dijeda atau ditutup (best-effort).
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _unsaved and not _saving:
			_save()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_menu()


# --- peta ---

func _load_map(map_id: String) -> void:
	_map_id = map_id
	if _terrain != null:
		_terrain.queue_free()
	if _npc_root != null:
		_npc_root.queue_free()
	_terrain = WorldBuild.build(map_id)
	add_child(_terrain)
	_breakables = Breakables.new()
	_breakables.setup(_terrain, _terrain)
	_spawn_chests(map_id)
	_npc_root = Node3D.new()
	_npc_root.name = "NPC"
	add_child(_npc_root)
	_npc_models = {}
	_pending.clear()
	for id: String in Maps.NPCS:
		var n: Dictionary = Maps.NPCS[id]
		if n.map != map_id:
			continue
		var model := Models.create(id)
		model.position = Vector3(n.pos.x + 0.5, 0.0, n.pos.y + 0.5)
		_npc_root.add_child(model)
		_npc_models[id] = model
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
	_spawn_warga(map_id)
	_env.environment = WorldBuild.environment_for(map_id)
	_sun.light_energy = WorldBuild.light_energy_for(map_id)
	_sun.light_color = WorldBuild.light_color_for(map_id)
	# Waktu dan cuaca berlaku di luar ruangan; suasana dasar peta disimpan dulu.
	_atmo_base = Atmosphere.capture(_env.environment, _sun)
	Atmosphere.apply(_env.environment, _sun, _atmo_base, map_id)
	Atmosphere.set_rain(_rain, map_id)
	_update_lamps()
	_sync_world()


## Peti harta di peta ini (isi diundi server saat dibuka).
func _spawn_chests(map_id: String) -> void:
	_chest_nodes = {}
	_chest_open = {}
	for c: Dictionary in Maps.chests_in(map_id):
		var node := Chest.new()
		node.build(str(c.id), int(c.tier))
		node.position = Vector3(c.pos.x + 0.5, 0.0, c.pos.y + 0.5)
		_terrain.add_child(node)
		_chest_nodes[str(c.id)] = node


## Minta daftar benda hancur dan peti terbuka ke server, lalu sesuaikan tampilan peta.
func _sync_world() -> void:
	if Session.offline:
		return
	var mid := _map_id
	var res: Dictionary = await Api.world_state(mid)
	if not res.ok or mid != _map_id or _breakables == null:
		return
	var items: Array = res.data.get("items", [])
	_breakables.apply_server(items)
	for it: Dictionary in items:
		var cid := str(it.get("id", ""))
		if cid != "" and _chest_nodes.has(cid):
			_chest_open[cid] = true
			(_chest_nodes[cid] as Chest).set_open(true, false)
			_reopen_later(cid, float(it.get("left", 0)))


## Peti terisi lagi setelah `left` detik.
func _reopen_later(cid: String, left: float) -> void:
	var mid := _map_id
	await get_tree().create_timer(maxf(left, 1.0)).timeout
	if mid == _map_id and _chest_nodes.has(cid):
		_chest_open.erase(cid)
		(_chest_nodes[cid] as Chest).set_open(false)


## Warga desa: wadah Node3D (bergerak) berisi model (berputar), bayangan, dan nama.
func _spawn_warga(map_id: String) -> void:
	_warga = []
	for def: Dictionary in Maps.WARGA:
		if def.map != map_id:
			continue
		var w := Warga.new(def, _warga.size() * 7919 + str(def.name).hash())
		var holder := Node3D.new()
		holder.name = "Warga_%s_%d" % [def.model, _warga.size()]
		var model := Models.create(str(def.model))
		holder.add_child(model)
		_add_shadow(holder, 0.28)
		var label := Label3D.new()
		label.text = str(def.name) + ("\n" + str(def.peran) if def.has("peran") else "")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.005
		label.font_size = 36
		label.outline_size = 8
		label.modulate = Color("e8e8d0")
		label.position = Vector3(0, 1.3 if def.has("peran") else 1.15, 0)
		holder.add_child(label)
		_npc_root.add_child(holder)
		w.node = holder
		w.model = model
		if w.door.x >= 0 and Atmosphere.outdoors(map_id) and Atmosphere.is_night():
			w.inside = true  # masuk peta saat malam: penduduk sudah di rumah
			w.pos = w.spot() if w.terlihat else w.front()
			if w.terlihat:
				w.yaw = atan2(w.arah.x, w.arah.y)
		w.apply()
		_warga.append(w)


## Munculkan musuh berkeliaran sesuai peta dan level pemain, jauh dari tempat pemain berdiri.
func _spawn_roamers(map_id: String) -> void:
	_roamers = []
	_roam_grace = ROAM_GRACE
	_roam_cfg = Maps.ROAMERS.get(map_id, {})
	_roam_kinds = []
	if _roam_cfg.is_empty() or _npc_root == null:
		return
	var level := int(Session.player.state.level)
	var weakest: Dictionary = {}
	for k: Dictionary in _roam_cfg.kinds:
		if int(k.lv) <= level:
			_roam_kinds.append(k)
		if weakest.is_empty() or int(k.lv) < int(weakest.lv):
			weakest = k
	if _roam_kinds.is_empty():
		_roam_kinds = [weakest]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tries := 0
	while _roamers.size() < int(_roam_cfg.n) and tries < 500:
		tries += 1
		var at := _roam_spot(map_id, rng)
		if at == Vector2.ZERO:
			break
		var kind: Dictionary = _roam_kinds[rng.randi() % _roam_kinds.size()]
		_roamers.append(_make_roamer(kind, map_id, at, int(rng.randi())))


## Titik acak yang cocok untuk musuh berkeliaran: petak yang sesuai, jauh dari pemain dan musuh lain.
## Vector2.ZERO bila tidak ada.
func _roam_spot(map_id: String, rng: RandomNumberGenerator) -> Vector2:
	var rows := Maps.rows(map_id)
	var min_d := 10.0 if Maps.width(map_id) >= 30 else 6.0
	var cands: Array[Vector2] = []
	for y in range(int(_roam_cfg.min_y), rows.size()):
		for x in rows[y].length():
			if not str(_roam_cfg.tiles).contains(rows[y][x]):
				continue
			var c := Vector2(x + 0.5, y + 0.5)
			if c.distance_to(_pos) >= min_d and Maps.roam_free(map_id, c):
				cands.append(c)
	for _i in 40:
		if cands.is_empty():
			return Vector2.ZERO
		var at: Vector2 = cands[rng.randi() % cands.size()]
		var apart := true
		for o in _roamers:
			if o.pos.distance_to(at) < 3.5:
				apart = false
				break
		if apart:
			return at
	return Vector2.ZERO


## Satu musuh pengganti muncul (dipanggil WorldFight setelah satu musuh tumbang).
func respawn_roamer() -> void:
	if _roam_cfg.is_empty() or _roam_kinds.is_empty() or _roamers.size() >= int(_roam_cfg.n):
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var at := _roam_spot(_map_id, rng)
	if at == Vector2.ZERO:
		return
	var kind: Dictionary = _roam_kinds[rng.randi() % _roam_kinds.size()]
	_roamers.append(_make_roamer(kind, _map_id, at, int(rng.randi())))


func _make_roamer(kind: Dictionary, map_id: String, at: Vector2, seed_value: int) -> Roamer:
	var r := Roamer.new(kind, map_id, at, seed_value)
	var holder := Node3D.new()
	holder.name = "Musuh_%s_%d" % [r.id, _roamers.size()]
	var model := Models.create(r.id)
	holder.add_child(model)
	_add_shadow(holder, 0.35)
	var base_id := r.id
	var size := 1.0
	if Models.VARIANTS.has(r.id):
		base_id = str(Models.VARIANTS[r.id].base)
		size = float(Models.VARIANTS[r.id].size)
	var top := float(Models.HEIGHTS.get(base_id, 1.0)) * size
	var name_label := Label3D.new()
	name_label.text = r.label
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.pixel_size = 0.005
	name_label.font_size = 34
	name_label.outline_size = 8
	name_label.modulate = Color("ffc2b0")
	name_label.position = Vector3(0, top + 0.3, 0)
	name_label.visible = false
	holder.add_child(name_label)
	var bang := Label3D.new()
	bang.text = "!"
	bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bang.no_depth_test = true
	bang.pixel_size = 0.011
	bang.font_size = 72
	bang.outline_size = 14
	bang.modulate = Color("ff3b30")
	bang.position = Vector3(0, top + 0.55, 0)
	bang.visible = false
	holder.add_child(bang)
	_npc_root.add_child(holder)
	r.node = holder
	r.model = model
	r.name_label = name_label
	r.alert = bang
	r.top = top
	r.apply(false)
	return r


## Musuh berjalan, mengejar bila pemain mendekat, dan memulai pertarungan langsung saat menyentuh.
func _update_roamers(delta: float) -> void:
	if _roamers.is_empty() or _locked:
		return
	_roam_grace = maxf(0.0, _roam_grace - delta)
	var can_aggro := _roam_grace <= 0.0 and not Session.offline and not _fight.busy()
	for r: Roamer in _roamers.duplicate():
		var touched := r.step(delta, _pos, can_aggro)
		r.apply(r.pos.distance_to(_pos) < ROAM_NEAR)
		if touched and not _fight.busy():
			_fight.engage(r)


## Pukulan/tendangan mengenai musuh berkeliaran di depan: pertarungan langsung dimulai (bila belum)
## dan aksinya (attack / skill1) dikirim ke server. Mengembalikan true bila ada musuh yang terkena.
func _hit_roamer(reach: float, cos_min: float, action := "attack") -> bool:
	if Session.offline or _locked or _roamers.is_empty():
		return false
	var f := _facing()
	var best: Roamer = null
	var best_d := reach + 0.4
	for r in _roamers:
		if r.dying:
			continue
		var off := r.pos - _pos
		var d := off.length()
		if d > reach + 0.4 or d >= best_d:
			continue
		if d > 0.05 and off.normalized().dot(f) < cos_min:
			continue
		best = r
		best_d = d
	if best == null:
		return false
	if _fight.active:
		if best == _fight.roamer:
			_fight.player_action(action)
			return true
		return false  # sedang melawan musuh lain
	if _fight.busy():
		return true  # pertarungan sedang dimulai
	_fight.engage(best, action)
	return true


func _add_shadow(parent: Node3D, radius: float) -> MeshInstance3D:
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
	return disc


## Pindah ke peta lain; posisi baru disimpan seperti gerakan biasa.
func _go_to_map(map_id: String, at: Vector2i) -> void:
	var st: Dictionary = Session.player.state
	st.map = map_id
	_load_map(map_id)
	if Maps.is_interior(map_id):
		_cam_pitch = maxf(_cam_pitch, 0.9)  # dari atas, supaya isi ruangan terlihat
	elif _cam_pitch > 0.85:
		_cam_pitch = 0.62
	_pos = Movement.safe_spot(map_id, at)
	_tile = Movement.tile_of(_pos)
	_step_acc = 0.0
	_spawn_roamers(map_id)
	_sync_state()
	_mark_dirty()
	_apply_transform()
	_update_talk_button()
	_show_toast(str(Maps.NAMES.get(map_id, map_id)))
	_set_status("Memasuki %s" % Maps.NAMES.get(map_id, map_id))


# --- per bingkai ---

func _process(delta: float) -> void:
	_update_world_life(delta)
	_tick_actions(delta)
	var rig := _player as Node
	if _locked:
		_set_moving(false)
		return
	var before := _pos
	var input := _input_vector()
	if _guard:
		input = Vector2.ZERO  # perisai terangkat: tetap di tempat
	_tick_jump(delta)
	var walking := false
	if input.length() > 0.08:
		var fwd := Vector2(-sin(_cam_yaw), -cos(_cam_yaw))
		var right := Vector2(cos(_cam_yaw), -sin(_cam_yaw))
		var dir := fwd * input.y + right * input.x
		if dir.length() > 1.0:
			dir = dir.normalized()
		_pos = Movement.move(_map_id, _pos, dir * SPEED * _speed_mul() * delta)
		walking = true
		if dir.length() > 0.05:
			_yaw = lerp_angle(_yaw, atan2(dir.x, dir.y), minf(1.0, delta * 14.0))
	if _dash_t > 0.0:
		var step := minf(delta, _dash_t)
		_dash_t -= step
		_pos = Movement.move(_map_id, _pos, _dash_vel * step)
	var moved := (_pos - before).length()
	_set_moving(walking and moved > 0.0001)
	if rig != null:
		_apply_transform()
	if moved > 0.0001:
		_sync_state()
		_mark_dirty()
		_after_step(moved)


## Waktu, cuaca, dan NPC yang bergerak pelan: semua hanya tampilan, tidak mengubah data permainan.
func _update_world_life(delta: float) -> void:
	Atmosphere.tick(delta)
	_atmo_acc += delta
	if _atmo_acc >= ATMO_STEP:
		_atmo_acc = 0.0
		Atmosphere.apply(_env.environment, _sun, _atmo_base, _map_id)
		Atmosphere.set_rain(_rain, _map_id)
		_update_lamps()
		_update_clock()
	if _rain != null:
		_rain.position = Vector3(_pos.x, 7.0, _pos.y)  # hujan mengikuti pemain
	_update_npcs(delta)
	_update_roamers(delta)


## Jam di atas layar: ikon matahari (siang) atau bulan (malam); di Gua Batu ikon gua.
func _update_clock() -> void:
	if _clock == null:
		return
	if Maps.is_interior(_map_id):  # di dalam bangunan: ikon menurut jam, teks nama ruangan
		var hh := Atmosphere.hour()
		_clock.set_info("sun" if hh >= 5.5 and hh < 18.0 else "moon", str(Maps.NAMES.get(_map_id, "")))
		return
	if not Atmosphere.outdoors(_map_id):
		_clock.set_info("cave", "Gua Batu")
		return
	var h := Atmosphere.hour()
	_clock.set_info("sun" if h >= 5.5 and h < 18.0 else "moon", Atmosphere.label())


## Lampu menara, gapura, dan rumah menyala menjelang malam dan padam saat pagi.
func _update_lamps() -> void:
	WorldBuild.set_night(_terrain, Atmosphere.night() if Atmosphere.outdoors(_map_id) else 0.0)


## NPC menoleh ke pemain bila dekat; selain itu berjalan pelan di sekitar petaknya.
## Petak NPC tetap terblokir di Maps, jadi tabrakan dan jangkauan bicara tidak berubah.
func _update_npcs(delta: float) -> void:
	_npc_time += delta
	_update_warga(delta)
	for id: String in _npc_models:
		var model := _npc_models[id] as Node3D
		if model == null or not is_instance_valid(model):
			continue
		var home := Vector2(Maps.NPCS[id].pos) + Vector2(0.5, 0.5)
		var to_player := _pos - home
		var near := to_player.length() < NPC_NOTICE
		var phase := float(id.hash() % 100) * 0.1
		var want := home
		if not near:
			want += Vector2(sin(_npc_time * 0.35 + phase), cos(_npc_time * 0.23 + phase * 1.7)) * NPC_WANDER
		var cur := Vector2(model.position.x, model.position.z)
		var nxt := cur.move_toward(want, NPC_SPEED * delta)
		var step := nxt - cur
		var walking := step.length() > 0.0005
		model.position = Vector3(nxt.x, 0.0, nxt.y)
		var face_dir := step if (walking and not near) else to_player
		if face_dir.length() > 0.01:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(face_dir.x, face_dir.y), minf(1.0, delta * 6.0))
		if "moving" in model:
			model.moving = walking and not near


## Warga desa berjalan bebas, saling menghindar, dan menjauh dari pemain.
func _update_warga(delta: float) -> void:
	var night := Atmosphere.outdoors(_map_id) and Atmosphere.is_night()
	for w in _warga:
		var others: Array[Vector2] = []
		for o in _warga:
			if o != w and not o.inside:
				others.append(o.pos)
		w.step(delta, _pos, others, night)
		w.apply()


func _set_moving(v: bool) -> void:
	if "moving" in _player:
		_player.moving = v


func _apply_transform() -> void:
	var jy := _jump_height()
	_player.position = Vector3(_pos.x, jy, _pos.y)
	_player.rotation.y = _yaw
	if _shadow_disc != null:
		_shadow_disc.position.y = 0.02 - jy / maxf(0.01, _player.scale.x)  # bayangan tetap di tanah
	var target := Vector3(_pos.x, 0.8 + jy * 0.5, _pos.y)
	var inside := Maps.is_interior(_map_id)
	var dist := CAM_DIST * (0.95 if inside else 1.0)
	if inside:
		target.z -= 1.5  # pandangan condong ke dalam ruangan: meja kasir dan penjaga ikut terlihat
	var offset := Vector3(sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch)) * dist
	_camera.position = target + offset
	if _shake > 0.0:
		_camera.position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * _shake * 0.5
	_camera.look_at(target, Vector3.UP)
	for a: MeshInstance3D in [_aura_guard, _aura_boost]:
		if a != null:
			a.position = Vector3(_pos.x, 0.55, _pos.y)
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
		if _fight.active:
			_set_status("Selesaikan pertarungan atau kabur dulu")
			return
		var ex := Maps.exit_at(_map_id, t.x, t.y)
		if not ex.is_empty():
			_go_to_map(str(ex.to), ex.at)
			return
		if not Session.offline and Maps.tile_at(_map_id, t.x, t.y) == Maps.BOSS_TILE:
			_start_encounter(true)
			return
	if Session.offline or _locked or _fight.busy():
		return
	var tile := Maps.tile_at(_map_id, _tile.x, _tile.y)
	if tile == "" or not Maps.ENCOUNTER_TILES.contains(tile) or _map_id == Maps.DEFAULT_MAP:
		return  # pertemuan hanya terjadi di ladang hutan / kerikil; Desa Awal aman
	_step_acc += moved
	while _step_acc >= 1.0:
		_step_acc -= 1.0
		if Session.safe_steps > 0:
			Session.safe_steps -= 1
		elif randf() < ENCOUNTER_CHANCE:
			_fight.engage_random()
			return


func _facing() -> Vector2:
	return Vector2(sin(_yaw), cos(_yaw))


func _speed_mul() -> float:
	var m := 1.0
	if _boost_t > 0.0:
		m *= BOOST_SPEED
	return m


## Tubuh model pahlawan (anak rig), dipakai untuk gerakan tambahan seperti menendang dan berguling.
func _body() -> Node3D:
	if _player != null and _player.get_child_count() > 0:
		return _player.get_child(0) as Node3D
	return null


func _tick_actions(delta: float) -> void:
	for k: String in _cd:
		_cd[k] = maxf(0.0, float(_cd[k]) - delta)
	_combo_t = maxf(0.0, _combo_t - delta)
	if _combo_t <= 0.0:
		_combo = 0
	_kick_t = maxf(0.0, _kick_t - delta)
	if _kick_t <= 0.0:
		_kick = 0
	_shake = maxf(0.0, _shake - delta)
	if _btn_tangan == null:
		return
	_btn_tangan.cooldown = float(_cd.tangan) / float(_cd_len.tangan)
	_btn_kaki.cooldown = float(_cd.kaki) / float(_cd_len.kaki)
	_btn_perisai.cooldown = float(_cd.hindar) / float(_cd_len.hindar)
	_btn_lompat.cooldown = float(_cd.lompat) / float(_cd_len.lompat)
	if _guard:
		if _btn_perisai.is_held() and _guard_t < 0.25:
			_guard_t = 0.25  # jari masih menahan Perisai: perisai tetap terangkat
		_guard_t -= delta
		if _guard_t <= 0.0 or _locked:
			_lower_guard()
	if _boost_t > 0.0:
		_boost_t -= delta
		_btn_boost.charge = clampf(_boost_t / BOOST_TIME, 0.0, 1.0)
		_btn_boost.active = true
		_btn_boost.glow = false
		if _aura_boost != null:
			_aura_boost.visible = true
			_aura_boost.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() / 90.0))
		if _boost_t <= 0.0:
			_end_boost()
	if _shake > 0.0 and _player != null:
		_apply_transform()
	_hint_t -= delta
	if _hint_t <= 0.0:
		_hint_t = 0.3
		for id: String in _chest_nodes:
			var n := _chest_nodes[id] as Chest
			n.set_hint(_pos.distance_to(Vector2(n.position.x, n.position.z)) < 4.0)
		_update_talk_button()


func _end_boost() -> void:
	_boost_t = 0.0
	_btn_boost.active = false
	_btn_boost.charge = _energy / 100.0
	_btn_boost.glow = _energy >= 100.0
	if _aura_boost != null:
		_aura_boost.visible = false


func _add_energy(v: float) -> void:
	if _boost_t > 0.0:
		return
	_energy = minf(100.0, _energy + v)
	_btn_boost.charge = _energy / 100.0
	_btn_boost.glow = _energy >= 100.0


## Putar menghadap benda terdekat di depan, supaya pukulan tidak harus pas membidik.
func _aim_assist(reach: float) -> void:
	if _breakables == null:
		return
	var near := _breakables.targets(_pos, _facing(), reach * 1.3, -0.2, 1, 0)
	if near.is_empty():
		return
	var off: Vector2 = (near[0] as Dictionary).pos - _pos
	_yaw = atan2(off.x, off.y)


func _dash(dir: Vector2, dist: float, time: float) -> void:
	if dir == Vector2.ZERO:
		return
	_dash_vel = dir.normalized() * dist / time
	_dash_t = time


## Satu ayunan: pukul benda dalam jangkauan, isi tenaga Boost, laporkan yang hancur ke server.
func _swing(reach: float, cos_min: float, dmg: float, solid_n: int, grass_n: int, action := "attack") -> int:
	if _hit_roamer(reach, cos_min, action):
		return 1
	if _breakables == null or _fight.busy():
		return 0  # saat bertarung pukulan hanya untuk musuh (server menolak aksi dunia selama pertarungan)
	if _boost_t > 0.0:
		dmg *= 2.0
	var list := _breakables.targets(_pos, _facing(), reach, cos_min, solid_n, grass_n)
	if list.is_empty():
		return 0
	var broken := _breakables.strike(list, dmg)
	_add_energy(ENERGY_PER_HIT * minf(list.size(), 3.0) + ENERGY_PER_BREAK * broken.size())
	_queue_breaks(broken)
	return list.size()


func _rig_attack() -> void:
	if _player != null and _player.has_method("play_attack"):
		_player.call("play_attack")


## Tinju dobel -> tebas dobel -> tusuk. Tiap pukulan mengenai pada detik `hits` (selaras dengan gerakan tubuh).
func _do_tangan() -> void:
	if _locked or float(_cd.tangan) > 0.0:
		return
	_lower_guard()
	_combo = _combo + 1 if (_combo_t > 0.0 and _combo < COMBO.size()) else 1
	_combo_t = COMBO_WINDOW
	var sp: Dictionary = COMBO[_combo - 1]
	_cd.tangan = float(sp.cd)
	_cd_len.tangan = float(sp.cd)
	_aim_assist(float(sp.reach))
	_rig_action(str(sp.anim))
	_dash(_facing(), float(sp.dash), 0.1)
	_set_status(str(sp.nama) + ("!" if _combo == COMBO.size() else ""))
	var hits: Array = sp.hits
	for h in hits.size():
		await get_tree().create_timer(float(hits[h]) - (float(hits[h - 1]) if h > 0 else 0.0)).timeout
		if not is_inside_tree() or _locked:
			return
		HeroFx.swoosh(self, Vector3(_pos.x, 0.65, _pos.y), _yaw, float(sp.len), Color("fff2c0"), float(sp.roll))
		_swing(float(sp.reach), float(sp.cos), float(sp.dmg), int(sp.solid), int(sp.grass))


## 1x tendang, 2x (dalam jeda singkat) tendangan dobel: dua kali menendang.
func _do_kaki(_held := 0.0) -> void:
	if _locked or float(_cd.kaki) > 0.0:
		return
	_lower_guard()
	_kick = _kick + 1 if (_kick_t > 0.0 and _kick < KICKS.size()) else 1
	_kick_t = KICK_WINDOW
	var sp: Dictionary = KICKS[_kick - 1]
	_cd.kaki = float(sp.cd)
	_cd_len.kaki = float(sp.cd)
	_aim_assist(float(sp.reach))
	_rig_action(str(sp.anim))
	_dash(_facing(), float(sp.dash), 0.1)
	_set_status(str(sp.nama) + "!")
	var prev := 0.0
	var hits: Array = sp.hits
	for h in hits.size():
		await get_tree().create_timer(float(hits[h]) - prev).timeout
		prev = float(hits[h])
		if not is_inside_tree() or _locked:
			return
		HeroFx.swoosh(self, Vector3(_pos.x, 0.3, _pos.y), _yaw, 1.0, Color("bfe8ff"))
		HeroFx.ring(self, Vector3(_pos.x, 0.0, _pos.y), Color("7fd1ff"), 1.0, 0.25)
		_swing(float(sp.reach), float(sp.cos), float(sp.dmg), int(sp.solid), int(sp.grass), "skill1")


## Ketuk Perisai sekali: perisai terangkat dan pahlawan tetap di tempat. Ketuk dua kali cepat: menghindar.
func _on_perisai_pressed() -> void:
	if _locked:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _tap_t <= DOUBLE_TAP and float(_cd.hindar) <= 0.0:
		_tap_t = -10.0
		_lower_guard()
		_do_dodge()
		return
	_tap_t = now
	_raise_guard()
	# Dalam pertarungan, mengangkat perisai langsung bertahan di server (waktunya menentukan tangkisan sempurna).
	if _fight != null and _fight.active:
		_fight.player_action("defend")


func _raise_guard() -> void:
	_guard = true
	_guard_t = GUARD_TIME
	_btn_perisai.active = true
	if _aura_guard != null:
		_aura_guard.visible = true
	_rig_action("tangkis")
	_set_status("Perisai terangkat. Ketuk dua kali untuk menghindar")


func _lower_guard() -> void:
	if not _guard:
		return
	_guard = false
	_guard_t = 0.0
	if _btn_perisai != null:
		_btn_perisai.active = false
	if _aura_guard != null:
		_aura_guard.visible = false
	var rig := _player as Node
	if rig != null and rig.has_method("stop_action"):
		rig.call("stop_action")


## Alias papan ketik/uji: sama dengan satu ketukan Perisai.
func _do_perisai(_held := 0.0) -> void:
	_on_perisai_pressed()


## Menghindar: melompat/berguling ke arah joystick (tanpa arah joystick: mundur).
func _do_dodge() -> void:
	if _locked or float(_cd.hindar) > 0.0:
		return
	_cd.hindar = 0.9
	_cd_len.hindar = 0.9
	var input := _input_vector()
	var dir := -_facing()  # tanpa arah joystick: melompat mundur
	if input.length() > 0.08:
		var fwd := Vector2(-sin(_cam_yaw), -cos(_cam_yaw))
		var right := Vector2(cos(_cam_yaw), -sin(_cam_yaw))
		dir = fwd * input.y + right * input.x
	_dash(dir, 2.1, 0.22)
	HeroFx.burst(self, Vector3(_pos.x, 0.1, _pos.y), Color("d9c8a0"), 6, 1.4)
	var body := _body()
	if body != null:
		var side := dir.normalized()
		var rot_sign := signf(side.dot(_facing()))
		var tw := create_tween()
		tw.tween_property(body, "rotation:x", TAU * (1.0 if rot_sign >= 0.0 else -1.0), 0.24)
		tw.tween_callback(func() -> void: body.rotation.x = 0.0)
	_set_status("Menghindar!")


# --- lompat ---

func _do_lompat() -> void:
	if _locked or _jump_t > 0.0 or float(_cd.lompat) > 0.0:
		return
	_jump_t = JUMP_TIME
	_cd.lompat = 0.85
	_cd_len.lompat = 0.85
	_rig_action("lompat")
	HeroFx.burst(self, Vector3(_pos.x, 0.1, _pos.y), Color("d9c8a0"), 6, 1.2)


func _tick_jump(delta: float) -> void:
	if _jump_t <= 0.0:
		return
	_jump_t = maxf(0.0, _jump_t - delta)
	if _jump_t <= 0.0:
		HeroFx.burst(self, Vector3(_pos.x, 0.1, _pos.y), Color("d9c8a0"), 5, 1.0)


## Tinggi pahlawan di atas tanah: parabola selama lompat.
func _jump_height() -> float:
	if _jump_t <= 0.0:
		return 0.0
	var u := 1.0 - _jump_t / JUMP_TIME
	return JUMP_HEIGHT * 4.0 * u * (1.0 - u)


## Gerakan tubuh pahlawan (hero_actions.gd); model tanpa rangka itu memakai klip serang biasa.
func _rig_action(anim: String) -> void:
	if _player != null and _player.has_method("play_action"):
		_player.call("play_action", anim)


func _do_boost() -> void:
	if _locked or _boost_t > 0.0:
		return
	if _energy < 100.0:
		_set_status("Boost belum penuh: %d%%" % int(_energy))
		return
	_energy = 0.0
	_boost_t = BOOST_TIME
	_btn_boost.glow = false
	_rig_attack()
	_shake = 0.35
	HeroFx.ring(self, Vector3(_pos.x, 0.0, _pos.y), Color("ffb347"), 3.6, 0.5)
	HeroFx.burst(self, Vector3(_pos.x, 0.5, _pos.y), Color("ffd25a"), 24, 4.0)
	if _hit_roamer(3.4, -1.0):
		return
	if _breakables != null:
		var list := _breakables.targets(_pos, Vector2.ZERO, 3.4, -1.0, 99, 99)
		_queue_breaks(_breakables.strike(list, 99.0))
	_show_toast("BOOST!")
	_set_status("Mode Boost: lebih cepat, pukulan dua kali lipat")


# --- hadiah dunia ---

func _queue_breaks(broken: Array) -> void:
	if broken.is_empty() or Session.offline:
		return
	for e: Dictionary in broken:
		var t: Vector2i = e.tile
		var item := {"kind": str(e.kind), "x": t.x, "z": t.y}
		if not _pending.has(item):
			_pending.append(item)
	if _flush_timer != null and _flush_timer.is_stopped():
		_flush_timer.start(BREAK_FLUSH)


func _flush_breaks() -> void:
	if _pending.is_empty():
		return
	if _breaking or _locked:
		_flush_timer.start(BREAK_FLUSH)
		return
	var batch: Array = _pending.slice(0, 12)
	_pending = _pending.slice(batch.size())
	_breaking = true
	var res: Dictionary = await Api.world_break(_map_id, _pos, _yaw, batch)
	_breaking = false
	if res.ok:
		Session.merge_server_player(res.data.player)
		_refresh_hud()
		_show_loot(res.data.loot, false)
	elif res.status == 409:
		_pending.clear()  # sedang bertarung di server: benda tetap hancur, tanpa hadiah
	if not _pending.is_empty():
		_flush_timer.start(BREAK_FLUSH)


## Satu baris hadiah ("+12 emas  +Berlian") di tengah layar.
func _show_loot(loot: Dictionary, chest: bool) -> void:
	var parts: Array[String] = []
	var gold := int(loot.get("gold", 0))
	if gold > 0:
		parts.append("+%d emas" % gold)
	var items: Variant = loot.get("items")
	if items is Array:
		for it: Dictionary in items:
			var nm := str(ITEM_NAMES.get(str(it.id), str(it.id)))
			parts.append("+%s" % nm if int(it.qty) <= 1 else "+%d %s" % [int(it.qty), nm])
	if parts.is_empty():
		return
	_show_toast(("Peti: " if chest else "") + "  ".join(parts))
	if items is Array and not (items as Array).is_empty():
		_set_status("Barang masuk Ransel (buka lewat Menu)")


func _open_chest(cid: String) -> void:
	if _chest_busy or _locked:
		return
	_chest_busy = true
	var res: Dictionary = await Api.world_chest(cid, _map_id, _pos, _yaw)
	_chest_busy = false
	var node := _chest_nodes.get(cid) as Chest
	if res.ok:
		Session.merge_server_player(res.data.player)
		_refresh_hud()
		_chest_open[cid] = true
		if node != null:
			node.set_open(true)
			HeroFx.burst(self, node.position + Vector3(0, 0.5, 0), Color("ffd24a"), 26, 3.4)
			HeroFx.ring(self, node.position, Color("ffd24a"), 2.0, 0.6)
		_shake = 0.2
		_show_loot(res.data.loot, true)
		_reopen_later(cid, 1800.0)
	else:
		if node != null and str(res.error).contains("kosong"):
			_chest_open[cid] = true
			node.set_open(true, false)
			_reopen_later(cid, 60.0)
		_show_toast(str(res.error))


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
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		_toggle_menu()
		return
	if _locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_J: _do_tangan()
			KEY_K: _do_kaki(0.0)
			KEY_L: _do_perisai()
			KEY_SPACE: _do_lompat()
			KEY_U: _do_boost()
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
	_cam_yaw -= rel.x * 0.008 * Session.cam_sens
	_cam_pitch = clampf(_cam_pitch + rel.y * 0.004 * Session.cam_sens, 0.3, 1.15)


func _on_ui(p: Vector2) -> bool:
	if _joy != null and _joy.get_global_rect().has_point(p):
		return true
	for b in _buttons:
		if b.visible and b.get_global_rect().has_point(p):
			return true
	for a: ActionButton in _act_buttons:
		if a.get_global_rect().has_point(p):
			return true
	return false


# --- pertarungan, NPC, layar lain ---

func _start_encounter(boss := false, enemy := "") -> void:
	if _locked:
		return
	_locked = true
	if enemy == "":
		_set_status("Sesuatu menyambutmu di singgasana..." if boss else "Sesuatu bergerak di sekitarmu...")
	await _flush_save()  # posisi harus tersimpan dulu; server tidak ikut gerak kita
	var res: Dictionary = await Api.battle_start(boss, enemy)
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
	for w in _warga:  # warga desa: posisi hidup (mereka berjalan), id dialog berawalan "warga:"
		if w.inside and not w.terlihat:
			continue
		var wd := _pos.distance_to(w.pos)
		var lim := KEEPER_RANGE if w.toko != "" else TALK_RANGE  # penjaga di balik meja kasir terjangkau lebih jauh
		if wd <= lim and (best == "" or wd <= best_d):
			best_d = wd
			best = Warga.TALK_PREFIX + w.id
	return best


func _chest_in_range() -> String:
	var best := ""
	var best_d := CHEST_RANGE
	for id: String in _chest_nodes:
		if _chest_open.has(id):
			continue
		var n := _chest_nodes[id] as Node3D
		var d := _pos.distance_to(Vector2(n.position.x, n.position.z))
		if d <= best_d:
			best_d = d
			best = id
	return best


## Tombol konteks: "Buka peti" dekat peti, "Bicara" dekat orang; selain itu tersembunyi.
## Tombolnya melayang tepat di atas nama orang/peti yang dituju (mengikuti kamera).
func _update_talk_button() -> void:
	if _talk_button == null:
		return
	if _fight != null and _fight.busy():
		_talk_button.visible = false  # tidak bisa bicara / buka peti saat bertarung
		return
	var chest := _chest_in_range()
	if chest != "" and not Session.offline:
		_talk_button.text = "Buka peti"
		_talk_button.visible = true
		_talk_button.disabled = false
		var cn := _chest_nodes[chest] as Node3D
		_place_talk_button(cn.position + Vector3(0, 1.5, 0))
		return
	var npc := _npc_in_range()
	_talk_button.text = "Bicara"
	_talk_button.visible = npc != ""
	_talk_button.disabled = Session.offline
	if npc != "":
		_place_talk_button(_npc_anchor(npc))


## Titik 3D di atas nama NPC/warga (tempat tombol Bicara melayang).
func _npc_anchor(npc_id: String) -> Vector3:
	if npc_id.begins_with(Warga.TALK_PREFIX):
		var wid := npc_id.substr(Warga.TALK_PREFIX.length())
		for w in _warga:
			if w.id == wid:
				return Vector3(w.pos.x, 1.4, w.pos.y)
	var n: Dictionary = Maps.NPCS.get(npc_id, {})
	if n.is_empty():
		return Vector3(_pos.x, 1.9, _pos.y)
	return Vector3(float(n.pos.x) + 0.5, 1.5, float(n.pos.y) + 0.5)


## Menaruh tombol konteks di layar tepat di atas titik 3D; di luar layar/di belakang kamera
## tombol ditahan di dalam layar (atau di posisi cadangan bawah bila titiknya di belakang).
func _place_talk_button(anchor: Vector3) -> void:
	var vs := get_viewport().get_visible_rect().size
	var sz := _talk_button.size
	if _camera == null or _camera.is_position_behind(anchor):
		_talk_button.position = Vector2(vs.x * 0.5 - sz.x * 0.5, vs.y * 0.55)
		return
	var sp := _camera.unproject_position(anchor)
	var x := clampf(sp.x - sz.x * 0.5, 8.0, vs.x - sz.x - 8.0)
	var y := clampf(sp.y - sz.y - 4.0, 190.0, vs.y * 0.7)
	_talk_button.position = Vector2(x, y)


func _talk() -> void:
	if _locked:
		return
	if _fight != null and _fight.busy():
		_set_status("Selesaikan pertarungan dulu")
		return
	var chest := _chest_in_range()
	if chest != "" and not Session.offline:
		_open_chest(chest)
		return
	var npc := _npc_in_range()
	if npc == "":
		return
	var keeper := _keeper_of(npc)
	if keeper != null:
		await _visit_keeper(keeper)
		return
	_locked = true
	Session.talk_npc = npc
	Session.talk_counts[npc] = int(Session.talk_counts.get(npc, 0)) + 1
	await _flush_save()  # versi pemain harus sinkron sebelum hadiah diambil
	get_tree().change_scene_to_file(DIALOG_SCENE)


## Penjaga toko dari id lawan bicara "warga:<id>", atau null bila bukan penjaga toko.
func _keeper_of(npc_id: String) -> Warga:
	if not npc_id.begins_with(Warga.TALK_PREFIX):
		return null
	var wid := npc_id.substr(Warga.TALK_PREFIX.length())
	for w in _warga:
		if w.id == wid and w.toko != "":
			return w
	return null


## Masuk ke toko lewat penjaganya: toko ramuan / rumah makan membuka layar toko, rumah sehat memulihkan pemain.
func _visit_keeper(w: Warga) -> void:
	if w.toko == "rawat":
		_set_status("%s: Duduklah, biar kurawat lukamu." % w.nama)
		var res: Dictionary = await Api.rest()
		if res.ok:
			Session.merge_server_player(res.data)
			_refresh_hud()
			_set_status("%s merawatmu: HP dan energi pulih penuh." % w.nama)
		else:
			_set_status("%s: %s" % [w.nama, str(res.error)])
		return
	Session.shop_keeper = w.nama
	if w.toko == "rekrut_pahlawan" or w.toko == "rekrut_prajurit":
		Session.recruit_kind = "pahlawan" if w.toko == "rekrut_pahlawan" else "prajurit"
		await _open_screen(RECRUIT_SCENE)
		return
	if w.toko == "latih_pahlawan" or w.toko == "latih_prajurit":
		Session.train_kind = "pahlawan" if w.toko == "latih_pahlawan" else "prajurit"
		await _open_screen(TRAIN_SCENE)
		return
	Session.shop_id = w.toko
	await _open_screen(SHOP_SCENE)


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

	_bars = HudBars.new()
	_bars.position = Vector2(20, 10)
	layer.add_child(_bars)

	_status = Label.new()
	_status.position = Vector2(20, 240)
	_status.size = Vector2(420, 60)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_status.add_theme_constant_override("outline_size", 6)
	layer.add_child(_status)

	_clock = ClockBadge.new()
	_clock.position = Vector2(300.0, 14.0)
	layer.add_child(_clock)

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
	_joy.size = Vector2(400, 380)
	layer.add_child(_joy)

	_talk_button = _add_button(layer, "Bicara", 0, _talk)
	_talk_button.position = Vector2(270, 500)
	_talk_button.size = Vector2(180, 72)
	_btn_tangan = _add_action(layer, ActionButton.Icon.TANGAN, "Tangan", Vector2(612, 1136), 72.0, Color("ffb347"))
	_btn_kaki = _add_action(layer, ActionButton.Icon.KAKI, "Kaki", Vector2(492, 1212), 52.0, Color("7fd1ff"))
	_btn_perisai = _add_action(layer, ActionButton.Icon.PERISAI, "Perisai", Vector2(478, 1090), 52.0, Color("8fe08f"))
	_btn_boost = _add_action(layer, ActionButton.Icon.BOOST, "Boost", Vector2(576, 986), 52.0, Color("ffe14a"))
	_btn_lompat = _add_action(layer, ActionButton.Icon.LOMPAT, "Lompat", Vector2(672, 1030), 44.0, Color("e8b4ff"))
	_btn_tangan.pressed.connect(_do_tangan)
	_btn_kaki.pressed.connect(_do_kaki)
	_btn_perisai.pressed.connect(_on_perisai_pressed)
	_btn_lompat.pressed.connect(_do_lompat)
	_btn_boost.pressed.connect(_do_boost)
	_flush_timer = Timer.new()
	_flush_timer.one_shot = true
	_flush_timer.timeout.connect(_flush_breaks)
	add_child(_flush_timer)
	_update_talk_button()

	var menu_btn := MenuBubble.new()
	menu_btn.position = Vector2(574, 12)
	menu_btn.size = Vector2(134, 60)
	menu_btn.pressed.connect(_toggle_menu)
	layer.add_child(menu_btn)
	_buttons.append(menu_btn)

	_menu = GameMenu.new()
	add_child(_menu)
	_menu.resumed.connect(_close_menu)
	_menu.go_home.connect(_leave_to_home.bind(false))
	_menu.logout.connect(_leave_to_home.bind(true))
	_menu.quit_game.connect(_quit_game)
	_menu.settings_changed.connect(_apply_quality)
	_menu.profile_requested.connect(_open_profile)
	_menu.inventory_requested.connect(_open_from_menu.bind(INVENTORY_SCENE))
	_menu.atribut_requested.connect(_open_from_menu.bind(ATRIBUT_SCENE))
	_profile = ProfileScreen.new()
	add_child(_profile)
	_profile.closed.connect(_close_profile)
	_profile.hero_changed.connect(_make_player)


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


func _add_action(layer: CanvasLayer, icon: int, title: String, center: Vector2, radius: float, tint: Color) -> ActionButton:
	var b := ActionButton.new()
	b.icon = icon
	b.title = title
	b.tint = tint
	b.size = Vector2.ONE * radius * 2.0
	b.position = center - b.size / 2.0
	layer.add_child(b)
	_act_buttons.append(b)
	return b


## Ransel dibuka dari Menu (toko hanya bisa dimasuki lewat penjaga di rumah toko) (menu menutup dulu, lalu pindah layar).
func _open_from_menu(scene: String) -> void:
	_menu.close()
	_locked = false
	_open_screen(scene)


func _refresh_hud() -> void:
	var st: Dictionary = Session.player.state
	if _bars != null:
		_bars.set_identity(str(Session.player.name), int(st.gold), Session.item_count("berlian"))
		_bars.set_values(int(st.level), int(st.xp), 20 * int(st.level), int(st.hp), int(st.max_hp))
		_bars.set_energy(Session.energy(), Session.MAX_ENERGY)


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)


# --- menu dalam game ---

func _toggle_menu() -> void:
	if _menu == null:
		return
	if _profile.is_open:
		_close_profile()
	elif _menu.is_open:
		_menu.back()
	elif not _locked:
		_locked = true
		_menu.open()


## Model pemain di dunia mengikuti pahlawan yang dipilih (dibuat ulang saat pilihan berganti).
func _make_player() -> void:
	var old := _player
	_player = Models.create(str(Heroes.current().id))
	add_child(_player)
	_shadow_disc = _add_shadow(_player, 0.3)
	if _aura_guard == null:
		_aura_guard = HeroFx.aura(Color(0.35, 0.65, 1.0, 0.28))
		add_child(_aura_guard)
		_aura_boost = HeroFx.aura(Color(1.0, 0.65, 0.15, 0.22), 0.8)
		add_child(_aura_boost)
	if old != null:
		old.queue_free()
		_apply_transform()


func _open_profile() -> void:
	_menu.close()
	_profile.open()


func _close_profile() -> void:
	_profile.close()
	_locked = false


func _close_menu() -> void:
	_menu.close()
	_locked = false


## Simpan posisi dulu, lalu kembali ke Beranda (dan bila `forget`, keluar dari akun di HP ini).
func _leave_to_home(forget: bool) -> void:
	_menu.close()
	_locked = true
	await _flush_save()
	if forget and not Session.offline:
		await Api.logout()  # gagal terhubung pun tidak masalah: token lokal tetap dihapus
		Api.token = ""
		Session.saved_name = ""
		Session.player = {}
		Session.save_config()
	get_tree().change_scene_to_file(LOGIN_SCENE)


func _quit_game() -> void:
	_menu.close()
	_locked = true
	await _flush_save()
	get_tree().quit()


## Kualitas grafis dari pengaturan: bayangan matahari dan tepi halus (MSAA).
func _apply_quality() -> void:
	var q: int = Session.quality
	_sun.shadow_enabled = q >= 1
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q == 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 16.0 if q == 1 else 26.0
	RenderingServer.directional_shadow_atlas_set_size(1024 if q == 1 else 2048, true)
	get_viewport().msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	# Resolusi 3D lebih rendah di HP beresolusi tinggi (UI tetap tajam): jauh lebih ringan bagi GPU.
	get_viewport().scaling_3d_scale = [0.6, 0.75, 1.0][clampi(q, 0, 2)]
