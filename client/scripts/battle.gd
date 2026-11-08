extends Control
## Layar pertarungan REAL-TIME dengan cooldown (seperti game konsol).
## Semua hasil dihitung SERVER (docs/API.md): musuh menyerang sendiri tiap beberapa detik,
## pemain memilih Serang / Bertahan / Skill 1 / Skill 2 / Ramuan / Kabur. Layar ini hanya
## mengirim aksi, menghitung mundur cooldown dari waktu relatif server, dan menganimasikan
## kejadian (events) dari jawaban server.
## Arena 3D: ksatria dan musuh (model dari scripts/models.gd) saling berhadapan.

const WORLD_SCENE := "res://scenes/world3d.tscn"
const Models = preload("res://scripts/models.gd")
const WorldBuild = preload("res://scripts/world_build.gd")
const Heroes = preload("res://scripts/heroes.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const POTION_ID := "ramuan"
const MAX_LOG_LINES := 4
const SAFE_STEPS_AFTER_BATTLE := 3
const SYNC_LATE_MS := 80      # lewat sekian ms dari jadwal serangan musuh -> minta sinkron
const POLL_MS := 4000         # sinkron berkala bila tidak ada kabar
const EVENT_STAGGER := 0.32   # jeda animasi antar kejadian dalam satu jawaban
const READY_SLACK_MS := 150   # toleransi tombol ditekan sedikit sebelum cooldown habis
const HERO_X := -1.0          # posisi dasar ksatria dan musuh di arena (sumbu x)
const ENEMY_X := 1.0
const CHEST_Y := 0.9          # tinggi dada: tempat percikan muncul
const LUNGE_MS := 0.12        # waktu penyerang maju sampai kena; efek kena menunggu sebentar

## Tombol utama: aksi -> [judul, subjudul].
const MAIN_ACTIONS := [
	["attack", "Serang", ""],
	["defend", "Bertahan", ""],
	["skill1", "Skill 1", ""],   # subjudul = nama skill pahlawan (lihat _skill_name)
	["skill2", "Skill 2", ""],
]

var _enemy_id := ""
var _hero_rig: Node3D
var _enemy_rig: Node3D
var _enemy_name: Label
var _enemy_bar: ProgressBar
var _telegraph: ProgressBar
var _enemy_view: SubViewportContainer
var _fx: Control
var _flash: ColorRect          # kilat layar (merah saat pemain kena)
var _vp: SubViewport           # dunia 3D arena (tempat percikan ditambahkan)
var _cam: Camera3D             # kamera arena (digetarkan saat kena)
var _log: Label
var _player_label: Label
var _player_bar: ProgressBar
var _buttons: Dictionary = {}  # aksi -> Button
var _controls: Control
var _btn_continue: Button
var _lines: Array[String] = []

var _busy := false            # ada permintaan ke server yang belum dijawab
var _pending := ""            # satu aksi yang menunggu giliran kirim
var _finished := false
var _result := ""

# Waktu (Time.get_ticks_msec) tempat kejadian dijadwalkan; diturunkan dari selisih relatif server.
var _enemy_at := 0
var _ally_at := 0           # serangan pendamping berikutnya (jam lokal, ms; 0 = tanpa pendamping)
var _ally_rigs: Dictionary = {}  # id pahlawan -> model pendamping di arena
var _enemy_iv := 2000
var _ready_at: Dictionary = {}
var _cd_max: Dictionary = {}
var _guard_until := 0
var _shield_until := 0
var _last_sync := 0
var _next_ask := 0


func _ready() -> void:
	if Session.battle.is_empty():
		# Tidak ada pertarungan (mis. dibuka langsung dari editor): kembali ke peta.
		get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)
		return
	_enemy_id = str(Session.battle.get("enemy_id", ""))
	_build_ui()
	_read_view(Session.battle, Time.get_ticks_msec())
	_add_lines(["%s muncul!" % str(Session.battle.get("enemy_name", "Musuh"))])
	_refresh()
	_ask("")  # selaraskan jam dengan server sebelum musuh menyerang


# --- komunikasi dengan server ---

func _on_action(action: String) -> void:
	if _finished:
		return
	if _cooldown_left(action) > READY_SLACK_MS:
		return  # belum siap; tombol sudah tampak mati
	if action == "potion" and (_potion_count() <= 0 or int(Session.player.state.hp) >= int(Session.player.state.max_hp)):
		return
	if _busy:
		_pending = action
		return
	# Cooldown langsung terasa; jawaban server menyetel ulang nilai persisnya.
	_ready_at[action] = Time.get_ticks_msec() + int(_cd_max.get(action, 1000))
	_ask(action)


## Kirim aksi (atau sinkron bila action kosong) dan terapkan jawabannya.
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
	if _pending != "" and not _finished:
		var next := _pending
		_pending = ""
		_on_action(next)


func _apply(res: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	_last_sync = now
	if not res.ok:
		var msg := str(res.error)
		# "belum siap" hanya berarti jam kita meleset sedikit: cukup selaraskan lagi.
		if msg.find("belum siap") < 0:
			_add_lines([msg])
		_next_ask = now + 150
		_refresh()
		return

	var data: Dictionary = res.data
	var status := str(data.get("status", "ongoing"))
	# Jika kalah, server memulangkan pemain ke desa: posisi ikut diambil dari server.
	Session.merge_server_player(data.player, status == "lost")
	var next_battle: Variant = data.get("battle")
	Session.battle = next_battle if next_battle is Dictionary else {}
	if not Session.battle.is_empty():
		_read_view(Session.battle, now)

	var lines: Array[String] = []
	for line in data.get("log", []):
		lines.append(str(line))
	_add_lines(lines)
	_play_events(data.get("events", []))
	if status != "ongoing":
		_finish(status)
	_refresh()


## Ubah tampilan relatif server menjadi jadwal di jam lokal.
func _read_view(v: Dictionary, now: int) -> void:
	_enemy_at = now + int(v.get("enemy_next_ms", 2000))
	_ally_at = now + int(v.get("ally_next_ms", 2400)) if not _ally_rigs.is_empty() else 0
	_enemy_iv = maxi(1, int(v.get("enemy_interval_ms", 2000)))
	var left: Dictionary = v.get("cooldowns", {})
	for a: String in left:
		_ready_at[a] = now + int(left[a])
	_cd_max = v.get("cooldown_max", _cd_max)
	_guard_until = now + int(v.get("guard_ms", 0))
	_shield_until = now + int(v.get("shield_ms", 0))


func _cooldown_left(action: String) -> int:
	return maxi(0, int(_ready_at.get(action, 0)) - Time.get_ticks_msec())


func _process(_delta: float) -> void:
	if _finished or _enemy_bar == null:
		return
	var now := Time.get_ticks_msec()
	var until_hit := _enemy_at - now
	_telegraph.value = clampf(1.0 - float(until_hit) / float(_enemy_iv), 0.0, 1.0)
	# Saat musuh jatuh tempo menyerang (atau lama tak ada kabar): tanya server.
	var ally_due := _ally_at > 0 and now - _ally_at > SYNC_LATE_MS
	if not _busy and now >= _next_ask and (until_hit < -SYNC_LATE_MS or ally_due or now - _last_sync > POLL_MS):
		_ask("")
	_update_buttons(now)


# --- animasi ---

func _play(rig: Node3D, method: String) -> void:
	if rig != null and is_instance_valid(rig) and rig.has_method(method):
		rig.call(method)


func _play_events(events: Array) -> void:
	for i in events.size():
		if i == 0:
			_play_event(events[i])
		else:
			get_tree().create_timer(EVENT_STAGGER * i).timeout.connect(_play_event.bind(events[i]))


## Satu kejadian dari server: siapa menyerang, siapa kena, berapa banyak.
func _play_event(e: Dictionary) -> void:
	if not is_inside_tree():
		return
	var kind := str(e.get("kind", ""))
	var dmg := int(e.get("dmg", 0))
	var heal := int(e.get("heal", 0))
	if str(e.get("who", "")) == "ally":
		var rig: Node3D = _ally_rigs.get(str(e.get("hero", "")))
		if rig != null:
			_play(rig, "play_attack")
			_lunge(rig, float(rig.get_meta("bx", rig.position.x)), 0.5)
		_after(LUNGE_MS, func() -> void:
			_play(_enemy_rig, "play_hurt")
			_burst(_enemy_pos(), Color("9fd8ff"), 8, 3.0))
		_pop("-%d" % dmg, Color("9fd8ff"), false, 30)
		return
	if str(e.get("who", "")) == "player":
		match kind:
			"attack", "crit", "skill1":
				_play(_hero_rig, "play_attack")
				_lunge(_hero_rig, HERO_X, 0.55)
				# Efek kena muncul saat pukulan mendarat: kilatan, percikan, getar.
				var hit_color := Color("ffffff")
				var burst := 10
				var power := 0.03
				if kind == "skill1":
					hit_color = Color("ff9a3c")
					burst = 28
					power = 0.08
				elif kind == "crit":
					hit_color = Color("ffd23c")
					burst = 22
					power = 0.09
				_after(LUNGE_MS, func() -> void:
					_play(_enemy_rig, "play_hurt")
					_flash_rig(_enemy_rig, hit_color)
					_burst(_enemy_pos(), hit_color, burst, 3.5)
					_shake(power))
				if kind == "skill1":
					_pop("%s! -%d" % [_skill_name("skill1"), dmg], Color("ff9a3c"), false, 44)
				elif kind == "crit":
					_pop("KRITIS -%d" % dmg, Color("ffd23c"), false, 44)
				else:
					_pop("-%d" % dmg, Color("ffffff"), false, 38)
			"guard":
				_burst(_hero_pos(), Color("6ec6ff"), 8, 2.0)
				_pop("Bertahan", Color("6ec6ff"), true, 36)
			"skill2":
				_burst(_hero_pos(), Color("7be06b"), 18, 2.5)
				_pop("+%d HP" % heal, Color("7be06b"), true, 40)
			"potion":
				_burst(_hero_pos(), Color("7be06b"), 14, 2.2)
				_pop("+%d HP" % heal, Color("7be06b"), true, 38)
	else:
		_play(_enemy_rig, "play_attack")
		_lunge(_enemy_rig, ENEMY_X, -0.55)
		match kind:
			"perfect":
				_after(LUNGE_MS, func() -> void:
					_burst(_hero_pos(), Color("6ef0ff"), 24, 4.0)
					_screen_flash(Color(0.43, 0.94, 1.0, 0.2))
					_shake(0.04))
				_pop("TANGKIS!", Color("6ef0ff"), true, 48)
			"guard":
				_play(_hero_rig, "play_hurt")
				_after(LUNGE_MS, func() -> void:
					_flash_rig(_hero_rig, Color("6ec6ff"))
					_burst(_hero_pos(), Color("6ec6ff"), 12, 2.5)
					_shake(0.03))
				_pop("Ditahan -%d" % dmg, Color("6ec6ff"), true, 38)
			"shield":
				_play(_hero_rig, "play_hurt")
				_after(LUNGE_MS, func() -> void:
					_flash_rig(_hero_rig, Color("ffe08a"))
					_burst(_hero_pos(), Color("ffe08a"), 12, 2.5)
					_shake(0.03))
				_pop("Perisai -%d" % dmg, Color("ffe08a"), true, 38)
			_:
				_play(_hero_rig, "play_hurt")
				# Makin besar kerusakan (dibanding HP maksimum), makin kuat getarannya.
				var share := clampf(float(dmg) / maxf(1.0, float(Session.player.state.max_hp)), 0.0, 1.0)
				_after(LUNGE_MS, func() -> void:
					_flash_rig(_hero_rig, Color("ff3030"))
					_burst(_hero_pos(), Color("ff5c5c"), 12 + int(share * 24.0), 3.5)
					_screen_flash(Color(1.0, 0.1, 0.1, 0.12 + share * 0.3))
					_shake(0.04 + share * 0.12))
				_pop("-%d" % dmg, Color("ff5c5c"), true, 44)


# --- efek kena ---

func _hero_pos() -> Vector3:
	return Vector3(HERO_X, CHEST_Y, 0)


func _enemy_pos() -> Vector3:
	return Vector3(ENEMY_X, CHEST_Y, 0)


## Jalankan fn setelah detik `seconds` (aman bila layar sudah ditutup).
func _after(seconds: float, fn: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_inside_tree():
			fn.call())


## Penyerang maju sebentar lalu kembali ke tempat semula.
func _lunge(rig: Node3D, base_x: float, toward: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var tween := create_tween()
	tween.tween_property(rig, "position:x", base_x + toward, LUNGE_MS).set_ease(Tween.EASE_OUT)
	tween.tween_property(rig, "position:x", base_x, 0.22).set_ease(Tween.EASE_IN_OUT)


## Kilatan warna sesaat pada seluruh model (lapisan transparan di atas bahan aslinya).
func _flash_rig(rig: Node3D, color: Color) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.55)
	var meshes := rig.find_children("*", "MeshInstance3D", true, false)
	for m: Node in meshes:
		(m as MeshInstance3D).material_overlay = mat
	_after(0.13, func() -> void:
		for m: Node in meshes:
			if is_instance_valid(m):
				(m as MeshInstance3D).material_overlay = null)


## Percikan kecil sekali ledak di titik `at` (dunia arena).
func _burst(at: Vector3, color: Color, amount: int, speed: float) -> void:
	if _vp == null or not is_instance_valid(_vp):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = mat
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0, 0)
	p.position = at
	_vp.add_child(p)
	p.emitting = true
	_after(1.2, func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Getar kamera arena; power 0.03 ringan, 0.12 kuat.
func _shake(power: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var tween := create_tween()
	for i in 6:
		var k := power * (1.0 - float(i) / 6.0)
		tween.tween_property(_cam, "h_offset", randf_range(-k, k), 0.035)
		tween.parallel().tween_property(_cam, "v_offset", randf_range(-k, k), 0.035)
	tween.tween_property(_cam, "h_offset", 0.0, 0.04)
	tween.parallel().tween_property(_cam, "v_offset", 0.0, 0.04)


## Kilat warna di seluruh layar yang memudar.
func _screen_flash(color: Color) -> void:
	if _flash == null:
		return
	_flash.color = color
	var tween := _flash.create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.3)


## Teks melayang di atas arena. hero=true di sisi ksatria (kiri), selain itu di sisi musuh (kanan).
func _pop(text: String, color: Color, hero: bool, size: int) -> void:
	if _enemy_view == null:
		return
	var label := _make_label(text, size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(label)
	var area := Rect2(_enemy_view.global_position, _enemy_view.size)
	var x := area.position.x + area.size.x * (0.14 if hero else 0.58)
	var y := area.position.y + area.size.y * 0.22
	label.global_position = Vector2(x, y)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", y - 90.0, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)


func _finish(status: String) -> void:
	_finished = true
	_result = status
	Session.safe_steps = SAFE_STEPS_AFTER_BATTLE
	_controls.visible = false
	_telegraph.visible = false
	_btn_continue.visible = true
	_btn_continue.text = "Kembali ke desa" if status == "lost" else "Lanjut"
	if status == "won":
		_play(_enemy_rig, "play_die")
		_burst(_enemy_pos(), Color("ffd23c"), 36, 4.5)
		_shake(0.1)
	elif status == "lost":
		_play(_hero_rig, "play_die")
		_burst(_hero_pos(), Color("ff5c5c"), 30, 4.0)
		_screen_flash(Color(0.6, 0.0, 0.0, 0.35))


func _on_continue() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- tampilan ---

func _add_lines(lines: Array[String]) -> void:
	_lines.append_array(lines)
	while _lines.size() > MAX_LOG_LINES:
		_lines.pop_front()
	if _log:
		_log.text = "\n".join(_lines)


func _refresh() -> void:
	var b: Dictionary = Session.battle
	if not b.is_empty():
		_enemy_name.text = str(b.get("enemy_name", ""))
		_enemy_bar.max_value = int(b.get("enemy_max_hp", 1))
		_enemy_bar.value = int(b.get("enemy_hp", 0))
	elif _finished:
		_enemy_bar.value = 0 if _result == "won" else _enemy_bar.value

	var st: Dictionary = Session.player.state
	_player_label.text = "%s  Lv %d   HP %d/%d   Emas %d" % [
		Session.player.name, st.level, st.hp, st.max_hp, st.gold,
	]
	_player_bar.max_value = int(st.max_hp)
	_player_bar.value = int(st.hp)
	_update_buttons(Time.get_ticks_msec())


func _update_buttons(now: int) -> void:
	if _buttons.is_empty():
		return
	for entry: Array in MAIN_ACTIONS:
		var action := str(entry[0])
		var button := _buttons[action] as Button
		var left := _cooldown_left(action)
		var sub := _skill_name(action) if str(entry[2]) == "" and action.begins_with("skill") else str(entry[2])
		if left > READY_SLACK_MS:
			sub = "%.1f d" % (left / 1000.0)
		elif action == "defend" and now < _guard_until:
			sub = "Menahan!"
		elif action == "skill2" and now < _shield_until:
			sub = "Perisai aktif"
		button.text = str(entry[1]) if sub == "" else "%s\n%s" % [entry[1], sub]
		button.disabled = left > READY_SLACK_MS
	var potions := _potion_count()
	var potion_button := _buttons["potion"] as Button
	var potion_left := _cooldown_left("potion")
	potion_button.text = "Ramuan (%d)" % potions if potion_left <= READY_SLACK_MS else "Ramuan %.1f d" % (potion_left / 1000.0)
	potion_button.disabled = potions <= 0 or int(Session.player.state.hp) >= int(Session.player.state.max_hp) or potion_left > READY_SLACK_MS
	var flee_button := _buttons["flee"] as Button
	var flee_left := _cooldown_left("flee")
	flee_button.text = "Kabur" if flee_left <= READY_SLACK_MS else "Kabur %.1f d" % (flee_left / 1000.0)
	flee_button.disabled = flee_left > READY_SLACK_MS


func _skill_name(action: String) -> String:
	return str(Heroes.current().get(action, ""))


func _potion_count() -> int:
	for item: Dictionary in Session.player.state.inventory:
		if item.id == POTION_ID:
			return int(item.qty)
	return 0


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a2420")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	_enemy_name = _make_label("", 38)
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_enemy_name)

	_enemy_bar = _make_bar(Color("d9534f"))
	box.add_child(_enemy_bar)

	# Penunjuk waktu serangan musuh berikutnya: penuh = musuh menyerang.
	_telegraph = _make_bar(Color("f0a030"))
	_telegraph.custom_minimum_size = Vector2(0, 16)
	_telegraph.max_value = 1.0
	box.add_child(_telegraph)

	_enemy_view = _build_arena()
	box.add_child(_enemy_view)

	_log = _make_label("", 26)
	_log.custom_minimum_size = Vector2(0, 120)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_log)

	_player_label = _make_label("", 28)
	box.add_child(_player_label)

	_player_bar = _make_bar(Color("4c9a4c"))
	box.add_child(_player_bar)

	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 14)
	box.add_child(_controls)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_controls.add_child(grid)
	for entry: Array in MAIN_ACTIONS:
		var button := _make_button(str(entry[1]), 32, 118)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_action.bind(str(entry[0])))
		grid.add_child(button)
		_buttons[str(entry[0])] = button

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_controls.add_child(row)
	for entry: Array in [["potion", "Ramuan"], ["flee", "Kabur"]]:
		var small := _make_button(str(entry[1]), 28, 84)
		small.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		small.pressed.connect(_on_action.bind(str(entry[0])))
		row.add_child(small)
		_buttons[str(entry[0])] = small

	_btn_continue = _make_button("Lanjut", 34, 110)
	_btn_continue.visible = false
	_btn_continue.pressed.connect(_on_continue)
	box.add_child(_btn_continue)

	# Lapisan teks melayang (angka kerusakan) di atas segalanya.
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Arena 3D di dalam SubViewport: ksatria di kiri, musuh di kanan.
func _build_arena() -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(0, 360)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(664, 360)
	vp.msaa_3d = Viewport.MSAA_2X if Session.quality >= 2 else Viewport.MSAA_DISABLED
	holder.add_child(vp)

	# Arena mengikuti peta tempat pertarungan terjadi: hutan, desa, gunung batu, atau gua.
	var map_id := str(Session.player.state.get("map", "desa_awal"))
	var we := WorldEnvironment.new()
	we.environment = WorldBuild.environment_for(map_id)
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-30), 0)
	sun.light_energy = WorldBuild.light_energy_for(map_id) + 0.15
	sun.light_color = WorldBuild.light_color_for(map_id)
	sun.shadow_enabled = Session.quality >= 1
	sun.directional_shadow_max_distance = 14.0
	vp.add_child(sun)
	# Waktu dan cuaca dunia berlaku juga di arena (kecuali gua).
	Atmosphere.apply(we.environment, sun, Atmosphere.capture(we.environment, sun), map_id)
	var rain_fx := Atmosphere.make_rain(Vector3(5, 0.2, 3), Atmosphere.rain_amount(Session.quality) / 2)
	rain_fx.position = Vector3(0, 6.5, 0)
	vp.add_child(rain_fx)
	Atmosphere.set_rain(rain_fx, map_id)

	vp.add_child(WorldBuild.build_arena(map_id))

	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.25, 3.7), Vector3(0, 0.75, 0))
	cam.current = true
	_vp = vp
	_cam = cam

	_hero_rig = Models.create(str(Heroes.current().id))
	_hero_rig.position = Vector3(HERO_X, 0, 0)
	_hero_rig.rotation.y = PI / 2.0  # menghadap +x
	vp.add_child(_hero_rig)
	var slots := [Vector3(-0.55, 0, 0.85), Vector3(-0.55, 0, -0.85), Vector3(0.0, 0, -1.6)]
	var party: Array = Session.player.get("state", {}).get("party", [])
	for i in mini(party.size(), slots.size()):
		var ally: Node3D = Models.create(str(party[i]))
		ally.position = Vector3(HERO_X, 0, 0) + (slots[i] as Vector3)
		ally.rotation.y = PI / 2.0
		ally.set_meta("bx", ally.position.x)
		vp.add_child(ally)
		_ally_rigs[str(party[i])] = ally
	_enemy_rig = Models.create(_enemy_id)
	_enemy_rig.position = Vector3(ENEMY_X, 0, 0)
	_enemy_rig.rotation.y = -PI / 2.0  # menghadap -x
	vp.add_child(_enemy_rig)
	return holder


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 30)
	bar.show_percentage = false
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	bar.add_theme_stylebox_override("fill", style)
	return bar


func _make_button(text: String, font_size: int, height: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size = Vector2(0, height)
	return button
