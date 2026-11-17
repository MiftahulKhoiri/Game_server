extends Node
## Dunia yang hidup (roadmap no. 186-200), di atas world3d.gd:
##   - Serbuan monster ke Desa Awal saat malam tertentu: goblin, orc, dan binatang tulang dari hutan muncul di
##     tepi desa, warga berlindung. Paket 1.2.0: radar muncul sendiri selama penyerbu ada dan hilang saat semuanya
##     kalah; serbuan terbatas (setelah RAID_GOAL dikalahkan tidak ada penyerbu baru); penjaga desa ikut bertarung
##     dan melukai penyerbu (maks. Roamer.wounds 3, HP awal >= 55% di server) tetapi hanya pahlawan yang bisa
##     mengalahkan mereka.
##   - Hari Pasar (potongan harga toko), papan wilayah Aman/Waspada/Berbahaya.
##   - Tempat rahasia berkilau samar yang bisa diperiksa, genangan air saat hujan, tanaman ladang
##     yang tumbuh dari hari ke hari.
## Jadwal kejadian dihitung dari jam dunia bersama (atmosphere.gd = internal/game/worldtime.go); semua
## hadiah diberikan server.

const Maps = preload("res://games/adventure/scripts/maps.gd")
const Atmosphere = preload("res://games/adventure/scripts/atmosphere.gd")
const HeroFx = preload("res://games/adventure/scripts/hero_fx.gd")
const Roamer = preload("res://games/adventure/scripts/roamer.gd")

const RAID_GOAL := 5             # sama dengan RaidGoal di server
const RAID_REWARD := 200
const RAID_RESPAWN_S := 8.0      # penyerbu pengganti muncul setiap sekian detik selama serbuan
const GUARD_LEASH := 9.0         # penjaga melawan penyerbu sejauh ini dari posnya (tidak mengejar ke mana-mana)
const GUARD_EVERY := 2.2         # jeda serangan penjaga (detik)
const ARCHER_REACH := 7.5        # pemanah penjaga (Laras) menyerang dari jauh
const MELEE_REACH := 1.3         # penjaga lain menyerang dari dekat (sama dengan Warga.GUARD_MELEE)
const MAX_WOUNDS := 3            # sama dengan MaxGuardWounds di server (internal/game/worldtime.go)
const SECRET_SHOW := 4.5         # kilau tempat rahasia terlihat dari sejauh ini
const SECRET_NEAR := 1.8         # tombol Periksa muncul dari sejauh ini
const PUDDLES := 26
const CROP_STAGES := ["Bibit", "Tunas", "Tumbuh", "Siap panen"]
const ZONE_COLOR := {"aman": Color("9fe6a0"), "waspada": Color("ffd27a"), "berbahaya": Color("ff8a7a")}

var world = null                 # world3d.gd
var raid_on := false
var raiders: Array = []          # Roamer penyerbu yang masih hidup di desa
var cleared_note := false        # pesan "desa aman" sudah ditampilkan untuk serbuan ini
var banner_text := ""            # isi papan (untuk uji)
var crop_stage := -1

var _banner: Label
var _banner_top := 0.0
var _banner_low := false
var _claim: Button
var _acc := 0.0
var _respawn := 0.0
var _guard_acc := 0.0
var _sparkles: Dictionary = {}   # id rahasia -> Node3D
var _puddles: Array[MeshInstance3D] = []
var _puddle_mat: StandardMaterial3D
var _busy := false


func setup(w: Node) -> void:
	world = w
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_banner = Label.new()
	# Di kanan, di bawah jam/tombol Menu: tidak menutupi bar nyawa di kiri atas.
	_banner.position = Vector2(300, 66)
	_banner.size = Vector2(408, 60)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", 21)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_banner)
	_claim = Button.new()
	_claim.text = "Ambil hadiah pertahanan (%d emas)" % RAID_REWARD
	_claim.position = Vector2(288, 130)
	_claim.size = Vector2(420, 70)
	_claim.add_theme_font_size_override("font_size", 24)
	_claim.focus_mode = Control.FOCUS_NONE
	_claim.visible = false
	_claim.pressed.connect(_on_claim)
	layer.add_child(_claim)


## Ikut tata letak layar world3d (roadmap no. 218): papan dan tombol hadiah menempel ke kanan atas.
func layout(dx: float, top: float) -> void:
	_banner_top = top
	if _banner != null:
		_banner.position = Vector2(300 + dx, 66 + top)
		_update_banner()
		_claim.position = Vector2(288 + dx, 130 + top)


## Dipanggil world3d setiap kali peta baru dimuat (node lama sudah ikut terhapus bersama _npc_root).
func on_map(map_id: String) -> void:
	raiders = []
	raid_on = false
	_sparkles = {}
	_puddles = []
	crop_stage = -1
	if world == null or world._npc_root == null:
		return
	_build_secrets(map_id)
	if Atmosphere.outdoors(map_id) and not Maps.is_interior(map_id):
		_build_puddles(map_id)
	if map_id == Maps.DEFAULT_MAP:
		_build_crops(map_id)
	_acc = 1.0  # periksa kejadian di bingkai berikutnya
	_update_banner()


func tick(delta: float) -> void:
	if world == null:
		return
	_acc += delta
	if _acc >= 1.0:
		_acc = 0.0
		_check_raid()
		_update_banner()
	if raid_on:
		_respawn += delta
		if _respawn >= RAID_RESPAWN_S:
			_respawn = 0.0
			_prune()
			if raiders.size() < raid_want():
				_spawn_raider()
		_assign_guards()
		_guard_acc += delta
		if _guard_acc >= GUARD_EVERY:
			_guard_acc = 0.0
			_guards_fight()
		_check_cleared()
	_update_sparkles()
	if _puddle_mat != null:
		_puddle_mat.albedo_color.a = clampf(Atmosphere.rain, 0.0, 1.0) * 0.55
		var on := Atmosphere.rain > 0.05
		for p in _puddles:
			p.visible = on


# --- Serbuan Goblin (no. 189-192, 200) ---

func raid_here() -> bool:
	return world._map_id == Maps.DEFAULT_MAP and Atmosphere.raid_active()


func _check_raid() -> void:
	var want := raid_here()
	if want and not raid_on:
		raid_on = true
		_respawn = 0.0
		cleared_note = raid_want() <= 0  # sudah dihalau sebelumnya (masuk lagi ke desa malam yang sama)
		if raid_want() > 0:
			world.notify("Serbuan monster ke Desa Awal! Goblin dan binatang tulang dari hutan menyerang. Radar menunjukkan posisi mereka.", "kejadian", "SERBUAN MONSTER!")
			world._set_status("Monster menyerbu desa! Warga berlindung, penjaga ikut melawan. Kalahkan %d penyerbu." % RAID_GOAL)
		for _i in raid_want():
			_spawn_raider()
	elif not want and raid_on:
		_end_raid()


## Jumlah penyerbu yang boleh hidup sekarang: serbuan terbatas, total penyerbu = RAID_GOAL. Kemenangan
## pemain tercatat di server (state.raid.kills); setelah RAID_GOAL tidak ada penyerbu baru.
func raid_want() -> int:
	return clampi(RAID_GOAL - raid_kills(), 0, Maps.RAID_N)


## Radar serbuan tampil sendiri selama serbuan masih punya penyerbu hidup di desa.
func radar_on() -> bool:
	if not raid_on:
		return false
	for r in raiders:
		if r != null and not r.dying and world._roamers.has(r):
			return true
	return false


## Semua penyerbu sudah dikalahkan pahlawan: radar hilang sendiri (lihat radar_on), papan berubah "desa aman".
func raid_cleared() -> bool:
	return raid_on and raid_want() <= 0 and not radar_on()


func _check_cleared() -> void:
	if cleared_note or not raid_cleared():
		return
	cleared_note = true
	for w in world._warga:
		w.guard_target = Vector2(-999, -999)
	world.notify("Semua penyerbu dikalahkan! Desa aman, radar dimatikan.", "kejadian", "DESA AMAN!")
	world._set_status("Penyerbu habis. Ambil hadiah pertahanan desa di kanan atas.")


func _spawn_raider() -> void:
	var lvl := int(Session.player.state.get("level", 1))
	var kinds: Array = []
	for k: Dictionary in Maps.RAID_KINDS:
		if int(k.lv) <= lvl:
			kinds.append(k)
	if kinds.is_empty():
		kinds = [Maps.RAID_KINDS[0]]
	var spots: Array[Vector2] = []
	for s in Maps.RAID_SPAWNS:
		if s.distance_to(world._pos) > 5.0:
			spots.append(s)
	if spots.is_empty():
		return
	var at: Vector2 = spots[randi() % spots.size()]
	var r: Roamer = world._make_roamer(kinds[randi() % kinds.size()], world._map_id, at, randi())
	# Penyerbu bergerak masuk ke tengah desa, lalu berkeliaran di sana.
	r.origin = Vector2(22.5, 22.5) + Vector2(randf_range(-9.0, 9.0), randf_range(-6.0, 6.0))
	r.home = r.origin
	world._roamers.append(r)
	raiders.append(r)


func _prune() -> void:
	var alive: Array = []
	for r in raiders:
		if r != null and world._roamers.has(r) and not r.dying:
			alive.append(r)
	raiders = alive


func _end_raid() -> void:
	raid_on = false
	for w in world._warga:
		w.guard_on = false
		w.guard_target = Vector2(-999, -999)
	_prune()
	for r in raiders:
		if r.fight:
			continue  # yang sedang dilawan tetap sampai pertarungannya selesai
		world._roamers.erase(r)
		if is_instance_valid(r.node):
			r.node.queue_free()
	raiders = []
	world._show_toast("Serbuan berakhir")
	world._set_status("Fajar tiba, para penyerbu mundur dari desa.")


## Penjaga desa (paket 1.2.0) memilih penyerbu terdekat dari posnya (dalam GUARD_LEASH) yang tidak sedang
## bertarung dengan pemain. Pemanah (warga diam, mis. Laras) tetap di tempat dan menyerang dari jauh.
func _assign_guards() -> void:
	_prune()
	for w in world._warga:
		var guard: bool = Maps.RAID_GUARDS.has(w.id)
		w.guard_on = guard
		if not guard:
			continue
		w.guard_reach = ARCHER_REACH if w.speed <= 0.0 else MELEE_REACH
		var best: Roamer = null
		var best_d := GUARD_LEASH
		for r in raiders:
			if r.fight or r.dying:
				continue
			var d: float = r.pos.distance_to(w.home)
			if w.speed <= 0.0:
				d = r.pos.distance_to(w.pos)
				if d > ARCHER_REACH:
					continue
			if d < best_d:
				best = r
				best_d = d
		w.guard_target = best.pos if best != null else Vector2(-999, -999)


## Serangan penjaga: penyerbu dalam jangkauan ditahan sejenak dan terluka (paling banyak MAX_WOUNDS luka).
## Penjaga TIDAK bisa mengalahkan penyerbu: luka hanya mengurangi HP awal saat pahlawan melawannya.
func _guards_fight() -> void:
	_prune()
	for w in world._warga:
		if not w.guard_on or w.inside or not w.has_guard_target():
			continue
		var best: Roamer = null
		for r in raiders:
			if not r.fight and not r.dying and r.pos.distance_to(w.guard_target) < 0.05:
				best = r
				break
		if best == null or best.pos.distance_to(w.pos) > w.guard_reach + 0.4:
			continue
		best.stun = maxf(best.stun, 1.6)
		best.chasing = false
		var to: Vector2 = best.pos - w.pos
		w.yaw = atan2(to.x, to.y)
		if w.model != null and is_instance_valid(w.model) and w.model.has_method("play_attack"):
			w.model.call("play_attack")
		var at := Vector3(best.pos.x, best.top * 0.6, best.pos.y)
		var text := ""
		if best.wounds < MAX_WOUNDS:
			best.wounds += 1
			text = "%s: -%d%%" % [w.nama, 15]
			HeroFx.burst(world, at, Color("ffd27a") if w.speed <= 0.0 else Color("bfe8ff"), 10, 2.4)
		else:
			text = "Ditahan %s! Kalahkan sekarang!" % w.nama
			HeroFx.burst(world, at, Color("bfe8ff"), 6, 1.8)
		if world._fight != null:
			world._fight._float_text(Vector3(best.pos.x, best.top + 0.7, best.pos.y), text, Color("bfe8ff"), 38)


func raid_kills() -> int:
	var raid: Dictionary = Session.player.state.get("raid", {})
	return int(raid.get("kills", 0)) if int(raid.get("id", -1)) == Atmosphere.raid_id() else 0


func raid_claimable() -> bool:
	var raid: Dictionary = Session.player.state.get("raid", {})
	return raid_on and raid_kills() >= RAID_GOAL and not bool(raid.get("claimed", false))


func _on_claim() -> void:
	if _busy or Session.offline:
		return
	_busy = true
	var res: Dictionary = await Api.raid_claim()
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		world._refresh_hud()
		world.notify("Desa terlindungi! Hadiah pertahanan +%d emas." % RAID_REWARD, "hadiah", "Desa terlindungi! +%d emas" % RAID_REWARD)
	else:
		world._set_status(str(res.error))
	_update_banner()


# --- papan kejadian & wilayah (no. 195-196, 200) ---

## Lebar baris terpanjang papan (rata kanan): dipakai untuk memeriksa tumpukan dengan papan ujian.
func _banner_lebar_teks() -> float:
	var font := _banner.get_theme_font("font")
	var fs := _banner.get_theme_font_size("font_size")
	var w := 0.0
	for line in _banner.text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return minf(w, _banner.size.x)

func _update_banner() -> void:
	if _banner == null or world == null:
		return
	# Papan ujian wilayah (kanan atas) tampil: papan ini turun ke bawahnya supaya tidak bertumpuk.
	var hud: Control = world._hutan_hud
	# Turun ke bawah papan ujian hanya bila keduanya bertumpuk mendatar (layar mendatar sempit, mis. 16:9).
	_banner_low = hud != null and hud.visible and hud.position.x + hud.size.x + 8.0 > _banner.position.x + _banner.size.x - _banner_lebar_teks()
	if _banner_low:
		_banner.position.y = hud.position.y + hud.size.y + 6.0
	else:
		_banner.position.y = 66.0 + _banner_top
	var map_id: String = world._map_id
	var text := ""
	var col := Color.WHITE
	if raid_on and raid_want() <= 0 and not radar_on():
		text = "DESA AMAN!\nSerbuan dihalau %d/%d" % [mini(raid_kills(), RAID_GOAL), RAID_GOAL]
		col = Color("9fe6a0")
	elif raid_on:
		text = "SERBUAN MONSTER!\nPertahanan desa %d/%d" % [mini(raid_kills(), RAID_GOAL), RAID_GOAL]
		col = Color("ff8a7a")
	elif map_id == Maps.DEFAULT_MAP and Atmosphere.market_active():
		text = "Hari Pasar\nPotongan %d%% di semua toko" % Atmosphere.MARKET_PERCENT
		col = Color("ffe08a")
	elif Maps.ZONA.has(map_id):
		var z: Array = Maps.ZONA[map_id]
		var danger := str(z[0])
		text = {"aman": "Wilayah aman", "waspada": "Waspada: Lv %d+", "berbahaya": "Berbahaya: Lv %d+"}[danger]
		if danger != "aman":
			text = text % int(z[1])
			if Atmosphere.outdoors(map_id) and Atmosphere.is_night():
				text += "\nMalam: musuh lebih kuat, XP +25%"
		col = ZONE_COLOR[danger]
	if world._story != null and not Session.offline:
		var g: String = world._story.goal()
		if g != "":
			text = (text + "\n" if text != "" else "") + "Tujuan: " + g  # cerita utama The Last Dragon
	banner_text = text
	_banner.text = text
	_banner.modulate = col
	_claim.visible = raid_claimable()


# --- tempat rahasia (no. 199) ---

func _build_secrets(map_id: String) -> void:
	var found: Array = Session.player.state.get("secrets", [])
	for s: Dictionary in Maps.RAHASIA:
		if s.map != map_id or found.has(s.id):
			continue
		var node := Node3D.new()
		node.name = "Rahasia_" + str(s.id)
		node.position = Vector3(s.pos.x + 0.5, 0.0, s.pos.y + 0.5)
		var p := CPUParticles3D.new()
		var dot := SphereMesh.new()
		dot.radius = 0.035
		dot.height = 0.07
		dot.radial_segments = 6
		dot.rings = 3
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("fff2a8")
		dot.material = m
		p.mesh = dot
		p.amount = 10
		p.lifetime = 1.4
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4
		p.direction = Vector3.UP
		p.initial_velocity_min = 0.15
		p.initial_velocity_max = 0.4
		p.gravity = Vector3.ZERO
		p.position.y = 0.4
		node.add_child(p)
		node.visible = false
		world._npc_root.add_child(node)
		_sparkles[str(s.id)] = node


func _update_sparkles() -> void:
	for id: String in _sparkles:
		var n := _sparkles[id] as Node3D
		if is_instance_valid(n):
			n.visible = Vector2(n.position.x, n.position.z).distance_to(world._pos) < SECRET_SHOW


## id tempat rahasia di dekat pemain ("" bila tidak ada).
func secret_near() -> String:
	for id: String in _sparkles:
		var n := _sparkles[id] as Node3D
		if is_instance_valid(n) and Vector2(n.position.x, n.position.z).distance_to(world._pos) < SECRET_NEAR:
			return id
	return ""


func secret_anchor(id: String) -> Vector3:
	var n := _sparkles.get(id) as Node3D
	return n.position + Vector3(0, 1.3, 0) if n != null else Vector3.ZERO


func inspect(id: String) -> void:
	if _busy or Session.offline:
		return
	_busy = true
	await world._flush_save()  # server memeriksa posisi tersimpan
	var res: Dictionary = await Api.world_secret(id)
	_busy = false
	if not res.ok:
		world._set_status(str(res.error))
		return
	Session.merge_server_player(res.data)
	world._refresh_hud()
	var nama := id
	for s: Dictionary in Maps.RAHASIA:
		if s.id == id:
			nama = str(s.name)
	world.notify("Tempat rahasia ditemukan: %s." % nama, "hadiah", "Tempat rahasia: %s!" % nama)
	world._set_status("Kamu menemukan %s. Hadiahnya masuk ke ransel." % nama)
	var n := _sparkles.get(id) as Node3D
	if n != null and is_instance_valid(n):
		HeroFx.burst(world, n.position + Vector3(0, 0.6, 0), Color("ffd24a"), 30, 3.5)
		n.queue_free()
	_sparkles.erase(id)


# --- genangan air (no. 193) ---

func _build_puddles(map_id: String) -> void:
	_puddle_mat = StandardMaterial3D.new()
	_puddle_mat.albedo_color = Color(0.32, 0.42, 0.55, 0.0)
	_puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puddle_mat.metallic = 0.6
	_puddle_mat.roughness = 0.05
	var rows := Maps.rows(map_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id)
	var tries := 0
	while _puddles.size() < PUDDLES and tries < 600:
		tries += 1
		var y := rng.randi_range(1, rows.size() - 2)
		var x := rng.randi_range(1, rows[y].length() - 2)
		if not ".=".contains(rows[y][x]):
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(0.25, 0.55)
		cm.bottom_radius = cm.top_radius
		cm.height = 0.01
		cm.radial_segments = 14
		mi.mesh = cm
		mi.material_override = _puddle_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(x + rng.randf_range(0.2, 0.8), 0.025, y + rng.randf_range(0.2, 0.8))
		mi.scale = Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))
		mi.visible = false
		world._npc_root.add_child(mi)
		_puddles.append(mi)


# --- tanaman ladang (no. 194) ---

## Tanaman di petak ladang (T) tumbuh tiap hari permainan: bibit -> tunas -> tumbuh -> siap panen.
func _build_crops(map_id: String) -> void:
	crop_stage = posmod(Atmosphere.world_day(), CROP_STAGES.size())
	var rows := Maps.rows(map_id)
	var spots: Array[Vector3] = []
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "T":
				for i in 3:
					spots.append(Vector3(x + 0.5, 0.0, y + 0.2 + i * 0.3))
	if spots.is_empty():
		return
	var h: float = [0.08, 0.18, 0.32, 0.42][crop_stage]
	var col: Color = [Color("8fbf5a"), Color("6fae45"), Color("4f9a3a"), Color("d9b440")][crop_stage]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, h, 0.12)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	mesh.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var off := Vector3((float(i % 5) - 2.0) * 0.12, h * 0.5 + 0.05, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i] + off))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tanaman"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world._npc_root.add_child(mmi)
