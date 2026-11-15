extends RefCounted
## World Engine — data enam pulau (data/islands.json) dan aturan perpindahan pulau.
## Aturan buka pulau:
##   - Pulau yang belum dibangun ("available": false) tampil "Segera hadir" dan tidak bisa dikunjungi.
##   - Pulau 1 selalu terbuka.
##   - Pulau dengan kelas <= kelas petualang terbuka (anak kelas 4 tidak dipaksa mengulang pulau kelas 1–3).
##   - Pulau berikutnya terbuka setelah bos pulau sebelumnya dikalahkan (world.bosses[id] = true).

const PATH := "res://games/education_sd/data/islands.json"

var doc: Dictionary = {}
var islands: Array = []
var by_id: Dictionary = {}
var errors: Array[String] = []


func load_data(path: String = PATH) -> bool:
	errors.clear()
	islands.clear()
	by_id.clear()
	if not FileAccess.file_exists(path):
		errors.append("berkas tidak ada: " + path)
		return false
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("islands")) != TYPE_ARRAY:
		errors.append("islands.json rusak")
		return false
	doc = v
	for isl in v.islands:
		var why := validate(isl)
		if why != "":
			errors.append(why)
			continue
		islands.append(isl)
		by_id[str(isl.id)] = isl
	if islands.size() != 6:
		errors.append("harus ada 6 pulau, ada %d" % islands.size())
	return errors.is_empty()


func validate(isl) -> String:
	if typeof(isl) != TYPE_DICTIONARY:
		return "pulau bukan objek"
	for k in ["id", "number", "grade", "name", "theme", "color", "map_pos", "boss", "learn", "intro"]:
		if not isl.has(k):
			return "pulau %s tanpa %s" % [str(isl.get("id", "?")), k]
	if by_id.has(str(isl.id)):
		return "id pulau ganda: " + str(isl.id)
	if int(isl.grade) < 1 or int(isl.grade) > 6:
		return "kelas pulau %s tidak sah" % str(isl.id)
	return ""


func island(id: String) -> Dictionary:
	return by_id.get(id, {})


func index_of(id: String) -> int:
	for i in islands.size():
		if str(islands[i].id) == id:
			return i
	return -1


## Status satu pulau untuk petualang `p`: "open" | "locked" | "soon".
func status(id: String, p: Dictionary) -> String:
	var isl := island(id)
	if isl.is_empty() or not bool(isl.get("available", false)):
		return "soon"
	var i := index_of(id)
	if i == 0 or int(isl.grade) <= int(p.profile.grade):
		return "open"
	if bool((p.world.bosses as Dictionary).get(str(islands[i - 1].id), false)):
		return "open"
	return "locked"


func lock_reason(id: String, p: Dictionary) -> String:
	match status(id, p):
		"soon":
			return "Pulau ini sedang dibangun. Segera hadir!"
		"locked":
			var prev: Dictionary = islands[maxi(index_of(id) - 1, 0)]
			return "Kalahkan %s di %s untuk membuka pulau ini." % [str(prev.boss.name), str(prev.name)]
	return ""


## Pulau awal untuk petualang: pulau terbuka dengan kelas tertinggi yang tidak melebihi kelasnya.
func start_island(p: Dictionary) -> String:
	var best := str(islands[0].id) if not islands.is_empty() else "pulau1"
	for isl in islands:
		if status(str(isl.id), p) == "open" and int(isl.grade) <= int(p.profile.grade):
			best = str(isl.id)
	return best


## Pindah ke pulau `id` bila terbuka. Mengembalikan "" bila berhasil, atau alasan penolakan.
func travel(p: Dictionary, id: String) -> String:
	if status(id, p) != "open":
		return lock_reason(id, p)
	if str(p.world.island) != id:
		p.world.sailed = int(p.world.sailed) + 1
	p.world.island = id
	(p.world.visited as Dictionary)[id] = true
	return ""
