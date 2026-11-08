extends Node
## Pembaruan isi game tanpa APK baru ("patch panas"). Aturan: docs/PATCH.md
##
## Autoload PERTAMA: `_init()` jalan sebelum Api/Session/Sound dibuat, jadi skrip dan adegan
## yang dimuat sesudahnya sudah berasal dari paket patch (.pck) yang menimpa isi APK.
##
## Alur tiap kali aplikasi dibuka:
##   1. Tanya server `GET /v1/patch?apk=<versi APK>` (batas waktu pendek, gagal = lanjut).
##   2. Ada patch baru -> unduh, cek SHA-256, simpan di user://patch/. Server kosong = patch dicabut.
##   3. Muat patch terpasang lewat ProjectSettings.load_resource_pack().
## Pengaman: bila dua kali buka berturut-turut tidak sampai layar masuk (`confirm()` tak terpanggil),
## patch dibuang dan aplikasi kembali ke isi APK.

const DIR := "user://patch"
const STATE := "user://patch/state.cfg"
const SETTINGS := "user://settings.cfg"
const DEFAULT_URL := "http://192.168.225.3:8090"
const CONNECT_TIMEOUT_MS := 4000
const MANIFEST_TIMEOUT_MS := 5000
const DOWNLOAD_TIMEOUT_MS := 40000
const MAX_BOOTS := 2

## Id patch yang sedang aktif ("" = isi APK apa adanya) dan pesan status untuk layar masuk.
var active_id := ""
var active_version := ""
var status := ""


func _init() -> void:
	# Uji lokal / editor tidak ikut menarik patch kecuali diminta (GAME_PATCH_URL).
	var forced := OS.get_environment("GAME_PATCH_URL")
	if forced == "" and not OS.has_feature("template"):
		return
	var url := forced if forced != "" else _saved_url()
	var apk := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	DirAccess.make_dir_recursive_absolute(DIR)
	var st := ConfigFile.new()
	st.load(STATE)
	if str(st.get_value("patch", "apk", apk)) != apk:
		_forget(st)  # APK baru dipasang: isi APK lebih baru daripada patch lama
	if int(st.get_value("patch", "boots", 0)) >= MAX_BOOTS:
		var bad := str(st.get_value("patch", "id", ""))
		_forget(st)
		st.set_value("patch", "bad", bad)  # jangan diunduh lagi: id ini membuat aplikasi gagal terbuka
		st.save(STATE)
		status = "Patch dibuang (aplikasi gagal terbuka)"
	_check_server(url, apk, st)
	_load_installed(st, apk)


## Dipanggil layar masuk begitu berhasil tampil: tandai patch sehat.
func confirm() -> void:
	if active_id == "":
		return
	var st := ConfigFile.new()
	if st.load(STATE) != OK:
		return
	st.set_value("patch", "boots", 0)
	st.save(STATE)


## Teks pendek untuk label versi, mis. " | patch 20260101-ab12cd"; "" bila tidak ada patch.
func suffix() -> String:
	return "  |  patch " + active_id if active_id != "" else ""


# --- Pemasangan --------------------------------------------------------------------------

func _load_installed(st: ConfigFile, apk: String) -> void:
	var id := str(st.get_value("patch", "id", ""))
	if id == "":
		return
	var path := "%s/%s.pck" % [DIR, id]
	if not FileAccess.file_exists(path) or not ProjectSettings.load_resource_pack(path, true):
		_forget(st)
		status = "Patch rusak, dibuang"
		return
	st.set_value("patch", "apk", apk)
	st.set_value("patch", "boots", int(st.get_value("patch", "boots", 0)) + 1)
	st.save(STATE)
	active_id = id
	active_version = str(st.get_value("patch", "version", ""))
	print("[patcher] patch aktif: ", id)


func _forget(st: ConfigFile) -> void:
	var id := str(st.get_value("patch", "id", ""))
	var bad := str(st.get_value("patch", "bad", ""))
	if id != "":
		DirAccess.remove_absolute("%s/%s.pck" % [DIR, id])
	st.clear()
	if bad != "":
		st.set_value("patch", "bad", bad)
	st.save(STATE)


func _check_server(url: String, apk: String, st: ConfigFile) -> void:
	var res := _http_get(url, "/v1/patch?apk=" + apk.uri_encode(), MANIFEST_TIMEOUT_MS, "")
	if not res.ok:
		return  # server tak terjangkau: pakai patch terpasang bila ada
	var info = JSON.parse_string(res.body.get_string_from_utf8())
	if typeof(info) != TYPE_DICTIONARY:
		return
	var id := str(info.get("id", ""))
	var have := str(st.get_value("patch", "id", ""))
	if id == "":
		if have != "":
			_forget(st)  # server mencabut patch (rollback)
			status = "Patch dicabut"
		return
	if id == str(st.get_value("patch", "bad", "")):
		return
	if id == have and FileAccess.file_exists("%s/%s.pck" % [DIR, id]):
		return
	var sha := str(info.get("sha256", "")).to_lower()
	var want_size := int(info.get("size", 0))
	var target := "%s/%s.pck" % [DIR, id]
	var part := target + ".part"
	var dl := _http_get(url, str(info.get("url", "")), DOWNLOAD_TIMEOUT_MS, part)
	if not dl.ok:
		DirAccess.remove_absolute(part)
		status = "Unduh patch gagal, dicoba lagi nanti"
		return
	var got_size := 0
	var f := FileAccess.open(part, FileAccess.READ)
	if f != null:
		got_size = f.get_length()
		f.close()
	if (want_size > 0 and got_size != want_size) or (sha != "" and FileAccess.get_sha256(part) != sha):
		DirAccess.remove_absolute(part)
		status = "Patch tidak cocok (sidik jari), dibuang"
		return
	DirAccess.rename_absolute(part, target)
	if have != "":
		DirAccess.remove_absolute("%s/%s.pck" % [DIR, have])
	st.set_value("patch", "id", id)
	st.set_value("patch", "version", str(info.get("version", "")))
	st.set_value("patch", "boots", 0)
	st.save(STATE)


# --- HTTP sinkron kecil -------------------------------------------------------------------

func _saved_url() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return DEFAULT_URL
	return str(cfg.get_value("server", "url", DEFAULT_URL))


## GET sinkron. `to_file` kosong = isi dikembalikan di `body`; berisi path = ditulis ke berkas.
## Mengembalikan {ok: bool, body: PackedByteArray}.
func _http_get(base: String, path: String, timeout_ms: int, to_file: String) -> Dictionary:
	var fail := {"ok": false, "body": PackedByteArray()}
	var https := base.begins_with("https://")
	var rest := base.trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	var port := 443 if https else 80
	var host := rest
	var colon := rest.rfind(":")
	if colon > 0:
		host = rest.substr(0, colon)
		port = int(rest.substr(colon + 1))
	var http := HTTPClient.new()
	var opts: TLSOptions = TLSOptions.client() if https else null
	if http.connect_to_host(host, port, opts) != OK:
		return fail
	var start := Time.get_ticks_msec()
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http.poll()
		if Time.get_ticks_msec() - start > mini(CONNECT_TIMEOUT_MS, timeout_ms):
			return fail
		OS.delay_msec(20)
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return fail
	if http.request(HTTPClient.METHOD_GET, path, PackedStringArray(["Accept: */*"])) != OK:
		return fail
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() - start > timeout_ms:
			return fail
		OS.delay_msec(10)
	if not http.has_response() or http.get_response_code() != 200:
		return fail
	var out := PackedByteArray()
	var file: FileAccess = null
	if to_file != "":
		file = FileAccess.open(to_file, FileAccess.WRITE)
		if file == null:
			return fail
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			if file != null:
				file.store_buffer(chunk)
			else:
				out.append_array(chunk)
		else:
			OS.delay_msec(5)
		if Time.get_ticks_msec() - start > timeout_ms:
			return fail
	if file != null:
		file.close()
	return {"ok": http.get_status() == HTTPClient.STATUS_DISCONNECTED or http.get_status() == HTTPClient.STATUS_CONNECTED, "body": out}
