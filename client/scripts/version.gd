extends RefCounted
## Versi aplikasi dan perbandingan versi. Aturan: docs/VERSIONING.md
##
## Sumber nomor versi: `config/version` di project.godot (format MAJOR.MINOR.PATCH).
## Nomor build dan commit diisi CI ke scripts/build_info.gd.

const BuildInfo = preload("res://scripts/build_info.gd")


## Contoh: "0.2.0"
static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Contoh: "v0.2.0 (build 12)", atau "v0.2.0 (dev)" untuk build lokal.
static func app_label() -> String:
	if BuildInfo.BUILD > 0:
		return "v%s (build %d)" % [app_version(), BuildInfo.BUILD]
	return "v%s (dev)" % app_version()


## -1 bila a < b, 0 bila sama, 1 bila a > b. Bagian yang tidak valid dianggap 0.
static func compare(a: String, b: String) -> int:
	var pa := _parse(a)
	var pb := _parse(b)
	for i in 3:
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0


static func _parse(v: String) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	var parts := v.strip_edges().trim_prefix("v").split(".")
	for i in mini(3, parts.size()):
		out[i] = int(parts[i]) if parts[i].is_valid_int() else 0
	return out
