extends Node

## Data sesi yang dipakai antar-layar: pemain yang sedang main + pengaturan tersimpan.

const CONFIG_PATH := "user://settings.cfg"
## Pencapaian baru terbuka (id); world3d menampilkannya sebagai pemberitahuan.
signal achievement_unlocked(id: String)
## Keakraban warga (sama dengan RepFriend, RepBestFriend, RepDiscountPercent di internal/game/warga.go).
const REP_FRIEND := 3
const REP_BEST := 10
const REP_DISCOUNT := 10
const SHOP_KEEPERS := {"toko": "penjaga_toko", "makan": "penjaga_makan", "peralatan": "penjaga_alat"}
## Pasukan prajurit biasa (sama dengan MaxSoldiers dan SoldierPrice di internal/game/ally.go).
const MAX_SOLDIERS := 50  # sama dengan MaxSoldiers di server (v0.66.0: dulu 5)
## Pelatihan di Aula Pelatihan (sama dengan train.go): level tertinggi, biaya emas/energi, detik per level.
const MAX_TRAIN_LEVEL := 20
const TRAIN := {
	"pahlawan": {"gold": 80, "energy": 30, "sec": 600},
	"prajurit": {"gold": 40, "energy": 20, "sec": 300},
}
const SOLDIER_PRICE := 60
const MAX_ENERGY := 100  # sama dengan MaxEnergy di internal/game/energy.go

## {"id", "name", "version", "state": {...}}  -- bentuk sama dengan docs/API.md
var player: Dictionary = {}
## Pertarungan yang sedang berjalan (jawaban server: enemy_id, enemy_name, enemy_hp, ...), {} bila tidak ada.
var battle: Dictionary = {}
## NPC yang sedang diajak bicara (untuk layar dialog).
var talk_npc := ""
## Toko yang akan dibuka layar toko ("toko" = toko ramuan, "makan" = rumah makan) dan nama penjaganya.
var shop_id := "toko"
## Layar rekrut basecamp: "pahlawan" (tenda merah) atau "prajurit" (tenda hijau).
var recruit_kind := "pahlawan"
var train_kind := "pahlawan"  # tempat latihan yang dibuka: "pahlawan" / "prajurit"
var shop_keeper := ""
## Berapa kali tiap lawan bicara sudah diajak bicara (kalimat warga bergantian). Tidak disimpan.
var talk_counts: Dictionary = {}
## Sisa langkah aman di ladang setelah pertarungan (tidak ada pertemuan baru).
var safe_steps := 0
## Layar narasi cerita The Last Dragon (story.gd) boleh tampil; uji e2e mematikannya kecuali saat menguji narasi.
var story_popups := true
## true = tidak terhubung ke server (mis. menguji peta langsung dari editor); tidak disimpan.
var offline := false
## Nama akun terakhir yang masuk di HP ini (untuk tombol "Lanjutkan sebagai ..."). Kata sandi tidak pernah disimpan.
var saved_name := ""
## Pengaturan grafis/kontrol (disimpan di HP): 0 = Hemat, 1 = Normal, 2 = Tinggi.
var quality := 1
var cam_sens := 1.0
## Kamera kembali ke belakang pahlawan (menghadap ke depan) setelah layar selesai digeser (v0.68.3).
var cam_follow := true
## Layar tetap menyala selama game dibuka (disimpan di HP).
var keep_on := false
## Percikan darah saat memukul makhluk hidup (roadmap no. 165); bisa dimatikan di Pengaturan.
var fx_blood := true
## Lapisan FPS & memori di tepi atas layar (roadmap no. 251); bisa dinyalakan di Pengaturan.
var show_perf := false
var _perf_overlay: CanvasLayer = null
## Kontrol layar sentuh (roadmap no. 217): ukuran tombol/joystick (0 kecil, 1 normal, 2 besar) dan
## mode tangan kiri (joystick di kanan, tombol aksi di kiri).
const UI_SCALES := [0.85, 1.0, 1.2]
var ui_size := 1
var left_hand := false
signal ui_changed
## Pemberitahuan (roadmap no. 216): 30 terakhir, terbaru di akhir. {text, kind, at, read}
var notices: Array = []
## Pesan untuk beranda setelah dikeluarkan dari dunia (mis. sesi kedaluwarsa).
var login_notice := ""
signal notice_added(n: Dictionary)
## Pengaturan suara (disimpan di HP): suara bicara NPC dan musik, masing-masing nyala/mati + volume 0..1.
var snd_npc := true
var snd_music := true
var vol_npc := 0.8
var vol_music := 0.6


func _ready() -> void:
	load_config()
	apply_display()
	# Layar lebih tinggi/lebar dari 9:16 memakai seluruh layar, tanpa pita hitam (roadmap no. 218). Diatur
	# di sini juga (selain project.godot) supaya berlaku lewat patch tanpa APK baru.
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	Api.base_url = str(cfg.get_value("server", "url", Api.base_url))
	Api.token = str(cfg.get_value("auth", "token", ""))
	saved_name = str(cfg.get_value("auth", "name", "")) if Api.token != "" else ""
	quality = clampi(int(cfg.get_value("game", "quality", 1)), 0, 2)
	cam_sens = clampf(float(cfg.get_value("game", "cam_sens", 1.0)), 0.5, 2.0)
	cam_follow = bool(cfg.get_value("game", "cam_follow", true))
	keep_on = bool(cfg.get_value("game", "keep_on", false))
	fx_blood = bool(cfg.get_value("game", "fx_blood", true))
	ui_size = clampi(int(cfg.get_value("game", "ui_size", 1)), 0, UI_SCALES.size() - 1)
	left_hand = bool(cfg.get_value("game", "left_hand", false))
	show_perf = bool(cfg.get_value("game", "show_perf", false))
	apply_display()
	snd_npc = bool(cfg.get_value("sound", "npc", true))
	snd_music = bool(cfg.get_value("sound", "music", true))
	vol_npc = clampf(float(cfg.get_value("sound", "vol_npc", 0.8)), 0.0, 1.0)
	vol_music = clampf(float(cfg.get_value("sound", "vol_music", 0.6)), 0.0, 1.0)


## Jumlah item dengan id tertentu di ransel (0 bila tidak ada).
func item_count(id: String) -> int:
	for item: Dictionary in player.get("state", {}).get("inventory", []):
		if str(item.get("id", "")) == id:
			return int(item.get("qty", 0))
	return 0


## Terapkan pengaturan layar yang berlaku di seluruh aplikasi: layar tetap menyala, batas FPS menurut
## kualitas grafis (Hemat 30 FPS supaya baterai awet, no. 249) dan lapisan FPS & memori (no. 251).
func apply_display() -> void:
	DisplayServer.screen_set_keep_on(keep_on)
	if DisplayServer.get_name() != "headless":  # uji otomatis berjalan secepat mungkin
		Engine.max_fps = int(load("res://scripts/perf.gd").FPS_CAP[clampi(quality, 0, 2)])
	if show_perf and _perf_overlay == null:
		_perf_overlay = load("res://scripts/perf_overlay.gd").new()
		add_child(_perf_overlay)
	elif not show_perf and _perf_overlay != null:
		_perf_overlay.queue_free()
		_perf_overlay = null


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "url", Api.base_url)
	cfg.set_value("auth", "token", Api.token)
	if Api.token != "" and str(player.get("name", "")) != "":
		saved_name = str(player.name)
	cfg.set_value("auth", "name", saved_name if Api.token != "" else "")
	cfg.set_value("game", "quality", quality)
	cfg.set_value("game", "cam_sens", cam_sens)
	cfg.set_value("game", "cam_follow", cam_follow)
	cfg.set_value("game", "keep_on", keep_on)
	cfg.set_value("game", "fx_blood", fx_blood)
	cfg.set_value("game", "ui_size", ui_size)
	cfg.set_value("game", "left_hand", left_hand)
	cfg.set_value("game", "show_perf", show_perf)
	cfg.set_value("sound", "npc", snd_npc)
	cfg.set_value("sound", "music", snd_music)
	cfg.set_value("sound", "vol_npc", vol_npc)
	cfg.set_value("sound", "vol_music", vol_music)
	cfg.save(CONFIG_PATH)


## Menyimpan data pemain dari server. JSON Godot menghasilkan float untuk semua
## angka, sedangkan server menolak "5.0" untuk field int, jadi semuanya diubah ke int.
func set_player(p: Dictionary) -> void:
	player = {
		"id": str(p.get("id", "")),
		"name": str(p.get("name", "")),
		"version": int(p.get("version", 1)),
		"state": _normalize_state(p.get("state", {})),
	}


## Menggabungkan data pemain dari server (mis. hasil pertarungan) ke data lokal.
## Statistik dan tas SELALU ikut server. Posisi (peta, x, y, fx, fz, yaw) tetap milik klien,
## kecuali adopt_position (mis. pemain kalah dan dipulangkan ke desa).
## Energi (kekuatan jurus) pemain: MAX_ENERGY dikurangi yang terpakai (sama dengan MaxEnergy di server).
func energy() -> int:
	return MAX_ENERGY - int(player.state.get("energy_used", 0))


func _reputation(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: String in v:
			var r: Variant = v[k]
			if r is Dictionary:
				out[k] = {"p": int(r.get("p", 0)), "t": int(r.get("t", 0)), "l": int(r.get("l", 0))}
	return out


## Poin kemampuan yang belum dipakai: 1 per naik level (sama dengan TalentPoints di server).
func talent_points() -> int:
	var used := 0
	for k: String in player.state.get("talent", {}):
		used += int(player.state.talent[k])
	return maxi(0, int(player.state.get("level", 1)) - 1 - used)


## Poin keakraban dan berapa kali bicara dengan warga `id` (roadmap no. 58-59).
func rep_points(id: String) -> int:
	return int(player.state.get("reputation", {}).get(id, {}).get("p", 0))


func rep_talks(id: String) -> int:
	return int(player.state.get("reputation", {}).get(id, {}).get("t", 0))


## Tingkat keakraban: Kenalan (0-2), Teman (3-9), Sahabat (10+) — sama dengan RepFriend/RepBestFriend di server.
func rep_tier(id: String) -> String:
	var p := rep_points(id)
	return "Sahabat" if p >= REP_BEST else ("Teman" if p >= REP_FRIEND else "Kenalan")


## Potongan harga (persen) di toko `shop` bila bersahabat dengan penjaganya (server: ShopDiscount).
func shop_discount(shop: String) -> int:
	var keeper: String = SHOP_KEEPERS.get(shop, "")
	var d := REP_DISCOUNT if keeper != "" and rep_points(keeper) >= REP_BEST else 0
	if load("res://scripts/atmosphere.gd").market_active():
		d += 10  # Hari Pasar (roadmap no. 189; MarketPercent di server)
	return d


func ui_scale() -> float:
	return float(UI_SCALES[clampi(ui_size, 0, UI_SCALES.size() - 1)])


## Tambah pemberitahuan (kind: info, dagang, kejadian, hadiah, peringatan). Pesan sama berturut-turut digabung.
func notify(text: String, kind := "info") -> void:
	if not notices.is_empty() and str(notices[-1].text) == text:
		return
	var n := {"text": text, "kind": kind, "at": int(Time.get_unix_time_from_system()), "read": false}
	notices.append(n)
	if notices.size() > 30:
		notices = notices.slice(notices.size() - 30)
	notice_added.emit(n)


func unread_notices() -> int:
	var c := 0
	for n: Dictionary in notices:
		if not bool(n.read):
			c += 1
	return c


func merge_server_player(p: Dictionary, adopt_position := false) -> void:
	var incoming := _normalize_state(p.get("state", {}))
	var st: Dictionary = player.state
	var before: Array = st.get("achievements", [])
	for a: String in incoming.achievements:
		if not before.has(a):
			achievement_unlocked.emit(a)  # pencapaian baru (roadmap no. 150)
	for key: String in ["level", "xp", "hp", "max_hp", "gold", "inventory", "equipment", "outfit", "reputation", "house", "talent", "achievements", "achievements_taken", "wins", "crafted", "hero", "allies", "party", "ally_hp", "soldiers", "soldiers_rest", "hero_levels", "soldier_level", "training", "energy_used", "hutan", "trials", "bank", "storage", "ledger", "visited", "secrets", "raid", "defended", "story"]:
		st[key] = incoming[key]
	if adopt_position:
		for key: String in ["map", "x", "y", "fx", "fz", "yaw"]:
			st[key] = incoming[key]
	player.version = int(p.get("version", player.version))


## Pemain sementara untuk uji tanpa server (sama dengan keadaan awal di server).
func use_offline_player() -> void:
	offline = true
	set_player({
		"name": "Penguji",
		"version": 1,
		"state": {"level": 1, "hp": 30, "max_hp": 30, "map": "desa_awal", "x": 5, "y": 5, "fx": 5.5, "fz": 5.5},
	})


## Kemajuan misi Hutan Lebat dari server: {wave: Goblin yang sudah kalah 0..3, kills: binatang tahap ini 0..100}.
func _hutan(v: Variant) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	return {"wave": clampi(int(d.get("wave", 0)), 0, 3), "kills": clampi(int(d.get("kills", 0)), 0, 100), "briefed": bool(d.get("briefed", false))}


## Ujian Gua Goblin / Gunung Batu (v0.65.0): {peta: {wave, kills}} dari server.
func _trials(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in v:
			out[str(k)] = _hutan(v[k])
	return out


## Musuh yang harus dikalahkan pada tahap `wave` (0 = tahap 1): 25, 75, 100 (sama dengan StageKills di server).
const STAGE_KILLS := [25, 75, 100]


static func stage_need(wave: int) -> int:
	return STAGE_KILLS[clampi(wave, 0, STAGE_KILLS.size() - 1)]


## Kemajuan ujian di peta `map_id` ({wave, kills}); sama dengan State.Trial di server, termasuk pemain lama
## yang sudah pernah sampai ke peta sesudahnya (dianggap lulus).
func trial(map_id: String) -> Dictionary:
	var st: Dictionary = player.get("state", {})
	if map_id == "hutan_lebat":
		return st.get("hutan", {"wave": 0, "kills": 0})
	var tr: Dictionary = st.get("trials", {})
	if tr.has(map_id):
		return tr[map_id]
	var nxt := str(load("res://scripts/maps.gd").TRIALS.get(map_id, {}).get("next", ""))
	if nxt != "" and (st.get("visited", []) as Array).has(nxt):
		return {"wave": 3, "kills": 0}
	return {"wave": 0, "kills": 0}


func trial_wave(map_id: String) -> int:
	return int(trial(map_id).get("wave", 0))


func trial_kills(map_id: String) -> int:
	return int(trial(map_id).get("kills", 0))


## Bos tahap ini sudah menunggu di singgasana peta itu.
func trial_boss_ready(map_id: String) -> bool:
	var w := trial_wave(map_id)
	return w < 3 and trial_kills(map_id) >= stage_need(w)


func hutan_wave() -> int:
	return int(player.get("state", {}).get("hutan", {}).get("wave", 0))


func hutan_kills() -> int:
	return int(player.get("state", {}).get("hutan", {}).get("kills", 0))


## Sudah boleh melawan musuh di Hutan Lebat: sudah bicara dengan Kapten Rimba (sama dengan Started() di server;
## pemain yang sudah punya kemajuan dianggap sudah diarahkan).
## Langkah cerita utama The Last Dragon yang sedang dijalani (0..12; 12 = tamat). Lihat story.gd.
func story() -> int:
	return int(player.get("state", {}).get("story", 0))


func hutan_started() -> bool:
	var h: Dictionary = player.get("state", {}).get("hutan", {})
	return bool(h.get("briefed", false)) or int(h.get("wave", 0)) > 0 or int(h.get("kills", 0)) > 0


## Radar Musuh (pemberian Kapten Rimba) ada di ransel.
func has_radar() -> bool:
	return item_count("radar_musuh") > 0


func _levels(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if v is Dictionary:
		for k: Variant in v:
			out[str(k)] = clampi(int(v[k]), 1, MAX_TRAIN_LEVEL)
	return out


## HP pendamping selalu bilangan bulat: JSON dari Godot menulis float utuh sebagai "30.0".
func _hp_map(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if v is Dictionary:
		for k: Variant in v:
			out[str(k)] = maxi(0, int(v[k]))
	return out


func _jobs(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for j: Variant in v:
			if j is Dictionary:
				out.append({"kind": str(j.get("kind", "")), "target": str(j.get("target", "")), "to_level": int(j.get("to_level", 2)), "ready_at": int(j.get("ready_at", 0))})
	return out


## Level latihan satu pahlawan pembantu (1 bila belum dilatih) dan level pasukan prajurit.
func hero_level(id: String) -> int:
	return maxi(1, int(player.state.get("hero_levels", {}).get(id, 1)))


## Prajurit yang dipasang dan ikut bertarung (sama dengan ActiveSoldiers di server): dimiliki dikurangi yang menunggu di kem.
func active_soldiers() -> int:
	var st: Dictionary = player.get("state", {})
	return maxi(0, int(st.get("soldiers", 0)) - int(st.get("soldiers_rest", 0)))


func squad_level() -> int:
	return maxi(1, int(player.state.get("soldier_level", 1)))


## HP satu prajurit menurut level pasukan (sama dengan State.SoldierMaxHP di server).
func soldier_max_hp() -> int:
	return 40 + 20 * (squad_level() - 1)


## Latihan yang sedang berjalan untuk tempat latihan itu ({} bila kosong).
func train_job(kind: String) -> Dictionary:
	for j: Dictionary in player.state.get("training", []):
		if j.kind == kind:
			return j
	return {}


func _strings(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x: Variant in v:
			out.append(str(x))
	return out


func _normalize_state(s: Dictionary) -> Dictionary:
	var inventory: Array = []
	for item: Dictionary in s.get("inventory", []):
		inventory.append({"id": str(item.get("id", "")), "qty": int(item.get("qty", 1))})
	var eq: Dictionary = s.get("equipment", {})
	return {
		"equipment": {"weapon": str(eq.get("weapon", "")), "armor": str(eq.get("armor", "")), "helmet": str(eq.get("helmet", ""))},
		# Ingatan + keakraban warga (roadmap no. 58-59; server: state.reputation) {id: {p, t, l}}.
		"reputation": _reputation(s.get("reputation", {})),
		"house": bool(s.get("house", false)),  # rumah di Desa Awal sudah dibeli (roadmap no. 127)
		# Pohon kemampuan, pencapaian, kemenangan, barang ditempa (roadmap no. 139, 145, 150).
		"talent": _levels(s.get("talent", {})),
		"achievements": _strings(s.get("achievements", [])),
		"achievements_taken": _strings(s.get("achievements_taken", [])),
		"wins": int(s.get("wins", 0)),
		"crafted": int(s.get("crafted", 0)),
		# Variasi warna pakaian pahlawan 0..3 (roadmap no. 14; server: state.outfit).
		"outfit": clampi(int(s.get("outfit", 0)), 0, 3),
		"level": int(s.get("level", 1)),
		"xp": int(s.get("xp", 0)),
		"hp": int(s.get("hp", 30)),
		"max_hp": int(s.get("max_hp", 30)),
		"gold": int(s.get("gold", 0)),
		"map": str(s.get("map", "desa_awal")),
		"x": int(s.get("x", 5)),
		"y": int(s.get("y", 5)),
		# Posisi halus dunia 3D (satuan = petak). 0,0 berarti belum ada: pakai tengah petak.
		"fx": float(s.get("fx", 0.0)),
		"fz": float(s.get("fz", 0.0)),
		"yaw": float(s.get("yaw", 0.0)),
		"inventory": inventory,
		"hero": str(s.get("hero", "")) if str(s.get("hero", "")) != "" else "ksatria",
		# Pahlawan pendamping yang sudah dibeli dan yang dipasang (hanya server yang mengubah).
		"allies": _strings(s.get("allies", [])),
		"party": _strings(s.get("party", [])),
		"ally_hp": _hp_map(s.get("ally_hp", {})),
		"soldiers": clampi(int(s.get("soldiers", 0)), 0, MAX_SOLDIERS),
		"soldiers_rest": clampi(int(s.get("soldiers_rest", 0)), 0, MAX_SOLDIERS),
		"hero_levels": _levels(s.get("hero_levels", {})),
		"soldier_level": clampi(int(s.get("soldier_level", 0)), 0, MAX_TRAIN_LEVEL),
		"training": _jobs(s.get("training", [])),
		"energy_used": clampi(int(s.get("energy_used", 0)), 0, MAX_ENERGY),
		"hutan": _hutan(s.get("hutan", {})),
		"trials": _trials(s.get("trials", {})),
		# Ekonomi (roadmap no. 180-182): tabungan bank, peti simpan di rumah, riwayat transaksi.
		"bank": maxi(0, int(s.get("bank", 0))),
		"storage": _stacks(s.get("storage", [])),
		"ledger": _ledger(s.get("ledger", [])),
		# Dunia (roadmap no. 190-199): wilayah dikunjungi, tempat rahasia, pertahanan desa.
		"visited": _strings(s.get("visited", [])),
		"secrets": _strings(s.get("secrets", [])),
		"raid": {"id": int((s.get("raid", {}) as Dictionary).get("id", 0)) if s.get("raid", {}) is Dictionary else 0,
			"kills": int((s.get("raid", {}) as Dictionary).get("kills", 0)) if s.get("raid", {}) is Dictionary else 0,
			"claimed": bool((s.get("raid", {}) as Dictionary).get("claimed", false)) if s.get("raid", {}) is Dictionary else false},
		"defended": int(s.get("defended", 0)),
		# Cerita utama The Last Dragon: langkah yang sedang dijalani (server: state.story, story.go).
		"story": clampi(int(s.get("story", 0)), 0, 12),
	}


static func _stacks(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for item: Variant in v:
			if item is Dictionary:
				out.append({"id": str(item.get("id", "")), "qty": int(item.get("qty", 1))})
	return out


static func _ledger(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for e: Variant in v:
			if e is Dictionary:
				out.append({"at": int(e.get("at", 0)), "kind": str(e.get("kind", "")), "note": str(e.get("note", "")), "gold": int(e.get("gold", 0))})
	return out
