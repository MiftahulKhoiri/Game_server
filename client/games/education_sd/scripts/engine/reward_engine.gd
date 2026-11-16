extends RefCounted
## Reward Engine — sistem RPG petualang: level & kekuatan, naik level, kartu pengetahuan, prestasi,
## toko (barang & kostum), dan lemari kostum. Data: data/rpg.json + toko kostum di bank soal (pulau_ilmu.json).
## Murni data: bisa diuji tanpa layar.

const SaveEngine := preload("res://games/education_sd/scripts/engine/save_engine.gd")
const Learning := preload("res://games/education_sd/scripts/engine/learning_engine.gd")
const PATH := "res://games/education_sd/data/rpg.json"

var doc: Dictionary = {}
var data  # SdData
var costumes: Dictionary = {}  # id -> {id, value, price, slot}
var errors: Array[String] = []


func setup(sd_data) -> bool:
	data = sd_data
	errors.clear()
	var v = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("rpg.json tidak bisa dibaca")
		return false
	doc = v
	for s in data.doc.get("shop", []):
		var id := str(s.id)
		costumes[id] = {"id": id, "value": str(s.value), "price": int(s.get("price", 0)), "slot": slot_of(id)}
	for sh in doc.get("shop", {}):
		for id in doc.shop[sh].stock:
			if not doc.items.has(id) and not costumes.has(id):
				errors.append("barang toko tidak dikenal: " + str(id))
	return errors.is_empty()


static func slot_of(id: String) -> String:
	return "outfit" if id.begins_with("warna_") else ("hat" if id.begins_with("topi_") else "acc")


# --- Level & kekuatan ------------------------------------------------------------------------------------------

## Kekuatan petualang dari level dan ilmu yang dikuasai (dipakai pertarungan Tahap 6).
func stats(p: Dictionary) -> Dictionary:
	var lv := SaveEngine.level(p)
	var mastered := mastered_count(p)
	var cards := (p.learning.cards as Array).size()
	return {"level": lv, "hp": 40 + 8 * lv, "atk": 6 + 2 * lv, "def": 2 + lv, "ilmu": 10 + 3 * mastered + cards,
		"xp": int(p.rpg.xp), "xp_from": SaveEngine.xp_for(lv), "xp_next": SaveEngine.xp_for(lv + 1), "mastered": mastered, "cards": cards}


static func mastered_count(p: Dictionary) -> int:
	var n := 0
	for k in (p.learning.topics as Dictionary):
		var parts := str(k).split("/")
		if parts.size() == 2 and Learning.status(p, int(parts[0]), parts[1]) == "kuasai":
			n += 1
	return n


## Naik level sejak terakhir diperiksa: hadiah koin per level. Level pertama kali dicatat tanpa hadiah.
func level_check(p: Dictionary) -> Array:
	var lv := SaveEngine.level(p)
	if not p.rpg.has("level_seen"):
		p.rpg["level_seen"] = lv
		return []
	var notes: Array = []
	var seen := int(p.rpg.level_seen)
	while seen < lv:
		seen += 1
		var coins := 10 * seen
		p.rpg.coins = int(p.rpg.coins) + coins
		var st := stats(p)
		notes.append({"kind": "level", "level": seen, "text": "Naik level! Level %d" % seen,
			"detail": "HP %d · Serang %d · Pertahanan %d · +%d koin" % [int(st.hp), int(st.atk), int(st.def), coins]})
	p.rpg.level_seen = lv
	return notes


# --- Kartu pengetahuan -------------------------------------------------------------------------------------------

func card(topic_id: String) -> Dictionary:
	var t: Dictionary = data.topics.get(topic_id, {})
	return t.get("card", {}) if not t.is_empty() else {}


## Kartu topik diberikan saat latihan sempurna (3 bintang) atau materi dikuasai. Sekali per topik.
func on_session(p: Dictionary, topic_id: String, result: Dictionary) -> Array:
	if int(result.get("stars", 0)) < 3 and str(result.get("status", "")) != "kuasai":
		return []
	return give_card(p, topic_id)


func give_card(p: Dictionary, topic_id: String) -> Array:
	var c := card(topic_id)
	if c.is_empty() or (p.learning.cards as Array).has(topic_id):
		return []
	(p.learning.cards as Array).append(topic_id)
	return [{"kind": "card", "topic": topic_id, "text": "Kartu Pengetahuan baru: %s!" % str(c.get("title", "")), "fact": str(c.get("fact", ""))}]


func cards_total() -> int:
	var n := 0
	for t in data.topics:
		if not card(t).is_empty():
			n += 1
	return n


# --- Prestasi ------------------------------------------------------------------------------------------------------

## ctx: {main_quests, places} dari mesin misi/NPC (boleh kosong).
func stat_values(p: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var quests_done := 0
	for q in (p.quests as Dictionary):
		if str(p.quests[q].get("state", "")) == "done":
			quests_done += 1
	var sessions := 0
	for k in (p.academy as Dictionary):
		sessions += int(p.academy[k].get("sessions", 0))
	return {"quests": quests_done, "main_quests": int(ctx.get("main_quests", 0)), "sessions": sessions,
		"correct": int(p.learning.totals.correct), "best_streak": int(p.learning.totals.best_streak), "mastered": mastered_count(p),
		"cards": (p.learning.cards as Array).size(), "places": (p.world.get("found", {}) as Dictionary).size(),
		"costumes": (p.rpg.owned as Array).size(), "level": SaveEngine.level(p)}


func achievements(p: Dictionary, ctx: Dictionary = {}) -> Array:
	var vals := stat_values(p, ctx)
	var got: Dictionary = p.rpg.get("achievements", {})
	var out: Array = []
	for a in doc.get("achievements", []):
		out.append({"id": str(a.id), "name": str(a.name), "desc": str(a.desc), "goal": int(a.goal), "coins": int(a.coins),
			"value": mini(int(vals.get(str(a.stat), 0)), int(a.goal)), "done": got.has(str(a.id))})
	return out


func check_achievements(p: Dictionary, ctx: Dictionary = {}) -> Array:
	if not p.rpg.has("achievements"):
		p.rpg["achievements"] = {}
	var notes: Array = []
	var vals := stat_values(p, ctx)
	for a in doc.get("achievements", []):
		if (p.rpg.achievements as Dictionary).has(str(a.id)):
			continue
		if int(vals.get(str(a.stat), 0)) >= int(a.goal):
			p.rpg.achievements[str(a.id)] = Time.get_date_string_from_system()
			p.rpg.coins = int(p.rpg.coins) + int(a.coins)
			notes.append({"kind": "achievement", "id": str(a.id), "text": "Prestasi: %s! (+%d koin)" % [str(a.name), int(a.coins)]})
	return notes


## Periksa semua (naik level lalu prestasi; prestasi level ikut setelah naik level).
func after(p: Dictionary, ctx: Dictionary = {}) -> Array:
	var notes := level_check(p)
	notes.append_array(check_achievements(p, ctx))
	return notes


# --- Barang, toko, kostum --------------------------------------------------------------------------------------------

## Nama & keterangan barang/kostum. extra = daftar barang misi (quest_engine.items).
func info(id: String, extra: Dictionary = {}) -> Dictionary:
	if doc.items.has(id):
		return doc.items[id]
	if extra.has(id):
		return extra[id]
	if costumes.has(id):
		return {"name": str(doc.costume_names.get(id, id)), "desc": "Kostum", "price": int(costumes[id].price)}
	return {"name": id, "desc": ""}


func shop(shop_id: String) -> Dictionary:
	return doc.get("shop", {}).get(shop_id, {})


func stock(p: Dictionary, shop_id: String) -> Array:
	var out: Array = []
	for id in shop(shop_id).get("stock", []):
		var is_item: bool = doc.items.has(id)
		var price := int(doc.items[id].price) if is_item else int(costumes.get(id, {}).get("price", 0))
		out.append({"id": str(id), "name": str(info(str(id)).name), "desc": str(info(str(id)).get("desc", "")), "price": price,
			"kind": "item" if is_item else "costume", "slot": "" if is_item else slot_of(str(id)),
			"owned": (not is_item) and (p.rpg.owned as Array).has(str(id)), "have": int((p.rpg.get("items", {}) as Dictionary).get(str(id), 0))})
	return out


## Beli. "" bila berhasil, atau alasan penolakan (koin kurang, kostum sudah dimiliki, tidak dijual).
func buy(p: Dictionary, shop_id: String, id: String) -> String:
	if not (shop(shop_id).get("stock", []) as Array).has(id):
		return "Barang itu tidak dijual di sini."
	var is_item: bool = doc.items.has(id)
	if not is_item and (p.rpg.owned as Array).has(id):
		return "Kamu sudah punya kostum ini."
	var price := int(doc.items[id].price) if is_item else int(costumes.get(id, {}).get("price", 0))
	if int(p.rpg.coins) < price:
		return "Koinmu belum cukup. Kumpulkan koin dengan belajar dan menolong warga!"
	p.rpg.coins = int(p.rpg.coins) - price
	if is_item:
		if not p.rpg.has("items"):
			p.rpg["items"] = {}
		p.rpg.items[id] = int((p.rpg.items as Dictionary).get(id, 0)) + 1
	else:
		(p.rpg.owned as Array).append(id)
	return ""


## Pakai kostum yang dimiliki. Topi/aksesori yang sama dipakai lagi = dilepas.
func equip(p: Dictionary, id: String) -> bool:
	if not (p.rpg.owned as Array).has(id):
		return false
	var slot := slot_of(id)
	if slot != "outfit" and str(p.profile[slot]) == id:
		p.profile[slot] = ""
	else:
		p.profile[slot] = id
	return true


func owned_costumes(p: Dictionary) -> Array:
	var out: Array = []
	for id in p.rpg.owned:
		if costumes.has(str(id)):
			var slot := slot_of(str(id))
			out.append({"id": str(id), "name": str(info(str(id)).name), "slot": slot, "worn": str(p.profile[slot]) == str(id),
				"value": str(costumes[str(id)].value)})
	return out
