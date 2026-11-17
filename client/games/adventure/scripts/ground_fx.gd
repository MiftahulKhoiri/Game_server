extends RefCounted
## Tanah & rumput yang lebih hidup untuk peta alam terbuka (Desa Awal, Perbatasan, Hutan Binatang).
##
## Hanya tampilan: petak peta, jalan, tabrakan, dan data server tidak berubah (tanah tetap datar, y = 0).
##   - Tanah: satu shader untuk semua petak rumput/jalan/pasir. Jenis petak dibaca dari tekstur kecil
##     (1 piksel = 1 petak) dengan penyaringan linear + derau, sehingga tepi jalan tanah berkelok alami,
##     rumput dua nada berbercak, lantai hutan lebih gelap di sekitar pohon, dan ada bintik kelopak bunga.
##   - Rumput: rumpun helai (gaya Petualangan Ilmu SD) dengan warna dari derau dunia, bergoyang angin,
##     mengecil lalu hilang di kejauhan. Kepadatan & jarak mengikuti profil grafis (Hemat/Normal/Tinggi).
##   - Bunga: berkelompok (derau), 6 warna, lewat INSTANCE_CUSTOM.
## Semua gerak dihitung GPU; bahan & tekstur derau dibuat sekali (cache statis). Aman untuk GL Compatibility.

const Maps = preload("res://games/adventure/scripts/maps.gd")
const Perf = preload("res://scripts/perf.gd")

## Peta yang memakai tampilan ini (alam terbuka, bukan gua/gunung/istana/ruangan).
const MAPS := ["desa_awal", "perbatasan", "hutan_lebat"]

## Rumpun hiasan per petak rumput, jarak rumput terlihat (m), dan peluang bunga per petak, per profil.
const TUFTS_PER_TILE := [0.8, 1.8, 2.8]
const GRASS_FAR := [18.0, 26.0, 36.0]
const FLOWER_CHANCE := [0.05, 0.09, 0.12]
const CHUNK := 12.0

const FLOWER_COLS := [Color("ffd23f"), Color("ff6fa8"), Color("ffffff"), Color("b28dff"), Color("ff8a3d"), Color("6fd0ff")]

static var _noise_tex: Texture2D
static var _shaders: Dictionary = {}
static var _meshes: Dictionary = {}
static var _grass_mats: Dictionary = {}  # "<far>|<flower>" -> ShaderMaterial (dibagi antar peta)


static func applies(map_id: String) -> bool:
	return map_id in MAPS


## Petak yang tanahnya digambar shader ini: rumput (termasuk di bawah pohon, pagar, gerbang, sumur kecil),
## jalan tanah, dan pasir tepi air. Petak lain (ladang, batu, lantai rumah) tetap memakai warna lama.
static func is_natural(t: String) -> bool:
	return t in [".", "f", "#", "=", "F", "P", "N"]


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


static func _shader(id: String) -> Shader:
	if not _shaders.has(id):
		var s := Shader.new()
		s.code = CODE[id]
		_shaders[id] = s
	return _shaders[id]


## Tekstur jenis petak: R = jalan tanah, G = pasir tepi air, B = lantai hutan (pohon & sekitarnya).
static func splat_texture(rows: Array[String], w: int, h: int, sand: Dictionary) -> ImageTexture:
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	for z in h:
		for x in w:
			var t := rows[z][x] if z < rows.size() and x < rows[z].length() else "."
			var r := 1.0 if t == "=" or t == "B" else 0.0
			var g := 1.0 if sand.has(Vector2i(x, z)) or t == "~" else 0.0
			var b := 1.0 if t == "#" else 0.0
			img.set_pixel(x, z, Color(r, g, b, 1.0))
	return ImageTexture.create_from_image(img)


## Bahan tanah untuk satu peta. `sand` = petak pasir tepi air (Vector2i -> true).
static func ground_mat(rows: Array[String], w: int, h: int, sand: Dictionary, hutan: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("ground")
	m.set_shader_parameter("noise", noise_tex())
	m.set_shader_parameter("splat", splat_texture(rows, w, h, sand))
	m.set_shader_parameter("size", Vector2(w, h))
	m.set_shader_parameter("grass_a", Color("3f8a2e") if hutan else Color("4c9a34"))
	m.set_shader_parameter("grass_b", Color("7fc04a") if hutan else Color("93cf55"))
	m.set_shader_parameter("grass_dry", Color("b9b866"))
	m.set_shader_parameter("forest_col", Color("2f5f22"))
	m.set_shader_parameter("path_col", Color("d8bd86"))
	m.set_shader_parameter("sand_col", Color("e2cf98"))
	m.set_shader_parameter("petals", 0.6 if hutan else 1.0)
	return m


## Serumpun rumput: helai segitiga; UV.y = tinggi relatif (0 pangkal, 1 ujung), UV.x = 1 di kepala bunga.
static func tuft_mesh(flower := false) -> ArrayMesh:
	var key := "flower" if flower else "tuft"
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if flower else 31
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var nrm := PackedVector3Array()
	var blades := 4 if flower else 6
	for i in blades:
		var a := TAU * i / blades + rng.randf_range(-0.4, 0.4)
		var r := rng.randf_range(0.02, 0.11)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var side := Vector3(-sin(a), 0, cos(a)) * rng.randf_range(0.03, 0.045)
		var hgt := rng.randf_range(0.24, 0.42) * (0.8 if flower else 1.0)
		var tip := base + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.14) + Vector3(0, hgt, 0)
		for p in [[base - side, 0.0], [base + side, 0.0], [tip, 1.0]]:
			v.append(p[0])
			uv.append(Vector2(0, p[1]))
			nrm.append(Vector3.UP)
	if flower:
		var top := Vector3(0, 0.36, 0)
		for p in [Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), top]:
			v.append(p)
			uv.append(Vector2(0, 0.5))
			nrm.append(Vector3.UP)
		var rr := 0.07
		var ring := [Vector3(rr, 0, 0), Vector3(0, 0, rr), Vector3(-rr, 0, 0), Vector3(0, 0, -rr)]
		for k in 4:
			for tri in [[top + Vector3(0, 0.045, 0), top + ring[k], top + ring[(k + 1) % 4]],
					[top - Vector3(0, 0.02, 0), top + ring[(k + 1) % 4], top + ring[k]]]:
				for p in tri:
					v.append(p)
					uv.append(Vector2(1.0, 1.0))
					nrm.append(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_NORMAL] = nrm
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = m
	return m


## Bahan rumput/bunga (dibagi antar peta; parameter `angin` diubah lewat set_wind saat hujan).
static func grass_mat(flower := false, far := -1.0) -> ShaderMaterial:
	if far < 0.0:
		far = float(Perf.pick(GRASS_FAR))
	var key := "%d|%s" % [roundi(far), flower]
	if not _grass_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("flower" if flower else "grass")
		m.set_shader_parameter("noise", noise_tex())
		m.set_shader_parameter("far", far)
		_grass_mats[key] = m
	return _grass_mats[key]


static func set_wind(v: float) -> void:
	for m: ShaderMaterial in _grass_mats.values():
		m.set_shader_parameter("angin", v)


static func _jit(x: int, z: int, salt: int) -> float:
	var h := (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	return float(h & 0xFFFF) / 65535.0


## Rumpun hiasan tambahan (tidak bisa dipukul) & bunga di petak rumput, dikelompokkan per sel 12 m dengan
## batas jarak gambar. `skip(x, z)` = true untuk petak yang harus dibiarkan kosong (titik awal, NPC, dsb.).
## Mengembalikan {"tufts": n, "bunga": n}.
static func plant(root: Node3D, rows: Array[String], skip: Callable) -> Dictionary:
	var per_tile: float = Perf.pick(TUFTS_PER_TILE)
	var p_flower: float = Perf.pick(FLOWER_CHANCE)
	var far: float = Perf.pick(GRASS_FAR)
	var cells := {}  # Vector2i -> [[xf, custom], ...] x2 (rumput, bunga)
	var n_t := 0
	var n_f := 0
	var fn := FastNoiseLite.new()
	fn.seed = 913
	fn.frequency = 0.08
	for z in rows.size():
		for x in rows[z].length():
			var t: String = rows[z][x]
			if t != "." and t != "f":
				continue
			if skip.call(x, z):
				continue
			# Padang tidak merata: sebagian bercak lebih jarang supaya tidak seperti karpet.
			var dens := per_tile * (0.45 if fn.get_noise_2d(x, z) < -0.3 else 1.0)
			var n := int(dens) + (1 if _jit(x, z, 300) < fmod(dens, 1.0) else 0)
			for i in n:
				var p := Vector3(x + _jit(x, z, 310 + i), 0.0, z + _jit(x, z, 330 + i))
				var sc := 0.8 + 0.55 * _jit(x, z, 350 + i)
				var xf := Transform3D(Basis(Vector3.UP, _jit(x, z, 370 + i) * TAU).scaled(Vector3(sc, sc * (0.85 + 0.4 * _jit(x, z, 390 + i)), sc)), p)
				_put(cells, p, 0, xf, Color(_jit(x, z, 410 + i), 0, 0, 0))
				n_t += 1
			# Bunga berkelompok: hanya di bercak derau positif.
			if fn.get_noise_2d(x * 0.7 + 50.0, z * 0.7) > 0.15 and _jit(x, z, 500) < p_flower * 2.5:
				var k := 1 + int(_jit(x, z, 501) * 2.0)
				for i in k:
					var pf := Vector3(x + 0.15 + 0.7 * _jit(x, z, 510 + i), 0.0, z + 0.15 + 0.7 * _jit(x, z, 520 + i))
					var fc: Color = FLOWER_COLS[int(_jit(x, z, 530 + i) * 1000.0) % FLOWER_COLS.size()]
					var sf := 0.85 + 0.4 * _jit(x, z, 540 + i)
					_put(cells, pf, 1, Transform3D(Basis(Vector3.UP, _jit(x, z, 550 + i) * TAU).scaled(Vector3.ONE * sf), pf),
						Color(_jit(x, z, 560 + i), fc.r, fc.g, fc.b))
					n_f += 1
	var holder := Node3D.new()
	holder.name = "RumputHias"
	holder.set_meta("no_merge", true)
	root.add_child(holder)
	for key: Vector2i in cells:
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
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = grass_mat(kind == 1, far)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = far + CHUNK
			holder.add_child(mi)
	return {"tufts": n_t, "bunga": n_f}


static func _put(cells: Dictionary, p: Vector3, kind: int, xf: Transform3D, custom: Color) -> void:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not cells.has(key):
		cells[key] = [[], []]
	cells[key][kind].append([xf, custom])


const CODE := {
"ground": """shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec2 size = vec2(48.0, 48.0);
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 grass_dry : source_color;
uniform vec3 forest_col : source_color;
uniform vec3 path_col : source_color;
uniform vec3 sand_col : source_color;
uniform float petals = 1.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wp.xz;
	float n1 = texture(noise, p * 0.02).r;
	float n2 = texture(noise, p * 0.11).r;
	float n3 = texture(noise, p * 0.47).r;
	// Petak dibaca dengan sedikit geser derau: tepi jalan, pasir, dan lantai hutan berkelok alami.
	vec4 m = texture(splat, (p + (vec2(n2, n3) - 0.5) * 0.9) / size);
	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
	col = mix(col, grass_dry, smoothstep(0.62, 0.82, n2) * 0.35);
	col *= 0.9 + 0.2 * n3;
	col = mix(col, forest_col * (0.85 + 0.3 * n2), smoothstep(0.15, 0.7, m.b) * 0.75);
	float edge = (n2 - 0.5) * 0.35 + (n3 - 0.5) * 0.2;
	float path = smoothstep(0.42, 0.56, m.r + edge);
	float rim = smoothstep(0.28, 0.42, m.r + edge) - path;
	col = mix(col, col * 0.8, clamp(rim, 0.0, 1.0));
	vec3 pc = path_col * (0.84 + 0.3 * n3) * (1.0 - 0.14 * smoothstep(0.55, 0.78, n2));
	col = mix(col, pc, path);
	float sand = smoothstep(0.4, 0.6, m.g + edge * 0.6);
	col = mix(col, sand_col * (0.9 + 0.16 * n3), sand * (1.0 - path));
	// Bintik kelopak bunga di rumput (tanpa geometri): sel kecil acak, sangat jarang.
	vec2 c = floor(p * 3.0);
	float h = fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
	vec2 f = fract(p * 3.0) - 0.5;
	float dot_ = step(0.985, h) * (1.0 - smoothstep(0.08, 0.16, length(f))) * petals;
	dot_ *= (1.0 - path) * (1.0 - sand) * (1.0 - m.b);
	vec3 pcol = mix(vec3(1.0, 0.55, 0.75), vec3(1.0, 0.9, 0.35), step(0.9925, h));
	col = mix(col, pcol, dot_);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
""",
"grass": """shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.3, 0.6, 0.2);
uniform vec3 grass_b : source_color = vec3(0.58, 0.81, 0.33);
uniform vec3 grass_dry : source_color = vec3(0.73, 0.72, 0.4);
uniform float angin = 1.0;
uniform float far = 26.0;
varying vec3 wp;
varying float h;
varying float tint;
void vertex() {
	h = UV.y;
	tint = INSTANCE_CUSTOM.r;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(o, CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(far - 8.0, far, d);
	float s = sin(TIME * (1.4 + 0.5 * angin) + o.x * 0.31 + o.z * 0.23) + 0.5 * sin(TIME * 2.9 + o.z * 0.7);
	VERTEX.x += (s + 0.5 * (angin - 1.0)) * 0.06 * h * h * angin;
	VERTEX.z += s * 0.03 * h * h * angin;
	wp = o;
}
void fragment() {
	float n1 = texture(noise, wp.xz * 0.02).r;
	float n2 = texture(noise, wp.xz * 0.11).r;
	vec3 base = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
	base = mix(base, grass_dry, smoothstep(0.62, 0.82, n2) * 0.35);
	ALBEDO = mix(base * 0.78, base * 1.18 + vec3(0.03, 0.04, 0.0), h) * (0.9 + 0.2 * tint);
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
""",
"flower": """shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.3, 0.6, 0.2);
uniform vec3 grass_b : source_color = vec3(0.58, 0.81, 0.33);
uniform float angin = 1.0;
uniform float far = 26.0;
varying vec3 wp;
varying float h;
varying float head;
varying vec3 petal;
void vertex() {
	h = UV.y;
	head = UV.x;
	petal = INSTANCE_CUSTOM.gba;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(o, CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(far - 8.0, far, d);
	float s = sin(TIME * (1.4 + 0.5 * angin) + o.x * 0.31 + o.z * 0.23);
	VERTEX.x += s * 0.05 * h * angin;
	wp = o;
}
void fragment() {
	float n1 = texture(noise, wp.xz * 0.02).r;
	vec3 base = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
	vec3 leaf = mix(base * 0.7, base * 1.2, h);
	ALBEDO = mix(leaf, petal, step(0.5, head));
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
""",
}
