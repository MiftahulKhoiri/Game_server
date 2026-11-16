extends Node
## Audio Pulau Ilmu yang DIBUAT DENGAN KODE (tanpa berkas suara: paket tetap kecil, tanpa masalah lisensi):
## klik tombol, jawaban benar, jawaban belum tepat (nada rendah lembut), bintang/hadiah, dan musik latar
## petualangan pendek yang berulang. Musik dan efek suara bisa dimatikan terpisah.
##
## Pilihan lagu (Pengaturan > Lagu): lagu ciptaan sendiri + lagu anak klasik/rakyat yang sudah domain publik
## (instrumental, tanpa lirik). "acak" memutar semua lagu bergantian. Lagu dibangun di utas latar
## (WorkerThreadPool) supaya permainan tidak tersendat; lagu berikutnya disiapkan selagi lagu sekarang diputar.

## [id, nama, ketukan per menit, ketukan per nada bas, nada [midi, ketukan] (-1 = diam), nada bas midi]
const SONGS := [
	["petualang", "Petualang Riang", 143, 2, [], []],
	["pulau", "Pulau Ceria", 132, 2,
		[[67, 1], [71, 1], [74, 1], [71, 1], [72, 1], [76, 1], [74, 2], [71, 1], [72, 1], [74, 1], [76, 1], [74, 1], [72, 1], [71, 2],
		[69, 1], [71, 1], [72, 1], [69, 1], [67, 1], [71, 1], [74, 2], [72, 1], [71, 1], [69, 1], [71, 1], [67, 4]],
		[43, 43, 48, 43, 48, 48, 43, 43, 45, 45, 43, 43, 48, 50, 43, 43]],
	["bintang", "Bintang Kerlip (lagu klasik)", 112, 2,
		[[72, 1], [72, 1], [79, 1], [79, 1], [81, 1], [81, 1], [79, 2], [77, 1], [77, 1], [76, 1], [76, 1], [74, 1], [74, 1], [72, 2],
		[79, 1], [79, 1], [77, 1], [77, 1], [76, 1], [76, 1], [74, 2], [79, 1], [79, 1], [77, 1], [77, 1], [76, 1], [76, 1], [74, 2],
		[72, 1], [72, 1], [79, 1], [79, 1], [81, 1], [81, 1], [79, 2], [77, 1], [77, 1], [76, 1], [76, 1], [74, 1], [74, 1], [72, 2]],
		[48, 48, 53, 48, 53, 48, 55, 48, 48, 53, 48, 55, 48, 53, 48, 55, 48, 48, 53, 48, 53, 48, 55, 48]],
	["domba", "Domba Kecil (lagu rakyat)", 126, 2,
		[[76, 1], [74, 1], [72, 1], [74, 1], [76, 1], [76, 1], [76, 2], [74, 1], [74, 1], [74, 2], [76, 1], [79, 1], [79, 2],
		[76, 1], [74, 1], [72, 1], [74, 1], [76, 1], [76, 1], [76, 1], [76, 1], [74, 1], [74, 1], [76, 1], [74, 1], [72, 4]],
		[48, 48, 48, 48, 43, 43, 48, 48, 48, 48, 48, 48, 43, 43, 48, 48]],
	["bangun", "Bangun Pagi (lagu rakyat)", 120, 2,
		[[72, 1], [74, 1], [76, 1], [72, 1], [72, 1], [74, 1], [76, 1], [72, 1], [76, 1], [77, 1], [79, 2], [76, 1], [77, 1], [79, 2],
		[79, 0.5], [81, 0.5], [79, 0.5], [77, 0.5], [76, 1], [72, 1], [79, 0.5], [81, 0.5], [79, 0.5], [77, 0.5], [76, 1], [72, 1],
		[72, 1], [67, 1], [72, 2], [72, 1], [67, 1], [72, 2]],
		[48, 55, 48, 55, 48, 55, 48, 55, 48, 55, 48, 55, 48, 55, 48, 55]],
	["gembira", "Lagu Gembira (Beethoven)", 112, 2,
		[[76, 1], [76, 1], [77, 1], [79, 1], [79, 1], [77, 1], [76, 1], [74, 1], [72, 1], [72, 1], [74, 1], [76, 1], [76, 1.5], [74, 0.5], [74, 2],
		[76, 1], [76, 1], [77, 1], [79, 1], [79, 1], [77, 1], [76, 1], [74, 1], [72, 1], [72, 1], [74, 1], [76, 1], [74, 1.5], [72, 0.5], [72, 2]],
		[48, 48, 43, 43, 48, 48, 43, 43, 48, 48, 43, 43, 48, 48, 43, 48]],
	["ombak", "Ombak Tenang", 96, 3,
		[[65, 2], [69, 1], [72, 2], [69, 1], [70, 2], [67, 1], [65, 3], [67, 2], [69, 1], [70, 2], [72, 1], [69, 3], [-1, 3],
		[65, 2], [69, 1], [72, 2], [77, 1], [76, 2], [74, 1], [72, 3], [70, 2], [69, 1], [67, 2], [69, 1], [65, 6]],
		[41, 46, 41, 48, 41, 48, 46, 41]],
]

const RATE := 22050
const PAD := 256  # sampel hening di ujung setiap suara

var music_on := true
var sfx_on := true
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next := 0
var _rain: AudioStreamPlayer
var _raining := false
var _amb_timer: Timer
var song := "acak"  # pilihan di Pengaturan: id lagu atau "acak"
var current := ""  # lagu yang sedang diputar
var _built: Dictionary = {}  # id -> AudioStreamWAV
var _tasks: Dictionary = {}  # id -> id tugas WorkerThreadPool
var _results: Dictionary = {}  # hasil dari utas latar (dijaga _lock)
var _lock := Mutex.new()
var _want := ""
var _upnext := ""  # lagu acak berikutnya (sudah disiapkan)  # lagu yang ingin diputar begitu selesai dibangun
var _rng := RandomNumberGenerator.new()
var sync_build := false  # uji headless: bangun langsung (tanpa utas)


func _ready() -> void:
	_rng.randomize()
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_sfx.append(p)


func apply(music: bool, sfx: bool) -> void:
	music_on = music
	sfx_on = sfx
	if music_on:
		if not _music.playing and _want == "":
			_play(_first())
	else:
		_want = ""
		_music.stop()


## [[id, nama], ...] untuk Pengaturan.
func songs() -> Array:
	return SONGS.map(func(sg): return [sg[0], sg[1]])


static func _song_def(id: String) -> Array:
	for sg in SONGS:
		if str(sg[0]) == id:
			return sg
	return []


func set_song(id: String) -> void:
	if id != "acak" and _song_def(id).is_empty():
		id = "acak"
	if id == song:
		return
	song = id
	if music_on and (_music.playing or _want != ""):
		_music.stop()
		_play(_first())


func _first() -> String:
	if song != "acak":
		return song
	return current if current != "" else str(SONGS[_rng.randi_range(0, SONGS.size() - 1)][0])


func _next_song() -> String:
	if song != "acak":
		return song
	if _upnext != "" and _upnext != current:
		return _upnext
	var i := 0
	for k in SONGS.size():
		if str(SONGS[k][0]) == current:
			i = k
	return str(SONGS[(i + 1 + _rng.randi_range(0, SONGS.size() - 2)) % SONGS.size()][0])


func _play(id: String) -> void:
	var st := _stream(id)
	if st == null:
		_want = id  # diputar di _process begitu selesai dibangun
		return
	_want = ""
	current = id
	_music.stream = st
	_music.play()
	if song == "acak":
		_upnext = ""
		_upnext = _next_song()
		_stream(_upnext)  # siapkan lagu berikutnya selagi ini diputar


## Lagu yang sudah jadi, atau null (lalu mulai dibangun di utas latar).
func _stream(id: String) -> AudioStreamWAV:
	if _built.has(id):
		return _built[id]
	_lock.lock()
	var done = _results.get(id)
	_lock.unlock()
	if done != null:
		_built[id] = done
		_tasks.erase(id)
		return done
	if sync_build or OS.get_thread_caller_id() != OS.get_main_thread_id():
		_built[id] = _make_song(id)
		return _built[id]
	if not _tasks.has(id):
		_tasks[id] = WorkerThreadPool.add_task(_bg_build.bind(id), false, "lagu " + id)
	return null


func _bg_build(id: String) -> void:
	var st := _make_song(id)
	_lock.lock()
	_results[id] = st
	_lock.unlock()


func _process(_delta: float) -> void:
	if _want != "" and music_on:
		_play(_want)


func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[id])
	_tasks.clear()


func _make_song(id: String) -> AudioStreamWAV:
	var sg := _song_def(id)
	if sg.is_empty() or (sg[4] as Array).is_empty():
		return _build_music()
	return _build_song(sg)


## Melodi segitiga + bas lembut. Nada: [midi, ketukan]; bas: satu nada midi per sg[3] ketukan.
static func _build_song(sg: Array) -> AudioStreamWAV:
	var beat := 60.0 / float(sg[2])
	var per_bass := float(sg[3])
	var notes: Array = sg[4]
	var bass: Array = sg[5]
	var beats := 0.0
	for nt in notes:
		beats += float(nt[1])
	var n := int(RATE * beat * beats)
	var data := PackedByteArray()
	data.resize((n + PAD) * 2)
	var idx := 0
	var start := 0.0  # ketukan awal nada sekarang
	var f := 0.0
	var dur := 1.0
	for i in n:
		var t := float(i) / RATE
		var b := t / beat
		while idx < notes.size() and b >= start + float(notes[idx][1]):
			start += float(notes[idx][1])
			idx += 1
		if idx < notes.size():
			var m := int(notes[idx][0])
			f = 0.0 if m < 0 else 440.0 * pow(2.0, (m - 69) / 12.0)
			dur = float(notes[idx][1]) * beat
		var local := t - start * beat
		var env := clampf(local / 0.015, 0.0, 1.0) * (0.35 + 0.65 * exp(-local * 3.0 / maxf(dur, 0.2))) * clampf((dur - local) / 0.04, 0.0, 1.0)
		var v := 0.0
		if f > 0.0:
			v += 0.30 * env * (0.8 * _tri(f * t) + 0.2 * sin(TAU * f * 2.0 * t))
		var bi := int(b / per_bass)
		var bl := t - bi * per_bass * beat
		var fb := 440.0 * pow(2.0, (int(bass[bi % bass.size()]) - 69) / 12.0)
		v += 0.15 * _tri(fb * t) * (0.45 + 0.55 * exp(-bl * 2.5))
		var tail := clampf((n - i) / 600.0, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * tail, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return s


## Musik diulang dengan memutar ulang saat selesai, BUKAN dengan loop bawaan AudioStreamWAV: di Samsung A18
## (Mali-G57, Android 16) loop WAV buatan kode membuat aplikasi crash tepat saat musik mencapai titik ulang
## (~6,7 detik setelah diputar; terlacak lewat jejak langkah 2.0.3/2.0.4).
## Suara lingkungan dunia 3D: kicau burung acak (efek suara) dan hujan (diputar ulang lewat finished,
## tanpa loop WAV — lihat catatan crash Samsung A18 di atas).
func ambient(on: bool) -> void:
	if _amb_timer == null:
		_amb_timer = Timer.new()
		_amb_timer.one_shot = true
		_amb_timer.timeout.connect(_on_ambient)
		add_child(_amb_timer)
	if on:
		_amb_timer.start(randf_range(3.0, 7.0))
	else:
		_amb_timer.stop()
		rain(false)


func _on_ambient() -> void:
	if not _raining:
		play("kicau")
	_amb_timer.start(randf_range(5.0, 11.0))


func rain(on: bool) -> void:
	_raining = on
	if _rain == null:
		_rain = AudioStreamPlayer.new()
		_rain.volume_db = -20.0
		_rain.finished.connect(func() -> void:
			if _raining and sfx_on:
				_rain.play())
		add_child(_rain)
	if on and sfx_on:
		if _rain.stream == null:
			_rain.stream = _build_rain()
		_rain.play()
	else:
		_rain.stop()


func _build_rain() -> AudioStreamWAV:
	var n := RATE * 2
	var data := PackedByteArray()
	data.resize((n + PAD) * 2)
	var prev := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		prev = prev * 0.82 + rng.randf_range(-1.0, 1.0) * 0.18
		var env := minf(1.0, minf(i, n - i) / 2000.0)
		data.encode_s16(i * 2, int(clampf(prev * 0.9 * env, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


func _chirp() -> AudioStreamWAV:
	var n := int(RATE * 0.36)
	var data := PackedByteArray()
	data.resize((n + PAD) * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := fmod(t, 0.12) / 0.12
		var f := 2600.0 + 1400.0 * sin(k * PI)
		ph += TAU * f / RATE
		var env := sin(k * PI) * (1.0 if t < 0.36 else 0.0)
		data.encode_s16(i * 2, int(clampf(0.18 * env * sin(ph), -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


func _on_music_finished() -> void:
	if not music_on or not is_inside_tree():
		return
	var nx := _next_song()
	if nx != current and _stream(nx) != null:
		_play(nx)
	else:
		_music.play()  # lagu berikutnya belum siap: ulangi lagu ini


func stop_all() -> void:
	_music.stop()
	for p in _sfx:
		p.stop()


## name: "klik", "benar", "salah", "bintang", "buka"
func play(name: String) -> void:
	if not sfx_on:
		return
	if not _cache.has(name):
		_cache[name] = _build_sfx(name)
	var p := _sfx[_next]
	_next = (_next + 1) % _sfx.size()
	p.stream = _cache[name]
	p.play()


func _build_sfx(name: String) -> AudioStreamWAV:
	match name:
		"benar":
			return _tones([[784.0, 0.09], [988.0, 0.09], [1319.0, 0.16]], 0.35)
		"salah":
			return _tones([[330.0, 0.14], [262.0, 0.2]], 0.22)  # lembut, tidak mengagetkan
		"bintang":
			return _tones([[1047.0, 0.07], [1319.0, 0.07], [1568.0, 0.07], [2093.0, 0.18]], 0.3)
		"kicau":
			return _chirp()
		"buka":
			return _tones([[523.0, 0.08], [659.0, 0.08], [784.0, 0.08], [1047.0, 0.22]], 0.3)
		_:
			return _tones([[880.0, 0.04]], 0.25)


## Musik latar: melodi pentatonik riang 8 ketuk diulang (± 7 detik), volume rendah.
func _build_music() -> AudioStreamWAV:
	var melody := [523.0, 659.0, 784.0, 659.0, 880.0, 784.0, 659.0, 587.0,
		523.0, 587.0, 659.0, 784.0, 659.0, 587.0, 523.0, 0.0]
	var bass := [262.0, 262.0, 196.0, 196.0, 220.0, 220.0, 196.0, 196.0]
	var beat := 0.42
	var n := int(RATE * beat * melody.size())
	var data := PackedByteArray()
	data.resize((n + PAD) * 2)  # ekor hening: pembaca resampler tidak pernah melewati ujung data
	for i in n:
		var t := float(i) / RATE
		var k := int(t / beat)
		var local := t - k * beat
		var env := clampf(local / 0.02, 0.0, 1.0) * exp(-local * 3.5)
		var f: float = melody[k % melody.size()]
		var v := 0.0
		if f > 0.0:
			v += 0.32 * env * _tri(f * t)
		var fb: float = bass[(k / 2) % bass.size()]
		v += 0.16 * _tri(fb * t) * (0.6 + 0.4 * exp(-(t - int(t / (beat * 2)) * beat * 2) * 2.0))
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return s


func _tones(notes: Array, vol: float) -> AudioStreamWAV:
	var total := 0.0
	for nt in notes:
		total += float(nt[1])
	var n := int(RATE * total)
	var data := PackedByteArray()
	data.resize((n + PAD) * 2)
	var i := 0
	for nt in notes:
		var f: float = nt[0]
		var cnt := int(RATE * float(nt[1]))
		for j in cnt:
			if i >= n:
				break
			var t := float(j) / RATE
			var env := clampf(t / 0.008, 0.0, 1.0) * exp(-t * 9.0)
			var v := vol * env * (0.7 * sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t))
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
			i += 1
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


static func _tri(phase: float) -> float:
	var x := fposmod(phase, 1.0)
	return 4.0 * absf(x - 0.5) - 1.0
