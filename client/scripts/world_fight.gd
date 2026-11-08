extends Node
## Pertarungan langsung di dunia (sejak v0.32.0): memukul atau disentuh musuh tidak lagi memindahkan
## layar. Musuh yang sama tetap berdiri di depan pemain, pemain terus bergerak, memukul, menendang,
## bertahan, minum ramuan, atau kabur, semuanya spontan seperti memukul pohon.
##
## Aturan tetap diurus server (pertarungan real-time di internal/game/battle.go): tiap aksi
## (attack / skill1 / defend / potion / flee) dikirim ke /v1/battle/action dan hasilnya (kejadian,
## HP, hadiah) dianimasikan di dunia. Serangan musuh dijadwalkan server; klien menanyakan keadaan tepat
## setelah jadwalnya lewat. Pertarungan bos tetap memakai layar pertarungan khusus.

const Maps = preload("res://scripts/maps.gd")
const Roamer = preload("res://scripts/roamer.gd")
const HeroFx = preload("res://scripts/hero_fx.gd")
const HudBars = preload("res://scripts/hud_bars.gd")

const READY_SLACK_MS := 150     # toleransi tombol ditekan sedikit sebelum cooldown habis
const POLL_MS := 4000           # tanya server paling lambat tiap sekian ms
const LATE_MS := 120            # setelah jadwal serangan musuh lewat sekian ms: tanya server
const FLEE_DIST := 6.0          # menjauh dari musuh sampai sini = otomatis mencoba kabur
const WARN_MS := 700            # musuh menandai serangan sekian ms sebelum jadwal
const SAFE_STEPS_AFTER := 4     # langkah aman setelah pertarungan
const RESPAWN_S := 45.0         # musuh pengganti muncul sekian detik setelah satu tumbang
const BOSS_IDS := ["raja_goblin"]
const POTION_ID := "ramuan"
const ACTION_BUTTONS := {"attack": "tangan", "skill1": "kaki", "defend": "hindar"}

## Bar nyawa musuh yang selalu menghadap kamera: bidang kecil dengan shader (isi mengikuti `ratio`).
const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
uniform float ratio = 1.0;
uniform vec4 fill : source_color = vec4(0.27, 0.9, 0.1, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec3 c = UV.x <= ratio ? fill.rgb : vec3(0.16, 0.06, 0.06);
	if (UV.x < 0.025 || UV.x > 0.975 || UV.y < 0.14 || UV.y > 0.86) {
		c = vec3(0.04);
	}
	ALBEDO = c;
}
"""

var world = null            # world3d.gd (dunia); dibiarkan tanpa tipe agar bisa memanggil anggotanya
var active := false        # ada pertarungan yang sedang berjalan di dunia
var roamer: Roamer         # musuh yang sedang dilawan
var last_result := ""       # hasil pertarungan terakhir: won / lost / fled (untuk uji)

var _starting := false
var _busy := false         # ada permintaan ke server yang belum dijawab
var _pending := ""         # satu aksi yang menunggu giliran kirim
var _finished := false
var _enemy_at := 0         # kapan musuh menyerang berikutnya (jam lokal, ms)
var _enemy_iv := 2000
var _ally_at := 0         # kapan pendamping menyerang berikutnya (jam lokal, ms; 0 = tanpa pendamping)
var _ready_at: Dictionary = {}
var _cd_max: Dictionary = {}
var _last_sync := 0
var _next_ask := 0
var _enemy_hp := 0
var _enemy_max := 1
var _enemy_name := ""
var _bar: MeshInstance3D
var _bar_mat: ShaderMaterial
var _bar_name: Label3D
var _flash: ColorRect
var _btn_potion: Button
var _btn_flee: Button
var _respawn_left: Array[float] = []


func setup(w: Node) -> void:
	world = w
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn_potion = _make_button(layer, "Ramuan", Vector2(24, 790), Vector2(176, 72))
	_btn_flee = _make_button(layer, "Kabur", Vector2(212, 790), Vector2(140, 72))
	_btn_potion.pressed.connect(player_action.bind("potion"))
	_btn_flee.pressed.connect(player_action.bind("flee"))


func _make_button(layer: CanvasLayer, text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	b.visible = false
	layer.add_child(b)
	if "_buttons" in world:
		world._buttons.append(b)  # jari di tombol tidak memutar kamera
	return b


## Sedang memulai atau menjalani pertarungan (musuh lain tidak boleh ikut menyerang).
func busy() -> bool:
	return active or _starting


# --- memulai ---

## Musuh `r` menyentuh/terkena pemain: mulai pertarungan di server. `first_action` = pukulan pertama
## yang langsung dikirim begitu pertarungan siap.
func engage(r: Roamer, first_action := "") -> void:
	if busy() or world._locked or r.dying:
		return
	_starting = true
	roamer = r
	r.fight = true
	r.chasing = false
	world._set_status("%s menyerang!" % r.label)
	await world._flush_save()  # posisi harus tersimpan dulu; server memilih musuh sesuai peta
	var res: Dictionary = await Api.battle_start(false, r.id)
	if not res.ok and res.status == 409:
		res = await Api.battle_get()  # sudah ada pertarungan di server: lanjutkan
	_starting = false
	if not is_inside_tree():
		return
	if res.ok and _has_battle(res.data):
		var b: Dictionary = res.data.battle
		if BOSS_IDS.has(str(b.get("enemy_id", ""))):
			r.fight = false
			world._locked = true
			world._enter_battle(res.data)
			return
		_begin(res.data, first_action)
	else:
		r.fight = false
		r.stun = 6.0
		roamer = null
		world._set_status(str(res.get("error", "Pertarungan gagal dimulai")))


## Pertemuan acak di ladang hutan / kerikil: server mengundi musuhnya, lalu musuh itu muncul di dekat pemain.
func engage_random() -> void:
	if busy() or world._locked:
		return
	_starting = true
	world._set_status("Sesuatu bergerak di sekitarmu...")
	await world._flush_save()
	var res: Dictionary = await Api.battle_start(false, "")
	if not res.ok and res.status == 409:
		res = await Api.battle_get()
	_starting = false
	if not is_inside_tree():
		return
	if res.ok and _has_battle(res.data):
		_spawn_and_begin(res.data)
	else:
		world._set_status(str(res.get("error", "")))


## Ada pertarungan berjalan di server saat dunia dibuka (mis. aplikasi ditutup di tengah pertarungan).
func resume() -> void:
	if busy():
		return
	var res: Dictionary = await Api.battle_get()
	if not is_inside_tree() or not res.ok or not _has_battle(res.data):
		return
	_spawn_and_begin(res.data)


func _has_battle(data: Dictionary) -> bool:
	var b: Variant = data.get("battle")
	return b is Dictionary and not (b as Dictionary).is_empty()


## Musuh dari server dimunculkan di dekat pemain (bos: layar pertarungan khusus), lalu pertarungan dimulai.
func _spawn_and_begin(data: Dictionary) -> void:
	var b: Dictionary = data.battle
	if BOSS_IDS.has(str(b.get("enemy_id", ""))):
		world._locked = true
		world._enter_battle(data)
		return
	var at := _spot_near(world._pos)
	var kind := {"id": str(b.get("enemy_id", "")), "name": str(b.get("enemy_name", "Musuh")), "lv": 1}
	var r: Roamer = world._make_roamer(kind, world._map_id, at, randi())
	world._roamers.append(r)
	roamer = r
	r.fight = true
	_begin(data, "")


## Titik bebas 2-4 petak dari `p` untuk memunculkan musuh; cadangan: tepat di depan pemain.
func _spot_near(p: Vector2) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var start := rng.randf() * TAU
	for i in 16:
		var ang := start + float(i) * TAU / 16.0
		var dist := rng.randf_range(2.4, 3.6)
		var cand := p + Vector2(cos(ang), sin(ang)) * dist
		if Maps.roam_free(world._map_id, cand) and Maps.roam_path_free(world._map_id, p, cand):
			return cand
	return p + world._facing() * 1.3


func _begin(data: Dictionary, first_action: String) -> void:
	Session.merge_server_player(data.player)
	var b: Dictionary = data.battle
	Session.battle = b
	active = true
	_finished = false
	_pending = ""
	_busy = false
	_ready_at = {}
	_read_view(b, Time.get_ticks_msec())
	_enemy_hp = int(b.get("enemy_hp", 1))
	_enemy_max = maxi(1, int(b.get("enemy_max_hp", 1)))
	_enemy_name = str(b.get("enemy_name", roamer.label))
	_make_bar()
	_last_sync = Time.get_ticks_msec()
	_next_ask = _last_sync + 300
	_btn_potion.visible = true
	_btn_flee.visible = true
	world._refresh_hud()
	world._set_status("%s! Pukul, tendang, atau bertahan." % _enemy_name)
	if first_action != "":
		player_action(first_action)


# --- aksi pemain ---

## Aksi pemain ke server. Mengembalikan true bila aksi dikirim (false: belum siap / tidak ada pertarungan).
func player_action(action: String) -> bool:
	if not active or _finished:
		return false
	if action == "potion" and (_potion_count() <= 0 or int(Session.player.state.hp) >= int(Session.player.state.max_hp)):
		world._set_status("Ramuan tidak bisa dipakai sekarang")
		return false
	if action == "skill1" and Session.energy() < 20:  # Skill1Energy di server
		world._set_status("Energi kurang! Minum Ramuan Kekuatan atau serang biasa dulu")
		return false
	if _cooldown_left(action) > READY_SLACK_MS:
		return false
	if _busy:
		_pending = action
		return false
	# Isi ulang langsung terasa; jawaban server menyetel nilai persisnya.
	var cd_ms := int(_cd_max.get(action, 1000))
	_ready_at[action] = Time.get_ticks_msec() + cd_ms
	if ACTION_BUTTONS.has(action):
		var key: String = ACTION_BUTTONS[action]
		world._cd[key] = float(cd_ms) / 1000.0
		world._cd_len[key] = float(cd_ms) / 1000.0
	_ask(action)
	return true


## Waktu isi ulang aksi (detik) menurut server; 0 bila siap.
func cooldown_s(action: String) -> float:
	return float(_cooldown_left(action)) / 1000.0


func _cooldown_left(action: String) -> int:
	return maxi(0, int(_ready_at.get(action, 0)) - Time.get_ticks_msec())


## Kirim aksi (atau sinkron bila kosong) lalu terapkan jawabannya.
func _ask(action: String) -> void:
	_busy = true
	_next_ask = Time.get_ticks_msec() + 300
	var res: Dictionary
	if action == "":
		res = await Api.battle_get()
	else:
		res = await Api.battle_action(action)
	if not is_inside_tree():
		return
	_busy = false
	_apply(res)
	if _pending != "" and active and not _finished:
		var next := _pending
		_pending = ""
		player_action(next)


func _apply(res: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	_last_sync = now
	if not res.ok:
		if int(res.get("status", 0)) == 404:
			_end_without_result()  # server tidak punya pertarungan lagi (selesai di tempat lain)
			return
		var msg := str(res.error)
		if msg.find("belum siap") < 0:  # "belum siap" hanya berarti jam kita meleset sedikit
			world._set_status(msg)
		_next_ask = now + 150
		return
	var data: Dictionary = res.data
	var status := str(data.get("status", "ongoing"))
	# Kalah: server memulangkan pemain ke desa, jadi posisinya ikut diambil dari server.
	Session.merge_server_player(data.player, status == "lost")
	var next_battle: Variant = data.get("battle")
	Session.battle = next_battle if next_battle is Dictionary else {}
	if not Session.battle.is_empty():
		_read_view(Session.battle, now)
		_enemy_hp = int(Session.battle.get("enemy_hp", _enemy_hp))
		_enemy_max = maxi(1, int(Session.battle.get("enemy_max_hp", _enemy_max)))
	elif status == "won":
		_enemy_hp = 0
	_update_bar()
	var events: Array = data.get("events", [])
	for i in events.size():
		if i == 0:
			_play_event(events[i])
		else:
			get_tree().create_timer(0.32 * float(i)).timeout.connect(_play_event.bind(events[i]))
	var lines: Array = data.get("log", [])
	if not lines.is_empty():
		world._set_status(str(lines[lines.size() - 1]))
	world._refresh_hud()
	if status != "ongoing":
		_finish(status, data)


## Ubah tampilan relatif server menjadi jadwal di jam lokal.
func _read_view(v: Dictionary, now: int) -> void:
	_enemy_at = now + int(v.get("enemy_next_ms", 2000))
	_enemy_iv = maxi(1, int(v.get("enemy_interval_ms", 2000)))
	var party: Array = Session.player.get("state", {}).get("party", [])
	_ally_at = now + int(v.get("ally_next_ms", 2400)) if not party.is_empty() else 0
	var left: Dictionary = v.get("cooldowns", {})
	for a: String in left:
		_ready_at[a] = now + int(left[a])
	_cd_max = v.get("cooldown_max", _cd_max)


# --- per bingkai ---

func _process(delta: float) -> void:
	_tick_respawn(delta)
	if not active or _finished:
		return
	var now := Time.get_ticks_msec()
	var until_hit := _enemy_at - now
	if roamer != null:
		roamer.warn = until_hit < WARN_MS and until_hit > -LATE_MS * 3
	# Saat musuh jatuh tempo menyerang (atau lama tak ada kabar): tanya server.
	var ally_due := _ally_at > 0 and now - _ally_at > LATE_MS
	if not _busy and now >= _next_ask and (until_hit < -LATE_MS or ally_due or now - _last_sync > POLL_MS):
		_ask("")
	# Menjauh dari musuh = mencoba kabur (server menentukan berhasil atau tidak).
	if roamer != null and not _busy and roamer.pos.distance_to(world._pos) > FLEE_DIST and _cooldown_left("flee") <= READY_SLACK_MS:
		world._set_status("Mencoba kabur...")
		player_action("flee")
	_update_buttons()
	if _flash != null and _flash.color.a > 0.0:
		_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.6)


func _update_buttons() -> void:
	var potions := _potion_count()
	var left := _cooldown_left("potion")
	_btn_potion.text = "Ramuan (%d)" % potions if left <= READY_SLACK_MS else "Ramuan %.1f d" % (float(left) / 1000.0)
	_btn_potion.disabled = potions <= 0 or int(Session.player.state.hp) >= int(Session.player.state.max_hp) or left > READY_SLACK_MS
	var fl := _cooldown_left("flee")
	_btn_flee.text = "Kabur" if fl <= READY_SLACK_MS else "Kabur %.1f d" % (float(fl) / 1000.0)
	_btn_flee.disabled = fl > READY_SLACK_MS


func _potion_count() -> int:
	for item: Dictionary in Session.player.state.inventory:
		if item.id == POTION_ID:
			return int(item.qty)
	return 0


# --- kejadian dari server ---

func _play_event(e: Dictionary) -> void:
	if not is_inside_tree() or world == null:
		return
	var kind := str(e.get("kind", ""))
	var dmg := int(e.get("dmg", 0))
	var heal := int(e.get("heal", 0))
	var enemy_at := Vector3.ZERO
	var enemy_top := 1.0
	if roamer != null and is_instance_valid(roamer.node):
		enemy_at = Vector3(roamer.pos.x, 0.0, roamer.pos.y)
		enemy_top = roamer.top
	var me_at := Vector3(world._pos.x, 0.0, world._pos.y)
	if str(e.get("who", "")) == "ally":
		_play_ally_event(e, enemy_at, enemy_top)
		_update_bar()
		return
	if str(e.get("who", "")) == "player":
		match kind:
			"attack", "crit", "skill1":
				if roamer != null and is_instance_valid(roamer.model) and roamer.model.has_method("play_hurt"):
					roamer.model.call("play_hurt")
				var col := Color("ffe9a0")
				var burst := 9
				if kind == "skill1":
					col = Color("ff9a3c")
					burst = 26
				elif kind == "crit":
					col = Color("ffd23c")
					burst = 16
				HeroFx.burst(world, enemy_at + Vector3(0, enemy_top * 0.55, 0), col, burst, 3.2)
				world._shake = 0.12 if kind == "attack" else 0.25
				_float_text(enemy_at + Vector3(0, enemy_top + 0.7, 0), ("-%d" % dmg) + ("!" if kind != "attack" else ""), col, 64 if kind != "attack" else 52)
			"skill2", "potion":
				HeroFx.burst(world, me_at + Vector3(0, 0.9, 0), Color("7dff8a"), 14, 2.0)
				_float_text(me_at + Vector3(0, 1.9, 0), "+%d" % heal, Color("7dff8a"), 56)
			"guard":
				HeroFx.ring(world, me_at + Vector3(0, 0.1, 0), Color("8fe08f"), 1.2, 0.3)
	else:
		if roamer != null and is_instance_valid(roamer.model) and roamer.model.has_method("play_attack"):
			roamer.model.call("play_attack")
		if roamer != null:
			roamer.warn = false
		if dmg > 0:
			world._shake = 0.3
			_flash.color.a = 0.32
			HeroFx.burst(world, me_at + Vector3(0, 0.9, 0), Color("ff5c5c"), 12, 2.6)
			_float_text(me_at + Vector3(0, 2.0, 0), "-%d" % dmg, Color("ff6b5c"), 60)
			var body: Variant = world._player
			if body != null and is_instance_valid(body) and body.has_method("play_hurt"):
				body.call("play_hurt")
		elif kind == "perfect":
			HeroFx.ring(world, me_at + Vector3(0, 0.9, 0), Color("7fd1ff"), 1.6, 0.4)
			_float_text(me_at + Vector3(0, 2.0, 0), "TANGKIS!", Color("7fd1ff"), 60)
		else:
			_float_text(me_at + Vector3(0, 2.0, 0), "Tertahan", Color("bfe8ff"), 48)
	_update_bar()


## Pendamping memukul musuh: animasi serang, percikan, dan angka kerusakan (lebih kecil dari pukulan pemain).
func _play_ally_event(e: Dictionary, enemy_at: Vector3, enemy_top: float) -> void:
	var hero := str(e.get("hero", ""))
	var comp: Variant = world._companions
	if comp != null:
		comp.attack(hero)
	if roamer != null and is_instance_valid(roamer.model) and roamer.model.has_method("play_hurt"):
		roamer.model.call("play_hurt")
	var col := Color("9fd8ff")
	HeroFx.burst(world, enemy_at + Vector3(0, enemy_top * 0.5, 0), col, 7, 2.6)
	_float_text(enemy_at + Vector3(0.35, enemy_top + 0.4, 0), "-%d" % int(e.get("dmg", 0)), col, 44)


## Angka/tulisan melayang yang naik lalu hilang (selalu menghadap kamera).
func _float_text(at: Vector3, text: String, color: Color, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.006
	label.font_size = size
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color(0.1, 0.02, 0.02)
	label.position = at
	world.add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", at.y + 1.1, 0.9)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.45)
	tw.chain().tween_callback(label.queue_free)


# --- bar nyawa musuh ---

func _make_bar() -> void:
	_clear_bar()
	if roamer == null or not is_instance_valid(roamer.node):
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(1.15, 0.16)
	var shader := Shader.new()
	shader.code = BAR_SHADER
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = shader
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	_bar.material_override = _bar_mat
	_bar.position = Vector3(0, roamer.top + 0.32, 0)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roamer.node.add_child(_bar)
	_bar_name = Label3D.new()
	_bar_name.text = _enemy_name
	_bar_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_name.no_depth_test = true
	_bar_name.pixel_size = 0.005
	_bar_name.font_size = 34
	_bar_name.outline_size = 8
	_bar_name.modulate = Color("ffc2b0")
	_bar_name.position = Vector3(0, roamer.top + 0.58, 0)
	roamer.node.add_child(_bar_name)
	_update_bar()


func _update_bar() -> void:
	if _bar_mat == null:
		return
	var ratio := clampf(float(_enemy_hp) / float(_enemy_max), 0.0, 1.0)
	_bar_mat.set_shader_parameter("ratio", ratio)
	_bar_mat.set_shader_parameter("fill", HudBars.hp_color(ratio))


func _clear_bar() -> void:
	if _bar != null and is_instance_valid(_bar):
		_bar.queue_free()
	if _bar_name != null and is_instance_valid(_bar_name):
		_bar_name.queue_free()
	_bar = null
	_bar_name = null
	_bar_mat = null


# --- selesai ---

func _finish(status: String, data: Dictionary) -> void:
	_finished = true
	last_result = status
	active = false
	_btn_potion.visible = false
	_btn_flee.visible = false
	Session.safe_steps = SAFE_STEPS_AFTER
	var r := roamer
	roamer = null
	match status:
		"won":
			var rw: Dictionary = data.get("rewards", {})
			var text := "Menang! +%d XP  +%d emas" % [int(rw.get("xp", 0)), int(rw.get("gold", 0))]
			var drop := str(rw.get("drop", ""))
			if drop != "":
				text += "\n" + str(world.ITEM_NAMES.get(drop, drop))
			if bool(rw.get("leveled_up", false)):
				text += "\nNAIK LEVEL! Lv %d" % int(rw.get("new_level", 0))
			world._show_toast(text)
			world._set_status("Menang! Barang masuk Ransel." if drop != "" else "Menang!")
			_defeat(r)
		"fled":
			world._set_status("Berhasil kabur!")
			if r != null:
				r.fight = false
				r.warn = false
				r.stun = 8.0
				r.home = r.pos
			_clear_bar()
		"lost":
			world._show_toast("Kamu kalah...")
			world._set_status("Kamu dibawa pulang ke desa")
			if r != null:
				r.fight = false
			_clear_bar()
			world._locked = true
			await get_tree().create_timer(1.6).timeout
			if is_inside_tree():
				get_tree().reload_current_scene()
		_:
			if r != null:
				r.fight = false
			_clear_bar()
	world._refresh_hud()


## Musuh tumbang: animasi mati, lalu dilepas dari dunia; musuh pengganti muncul beberapa saat kemudian.
func _defeat(r: Roamer) -> void:
	_clear_bar()
	if r == null:
		return
	r.dying = true
	r.fight = false
	r.warn = false
	world._roamers.erase(r)
	if is_instance_valid(r.model) and r.model.has_method("play_die"):
		r.model.call("play_die")
	if is_instance_valid(r.node):
		HeroFx.burst(world, Vector3(r.pos.x, r.top * 0.5, r.pos.y), Color("ffd23c"), 28, 4.0)
		var tw := r.node.create_tween()  # tween ikut mati bersama node, jadi tak ada panggilan ke objek yang sudah dibebaskan
		tw.tween_interval(1.6)
		tw.tween_callback(r.node.queue_free)
	_respawn_left.append(RESPAWN_S)


func _end_without_result() -> void:
	last_result = "gone"
	active = false
	_finished = true
	_btn_potion.visible = false
	_btn_flee.visible = false
	if roamer != null:
		roamer.fight = false
		roamer.warn = false
		roamer.stun = 4.0
	roamer = null
	Session.battle = {}
	_clear_bar()


func _tick_respawn(delta: float) -> void:
	if _respawn_left.is_empty():
		return
	for i in range(_respawn_left.size() - 1, -1, -1):
		_respawn_left[i] -= delta
		if _respawn_left[i] <= 0.0:
			_respawn_left.remove_at(i)
			world.respawn_roamer()
