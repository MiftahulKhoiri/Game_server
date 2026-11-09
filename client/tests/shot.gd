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
	if OS.get_environment("SHOT_MAP") != "":
		Session.player.state.map = OS.get_environment("SHOT_MAP")
	if OS.get_environment("SHOT_HEROID") != "":
		Session.player.state.hero = OS.get_environment("SHOT_HEROID")
	var id := OS.get_environment("SHOT_ENEMY") if OS.get_environment("SHOT_ENEMY") != "" else "goblin"
	Session.battle = {"enemy_id": id, "enemy_name": id, "enemy_hp": 20, "enemy_max_hp": 24}
	var scene: Node = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().create_timer(1.2).timeout
	# Tanpa server: isi keadaan pertarungan secara manual supaya tombol dan penunjuk tampak.
	var now := Time.get_ticks_msec()
	scene._lines.clear()
	var demo: Array[String] = ["Kamu menyerang: -6 HP.", "Tebasan Kuat! -13 HP.", "Musuh menyerang: -3 HP."]
	scene._add_lines(demo)
	scene._ready_at["skill1"] = now + 3200
	scene._ready_at["skill2"] = now + 9000
	scene._ready_at["attack"] = now + 400
	scene._enemy_at = now + 800
	scene._last_sync = now + 100000
	scene._pop("Tebasan! -13", Color("ff9a3c"), false, 44)
	scene._pop("-3", Color("ff5c5c"), true, 44)
	await get_tree().create_timer(0.25).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(540, 960, Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


func _profile() -> void:
	Session.use_offline_player()
	var scr: CanvasLayer = load("res://scripts/profile.gd").new()
	get_tree().root.add_child.call_deferred(scr)
	await get_tree().create_timer(0.5).timeout
	scr.open()
	scr._select(int(OS.get_environment("SHOT_HERO")) if OS.get_environment("SHOT_HERO") != "" else 0)
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(540, 960, Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


## Layar Atribut, tab Pendamping, dengan SHOT_SOLDIERS prajurit dipasang (SHOT_REST menunggu di kem).
func _atribut() -> void:
	Session.use_offline_player()
	Session.player.state["soldiers"] = int(OS.get_environment("SHOT_SOLDIERS")) if OS.get_environment("SHOT_SOLDIERS") != "" else 5
	Session.player.state["soldiers_rest"] = int(OS.get_environment("SHOT_REST")) if OS.get_environment("SHOT_REST") != "" else 0
	var scr: Node = load("res://scenes/atribut.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scr)
	await get_tree().create_timer(0.8).timeout
	scr._show_page(1)
	await get_tree().create_timer(0.6).timeout
	for _i in int(OS.get_environment("SHOT_STEP")) if OS.get_environment("SHOT_STEP") != "" else 0:
		scr._on_sol_step(-1)
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(540, 960, Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


func _ready() -> void:
	if OS.get_environment("SHOT_SCENE") == "atribut":
		_atribut()
		return
	if OS.get_environment("SHOT_SCENE") == "profile":
		_profile()
		return
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
	# SHOT_HOUR (0-24) dan SHOT_RAIN (0-1) memaksa waktu dan hujan untuk tangkapan layar.
	const Atmo = preload("res://scripts/atmosphere.gd")
	if OS.get_environment("SHOT_HOUR") != "":
		Atmo.hour_override = float(OS.get_environment("SHOT_HOUR"))
	if OS.get_environment("SHOT_RAIN") != "":
		Atmo.rain = float(OS.get_environment("SHOT_RAIN"))
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
	if OS.get_environment("SHOT_MENU") != "":
		scene._toggle_menu()
		if OS.get_environment("SHOT_MENU") == "pengaturan":
			scene._menu._show_page(false)
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(540, 960, Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	print("tangkapan layar: ", OS.get_environment("SHOT_OUT"))
	get_tree().quit()
