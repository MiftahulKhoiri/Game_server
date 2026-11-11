extends Node3D
## Dunia 3D: jalan bebas dengan joystick layar, kamera di belakang pemain (geser layar
## untuk memutar). Peta, pintu, pertemuan musuh, NPC, dan penyimpanan memakai aturan
## yang sama dengan peta petak lama; posisi halus (fx, fz, yaw) ikut disimpan ke server.

const Maps = preload("res://scripts/maps.gd")
const Movement = preload("res://scripts/movement.gd")
const WorldBuild = preload("res://scripts/world_build.gd")
const Models = preload("res://scripts/models.gd")
const Joystick = preload("res://scripts/joystick.gd")
const GameMenu = preload("res://scripts/game_menu.gd")
const Companions = preload("res://scripts/companions.gd")
const ProfileScreen = preload("res://scripts/profile.gd")
const TempaScreen = preload("res://scripts/tempa.gd")
const EkonomiScreen = preload("res://scripts/ekonomi.gd")
const WorldLife = preload("res://scripts/world_life.gd")
const StoryMod = preload("res://scripts/story.gd")
const JurnalScreen = preload("res://scripts/jurnal.gd")
const Heroes = preload("res://scripts/heroes.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const Warga = preload("res://scripts/warga.gd")
const WargaDialog = preload("res://scripts/warga_dialog.gd")
const Breakables = preload("res://scripts/breakables.gd")
const ActionButton = preload("res://scripts/action_button.gd")
const Chest = preload("res://scripts/chest.gd")
const HeroFx = preload("res://scripts/hero_fx.gd")
const Roamer = preload("res://scripts/roamer.gd")
const WorldFight = preload("res://scripts/world_fight.gd")
const HudBars = preload("res://scripts/hud_bars.gd")
const HutanHud = preload("res://scripts/hutan_hud.gd")
const RadarMusuh = preload("res://scripts/radar_musuh.gd")
const Perf = preload("res://scripts/perf.gd")
const NameLabels = preload("res://scripts/name_labels.gd")

const SPEED := 3.3  # petak per detik
const SAVE_DELAY := 1.5
const RETRY_DELAY := 5.0
const ENCOUNTER_CHANCE := 0.18  # peluang bertemu musuh tiap "langkah" (1 petak jalan) di ladang
const TALK_RANGE := 1.5
const KEEPER_RANGE := 2.3  # penjaga toko berdiri di balik meja kasir
const CAM_DIST := 6.4  # jarak lama; sejak v0.68.4 jarak diatur pemain (Session.cam_dist)
const ATMO_STEP := 0.4        # detik antar pembaruan langit/cahaya (cukup halus, hemat tenaga)
const NPC_NOTICE := 3.5       # jarak (petak) NPC mulai menoleh ke pemain
const NPC_WANDER := 0.22      # NPC berjalan pelan di dalam petaknya sendiri (jangkauan, petak)
const NPC_SPEED := 0.5        # petak per detik
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const TRAIN_SCENE := "res://scenes/train.tscn"
const RECRUIT_SCENE := "res://scenes/recruit.tscn"
const INVENTORY_SCENE := "res://scenes/inventory.tscn"
const ATRIBUT_SCENE := "res://scenes/atribut.tscn"
const DIALOG_SCENE := "res://scenes/dialog.tscn"
const LOGIN_SCENE := "res://scenes/login.tscn"

# Aksi dunia (sejak v0.37.0):
#   Tangan: 1x tinju dobel, 2x tebas dobel, 3x tusuk (kombo; kembali ke tinju setelah jeda).
#   Kaki: 1x tendang, 2x tendangan dobel (dua kali menendang).
#   Perisai: 1x angkat perisai (tetap di tempat), 2x cepat = menghindar (berguling).
#   Lompat: melompat. Boost: isi dari memukul, lalu ledakan + mode Boost.
# `hits` = detik setelah tombol ditekan saat tiap pukulan/tendangan mengenai (selaras dengan gerakan tubuh).
const COMBO_WINDOW := 1.1
const COMBO := [
	{"nama": "Tinju dobel", "anim": "tinju", "reach": 1.5, "cos": 0.25, "dmg": 1.0, "solid": 1, "grass": 2, "cd": 0.62, "len": 0.9, "roll": 0.0, "dash": 0.16, "hits": [0.14, 0.4]},
	{"nama": "Tebas dobel", "anim": "tebas", "reach": 2.0, "cos": -0.3, "dmg": 1.6, "solid": 2, "grass": 5, "cd": 0.8, "len": 1.5, "roll": 0.8, "dash": 0.2, "hits": [0.27, 0.65]},
	{"nama": "Tusuk", "anim": "tusuk", "reach": 2.7, "cos": 0.55, "dmg": 3.0, "solid": 2, "grass": 4, "cd": 0.62, "len": 2.2, "roll": 0.0, "dash": 0.5, "hits": [0.27]},
]
const KICKS := [
	{"nama": "Tendang", "anim": "tendang", "reach": 1.55, "cos": 0.1, "dmg": 1.5, "solid": 1, "grass": 3, "cd": 0.5, "hits": [0.15], "dash": 0.2},
	{"nama": "Tendangan dobel", "anim": "tendang2", "reach": 1.7, "cos": 0.0, "dmg": 1.7, "solid": 2, "grass": 4, "cd": 0.95, "hits": [0.14, 0.62], "dash": 0.3},
]
const KICK_WINDOW := 1.0
## Kombo per gaya senjata (roadmap no. 155-158). "pedang" memakai COMBO di atas. `proj` = jenis peluru
## (panah/sihir) yang terbang ke sasaran; `wave` = gelombang kejut di tanah; `swoosh` = warna jejak senjata.
const STYLE_COMBOS := {
	"kapak": [
		{"nama": "Ayunan kapak", "anim": "tebas", "reach": 2.0, "cos": -0.4, "dmg": 2.0, "solid": 2, "grass": 5, "cd": 0.85, "len": 1.7, "roll": 0.8, "dash": 0.15, "hits": [0.3], "swoosh": Color("ffd0a0")},
		{"nama": "Ayunan balik", "anim": "tebas", "reach": 2.0, "cos": -0.4, "dmg": 2.0, "solid": 2, "grass": 5, "cd": 0.85, "len": 1.7, "roll": -0.8, "dash": 0.15, "hits": [0.68], "swoosh": Color("ffd0a0")},
		{"nama": "Hantaman kapak", "anim": "hantam", "reach": 2.3, "cos": -1.0, "dmg": 3.6, "solid": 3, "grass": 8, "cd": 1.0, "len": 1.2, "roll": 1.5, "dash": 0.25, "hits": [0.45], "wave": true, "swoosh": Color("ffb070")},
	],
	"tombak": [
		{"nama": "Tusuk cepat", "anim": "tusuk", "reach": 2.9, "cos": 0.6, "dmg": 1.3, "solid": 1, "grass": 2, "cd": 0.42, "len": 2.6, "roll": 0.0, "dash": 0.3, "hits": [0.27], "swoosh": Color("e0f0ff")},
		{"nama": "Tusuk dobel", "anim": "tusuk", "reach": 2.9, "cos": 0.6, "dmg": 1.3, "solid": 1, "grass": 2, "cd": 0.42, "len": 2.6, "roll": 0.0, "dash": 0.3, "hits": [0.27], "swoosh": Color("e0f0ff")},
		{"nama": "Sapuan tombak", "anim": "tebas", "reach": 3.0, "cos": -0.5, "dmg": 2.4, "solid": 2, "grass": 7, "cd": 0.8, "len": 2.6, "roll": 0.6, "dash": 0.2, "hits": [0.3, 0.68], "swoosh": Color("c8e4ff")},
	],
	"busur": [
		{"nama": "Tembak", "anim": "bidik", "reach": 6.0, "cos": 0.75, "dmg": 1.3, "solid": 1, "grass": 0, "cd": 0.5, "dash": 0.0, "hits": [0.22], "proj": "panah"},
		{"nama": "Tembak", "anim": "bidik", "reach": 6.0, "cos": 0.75, "dmg": 1.3, "solid": 1, "grass": 0, "cd": 0.5, "dash": 0.0, "hits": [0.22], "proj": "panah"},
		{"nama": "Tembak dobel", "anim": "bidik", "reach": 6.0, "cos": 0.75, "dmg": 1.5, "solid": 1, "grass": 0, "cd": 0.7, "dash": -0.15, "hits": [0.2, 0.42], "proj": "panah"},
	],
	"sihir": [
		{"nama": "Bola sihir", "anim": "rapal", "reach": 5.0, "cos": 0.7, "dmg": 1.4, "solid": 1, "grass": 2, "cd": 0.6, "dash": 0.0, "hits": [0.33], "proj": "sihir"},
		{"nama": "Bola sihir", "anim": "rapal", "reach": 5.0, "cos": 0.7, "dmg": 1.4, "solid": 1, "grass": 2, "cd": 0.6, "dash": 0.0, "hits": [0.33], "proj": "sihir"},
		{"nama": "Ledakan sihir", "anim": "rapal", "reach": 5.0, "cos": 0.7, "dmg": 3.2, "solid": 2, "grass": 6, "cd": 0.8, "dash": 0.0, "hits": [0.36], "proj": "sihir_besar", "wave": true},
	],
}
## Jurus 1 (tombol Kaki) untuk gaya jarak jauh: satu tembakan besar, bukan tendangan.
const STYLE_SKILL := {
	"busur": {"nama": "Panah Tembus", "anim": "bidik", "reach": 7.0, "cos": 0.7, "dmg": 3.0, "solid": 2, "grass": 0, "cd": 0.6, "hits": [0.25], "dash": -0.2, "proj": "panah_besar"},
	"sihir": {"nama": "Bola Api", "anim": "rapal", "reach": 6.0, "cos": 0.7, "dmg": 3.0, "solid": 2, "grass": 5, "cd": 0.7, "hits": [0.36], "dash": 0.0, "proj": "api", "wave": true},
}
## Warna peluru per jenis.
const PROJ_COLOR := {"panah": Color("f2e6c8"), "panah_besar": Color("ffe27a"), "sihir": Color("b77dff"), "sihir_besar": Color("d6a8ff"), "api": Color("ff8a2a")}
const DOUBLE_TAP := 0.4        # dua ketukan Perisai secepat ini = menghindar
const GUARD_TIME := 1.6        # sekali ketuk Perisai: perisai terangkat selama ini (tetap di tempat)
const JUMP_TIME := 0.75
const JUMP_HEIGHT := 1.0
const BOOST_TIME := 8.0
const BOOST_SPEED := 1.35
const ENERGY_PER_HIT := 5.0
const ENERGY_PER_BREAK := 9.0
const BREAK_FLUSH := 0.25      # kumpulkan benda hancur sebentar lalu lapor ke server sekaligus
const CHEST_RANGE := 1.9
const ROAM_GRACE := 3.0        # detik setelah masuk peta: musuh berkeliaran belum mengejar
const ROAM_NEAR := 6.5         # jarak (petak) nama musuh mulai tampil
const ITEM_NAMES := {"kayu": "Kayu", "bongkah_batu": "Bongkah Batu", "serat": "Serat Rumput", "ramuan": "Ramuan", "berlian": "Berlian", "ramuan_kekuatan": "Ramuan Kekuatan", "kartu_keahlian": "Kartu Keahlian", "koin_kuno": "Koin Kuno", "permata_merah": "Permata Merah"}

var _map_id := Maps.DEFAULT_MAP
var _pos := Vector2(5.5, 5.5)  # (x, z) di dunia
var _yaw := 0.0  # arah hadap pemain
var _cam_yaw := 0.0
var _cam_target := Vector3.ZERO   # titik pandang kamera yang dihaluskan
var _cam_ready := false
const CAM_FOLLOW := 9.0           # makin besar makin rapat mengikuti
const CAM_SNAP := 3.0             # petak: lebih jauh dari ini kamera langsung pindah
var _cam_pitch := 0.4  # disetel dari Session.cam_pitch saat dunia dibuka
var _tile := Vector2i(-1, -1)
var _step_acc := 0.0
var _unsaved := false
var _saving := false
var _locked := false  # sedang pindah layar (pertarungan, toko, dialog)

var _terrain: Node3D
var _npc_root: Node3D
var _player: Node3D
var _camera: Camera3D
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _save_timer: Timer

var _atmo_base: Dictionary = {}   # suasana dasar peta ini (sebelum waktu/cuaca)
var _atmo_acc := 0.0
var _rain: CPUParticles3D
var _clock: ClockBadge
var _companions: Companions
var _npc_models: Dictionary = {}  # id NPC -> model 3D
var _npc_time := 0.0
var _warga: Array[Warga] = []        # warga desa yang berjalan bebas
var _roamers: Array[Roamer] = []     # musuh yang berkeliaran di peta
var _names := NameLabels.new()         # tata letak nama di atas kepala (tidak menumpuk)
var _names_acc := 0.0
var _lights: Array = []                # lampu titik di peta ini (dibatasi yang terdekat saja)
var _lights_acc := 0.0
var _name_label_of: Dictionary = {}     # id NPC / "warga:id" -> Label3D namanya
var _roam_cfg: Dictionary = {}       # pengaturan musuh peta ini (Maps.ROAMERS), untuk memunculkan pengganti
var _roam_kinds: Array = []
var _fight: WorldFight               # pertarungan langsung di dunia
var _roam_grace := 0.0
var _bars: HudBars

var _joy: Control
var _cam_finger := -1
var _cam_idle := 99.0  # detik sejak kamera terakhir digeser (lihat _follow_camera)
var _status: Label
var _radar: Control            # Radar Musuh (titik musuh di hutan); tampil bila Radar ada di ransel
var _hutan_hud: Control        # papan misi wilayah ujian: musuh X/25|75|100, bos, panah arah
var _hutan_boss: Roamer        # Goblin yang menunggu di singgasana hutan (bila sudah waktunya)
var _hutan_sig := -1           # tanda kemajuan terakhir (untuk pesan saat berubah)
var _toast: Label
var _talk_button: Button
var _buttons: Array[Button] = []
var _menu: CanvasLayer
var _profile: CanvasLayer
var _tempa: CanvasLayer                     # layar tempa di pandai besi (roadmap no. 145)
var _ekonomi: CanvasLayer                   # bank, peti simpan, dagang (roadmap no. 176-182)
var _life: Node                             # serbuan, Hari Pasar, wilayah, rahasia, hujan, ladang (roadmap no. 186-200)
var _story: Node                            # cerita utama The Last Dragon: narasi, Batu Sihir, naga (story.gd)
## Tata letak HUD untuk berbagai ukuran layar (roadmap no. 217-218): [Control, posisi dasar 720x1280, jenis].
## Jenis: "tl" kiri atas, "tr" kanan atas, "tc" tengah atas, "br" kelompok kanan bawah (tombol aksi),
## "bl" kelompok kiri bawah (joystick, ramuan/kabur). Kelompok bawah ikut ukuran kontrol dan mode tangan kiri.
var _hud_items: Array = []
var _toast_tw: Tween
var _toast_queue: Array = []
var _jurnal: CanvasLayer                     # Misi, Peta, Kabar (roadmap no. 212-213, 216)
var _trade_acc := 50.0
var _net_label: Label                       # "Koneksi terputus" (roadmap no. 231-232)
var _net_acc := 0.0
static var _trade_seen: Dictionary = {}
const BASE_W := 720.0
const BASE_H := 1280.0
var stamina := 100.0                        # stamina lari dan lompat (roadmap no. 135), hanya di klien
var _tired := false                         # stamina habis: tidak bisa berlari sampai pulih sebagian

var _breakables: Breakables
var _chest_nodes: Dictionary = {}   # id peti -> Chest
var _chest_open: Dictionary = {}    # id peti -> true (sudah dibuka, belum terisi lagi)
var _chest_busy := false
var _act_buttons: Array = []
var _btn_tangan: ActionButton
var _btn_kaki: ActionButton
var _btn_perisai: ActionButton
var _btn_boost: ActionButton
var _btn_lompat: ActionButton
var _cd := {"tangan": 0.0, "kaki": 0.0, "hindar": 0.0, "lompat": 0.0}
var _cd_len := {"tangan": 0.3, "kaki": 0.5, "hindar": 0.9, "lompat": 0.85}
var _combo := 0
var _combo_t := 0.0
var _kick := 0           # urutan tendangan (1 = tendang, 2 = dobel)
var _kick_t := 0.0
var _guard_t := 0.0      # sisa waktu perisai terangkat
var _tap_t := -10.0      # kapan Perisai terakhir diketuk (detik, jam lokal)
var _jump_t := 0.0       # sisa waktu lompat (0 = di tanah)
var _dress_sig := ""     # pakaian + perlengkapan yang terakhir dipakaikan ke model
var _chat_acc := 0.0     # jeda pemeriksaan obrolan antar-warga
var _chat_n := 0
const CHAT_CHECK := 1.0
const HOUSE_RANGE := 1.4
const STAMINA_DRAIN := 14.0   # per detik saat berlari
const STAMINA_REGEN := 9.0
const STAMINA_JUMP := 12.0
const STAMINA_RECOVER := 35.0 # setelah habis, berlari lagi setelah pulih sampai sini
const TIRED_SPEED := 0.6
const DOOR_NEAR := 2.2
const BED_AT := Vector2(1.5, 1.5)  # ranjang di rumah pemain (Maps.RUMAH_ROWS, petak R)
const STORE_AT := Vector2(7.0, 1.5)  # lemari = peti simpan di rumah pemain (petak LL, roadmap no. 180)
var _doors: Array = []          # pintu interaktif peta ini (lihat _make_doors)
const CHAT_DIST := 1.3
const WARGA_LOD_FAR := 18.0   # warga lebih jauh dari ini (petak) diperbarui jarang
const WARGA_LOD_STEP := 0.25
const ROAM_LOD_FAR := 16.0    # musuh lebih jauh dari ini (petak) diperbarui jarang
const ROAM_LOD_STEP := 0.2
const SOLDIER_SIGHT := 5.0   # jarak (petak) pasukan prajurit melihat musuh lalu menyerang sendiri
var _shadow_disc: MeshInstance3D
var _energy := 0.0
var _boost_t := 0.0
var _guard := false
var _dash_vel := Vector2.ZERO
var _dash_t := 0.0
var _shake := 0.0
var _hint_t := 0.0
var _aura_guard: MeshInstance3D
var _aura_boost: MeshInstance3D
var _pending: Array = []
var _breaking := false
var _flush_timer: Timer


func _ready() -> void:
	if Session.player.is_empty():
		Session.use_offline_player()  # dijalankan langsung dari editor

	_env = WorldEnvironment.new()
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	add_child(_sun)
	_apply_quality()
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.far = float(Perf.pick(Perf.CAMERA_FAR))
	add_child(_camera)
	_camera.current = true
	_rain = Atmosphere.make_rain(Vector3(6, 0.2, 6), Atmosphere.rain_amount(Session.quality))
	add_child(_rain)

	_make_player()
	_life = WorldLife.new()
	add_child(_life)
	_life.setup(self)
	_story = StoryMod.new()
	add_child(_story)
	_story.setup(self)
	if not Session.offline and not Atmosphere.clock_locked:
		_sync_world_clock()

	var st: Dictionary = Session.player.state
	var map_id := str(st.map)
	if Maps.rows(map_id).is_empty():
		map_id = Maps.DEFAULT_MAP
		st.x = Maps.SPAWN.x
		st.y = Maps.SPAWN.y
		st.fx = 0.0
		st.fz = 0.0
	_load_map(map_id)
	var start := Vector2(float(st.fx), float(st.fz))
	if start == Vector2.ZERO or Movement.tile_of(start) != Vector2i(int(st.x), int(st.y)):
		start = Vector2(int(st.x), int(st.y)) + Vector2(0.5, 0.5)
	if Movement.collides(_map_id, start):
		start = Movement.safe_spot(_map_id, Movement.tile_of(start))
	_pos = start
	_yaw = float(st.yaw)
	_cam_yaw = _yaw + PI  # mulai dari belakang pahlawan
	_cam_pitch = maxf(Session.cam_pitch, 0.9) if Maps.is_interior(_map_id) else Session.cam_pitch
	_tile = Movement.tile_of(_pos)
	_spawn_roamers(_map_id)
	_sync_state()

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)

	_build_ui()
	_fight = WorldFight.new()
	add_child(_fight)
	_fight.setup(self)
	_companions = Companions.new()
	add_child(_companions)
	_companions.setup(self)
	for b: Control in [_fight._btn_potion, _fight._btn_flee]:
		register_hud(b, "bl")
	if "_heal_button" in _companions and _companions._heal_button != null:
		register_hud(_companions._heal_button, "bl")
	get_viewport().size_changed.connect(_layout_hud)
	if not Api.connection_changed.is_connected(_on_connection):
		Api.connection_changed.connect(_on_connection)
	if not Api.session_expired.is_connected(_on_session_expired):
		Api.session_expired.connect(_on_session_expired)
	if not Session.ui_changed.is_connected(_layout_hud):
		Session.ui_changed.connect(_layout_hud)
	_layout_hud()
	_refresh_hud()
	_update_clock()
	_apply_transform()
	_set_status("Mode uji (tidak disimpan)" if Session.offline else "Tersimpan")
	if not Session.offline:
		_fight.resume()  # mis. aplikasi ditutup di tengah pertarungan: musuhnya muncul lagi di dekat pemain


func _notification(what: int) -> void:
	# Simpan seketika saat aplikasi dijeda atau ditutup (best-effort).
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _unsaved and not _saving:
			_save()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_menu()


# --- peta ---

func _load_map(map_id: String) -> void:
	_map_id = map_id
	if _terrain != null:
		_terrain.queue_free()
	if _npc_root != null:
		_npc_root.queue_free()
	_terrain = WorldBuild.build(map_id)
	add_child(_terrain)
	_breakables = Breakables.new()
	_breakables.setup(_terrain, _terrain)
	_spawn_chests(map_id)
	_hutan_boss = null
	_hutan_sig = -1
	_names.clear()
	_name_label_of = {}
	_npc_root = Node3D.new()
	_npc_root.name = "NPC"
	add_child(_npc_root)
	_make_doors(map_id)
	_npc_models = {}
	_pending.clear()
	for id: String in Maps.NPCS:
		var n: Dictionary = Maps.NPCS[id]
		if n.map != map_id:
			continue
		var model := Models.create(id)
		model.position = Vector3(n.pos.x + 0.5, 0.0, n.pos.y + 0.5)
		_npc_root.add_child(model)
		_npc_models[id] = model
		_add_shadow(model, 0.3)
		var label := Label3D.new()
		label.text = str(n.name) + ("\n" + str(n.peran) if n.has("peran") else "")  # identitas (no. 41)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.006
		label.font_size = 40
		label.outline_size = 10
		label.position = model.position + Vector3(0, 1.25, 0)
		_npc_root.add_child(label)
		_names.add(label, label.text, str(n.name))
		_name_label_of[id] = label
	_spawn_warga(map_id)
	_env.environment = WorldBuild.environment_for(map_id)
	_sun.light_energy = WorldBuild.light_energy_for(map_id)
	_sun.light_color = WorldBuild.light_color_for(map_id)
	# Waktu dan cuaca berlaku di luar ruangan; suasana dasar peta disimpan dulu.
	_atmo_base = Atmosphere.capture(_env.environment, _sun)
	Atmosphere.apply(_env.environment, _sun, _atmo_base, map_id)
	Atmosphere.set_rain(_rain, map_id)
	_lights = _terrain.find_children("*", "OmniLight3D", true, false) + _npc_root.find_children("*", "OmniLight3D", true, false)
	_update_lamps()
	_cull_lights()
	_sync_world()
	if _life != null:
		_life.on_map(map_id)
	if _story != null:
		_story.on_map(map_id)


## Jam dunia bersama (roadmap no. 186): selisih jam server dan jam HP, sekali per jalannya aplikasi.
func _sync_world_clock() -> void:
	var t: Dictionary = await Api.server_time()
	if t.ok and t.data.has("unix"):
		Atmosphere.clock_offset = float(t.data.unix) - Time.get_unix_time_from_system()
		Atmosphere.clock_locked = true


## Peti harta di peta ini (isi diundi server saat dibuka).
func _spawn_chests(map_id: String) -> void:
	_chest_nodes = {}
	_chest_open = {}
	for c: Dictionary in Maps.chests_in(map_id):
		var node := Chest.new()
		node.build(str(c.id), int(c.tier))
		node.position = Vector3(c.pos.x + 0.5, 0.0, c.pos.y + 0.5)
		_terrain.add_child(node)
		_chest_nodes[str(c.id)] = node


## Minta daftar benda hancur dan peti terbuka ke server, lalu sesuaikan tampilan peta.
func _sync_world() -> void:
	if Session.offline:
		return
	var mid := _map_id
	var res: Dictionary = await Api.world_state(mid)
	if not res.ok or mid != _map_id or _breakables == null:
		return
	var items: Array = res.data.get("items", [])
	_breakables.apply_server(items)
	for it: Dictionary in items:
		var cid := str(it.get("id", ""))
		if cid != "" and _chest_nodes.has(cid):
			_chest_open[cid] = true
			(_chest_nodes[cid] as Chest).set_open(true, false)
			_reopen_later(cid, float(it.get("left", 0)))


## Peti terisi lagi setelah `left` detik.
func _reopen_later(cid: String, left: float) -> void:
	var mid := _map_id
	await get_tree().create_timer(maxf(left, 1.0)).timeout
	if mid == _map_id and _chest_nodes.has(cid):
		_chest_open.erase(cid)
		(_chest_nodes[cid] as Chest).set_open(false)


## Warga desa: wadah Node3D (bergerak) berisi model (berputar), bayangan, dan nama.
func _spawn_warga(map_id: String) -> void:
	_warga = []
	for def: Dictionary in Maps.WARGA:
		if def.map != map_id:
			continue
		var langkah := Session.story()
		if langkah < int(def.get("cerita_min", 0)) or langkah > int(def.get("cerita_max", 99)):
			continue  # tokoh cerita yang belum / sudah tidak ada di sini (The Last Dragon)
		var w := Warga.new(def, _warga.size() * 7919 + str(def.name).hash())
		var holder := Node3D.new()
		holder.name = "Warga_%s_%d" % [def.model, _warga.size()]
		var model := Models.create_warga(def)  # model + variasi baju/kulit/ukuran (roadmap no. 31-32)
		holder.add_child(model)
		_add_shadow(holder, 0.28)
		if def.has("alat"):
			_add_tool(str(def.alat), Vector2(def.pos), w.yaw)
		for j: Dictionary in def.get("jadwal", []):  # alat di tempat kerja jadwal (mis. lapak kain)
			if j.has("alat"):
				_add_tool(str(j.alat), Vector2(j.pos), deg_to_rad(float(j.get("hadap", 0.0))))
		var bubble := Label3D.new()  # gelembung kalimat: obrolan, teriakan, kata-kata saat bekerja
		bubble.name = "Gelembung"
		bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bubble.no_depth_test = true
		bubble.pixel_size = 0.0045
		bubble.font_size = 34
		bubble.outline_size = 10
		bubble.modulate = Color("fff3b0")
		bubble.position = Vector3(0, 2.05, 0)  # di atas nama + peran
		bubble.visible = false
		holder.add_child(bubble)
		w.bubble = bubble
		var label := Label3D.new()
		label.text = str(def.name) + ("\n" + str(def.peran) if def.has("peran") else "")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.005
		label.font_size = 36
		label.outline_size = 8
		label.modulate = Color("e8e8d0")
		label.position = Vector3(0, 1.3 if def.has("peran") else 1.15, 0)
		holder.add_child(label)
		label.set_meta("teks", label.text)
		_names.add(label, label.text, str(def.name))
		_name_label_of[Warga.TALK_PREFIX + str(w.id)] = label
		_npc_root.add_child(holder)
		w.node = holder
		w.model = model
		var job: Dictionary = w.job_at(Atmosphere.hour())
		if not job.is_empty() and not (w.door.x >= 0 and Atmosphere.is_night()):
			w.job = job  # masuk peta saat jam kerja: pekerja sudah di tempat kerjanya
			w.at_job = true
			w.pos = job.pos
			w.yaw = deg_to_rad(float(job.get("hadap", 0.0)))
		if w.door.x >= 0 and Atmosphere.outdoors(map_id) and Atmosphere.is_night():
			w.inside = true  # masuk peta saat malam: penduduk sudah di rumah
			w.pos = w.spot() if w.terlihat else w.front()
			if w.terlihat:
				w.yaw = atan2(w.arah.x, w.arah.y)
		w.apply()
		_warga.append(w)


## Nama warga di atas kepala; saat tidur ditambah "Zzz".
func _update_warga_label(w: Warga) -> void:
	for c in w.node.get_children():
		if c is Label3D and c.has_meta("teks"):
			var base := str(c.get_meta("teks", c.text))
			c.set_meta("zzz", w.sleeping)
			(c as Label3D).text = base + ("  Zzz" if w.sleeping else "")


## Benda kerja di dekat warga (roadmap no. 35-36): landasan tempa di depan pandai besi, batu tempat duduk.
func _add_tool(kind: String, at: Vector2, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "Alat_" + kind
	var fwd := Vector2(sin(yaw), cos(yaw))
	if kind == "landasan":
		var p := at + fwd * 0.55
		root.position = Vector3(p.x, 0, p.y)
		root.rotation.y = yaw
		Models.box(root, Vector3(0.28, 0.26, 0.28), Vector3(0, 0.13, 0), Color("5a4a3a"))   # balok kayu
		Models.box(root, Vector3(0.42, 0.1, 0.2), Vector3(0, 0.31, 0), Color("4a4e58"))      # landasan besi
		Models.box(root, Vector3(0.12, 0.08, 0.12), Vector3(0.24, 0.31, 0), Color("4a4e58")) # tanduk landasan
		Models.box(root, Vector3(0.1, 0.03, 0.06), Vector3(-0.05, 0.37, 0), Color("ff8a3a"), Vector3.ZERO, true)  # besi membara
		var fire := OmniLight3D.new()
		fire.light_color = Color("ff9a4a")
		fire.light_energy = 0.6
		fire.omni_range = 1.4
		fire.position = Vector3(0, 0.5, 0)
		root.add_child(fire)
	elif kind == "lapak":  # lapak kain pedagang (no. 51)
		var p := at + fwd * 0.6
		WorldBuild.lapak(root, Vector3(p.x, 0, p.y), yaw)
		root.name = "Alat_lapak"
	elif kind == "batu":
		root.position = Vector3(at.x, 0, at.y)
		Models.cyl(root, 0.26, 0.32, 0.22, Vector3(0, 0.11, 0), Color("8a8478"))
	_npc_root.add_child(root)


## Munculkan musuh berkeliaran sesuai peta dan level pemain, jauh dari tempat pemain berdiri.
## Wilayah ujian (Hutan Lebat, Gua Goblin, Gunung Batu): setelah musuh tahap ini cukup (25/75/100), tidak ada
## musuh baru sampai bos tahap itu kalah.
func _hutan_boss_phase() -> bool:
	return Maps.TRIALS.has(_map_id) and Session.trial_boss_ready(_map_id)


func _spawn_roamers(map_id: String) -> void:
	_roamers = []
	_roam_grace = ROAM_GRACE
	_roam_cfg = Maps.ROAMERS.get(map_id, {})
	_roam_kinds = []
	if _roam_cfg.is_empty() or _npc_root == null:
		return
	var level := int(Session.player.state.level)
	var weakest: Dictionary = {}
	for k: Dictionary in _roam_cfg.kinds:
		if not _kind_time_ok(k, map_id):
			continue  # musuh siang/malam (roadmap no. 188)
		if int(k.lv) <= level:
			_roam_kinds.append(k)
		if weakest.is_empty() or int(k.lv) < int(weakest.lv):
			weakest = k
	if _roam_kinds.is_empty():
		_roam_kinds = [weakest]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tries := 0
	var cap := 0 if (Maps.TRIALS.has(map_id) and Session.trial_boss_ready(map_id)) else Perf.roam_cap(int(_roam_cfg.n))
	while _roamers.size() < cap and tries < 500:
		tries += 1
		var at := _roam_spot(map_id, rng)
		if at == Vector2.ZERO:
			break
		var kind: Dictionary = _roam_kinds[rng.randi() % _roam_kinds.size()]
		_roamers.append(_make_roamer(kind, map_id, at, int(rng.randi())))


## Musuh yang hanya muncul siang atau malam ("waktu" di Maps.ROAMERS; server memeriksanya juga).
func _kind_time_ok(k: Dictionary, map_id: String) -> bool:
	var w := str(k.get("waktu", ""))
	if w == "" or not Atmosphere.outdoors(map_id):
		return true
	return (w == "malam") == Atmosphere.is_night()


## Titik acak yang cocok untuk musuh berkeliaran: petak yang sesuai, jauh dari pemain dan musuh lain.
## Vector2.ZERO bila tidak ada.
func _roam_spot(map_id: String, rng: RandomNumberGenerator) -> Vector2:
	var rows := Maps.rows(map_id)
	var min_d := 10.0 if Maps.width(map_id) >= 30 else 6.0
	var cands: Array[Vector2] = []
	for y in range(int(_roam_cfg.min_y), rows.size()):
		for x in rows[y].length():
			if not str(_roam_cfg.tiles).contains(rows[y][x]):
				continue
			var c := Vector2(x + 0.5, y + 0.5)
			if c.distance_to(_pos) >= min_d and Maps.roam_free(map_id, c):
				cands.append(c)
	for _i in 40:
		if cands.is_empty():
			return Vector2.ZERO
		var at: Vector2 = cands[rng.randi() % cands.size()]
		var apart := true
		for o in _roamers:
			if o.pos.distance_to(at) < 3.5:
				apart = false
				break
		if apart:
			return at
	return Vector2.ZERO


## Satu musuh pengganti muncul (dipanggil WorldFight setelah satu musuh tumbang).
func respawn_roamer() -> void:
	if _roam_cfg.is_empty() or _roam_kinds.is_empty() or _roamers.size() >= Perf.roam_cap(int(_roam_cfg.n)) or _hutan_boss_phase():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var at := _roam_spot(_map_id, rng)
	if at == Vector2.ZERO:
		return
	var ok_kinds: Array = []
	for k: Dictionary in _roam_kinds:
		if _kind_time_ok(k, _map_id):
			ok_kinds.append(k)
	if ok_kinds.is_empty():
		return
	var kind: Dictionary = ok_kinds[rng.randi() % ok_kinds.size()]
	_roamers.append(_make_roamer(kind, _map_id, at, int(rng.randi())))


func _make_roamer(kind: Dictionary, map_id: String, at: Vector2, seed_value: int) -> Roamer:
	var r := Roamer.new(kind, map_id, at, seed_value)
	var holder := Node3D.new()
	holder.name = "Musuh_%s_%d" % [r.id, _roamers.size()]
	var model := Models.create(r.id)
	# Variasi ukuran tiap ekor (roadmap no. 72): 90%-115% dari ukuran jenisnya.
	var jitter := 0.9 + float(seed_value % 26) / 100.0
	model.scale = model.scale * jitter
	holder.add_child(model)
	_add_shadow(holder, 0.35)
	var base_id := r.id
	var size := jitter
	if Models.VARIANTS.has(r.id):
		base_id = str(Models.VARIANTS[r.id].base)
		size *= float(Models.VARIANTS[r.id].size)
	var top := float(Models.HEIGHTS.get(base_id, 1.0)) * size
	var name_label := Label3D.new()
	name_label.text = "%s  Lv %d" % [r.label, r.lv]  # level musuh (no. 84)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.pixel_size = 0.005
	name_label.font_size = 34
	name_label.outline_size = 8
	name_label.modulate = Color("ffc2b0")
	name_label.position = Vector3(0, top + 0.3, 0)
	name_label.visible = false
	holder.add_child(name_label)
	var bang := Label3D.new()
	bang.text = "!"
	bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bang.no_depth_test = true
	bang.pixel_size = 0.011
	bang.font_size = 72
	bang.outline_size = 14
	bang.modulate = Color("ff3b30")
	bang.position = Vector3(0, top + 0.55, 0)
	bang.visible = false
	holder.add_child(bang)
	_npc_root.add_child(holder)
	r.node = holder
	r.model = model
	r.name_label = name_label
	r.alert = bang
	r.top = top
	r.apply(false)
	return r


## Musuh berjalan, mengejar bila pemain mendekat, dan memulai pertarungan langsung saat menyentuh.
func _update_roamers(delta: float) -> void:
	if _roamers.is_empty() or _locked:
		return
	_roam_grace = maxf(0.0, _roam_grace - delta)
	var can_aggro := _roam_grace <= 0.0 and not Session.offline and not _fight.busy() and _hutan_ok()
	var lvl := int(Session.player.state.get("level", 1))
	for r: Roamer in _roamers.duplicate():
		# Optimasi (roadmap no. 88): musuh jauh dari pemain (yang tidak sedang mengejar/bertarung) diperbarui jarang.
		var dt := delta
		if not r.chasing and not r.fight and r.pos.distance_to(_pos) > float(Perf.pick(Perf.ROAM_LOD_FAR)):
			r.lod_acc += delta
			if r.lod_acc < ROAM_LOD_STEP:
				continue
			dt = r.lod_acc
		r.lod_acc = 0.0
		var touched := r.step(dt, _pos, can_aggro, lvl)
		r.apply(r.pos.distance_to(_pos) < ROAM_NEAR)
		if touched and not _fight.busy():
			_fight.engage(r)
	# Pasukan prajurit (v0.66.0) menyerang sendiri musuh yang terlihat: pertarungan dimulai tanpa menunggu
	# musuh menyentuh pemain.
	if can_aggro and not _fight.busy() and Session.active_soldiers() > 0:
		var target: Roamer = null
		var best := SOLDIER_SIGHT
		for r: Roamer in _roamers:
			if r.dying or r.fight:
				continue
			var d := r.pos.distance_to(_pos)
			if d < best and Maps.roam_free(_map_id, r.pos):
				best = d
				target = r
		if target != null:
			_show_toast("Pasukan menyerang %s!" % str(target.label))
			_fight.engage(target)


## Musuh di Hutan Lebat baru aktif setelah pemain bicara dengan Kapten Rimba (server menolak pertarungannya sebelum itu).
func _hutan_ok() -> bool:
	return _map_id != Maps.HUTAN or Session.hutan_started()


## Radar Musuh: tampil di Hutan Lebat bila radar ada di ransel; titik = musuh yang masih hidup, oranye = Goblin bos.
func _update_radar() -> void:
	if _radar == null:
		return
	var on := Maps.TRIALS.has(_map_id) and Session.has_radar()
	_radar.visible = on
	if not on:
		return
	var pts: Array[Vector2] = []
	var boss := Vector2(-1, -1)
	for r: Roamer in _roamers:
		if r.dying:
			continue
		if r == _hutan_boss:
			boss = r.pos
		else:
			pts.append(r.pos)
	_radar.update_view(_pos, _cam_yaw, pts, boss)


## Pukulan/tendangan mengenai musuh berkeliaran di depan: pertarungan langsung dimulai (bila belum)
## dan aksinya (attack / skill1) dikirim ke server. Mengembalikan true bila ada musuh yang terkena.
func _hit_roamer(reach: float, cos_min: float, action := "attack") -> bool:
	if Session.offline or _locked or _roamers.is_empty():
		return false
	var f := _facing()
	var best: Roamer = null
	var best_d := reach + 0.4
	for r in _roamers:
		if r.dying:
			continue
		var off := r.pos - _pos
		var d := off.length()
		if d > reach + 0.4 or d >= best_d:
			continue
		if d > 0.05 and off.normalized().dot(f) < cos_min:
			continue
		best = r
		best_d = d
	if best == null:
		return false
	if _fight.active:
		if best == _fight.roamer:
			_fight.player_action(action)
			return true
		return false  # sedang melawan musuh lain
	if _fight.busy():
		return true  # pertarungan sedang dimulai
	if not _hutan_ok():
		_show_toast("Bicara dulu dengan Kapten Rimba")
		_set_status("Temui Kapten Rimba di kem hutan (Perbatasan) sebelum melawan musuh di hutan")
		return true
	_fight.engage(best, action)
	return true


func _add_shadow(parent: Node3D, radius: float) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.01
	m.radial_segments = 12
	disc.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0, 0.32)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.position.y = 0.02
	disc.scale = Vector3.ONE / parent.scale.x  # model sudah diskalakan; bayangan tetap berukuran dunia
	parent.add_child(disc)
	return disc


## Pindah ke peta lain; posisi baru disimpan seperti gerakan biasa.
func _go_to_map(map_id: String, at: Vector2i) -> void:
	var st: Dictionary = Session.player.state
	st.map = map_id
	_load_map(map_id)
	if Maps.is_interior(map_id):
		_cam_pitch = maxf(_cam_pitch, 0.9)  # dari atas, supaya isi ruangan terlihat
	else:
		_cam_pitch = Session.cam_pitch  # keluar ruangan: kembali ke sudut pilihan pemain
	_pos = Movement.safe_spot(map_id, at)
	_tile = Movement.tile_of(_pos)
	_step_acc = 0.0
	_spawn_roamers(map_id)
	_sync_state()
	_mark_dirty()
	_apply_transform()
	_update_talk_button()
	var visited: Array = Session.player.state.get("visited", [])
	if Maps.ZONA.has(map_id) and not visited.has(map_id) and not Session.offline:
		visited.append(map_id)  # server mencatat sendiri saat posisi disimpan (roadmap no. 198)
		notify("Wilayah baru ditemukan: %s" % Maps.NAMES.get(map_id, map_id), "info", "Wilayah baru: %s" % Maps.NAMES.get(map_id, map_id))
	else:
		_show_toast(str(Maps.NAMES.get(map_id, map_id)))
	_set_status("Memasuki %s" % Maps.NAMES.get(map_id, map_id))


# --- per bingkai ---

func _process(delta: float) -> void:
	_update_world_life(delta)
	_names_acc += delta
	if _names_acc >= 0.1:
		_names_acc = 0.0
		_layout_names()
	_lights_acc += delta
	if _lights_acc >= 0.5:
		_lights_acc = 0.0
		_cull_lights()
	if _hutan_hud != null and _hutan_hud.visible:
		_hutan_hud.update_view(Session.trial_kills(_map_id), Session.trial_wave(_map_id), _pos, _cam_yaw, Session.hutan_started() or _map_id != Maps.HUTAN, _map_id)
	_update_radar()
	_update_doors(delta)
	_tick_actions(delta)
	_follow_camera(delta, _input_vector() if not _locked else Vector2.ZERO)
	var rig := _player as Node
	if _locked:
		_set_moving(false)
		return
	var before := _pos
	var input := _input_vector()
	if _guard:
		input = Vector2.ZERO  # perisai terangkat: tetap di tempat
	_tick_jump(delta)
	var walking := false
	if input.length() > 0.08:
		var fwd := Vector2(-sin(_cam_yaw), -cos(_cam_yaw))
		var right := Vector2(cos(_cam_yaw), -sin(_cam_yaw))
		var dir := fwd * input.y + right * input.x
		if dir.length() > 1.0:
			dir = dir.normalized()
		_pos = Movement.move(_map_id, _pos, dir * SPEED * _speed_mul() * delta)
		walking = true
		if dir.length() > 0.05:
			_yaw = lerp_angle(_yaw, atan2(dir.x, dir.y), minf(1.0, delta * 14.0))
	if _dash_t > 0.0:
		var step := minf(delta, _dash_t)
		_dash_t -= step
		_pos = Movement.move(_map_id, _pos, _dash_vel * step)
	var moved := (_pos - before).length()
	_set_moving(walking and moved > 0.0001)
	_tick_stamina(delta, walking and input.length() > 0.85 and moved > 0.0001)
	if "move_speed" in _player and delta > 0.0:
		_player.move_speed = moved / delta  # klip jalan/lari mengikuti kecepatan (roadmap no. 6-7)
	if rig != null:
		_apply_transform()
	if moved > 0.0001:
		_sync_state()
		_mark_dirty()
		_after_step(moved)


## Waktu, cuaca, dan NPC yang bergerak pelan: semua hanya tampilan, tidak mengubah data permainan.
func _update_world_life(delta: float) -> void:
	Atmosphere.tick(delta)
	_atmo_acc += delta
	if _atmo_acc >= ATMO_STEP:
		_atmo_acc = 0.0
		Atmosphere.apply(_env.environment, _sun, _atmo_base, _map_id)
		Atmosphere.set_rain(_rain, _map_id)
		WorldBuild.set_wind(Atmosphere.wind_strength())  # pohon dan rumput bergoyang lebih kencang saat hujan
		_update_lamps()
		_update_clock()
	if _rain != null:
		_rain.position = Vector3(_pos.x, 7.0, _pos.y)  # hujan mengikuti pemain
	_update_npcs(delta)
	_update_roamers(delta)
	if _life != null:
		_life.tick(delta)
	if _story != null:
		_story.tick(delta)
	_poll_trades(delta)
	_tick_reconnect(delta)


## Koneksi putus/tersambung lagi (roadmap no. 231-232). Saat putus: tulisan peringatan dan server ditanya
## tiap 5 detik. Saat tersambung lagi: data pemain diambil ulang dan posisi yang belum tersimpan dikirim.
func _on_connection(is_online: bool) -> void:
	if not is_inside_tree() or Session.offline:
		return
	if _net_label != null:
		_net_label.visible = not is_online
	if is_online:
		_set_status("Tersambung lagi ke server")
		notify("Koneksi ke server tersambung lagi.", "info", "")
		var me: Dictionary = await Api.get_me()
		if me.ok and is_inside_tree():
			Session.merge_server_player(me.data)
			_refresh_hud()
		if _unsaved and not _saving and is_inside_tree():
			_save()
	else:
		_net_acc = 0.0
		_set_status("Koneksi terputus. Kemajuan disimpan setelah tersambung lagi.")


func _tick_reconnect(delta: float) -> void:
	if Api.online or Session.offline:
		return
	_net_acc += delta
	if _net_acc >= 5.0:
		_net_acc = 0.0
		Api.health()  # hasilnya memicu connection_changed bila sudah tersambung


## Token ditolak (sesi kedaluwarsa atau dicabut dari perangkat lain): kembali ke beranda untuk masuk lagi.
func _on_session_expired(message: String) -> void:
	if not is_inside_tree() or Session.offline:
		return
	Api.session_expired.disconnect(_on_session_expired)
	Session.login_notice = "%s. Silakan masuk lagi." % message.trim_suffix(".")
	Api.token = ""
	Session.save_config()
	_locked = true
	_show_toast("Sesi berakhir")
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(LOGIN_SCENE)


## Tawaran dagang masuk (roadmap no. 176, 216): diperiksa tiap 60 detik, pemberitahuan sekali per tawaran.
func _poll_trades(delta: float) -> void:
	if Session.offline:
		return
	_trade_acc += delta
	if _trade_acc < 60.0:
		return
	_trade_acc = 0.0
	var res: Dictionary = await Api.trades_get()
	if not res.ok or not is_inside_tree():
		return
	var me := str(Session.player.get("name", "")).to_lower()
	for t: Dictionary in res.data.get("trades", []):
		var id := int(t.get("id", 0))
		if str(t.get("status", "")) == "pending" and str(t.get("to", "")).to_lower() == me and not _trade_seen.has(id):
			_trade_seen[id] = true
			notify("Tawaran dagang dari %s: %s x%d seharga %d emas (Menu > Dagang)." % [t.get("from", "?"), str(t.get("item", "")), int(t.get("qty", 1)), int(t.get("price", 0))], "dagang", "Tawaran dagang masuk!")


## Jam di atas layar: ikon matahari (siang) atau bulan (malam); di Gua Batu ikon gua.
func _update_clock() -> void:
	if _clock == null:
		return
	if Maps.is_interior(_map_id):  # di dalam bangunan: ikon menurut jam, teks nama ruangan
		var hh := Atmosphere.hour()
		_clock.set_info("sun" if hh >= 5.5 and hh < 18.0 else "moon", str(Maps.NAMES.get(_map_id, "")))
		return
	if not Atmosphere.outdoors(_map_id):
		_clock.set_info("cave", str(Maps.NAMES.get(_map_id, "Gua")))
		return
	var h := Atmosphere.hour()
	_clock.set_info("sun" if h >= 5.5 and h < 18.0 else "moon", Atmosphere.label())


## Lampu menara, gapura, dan rumah menyala menjelang malam dan padam saat pagi.
func _update_lamps() -> void:
	WorldBuild.set_night(_terrain, Atmosphere.night() if Atmosphere.outdoors(_map_id) else 0.0)


## NPC menoleh ke pemain bila dekat; selain itu berjalan pelan di sekitar petaknya.
## Petak NPC tetap terblokir di Maps, jadi tabrakan dan jangkauan bicara tidak berubah.
func _update_npcs(delta: float) -> void:
	_npc_time += delta
	_update_warga(delta)
	for id: String in _npc_models:
		var model := _npc_models[id] as Node3D
		if model == null or not is_instance_valid(model):
			continue
		var home := Vector2(Maps.NPCS[id].pos) + Vector2(0.5, 0.5)
		var to_player := _pos - home
		var near := to_player.length() < NPC_NOTICE
		var phase := float(id.hash() % 100) * 0.1
		var want := home
		if not near:
			want += Vector2(sin(_npc_time * 0.35 + phase), cos(_npc_time * 0.23 + phase * 1.7)) * NPC_WANDER
		var cur := Vector2(model.position.x, model.position.z)
		var nxt := cur.move_toward(want, NPC_SPEED * delta)
		var step := nxt - cur
		var walking := step.length() > 0.0005
		model.position = Vector3(nxt.x, 0.0, nxt.y)
		var face_dir := step if (walking and not near) else to_player
		if face_dir.length() > 0.01:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(face_dir.x, face_dir.y), minf(1.0, delta * 6.0))
		if "moving" in model:
			model.moving = walking and not near


## Warga desa berjalan bebas, saling menghindar, dan menjauh dari pemain.
func _update_warga(delta: float) -> void:
	var night := Atmosphere.outdoors(_map_id) and Atmosphere.is_night()
	var hour := Atmosphere.hour()
	var monsters: Array[Vector2] = []  # warga takut pada musuh di dekatnya (roadmap no. 53-55)
	for r in _roamers:
		if not r.dying:
			monsters.append(r.pos)
	_chat_acc += delta
	if _chat_acc >= CHAT_CHECK:
		_chat_acc = 0.0
		_try_chats()
	for w in _warga:
		# Optimasi (no. 60): warga jauh dari pemain diperbarui jarang (4x sedetik, bukan tiap bingkai).
		var dt := delta
		var far := w.pos.distance_to(_pos) > float(Perf.pick(Perf.WARGA_LOD_FAR))
		if far:
			w.lod_acc += delta
			if w.lod_acc < WARGA_LOD_STEP:
				continue
			dt = w.lod_acc
		w.lod_acc = 0.0
		var others: Array[Vector2] = []
		for o in _warga:
			if o != w and not o.inside:
				others.append(o.pos)
		var was_sleeping: bool = w.sleeping
		# Berteduh saat hujan deras / serbuan (roadmap no. 190, 193); penjaga desa tetap di luar.
		w.shelter = Atmosphere.outdoors(_map_id) and (Atmosphere.rain > 0.85 or (_life != null and _life.raid_on)) and not Maps.RAID_GUARDS.has(w.id)
		# Tokoh cerita yang sedang menunggu pemain (Kepala Desa di prolog dan epilog) tetap di luar saat malam.
		var awake: bool = (Maps.STORY_AWAKE.get(w.id, []) as Array).has(Session.story())
		if awake:
			w.shelter = false
		w.step(dt, _pos, others, night and not awake, hour, monsters)
		w.apply()
		if w.sleeping != was_sleeping and w.node != null:
			_update_warga_label(w)


## Dua warga yang berpapasan berhenti dan mengobrol sebentar (roadmap no. 50).
func _try_chats() -> void:
	for i in _warga.size():
		var a: Warga = _warga[i]
		if not a.can_chat():
			continue
		for j in range(i + 1, _warga.size()):
			var b: Warga = _warga[j]
			if not b.can_chat() or a.pos.distance_to(b.pos) > CHAT_DIST:
				continue
			var lines: Array = WargaDialog.chat_pair(_chat_n)
			_chat_n += 1
			a.start_chat(b.pos, str(lines[0]))
			b.start_chat(a.pos, str(lines[1]))
			b.say_t = Warga.CHAT_TIME  # jawaban muncul bersamaan; keduanya terlihat bercakap
			for m: Node3D in [a.model, b.model]:
				if m != null and m.has_method("play_action"):
					m.call("play_action", "bicara")
			break


func _set_moving(v: bool) -> void:
	if "moving" in _player:
		_player.moving = v


func _apply_transform() -> void:
	var jy := _jump_height()
	_player.position = Vector3(_pos.x, jy, _pos.y)
	_player.rotation.y = _yaw
	if _shadow_disc != null:
		_shadow_disc.position.y = 0.02 - jy / maxf(0.01, _player.scale.x)  # bayangan tetap di tanah
	var target := Vector3(_pos.x, 0.8 + jy * 0.5, _pos.y)
	var inside := Maps.is_interior(_map_id)
	var dist := CAM_DIST * 0.95 if inside else Session.cam_dist
	if inside:
		target.z -= 1.5  # pandangan condong ke dalam ruangan: meja kasir dan penjaga ikut terlihat
	# Kamera mengikuti dengan halus (roadmap no. 19); lompatan jauh (pindah peta, dipulangkan) langsung.
	var dt := get_process_delta_time()
	if _cam_ready and _cam_target.distance_to(target) < CAM_SNAP and dt > 0.0:
		_cam_target = _cam_target.lerp(target, minf(1.0, dt * CAM_FOLLOW))
	else:
		_cam_target = target
		_cam_ready = true
	target = _cam_target
	var offset := Vector3(sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch)) * dist
	_camera.position = target + offset
	if _shake > 0.0:
		_camera.position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * _shake * 0.5
	_camera.look_at(target, Vector3.UP)
	for a: MeshInstance3D in [_aura_guard, _aura_boost]:
		if a != null:
			a.position = Vector3(_pos.x, 0.55, _pos.y)
	_update_talk_button()


## Menyalin posisi ke data pemain (yang dikirim ke server saat menyimpan).
func _sync_state() -> void:
	var st: Dictionary = Session.player.state
	var t := Movement.tile_of(_pos)
	st.map = _map_id
	st.x = t.x
	st.y = t.y
	st.fx = _pos.x
	st.fz = _pos.y
	st.yaw = _yaw


func _mark_dirty() -> void:
	_unsaved = true
	if _save_timer != null:
		_save_timer.start(SAVE_DELAY)


## Dipanggil tiap kali pemain bergerak sejauh `moved` petak.
func _after_step(moved: float) -> void:
	var t := Movement.tile_of(_pos)
	if t != _tile:
		_tile = t
		if _fight.active:
			_set_status("Selesaikan pertarungan atau kabur dulu")
			return
		var ex := Maps.exit_at(_map_id, t.x, t.y)
		if not ex.is_empty():
			if str(ex.to) == Maps.RUMAH_PEMAIN and not bool(Session.player.state.get("house", false)):
				_pos = Vector2(_pos.x, float(t.y) + 1.6)  # rumah belum dibeli: mundur dari pintu (no. 127)
				_tile = Movement.tile_of(_pos)
				_apply_transform()
				_show_toast("Rumah ini dijual")
				_set_status("Rumah dijual %d emas: tekan \"Beli rumah\" di depan pintunya" % Maps.HARGA_RUMAH)
				return
			if Maps.exit_locked(_map_id, t.x, t.y, Session.trial_wave(_map_id)):
				_pos = Vector2(_pos.x, float(t.y) - 0.6)   # gerbang wilayah ujian masih terkunci: mundur selangkah
				_tile = Movement.tile_of(_pos)
				_apply_transform()
				_show_toast("Gerbang terkunci!")
				_set_status("Kalahkan 3 bos di %s untuk membuka jalan ke %s" % [Maps.NAMES.get(_map_id, _map_id), Maps.NAMES.get(str(Maps.TRIALS[_map_id].next), "")])
				return
			if Maps.story_locked(_map_id, t.x, t.y, Session.story()):
				# Gerbang cerita The Last Dragon belum terbuka: mundur selangkah ke arah datang.
				var back := -0.6 if t.y > Maps.height(_map_id) / 2 else 1.6
				_pos = Vector2(_pos.x, float(t.y) + back)
				_tile = Movement.tile_of(_pos)
				_apply_transform()
				_show_toast("Jalan tertutup!")
				_set_status(str(Maps.STORY_GATES[_map_id].pesan))
				return
			_go_to_map(str(ex.to), ex.at)
			return
		if not Session.offline and _map_id != Maps.HUTAN and Maps.tile_at(_map_id, t.x, t.y) == Maps.BOSS_TILE \
				and Maps.boss_tile_active(_map_id, Session.story()):
			_start_encounter(true)
			return
	if Session.offline or _locked or _fight.busy():
		return
	var tile := Maps.tile_at(_map_id, _tile.x, _tile.y)
	if tile == "" or not Maps.ENCOUNTER_TILES.contains(tile) or _map_id == Maps.DEFAULT_MAP:
		return  # pertemuan hanya terjadi di ladang hutan / kerikil; Desa Awal aman
	_step_acc += moved
	while _step_acc >= 1.0:
		_step_acc -= 1.0
		if Session.safe_steps > 0:
			Session.safe_steps -= 1
		elif randf() < ENCOUNTER_CHANCE:
			_fight.engage_random()
			return


func _facing() -> Vector2:
	return Vector2(sin(_yaw), cos(_yaw))


func _speed_mul() -> float:
	var m := 1.0
	if _boost_t > 0.0:
		m *= BOOST_SPEED
	if _tired:
		m *= TIRED_SPEED  # kehabisan stamina: hanya bisa berjalan (no. 135)
	return m


## Stamina (no. 135): berkurang saat berlari (joystick didorong penuh) dan melompat, pulih saat berjalan/diam.
func _tick_stamina(delta: float, running: bool) -> void:
	if running and not _tired:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * delta)
		if stamina <= 0.0:
			_tired = true
			_set_status("Kehabisan napas! Berjalan dulu sebentar.")
	else:
		stamina = minf(100.0, stamina + STAMINA_REGEN * delta * (1.6 if not running else 1.0))
		if _tired and stamina >= STAMINA_RECOVER:
			_tired = false
	if _bars != null:
		_bars.set_stamina(stamina / 100.0, _tired)


## Pencapaian baru (no. 150): pemberitahuan; hadiahnya diambil di Atribut > Pencapaian.
func _on_achievement(id: String) -> void:
	notify("Pencapaian baru terbuka. Ambil hadiahnya di Atribut > Pencapaian.", "hadiah", "Pencapaian baru!")
	_set_status("Pencapaian terbuka: ambil hadiahnya di menu Atribut > Pencapaian")
	HeroFx.ring(self, Vector3(_pos.x, 0.1, _pos.y), Color("ffd24a"), 2.2, 0.6)


## Tubuh model pahlawan (anak rig), dipakai untuk gerakan tambahan seperti menendang dan berguling.
func _body() -> Node3D:
	if _player != null and _player.get_child_count() > 0:
		return _player.get_child(0) as Node3D
	return null


func _tick_actions(delta: float) -> void:
	for k: String in _cd:
		_cd[k] = maxf(0.0, float(_cd[k]) - delta)
	_combo_t = maxf(0.0, _combo_t - delta)
	if _combo_t <= 0.0:
		_combo = 0
	_kick_t = maxf(0.0, _kick_t - delta)
	if _kick_t <= 0.0:
		_kick = 0
	_shake = maxf(0.0, _shake - delta)
	if _btn_tangan == null:
		return
	_btn_tangan.cooldown = float(_cd.tangan) / float(_cd_len.tangan)
	_btn_kaki.cooldown = float(_cd.kaki) / float(_cd_len.kaki)
	_btn_perisai.cooldown = float(_cd.hindar) / float(_cd_len.hindar)
	_btn_lompat.cooldown = float(_cd.lompat) / float(_cd_len.lompat)
	if _guard:
		if _btn_perisai.is_held() and _guard_t < 0.25:
			_guard_t = 0.25  # jari masih menahan Perisai: perisai tetap terangkat
		_guard_t -= delta
		if _guard_t <= 0.0 or _locked:
			_lower_guard()
	if _boost_t > 0.0:
		_boost_t -= delta
		_btn_boost.charge = clampf(_boost_t / BOOST_TIME, 0.0, 1.0)
		_btn_boost.active = true
		_btn_boost.glow = false
		if _aura_boost != null:
			_aura_boost.visible = true
			_aura_boost.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() / 90.0))
		if _boost_t <= 0.0:
			_end_boost()
	if _shake > 0.0 and _player != null:
		_apply_transform()
	_hint_t -= delta
	if _hint_t <= 0.0:
		_hint_t = 0.3
		for id: String in _chest_nodes:
			var n := _chest_nodes[id] as Chest
			n.set_hint(_pos.distance_to(Vector2(n.position.x, n.position.z)) < 4.0)
		_update_talk_button()


func _end_boost() -> void:
	_boost_t = 0.0
	_btn_boost.active = false
	_btn_boost.charge = _energy / 100.0
	_btn_boost.glow = _energy >= 100.0
	if _aura_boost != null:
		_aura_boost.visible = false


func _add_energy(v: float) -> void:
	if _boost_t > 0.0:
		return
	_energy = minf(100.0, _energy + v)
	_btn_boost.charge = _energy / 100.0
	_btn_boost.glow = _energy >= 100.0


## Putar menghadap benda terdekat di depan, supaya pukulan tidak harus pas membidik.
func _aim_assist(reach: float) -> void:
	# Musuh lebih dulu (roadmap no. 168): putar badan ke musuh terdekat yang ada di depan/samping.
	var best: Roamer = null
	var best_d := reach * 1.2 + 0.4
	for r in _roamers:
		if r.dying:
			continue
		var off := r.pos - _pos
		var d := off.length()
		if d < best_d and (d < 0.05 or off.normalized().dot(_facing()) > -0.2):
			best = r
			best_d = d
	if best != null:
		var to := best.pos - _pos
		if to.length() > 0.05:
			_yaw = atan2(to.x, to.y)
		return
	if _breakables == null:
		return
	var near := _breakables.targets(_pos, _facing(), reach * 1.3, -0.2, 1, 0)
	if near.is_empty():
		return
	var off: Vector2 = (near[0] as Dictionary).pos - _pos
	_yaw = atan2(off.x, off.y)


func _dash(dir: Vector2, dist: float, time: float) -> void:
	if dir == Vector2.ZERO:
		return
	_dash_vel = dir.normalized() * dist / time
	_dash_t = time


## Satu ayunan: pukul benda dalam jangkauan, isi tenaga Boost, laporkan yang hancur ke server.
func _swing(reach: float, cos_min: float, dmg: float, solid_n: int, grass_n: int, action := "attack") -> int:
	if _hit_roamer(reach, cos_min, action):
		return 1
	if _breakables == null or _fight.busy():
		return 0  # saat bertarung pukulan hanya untuk musuh (server menolak aksi dunia selama pertarungan)
	if _boost_t > 0.0:
		dmg *= 2.0
	var list := _breakables.targets(_pos, _facing(), reach, cos_min, solid_n, grass_n)
	if list.is_empty():
		return 0
	var broken := _breakables.strike(list, dmg)
	_add_energy(ENERGY_PER_HIT * minf(list.size(), 3.0) + ENERGY_PER_BREAK * broken.size())
	_queue_breaks(broken)
	return list.size()


func _rig_attack() -> void:
	if _player != null and _player.has_method("play_attack"):
		_player.call("play_attack")


## Tinju dobel -> tebas dobel -> tusuk. Tiap pukulan mengenai pada detik `hits` (selaras dengan gerakan tubuh).
func _do_tangan() -> void:
	if _locked or float(_cd.tangan) > 0.0:
		return
	_lower_guard()
	var combo := combo_list()
	_combo = _combo + 1 if (_combo_t > 0.0 and _combo < combo.size()) else 1
	_combo_t = COMBO_WINDOW
	var sp: Dictionary = combo[_combo - 1]
	_cd.tangan = float(sp.cd)
	_cd_len.tangan = float(sp.cd)
	_aim_assist(float(sp.reach))
	_rig_action(str(sp.anim))
	_dash(_facing(), float(sp.dash), 0.1)
	_set_status(str(sp.nama) + ("!" if _combo == combo.size() else ""))
	var hits: Array = sp.hits
	for h in hits.size():
		await get_tree().create_timer(float(hits[h]) - (float(hits[h - 1]) if h > 0 else 0.0)).timeout
		if not is_inside_tree() or _locked:
			return
		_strike_fx(sp)
		_swing(float(sp.reach), float(sp.cos), float(sp.dmg), int(sp.solid), int(sp.grass))


## Kombo serangan biasa untuk gaya senjata pahlawan yang dipakai.
func combo_list() -> Array:
	return STYLE_COMBOS.get(style(), COMBO)


func style() -> String:
	return str(Heroes.current().get("style", "pedang"))


## Efek satu pukulan/tembakan: jejak senjata, peluru yang terbang ke sasaran, atau gelombang kejut.
func _strike_fx(sp: Dictionary) -> void:
	if sp.has("proj"):
		var kind := str(sp.proj)
		var from := Vector3(_pos.x, 0.75, _pos.y) + Vector3(_facing().x, 0, _facing().y) * 0.4
		var to2 := _shot_target(float(sp.reach), float(sp.cos))
		var top := 0.6
		for r in _roamers:
			if not r.dying and r.pos.distance_to(to2) < 0.05:
				top = r.top * 0.55
		HeroFx.bolt(self, from, Vector3(to2.x, top, to2.y), PROJ_COLOR.get(kind, Color.WHITE), kind)
	elif sp.has("len"):
		HeroFx.swoosh(self, Vector3(_pos.x, 0.65, _pos.y), _yaw, float(sp.len), sp.get("swoosh", Color("fff2c0")) as Color, float(sp.roll))
	if bool(sp.get("wave", false)):
		var at := Vector3(_pos.x, 0.05, _pos.y) + Vector3(_facing().x, 0, _facing().y) * (1.2 if sp.has("len") else 0.0)
		HeroFx.ring(self, at, sp.get("swoosh", PROJ_COLOR.get(str(sp.get("proj", "")), Color("ffd0a0"))) as Color, 2.0, 0.4)
		_shake = maxf(_shake, 0.18)


## Titik sasaran tembakan: musuh terdekat di depan dalam jangkauan, atau ujung jangkauan.
func _shot_target(reach: float, cos_min: float) -> Vector2:
	var f := _facing()
	var best := _pos + f * reach
	var best_d := reach + 0.4
	for r in _roamers:
		if r.dying:
			continue
		var off := r.pos - _pos
		var d := off.length()
		if d < best_d and (d < 0.05 or off.normalized().dot(f) >= cos_min):
			best = r.pos
			best_d = d
	return best


## 1x tendang, 2x (dalam jeda singkat) tendangan dobel: dua kali menendang.
func _do_kaki(_held := 0.0) -> void:
	if _locked or float(_cd.kaki) > 0.0:
		return
	_lower_guard()
	if STYLE_SKILL.has(style()):
		_do_shot_skill(STYLE_SKILL[style()])
		return
	_kick = _kick + 1 if (_kick_t > 0.0 and _kick < KICKS.size()) else 1
	_kick_t = KICK_WINDOW
	var sp: Dictionary = KICKS[_kick - 1]
	_cd.kaki = float(sp.cd)
	_cd_len.kaki = float(sp.cd)
	_aim_assist(float(sp.reach))
	_rig_action(str(sp.anim))
	_dash(_facing(), float(sp.dash), 0.1)
	_set_status(str(sp.nama) + "!")
	var prev := 0.0
	var hits: Array = sp.hits
	for h in hits.size():
		await get_tree().create_timer(float(hits[h]) - prev).timeout
		prev = float(hits[h])
		if not is_inside_tree() or _locked:
			return
		HeroFx.swoosh(self, Vector3(_pos.x, 0.3, _pos.y), _yaw, 1.0, Color("bfe8ff"))
		HeroFx.ring(self, Vector3(_pos.x, 0.0, _pos.y), Color("7fd1ff"), 1.0, 0.25)
		_swing(float(sp.reach), float(sp.cos), float(sp.dmg), int(sp.solid), int(sp.grass), "skill1")


## Jurus 1 gaya jarak jauh (Panah Tembus / Bola Api): satu tembakan besar.
func _do_shot_skill(sp: Dictionary) -> void:
	_cd.kaki = float(sp.cd)
	_cd_len.kaki = float(sp.cd)
	_aim_assist(float(sp.reach))
	_rig_action(str(sp.anim))
	_dash(_facing(), float(sp.dash), 0.1)
	_set_status(str(sp.nama) + "!")
	await get_tree().create_timer(float((sp.hits as Array)[0])).timeout
	if not is_inside_tree() or _locked:
		return
	_strike_fx(sp)
	_swing(float(sp.reach), float(sp.cos), float(sp.dmg), int(sp.solid), int(sp.grass), "skill1")


## Ketuk Perisai sekali: perisai terangkat dan pahlawan tetap di tempat. Ketuk dua kali cepat: menghindar.
func _on_perisai_pressed() -> void:
	if _locked:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _tap_t <= DOUBLE_TAP and float(_cd.hindar) <= 0.0:
		_tap_t = -10.0
		_lower_guard()
		_do_dodge()
		return
	_tap_t = now
	_raise_guard()
	# Dalam pertarungan, mengangkat perisai langsung bertahan di server (waktunya menentukan tangkisan sempurna).
	if _fight != null and _fight.active:
		_fight.player_action("defend")


func _raise_guard() -> void:
	_guard = true
	_guard_t = GUARD_TIME
	_btn_perisai.active = true
	if _aura_guard != null:
		_aura_guard.visible = true
	_rig_action("tangkis")
	_set_status("Perisai terangkat. Ketuk dua kali untuk menghindar")


func _lower_guard() -> void:
	if not _guard:
		return
	_guard = false
	_guard_t = 0.0
	if _btn_perisai != null:
		_btn_perisai.active = false
	if _aura_guard != null:
		_aura_guard.visible = false
	var rig := _player as Node
	if rig != null and rig.has_method("stop_action"):
		rig.call("stop_action")


## Alias papan ketik/uji: sama dengan satu ketukan Perisai.
func _do_perisai(_held := 0.0) -> void:
	_on_perisai_pressed()


## Menghindar: melompat/berguling ke arah joystick (tanpa arah joystick: mundur).
func _do_dodge() -> void:
	if _locked or float(_cd.hindar) > 0.0:
		return
	_cd.hindar = 0.9
	_cd_len.hindar = 0.9
	var input := _input_vector()
	var dir := -_facing()  # tanpa arah joystick: melompat mundur
	if input.length() > 0.08:
		var fwd := Vector2(-sin(_cam_yaw), -cos(_cam_yaw))
		var right := Vector2(cos(_cam_yaw), -sin(_cam_yaw))
		dir = fwd * input.y + right * input.x
	_dash(dir, 2.1, 0.22)
	# Dalam pertarungan, menghindar dikirim ke server (roadmap no. 162): serangan musuh yang tiba
	# sesaat setelahnya meleset.
	if _fight != null and _fight.active:
		_fight.player_action("dodge")
	HeroFx.burst(self, Vector3(_pos.x, 0.1, _pos.y), Color("d9c8a0"), 6, 1.4)
	var body := _body()
	if body != null:
		var side := dir.normalized()
		var rot_sign := signf(side.dot(_facing()))
		var tw := create_tween()
		tw.tween_property(body, "rotation:x", TAU * (1.0 if rot_sign >= 0.0 else -1.0), 0.24)
		tw.tween_callback(func() -> void: body.rotation.x = 0.0)
	_set_status("Menghindar!")


# --- lompat ---

func _do_lompat() -> void:
	if _locked or _jump_t > 0.0 or float(_cd.lompat) > 0.0:
		return
	if stamina < STAMINA_JUMP:
		_set_status("Terlalu lelah untuk melompat")
		return
	stamina -= STAMINA_JUMP
	_jump_t = JUMP_TIME
	_cd.lompat = 0.85
	_cd_len.lompat = 0.85
	_rig_action("lompat")
	HeroFx.burst(self, Vector3(_pos.x, 0.1, _pos.y), Color("d9c8a0"), 6, 1.2)


func _tick_jump(delta: float) -> void:
	if _jump_t <= 0.0:
		return
	_jump_t = maxf(0.0, _jump_t - delta)
	if _jump_t <= 0.0:
		HeroFx.burst(self, Vector3(_pos.x, 0.1, _pos.y), Color("d9c8a0"), 5, 1.0)


## Tinggi pahlawan di atas tanah: parabola selama lompat.
func _jump_height() -> float:
	if _jump_t <= 0.0:
		return 0.0
	var u := 1.0 - _jump_t / JUMP_TIME
	return JUMP_HEIGHT * 4.0 * u * (1.0 - u)


## Gerakan tubuh pahlawan (hero_actions.gd); model tanpa rangka itu memakai klip serang biasa.
func _rig_action(anim: String) -> void:
	if _player != null and _player.has_method("play_action"):
		_player.call("play_action", anim)


func _do_boost() -> void:
	if _locked or _boost_t > 0.0:
		return
	if _energy < 100.0:
		_set_status("Boost belum penuh: %d%%" % int(_energy))
		return
	_energy = 0.0
	_boost_t = BOOST_TIME
	_btn_boost.glow = false
	_rig_attack()
	_shake = 0.35
	HeroFx.ring(self, Vector3(_pos.x, 0.0, _pos.y), Color("ffb347"), 3.6, 0.5)
	HeroFx.burst(self, Vector3(_pos.x, 0.5, _pos.y), Color("ffd25a"), 24, 4.0)
	if _hit_roamer(3.4, -1.0):
		return
	if _breakables != null:
		var list := _breakables.targets(_pos, Vector2.ZERO, 3.4, -1.0, 99, 99)
		_queue_breaks(_breakables.strike(list, 99.0))
	_show_toast("BOOST!")
	_set_status("Mode Boost: lebih cepat, pukulan dua kali lipat")


# --- hadiah dunia ---

func _queue_breaks(broken: Array) -> void:
	if broken.is_empty() or Session.offline:
		return
	for e: Dictionary in broken:
		var t: Vector2i = e.tile
		var item := {"kind": str(e.kind), "x": t.x, "z": t.y}
		if not _pending.has(item):
			_pending.append(item)
	if _flush_timer != null and _flush_timer.is_stopped():
		_flush_timer.start(BREAK_FLUSH)


func _flush_breaks() -> void:
	if _pending.is_empty():
		return
	if _breaking or _locked:
		_flush_timer.start(BREAK_FLUSH)
		return
	var batch: Array = _pending.slice(0, 12)
	_pending = _pending.slice(batch.size())
	_breaking = true
	var res: Dictionary = await Api.world_break(_map_id, _pos, _yaw, batch)
	_breaking = false
	if res.ok:
		Session.merge_server_player(res.data.player)
		_refresh_hud()
		_show_loot(res.data.loot, false)
	elif res.status == 409:
		_pending.clear()  # sedang bertarung di server: benda tetap hancur, tanpa hadiah
	if not _pending.is_empty():
		_flush_timer.start(BREAK_FLUSH)


## Satu baris hadiah ("+12 emas  +Berlian") di tengah layar.
func _show_loot(loot: Dictionary, chest: bool) -> void:
	var parts: Array[String] = []
	var gold := int(loot.get("gold", 0))
	if gold > 0:
		parts.append("+%d emas" % gold)
	var items: Variant = loot.get("items")
	if items is Array:
		for it: Dictionary in items:
			var nm := str(ITEM_NAMES.get(str(it.id), str(it.id)))
			parts.append("+%s" % nm if int(it.qty) <= 1 else "+%d %s" % [int(it.qty), nm])
	if parts.is_empty():
		return
	_show_toast(("Peti: " if chest else "") + "  ".join(parts))
	if items is Array and not (items as Array).is_empty():
		_set_status("Barang masuk Ransel (buka lewat Menu)")


func _open_chest(cid: String) -> void:
	if _chest_busy or _locked:
		return
	_chest_busy = true
	var res: Dictionary = await Api.world_chest(cid, _map_id, _pos, _yaw)
	_chest_busy = false
	var node := _chest_nodes.get(cid) as Chest
	if res.ok:
		Session.merge_server_player(res.data.player)
		_refresh_hud()
		_chest_open[cid] = true
		if node != null:
			node.set_open(true)
			HeroFx.burst(self, node.position + Vector3(0, 0.5, 0), Color("ffd24a"), 26, 3.4)
			HeroFx.ring(self, node.position, Color("ffd24a"), 2.0, 0.6)
		_shake = 0.2
		_rig_action("ambil")  # roadmap no. 13: pahlawan jongkok mengambil isi peti
		_show_loot(res.data.loot, true)
		_reopen_later(cid, 1800.0)
	else:
		if node != null and str(res.error).contains("kosong"):
			_chest_open[cid] = true
			node.set_open(true, false)
			_reopen_later(cid, 60.0)
		_show_toast(str(res.error))


# --- masukan ---

func _input_vector() -> Vector2:
	var v := Vector2.ZERO
	if _joy != null:
		v = _joy.vec  # x kanan, y bawah layar
		v.y = -v.y  # y positif = maju
	var k := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)))
	if k != Vector2.ZERO:
		v = k
	if Input.is_physical_key_pressed(KEY_Q):
		_cam_yaw -= 0.03
	if Input.is_physical_key_pressed(KEY_E):
		_cam_yaw += 0.03
	return v


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		_toggle_menu()
		return
	if _locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_J: _do_tangan()
			KEY_K: _do_kaki(0.0)
			KEY_L: _do_perisai()
			KEY_SPACE: _do_lompat()
			KEY_U: _do_boost()
	# Geser layar (di luar joystick dan tombol) untuk memutar kamera.
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			if _cam_finger < 0 and not _on_ui(te.position):
				_cam_finger = te.index
		elif te.index == _cam_finger:
			_cam_finger = -1
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == _cam_finger:
			_rotate_camera(de.relative)
	elif event is InputEventMouseMotion:
		var me := event as InputEventMouseMotion
		if me.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_rotate_camera(me.relative)


## Kamera ikut di belakang (v0.68.3): selama layar digeser kamera bebas melihat ke kanan-kiri dan atas-bawah;
## sejak jari dilepas CAM_RETURN_DELAY detik, kamera kembali pelan ke belakang pahlawan, menghadap ke arah
## yang ia hadapi, dan sudut atas-bawah kembali normal. Saat berjalan menyamping kembalinya diperlambat supaya
## pahlawan tidak berlari berputar-putar. Tidak berlaku di dalam ruangan (kamera ruangan tetap dari depan).
const CAM_RETURN_DELAY := 1.2
const CAM_RETURN_RATE := 2.6


func _follow_camera(delta: float, input: Vector2) -> void:
	if _cam_finger >= 0:
		_cam_idle = 0.0
		return
	_cam_idle += delta
	if Maps.is_interior(_map_id):
		return
	if Session.cam_lock:
		# Kamera dikunci: selalu di belakang pahlawan dengan sudut pilihan pemain (tanpa jeda).
		_cam_yaw = lerp_angle(_cam_yaw, _yaw + PI, minf(1.0, delta * CAM_RETURN_RATE * (1.0 - 0.75 * clampf(absf(input.x), 0.0, 1.0))))
		_cam_pitch = Session.cam_pitch
		return
	if not Session.cam_follow or _cam_idle < CAM_RETURN_DELAY:
		return
	var k := minf(1.0, delta * CAM_RETURN_RATE * (1.0 - 0.75 * clampf(absf(input.x), 0.0, 1.0)))
	_cam_yaw = lerp_angle(_cam_yaw, _yaw + PI, k)
	_cam_pitch = lerpf(_cam_pitch, Session.cam_pitch, minf(1.0, delta * CAM_RETURN_RATE))


func _rotate_camera(rel: Vector2) -> void:
	if Session.cam_lock:
		return  # kamera dikunci di Pengaturan
	_cam_idle = 0.0
	_cam_yaw -= rel.x * 0.008 * Session.cam_sens
	_cam_pitch = clampf(_cam_pitch + rel.y * 0.004 * Session.cam_sens, 0.12, 1.15)


func _on_ui(p: Vector2) -> bool:
	if _joy != null and _joy.get_global_rect().has_point(p):
		return true
	for b in _buttons:
		if b.visible and b.get_global_rect().has_point(p):
			return true
	for a: ActionButton in _act_buttons:
		if a.get_global_rect().has_point(p):
			return true
	return false


# --- pertarungan, NPC, layar lain ---

func _start_encounter(boss := false, enemy := "") -> void:
	if _locked:
		return
	_locked = true
	if enemy == "":
		_set_status("Sesuatu menyambutmu di singgasana..." if boss else "Sesuatu bergerak di sekitarmu...")
	await _flush_save()  # posisi harus tersimpan dulu; server tidak ikut gerak kita
	var res: Dictionary = await Api.battle_start(boss, enemy)
	if res.ok:
		_enter_battle(res.data)
	elif res.status == 409:
		# Sudah ada pertarungan di server: lanjutkan yang itu.
		if not await _resume_battle_if_any():
			_locked = false
	else:
		_locked = false
		_set_status(str(res.error))


## Mengembalikan true bila ada pertarungan berjalan dan layar pindah ke sana.
func _resume_battle_if_any() -> bool:
	var res: Dictionary = await Api.battle_get()
	if not res.ok:
		return false
	_locked = true
	_enter_battle(res.data)
	return true


func _enter_battle(data: Dictionary) -> void:
	Session.merge_server_player(data.player)
	var battle: Variant = data.get("battle")
	Session.battle = battle if battle is Dictionary else {}
	get_tree().change_scene_to_file(BATTLE_SCENE)


## id NPC terdekat dalam jangkauan bicara, atau "".
func _npc_in_range() -> String:
	var best := ""
	var best_d := TALK_RANGE
	for id: String in Maps.NPCS:
		var n: Dictionary = Maps.NPCS[id]
		if n.map != _map_id:
			continue
		var d := _pos.distance_to(Vector2(n.pos) + Vector2(0.5, 0.5))
		if d <= best_d:
			best_d = d
			best = id
	for w in _warga:  # warga desa: posisi hidup (mereka berjalan), id dialog berawalan "warga:"
		if (w.inside and not w.terlihat) or w.sleeping:
			continue  # di dalam rumah atau sedang tidur: tidak bisa diajak bicara
		var wd := _pos.distance_to(w.pos)
		var lim := KEEPER_RANGE if w.toko != "" else TALK_RANGE  # penjaga di balik meja kasir terjangkau lebih jauh
		if wd <= lim and (best == "" or wd <= best_d):
			best_d = wd
			best = Warga.TALK_PREFIX + w.id
	return best


func _chest_in_range() -> String:
	var best := ""
	var best_d := CHEST_RANGE
	for id: String in _chest_nodes:
		if _chest_open.has(id):
			continue
		var n := _chest_nodes[id] as Node3D
		var d := _pos.distance_to(Vector2(n.position.x, n.position.z))
		if d <= best_d:
			best_d = d
			best = id
	return best


## Tombol konteks: "Buka peti" dekat peti, "Bicara" dekat orang; selain itu tersembunyi.
## Tombolnya melayang tepat di atas nama orang/peti yang dituju (mengikuti kamera).
func _update_talk_button() -> void:
	if _talk_button == null:
		return
	if _fight != null and _fight.busy():
		_talk_button.visible = false  # tidak bisa bicara / buka peti saat bertarung
		return
	var chest := _chest_in_range()
	if chest != "" and not Session.offline:
		_talk_button.text = "Buka peti"
		_talk_button.visible = true
		_talk_button.disabled = false
		var cn := _chest_nodes[chest] as Node3D
		_place_talk_button(cn.position + Vector3(0, 1.5, 0))
		return
	if _bed_near():
		_talk_button.text = "Tidur"
		_talk_button.visible = true
		_talk_button.disabled = Session.offline
		_place_talk_button(Vector3(BED_AT.x, 1.4, BED_AT.y))
		return
	if _story != null and not Session.offline and _story.stone_near():
		_talk_button.text = "Hancurkan"
		_talk_button.visible = true
		_talk_button.disabled = false
		_place_talk_button(_story.stone_anchor())
		return
	var secret: String = _life.secret_near() if _life != null else ""
	if secret != "" and not Session.offline:
		_talk_button.text = "Periksa"
		_talk_button.visible = true
		_talk_button.disabled = false
		_place_talk_button(_life.secret_anchor(secret))
		return
	if _store_near():
		_talk_button.text = "Peti simpan"
		_talk_button.visible = true
		_talk_button.disabled = Session.offline
		_place_talk_button(Vector3(STORE_AT.x, 1.6, STORE_AT.y))
		return
	if _house_for_sale_near():
		_talk_button.text = "Beli rumah (%d emas)" % Maps.HARGA_RUMAH
		_talk_button.visible = true
		_talk_button.disabled = Session.offline
		_place_talk_button(Vector3(Maps.RUMAH_PEMAIN_PINTU.x + 0.5, 2.2, Maps.RUMAH_PEMAIN_PINTU.y + 1.0))
		return
	var npc := _npc_in_range()
	_talk_button.text = "Bicara"
	_talk_button.visible = npc != ""
	_talk_button.disabled = Session.offline
	if npc != "":
		_place_talk_button(_npc_anchor(npc))


## Hanya beberapa lampu titik terdekat yang menyala (Perf.LIGHTS): di perender HP (GL Compatibility)
## setiap lampu menambah lintasan gambar untuk benda yang diteranginya — malam di desa (±23 lampu)
## dulu turun ke ±13 FPS di Samsung A50.
func _cull_lights() -> void:
	var cand: Array = []
	for l in _lights:
		if not is_instance_valid(l):
			continue
		var on := bool(l.get_meta("malam_on", true))
		var d := Vector2(l.global_position.x, l.global_position.z).distance_to(_pos) if l.is_inside_tree() else 0.0
		cand.append([d, l, on])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var left: int = int(Perf.pick(Perf.LIGHTS))
	for c: Array in cand:
		var l: OmniLight3D = c[1]
		var allowed: bool = c[2] and left > 0
		if allowed:
			left -= 1
		l.set_meta("jauh", not allowed)
		l.visible = allowed


## Nama di atas kepala tidak saling menumpuk dan tidak tertutup tombol konteks.
func _layout_names() -> void:
	var obstacle := Rect2()
	var owner: Label3D = null
	if _talk_button != null and _talk_button.visible:
		obstacle = Rect2(_talk_button.position, _talk_button.size)
		if _talk_button.text == "Bicara":
			owner = _name_label_of.get(_npc_in_range(), null)
	var hud: Array = []
	for it: Array in _hud_items:
		var c := it[0] as Control
		if str(it[2]).begins_with("t") and is_instance_valid(c) and c.is_visible_in_tree():
			var r := c.get_global_rect()
			if c is Label:  # kotak label bisa jauh lebih lebar dari tulisannya
				var lb := c as Label
				if lb.text.strip_edges() == "":
					continue
				var tw := lb.get_theme_font("font").get_multiline_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.get_theme_font_size("font_size")).x
				r.size.x = minf(r.size.x, tw + 8.0)
			hud.append(r)
	if _clock != null and _clock.is_visible_in_tree():
		hud.append(_clock.get_global_rect())
	_names.layout(_camera, obstacle, owner, hud)
	if _camera != null:
		var bubbles: Array = []
		for w in _warga:
			if w.bubble != null:
				bubbles.append(w.bubble)
		NameLabels.fade_bubbles(_camera, bubbles, hud)


## Titik 3D di atas nama NPC/warga (tempat tombol Bicara melayang).
func _npc_anchor(npc_id: String) -> Vector3:
	if npc_id.begins_with(Warga.TALK_PREFIX):
		var wid := npc_id.substr(Warga.TALK_PREFIX.length())
		for w in _warga:
			if w.id == wid:
				return Vector3(w.pos.x, 1.75, w.pos.y)  # di atas nama + peran, tidak menutupinya
	var n: Dictionary = Maps.NPCS.get(npc_id, {})
	if n.is_empty():
		return Vector3(_pos.x, 1.9, _pos.y)
	return Vector3(float(n.pos.x) + 0.5, 1.75, float(n.pos.y) + 0.5)


## Menaruh tombol konteks di layar tepat di atas titik 3D; di luar layar/di belakang kamera
## tombol ditahan di dalam layar (atau di posisi cadangan bawah bila titiknya di belakang).
func _place_talk_button(anchor: Vector3) -> void:
	var vs := get_viewport().get_visible_rect().size
	var sz := _talk_button.size
	if _camera == null or _camera.is_position_behind(anchor):
		_talk_button.position = Vector2(vs.x * 0.5 - sz.x * 0.5, vs.y * 0.55)
		return
	var sp := _camera.unproject_position(anchor)
	var x := clampf(sp.x - sz.x * 0.5, 8.0, vs.x - sz.x - 8.0)
	# Di bawah HUD kiri atas dan tombol Menu kanan atas; di tengah (layar mendatar) cukup di bawah jam.
	var top := 190.0 if (x < 240.0 or x + sz.x > vs.x - 260.0) else 70.0
	var y := clampf(sp.y - sz.y - 4.0, top, vs.y * 0.7)
	_talk_button.position = Vector2(x, y)


func _talk() -> void:
	if _locked:
		return
	if _fight != null and _fight.busy():
		_set_status("Selesaikan pertarungan dulu")
		return
	var chest := _chest_in_range()
	if chest != "" and not Session.offline:
		_open_chest(chest)
		return
	if _house_for_sale_near():
		await _buy_house()
		return
	if _story != null and not Session.offline and _story.stone_near():
		await _story.smash_stone()
		return
	var secret: String = _life.secret_near() if _life != null else ""
	if secret != "" and not Session.offline:
		await _life.inspect(secret)
		return
	if _store_near():
		await open_ekonomi(EkonomiScreen.MODE_PETI)
		return
	if _bed_near():
		_set_status("Kamu berbaring di ranjangmu...")
		var rb: Dictionary = await Api.rest()
		if rb.ok:
			Session.merge_server_player(rb.data)
			_refresh_hud()
			_show_toast("Segar kembali!")
			_set_status("Tidur nyenyak di rumah sendiri: HP dan energi pulih penuh.")
		else:
			_set_status(str(rb.error))
		return
	var npc := _npc_in_range()
	if npc == "":
		return
	var keeper := _keeper_of(npc)
	if keeper != null:
		await _visit_keeper(keeper)
		return
	_locked = true
	Session.talk_npc = npc
	Session.talk_counts[npc] = int(Session.talk_counts.get(npc, 0)) + 1
	await _flush_save()  # versi pemain harus sinkron sebelum hadiah diambil
	get_tree().change_scene_to_file(DIALOG_SCENE)


## Pintu interaktif (roadmap no. 125): di dalam ruangan daun pintu keluar membuka sendiri saat pemain
## mendekat; di desa, pintu bangunan yang bisa dimasuki menampilkan nama tujuannya (atau "Dijual" /
## "Terkunci") saat pemain mendekat.
func _make_doors(map_id: String) -> void:
	_doors = []
	for ex: Dictionary in Maps.EXITS.get(map_id, []):
		var to := str(ex.to)
		var p: Vector2i = ex.pos
		if Maps.is_interior(map_id):
			var hinge := Node3D.new()
			hinge.name = "Pintu"
			hinge.position = Vector3(p.x + 0.08, 0.0, p.y + 0.55)
			_npc_root.add_child(hinge)
			var leaf := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.84, 0.9, 0.07)  # rendah: tidak menutupi pemain dari kamera
			leaf.mesh = bm
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color("6b4426")
			leaf.material_override = lm
			leaf.position = Vector3(0.42, 0.45, 0.0)
			hinge.add_child(leaf)
			_doors.append({"hinge": hinge, "at": Vector2(p.x + 0.5, p.y + 0.5), "open": 0.0})
		elif Maps.is_interior(to):
			var tag := Label3D.new()
			tag.name = "PapanPintu"
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.pixel_size = 0.005
			tag.font_size = 38
			tag.outline_size = 10
			tag.modulate = Color("bff0ff")
			tag.position = Vector3(p.x + 0.5, 1.9, p.y + 1.2)
			tag.visible = false
			_npc_root.add_child(tag)
			_doors.append({"tag": tag, "to": to, "at": Vector2(p.x + 0.5, p.y + 1.0)})


func _update_doors(delta: float) -> void:
	for d: Dictionary in _doors:
		var near: bool = _pos.distance_to(d.at) < DOOR_NEAR
		if d.has("hinge"):
			d.open = move_toward(float(d.open), 1.0 if near else 0.0, delta * 3.0)
			(d.hinge as Node3D).rotation.y = -1.6 * smoothstep(0.0, 1.0, float(d.open))
		else:
			var tag := d.tag as Label3D
			tag.visible = near
			if near:
				var to := str(d.to)
				var nama := str(Maps.NAMES.get(to, to))
				if to == Maps.RUMAH_PEMAIN and not bool(Session.player.state.get("house", false)):
					tag.text = "Rumah dijual: %d emas" % Maps.HARGA_RUMAH
				else:
					tag.text = "Masuk: " + nama


## Dekat ranjang di rumah sendiri (roadmap no. 123, 127)?
func _bed_near() -> bool:
	return _map_id == Maps.RUMAH_PEMAIN and _pos.distance_to(BED_AT) < 1.6


## Dekat lemari (peti simpan) di rumah sendiri?
func _store_near() -> bool:
	return _map_id == Maps.RUMAH_PEMAIN and _pos.distance_to(STORE_AT) < 1.6


## Buka layar ekonomi: posisi disimpan dulu (server memeriksa pemain ada di desa / di rumahnya).
func open_ekonomi(mode: String, keeper := "") -> void:
	if Session.offline or _ekonomi == null:
		return
	_locked = true
	_set_moving(false)
	await _flush_save()
	if keeper != "":
		_ekonomi.keeper = keeper
	_ekonomi.open(mode)


## Pemain berdiri di depan rumah yang dijual (belum punya rumah)?
func _house_for_sale_near() -> bool:
	if _map_id != Maps.DEFAULT_MAP or bool(Session.player.state.get("house", false)):
		return false
	var front := Vector2(Maps.RUMAH_PEMAIN_PINTU.x + 0.5, Maps.RUMAH_PEMAIN_PINTU.y + 1.5)
	return _pos.distance_to(front) < HOUSE_RANGE


## Membeli rumah (roadmap no. 127): server memeriksa emas dan tempat.
func _buy_house() -> void:
	if Session.offline:
		return
	await _flush_save()  # posisi tersimpan dulu: server memeriksa pemain ada di Desa Awal
	var res: Dictionary = await Api.house_buy()
	if res.ok:
		Session.merge_server_player(res.data)
		_refresh_hud()
		_show_toast("Rumah ini milikmu!")
		_set_status("Selamat! Masuk lewat pintunya. Di dalam ada ranjang untuk beristirahat.")
		HeroFx.burst(self, Vector3(Maps.RUMAH_PEMAIN_PINTU.x + 0.5, 1.0, Maps.RUMAH_PEMAIN_PINTU.y + 1.0), Color("ffd24a"), 30, 3.5)
	else:
		_set_status(str(res.error))


## Penjaga toko dari id lawan bicara "warga:<id>", atau null bila bukan penjaga toko.
func _keeper_of(npc_id: String) -> Warga:
	if not npc_id.begins_with(Warga.TALK_PREFIX):
		return null
	var wid := npc_id.substr(Warga.TALK_PREFIX.length())
	for w in _warga:
		if w.id == wid and w.toko != "":
			return w
	return null


## Masuk ke toko lewat penjaganya: toko ramuan / rumah makan membuka layar toko, rumah sehat memulihkan pemain.
func _visit_keeper(w: Warga) -> void:
	if w.toko == "tempa":  # pandai besi: layar tempa (no. 145)
		_locked = true
		_set_moving(false)
		_tempa.keeper = w.nama
		_tempa.open()
		return
	if w.toko == "bank":  # bank desa (no. 181): menabung / mengambil emas, riwayat transaksi
		await open_ekonomi(EkonomiScreen.MODE_BANK, w.nama)
		return
	if w.toko == "inap":  # penginapan (no. 115): menginap semalam, pulih penuh
		_set_status("%s: Kamarmu sudah siap. Selamat beristirahat!" % w.nama)
		var ri: Dictionary = await Api.rest()
		if ri.ok:
			Session.merge_server_player(ri.data)
			_refresh_hud()
			_set_status("Kamu menginap di penginapan: HP dan energi pulih penuh.")
		else:
			_set_status("%s: %s" % [w.nama, str(ri.error)])
		return
	if w.toko == "rawat":
		_set_status("%s: Duduklah, biar kurawat lukamu." % w.nama)
		var res: Dictionary = await Api.rest()
		if res.ok:
			Session.merge_server_player(res.data)
			_refresh_hud()
			_set_status("%s merawatmu: HP dan energi pulih penuh." % w.nama)
		else:
			_set_status("%s: %s" % [w.nama, str(res.error)])
		return
	Session.shop_keeper = w.nama
	if w.toko == "rekrut_pahlawan" or w.toko == "rekrut_prajurit":
		Session.recruit_kind = "pahlawan" if w.toko == "rekrut_pahlawan" else "prajurit"
		await _open_screen(RECRUIT_SCENE)
		return
	if w.toko == "latih_pahlawan" or w.toko == "latih_prajurit":
		Session.train_kind = "pahlawan" if w.toko == "latih_pahlawan" else "prajurit"
		await _open_screen(TRAIN_SCENE)
		return
	Session.shop_id = w.toko
	await _open_screen(SHOP_SCENE)


## Pindah ke layar lain (toko, tas) setelah menyimpan posisi: versi pemain harus
## sinkron dengan server sebelum bertransaksi.
func _open_screen(scene: String) -> void:
	if _locked:
		return
	_locked = true
	await _flush_save()
	get_tree().change_scene_to_file(scene)


func _flush_save() -> void:
	_save_timer.stop()
	while _saving:
		await get_tree().process_frame
	if _unsaved:
		await _save()


# --- simpan ke server ---

func _save() -> void:
	if Session.offline:
		return
	if _saving:
		_save_timer.start(SAVE_DELAY)
		return
	_saving = true
	_unsaved = false
	_set_status("Menyimpan...")

	var res: Dictionary = await Api.save(Session.player.version, Session.player.state)
	if not res.ok and res.status == 409:
		# Versi di server berbeda (mis. main dari perangkat lain): ikuti versi server,
		# lalu simpan ulang keadaan lokal.
		var me: Dictionary = await Api.get_me()
		if me.ok:
			Session.player.version = int(me.data.version)
			res = await Api.save(Session.player.version, Session.player.state)

	_saving = false
	if res.ok:
		Session.player.version = int(res.data.version)
		_set_status("Tersimpan")
		if _unsaved:  # ada gerakan baru saat menyimpan
			_save_timer.start(SAVE_DELAY)
	elif res.status == 426:
		# Aplikasi terlalu lama untuk server: percuma mengulang, pemain harus update.
		_unsaved = true
		_set_status(str(res.error))
	else:
		_unsaved = true
		_set_status("Gagal menyimpan: %s (coba lagi...)" % res.error)
		_save_timer.start(RETRY_DELAY)


# --- tampilan ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_bars = HudBars.new()
	_bars.position = Vector2(20, 10)
	layer.add_child(_bars)

	_hutan_hud = HutanHud.new()
	_hutan_hud.position = Vector2(290, 58)
	_hutan_hud.visible = false
	layer.add_child(_hutan_hud)

	_radar = RadarMusuh.new()
	# Layar mendatar (v0.68.2): radar di kolom kiri di bawah tulisan status, tidak menabrak papan kanan dan tombol aksi.
	_radar.position = Vector2(20, 296)
	_radar.visible = false
	layer.add_child(_radar)

	_status = Label.new()
	_status.position = Vector2(20, 240)
	_status.size = Vector2(420, 60)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_status.add_theme_constant_override("outline_size", 6)
	layer.add_child(_status)

	_clock = ClockBadge.new()
	_clock.position = Vector2(300.0, 14.0)
	layer.add_child(_clock)

	_net_label = Label.new()
	_net_label.position = Vector2(120, 196)
	_net_label.size = Vector2(480, 40)
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_label.add_theme_font_size_override("font_size", 24)
	_net_label.add_theme_color_override("font_color", Color("ff9c8c"))
	_net_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_net_label.add_theme_constant_override("outline_size", 8)
	_net_label.text = "Koneksi terputus — mencoba lagi..."
	_net_label.visible = false
	layer.add_child(_net_label)

	_toast = Label.new()
	_toast.position = Vector2(0, 260)
	_toast.size = Vector2(720, 80)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 44)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 12)
	_toast.modulate.a = 0.0
	layer.add_child(_toast)

	_joy = Joystick.new()
	_joy.position = Vector2(20, 880)
	_joy.size = Vector2(400, 380)
	layer.add_child(_joy)

	_talk_button = _add_button(layer, "Bicara", 0, _talk)
	_talk_button.position = Vector2(270, 500)
	_talk_button.size = Vector2(180, 72)
	_btn_tangan = _add_action(layer, ActionButton.Icon.TANGAN, "Tangan", Vector2(612, 1136), 72.0, Color("ffb347"))
	_btn_kaki = _add_action(layer, ActionButton.Icon.KAKI, "Kaki", Vector2(492, 1212), 52.0, Color("7fd1ff"))
	_btn_perisai = _add_action(layer, ActionButton.Icon.PERISAI, "Perisai", Vector2(478, 1090), 52.0, Color("8fe08f"))
	_btn_boost = _add_action(layer, ActionButton.Icon.BOOST, "Boost", Vector2(576, 986), 52.0, Color("ffe14a"))
	_btn_lompat = _add_action(layer, ActionButton.Icon.LOMPAT, "Lompat", Vector2(672, 1030), 44.0, Color("e8b4ff"))
	_btn_tangan.pressed.connect(_do_tangan)
	_btn_kaki.pressed.connect(_do_kaki)
	_btn_perisai.pressed.connect(_on_perisai_pressed)
	_btn_lompat.pressed.connect(_do_lompat)
	_btn_boost.pressed.connect(_do_boost)
	_flush_timer = Timer.new()
	_flush_timer.one_shot = true
	_flush_timer.timeout.connect(_flush_breaks)
	add_child(_flush_timer)
	_update_talk_button()

	var menu_btn := MenuBubble.new()
	menu_btn.position = Vector2(574, 12)
	menu_btn.size = Vector2(134, 60)
	menu_btn.pressed.connect(_toggle_menu)
	layer.add_child(menu_btn)
	_buttons.append(menu_btn)

	_menu = GameMenu.new()
	add_child(_menu)
	_menu.resumed.connect(_close_menu)
	_menu.go_home.connect(_leave_to_home.bind(false))
	_menu.logout.connect(_leave_to_home.bind(true))
	_menu.quit_game.connect(_quit_game)
	_menu.settings_changed.connect(_apply_quality)
	_menu.profile_requested.connect(_open_profile)
	_menu.inventory_requested.connect(_open_from_menu.bind(INVENTORY_SCENE))
	_menu.atribut_requested.connect(_open_from_menu.bind(ATRIBUT_SCENE))
	_profile = ProfileScreen.new()
	add_child(_profile)
	_profile.closed.connect(_close_profile)
	_tempa = TempaScreen.new()
	add_child(_tempa)
	_tempa.closed.connect(func() -> void:
		_tempa.close()
		_locked = false
		_refresh_hud())
	_ekonomi = EkonomiScreen.new()
	add_child(_ekonomi)
	_ekonomi.closed.connect(func() -> void:
		_ekonomi.close()
		_locked = false
		_refresh_hud())
	_menu.trade_requested.connect(func() -> void:
		_menu.close()
		open_ekonomi(EkonomiScreen.MODE_DAGANG))
	_jurnal = JurnalScreen.new()
	add_child(_jurnal)
	_jurnal.closed.connect(func() -> void:
		_jurnal.close()
		_locked = false)
	_menu.journal_requested.connect(func(t: int) -> void:
		_menu.close()
		_locked = true
		_set_moving(false)
		if not Session.offline:
			await _flush_save()  # peta memakai posisi terbaru
		_jurnal.open(t))
	if not Session.achievement_unlocked.is_connected(_on_achievement):
		Session.achievement_unlocked.connect(_on_achievement)
	_profile.hero_changed.connect(_make_player)
	for pair: Array in [[_bars, "tl"], [_status, "tl"], [_hutan_hud, "tc"], [_net_label, "tc"], [_radar, "tl"], [menu_btn, "tr"], [_joy, "bl"]]:
		register_hud(pair[0], pair[1])
	for b: Control in _act_buttons:
		register_hud(b, "br")


## Daftarkan elemen HUD supaya ikut tata letak layar (lihat _hud_items).
func register_hud(c: Control, kind: String) -> void:
	if c == null:
		return
	_hud_items.append([c, c.position, kind])


## Jarak aman di atas (poni/kamera depan HP), dalam satuan layar permainan.
func _safe_top() -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	return float(safe.position.y) * get_viewport().get_visible_rect().size.y / float(win.y)


## Tata letak HUD (roadmap no. 217-218): layar lebih tinggi/lebar dari 720x1280 tidak lagi diberi pita
## hitam; elemen kanan menempel ke kanan, kontrol bawah menempel ke bawah dan ikut ukuran kontrol, dan
## mode tangan kiri menukar sisi joystick dan tombol aksi.
func _layout_hud() -> void:
	var vs := get_viewport().get_visible_rect().size
	var dx := vs.x - BASE_W
	var dy := vs.y - BASE_H
	var top := _safe_top()
	var s := Session.ui_scale()
	for it: Array in _hud_items:
		var c := it[0] as Control
		if c == null or not is_instance_valid(c):
			continue
		var p: Vector2 = it[1]
		match str(it[2]):
			"tl":
				c.position = p + Vector2(0, top)
			"tr":
				c.position = p + Vector2(dx, top)
			"tc":
				c.position = p + Vector2(dx * 0.5, top)
			_:
				var right := str(it[2]) == "br"
				var corner := Vector2(BASE_W if right else 0.0, BASE_H)
				var center := p + c.size * 0.5
				center = corner + (center - corner) * s
				center += Vector2(dx if right else 0.0, dy)
				if Session.left_hand:
					center.x = vs.x - center.x
				c.pivot_offset = c.size * 0.5
				c.scale = Vector2.ONE * s
				c.position = center - c.size * 0.5
	if _clock != null:
		_clock.center_x = 440.0 + dx * 0.5
		_clock.position.y = 14.0 + top
		_clock.position.x = _clock.center_x - _clock.size.x / 2.0
	if _toast != null:
		_toast.size.x = vs.x
	if _life != null and _life.has_method("layout"):
		_life.layout(dx, top)


func _add_button(layer: CanvasLayer, text: String, slot: int, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(548, 940 + slot * 100)
	b.size = Vector2(152, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(callback)
	layer.add_child(b)
	_buttons.append(b)
	return b


func _add_action(layer: CanvasLayer, icon: int, title: String, center: Vector2, radius: float, tint: Color) -> ActionButton:
	var b := ActionButton.new()
	b.icon = icon
	b.title = title
	b.tint = tint
	b.size = Vector2.ONE * radius * 2.0
	b.position = center - b.size / 2.0
	layer.add_child(b)
	_act_buttons.append(b)
	return b


## Ransel dibuka dari Menu (toko hanya bisa dimasuki lewat penjaga di rumah toko) (menu menutup dulu, lalu pindah layar).
func _open_from_menu(scene: String) -> void:
	_menu.close()
	_locked = false
	_open_screen(scene)


## Ringkasan pakaian + perlengkapan; model pahlawan dipakaikan ulang bila berubah.
func _dress_signature() -> String:
	var st: Dictionary = Session.player.state
	return "%s|%s" % [st.get("outfit", 0), str(st.get("equipment", {}))]


func _refresh_hud() -> void:
	_refresh_hutan()
	if _player != null and _dress_signature() != _dress_sig:
		_dress_sig = _dress_signature()
		Models.dress_current(_player)
	var st: Dictionary = Session.player.state
	if _bars != null:
		_bars.set_identity(str(Session.player.name), int(st.gold), Session.item_count("berlian"))
		_bars.set_values(int(st.level), int(st.xp), 20 * int(st.level), int(st.hp), int(st.max_hp))
		_bars.set_energy(Session.energy(), Session.MAX_ENERGY)


## Wilayah ujian: papan misi (musuh X/25|75|100, bos, panah arah), palang gerbang, dan bos di dekat singgasana.
func _refresh_hutan() -> void:
	if _hutan_hud == null:
		return
	var on := Maps.TRIALS.has(_map_id)
	_hutan_hud.visible = on
	var wave := Session.trial_wave(_map_id) if on else 0
	var kills := Session.trial_kills(_map_id) if on else 0
	var need := Session.stage_need(wave)
	if _terrain != null:
		var lock := _terrain.get_node_or_null("KunciGerbang")
		if lock != null:
			lock.visible = on and wave < 3
	var boss_up := on and kills >= need and wave < 3
	_update_hutan_boss(boss_up, wave + 1)
	if not on:
		return
	var t: Dictionary = Maps.TRIALS[_map_id]
	_hutan_hud.update_view(kills, wave, _pos, _cam_yaw, Session.hutan_started() or _map_id != Maps.HUTAN, _map_id)
	var sig := wave * 1000 + kills
	if _hutan_sig >= 0 and sig != _hutan_sig:
		var old_wave := _hutan_sig / 1000
		if wave >= 3 and old_wave < 3:
			_show_toast("Jalan ke %s terbuka!" % Maps.NAMES.get(str(t.next), ""))
		elif wave > old_wave:
			_show_toast(Maps.boss_label(_map_id, wave) + " kalah!")
			_set_status("Tahap %d: kalahkan %d %s" % [wave + 1, need, str(t.foe).to_lower()])
			for _i in int(_roam_cfg.get("n", 0)):
				respawn_roamer()
		elif kills >= need and _hutan_sig % 1000 < need:
			_show_toast(Maps.boss_label(_map_id, wave + 1) + " muncul!")
		elif kills > _hutan_sig % 1000:
			_set_status("%s %d/%d" % [t.foe, kills, need])
	_hutan_sig = sig


## Bos wilayah berkeliaran di sekitar singgasana seperti musuh biasa (pertarungan langsung di dunia, hanya lebih kuat).
func _update_hutan_boss(show: bool, level: int) -> void:
	var cur: Roamer = _hutan_boss
	if cur != null and (cur.dying or cur.node == null or not is_instance_valid(cur.node)):
		cur = null
		_hutan_boss = null
	if not show or not Maps.TRIALS.has(_map_id):
		if cur != null and not cur.fight:
			_remove_roamer(cur)
		_hutan_boss = null
		return
	var t: Dictionary = Maps.TRIALS[_map_id]
	var want := "%s%d" % [t.prefix, level]
	if cur != null and cur.id == want:
		return
	if cur != null and not cur.fight:
		_remove_roamer(cur)
	if _terrain == null or _npc_root == null:
		return
	var kind := {"id": want, "name": Maps.boss_label(_map_id, level), "lv": 1}
	var bp: Vector2i = t.boss
	var at := Vector2(float(bp.x) + 0.5, float(bp.y) - 1.5)
	var r := _make_roamer(kind, _map_id, at, 7000 + level)
	r.chase_speed = 2.0
	_roamers.append(r)
	_hutan_boss = r


func _remove_roamer(r: Roamer) -> void:
	_roamers.erase(r)
	if r.node != null and is_instance_valid(r.node):
		r.node.queue_free()


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


## Tulisan besar di tengah layar. Beberapa tulisan berturut-turut tampil bergantian (roadmap no. 216),
## tidak saling menimpa.
func _show_toast(text: String) -> void:
	if _toast_tw != null and _toast_tw.is_valid() and _toast_tw.is_running():
		if _toast_queue.size() < 4 and not _toast_queue.has(text) and _toast.text != text:
			_toast_queue.append(text)
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.2)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.8)
	_toast_tw.tween_callback(func() -> void:
		if not _toast_queue.is_empty():
			_show_toast(str(_toast_queue.pop_front())))


## Pemberitahuan: tulisan besar + tersimpan di Menu > Jurnal > Kabar.
func notify(text: String, kind := "info", toast := "") -> void:
	Session.notify(text, kind)
	if toast != "":
		_show_toast(toast)


# --- menu dalam game ---

func _toggle_menu() -> void:
	if _menu == null:
		return
	if _profile.is_open:
		_close_profile()
	elif _menu.is_open:
		_menu.back()
	elif not _locked:
		_locked = true
		_menu.open()


## Model pemain di dunia mengikuti pahlawan yang dipilih (dibuat ulang saat pilihan berganti).
func _make_player() -> void:
	var old := _player
	_player = Models.create(str(Heroes.current().id))
	Models.dress_current(_player)  # pakaian + perlengkapan terlihat (roadmap no. 14-18)
	_dress_sig = _dress_signature()
	add_child(_player)
	_shadow_disc = _add_shadow(_player, 0.3)
	if _aura_guard == null:
		_aura_guard = HeroFx.aura(Color(0.35, 0.65, 1.0, 0.28))
		add_child(_aura_guard)
		_aura_boost = HeroFx.aura(Color(1.0, 0.65, 0.15, 0.22), 0.8)
		add_child(_aura_boost)
	if old != null:
		old.queue_free()
		_apply_transform()


func _open_profile() -> void:
	_menu.close()
	_profile.open()


func _close_profile() -> void:
	_profile.close()
	_locked = false


func _close_menu() -> void:
	_menu.close()
	_locked = false


## Simpan posisi dulu, lalu kembali ke Beranda (dan bila `forget`, keluar dari akun di HP ini).
func _leave_to_home(forget: bool) -> void:
	_menu.close()
	_locked = true
	await _flush_save()
	if forget and not Session.offline:
		await Api.logout()  # gagal terhubung pun tidak masalah: token lokal tetap dihapus
		Api.token = ""
		Session.saved_name = ""
		Session.player = {}
		Session.save_config()
	get_tree().change_scene_to_file(LOGIN_SCENE)


func _quit_game() -> void:
	_menu.close()
	_locked = true
	await _flush_save()
	get_tree().quit()


## Kualitas grafis dari pengaturan: bayangan matahari dan tepi halus (MSAA).
func _apply_quality() -> void:
	var q: int = Session.quality
	_sun.shadow_enabled = q >= 1
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q == 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = maxf(float(Perf.pick(Perf.SHADOW_DIST)), 1.0)
	RenderingServer.directional_shadow_atlas_set_size(1024 if q == 1 else 2048, true)
	get_viewport().msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	# Resolusi 3D lebih rendah di HP beresolusi tinggi (UI tetap tajam): jauh lebih ringan bagi GPU.
	get_viewport().scaling_3d_scale = float(Perf.pick(Perf.SCALE_3D))
	if _camera != null:
		_camera.far = float(Perf.pick(Perf.CAMERA_FAR))
