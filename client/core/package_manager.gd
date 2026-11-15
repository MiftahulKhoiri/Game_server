extends RefCounted
## Pemasangan, pemuatan, rollback, dan penghapusan paket game (.pck).
##
## Alur pasang (dipanggil GameManager SETELAH tanda tangan manifest sah):
##   berkas sementara (.part) -> cek ukuran -> cek SHA-256 -> baca header & direktori PCK
##   (versi mesin, path harus di res://games/<id>/) -> pindah atomik ke
##   user://user_data/packages/<id>/<versi>-<sha8>.pck -> catat di registry (versi lama disimpan
##   sebagai "previous" untuk rollback) -> baru kemudian berkas versi yang lebih lama dibuang.
## Paket dimuat dengan replace_files=false: tidak bisa menimpa berkas aplikasi atau game lain.
## Godot tidak bisa melepas (unload) paket yang sudah dimuat; bila versi lain dari game yang sama sudah
## dimuat di sesi ini, aplikasi perlu dibuka ulang (restart_required).

const SecurityManager := preload("res://core/security_manager.gd")
const VersionManager := preload("res://core/version_manager.gd")
const PckReader := preload("res://core/pck_reader.gd")

const PACKAGES_DIR := "user://user_data/packages"

var registry  # game_registry.gd
## id -> path paket yang SUDAH dimuat di sesi ini (tidak bisa dilepas sampai aplikasi ditutup).
static var loaded: Dictionary = {}


func _init(reg) -> void:
	registry = reg
	DirAccess.make_dir_recursive_absolute(PACKAGES_DIR)


static func package_dir(id: String) -> String:
	return "%s/%s" % [PACKAGES_DIR, id]


## Periksa berkas paket terhadap manifest. "" = lolos.
static func verify_file(path: String, manifest: Dictionary) -> String:
	var id := str(manifest.get("id", ""))
	var size := SecurityManager.file_size(path)
	if size < 0:
		return "Berkas paket tidak ada"
	if size != int(manifest.get("size", -1)):
		return "Ukuran paket tidak cocok (%d, seharusnya %d)" % [size, int(manifest.get("size", -1))]
	if SecurityManager.file_sha256(path) != str(manifest.get("sha256", "")).to_lower():
		return "SHA-256 paket tidak cocok (berkas rusak atau diubah)"
	return verify_structure(path, id)


## Periksa header + direktori PCK tanpa memuatnya. "" = lolos.
static func verify_structure(path: String, id: String) -> String:
	var info := PckReader.read(path)
	if not info.ok:
		return str(info.error)
	var eng: Array = info.engine
	var run := VersionManager.parse(VersionManager.engine_version())
	if int(eng[0]) != run[0] or int(eng[1]) != run[1]:
		return "Paket dibuat dengan Godot %d.%d.%d, aplikasi memakai %s" % [eng[0], eng[1], eng[2], VersionManager.engine_version()]
	return PckReader.check_paths(info.files, id)


## Pasang paket dari berkas sementara `part_path`. manifest harus sudah sah (tanda tangan + validasi).
## Mengembalikan {ok, error}. Gagal = versi lama (bila ada) tetap utuh dan tetap tercatat.
func install(part_path: String, manifest: Dictionary) -> Dictionary:
	var id := str(manifest.id)
	var why := SecurityManager.validate_manifest(manifest, id)
	if why == "":
		why = VersionManager.incompatibility(manifest)
	if why == "":
		why = verify_file(part_path, manifest)
	if why != "":
		DirAccess.remove_absolute(part_path)
		return {"ok": false, "error": why}
	var dir := package_dir(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var sha := str(manifest.sha256).to_lower()
	var target := "%s/%s-%s.pck" % [dir, str(manifest.version), sha.substr(0, 8)]
	if FileAccess.file_exists(target) and SecurityManager.file_sha256(target) == sha:
		DirAccess.remove_absolute(part_path)  # versi identik sudah ada
	else:
		DirAccess.remove_absolute(target)
		if DirAccess.rename_absolute(part_path, target) != OK:
			DirAccess.remove_absolute(part_path)
			return {"ok": false, "error": "Gagal memindahkan paket ke folder game"}
	var old: Dictionary = registry.installed.get(id, {})
	var rec := {
		"version": str(manifest.version),
		"package_path": target,
		"sha256": sha,
		"size": int(manifest.size),
		"manifest": manifest,
		"installed_at": Time.get_datetime_string_from_system(true),
	}
	if not old.is_empty() and str(old.get("package_path", "")) != target:
		var prev := old.duplicate()
		prev.erase("previous")
		rec["previous"] = prev
	registry.installed[id] = rec
	if not registry.save_installed():
		if old.is_empty():
			registry.installed.erase(id)
		else:
			registry.installed[id] = old
		return {"ok": false, "error": "Gagal menyimpan registry game"}
	_cleanup(id)
	return {"ok": true, "error": ""}


## Kembali ke versi sebelumnya (dipakai otomatis bila versi baru gagal dimuat).
func rollback(id: String) -> Dictionary:
	var rec: Dictionary = registry.installed.get(id, {})
	var prev: Dictionary = rec.get("previous", {})
	if prev.is_empty():
		return {"ok": false, "error": "Tidak ada versi sebelumnya"}
	if verify_file(str(prev.package_path), prev.manifest) != "":
		return {"ok": false, "error": "Versi sebelumnya juga rusak"}
	var bad_path := str(rec.package_path)
	registry.installed[id] = prev
	if not registry.save_installed():
		registry.installed[id] = rec
		return {"ok": false, "error": "Gagal menyimpan registry game"}
	if not loaded.has(id) or str(loaded[id]) != bad_path:
		DirAccess.remove_absolute(bad_path)
	return {"ok": true, "error": "", "version": str(prev.version)}


## Muat paket game terpasang. {ok, error, restart_required}
func load_game(id: String) -> Dictionary:
	var rec: Dictionary = registry.installed.get(id, {})
	if rec.is_empty():
		return {"ok": false, "error": "Game belum terpasang", "restart_required": false}
	var path := str(rec.package_path)
	if loaded.has(id):
		if str(loaded[id]) == path:
			return {"ok": true, "error": "", "restart_required": false}
		return {"ok": false, "error": "Versi lain game ini sudah dimuat. Tutup lalu buka ulang aplikasi untuk memakai versi %s." % rec.version,
			"restart_required": true}
	var why := verify_file(path, rec.manifest)
	if why == "":
		why = VersionManager.incompatibility(rec.manifest)
	if why != "":
		return {"ok": false, "error": why, "restart_required": false}
	if not ProjectSettings.load_resource_pack(path, false):
		return {"ok": false, "error": "Mesin gagal memuat paket", "restart_required": false}
	loaded[id] = path
	var entry := str(rec.manifest.entry_scene)
	if not ResourceLoader.exists(entry):
		return {"ok": false, "error": "Entry scene tidak ada di paket: " + entry, "restart_required": false}
	return {"ok": true, "error": "", "restart_required": false}


## Hapus game unduhan. Progres pemain TIDAK dihapus. {ok, error, restart_required}
func uninstall(id: String) -> Dictionary:
	if registry.builtin.has(id):
		return {"ok": false, "error": "Game bawaan tidak bisa dihapus", "restart_required": false}
	if not registry.installed.has(id):
		return {"ok": false, "error": "Game belum terpasang", "restart_required": false}
	var rec: Dictionary = registry.installed[id]
	registry.installed.erase(id)
	if not registry.save_installed():
		registry.installed[id] = rec
		return {"ok": false, "error": "Gagal menyimpan registry game", "restart_required": false}
	var dir := package_dir(id)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
	return {"ok": true, "error": "", "restart_required": loaded.has(id)}


## Buang berkas paket selain versi aktif dan versi sebelumnya (setelah versi baru tercatat sah).
func _cleanup(id: String) -> void:
	var rec: Dictionary = registry.installed.get(id, {})
	var keep := [str(rec.get("package_path", ""))]
	if rec.has("previous"):
		keep.append(str(rec.previous.get("package_path", "")))
	if loaded.has(id):
		keep.append(str(loaded[id]))
	var dir := package_dir(id)
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var p := dir + "/" + f
		if f.ends_with(".pck") and not keep.has(p):
			DirAccess.remove_absolute(p)
