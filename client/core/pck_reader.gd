extends RefCounted
## Membaca header dan direktori berkas .pck Godot TANPA memuatnya, supaya isi paket bisa diperiksa
## sebelum ProjectSettings.load_resource_pack(): versi mesin, enkripsi, dan daftar path.
## Format (Godot 4.4+, pack format 3/4): lihat docs/PCK_PACKAGE_FORMAT.md

const MAGIC := 0x43504447  # "GDPC" little-endian
const FLAG_DIR_ENCRYPTED := 1
const FLAG_REL_FILEBASE := 2
const MAX_FILES := 20000

## Berkas di luar namespace game yang boleh ada karena SELALU diikutkan ekspor Godot. Paket dimuat dengan
## replace_files=false, jadi berkas ini tidak pernah menimpa milik aplikasi (diabaikan).
const ENGINE_FILES := ["project.binary", ".godot/uid_cache.bin", ".godot/global_script_class_cache.cfg",
	"icon.svg.import", "icon.svg", "assets/icon/icon_512.png"]


## {ok, error, format, engine: [maj, min, patch], files: [{path, offset, size, flags}]}
static func read(path: String) -> Dictionary:
	var out := {"ok": false, "error": "", "format": 0, "engine": [0, 0, 0], "files": []}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out.error = "Paket tidak bisa dibuka"
		return out
	var length := f.get_length()
	if length < 40 or f.get_32() != MAGIC:
		out.error = "Bukan berkas PCK"
		return out
	var fmt := f.get_32()
	out.format = fmt
	out.engine = [f.get_32(), f.get_32(), f.get_32()]
	if fmt < 3 or fmt > 4:
		out.error = "Format PCK %d tidak didukung" % fmt
		return out
	var flags := f.get_32()
	if flags & FLAG_DIR_ENCRYPTED:
		out.error = "Direktori PCK terenkripsi tidak didukung"
		return out
	if flags & ~FLAG_REL_FILEBASE:
		out.error = "Flag PCK tidak dikenal: %d" % flags
		return out
	var file_base := f.get_64()
	var dir_offset := f.get_64()
	if dir_offset < 40 or dir_offset >= length:
		out.error = "Offset direktori PCK rusak"
		return out
	var base := file_base if flags & FLAG_REL_FILEBASE else 0
	f.seek(dir_offset)
	var count := f.get_32()
	if count > MAX_FILES:
		out.error = "Jumlah berkas PCK tidak wajar"
		return out
	var files: Array = []
	for i in count:
		if f.get_position() + 4 > length:
			out.error = "Direktori PCK terpotong"
			return out
		var plen := f.get_32()
		if plen == 0 or plen > 4096 or f.get_position() + plen + 36 > length:
			out.error = "Path PCK rusak"
			return out
		var raw := f.get_buffer(plen)
		var p := raw.get_string_from_utf8()  # berhenti di \0 padding
		var off := f.get_64()
		var size := f.get_64()
		f.get_buffer(16)  # md5
		var fflags := f.get_32()
		if base + off + size > length:
			out.error = "Isi berkas PCK di luar batas: " + p
			return out
		files.append({"path": p.trim_prefix("res://"), "offset": base + off, "size": size, "flags": fflags})
	f.close()
	out.files = files
	out.ok = true
	return out


## Periksa daftar path paket game `game_id`. "" = aman, selain itu alasan penolakan.
## Aturan: semua berkas di res://games/<id>/, atau berkas hasil ekspor yang dialamatkan oleh hash path
## (.godot/exported, .godot/imported), atau berkas mesin yang selalu ikut (ENGINE_FILES).
## Berkas terenkripsi atau berflag "hapus" (removal) ditolak.
static func check_paths(files: Array, game_id: String) -> String:
	var ns := "games/%s/" % game_id
	var has_ns := false
	for e: Dictionary in files:
		var p := str(e.path)
		if int(e.flags) != 0:
			return "Berkas PCK berflag khusus (enkripsi/hapus) ditolak: " + p
		if p.contains("..") or p.begins_with("/") or p.contains("\\") or p.contains("//"):
			return "Path PCK tidak aman: " + p
		if p.begins_with(ns):
			has_ns = true
			continue
		if p.begins_with("games/"):
			return "Paket menyentuh namespace game lain: " + p
		if p.begins_with(".godot/exported/") or p.begins_with(".godot/imported/"):
			continue
		if p in ENGINE_FILES:
			continue
		return "Berkas di luar namespace res://%s: %s" % [ns, p]
	if not has_ns:
		return "Paket tidak berisi res://%s" % ns
	return ""
