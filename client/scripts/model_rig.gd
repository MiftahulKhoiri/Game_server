extends Node3D
## Animasi sederhana untuk model 3D buatan kode: mengayun sendi (pivot) dengan sinus.
## Tidak memerlukan Skeleton. Bila model GLB pengganti punya AnimationPlayer
## (klip idle/walk/attack), klip itu yang dipakai (lihat Models.create).
##
## Pivot standar (semua opsional): arm_l, arm_r, leg_l, leg_r, head, tail, wing_l,
## wing_r, body, seg_0..seg_N (ular). Arah depan model = +Z.

var kind := "biped"  # biped | quad | snake | bat | golem | hopper
var pivots: Dictionary = {}
var moving := false
var anim_player: AnimationPlayer = null
var base_y := 0.0

var _rest: Dictionary = {}  # nama pivot -> rotasi awal
var _t := 0.0
var _attack := 0.0
var _hurt := 0.0
var _dead := 0.0
var _anim_names: Dictionary = {}

const ATTACK_TIME := 0.5
const HURT_TIME := 0.35


func setup(p_kind: String, p_pivots: Dictionary) -> void:
	kind = p_kind
	pivots = p_pivots
	for n: String in pivots:
		_rest[n] = (pivots[n] as Node3D).rotation
	base_y = position.y


func use_animation_player(ap: AnimationPlayer) -> void:
	anim_player = ap
	for name: String in ap.get_animation_list():
		var low := name.to_lower()
		for key: String in ["idle", "walk", "attack", "hurt", "die"]:
			if low.contains(key) and not _anim_names.has(key):
				_anim_names[key] = name
	if _anim_names.has("idle"):
		ap.play(_anim_names.idle)


func play_attack() -> void:
	_attack = ATTACK_TIME
	if anim_player != null and _anim_names.has("attack"):
		anim_player.play(_anim_names.attack)


func play_hurt() -> void:
	_hurt = HURT_TIME
	if anim_player != null and _anim_names.has("hurt"):
		anim_player.play(_anim_names.hurt)


func play_die() -> void:
	_dead = 0.001
	if anim_player != null and _anim_names.has("die"):
		anim_player.play(_anim_names.die)


func is_dead() -> bool:
	return _dead > 0.0


func _rot(name: String, x := 0.0, y := 0.0, z := 0.0) -> void:
	if not pivots.has(name):
		return
	var r: Vector3 = _rest[name]
	(pivots[name] as Node3D).rotation = r + Vector3(x, y, z)


func _process(delta: float) -> void:
	_t += delta
	_attack = maxf(0.0, _attack - delta)
	_hurt = maxf(0.0, _hurt - delta)
	if _dead > 0.0:
		_dead = minf(1.0, _dead + delta * 1.6)
		if not _anim_names.has("die"):  # tanpa klip mati: roboh ke samping
			rotation.z = lerpf(0.0, PI / 2.0, _dead)
			position.y = base_y - 0.15 * _dead
		return
	if anim_player != null and not _anim_names.is_empty():
		_drive_animation_player()
		return
	var amount := 1.0 if moving else 0.0
	var ph := _t * (9.0 if kind != "golem" and kind != "static" else 5.0)
	var swing := sin(ph) * 0.55 * amount
	var idle := sin(_t * 2.0) * 0.03
	var atk := 0.0
	if _attack > 0.0:
		atk = sin((1.0 - _attack / ATTACK_TIME) * PI)

	match kind:
		"static":
			# Model tanpa rangka (hasil gambar-ke-3D): badan utuh bergoyang, maju saat serang.
			_rot("body", 0.0, 0.0, sin(ph) * 0.05 * amount)
			if pivots.has("body"):
				(pivots["body"] as Node3D).position.y = absf(sin(ph)) * 0.06 * amount + sin(_t * 2.0) * 0.015
		"biped", "golem":
			_rot("leg_l", swing)
			_rot("leg_r", -swing)
			_rot("arm_l", -swing * 0.8 + idle)
			_rot("arm_r", swing * 0.8 - idle - atk * 2.2)
			_rot("head", 0.0, sin(_t * 1.1) * 0.05)
			_rot("body", 0.0, 0.0, sin(ph) * 0.03 * amount)
		"quad":
			_rot("leg_fl", swing)
			_rot("leg_br", swing)
			_rot("leg_fr", -swing)
			_rot("leg_bl", -swing)
			_rot("tail", 0.0, sin(_t * 5.0) * 0.4)
			_rot("head", -atk * 0.5 + idle)
		"snake":
			for i in 10:
				var n := "seg_%d" % i
				if pivots.has(n):
					_rot(n, 0.0, sin(_t * 4.0 - i * 0.7) * (0.35 + 0.3 * amount) + atk * 0.0)
		"bat":
			var flap := sin(_t * 14.0) * 0.9
			_rot("wing_l", 0.0, 0.0, flap)
			_rot("wing_r", 0.0, 0.0, -flap)
			position.y = base_y + sin(_t * 3.0) * 0.06
		"hopper":
			var hop := absf(sin(_t * 6.0)) * 0.12 * (1.0 if moving else 0.25)
			_rot("body", 0.0, 0.0, 0.0)
			_rot("leg_l", -hop * 3.0)
			_rot("leg_r", -hop * 3.0)
			position.y = base_y + hop
	var lunge := atk * 0.35  # serang: badan maju sedikit lalu kembali
	if pivots.has("body"):
		(pivots["body"] as Node3D).position.z = lunge
	if _hurt > 0.0:
		# Terkena: terhuyung ke belakang.
		var k := _hurt / HURT_TIME
		if pivots.has("body"):
			(pivots["body"] as Node3D).position.z -= sin(k * PI) * 0.15
			(pivots["body"] as Node3D).rotation.x = -sin(k * PI) * 0.25


func _drive_animation_player() -> void:
	_overlay_without_clips()
	var want := "idle"
	if _hurt > 0.0 and _anim_names.has("hurt"):
		want = "hurt"
	elif _attack > 0.0 and _anim_names.has("attack"):
		want = "attack"
	elif moving and _anim_names.has("walk"):
		want = "walk"
	if _anim_names.has(want) and anim_player.current_animation != _anim_names[want]:
		anim_player.play(_anim_names[want])


## Model berangka yang tidak punya klip serang/terkena (hewan Quaternius hanya idle dan jalan):
## badan utuh (pivot "body") maju saat menyerang dan terhuyung saat terkena.
func _overlay_without_clips() -> void:
	if not pivots.has("body"):
		return
	var b := pivots["body"] as Node3D
	var z := 0.0
	var rx := 0.0
	if not _anim_names.has("attack") and _attack > 0.0:
		z += sin((1.0 - _attack / ATTACK_TIME) * PI) * 0.35
	if not _anim_names.has("hurt") and _hurt > 0.0:
		var k := _hurt / HURT_TIME
		z -= sin(k * PI) * 0.15
		rx = -sin(k * PI) * 0.25
	b.position.z = z
	b.rotation.x = rx
