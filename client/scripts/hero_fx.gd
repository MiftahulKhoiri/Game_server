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
	var t := parent.get_tree().create_timer(1.1)
	t.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


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
