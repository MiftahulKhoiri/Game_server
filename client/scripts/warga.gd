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
const HOME_SPEED := 1.6    # pulang berjalan lebih cepat dari biasanya (pengali kecepatan)

var id := ""              # kunci dialog (Maps.WARGA[].id)
var map_id := ""
var home := Vector2.ZERO
var radius := 3.0
var speed := 0.7
var pos := Vector2.ZERO
var yaw := 0.0
var walking := false
var door := Vector2i(-1, -1)  # petak pintu rumahnya (D); (-1,-1) = tidak punya rumah (tetap di luar)
var inside := false           # sedang di dalam rumah (malam): tidak terlihat dan tidak bisa diajak bicara
var node: Node3D            # wadah di dunia (posisi); model di dalamnya yang berputar
var model: Node3D

var _target := Vector2.ZERO
var _has_target := false
var _wait := 0.0
var _route: Array[Vector2] = []
var _route_done := false
var _rng := RandomNumberGenerator.new()


func _init(def: Dictionary, seed_value: int) -> void:
	id = str(def.id)
	map_id = str(def.map)
	home = def.pos
	if def.has("rumah"):
		door = def.rumah
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


## Titik tepat di depan pintu rumah (petak di bawah D), tempat warga masuk dan keluar.
func front() -> Vector2:
	return Vector2(door.x + 0.5, door.y + 1.5)


## Jalur petak (pusat petak) dari posisi sekarang ke depan pintu, lewat petak yang boleh dilalui warga.
## Kosong bila tak ada jalur. Pencarian melebar (BFS) pada kisi petak, sekali saat warga mulai pulang.
func _route_home() -> Array[Vector2]:
	var goal := Vector2i(door.x, door.y + 1)
	var start := Vector2i(int(floor(pos.x)), int(floor(pos.y)))
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	var found := start == goal
	while qi < queue.size() and not found:
		var cur := queue[qi]
		qi += 1
		for d: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := cur + d
			if prev.has(n):
				continue
			if n != goal and not Maps.warga_free(map_id, Vector2(n.x + 0.5, n.y + 0.5)):
				continue
			prev[n] = cur
			if n == goal:
				found = true
				break
			queue.append(n)
	var out: Array[Vector2] = []
	if not found:
		return out
	if start == goal:
		return [Vector2(goal.x + 0.5, goal.y + 0.5)]
	var t := goal
	while t != start:
		out.push_front(Vector2(t.x + 0.5, t.y + 0.5))
		t = prev[t]
	return out


## Berjalan pulang: ikuti jalur sampai depan pintu, lalu masuk (menghilang). Tidak menunggu pemain/warga lain
## (jalur petak sudah bebas rintangan), supaya tidak macet.
func _step_home(delta: float) -> void:
	if not _route_done:
		_route = _route_home()
		_route_done = true
		if _route.is_empty():
			inside = true  # tak ada jalur: langsung dianggap sudah di dalam
			return
		_route.append(Vector2(door.x + 0.5, door.y + 0.5))  # langkah terakhir: masuk lewat pintu
	_has_target = false
	var goal: Vector2 = _route[0]
	var to_goal := goal - pos
	var dist := to_goal.length()
	var stepd := speed * HOME_SPEED * delta
	if dist <= stepd + 0.02:
		pos = goal
		_route.remove_at(0)
		if _route.is_empty():
			inside = true
			walking = false
			return
	else:
		pos += to_goal / dist * stepd
	walking = true
	if dist > 0.01:
		yaw = lerp_angle(yaw, atan2(to_goal.x, to_goal.y), minf(1.0, delta * TURN_RATE * 1.5))


## Pagi hari: keluar dari pintu dan mulai berjalan lagi.
func leave_home() -> void:
	inside = false
	_route = []
	_route_done = false
	pos = front()
	_has_target = false
	_wait = _rng.randf_range(0.5, 4.0)


## Maju delta detik. `player` = posisi pemain, `others` = posisi warga lain, `night` = sudah malam
## (warga yang punya rumah pulang dan bermalam di dalam).
func step(delta: float, player: Vector2, others: Array[Vector2], night := false) -> void:
	walking = false
	if door.x >= 0:
		if night and not inside:
			_step_home(delta)
			return
		if not night and inside:
			leave_home()
		if inside:
			return
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
	node.visible = not inside
	if model != null and is_instance_valid(model):
		model.rotation.y = yaw
		if "moving" in model:
			model.moving = walking
