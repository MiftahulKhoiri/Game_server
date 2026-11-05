extends Control
## Layar pertarungan bergiliran. Semua hasil dihitung SERVER; layar ini hanya
## mengirim aksi pemain dan menampilkan jawaban server (docs/API.md).
## Gambar musuh dimuat dari res://assets/enemies/<id musuh>.png bila ada;
## musuh yang gambarnya belum dibuat tetap memakai bulatan placeholder.

const WORLD_SCENE := "res://scenes/world.tscn"
const ENEMY_ART_DIR := "res://assets/enemies/"
const POTION_ID := "ramuan"
const MAX_LOG_LINES := 6
const SAFE_STEPS_AFTER_BATTLE := 3

const ENEMY_COLORS := {
	"tikus_sawah": Color("8d8d93"),
	"belalang_raksasa": Color("7ccf4a"),
	"ular_sawah": Color("8a9a3a"),
	"babi_hutan": Color("8a5a3c"),
}

var _enemy_id := ""
var _enemy_tex: Texture2D
var _enemy_name: Label
var _enemy_bar: ProgressBar
var _enemy_view: Control
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
	_enemy_tex = _load_enemy_art(_enemy_id)
	_build_ui()
	_add_lines(["%s muncul!" % str(Session.battle.get("enemy_name", "Musuh"))])
	_refresh()


# --- aksi ---

func _on_action(action: String) -> void:
	if _busy or _finished:
		return
	_busy = true
	_refresh()
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
	if status != "ongoing":
		_finish(status)
	_refresh()


func _finish(status: String) -> void:
	_finished = true
	_result = status
	Session.safe_steps = SAFE_STEPS_AFTER_BATTLE
	_grid.visible = false
	_btn_continue.visible = true
	_btn_continue.text = "Kembali ke desa" if status == "lost" else "Lanjut"
	if status == "won":
		_enemy_view.modulate = Color(1, 1, 1, 0.25)
	_enemy_view.queue_redraw()


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

	_enemy_view = Control.new()
	_enemy_view.custom_minimum_size = Vector2(0, 380)
	_enemy_view.draw.connect(_draw_enemy)
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


## Musuh yang belum punya gambar sendiri meminjam gambar musuh lain (dengan warna berbeda).
const ART_ALIAS := {"raja_goblin": "goblin"}
const ART_TINT := {"raja_goblin": Color(1.0, 0.65, 0.65)}


func _load_enemy_art(id: String) -> Texture2D:
	id = str(ART_ALIAS.get(id, id))
	var path := ENEMY_ART_DIR + id + ".png"
	if id != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw_enemy() -> void:
	var size := _enemy_view.size
	if _enemy_tex:
		var tex_size := _enemy_tex.get_size()
		var scale := minf(size.x / tex_size.x, size.y / tex_size.y)
		var draw_size := tex_size * scale
		_enemy_view.draw_texture_rect(_enemy_tex, Rect2((size - draw_size) / 2.0, draw_size), false, ART_TINT.get(_enemy_id, Color.WHITE))
		return
	var center := size / 2.0
	var color: Color = ENEMY_COLORS.get(_enemy_id, Color("b04a8a"))
	_enemy_view.draw_circle(center + Vector2(0, 120), 90, Color(0, 0, 0, 0.25))  # bayangan
	_enemy_view.draw_circle(center, 110, color)
	_enemy_view.draw_circle(center + Vector2(-38, -20), 18, Color.WHITE)
	_enemy_view.draw_circle(center + Vector2(38, -20), 18, Color.WHITE)
	_enemy_view.draw_circle(center + Vector2(-34, -18), 8, Color.BLACK)
	_enemy_view.draw_circle(center + Vector2(34, -18), 8, Color.BLACK)


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
