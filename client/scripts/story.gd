extends Node
## Cerita utama "The Last Dragon" di dunia (docs/STORY.md), di atas world3d.gd:
##   - narasi bab: layar cerita setiap kali langkah cerita selesai (dan prolog untuk pemain baru),
##   - tujuan singkat yang sedang dijalani (dipakai papan kanan atas world_life.gd dan Jurnal),
##   - Batu Sihir penguat kutukan di Benteng Orc yang bisa dihancurkan (tombol "Hancurkan"),
##   - Aldragor yang pulih terbang mengitari langit Desa Awal setelah cerita tamat.
## Kemajuan (State.Story) dan hadiahnya diurus server (internal/game/story.go); di sini hanya tampilan.

const Maps = preload("res://scripts/maps.gd")
const Models = preload("res://scripts/models.gd")
const HeroFx = preload("res://scripts/hero_fx.gd")

const END := 12                       # sama dengan StoryEnd di server
const SEEN_FILE := "user://cerita.cfg"
const STONE_POS := Vector2(9.5, 12.5)  # Batu Sihir di Benteng Orc (sama dengan langkah benteng_batu di server)
const STONE_STEP := 7
const STONE_NEAR := 1.9

## Bab tiap langkah (untuk judul layar cerita dan Jurnal).
const CHAPTERS := [
	"Prolog: Serangan di Desa Awal", "Prolog: Serangan di Desa Awal",
	"Bab 1: Hutan Binatang", "Bab 1: Hutan Binatang",
	"Bab 2: Gua Goblin",
	"Bab 3: Gunung Berapi", "Bab 3: Gunung Berapi", "Bab 3: Gunung Berapi", "Bab 3: Gunung Berapi",
	"Bab 4: Istana Kegelapan", "Bab 4: Istana Kegelapan",
	"Epilog: Dunia Kembali Damai",
]
## Tujuan singkat langkah yang sedang dijalani (papan kanan atas).
const GOALS := [
	"Temui Kepala Desa di utara desa",
	"Temui Kapten Rimba di kem Perbatasan",
	"Cari Penjaga Hutan di Hutan Binatang",
	"Kalahkan 3 Goblin di Hutan Binatang",
	"Kalahkan Raja Goblin di Gua Goblin",
	"Kalahkan 3 Orc Batu di Gunung Berapi",
	"Kalahkan Panglima Orc Batu di Benteng Orc",
	"Hancurkan Batu Sihir di Benteng Orc",
	"Bicara dengan Orc Tua di Benteng Orc",
	"Kalahkan Aldragor di Istana Kegelapan",
	"Kalahkan Malzareth di ruang takhta",
	"Bawa Elara pulang ke Kepala Desa",
]
## Tujuan lengkap (Jurnal).
const GOALS_LONG := [
	"Desa diserang semalam dan Elara diculik. Bicaralah dengan Kepala Desa di rumahnya, di utara desa.",
	"Ambil bekal, keluar lewat gerbang selatan, lalu temui Kapten Rimba di kem Perbatasan.",
	"Masuki Hutan Binatang di selatan Perbatasan dan temukan Penjaga Hutan yang terluka di dekat pintu masuk.",
	"Hadapi binatang yang dikutuk dan kalahkan tiga Goblin yang membawa Elara. Gerbang Gua Goblin lalu terbuka.",
	"Masuki Gua Goblin, kalahkan para Kepala Goblin, dan hadapi Raja Goblin yang terkutuk.",
	"Lewati lereng Gunung Berapi dan kalahkan tiga Orc Batu penjaga jalur lava.",
	"Masuki Benteng Orc di perut gunung dan kalahkan Panglima Orc Batu di singgasananya.",
	"Hancurkan Batu Sihir yang berdenyut di samping singgasana Panglima.",
	"Seorang Orc tua mulai sadar dari kutukan. Bicaralah dengannya.",
	"Lewati lorong selatan Benteng Orc menuju Istana Kegelapan. Kalahkan Aldragor tanpa membunuhnya.",
	"Masuki ruang takhta, hadapi Malzareth dalam tiga fase, dan bebaskan Elara.",
	"Kutukan telah patah. Bawa Elara pulang dan temui Kepala Desa di Desa Awal.",
]
## Narasi setelah langkah i selesai: [judul, isi]. -1 = pembuka prolog untuk pemain baru.
const NARASI := {
	-1: ["The Last Dragon", "Dahulu Eldoria hidup damai di bawah perlindungan Aldragor, naga terakhir.\n\nSemalam, Desa Awal diserang. Monster datang dari arah hutan, dan di tengah kekacauan seorang penyihir berjubah gelap menculik Elara, putri Kepala Desa. Kamu berusaha melawan, tetapi penyihir itu menghilang dalam kabut hitam.\n\nPagi ini Kepala Desa ingin bicara denganmu."],
	0: ["Prolog: Serangan di Desa Awal", "\"Elara telah dibawa pergi oleh penyihir itu. Aku tidak sanggup meninggalkan desa untuk mencarinya. Tolong temukan putriku dan bawa dia pulang. Aku percaya kepadamu.\"\n\nKepala Desa memberimu bekal perjalanan. Keluarlah lewat gerbang selatan dan temui Kapten Rimba di kem Perbatasan."],
	1: ["Prolog: Serangan di Desa Awal", "Kapten Rimba menunjukkan jejak cakar dan kaki kecil di tanah: semuanya menuju Hutan Binatang di selatan.\n\nRadar Musuh pemberiannya akan menunjukkan makhluk-makhluk yang berkeliaran di sana."],
	2: ["Bab 1: Hutan Binatang", "\"Jangan kira mereka memilih menjadi seperti ini. Dahulu mereka hidup damai. Sihir hitam telah merampas kendali mereka. Aku melihat para Goblin membawa seorang gadis ke gua di balik hutan.\"\n\nTiga Goblin menjaga jalan menuju Gua Goblin. Kalahkan mereka."],
	3: ["Bab 1: Hutan Binatang", "Goblin terakhir tumbang. Di dekat singgasananya kamu menemukan sehelai pita rambut milik Elara.\n\nJejak pasukan Goblin mengarah ke Gua Goblin. Gerbangnya kini terbuka."],
	4: ["Bab 2: Gua Goblin", "Raja Goblin rebah. Kilau merah di matanya padam, dan ia bergumam lirih, \"Kami... dulu penambang...\"\n\nDi singgasananya kamu menemukan catatan dan Lambang Malzareth. Para Goblin bukan dalang penculikan; mereka hanya diperintah penyihir itu. Catatan itu menyebut sumber kekuatan sihir di gunung berapi, dan seekor naga yang menjaga istananya."],
	5: ["Bab 3: Gunung Berapi", "Orc Batu terakhir di lereng runtuh menjadi bongkahan. Udara makin panas, aliran lava menerangi jalan.\n\nDi ujung selatan lereng, pintu Benteng Orc terbuka ke perut gunung."],
	6: ["Bab 3: Gunung Berapi", "Panglima Orc Batu tumbang dari singgasananya.\n\nDi samping singgasana itu sebuah batu ungu berdenyut seperti jantung: Batu Sihir penguat kutukan. Hancurkan!"],
	7: ["Bab 3: Gunung Berapi", "Batu Sihir pecah berkeping-keping. Gelombang cahaya menyapu benteng dan kutukan di gunung melemah.\n\nDi sudut ruangan, seorang Orc tua mengerang. Matanya tidak lagi merah."],
	8: ["Bab 3: Gunung Berapi", "\"Kami dahulu penjaga gunung, bukan monster. Penyihir itu mengikat pikiran kami. Batu ini hanya penguat kutukannya. Selama Malzareth hidup, kutukan tidak akan berakhir. Naga terakhir pun telah ia kuasai.\"\n\nOrc Tua menunjukkan lorong rahasia di selatan benteng: jalan menuju Istana Kegelapan."],
	9: ["Bab 4: Istana Kegelapan", "Naga itu berhenti menyerang. Di balik mata yang gelap, masih tersisa kesadaran sang pelindung. Ia bukan musuh yang memilih kejahatan; ia adalah korban terakhir Malzareth.\n\nGerbang ruang takhta terbuka."],
	10: ["Bab 4: Istana Kegelapan", "\"Semua makhluk tunduk kepadaku! Goblin, Orc, binatang, bahkan naga terakhir! Kau tidak akan mengubah apa pun!\"\n\n\"Mereka bukan milikmu. Kau merampas kehidupan mereka. Hari ini kutukanmu berakhir!\"\n\nMalzareth kalah. Sihir hitam kehilangan sumbernya dan kutukan mulai terlepas dari semua makhluk. Rantai Elara terlepas.\n\nAldragor, yang kini sadar kembali, menunduk di hadapanmu dan menawarkan punggungnya untuk terbang pulang."],
	11: ["Epilog: Dunia Kembali Damai", "Binatang kembali ke wujud aslinya. Goblin dan Orc terbebas dari kendali sihir. Aldragor pulih dan kembali menjadi pelindung Eldoria.\n\n\"Engkau telah membawa putriku pulang dan membebaskan dunia dari kutukan. Desa ini tidak akan melupakan keberanianmu.\"\n\n\"Terima kasih karena tidak menyerah mencariku. Hari ini bukan hanya aku yang diselamatkan, seluruh dunia mendapat kesempatan untuk hidup damai kembali.\"\n\nAldragor terbang melintasi langit saat matahari terbit. Kisahmu menjadi legenda.\n\nTHE END. Kutukan telah berakhir."],
}

var world = null              # world3d.gd
var showing := false          # layar cerita sedang terbuka (untuk uji)
var shown_title := ""         # judul layar cerita terakhir (untuk uji)

var _layer: CanvasLayer
var _panel: Control
var _title: Label
var _body: Label
var _next: Button
var _queue: Array = []
var _stone: Node3D
var _dragon: Node3D
var _t := 0.0
var _busy := false
var _fly_home := false        # setelah Malzareth kalah: Aldragor yang pulih menerbangkan pemain dan Elara pulang


func setup(w: Node) -> void:
	world = w
	_layer = CanvasLayer.new()
	_layer.layer = 8
	add_child(_layer)
	_panel = Control.new()
	_panel.visible = false
	_layer.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.88)
	_panel.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 90)
	_panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 26)
	margin.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color("e8c070"))
	box.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("font_size", 30)
	_body.add_theme_color_override("font_color", Color("f2ead8"))
	scroll.add_child(_body)
	_next = Button.new()
	_next.text = "Lanjut"
	_next.custom_minimum_size = Vector2(0, 100)
	_next.add_theme_font_size_override("font_size", 34)
	_next.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(_on_next)
	box.add_child(_next)


## Langkah cerita sekarang (0..END).
static func step() -> int:
	return Session.story()


static func done() -> bool:
	return step() >= END


static func chapter(i: int) -> String:
	return "Tamat" if i >= CHAPTERS.size() else str(CHAPTERS[clampi(i, 0, CHAPTERS.size() - 1)])


## Tujuan singkat langkah sekarang ("" bila tamat).
static func goal() -> String:
	var i := step()
	return "" if i >= GOALS.size() else str(GOALS[i])


static func goal_long() -> String:
	var i := step()
	return "Kutukan Malzareth telah berakhir. Elara pulang dan Aldragor kembali menjaga Eldoria. Terima kasih, Pahlawan!" if i >= GOALS_LONG.size() else str(GOALS_LONG[i])


## Dipanggil world3d setiap kali peta dimuat.
func on_map(map_id: String) -> void:
	_stone = null
	_dragon = null
	if world == null or world._npc_root == null or Session.offline:
		return
	if map_id == Maps.GUA and step() <= STONE_STEP:
		_build_stone()
	if map_id == Maps.DEFAULT_MAP and done():
		_build_dragon()
	check.call_deferred()


func tick(delta: float) -> void:
	_t += delta
	if _stone != null and is_instance_valid(_stone):
		var crystal := _stone.get_node_or_null("Kristal") as Node3D
		if crystal != null:
			crystal.rotation.y += delta * 0.8
			crystal.position.y = 1.05 + sin(_t * 2.2) * 0.08
			crystal.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 4.4))
	if _dragon != null and is_instance_valid(_dragon):
		# Aldragor yang pulih terbang memutari desa, tinggi di atas atap.
		var a := _t * 0.12
		var c := Vector2(28.0, 22.0)
		_dragon.position = Vector3(c.x + cos(a) * 22.0, 11.0 + sin(_t * 0.7) * 1.2, c.y + sin(a) * 16.0)
		_dragon.rotation.y = atan2(-sin(a) * 22.0, cos(a) * 16.0)


# --- layar cerita ---

## Tampilkan narasi untuk langkah yang baru selesai sejak terakhir dilihat di HP ini.
func check() -> void:
	if world == null or Session.offline or showing or not Session.story_popups:
		return
	var cur := step()
	var seen := _seen()
	if seen == -2:  # belum pernah membuka cerita di HP ini
		if cur == 0:
			_queue.append(NARASI[-1])
		elif cur > 0:
			_queue.append(NARASI[cur - 1])  # pemain lama: cukup narasi terakhir
	elif cur > seen:
		for i in range(maxi(seen, cur - 2), cur):  # paling banyak dua narasi berturut-turut
			if NARASI.has(i):
				_queue.append(NARASI[i])
		_fly_home = cur == 11 and world._map_id == Maps.TAKHTA
	_set_seen(cur)
	if not _queue.is_empty():
		_show_next()


func _show_next() -> void:
	var item: Array = _queue.pop_front()
	shown_title = str(item[0])
	_title.text = shown_title
	_body.text = str(item[1])
	_next.text = "Lanjut" if not _queue.is_empty() else "Tutup"
	_panel.visible = true
	showing = true
	world._locked = true


func _on_next() -> void:
	if not _queue.is_empty():
		_show_next()
		return
	close()


func close() -> void:
	_panel.visible = false
	showing = false
	world._locked = false
	if _fly_home:
		_fly_home = false
		world._show_toast("Aldragor menerbangkanmu pulang")
		world._set_status("Aldragor yang telah pulih membawamu dan Elara terbang pulang ke Desa Awal.")
		world._go_to_map(Maps.DEFAULT_MAP, Vector2i(40, 7))
		return
	var g := goal()
	if g != "":
		world._set_status("Tujuan: " + g)
		world.notify("Cerita: " + g, "kejadian")


func _seen() -> int:
	var cf := ConfigFile.new()
	if cf.load(SEEN_FILE) != OK:
		return -2
	return int(cf.get_value("cerita", _key(), -2))


func _set_seen(v: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SEEN_FILE)
	cf.set_value("cerita", _key(), v)
	cf.save(SEEN_FILE)


func _key() -> String:
	var id := str(Session.player.get("id", ""))
	return id if id != "" else "lokal"


# --- Batu Sihir (Bab 3) ---

func _build_stone() -> void:
	_stone = Node3D.new()
	_stone.name = "BatuSihir"
	_stone.position = Vector3(STONE_POS.x, 0.0, STONE_POS.y)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.42
	cyl.height = 0.6
	cyl.radial_segments = 8
	base.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("3a3440")
	base.material_override = bm
	base.position.y = 0.3
	_stone.add_child(base)
	var crystal := MeshInstance3D.new()
	crystal.name = "Kristal"
	var pm := PrismMesh.new()
	pm.size = Vector3(0.45, 0.9, 0.45)
	crystal.mesh = pm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("b070ff")
	cm.emission_enabled = true
	cm.emission = Color("8a3cff")
	cm.emission_energy_multiplier = 2.4
	crystal.material_override = cm
	crystal.position.y = 1.05
	_stone.add_child(crystal)
	var light := OmniLight3D.new()
	light.light_color = Color("b070ff")
	light.light_energy = 1.6
	light.omni_range = 4.5
	light.position.y = 1.2
	_stone.add_child(light)
	var label := Label3D.new()
	label.text = "Batu Sihir"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0045
	label.font_size = 34
	label.outline_size = 10
	label.modulate = Color("e0c0ff")
	label.position.y = 1.85
	_stone.add_child(label)
	world._npc_root.add_child(_stone)


## Pemain berdiri di dekat Batu Sihir dan sudah waktunya menghancurkannya.
func stone_near() -> bool:
	return _stone != null and is_instance_valid(_stone) and step() == STONE_STEP \
		and STONE_POS.distance_to(world._pos) < STONE_NEAR


func stone_anchor() -> Vector3:
	return Vector3(STONE_POS.x, 2.2, STONE_POS.y)


func smash_stone() -> void:
	if _busy:
		return
	_busy = true
	await world._flush_save()  # server memeriksa posisi tersimpan
	var res: Dictionary = await Api.story_talk("batu_sihir")
	_busy = false
	if not res.ok:
		world._set_status(str(res.error))
		return
	Session.merge_server_player(res.data)
	world._refresh_hud()
	if _stone != null and is_instance_valid(_stone):
		HeroFx.burst(world, _stone.position + Vector3(0, 1.0, 0), Color("c890ff"), 40, 4.0)
		_stone.queue_free()
	_stone = null
	world._show_toast("Batu Sihir hancur!")
	check()


# --- Aldragor di langit desa (epilog) ---

func _build_dragon() -> void:
	_dragon = Models.create("aldragor")
	_dragon.name = "AldragorTerbang"
	_dragon.scale = _dragon.scale * 1.6
	world._npc_root.add_child(_dragon)
