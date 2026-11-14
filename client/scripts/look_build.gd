extends RefCounted
## Character Creator (v0.82.0): menggambar penampilan pahlawan utama di atas model KayKit — rambut, mata,
## hidung, mulut, warna kulit, bentuk tubuh, pakaian, celana, sarung tangan, topi, jubah, aksesori, sepatu,
## perisai, dan senjata per jenis. Semua bagian dibuat dari bentuk dasar dan ditempel ke tulang rangka
## (BoneAttachment3D), jadi ikut bergerak bersama animasi tanpa mengubah rangka. Dipanggil dari Models.dress.
##
## Data warna/bentuk kosmetik berasal dari server (Session.cosmetics, GET /v1/wardrobe); bila belum dimuat,
## bentuk diturunkan dari id (FALLBACK_SHAPE) supaya model tetap tampil.

const BodyShape = preload("res://scripts/body_shape.gd")
const DRESS_NODE := "Perlengkapan"  # sama dengan Models.DRESS_NODE: tempelan lama dibuang saat dress ulang

## Warna kulit tekstur palet KayKit (diukur dari ksatria/pemanah/... _texture.png): tengah, terang, gelap.
const BASE_SKIN := Color("f6c09c")
const SKIN_LIGHT := Color("f8ccab")
const SKIN_DARK := Color("f2a87e")

## Shader kulit (v0.82.1): hanya piksel tekstur berwarna kulit KayKit yang diganti warna kulit pilihan, dengan
## terang-gelap yang sama; rambut, mata, baju, zirah di tekstur yang sama tetap. Kode di sini (bukan berkas aset)
## supaya ikut patch skrip. Gaya toon + cahaya tepi sama dengan bahan pahlawan lain.
const SKIN_SHADER := """
shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 skin : source_color = vec4(0.965, 0.753, 0.612, 1.0);
uniform vec4 key_mid : source_color = vec4(0.965, 0.753, 0.612, 1.0);
uniform vec4 key_light : source_color = vec4(0.973, 0.800, 0.671, 1.0);
uniform vec4 key_dark : source_color = vec4(0.949, 0.659, 0.494, 1.0);
uniform float tolerance = 0.07;
uniform bool grey_swap = false;
uniform vec4 grey_to : source_color = vec4(1.0);
uniform float rim_amount = 0.35;
uniform float rim_tint_amount = 0.4;
float hit(vec3 c, vec3 key) { return 1.0 - smoothstep(tolerance * 0.5, tolerance, distance(c, key)); }
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 o = c;
	o = mix(o, skin.rgb, hit(c, key_mid.rgb));
	o = mix(o, skin.rgb * (key_light.rgb / key_mid.rgb), hit(c, key_light.rgb));
	o = mix(o, skin.rgb * (key_dark.rgb / key_mid.rgb), hit(c, key_dark.rgb));
	if (grey_swap) {
		// janggut abu-abu kepala Barbarian (v0.83.0): jadi warna kulit (pahlawan perempuan) atau warna rambut
		float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
		float lum = (c.r + c.g + c.b) / 3.0;
		if (sat < 0.1 && lum > 0.3 && lum < 0.72) {
			o = grey_to.rgb * clamp(lum / 0.55, 0.7, 1.2);
		}
	}
	ALBEDO = o * tint.rgb;
	ROUGHNESS = 0.75;
	RIM = rim_amount;
	RIM_TINT = rim_tint_amount;
}
"""
static var _skin_shader: Shader = null
const MOUTH := Color("6a2a24")

## Bentuk rambut bila katalog belum dimuat.
const FALLBACK_SHAPE := {
	"rambut_pendek": "pendek", "rambut_lurus": "lurus", "rambut_panjang": "panjang", "rambut_botak": "botak",
	"rambut_bergelombang": "gelombang", "rambut_ikal": "ikal", "rambut_kepang": "kepang", "rambut_kuncir": "kuncir",
	"rambut_jambul": "jambul", "topi_petualang": "topi", "tudung_kepala": "tudung", "mahkota": "mahkota",
	"mahkota_naga": "mahkota", "sabuk_kulit": "sabuk", "kalung_perak": "kalung", "kalung_permata": "kalung",
	"cincin_emas": "cincin", "perisai_punggung": "perisai_punggung", "ornamen_bahu": "ornamen",
	"sayap_malaikat": "sayap", "sayap_naga": "sayap_naga", "baju_petualang": "petualang",
	"jubah_petualang": "jubah_pendek", "jubah_penyihir": "jubah_panjang", "pakaian_bangsawan": "bangsawan",
}

## Senjata dengan model sendiri (menggantikan senjata bawaan KayKit di tangan kanan).
## kind: bentuk; blade/grip: warna bilah/gagang; glow: cahaya pendar (opsional).
const WEAPONS := {
	"belati": {"kind": "pedang", "len": 0.55, "wide": 0.075, "blade": Color("d8dde6"), "grip": Color("5a3a22")},
	"pedang_pendek": {"kind": "pedang", "len": 0.85, "wide": 0.1, "blade": Color("dfe4ec"), "grip": Color("6a4426")},
	"pedang_panjang": {"kind": "pedang", "len": 1.25, "wide": 0.11, "blade": Color("cfd8e6"), "grip": Color("3a2a4a")},
	"pedang_dua_tangan": {"kind": "pedang", "len": 1.6, "wide": 0.16, "blade": Color("b8c4d6"), "grip": Color("2a2a2a"), "grip_len": 0.5},
	"pedang_legenda": {"kind": "pedang", "len": 1.35, "wide": 0.13, "blade": Color("fff0b0"), "grip": Color("c8962a"), "glow": Color("ffcc33")},
	"pedang_naga_purba": {"kind": "pedang", "len": 1.5, "wide": 0.17, "blade": Color("ff8a5a"), "grip": Color("3a0e08"), "glow": Color("ff4a12")},
	"kapak_tangan": {"kind": "kapak", "len": 1.0, "blade": Color("c8ccd4"), "grip": Color("7a5232")},
	"kapak_besar": {"kind": "kapak2", "len": 1.5, "blade": Color("aab2be"), "grip": Color("5a3a22")},
	"palu_perang": {"kind": "palu", "len": 1.4, "blade": Color("8a8e98"), "grip": Color("4a3020")},
	"tombak_besi": {"kind": "tombak", "len": 2.4, "blade": Color("d0d6de"), "grip": Color("8a6238")},
	"tombak_naga": {"kind": "tombak", "len": 2.6, "blade": Color("ff7a4a"), "grip": Color("3a1a12"), "glow": Color("ff4a12")},
	"tongkat_kayu": {"kind": "tongkat", "len": 2.2, "blade": Color("7adf6a"), "grip": Color("7a5232"), "glow": Color("5adf4a")},
	"tongkat_kristal": {"kind": "tongkat", "len": 2.4, "blade": Color("8ad8ff"), "grip": Color("4a4a6a"), "glow": Color("3fb6ff"), "crystal": true},
	"busur_pendek": {"kind": "busur", "len": 1.1, "blade": Color("8a5a30"), "grip": Color("4a2a1a")},
	"busur_panjang": {"kind": "busur", "len": 1.6, "blade": Color("6a4426"), "grip": Color("c8a24a")},
}
const SHIELDS := {
	"perisai_kayu": {"face": Color("9a6a3a"), "rim": Color("5a5a62"), "r": 0.42},
	"perisai_besi": {"face": Color("aab4c2"), "rim": Color("5e6676"), "r": 0.46, "metal": true},
	"perisai_legenda": {"face": Color("e8c050"), "rim": Color("8a5a1a"), "r": 0.5, "metal": true, "glow": Color("ffcc33")},
}
const BOOTS := {
	"sepatu_biasa": {"c": Color("6a5a4a")},
	"sepatu_petualang": {"c": Color("7a5232")},
	"sepatu_kulit": {"c": Color("5a3620")},
	"sepatu_besi": {"c": Color("8a929e"), "metal": true},
	"sepatu_armor": {"c": Color("aeb8c6"), "metal": true, "tall": true},
	"sepatu_legenda": {"c": Color("e8c050"), "metal": true, "tall": true, "glow": Color("ffcc33")},
}
## Bagian senjata/perisai bawaan KayKit yang disembunyikan bila diganti.
const BUILTIN_WEAPONS := ["1H_Sword", "2H_Axe", "Spear", "2H_Crossbow", "1H_Crossbow", "Knife", "Throwable"]
const BUILTIN_SHIELD := ["Badge_Shield", "Round_Shield", "Spike_Shield", "Rectangle_Shield", "Knife_Offhand"]

## Bentuk wajah dan tubuh: pengali skala tulang.
const FACE_SCALE := {"oval": Vector3(1, 1, 1), "bulat": Vector3(1.14, 0.93, 1.08), "persegi": Vector3(1.12, 1.02, 1.12), "lancip": Vector3(0.88, 1.1, 0.94)}
## Tubuh: [lebar, otot, badan] tambahan penggeser.
const BODY_PRESET := {"sedang": [0.0, 0.0, 0.0], "ramping": [-1.5, -1.0, 0.3], "kekar": [1.0, 2.0, 0.0], "gempal": [2.5, 0.5, -0.6]}
const STEP_HEIGHT := 0.035
const STEP_WIDTH := 0.045
const STEP_MUSCLE := 0.05
const STEP_HEAD := 0.06
const STEP_TORSO := 0.05


# --- data ---

static func cosm(id: String) -> Dictionary:
	if id == "":
		return {}
	var s := _session()
	if s != null and (s.get("cosmetics") as Dictionary).has(id):
		return s.cosmetics[id]
	return {"id": id, "shape": FALLBACK_SHAPE.get(id, "")}


static func _session() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Session")
	return null


static func col(hex: Variant, fallback := Color(1, 1, 1)) -> Color:
	var h := str(hex)
	return Color(h) if h.begins_with("#") and h.length() == 7 else fallback


static func glow_of(c: Dictionary) -> Color:
	var g := str(c.get("glow", ""))
	return Color(g) if g.begins_with("#") else Color(0, 0, 0, 0)


static func shape_of(c: Dictionary) -> String:
	var sh := str(c.get("shape", ""))
	return sh if sh != "" else str(FALLBACK_SHAPE.get(str(c.get("id", "")), ""))


## Warna pakaian dari skin toko: [warna, cahaya] atau [] (pakai Outfit lama).
static func skin_tint(look: Dictionary) -> Array:
	var id := str(look.get("skin", ""))
	if id == "":
		return []
	var c := cosm(id)
	if not c.has("color"):
		return []
	return [col(c.color), glow_of(c)]


## Warna kulit pilihan (bawaan = warna kulit tekstur KayKit).
static func skin_color(look: Dictionary) -> Color:
	return col(look.get("skin_color", ""), BASE_SKIN)


## Pasang/lepas shader kulit pada mesh kepala/lengan. on = warna kulit dipilih. Bahan standar asli disimpan di
## meta supaya bisa dikembalikan (ganti pahlawan/penampilan berkali-kali tidak menumpuk bahan).
static func set_skin(mi: MeshInstance3D, on: bool, c: Color, grey_to := Color(0, 0, 0, 0)) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var cur := mi.get_surface_override_material(i)
		var key := "std_mat_%d" % i
		if not on:
			if cur is ShaderMaterial and mi.has_meta(key):
				mi.set_surface_override_material(i, mi.get_meta(key) as Material)
			continue
		if cur is StandardMaterial3D:
			var std := cur as StandardMaterial3D
			if std.albedo_texture == null:
				continue  # tanpa tekstur palet: tidak ada piksel kulit
			mi.set_meta(key, std)
			if _skin_shader == null:
				_skin_shader = Shader.new()
				_skin_shader.code = SKIN_SHADER
			var sm := ShaderMaterial.new()
			sm.shader = _skin_shader
			sm.set_shader_parameter("albedo_tex", std.albedo_texture)
			sm.set_shader_parameter("tint", std.get_meta("base_col", std.albedo_color) if std.has_meta("base_col") else std.albedo_color)
			mi.set_surface_override_material(i, sm)
			cur = sm
		if cur is ShaderMaterial:
			(cur as ShaderMaterial).set_shader_parameter("skin", c)
			(cur as ShaderMaterial).set_shader_parameter("grey_swap", grey_to.a > 0.0)
			(cur as ShaderMaterial).set_shader_parameter("grey_to", grey_to)


static func hair_color(look: Dictionary) -> Color:
	return col(look.get("hair_color", ""), Color("5a3620") if is_female(look) else Color("2a1c12"))


## Pahlawan perempuan (v0.83.0): pilihan Jenis Kelamin di Character Creator, berlaku untuk semua pahlawan.
static func is_female(look: Dictionary) -> bool:
	return str(look.get("gender", "")) == "wanita"


const LIPS := Color("c8505a")
const LASH := Color("1a1210")
const BLUSH := Color("f29a8a")


## Ciri wajah untuk Models._face (alis dan janggut mengikuti warna rambut).
static func face_dict(look: Dictionary) -> Dictionary:
	var hc := hair_color(look)
	var f := {"brow": hc}
	match str(look.get("brow", "")):
		"tipis":
			f["brow_w"] = 0.6
			f["brow_tilt"] = 0.05
		"tebal":
			f["brow_w"] = 1.7
			f["brow_tilt"] = 0.12
		"melengkung":
			f["brow_tilt"] = -0.22
		_:
			f["brow_tilt"] = 0.2
	if is_female(look):  # alis lebih tipis dan melengkung, pipi merona, tanpa jenggot
		f["brow_w"] = float(f.get("brow_w", 1.0)) * 0.6
		if str(look.get("brow", "")) in ["", "tegas"]:
			f["brow_tilt"] = -0.14
		f["blush"] = BLUSH
		return f
	match str(look.get("beard", "")):
		"kumis":
			f["mustache"] = hc
		"tipis":
			f["stubble"] = hc
		"tebal":
			f["beard"] = hc
		"kambing":
			f["goatee"] = hc
		"lengkap":
			f["mustache"] = hc
			f["beard"] = hc
		"penyihir":
			f["wizard_beard"] = hc
	return f


# --- bahan dan tempelan ---

## Bahan dipakai bersama per (warna, logam, cahaya): ganti item berulang tidak membuat bahan baru terus-menerus,
## dan bagian berwarna sama dalam satu tempelan bisa digabung jadi satu panggilan gambar (v0.82.2). Bahan ini
## tidak pernah diubah setelah dibuat. Jumlahnya terbatas (warna katalog/palet dan turunannya).
static var _mats: Dictionary = {}
## Gabungkan bagian sebahan per tempelan (dimatikan hanya oleh uji untuk mengukur penghematan).
static var merge_parts := true


static func material_count() -> int:
	return _mats.size() + _vc_mats.size()


static func _mat(c: Color, metal := false, glow := Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), metal, glow.to_html() if glow.a > 0.0 else ""]
	if _mats.has(key):
		return _mats[key]
	var m := _new_mat(c, metal, glow)
	_mats[key] = m
	return m


static func _new_mat(c: Color, metal := false, glow := Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.4 if metal else 0.85
	m.metallic = 0.35 if metal else 0.0
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.4
	if glow.a > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 0.8
	return m


static func _part(mesh: Mesh, c: Color, pos := Vector3.ZERO, metal := false, glow := Color(0, 0, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, metal, glow)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _sphere(r: float, h := -1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h if h > 0.0 else r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 16
	m.ring_segments = 6
	return m


## Tempel `part` ke tulang. Bila `rig_pos` diberikan, part dibangun dalam ruang rangka (sumbu Y ke atas,
## +Z ke depan) dengan titik asal di rig_pos; selain itu part sudah dalam ruang tulang.
static func _attach(sk: Skeleton3D, bone: String, part: Node3D, rig_pos: Variant = null) -> void:
	var bi := sk.find_bone(bone)
	if bi < 0:
		part.free()
		return
	if merge_parts:
		merge_colored(part)  # semua bagian satu tempelan jadi 1-2 mesh: lebih sedikit panggilan gambar di HP
	var ba := BoneAttachment3D.new()
	ba.name = "%s_%s_%s" % [DRESS_NODE, bone, part.name]
	ba.set_meta(DRESS_NODE, true)
	sk.add_child(ba)
	ba.bone_name = bone
	var rest := sk.get_bone_global_rest(bi)
	ba.transform = rest
	if rig_pos != null:
		part.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, rig_pos as Vector3)
	ba.add_child(part)


static func _bone_pos(sk: Skeleton3D, bone: String) -> Vector3:
	var bi := sk.find_bone(bone)
	return sk.get_bone_global_rest(bi).origin if bi >= 0 else Vector3.ZERO


# --- penggabungan mesh (v0.82.2) ---

## Gabungkan semua bentuk dasar di bawah `root` menjadi satu mesh per jenis bahan (logam/cahaya tepi/cahaya),
## warnanya disimpan sebagai warna titik. Satu tempelan (rambut, wajah, sepatu, sayap...) biasanya jadi 1-2
## panggilan gambar, bukan satu per bentuk. Node bernama (dicari kode lain) dan node berskrip tidak disentuh.
static var _vc_mats: Dictionary = {}


static func merge_colored(root: Node3D) -> void:
	var groups := {}
	_gather(root, Transform3D.IDENTITY, groups)
	for key: String in groups:
		var g: Dictionary = groups[key]
		if (g.nodes as Array).size() < 2:
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_COLOR] = g.c
		arrays[Mesh.ARRAY_INDEX] = g.i
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Gabungan"
		mi.mesh = am
		mi.material_override = _vc_mat(g.mat as StandardMaterial3D, key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = float(g.far)
		root.add_child(mi)
		for n: Node in g.nodes:
			n.get_parent().remove_child(n)
			n.free()


static func _gather(node: Node, xf: Transform3D, groups: Dictionary) -> void:
	for c in node.get_children():
		if not (c is Node3D) or not str(c.name).begins_with("@") or c.get_script() != null:
			continue
		var n3 := c as Node3D
		if not n3.visible:
			continue
		var cxf := xf * n3.transform
		if n3 is MeshInstance3D and n3.get_child_count() == 0:
			_gather_mesh(n3 as MeshInstance3D, cxf, groups)
		elif n3.get_class() == "Node3D":
			_gather(n3, cxf, groups)


static func _gather_mesh(mi: MeshInstance3D, xf: Transform3D, groups: Dictionary) -> void:
	var m := mi.material_override as StandardMaterial3D
	if mi.mesh == null or m == null or not (mi.mesh is PrimitiveMesh) or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	var glow := m.emission.to_html() + str(m.emission_energy_multiplier) if m.emission_enabled else ""
	var key := "%s|%s|%s|%s" % [m.metallic > 0.0 or m.roughness < 0.6, m.rim_enabled, glow, mi.visibility_range_end]
	if not groups.has(key):
		groups[key] = {"mat": m, "far": mi.visibility_range_end, "nodes": [], "v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	var g: Dictionary = groups[key]
	var src := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX] if src[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	var base := (g.v as PackedVector3Array).size()
	var v: PackedVector3Array = g.v
	var n: PackedVector3Array = g.n
	var c: PackedColorArray = g.c
	var ii: PackedInt32Array = g.i
	for k in verts.size():
		v.append(xf * verts[k])
		n.append((nb * norms[k]).normalized() if k < norms.size() else Vector3.UP)
		c.append(m.albedo_color)
	if idx.is_empty():
		for k in verts.size():
			ii.append(base + k)
	else:
		for k in idx.size():
			ii.append(base + idx[k])
	g.v = v
	g.n = n
	g.c = c
	g.i = ii
	(g.nodes as Array).append(mi)


## Bahan warna-titik bersama per jenis (logam, cahaya tepi, cahaya).
static func _vc_mat(src: StandardMaterial3D, key: String) -> StandardMaterial3D:
	if _vc_mats.has(key):
		return _vc_mats[key]
	var m := src.duplicate() as StandardMaterial3D
	m.albedo_color = Color(1, 1, 1)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	_vc_mats[key] = m
	return m


# --- penerapan ---

## Ukuran bagian tubuh dalam ruang rangka (dari AABB mesh KayKit).
static func boxes(list: Array) -> Dictionary:
	var out := {}
	for pair: Array in list:
		var mi := pair[0] as MeshInstance3D
		var nm := str(mi.name)
		var box := (pair[1] as Transform3D) * mi.get_aabb()
		for key: String in ["_Head", "_Head_Hooded", "_Body", "_ArmLeft", "_ArmRight", "_LegLeft", "_LegRight"]:
			if nm.ends_with(key):
				out[key.trim_prefix("_").replace("_Hooded", "")] = box
				if key == "_Head_Hooded":
					out["hooded"] = true
	return out


## Semua tempelan penampilan. head_covered = helm/topi terpasang.
static func apply(rig: Node3D, sk: Skeleton3D, list: Array, look: Dictionary, equipment: Dictionary, head_covered: bool) -> void:
	var bx := boxes(list)
	var head: AABB = bx.get("Head", AABB())
	if not look.is_empty() and head.size != Vector3.ZERO:
		if not bool(bx.get("hooded", false)):
			_hair(sk, look, head, head_covered)
		_face_extra(sk, look, head)
		var hat := cosm(str(look.get("hat", "")))
		if not hat.is_empty():
			_hat(sk, hat, head)
	if not look.is_empty():
		_clothes(sk, look, bx)
		_gloves(sk, look, bx)
		_cape(sk, look, bx)
		for a: Variant in look.get("accessories", []):
			_accessory(sk, cosm(str(a)), bx, head)
	_boots(sk, str(equipment.get("boots", "")), bx)
	var w := str(equipment.get("weapon", ""))
	if WEAPONS.has(w):
		_attach(sk, "handslot.r", weapon_mesh(WEAPONS[w]))
	var sh := str(equipment.get("offhand", ""))
	if SHIELDS.has(sh):
		_attach(sk, "handslot.l", shield_mesh(SHIELDS[sh]))
	apply_body(rig, sk, look)


## Rambut di atas kepala (warna rambut pilihan). Bila kepala tertutup helm/topi, hanya bagian yang menjuntai
## di belakang yang digambar.
static func _hair(sk: Skeleton3D, look: Dictionary, head: AABB, covered: bool) -> void:
	var c := cosm(str(look.get("hair", "")))
	var shape := shape_of(c)
	if shape == "" and is_female(look):
		shape = "panjang"  # perempuan tanpa pilihan rambut: rambut panjang bawaan
	if shape == "":
		return
	var hc := hair_color(look)
	if shape == "botak":
		hc = skin_color(look)
	var w := head.size.x
	var d := head.size.z
	var h := head.size.y
	var r := maxf(w, d) * 0.56
	var root := Node3D.new()
	root.name = "rambut"
	var origin := Vector3(head.get_center().x, head.position.y + h * 0.56, head.get_center().z - d * 0.03)
	var cap_y_scale := 0.95
	if not covered:
		if shape == "ikal":
			for i in 22:  # ikal-ikal kecil menutup bagian atas kepala (titik Fibonacci di setengah bola)
				var t := (float(i) + 0.5) / 22.0
				var phi := acos(t)
				var th := float(i) * 2.39996
				var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)) * r * 0.95
				if p.z > r * 0.55 and p.y < r * 0.5:
					continue  # jangan menutupi wajah
				root.add_child(_part(_sphere(r * 0.3), hc, p))
			cap_y_scale = 0.85
	# Tempurung rambut = elips mengikuti kotak kepala, sedikit ke atas dan ke belakang: bagian depan-bawahnya masuk
	# ke dalam kepala sehingga wajah tetap terlihat dan tidak ada tepi mangkuk yang kaku. Di bawah helm/topi dibuat
	# sedikit lebih kecil (di dalam helm) supaya hanya rambut di bawah pinggir helm yang terlihat, tanpa menembus.
	var shrink := 0.86 if covered else 1.0
	var cap := _part(_sphere(0.5, 1.0), hc, Vector3(0, -h * 0.03 if covered else h * 0.04, -d * 0.05), shape == "botak")
	cap.scale = Vector3(w * 1.08, h * cap_y_scale / 0.95, d * 1.1) * shrink
	root.add_child(cap)
	if not covered and shape != "botak":
		# jambul rambut bawaan model KayKit di atas dahi ikut tertutup warna rambut pilihan
		var crown := _part(_sphere(0.5, 1.0), hc, Vector3(0, h * 0.3, d * 0.2))
		crown.scale = Vector3(w * 0.9, h * 0.42, d * 0.8)
		root.add_child(crown)
		for sx: float in [-1.0, 1.0]:  # poni: dua helai miring di dahi
			var bang := _part(_sphere(0.5, 1.0), hc, Vector3(sx * w * 0.17, -h * 0.03, d * 0.4))
			bang.scale = Vector3(w * 0.42, h * 0.2, d * 0.18)
			bang.rotation.z = sx * 0.35
			root.add_child(bang)
	match shape:
		"lurus", "panjang":
			var length := h * (0.75 if shape == "lurus" else 1.2)
			var back := _part(_sphere(0.5, 1.0), hc, Vector3(0, -length / 2.0 + h * 0.15, -d * 0.4))
			back.scale = Vector3(w * 0.96, length, d * 0.32)  # helai belakang membulat mengikuti kepala
			root.add_child(back)
			if not covered:
				for sx: float in [-1.0, 1.0]:
					root.add_child(_part(_box(Vector3(w * 0.12, h * 0.55, d * 0.6)), hc, Vector3(sx * w * 0.47, -h * 0.2, -d * 0.1)))
		"gelombang":
			for sx: float in [-1.0, 1.0]:
				for k in 3:
					root.add_child(_part(_sphere(r * 0.3), hc, Vector3(sx * w * (0.48 - k * 0.03), -k * h * 0.17, -d * 0.08 - k * d * 0.06)))
			root.add_child(_part(_box(Vector3(w * 0.95, h * 0.6, d * 0.2)), hc, Vector3(0, -h * 0.2, -d * 0.42)))
		"kepang":
			for k in 7:
				var rr := r * (0.28 - k * 0.022)
				root.add_child(_part(_sphere(rr), hc, Vector3(0, -h * 0.05 - k * rr * 1.5, -d * 0.52 - k * d * 0.015)))
			root.add_child(_part(_torus(r * 0.08, r * 0.14), Color("c83a2a"), Vector3(0, -h * 0.05 - 7 * r * 0.2 * 1.3, -d * 0.6)))
		"kuncir":
			if not covered:
				root.add_child(_part(_sphere(r * 0.32), hc, Vector3(0, r * 0.75, -d * 0.32)))
			var tail := _part(_cyl(r * 0.16, r * 0.05, h * 0.75), hc, Vector3(0, r * 0.2, -d * 0.62))
			tail.rotation.x = 0.5
			root.add_child(tail)
		"jambul":
			if not covered:
				for k in 5:
					var spike := _part(_cyl(0.0, r * 0.22, r * 0.9, 6), hc, Vector3((k - 2) * w * 0.14, r * 0.85, d * 0.05 - absf(k - 2) * d * 0.06))
					spike.rotation.x = -0.35
					spike.rotation.z = (2 - k) * 0.18
					root.add_child(spike)
	if root.get_child_count() == 0:
		root.free()
		return
	_attach(sk, "head", root, origin)


## Mata, hidung, dan mulut di depan kepala.
static func _face_extra(sk: Skeleton3D, look: Dictionary, head: AABB) -> void:
	var w := head.size.x
	var h := head.size.y
	var root := Node3D.new()
	root.name = "wajah2"
	var eye_y := head.position.y + h * 0.42
	var front := head.end.z
	var eyes := str(look.get("eyes", ""))
	if eyes != "" or str(look.get("eye_color", "")) != "":
		var ec := col(look.get("eye_color", ""), Color("3a2414"))
		var sz := {"bulat": Vector2(1.0, 1.0), "sipit": Vector2(1.1, 0.45), "besar": Vector2(1.3, 1.3), "tajam": Vector2(1.15, 0.6)}.get(eyes, Vector2.ONE) as Vector2
		var lid := skin_color(look)
		for sx: float in [-1.0, 1.0]:
			# Penutup mata lukisan tekstur KayKit (warna kulit), supaya bentuk mata pilihan tidak tumpang tindih.
			var cover := _part(_sphere(w * 0.1), lid, Vector3(sx * w * 0.17, h * 0.03, -w * 0.03))
			cover.scale = Vector3(1.25, 1.15, 0.22)
			root.add_child(cover)
			var eye := Node3D.new()
			eye.position = Vector3(sx * w * 0.17, h * 0.02, -w * 0.005)
			if eyes == "tajam":
				eye.rotation.z = sx * 0.25
			var white := _part(_sphere(w * 0.065), Color("f4f2ee"))
			white.scale = Vector3(sz.x, sz.y, 0.35)
			eye.add_child(white)
			var iris := _part(_sphere(w * 0.042), ec, Vector3(0, 0, w * 0.018))
			iris.scale = Vector3(sz.x * 0.9, minf(sz.y, 1.0) * 0.95, 0.3)
			eye.add_child(iris)
			var pupil := _part(_sphere(w * 0.02), Color("0e0a08"), Vector3(0, 0, w * 0.03))
			pupil.scale = Vector3(1, minf(sz.y, 1.0), 0.3)
			eye.add_child(pupil)
			root.add_child(eye)
	var female := is_female(look)
	if female:  # bulu mata: tiga helai miring di atas tiap mata
		for sx: float in [-1.0, 1.0]:
			for k in 3:
				var lash := _part(_box(Vector3(w * 0.045, h * 0.012, w * 0.02)), LASH, Vector3(sx * w * (0.13 + k * 0.045), h * (0.075 + k * 0.012), -w * 0.0))
				lash.rotation.z = sx * (0.25 + k * 0.25)
				root.add_child(lash)
	var mouth_c := LIPS if female else MOUTH
	var skin := skin_color(look) * Color(0.9, 0.85, 0.82)
	match str(look.get("nose", "")):
		"kecil":
			root.add_child(_part(_sphere(w * 0.04), skin, Vector3(0, -h * 0.1, w * 0.0)))
		"mancung":
			var n := _part(_cyl(w * 0.015, w * 0.05, w * 0.13, 8), skin, Vector3(0, -h * 0.1, w * 0.02))
			n.rotation.x = 1.2
			root.add_child(n)
		"lebar":
			var n2 := _part(_sphere(w * 0.05), skin, Vector3(0, -h * 0.11, w * 0.0))
			n2.scale = Vector3(1.6, 0.8, 0.8)
			root.add_child(n2)
	match str(look.get("mouth", "")):
		"senyum":
			root.add_child(_part(_box(Vector3(w * 0.12, h * 0.025, w * 0.02)), mouth_c, Vector3(0, -h * 0.22, -w * 0.005)))
			for sx: float in [-1.0, 1.0]:
				var corner := _part(_box(Vector3(w * 0.06, h * 0.022, w * 0.02)), mouth_c, Vector3(sx * w * 0.08, -h * 0.205, -w * 0.01))
				corner.rotation.z = sx * 0.5
				root.add_child(corner)
		"datar":
			root.add_child(_part(_box(Vector3(w * 0.16, h * 0.025, w * 0.02)), mouth_c, Vector3(0, -h * 0.22, -w * 0.005)))
		"tipis":
			root.add_child(_part(_box(Vector3(w * 0.13, h * 0.012, w * 0.02)), mouth_c, Vector3(0, -h * 0.22, -w * 0.005)))
		"":
			if female:  # bibir kecil berwarna
				var lips := _part(_sphere(w * 0.05), LIPS, Vector3(0, -h * 0.21, -w * 0.01))
				lips.scale = Vector3(1.5, 0.55, 0.5)
				root.add_child(lips)
		"lebar":
			var m := _part(_box(Vector3(w * 0.24, h * 0.045, w * 0.02)), mouth_c, Vector3(0, -h * 0.22, -w * 0.005))
			root.add_child(m)
			root.add_child(_part(_box(Vector3(w * 0.2, h * 0.015, w * 0.022)), Color("f4f2ee"), Vector3(0, -h * 0.207, 0)))
	if root.get_child_count() == 0:
		root.free()
		return
	_attach(sk, "head", root, Vector3(head.get_center().x, eye_y, front))


## Topi/tudung/mahkota (kosmetik; menggantikan tampilan helm).
static func _hat(sk: Skeleton3D, c: Dictionary, head: AABB) -> void:
	var w := maxf(head.size.x, head.size.z)
	var h := head.size.y
	var color := col(c.get("color", ""), Color("7a5232"))
	var glow := glow_of(c)
	var root := Node3D.new()
	root.name = "topi"
	match shape_of(c):
		"topi":
			root.add_child(_part(_cyl(w * 0.8, w * 0.82, h * 0.05, 20), color))
			root.add_child(_part(_cyl(w * 0.4, w * 0.47, h * 0.42, 16), color, Vector3(0, h * 0.21, 0)))
			root.add_child(_part(_cyl(w * 0.475, w * 0.475, h * 0.08, 16), Color("3a2414"), Vector3(0, h * 0.05, 0)))
			var feather := _part(_cyl(w * 0.01, w * 0.06, h * 0.55, 6), Color("e83a2a"), Vector3(w * 0.38, h * 0.3, -w * 0.1))
			feather.rotation = Vector3(-0.5, 0, -0.5)
			root.add_child(feather)
		"tudung":
			var hood := _part(_sphere(w * 0.6, w * 0.6), color, Vector3(0, -h * 0.05, -w * 0.04))
			(hood.mesh as SphereMesh).is_hemisphere = true
			hood.scale = Vector3(1.0, 1.35, 1.08)
			root.add_child(hood)
			root.add_child(_part(_box(Vector3(w * 1.0, h * 0.9, w * 0.1)), color * Color(0.85, 0.85, 0.85), Vector3(0, -h * 0.45, -w * 0.5)))
		"mahkota":
			root.add_child(_part(_cyl(w * 0.46, w * 0.44, h * 0.16, 20), color, Vector3(0, h * 0.06, 0), false, glow))
			for k in 8:
				var a := TAU * float(k) / 8.0
				var spike := _part(_cyl(0.0, w * 0.07, h * 0.24, 6), color, Vector3(sin(a) * w * 0.44, h * 0.24, cos(a) * w * 0.44), false, glow)
				root.add_child(spike)
				if k % 2 == 0:
					root.add_child(_part(_sphere(w * 0.045), Color("e83a5a") if glow.a == 0.0 else Color("ffef8a"), Vector3(sin(a) * w * 0.47, h * 0.08, cos(a) * w * 0.47), false, glow))
	if root.get_child_count() == 0:
		root.free()
		return
	_attach(sk, "head", root, Vector3(head.get_center().x, head.position.y + h * 0.62, head.get_center().z))


## Tambahan bentuk pakaian (warna badan/kaki sudah diwarnai di Models.dress).
static func _clothes(sk: Skeleton3D, look: Dictionary, bx: Dictionary) -> void:
	var c := cosm(str(look.get("clothes", "")))
	var body: AABB = bx.get("Body", AABB())
	if c.is_empty() or body.size == Vector3.ZERO:
		return
	var color := col(c.get("color", ""), Color(1, 1, 1))
	var hips := _bone_pos(sk, "hips")
	var foot := _bone_pos(sk, "foot.l")
	var bw := body.size.x
	var bd := body.size.z
	var cx := body.get_center().x
	var cz := body.get_center().z
	match shape_of(c):
		"petualang":
			_belt(sk, Color("5a3620"), body, hips.y)
			var pouch := Node3D.new()
			pouch.name = "kantong"
			pouch.add_child(_part(_box(Vector3(bw * 0.2, bw * 0.22, bd * 0.2)), Color("7a5232")))
			_attach(sk, "hips", pouch, Vector3(cx + bw * 0.42, hips.y - bw * 0.08, cz + bd * 0.2))
		"jubah_pendek":
			var mantle := Node3D.new()
			mantle.name = "mantel"
			mantle.add_child(_part(_cyl(bw * 0.3, bw * 0.66, body.size.y * 0.45, 16), color))
			_attach(sk, "chest", mantle, Vector3(cx, body.end.y - body.size.y * 0.2, cz))
		"jubah_panjang":
			var robe := Node3D.new()
			robe.name = "jubah_panjang"
			var top := hips.y + body.size.y * 0.15
			var robe_len := maxf(0.2, top - foot.y - 0.05)
			robe.add_child(_part(_cyl(bw * 0.52, bw * 0.78, robe_len, 16), color))
			robe.add_child(_part(_torus(bw * 0.7, bw * 0.8), Color("e8c050"), Vector3(0, -robe_len / 2.0 + 0.04, 0), true))
			_attach(sk, "hips", robe, Vector3(cx, top - robe_len / 2.0, cz))
		"bangsawan":
			_belt(sk, Color("e8c050"), body, hips.y, true)
			var collar := Node3D.new()
			collar.name = "kerah"
			collar.add_child(_part(_torus(bw * 0.28, bw * 0.4), Color("e8c050"), Vector3.ZERO, true))
			_attach(sk, "chest", collar, Vector3(cx, body.end.y - body.size.y * 0.05, cz))


static func _belt(sk: Skeleton3D, c: Color, body: AABB, y: float, metal := false) -> void:
	var belt := Node3D.new()
	belt.name = "sabuk"
	var t := _part(_torus(body.size.x * 0.5, body.size.x * 0.58), c, Vector3.ZERO, metal)
	t.scale = Vector3(1, 1, body.size.z / maxf(0.01, body.size.x) * 1.05)
	belt.add_child(t)
	belt.add_child(_part(_box(Vector3(body.size.x * 0.16, body.size.x * 0.12, body.size.x * 0.05)), Color("e8c050"), Vector3(0, 0, body.size.z * 0.55), true))
	_attach(sk, "hips", belt, Vector3(body.get_center().x, y, body.get_center().z))


static func _gloves(sk: Skeleton3D, look: Dictionary, bx: Dictionary) -> void:
	var c := cosm(str(look.get("gloves", "")))
	if c.is_empty():
		return
	var arm: AABB = bx.get("ArmRight", AABB())
	var r := maxf(0.08, minf(arm.size.x, arm.size.z) * 0.42) if arm.size != Vector3.ZERO else 0.12
	var color := col(c.get("color", ""), Color("7a4a2a"))
	for side: String in ["l", "r"]:
		var g := Node3D.new()
		g.name = "sarung_" + side
		g.add_child(_part(_sphere(r), color, Vector3.ZERO, color.v > 0.6, glow_of(c)))
		g.add_child(_part(_cyl(r * 0.95, r * 1.1, r * 1.2), color * Color(0.85, 0.85, 0.85), Vector3(0, r * 0.9, 0)))
		_attach(sk, "hand." + side, g, _bone_pos(sk, "hand." + side))


static func _cape(sk: Skeleton3D, look: Dictionary, bx: Dictionary) -> void:
	var c := cosm(str(look.get("cape", "")))
	var body: AABB = bx.get("Body", AABB())
	if c.is_empty() or body.size == Vector3.ZERO:
		return
	var knee := _bone_pos(sk, "lowerleg.l")
	var top := body.end.y - body.size.y * 0.05
	var length := maxf(0.3, top - knee.y)
	var cape := Node3D.new()
	cape.name = "jubah"
	var cloth := _part(_box(Vector3(body.size.x * 1.0, length, 0.04)), col(c.get("color", ""), Color("b8322a")), Vector3(0, -length / 2.0, 0), false, glow_of(c))
	cloth.rotation.x = -0.1  # ujung bawah menjauh dari punggung
	cape.add_child(cloth)
	cape.add_child(_part(_cyl(body.size.x * 0.06, body.size.x * 0.06, body.size.x * 1.05, 8), Color("e8c050"), Vector3(0, 0, 0.02), true))
	(cape.get_child(1) as Node3D).rotation.z = PI / 2.0
	_attach(sk, "chest", cape, Vector3(body.get_center().x, top, body.position.z - 0.05))


static func _accessory(sk: Skeleton3D, c: Dictionary, bx: Dictionary, head: AABB) -> void:
	var body: AABB = bx.get("Body", AABB())
	if c.is_empty() or body.size == Vector3.ZERO:
		return
	var color := col(c.get("color", ""), Color("d8dce4"))
	var glow := glow_of(c)
	var bw := body.size.x
	var cx := body.get_center().x
	var cz := body.get_center().z
	var neck := Vector3(cx, body.end.y - body.size.y * 0.04, cz)
	match shape_of(c):
		"kalung":
			var n := Node3D.new()
			n.name = "kalung"
			var ring := _part(_torus(bw * 0.3, bw * 0.33), color, Vector3.ZERO, true)
			ring.rotation.x = 0.35
			n.add_child(ring)
			n.add_child(_part(_sphere(bw * 0.08), color, Vector3(0, -bw * 0.2, body.size.z * 0.6), true, glow))  # liontin di depan dada
			var chain := _part(_cyl(bw * 0.012, bw * 0.012, bw * 0.2, 6), color, Vector3(0, -bw * 0.1, body.size.z * 0.57), true)
			n.add_child(chain)
			_attach(sk, "chest", n, neck)
		"cincin":
			var ri := Node3D.new()
			ri.name = "cincin"
			ri.add_child(_part(_torus(0.035, 0.055), color, Vector3.ZERO, true, glow))
			_attach(sk, "hand.r", ri, _bone_pos(sk, "hand.r") + Vector3(0, -0.06, 0))
		"sabuk":
			_belt(sk, color, body, _bone_pos(sk, "hips").y)
		"perisai_punggung":
			var ps := Node3D.new()
			ps.name = "perisai_punggung"
			var disc := _part(_cyl(bw * 0.42, bw * 0.42, 0.05, 20), color)
			disc.rotation.x = PI / 2.0
			ps.add_child(disc)
			var boss := _part(_sphere(bw * 0.08), Color("c8ccd4"), Vector3(0, 0, -0.04), true)
			ps.add_child(boss)
			_attach(sk, "chest", ps, Vector3(cx, body.get_center().y + body.size.y * 0.1, body.position.z - 0.06))
		"ornamen":
			for side: String in ["l", "r"]:
				var o := Node3D.new()
				o.name = "ornamen_" + side
				o.add_child(_part(_sphere(bw * 0.13, bw * 0.16), color, Vector3.ZERO, true, glow))
				o.add_child(_part(_cyl(0.0, bw * 0.05, bw * 0.18, 6), color, Vector3(0, bw * 0.1, 0), true, glow))
				_attach(sk, "upperarm." + side, o, _bone_pos(sk, "upperarm." + side) + Vector3(0, bw * 0.05, 0))
		"sayap", "sayap_naga":
			var wings := Node3D.new()
			wings.name = "sayap"
			var dragon := shape_of(c) == "sayap_naga"
			for sx: float in [-1.0, 1.0]:
				var wing := Node3D.new()
				wing.rotation.y = sx * 0.45  # sayap sedikit ke belakang
				for k in 4:  # bulu/selaput mengipas dari 15 derajat sampai 70 derajat ke atas
					var ang := deg_to_rad(15.0 + k * 18.0)
					var length := bw * (1.3 - k * 0.15)
					var dir := Vector3(sx * cos(ang), sin(ang), 0)
					var shade := color if not dragon or k % 2 == 0 else color * Color(0.7, 0.7, 0.7)
					var f := _part(_sphere(0.5), shade, dir * length * 0.5, false, glow)
					f.scale = Vector3(length, bw * (0.32 if not dragon else 0.45), 0.05)
					f.rotation.z = sx * ang
					wing.add_child(f)
				if dragon:
					var bone := _part(_cyl(bw * 0.03, bw * 0.03, bw * 1.3, 6), Color("2a0a06"), Vector3(sx * bw * 0.35, bw * 0.45, 0.01))
					bone.rotation.z = sx * -0.6
					wing.add_child(bone)
				wings.add_child(wing)
			_attach(sk, "chest", wings, Vector3(cx, body.end.y - body.size.y * 0.1, body.position.z - 0.13))  # di belakang jubah


static func _boots(sk: Skeleton3D, id: String, bx: Dictionary) -> void:
	if not BOOTS.has(id):
		return
	var look: Dictionary = BOOTS[id]
	var leg: AABB = bx.get("LegLeft", AABB())
	var lw := maxf(0.12, leg.size.x * 0.9) if leg.size != Vector3.ZERO else 0.22
	for side: String in ["l", "r"]:
		var foot := _bone_pos(sk, "foot." + side)
		var knee := _bone_pos(sk, "lowerleg." + side)
		var tall := (knee.y - foot.y) * (0.75 if look.get("tall", false) else 0.4)
		var b := Node3D.new()
		b.name = "sepatu_" + side
		var shaft := _part(_cyl(lw * 0.58, lw * 0.6, tall, 12), look.c, Vector3(0, tall / 2.0 - lw * 0.15, 0), bool(look.get("metal", false)), look.get("glow", Color(0, 0, 0, 0)))
		b.add_child(shaft)
		b.add_child(_part(_box(Vector3(lw * 1.1, lw * 0.4, lw * 1.7)), look.c * Color(0.85, 0.85, 0.85), Vector3(0, -lw * 0.2, lw * 0.35), bool(look.get("metal", false))))
		_attach(sk, "foot." + side, b, foot)


## Model senjata dalam ruang tulang handslot.r (sumbu Y = arah genggaman, seperti tongkat Penyihir).
static func weapon_mesh(wl: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "senjata"
	var blade: Color = wl.blade
	var grip: Color = wl.grip
	var glow: Color = wl.get("glow", Color(0, 0, 0, 0))
	var length := float(wl.get("len", 1.0))
	match str(wl.kind):
		"pedang":
			var gl := float(wl.get("grip_len", 0.28))
			var wide := float(wl.get("wide", 0.1))
			root.add_child(_part(_cyl(0.035, 0.04, gl, 8), grip, Vector3(0, gl * 0.1, 0)))
			root.add_child(_part(_sphere(0.055), Color("c8a24a"), Vector3(0, -gl * 0.42, 0), true))
			root.add_child(_part(_box(Vector3(wide * 2.8, 0.05, 0.08)), Color("c8a24a"), Vector3(0, gl * 0.62, 0), true))
			root.add_child(_part(_box(Vector3(wide, length, 0.025)), blade, Vector3(0, gl * 0.62 + length / 2.0, 0), true, glow))
			var tip := _part(_cyl(0.0, wide * 0.7, wide * 1.2, 4), blade, Vector3(0, gl * 0.62 + length + wide * 0.55, 0), true, glow)
			tip.scale = Vector3(1, 1, 0.25)
			root.add_child(tip)
		"kapak", "kapak2":
			root.add_child(_part(_cyl(0.04, 0.05, length, 8), grip, Vector3(0, length * 0.35, 0)))
			var top := length * 0.78
			for sx: float in ([1.0] if wl.kind == "kapak" else [1.0, -1.0]):
				var head := _part(_box(Vector3(0.42, 0.34, 0.05)), blade, Vector3(sx * 0.22, top, 0), true, glow)
				root.add_child(head)
				var edge := _part(_cyl(0.17, 0.17, 0.05, 12), blade, Vector3(sx * 0.36, top, 0), true, glow)
				edge.rotation.x = PI / 2.0
				edge.scale = Vector3(0.5, 1, 1.1)
				root.add_child(edge)
		"palu":
			root.add_child(_part(_cyl(0.045, 0.055, length, 8), grip, Vector3(0, length * 0.35, 0)))
			root.add_child(_part(_box(Vector3(0.55, 0.32, 0.32)), blade, Vector3(0, length * 0.82, 0), true, glow))
			root.add_child(_part(_box(Vector3(0.6, 0.06, 0.36)), Color("c8a24a"), Vector3(0, length * 0.82, 0), true))
		"tombak":
			root.add_child(_part(_cyl(0.035, 0.04, length, 8), grip, Vector3(0, length * 0.32, 0)))
			var tip_y := length * 0.82 + 0.18
			root.add_child(_part(_cyl(0.0, 0.09, 0.4, 6), blade, Vector3(0, tip_y, 0), true, glow))
			root.add_child(_part(_torus(0.04, 0.07), Color("c8a24a"), Vector3(0, tip_y - 0.22, 0), true))
			if glow.a > 0.0:
				for sx: float in [-1.0, 1.0]:
					var fin := _part(_box(Vector3(0.18, 0.06, 0.02)), blade, Vector3(sx * 0.1, tip_y - 0.16, 0), true, glow)
					fin.rotation.z = sx * 0.6
					root.add_child(fin)
		"tongkat":
			root.add_child(_part(_cyl(0.04, 0.055, length, 8), grip, Vector3(0, length * 0.3, 0)))
			var orb_y := length * 0.82
			if bool(wl.get("crystal", false)):
				var cr := _part(_cyl(0.0, 0.13, 0.26, 6), blade, Vector3(0, orb_y + 0.13, 0), false, glow)
				root.add_child(cr)
				var cr2 := _part(_cyl(0.13, 0.0, 0.18, 6), blade, Vector3(0, orb_y - 0.09, 0), false, glow)
				root.add_child(cr2)
			else:
				root.add_child(_part(_sphere(0.14), blade, Vector3(0, orb_y, 0), false, glow))
			root.add_child(_part(_torus(0.08, 0.13), Color("c8a24a"), Vector3(0, orb_y - 0.2, 0), true))
		"busur":
			var segs := 7
			for k in segs:
				var t := (float(k) / float(segs - 1)) * 2.0 - 1.0  # -1..1 sepanjang busur
				var seg := _part(_box(Vector3(0.05, length / float(segs) * 1.15, 0.05)), blade, Vector3(-0.22 * (1.0 - t * t), t * length / 2.0, 0))
				seg.rotation.z = t * 0.6
				root.add_child(seg)
			root.add_child(_part(_box(Vector3(0.012, length * 0.98, 0.012)), Color("eeeae0"), Vector3(0.0, 0, 0)))
			root.add_child(_part(_cyl(0.05, 0.05, 0.2, 8), grip, Vector3(-0.22, 0, 0)))
	return root


## Perisai di tangan kiri (ruang tulang handslot.l).
static func shield_mesh(sl: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "perisai"
	var r := float(sl.r)
	var face := _part(_cyl(r, r, 0.06, 20), sl.face, Vector3.ZERO, bool(sl.get("metal", false)), sl.get("glow", Color(0, 0, 0, 0)))
	face.rotation.x = PI / 2.0  # muka perisai tegak (sumbu Z tulang)
	root.add_child(face)
	var rim := _part(_torus(r * 0.92, r * 1.02), sl.rim, Vector3.ZERO, true)
	rim.rotation.x = PI / 2.0
	root.add_child(rim)
	root.add_child(_part(_sphere(r * 0.18), Color("c8a24a"), Vector3(0, 0, 0.05), true))
	root.position = Vector3(0, 0.1, 0.06)
	return root


## Bentuk tubuh: tinggi = skala model, lebar/otot/kepala/badan = skala tulang (body_shape.gd).
static func apply_body(rig: Node3D, sk: Skeleton3D, look: Dictionary) -> void:
	for old in sk.get_children():
		if old.name == BodyShape.NODE_NAME:
			sk.remove_child(old)
			old.free()
	if not rig.has_meta("base_scale"):
		rig.set_meta("base_scale", rig.scale)
	var base: Vector3 = rig.get_meta("base_scale")
	if look.is_empty():
		rig.scale = base
		return
	var preset: Array = BODY_PRESET.get(str(look.get("body", "")), [0.0, 0.0, 0.0])
	var height := float(look.get("height", 0))
	var width := float(look.get("width", 0)) + float(preset[0])
	var muscle := float(look.get("muscle", 0)) + float(preset[1])
	var torso := float(look.get("torso", 0)) + float(preset[2])
	var head := float(look.get("head", 0))
	var female := is_female(look)
	if female:  # tubuh perempuan: sedikit lebih pendek, bahu lebih sempit, lengan lebih ramping
		height -= 0.8
		width -= 0.5
	rig.scale = base * (1.0 + STEP_HEIGHT * height)
	var kw := 1.0 + STEP_WIDTH * width
	var km := 1.0 + STEP_MUSCLE * muscle
	var kt := 1.0 + STEP_TORSO * torso
	var fs: Vector3 = FACE_SCALE.get(str(look.get("face", "")), Vector3.ONE)
	var kh := 1.0 + STEP_HEAD * head
	var kc := km * (0.88 if female else 1.0)  # bahu (dada) lebih sempit
	var ka := km * (0.88 if female else 1.0)  # lengan atas lebih ramping
	if female:
		kh *= 1.04
	var scales := {}
	if kw != 1.0:
		scales["hips"] = Vector3(kw, 1, kw)
	if km != 1.0 or kt != 1.0 or female:
		scales["chest"] = Vector3(kc, 1, kc)
		scales["spine"] = Vector3(1, kt, 1)
		for side: String in ["l", "r"]:
			scales["upperarm." + side] = Vector3(ka, 1, ka)
			scales["upperleg." + side] = Vector3(km, 1, km)
	# Kepala mewarisi skala tulang induk (hips, spine, chest): dibalik supaya ukurannya hanya dari pilihan kepala.
	var inherit := Vector3(kw * kc, kt, kw * kc)
	scales["head"] = Vector3(kh * fs.x / inherit.x, kh * fs.y / inherit.y, kh * fs.z / inherit.z)
	if scales["head"] == Vector3.ONE:
		scales.erase("head")
	if scales.is_empty():
		return
	var mod := BodyShape.new()
	mod.name = BodyShape.NODE_NAME
	mod.set_scales(scales)
	sk.add_child(mod)
	sk.move_child(mod, 0)  # sebelum gerakan pahlawan (hero_actions.gd) yang dibuat belakangan
