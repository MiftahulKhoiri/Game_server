extends Control
## Layar pertarungan bergiliran. Semua hasil dihitung SERVER; layar ini hanya
## mengirim aksi pemain dan menampilkan jawaban server (docs/API.md).
## Arena 3D: ksatria dan musuh (model dari scripts/models.gd) saling berhadapan.

const WORLD_SCENE := "res://scenes/world3d.tscn"
const Models = preload("res://scripts/models.gd")
const POTION_ID := "ramuan"
const MAX_LOG_LINES := 6
const SAFE_STEPS_AFTER_BATTLE := 3

var _enemy_id := ""
var _hero_rig: Node3D
var _enemy_rig: Node3D
var _last_enemy_hp := -1
var _last_hero_hp := -1
var _enemy_name: Label
var _enemy_bar: ProgressBar
var _enemy_view: SubViewportContainer
var _log: Label
var _player_label: Label
var _player_bar: ProgressBar
var _grid: GridContainer
var _buttons: Dictionary = {}  # aksi -> Button
var _btn_continue: Button
var _lines: Array[String] = []
var _busy := false
var _finished := false
var _result := ""


func _ready() -> void:
	if Session.battle.is_empty():
		# Tidak ada pertarungan (mis. dibuka langsung dari editor): kembali ke peta.
		get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)
		return
	_enemy_id = str(Session.battle.get("enemy_id", ""))
	_build_ui()
	_add_lines(["%s muncul!" % str(Session.battle.get("enemy_name", "Musuh"))])
	_refresh()


# --- aksi ---

func _on_action(action: String) -> void:
	if _busy or _finished:
		return
	_busy = true
	_refresh()
	_last_enemy_hp = int(Session.battle.get("enemy_hp", -1))
	_last_hero_hp = int(Session.player.state.hp)
	if action == "attack":
		_play(_hero_rig, "play_attack")
	var res: Dictionary = await Api.battle_action(action)
	_busy = false
	if not res.ok:
		_add_lines([str(res.error)])
		_refresh()
		return

	var data: Dictionary = res.data
	var status := str(data.get("status", "ongoing"))
	# Jika kalah, server memulangkan pemain ke desa: posisi ikut diambil dari server.
	Session.merge_server_player(data.player, status == "lost")
	var next_battle: Variant = data.get("battle")
	Session.battle = next_battle if next_battle is Dictionary else {}
	var lines: Array[String] = []
	for line in data.get("log", []):
		lines.append(str(line))
	_add_lines(lines)
	_animate_result(status)
	if status != "ongoing":
		_finish(status)
	_refresh()


func _play(rig: Node3D, method: String) -> void:
	if rig != null and is_instance_valid(rig) and rig.has_method(method):
		rig.call(method)


## Animasi mengikuti hasil dari server: siapa yang terkena, siapa yang menyerang.
func _animate_result(status: String) -> void:
	var enemy_hp := int(Session.battle.get("enemy_hp", 0)) if status == "ongoing" else 0
	if _last_enemy_hp >= 0 and enemy_hp < _last_enemy_hp:
		_play(_enemy_rig, "play_hurt")
	if int(Session.player.state.hp) < _last_hero_hp:
		_play(_enemy_rig, "play_attack")
		_play(_hero_rig, "play_hurt")
	if status == "won":
		_play(_enemy_rig, "play_die")
	elif status == "lost":
		_play(_hero_rig, "play_die")


func _finish(status: String) -> void:
	_finished = true
	_result = status
	Session.safe_steps = SAFE_STEPS_AFTER_BATTLE
	_grid.visible = false
	_btn_continue.visible = true
	_btn_continue.text = "Kembali ke desa" if status == "lost" else "Lanjut"


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

	var potions := _potion_count()
	var locked := _busy or _finished
	(_buttons["attack"] as Button).disabled = locked
	(_buttons["defend"] as Button).disabled = locked
	(_buttons["flee"] as Button).disabled = locked
	var potion_button := _buttons["potion"] as Button
	potion_button.text = "Ramuan (%d)" % potions
	potion_button.disabled = locked or potions <= 0 or int(st.hp) >= int(st.max_hp)


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
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_enemy_name = _make_label("", 40)
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_enemy_name)

	_enemy_bar = _make_bar(Color("d9534f"))
	box.add_child(_enemy_bar)

	_enemy_view = _build_arena()
	box.add_child(_enemy_view)

	_log = _make_label("", 28)
	_log.custom_minimum_size = Vector2(0, 230)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_log)

	_player_label = _make_label("", 28)
	box.add_child(_player_label)

	_player_bar = _make_bar(Color("4c9a4c"))
	box.add_child(_player_bar)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	box.add_child(_grid)
	for entry: Array in [["attack", "Serang"], ["defend", "Bertahan"], ["potion", "Ramuan"], ["flee", "Kabur"]]:
		var button := _make_button(str(entry[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_action.bind(str(entry[0])))
		_grid.add_child(button)
		_buttons[str(entry[0])] = button

	_btn_continue = _make_button("Lanjut")
	_btn_continue.visible = false
	_btn_continue.pressed.connect(_on_continue)
	box.add_child(_btn_continue)


## Arena 3D di dalam SubViewport: ksatria di kiri, musuh di kanan.
func _build_arena() -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(0, 420)
	holder.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(648, 420)
	vp.msaa_3d = Viewport.MSAA_2X
	holder.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b3a33")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aab8b0")
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-25), 0)
	sun.light_energy = 1.1
	vp.add_child(sun)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 3.4
	floor_mesh.bottom_radius = 3.4
	floor_mesh.height = 0.2
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("5b7a4a")
	mat.roughness = 1.0
	floor_node.material_override = mat
	floor_node.position = Vector3(0, -0.1, 0)
	vp.add_child(floor_node)

	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.25, 3.7), Vector3(0, 0.75, 0))
	cam.current = true

	_hero_rig = Models.create("ksatria")
	_hero_rig.position = Vector3(-1.0, 0, 0)
	_hero_rig.rotation.y = PI / 2.0  # menghadap +x
	vp.add_child(_hero_rig)
	_enemy_rig = Models.create(_enemy_id)
	_enemy_rig.position = Vector3(1.0, 0, 0)
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
	bar.custom_minimum_size = Vector2(0, 34)
	bar.show_percentage = false
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	bar.add_theme_stylebox_override("fill", style)
	return bar


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 34)
	button.custom_minimum_size = Vector2(0, 110)
	return button
