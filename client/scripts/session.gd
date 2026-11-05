extends Node
## Data sesi yang dipakai antar-layar: pemain yang sedang main + pengaturan tersimpan.

const CONFIG_PATH := "user://settings.cfg"

## {"id", "name", "version", "state": {...}}  -- bentuk sama dengan docs/API.md
var player: Dictionary = {}
## true = tidak terhubung ke server (mis. menguji peta langsung dari editor); tidak disimpan.
var offline := false


func _ready() -> void:
	load_config()


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	Api.base_url = str(cfg.get_value("server", "url", Api.base_url))
	Api.token = str(cfg.get_value("auth", "token", ""))


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "url", Api.base_url)
	cfg.set_value("auth", "token", Api.token)
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


## Pemain sementara untuk uji tanpa server (sama dengan keadaan awal di server).
func use_offline_player() -> void:
	offline = true
	set_player({
		"name": "Penguji",
		"version": 1,
		"state": {"level": 1, "hp": 30, "max_hp": 30, "map": "desa_awal", "x": 5, "y": 5},
	})


func _normalize_state(s: Dictionary) -> Dictionary:
	var inventory: Array = []
	for item: Dictionary in s.get("inventory", []):
		inventory.append({"id": str(item.get("id", "")), "qty": int(item.get("qty", 1))})
	return {
		"level": int(s.get("level", 1)),
		"xp": int(s.get("xp", 0)),
		"hp": int(s.get("hp", 30)),
		"max_hp": int(s.get("max_hp", 30)),
		"gold": int(s.get("gold", 0)),
		"map": str(s.get("map", "desa_awal")),
		"x": int(s.get("x", 5)),
		"y": int(s.get("y", 5)),
		"inventory": inventory,
	}
