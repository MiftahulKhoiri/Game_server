extends SubViewportContainer
## Potret 3D yang "membacakan" pesan: kepala & bahu penduduk / Bu Guru di pojok dialog. Saat suara
## pembaca berbicara, tokoh mengangguk dan bergoyang pelan, dan gelombang suara di pojok bergerak.

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const Voice := preload("res://games/education_sd/scripts/voice.gd")


class Waves extends Control:
	var on := false
	var t := 0.0

	func _draw() -> void:
		if not on:
			return
		for i in 3:
			var h := 8.0 + absf(sin(t * 9.0 + i * 1.3)) * 18.0
			draw_rect(Rect2(Vector2(i * 9.0, 28.0 - h), Vector2(6, h)), Color("3f7fd8"))


var rig: Node3D
var model := ""
var talking := false
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _waves: Waves
var _t := 0.0
var _voice: Node


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(150, 170)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.4, 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("fff3e0")
	env.environment.ambient_light_energy = 0.6
	_vp.add_child(env)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_waves = Waves.new()
	_waves.name = "Waves"
	_waves.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_waves.size = Vector2(30, 30)
	add_child(_waves)


## model: id GLB penduduk (res://assets/models/<model>.glb). Tidak dibangun ulang bila sama.
func set_model(m: String, tint := "", height := 1.7) -> void:
	if m == model and rig != null:
		return
	model = m
	if rig != null:
		rig.queue_free()
		rig = null
	if m == "" or not ResourceLoader.exists(Rig.MODEL_DIR + m + ".glb"):
		return
	rig = Rig.new()
	rig.glb_id = m
	rig.glb_height = height
	if tint != "":
		rig.glb_tint = Color.from_string(tint, Color.WHITE)
	_pivot.add_child(rig)
	rig.build()
	_cam.position = Vector3(0, height * 0.8, 2.3)
	_cam.rotation = Vector3(-0.08, 0, 0)


func _enter_tree() -> void:
	_voice = Voice.shared
	if _voice != null and not _voice.started.is_connected(_on_start):
		_voice.started.connect(_on_start)
		_voice.ended.connect(_on_end)
		_voice.word.connect(_on_word)
	talking = _voice != null and bool(_voice.speaking)


func _exit_tree() -> void:
	if _voice != null and is_instance_valid(_voice) and _voice.started.is_connected(_on_start):
		_voice.started.disconnect(_on_start)
		_voice.ended.disconnect(_on_end)
		_voice.word.disconnect(_on_word)
	_voice = null


func _on_start() -> void:
	talking = true


func _on_end() -> void:
	talking = false


func _on_word(_a: int, _b: int) -> void:
	if rig != null:
		rig.play_once("interaksi", 0.22)


func _process(delta: float) -> void:
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not is_visible_in_tree():
		return
	if rig != null:
		rig.animate(delta, 0.0, true)
	if talking:
		_t += delta
		_pivot.rotation.y = sin(_t * 2.3) * 0.14
		_pivot.position.y = absf(sin(_t * 7.0)) * 0.025
	else:
		_pivot.rotation.y = lerpf(_pivot.rotation.y, 0.0, minf(1.0, delta * 6.0))
		_pivot.position.y = lerpf(_pivot.position.y, 0.0, minf(1.0, delta * 6.0))
	_waves.position = Vector2(size.x - 36, size.y - 36)
	_waves.on = talking
	_waves.t = _t
	_waves.queue_redraw()
