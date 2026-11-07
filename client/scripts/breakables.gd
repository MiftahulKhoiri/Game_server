extends RefCounted
## Benda dunia yang bisa dipukul: pohon, batu, dan rumput. Daftarnya dicatat WorldBuild saat
## membangun peta (meta "breakables"): tiap benda = satu baris di sebuah MultiMesh. Memukul
## mengguncangnya; saat hancur barisnya disembunyikan (skala 0) dan pohon/batu meninggalkan
## tunggul/puing. Server yang mengundi hadiah dan menentukan kapan benda tumbuh lagi.

const WorldBuild = preload("res://scripts/world_build.gd")
const HeroFx = preload("res://scripts/hero_fx.gd")

const HP := {"pohon": 3.0, "batu": 4.0, "rumput": 1.0}
const RADIUS := {"pohon": 0.5, "batu": 0.6, "rumput": 0.15}  # lebar benda: jangkauan dihitung dari tepinya
const CELL := 4.0
const RESPAWN := 600.0
const SHAKE_TIME := 0.09
const DEBRIS := {"pohon": Color("3f8f3a"), "batu": Color("8d8d95"), "rumput": Color("62b84c")}

var _grid: Dictionary = {}   # Vector2i -> Array[Dictionary]
var _entries: Array = []
var _flash: Array = []       # benda yang sedang terguncang
var _gone: Array = []        # benda yang hancur dan menunggu tumbuh lagi
var _fx_root: Node3D


func setup(terrain: Node3D, fx_root: Node3D) -> void:
	_fx_root = fx_root
	var reg: Array = terrain.get_meta("breakables", [])
	for src: Dictionary in reg:
		var e: Dictionary = src
		var xf: Transform3D = e.xf
		e.hp = float(HP.get(e.kind, 1.0))
		e.gone = false
		e.back = 0.0
		e.pos = Vector2(xf.origin.x, xf.origin.z)
		e.tile = Vector2i(floori(xf.origin.x), floori(xf.origin.z))
		e.rubble = null
		var cell := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(e)
		_entries.append(e)


func count() -> int:
	return _entries.size()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Benda di depan `origin` yang terjangkau: paling banyak `solid_n` pohon/batu terdekat
## dan `grass_n` rumput. `cos_min` = batas sudut (dot dengan arah hadap); benda yang
## sangat dekat selalu kena.
func targets(origin: Vector2, dir: Vector2, reach: float, cos_min: float, solid_n: int, grass_n: int) -> Array:
	var found: Array = []
	var span := ceili((reach + 1.0) / CELL)
	var c0 := Vector2i(floori(origin.x / CELL), floori(origin.y / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var cell: Array = _grid.get(c0 + Vector2i(dx, dz), [])
			for e: Dictionary in cell:
				if e.gone:
					continue
				var off: Vector2 = e.pos - origin
				var d := off.length()
				if d - float(RADIUS[e.kind]) > reach:
					continue
				if d > 0.9 and dir != Vector2.ZERO and off.normalized().dot(dir) < cos_min:
					continue
				found.append([d, e])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	var s := 0
	var g := 0
	for pair: Array in found:
		var e2: Dictionary = pair[1]
		if e2.kind == "rumput":
			if g < grass_n:
				out.append(e2)
				g += 1
		elif s < solid_n:
			out.append(e2)
			s += 1
	return out


## Memukul benda-benda `list` dengan kekuatan `dmg`. Mengembalikan yang hancur.
func strike(list: Array, dmg: float) -> Array:
	var broken: Array = []
	for e: Dictionary in list:
		e.hp -= dmg
		if e.hp <= 0.0:
			_break(e, RESPAWN, true)
			broken.append(e)
		else:
			_shake(e)
	return broken


func _shake(e: Dictionary) -> void:
	var xf: Transform3D = e.xf
	var mm: MultiMesh = e.mm
	mm.set_instance_transform(int(e.idx), Transform3D(xf.basis.scaled(Vector3(1.1, 0.9, 1.1)), xf.origin))
	if not _flash.has(e):
		_flash.append(e)
	e.shake = SHAKE_TIME
	HeroFx.burst(_fx_root, Vector3(e.pos.x, 0.8, e.pos.y), DEBRIS[e.kind], 3, 1.6)


func _break(e: Dictionary, left: float, effects: bool) -> void:
	e.gone = true
	e.back = _now() + left
	var xf: Transform3D = e.xf
	var mm: MultiMesh = e.mm
	mm.set_instance_transform(int(e.idx), Transform3D(Basis().scaled(Vector3.ZERO), xf.origin))
	_flash.erase(e)
	_gone.append(e)
	if e.kind != "rumput":
		_leave_rubble(e)
	if effects:
		HeroFx.burst(_fx_root, Vector3(e.pos.x, 0.6, e.pos.y), DEBRIS[e.kind], 12 if e.kind != "rumput" else 6)


## Pohon menjadi tunggul, batu menjadi puing (keduanya tetap menghalangi seperti sebelumnya).
func _leave_rubble(e: Dictionary) -> void:
	var id: String = WorldBuild.STUMPS[0] if e.kind == "pohon" else WorldBuild.ROCKS[1]
	var mesh: Mesh = WorldBuild._dekor_mesh(id)
	if mesh == null:
		return
	var xf: Transform3D = e.xf
	var s := xf.basis.get_scale().x * 1.1
	if e.kind == "batu":
		s = 2.0 if String(e.model).begins_with("mountain") else xf.basis.get_scale().x * 0.55
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * s
	mi.position = Vector3(xf.origin.x, -mesh.get_aabb().position.y * s, xf.origin.z)
	mi.rotation.y = xf.basis.get_euler().y
	_fx_root.add_child(mi)
	e.rubble = mi


func _restore(e: Dictionary) -> void:
	e.gone = false
	e.hp = float(HP.get(e.kind, 1.0))
	var mm: MultiMesh = e.mm
	mm.set_instance_transform(int(e.idx), e.xf)
	if e.rubble != null and is_instance_valid(e.rubble):
		(e.rubble as Node).queue_free()
	e.rubble = null


## Sembunyikan benda yang menurut server masih belum tumbuh lagi (saat peta dimuat).
## `items`: [{kind, x, z, left}] dari GET /v1/world.
func apply_server(items: Array) -> void:
	for it: Dictionary in items:
		var kind := str(it.get("kind", ""))
		if kind == "":
			continue
		var tile := Vector2i(int(it.x), int(it.z))
		var left := float(it.get("left", RESPAWN))
		var cell: Array = _grid.get(Vector2i(floori((tile.x + 0.5) / CELL), floori((tile.y + 0.5) / CELL)), [])
		for e: Dictionary in cell:
			if e.kind == kind and e.tile == tile and not e.gone:
				_break(e, left, false)


## Dipanggil tiap bingkai: pulihkan guncangan dan tumbuhkan benda yang waktunya tiba.
func tick(delta: float) -> void:
	for e: Dictionary in _flash.duplicate():
		e.shake = float(e.shake) - delta
		if float(e.shake) <= 0.0:
			_flash.erase(e)
			if not e.gone:
				var mm: MultiMesh = e.mm
				mm.set_instance_transform(int(e.idx), e.xf)
	if _gone.is_empty():
		return
	var now := _now()
	for e: Dictionary in _gone.duplicate():
		if now >= float(e.back):
			_gone.erase(e)
			_restore(e)
