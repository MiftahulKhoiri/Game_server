extends RefCounted
## Registry game: menggabungkan tiga sumber menjadi satu daftar dengan status yang jelas.
##   1. Game bawaan  : res://config/games.json (ikut APK, selalu ada walau tanpa internet)
##   2. Katalog      : user://user_data/registry/catalog.json + catalog.sig, salinan katalog server
##                     terakhir yang TANDA TANGANNYA SAH (diperiksa ulang setiap dimuat).
##   3. Terpasang    : user://user_data/registry/installed.json (ditulis hanya oleh PackageManager
##                     setelah paket lolos semua pemeriksaan).
## Status tidak pernah ditentukan dari keberadaan berkas saja: harus tercatat di registry terpasang,
## lolos validasi manifest, ukuran berkas cocok, dan kompatibel.

const SecurityManager := preload("res://core/security_manager.gd")
const VersionManager := preload("res://core/version_manager.gd")

const BUILTIN_PATH := "res://config/games.json"
const REG_DIR := "user://user_data/registry"
const CATALOG_PATH := REG_DIR + "/catalog.json"
const CATALOG_SIG_PATH := REG_DIR + "/catalog.sig"
const INSTALLED_PATH := REG_DIR + "/installed.json"
const INSTALLED_SCHEMA := 1

enum State { NOT_INSTALLED, DOWNLOADING, VERIFYING, INSTALLING, INSTALLED, UPDATE_AVAILABLE, ERROR, DISABLED }
const STATE_NAMES := ["NOT_INSTALLED", "DOWNLOADING", "VERIFYING", "INSTALLING", "INSTALLED",
	"UPDATE_AVAILABLE", "ERROR", "DISABLED"]

var builtin: Dictionary = {}      # id -> manifest
var catalog: Dictionary = {}      # id -> entri katalog (sudah divalidasi)
var catalog_meta: Dictionary = {} # {generated, catalog_version}
var installed: Dictionary = {}    # id -> {version, package_path, sha256, size, manifest, installed_at, previous}
var load_errors: Array[String] = []


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(REG_DIR)


func load_all() -> void:
	load_errors.clear()
	_load_builtin()
	_load_catalog_cache()
	_load_installed()


func _load_builtin() -> void:
	builtin.clear()
	var f := FileAccess.open(BUILTIN_PATH, FileAccess.READ)
	if f == null:
		load_errors.append("games.json bawaan tidak ada")
		return
	var v = JSON.parse_string(f.get_as_text())
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("games")) != TYPE_ARRAY:
		load_errors.append("games.json bawaan rusak")
		return
	for g in v.games:
		if typeof(g) != TYPE_DICTIONARY:
			continue
		var why := SecurityManager.validate_manifest(g)
		if why == "" and str(g.type) != "builtin":
			why = "tipe bukan builtin"
		if why != "":
			load_errors.append("Game bawaan ditolak (%s): %s" % [str(g.get("id", "?")), why])
			continue
		if builtin.has(g.id):
			load_errors.append("ID game bawaan kembar: " + str(g.id))
			continue
		builtin[g.id] = g


# --- Katalog ----------------------------------------------------------------------------------

## Pasang katalog baru (byte persis dari server + tanda tangan). Tanda tangan diperiksa DULU; katalog
## hanya disimpan bila sah. Mengembalikan "" atau alasan penolakan (katalog lama tetap dipakai).
func accept_catalog(raw: PackedByteArray, sig_b64: String) -> String:
	var old_catalog := catalog
	var old_meta := catalog_meta
	var why := _parse_catalog(raw, sig_b64)
	if why != "":
		catalog = old_catalog
		catalog_meta = old_meta
		return why
	_write_bytes(CATALOG_PATH, raw)
	_write_bytes(CATALOG_SIG_PATH, sig_b64.to_utf8_buffer())
	return ""


func _load_catalog_cache() -> void:
	catalog.clear()
	catalog_meta.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var raw := FileAccess.get_file_as_bytes(CATALOG_PATH)
	var sig := FileAccess.get_file_as_string(CATALOG_SIG_PATH)
	var why := _parse_catalog(raw, sig)
	if why != "":
		load_errors.append("Katalog tersimpan ditolak: " + why)
		catalog.clear()
		catalog_meta.clear()


func _parse_catalog(raw: PackedByteArray, sig_b64: String) -> String:
	if not SecurityManager.verify_signature(raw, sig_b64):
		return "Tanda tangan katalog tidak sah"
	var v := SecurityManager.parse_json_object(raw)
	if v.is_empty() or typeof(v.get("games")) != TYPE_ARRAY:
		return "Isi katalog rusak"
	var parsed := {}
	for g in v.games:
		if typeof(g) != TYPE_DICTIONARY:
			continue
		var why := SecurityManager.validate_manifest(g)
		if why == "" and str(g.type) != "download":
			why = "katalog server hanya boleh berisi game unduhan"
		if why == "" and builtin.has(g.id):
			why = "ID sama dengan game bawaan"
		if why != "":
			push_warning("[registry] entri katalog ditolak: %s (%s)" % [str(g.get("id", "?")), why])
			continue
		if parsed.has(g.id):
			continue
		parsed[g.id] = g
	catalog = parsed
	catalog_meta = {"generated": str(v.get("generated", "")), "catalog_version": int(v.get("catalog_version", 0))}
	return ""


# --- Terpasang --------------------------------------------------------------------------------

func _load_installed() -> void:
	installed.clear()
	var v = _read_json(INSTALLED_PATH)
	if typeof(v) != TYPE_DICTIONARY and FileAccess.file_exists(INSTALLED_PATH + ".bak"):
		v = _read_json(INSTALLED_PATH + ".bak")
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("games")) != TYPE_DICTIONARY:
		return
	for id in v.games:
		var rec = v.games[id]
		if typeof(rec) != TYPE_DICTIONARY or not SecurityManager.is_valid_id(str(id)):
			continue
		if typeof(rec.get("manifest")) != TYPE_DICTIONARY:
			continue
		if SecurityManager.validate_manifest(rec.manifest, str(id)) != "" or str(rec.manifest.type) != "download":
			load_errors.append("Catatan instalasi %s rusak, diabaikan" % id)
			continue
		installed[str(id)] = rec


func save_installed() -> bool:
	var text := JSON.stringify({"schema_version": INSTALLED_SCHEMA, "games": installed}, "\t")
	var tmp := INSTALLED_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(INSTALLED_PATH):
		DirAccess.remove_absolute(INSTALLED_PATH + ".bak")
		DirAccess.copy_absolute(INSTALLED_PATH, INSTALLED_PATH + ".bak")
	DirAccess.remove_absolute(INSTALLED_PATH)
	return DirAccess.rename_absolute(tmp, INSTALLED_PATH) == OK


## Paket game terpasang masih utuh menurut catatan (ada dan ukurannya sama). SHA-256 penuh diperiksa
## PackageManager tepat sebelum dimuat.
func installed_package_ok(id: String) -> bool:
	if not installed.has(id):
		return false
	var rec: Dictionary = installed[id]
	var path := str(rec.get("package_path", ""))
	if not path.begins_with("user://user_data/packages/%s/" % id):
		return false
	return SecurityManager.file_size(path) == int(rec.get("size", -1))


# --- Daftar untuk launcher ----------------------------------------------------------------------

## Satu entri per game: {id, manifest, state, state_name, reason, installed_version, latest_version, type}
## `transient`: id -> State sementara (DOWNLOADING/VERIFYING/INSTALLING) dari GameManager.
## `errors`: id -> pesan error terakhir.
func list(transient: Dictionary = {}, errors: Dictionary = {}) -> Array:
	var ids: Array = []
	for id in builtin:
		ids.append(id)
	for id in catalog:
		if not ids.has(id):
			ids.append(id)
	for id in installed:
		if not ids.has(id):
			ids.append(id)
	var out: Array = []
	for id in ids:
		out.append(entry(id, transient, errors))
	return out


func entry(id: String, transient: Dictionary = {}, errors: Dictionary = {}) -> Dictionary:
	var e := {"id": id, "manifest": {}, "state": State.NOT_INSTALLED, "reason": "",
		"installed_version": "", "latest_version": "", "type": ""}
	if builtin.has(id):
		var m: Dictionary = builtin[id]
		e.manifest = m
		e.type = "builtin"
		e.installed_version = str(m.version)
		e.latest_version = str(m.version)
		e.state = State.INSTALLED
		if not bool(m.get("enabled", true)):
			e.state = State.DISABLED
			e.reason = "Dinonaktifkan"
		else:
			var why := VersionManager.incompatibility(m)
			if why != "":
				e.state = State.DISABLED
				e.reason = why
	else:
		e.type = "download"
		var cat: Dictionary = catalog.get(id, {})
		var inst: Dictionary = installed.get(id, {})
		e.manifest = (inst.manifest as Dictionary).duplicate() if not inst.is_empty() else cat.duplicate()
		if not cat.is_empty():
			e.latest_version = str(cat.version)
			for k in ["name", "description", "category", "icon_color", "size"]:
				if cat.has(k) and (k != "size" or inst.is_empty()):
					e.manifest[k] = cat[k]
		if not inst.is_empty() and installed_package_ok(id):
			e.installed_version = str(inst.version)
			e.state = State.INSTALLED
			if not cat.is_empty() and VersionManager.compare(str(cat.version), str(inst.version)) > 0 \
					and VersionManager.incompatibility(cat) == "":
				e.state = State.UPDATE_AVAILABLE
			var why := VersionManager.incompatibility(inst.manifest)
			if why != "":
				e.state = State.DISABLED
				e.reason = why
		elif not inst.is_empty():
			e.state = State.ERROR
			e.reason = "Berkas paket hilang atau rusak; unduh ulang"
		elif cat.is_empty():
			e.state = State.DISABLED
			e.reason = "Tidak ada di katalog"
		else:
			var why := VersionManager.incompatibility(cat)
			if why != "":
				e.state = State.DISABLED
				e.reason = why
			elif not bool(cat.get("enabled", true)):
				e.state = State.DISABLED
				e.reason = "Dinonaktifkan oleh server"
	if transient.has(id):
		e.state = transient[id]
	elif errors.has(id):
		e.reason = str(errors[id])
		if e.state == State.NOT_INSTALLED:
			e.state = State.ERROR
	e.state_name = STATE_NAMES[e.state]
	return e


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _write_bytes(path: String, data: PackedByteArray) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(data)
	f.close()
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)
