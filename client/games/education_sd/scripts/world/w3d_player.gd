extends CharacterBody3D
## Pemain 3D: gerak relatif kamera, lari, lompat, kamera orang-ketiga (SpringArm3D, tidak menembus dinding).
## Masukan: move_input (joystick layar / WASD), look() (geser layar kanan / mouse), jump(), run.

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")

const WALK := 4.2
const RUN := 7.2
const GRAVITY := 22.0
const JUMP := 8.2
const LOOK_SENS := 0.006
## Kamera orang-ketiga bebas 360° (2.3.0): yaw tanpa batas (dibungkus 0..TAU), pitch dibatasi supaya kamera
## tidak terbalik / masuk tanah, jarak bisa diatur (scroll mouse / cubit dua jari), mengikuti halus di _process.
const PITCH_MIN := -1.2  # menunduk paling dalam (kamera tinggi di atas)
const PITCH_MAX := 0.35  # mendongak (kamera rendah, tetap di atas tanah)
const ZOOM_MIN := 2.2
const ZOOM_MAX := 8.0
const CAM_HEIGHT := 1.25

var move_input := Vector2.ZERO  # x kanan, y maju (dari HUD)
var run := false
var spawn := Vector3.ZERO
var rig: Node3D
var cam: Camera3D
var yaw := 0.0
var pitch := -0.32
var frozen := false  # saat dialog/menu terbuka
var _jump_req := false
var _pivot: Node3D
var _arm: SpringArm3D
var distance := 4.4
var zoom_max := ZOOM_MAX
var speed_bonus := 1.0


func setup(look: Dictionary) -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.5
	shape.shape = cap
	shape.position.y = 0.75
	add_child(shape)
	rig = Rig.new()
	rig.shirt = look.get("shirt", Color("e05a4f"))
	rig.long_hair = bool(look.get("long_hair", false))
	rig.hair = Color("6b3a1e") if rig.long_hair else Color("3a2a20")
	rig.hat = str(look.get("hat", ""))
	rig.acc = str(look.get("acc", ""))
	if str(look.get("model_path", "")) != "":
		# Pahlawan anak buatan sendiri (Fase 9): baju diwarnai sesuai kostum, topi/aksesori ditempel ke tulang.
		rig.glb_path = str(look.model_path)
		rig.glb_height = 1.47
		rig.glb_recolor = {"Baju": rig.shirt}
	elif str(look.get("model", "")) != "":
		rig.glb_id = str(look.model)
		rig.glb_height = 1.45
		rig.glb_tint = rig.shirt.lerp(Color.WHITE, 0.55)
	add_child(rig)
	rig.build()
	if rig.is_glb():
		rig.attach_costume()
	var disc := Rig.part(Rig.cyl(0.42, 0.42, 0.02, 16), Color(0, 0, 0, 0.25), Vector3(0, 0.03, 0))
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0, 0, 0, 0.22)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_pivot = Node3D.new()
	_pivot.top_level = true
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.collision_mask = 1  # dinding, bangunan, batu, batang pohon, tanah
	_arm.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_pivot.add_child(_arm)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 220.0
	_arm.add_child(cam)
	_arm.add_excluded_object(get_rid())


func place(pos: Vector3, face_yaw: float) -> void:
	global_position = pos
	spawn = pos
	yaw = face_yaw
	rig.rotation.y = face_yaw + PI
	velocity = Vector3.ZERO
	_update_camera(true)


func look(rel: Vector2) -> void:
	yaw = fposmod(yaw - rel.x * LOOK_SENS, TAU)
	pitch = clampf(pitch - rel.y * LOOK_SENS, PITCH_MIN, PITCH_MAX)


func zoom(step: float) -> void:
	distance = clampf(distance + step, ZOOM_MIN, zoom_max)


func jump() -> void:
	_jump_req = true


func _keyboard() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	var inp := move_input if move_input.length() > 0.05 else _keyboard()
	var running := run or Input.is_physical_key_pressed(KEY_SHIFT)
	if frozen:
		inp = Vector2.ZERO
		_jump_req = false
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := (right * inp.x + fwd * inp.y)
	var spd := (RUN if running else WALK) * minf(1.0, inp.length()) * speed_bonus
	var target := dir.normalized() * spd if dir.length() > 0.01 else Vector3.ZERO
	var accel := 14.0 if is_on_floor() else 5.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * maxf(spd, WALK))
	velocity.z = move_toward(velocity.z, target.z, accel * delta * maxf(spd, WALK))
	if is_on_floor():
		if _jump_req:
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * delta
	_jump_req = false
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z)
	rig.vy = velocity.y
	if hv.length() > 0.3:
		var want := atan2(velocity.x, velocity.z)
		if is_on_floor() and absf(angle_difference(rig.rotation.y, want)) > 2.3 and rig._act_t <= 0.0:
			rig.play_once("putar", 0.3)  # berbalik arah
		rig.rotation.y = lerp_angle(rig.rotation.y, want, minf(1.0, delta * 12.0))
	rig.animate(delta, hv.length(), is_on_floor())
	if global_position.y < -8.0:
		global_position = spawn
		velocity = Vector3.ZERO


## Kamera diperbarui di _process (laju layar), bukan di langkah fisika, supaya tidak tersendat/bergetar.
func _process(delta: float) -> void:
	_update_camera(false, delta)


func _update_camera(snap: bool, delta := 0.016) -> void:
	var target := global_position + Vector3(0, CAM_HEIGHT, 0)
	var k := 1.0 if snap else 1.0 - exp(-delta * 12.0)
	_pivot.global_position = _pivot.global_position.lerp(target, k)
	_pivot.rotation = Vector3(pitch, yaw, 0)
	_arm.spring_length = distance if snap else lerpf(_arm.spring_length, distance, 1.0 - exp(-delta * 8.0))


## Arah hadap karakter (untuk memilih objek interaksi yang ada di depan).
func facing() -> Vector3:
	return Vector3(sin(rig.rotation.y), 0, cos(rig.rotation.y))
