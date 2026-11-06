extends RefCounted
## Warga desa yang berjalan bebas (pemanis). Satu objek = satu warga: titik asal, tujuan
## berikutnya, jeda, dan modelnya. Gerak dihitung di sini supaya bisa diuji tanpa layar.
##
## Aturan: berjalan lurus ke titik acak dalam jari-jarinya (hanya lewat petak jalan/rumput/bunga,
## lihat Maps.warga_free), berhenti sebentar, lalu pilih tujuan baru. Berhenti dan
## menoleh bila pemain atau warga lain terlalu dekat di depannya.

const Maps = preload("res://scripts/maps.gd")

## Awalan id lawan bicara (Session.talk_npc) untuk membedakan warga dari NPC misi.
const TALK_PREFIX := "warga:"
const PLAYER_GAP := 0.85   # jarak minimal ke pemain (petak)
const OTHER_GAP := 0.6     # jarak minimal ke warga lain
const NOTICE := 2.6        # jarak warga yang berhenti mulai menoleh ke pemain
const GREET := 1.9         # pemain sedekat ini: warga berhenti dan menoleh (supaya mudah diajak bicara)
const TURN_RATE := 7.0

var id := ""              # kunci dialog (Maps.WARGA[].id)
var map_id := ""
var home := Vector2.ZERO
var radius := 3.0
var speed := 0.7
var pos := Vector2.ZERO
var yaw := 0.0
var walking := false
var node: Node3D            # wadah di dunia (posisi); model di dalamnya yang berputar
var model: Node3D

var _target := Vector2.ZERO
var _has_target := false
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _init(def: Dictionary, seed_value: int) -> void:
	id = str(def.id)
	map_id = str(def.map)
	home = def.pos
	radius = float(def.radius)
	speed = float(def.speed)
	pos = home
	_rng.seed = seed_value
	_wait = _rng.randf_range(0.0, 2.5)  # tidak semua mulai berjalan serentak
	yaw = _rng.randf_range(-PI, PI)


## Memilih tujuan baru yang bisa dicapai lurus dari posisi sekarang. false bila tak ada.
func _pick_target() -> bool:
	for _i in 12:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(1.0, radius)
		var cand := home + Vector2(cos(ang), sin(ang)) * dist
		if Maps.warga_free(map_id, cand) and Maps.warga_path_free(map_id, pos, cand):
			_target = cand
			_has_target = true
			return true
	return false


## Maju delta detik. `player` = posisi pemain, `others` = posisi warga lain.
func step(delta: float, player: Vector2, others: Array[Vector2]) -> void:
	walking = false
	var want_yaw := yaw
	var face_player := false
	if pos.distance_to(player) < GREET:
		face_player = true  # menyapa: diam di tempat sambil menoleh ke pemain
	elif _wait > 0.0:
		_wait -= delta
		face_player = pos.distance_to(player) < NOTICE
	elif not _has_target:
		if not _pick_target():
			_wait = _rng.randf_range(0.8, 2.0)
	else:
		var to_target := _target - pos
		var dist := to_target.length()
		if dist < 0.06:
			_has_target = false
			_wait = _rng.randf_range(1.5, 5.0)
		else:
			var nxt := pos + to_target / dist * minf(speed * delta, dist)
			if _blocked(nxt, player, others):
				# ada yang menghalangi di depan: diam sebentar lalu cari arah lain
				_has_target = false
				_wait = _rng.randf_range(0.5, 1.2)
				face_player = pos.distance_to(player) < NOTICE
			else:
				pos = nxt
				walking = true
				want_yaw = atan2(to_target.x, to_target.y)
	if face_player:
		var tp := player - pos
		want_yaw = atan2(tp.x, tp.y)
	if walking or face_player:
		yaw = lerp_angle(yaw, want_yaw, minf(1.0, delta * TURN_RATE))


## Langkah ke `nxt` ditolak bila menabrak penghalang, atau mendekati pemain/warga lain.
func _blocked(nxt: Vector2, player: Vector2, others: Array[Vector2]) -> bool:
	if not Maps.warga_free(map_id, nxt):
		return true
	if nxt.distance_to(player) < PLAYER_GAP and nxt.distance_to(player) < pos.distance_to(player):
		return true
	for o in others:
		if nxt.distance_to(o) < OTHER_GAP and nxt.distance_to(o) < pos.distance_to(o):
			return true
	return false


## Menyalin keadaan ke node 3D.
func apply() -> void:
	if node == null or not is_instance_valid(node):
		return
	node.position = Vector3(pos.x, 0.0, pos.y)
	if model != null and is_instance_valid(model):
		model.rotation.y = yaw
		if "moving" in model:
			model.moving = walking
