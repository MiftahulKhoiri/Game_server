extends RefCounted
## Lokasi tambahan per pulau (Fase 3). Setiap lokasi bisa dikunjungi (zona kunjungan), punya papan aktivitas
## (teka-teki 3 soal dari topik wilayah sesuai kelas) dan bisa punya aktivitas tambahan:
##   museum   = lihat kartu pengetahuan wilayah yang sudah didapat
##   hewan    = lihat fakta hewan dari koleksi hewan
##   minigame = mini-game wilayah
##   warga    = warga desa yang meminta bantuan (misi NPC)
## Bentuk bangunan dibuat dari mesh primitif low-poly (lihat docs/SD_PULAU_ILMU_3D.md, Fase 5).

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")

## Lima slot di alun-alun besar (pulau dibesarkan di Fase 3).
const SLOTS := [Vector3(-17, 0, 21), Vector3(17, 0, 21), Vector3(-17, 0, 4), Vector3(17, 0, 4), Vector3(0, 0, 27)]

const DEFS := {
	"matematika": [
		{"id": "gua_angka", "name": "Gua Teka-Teki Angka", "build": "cave", "desc": "Pintu gua terbuka bagi yang pandai berhitung."},
		{"id": "menara", "name": "Menara Matematika", "build": "tower", "desc": "Penjaga menara menyiapkan soal di setiap lantai."},
		{"id": "labirin", "name": "Labirin Matematika", "build": "maze", "desc": "Cari jalan ke tengah labirin, lalu pecahkan teka-teki di sana."},
		{"id": "jembatan_angka", "name": "Jembatan Angka", "build": "stones", "desc": "Lompati batu-batu angka di atas kolam!"},
		{"id": "desa_angka", "name": "Desa Penduduk", "build": "village", "desc": "Pak Hitung butuh bantuanmu menghitung panen.", "villager": "Pak Hitung"},
	],
	"bahasa": [
		{"id": "perpustakaan", "name": "Perpustakaan Alam", "build": "hall", "desc": "Rak buku dari akar pohon. Kartu pengetahuanmu dipajang di sini.", "extra": "museum"},
		{"id": "desa_hewan", "name": "Desa Hewan", "build": "village", "desc": "Bu Rusa ingin menulis surat, tapi hurufnya tercampur.", "villager": "Bu Rusa", "extra": "hewan"},
		{"id": "sungai_huruf", "name": "Sungai Huruf", "build": "river", "desc": "Huruf-huruf hanyut di sungai. Susun kembali katanya!"},
		{"id": "gua_kata", "name": "Gua Kata", "build": "cave", "desc": "Gema gua hanya menjawab kalimat yang benar."},
		{"id": "pohon_cerita", "name": "Pohon Cerita", "build": "bigtree", "desc": "Setiap daun menyimpan sebuah cerita."},
	],
	"ipa": [
		{"id": "kebun", "name": "Kebun Percobaan", "build": "garden", "desc": "Tanaman tumbuh bila pertanyaannya terjawab."},
		{"id": "lab_eksperimen", "name": "Laboratorium Eksperimen", "build": "lab", "desc": "Campurkan pengetahuan, bukan bahan berbahaya!"},
		{"id": "danau", "name": "Danau Ekosistem", "build": "lake", "desc": "Ikan, katak, dan tumbuhan air hidup bersama."},
		{"id": "hutan_hewan", "name": "Hutan Hewan", "build": "animals", "desc": "Kenali hewan yang tinggal di sini.", "extra": "hewan", "villager": "Peneliti Ana"},
		{"id": "tata_surya", "name": "Area Tata Surya", "build": "solar", "desc": "Planet-planet berputar mengelilingi matahari."},
	],
	"ips": [
		{"id": "museum", "name": "Museum Nusantara", "build": "hall", "desc": "Benda bersejarah dan kartu pengetahuanmu dipajang di sini.", "extra": "museum"},
		{"id": "pelabuhan", "name": "Pelabuhan", "build": "harbor", "desc": "Kapal datang membawa barang dari pulau lain."},
		{"id": "pasar", "name": "Pasar Tradisional", "build": "market", "desc": "Pedagang menawarkan hasil bumi dari seluruh Nusantara.", "extra": "minigame", "villager": "Mbok Sari"},
		{"id": "desa_adat", "name": "Desa Rumah Adat", "build": "houses", "desc": "Rumah adat dari berbagai daerah berdiri di sini."},
		{"id": "sejarah", "name": "Area Sejarah Indonesia", "build": "monument", "desc": "Tugu ini mengingatkan perjuangan para pahlawan."},
	],
}


static func for_region(region_id: String) -> Array:
	return DEFS.get(region_id, [])


static func find(region_id: String, loc_id: String) -> Dictionary:
	for d in for_region(region_id):
		if str(d.id) == loc_id:
			return d
	return {}


## Indeks lokasi menentukan topik teka-tekinya (berputar di topik kelas aktif).
static func index_of(region_id: String, loc_id: String) -> int:
	var defs := for_region(region_id)
	for i in defs.size():
		if str(defs[i].id) == loc_id:
			return i
	return -1


# --- Pembangun bangunan ---------------------------------------------------------------------------------
# w = node dunia (w3d_world.gd): memakai w._label(), w._static_box_at(), w.add_life().
# root = Node3D lokasi (posisi slot). Mengembalikan posisi lokal papan aktivitas.

static func build(w: Node3D, root: Node3D, def: Dictionary, accent: Color, crown: Color) -> Vector3:
	match str(def.build):
		"cave":
			return _cave(w, root)
		"tower":
			return _tower(w, root, accent)
		"maze":
			return _maze(w, root, crown)
		"stones":
			return _stones(w, root)
		"village":
			return _village(w, root, accent)
		"hall":
			return _hall(w, root, accent)
		"river":
			return _river(w, root)
		"bigtree":
			return _bigtree(w, root, crown)
		"garden":
			return _garden(w, root)
		"lab":
			return _lab(w, root)
		"lake":
			return _lake(w, root)
		"animals":
			return _animals(w, root, crown)
		"solar":
			return _solar(w, root)
		"harbor":
			return _harbor(w, root)
		"market":
			return _market(w, root)
		"houses":
			return _houses(w, root)
		"monument":
			return _monument(w, root)
	return Vector3.ZERO


static func _m(mesh: Mesh, c: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	return Rig.part(mesh, c, pos, scl)


static func _cave(w: Node3D, root: Node3D) -> Vector3:
	root.add_child(_m(Rig.sphere(5.0), Color("8a8174"), Vector3(0, 0, -1.5), Vector3(1.3, 0.85, 1.0)))
	root.add_child(_m(Rig.sphere(2.0), Color("2b2440"), Vector3(0, 0.6, 3.1), Vector3(1.0, 1.1, 0.5)))
	for i in 5:
		root.add_child(_m(Rig.sphere(0.9), Color("a39a8c"), Vector3(-4.5 + i * 2.2, 0.3, 3.6 + (i % 2) * 0.5)))
	w._static_cyl_at(root, 5.2, 4.0, Vector3(0, 2, -1.5))
	return Vector3(2.6, 0, 5.0)


static func _tower(w: Node3D, root: Node3D, accent: Color) -> Vector3:
	root.add_child(_m(Rig.cyl(2.4, 2.8, 12.0, 14), Color("f4efff"), Vector3(0, 6, 0)))
	root.add_child(_m(Rig.cyl(0.0, 3.2, 3.6, 14), accent, Vector3(0, 13.8, 0)))
	for k in 4:
		root.add_child(_m(Rig.box(Vector3(0.9, 1.2, 0.2)), Color("8fd0ff"), Vector3(0, 2.5 + k * 2.6, 2.6)))
	root.add_child(_m(Rig.box(Vector3(1.6, 2.4, 0.3)), Color("8a5a2b"), Vector3(0, 1.2, 2.75)))
	w._static_cyl_at(root, 2.8, 12.0, Vector3(0, 6, 0))
	var l: Label3D = w._label("1 2 3 + − × ÷", 64, Color("f0b429"))
	l.position = Vector3(0, 8.0, 2.8)
	root.add_child(l)
	return Vector3(2.2, 0, 4.2)


## Labirin 4x4 (sel 2,6 m) berdinding pagar tanaman 1,7 m. Masuk dari sisi timur sel (3,0), tujuan sel (1,2).
static func _maze(w: Node3D, root: Node3D, crown: Color) -> Vector3:
	var c := 2.6
	var hedge := crown.darkened(0.15)
	var walls := [
		[Vector3(0, 0, -5.2), Vector3(10.4, 0, 0)], [Vector3(0, 0, 5.2), Vector3(10.4, 0, 0)],
		[Vector3(-5.2, 0, 0), Vector3(0, 0, 10.4)], [Vector3(5.2, 0, 1.3), Vector3(0, 0, 7.8)],
		[Vector3(2.6, 0, 1.3), Vector3(0, 0, 7.8)], [Vector3(0, 0, -2.6), Vector3(5.2, 0, 0)],
		[Vector3(-2.6, 0, 0), Vector3(0, 0, 5.2)], [Vector3(-1.3, 0, 2.6), Vector3(2.6, 0, 0)],
		[Vector3(0, 0, -1.3), Vector3(0, 0, 2.6)],
	]
	for wl in walls:
		var at: Vector3 = wl[0]
		var len: Vector3 = wl[1]
		var size := Vector3(maxf(len.x, 0.4) + 0.4, 1.7, maxf(len.z, 0.4) + 0.4)
		w._static_box_at(root, size, at + Vector3(0, 0.85, 0), hedge)
	var goal := Vector3(-c * 0.5, 0, c * 0.5)
	root.add_child(_m(Rig.cyl(0.6, 0.6, 0.2, 12), Color("f0b429"), goal + Vector3(0, 0.1, 0)))
	var l: Label3D = w._label("PINTU MASUK →", 48, Color.WHITE, true)
	l.position = Vector3(6.4, 2.2, -3.9)
	root.add_child(l)
	return goal


static func _stones(w: Node3D, root: Node3D) -> Vector3:
	root.add_child(_m(Rig.cyl(6.5, 6.5, 0.06, 26), Color("5ab8e8"), Vector3(0, 0.04, 0)))
	for i in 7:
		var a := PI * 0.9 - i * PI * 0.8 / 6.0
		var pos := Vector3(cos(a) * 4.2, 0, sin(a) * 4.2 - 0.5)
		var s: StaticBody3D = w._static_cyl_at(root, 0.75, 0.5 + 0.12 * i, pos + Vector3(0, (0.5 + 0.12 * i) / 2.0, 0))
		s.add_child(_m(Rig.cyl(0.75, 0.8, 0.5 + 0.12 * i, 10), Color("b9b3c9"), Vector3.ZERO))
		var l: Label3D = w._label(str((i + 1) * 2), 64, Color("2b2440"))
		l.outline_modulate = Color.WHITE
		l.rotation.x = -PI / 2.0
		l.position = Vector3(0, (0.5 + 0.12 * i) / 2.0 + 0.02, 0)
		s.add_child(l)
	return Vector3(4.4, 0, 3.2)


static func _house(root: Node3D, at: Vector3, wall: Color, roof: Color, rot := 0.0) -> void:
	var h := Node3D.new()
	h.position = at
	h.rotation.y = rot
	h.add_child(_m(Rig.box(Vector3(3.2, 2.4, 3.0)), wall, Vector3(0, 1.2, 0)))
	var pr := PrismMesh.new()
	pr.size = Vector3(3.8, 1.6, 3.4)
	h.add_child(_m(pr, roof, Vector3(0, 3.2, 0)))
	h.add_child(_m(Rig.box(Vector3(0.9, 1.5, 0.1)), Color("8a5a2b"), Vector3(0, 0.75, 1.52)))
	root.add_child(h)


static func _village(w: Node3D, root: Node3D, accent: Color) -> Vector3:
	_house(root, Vector3(-4.5, 0, -2.5), Color("f4e1c1"), Color("c0503a"), 0.3)
	_house(root, Vector3(4.5, 0, -2.5), Color("e8f0d8"), accent, -0.3)
	_house(root, Vector3(0, 0, -5.5), Color("fff3c4"), Color("8a6bd8"))
	for x in [-4.5, 4.5]:
		w._static_box_at(root, Vector3(3.4, 3, 3.2), Vector3(x, 1.5, -2.5), null)
	w._static_box_at(root, Vector3(3.4, 3, 3.2), Vector3(0, 1.5, -5.5), null)
	root.add_child(_m(Rig.cyl(0.9, 1.0, 0.8, 12), Color("8a8174"), Vector3(0, 0.4, 0.8)))
	return Vector3(2.2, 0, 2.8)


static func _hall(w: Node3D, root: Node3D, accent: Color) -> Vector3:
	root.add_child(_m(Rig.box(Vector3(10, 0.4, 7)), Color("e8e2f2"), Vector3(0, 0.2, -1)))
	root.add_child(_m(Rig.box(Vector3(10, 4.5, 0.4)), Color("f4efff"), Vector3(0, 2.6, -4.3)))
	root.add_child(_m(Rig.box(Vector3(11, 0.6, 7.6)), accent, Vector3(0, 5.1, -1)))
	var pr := PrismMesh.new()
	pr.size = Vector3(11, 1.6, 7.6)
	root.add_child(_m(pr, accent.darkened(0.2), Vector3(0, 6.2, -1)))
	for x in [-4.4, -1.5, 1.5, 4.4]:
		root.add_child(_m(Rig.cyl(0.32, 0.36, 4.5, 10), Color.WHITE, Vector3(x, 2.6, 2.0)))
	for k in 6:
		root.add_child(_m(Rig.box(Vector3(1.2, 1.5, 0.08)), [Color("ffd166"), Color("8fd0ff"), Color("c9b2f0")][k % 3],
			Vector3(-3.75 + k * 1.5, 2.4, -4.05)))
	w._static_box_at(root, Vector3(10, 4.5, 0.6), Vector3(0, 2.25, -4.3), null)
	return Vector3(0, 0, 0.5)


static func _river(w: Node3D, root: Node3D) -> Vector3:
	var water := _m(Rig.box(Vector3(3.2, 0.06, 14)), Color("4aa3df"), Vector3(-1.5, 0.04, 0))
	water.set_meta("water", true)
	root.add_child(water)
	var letters := "BACAKATA"
	for i in letters.length():
		var b := Node3D.new()
		b.position = Vector3(-1.5 + (0.6 if i % 2 == 0 else -0.6), 0.3, -6.0 + i * 1.6)
		b.add_child(_m(Rig.box(Vector3(0.8, 0.8, 0.8)), [Color("e05a4f"), Color("3f7fd8"), Color("f0b429"), Color("3fae63")][i % 4], Vector3.ZERO))
		var l: Label3D = w._label(letters[i], 56, Color.WHITE, true)
		l.position.y = 0.75
		b.add_child(l)
		root.add_child(b)
		w.add_life("bob", b)
	return Vector3(2.0, 0, 1.0)


static func _bigtree(w: Node3D, root: Node3D, crown: Color) -> Vector3:
	root.add_child(_m(Rig.cyl(1.4, 2.2, 9.0, 12), Color("7a4a22"), Vector3(0, 4.5, -1)))
	for p in [Vector3(0, 10, -1), Vector3(-2.8, 8.5, -0.5), Vector3(2.8, 8.8, -1.5), Vector3(0, 8.2, 1.6)]:
		root.add_child(_m(Rig.sphere(3.4), crown, p))
	root.add_child(_m(Rig.box(Vector3(0.08, 3.5, 0.08)), Color("5a3a1a"), Vector3(-0.7, 4.6, 2.2)))
	root.add_child(_m(Rig.box(Vector3(0.08, 3.5, 0.08)), Color("5a3a1a"), Vector3(0.7, 4.6, 2.2)))
	root.add_child(_m(Rig.box(Vector3(1.6, 0.12, 0.5)), Color("c98a4b"), Vector3(0, 2.85, 2.2)))
	w._static_cyl_at(root, 2.2, 9.0, Vector3(0, 4.5, -1))
	return Vector3(2.6, 0, 2.6)


static func _garden(w: Node3D, root: Node3D) -> Vector3:
	for r in 3:
		for k in 4:
			var at := Vector3(-4.5 + k * 3.0, 0, -3.5 + r * 2.6)
			root.add_child(_m(Rig.box(Vector3(2.4, 0.3, 1.8)), Color("7a5a3a"), at + Vector3(0, 0.15, 0)))
			var h := 0.6 + float((r * 4 + k) % 3) * 0.35
			root.add_child(_m(Rig.cyl(0.06, 0.08, h, 6), Color("3fae63"), at + Vector3(0, 0.3 + h / 2.0, 0)))
			root.add_child(_m(Rig.sphere(0.35), [Color("e05a4f"), Color("f0b429"), Color("c9b2f0")][(r + k) % 3], at + Vector3(0, 0.35 + h, 0)))
	return Vector3(0, 0, 3.2)


static func _lab(w: Node3D, root: Node3D) -> Vector3:
	root.add_child(_m(Rig.cyl(4.5, 4.5, 3.4, 18), Color("e8eef5"), Vector3(0, 1.7, -2)))
	root.add_child(_m(Rig.sphere(4.5), Color("9fe3ff"), Vector3(0, 3.3, -2), Vector3(1, 0.55, 1)))
	root.add_child(_m(Rig.box(Vector3(4.0, 0.9, 1.2)), Color("dfe8ef"), Vector3(0, 0.45, 3.0)))
	for i in 4:
		var fl := _m(Rig.sphere(0.32), [Color("ff7eb6"), Color("7ee0ff"), Color("b6ff7e"), Color("ffd166")][i], Vector3(-1.5 + i, 1.25, 3.0))
		root.add_child(fl)
		w.add_life("bubble", fl)
	w._static_cyl_at(root, 4.5, 3.4, Vector3(0, 1.7, -2))
	w._static_box_at(root, Vector3(4.0, 0.9, 1.2), Vector3(0, 0.45, 3.0), null)
	return Vector3(2.8, 0, 4.4)


static func _lake(w: Node3D, root: Node3D) -> Vector3:
	var water := _m(Rig.cyl(6.0, 6.0, 0.06, 26), Color("4aa3df"), Vector3(0, 0.04, -0.5))
	water.set_meta("water", true)
	root.add_child(water)
	for i in 5:
		var a := TAU * i / 5.0
		root.add_child(_m(Rig.cyl(0.04, 0.06, 1.4, 5), Color("3f8f4a"), Vector3(cos(a) * 6.2, 0.7, sin(a) * 6.2 - 0.5)))
	for i in 3:
		root.add_child(_m(Rig.cyl(0.8, 0.8, 0.05, 10), Color("5aa84a"), Vector3(-2.0 + i * 2.0, 0.09, -1.0 + (i % 2) * 1.6)))
	for i in 3:
		var fish := Node3D.new()
		fish.position = Vector3(-2.5 + i * 2.5, 0, -0.5)
		fish.add_child(_m(Rig.capsule(0.16, 0.6), [Color("ff9f43"), Color("f0b429"), Color("e05a4f")][i], Vector3.ZERO, Vector3(1, 1, 1)))
		(fish.get_child(0) as Node3D).rotation.z = PI / 2.0
		fish.visible = false
		root.add_child(fish)
		w.add_life("fish", fish)
	return Vector3(5.0, 0, 5.2)


static func _animals(w: Node3D, root: Node3D, crown: Color) -> Vector3:
	for i in 5:
		root.add_child(_m(Rig.cyl(0.25, 0.32, 2.0, 7), Color("7a4a22"), Vector3(-5 + i * 2.5, 1.0, -5.0 + (i % 2) * 1.2)))
		root.add_child(_m(Rig.sphere(1.5), crown, Vector3(-5 + i * 2.5, 2.8, -5.0 + (i % 2) * 1.2)))
	var cols := [Color("c98a4b"), Color("f4efe6"), Color("8a8174")]
	for i in 3:
		w.add_animal(root, Vector3(-3.0 + i * 3.0, 0, 0), cols[i], 4.0)
	return Vector3(4.6, 0, 3.6)


static func _solar(w: Node3D, root: Node3D) -> Vector3:
	var sun := _m(Rig.sphere(1.4), Color("ffcf3f"), Vector3(0, 2.2, 0))
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("ffcf3f")
	sm.emission_enabled = true
	sm.emission = Color("ffb020")
	sun.material_override = sm
	root.add_child(sun)
	var cols := [Color("b9b3c9"), Color("f0c070"), Color("3f7fd8"), Color("e05a4f"), Color("e0b080"), Color("f0d890"), Color("8fe0e0"), Color("4a6fd8")]
	for i in 8:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 2.2, 0)
		pivot.rotation.y = i * 0.8
		var r := 2.3 + i * 0.75
		pivot.add_child(_m(Rig.sphere(0.18 + (0.25 if i in [4, 5] else 0.08)), cols[i], Vector3(r, 0, 0)))
		root.add_child(pivot)
		w.add_life("orbit", pivot, {"speed": 0.9 / (1.0 + i * 0.6)})
	return Vector3(0, 0, 8.6)


static func _harbor(w: Node3D, root: Node3D) -> Vector3:
	root.add_child(_m(Rig.box(Vector3(3.0, 0.3, 10.0)), Color("b07a45"), Vector3(0, 0.45, -1)))
	for z in [-5.5, -2.5, 0.5, 3.5]:
		for x in [-1.4, 1.4]:
			root.add_child(_m(Rig.cyl(0.14, 0.14, 1.0, 6), Color("5a3a1a"), Vector3(x, 0.3, z)))
	var sea := _m(Rig.box(Vector3(10, 0.06, 9)), Color("4aa3df"), Vector3(0, 0.04, -3))
	sea.set_meta("water", true)
	root.add_child(sea)
	for i in 2:
		var boat := Node3D.new()
		boat.position = Vector3(-3.2 + i * 6.4, 0.2, -3.5)
		boat.add_child(_m(Rig.box(Vector3(1.6, 0.6, 4.0)), Color("8a5a2b"), Vector3(0, 0.3, 0)))
		boat.add_child(_m(Rig.cyl(0.06, 0.06, 3.0, 6), Color("5a3a1a"), Vector3(0, 1.8, 0)))
		boat.add_child(_m(Rig.box(Vector3(0.05, 1.6, 1.6)), [Color.WHITE, Color("e05a4f")][i], Vector3(0, 2.0, 0.2)))
		root.add_child(boat)
		w.add_life("bob", boat)
	w._static_box_at(root, Vector3(3.0, 0.6, 10.0), Vector3(0, 0.3, -1), null)
	return Vector3(2.6, 0, 4.6)


static func _market(w: Node3D, root: Node3D) -> Vector3:
	var palette := [Color("e05a4f"), Color("f0b429"), Color("3fae63"), Color("3f7fd8")]
	for i in 4:
		var st := Node3D.new()
		st.position = Vector3(-4.8 + (i % 2) * 9.6, 0, -3.0 + (i / 2) * 4.0)
		st.rotation.y = PI / 2.0 if i % 2 == 0 else -PI / 2.0
		st.add_child(_m(Rig.box(Vector3(2.6, 1.0, 1.4)), Color("c98a4b"), Vector3(0, 0.5, 0)))
		st.add_child(_m(Rig.box(Vector3(3.0, 0.12, 1.8)), palette[i], Vector3(0, 2.2, 0)))
		for cx in [-1.3, 1.3]:
			st.add_child(_m(Rig.cyl(0.06, 0.06, 2.2, 6), Color("5a3a1a"), Vector3(cx, 1.1, 0.6)))
		for k in 3:
			st.add_child(_m(Rig.sphere(0.22), palette[(i + k + 1) % 4], Vector3(-0.7 + k * 0.7, 1.15, 0)))
		root.add_child(st)
		w._static_box_at(root, Vector3(1.4, 1.0, 2.6), st.position + Vector3(0, 0.5, 0), null)
	return Vector3(0, 0, 3.0)


static func _houses(w: Node3D, root: Node3D) -> Vector3:
	var styles := [[Color("f4e1c1"), Color("a0452e")], [Color("e8d0a0"), Color("5a3a1a")], [Color("fff3c4"), Color("3b5b9a")]]
	for i in 3:
		var at := Vector3(-5.0 + i * 5.0, 0, -2.0 - (i % 2) * 1.5)
		var h := Node3D.new()
		h.position = at
		h.add_child(_m(Rig.box(Vector3(3.6, 0.5, 3.0)), Color("8a5a2b"), Vector3(0, 0.9, 0)))
		for cx in [-1.5, 1.5]:
			for cz in [-1.2, 1.2]:
				h.add_child(_m(Rig.cyl(0.12, 0.12, 1.0, 6), Color("5a3a1a"), Vector3(cx, 0.5, cz)))
		h.add_child(_m(Rig.box(Vector3(3.2, 1.8, 2.6)), styles[i][0], Vector3(0, 2.05, 0)))
		var pr := PrismMesh.new()
		pr.size = Vector3(4.2, 2.4 + i * 0.4, 3.4)
		h.add_child(_m(pr, styles[i][1], Vector3(0, 4.1 + i * 0.2, 0)))
		root.add_child(h)
		w._static_box_at(root, Vector3(3.6, 3.0, 3.0), at + Vector3(0, 1.5, 0), null)
	return Vector3(0, 0, 2.8)


static func _monument(w: Node3D, root: Node3D) -> Vector3:
	root.add_child(_m(Rig.box(Vector3(5, 0.6, 5)), Color("e8e2f2"), Vector3(0, 0.3, -1)))
	root.add_child(_m(Rig.box(Vector3(1.4, 9, 1.4)), Color("f4efff"), Vector3(0, 5.1, -1)))
	var flame := _m(Rig.sphere(0.8), Color("f0b429"), Vector3(0, 10.2, -1), Vector3(1, 1.4, 1))
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("f0b429")
	fm.emission_enabled = true
	fm.emission = Color("ff9020")
	flame.material_override = fm
	root.add_child(flame)
	w.add_life("bob", flame)
	for x in [-3.6, 3.6]:
		root.add_child(_m(Rig.box(Vector3(1.6, 1.2, 0.2)), Color("8a6b3a"), Vector3(x, 0.6, 1.5)))
	w._static_box_at(root, Vector3(5, 0.6, 5), Vector3(0, 0.3, -1), null)
	w._static_box_at(root, Vector3(1.4, 9, 1.4), Vector3(0, 5.1, -1), null)
	return Vector3(2.8, 0, 2.6)
