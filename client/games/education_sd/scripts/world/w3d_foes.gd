extends Node3D
## Musuh ramah anak (2.3.0): "Pengacau Lupa" — makhluk kecil yang mengacak pengetahuan. Pola perilaku:
##   patroli (bolak-balik di sekitar rumahnya) -> kejar (pemain dalam 7 m) -> menantang (menyentuh pemain:
##   soal cepat) -> jinak (jawaban benar: berubah emas, melompat, menghilang) / mundur (jawaban salah: pemain
##   terdorong lembut, pengacau kembali ke rumah dan istirahat 4 detik).
## Penjaga Wilayah juga punya pola: berjaga -> hentakan (gelombang mendorong pemain yang terlalu dekat) ->
## lelah (hanya saat lelah ia mau ditantang ujian akhir).
## Tidak ada nyawa/kalah: kesalahan hanya mendorong pemain. Semua diperbarui dari satu _process, dan hanya
## yang dekat pemain yang dianimasikan.

signal foe_touched(foe: Node3D)
signal boss_stomp

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")

const CHASE_RANGE := 7.0
const TOUCH_RANGE := 1.3
const PATROL_SPEED := 1.2
const CHASE_SPEED := 2.4
const ACTIVE_RANGE := 45.0

var world: Node3D
var foes: Array = []  # [{node, rig, home, a, b, state, t, cool}]
var boss: Dictionary = {}  # {node, rig, state, t, active}
var paused := false
var _rng := RandomNumberGenerator.new()


func setup(w: Node3D, seed_value: int) -> void:
	world = w
	_rng.seed = seed_value


func spawn(at: Vector3, span: Vector3, tint: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "Foe%d" % foes.size()
	n.position = at
	var rig := Rig.new()
	rig.glb_id = "goblin"
	rig.glb_height = 0.95
	rig.glb_tint = tint
	rig.glb_hide = ["Sword", "Axe", "Dagger", "Club", "Spear", "Bow", "Weapon"]
	if not Rig.has_model("goblin"):
		rig.shirt = tint
		rig.skin = tint.lightened(0.3)
		rig.extra = "telinga"
		rig.scale = Vector3.ONE * 0.7
	n.add_child(rig)
	rig.build()
	var l: Label3D = world._label("Pengacau Lupa", 40, Color("ffd166"), true)
	l.position.y = 1.5
	n.add_child(l)
	add_child(n)
	n.set_meta("rig", rig)
	foes.append({"node": n, "rig": rig, "home": at, "a": at - span, "b": at + span, "to_b": true, "state": "patroli", "t": 0.0, "cool": 0.0})
	return n


func set_boss(node: Node3D, rig: Node3D, active: bool) -> void:
	boss = {"node": node, "rig": rig, "state": "berjaga", "t": 0.0, "active": active, "home": node.position}


func boss_tired() -> bool:
	return boss.is_empty() or not bool(boss.active) or str(boss.state) == "lelah"


func foe_data(n: Node3D) -> Dictionary:
	for f in foes:
		if f.node == n:
			return f
	return {}


func tame(n: Node3D) -> void:
	var f := foe_data(n)
	if f.is_empty():
		return
	f.state = "jinak"
	f.t = 0.0
	(f.rig as Node3D).play_once("sorak", 2.0)
	var tw := create_tween()
	tw.tween_property(n, "position:y", n.position.y + 1.2, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.6)
	tw.tween_callback(n.hide)


func retreat(n: Node3D) -> void:
	var f := foe_data(n)
	if f.is_empty():
		return
	f.state = "mundur"
	f.cool = 4.0
	push_player(n.global_position, 7.0)


func push_player(from: Vector3, force: float) -> void:
	var pl: CharacterBody3D = world.player
	var d: Vector3 = pl.global_position - from
	d.y = 0
	if d.length() < 0.01:
		d = Vector3(0, 0, 1)
	pl.velocity = d.normalized() * force + Vector3(0, 4.0, 0)
	pl.rig.play_once("kena", 0.45)


func active_foes() -> int:
	var n := 0
	for f in foes:
		if f.state != "jinak":
			n += 1
	return n


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	var pp: Vector3 = world.player.global_position
	for f in foes:
		var n: Node3D = f.node
		if f.state == "jinak" or not n.visible:
			continue
		var d := n.global_position.distance_to(pp)
		if d > ACTIVE_RANGE:
			continue
		f.cool = maxf(0.0, float(f.cool) - delta)
		var target: Vector3
		var spd := PATROL_SPEED
		match str(f.state):
			"patroli":
				target = f.b if f.to_b else f.a
				if n.position.distance_to(target) < 0.3:
					f.to_b = not f.to_b
				if d < CHASE_RANGE and f.cool <= 0.0 and not paused:
					f.state = "kejar"
			"kejar":
				target = world.to_local(pp)
				spd = CHASE_SPEED
				if d > CHASE_RANGE * 1.5:
					f.state = "patroli"
				elif d < TOUCH_RANGE and not paused:
					f.state = "menantang"
					foe_touched.emit(n)
			"menantang":
				target = n.position
				spd = 0.0
			"mundur":
				target = f.home
				if f.cool <= 0.0:
					f.state = "patroli"
		var to: Vector3 = target - n.position
		to.y = 0
		var moving := spd > 0.0 and to.length() > 0.1
		if moving:
			n.position += to.normalized() * minf(spd * delta, to.length())
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 8.0))
		(f.rig as Node3D).animate(delta, spd if moving else 0.0, true)
	_boss(delta, pp)


func _boss(delta: float, pp: Vector3) -> void:
	if boss.is_empty() or not bool(boss.active):
		return
	var n: Node3D = boss.node
	if n.global_position.distance_to(pp) > ACTIVE_RANGE:
		return
	boss.t = float(boss.t) + delta
	var rig: Node3D = boss.rig
	match str(boss.state):
		"berjaga":
			var to: Vector3 = world.to_local(pp) - n.position
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 3.0))
			rig.animate(delta, 0.0, true)
			if float(boss.t) > 3.0:
				boss.state = "hentakan"
				boss.t = 0.0
		"hentakan":
			var ph := float(boss.t) / 1.2
			n.position.y = float(boss.home.y) + sin(clampf(ph, 0.0, 1.0) * PI) * 1.4
			rig.animate(delta, 0.0, false)
			if ph >= 1.0:
				n.position.y = float(boss.home.y)
				boss_stomp.emit()
				if n.global_position.distance_to(pp) < 5.5:
					push_player(n.global_position, 9.0)
				boss.state = "lelah"
				boss.t = 0.0
				rig.play_once("interaksi", 4.0)
		"lelah":
			rig.animate(delta, 0.0, true)
			n.rotation.x = 0.25
			if float(boss.t) > 4.5:
				n.rotation.x = 0.0
				boss.state = "berjaga"
				boss.t = 0.0
