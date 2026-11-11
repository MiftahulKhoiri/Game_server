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
const TERRITORY := 7.0      # jari-jari wilayah musuh dari titik asalnya (roadmap no. 82)
const FEAR_GAP := 5         # pemain sekian level di atas musuh: musuh takut dan lari (no. 81)
const FLEE_SPEED := 1.9
const PATROL_R := 2.5       # jari-jari jalur patroli (no. 78)

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
var bulk := 1.0             # ukuran badan (m, sisi terpanjang) untuk besar titik di radar
var top := 1.0              # tinggi badan (m), untuk menaruh bar nyawa dan angka kerusakan
var fight := false          # sedang bertarung dengan pemain (pertarungan langsung di dunia)
var warn := false           # tanda seru berkedip: sebentar lagi menyerang
var stun := 0.0             # > 0: belum mau mengejar (habis ditinggal kabur / gagal memulai)
var dying := false          # sudah kalah: tidak bergerak lagi
var lv := 1                 # level musuh (no. 84)
var origin := Vector2.ZERO  # pusat wilayahnya; mengejar tidak sampai keluar wilayah
var shy := false            # pemalu: selalu menghindari pemain
var patrol := false         # berpatroli berkeliling, bukan berkeliaran acak
var fleeing := false        # sedang lari dari pemain
var returning := false      # kembali ke wilayahnya setelah berhenti mengejar
var steps := 0              # berapa kali step() dijalankan (uji optimasi no. 88)
var lod_acc := 0.0
# Gerak bertarung (v0.69.0): mengitari pemain, mundur bersiap sebelum menyerang, menerjang saat menyerang,
# dan terpental saat dipukul.
const ORBIT_SPEED := 1.25
const LUNGE_SPEED := 7.0
const LUNGE_TIME := 0.2
const WINDUP_BACK := 0.5     # mundur sejauh ini (petak) dari jarak berdiri saat bersiap menyerang
var _orbit_dir := 1.0
var _orbit_t := 0.0
var _lunge_t := 0.0
var _knock := Vector2.ZERO
var _patrol_pts: Array[Vector2] = []
var _patrol_i := 0

var _target := Vector2.ZERO
var _has_target := false
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _init(kind: Dictionary, map: String, at: Vector2, seed_value: int) -> void:
	id = str(kind.id)
	label = str(kind.name)
	lv = int(kind.get("lv", 1))
	shy = bool(kind.get("pemalu", false))
	patrol = bool(kind.get("patroli", false))
	map_id = map
	home = at
	origin = at
	pos = at
	_rng.seed = seed_value
	_wait = _rng.randf_range(0.0, 3.0)  # tidak semua mulai berjalan serentak
	yaw = _rng.randf_range(-PI, PI)
	chase_speed = _rng.randf_range(2.0, 2.6)


## Memilih tujuan acak di sekitar `home` yang bisa dicapai lurus. false bila tidak ada.
func _pick_target() -> bool:
	if patrol:
		return _next_patrol()
	for _i in 10:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(1.0, WANDER_RADIUS)
		var cand := home + Vector2(cos(ang), sin(ang)) * dist
		if Maps.roam_free(map_id, cand) and Maps.roam_path_free(map_id, pos, cand):
			_target = cand
			_has_target = true
			return true
	return false


## Patroli (no. 78): titik-titik keliling di sekitar asalnya yang bisa dicapai, didatangi bergiliran.
func _next_patrol() -> bool:
	if _patrol_pts.is_empty():
		var prev := origin
		for k in 6:
			var ang := TAU * k / 6.0
			var p := origin + Vector2(cos(ang), sin(ang)) * PATROL_R
			if Maps.roam_free(map_id, p) and Maps.roam_path_free(map_id, prev, p):
				_patrol_pts.append(p)
				prev = p
		if _patrol_pts.size() < 2:
			patrol = false  # tempatnya terlalu sempit: berkeliaran biasa
			return _pick_target()
	var p: Vector2 = _patrol_pts[_patrol_i % _patrol_pts.size()]
	_patrol_i += 1
	if not Maps.roam_path_free(map_id, pos, p):
		return false
	_target = p
	_has_target = true
	return true


## Takut pada pemain: pemalu, atau pemain jauh lebih kuat (no. 81).
func afraid_of(player_level: int) -> bool:
	return shy or player_level >= lv + FEAR_GAP


## Maju delta detik. `player` = posisi pemain; `can_aggro` = boleh mengejar (false saat jeda
## awal, di layar lain, atau mode uji); `player_level` = level pemain (musuh lemah takut pada
## pemain yang jauh lebih kuat). Mengembalikan true bila menyentuh pemain.
func step(delta: float, player: Vector2, can_aggro: bool, player_level := 1) -> bool:
	steps += 1
	walking = false
	fleeing = false
	if dying:
		return false
	if stun > 0.0:
		stun -= delta
		can_aggro = false
	if fight:
		_step_fight(delta, player)
		return false
	var d := pos.distance_to(player)
	if can_aggro and d < AGGRO and afraid_of(player_level):
		chasing = false
		_flee(delta, player)
		return false
	# Wilayah (no. 82): berhenti mengejar bila pemain jauh atau musuh sudah keluar wilayahnya, lalu pulang.
	if chasing and (not can_aggro or d > LOSE or pos.distance_to(origin) > TERRITORY):
		chasing = false
		returning = pos.distance_to(origin) > WANDER_RADIUS
		_wait = _rng.randf_range(0.8, 2.0)
	if not chasing and not returning and can_aggro and d < AGGRO and player.distance_to(origin) < TERRITORY \
			and Maps.roam_path_free(map_id, pos, player):
		chasing = true
		_has_target = false
	if returning and not chasing:
		var to_o := origin - pos
		var od := to_o.length()
		var nxt_o := pos + to_o / maxf(od, 0.001) * minf(WANDER_SPEED * 1.4 * delta, od)
		if od < 0.3 or not Maps.roam_free(map_id, nxt_o):
			returning = false
			home = pos if od >= 0.3 else origin
		else:
			pos = nxt_o
			walking = true
			yaw = lerp_angle(yaw, atan2(to_o.x, to_o.y), minf(1.0, delta * TURN_RATE))
			return false
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


## Lari menjauhi pemain (dicoba beberapa arah supaya tidak menabrak tembok).
func _flee(delta: float, player: Vector2) -> void:
	var away := pos - player
	away = away.normalized() if away.length() > 0.001 else Vector2(1, 0)
	for ang: float in [0.0, 0.6, -0.6, 1.3, -1.3]:
		var dir := away.rotated(ang)
		var nxt := pos + dir * FLEE_SPEED * delta
		if Maps.roam_free(map_id, nxt):
			pos = nxt
			walking = true
			fleeing = true
			yaw = lerp_angle(yaw, atan2(dir.x, dir.y), minf(1.0, delta * TURN_RATE))
			break
	_has_target = false


## Musuh menerjang ke arah pemain (dipanggil saat serangannya tiba).
func lunge() -> void:
	_lunge_t = LUNGE_TIME


## Musuh terpental menjauhi titik `from` (pukulan pemain); `power` 0..1.
func knock(from: Vector2, power := 0.5) -> void:
	var away := pos - from
	if away.length() < 0.001:
		away = Vector2(sin(yaw), cos(yaw)) * -1.0
	_knock = away.normalized() * (2.5 + 3.5 * power)


## Geser `move` bila bebas (menyusuri tembok satu sumbu bila terhalang). true bila bergerak.
func _slide(move: Vector2) -> bool:
	for m: Vector2 in [move, Vector2(move.x, 0.0), Vector2(0.0, move.y)]:
		if m.length() > 0.0001 and Maps.roam_free(map_id, pos + m):
			pos += m
			return true
	return false


## Musuh yang sedang bertarung: menghadap pemain, mengitarinya, mundur bersiap sebelum menyerang, menerjang saat
## menyerang, dan terpental saat dipukul (tanpa menyentuh = tanpa memulai pertarungan lagi).
func _step_fight(delta: float, player: Vector2) -> void:
	var to := player - pos
	var d := to.length()
	var want := yaw
	var dir := Vector2.ZERO
	if d > 0.001:
		want = atan2(to.x, to.y)
		dir = to / d
	if _knock.length() > 0.05:
		_slide(_knock * delta)
		_knock = _knock.move_toward(Vector2.ZERO, delta * 14.0)
	elif _lunge_t > 0.0:
		_lunge_t -= delta
		if d > 0.75:
			walking = _slide(dir * minf(LUNGE_SPEED * delta, d - 0.75))
	else:
		var stand := STAND + (WINDUP_BACK if warn else 0.0)
		var move := Vector2.ZERO
		if d > stand + 0.05:
			move = dir * minf(chase_speed * delta, d - stand)
		elif d < stand - 0.05:
			move = -dir * minf(1.6 * delta, stand - d)  # mundur bersiap / menjaga jarak
		if not warn:
			# Mengitari pemain; arah putaran berganti sesekali atau saat menabrak.
			_orbit_t -= delta
			if _orbit_t <= 0.0:
				_orbit_t = _rng.randf_range(1.2, 2.6)
				_orbit_dir = -_orbit_dir if _rng.randf() < 0.6 else _orbit_dir
			move += Vector2(-dir.y, dir.x) * _orbit_dir * ORBIT_SPEED * delta
		if move.length() > 0.0001:
			walking = _slide(move)
			if not walking:
				_orbit_dir = -_orbit_dir
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
