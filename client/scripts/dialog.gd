extends Control
## Layar bicara dengan NPC. Misi, kemajuan, dan hadiah semuanya diurus SERVER
## (docs/API.md); layar ini hanya menampilkan dan mengirim "terima" / "ambil hadiah".

const WARGA_DIALOG = preload("res://scripts/warga_dialog.gd")
const WORLD_SCENE := "res://scenes/world3d.tscn"
const ART_DIR := "res://assets/characters/"
const NPC_NAMES := {"nenek_penjual": "Nenek Penjual Sayur", "petani": "Petani"}
## Kalimat per misi (kunci = id misi di server): tawaran, terkunci, ucapan terima kasih, sesudah selesai.
const QUEST_TEXTS := {
	"selamatkan_nenek": {
		"offer": "Selamat datang, Nak. Desa ini sedang tidak aman...",
		"thanks": "Terima kasih sudah menyelamatkanku, Nak! Ambil hadiah kecil ini:",
		"done": "Berkat kamu desa ini lebih aman. Semoga kerajaan selalu melindungimu.",
	},
	"selamatkan_petani": {
		"offer": "Hei, Ksatria! Ladangku sudah diinjak-injak goblin-goblin hijau itu...",
		"locked": "Aku masih gemetar... Tolong bantu Nenek lebih dulu, baru kita bicara lagi.",
		"thanks": "Kamu menyelamatkan ladangku! Terimalah ini sebagai tanda terima kasih:",
		"done": "Ladangku aman lagi. Kerajaan beruntung memilikimu, Ksatria.",
	},
	"hentikan_raja_goblin": {
		"offer": "Ksatria! Seekor orc tertangkap dan ia mengaku disuruh seseorang di bawah gunung...",
		"locked": "Aku punya kabar penting, tapi selesaikan urusan Nenek dan Monster Batu dulu.",
		"thanks": "Raja Iblis sudah tumbang! Kerajaan aman berkatmu. Terimalah ini:",
		"done": "Desa ini dan seluruh kerajaan berutang padamu, Pelindung Kerajaan.",
	},
	"usir_ogre": {
		"offer": "Ksatria... ada kabar buruk dari para pedagang. Sumber semua kekacauan ini ada di gunung.",
		"locked": "Nenek sedang mengkhawatirkan banyak hal. Bantu Petani dulu, ya, Nak.",
		"thanks": "Kamu mengalahkan Monster Batu! Kerajaan berutang budi padamu. Ini untukmu:",
		"done": "Gunung itu sunyi sekarang. Terima kasih, Pelindung Kerajaan.",
	},
	# Misi sampingan (v0.20.0)
	"kebun_babi": {
		"offer": "Nak, kebun sayurku diobrak-abrik babi hutan semalam. Sayurnya hampir habis...",
		"locked": "Tolong urus keadaanku dulu, baru kita bicara soal kebun.",
		"thanks": "Kebunku selamat, terima kasih! Pakailah baju ini, dulu milik suamiku:",
		"done": "Sayurnya tumbuh lagi. Kamu selalu diterima di dapurku, Nak.",
	},
	"ramuan_nenek": {
		"offer": "Banyak pengungsi terluka di desa. Aku bisa meracik obat, tapi butuh taring goblin dari Gunung Batu.",
		"locked": "Tolong urus keadaanku dulu, baru kita bicara soal obat.",
		"thanks": "Taring-taring ini cukup untuk satu panci obat! Ini bagianmu:",
		"done": "Para pengungsi sudah pulih berkat obatmu, Nak.",
	},
	"serigala_perbatasan": {
		"offer": "Serigala-serigala turun dari gunung seperti ada yang mengusir mereka. Pedagang tak berani lewat.",
		"locked": "Aku masih gemetar... Tolong bantu Nenek lebih dulu, baru kita bicara lagi.",
		"thanks": "Jalan raja aman lagi, pedagang mulai berdatangan. Ini upahmu:",
		"done": "Pedagang kembali lewat tiap pagi. Terima kasih, Ksatria.",
	},
	"sisa_pasukan": {
		"offer": "Raja Iblis memang tumbang, tapi pasukan orc-nya belum semua padam. Mereka masih berkeliaran.",
		"locked": "Aku punya kabar penting, tapi selesaikan dulu urusan Raja Iblis.",
		"thanks": "Gunung dan gua kini benar-benar sunyi. Kerajaan memberimu zirah ini:",
		"done": "Tak ada lagi orc yang mengusik desa. Kamu pahlawan kami.",
	},
	"permata_nenek": {
		"offer": "Permata merah itu rupanya sumber kekuatan pasukan iblis. Jangan biarkan jatuh ke tangan salah.",
		"locked": "Ada sesuatu yang ingin kubicarakan soal permata merah, tapi nanti, setelah Raja Iblis tumbang.",
		"thanks": "Permata-permata ini kusimpan aman di kuil kerajaan. Terimalah pedang ini:",
		"done": "Kuil menjaga permata itu sekarang. Kerajaan tenang berkatmu, Nak.",
	},
}
const GREETINGS := {
	"nenek_penjual": "Selamat datang, Nak. Desa ini sedang tidak aman...",
	"petani": "Hei, Ksatria! Ladangku sudah diinjak-injak goblin-goblin hijau itu...",
}

var _npc := ""
var _warga_id := ""  # id warga desa bila lawan bicara bukan NPC misi
var _stage := 0      # tahap cerita utama (untuk kalimat warga)
var _quest: Dictionary = {}  # misi milik NPC ini (tampilan dari server), {} bila tidak ada
var _others: Array[Dictionary] = []  # misi lain NPC ini yang sedang dikerjakan
var _name_label: Label
var _text: Label
var _action: Button
var _portrait: Control
var _tex: Texture2D
var _busy := false


func _ready() -> void:
	_npc = Session.talk_npc
	if _npc.begins_with("warga:"):
		_warga_id = _npc.trim_prefix("warga:")
	var path := ART_DIR + (_warga_id if _warga_id != "" else _npc) + ".png"
	if ResourceLoader.exists(path):
		_tex = load(path) as Texture2D
	_build_ui()
	_text.text = "..."
	if _warga_id != "":
		await _load_stage()
		_render_warga()
		return
	await _load_quest()
	_render()


## Tahap cerita untuk kalimat warga: banyak misi utama yang sudah tuntas.
func _load_stage() -> void:
	var res: Dictionary = await Api.quests_get()
	_stage = WARGA_DIALOG.stage_from_quests(res.data.get("quests", [])) if res.ok else 0


func _render_warga() -> void:
	_name_label.text = WARGA_DIALOG.display_name(_warga_id)
	_action.visible = false
	var n := int(Session.talk_counts.get(_npc, 1)) - 1
	_text.text = WARGA_DIALOG.line(_warga_id, _stage, n)


func _load_quest() -> void:
	var res: Dictionary = await Api.quests_get()
	_quest = {}
	if not res.ok:
		_text.text = str(res.error)
		return
	# NPC bisa punya beberapa misi. Yang ditampilkan: siap diklaim > baru ditawarkan >
	# sedang dikerjakan > terkunci; kalau semua sudah selesai, yang terakhir.
	# Dalam status yang sama, urutan di server berlaku (misi utama lebih dulu).
	var mine: Array[Dictionary] = []
	for q: Dictionary in res.data.get("quests", []):
		if str(q.giver) == _npc:
			mine.append(q)
	_others = []
	for status: String in ["done", "available", "active", "locked"]:
		for q: Dictionary in mine:
			if str(q.status) == status:
				_quest = q
				break
		if not _quest.is_empty():
			break
	if _quest.is_empty() and not mine.is_empty():
		_quest = mine[mine.size() - 1]
	# Misi lain yang sedang dikerjakan ikut dicatat supaya kemajuannya tetap terlihat.
	for q: Dictionary in mine:
		if str(q.status) == "active" and str(q.id) != str(_quest.get("id", "")):
			_others.append(q)


func _text_for(key: String, fallback := "") -> String:
	return str(QUEST_TEXTS.get(str(_quest.get("id", "")), {}).get(key, fallback))


func _render() -> void:
	_name_label.text = str(NPC_NAMES.get(_npc, "Penduduk"))
	_action.visible = false
	if _quest.is_empty():
		_text.text = str(GREETINGS.get(_npc, "Halo."))
		return
	var status := str(_quest.status)
	var target := int(_quest.target_count)
	match status:
		"locked":
			_text.text = _text_for("locked", "Belum saatnya.")
		"available":
			_text.text = "%s\n\n%s\n\nHadiah: %s." % [_text_for("offer"), _quest.description, _quest.reward_text]
			_set_action("Terima misi", "accept")
		"active":
			_text.text = "%s\n\nKemajuan: %d/%d. Hati-hati di luar sana, ya." % [_quest.title, int(_quest.progress), target]
		"done":
			_text.text = "%s %s." % [_text_for("thanks", "Terima kasih!"), _quest.reward_text]
			_set_action("Ambil hadiah", "claim")
		_:
			_text.text = _text_for("done", "Terima kasih.")
	if not _others.is_empty() and status != "claimed":
		var lines: PackedStringArray = []
		for q: Dictionary in _others:
			lines.append("%s %d/%d" % [str(q.title), int(q.progress), int(q.target_count)])
		_text.text += "\n\nMisi lain yang kamu kerjakan: " + ", ".join(lines) + "."


func _set_action(label: String, kind: String) -> void:
	_action.text = label
	_action.visible = true
	_action.disabled = false
	for c in _action.pressed.get_connections():
		_action.pressed.disconnect(c.callable)
	_action.pressed.connect(_on_action.bind(kind))


func _on_action(kind: String) -> void:
	if _busy:
		return
	_busy = true
	_action.disabled = true
	var res: Dictionary
	if kind == "accept":
		res = await Api.quest_accept(str(_quest.id))
	else:
		res = await Api.quest_claim(str(_quest.id))
	_busy = false
	if not res.ok:
		_text.text = str(res.error)
		_action.disabled = false
		return
	Session.merge_server_player(res.data.player)  # emas dan versi baru dari server
	for q: Dictionary in res.data.get("quests", []):
		if str(q.id) == str(_quest.id):
			_quest = q
	_render()
	if kind == "claim":
		_text.text += "\n\nKamu menerima: %s" % str(res.data.get("reward_text", ""))


func _on_back() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- tampilan ---

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a2420")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(0, 520)
	_portrait.draw.connect(_draw_portrait)
	box.add_child(_portrait)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 40)
	_name_label.add_theme_color_override("font_color", Color("e0c070"))
	box.add_child(_name_label)

	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 30)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)

	_action = _make_button("")
	_action.visible = false
	box.add_child(_action)

	var back := _make_button("Kembali")
	back.pressed.connect(_on_back)
	box.add_child(back)


func _draw_portrait() -> void:
	var size := _portrait.size
	if _tex == null:
		_portrait.draw_circle(size / 2.0, 140, Color("c8a040") if _warga_id == "" else Color("7a9a6a"))
		if _warga_id != "":  # warga tanpa gambar: huruf depan namanya di tengah lingkaran
			var initial := WARGA_DIALOG.display_name(_warga_id).substr(0, 1)
			var font := ThemeDB.fallback_font
			_portrait.draw_string(font, size / 2.0 + Vector2(-34, 38), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, Color("1a2420"))
		return
	var ts := _tex.get_size()
	var scale := minf(size.x / ts.x, size.y / ts.y)
	var draw_size := ts * scale
	_portrait.draw_texture_rect(_tex, Rect2((size - draw_size) / 2.0, draw_size), false)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 34)
	button.custom_minimum_size = Vector2(0, 100)
	return button
