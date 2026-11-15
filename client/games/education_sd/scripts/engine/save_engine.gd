extends RefCounted
## Save Engine — progres "Petualangan Ilmu: Dunia Enam Pulau" (skema 3).
## Disimpan lewat GameManager.save_progress("education_sd", data, SCHEMA). Data lama dari game Pulau Ilmu
## 2.x (skema 2) dan game kuis 1.x (skema 1) dipindahkan otomatis: nama, kelas, koin, XP, kostum, pahlawan,
## pengaturan, serta seluruh catatan belajar (statistik topik, riwayat, kartu, hewan, lencana).
## Bagian dunia lama (peti, gerbang, alat) tidak berlaku di dunia baru dan disimpan di "legacy" saja.
## Semua fungsi statis dan hanya mengubah Dictionary progres.

const SdProgress := preload("res://games/education_sd/scripts/sd_progress.gd")

const SCHEMA := 3
const HEROES := ["laki", "perempuan"]
const GFX := ["hemat", "seimbang", "tinggi"]
const MAX_NAME := 16


static func default_data() -> Dictionary:
	return {
		"schema": SCHEMA,
		"profile": {"name": "", "grade": 1, "hero": "laki", "outfit": "warna_merah", "hat": "", "acc": "",
			"created": ""},
		"rpg": {"xp": 0, "coins": 0, "owned": ["warna_merah", "warna_biru"]},
		"world": {"island": "pulau1", "visited": {}, "bosses": {}, "sailed": 0, "met": {}, "found": {}},
		"learning": {"totals": {"answered": 0, "correct": 0, "wrong": 0, "streak": 0, "best_streak": 0},
			"topics": {}, "grades": {}, "history": [], "cards": [], "animals": [], "badges": {}, "daily": {},
			"minigames": {}},
		"quests": {},
		"academy": {},
		"settings": {"music": true, "sfx": true, "gfx": "seimbang", "perf": false},
		"seen_intro": {},
		"migrated_from": 0,
		"legacy": {},
		"diag": [],
	}


## Bentuk data skema 2/1 (game lama) dikenali dari isinya, bukan dari nomor skema saja: data yang
## dipulihkan dari server bisa saja datang tanpa melewati migrasi GameManager.
static func is_old(d: Dictionary) -> bool:
	return not d.has("profile") and (d.has("player") or d.has("levels") or d.has("last_answers") or d.has("grades"))


static func upgrade(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return default_data()
	if is_old(d):
		return ensure(migrate_v2(SdProgress.upgrade(d)))
	return ensure(d)


## Skema 2 (Pulau Ilmu 2.x) -> skema 3.
static func migrate_v2(old: Dictionary) -> Dictionary:
	var d := default_data()
	var pl: Dictionary = old.get("player", {})
	var av: Dictionary = pl.get("avatar", {})
	var st: Dictionary = old.get("settings", {})
	d.profile.name = str(pl.get("name", "")).substr(0, MAX_NAME)
	d.profile.grade = clampi(int(pl.get("grade", 1)), 1, 6)
	d.profile.hero = str(st.get("hero", "laki")) if HEROES.has(str(st.get("hero", "laki"))) else "laki"
	d.profile.outfit = str(av.get("outfit", "warna_merah"))
	d.profile.hat = str(av.get("hat", ""))
	d.profile.acc = str(av.get("acc", ""))
	d.rpg.xp = int(old.get("xp", 0))
	d.rpg.coins = int(old.get("coins", 0))
	if typeof(old.get("owned")) == TYPE_ARRAY and not (old.owned as Array).is_empty():
		d.rpg.owned = (old.owned as Array).duplicate()
	for k in ["totals", "topics", "grades", "history", "cards", "animals", "badges", "daily", "minigames"]:
		if old.has(k) and typeof(old[k]) == typeof(d.learning[k]):
			d.learning[k] = old[k]
	for k in ["music", "sfx", "gfx", "perf"]:
		if st.has(k):
			d.settings[k] = st[k]
	d.migrated_from = 2
	d.legacy = {"world_v2": old.get("world", {}), "legacy_v1": old.get("legacy", {})}
	for k in ["safe_level", "safe_reset"]:
		if old.has(k):
			d[k] = old[k]
	return d


## Lengkapi kunci yang hilang tanpa membuang isi; JSON menyimpan angka sebagai float, kembalikan ke int.
static func ensure(d: Dictionary) -> Dictionary:
	var base := default_data()
	for k in base:
		if not d.has(k) or not _same_kind(d[k], base[k]):
			d[k] = base[k]
	for part in ["profile", "rpg", "world", "learning", "settings"]:
		for k in base[part]:
			if not d[part].has(k) or not _same_kind(d[part][k], base[part][k]):
				d[part][k] = base[part][k]
	for k in base.learning.totals:
		d.learning.totals[k] = int(d.learning.totals.get(k, 0))
	d.profile.grade = clampi(int(d.profile.grade), 1, 6)
	d.profile.name = str(d.profile.name).substr(0, MAX_NAME)
	if not HEROES.has(str(d.profile.hero)):
		d.profile.hero = "laki"
	if not GFX.has(str(d.settings.gfx)):
		d.settings.gfx = "seimbang"
	d.rpg.xp = maxi(int(d.rpg.xp), 0)
	d.rpg.coins = maxi(int(d.rpg.coins), 0)
	d.world.sailed = int(d.world.sailed)
	d.migrated_from = int(d.migrated_from)
	d.schema = SCHEMA
	return d


## JSON menyimpan semua angka sebagai float: int dan float dianggap sejenis.
static func _same_kind(a, b) -> bool:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in num and typeof(b) in num:
		return true
	return typeof(a) == typeof(b)


## Migrasi untuk GameManager.load_progress: kunci = versi asal.
static func migrations() -> Dictionary:
	return {
		1: func(d: Dictionary) -> Dictionary: return SdProgress.upgrade(d),
		2: func(d: Dictionary) -> Dictionary: return migrate_v2(SdProgress.upgrade(d)),
	}


# --- Level petualang (rumus sama dengan 2.x supaya level lama tidak turun) -----------------------------

static func level(d: Dictionary) -> int:
	return int(floor((1.0 + sqrt(1.0 + 8.0 * int(d.rpg.xp) / 100.0)) / 2.0))


static func xp_for(lv: int) -> int:
	return 100 * lv * (lv - 1) / 2


static func has_profile(d: Dictionary) -> bool:
	return str(d.get("profile", {}).get("name", "")).strip_edges() != ""
