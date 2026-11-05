extends Node
## Pembaruan dari dalam aplikasi: unduh APK rilis terbaru, periksa, lalu serahkan ke
## pemasang Android. Pemain tidak perlu membuka halaman web.
##
## Alur Android (tanpa plugin, hanya GDScript + JavaClassWrapper):
##   1. Izin "Pasang aplikasi tak dikenal" (sekali saja; Android membukakan pengaturannya).
##   2. Unduh APK dari GitHub Releases ke user:// lalu periksa ukuran dan sha256.
##   3. Salin ke folder Download lewat MediaStore (tanpa izin penyimpanan, Android 10+),
##      lalu buka pemasang sistem dengan content:// URI. Pemain cukup menekan "Pasang".
## Di platform lain, atau bila ada langkah gagal, pemanggil membuka halaman unduhan.

signal status(text: String)
signal progress(received: int, total: int)

const SAVE_PATH := "user://update.apk"
const MEDIA_NAME := "GamePetualang-update.apk"
const MIME_APK := "application/vnd.android.package-archive"
const CHUNK := 1048576  # 1 MiB per tulis, supaya memori tetap kecil
const UA := "User-Agent: GamePetualang"

var _http: HTTPRequest
var _expected_total := 0


# --- fungsi murni (diuji di e2e) ---

## https://github.com/<pemilik>/<repo>/releases/... -> alamat API rilis terbaru ("" bila bukan GitHub).
static func api_url_for(update_url: String) -> String:
	var re := RegEx.new()
	re.compile("^https://github\\.com/([^/]+)/([^/]+)/releases")
	var m := re.search(update_url)
	if m == null:
		return ""
	return "https://api.github.com/repos/%s/%s/releases/latest" % [m.get_string(1), m.get_string(2)]


## Pilih berkas .apk dari JSON rilis GitHub. {} bila tidak ada.
static func pick_asset(release: Dictionary) -> Dictionary:
	for asset: Dictionary in release.get("assets", []):
		var name := str(asset.get("name", ""))
		var url := str(asset.get("browser_download_url", ""))
		if not name.ends_with(".apk") or url == "":
			continue
		var digest := str(asset.get("digest", ""))
		return {
			"name": name,
			"url": url,
			"size": int(asset.get("size", 0)),
			"sha256": digest.trim_prefix("sha256:") if digest.begins_with("sha256:") else "",
			"tag": str(release.get("tag_name", "")),
		}
	return {}


## Periksa berkas unduhan. "" = sah, selain itu pesan kesalahan.
static func verify(asset: Dictionary, path: String = SAVE_PATH) -> String:
	if not FileAccess.file_exists(path):
		return "Berkas unduhan tidak ditemukan."
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Berkas unduhan tidak bisa dibaca."
	var size := f.get_length()
	f.close()
	if size < 1024:
		return "Berkas unduhan terlalu kecil."
	var want_size := int(asset.get("size", 0))
	if want_size > 0 and size != want_size:
		return "Ukuran berkas tidak cocok (%d dari %d byte)." % [size, want_size]
	var want_hash := str(asset.get("sha256", ""))
	if want_hash != "" and FileAccess.get_sha256(path) != want_hash:
		return "Sidik jari berkas tidak cocok. Unduhan dibatalkan."
	return ""


## Pemasangan otomatis hanya ada di Android.
static func supported() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime")


## Hapus sisa unduhan lama (setelah pembaruan berhasil, berkas ini tidak berguna lagi).
static func cleanup() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# --- alur utama ---

## Hasil: {"ok": bool, "message": String, "web": bool}. web = true berarti
## pemanggil sebaiknya menawarkan halaman unduhan sebagai cadangan.
func run(update_url: String) -> Dictionary:
	if not supported():
		return {"ok": false, "message": "Pasang otomatis hanya tersedia di Android.", "web": true}
	if not _can_install():
		_open_install_settings()
		return {"ok": false, "web": false, "message":
			"Aktifkan \"Izinkan dari sumber ini\" untuk Game Petualang, lalu kembali dan tekan tombol lagi."}

	status.emit("Memeriksa versi terbaru...")
	var info: Dictionary = await fetch_latest(update_url)
	if not info.ok:
		return {"ok": false, "message": str(info.error), "web": true}
	var asset: Dictionary = info.asset

	if verify(asset) != "":  # unduhan sebelumnya yang utuh dipakai lagi
		status.emit("Mengunduh %s..." % asset.name)
		var err: String = await download(asset)
		if err != "":
			return {"ok": false, "message": err, "web": true}
		err = verify(asset)
		if err != "":
			cleanup()
			return {"ok": false, "message": err, "web": true}

	status.emit("Membuka pemasang...")
	var install_err := _install(SAVE_PATH)
	if install_err != "":
		return {"ok": false, "message": install_err, "web": true}
	return {"ok": true, "web": false, "message": "Pemasang Android terbuka. Tekan Pasang, lalu buka aplikasi lagi."}


## Ambil info rilis terbaru dari GitHub. {"ok", "asset" | "error"}.
func fetch_latest(update_url: String) -> Dictionary:
	var api := api_url_for(update_url)
	if api == "":
		return {"ok": false, "error": "Alamat pembaruan tidak dikenali."}
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(api, ["Accept: application/vnd.github+json", UA])
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Tidak bisa menghubungi GitHub."}
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return {"ok": false, "error": "Gagal membaca rilis terbaru (kode %d)." % int(r[1])}
	var data: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Balasan GitHub tidak terbaca."}
	var asset := pick_asset(data)
	if asset.is_empty():
		return {"ok": false, "error": "Rilis terbaru belum memuat APK."}
	return {"ok": true, "asset": asset}


## Unduh asset ke path. "" = berhasil, selain itu pesan kesalahan.
func download(asset: Dictionary, path: String = SAVE_PATH) -> String:
	_http = HTTPRequest.new()
	_http.download_file = path
	_http.max_redirects = 8
	add_child(_http)
	_expected_total = int(asset.get("size", 0))
	var err := _http.request(str(asset.url), [UA])
	if err != OK:
		_http.queue_free()
		_http = null
		return "Tidak bisa memulai unduhan."
	set_process(true)
	var r: Array = await _http.request_completed
	set_process(false)
	_http.queue_free()
	_http = null
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return "Unduhan gagal (hasil %d, kode %d). Periksa sambungan internet." % [int(r[0]), int(r[1])]
	return ""


func _process(_delta: float) -> void:
	if _http == null:
		return
	var total := _http.get_body_size()
	if total <= 0:
		total = _expected_total
	progress.emit(_http.get_downloaded_bytes(), total)


# --- Android ---

func _can_install() -> bool:
	var rt: Object = Engine.get_singleton("AndroidRuntime")
	var pm: Variant = rt.getApplicationContext().getPackageManager()
	if pm == null:
		return true  # tidak bisa dicek: biarkan sistem yang meminta
	var ok: Variant = pm.canRequestPackageInstalls()
	return ok == null or bool(ok)


func _open_install_settings() -> void:
	var rt: Object = Engine.get_singleton("AndroidRuntime")
	var ctx: Variant = rt.getApplicationContext()
	var Intent: Variant = JavaClassWrapper.wrap("android.content.Intent")
	var Uri: Variant = JavaClassWrapper.wrap("android.net.Uri")
	var uri: Variant = Uri.parse("package:" + str(ctx.getPackageName()))
	var intent: Variant = Intent.Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES", uri)
	intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
	rt.getActivity().startActivity(intent)


## Salin APK ke Download (MediaStore) lalu buka pemasang. "" = berhasil.
func _install(path: String) -> String:
	var rt: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Variant = rt.getActivity()
	var resolver: Variant = rt.getApplicationContext().getContentResolver()
	var sdk: int = JavaClassWrapper.wrap("android.os.Build$VERSION").SDK_INT
	if sdk < 29:
		return "Android di bawah 10 belum didukung untuk pasang otomatis."

	var Downloads: Variant = JavaClassWrapper.wrap("android.provider.MediaStore$Downloads")
	var table: Variant = Downloads.EXTERNAL_CONTENT_URI
	if table == null:
		return "Folder Download tidak bisa diakses."
	# Buang salinan lama agar namanya tidak jadi "(1)".
	resolver.delete(table, "_display_name='%s'" % MEDIA_NAME, null)

	var ContentValues: Variant = JavaClassWrapper.wrap("android.content.ContentValues")
	var values: Variant = ContentValues.ContentValues()
	values.put("_display_name", MEDIA_NAME)
	values.put("mime_type", MIME_APK)
	values.put("relative_path", "Download/")
	var uri: Variant = resolver.insert(table, values)
	if uri == null:
		return "Tidak bisa membuat berkas di folder Download."

	var out: Variant = resolver.openOutputStream(uri)
	var src := FileAccess.open(path, FileAccess.READ)
	if out == null or src == null:
		return "Tidak bisa menulis berkas pembaruan."
	while not src.eof_reached():
		var chunk := src.get_buffer(CHUNK)
		if chunk.is_empty():
			break
		out.write(chunk)
	out.flush()
	out.close()
	src.close()

	var Intent: Variant = JavaClassWrapper.wrap("android.content.Intent")
	var intent: Variant = Intent.Intent(Intent.ACTION_VIEW)
	intent.setDataAndType(uri, MIME_APK)
	intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK)
	activity.startActivity(intent)
	return ""
