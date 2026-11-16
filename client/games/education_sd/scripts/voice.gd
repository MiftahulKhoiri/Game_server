extends Node
## Pembaca suara untuk anak yang belum lancar membaca (kelas 1–2): membacakan dialog, misi, materi, soal,
## dan pilihan jawaban memakai mesin suara bawaan HP (TTS Android/Google, bahasa Indonesia, tanpa internet
## bila suaranya sudah terpasang). Tidak ada berkas suara di paket.
##
## Mode (p.settings.voice):  auto = otomatis membacakan untuk kelas 1–2 | on = selalu | off = mati.
## Tombol "Dengar" tetap tersedia di mode auto/on (juga untuk kelas 3–6).
## Sinyal word(from, to) memberi posisi kata yang sedang diucapkan dalam teks ASLI, untuk sorot kata.
## Uji headless memakai fake = true (kata maju tiap fake_step detik tanpa mesin suara).

signal started
signal word(from: int, to: int)
signal ended

static var shared: Node = null

const RATE := 0.9  # sedikit lebih pelan dari normal, nyaman untuk anak
const SPOKEN := {"×": " kali ", "÷": " dibagi ", "+": " tambah ", "=": " sama dengan ", "−": " kurang ", "\n": ", ",
	"&": " dan ", "%": " persen ", ":": ", "}

var mode := "auto"
var grade := 1
var fake := false
var fake_step := 0.04
var voice_id := ""
var speaking := false
var text := ""  # teks asli yang sedang dibaca
var history: Array = []  # semua teks yang dibacakan (uji & laporan)
var _spoken := ""
var _map: PackedInt32Array = []  # indeks huruf yang diucapkan -> indeks huruf teks asli
var _uid := 0
var _fake_t := 0.0
var _fake_pos := 0
var _hooked := false


func _ready() -> void:
	shared = self
	_probe()


func _exit_tree() -> void:
	if shared == self:
		shared = null
	stop()


## Mesin suara aktif di aplikasi (APK v0.84.4+ menyalakan audio/general/text_to_speech).
static func engine_on() -> bool:
	return bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)) and DisplayServer.get_name() != "headless"


func _probe() -> void:
	voice_id = ""
	if not engine_on():
		return
	for lang in ["id", "in"]:  # Android lama menamai bahasa Indonesia "in"
		var v := DisplayServer.tts_get_voices_for_language(lang)
		if not v.is_empty():
			voice_id = v[0]
			break
	if not _hooked:
		_hooked = true
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, _on_started)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_ended)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_ended)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_BOUNDARY, _on_boundary)


func available() -> bool:
	return fake or voice_id != ""


## Alasan suara tidak tersedia (untuk Pengaturan), "" bila tersedia.
func status() -> String:
	if available():
		return ""
	if not engine_on():
		return "Suara pembaca butuh aplikasi versi terbaru. Perbarui aplikasi Game Petualang."
	return "Suara bahasa Indonesia belum terpasang di HP. Buka Pengaturan HP > Text-to-speech > Mesin Google > pasang Bahasa Indonesia."


## Tombol Dengar ditampilkan.
func listen_enabled() -> bool:
	return available() and mode != "off"


## Dibacakan otomatis tanpa menekan Dengar.
func auto_read() -> bool:
	return available() and (mode == "on" or (mode == "auto" and grade <= 2))


static func say(t: String) -> void:
	if shared != null and shared.listen_enabled():
		shared.speak(t)


static func say_auto(t: String) -> void:
	if shared != null and shared.auto_read():
		shared.speak(t)


static func hush() -> void:
	if shared != null:
		shared.stop()


static func listen_ok() -> bool:
	return shared != null and shared.listen_enabled()


func speak(t: String) -> void:
	stop()
	_build(t)
	if _spoken.strip_edges() == "":
		return
	text = t
	_uid += 1
	speaking = true
	history.append(t)
	if history.size() > 60:
		history.pop_front()
	started.emit()
	if fake:
		_fake_pos = 0
		_fake_t = 0.0
		return
	DisplayServer.tts_speak(_spoken, voice_id, 90, 1.0, RATE, _uid, true)


func stop() -> void:
	if not speaking:
		return
	speaking = false
	if not fake and engine_on():
		DisplayServer.tts_stop()
	ended.emit()


## Teks yang dikirim ke mesin suara: simbol matematika jadi kata, emoji/tanda hias jadi jeda;
## _map menyimpan asal setiap huruf agar sorot kata tetap tepat.
func _build(t: String) -> void:
	_spoken = ""
	_map = PackedInt32Array()
	var n := t.length()
	var i := 0
	while i < n:
		var c := t[i]
		var prev := t[i - 1] if i > 0 else " "
		var nxt := t[i + 1] if i + 1 < n else " "
		var rep := c
		if SPOKEN.has(c):
			rep = SPOKEN[c]
		elif c == "-" and prev == " " and nxt == " ":
			rep = " kurang "
		elif c == "?" and (prev == " " or prev == "(") and (nxt == " " or nxt == ")" or i + 1 == n):
			rep = " berapa "
		elif c == "_":
			var j := i
			while j < n and t[j] == "_":
				j += 1
			for k in range(i, j):
				_put(" titik " if k == i else "", k)
			i = j
			continue
		elif not _keep(c):
			rep = " "
		_put(rep, i)
		i += 1


func _put(s: String, at: int) -> void:
	for ch in s:
		_spoken += ch
		_map.append(at)


static func _keep(c: String) -> bool:
	var u := c.unicode_at(0)
	if u < 128:
		return u >= 32
	return (u >= 0xC0 and u <= 0x24F)  # huruf Latin beraksen


## Rentang kata di teks asli yang memuat huruf ke-pos dari teks yang diucapkan.
func span_at(pos: int) -> Vector2i:
	if _map.is_empty():
		return Vector2i(-1, -1)
	var a := _map[clampi(pos, 0, _map.size() - 1)]
	while a < text.length() and _space(text[a]):
		a += 1
	var b := a
	while b < text.length() and not _space(text[b]):
		b += 1
	return Vector2i(a, b)


static func _space(c: String) -> bool:
	return c == " " or c == "\n" or c == "\t"


func _on_started(_id: int) -> void:
	pass


func _on_ended(id: int) -> void:
	if id == _uid and speaking:
		speaking = false
		ended.emit.call_deferred()


func _on_boundary(pos: int, id: int) -> void:
	if id != _uid or not speaking:
		return
	var s := span_at(pos)
	if s.x >= 0 and s.x < s.y:
		word.emit.call_deferred(s.x, s.y)


func _process(delta: float) -> void:
	if not fake or not speaking:
		return
	_fake_t += delta
	if _fake_t < fake_step:
		return
	_fake_t = 0.0
	while _fake_pos < _spoken.length() and _spoken[_fake_pos] == " ":
		_fake_pos += 1
	if _fake_pos >= _spoken.length():
		speaking = false
		ended.emit()
		return
	var s := span_at(_fake_pos)
	if s.x >= 0 and s.x < s.y:
		word.emit(s.x, s.y)
	while _fake_pos < _spoken.length() and _spoken[_fake_pos] != " ":
		_fake_pos += 1
