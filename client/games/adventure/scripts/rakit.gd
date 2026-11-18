extends RefCounted
## Perakit mesh berwarna titik (paket adventure 1.3.0). Bentuk dasar (kotak, silinder, bola, cincin) dengan
## warnanya sendiri dikumpulkan lalu dijadikan SATU mesh per kelompok:
##   "padat"  - bahan biasa, berbayangan        "rata" - bahan biasa, tanpa bayangan (karpet, retakan)
##   "pendar" - bahan menyala (warna = cahaya)  "logam" - kilau logam (emas)
## Jadi hiasan sebanyak apa pun = beberapa panggilan gambar (dulu: satu per bahan per sel 12 m). Dipakai
## istana_dekor.gd dan gunung_dekor.gd. Warna disimpan di COLOR tiap titik; bahan dibagi antar peta.

static var _mats: Dictionary = {}

var _st: Dictionary = {}    # kelompok -> SurfaceTool
var _n: Dictionary = {}     # kelompok -> jumlah bentuk


static func bahan(kelompok: String) -> StandardMaterial3D:
	if _mats.has(kelompok):
		return _mats[kelompok]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	match kelompok:
		"pendar":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # warna penuh tanpa terang-gelap = tampak menyala
		"logam":
			m.metallic = 0.6
			m.roughness = 0.35
	_mats[kelompok] = m
	return m


## Tambahkan bentuk `mesh` (satu permukaan) dengan transformasi `xf` dan warna `warna` ke `kelompok`.
func tambah(mesh: Mesh, xf: Transform3D, warna: Color, kelompok := "padat") -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	if not _st.has(kelompok):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[kelompok] = st
		_n[kelompok] = 0
	var st2: SurfaceTool = _st[kelompok]
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	var ada_normal := nr.size() == v.size()
	if idx.is_empty():
		idx.resize(v.size())
		for i in v.size():
			idx[i] = i
	for i in idx:
		st2.set_color(warna)
		if ada_normal:
			st2.set_normal((nb * nr[i]).normalized())
		st2.add_vertex(xf * v[i])
	_n[kelompok] = int(_n[kelompok]) + 1


## Bentuk siap pakai: posisi + putaran (radian) + skala.
func bentuk(mesh: Mesh, pos: Vector3, warna: Color, kelompok := "padat", rot := Vector3.ZERO, skala := Vector3.ONE) -> void:
	tambah(mesh, Transform3D(Basis.from_euler(rot) * Basis.from_scale(skala), pos), warna, kelompok)


func jumlah() -> int:
	var t := 0
	for k: String in _n:
		t += int(_n[k])
	return t


## Jadikan mesh dan pasang di `root`. Node bernama (tidak digabung ulang MeshMerge), tanpa batas jarak gambar.
func pasang(root: Node3D, nama: String) -> void:
	for k: String in _st:
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [nama, k]
		mi.mesh = (_st[k] as SurfaceTool).commit()
		mi.material_override = bahan(k)
		if k != "padat" and k != "logam":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_st.clear()
