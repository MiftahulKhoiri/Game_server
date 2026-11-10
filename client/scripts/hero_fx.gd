extends RefCounted
## Efek visual kecil untuk aksi di dunia: serpihan, riak kejut, goresan serangan.
## Semua dibuat dari bentuk dasar dan membersihkan dirinya sendiri.

static func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Semburan serpihan kecil (daun, pecahan batu, rumput, kilau emas).
static func burst(parent: Node3D, pos: Vector3, color: Color, amount := 10, speed := 2.6) -> void:
	var p := CPUParticles3D.new()
	var bit := BoxMesh.new()
	bit.size = Vector3(0.09, 0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	bit.material = mat
	p.mesh = bit
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.position = pos
	p.emitting = true
	parent.add_child(p)
	p.finished.connect(p.queue_free)


## Cincin yang melebar di tanah (ledakan Boost, tendangan jauh).
static func ring(parent: Node3D, pos: Vector3, color: Color, radius: float, time := 0.45) -> void:
	var disc := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.3
	m.bottom_radius = 0.3
	m.height = 0.05
	m.radial_segments = 20
	disc.mesh = m
	var mat := _unshaded(Color(color, 0.7))
	disc.material_override = mat
	disc.position = pos + Vector3(0, 0.08, 0)
	parent.add_child(disc)
	var tw := disc.create_tween()
	tw.set_parallel(true)
	tw.tween_property(disc, "scale", Vector3(radius / 0.3, 1.0, radius / 0.3), time)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(disc.queue_free)


## Goresan serangan: batang tipis berpendar di depan pahlawan. `roll` memiringkannya (tebasan).
static func swoosh(parent: Node3D, from: Vector3, yaw: float, length: float, color: Color, roll := 0.0) -> void:
	var bar := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.07, 0.07, length)
	bar.mesh = m
	var mat := _unshaded(Color(color, 0.9))
	bar.material_override = mat
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	bar.position = from + fwd * (length * 0.5 + 0.2)
	bar.rotation = Vector3(0, yaw, roll)
	parent.add_child(bar)
	var tw := bar.create_tween()
	tw.set_parallel(true)
	tw.tween_property(bar, "scale", Vector3(0.2, 3.0, 1.15), 0.16)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(bar.queue_free)


## Gelembung pelindung / aura di sekitar pahlawan.
static func aura(color: Color, radius := 0.62) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 14
	s.rings = 8
	mi.mesh = s
	mi.material_override = _unshaded(color)
	mi.position = Vector3(0, 0.55, 0)
	mi.visible = false
	return mi


## Peluru yang terbang dari `from` ke `to` (roadmap no. 157-158, 164, 166): panah = batang tipis
## dengan ujung; sihir/api = bola berpendar dengan ekor kilau. Meledak kecil di sasaran.
static func bolt(parent: Node3D, from: Vector3, to: Vector3, color: Color, kind := "panah") -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var magic := not kind.begins_with("panah")
	var big := kind.ends_with("besar") or kind == "api"
	var speed := 14.0 if not magic else 9.0
	var time := clampf(dist / speed, 0.06, 0.6)
	var node := Node3D.new()
	parent.add_child(node)
	node.position = from
	if from.distance_to(to) > 0.01:
		node.look_at_from_position(from, to, Vector3.UP)
	if magic:
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16 if big else 0.11
		sm.height = sm.radius * 2.0
		sm.radial_segments = 10
		sm.rings = 5
		orb.mesh = sm
		var om := _unshaded(color.lightened(0.3))
		orb.material_override = om
		node.add_child(orb)
		var trail := CPUParticles3D.new()
		var dot := SphereMesh.new()
		dot.radius = 0.05
		dot.height = 0.1
		dot.radial_segments = 6
		dot.rings = 3
		dot.material = _unshaded(color)
		trail.mesh = dot
		trail.amount = 16
		trail.lifetime = 0.3
		trail.local_coords = false
		trail.spread = 180.0
		trail.initial_velocity_min = 0.2
		trail.initial_velocity_max = 0.6
		trail.gravity = Vector3.ZERO
		trail.scale_amount_min = 0.5
		trail.scale_amount_max = 1.2
		node.add_child(trail)
	else:
		var shaft := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.035, 0.7 if big else 0.5)
		shaft.mesh = bm
		shaft.material_override = _unshaded(color)
		node.add_child(shaft)
		var tip := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.1, 0.14, 0.03)
		tip.mesh = pm
		tip.material_override = _unshaded(Color("c8ccd4"))
		tip.rotation = Vector3(-PI / 2.0, 0, 0)
		tip.position = Vector3(0, 0, -bm.size.z * 0.5 - 0.06)  # look_at: depan = -Z
		node.add_child(tip)
	var tw := node.create_tween()
	tw.tween_property(node, "position", to, time)
	tw.tween_callback(func() -> void:
		var p := node.get_parent() as Node3D
		if p != null:
			burst(p, to, color, 14 if big else 7, 2.4 if magic else 1.6)
			if magic:
				ring(p, Vector3(to.x, 0.02, to.z), color, 1.3 if big else 0.8, 0.3)
		node.queue_free())


## Percikan darah bergaya kartun (roadmap no. 165): tetes merah kecil yang jatuh, tanpa genangan.
## Makhluk batu/kerangka memercikkan serpihan abu-abu sebagai gantinya.
static func blood(parent: Node3D, pos: Vector3, amount := 8, stone := false) -> void:
	var p := CPUParticles3D.new()
	var drop := SphereMesh.new()
	drop.radius = 0.045
	drop.height = 0.09
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("9a9a96") if stone else Color("b0121c")
	mat.roughness = 0.4
	drop.material = mat
	p.mesh = drop
	p.amount = amount
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.position = pos
	p.emitting = true
	parent.add_child(p)
	p.finished.connect(p.queue_free)


## Lingkaran mantra di tanah (roadmap no. 166): cincin berpendar yang berputar lalu memudar.
static func magic_circle(parent: Node3D, pos: Vector3, color: Color, radius := 1.0, time := 0.9) -> void:
	var ring_mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.86
	tm.outer_radius = radius
	tm.rings = 24
	tm.ring_segments = 4
	ring_mi.mesh = tm
	var mat := _unshaded(Color(color, 0.85))
	ring_mi.material_override = mat
	ring_mi.position = pos + Vector3(0, 0.04, 0)
	ring_mi.scale = Vector3(1, 0.15, 1)
	parent.add_child(ring_mi)
	var inner := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = radius * 0.5
	tm2.outer_radius = radius * 0.56
	tm2.rings = 6  # segi enam: kesan rune
	tm2.ring_segments = 4
	inner.mesh = tm2
	inner.material_override = mat
	ring_mi.add_child(inner)
	var sparks := CPUParticles3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = _unshaded(color.lightened(0.4))
	sparks.mesh = dot
	sparks.amount = 18
	sparks.lifetime = 0.8
	sparks.one_shot = true
	sparks.explosiveness = 0.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_radius = radius * 0.9
	sparks.emission_ring_inner_radius = radius * 0.5
	sparks.emission_ring_height = 0.05
	sparks.emission_ring_axis = Vector3.UP
	sparks.direction = Vector3.UP
	sparks.spread = 10.0
	sparks.initial_velocity_min = 0.8
	sparks.initial_velocity_max = 1.6
	sparks.gravity = Vector3.ZERO
	sparks.position = pos
	sparks.emitting = true
	parent.add_child(sparks)
	sparks.finished.connect(sparks.queue_free)
	var tw := ring_mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring_mi, "rotation:y", TAU * 0.5, time)
	tw.tween_property(mat, "albedo_color:a", 0.0, time * 0.5).set_delay(time * 0.5)
	tw.chain().tween_callback(ring_mi.queue_free)
