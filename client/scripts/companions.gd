extends Node
## Pahlawan pendamping (dibeli di layar Atribut): berbaris di belakang pemain dan mengikutinya.
## Saat bertarung mereka menghadap musuh dan menyerang otomatis (kejadian "ally" dari server,
## lihat internal/game/battle.go); layar dunia hanya menampilkan.

const Models = preload("res://scripts/models.gd")
const Movement = preload("res://scripts/movement.gd")
const BACK := [1.5, 1.7, 1.7]       # jarak di belakang pemain per urutan
const SIDE := [0.0, 0.95, -0.95]    # geser kanan(+)/kiri(-)
const MAX_SPEED := 7.0
const CHARGE_SPEED := 9.5       # kecepatan maju saat musuh mengejar / bertarung
const ENGAGE_DIST := 7.5        # musuh pengejar sedekat ini membuat pendamping maju menyambutnya
const FOE_RING := 1.15          # jarak pendamping dari musuh saat mengepung
const FOLLOW_GAIN := 5.0
const SNAP_DIST := 9.0

var world = null            # world3d.gd
var _units: Array = []      # {id, node, pos: Vector2, yaw: float, shadow}
var _party_key := ""
var _heal_button: Button
var _heal_target := ""
var _heal_busy := false


func setup(w: Node) -> void:
	world = w
	sync()
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_heal_button = Button.new()
	_heal_button.text = "Sembuhkan Pendamping"
	_heal_button.position = Vector2(24, 700)
	_heal_button.size = Vector2(300, 68)
	_heal_button.add_theme_font_size_override("font_size", 24)
	_heal_button.visible = false
	layer.add_child(_heal_button)
	_heal_button.pressed.connect(_heal_first_down)
	if world != null and "_buttons" in world:
		world._buttons.append(_heal_button)


## Samakan pendamping di dunia dengan Session.player.state.party.
func sync() -> void:
	var party: Array = (Session.player.get("state", {}).get("party", []) as Array).duplicate()
	for n in Session.active_soldiers():
		party.append("prajurit_%d" % (n + 1))  # pasukan prajurit biasa ikut berbaris
	var key := ",".join(PackedStringArray(party))
	if key == _party_key:
		return
	_party_key = key
	for u: Dictionary in _units:
		if is_instance_valid(u.node):
			u.node.queue_free()
	_units.clear()
	if world == null or world._player == null:
		_party_key = ""
		return
	var i := 0
	for id: String in party:
		var node: Node3D = Models.create("prajurit" if id.begins_with("prajurit_") else id)
		world.add_child(node)
		var shadow: Variant = world._add_shadow(node, 0.3)
		var start: Vector2 = _slot(i)
		node.position = Vector3(start.x, 0.0, start.y)
		_units.append({"id": id, "node": node, "pos": start, "yaw": world._yaw, "shadow": shadow})
		i += 1


func count() -> int:
	return _units.size()


## Pendamping menyerang (animasi pukul). Dipanggil saat kejadian "ally" dari server.
func attack(hero_id: String) -> void:
	for u: Dictionary in _units:
		var hp_map: Dictionary = Session.player.get("state", {}).get("ally_hp", {})
		if int(hp_map.get(hero_id, 30)) <= 0:
			return
		if u.id == hero_id and is_instance_valid(u.node) and u.node.has_method("play_attack"):
			u.node.call("play_attack")
			return


## Posisi dunia (x, 0, z) pendamping `hero_id`; Vector3.ZERO bila tidak ada.
## Reaksi saat pendamping terkena serangan atau tumbang.
func hit(hero_id: String, down: bool) -> void:
	for u: Dictionary in _units:
		if u.id != hero_id or not is_instance_valid(u.node):
			continue
		if down and u.node.has_method("play_die"):
			u.node.call("play_die")
		elif u.node.has_method("play_hurt"):
			u.node.call("play_hurt")
		return


func position_of(hero_id: String) -> Vector3:
	for u: Dictionary in _units:
		if u.id == hero_id:
			var p: Vector2 = u.pos
			return Vector3(p.x, 0.0, p.y)
	return Vector3.ZERO


func _refresh_heal_button() -> void:
	if _heal_button == null:
		return
	_heal_target = ""
	var st: Dictionary = Session.player.get("state", {})
	var hp_map: Dictionary = st.get("ally_hp", {})
	for id: String in st.get("party", []):
		if int(hp_map.get(id, 30)) <= 0:
			_heal_target = id
			break
	var fighting: bool = world._fight != null and world._fight.active
	_heal_button.visible = _heal_target != "" and not fighting
	_heal_button.disabled = _heal_busy or Session.item_count("ramuan") <= 0
	if _heal_target != "":
		var hero_name := _heal_target
		if hero_name == "ksatria":
			hero_name = "Ksatria"
		elif hero_name == "pemanah":
			hero_name = "Pemanah"
		elif hero_name == "pendekar_kapak":
			hero_name = "Pendekar Kapak"
		_heal_button.text = "Sembuhkan %s (%d)" % [hero_name, Session.item_count("ramuan")]


func _heal_first_down() -> void:
	if _heal_busy or _heal_target == "":
		return
	_heal_busy = true
	_heal_button.disabled = true
	var target := _heal_target
	var res: Dictionary = await Api.heal_ally(target)
	_heal_busy = false
	if not is_inside_tree():
		return
	if res.ok:
		Session.merge_server_player(res.data)
		sync()
		world._set_status("%s telah disembuhkan dengan ramuan." % target)
	else:
		world._set_status(str(res.get("error", "Gagal menyembuhkan pendamping")))
	_refresh_heal_button()


func _slot(i: int) -> Vector2:
	var yaw: float = world._yaw
	var fwd := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var k := mini(i, BACK.size() - 1)
	var back := float(BACK[k])
	var side := float(SIDE[k])
	if i >= BACK.size():  # lapis berikutnya: tiga prajurit sebaris, makin jauh ke belakang
		var j := i - BACK.size()
		back = 2.9 + 0.8 * float(j / 3)
		side = float([0.0, 1.1, -1.1][j % 3])
	return world._pos - fwd * back + right * side


func _process(delta: float) -> void:
	if world == null or world._player == null:
		return
	sync()
	_refresh_heal_button()
	var foe: Vector2 = Vector2.ZERO
	var fighting := false
	var fight: Variant = world._fight
	if fight != null and fight.active and fight.roamer != null:
		foe = fight.roamer.pos
		fighting = true
	else:
		# Musuh sedang mengejar pemain: pendamping tidak diam di belakang, tetapi maju menyambutnya.
		var near: float = ENGAGE_DIST
		for r: Variant in world._roamers:
			if r.chasing and not r.dying and r.pos.distance_to(world._pos) < near:
				near = r.pos.distance_to(world._pos)
				foe = r.pos
				fighting = true
	for i in _units.size():
		var u: Dictionary = _units[i]
		var node: Node3D = u.node
		if not is_instance_valid(node):
			continue
		var hp_map: Dictionary = Session.player.get("state", {}).get("ally_hp", {})
		if int(hp_map.get(str(u.id), 30)) <= 0:
			node.visible = false
			continue
		node.visible = true
		var pos: Vector2 = u.pos
		var target := _slot(i)
		if fighting:
			# Mengepung musuh dari sisi pemain, tersebar menurut urutan.
			var from_foe: Vector2 = world._pos - foe
			var base: float = atan2(from_foe.x, from_foe.y)
			var ang: float = base + (float(i) - float(_units.size() - 1) / 2.0) * 0.8
			target = foe + Vector2(sin(ang), cos(ang)) * (FOE_RING + 0.15 * float(i % 3))
		var gap := target - pos
		if gap.length() > SNAP_DIST:
			pos = target
			gap = Vector2.ZERO
		var vel := gap * FOLLOW_GAIN
		var top_speed := CHARGE_SPEED if fighting else MAX_SPEED
		if vel.length() > top_speed:
			vel = vel.normalized() * top_speed
		var before := pos
		if vel.length() > 0.2:
			pos = Movement.move(world._map_id, pos, vel * delta)
		var moved := (pos - before).length() / maxf(delta, 0.0001)
		var yaw: float = u.yaw
		if fighting:
			var toward := foe - pos
			if toward.length() > 0.1:
				yaw = lerp_angle(yaw, atan2(toward.x, toward.y), minf(1.0, delta * 10.0))
		elif moved > 0.5:
			yaw = lerp_angle(yaw, atan2(vel.x, vel.y), minf(1.0, delta * 10.0))
		else:
			yaw = lerp_angle(yaw, world._yaw, minf(1.0, delta * 4.0))
		u.pos = pos
		u.yaw = yaw
		node.position = Vector3(pos.x, 0.0, pos.y)
		node.rotation.y = yaw
		if "moving" in node:
			node.moving = moved > 0.8
