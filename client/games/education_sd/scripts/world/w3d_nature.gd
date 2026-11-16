extends RefCounted
## Alam & suasana pulau (paket visual 5.0): shader medan, laut, sungai, rumput, daun bergoyang, awan,
## burung, kupu-kupu, serbuk sari. Semua gerakan dihitung di GPU (shader + INSTANCE_CUSTOM), tanpa
## pembaruan per bingkai di CPU. Shader & tekstur derau dibuat sekali lalu dipakai ulang (cache statis).
## Aman untuk renderer GL Compatibility (Android).

static var _noise_tex: Texture2D
static var _shaders: Dictionary = {}
static var _meshes: Dictionary = {}


static func noise_tex() -> Texture2D:
	if _noise_tex == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		fn.seed = 4242
		var img := fn.get_seamless_image(256, 256)
		img.generate_mipmaps()
		_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex


static func shader(id: String) -> Shader:
	if not _shaders.has(id):
		var s := Shader.new()
		s.code = CODE[id]
		_shaders[id] = s
	return _shaders[id]


static func smat(id: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(id)
	if id in ["terrain", "sea", "river", "grass", "flower"]:
		m.set_shader_parameter("noise", noise_tex())
	return m


## Palet rumput dari warna dasar pulau: dua nada (gelap kebiruan & terang kekuningan) + rumput kering.
static func grass_palette(base: Color) -> Dictionary:
	var a := Color.from_hsv(fposmod(base.h + 0.025, 1.0), clampf(base.s * 1.05, 0.0, 0.85), base.v * 0.62)
	var b := Color.from_hsv(fposmod(base.h - 0.03, 1.0), clampf(base.s * 0.95, 0.0, 0.85), minf(base.v * 0.86, 0.85))
	var dry := Color.from_hsv(0.13, 0.45, minf(base.v * 0.9, 0.85))
	return {"a": a, "b": b, "dry": dry}


static func terrain_mat(t, base: Color, sand: Color, path: Color, plaza: Color) -> ShaderMaterial:
	var m := smat("terrain")
	var p := grass_palette(base)
	m.set_shader_parameter("splat", t.splat_texture())
	m.set_shader_parameter("grass_a", p.a)
	m.set_shader_parameter("grass_b", p.b)
	m.set_shader_parameter("grass_dry", p.dry)
	m.set_shader_parameter("path_col", path)
	m.set_shader_parameter("plaza_col", plaza)
	m.set_shader_parameter("forest_col", Color.from_hsv(fposmod(p.a.h + 0.03, 1.0), p.a.s * 0.9, p.a.v * 0.62))
	var sd := sand.lerp(Color("d0a462"), 0.6).darkened(0.1)
	m.set_shader_parameter("sand_col", sd)
	m.set_shader_parameter("wet_col", sd.darkened(0.3).lerp(Color("5f7a6a"), 0.15))
	m.set_shader_parameter("extent", float(t.extent))
	m.set_shader_parameter("radius", float(t.radius))
	return m


# --- Rumput & bunga ---------------------------------------------------------------------------------

## Serumpun rumput: `blades` helai segitiga; COLOR.r = tinggi relatif (0 pangkal, 1 ujung),
## COLOR.g = 1 untuk kepala bunga. Normal menghadap atas supaya warnanya menyatu dengan tanah.
static func tuft_mesh(flower: bool) -> ArrayMesh:
	var key := "flower" if flower else "tuft"
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if flower else 31
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var nrm := PackedVector3Array()
	var blades := 4 if flower else 6
	for i in blades:
		var a := TAU * i / blades + rng.randf_range(-0.4, 0.4)
		var r := rng.randf_range(0.02, 0.12)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var side := Vector3(-sin(a), 0, cos(a)) * rng.randf_range(0.035, 0.05)
		var hgt := rng.randf_range(0.28, 0.5) * (0.8 if flower else 1.0)
		var tip := base + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.06, 0.16) + Vector3(0, hgt, 0)
		for p in [[base - side, 0.0], [base + side, 0.0], [tip, 1.0]]:
			v.append(p[0])
			c.append(Color(p[1], 0, 0))
			nrm.append(Vector3.UP)
	if flower:
		# Kepala bunga: piramida ganda kecil di atas tangkai tengah.
		var top := Vector3(0, 0.42, 0)
		var stem := [Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), top]
		for p in stem:
			v.append(p)
			c.append(Color(0.5, 0, 0))
			nrm.append(Vector3.UP)
		var rr := 0.075
		var ring := [Vector3(rr, 0, 0), Vector3(0, 0, rr), Vector3(-rr, 0, 0), Vector3(0, 0, -rr)]
		for k in 4:
			for tri in [[top + Vector3(0, 0.05, 0), top + ring[k], top + ring[(k + 1) % 4]], [top - Vector3(0, 0.02, 0), top + ring[(k + 1) % 4], top + ring[k]]]:
				for p in tri:
					v.append(p)
					c.append(Color(1.0, 1.0, 0))
					nrm.append(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_NORMAL] = nrm
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = m
	return m


const FLOWER_COLS := [Color("ffd23f"), Color("ff6fa8"), Color("ffffff"), Color("b28dff"), Color("ff8a3d"), Color("6fd0ff")]


## Tanam rumput & bunga di sekitar pulau dalam petak 16 m (MultiMesh per petak supaya petak jauh
## tidak digambar). count = jumlah rumpun rumput; bunga ~ 1/6. far = jarak rumput mengecil lalu hilang.
## Mengembalikan titik-titik bunga (untuk kupu-kupu).
static func plant_grass(w: Node3D, t, base: Color, count: int, far: float, sway: bool, seed_: int) -> Array:
	var fl_pts := []
	if count <= 0:
		return fl_pts
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var chunk := 16.0
	var cells := {}
	var total := count + count / 6
	var placed := 0
	var tries := 0
	var r: float = t.radius - 2.0
	while placed < total and tries < total * 4:
		tries += 1
		# Ditanam bertahap (tidak menahan bingkai pertama saat pulau dibuka di HP).
		if tries % 3000 == 0:
			await w.get_tree().process_frame
			if not is_instance_valid(w) or not w.is_inside_tree():
				return fl_pts
		var p := Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
		if p.length() > r or not t.grass_ok(p.x, p.y):
			continue
		# Rumput tidak merata: sebagian padang lebih jarang (tidak terlihat seperti karpet).
		if t.noise2.get_noise_2d(p.x * 2.0, p.y * 2.0) < -0.35 and rng.randf() < 0.7:
			continue
		var flower := placed >= count
		if flower and t.noise2.get_noise_2d(p.x * 3.0, p.y * 3.0) < 0.1:
			continue  # bunga tumbuh berkelompok (petak-petak), bukan merata
		var key := Vector2i(floori(p.x / chunk), floori(p.y / chunk))
		if not cells.has(key):
			cells[key] = [[], []]
		var sc := rng.randf_range(0.75, 1.35)
		var y: float = t.height(p.x, p.y) - 0.02
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc)), Vector3(p.x, y, p.y))
		var fc: Color = FLOWER_COLS[rng.randi() % FLOWER_COLS.size()]
		cells[key][1 if flower else 0].append([xf, Color(rng.randf(), fc.r, fc.g, fc.b)])
		if flower and fl_pts.size() < 60:
			fl_pts.append(Vector3(p.x, y, p.y))
		placed += 1
	var pal := grass_palette(base)
	var mats := []
	for flower in [false, true]:
		var m := smat("flower" if flower else "grass")
		m.set_shader_parameter("grass_a", pal.a)
		m.set_shader_parameter("grass_b", pal.b)
		m.set_shader_parameter("grass_dry", pal.dry)
		m.set_shader_parameter("far", far)
		m.set_shader_parameter("sway", 1.0 if sway else 0.0)
		mats.append(m)
	var root := Node3D.new()
	root.name = "Grass"
	w.add_child(root)
	var nchunk := 0
	for key in cells:
		nchunk += 1
		if nchunk % 10 == 0:
			await w.get_tree().process_frame
			if not is_instance_valid(w) or not w.is_inside_tree():
				return fl_pts
		for kind in 2:
			var arr: Array = cells[key][kind]
			if arr.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = tuft_mesh(kind == 1)
			mm.instance_count = arr.size()
			for i in arr.size():
				mm.set_instance_transform(i, arr[i][0])
				mm.set_instance_custom_data(i, arr[i][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mats[kind]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = far + chunk
			root.add_child(mmi)
	root.set_meta("tufts", placed)
	return fl_pts


## Bahan daun bergoyang untuk pohon MultiMesh: warna asli permukaan × variasi per pohon (INSTANCE_CUSTOM).
static func leaf_mat(src: Material, sway: bool) -> ShaderMaterial:
	var col := Color("3f8f3f")
	if src is BaseMaterial3D:
		col = (src as BaseMaterial3D).albedo_color
	var m := smat("leaf")
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("sway", 1.0 if sway else 0.0)
	return m


static func bark_mat(src: Material) -> ShaderMaterial:
	var col := Color("8a5a2b")
	if src is BaseMaterial3D:
		col = (src as BaseMaterial3D).albedo_color
	var m := smat("bark")
	m.set_shader_parameter("albedo", col)
	return m


# --- Suasana: awan, burung, kupu-kupu, serbuk sari --------------------------------------------------

static func _cloud_mesh() -> ArrayMesh:
	if _meshes.has("cloud"):
		return _meshes.cloud
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var puffs := [[Vector3(0, 0, 0), 4.2], [Vector3(4.5, -0.6, 0.8), 3.3], [Vector3(-4.6, -0.8, -0.4), 3.0],
		[Vector3(1.6, 1.8, -0.6), 3.0], [Vector3(-1.8, 1.2, 1.2), 2.6], [Vector3(7.5, -1.4, -0.4), 2.1], [Vector3(-7.4, -1.6, 0.6), 1.9]]
	for pf in puffs:
		var sm := SphereMesh.new()
		sm.radius = pf[1]
		sm.height = pf[1] * 1.6
		sm.radial_segments = 10
		sm.rings = 6
		st.append_from(sm, 0, Transform3D(Basis(), pf[0]))
	var m := st.commit()
	_meshes.cloud = m
	return m


## Burung: dua sayap segitiga (COLOR.r = jarak dari badan, untuk kepakan).
static func _bird_mesh() -> ArrayMesh:
	if _meshes.has("bird"):
		return _meshes.bird
	var v := PackedVector3Array([Vector3(0, 0, 0.25), Vector3(0, 0, -0.2), Vector3(-0.75, 0.05, -0.1),
		Vector3(0, 0, -0.2), Vector3(0, 0, 0.25), Vector3(0.75, 0.05, -0.1),
		Vector3(0, 0.02, 0.35), Vector3(-0.06, 0, -0.25), Vector3(0.06, 0, -0.25)])
	var c := PackedColorArray([Color(0, 0, 0), Color(0, 0, 0), Color(1, 0, 0), Color(0, 0, 0), Color(0, 0, 0), Color(1, 0, 0),
		Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes.bird = m
	return m


static func _gpu_swarm(w: Node3D, name_: String, mesh: Mesh, mat: Material, customs: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = customs.size()
	for i in customs.size():
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-400, -20, -400), Vector3(800, 200, 800))
	w.add_child(mmi)
	return mmi


## Awan berarak, burung berputar, kupu-kupu di padang bunga. profile: {birds, fx}; flowers: titik bunga.
static func ambience(w: Node3D, radius: float, profile: Dictionary, sky_tint: Color, flowers: Array, seed_: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	# Awan: 12 gumpal di cincin sekeliling pulau; bergerak memutar sangat pelan di shader.
	var clouds := []
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf_range(-0.2, 0.2)
		var d := rng.randf_range(radius * 0.9, radius * 2.2)
		clouds.append(Color(a, d, rng.randf_range(34.0, 52.0), rng.randf_range(0.8, 1.6)))
	var cm := smat("cloud")
	cm.set_shader_parameter("shade", sky_tint.lerp(Color("c8d4e8"), 0.6))
	cm.set_shader_parameter("move", 1.0 if bool(profile.get("fx", true)) else 0.0)
	_gpu_swarm(w, "Clouds", _cloud_mesh(), cm, clouds)
	# Burung: berputar di atas pulau & camar di atas pantai.
	var nb := int(profile.get("birds", 0)) * 3
	if nb > 0:
		var birds := []
		for i in nb:
			var gull := i % 3 == 0
			var a := rng.randf() * TAU
			var d := rng.randf_range(radius * 0.95, radius * 1.15) if gull else rng.randf_range(8.0, radius * 0.7)
			birds.append(Color(cos(a) * d, sin(a) * d, rng.randf_range(10.0, 18.0) + (0.0 if gull else 6.0), rng.randf_range(0.0, 100.0)))
		var bm := smat("bird")
		bm.set_shader_parameter("tint", Color("f4f2ea"))
		_gpu_swarm(w, "Birds", _bird_mesh(), bm, birds)
	# Kupu-kupu di sekitar padang bunga.
	if bool(profile.get("fx", false)) and not flowers.is_empty():
		var bf := []
		for i in mini(int(profile.get("birds", 0)) * 5, 30):
			var p: Vector3 = flowers[rng.randi() % flowers.size()]
			var fc: Color = FLOWER_COLS[rng.randi() % FLOWER_COLS.size()]
			bf.append(Color(p.x + rng.randf_range(-2, 2), p.z + rng.randf_range(-2, 2), p.y + rng.randf_range(0.6, 1.4), fc.h))
		if not bf.is_empty():
			var bmi := _gpu_swarm(w, "Butterflies", _bird_mesh(), smat("butterfly"), bf)
			bmi.visibility_range_end = 45.0


## Serbuk sari / debu cahaya melayang di sekitar pemain (CPUParticles, ringan).
static func motes(player: Node3D, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Motes"
	p.amount = 36
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14, 3, 14)
	p.direction = Vector3(0.3, 0.2, 0.1)
	p.spread = 180.0
	p.gravity = Vector3(0, 0.02, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, 0.75)
	q.material = m
	p.mesh = q
	p.position = Vector3(0, 1.5, 0)
	player.add_child(p)
	return p


const CODE := {
"terrain": """shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 grass_dry : source_color;
uniform vec3 path_col : source_color;
uniform vec3 plaza_col : source_color;
uniform vec3 forest_col : source_color;
uniform vec3 sand_col : source_color;
uniform vec3 wet_col : source_color;
uniform float extent = 80.0;
uniform float radius = 70.0;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = NORMAL;
}
void fragment() {
	vec2 p = wp.xz;
	float n1 = texture(noise, p * 0.012).r;
	float n2 = texture(noise, p * 0.09).r;
	float n3 = texture(noise, p * 0.41).r;
	vec4 m = texture(splat, p / (2.0 * extent) + 0.5 + (vec2(n2, n3) - 0.5) * 0.004);
	vec3 col = mix(grass_a, grass_b, smoothstep(0.32, 0.68, n1));
	col = mix(col, grass_dry, smoothstep(0.6, 0.8, n2) * 0.4);
	col *= 0.88 + 0.24 * n3;
	col = mix(col, forest_col, m.b * 0.8);
	float edge = (n2 - 0.5) * 0.4 + (n3 - 0.5) * 0.2;
	float path = smoothstep(0.4, 0.52, m.r + edge);
	float rim = smoothstep(0.3, 0.42, m.r + edge) - path;
	vec3 pc = path_col * (0.86 + 0.28 * n3) * (1.0 - 0.12 * smoothstep(0.55, 0.75, n2));
	col = mix(col, col * 0.78, clamp(rim, 0.0, 1.0));
	col = mix(col, pc, path);
	vec2 cell = floor(p * 1.1);
	vec2 tile = abs(fract(p * 1.1) - 0.5);
	float joint = smoothstep(0.42, 0.48, max(tile.x, tile.y));
	float tn = texture(noise, cell * 0.173).r;
	vec3 plc = plaza_col * (0.85 + 0.3 * tn) * (1.0 - 0.2 * joint);
	float plaza = smoothstep(0.42, 0.58, m.g + edge * 0.3);
	col = mix(col, plc, plaza);
	float r = length(p) + (n1 - 0.5) * 5.0;
	float sand = smoothstep(radius - 2.0, radius + 0.5, r);
	col = mix(col, sand_col * (0.92 + 0.14 * n3), sand);
	col = mix(col, wet_col * (0.9 + 0.2 * n3), 1.0 - smoothstep(-0.42, -0.1, wp.y));
	col *= mix(0.8, 1.0, smoothstep(0.7, 0.96, wn.y));
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
""",
"sea": """shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.05, 0.33, 0.62);
uniform vec3 shallow : source_color = vec3(0.2, 0.75, 0.8);
uniform vec3 foam : source_color = vec3(0.96, 0.98, 1.0);
uniform float shore_r = 75.0;
uniform float move = 1.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float t = TIME * move;
	vec2 p = wp.xz;
	float n1 = texture(noise, p * 0.018 + vec2(t * 0.006, t * 0.004)).r;
	float n2 = texture(noise, p * 0.055 - vec2(t * 0.011, -t * 0.008)).r;
	float n3 = texture(noise, p * 0.13 + vec2(-t * 0.02, t * 0.017)).r;
	float d = length(p) - shore_r + (n1 - 0.5) * 3.0;
	vec3 col = mix(shallow, deep, smoothstep(-1.0, 22.0, d));
	col += vec3(0.05, 0.07, 0.07) * smoothstep(0.55, 0.85, n2 * 0.6 + n3 * 0.5);
	float band = sin(d * 2.4 - t * 1.4) * 0.5 + 0.5;
	float lines = (1.0 - smoothstep(0.5, 3.5, d)) * smoothstep(-0.5, 0.5, d) * smoothstep(0.62, 0.92, band * 0.55 + n3 * 0.6);
	float edge = 1.0 - smoothstep(-0.4, 0.5, d + (n3 - 0.5) * 1.2);
	float f = clamp(max(lines * 0.7, edge * 0.75), 0.0, 1.0);
	col = mix(col, foam, f * 0.8);
	NORMAL_MAP = normalize(vec3(n2 - 0.5 + (n3 - 0.5) * 0.6, n3 - 0.5 - (n2 - 0.5) * 0.4, 1.4)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ALBEDO = col;
	ROUGHNESS = mix(0.18, 0.7, f);
	SPECULAR = 0.35;
}
""",
"river": """shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.05, 0.3, 0.52);
uniform vec3 shallow : source_color = vec3(0.2, 0.55, 0.6);
uniform float move = 1.0;
varying vec3 wp;
varying vec2 uv;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	uv = UV;
}
void fragment() {
	float t = TIME * move;
	vec2 p = wp.xz;
	float across = abs(uv.y - 0.5) * 2.0;
	float n1 = texture(noise, vec2(p.x * 0.05 - t * 0.12, p.y * 0.12)).r;
	float n2 = texture(noise, vec2(p.x * 0.14 - t * 0.3, p.y * 0.35)).r;
	vec3 col = mix(deep, shallow, smoothstep(0.35, 1.0, across + (n1 - 0.5) * 0.3));
	float streak = smoothstep(0.62, 0.8, n2) * (1.0 - across * 0.6);
	col += vec3(0.12) * streak;
	float f = smoothstep(0.82, 1.0, across + (n2 - 0.5) * 0.25);
	col = mix(col, vec3(0.94, 0.97, 1.0), f * 0.8);
	NORMAL_MAP = vec3(n1, n2, 1.0);
	NORMAL_MAP_DEPTH = 0.5;
	ALBEDO = col;
	ROUGHNESS = mix(0.15, 0.6, f);
	SPECULAR = 0.35;
}
""",
"grass": """shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 grass_dry : source_color;
uniform float sway = 1.0;
uniform float far = 32.0;
varying vec3 wp;
varying float h;
varying float tint;
void vertex() {
	h = COLOR.r;
	tint = INSTANCE_CUSTOM.r;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(o, CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(far - 10.0, far, d);
	float s = sin(TIME * 1.6 + o.x * 0.31 + o.z * 0.23) + 0.5 * sin(TIME * 2.9 + o.z * 0.7);
	VERTEX.x += s * 0.07 * h * h * sway;
	VERTEX.z += s * 0.035 * h * h * sway;
	wp = o;
}
void fragment() {
	float n1 = texture(noise, wp.xz * 0.012).r;
	float n2 = texture(noise, wp.xz * 0.09).r;
	vec3 base = mix(grass_a, grass_b, smoothstep(0.32, 0.68, n1));
	base = mix(base, grass_dry, smoothstep(0.6, 0.8, n2) * 0.4);
	ALBEDO = mix(base * 0.82, base * 1.16 + vec3(0.02, 0.03, 0.0), h) * (0.92 + 0.16 * tint);
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
""",
"flower": """shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 grass_dry : source_color;
uniform float sway = 1.0;
uniform float far = 32.0;
varying vec3 wp;
varying float h;
varying float head;
varying vec3 petal;
void vertex() {
	h = COLOR.r;
	head = COLOR.g;
	petal = INSTANCE_CUSTOM.gba;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(o, CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(far - 10.0, far, d);
	float s = sin(TIME * 1.6 + o.x * 0.31 + o.z * 0.23);
	VERTEX.x += s * 0.06 * h * sway;
	wp = o;
}
void fragment() {
	float n1 = texture(noise, wp.xz * 0.012).r;
	vec3 base = mix(grass_a, grass_b, smoothstep(0.32, 0.68, n1));
	vec3 leaf = mix(base * 0.7, base * 1.2, h);
	ALBEDO = mix(leaf, petal, step(0.5, head));
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
""",
"leaf": """shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 albedo : source_color;
uniform float sway = 1.0;
varying float tint;
varying float warm;
void vertex() {
	tint = INSTANCE_CUSTOM.r;
	warm = INSTANCE_CUSTOM.g;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = max(VERTEX.y - 0.8, 0.0);
	float s = sin(TIME * 1.1 + o.x * 0.2 + o.z * 0.17) * 0.045 + sin(TIME * 2.3 + VERTEX.y * 2.0 + o.x) * 0.012;
	VERTEX.x += s * k * sway;
	VERTEX.z += s * 0.6 * k * sway;
}
void fragment() {
	vec3 c = albedo * (0.82 + 0.36 * tint);
	c = mix(c, c * vec3(1.18, 1.08, 0.7), warm * 0.45);
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
""",
"bark": """shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 albedo : source_color;
varying float tint;
void vertex() {
	tint = INSTANCE_CUSTOM.r;
}
void fragment() {
	ALBEDO = albedo * (0.85 + 0.3 * tint);
	ROUGHNESS = 0.95;
}
""",
"cloud": """shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, shadows_disabled;
uniform vec3 shade : source_color = vec3(0.78, 0.84, 0.95);
uniform float move = 1.0;
varying float ly;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float a = c.r + TIME * 0.0035 * move;
	ly = VERTEX.y;
	vec3 v = VERTEX * c.a;
	float ca = cos(a);
	float sa = sin(a);
	vec3 rv = vec3(v.x * ca - v.z * sa, v.y, v.x * sa + v.z * ca);
	VERTEX = rv + vec3(cos(a) * c.g, c.b, sin(a) * c.g);
}
void fragment() {
	float k = smoothstep(-2.5, 3.5, ly);
	ALBEDO = mix(shade, vec3(1.0), k);
}
""",
"bird": """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.95, 0.95, 0.92);
varying float wing;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float sp = 0.18 + fract(c.a * 0.37) * 0.12;
	float a = TIME * sp + c.a;
	float rad = 7.0 + fract(c.a * 0.71) * 9.0;
	vec3 center = vec3(c.r, c.b + sin(TIME * 0.4 + c.a) * 1.5, c.g);
	vec3 pos = center + vec3(cos(a) * rad, 0.0, sin(a) * rad);
	vec3 fwd = normalize(vec3(-sin(a), 0.0, cos(a)));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 v = VERTEX;
	wing = COLOR.r;
	v.y += sin(TIME * 9.0 + c.a * 3.0) * 0.35 * COLOR.r;
	VERTEX = pos + right * v.x * 1.1 + vec3(0.0, v.y, 0.0) + fwd * v.z * 1.1;
}
void fragment() {
	ALBEDO = mix(tint * 0.75, tint, wing);
}
""",
"butterfly": """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
varying vec3 col;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float ph = fract(sin(c.r * 12.9898 + c.g * 78.233) * 43758.5453) * 100.0;
	float a = TIME * 0.6 + ph;
	vec3 pos = vec3(c.r + sin(a) * 1.8 + sin(a * 2.3) * 0.6, c.b + sin(a * 3.1) * 0.35, c.g + cos(a * 0.8) * 1.6);
	vec3 fwd = normalize(vec3(cos(a) * 1.8, 0.0, -sin(a * 0.8) * 1.3) + vec3(0.001));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 v = VERTEX * 0.22;
	float flap = sin(TIME * 22.0 + ph * 7.0);
	v.y += abs(v.x) * flap * 1.6;
	v.x *= 0.6 + 0.4 * abs(cos(TIME * 22.0 + ph * 7.0));
	VERTEX = pos + right * v.x + vec3(0.0, v.y, 0.0) + fwd * v.z;
	float hh = c.a;
	col = clamp(abs(fract(vec3(hh) + vec3(0.0, 0.667, 0.333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0) * 0.8 + 0.2;
}
void fragment() {
	ALBEDO = col;
}
""",
}
