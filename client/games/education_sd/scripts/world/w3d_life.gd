extends Node3D
## Dunia hidup (Fase 6): warga berjalan berpatroli, hewan berkeliaran, burung terbang, ikan melompat, benda
## bergoyang/berputar, siklus siang-malam, cuaca cerah/hujan.
## Hemat baterai: semua makhluk diperbarui dari SATU _process (bukan satu skrip per makhluk), dan hanya yang
## dekat pemain (jarak profil grafis) yang dianimasikan; yang jauh disembunyikan. Jumlah dibatasi per profil.

signal rain_changed(raining: bool)

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")

const DAY_LENGTH := 300.0  # detik per siklus siang-malam
const RAIN_CHECK := 60.0
const RAIN_DURATION := 35.0

var world: Node3D
var entities: Array = []  # [{kind, node, home, t, data, active}]
var raining := false
var cycle := 0.18  # 0..1, mulai pagi
var day_factor := 1.0
var _check_t := 0.0
var _rain_t := 0.0
var _rain: CPUParticles3D
var _rng := RandomNumberGenerator.new()
var range_m := 60.0
var rain_amount := 250
var cycle_on := true


func setup(w: Node3D, profile: Dictionary, seed_value: int) -> void:
	world = w
	_rng.seed = seed_value
	range_m = float(profile.range)
	rain_amount = int(profile.get("rain", 0))
	cycle_on = bool(profile.get("cycle", true))


func add(kind: String, node: Node3D, data: Dictionary = {}) -> void:
	entities.append({"kind": kind, "node": node, "home": node.position, "t": _rng.randf() * 10.0, "data": data, "active": true})


func count(kind: String) -> int:
	var n := 0
	for e in entities:
		if e.kind == kind:
			n += 1
	return n


func active_count() -> int:
	var n := 0
	for e in entities:
		if e.active:
			n += 1
	return n


static func make_animal(color: Color) -> Node3D:
	var a := Node3D.new()
	a.add_child(Rig.part(Rig.capsule(0.32, 1.2), color, Vector3(0, 0.75, 0)))
	(a.get_child(0) as Node3D).rotation.x = PI / 2.0
	a.add_child(Rig.part(Rig.sphere(0.28), color.lightened(0.1), Vector3(0, 1.05, 0.6)))
	a.add_child(Rig.part(Rig.sphere(0.05), Color("2b2440"), Vector3(0.12, 1.12, 0.84)))
	a.add_child(Rig.part(Rig.sphere(0.05), Color("2b2440"), Vector3(-0.12, 1.12, 0.84)))
	var legs: Array = []
	for p in [Vector3(-0.18, 0.55, 0.35), Vector3(0.18, 0.55, 0.35), Vector3(-0.18, 0.55, -0.35), Vector3(0.18, 0.55, -0.35)]:
		var pivot := Node3D.new()
		pivot.position = p
		pivot.add_child(Rig.part(Rig.cyl(0.07, 0.07, 0.55, 6), color.darkened(0.3), Vector3(0, -0.27, 0)))
		a.add_child(pivot)
		legs.append(pivot)
	a.add_child(Rig.part(Rig.capsule(0.05, 0.4), color.darkened(0.2), Vector3(0, 0.9, -0.7)))
	a.set_meta("legs", legs)
	return a


static func make_bird(color: Color) -> Node3D:
	var b := Node3D.new()
	b.add_child(Rig.part(Rig.sphere(0.18), color, Vector3.ZERO, Vector3(1, 0.8, 1.4)))
	b.add_child(Rig.part(Rig.sphere(0.1), color.lightened(0.2), Vector3(0, 0.08, 0.24)))
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.1 * side, 0.02, 0)
		pivot.add_child(Rig.part(Rig.box(Vector3(0.5, 0.03, 0.22)), color.darkened(0.15), Vector3(0.25 * side, 0, 0)))
		b.add_child(pivot)
		wings.append(pivot)
	b.set_meta("wings", wings)
	return b


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	var ppos: Vector3 = world.player.global_position
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		for e in entities:
			var n: Node3D = e.node
			if not is_instance_valid(n):
				continue
			var d := n.global_position.distance_to(ppos)
			e.active = d < range_m
			if e.kind in ["animal", "bird", "villager"]:
				n.visible = d < range_m + 15.0
	for e in entities:
		if e.active and is_instance_valid(e.node):
			_update(e, delta)
	_sky(delta)
	_weather(delta, ppos)


func _update(e: Dictionary, delta: float) -> void:
	e.t = float(e.t) + delta
	var n: Node3D = e.node
	var t: float = e.t
	match str(e.kind):
		"bob":
			n.position.y = e.home.y + sin(t * 1.6) * 0.15
			n.rotation.z = sin(t * 1.1) * 0.05
		"bubble":
			var s := 1.0 + sin(t * 4.0) * 0.12
			n.scale = Vector3(s, s, s)
		"orbit":
			n.rotation.y += delta * float(e.data.get("speed", 0.5))
		"fish":
			var period := 4.0
			var ph := fmod(t, period)
			if ph < 1.0:
				n.visible = true
				n.position = e.home + Vector3(ph * 1.6 - 0.8, sin(ph * PI) * 1.1, 0)
				n.rotation.z = -cos(ph * PI) * 0.9
			else:
				n.visible = false
		"bird":
			var r: float = e.data.get("radius", 12.0)
			var sp: float = e.data.get("speed", 0.35)
			var a := t * sp
			n.position = e.home + Vector3(cos(a) * r, sin(t * 0.7) * 1.2, sin(a) * r)
			n.rotation.y = -a
			for wing in n.get_meta("wings"):
				var side := 1.0 if (wing as Node3D).position.x > 0 else -1.0
				(wing as Node3D).rotation.z = sin(t * 14.0) * 0.7 * side
		"animal":
			_wander(e, delta)
		"villager":
			_patrol(e, delta)


func _wander(e: Dictionary, delta: float) -> void:
	var n: Node3D = e.node
	var data: Dictionary = e.data
	if not data.has("target") or float(data.get("wait", 0.0)) > 0.0:
		data.wait = float(data.get("wait", 0.0)) - delta
		if float(data.wait) <= 0.0 and not data.has("target"):
			var r: float = data.get("radius", 4.0)
			data.target = e.home + Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r))
		_legs(n, 0.0)
		if n.has_meta("rig"):
			n.get_meta("rig").animate(delta, 0.0, true)
		return
	var tgt: Vector3 = data.target
	var to := tgt - n.position
	to.y = 0
	if to.length() < 0.2:
		data.erase("target")
		data.wait = _rng.randf_range(1.0, 3.5)
		return
	if n.has_meta("rig"):
		n.get_meta("rig").animate(delta, 1.1, true)
	var step := to.normalized() * minf(1.1 * delta, to.length())
	n.position += step
	n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 6.0))
	_legs(n, e.t)


func _legs(n: Node3D, t: float) -> void:
	var legs: Array = n.get_meta("legs", [])
	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sin(t * 9.0 + (PI if i % 2 == 0 else 0.0)) * 0.5 if t > 0.0 else 0.0


func _patrol(e: Dictionary, delta: float) -> void:
	var n: Node3D = e.node
	var data: Dictionary = e.data
	var rig = data.rig
	var pts: Array = data.points
	if world.has_method("is_talking_to") and world.is_talking_to(n):
		rig.animate(delta, 0.0, true)
		return
	if float(data.get("wait", 0.0)) > 0.0:
		data.wait = float(data.wait) - delta
		rig.animate(delta, 0.0, true)
		return
	var tgt: Vector3 = pts[int(data.get("i", 0))]
	var to := tgt - n.position
	to.y = 0
	if to.length() < 0.15:
		data.i = (int(data.get("i", 0)) + 1) % pts.size()
		data.wait = _rng.randf_range(2.0, 4.0)
		rig.play_once("interaksi", 1.2)  # aktivitas: menyapa / bekerja
		return
	n.position += to.normalized() * minf(1.4 * delta, to.length())
	n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 6.0))
	rig.animate(delta, 1.4, true)


# --- Siang-malam & cuaca ------------------------------------------------------------------------------

func _sky(delta: float) -> void:
	if not cycle_on:
		return
	cycle = fmod(cycle + delta / DAY_LENGTH, 1.0)
	# Siang 0..0,7; senja-malam singkat 0,7..1 (malam tetap terang untuk anak-anak).
	day_factor = 1.0 if cycle < 0.62 else (0.45 + 0.55 * clampf(absf(cycle - 0.85) / 0.23, 0.0, 1.0))
	apply_light()


func apply_light() -> void:
	var dim := day_factor * (0.7 if raining else 1.0)
	if world._sun != null:
		world._sun.light_energy = lerpf(0.22, 0.65, dim)
		world._sun.light_color = Color(1.0, lerpf(0.72, 0.93, day_factor), lerpf(0.55, 0.82, day_factor))
	if world._env != null:
		world._env.ambient_light_energy = lerpf(0.1, 0.15, dim)
		var sky_mat: ProceduralSkyMaterial = world._env.sky.sky_material
		var day_top: Color = world.sky_day_top
		sky_mat.sky_top_color = day_top.lerp(Color("2b3a6b"), 1.0 - day_factor).lerp(Color("8a94a6"), 0.5 if raining else 0.0)
		sky_mat.sky_horizon_color = (world.sky_day_horizon as Color).lerp(Color("f4a36b"), (1.0 - day_factor) * 0.8)


func is_night() -> bool:
	return day_factor < 0.7


func _weather(delta: float, ppos: Vector3) -> void:
	_rain_t += delta
	if not raining and _rain_t >= RAIN_CHECK:
		_rain_t = 0.0
		if _rng.randf() < 0.3:
			set_rain(true)
	elif raining and _rain_t >= RAIN_DURATION:
		_rain_t = 0.0
		set_rain(false)
	if _rain != null:
		_rain.global_position = ppos + Vector3(0, 9, 0)


func set_rain(on: bool) -> void:
	raining = on
	_rain_t = 0.0
	if on and rain_amount > 0 and _rain == null:
		_rain = CPUParticles3D.new()
		_rain.amount = rain_amount
		_rain.lifetime = 0.7
		_rain.local_coords = false
		_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_rain.emission_box_extents = Vector3(14, 0.5, 14)
		_rain.direction = Vector3(0, -1, 0)
		_rain.spread = 3.0
		_rain.initial_velocity_min = 16.0
		_rain.initial_velocity_max = 18.0
		_rain.gravity = Vector3(0, -10, 0)
		var drop := BoxMesh.new()
		drop.size = Vector3(0.025, 0.45, 0.025)
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.75, 0.85, 1.0, 0.6)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		drop.material = dm
		_rain.mesh = drop
		add_child(_rain)
	if _rain != null:
		_rain.emitting = on
	apply_light()
	rain_changed.emit(on)
