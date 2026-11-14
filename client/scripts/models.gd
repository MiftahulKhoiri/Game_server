extends RefCounted
## Model 3D karakter, NPC, dan musuh.
##
## Bila ada assets/models/<id>.glb, itu yang dipakai (id = id NPC/musuh/ksatria). Bila tidak,
## model dirakit dari bentuk dasar (placeholder) sehingga game tetap jalan sampai model
## asli datang. Arah depan semua model = +Z, tinggi kira-kira 1 petak.

const Rig = preload("res://scripts/model_rig.gd")
const WB = preload("res://scripts/world_build.gd")

const MODEL_DIR := "res://assets/models/"

## Tinggi akhir (satuan petak) untuk model GLB buatan AI/unduhan selain ksatria. Ukuran asli
## GLB tidak dipercaya: model diukur lalu diskalakan ke tinggi ini, kaki di tanah, di tengah.
const HEIGHTS := {"golem_lava": 1.4, "golem_kerikil": 1.15, "ogre_batu": 1.3, "raja_goblin": 1.65, "goblin": 1.05, "goblin_penjaga": 1.15, "nenek_penjual": 0.85, "petani": 0.95, "warga_ibu": 0.88, "warga_ibu2": 0.86, "warga_bapak": 0.98, "warga_bapak2": 0.96, "anak_desa": 0.62, "babi_hutan": 0.75, "anak_ayam": 0.5,
	"serigala_hutan": 0.8,
	"aldragor": 3.0, "kelelawar_hutan": 0.7, "iblis_biru": 1.65}
const DEFAULT_HEIGHT := 1.0
## Model yang memanjang dan rendah (ular, tikus berekor) diukur dari panjangnya, bukan tingginya (satuan petak),
## supaya ular yang tipis tidak membesar belasan kali lipat. v0.77.0 (roadmap no. 67-68, OpenGameArt CC0).
const LENGTHS := {"tikus_sawah": 1.1, "ular_sawah": 1.3, "belalang_raksasa": 1.15}  # belalang: v0.80.0 (no. 69)

## Pahlawan yang bisa dipilih pemain (semua dari KayKit, berangka + animasi sendiri). Urutan = urutan di layar profil.
const HEROES := ["ksatria", "pendekar_kapak", "pemanah", "pendekar_tombak", "penyihir"]
## Pahlawan/model yang memakai berkas GLB lain. Penyihir punya model sendiri sejak v0.80.0 (roadmap no. 158):
## KayKit Rogue berkerudung (CC0, rangka sama dengan pahlawan lain) berjubah ungu, dulu meminjam Mage Nenek Penjual.
const HERO_GLB := {"iblis_biru": "raja_goblin"}
## (iblis_biru: model Iblis Biru untuk layar judul; id musuh raja_goblin kini Panglima Orc Batu, lihat VARIANTS.)


static func is_hero(id: String) -> bool:
	return HEROES.has(id)


## Skala akhir model terhadap petak (disetel supaya tinggi mendekati 1 petak).
const SCALES := {
	"ksatria": 0.42, "pendekar_kapak": 0.44, "pemanah": 0.42, "pendekar_tombak": 0.42, "penyihir": 0.42, "nenek_penjual": 0.66, "petani": 0.74,
	"goblin": 0.58, "goblin_penjaga": 0.68, "raja_goblin": 0.95, "ogre_batu": 1.1,
	"golem_kerikil": 1.0, "golem_lava": 1.1, 
	"tikus_sawah": 0.8, "babi_hutan": 0.95, "serigala_hutan": 0.95,
	"ular_sawah": 1.0, "belalang_raksasa": 0.95,
}


## Warna Naga Lava (bos Gunung Berapi): merah lava, sayap hangus, perut jingga menyala.
const NAGA_LAVA := {"Main": Color("9a2412"), "Wings": Color("3a0e08"), "Belly": Color("ff9a2a"), "Claws": Color("f2ead6"), "Eyes": Color("fff060")}

## Musuh yang memakai model musuh lain dengan ukuran (kali lipat) dan warna (pengali) berbeda,
## supaya satu model bisa jadi goblin kecil, orc besar, atau serigala alfa tanpa berkas baru.
const VARIANTS := {
	"goblin_pemburu": {"base": "goblin", "size": 1.2, "tint": Color("9fd8d0")},
	# Penyerbu desa saat Serbuan Goblin (roadmap no. 190): goblin kemerahan dan orc besar.
	"goblin_penyerbu": {"base": "goblin", "size": 1.1, "tint": Color("ff9c8c")},
	"orc_penyerbu": {"base": "goblin", "size": 1.7, "tint": Color("c9785a")},
	"orc_gua": {"base": "goblin", "size": 1.55, "tint": Color("b8a070")},
	"orc_penjaga": {"base": "goblin", "size": 1.8, "tint": Color("d9906a")},
	"orc_buas": {"base": "goblin", "size": 2.05, "tint": Color("cc6a62")},
	"ular_hutan": {"base": "ular_sawah", "size": 1.2, "tint": Color("86b890")},
	"serigala_alfa": {"base": "serigala_hutan", "size": 1.25, "tint": Color("6a6f7c")},
	# Hutan Lebat (v0.46.0): binatang hutan memakai model hewan yang sudah ada dengan ukuran/warna berbeda.
	"kancil_hutan": {"base": "anak_ayam", "size": 1.45, "tint": Color("d9b98a")},
	# v0.77.0 (roadmap no. 70): Kelelawar Gua memakai kelelawar Quaternius (dulu kerangka KayKit), lebih besar dan gelap.
	"kelelawar_gua": {"base": "kelelawar_hutan", "size": 1.3, "tint": Color("8f8a9c")},
	"rubah_hutan": {"base": "serigala_hutan", "size": 0.85, "tint": Color("f0a060")},
	"ular_belang": {"base": "ular_sawah", "size": 1.15, "tint": Color("c8b070")},
	"babi_bertaring": {"base": "babi_hutan", "size": 1.2, "tint": Color("b09078")},
	"serigala_hitam": {"base": "serigala_hutan", "size": 1.15, "tint": Color("55555e")},
	"beruang_hutan": {"base": "babi_hutan", "size": 1.7, "tint": Color("8a6244")},
	# Bos Goblin Level 1..3 (makin besar dan makin merah) dan penjaga Gua Goblin.
	"goblin_hutan_1": {"base": "goblin_penjaga", "size": 1.6, "tint": Color("b8e0a0")},
	"goblin_hutan_2": {"base": "goblin_penjaga", "size": 1.95, "tint": Color("e8c070")},
	"goblin_hutan_3": {"base": "goblin_penjaga", "size": 2.3, "tint": Color("e07060")},
	# Urutan bos (v0.72.0): Hutan = Goblin, Gua Goblin = Orc Batu, Gunung Berapi = Naga Lava. Id lama dipertahankan.
	"kepala_goblin_1": {"base": "ogre_batu", "size": 1.6, "tint": Color("d6ccb4")},
	"kepala_goblin_2": {"base": "ogre_batu", "size": 1.9, "tint": Color("b4bccc")},
	"kepala_goblin_3": {"base": "ogre_batu", "size": 2.25, "tint": Color("e6a888")},
	# v0.76.0: Naga Lava ±25% lebih besar.
	"ogre_gunung_1": {"base": "aldragor", "size": 1.0, "tint": Color.WHITE, "colors": NAGA_LAVA},
	"ogre_gunung_2": {"base": "aldragor", "size": 1.2, "tint": Color.WHITE, "colors": NAGA_LAVA},
	"ogre_gunung_3": {"base": "aldragor", "size": 1.4, "tint": Color("fff0e0"), "colors": NAGA_LAVA},
	# Istana Kegelapan (v0.72.0): dua jenis naga kecil berkeliaran.
	"naga_bayangan": {"base": "aldragor", "size": 0.5, "tint": Color.WHITE, "colors": {"Main": Color("3e2e62"), "Wings": Color("1c1230"), "Belly": Color("8a6ab4"), "Claws": Color("d8d0e8"), "Eyes": Color("d080ff")}},
	"naga_api": {"base": "aldragor", "size": 0.56, "tint": Color.WHITE, "colors": {"Main": Color("d8662c"), "Wings": Color("7a2a12"), "Belly": Color("f4c868"), "Claws": Color("f2ead6"), "Eyes": Color("ffe040")}},
	# Ogre Rawa (roadmap no. 63): Monster Batu yang lebih kecil dan hijau lumut.
	"ogre_rawa": {"base": "ogre_batu", "size": 0.88, "tint": Color("a8d090")},
	# Cerita The Last Dragon (v0.67.0). Panglima Orc Batu (id lama raja_goblin) memakai model Monster Batu yang besar
	# dan kelabu; Malzareth = model Mage yang gelap dan lebih tinggi; penjaga Istana Kegelapan berwarna ungu kutukan.
	"raja_goblin": {"base": "ogre_batu", "size": 2.1, "tint": Color("a8a4a0")},
	"malzareth": {"base": "nenek_penjual", "size": 1.35, "tint": Color("6f4a8f")},
	"kelelawar_istana": {"base": "kelelawar_hutan", "size": 1.3, "tint": Color("b48cff")},
	"prajurit_kutukan": {"base": "goblin_penjaga", "size": 1.25, "tint": Color("a58ad6")},
	"orc_kegelapan": {"base": "goblin", "size": 2.0, "tint": Color("8a6aa8")},
	"iblis_bayangan": {"base": "golem_lava", "size": 1.15, "tint": Color("9070c8")},
	# Prajurit biasa (pasukan dari tenda hijau): pendekar tombak yang lebih kecil dan kehijauan.
	"prajurit": {"base": "pendekar_tombak", "size": 0.88, "tint": Color("b6d8a4")},
	# Lereng Gunung Berapi (v0.75.0): goblin dan orc batu bermodel merah lava yang berpendar (lihat MAP_SKINS).
	"goblin_lava": {"base": "goblin", "size": 1.0, "tint": Color("ff5a3a"), "lava": true},
	"goblin_pemburu_lava": {"base": "goblin", "size": 1.2, "tint": Color("ff8a40"), "lava": true},
	"goblin_penjaga_lava": {"base": "goblin_penjaga", "size": 1.0, "tint": Color("ff4630"), "lava": true},
	"orc_batu_lava": {"base": "ogre_batu", "size": 1.0, "tint": Color("e0502c"), "lava": true},
}

## Model khas peta (v0.75.0): musuh yang sama (id server sama) tampil dengan model lain di peta tertentu.
## Lereng Gunung Berapi: goblin dan orc batu berwarna merah lava seperti binatang tengkorak lava di sana.
const MAP_SKINS := {
	"gunung_batu": {"goblin": "goblin_lava", "goblin_pemburu": "goblin_pemburu_lava", "goblin_penjaga": "goblin_penjaga_lava", "ogre_batu": "orc_batu_lava"},
}
const LAVA_GLOW := Color("ff4a12")


## Id model untuk musuh `id` di peta `map_id` (id itu sendiri bila peta tidak punya model khas).
static func skin(id: String, map_id: String) -> String:
	return str((MAP_SKINS.get(map_id, {}) as Dictionary).get(id, id))


## Pendar merah lava pada semua bahan model (tepi menyala + cahaya jingga redup).
static func _lava_glow(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mats: Array[StandardMaterial3D] = []
		if mi.material_override is StandardMaterial3D:
			mats.append(mi.material_override as StandardMaterial3D)
		elif mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m is StandardMaterial3D:
					mats.append(m as StandardMaterial3D)
		for sm in mats:
			sm.rim_enabled = true
			sm.rim = 0.7
			sm.rim_tint = 0.9
			sm.emission_enabled = true
			sm.emission = LAVA_GLOW
			sm.emission_energy_multiplier = 0.32
	for ch in n.get_children():
		_lava_glow(ch)


## Warna hewan Quaternius per nama bahan (roadmap no. 61-70): warna aslinya hilang saat diubah ke GLB
## ringan (semua bahan abu-abu 0,8), sehingga anak ayam, Kucing Liar, dan Serigala tampil putih polos.
const ANIMAL_COLORS := {
	"anak_ayam": {"Material.001": Color("f2c94c"), "Material.002": Color("f08a24")},         # anak ayam: kuning, paruh/kaki oranye
	"serigala_hutan": {"Wolf": Color("8a8478")},                                             # serigala abu-cokelat
	# Monster Quaternius (Animated Monsters, CC0): Aldragor merah tua bersayap ungu gelap (dikutuk), kelelawar kelabu ungu.
	"aldragor": {"Main": Color("8e2f3a"), "Wings": Color("5a2448"), "Belly": Color("e2b45c"), "Claws": Color("f2ead6"), "Eyes": Color("ffd23a")},
	"kelelawar_hutan": {"Main": Color("5b4a63"), "Belly": Color("9a8090"), "Black": Color("1c1a20"), "Eyes": Color("ff4a3a"), "Nose": Color("d48a9a")},
}


static func _color_by_material(n: Node, colors: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as StandardMaterial3D
			if m != null and colors.has(m.resource_name):
				m.albedo_color = colors[m.resource_name]
	for c in n.get_children():
		_color_by_material(c, colors)


## Goblin (v0.69.1): model aslinya gelap di cahaya hutan. Warna dasar dikalikan faktor ini dan
## diberi cahaya tepi tipis agar siluetnya tetap terbaca; warna varian dilunakkan ke putih.
const BRIGHT := {"goblin": 1.15, "goblin_penjaga": 1.1}
const BRIGHT_TINT_SOFTEN := 0.25
const BRIGHT_RIM := 0.3
const BRIGHT_GLOW := 0.2

static func _brighten(n: Node, k: float) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var sm := mi.get_surface_override_material(i) as StandardMaterial3D
				if sm == null:
					continue
				var c := sm.albedo_color
				sm.albedo_color = Color(c.r * k, c.g * k, c.b * k, 1.0)
				sm.rim_enabled = true
				sm.rim = BRIGHT_RIM
				sm.rim_tint = 0.5
				# sisi yang membelakangi matahari tidak lagi hampir hitam
				sm.emission_enabled = sm.albedo_texture != null
				sm.emission = Color(c.r, c.g, c.b)
				sm.emission_texture = sm.albedo_texture
				sm.emission_energy_multiplier = BRIGHT_GLOW
	for ch in n.get_children():
		_brighten(ch, k)


## Mengalikan warna semua bahan model (hanya bahan hasil _fix_materials / bentuk dasar).
static func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var mo := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			mo.albedo_color = mo.albedo_color * c
			mi.material_override = mo
		elif mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m is StandardMaterial3D:
					var sm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.albedo_color = sm.albedo_color * c
					mi.set_surface_override_material(i, sm)
	for ch in n.get_children():
		_tint(ch, c)


## Membuat model untuk id. Selalu mengembalikan node (placeholder bila tidak dikenal).
## Skala binatang kerangka menurut jenisnya (sama untuk tiap palet peta).
const BONE_SCALES := {"rubah": 1.2, "babi": 1.3, "ular": 1.15, "serigala": 1.25, "beruang": 1.45}


static func create(id: String) -> Node3D:
	if VARIANTS.has(id):
		var v: Dictionary = VARIANTS[id]
		var base := create(str(v.base))
		base.scale = base.scale * float(v.size)
		if v.has("colors"):  # warna per bahan (model Quaternius), mis. naga lava / naga bayangan
			_color_by_material(base, v.colors)
		var tint: Color = v.tint
		if BRIGHT.has(str(v.base)):
			tint = tint.lerp(Color.WHITE, BRIGHT_TINT_SOFTEN)  # warna varian goblin tidak menggelapkan model
		_tint(base, tint)
		if bool(v.get("lava", false)):
			_lava_glow(base)
		base.name = id
		return base
	var path := MODEL_DIR + str(HERO_GLB.get(id, id)) + ".glb"
	var node: Node3D = null
	var from_glb := false
	if ResourceLoader.exists(path):
		node = _from_glb(id, path)
		from_glb = node != null
	if node == null:
		node = build_placeholder(id)
	if from_glb and not is_hero(id):
		node.scale = Vector3.ONE  # sudah dinormalkan di _from_glb
	else:
		var bk := _bone_kind(id)
		node.scale = Vector3.ONE * float(BONE_SCALES[bk] if bk != "" else SCALES.get(id, 0.7))
	node.name = id
	return node


static func has_glb(id: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + str(HERO_GLB.get(id, id)) + ".glb")


# --- GLB pengganti ---

static func _from_glb(id: String, path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	if not is_hero(id):
		# Gaya toon diterapkan konsisten pada seluruh NPC warga, bukan hanya Bu Sari.
		var stylized_npc := [
			"warga_ibu", "warga_ibu2", "warga_bapak", "warga_bapak2",
			"anak_desa", "nenek_penjual", "petani"
		].has(id)
		_fix_materials(inst, stylized_npc)
		if ANIMAL_COLORS.has(id):
			_color_by_material(inst, ANIMAL_COLORS[id])
		if BRIGHT.has(id):
			_brighten(inst, float(BRIGHT[id]))
		_normalize(inst, float(HEIGHTS.get(id, DEFAULT_HEIGHT)), float(LENGTHS.get(id, 0.0)))
	else:
		_style_hero(inst)
	var rig := Rig.new()
	var holder: Node3D = null  # badan utuh: digerakkan rig untuk model tanpa rangka
	if is_hero(id):
		rig.add_child(inst)  # pahlawan tidak butuh pegangan (dulu tetap dibuat dan jadi node yatim, no. 253)
	else:
		holder = Node3D.new()
		holder.name = "body"
		holder.add_child(inst)
		rig.add_child(holder)
	var ap := _find_animation_player(inst)
	if ap != null and not ap.get_animation_list().is_empty():
		rig.setup("biped", {} if is_hero(id) else {"body": holder})
		rig.use_animation_player(ap)
	elif id == "ksatria":
		rig.setup("biped", _paladin_pivots(inst))
	else:
		rig.setup("static", {"body": holder} if holder != null else {})  # tanpa sendi: badan utuh bergoyang
	return rig


## Warna per titik (hasil gambar-ke-3D) dipakai sebagai warna dasar; dua sisi terlihat.
## Bu Sari memakai diffuse toon agar shading-nya lebih terasa seperti RPG fantasi stylized.
static func _fix_materials(n: Node, stylized := false) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				var sm: StandardMaterial3D = (m.duplicate() as StandardMaterial3D) if m is StandardMaterial3D else StandardMaterial3D.new()
				if sm.albedo_texture == null:
					sm.vertex_color_use_as_albedo = true
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED
				# beberapa glb (babi hutan) membawa alpha 0 + mode MASK -> model tak terlihat sama sekali
				sm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				sm.albedo_color = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, 1.0)
				sm.roughness = 0.9
				sm.metallic = 0.0
				if stylized:
					sm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
					sm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mi.set_surface_override_material(i, sm)
	for c in n.get_children():
		_fix_materials(c, stylized)


## Bahan pahlawan KayKit (roadmap no. 1): tekstur palet dibaca tajam supaya warna antarsel
## palet tidak bercampur jadi abu-abu, bayangan toon seperti NPC desa (satu gaya), dan cahaya
## tepi tipis supaya pahlawan tidak tenggelam di tanah/rumput. Bahan dipasang sebagai override
## per permukaan, sehingga _tint (varian "prajurit") juga ikut berlaku.
const HERO_RIM := 0.35
const HERO_RIM_TINT := 0.4

static func _style_hero(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if not (m is StandardMaterial3D):
					continue
				var sm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				if sm.albedo_texture != null:
					sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				sm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				sm.specular_mode = BaseMaterial3D.SPECULAR_TOON
				sm.metallic = 0.0
				sm.roughness = 0.75
				sm.rim_enabled = true
				sm.rim = HERO_RIM
				sm.rim_tint = HERO_RIM_TINT
				mi.set_surface_override_material(i, sm)
	for c in n.get_children():
		_style_hero(c)


# --- pakaian dan perlengkapan pahlawan (roadmap no. 14-18) ---

## Variasi pakaian (sama urutannya dengan NumOutfits di server). Warna = pengali tekstur jubah/badan/kaki.
const OUTFIT_NAMES := ["Asli", "Merah Kerajaan", "Hijau Rimba", "Biru Malam"]
const OUTFIT_TINTS := [Color(1, 1, 1), Color("ff9c8c"), Color("a6e09a"), Color("9cb6ff")]
## Pelindung: pengali warna badan/kaki, dan apakah ada bantalan bahu.
const ARMOR_LOOK := {
	"baju_kulit": {"tint": Color("d9b48a"), "pads": false},
	"zirah_besi": {"tint": Color("c8d2e0"), "pads": true},
}
## Senjata: pengali warna bilah dan cahaya (pedang rune berpendar).
const WEAPON_LOOK := {
	"pedang_besi": {"tint": Color("e6eaf0")},
	"pedang_baja": {"tint": Color("b4c6ee")},
	"pedang_rune": {"tint": Color("9fd8ff"), "glow": Color("3fb6ff")},
}
## Helm: warna kubah dan pinggiran; helm besi punya jambul merah dan pelindung hidung.
const HELMET_LOOK := {
	"helm_kulit": {"dome": Color("b47c48"), "trim": Color("6e4628"), "crest": false},
	"helm_besi": {"dome": Color("aeb8c6"), "trim": Color("5e6676"), "crest": true},
}
## Akhiran nama mesh KayKit.
const CLOTH_PARTS := ["_Cape", "_Body", "_LegLeft", "_LegRight"]
const ARMOR_PARTS := ["_Body", "_LegLeft", "_LegRight"]
const WEAPON_PARTS := ["1H_Sword", "2H_Axe", "Spear", "2H_Crossbow"]
const HEADGEAR_PARTS := ["Knight_Helmet", "Barbarian_Hat"]
const DRESS_NODE := "Perlengkapan"


static func _ends_with_any(n: String, parts: Array) -> bool:
	for p: String in parts:
		if n.ends_with(p) or n == p:
			return true
	return false


## Warnai semua permukaan mesh: warna dasar asli (disimpan sekali) dikali c; glow = cahaya pendar.
static func _paint(mi: MeshInstance3D, c: Color, glow := Color(0, 0, 0, 0)) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(i) as StandardMaterial3D
		if m == null:
			continue
		if not m.has_meta("base_col"):
			m.set_meta("base_col", m.albedo_color)
		m.albedo_color = (m.get_meta("base_col") as Color) * c
		m.emission_enabled = glow.a > 0.0
		if glow.a > 0.0:
			m.emission = glow
			m.emission_energy_multiplier = 0.9


## Mesh di bawah n beserta transformasinya relatif terhadap n (model belum tentu sudah di pohon).
static func _meshes(n: Node, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		var cx := xf
		if c is Node3D:
			cx = xf * (c as Node3D).transform
		if c is MeshInstance3D:
			out.append([c, cx])
		_meshes(c, cx, out)


## Kenakan pakaian dan perlengkapan pada model pahlawan buatan create(). Boleh dipanggil berulang
## (mis. setelah ganti perlengkapan): warna dihitung ulang dari warna asli dan tempelan lama dibuang.
## equipment = {"weapon", "armor", "helmet"} (id barang, "" = kosong).
static func dress(rig: Node3D, outfit: int, equipment: Dictionary) -> void:
	if rig == null:
		return
	var sk: Skeleton3D = null
	for n in rig.find_children("*", "Skeleton3D", true, false):
		sk = n as Skeleton3D
		break
	if sk == null:
		return
	for old in sk.get_children():
		if old.has_meta(DRESS_NODE):  # tempelan lama (BoneAttachment3D harus anak langsung rangka)
			sk.remove_child(old)
			old.free()
	var cloth: Color = OUTFIT_TINTS[clampi(outfit, 0, OUTFIT_TINTS.size() - 1)]
	var armor: Dictionary = ARMOR_LOOK.get(str(equipment.get("armor", "")), {})
	var weapon: Dictionary = WEAPON_LOOK.get(str(equipment.get("weapon", "")), {})
	var helmet: Dictionary = HELMET_LOOK.get(str(equipment.get("helmet", "")), {})
	var list: Array = []
	_meshes(sk, Transform3D.IDENTITY, list)
	var head_box := AABB()
	var chest_y := 0.0
	var has_weapon := false
	var is_mage := false
	for pair: Array in list:
		var mi := pair[0] as MeshInstance3D
		var nm := str(mi.name)
		var c := Color(1, 1, 1)
		if _ends_with_any(nm, CLOTH_PARTS):
			c = c * cloth
		if not armor.is_empty() and _ends_with_any(nm, ARMOR_PARTS):
			c = c * (armor.tint as Color)
		var glow := Color(0, 0, 0, 0)
		if not weapon.is_empty() and _ends_with_any(nm, WEAPON_PARTS):
			c = c * (weapon.tint as Color)
			glow = weapon.get("glow", glow)
		_paint(mi, c, glow)
		if _ends_with_any(nm, HEADGEAR_PARTS):
			mi.visible = helmet.is_empty()  # helm yang dipakai menggantikan topi/helm bawaan
		if _ends_with_any(nm, WEAPON_PARTS):
			has_weapon = true
		if nm.begins_with("Mage_") or nm.ends_with("_Head_Hooded"):  # Penyihir berkerudung (v0.80.0)
			is_mage = true
		if nm.ends_with("_Head") or nm.ends_with("_Head_Hooded"):
			head_box = (pair[1] as Transform3D) * mi.get_aabb()
		if nm.ends_with("_Body"):
			var bb := (pair[1] as Transform3D) * mi.get_aabb()
			chest_y = bb.end.y
	if not helmet.is_empty() and head_box.size != Vector3.ZERO:
		_attach(sk, "head", _helmet_mesh(helmet, head_box))
	if armor.get("pads", false) and chest_y > 0.0:
		for side: String in ["l", "r"]:
			_attach(sk, "upperarm." + side, _pad_mesh(armor.tint as Color))
	if is_mage and not has_weapon:
		var w_tint: Color = weapon.get("tint", Color(1, 1, 1))
		_attach(sk, "handslot.r", _staff_mesh(weapon.get("glow", Color("b77dff")) as Color, w_tint))
	if head_box.size != Vector3.ZERO:
		_face(sk, FACES.get(str(rig.name), {}), head_box, not helmet.is_empty())


## Wajah khas tiap pahlawan (roadmap no. 5, v0.80.0). Model KayKit memakai kepala yang sama per jenis, jadi
## ciri wajah dibuat dari bentuk sederhana yang ditempel di tulang kepala: alis, kumis, janggut, pipi merona.
## Ukuran mengikuti kotak kepala, jadi tetap pas bila skala model berubah.
const FACES := {
	"ksatria": {"brow": Color("3a2414"), "brow_tilt": 0.18, "stubble": Color("5a3a24")},
	"pendekar_kapak": {"brow": Color("7a3a1c"), "brow_tilt": 0.32, "beard": Color("9a4a22")},
	"pemanah": {"brow": Color("6a3a20"), "brow_tilt": -0.08, "blush": Color("f29a8a")},
	"pendekar_tombak": {"brow": Color("2a1c12"), "brow_tilt": 0.1, "mustache": Color("2a1c12")},
	"penyihir": {"brow": Color("e8e8f0"), "brow_tilt": -0.2, "wizard_beard": Color("eeeef4")},
}

## Ciri wajah `f` (lihat FACES / WARGA_FACES) ditempel di tulang kepala. far > 0 = bagian wajah tidak digambar
## lebih jauh dari `far` meter (warga jauh: hemat panggilan gambar di HP).
static func _face(sk: Skeleton3D, f: Dictionary, head: AABB, helmet: bool, far := 0.0) -> void:
	if f.is_empty():
		return
	var root := Node3D.new()
	root.name = "wajah"
	var w := head.size.x
	var h := head.size.y
	var cx := head.position.x + w / 2.0
	var front := head.end.z
	var eye_y := head.position.y + h * float(f.get("eye_y", FACE_EYE_Y))
	root.set_meta("rig_pos", Vector3(cx, eye_y, front))
	if f.has("brow") and not helmet:
		var bw := float(f.get("brow_w", 1.0))
		for sx: float in [-1.0, 1.0]:
			var b := _face_part(BoxMesh.new(), f.brow as Color)
			(b.mesh as BoxMesh).size = Vector3(w * 0.17, h * 0.035 * bw, w * 0.04)
			b.position = Vector3(sx * w * 0.17, h * 0.1, -w * 0.02)
			b.rotation.z = sx * float(f.get("brow_tilt", 0.0))
			root.add_child(b)
	if f.has("blush"):
		for sx: float in [-1.0, 1.0]:
			var c := _face_part(SphereMesh.new(), f.blush as Color)
			(c.mesh as SphereMesh).radius = w * 0.07
			(c.mesh as SphereMesh).height = w * 0.05
			c.position = Vector3(sx * w * 0.27, -h * 0.09, -w * 0.05)
			root.add_child(c)
	if f.has("freckles"):  # bintik di pipi (anak-anak)
		for sx: float in [-1.0, 1.0]:
			for k in 3:
				var fr := _face_part(SphereMesh.new(), f.freckles as Color)
				(fr.mesh as SphereMesh).radius = w * 0.014
				(fr.mesh as SphereMesh).height = w * 0.02
				fr.position = Vector3(sx * w * (0.2 + 0.05 * k), -h * (0.04 + 0.03 * (k % 2)), -w * 0.02)
				root.add_child(fr)
	if f.has("mustache"):
		for sx: float in [-1.0, 1.0]:
			var m := _face_part(CapsuleMesh.new(), f.mustache as Color)
			(m.mesh as CapsuleMesh).radius = w * 0.035
			(m.mesh as CapsuleMesh).height = w * 0.22
			m.position = Vector3(sx * w * 0.08, -h * 0.17, -w * 0.01)
			m.rotation.z = sx * float(f.get("mustache_tilt", 1.25))
			root.add_child(m)
	if f.has("stubble"):
		var s := _face_part(SphereMesh.new(), f.stubble as Color)
		(s.mesh as SphereMesh).radius = w * 0.2
		(s.mesh as SphereMesh).height = w * 0.18
		s.position = Vector3(0, -h * 0.3, -w * 0.12)
		s.scale = Vector3(1.0, 0.7, 0.55)
		root.add_child(s)
	if f.has("goatee"):  # jenggot kambing: kerucut kecil di dagu
		var g := _face_part(CylinderMesh.new(), f.goatee as Color)
		var gm := g.mesh as CylinderMesh
		gm.top_radius = w * 0.07
		gm.bottom_radius = w * 0.01
		gm.height = h * 0.22
		gm.radial_segments = 6
		g.position = Vector3(0, -h * 0.36, -w * 0.04)
		g.scale = Vector3(1.0, 1.0, 0.6)
		root.add_child(g)
	if f.has("beard"):
		var bd := _face_part(SphereMesh.new(), f.beard as Color)
		(bd.mesh as SphereMesh).radius = w * 0.3
		(bd.mesh as SphereMesh).height = w * 0.6
		bd.position = Vector3(0, -h * 0.34, -w * 0.12)
		bd.scale = Vector3(1.0, 1.05, 0.6)
		root.add_child(bd)
	if f.has("wizard_beard"):
		var wb := _face_part(CylinderMesh.new(), f.wizard_beard as Color)
		var cm := wb.mesh as CylinderMesh
		cm.top_radius = w * 0.26
		cm.bottom_radius = w * 0.02
		cm.height = h * 0.75
		cm.radial_segments = 8
		wb.position = Vector3(0, -h * 0.25 - cm.height / 2.0, -w * 0.1)
		wb.scale = Vector3(1.0, 1.0, 0.55)
		root.add_child(wb)
		var mo := _face_part(CapsuleMesh.new(), f.wizard_beard as Color)
		(mo.mesh as CapsuleMesh).radius = w * 0.04
		(mo.mesh as CapsuleMesh).height = w * 0.42
		mo.position = Vector3(0, -h * 0.18, -w * 0.0)
		mo.rotation.z = PI / 2.0
		root.add_child(mo)
	if f.has("mole"):  # tahi lalat di pipi
		var ml := _face_part(SphereMesh.new(), Color("3a2418"))
		(ml.mesh as SphereMesh).radius = w * 0.022
		(ml.mesh as SphereMesh).height = w * 0.03
		ml.position = Vector3(float(f.mole) * w * 0.24, -h * 0.16, -w * 0.03)
		root.add_child(ml)
	if f.has("scar"):  # bekas luka miring melintasi mata (prajurit)
		var sc := _face_part(BoxMesh.new(), Color("b8645a"))
		(sc.mesh as BoxMesh).size = Vector3(w * 0.03, h * 0.3, w * 0.03)
		sc.position = Vector3(float(f.scar) * w * 0.17, -h * 0.02, w * 0.005)
		sc.rotation.z = float(f.scar) * 0.45
		root.add_child(sc)
	if f.has("glasses"):  # kacamata bulat: dua lingkar + jembatan
		for sx: float in [-1.0, 1.0]:
			var lens := _face_part(TorusMesh.new(), f.glasses as Color)
			var tm := lens.mesh as TorusMesh
			tm.inner_radius = w * 0.075
			tm.outer_radius = w * 0.1
			tm.rings = 12
			tm.ring_segments = 6
			lens.position = Vector3(sx * w * 0.17, -h * 0.01, w * 0.03)
			lens.rotation.x = PI / 2.0
			root.add_child(lens)
		var br := _face_part(BoxMesh.new(), f.glasses as Color)
		(br.mesh as BoxMesh).size = Vector3(w * 0.14, w * 0.025, w * 0.025)
		br.position = Vector3(0, -h * 0.0, w * 0.03)
		root.add_child(br)
	if far > 0.0:
		for part in root.get_children():
			(part as GeometryInstance3D).visibility_range_end = far
	_attach(sk, "head", root)


## Tinggi garis mata di kotak kepala (0 = dagu/bawah, 1 = puncak rambut/topi).
const FACE_EYE_Y := 0.42

static func _face_part(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _mat(color)
	m.rim_enabled = false
	mi.material_override = m
	return mi


## Tongkat sihir Penyihir (roadmap no. 158): batang kayu, cincin logam, dan bola kristal berpendar.
## Dipasang di tulang handslot.r (sumbu Y tulang = arah genggaman, seperti senjata KayKit).
static func _staff_mesh(glow: Color, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "tongkat"
	var rod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.06
	cm.height = 2.3
	cm.radial_segments = 8
	rod.mesh = cm
	rod.material_override = _mat(Color("7a5232") * tint)
	rod.position = Vector3(0, 0.55, 0)
	root.add_child(rod)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.13
	ring.mesh = tm
	ring.material_override = _mat(Color("d9b45a"), true)
	ring.position = Vector3(0, 1.62, 0)
	root.add_child(ring)
	var orb := MeshInstance3D.new()
	orb.name = "bola"
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	orb.mesh = sm
	var om := _mat(glow)
	om.rim_enabled = false
	om.emission_enabled = true
	om.emission = glow
	om.emission_energy_multiplier = 0.7
	orb.material_override = om
	orb.position = Vector3(0, 1.82, 0)
	root.add_child(orb)
	return root


## Tempelkan `part` (posisi dalam ruang rangka) ke tulang `bone` supaya ikut bergerak.
static func _attach(sk: Skeleton3D, bone: String, part: Node3D) -> void:
	var bi := sk.find_bone(bone)
	if bi < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.name = "%s_%s" % [DRESS_NODE, bone]
	ba.set_meta(DRESS_NODE, true)
	sk.add_child(ba)
	ba.bone_name = bone
	ba.transform = sk.get_bone_global_rest(bi)  # posisi awal; selanjutnya diikuti otomatis
	var rest := sk.get_bone_global_rest(bi)
	if part.has_meta("rig_pos"):
		# bagian diletakkan di posisi rangka tertentu: ubah ke ruang tulang
		var t := Transform3D(Basis.IDENTITY, part.get_meta("rig_pos") as Vector3)
		part.transform = rest.affine_inverse() * t
	ba.add_child(part)


static func _mat(c: Color, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.45 if metal else 0.85
	m.rim_enabled = true
	m.rim = HERO_RIM
	m.rim_tint = HERO_RIM_TINT
	return m


## Helm dari bentuk dasar, disesuaikan dengan ukuran kepala model.
static func _helmet_mesh(look: Dictionary, head: AABB) -> Node3D:
	var root := Node3D.new()
	root.name = "helm"
	var w := maxf(head.size.x, head.size.z)
	var r := w * 0.52
	var top := head.position.y + head.size.y * 0.56
	root.set_meta("rig_pos", Vector3(head.get_center().x, top, head.get_center().z))
	var metal: bool = look.crest
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 8
	dome.mesh = sm
	dome.material_override = _mat(look.dome as Color, metal)
	dome.scale = Vector3(1.0, 1.15, 1.05)
	root.add_child(dome)
	var brim := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 1.06
	cm.bottom_radius = r * 1.1
	cm.height = r * 0.16
	cm.radial_segments = 20
	brim.mesh = cm
	brim.material_override = _mat(look.trim as Color, metal)
	brim.scale = Vector3(1.0, 1.0, 1.05)
	root.add_child(brim)
	if metal:
		var crest := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 0.14, r * 0.32, r * 1.3)
		crest.mesh = bm
		crest.material_override = _mat(Color("c23c32"))
		crest.position = Vector3(0, r * 1.15, 0)
		root.add_child(crest)
		var nose := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(r * 0.14, r * 0.55, r * 0.1)
		nose.mesh = nm
		nose.material_override = _mat(look.trim as Color, true)
		nose.position = Vector3(0, -r * 0.25, r * 1.08)
		root.add_child(nose)
	return root


## Bantalan bahu zirah besi: bola pipih di sendi bahu.
static func _pad_mesh(c: Color) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "bahu"
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.34
	sm.radial_segments = 14
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _mat(c * Color("b8c0cc"), true)
	mi.position = Vector3(0, 0.1, 0)  # sedikit ke arah lengan (sumbu Y tulang lengan atas)
	return mi


## Variasi warga (roadmap no. 31-32): warna baju (jubah/badan/kaki) dan kulit/rambut (kepala, lengan).
## Putih = warna asli. Bekerja pada model KayKit (pahlawan maupun warga).
static func npc_look(rig: Node3D, baju := Color(1, 1, 1), kulit := Color(1, 1, 1)) -> void:
	if rig == null:
		return
	var list: Array = []
	_meshes(rig, Transform3D.IDENTITY, list)
	for pair: Array in list:
		var mi := pair[0] as MeshInstance3D
		var nm := str(mi.name)
		if _ends_with_any(nm, CLOTH_PARTS):
			_paint(mi, baju)
		elif nm.ends_with("_Head") or nm.ends_with("_ArmLeft") or nm.ends_with("_ArmRight"):
			_paint(mi, kulit)


## Model warga dari definisi Maps.WARGA: model, ukuran, dan variasi warnanya.
static func create_warga(def: Dictionary) -> Node3D:
	var m := create(str(def.model))
	if def.has("ukuran"):
		m.scale = m.scale * float(def.ukuran)
	if def.has("baju") or def.has("kulit"):
		npc_look(m, def.get("baju", Color(1, 1, 1)), def.get("kulit", Color(1, 1, 1)))
	npc_face(m, def)
	return m


# --- variasi wajah warga (roadmap no. 31, v0.81.0) ---

## Jenis wajah per model warga: pria, wanita, atau anak. Model lain (hewan, goblin) tidak diberi wajah.
const FACE_KIND := {
	"warga_bapak": "pria", "warga_bapak2": "pria", "pendekar_kapak": "pria", "pendekar_tombak": "pria",
	"ksatria": "pria", "prajurit": "pria", "warga_ibu": "wanita", "warga_ibu2": "wanita", "pemanah": "wanita",
	"anak_desa": "anak",
}
## Kumpulan wajah; warga mendapat satu wajah tetap menurut id+namanya (sama di dunia dan di layar dialog).
const WARGA_FACES := {
	"pria": [
		{"brow": Color("2a1c12"), "brow_tilt": 0.1, "mustache": Color("2a1c12")},
		{"brow": Color("4a2e1a"), "brow_tilt": 0.22, "brow_w": 1.4, "stubble": Color("4a3020")},
		{"brow": Color("1e1610"), "brow_tilt": -0.05, "goatee": Color("1e1610")},
		{"brow": Color("8a8a8a"), "brow_tilt": -0.12, "mustache": Color("a8a8a8"), "mustache_tilt": 1.45},
		{"brow": Color("3a2414"), "brow_tilt": 0.05, "beard": Color("3a2414")},
		{"brow": Color("5a3a22"), "brow_tilt": 0.15, "mole": 1.0},
		{"brow": Color("2a1c12"), "brow_tilt": 0.0, "glasses": Color("4a3a2a")},
	],
	"wanita": [
		{"brow": Color("3a2414"), "brow_tilt": -0.08, "brow_w": 0.7, "blush": Color("f29a8a")},
		{"brow": Color("2a1c12"), "brow_tilt": -0.15, "brow_w": 0.7, "mole": -1.0},
		{"brow": Color("6a3a20"), "brow_tilt": -0.05, "brow_w": 0.8, "blush": Color("e88a90"), "mole": 1.0},
		{"brow": Color("1e1610"), "brow_tilt": -0.2, "brow_w": 0.65},
		{"brow": Color("9a9a9a"), "brow_tilt": -0.1, "brow_w": 0.7, "glasses": Color("8a6a3a")},
	],
	"anak": [
		{"brow": Color("4a2e1a"), "brow_tilt": -0.1, "brow_w": 0.8, "blush": Color("f4a090"), "freckles": Color("b07050")},
		{"brow": Color("2a1c12"), "brow_tilt": 0.12, "brow_w": 0.9, "freckles": Color("a06848")},
		{"brow": Color("3a2414"), "brow_tilt": -0.05, "brow_w": 0.8, "blush": Color("f29a8a")},
	],
}
## Ciri wajah tidak digambar dari jauh (meter) supaya warga jauh tidak menambah panggilan gambar di HP.
const WARGA_FACE_FAR := 16.0


## Wajah warga `def` (Maps.WARGA): def.wajah (kamus ciri) bila ada, selain itu dipilih dari WARGA_FACES.
static func warga_face_of(def: Dictionary) -> Dictionary:
	if def.has("wajah"):
		return def.wajah
	var pool: Array = WARGA_FACES.get(FACE_KIND.get(str(def.get("model", "")), ""), [])
	if pool.is_empty():
		return {}
	var key := (str(def.get("id", "")) + "/" + str(def.get("name", ""))).hash()
	return pool[absi(key) % pool.size()]


static func npc_face(rig: Node3D, def: Dictionary) -> void:
	var f := warga_face_of(def)
	if f.is_empty() or rig == null:
		return
	var sk: Skeleton3D = null
	for n in rig.find_children("*", "Skeleton3D", true, false):
		sk = n as Skeleton3D
		break
	if sk == null:
		return
	var list: Array = []
	_meshes(sk, Transform3D.IDENTITY, list)
	for pair: Array in list:
		var nm := str((pair[0] as MeshInstance3D).name)
		if nm.ends_with("_Head") or nm.ends_with("_Head_Hooded"):
			_face(sk, f, (pair[1] as Transform3D) * (pair[0] as MeshInstance3D).get_aabb(), false, WARGA_FACE_FAR)
			return


## Pakaian dan perlengkapan pemain yang sedang login.
static func dress_current(rig: Node3D) -> void:
	var st: Dictionary = Session.player.get("state", {})
	dress(rig, int(st.get("outfit", 0)), st.get("equipment", {}))


static func _aabb_of(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var has := false
	if n is MeshInstance3D:
		box = xf * (n as MeshInstance3D).get_aabb()
		has = true
	for c in n.get_children():
		if c is Node3D:
			var sub := _aabb_of(c, xf * (c as Node3D).transform)
			if sub.size != Vector3.ZERO:
				box = sub if not has else box.merge(sub)
				has = true
	return box


## Skala ke tinggi h, kaki di y=0, pusat di x=z=0.
static func _normalize(inst: Node3D, h: float, length := 0.0) -> void:
	var box := _aabb_of(inst, Transform3D.IDENTITY)
	if box.size.y <= 0.0001:
		return
	var k := h / box.size.y
	if length > 0.0:
		k = length / maxf(box.size.x, box.size.z)
	inst.scale = Vector3.ONE * k
	var c := box.get_center()
	inst.position = Vector3(-c.x * k, -box.position.y * k, -c.z * k)


static func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_animation_player(c)
		if f != null:
			return f
	return null


## Paladin dari Blender/trimesh: potongan mesh terpisah tanpa Skeleton, jadi kelompok
## potongan dipasang ke pivot supaya bisa diayun (animasi prosedural).
static func _paladin_pivots(hero: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var defs := {
		"leg_l": [Vector3(-0.17, 0.96, 0.0), ["L_boot", "L_toe", "L_greave", "L_knee", "L_thigh", "L_thigh_armor"]],
		"leg_r": [Vector3(0.17, 0.96, 0.0), ["R_boot", "R_toe", "R_greave", "R_knee", "R_thigh", "R_thigh_armor"]],
		"arm_l": [Vector3(-0.40, 1.45, 0.0), [
			"L_pauldron", "L_pauldron_shell", "L_upperarm", "L_vambrace", "L_bracer_trim", "L_glove",
			"sword_grip", "sword_grip_wrap_1.08", "sword_grip_wrap_1.135", "sword_grip_wrap_1.19",
			"sword_grip_wrap_1.245", "sword_grip_wrap_1.3", "sword_guard", "rune_sword_blade",
			"sword_blade_edge", "rune_0", "rune_1", "rune_2", "rune_3"]],
		"arm_r": [Vector3(0.40, 1.45, 0.0), [
			"R_pauldron", "R_pauldron_shell", "R_upperarm", "R_vambrace", "R_bracer_trim", "R_glove",
			"lion_shield", "shield_gold_face", "shield_silver_inset", "lion_mane", "lion_face", "lion_muzzle",
			"lion_eye_0.62", "lion_eye_0.68", "lion_mane_tuft_0", "lion_mane_tuft_1", "lion_mane_tuft_2",
			"lion_mane_tuft_3", "lion_mane_tuft_4", "lion_mane_tuft_5", "lion_mane_tuft_6", "lion_mane_tuft_7"]],
		"tail": [Vector3(0.0, 1.50, -0.15), ["red_cape"]],
		"head": [Vector3(0.0, 1.68, 0.0), [
			"neck", "head", "ear_-0.17", "ear_0.17", "hair_cap", "hair_lock_0", "hair_lock_1", "hair_lock_2",
			"hair_lock_3", "hair_lock_4", "eye_white_-0.065", "eye_white_0.065", "eye_iris_-0.065",
			"eye_iris_0.065", "brow_L", "brow_R", "nose", "mouth"]],
	}
	var frame := hero.find_child("world", true, false) as Node3D  # induk semua potongan
	if frame == null:
		frame = hero
	for pname: String in defs:
		var pivot := Node3D.new()
		pivot.name = pname
		frame.add_child(pivot)
		pivot.position = defs[pname][0]
		pv[pname] = pivot
		for mesh_name: String in defs[pname][1]:
			var m := hero.find_child(mesh_name, true, false) as Node3D
			if m != null and m != pivot:
				# Model belum ada di pohon adegan, jadi pakai rumus: posisi lokal dikurangi posisi pivot.
				m.owner = null  # hindari peringatan pemilik adegan
				m.reparent(pivot, false)
				m.position -= pivot.position
	return pv


# --- bentuk dasar ---

static func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot := Vector3.ZERO, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if glow:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.6
		mi.material_override = m
	else:
		mi.material_override = WB.mat(color)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO, glow := false) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mi(parent, m, pos, color, rot, glow)


static func ball(parent: Node3D, r: float, pos: Vector3, color: Color, scl := Vector3.ONE, glow := false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 6
	var mi := _mi(parent, m, pos, color, Vector3.ZERO, glow)
	mi.scale = scl
	return mi


static func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	return _mi(parent, m, pos, color, rot)


static func _cone_mesh(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


## Kerucut dengan ujung di +Y (diputar lewat rot).
static func cone(parent: Node3D, r: float, h: float, pos: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	return cyl(parent, 0.0, r, h, pos, color, rot)


static func pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


static func _eyes(head: Node3D, hr: float, color := Color("1a1a1a"), glow := false, z := 0.85, spread := 0.38) -> void:
	for s in [-1.0, 1.0]:
		ball(head, hr * 0.13, Vector3(s * hr * spread, hr * 1.05, hr * z), color, Vector3.ONE, glow)


# --- perakit ---

static func build_placeholder(id: String) -> Node3D:
	var rig := Rig.new()
	var pv: Dictionary = {}
	var kind := "biped"
	match id:
		"ksatria":
			pv = _humanoid(rig, {"skin": Color("e8b890"), "shirt": Color("b8c0cc"), "pants": Color("7d8794"), "shoes": Color("5a4630"), "hair": Color("3a2414"), "metal": true})
			box(pv.body, Vector3(0.4, 0.62, 0.05), Vector3(0, 0.78, -0.15), Color("8b1a1a"))  # jubah
			var sword := box(pv.arm_l, Vector3(0.05, 0.62, 0.02), Vector3(0, -0.62, 0.08), Color("c8d4e0"))
			sword.rotation.x = 0.0
			cyl(pv.arm_r, 0.17, 0.17, 0.04, Vector3(0, -0.34, 0.1), Color("a8b4c0"), Vector3(PI / 2.0, 0, 0))  # perisai
		"nenek_penjual":
			pv = _humanoid(rig, {"skin": Color("e8c9a5"), "shirt": Color("6a4a8a"), "pants": Color("6a4a8a"), "shoes": Color("4a3a2a"), "hair": Color("d8d8d8"), "head_r": 0.18, "bulk": 0.9})
			cyl(pv.body, 0.19, 0.34, 0.5, Vector3(0, 0.3, 0), Color("6a4a8a"))  # rok panjang
			box(pv.body, Vector3(0.26, 0.4, 0.04), Vector3(0, 0.68, 0.12), Color("f0e6cc"))  # celemek
			ball(pv.head, 0.09, Vector3(0, 0.4, -0.12), Color("d8d8d8"))  # sanggul
		"petani":
			pv = _humanoid(rig, {"skin": Color("d9a878"), "shirt": Color("c8b070"), "pants": Color("3a5a8a"), "shoes": Color("4a3a2a"), "hair": Color("5a3a1a")})
			cyl(pv.head, 0.3, 0.3, 0.03, Vector3(0, 0.3, 0), Color("e0c060"))  # topi jerami
			cyl(pv.head, 0.16, 0.18, 0.14, Vector3(0, 0.36, 0), Color("e0c060"))
		"goblin", "goblin_penjaga", "raja_goblin":
			pv = _goblin(rig, id)
		"ogre_batu":
			pv = _humanoid(rig, {"skin": Color("8a8068"), "shirt": Color("5a4a3a"), "pants": Color("4a3a2a"), "shoes": Color("3a2a1a"), "head_r": 0.2, "bulk": 1.5, "torso_w": 0.5, "torso_d": 0.32, "torso_h": 0.5, "arm_len": 0.48})
			ball(pv.body, 0.28, Vector3(0, 0.68, 0.1), Color("8a8068"), Vector3(1.2, 1.0, 0.9))  # perut
			for s in [-1.0, 1.0]:
				cone(pv.head, 0.035, 0.12, Vector3(s * 0.08, 0.04, 0.2), Color("e8e0c0"), Vector3(0.0, 0.0, 0.0))  # taring
			cyl(pv.arm_r, 0.1, 0.17, 0.75, Vector3(0, -0.5, 0.25), Color("6a4a2a"), Vector3(-PI / 3.0, 0, 0))  # gada
			kind = "golem"
		"golem_kerikil":
			pv = _golem(rig, Color("6f6f68"), Color("55554e"), Color("4a7a3a"), false)
			kind = "golem"
		"golem_lava":
			pv = _golem(rig, Color("4a4540"), Color("38342f"), Color("ff7a1a"), true)
			kind = "golem"
		"tikus_sawah":
			pv = _quad(rig, {"body": Color("8a6a4a"), "belly": Color("d8c8a8"), "len": 0.22, "wid": 0.13, "hgt": 0.13, "leg_len": 0.08, "snout": "cone", "ears": "round", "tail": "thin", "head_r": 0.1})
			kind = "quad"
		"babi_hutan":
			pv = _quad(rig, {"body": Color("5a3a28"), "belly": Color("7a5a44"), "len": 0.38, "wid": 0.24, "hgt": 0.24, "leg_len": 0.17, "snout": "boar", "ears": "pointy", "tail": "curl", "head_r": 0.17})
			kind = "quad"
		"serigala_hutan":
			pv = _quad(rig, {"body": Color("7d8088"), "belly": Color("b8bcc4"), "len": 0.4, "wid": 0.19, "hgt": 0.22, "leg_len": 0.26, "snout": "long", "ears": "pointy", "tail": "bushy", "head_r": 0.15})
			kind = "quad"
		"ular_sawah":
			pv = _snake(rig)
			kind = "snake"
		"belalang_raksasa":
			pv = _hopper(rig)
			kind = "hopper"
		"kelelawar_gua":
			pv = _bat(rig)
			kind = "bat"
		_ when _bone_kind(id) != "":
			# Binatang kerangka khas tiap peta (v0.73.0-v0.74.0): tulang (Gua Goblin), lava (Gunung Berapi),
			# batu (Benteng Orc), bayangan (Istana Kegelapan). Bentuk sama, warna/cahaya beda.
			var bk := _bone_kind(id)
			var pal: Dictionary = BONE_PALETTES[id.substr(bk.length() + 1)]
			if bk == "ular":
				pv = _bone_snake(rig, pal)
				kind = "snake"
			else:
				var o: Dictionary = (BONE_SHAPES[bk] as Dictionary).duplicate()
				o.merge(pal)
				pv = _bone_beast(rig, o)
				kind = "quad"
		_:
			pv = _humanoid(rig, {"skin": Color("c8a878"), "shirt": Color("8a5a3c"), "pants": Color("4a3a2a"), "shoes": Color("3a2a1a")})
	rig.setup(kind, pv)
	return rig


static func _humanoid(root: Node3D, o: Dictionary) -> Dictionary:
	var skin: Color = o.get("skin", Color("e8b890"))
	var shirt: Color = o.get("shirt", Color("808080"))
	var pants: Color = o.get("pants", Color("404040"))
	var shoes: Color = o.get("shoes", Color("3a2a1a"))
	var bulk := float(o.get("bulk", 1.0))
	var leg_len := float(o.get("leg_len", 0.42))
	var th := float(o.get("torso_h", 0.46))
	var tw := float(o.get("torso_w", 0.36))
	var td := float(o.get("torso_d", 0.22))
	var hr := float(o.get("head_r", 0.17))
	var al := float(o.get("arm_len", 0.40))
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var hip_y := leg_len + 0.03
	for side in [-1.0, 1.0]:
		var nm := "leg_l" if side < 0.0 else "leg_r"
		var leg := pivot(body, nm, Vector3(side * tw * 0.28, hip_y, 0))
		pv[nm] = leg
		box(leg, Vector3(0.14 * bulk, leg_len, 0.15 * bulk), Vector3(0, -leg_len / 2.0, 0), pants)
		box(leg, Vector3(0.16 * bulk, 0.07, 0.25 * bulk), Vector3(0, -leg_len + 0.035, 0.04), shoes)
	box(body, Vector3(tw, th, td), Vector3(0, hip_y + th / 2.0, 0), shirt)
	var shoulder_y := hip_y + th - 0.05
	for side2 in [-1.0, 1.0]:
		var an := "arm_l" if side2 < 0.0 else "arm_r"
		var arm := pivot(body, an, Vector3(side2 * (tw / 2.0 + 0.07 * bulk), shoulder_y, 0))
		pv[an] = arm
		box(arm, Vector3(0.1 * bulk, al, 0.1 * bulk), Vector3(0, -al / 2.0, 0), shirt if not o.get("metal", false) else Color("a0a8b4"))
		ball(arm, 0.06 * bulk, Vector3(0, -al - 0.02, 0), skin)
	var head := pivot(body, "head", Vector3(0, hip_y + th, 0))
	pv["head"] = head
	ball(head, hr, Vector3(0, hr * 0.95, 0), skin)
	_eyes(head, hr)
	if o.has("hair"):
		ball(head, hr * 1.06, Vector3(0, hr * 1.18, -hr * 0.12), o.hair, Vector3(1.0, 0.8, 1.0))
	if o.get("metal", false):
		ball(body, 0.13 * bulk, Vector3(-0.22, shoulder_y + 0.02, 0), Color("c8a040"), Vector3(1.0, 0.7, 1.0))  # bahu zirah
		ball(body, 0.13 * bulk, Vector3(0.22, shoulder_y + 0.02, 0), Color("c8a040"), Vector3(1.0, 0.7, 1.0))
	return pv


static func _goblin(root: Node3D, id: String) -> Dictionary:
	var skin := Color("6aa84a")
	var big := id == "raja_goblin"
	var guard := id == "goblin_penjaga"
	if guard:
		skin = Color("56883e")
	if big:
		skin = Color("4a7a3a")
	var pv := _humanoid(root, {"skin": skin, "shirt": Color("7a5a3a") if not big else Color("6a2a6a"), "pants": Color("5a4028"), "shoes": Color("3a2a1a"), "head_r": 0.2, "bulk": 1.1 if big else 1.0, "torso_w": 0.34, "arm_len": 0.38})
	var head: Node3D = pv.head
	for s in [-1.0, 1.0]:  # telinga lancip
		cone(head, 0.06, 0.3, Vector3(s * 0.26, 0.2, 0.0), skin, Vector3(0, 0, -s * PI / 2.0 * 1.15))
	cone(head, 0.04, 0.12, Vector3(0, 0.17, 0.2), Color("8ab860"), Vector3(PI / 2.0, 0, 0))  # hidung
	if guard:
		var helm := ball(head, 0.22, Vector3(0, 0.26, 0), Color("8a8e96"), Vector3(1.0, 0.7, 1.0))
		helm.position.y = 0.3
		cyl(pv.arm_r, 0.015, 0.015, 0.9, Vector3(0, -0.2, 0.2), Color("6a4a2a"), Vector3(PI / 2.0, 0, 0))  # tombak
		cone(pv.arm_r, 0.04, 0.16, Vector3(0, -0.2, 0.7), Color("c8d0d8"), Vector3(PI / 2.0, 0, 0))
	else:
		box(pv.arm_r, Vector3(0.035, 0.28, 0.015), Vector3(0, -0.5, 0.06), Color("c8d4e0"), Vector3(0.3, 0, 0))  # belati
	if big:
		cyl(head, 0.16, 0.2, 0.12, Vector3(0, 0.46, 0), Color("e0b830"))  # mahkota
		for i in 5:
			var a := TAU * i / 5.0
			cone(head, 0.03, 0.1, Vector3(cos(a) * 0.17, 0.56, sin(a) * 0.17), Color("e0b830"))
		box(pv.body, Vector3(0.5, 0.7, 0.05), Vector3(0, 0.78, -0.16), Color("8a1f1f"))  # jubah
	return pv


static func _golem(root: Node3D, rock: Color, rock2: Color, accent: Color, lava: bool) -> Dictionary:
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	for side in [-1.0, 1.0]:
		var nm := "leg_l" if side < 0.0 else "leg_r"
		var leg := pivot(body, nm, Vector3(side * 0.2, 0.5, 0))
		pv[nm] = leg
		box(leg, Vector3(0.3, 0.5, 0.32), Vector3(0, -0.25, 0), rock2, Vector3(0, side * 0.1, 0))
		box(leg, Vector3(0.34, 0.12, 0.42), Vector3(0, -0.46, 0.03), rock)
	box(body, Vector3(0.78, 0.72, 0.5), Vector3(0, 0.88, 0), rock, Vector3(0, 0.05, 0))
	box(body, Vector3(0.62, 0.3, 0.42), Vector3(0, 0.55, 0), rock2)
	for side2 in [-1.0, 1.0]:
		var an := "arm_l" if side2 < 0.0 else "arm_r"
		var arm := pivot(body, an, Vector3(side2 * 0.55, 1.15, 0))
		pv[an] = arm
		box(arm, Vector3(0.28, 0.62, 0.28), Vector3(0, -0.32, 0), rock2, Vector3(0, 0, side2 * 0.08))
		box(arm, Vector3(0.38, 0.34, 0.38), Vector3(0, -0.72, 0), rock)
		box(arm, Vector3(0.34, 0.14, 0.34), Vector3(0, 0.0, 0), rock)  # bahu
	var head := pivot(body, "head", Vector3(0, 1.28, 0.05))
	pv["head"] = head
	box(head, Vector3(0.4, 0.34, 0.36), Vector3(0, 0.17, 0), rock, Vector3(0.0, 0.06, 0.0))
	_eyes(head, 0.17, accent if lava else Color("e8e8d0"), lava, 1.0, 0.45)
	if lava:
		for i in 5:  # retakan menyala di dada
			var a := -0.5 + i * 0.25
			box(body, Vector3(0.05, 0.4, 0.02), Vector3(a, 0.88, 0.26), accent, Vector3(0, 0, a * 0.9), true)
		box(body, Vector3(0.7, 0.04, 0.02), Vector3(0, 0.9, 0.26), accent, Vector3.ZERO, true)
	else:
		for i in 6:  # lumut di bahu dan kepala
			var a2 := (i - 2.5) * 0.14
			box(body, Vector3(0.14, 0.04, 0.14), Vector3(a2, 1.25 - 0.02 * i, 0.12 * ((i % 3) - 1)), accent)
		box(head, Vector3(0.22, 0.04, 0.2), Vector3(0.05, 0.36, 0.0), accent)
	return pv


static func _quad(root: Node3D, o: Dictionary) -> Dictionary:
	var c: Color = o.body
	var belly: Color = o.belly
	var len := float(o.len)
	var wid := float(o.wid)
	var hgt := float(o.hgt)
	var leg_len := float(o.leg_len)
	var hr := float(o.head_r)
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var by := leg_len + hgt * 0.8
	ball(body, 1.0, Vector3(0, by, 0), c, Vector3(wid, hgt, len))
	ball(body, 1.0, Vector3(0, by - hgt * 0.35, 0.02), belly, Vector3(wid * 0.9, hgt * 0.7, len * 0.9))
	var head := pivot(body, "head", Vector3(0, by + hgt * 0.35, len * 0.85))
	pv["head"] = head
	ball(head, hr, Vector3(0, 0, 0), c)
	_eyes(head, hr * 0.9, Color("1a1a1a"), false, 0.75, 0.55)
	match str(o.snout):
		"cone":
			cone(head, hr * 0.7, hr * 1.6, Vector3(0, -hr * 0.1, hr * 1.0), c, Vector3(PI / 2.0, 0, 0))
		"long":
			box(head, Vector3(hr * 0.9, hr * 0.8, hr * 2.0), Vector3(0, -hr * 0.2, hr * 1.5), belly)
			ball(head, hr * 0.18, Vector3(0, -hr * 0.05, hr * 2.5), Color("202020"))
		"boar":
			cyl(head, hr * 0.55, hr * 0.65, hr * 1.0, Vector3(0, -hr * 0.2, hr * 1.2), Color("8a6a5a"), Vector3(PI / 2.0, 0, 0))
			for s in [-1.0, 1.0]:
				cone(head, hr * 0.14, hr * 1.0, Vector3(s * hr * 0.55, -hr * 0.45, hr * 1.35), Color("f0e8d0"), Vector3(0.4, 0, s * 0.2))
	for s2 in [-1.0, 1.0]:
		if str(o.ears) == "round":
			ball(head, hr * 0.55, Vector3(s2 * hr * 0.75, hr * 0.85, -hr * 0.2), belly, Vector3(1.0, 1.0, 0.3))
		else:
			cone(head, hr * 0.35, hr * 1.0, Vector3(s2 * hr * 0.6, hr * 1.1, -hr * 0.2), c)
	var tail := pivot(body, "tail", Vector3(0, by + hgt * 0.2, -len * 0.95))
	pv["tail"] = tail
	match str(o.tail):
		"thin":
			cyl(tail, 0.012, 0.025, 0.5, Vector3(0, 0, -0.25), Color("d8a898"), Vector3(PI / 2.0 + 0.2, 0, 0))
		"bushy":
			ball(tail, 0.1, Vector3(0, -0.02, -0.18), c, Vector3(0.8, 0.8, 2.2))
		"curl":
			ball(tail, 0.05, Vector3(0, 0.06, -0.05), Color("7a5a44"))
	var legs := {"leg_fl": Vector2(-1, 1), "leg_fr": Vector2(1, 1), "leg_bl": Vector2(-1, -1), "leg_br": Vector2(1, -1)}
	for nm: String in legs:
		var d: Vector2 = legs[nm]
		var leg := pivot(body, nm, Vector3(d.x * wid * 0.6, leg_len + hgt * 0.2, d.y * len * 0.55))
		pv[nm] = leg
		box(leg, Vector3(0.07 + wid * 0.12, leg_len + hgt * 0.2, 0.07 + wid * 0.12), Vector3(0, -(leg_len + hgt * 0.2) / 2.0, 0), c.darkened(0.15))
	return pv


## Binatang tulang (v0.72.0, Gua Goblin): kerangka binatang yang dibangkitkan kutukan, dari bentuk dasar. Tengkorak
## bermata merah menyala, rahang bergigi, tulang punggung, rongga rusuk, panggul, kaki bertulang dua ruas, dan ekor
## dari ruas tulang. Memakai sendi yang sama dengan _quad (leg_fl.., head, tail) supaya geraknya ikut rig "quad".
const BONE := Color("e8dec6")
const BONE_DARK := Color("1e1612")
const BONE_EYE := Color("ff3020")
## Bentuk tiap jenis binatang kerangka dan palet warna tiap peta (bone = tulang, rib = rusuk, glow = rusuk menyala).
const BONE_SHAPES := {
	"rubah": {"len": 0.32, "wid": 0.13, "hgt": 0.15, "leg_len": 0.22, "head_r": 0.11, "snout": 2.3},
	"babi": {"len": 0.42, "wid": 0.23, "hgt": 0.25, "leg_len": 0.17, "head_r": 0.16, "snout": 1.5, "tusks": true},
	"serigala": {"len": 0.42, "wid": 0.17, "hgt": 0.2, "leg_len": 0.3, "head_r": 0.13, "snout": 2.1},
	"beruang": {"len": 0.52, "wid": 0.3, "hgt": 0.32, "leg_len": 0.34, "head_r": 0.17, "snout": 1.4, "spikes": true},
	"ular": {},
}
const BONE_PALETTES := {
	"tulang": {"bone": Color("e8dec6"), "rib": Color("e8dec6"), "eye": Color("ff3020"), "dark": Color("1e1612"), "glow": false},
	"lava": {"bone": Color("2e2420"), "rib": Color("d83a0c"), "eye": Color("ffd040"), "dark": Color("0a0605"), "glow": true},
	"batu": {"bone": Color("8e8b84"), "rib": Color("6c7f5a"), "eye": Color("ffb040"), "dark": Color("1a1a18"), "glow": false},
	"bayangan": {"bone": Color("3a2c52"), "rib": Color("7a3ae0"), "eye": Color("e090ff"), "dark": Color("08050f"), "glow": true},
}


## Jenis dasar binatang kerangka dari id (mis. "serigala_lava" -> "serigala"), "" bila bukan.
static func _bone_kind(id: String) -> String:
	for k: String in BONE_SHAPES:
		if id.begins_with(k + "_") and BONE_PALETTES.has(id.substr(k.length() + 1)):
			return k
	return ""

static func _bone_beast(root: Node3D, o: Dictionary) -> Dictionary:
	var ln := float(o.len)
	var wid := float(o.wid)
	var hgt := float(o.hgt)
	var leg_len := float(o.leg_len)
	var hr := float(o.head_r)
	var bc: Color = o.get("bone", BONE)
	var dk: Color = o.get("dark", BONE_DARK)
	var ey: Color = o.get("eye", BONE_EYE)
	var rib_c: Color = o.get("rib", bc)
	var rib_glow := bool(o.get("glow", false))
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var by := leg_len + hgt * 0.75
	for i in 9:  # tulang punggung melengkung
		var t := float(i) / 8.0
		var z := lerpf(-ln, ln, t)
		ball(body, 0.05 + wid * 0.12, Vector3(0, by + sin(t * PI) * hgt * 0.25, z), bc, Vector3(1.0, 0.8, 1.2))
	for k in 5:  # rongga rusuk: cincin tulang dari punggung ke dada
		var z2 := lerpf(-ln * 0.15, ln * 0.7, float(k) / 4.0)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.85
		ring.outer_radius = 1.0
		ring.rings = 12
		ring.ring_segments = 5
		var rib := _mi(body, ring, Vector3(0, by - hgt * 0.35, z2), rib_c, Vector3(PI / 2.0, 0, 0), rib_glow)
		var shrink := 1.0 - absf(float(k) - 2.0) * 0.12
		rib.scale = Vector3(wid * shrink, 1.0 / 0.15 * 0.03, hgt * 0.75 * shrink)
	box(body, Vector3(wid * 1.3, hgt * 0.35, ln * 0.3), Vector3(0, by - hgt * 0.1, -ln * 0.8), bc)  # panggul
	var head := pivot(body, "head", Vector3(0, by + hgt * 0.35, ln * 1.05))
	pv["head"] = head
	ball(head, hr, Vector3(0, 0, 0), bc, Vector3(0.8, 0.75, 0.95))  # tempurung
	var sn := float(o.snout)
	box(head, Vector3(hr * 1.0, hr * 0.55, hr * sn), Vector3(0, -hr * 0.2, hr * (0.55 + sn * 0.5)), bc)  # moncong
	box(head, Vector3(hr * 0.9, hr * 0.18, hr * sn * 0.95), Vector3(0, -hr * 0.62, hr * (0.5 + sn * 0.5)), bc, Vector3(0.18, 0, 0))  # rahang
	for i2 in 5:  # gigi
		var tz := hr * (0.75 + sn * 0.8) - i2 * hr * sn * 0.16
		for sx in [-1.0, 1.0]:
			cone(head, hr * 0.06, hr * 0.22, Vector3(sx * hr * 0.38, -hr * 0.5, tz), bc, Vector3(PI, 0, 0))
	for s in [-1.0, 1.0]:
		ball(head, hr * 0.22, Vector3(s * hr * 0.36, hr * 0.12, hr * 0.62), dk)  # rongga mata
		ball(head, hr * 0.12, Vector3(s * hr * 0.37, hr * 0.12, hr * 0.74), ey, Vector3.ONE, true)  # mata menyala
		cone(head, hr * 0.22, hr * 0.7, Vector3(s * hr * 0.55, hr * 0.85, -hr * 0.2), bc, Vector3(-0.3, 0, -s * 0.35))  # telinga/tanduk
	ball(head, hr * 0.12, Vector3(0, -hr * 0.05, hr * (0.6 + sn)), dk)  # lubang hidung
	if bool(o.get("tusks", false)):  # taring babi melengkung ke atas
		for s3 in [-1.0, 1.0]:
			cone(head, hr * 0.12, hr * 0.9, Vector3(s3 * hr * 0.5, -hr * 0.3, hr * (0.4 + sn * 0.8)), bc, Vector3(0.5, 0, s3 * 0.35))
	if bool(o.get("spikes", false)):
		for i3 in 4:  # duri tulang di punggung beruang
			cone(body, wid * 0.12, hgt * 0.7, Vector3(0, by + hgt * 0.5, lerpf(-ln * 0.4, ln * 0.6, float(i3) / 3.0)), bc, Vector3(-0.25, 0, 0))
	var tail := pivot(body, "tail", Vector3(0, by, -ln * 1.05))
	pv["tail"] = tail
	for i4 in 5:
		ball(tail, 0.04 + wid * 0.08 - i4 * 0.008, Vector3(0, -i4 * 0.03, -0.06 - i4 * 0.08), bc)
	var legs := {"leg_fl": Vector2(-1, 1), "leg_fr": Vector2(1, 1), "leg_bl": Vector2(-1, -1), "leg_br": Vector2(1, -1)}
	for nm: String in legs:
		var d: Vector2 = legs[nm]
		var top := leg_len + hgt * 0.3
		var leg := pivot(body, nm, Vector3(d.x * wid * 0.75, top, d.y * ln * 0.6))
		pv[nm] = leg
		var r := 0.025 + wid * 0.08
		ball(leg, r * 1.5, Vector3(0, 0, 0), bc)                                 # sendi bahu/pinggul
		cyl(leg, r, r * 0.9, top * 0.52, Vector3(0, -top * 0.26, 0), bc)        # tulang atas
		ball(leg, r * 1.25, Vector3(0, -top * 0.52, 0), bc)                     # lutut
		cyl(leg, r * 0.85, r * 0.75, top * 0.46, Vector3(0, -top * 0.76, 0.0), bc)  # tulang bawah
		box(leg, Vector3(r * 3.0, r * 1.2, r * 3.6), Vector3(0, -top + r * 0.6, r * 0.9), bc)  # cakar
	return pv


## Ular tulang (v0.73.0): ruas tulang belakang dengan sepasang rusuk kecil di tiap ruas, tengkorak bertaring, mata
## merah menyala. Sendinya sama dengan _snake (seg_0..seg_9) supaya meliuk dengan rig "snake".
static func _bone_snake(root: Node3D, pal: Dictionary = {}) -> Dictionary:
	var bc: Color = pal.get("bone", BONE)
	var dk: Color = pal.get("dark", BONE_DARK)
	var ey: Color = pal.get("eye", BONE_EYE)
	var rib_c: Color = pal.get("rib", bc)
	var rib_glow := bool(pal.get("glow", false))
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var parent: Node3D = body
	for i in 10:
		var seg := pivot(parent, "seg_%d" % i, Vector3(0, 0.1, 0.5) if i == 0 else Vector3(0, 0, -0.17))
		pv["seg_%d" % i] = seg
		var r := 0.075 - i * 0.005
		ball(seg, r, Vector3.ZERO, bc, Vector3(1.0, 0.9, 1.15))
		if i > 0 and i < 9:
			for s in [-1.0, 1.0]:
				_mi(seg, _cone_mesh(r * 0.35, r * 2.4), Vector3(s * r * 1.3, -r * 0.3, 0), rib_c, Vector3(0, 0, -s * 1.9), rib_glow)
		parent = seg
	var head: Node3D = pv.seg_0
	ball(head, 0.11, Vector3(0, 0.02, 0.1), bc, Vector3(0.9, 0.65, 1.35))  # tengkorak pipih
	for s2 in [-1.0, 1.0]:
		ball(head, 0.035, Vector3(s2 * 0.05, 0.06, 0.16), dk)
		ball(head, 0.02, Vector3(s2 * 0.05, 0.065, 0.185), ey, Vector3.ONE, true)
		cone(head, 0.015, 0.09, Vector3(s2 * 0.035, -0.04, 0.22), bc, Vector3(PI, 0, 0))  # taring
	return pv


static func _snake(root: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	var parent: Node3D = body
	var green := Color("6a9a3a")
	for i in 10:
		var seg := pivot(parent, "seg_%d" % i, Vector3(0, 0.12, 0.5) if i == 0 else Vector3(0, 0, -0.17))
		pv["seg_%d" % i] = seg
		var r := 0.12 - i * 0.008
		ball(seg, r, Vector3.ZERO, green.lerp(Color("c8b838"), 0.0 if i % 2 == 0 else 0.35), Vector3(1.0, 0.9, 1.3))
		parent = seg
	var head: Node3D = pv.seg_0
	ball(head, 0.14, Vector3(0, 0.02, 0.1), green.darkened(0.1), Vector3(1.0, 0.8, 1.3))
	_eyes(head, 0.14, Color("f0d020"), false, 1.2, 0.8)
	box(head, Vector3(0.02, 0.01, 0.12), Vector3(0, -0.02, 0.32), Color("d02020"))  # lidah
	return pv


static func _hopper(root: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var green := Color("7ab83a")
	var body := pivot(root, "body", Vector3.ZERO)
	pv["body"] = body
	ball(body, 1.0, Vector3(0, 0.34, 0), green, Vector3(0.14, 0.14, 0.4))
	ball(body, 0.13, Vector3(0, 0.4, 0.42), green.lightened(0.1))
	for s in [-1.0, 1.0]:
		ball(body, 0.07, Vector3(s * 0.1, 0.5, 0.48), Color("e8e8c0"))  # mata besar
		ball(body, 0.03, Vector3(s * 0.11, 0.5, 0.54), Color("101010"))
		box(body, Vector3(0.015, 0.015, 0.4), Vector3(s * 0.05, 0.62, 0.62), Color("5a7a2a"), Vector3(-0.5, 0, s * 0.2))  # sungut
		box(body, Vector3(0.14, 0.015, 0.45), Vector3(s * 0.09, 0.46, -0.05), Color("a8d868"), Vector3(0, s * 0.1, 0))  # sayap
		var nm := "leg_l" if s < 0.0 else "leg_r"
		var leg := pivot(body, nm, Vector3(s * 0.12, 0.3, -0.15))
		pv[nm] = leg
		box(leg, Vector3(0.05, 0.4, 0.06), Vector3(0, 0.1, -0.12), green.darkened(0.1), Vector3(0.9, 0, 0))
		box(leg, Vector3(0.04, 0.34, 0.05), Vector3(0, -0.18, -0.3), green.darkened(0.2), Vector3(-0.3, 0, 0))
		for k in [-0.1, 0.1]:  # kaki depan kecil
			box(body, Vector3(0.035, 0.25, 0.035), Vector3(s * 0.1, 0.2, 0.3 + k), green.darkened(0.2))
	return pv


static func _bat(root: Node3D) -> Dictionary:
	var pv: Dictionary = {}
	var fur := Color("3a2f45")
	var body := pivot(root, "body", Vector3(0, 0.7, 0))
	pv["body"] = body
	ball(body, 0.14, Vector3.ZERO, fur, Vector3(1.0, 1.0, 1.3))
	var head := pivot(body, "head", Vector3(0, 0.08, 0.18))
	pv["head"] = head
	ball(head, 0.1, Vector3.ZERO, fur.lightened(0.05))
	_eyes(head, 0.1, Color("ff3030"), true, 0.9, 0.5)
	for s in [-1.0, 1.0]:
		cone(head, 0.04, 0.12, Vector3(s * 0.06, 0.12, -0.02), fur)
		var nm := "wing_l" if s < 0.0 else "wing_r"
		var wing := pivot(body, nm, Vector3(s * 0.1, 0.03, 0))
		pv[nm] = wing
		box(wing, Vector3(0.4, 0.015, 0.26), Vector3(s * 0.22, 0, -0.02), Color("55406a"))
		box(wing, Vector3(0.25, 0.012, 0.2), Vector3(s * 0.5, 0, -0.04), Color("55406a"), Vector3(0, s * 0.3, 0))
		box(wing, Vector3(0.5, 0.02, 0.03), Vector3(s * 0.28, 0.01, 0.1), fur)
	return pv
