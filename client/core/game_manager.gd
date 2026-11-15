extends Node
## GameManager (autoload): pusat platform multi-game.
##   - daftar game + status (lewat GameRegistry)
##   - katalog server bertanda tangan (lewat ApiClient), disimpan untuk dipakai offline
##   - unduh -> verifikasi -> pasang (DownloadManager + SecurityManager + PackageManager)
##   - menjalankan satu game aktif, kembali ke launcher, menyimpan progres, sinkronisasi saat online
## Dokumen: docs/ARCHITECTURE.md (bagian Platform Multi-Game)

signal games_changed
signal download_progress(id: String, received: int, total: int)
signal notice(text: String, is_error: bool)
signal online_changed(online: bool)
## Dipancarkan tepat sebelum game aktif ditutup (game menyimpan progres di sini bila belum).
signal game_exiting(id: String)

const GameRegistry := preload("res://core/game_registry.gd")
const PackageManager := preload("res://core/package_manager.gd")
const DownloadManager := preload("res://core/download_manager.gd")
const SecurityManager := preload("res://core/security_manager.gd")
const VersionManager := preload("res://core/version_manager.gd")
const SaveManager := preload("res://core/save_manager.gd")
const ApiClient := preload("res://core/api_client.gd")

const LAUNCHER_SCENE := "res://launcher/scenes/main_menu.tscn"
const STATE_FILE := "user://user_data/registry/launcher.cfg"
const SYNC_FILE := "user://user_data/registry/sync_pending.json"
const State := GameRegistry.State

var registry := GameRegistry.new()
var packages := PackageManager.new(registry)
var downloads: DownloadManager
var api: ApiClient

var active_game_id := ""
var online := false
var last_catalog_error := ""
var refreshing := false
var _transient: Dictionary = {}   # id -> State sementara
var _errors: Dictionary = {}      # id -> pesan error terakhir
var _pending: Dictionary = {}     # id -> manifest bertanda tangan sah yang sedang diunduh
var _sync_pending: Dictionary = {} # id -> true (progres lokal belum terkirim ke server)
var _restart_notes: Dictionary = {} # id -> pesan "buka ulang aplikasi"


func _ready() -> void:
	downloads = DownloadManager.new()
	downloads.name = "Downloads"
	add_child(downloads)
	downloads.progress.connect(_on_download_progress)
	downloads.finished.connect(_on_download_finished)
	api = ApiClient.new()
	api.name = "ApiClient"
	add_child(api)
	registry.load_all()
	for e in registry.load_errors:
		push_warning("[platform] " + e)
	_load_sync_pending()


# --- Daftar & katalog ---------------------------------------------------------------------------

func games() -> Array:
	return registry.list(_transient, _errors)


func game(id: String) -> Dictionary:
	return registry.entry(id, _transient, _errors)


## Ambil katalog terbaru dari server. Gagal = katalog terakhir yang sah tetap dipakai (mode offline).
func refresh_catalog() -> bool:
	if refreshing:
		return online
	refreshing = true
	var res: Dictionary = await api.fetch_catalog()
	refreshing = false
	if not res.ok:
		_set_online(false)
		last_catalog_error = str(res.error)
		games_changed.emit()
		return false
	_set_online(true)
	var why := registry.accept_catalog(res.raw, res.sig)
	last_catalog_error = why
	if why != "":
		notice.emit("Katalog server ditolak: " + why, true)
	games_changed.emit()
	_flush_sync()
	return why == ""


func _set_online(v: bool) -> void:
	if v != online:
		online = v
		online_changed.emit(v)


# --- Unduh / pasang / perbarui ------------------------------------------------------------------

## Unduh dan pasang (atau perbarui) game unduhan. Hasil akhir lewat games_changed / notice.
func install(id: String) -> void:
	if _transient.has(id):
		return
	var e := game(id)
	if e.type != "download" or not registry.catalog.has(id):
		notice.emit("Game ini tidak ada di katalog server", true)
		return
	_errors.erase(id)
	_transient[id] = State.DOWNLOADING
	games_changed.emit()
	var man: Dictionary = await api.fetch_manifest(id)
	if not man.ok:
		_finish_error(id, "Manifest tidak bisa diambil: " + str(man.error))
		_set_online(false)
		return
	if man.raw.size() > SecurityManager.MAX_MANIFEST_BYTES or not SecurityManager.verify_signature(man.raw, man.sig):
		_finish_error(id, "Tanda tangan manifest tidak sah — paket ditolak")
		return
	var m := SecurityManager.parse_json_object(man.raw)
	var why := SecurityManager.validate_manifest(m, id)
	if why == "" and str(m.type) != "download":
		why = "Manifest bukan game unduhan"
	if why == "":
		why = VersionManager.incompatibility(m)
	if why == "" and registry.installed.has(id) and VersionManager.compare(str(m.version), str(registry.installed[id].version)) < 0:
		why = "Server menawarkan versi lebih lama (%s) daripada yang terpasang" % m.version
	if why != "":
		_finish_error(id, why)
		return
	_pending[id] = m
	var part := DownloadManager.part_path(id, str(m.version))
	var err: String = downloads.start(id, api.base_url(), "/v1/games/%s/download" % id, part, int(m.size))
	if err != "":
		_pending.erase(id)
		_finish_error(id, err)


func cancel(id: String) -> void:
	if downloads.is_active(id):
		downloads.cancel(id)


func download_active(id: String) -> bool:
	return downloads.is_active(id)


func _on_download_progress(id: String, received: int, total: int) -> void:
	download_progress.emit(id, received, total)


func _on_download_finished(id: String, ok: bool, error: String, path: String) -> void:
	var m: Dictionary = _pending.get(id, {})
	_pending.erase(id)
	if not ok or m.is_empty():
		_finish_error(id, error if error != "" else "Unduhan gagal")
		return
	_transient[id] = State.VERIFYING
	games_changed.emit()
	await get_tree().process_frame  # beri kesempatan UI menampilkan "Memverifikasi"
	var why := PackageManager.verify_file(path, m)
	if why != "":
		DirAccess.remove_absolute(path)
		_finish_error(id, why)
		return
	_transient[id] = State.INSTALLING
	games_changed.emit()
	await get_tree().process_frame
	var had := registry.installed.has(id)
	var res := packages.install(path, m)
	_transient.erase(id)
	if not res.ok:
		_finish_error(id, str(res.error))
		return
	_errors.erase(id)
	if PackageManager.loaded.has(id):
		_restart_notes[id] = "Versi %s terpasang. Buka ulang aplikasi untuk memakainya." % m.version
	notice.emit(("%s diperbarui ke %s" if had else "%s terpasang (versi %s)") % [str(m.name), str(m.version)], false)
	games_changed.emit()


func _finish_error(id: String, why: String) -> void:
	_transient.erase(id)
	_errors[id] = why
	notice.emit(why, true)
	games_changed.emit()


func uninstall(id: String) -> void:
	var res := packages.uninstall(id)
	if not res.ok:
		notice.emit(str(res.error), true)
	else:
		_errors.erase(id)
		notice.emit("Game dihapus. Progres belajar tetap tersimpan.", false)
		if res.restart_required:
			_restart_notes[id] = "Game sudah dihapus; buka ulang aplikasi untuk membersihkan memori."
	games_changed.emit()


func restart_note(id: String) -> String:
	return str(_restart_notes.get(id, ""))


# --- Menjalankan game ---------------------------------------------------------------------------

## Jalankan game. Hanya satu game aktif; game lain (bila ada) ditutup dulu.
func play(id: String) -> void:
	var e := game(id)
	if e.state != State.INSTALLED and e.state != State.UPDATE_AVAILABLE:
		notice.emit(e.reason if e.reason != "" else "Game belum siap dimainkan", true)
		return
	if active_game_id != "" and active_game_id != id:
		await exit_to_launcher(false)
	if e.type == "download":
		var res := packages.load_game(id)
		if not res.ok and not res.restart_required and registry.installed.get(id, {}).has("previous"):
			var rb := packages.rollback(id)
			if rb.ok:
				notice.emit("Versi baru gagal dimuat (%s); kembali ke versi %s" % [res.error, rb.version], true)
				res = packages.load_game(id)
		if not res.ok:
			_errors[id] = str(res.error)
			notice.emit(str(res.error), true)
			games_changed.emit()
			return
	var entry := str(e.manifest.entry_scene)
	if not ResourceLoader.exists(entry):
		notice.emit("Entry scene tidak ditemukan: " + entry, true)
		return
	active_game_id = id
	_remember_last(id)
	set_platform_music(str(e.manifest.get("background_music", "")) == "platform")
	var err := get_tree().change_scene_to_file(entry)
	if err != OK:
		active_game_id = ""
		notice.emit("Game gagal dibuka (kode %d)" % err, true)


## Tutup game aktif dan kembali ke launcher: game diberi kesempatan menyimpan (sinyal game_exiting dan
## metode opsional platform_before_exit() pada scene aktif), audio dihentikan, scene dilepas.
func exit_to_launcher(change_scene := true) -> void:
	var id := active_game_id
	if id != "":
		game_exiting.emit(id)
		var cur := get_tree().current_scene
		if cur != null and cur.has_method("platform_before_exit"):
			await cur.platform_before_exit()
	_stop_audio()
	active_game_id = ""
	if change_scene:
		get_tree().change_scene_to_file(LAUNCHER_SCENE)


## Musik desa milik Game Petualangan (autoload Sound) hanya berbunyi di game yang memintanya
## ("background_music": "platform"); di launcher dan game lain dijeda. Suara NPC dihentikan.
func _stop_audio() -> void:
	set_platform_music(false)
	var snd = get_node_or_null("/root/Sound")
	if snd != null and snd.has_method("npc_stop"):
		snd.npc_stop()


func set_platform_music(on: bool) -> void:
	var snd = get_node_or_null("/root/Sound")
	if snd != null and snd.has_method("set_music_paused"):
		snd.set_music_paused(not on)


func last_played() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(STATE_FILE) != OK:
		return ""
	return str(cfg.get_value("launcher", "last_game", ""))


func _remember_last(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATE_FILE)
	cfg.set_value("launcher", "last_game", id)
	cfg.save(STATE_FILE)


# --- Progres & sinkronisasi ---------------------------------------------------------------------

## Simpan progres game `id` secara lokal (selalu berhasil tanpa internet), lalu tandai untuk dikirim
## ke server saat online dan sudah masuk.
func save_progress(id: String, data: Dictionary, schema: int) -> bool:
	var ok := SaveManager.save(id, data, schema)
	if ok:
		_sync_pending[id] = true
		_save_sync_pending()
		_flush_sync.call_deferred()
	return ok


func load_progress(id: String, schema: int, migrations: Dictionary = {}) -> Dictionary:
	return SaveManager.load_progress(id, schema, migrations)


## Pulihkan progres dari server bila lokal kosong (HP baru). Mengembalikan data atau {}.
func restore_progress_from_server(id: String, schema: int) -> Dictionary:
	if SaveManager.has_progress(id) or not api.has_login():
		return {}
	var r: Dictionary = await api.progress_get(id)
	if not r.ok or typeof(r.data.get("data")) != TYPE_DICTIONARY or (r.data.data as Dictionary).is_empty():
		return {}
	if int(r.data.get("schema_version", 0)) > schema:
		return {}
	SaveManager.save(id, r.data.data, int(r.data.get("schema_version", schema)))
	return SaveManager.load_progress(id, schema).get("data", {})


func _flush_sync() -> void:
	if _sync_pending.is_empty() or not api.has_login():
		return
	for id in _sync_pending.keys():
		var p := SaveManager.path_for(id)
		var w = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		if typeof(w) != TYPE_DICTIONARY:
			_sync_pending.erase(id)
			continue
		var r: Dictionary = await api.progress_put(id, w.get("data", {}), int(w.get("schema_version", 1)), str(w.get("saved_at", "")))
		if r.ok:
			_sync_pending.erase(id)
		elif int(r.status) == 0:
			_set_online(false)
			break
		elif int(r.status) == 401:
			break
		else:
			push_warning("[platform] sinkron progres %s ditolak: %s" % [id, r.error])
			_sync_pending.erase(id)
	_save_sync_pending()


func _load_sync_pending() -> void:
	var v = JSON.parse_string(FileAccess.get_file_as_string(SYNC_FILE)) if FileAccess.file_exists(SYNC_FILE) else null
	if typeof(v) == TYPE_DICTIONARY:
		for id in v:
			if SecurityManager.is_valid_id(str(id)):
				_sync_pending[str(id)] = true


func _save_sync_pending() -> void:
	var f := FileAccess.open(SYNC_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_sync_pending))
