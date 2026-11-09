extends Node
## Data sesi yang dipakai antar-layar: pemain yang sedang main + pengaturan tersimpan.

const CONFIG_PATH := "user://settings.cfg"
## Pasukan prajurit biasa (sama dengan MaxSoldiers dan SoldierPrice di internal/game/ally.go).
const MAX_SOLDIERS := 5
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
## true = tidak terhubung ke server (mis. menguji peta langsung dari editor); tidak disimpan.
var offline := false
## Nama akun terakhir yang masuk di HP ini (untuk tombol "Lanjutkan sebagai ..."). Kata sandi tidak pernah disimpan.
var saved_name := ""
## Pengaturan grafis/kontrol (disimpan di HP): 0 = Hemat, 1 = Normal, 2 = Tinggi.
var quality := 1
var cam_sens := 1.0
## Layar tetap menyala selama game dibuka (disimpan di HP).
var keep_on := false
## Pengaturan suara (disimpan di HP): suara bicara NPC dan musik, masing-masing nyala/mati + volume 0..1.
var snd_npc := true
var snd_music := true
var vol_npc := 0.8
var vol_music := 0.6


func _ready() -> void:
	load_config()


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	Api.base_url = str(cfg.get_value("server", "url", Api.base_url))
	Api.token = str(cfg.get_value("auth", "token", ""))
	saved_name = str(cfg.get_value("auth", "name", "")) if Api.token != "" else ""
	quality = clampi(int(cfg.get_value("game", "quality", 1)), 0, 2)
	cam_sens = clampf(float(cfg.get_value("game", "cam_sens", 1.0)), 0.5, 2.0)
	keep_on = bool(cfg.get_value("game", "keep_on", false))
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


## Terapkan pengaturan layar yang berlaku di seluruh aplikasi (layar tetap menyala).
func apply_display() -> void:
	DisplayServer.screen_set_keep_on(keep_on)


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "url", Api.base_url)
	cfg.set_value("auth", "token", Api.token)
	if Api.token != "" and str(player.get("name", "")) != "":
		saved_name = str(player.name)
	cfg.set_value("auth", "name", saved_name if Api.token != "" else "")
	cfg.set_value("game", "quality", quality)
	cfg.set_value("game", "cam_sens", cam_sens)
	cfg.set_value("game", "keep_on", keep_on)
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


func merge_server_player(p: Dictionary, adopt_position := false) -> void:
	var incoming := _normalize_state(p.get("state", {}))
	var st: Dictionary = player.state
	for key: String in ["level", "xp", "hp", "max_hp", "gold", "inventory", "equipment", "hero", "allies", "party", "ally_hp", "soldiers", "soldiers_rest", "hero_levels", "soldier_level", "training", "energy_used", "hutan"]:
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


func hutan_wave() -> int:
	return int(player.get("state", {}).get("hutan", {}).get("wave", 0))


func hutan_kills() -> int:
	return int(player.get("state", {}).get("hutan", {}).get("kills", 0))


## Sudah boleh melawan musuh di Hutan Lebat: sudah bicara dengan Kapten Rimba (sama dengan Started() di server;
## pemain yang sudah punya kemajuan dianggap sudah diarahkan).
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
		"equipment": {"weapon": str(eq.get("weapon", "")), "armor": str(eq.get("armor", ""))},
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
	}
