extends RefCounted
## NPC Engine — isi pulau (data/islandN.json): penduduk, dialog, tempat, papan.
## Murni data: memilih kalimat dialog (perkenalan pertama / kalimat berikutnya), mencatat siapa yang sudah
## ditemui (p.world.met) dan tempat yang sudah ditemukan (p.world.found). Bisa diuji tanpa layar.

const DIR := "res://games/education_sd/data/"

var layout: Dictionary = {}
var npcs: Dictionary = {}  # id -> npc
var places: Dictionary = {}  # id -> tempat
var errors: Array[String] = []


func load_layout(file: String) -> bool:
	errors.clear()
	npcs.clear()
	places.clear()
	var path := DIR + file
	if file == "" or not FileAccess.file_exists(path):
		errors.append("tata letak pulau tidak ada: " + path)
		return false
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("tata letak rusak: " + path)
		return false
	layout = v
	for n in v.get("npcs", []):
		for k in ["id", "name", "role", "model", "pos", "lines"]:
			if not n.has(k):
				errors.append("npc %s tanpa %s" % [str(n.get("id", "?")), k])
		if npcs.has(str(n.id)):
			errors.append("id npc ganda: " + str(n.id))
		npcs[str(n.id)] = n
	for pl in v.get("places", []):
		for k in ["id", "name", "pos", "radius"]:
			if not pl.has(k):
				errors.append("tempat %s tanpa %s" % [str(pl.get("id", "?")), k])
		places[str(pl.id)] = pl
	return errors.is_empty()


static func _key(island_id: String, id: String) -> String:
	return island_id + "/" + id


static func _fill(text: String, p: Dictionary) -> String:
	return text.replace("{name}", str(p.profile.name))


## Kalimat untuk bicara dengan NPC `id`. Pertemuan pertama: "lines"; berikutnya: "again" (bila ada).
## Mencatat pertemuan di p.world.met. Mengembalikan {name, role, lines: Array[String], first: bool}.
func talk(p: Dictionary, island_id: String, id: String) -> Dictionary:
	var n: Dictionary = npcs.get(id, {})
	if n.is_empty():
		return {}
	if not p.world.has("met"):
		p.world["met"] = {}
	var k := _key(island_id, id)
	var first := not (p.world.met as Dictionary).has(k)
	var src: Array = n.lines if first or (n.get("again", []) as Array).is_empty() else n.again
	var out: Array = []
	for l in src:
		out.append(_fill(str(l), p))
	p.world.met[k] = int(p.world.met.get(k, 0)) + 1
	return {"name": str(n.name), "role": str(n.role), "lines": out, "first": first}


func met_count(p: Dictionary, island_id: String) -> int:
	var c := 0
	for id in npcs:
		if (p.world.get("met", {}) as Dictionary).has(_key(island_id, id)):
			c += 1
	return c


## Tandai tempat ditemukan. true bila baru pertama kali.
func discover(p: Dictionary, island_id: String, place_id: String) -> bool:
	if not places.has(place_id):
		return false
	if not p.world.has("found"):
		p.world["found"] = {}
	var k := _key(island_id, place_id)
	if (p.world.found as Dictionary).has(k):
		return false
	p.world.found[k] = true
	return true


func found_count(p: Dictionary, island_id: String) -> int:
	var c := 0
	for id in places:
		if (p.world.get("found", {}) as Dictionary).has(_key(island_id, id)):
			c += 1
	return c


## Tempat yang memuat titik (x, z), yang paling kecil lebih dulu (mis. Dermaga di dalam Desa).
func place_at(x: float, z: float) -> String:
	var best := ""
	var best_r := INF
	for id in places:
		var pl: Dictionary = places[id]
		var d := Vector2(x - float(pl.pos[0]), z - float(pl.pos[1])).length()
		if d <= float(pl.radius) and float(pl.radius) < best_r:
			best_r = float(pl.radius)
			best = id
	return best
