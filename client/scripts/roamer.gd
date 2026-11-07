extends RefCounted
## Musuh yang berkeliaran di peta. Satu objek = satu musuh: berjalan acak di sekitar titiknya,
## mengejar pemain yang terlalu dekat (selama jalannya lurus dan tidak terhalang), dan
## melaporkan sentuhan supaya dunia memulai pertarungan. Gerak dihitung di sini (tanpa mesin
## fisika) sehingga bisa diuji tanpa layar. Lawan sebenarnya tetap ditentukan server.

const Maps = preload("res://scripts/maps.gd")

const WANDER_SPEED := 0.85
const AGGRO := 4.2          # jarak (petak) musuh mulai mengejar
const LOSE := 8.0           # lebih jauh dari ini, pengejaran dilepas
const CONTACT := 0.95       # sedekat ini = menyentuh pemain
const WANDER_RADIUS := 4.0
const TURN_RATE := 8.0
const STAND := 1.15         # jarak berdiri musuh yang sedang bertarung dengan pemain (petak)

var id := ""                # id musuh (server)
var label := ""             # nama untuk ditampilkan
var map_id := ""
var home := Vector2.ZERO
var pos := Vector2.ZERO
var yaw := 0.0
var walking := false
var chasing := false
var chase_speed := 2.3
var node: Node3D            # wadah di dunia (posisi)
var model: Node3D           # model di dalamnya (berputar)
var alert: Node3D           # tanda seru di atas kepala saat mengejar
var name_label: Node3D
var top := 1.0              # tinggi badan (m), untuk menaruh bar nyawa dan angka kerusakan
var fight := false          # sedang bertarung dengan pemain (pertarungan langsung di dunia)
var warn := false           # tanda seru berkedip: sebentar lagi menyerang
var stun := 0.0             # > 0: belum mau mengejar (habis ditinggal kabur / gagal memulai)
var dying := false          # sudah kalah: tidak bergerak lagi

var _target := Vector2.ZERO
var _has_target := false
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _init(kind: Dictionary, map: String, at: Vector2, seed_value: int) -> void:
	id = str(kind.id)
	label = str(kind.name)
	map_id = map
	home = at
	pos = at
	_rng.seed = seed_value
	_wait = _rng.randf_range(0.0, 3.0)  # tidak semua mulai berjalan serentak
	yaw = _rng.randf_range(-PI, PI)
	chase_speed = _rng.randf_range(2.0, 2.6)


## Memilih tujuan acak di sekitar `home` yang bisa dicapai lurus. false bila tidak ada.
func _pick_target() -> bool:
	for _i in 10:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(1.0, WANDER_RADIUS)
		var cand := home + Vector2(cos(ang), sin(ang)) * dist
		if Maps.roam_free(map_id, cand) and Maps.roam_path_free(map_id, pos, cand):
			_target = cand
			_has_target = true
			return true
	return false


## Maju delta detik. `player` = posisi pemain; `can_aggro` = boleh mengejar (false saat jeda
## awal, di layar lain, atau mode uji). Mengembalikan true bila menyentuh pemain.
func step(delta: float, player: Vector2, can_aggro: bool) -> bool:
	walking = false
	if dying:
		return false
	if stun > 0.0:
		stun -= delta
		can_aggro = false
	if fight:
		_step_fight(delta, player)
		return false
	var d := pos.distance_to(player)
	if chasing and (not can_aggro or d > LOSE):
		chasing = false
		home = pos
		_wait = _rng.randf_range(0.8, 2.0)
	if not chasing and can_aggro and d < AGGRO and Maps.roam_path_free(map_id, pos, player):
		chasing = true
		_has_target = false
	var want_yaw := yaw
	if chasing:
		if d < CONTACT:
			return true
		var dir := (player - pos) / maxf(d, 0.001)
		var move := dir * minf(chase_speed * delta, d)
		var nxt := pos + move
		if not Maps.roam_free(map_id, nxt):
			# terhalang: geser menyusuri tembok (satu sumbu), kalau macet lepaskan pengejaran
			var nx := pos + Vector2(move.x, 0.0)
			var nz := pos + Vector2(0.0, move.y)
			if absf(move.x) >= absf(move.y) and Maps.roam_free(map_id, nx):
				nxt = nx
			elif Maps.roam_free(map_id, nz):
				nxt = nz
			elif Maps.roam_free(map_id, nx):
				nxt = nx
			else:
				chasing = false
				home = pos
				_wait = _rng.randf_range(0.6, 1.4)
				return false
		pos = nxt
		walking = true
		want_yaw = atan2(dir.x, dir.y)
	elif _wait > 0.0:
		_wait -= delta
	elif not _has_target:
		if not _pick_target():
			_wait = _rng.randf_range(0.8, 2.0)
	else:
		var to_target := _target - pos
		var dist := to_target.length()
		if dist < 0.06:
			_has_target = false
			_wait = _rng.randf_range(1.5, 4.5)
		else:
			var nxt2 := pos + to_target / dist * minf(WANDER_SPEED * delta, dist)
			if not Maps.roam_free(map_id, nxt2):
				_has_target = false
				_wait = _rng.randf_range(0.5, 1.2)
			else:
				pos = nxt2
				walking = true
				want_yaw = atan2(to_target.x, to_target.y)
	if walking:
		yaw = lerp_angle(yaw, want_yaw, minf(1.0, delta * TURN_RATE))
	return false


## Musuh yang sedang bertarung: menghadap pemain dan menempel di jaraknya (tanpa menyentuh = tanpa memulai lagi).
func _step_fight(delta: float, player: Vector2) -> void:
	var to := player - pos
	var d := to.length()
	var want := yaw
	if d > 0.001:
		want = atan2(to.x, to.y)
	if d > STAND:
		var move := to / d * minf(chase_speed * delta, d - STAND)
		var nxt := pos + move
		if Maps.roam_free(map_id, nxt):
			pos = nxt
			walking = true
		elif Maps.roam_free(map_id, pos + Vector2(move.x, 0.0)):
			pos += Vector2(move.x, 0.0)
			walking = true
		elif Maps.roam_free(map_id, pos + Vector2(0.0, move.y)):
			pos += Vector2(0.0, move.y)
			walking = true
	yaw = lerp_angle(yaw, want, minf(1.0, delta * TURN_RATE))


## Menyalin keadaan ke node 3D. `near` = pemain cukup dekat untuk menampilkan nama.
func apply(near: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.position = Vector3(pos.x, 0.0, pos.y)
	if model != null and is_instance_valid(model):
		model.rotation.y = yaw
		if "moving" in model:
			model.moving = walking
	if alert != null and is_instance_valid(alert):
		alert.visible = chasing or warn
	if name_label != null and is_instance_valid(name_label):
		name_label.visible = near and not chasing and not fight
