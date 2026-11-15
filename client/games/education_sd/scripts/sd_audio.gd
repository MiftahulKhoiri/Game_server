extends Node
## Audio Pulau Ilmu yang DIBUAT DENGAN KODE (tanpa berkas suara: paket tetap kecil, tanpa masalah lisensi):
## klik tombol, jawaban benar, jawaban belum tepat (nada rendah lembut), bintang/hadiah, dan musik latar
## petualangan pendek yang berulang. Musik dan efek suara bisa dimatikan terpisah.

const RATE := 22050

var music_on := true
var sfx_on := true
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next := 0


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
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
		if not _music.playing:
			if _music.stream == null:
				_music.stream = _build_music()
			_music.play()
	else:
		_music.stop()


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
	data.resize(n * 2)
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
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s


func _tones(notes: Array, vol: float) -> AudioStreamWAV:
	var total := 0.0
	for nt in notes:
		total += float(nt[1])
	var n := int(RATE * total)
	var data := PackedByteArray()
	data.resize(n * 2)
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
