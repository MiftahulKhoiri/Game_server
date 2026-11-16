extends RefCounted
## Quest Engine — misi utama & sampingan satu pulau (data/questsN.json).
## Langkah misi: learn (latihan di akademi), talk (bicara/antar ke penduduk), collect (kumpulkan barang yang
## tersebar), challenge (teka-teki belajar di penduduk / batu / papan), use (pakai barang pada sesuatu,
## mis. kunci di gerbang), places_all (temukan semua tempat), meet_all (kenal semua penduduk).
## Status di p.quests[id] = {state: "active"|"done", step, n}; barang di p.rpg.items; bendera dunia
## (gua terbuka, gerbang terbuka) di p.world.flags; barang yang sudah dipungut di p.world.picked.
## Murni data: bisa diuji tanpa layar.

const DIR := "res://games/education_sd/data/"

var doc: Dictionary = {}
var quests: Array = []
var by_id: Dictionary = {}
var items: Dictionary = {}
var challenges: Dictionary = {}
var island_id := ""
var errors: Array[String] = []
const STEP_TYPES := ["learn", "talk", "collect", "challenge", "use", "places_all", "meet_all"]


func load_quests(file: String) -> bool:
	errors.clear()
	quests.clear()
	by_id.clear()
	var path := DIR + file
	if file == "" or not FileAccess.file_exists(path):
		errors.append("berkas misi tidak ada: " + path)
		return false
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("berkas misi rusak")
		return false
	doc = v
	island_id = str(v.get("island", ""))
	items = v.get("items", {})
	challenges = v.get("challenges", {})
	for q in v.get("quests", []):
		var why := _validate(q)
		if why != "":
			errors.append(why)
			continue
		quests.append(q)
		by_id[str(q.id)] = q
	return errors.is_empty()


func _validate(q) -> String:
	for k in ["id", "kind", "title", "steps", "reward"]:
		if not q.has(k):
			return "misi %s tanpa %s" % [str(q.get("id", "?")), k]
	if by_id.has(str(q.id)):
		return "id misi ganda: " + str(q.id)
	if not bool(q.get("auto", false)) and not q.has("giver"):
		return "misi %s tanpa pemberi" % str(q.id)
	for s in q.steps:
		if not STEP_TYPES.has(str(s.get("type", ""))):
			return "misi %s: langkah %s tidak dikenal" % [str(q.id), str(s.get("type", ""))]
		if str(s.type) == "collect" and (not items.has(str(s.get("item", ""))) or (s.get("pickups", []) as Array).size() < int(s.get("count", 1))):
			return "misi %s: barang/pungutan kurang" % str(q.id)
		if str(s.type) == "challenge" and not challenges.has(str(s.get("challenge", ""))):
			return "misi %s: tantangan %s tidak ada" % [str(q.id), str(s.get("challenge", ""))]
	return ""


static func _ensure(p: Dictionary) -> void:
	for k in ["flags", "picked"]:
		if not p.world.has(k):
			p.world[k] = {}
	if not p.rpg.has("items"):
		p.rpg["items"] = {}


static func fill(text: String, p: Dictionary) -> String:
	return text.replace("{name}", str(p.profile.name))


func state(p: Dictionary, id: String) -> String:
	return str((p.quests as Dictionary).get(id, {}).get("state", ""))


func step(p: Dictionary, id: String) -> Dictionary:
	var q: Dictionary = by_id.get(id, {})
	var rec: Dictionary = (p.quests as Dictionary).get(id, {})
	if q.is_empty() or str(rec.get("state", "")) != "active":
		return {}
	var i := int(rec.get("step", 0))
	return q.steps[i] if i < (q.steps as Array).size() else {}


func requires_met(p: Dictionary, q: Dictionary) -> bool:
	for r in q.get("requires", []):
		if state(p, str(r)) != "done":
			return false
	return true


## Misi yang bisa ditawarkan penduduk `npc` sekarang (utama didahulukan). {} bila tidak ada.
func offer_for(p: Dictionary, npc: String) -> Dictionary:
	for kind in ["main", "side"]:
		for q in quests:
			if str(q.kind) == kind and str(q.get("giver", "")) == npc and state(p, str(q.id)) == "" and requires_met(p, q):
				return q
	return {}


func active(p: Dictionary) -> Array:
	var out: Array = []
	for kind in ["main", "side"]:
		for q in quests:
			if str(q.kind) == kind and state(p, str(q.id)) == "active":
				out.append(str(q.id))
	return out


func count_item(p: Dictionary, item: String) -> int:
	_ensure(p)
	return int((p.rpg.items as Dictionary).get(item, 0))


static func _add_item(p: Dictionary, item: String, n: int) -> void:
	var have := int((p.rpg.items as Dictionary).get(item, 0)) + n
	if have <= 0:
		(p.rpg.items as Dictionary).erase(item)
	else:
		p.rpg.items[item] = have


## Mulai misi. Mengembalikan catatan (langkah yang langsung selesai, mis. barang sudah dimiliki).
func start(p: Dictionary, id: String, ctx: Dictionary = {}) -> Array:
	_ensure(p)
	var q: Dictionary = by_id.get(id, {})
	if q.is_empty() or state(p, id) != "" or not requires_met(p, q):
		return []
	p.quests[id] = {"state": "active", "step": 0, "n": 0}
	var notes: Array = [{"kind": "start", "quest": id, "title": str(q.title), "text": "Misi baru: " + str(q.title)}]
	notes.append_array(_settle(p, id, ctx))
	return notes


## Misi otomatis (tanpa pemberi) dimulai sendiri.
func start_auto(p: Dictionary, ctx: Dictionary = {}) -> Array:
	var notes: Array = []
	for q in quests:
		if bool(q.get("auto", false)) and state(p, str(q.id)) == "" and requires_met(p, q):
			notes.append_array(start(p, str(q.id), ctx))
	return notes


## Langkah yang sudah terpenuhi (barang cukup, tempat semua ditemukan) langsung maju.
func _settle(p: Dictionary, id: String, ctx: Dictionary) -> Array:
	var notes: Array = []
	var guard := 0
	while guard < 10:
		guard += 1
		var s := step(p, id)
		if s.is_empty():
			break
		var ok := false
		match str(s.type):
			"collect":
				ok = count_item(p, str(s.item)) >= int(s.get("count", 1))
			"places_all":
				ok = ctx.has("found") and int(ctx.found) >= int(ctx.places)
			"meet_all":
				ok = ctx.has("met") and int(ctx.met) >= int(ctx.npcs)
		if not ok:
			break
		notes.append_array(_advance(p, id))
	return notes


func _advance(p: Dictionary, id: String) -> Array:
	var q: Dictionary = by_id[id]
	var rec: Dictionary = p.quests[id]
	var s: Dictionary = q.steps[int(rec.step)]
	var notes: Array = []
	for f in s.get("flags", []):
		p.world.flags[str(f)] = true
	for it in (s.get("take", {}) as Dictionary):
		_add_item(p, str(it), -int(s.take[it]))
	var say: Array = []
	for l in s.get("say", []):
		say.append(fill(str(l), p))
	notes.append({"kind": "step", "quest": id, "title": str(q.title), "text": "Selesai: " + str(s.get("text", "")), "say": say})
	rec.step = int(rec.step) + 1
	rec.n = 0
	if int(rec.step) >= (q.steps as Array).size():
		rec.state = "done"
		var rw: Dictionary = q.reward
		p.rpg.coins = int(p.rpg.coins) + int(rw.get("coins", 0))
		p.rpg.xp = int(p.rpg.xp) + int(rw.get("xp", 0))
		for it in (rw.get("items", {}) as Dictionary):
			_add_item(p, str(it), int(rw.items[it]))
		if str(rw.get("outfit", "")) != "" and not (p.rpg.owned as Array).has(str(rw.outfit)):
			(p.rpg.owned as Array).append(str(rw.outfit))
		for f in rw.get("flags", []):
			p.world.flags[str(f)] = true
		notes.append({"kind": "done", "quest": id, "title": str(q.title), "text": "Misi selesai: %s!" % str(q.title),
			"reward": reward_text(rw)})
	return notes


func reward_text(rw: Dictionary) -> String:
	var parts: Array = []
	if int(rw.get("coins", 0)) > 0:
		parts.append("+%d koin" % int(rw.coins))
	if int(rw.get("xp", 0)) > 0:
		parts.append("+%d XP" % int(rw.xp))
	for it in (rw.get("items", {}) as Dictionary):
		parts.append("%s ×%d" % [str(items.get(it, {}).get("name", it)), int(rw.items[it])])
	if str(rw.get("outfit", "")) != "":
		parts.append("baju baru")
	return ", ".join(parts)


## Kejadian di dunia. kind: learn | talk(npc) | pickup(uid) | challenge(id) | use(target) | world(ctx saja).
## ctx: {found, places, met, npcs} untuk langkah jelajah. Mengembalikan catatan untuk ditampilkan.
func event(p: Dictionary, kind: String, arg: String = "", ctx: Dictionary = {}) -> Array:
	_ensure(p)
	var notes: Array = []
	if kind == "pickup":
		var pk := pickup(arg)
		if pk.is_empty() or (p.world.picked as Dictionary).has(arg):
			return notes
		p.world.picked[arg] = true
		_add_item(p, str(pk.item), 1)
		notes.append({"kind": "item", "quest": str(pk.quest), "text": "Dapat %s (%d/%d)" % [str(items.get(str(pk.item), {}).get("name", pk.item)),
			count_item(p, str(pk.item)), int(pk.count)]})
	for id in active(p):
		var s := step(p, id)
		if s.is_empty():
			continue
		var hit := false
		match str(s.type):
			"learn":
				if kind == "learn":
					p.quests[id].n = int(p.quests[id].n) + 1
					hit = int(p.quests[id].n) >= int(s.get("count", 1))
			"talk":
				hit = kind == "talk" and arg == str(s.npc) and _has_take(p, s)
			"challenge":
				hit = kind == "challenge" and arg == str(s.challenge)
			"use":
				hit = kind == "use" and arg == str(s.target) and count_item(p, str(s.get("item", ""))) > 0
		if hit:
			notes.append_array(_advance(p, id))
		notes.append_array(_settle(p, id, ctx))
	notes.append_array(start_auto(p, ctx))
	return notes


func _has_take(p: Dictionary, s: Dictionary) -> bool:
	for it in (s.get("take", {}) as Dictionary):
		if count_item(p, str(it)) < int(s.take[it]):
			return false
	return true


## Langkah aktif yang ditangani penduduk/tempat ini: {quest, step} (talk atau challenge), atau {}.
func step_at(p: Dictionary, npc := "", spot := "") -> Dictionary:
	for id in active(p):
		var s := step(p, id)
		if s.is_empty():
			continue
		if npc != "" and str(s.get("npc", "")) == npc and str(s.type) in ["talk", "challenge"]:
			return {"quest": id, "step": s}
		if spot != "" and str(s.get("spot", "")) == spot and str(s.type) == "challenge":
			return {"quest": id, "step": s}
		if spot != "" and str(s.type) == "use" and str(s.get("target", "")) == spot:
			return {"quest": id, "step": s}
	return {}


## Daftar pungutan: [{uid, item, pos, quest, count}] — semua, atau hanya yang tampil sekarang (misi aktif
## pada langkah collect itu, belum dipungut).
func pickups(p: Dictionary = {}, visible_only := false) -> Array:
	var out: Array = []
	for q in quests:
		for si in (q.steps as Array).size():
			var s: Dictionary = q.steps[si]
			if str(s.type) != "collect":
				continue
			var pts: Array = s.pickups
			for i in pts.size():
				var uid := "%s/%s_%d" % [str(q.id), str(s.item), i]
				var e := {"uid": uid, "item": str(s.item), "pos": pts[i], "quest": str(q.id), "count": int(s.get("count", 1))}
				if visible_only:
					if (p.world.get("picked", {}) as Dictionary).has(uid):
						continue
					var rec: Dictionary = (p.quests as Dictionary).get(str(q.id), {})
					if str(rec.get("state", "")) != "active" or int(rec.get("step", 0)) != si:
						continue
				out.append(e)
	return out


func pickup(uid: String) -> Dictionary:
	for e in pickups():
		if str(e.uid) == uid:
			return e
	return {}


## Tujuan langkah aktif misi utama (atau sampingan bila tidak ada): {quest, title, text, where}.
func objective(p: Dictionary) -> Dictionary:
	for id in active(p):
		var s := step(p, id)
		if s.is_empty() or str(s.type) in ["places_all", "meet_all"]:
			continue
		var text := str(s.get("text", ""))
		if str(s.type) == "collect":
			text += " (%d/%d)" % [mini(count_item(p, str(s.item)), int(s.get("count", 1))), int(s.get("count", 1))]
		return {"quest": id, "title": str(by_id[id].title), "text": text, "where": s.get("where", {})}
	return {}


## Penduduk yang punya misi baru (tanda "!") atau langkah untuknya (tanda "?").
func marks(p: Dictionary) -> Dictionary:
	var out := {}
	for q in quests:
		var g := str(q.get("giver", ""))
		if g != "" and state(p, str(q.id)) == "" and requires_met(p, q):
			out[g] = "!"
	for id in active(p):
		var s := step(p, id)
		if str(s.get("npc", "")) != "":
			out[str(s.npc)] = "?"
	return out


func done_count(p: Dictionary, kind := "") -> int:
	var c := 0
	for q in quests:
		if (kind == "" or str(q.kind) == kind) and state(p, str(q.id)) == "done":
			c += 1
	return c


## Soal untuk tantangan: topik pertama dari "prefer" yang punya isi untuk kelas anak.
func challenge_topic(id: String, data, grade: int) -> String:
	var c: Dictionary = challenges.get(id, {})
	for t in c.get("prefer", []):
		if data.has_content(str(t), grade):
			return str(t)
	for t in c.get("prefer", []):
		if data.easier_grade(str(t), grade) > 0:
			return str(t)
	return ""
