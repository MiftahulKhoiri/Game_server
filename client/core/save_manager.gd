extends RefCounted
## Penyimpanan progres lokal PER GAME (tidak pernah dicampur):
##   user://user_data/progress/<game_id>/save.json      data terbaru
##   user://user_data/progress/<game_id>/save.json.bak  salinan sebelum penulisan terakhir
## Penulisan atomik (tulis .tmp -> salin data lama ke .bak -> ganti nama). Bila save.json rusak, .bak dipakai.
## Setiap berkas punya schema_version; migrasi dijalankan game lewat `migrations` saat memuat.
## Game Petualangan (adventure) menyimpan progresnya di server Game_server seperti sebelumnya.

const SecurityManager := preload("res://core/security_manager.gd")

const ROOT := "user://user_data"
const PROGRESS_DIR := ROOT + "/progress"
const MAX_SAVE_BYTES := 2 * 1024 * 1024


static func dir_for(game_id: String) -> String:
	return "%s/%s" % [PROGRESS_DIR, game_id]


static func path_for(game_id: String) -> String:
	return dir_for(game_id) + "/save.json"


## Simpan `data` (Dictionary) untuk game `game_id` dengan versi skema `schema`. true bila berhasil.
static func save(game_id: String, data: Dictionary, schema: int) -> bool:
	if not SecurityManager.is_valid_id(game_id):
		push_error("[save] id game tidak sah: " + game_id)
		return false
	var dir := dir_for(game_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var wrapped := {
		"game_id": game_id,
		"schema_version": schema,
		"saved_at": Time.get_datetime_string_from_system(true),
		"data": data,
	}
	var text := JSON.stringify(wrapped)
	if text.length() > MAX_SAVE_BYTES:
		push_error("[save] data terlalu besar")
		return false
	var target := path_for(game_id)
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# Pastikan .tmp terbaca utuh sebelum menggantikan data lama.
	if _read_wrapped(tmp, game_id).is_empty():
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target + ".bak")
		DirAccess.copy_absolute(target, target + ".bak")
	DirAccess.remove_absolute(target)
	return DirAccess.rename_absolute(tmp, target) == OK


## Muat progres. `migrations`: {versi_lama:int -> Callable(data: Dictionary) -> Dictionary} untuk
## menaikkan data versi N ke N+1. Mengembalikan {data, schema_version, restored_from_backup} atau {} bila
## belum ada / tidak bisa dipulihkan. Data dari skema lebih BARU daripada `schema` tidak diturunkan
## (dikembalikan apa adanya dengan "newer": true) supaya tidak hilang.
static func load_progress(game_id: String, schema: int, migrations: Dictionary = {}) -> Dictionary:
	if not SecurityManager.is_valid_id(game_id):
		return {}
	var target := path_for(game_id)
	var w := _read_wrapped(target, game_id)
	var restored := false
	if w.is_empty() and FileAccess.file_exists(target + ".bak"):
		w = _read_wrapped(target + ".bak", game_id)
		restored = not w.is_empty()
	if w.is_empty():
		return {}
	var ver := int(w.get("schema_version", 0))
	var data: Dictionary = w.get("data", {})
	if ver > schema:
		return {"data": data, "schema_version": ver, "restored_from_backup": restored, "newer": true}
	while ver < schema:
		if not migrations.has(ver):
			push_error("[save] tidak ada migrasi %s v%d -> v%d" % [game_id, ver, ver + 1])
			return {"data": data, "schema_version": ver, "restored_from_backup": restored, "migration_failed": true}
		data = migrations[ver].call(data)
		ver += 1
	if restored or int(w.get("schema_version", 0)) != schema:
		save(game_id, data, schema)  # tulis ulang dalam versi baru (data lama tetap di .bak)
	return {"data": data, "schema_version": schema, "restored_from_backup": restored}


static func has_progress(game_id: String) -> bool:
	return FileAccess.file_exists(path_for(game_id)) or FileAccess.file_exists(path_for(game_id) + ".bak")


static func _read_wrapped(path: String, game_id: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_SAVE_BYTES:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(v) != TYPE_DICTIONARY or str(v.get("game_id", "")) != game_id:
		return {}
	if typeof(v.get("data")) != TYPE_DICTIONARY:
		return {}
	return v
