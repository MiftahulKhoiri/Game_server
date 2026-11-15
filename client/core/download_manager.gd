extends Node
## Pengunduh paket game: streaming ke berkas sementara (.part), progres, lanjut (HTTP Range) setelah
## koneksi putus, batal, cek ruang penyimpanan, dan batas waktu macet. TIDAK memverifikasi isi; itu tugas
## PackageManager setelah unduhan selesai. Aturan: docs/DOWNLOAD_SYSTEM.md
##
## Sumber dibatasi: hanya server game yang dikonfigurasi, path di bawah /v1/games/, dan HTTPS (HTTP biasa
## hanya untuk alamat lokal/LAN: 127.x, 10.x, 192.168.x, 172.16-31.x — tanda tangan tetap diperiksa).

signal progress(id: String, received: int, total: int)
signal finished(id: String, ok: bool, error: String, path: String)

const CACHE_DIR := "user://user_data/cache/downloads"
const CHUNK := 64 * 1024
const CONNECT_TIMEOUT_MS := 15000
const STALL_TIMEOUT_MS := 30000
const SPACE_MARGIN := 8 * 1024 * 1024
const PATH_PREFIX := "/v1/games/"

enum Phase { CONNECTING, REQUESTING, BODY }

var _jobs: Dictionary = {}  # id -> job (Dictionary)
## Untuk uji: batasi byte per frame (0 = tanpa batas) dan paksa putus setelah N byte (0 = tidak).
var throttle_bytes_per_poll := 0
var fail_after_bytes := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	set_process(false)


static func part_path(id: String, version: String) -> String:
	return "%s/%s-%s.part" % [CACHE_DIR, id, version]


static func is_allowed_url(base_url: String, path: String) -> String:
	if not path.begins_with(PATH_PREFIX) or path.contains("..") or path.contains("//") or path.contains("\\"):
		return "Alamat paket di luar /v1/games/"
	if base_url.begins_with("https://"):
		return ""
	if not base_url.begins_with("http://"):
		return "Alamat server tidak sah"
	var host := base_url.trim_prefix("http://").split("/")[0].split(":")[0]
	if host == "localhost" or host.begins_with("127.") or host.begins_with("10.") or host.begins_with("192.168."):
		return ""
	if host.begins_with("172."):
		var second := int(host.split(".")[1]) if host.split(".").size() > 1 else 0
		if second >= 16 and second <= 31:
			return ""
	return "Unduhan paket wajib lewat HTTPS"


func is_active(id: String) -> bool:
	return _jobs.has(id)


## Mulai / lanjutkan unduhan. Mengembalikan "" atau alasan gagal langsung.
func start(id: String, base_url: String, path: String, dest: String, expected_size: int) -> String:
	if _jobs.has(id):
		return "Sedang diunduh"
	var why := is_allowed_url(base_url, path)
	if why != "":
		return why
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var have := 0
	if FileAccess.file_exists(dest):
		var f := FileAccess.open(dest, FileAccess.READ)
		have = f.get_length() if f != null else 0
		if f != null:
			f.close()
		if have > expected_size:
			DirAccess.remove_absolute(dest)
			have = 0
	if have == expected_size and expected_size > 0:
		finished.emit.call_deferred(id, true, "", dest)
		return ""
	var space := _space_left()
	if space >= 0 and space < (expected_size - have) + SPACE_MARGIN:
		return "Ruang penyimpanan tidak cukup (butuh %s, tersisa %s)" % [_mb(expected_size - have + SPACE_MARGIN), _mb(space)]
	var https := base_url.begins_with("https://")
	var rest := base_url.trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	var host := rest
	var port := 443 if https else 80
	var colon := rest.rfind(":")
	if colon > 0:
		host = rest.substr(0, colon)
		port = int(rest.substr(colon + 1))
	var http := HTTPClient.new()
	http.read_chunk_size = CHUNK
	var err := http.connect_to_host(host, port, TLSOptions.client() if https else null)
	if err != OK:
		return "Tidak bisa menghubungi server (kode %d)" % err
	_jobs[id] = {
		"id": id, "http": http, "path": path, "dest": dest, "expected": expected_size, "have": have,
		"phase": Phase.CONNECTING, "file": null, "received": have, "total": expected_size,
		"started": Time.get_ticks_msec(), "last": Time.get_ticks_msec(), "retried_416": false,
		"base_url": base_url,
	}
	set_process(true)
	progress.emit(id, have, expected_size)
	return ""


## Batalkan unduhan dan hapus berkas sementaranya.
func cancel(id: String) -> void:
	if not _jobs.has(id):
		return
	var job: Dictionary = _jobs[id]
	_close(job)
	DirAccess.remove_absolute(job.dest)
	_jobs.erase(id)
	finished.emit(id, false, "Dibatalkan", "")


func _process(_delta: float) -> void:
	for id in _jobs.keys():
		_poll(_jobs[id])
	if _jobs.is_empty():
		set_process(false)


func _poll(job: Dictionary) -> void:
	var http: HTTPClient = job.http
	http.poll()
	var st := http.get_status()
	var now := Time.get_ticks_msec()
	match job.phase:
		Phase.CONNECTING:
			if st == HTTPClient.STATUS_CONNECTED:
				var headers := PackedStringArray(["Accept: application/octet-stream",
					"X-Client-Version: " + str(ProjectSettings.get_setting("application/config/version", ""))])
				if int(job.have) > 0:
					headers.append("Range: bytes=%d-" % int(job.have))
				if http.request(HTTPClient.METHOD_GET, job.path, headers) != OK:
					_fail(job, "Permintaan unduhan gagal dikirim", true)
					return
				job.phase = Phase.REQUESTING
				job.last = now
			elif st in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
				_fail(job, "Server tidak terjangkau", true)
			elif now - int(job.started) > CONNECT_TIMEOUT_MS:
				_fail(job, "Waktu menghubungi server habis", true)
		Phase.REQUESTING:
			if st == HTTPClient.STATUS_BODY or (st == HTTPClient.STATUS_CONNECTED and http.has_response()):
				_on_response(job)
			elif st != HTTPClient.STATUS_REQUESTING:
				_fail(job, "Koneksi terputus", true)
			elif now - int(job.last) > STALL_TIMEOUT_MS:
				_fail(job, "Server tidak menjawab", true)
		Phase.BODY:
			if st == HTTPClient.STATUS_BODY:
				var got := 0
				while http.get_status() == HTTPClient.STATUS_BODY:
					var chunk := http.read_response_body_chunk()
					if chunk.is_empty():
						break
					(job.file as FileAccess).store_buffer(chunk)
					job.received = int(job.received) + chunk.size()
					got += chunk.size()
					if fail_after_bytes > 0 and int(job.received) >= fail_after_bytes:
						fail_after_bytes = 0
						_fail(job, "Koneksi terputus (uji)", true)
						return
					if int(job.received) > int(job.expected):
						_fail(job, "Server mengirim lebih banyak data daripada ukuran paket", false)
						return
					if throttle_bytes_per_poll > 0 and got >= throttle_bytes_per_poll:
						break
					http.poll()
				if got > 0:
					job.last = now
					progress.emit(job.id, int(job.received), int(job.total))
				elif now - int(job.last) > STALL_TIMEOUT_MS:
					_fail(job, "Unduhan macet", true)
			elif st == HTTPClient.STATUS_CONNECTED or st == HTTPClient.STATUS_DISCONNECTED:
				_complete(job)
			else:
				_fail(job, "Koneksi terputus", true)


func _on_response(job: Dictionary) -> void:
	var http: HTTPClient = job.http
	var code := http.get_response_code()
	var have := int(job.have)
	if code == 206 and have > 0:
		var f := FileAccess.open(job.dest, FileAccess.READ_WRITE)
		if f == null:
			_fail(job, "Berkas sementara tidak bisa ditulis", false)
			return
		f.seek_end()
		job.file = f
		job.received = have
	elif code == 200:
		var f := FileAccess.open(job.dest, FileAccess.WRITE)  # server tidak mendukung Range: mulai dari 0
		if f == null:
			_fail(job, "Berkas sementara tidak bisa ditulis", false)
			return
		job.file = f
		job.received = 0
	elif code == 416 and not bool(job.retried_416):
		# Berkas sementara tidak cocok dengan server (mis. paket diganti): mulai ulang dari awal.
		var base := str(job.base_url)
		var id := str(job.id)
		var path := str(job.path)
		var dest := str(job.dest)
		var expected := int(job.expected)
		_close(job)
		_jobs.erase(id)
		DirAccess.remove_absolute(dest)
		var why := start(id, base, path, dest, expected)
		if why != "":
			finished.emit(id, false, why, "")
		elif _jobs.has(id):
			_jobs[id].retried_416 = true
		return
	else:
		_fail(job, "Server menjawab %d" % code, code >= 500)
		return
	job.total = int(job.expected)
	job.phase = Phase.BODY
	job.last = Time.get_ticks_msec()


func _complete(job: Dictionary) -> void:
	_close(job)
	_jobs.erase(job.id)
	var size := 0
	var f := FileAccess.open(job.dest, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	if size != int(job.expected):
		# Kurang = koneksi terputus di tengah: simpan untuk dilanjutkan. Lebih = rusak: buang.
		if size > int(job.expected):
			DirAccess.remove_absolute(job.dest)
		finished.emit(job.id, false, "Unduhan tidak lengkap (%s dari %s), bisa dilanjutkan" % [_mb(size), _mb(job.expected)], "")
		return
	finished.emit(job.id, true, "", job.dest)


## keep_part: true = berkas sementara disimpan agar bisa dilanjutkan (koneksi putus).
func _fail(job: Dictionary, why: String, keep_part: bool) -> void:
	_close(job)
	_jobs.erase(job.id)
	if not keep_part:
		DirAccess.remove_absolute(job.dest)
	finished.emit(job.id, false, why, "")


func _close(job: Dictionary) -> void:
	if job.file != null:
		(job.file as FileAccess).close()
		job.file = null
	(job.http as HTTPClient).close()


static func _space_left() -> int:
	var d := DirAccess.open("user://")
	return d.get_space_left() if d != null else -1


static func _mb(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0)
