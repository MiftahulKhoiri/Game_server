extends RefCounted
## Menggabungkan benda kecil statis yang dirakit dari bentuk dasar (kotak, silinder, bola, prisma, bidang)
## menjadi beberapa mesh besar per bahan dan per sel peta (perbaikan dari uji Samsung A50).
##
## Dulu tiap tiang lampu, lentera, papan, lapak, peti kayu, dsb. adalah MeshInstance3D sendiri sehingga
## digambar satu per satu (±400 bentuk di Desa). Setelah digabung, satu bahan di satu sel = satu panggilan
## gambar. Bahan tetap objek yang sama, jadi perubahan bahan saat malam (lampu menyala) tetap berlaku.
##
## Yang TIDAK digabung (bisa bergerak/diubah kode lain): node bernama (bukan "@..."), node berskrip,
## node yang punya anak, bahan transparan, node tak terlihat, dan isi cabang ber-meta "no_merge".

const SEL := 12.0   # ukuran sel (meter); sel di luar layar tetap tidak digambar

const PRIMS := ["BoxMesh", "CylinderMesh", "SphereMesh", "PrismMesh", "PlaneMesh", "CapsuleMesh", "QuadMesh", "TorusMesh"]


## Gabungkan di bawah `root` (boleh belum masuk pohon adegan). Mengembalikan jumlah bentuk yang digabung.
static func merge(root: Node3D, visibility_end := 0.0) -> int:
	var groups := {}  # kunci -> {mat, shadow, st: SurfaceTool, n}
	_collect(root, Transform3D.IDENTITY, groups)
	for key: String in groups:
		var g: Dictionary = groups[key]
		if int(g.n) < 2:
			continue  # satu bentuk saja: tidak ada untungnya, biarkan apa adanya
		var st: SurfaceTool = g.st
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Gabungan"
		mi.mesh = mesh
		mi.material_override = g.mat
		mi.cast_shadow = g.shadow
		if visibility_end > 0.0:
			mi.visibility_range_end = visibility_end
		root.add_child(mi)
		for v: Node in g.nodes:
			v.get_parent().remove_child(v)
			v.free()
	var merged := 0
	for key: String in groups:
		if int(groups[key].n) >= 2:
			merged += int(groups[key].n)
	root.set_meta("digabung", merged)
	return merged


static func _collect(node: Node, xf: Transform3D, groups: Dictionary) -> void:
	for c in node.get_children():
		if not (c is Node3D):
			continue
		var n3 := c as Node3D
		if not n3.visible or n3.has_meta("no_merge") or n3.get_script() != null:
			continue
		var cxf := xf * n3.transform
		if not str(n3.name).begins_with("@"):
			continue  # node bernama mungkin dicari/diubah kode lain
		if n3 is MeshInstance3D and n3.get_child_count() == 0:
			_take(n3 as MeshInstance3D, cxf, groups)
		elif n3.get_class() == "Node3D":
			_collect(n3, cxf, groups)


static func _take(mi: MeshInstance3D, xf: Transform3D, groups: Dictionary) -> void:
	var mesh := mi.mesh
	if mesh == null or not (mesh.get_class() in PRIMS) or mesh.get_surface_count() != 1:
		return
	if mi.skeleton != NodePath("") and mi.skin != null:
		return
	var m: Material = mi.material_override
	if m == null:
		m = mi.get_surface_override_material(0)
	if m == null:
		m = mesh.surface_get_material(0)
	if m == null or not (m is StandardMaterial3D):
		return
	var sm := m as StandardMaterial3D
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	if mi.visibility_range_end > 0.0:
		return
	var o := xf.origin
	var key := "%d|%d|%d|%d" % [m.get_instance_id(), mi.cast_shadow, floori(o.x / SEL), floori(o.z / SEL)]
	if not groups.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[key] = {"mat": m, "shadow": mi.cast_shadow, "st": st, "n": 0, "nodes": []}
	var g: Dictionary = groups[key]
	(g.st as SurfaceTool).append_from(mesh, 0, xf)
	g.n = int(g.n) + 1
	(g.nodes as Array).append(mi)
