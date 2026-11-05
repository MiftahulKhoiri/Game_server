extends Node2D
## Layar peta: gerak per kotak (grid, tampak atas) dan simpan otomatis ke server.
## Gambar masih berupa bentuk sederhana (placeholder) sampai aset ilustrator masuk.

const Maps = preload("res://scripts/maps.gd")

const TILE := 48
const MOVE_TIME := 0.10
const SAVE_DELAY := 1.5
const RETRY_DELAY := 5.0
const HUD_TOP := 960
const ENCOUNTER_CHANCE := 0.18  # peluang bertemu musuh tiap langkah di ladang
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const DIALOG_SCENE := "res://scenes/dialog.tscn"
const NPC_ART_DIR := "res://assets/characters/"

var _map_id := Maps.DEFAULT_MAP
var _vis := Vector2.ZERO  # posisi gambar pemain (piksel), digeser halus oleh tween
var _moving := false
var _held := Vector2i.ZERO  # arah tombol layar yang sedang ditekan
var _unsaved := false
var _saving := false
var _talk_button: Button
var _npc_tex: Dictionary = {}  # id NPC -> Texture2D (atau null)
var _encountering := false  # sedang menuju pertarungan: gerak dikunci
var _save_timer: Timer
var _hud: Label
var _status: Label


func _ready() -> void:
	if Session.player.is_empty():
		Session.use_offline_player()  # dijalankan langsung dari editor

	var st: Dictionary = Session.player.state
	_map_id = str(st.map)
	if not Maps.walkable(_map_id, st.x, st.y):
		# Peta/posisi tidak dikenal: kembalikan ke titik awal.
		_map_id = Maps.DEFAULT_MAP
		st.map = _map_id
		st.x = Maps.SPAWN.x
		st.y = Maps.SPAWN.y
	_vis = Vector2(st.x, st.y) * TILE

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)

	_build_ui()
	_refresh_hud()
	_set_status("Mode uji (tidak disimpan)" if Session.offline else "Tersimpan")
	if not Session.offline:
		_resume_battle_if_any()  # mis. aplikasi ditutup di tengah pertarungan


func _process(_delta: float) -> void:
	if _encountering:
		return
	if _moving:
		queue_redraw()
		return
	var dir := _held if _held != Vector2i.ZERO else _key_dir()
	if dir != Vector2i.ZERO:
		_try_move(dir)


func _notification(what: int) -> void:
	# Simpan seketika saat aplikasi dijeda atau ditutup (best-effort).
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _unsaved and not _saving:
			_save()


# --- gerak ---

func _key_dir() -> Vector2i:
	if Input.is_action_pressed("ui_left"):
		return Vector2i.LEFT
	if Input.is_action_pressed("ui_right"):
		return Vector2i.RIGHT
	if Input.is_action_pressed("ui_up"):
		return Vector2i.UP
	if Input.is_action_pressed("ui_down"):
		return Vector2i.DOWN
	return Vector2i.ZERO


func _try_move(dir: Vector2i) -> void:
	var st: Dictionary = Session.player.state
	var nx: int = st.x + dir.x
	var ny: int = st.y + dir.y
	if not Maps.walkable(_map_id, nx, ny) or Maps.npc_at(_map_id, nx, ny) != "":
		return
	st.x = nx
	st.y = ny
	_moving = true
	var tween := create_tween()
	tween.tween_property(self, "_vis", Vector2(nx, ny) * TILE, MOVE_TIME)
	tween.tween_callback(_on_move_done)
	_unsaved = true
	_save_timer.start(SAVE_DELAY)


func _on_move_done() -> void:
	_moving = false
	queue_redraw()
	_update_talk_button()
	var st0: Dictionary = Session.player.state
	var ex := Maps.exit_at(_map_id, st0.x, st0.y)
	if not ex.is_empty():
		_go_to_map(str(ex.to), ex.at)
		return
	if Session.offline or _encountering:
		return
	var st: Dictionary = Session.player.state
	var tile := Maps.tile_at(_map_id, st.x, st.y)
	if tile == "" or not Maps.ENCOUNTER_TILES.contains(tile):
		return  # pertemuan hanya terjadi di ladang / kerikil
	if Session.safe_steps > 0:
		Session.safe_steps -= 1
		return
	if randf() < ENCOUNTER_CHANCE:
		_start_encounter()


## Pindah ke peta lain; posisi baru disimpan seperti gerakan biasa.
func _go_to_map(map_id: String, at: Vector2i) -> void:
	var st: Dictionary = Session.player.state
	_held = Vector2i.ZERO
	_map_id = map_id
	st.map = map_id
	st.x = at.x
	st.y = at.y
	_vis = Vector2(at) * TILE
	_unsaved = true
	_save_timer.start(SAVE_DELAY)
	_update_talk_button()
	queue_redraw()
	_set_status("Memasuki %s" % Maps.NAMES.get(map_id, map_id))


# --- pertarungan ---

func _start_encounter() -> void:
	_encountering = true
	_held = Vector2i.ZERO
	_set_status("Sesuatu bergerak di ladang...")
	await _flush_save()  # posisi harus tersimpan dulu; server tidak ikut gerak kita
	var res: Dictionary = await Api.battle_start()
	if res.ok:
		_enter_battle(res.data)
	elif res.status == 409:
		# Sudah ada pertarungan di server: lanjutkan yang itu.
		if not await _resume_battle_if_any():
			_encountering = false
	else:
		_encountering = false
		_set_status(str(res.error))


## Mengembalikan true bila ada pertarungan berjalan dan layar pindah ke sana.
func _resume_battle_if_any() -> bool:
	var res: Dictionary = await Api.battle_get()
	if not res.ok:
		return false
	_encountering = true
	_enter_battle(res.data)
	return true


func _enter_battle(data: Dictionary) -> void:
	Session.merge_server_player(data.player)
	var battle: Variant = data.get("battle")
	Session.battle = battle if battle is Dictionary else {}
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _update_talk_button() -> void:
	if _talk_button == null:
		return
	var st: Dictionary = Session.player.state
	_talk_button.disabled = Session.offline or Maps.npc_near(_map_id, st.x, st.y) == ""


func _talk() -> void:
	var st: Dictionary = Session.player.state
	var npc := Maps.npc_near(_map_id, st.x, st.y)
	if npc == "" or _encountering:
		return
	_encountering = true
	_held = Vector2i.ZERO
	Session.talk_npc = npc
	await _flush_save()  # versi pemain harus sinkron sebelum hadiah diambil
	get_tree().change_scene_to_file(DIALOG_SCENE)


func _open_shop() -> void:
	if _encountering:
		return
	_encountering = true  # kunci gerak selagi pindah layar
	_held = Vector2i.ZERO
	await _flush_save()  # versi pemain harus sinkron dengan server sebelum berdagang
	get_tree().change_scene_to_file(SHOP_SCENE)


func _flush_save() -> void:
	_save_timer.stop()
	while _saving:
		await get_tree().process_frame
	if _unsaved:
		await _save()


# --- simpan ke server ---

func _save() -> void:
	if Session.offline:
		return
	if _saving:
		_save_timer.start(SAVE_DELAY)
		return
	_saving = true
	_unsaved = false
	_set_status("Menyimpan...")

	var res: Dictionary = await Api.save(Session.player.version, Session.player.state)
	if not res.ok and res.status == 409:
		# Versi di server berbeda (mis. main dari perangkat lain): ikuti versi server,
		# lalu simpan ulang keadaan lokal.
		var me: Dictionary = await Api.get_me()
		if me.ok:
			Session.player.version = int(me.data.version)
			res = await Api.save(Session.player.version, Session.player.state)

	_saving = false
	if res.ok:
		Session.player.version = int(res.data.version)
		_set_status("Tersimpan")
		if _unsaved:  # ada gerakan baru saat menyimpan
			_save_timer.start(SAVE_DELAY)
	elif res.status == 426:
		# Aplikasi terlalu lama untuk server: percuma mengulang, pemain harus update.
		_unsaved = true
		_set_status(str(res.error))
	else:
		_unsaved = true
		_set_status("Gagal menyimpan: %s (coba lagi...)" % res.error)
		_save_timer.start(RETRY_DELAY)


# --- tampilan ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_hud = Label.new()
	_hud.position = Vector2(24, HUD_TOP + 20)
	_hud.add_theme_font_size_override("font_size", 30)
	layer.add_child(_hud)

	_talk_button = Button.new()
	_talk_button.text = "Bicara"
	_talk_button.position = Vector2(240, 1110)
	_talk_button.size = Vector2(200, 70)
	_talk_button.focus_mode = Control.FOCUS_NONE
	_talk_button.add_theme_font_size_override("font_size", 28)
	_talk_button.pressed.connect(_talk)
	layer.add_child(_talk_button)
	_update_talk_button()

	var shop := Button.new()
	shop.text = "Toko"
	shop.position = Vector2(24, 1110)
	shop.size = Vector2(200, 70)
	shop.focus_mode = Control.FOCUS_NONE
	shop.add_theme_font_size_override("font_size", 28)
	shop.disabled = Session.offline  # toko butuh server
	shop.pressed.connect(_open_shop)
	layer.add_child(shop)

	_status = Label.new()
	_status.position = Vector2(24, 1200)
	_status.size = Vector2(360, 70)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 22)
	layer.add_child(_status)

	var origin := Vector2(408, 975)
	_add_pad(layer, "Atas", Vector2i.UP, origin + Vector2(96, 0))
	_add_pad(layer, "Kiri", Vector2i.LEFT, origin + Vector2(0, 96))
	_add_pad(layer, "Kanan", Vector2i.RIGHT, origin + Vector2(192, 96))
	_add_pad(layer, "Bawah", Vector2i.DOWN, origin + Vector2(96, 192))


func _add_pad(layer: CanvasLayer, text: String, dir: Vector2i, pos: Vector2) -> void:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = Vector2(96, 96)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.button_down.connect(func() -> void: _held = dir)
	button.button_up.connect(func() -> void:
		if _held == dir:
			_held = Vector2i.ZERO)
	layer.add_child(button)


func _refresh_hud() -> void:
	var st: Dictionary = Session.player.state
	var potions := 0
	for item: Dictionary in st.inventory:
		if item.id == "ramuan":
			potions = int(item.qty)
	_hud.text = "%s  Lv %d\nHP %d/%d  Emas %d\nRamuan %d  XP %d/%d" % [
		Session.player.name, st.level, st.hp, st.max_hp, st.gold,
		potions, st.xp, 20 * int(st.level),
	]


func _set_status(text: String) -> void:
	_status.text = text


func _draw() -> void:
	var rows := Maps.rows(_map_id)
	for y in rows.size():
		for x in rows[y].length():
			_draw_tile(rows[y][x], Vector2(x, y) * TILE)

	draw_rect(Rect2(0, HUD_TOP, 720, 320), Color("14201a"))

	for id: String in Maps.NPCS:
		var n: Dictionary = Maps.NPCS[id]
		if n.map == _map_id:
			_draw_npc(id, Vector2(n.pos) * TILE)

	# Pemain (placeholder)
	draw_circle(_vis + Vector2(24, 40), 14, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(_vis + Vector2(12, 14), Vector2(24, 26)), Color("d9534f"))
	draw_circle(_vis + Vector2(24, 12), 10, Color("f1c9a5"))


## Gambar NPC: ilustrasi dari assets/characters/<id>.png bila ada (dikecilkan ke
## satu petak lebar dan 1,5 petak tinggi), kalau tidak bentuk placeholder.
func _draw_npc(id: String, pos: Vector2) -> void:
	if not _npc_tex.has(id):
		var path := NPC_ART_DIR + id + ".png"
		_npc_tex[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	var tex: Texture2D = _npc_tex[id]
	draw_circle(pos + Vector2(24, 42), 16, Color(0, 0, 0, 0.25))
	if tex == null:
		draw_rect(Rect2(pos + Vector2(12, 14), Vector2(24, 26)), Color("c8a040"))
		draw_circle(pos + Vector2(24, 12), 10, Color("e8c9a5"))
		return
	var h := TILE * 1.6
	var w := h * tex.get_width() / tex.get_height()
	draw_texture_rect(tex, Rect2(pos + Vector2((TILE - w) / 2.0, TILE - h + 4), Vector2(w, h)), false)


func _draw_tile(tile: String, pos: Vector2) -> void:
	var rect := Rect2(pos, Vector2(TILE, TILE))
	match tile:
		"~":
			draw_rect(rect, Color("3a7bd5"))
			draw_rect(Rect2(pos + Vector2(8, 14), Vector2(24, 3)), Color("6fa3ec"))
		"B":
			draw_rect(rect, Color("3a7bd5"))
			draw_rect(Rect2(pos + Vector2(6, 0), Vector2(TILE - 12, TILE)), Color("9a6b3c"))
			for i in 4:
				draw_rect(Rect2(pos + Vector2(6, 10 + i * 12), Vector2(TILE - 12, 2)), Color("6e4a28"))
		"=":
			draw_rect(rect, Color("c9a96e"))
		"H":
			draw_rect(rect, Color("8a5a3c"))
			draw_rect(Rect2(pos, Vector2(TILE, 18)), Color("a33a3a"))
		"D":
			draw_rect(rect, Color("8a5a3c"))
			draw_rect(Rect2(pos + Vector2(12, 8), Vector2(24, 40)), Color("4a2f1a"))
			draw_circle(pos + Vector2(32, 30), 2, Color("e0c060"))
		"F":
			_draw_grass(pos)
			draw_rect(Rect2(pos + Vector2(0, 20), Vector2(TILE, 4)), Color("7a5530"))
			for i in 3:
				draw_rect(Rect2(pos + Vector2(4 + i * 18, 12), Vector2(6, 26)), Color("5b3b1e"))
		"W":
			_draw_grass(pos)
			draw_circle(pos + Vector2(24, 24), 18, Color("7d7d85"))
			draw_circle(pos + Vector2(24, 24), 11, Color("2a4f8a"))
		"T":
			draw_rect(rect, Color("7a5a38"))
			for i in 4:
				draw_rect(Rect2(pos + Vector2(0, 6 + i * 12), Vector2(TILE, 4)), Color("5e4326"))
		"f":
			_draw_grass(pos)
			draw_circle(pos + Vector2(14, 16), 4, Color("f0d040"))
			draw_circle(pos + Vector2(32, 30), 4, Color("e86a9a"))
			draw_circle(pos + Vector2(30, 12), 3, Color("ffffff"))
		"M":
			draw_rect(rect, Color("8a7f72"))
			draw_rect(Rect2(pos + Vector2(10, 12), Vector2(6, 4)), Color("756b5f"))
			draw_rect(Rect2(pos + Vector2(30, 32), Vector2(8, 4)), Color("9a8f81"))
		"G":
			draw_rect(rect, Color("6e6258"))
			for i in 6:
				draw_circle(pos + Vector2(8 + (i * 17) % 36, 8 + (i * 13) % 34), 3, Color("968a7c"))
		"R":
			draw_rect(rect, Color("8a7f72"))
			draw_circle(pos + Vector2(24, 26), 20, Color("55504a"))
			draw_circle(pos + Vector2(20, 20), 12, Color("6b655d"))
		"S":
			draw_rect(rect, Color("7d7d85"))
			for i in 3:
				draw_rect(Rect2(pos + Vector2(0, 14 + i * 14), Vector2(TILE, 2)), Color("55555c"))
			draw_rect(Rect2(pos + Vector2(14, 0), Vector2(2, 14)), Color("55555c"))
			draw_rect(Rect2(pos + Vector2(32, 14), Vector2(2, 14)), Color("55555c"))
		"#":
			draw_rect(rect, Color("2f6b2f"))
			draw_rect(Rect2(pos + Vector2(20, 28), Vector2(8, 16)), Color("5b3b1e"))
			draw_circle(pos + Vector2(24, 22), 17, Color("1f4d1f"))
		_:
			_draw_grass(pos)


func _draw_grass(pos: Vector2) -> void:
	draw_rect(Rect2(pos, Vector2(TILE, TILE)), Color("4c9a4c"))
	if int(pos.x * 7 + pos.y * 13) % 5 == 0:
		draw_rect(Rect2(pos + Vector2(14, 20), Vector2(4, 4)), Color("3f853f"))
