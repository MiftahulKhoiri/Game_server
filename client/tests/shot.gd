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
		# SHOT_DRESS = "pakaian,senjata,pelindung,helm" (mis. "1,pedang_rune,zirah_besi,helm_besi")
		if OS.get_environment("SHOT_DRESS") != "":
			var d: PackedStringArray = OS.get_environment("SHOT_DRESS").split(",")
			Models.dress(m, int(d[0]), {"weapon": d[1], "armor": d[2], "helmet": d[3]})
		m.position = Vector3((i % 2) * 2.0 - 1.0, 0, (i / 2) * -2.0)
		m.rotation.y = deg_to_rad(float(OS.get_environment("SHOT_TURN")) if OS.get_environment("SHOT_TURN") != "" else 0.0)
		root.add_child(m)
	var cam := Camera3D.new()
	cam.fov = 34
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	root.add_child(cam)
	cam.position = Vector3(0, 4.2, 6.2) * (float(OS.get_environment("SHOT_ZOOM")) if OS.get_environment("SHOT_ZOOM") != "" else 1.0)
	cam.look_at(Vector3(0, 0.5, -1.6))
	cam.current = true
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
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
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
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
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
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
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


## Layar dialog dengan warga SHOT_NPC (mis. "warga:mpu_karta").
func _dialog() -> void:
	Session.use_offline_player()
	Session.talk_npc = OS.get_environment("SHOT_NPC")
	var scene: Node = load("res://scenes/dialog.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().create_timer(1.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


## Layar apa saja dari SHOT_PATH (mis. res://scenes/login.tscn), pemain uji tanpa server.
func _file() -> void:
	if OS.get_environment("SHOT_OFFLINE") != "0":
		Session.use_offline_player()
	var scene: Node = load(OS.get_environment("SHOT_PATH")).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().create_timer(1.2).timeout
	if OS.get_environment("SHOT_CALL") != "" and scene.has_method(OS.get_environment("SHOT_CALL")):
		scene.call(OS.get_environment("SHOT_CALL"))
		await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	var vs := img.get_size()
	img.resize(960, int(960.0 * vs.y / vs.x), Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()


func _ready() -> void:
	if OS.get_environment("SHOT_SCENE") == "file":
		_file()
		return
	if OS.get_environment("SHOT_SCENE") == "dialog":
		_dialog()
		return
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
	if OS.get_environment("SHOT_QUALITY") != "":
		Session.quality = int(OS.get_environment("SHOT_QUALITY"))
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
	if OS.get_environment("SHOT_PERF") != "":
		scene._names.debug = true
	if OS.get_environment("SHOT_YAW") != "":
		scene._cam_yaw = deg_to_rad(float(OS.get_environment("SHOT_YAW")))
	if OS.get_environment("SHOT_PITCH") != "":
		scene._cam_pitch = deg_to_rad(float(OS.get_environment("SHOT_PITCH")))
	if OS.get_environment("SHOT_JURNAL") != "":
		scene._jurnal.quests = [{"id": "q1", "title": "Selamatkan Nenek", "status": "active", "progress": 2, "target_count": 5, "giver": "nenek_penjual", "reward_text": "30 emas, 2 Ramuan", "description": "Kalahkan Ayam Liar yang merusak kebun Nenek."},
			{"id": "q2", "title": "Selamatkan Petani", "status": "available", "giver": "petani", "reward_gold": 40, "description": "Bantu Petani mengusir rubah."}]
		scene._jurnal.open(int(OS.get_environment("SHOT_JURNAL")))
	if OS.get_environment("SHOT_NARASI") != "":  # layar narasi cerita langkah SHOT_NARASI (-1 = prolog)
		scene._story._queue.append(scene._story.NARASI[int(OS.get_environment("SHOT_NARASI"))])
		scene._story._show_next()
	if OS.get_environment("SHOT_MENU") != "":
		scene._toggle_menu()
		if OS.get_environment("SHOT_MENU") == "pengaturan":
			scene._menu._show_page(false)
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_png(OS.get_environment("SHOT_OUT"))
	print("tangkapan layar: ", OS.get_environment("SHOT_OUT"))
	if OS.get_environment("SHOT_PERF") != "":
		_perf_report(scene)
		await _perf_split(scene)
	get_tree().quit()


## Berapa panggilan gambar yang hilang bila satu golongan benda disembunyikan.
func _perf_split(scene: Node) -> void:
	var groups := {
		"MultiMesh (rumput, pohon, pagar, batu)": "MultiMeshInstance3D",
		"MeshInstance (bangunan, bentuk)": "MeshInstance3D",
		"Label3D (nama, papan)": "Label3D",
		"Partikel": "CPUParticles3D",
		"UI 2D (HUD, tombol)": "CanvasLayer",
	}
	var base := await _draws()
	print("PERF pisah: total %d" % base)
	var ui := {}
	for cl in scene.find_children("*", "CanvasLayer", true, false):
		if not cl.visible:
			continue
		for c in cl.find_children("*", "CanvasItem", true, false):
			if (c as CanvasItem).is_visible_in_tree():
				var k := "%s/%s" % [cl.name, c.get_class()]
				ui[k] = int(ui.get(k, 0)) + 1
	var uk := ui.keys()
	uk.sort_custom(func(a, b): return ui[a] > ui[b])
	for k in uk.slice(0, 15):
		print("PERF ui %4d  %s" % [ui[k], k])
	for cl in scene.find_children("*", "CanvasLayer", true, false):
		if not cl.visible:
			continue
		for c in cl.get_children():
			if c is CanvasItem and (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
				var d := await _draws()
				(c as CanvasItem).visible = true
				var sc: Script = c.get_script()
				print("PERF ui-item %4d  %s %s %s" % [base - d, c.name, c.get_class(), sc.resource_path.get_file() if sc != null else ""])
	for g in groups:
		var hidden: Array = []
		for n in scene.find_children("*", groups[g], true, false):
			if n.visible:
				n.visible = false
				hidden.append(n)
		var d := await _draws()
		print("PERF pisah: %-40s %4d" % [g, base - d])
		for n in hidden:
			n.visible = true
	var sun := scene.get("_sun") as DirectionalLight3D
	if sun != null and sun.shadow_enabled:
		sun.shadow_enabled = false
		print("PERF pisah: %-40s %4d" % ["bayangan matahari", base - await _draws()])
		sun.shadow_enabled = true


func _draws() -> int:
	for i in 3:
		await get_tree().process_frame
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


## SHOT_PERF=1: angka performa + rincian benda yang digambar (untuk mencari penyebab panggilan gambar).
func _perf_report(scene: Node) -> void:
	const Perf = preload("res://scripts/perf.gd")
	print("PERF ", Perf.text(Perf.snapshot()))
	var nl = scene.get("_names")
	if nl != null:
		for k in nl.reasons:
			print("PERF nama tersembunyi: %s — %s" % [k, nl.reasons[k]])
	var counts := {}
	var shadow := 0
	var lights := 0
	for n in scene.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var key := vi.get_class()
		if vi is MeshInstance3D and (vi as MeshInstance3D).mesh != null:
			key += "(%d permukaan)" % (vi as MeshInstance3D).mesh.get_surface_count()
		counts[key] = int(counts.get(key, 0)) + 1
		if vi is GeometryInstance3D and (vi as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow += 1
		if vi is OmniLight3D:
			lights += 1
	var by_mesh := {}
	var cam := get_viewport().get_camera_3d()
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		if cam != null and cam.global_position.distance_to(mi.global_position) > cam.far:
			continue
		var nm := mi.mesh.resource_name if mi.mesh.resource_name != "" else mi.mesh.get_class()
		var top: Node = mi
		while top.get_parent() != null and top.get_parent() != scene and top.get_parent().get_parent() != scene:
			top = top.get_parent()
		var root_kid: Node = mi
		while root_kid.get_parent() != scene and root_kid.get_parent() != null:
			root_kid = root_kid.get_parent()
		var tn := str(root_kid.name) + "/" + str(top.name)
		if tn.begins_with("@"):
			tn = "(tanpa nama)"
		var k2 := "%s @ %s" % [nm, tn.left(24)]
		by_mesh[k2] = int(by_mesh.get(k2, 0)) + 1
	var medan := scene.get("_terrain") as Node
	if medan != null:
		var kinds := {}
		for c in medan.get_children():
			var sc: Script = c.get_script()
			var k := "%s %s anak=%d" % [c.get_class(), sc.resource_path.get_file() if sc != null else "-", c.get_child_count()]
			kinds[k] = int(kinds.get(k, 0)) + 1
		for k in kinds:
			if int(kinds[k]) > 2:
				print("PERF medan %4d  %s" % [kinds[k], k])
	var mk := by_mesh.keys()
	mk.sort_custom(func(a, b): return by_mesh[a] > by_mesh[b])
	for k in mk.slice(0, 25):
		print("PERF mesh %4d  %s" % [by_mesh[k], k])
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	for k in keys.slice(0, 14):
		print("PERF   %4d  %s" % [counts[k], k])
	print("PERF bayangan: %d benda melempar bayangan, lampu titik menyala: %d" % [shadow, lights])
