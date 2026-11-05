extends Node
## Alat pengembang: menjalankan dunia 3D lalu menyimpan tangkapan layar.
## Dipakai lewat ~/Claude/shot.sh (Xvfb + llvmpipe); tidak ikut ke APK.
## Lingkungan: SHOT_MAP, SHOT_X, SHOT_Z (petak), SHOT_YAW (kamera, derajat),
## SHOT_OUT (berkas keluaran), SHOT_SCENE (world | battle).

func _gallery() -> void:
	const Models = preload("res://scripts/models.gd")
	var ids: Array = OS.get_environment("SHOT_IDS").split(",")
	var root := Node3D.new()
	get_tree().root.add_child.call_deferred(root)
	await get_tree().process_frame
	await get_tree().process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("5a7a9a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("e8f0ff")
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-25), 0)
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("4c7a4c")
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	for i in ids.size():
		var m: Node3D = Models.create(ids[i])
		m.position = Vector3((i % 2) * 2.0 - 1.0, 0, (i / 2) * -2.0)
		m.rotation.y = deg_to_rad(float(OS.get_environment("SHOT_TURN")) if OS.get_environment("SHOT_TURN") != "" else 0.0)
		root.add_child(m)
	var cam := Camera3D.new()
	cam.fov = 34
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	root.add_child(cam)
	cam.position = Vector3(0, 4.2, 6.2)
	cam.look_at(Vector3(0, 0.5, -1.6))
	cam.current = true
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(540, 960, Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


func _battle() -> void:
	Session.use_offline_player()
	var id := OS.get_environment("SHOT_ENEMY") if OS.get_environment("SHOT_ENEMY") != "" else "goblin"
	Session.battle = {"enemy_id": id, "enemy_name": id, "enemy_hp": 20, "enemy_max_hp": 24}
	var scene: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(540, 960, Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


func _ready() -> void:
	if OS.get_environment("SHOT_SCENE") == "models":
		_gallery()
		return
	if OS.get_environment("SHOT_SCENE") == "battle":
		_battle()
		return
	var map_id := OS.get_environment("SHOT_MAP")
	var x := float(OS.get_environment("SHOT_X")) if OS.get_environment("SHOT_X") != "" else 5.5
	var z := float(OS.get_environment("SHOT_Z")) if OS.get_environment("SHOT_Z") != "" else 7.5
	Session.use_offline_player()
	if map_id != "":
		Session.player.state.map = map_id
	Session.player.state.x = int(x)
	Session.player.state.y = int(z)
	Session.player.state.fx = x
	Session.player.state.fz = z
	var scene: Node = load("res://scenes/world3d.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().create_timer(0.3).timeout
	if OS.get_environment("SHOT_YAW") != "":
		scene._cam_yaw = deg_to_rad(float(OS.get_environment("SHOT_YAW")))
	if OS.get_environment("SHOT_PITCH") != "":
		scene._cam_pitch = deg_to_rad(float(OS.get_environment("SHOT_PITCH")))
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(540, 960, Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	print("tangkapan layar: ", OS.get_environment("SHOT_OUT"))
	get_tree().quit()
