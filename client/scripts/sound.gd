extends Node
## Suara game (autoload "Sound"): musik latar desa dan suara bicara NPC. Dua bus terpisah ("Musik" dan
## "NPC") supaya pengaturan di menu (nyala/mati dan volume) berlaku tanpa menyentuh bagian lain.
## Berkas suara dibuat dengan tools/gen_suara.py (sintesis sendiri, bebas lisensi).

const MUSIC_PATH := "res://assets/audio/musik_desa.ogg"
const VOICE_PATHS := [
	"res://assets/audio/npc_0.ogg", "res://assets/audio/npc_1.ogg", "res://assets/audio/npc_2.ogg",
	"res://assets/audio/npc_3.ogg", "res://assets/audio/npc_4.ogg", "res://assets/audio/npc_5.ogg",
]
const BUS_MUSIC := "Musik"
const BUS_NPC := "NPC"
const MUSIC_GAIN := 0.8      # musik selalu sedikit lebih pelan dari pengaturan agar tidak menutupi suara lain
const BLIP_GAP_S := 0.095    # jeda antar "kata" saat NPC berbicara
const MAX_BLIPS := 14

var _music: AudioStreamPlayer
var _voices: Array[AudioStream] = []
var _pool: Array[AudioStreamPlayer] = []
var _speak_id := 0


func _ready() -> void:
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_NPC)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	if ResourceLoader.exists(MUSIC_PATH):
		var stream := load(MUSIC_PATH) as AudioStream
		if stream != null:
			var loop_stream := stream.duplicate() as AudioStream
			if "loop" in loop_stream:
				loop_stream.set("loop", true)
			_music.stream = loop_stream
	add_child(_music)
	for path: String in VOICE_PATHS:
		if ResourceLoader.exists(path):
			var v := load(path) as AudioStream
			if v != null:
				_voices.append(v)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_NPC
		add_child(p)
		_pool.append(p)
	apply_settings()


static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


## Terapkan Session.snd_* / vol_* ke bus dan pemutar musik. Dipanggil dari menu Pengaturan.
func apply_settings() -> void:
	_set_bus(BUS_MUSIC, Session.vol_music * MUSIC_GAIN, not Session.snd_music)
	_set_bus(BUS_NPC, Session.vol_npc, not Session.snd_npc)
	if _music == null or _music.stream == null:
		return
	if Session.snd_music and Session.vol_music > 0.0:
		if not _music.playing:
			_music.play()
	elif _music.playing:
		_music.stop()


static func _set_bus(bus_name: String, linear: float, mute: bool) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, mute)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))


## NPC "berbicara": deretan bunyi pendek, banyaknya mengikuti panjang kalimat. `voice` (>= 0)
## memilih warna suara tetap untuk satu NPC (mis. dari hash namanya); -1 = acak.
func npc_say(text: String, voice := -1) -> void:
	if not Session.snd_npc or Session.vol_npc <= 0.0 or _voices.is_empty():
		return
	_speak_id += 1
	var my_id := _speak_id
	var count := clampi(int(float(text.length()) / 4.0), 3, MAX_BLIPS)
	var base := voice if voice >= 0 else randi()
	for i in count:
		if my_id != _speak_id or not is_inside_tree():
			return  # kalimat baru dimulai: yang lama berhenti
		var player := _pool[i % _pool.size()]
		player.stream = _voices[(absi(base) + (randi() % 2)) % _voices.size()]
		player.pitch_scale = randf_range(0.88, 1.18) * (0.9 + 0.025 * float(absi(base) % 9))
		player.play()
		await get_tree().create_timer(BLIP_GAP_S).timeout


## Hentikan suara bicara yang sedang berjalan.
func npc_stop() -> void:
	_speak_id += 1
