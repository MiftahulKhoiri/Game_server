extends RefCounted
## Sistem misi dunia 3D (Fase 4). Misi DIHITUNG dari progres yang sudah sah (area selesai, ujian lulus, lokasi
## selesai, benda ditemukan, soal hari ini) — tidak ada tombol yang memberi hadiah langsung.
## Hadiah (koin + XP, mata uang lama) diberikan SEKALI per kunci misi: kunci dicatat di progres.world.claimed,
## jadi memuat ulang scene, mengulang sesi, atau membuka game lagi tidak memberi hadiah dua kali.
##
## Jenis: utama, sampingan, teka-teki, npc, eksplorasi, benda, harian.

const Locations := preload("res://games/education_sd/scripts/world/w3d_locations.gd")
const SdProgress := preload("res://games/education_sd/scripts/sd_progress.gd")

const ITEMS_PER_ISLAND := 5
const DAILY_ANSWERS := 10
const KEEP_DAILY_DAYS := 7


static func _m(id: String, key: String, type: String, name: String, desc: String, subject: String, cur: int, goal: int, coins: int, xp: int, claimed: Dictionary) -> Dictionary:
	return {"id": id, "key": key, "type": type, "name": name, "desc": desc, "subject": subject,
		"progress": mini(cur, goal), "goal": goal, "done": cur >= goal and goal > 0,
		"reward": {"coins": coins, "xp": xp}, "claimed": claimed.has(key)}


## Daftar misi untuk satu pulau pada kelas aktif (+ misi global & harian).
static func build(p: Dictionary, data, grade: int, rid: String, today: String) -> Array:
	var w: Dictionary = p.world
	var claimed: Dictionary = w.claimed
	var region: Dictionary = data.region(rid)
	var subject := str(region.get("subject", ""))
	var k := "k%d/%s" % [grade, rid]
	var out: Array = []
	var ts: Array = data.topics_for(rid, grade)
	var done := 0
	for t in ts:
		if SdProgress.area_rec(p, grade, rid, str(t.id)).get("done", false):
			done += 1
	out.append(_m("gerbang", k + "/gerbang", "utama", "Buka semua gerbang",
		"Selesaikan semua area belajar %s kelas %d." % [str(region.get("name", "")), grade], subject, done, ts.size(), 30, 50, claimed))
	var ex: Dictionary = SdProgress.grade_rec(p, grade).exams.get(rid, {})
	out.append(_m("penjaga", k + "/penjaga", "utama", "Kalahkan Penjaga Wilayah",
		"Lulus ujian akhir wilayah (nilai 70 ke atas). Syarat: semua gerbang terbuka.", subject, 1 if ex.get("passed", false) else 0, 1, 40, 80, claimed))
	var locs: Dictionary = w.locs
	for d in Locations.for_region(rid):
		var lid := str(d.id)
		var type := "npc" if d.has("villager") else ("teka-teki" if str(d.build) in ["maze", "cave"] else "sampingan")
		var desc := str(d.desc)
		if d.has("villager"):
			desc = "Bantu %s di %s." % [str(d.villager), str(d.name)]
		var ok := bool(locs.get(k + "/" + lid, {}).get("done", false))
		out.append(_m("lokasi_" + lid, k + "/lokasi_" + lid, type, str(d.name), desc + " Jawab minimal 2 dari 3 soal dengan benar.",
			subject, 1 if ok else 0, 1, 15, 20, claimed))
	var visited: Dictionary = (w.visited as Dictionary).get(rid, {})
	var nloc := Locations.for_region(rid).size()
	out.append(_m("jelajah", rid + "/jelajah", "eksplorasi", "Penjelajah pulau", "Kunjungi semua %d lokasi di pulau ini." % nloc,
		subject, visited.size(), nloc, 15, 20, claimed))
	out.append(_m("rahasia", k + "/rahasia", "eksplorasi", "Tempat rahasia", "Temukan tempat tersembunyi di pojok alun-alun.",
		subject, 1 if (w.found as Dictionary).get(k, false) else 0, 1, 10, 10, claimed))
	var items: Array = (w.items as Dictionary).get(rid, [])
	out.append(_m("benda", rid + "/benda", "benda", "Pengumpul benda", "Temukan %d benda tersembunyi di pulau ini." % ITEMS_PER_ISLAND,
		subject, items.size(), ITEMS_PER_ISLAND, 20, 25, claimed))
	out.append(_m("empat_pulau", "global/empat_pulau", "eksplorasi", "Penjelajah Nusantara Ilmu", "Kunjungi keempat pulau.",
		"", (w.islands as Dictionary).size(), 4, 25, 30, claimed))
	var day: Array = (p.daily as Dictionary).get(today, [0, 0])
	out.append(_m("soal_harian", "harian/%s/soal" % today, "harian", "Rajin hari ini", "Jawab %d soal hari ini (mode apa saja)." % DAILY_ANSWERS,
		"", int(day[1]), DAILY_ANSWERS, 10, 15, claimed))
	out.append(_m("lokasi_harian", "harian/%s/lokasi" % today, "harian", "Petualang hari ini", "Selesaikan 1 teka-teki lokasi hari ini.",
		"", int((w.daily_locs as Dictionary).get(today, 0)), 1, 10, 15, claimed))
	return out


## Beri hadiah misi yang selesai dan belum diklaim. Mengembalikan misi yang baru diberi hadiah.
static func award(p: Dictionary, missions: Array, today: String) -> Array:
	var got: Array = []
	var claimed: Dictionary = p.world.claimed
	for m in missions:
		if m.done and not claimed.has(m.key):
			claimed[m.key] = today
			p.coins = int(p.coins) + int(m.reward.coins)
			p.xp = int(p.xp) + int(m.reward.xp)
			m.claimed = true
			got.append(m)
	_prune(claimed, today)
	return got


## Kunci misi harian lama dibuang (tetap kecil), kunci misi lain disimpan selamanya.
static func _prune(claimed: Dictionary, today: String) -> void:
	var days: Array = []
	for key in claimed.keys():
		if str(key).begins_with("harian/"):
			var d := str(key).split("/")[1]
			if not days.has(d):
				days.append(d)
	days.sort()
	while days.size() > KEEP_DAILY_DAYS:
		var old: String = days.pop_front()
		for key in claimed.keys():
			if str(key).begins_with("harian/%s/" % old):
				claimed.erase(key)


static func type_name(t: String) -> String:
	return {"utama": "Misi utama", "sampingan": "Misi sampingan", "teka-teki": "Teka-teki", "npc": "Misi warga",
		"eksplorasi": "Eksplorasi", "benda": "Cari benda", "harian": "Misi harian"}.get(t, t)


static func lines(missions: Array) -> Array:
	var out: Array = []
	for m in missions:
		var mark := "✓" if m.done else "•"
		var rw := "+%d koin, +%d XP" % [int(m.reward.coins), int(m.reward.xp)]
		out.append("%s [%s] %s — %d/%d\n    %s  (%s%s)" % [mark, type_name(str(m.type)), str(m.name), int(m.progress), int(m.goal),
			str(m.desc), rw, ", sudah diterima" if m.claimed else ""])
	return out
