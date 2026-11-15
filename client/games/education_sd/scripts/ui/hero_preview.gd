extends SubViewportContainer
## Pratinjau 3D pahlawan anak (laki-laki/perempuan, GLB buatan sendiri) untuk layar profil petualang.
## Berputar pelan; set_look() membangun ulang model dengan warna baju, topi, dan aksesori baru.

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")

var rig: Node3D
var _vp: SubViewport
var _pivot: Node3D
var spin := true


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.95, 3.6)
	cam.rotation.x = -0.12
	cam.fov = 38.0
	_vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("fff3e0")
	env.environment.ambient_light_energy = 0.55
	_vp.add_child(env)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var disc := MeshInstance3D.new()
	disc.mesh = Rig.cyl(0.5, 0.54, 0.08, 32)
	disc.material_override = Rig.mat(Color("7cc95a"))
	disc.position.y = -0.04
	_pivot.add_child(disc)


## look: {hero: "laki"/"perempuan", shirt: Color, hat: String, acc: String}
func set_look(look: Dictionary) -> void:
	if rig != null:
		rig.queue_free()
	rig = Rig.new()
	rig.shirt = look.get("shirt", Color("e05a4f"))
	rig.long_hair = str(look.get("hero", "laki")) == "perempuan"
	rig.hair = Color("6b3a1e") if rig.long_hair else Color("3a2a20")
	rig.hat = str(look.get("hat", ""))
	rig.acc = str(look.get("acc", ""))
	var path: String = Rig.hero_path("female" if rig.long_hair else "male")
	if ResourceLoader.exists(path):
		rig.glb_path = path
		rig.glb_height = 1.47
		rig.glb_recolor = {"Baju": rig.shirt}
	_pivot.add_child(rig)
	rig.build()
	if rig.is_glb():
		rig.attach_costume()


func _process(delta: float) -> void:
	if spin:
		_pivot.rotation.y += delta * 0.6
	if rig != null and rig.has_method("animate"):
		rig.animate(delta, 0.0, true)
