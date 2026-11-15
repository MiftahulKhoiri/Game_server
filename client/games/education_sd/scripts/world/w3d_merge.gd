extends RefCounted
## Optimasi Fase 8: gabungkan mesh statis satu bangunan/lokasi menjadi satu MeshInstance3D (satu surface per
## material). Hasil ukur di Pi: draw call alun-alun Seimbang turun dari ±400. Node yang bergerak (benda
## bergoyang, planet, hewan, warga, tutup peti, jeruji gerbang) dilewati supaya animasinya tetap jalan.



static func merge(root: Node3D, skip: Array, range_end := 0.0) -> int:
	var groups := {}  # Material -> SurfaceTool
	var victims: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not _mergeable(mi, root, skip):
			continue
		var mat: Material = (mi as MeshInstance3D).material_override
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mat == null or mesh == null or mesh.get_surface_count() != 1:
			continue
		var xf := xf_to(root, mi)
		if not groups.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[mat] = st
		(groups[mat] as SurfaceTool).append_from(mesh, 0, xf)
		victims.append(mi)
	if victims.size() < 2:
		return 0
	var am := ArrayMesh.new()
	var mats: Array = []
	for mat in groups:
		(groups[mat] as SurfaceTool).commit(am)
		mats.append(mat)
	for i in mats.size():
		am.surface_set_material(i, mats[i])
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = am
	out.visibility_range_end = range_end
	root.add_child(out)
	for v in victims:
		v.get_parent().remove_child(v)
		v.free()
	return victims.size()


static func _mergeable(n: Node, root: Node, skip: Array) -> bool:
	if not (n as MeshInstance3D).visible or n.has_meta("water"):
		return false
	var cur := n
	while cur != null and cur != root:
		if skip.has(cur) or cur.has_meta("rig") or cur.has_meta("animated") or cur is CPUParticles3D:
			return false
		if cur is Node3D and cur.get_script() != null and cur != n:
			return false  # bagian dari karakter (rig) atau objek bernaskah lain
		cur = cur.get_parent()
	return true


static func xf_to(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D()
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
