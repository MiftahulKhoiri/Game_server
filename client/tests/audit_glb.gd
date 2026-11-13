extends SceneTree
## Alat pengembang (v0.78.0): daftar klip animasi dan rangka setiap model GLB, untuk docs/AI_HYBRID.md.
## Jalankan: godot --headless --path client -s res://tests/audit_glb.gd   (tidak ikut ke APK)

func _init() -> void:
	var dir := DirAccess.open("res://assets/models")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			files.append(f)
	files.sort()
	print("| Model | Tulang | Klip |")
	print("|-------|--------|------|")
	for f in files:
		var scene := load("res://assets/models/" + f) as PackedScene
		if scene == null:
			print("| %s | ? | (gagal dimuat) |" % f)
			continue
		var inst := scene.instantiate()
		var bones := 0
		var clips: PackedStringArray = []
		for n in inst.find_children("*", "Skeleton3D", true, false):
			bones = maxi(bones, (n as Skeleton3D).get_bone_count())
		for n in inst.find_children("*", "AnimationPlayer", true, false):
			for a in (n as AnimationPlayer).get_animation_list():
				clips.append(a)
		print("| %s | %d | %s |" % [f.get_basename(), bones, ", ".join(clips) if not clips.is_empty() else "-"])
		inst.free()
	quit()
