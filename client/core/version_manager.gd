extends RefCounted
## Versi semantik (MAJOR.MINOR.PATCH) dan pemeriksaan kecocokan game dengan launcher/mesin.
## Dipakai lewat preload (tanpa class_name) agar aman dimuat dari paket game mana pun.

const SEMVER_RE := "^(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})$"


static func is_valid(v: String) -> bool:
	var re := RegEx.new()
	re.compile(SEMVER_RE)
	return re.search(v) != null


## [major, minor, patch]; versi tidak sah -> [] .
static func parse(v: String) -> Array:
	if not is_valid(v):
		return []
	var p := v.split(".")
	return [int(p[0]), int(p[1]), int(p[2])]


## -1 bila a < b, 0 bila sama, 1 bila a > b. Versi tidak sah dianggap paling kecil.
static func compare(a: String, b: String) -> int:
	var pa := parse(a)
	var pb := parse(b)
	if pa.is_empty() or pb.is_empty():
		if pa.is_empty() and pb.is_empty():
			return 0
		return -1 if pa.is_empty() else 1
	for i in 3:
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0


## Versi launcher = versi aplikasi (application/config/version).
static func launcher_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Versi mesin yang sedang berjalan, mis. "4.7.2".
static func engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [info.major, info.minor, info.patch]


## Alasan game tidak bisa dijalankan di launcher ini ("" = cocok).
## Paket PCK hanya cocok dengan mesin MAJOR.MINOR yang sama dan patch >= minimum.
static func incompatibility(manifest: Dictionary, launcher: String = "", engine: String = "") -> String:
	if launcher == "":
		launcher = launcher_version()
	if engine == "":
		engine = engine_version()
	var min_l := str(manifest.get("min_launcher_version", "0.0.0"))
	if not is_valid(min_l):
		return "Versi minimum launcher tidak sah"
	if compare(launcher, min_l) < 0:
		return "Butuh aplikasi versi %s atau lebih baru (terpasang %s)" % [min_l, launcher]
	var min_e := str(manifest.get("min_engine_version", "0.0.0"))
	if not is_valid(min_e):
		return "Versi minimum mesin tidak sah"
	var pe := parse(engine)
	var pm := parse(min_e)
	if str(manifest.get("type", "")) == "download":
		if pe[0] != pm[0] or pe[1] != pm[1]:
			return "Paket dibuat untuk mesin %d.%d, aplikasi memakai %d.%d" % [pm[0], pm[1], pe[0], pe[1]]
	if compare(engine, min_e) < 0:
		return "Butuh mesin Godot %s (terpasang %s)" % [min_e, engine]
	return ""
