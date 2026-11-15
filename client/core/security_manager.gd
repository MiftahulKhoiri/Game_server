extends RefCounted
## Keamanan paket game: tanda tangan digital (RSA + SHA-256), sidik SHA-256 berkas, dan validasi
## manifest / id / versi / path. Kunci PRIVAT tidak pernah ada di aplikasi; hanya kunci publik penerbit
## (res://config/publisher_public.pem) yang dibawa APK. Aturan lengkap: docs/SECURITY.md

const VersionManager := preload("res://core/version_manager.gd")

const PUBLIC_KEY_PATH := "res://config/publisher_public.pem"
const ID_RE := "^[a-z][a-z0-9_]{1,31}$"
## Batas ukuran paket yang mau diunduh (pengaman terhadap katalog/manifest yang aneh).
const MAX_PACKAGE_BYTES := 512 * 1024 * 1024
const MAX_MANIFEST_BYTES := 64 * 1024
const MANIFEST_FIELDS := ["id", "name", "version", "type", "entry_scene", "min_launcher_version",
	"min_engine_version"]
const DOWNLOAD_FIELDS := ["package", "size", "sha256"]
const SHA_RE := "^[0-9a-f]{64}$"

static var _key: CryptoKey = null
static var _key_tried := false


static func is_valid_id(id: String) -> bool:
	return _match(ID_RE, id)


static func _match(pattern: String, text: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return re.search(text) != null


## Path aman: tanpa "..", tanpa "\", tanpa karakter kontrol, tanpa skema lain, dan (bila prefix diisi)
## berada di bawah prefix itu.
static func is_safe_res_path(path: String, prefix: String = "") -> bool:
	if path == "" or path.contains("..") or path.contains("\\") or path.contains(":/") and not path.begins_with("res://"):
		return false
	for c in path:
		if c.unicode_at(0) < 32:
			return false
	var rest := path.trim_prefix("res://")
	if rest == "" or rest.begins_with("/") or rest.contains("//"):
		return false
	return prefix == "" or path.begins_with(prefix)


## Nama berkas paket: hanya huruf/angka/._- dan berakhiran .pck.
static func is_safe_package_name(name: String) -> bool:
	return _match("^[A-Za-z0-9._-]{1,80}\\.pck$", name) and not name.contains("..")


static func public_key() -> CryptoKey:
	if _key_tried:
		return _key
	_key_tried = true
	var f := FileAccess.open(PUBLIC_KEY_PATH, FileAccess.READ)
	if f == null:
		push_warning("[security] kunci publik penerbit tidak ada: " + PUBLIC_KEY_PATH)
		return null
	var k := CryptoKey.new()
	if k.load_from_string(f.get_as_text(), true) != OK:
		push_warning("[security] kunci publik penerbit rusak")
		return null
	_key = k
	return _key


## Untuk uji: pakai kunci publik lain (null = kembali ke kunci bawaan).
static func override_public_key(k: CryptoKey) -> void:
	_key = k
	_key_tried = k != null


## Periksa tanda tangan `sig_b64` (RSA PKCS#1 v1.5, SHA-256, base64) atas byte `data` persis.
static func verify_signature(data: PackedByteArray, sig_b64: String, key: CryptoKey = null) -> bool:
	if key == null:
		key = public_key()
	if key == null or data.is_empty():
		return false
	var sig := Marshalls.base64_to_raw(sig_b64.strip_edges())
	if sig.is_empty():
		return false
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	var digest := ctx.finish()
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest, sig, key)


## SHA-256 berkas (hex kecil); "" bila tidak bisa dibaca.
static func file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


static func file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n


## Periksa isi manifest. Mengembalikan "" bila sah, atau alasan penolakan.
## expected_id: bila diisi, id manifest harus sama (mencegah manifest game lain disisipkan).
static func validate_manifest(m: Dictionary, expected_id: String = "") -> String:
	for k in MANIFEST_FIELDS:
		if not m.has(k) or typeof(m[k]) != TYPE_STRING:
			return "Manifest tidak lengkap: " + k
	var id := str(m.id)
	if not is_valid_id(id):
		return "ID game tidak sah"
	if expected_id != "" and id != expected_id:
		return "ID manifest (%s) tidak sama dengan yang diminta (%s)" % [id, expected_id]
	if not VersionManager.is_valid(str(m.version)):
		return "Versi game tidak sah"
	if not VersionManager.is_valid(str(m.min_launcher_version)) or not VersionManager.is_valid(str(m.min_engine_version)):
		return "Versi minimum tidak sah"
	var t := str(m.type)
	if t != "builtin" and t != "download":
		return "Tipe game tidak dikenal"
	var entry := str(m.entry_scene)
	if not entry.ends_with(".tscn") and not entry.ends_with(".scn"):
		return "Entry scene harus .tscn/.scn"
	if t == "download":
		# Game unduhan WAJIB berada di namespace-nya sendiri.
		if not is_safe_res_path(entry, "res://games/%s/" % id):
			return "Entry scene di luar namespace res://games/%s/" % id
		for k in DOWNLOAD_FIELDS:
			if not m.has(k):
				return "Manifest paket tidak lengkap: " + k
		if not is_safe_package_name(str(m.package)):
			return "Nama paket tidak sah"
		if not _match(SHA_RE, str(m.sha256)):
			return "SHA-256 manifest tidak sah"
		var size = m.size
		if typeof(size) != TYPE_FLOAT and typeof(size) != TYPE_INT:
			return "Ukuran paket tidak sah"
		if int(size) <= 0 or int(size) > MAX_PACKAGE_BYTES:
			return "Ukuran paket di luar batas"
	elif not is_safe_res_path(entry, "res://"):
		return "Entry scene tidak sah"
	return ""


## Parse JSON objek dari byte; {} bila bukan objek.
static func parse_json_object(data: PackedByteArray) -> Dictionary:
	if data.size() == 0 or data.size() > 4 * 1024 * 1024:
		return {}
	var v = JSON.parse_string(data.get_string_from_utf8())
	return v if typeof(v) == TYPE_DICTIONARY else {}
