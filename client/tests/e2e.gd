extends SceneTree
## Uji ujung-ke-ujung klien <-> server. Dijalankan lewat: make client-test
## (butuh server Go yang hidup di GAME_URL, bawaan http://127.0.0.1:8099).

const Maps = preload("res://scripts/maps.gd")
const Version = preload("res://scripts/version.gd")

var _failed := false
var Api: Node  # autoload tidak dikenal saat skrip utama dikompilasi; ambil dari pohon
var Session: Node


func _initialize() -> void:
	await _run()
	quit(1 if _failed else 0)


func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  GAGAL ") + label)
	if not cond:
		_failed = true


## Semua petak yang bisa dilewati harus tersambung dari titik awal
## (tidak boleh ada ladang/halaman yang terkurung).
func _check_map_connected(map_id: String) -> void:
	var total := 0
	for y in Maps.height(map_id):
		for x in Maps.width(map_id):
			if Maps.walkable(map_id, x, y):
				total += 1
	var seen := {Maps.SPAWN: true}
	var queue: Array[Vector2i] = [Maps.SPAWN]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = cur + d
			if not seen.has(n) and Maps.walkable(map_id, n.x, n.y):
				seen[n] = true
				queue.append(n)
	_check(seen.size() == total, "semua petak bisa dilewati tersambung (%d dari %d)" % [seen.size(), total])


func _run() -> void:
	await process_frame  # tunggu pohon siap sebelum memakai node/HTTPRequest
	Api = root.get_node("Api")
	Session = root.get_node("Session")
	print("== peta")
	for y in Maps.height(Maps.DEFAULT_MAP):
		_check(Maps.rows(Maps.DEFAULT_MAP)[y].length() == 15, "baris peta %d lebar 15" % y)
	_check(Maps.walkable(Maps.DEFAULT_MAP, Maps.SPAWN.x, Maps.SPAWN.y), "titik awal bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 0, 0), "pohon di tepi tidak bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, -1, 3), "luar peta tidak bisa dilewati")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 7, 12), "jembatan bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 3, 12), "sungai tidak bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 7, 8), "sumur menghalangi")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 4, 2), "pintu rumah bisa dilewati")
	_check_map_connected(Maps.DEFAULT_MAP)

	print("== api")
	Api.base_url = OS.get_environment("GAME_URL") if OS.get_environment("GAME_URL") != "" else "http://127.0.0.1:8099"
	var h: Dictionary = await Api.health()
	_check(h.ok, "healthz")
	if not h.ok:
		print("  server tidak terjangkau: ", h.get("error"))
		return

	print("== versi")
	_check(Version.compare("0.1.0", "0.2.0") < 0, "0.1.0 < 0.2.0")
	_check(Version.compare("0.10.0", "0.9.0") > 0, "0.10.0 > 0.9.0 (angka, bukan teks)")
	_check(Version.compare("v1.0.0", "1.0.0") == 0, "awalan v diabaikan")
	_check(Version.app_version().split(".").size() == 3, "versi aplikasi berbentuk MAJOR.MINOR.PATCH (%s)" % Version.app_version())
	var vi: Dictionary = await Api.version_info()
	_check(vi.ok and str(vi.data.get("server", "")) != "", "GET /v1/version")
	if vi.ok:
		_check(Version.compare(Version.app_version(), str(vi.data.min_client)) >= 0, "aplikasi memenuhi versi minimum server")
	Api.client_version = "0.0.1"
	var old_try: Dictionary = await Api.register("VersiLawas")
	_check(not old_try.ok and old_try.status == 426, "versi terlalu lama ditolak 426")
	_check(old_try.get("data", {}).has("update_url"), "426 membawa update_url")
	Api.client_version = Version.app_version()

	print("== layar masuk")
	var login: Control = load("res://scenes/login.tscn").instantiate()
	root.add_child(login)
	await create_timer(0.6).timeout
	_check(login._version_label.text.contains("Server v"), "layar masuk menampilkan versi server")
	_check(not login._btn_update.visible, "tidak ada ajakan update bila versi sudah terbaru")
	_check(not login._btn_start.disabled, "tombol aktif bila versi memenuhi syarat")
	login.queue_free()

	var name := "Uji%d" % (Time.get_ticks_usec() % 100000)
	var reg: Dictionary = await Api.register(name)
	_check(reg.ok, "daftar pemain " + name)
	if not reg.ok:
		return
	Api.token = str(reg.data.token)
	Session.set_player(reg.data.player)
	_check(Session.player.state.x == 5 and typeof(Session.player.state.x) == TYPE_INT, "state memakai int")

	var dup: Dictionary = await Api.register(name)
	_check(not dup.ok and dup.status == 409, "nama kembar ditolak 409")

	print("== world: gerak lalu simpan otomatis")
	Session.offline = false
	Session.safe_steps = 100000  # cegah pertemuan acak mengganggu uji gerak
	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world._try_move(Vector2i.RIGHT)  # (5,5) -> (6,5)
	await create_timer(0.3).timeout
	world._try_move(Vector2i.DOWN)  # (6,5) -> (6,6)
	await create_timer(0.3).timeout
	world._try_move(Vector2i.UP)
	await create_timer(0.3).timeout
	_check(Session.player.state.x == 6 and Session.player.state.y == 5, "posisi lokal (6,5)")

	await create_timer(2.5).timeout  # tunggu simpan otomatis (jeda 1.5 dtk)
	var me: Dictionary = await Api.get_me()
	_check(me.ok, "ambil data setelah simpan")
	_check(int(me.data.state.x) == 6 and int(me.data.state.y) == 5, "server menyimpan posisi (6,5)")
	_check(int(me.data.version) >= 2, "versi di server naik")
	_check(int(me.data.version) == Session.player.version, "versi lokal sinkron dengan server")

	print("== tabrakan")
	# Dari (6,5) jalan ke atas sampai mentok pohon/rumah tidak boleh tembus peta.
	for i in 30:
		world._try_move(Vector2i.UP)
		await create_timer(0.12).timeout
	var y: int = Session.player.state.y
	_check(Maps.walkable(Maps.DEFAULT_MAP, Session.player.state.x, y), "pemain tetap di petak yang bisa dilewati (y=%d)" % y)

	print("== pertarungan")
	world.queue_free()
	await process_frame
	Session.safe_steps = 0
	var none: Dictionary = await Api.battle_get()
	_check(not none.ok and none.status == 404, "belum ada pertarungan -> 404")
	var pos_before := Vector2i(Session.player.state.x, Session.player.state.y)
	var start: Dictionary = await Api.battle_start()
	_check(start.ok and start.status == 201, "mulai pertarungan 201")
	if start.ok:
		var again: Dictionary = await Api.battle_start()
		_check(not again.ok and again.status == 409, "mulai dua kali ditolak 409")
		Session.merge_server_player(start.data.player)
		Session.battle = start.data.battle
		_check(Vector2i(Session.player.state.x, Session.player.state.y) == pos_before, "merge tidak mengubah posisi lokal")
		_check(typeof(Session.player.state.hp) == TYPE_INT, "hasil merge memakai int")
		var scene: Control = load("res://scenes/battle.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		_check(scene._enemy_name.text == str(Session.battle.enemy_name), "layar pertarungan menampilkan nama musuh")
		_check((scene._buttons["potion"] as Button).disabled, "ramuan nonaktif saat HP penuh")
		var guard := 0
		while not scene._finished and guard < 60:
			guard += 1
			scene._on_action("attack")
			while scene._busy:
				await process_frame
		_check(scene._finished, "pertarungan selesai (%s) dalam %d aksi" % [scene._result, guard])
		_check(Session.battle.is_empty(), "sesi tidak lagi menyimpan pertarungan")
		_check(scene._btn_continue.visible, "tombol lanjut muncul")
		var after: Dictionary = await Api.get_me()
		_check(after.ok and int(after.data.state.hp) == Session.player.state.hp, "HP lokal sama dengan server")
		_check(int(after.data.version) == Session.player.version, "versi lokal sinkron setelah pertarungan")
		if scene._result == "won":
			_check(int(after.data.state.xp) > 0 or int(after.data.state.level) > 1, "menang memberi XP")
		scene.queue_free()
		await process_frame
	var gone: Dictionary = await Api.battle_get()
	_check(not gone.ok and gone.status == 404, "pertarungan terhapus di server setelah selesai")

	print("== toko")
	var shop_list: Dictionary = await Api.shop_get()
	_check(shop_list.ok and shop_list.data.items.size() > 0, "daftar toko")
	var gold_before: int = Session.player.state.gold
	var shop_scene: Control = load("res://scenes/shop.tscn").instantiate()
	root.add_child(shop_scene)
	await create_timer(0.8).timeout
	_check(shop_scene._list.get_child_count() > 2, "layar toko menampilkan barang")
	shop_scene._on_trade("sell", "ramuan")
	while shop_scene._busy:
		await process_frame
	await process_frame
	var shop_me: Dictionary = await Api.get_me()
	_check(int(shop_me.data.state.gold) == gold_before + 6, "menjual 1 ramuan menambah 6 emas di server")
	_check(Session.player.state.gold == int(shop_me.data.state.gold), "emas lokal sama dengan server")
	_check(Session.player.version == int(shop_me.data.version), "versi lokal sinkron setelah dagang")
	var gold_mid: int = int(shop_me.data.state.gold)
	shop_scene._on_trade("buy", "ramuan")
	while shop_scene._busy:
		await process_frame
	var shop_me2: Dictionary = await Api.get_me()
	var expected := gold_mid - 15 if gold_mid >= 15 else gold_mid  # emas kurang -> ditolak, emas tetap
	_check(int(shop_me2.data.state.gold) == expected, "beli ramuan: emas %d -> %d" % [gold_mid, expected])
	shop_scene.queue_free()
	await process_frame
	var bad_buy: Dictionary = await Api.shop_buy("naga", 1)
	_check(not bad_buy.ok and bad_buy.status == 404, "barang asing 404")

	print("== misi")
	var q0: Dictionary = await Api.quests_get()
	_check(q0.ok and q0.data.quests.size() > 0 and q0.data.quests[0].status == "available", "misi awal tersedia")
	var early: Dictionary = await Api.quest_claim("selamatkan_nenek")
	_check(not early.ok and early.status == 422, "klaim sebelum terima ditolak 422")
	Session.talk_npc = "nenek_penjual"
	var dialog: Control = load("res://scenes/dialog.tscn").instantiate()
	root.add_child(dialog)
	await create_timer(0.8).timeout
	_check(dialog._action.visible and dialog._action.text == "Terima misi", "dialog menawarkan misi")
	dialog._on_action("accept")
	while dialog._busy:
		await process_frame
	_check(not dialog._action.visible and dialog._text.text.contains("0/5"), "misi diterima, kemajuan 0/5")
	var q1: Dictionary = await Api.quests_get()
	_check(q1.data.quests[0].status == "active", "server mencatat misi aktif")
	_check(Session.player.version == int((await Api.get_me()).data.version), "versi lokal sinkron setelah terima misi")
	dialog.queue_free()
	await process_frame
	_check(Maps.npc_at(Maps.DEFAULT_MAP, 3, 6) == "nenek_penjual", "nenek berdiri di (3,6)")
	_check(Maps.npc_near(Maps.DEFAULT_MAP, 4, 6) == "nenek_penjual" and Maps.npc_near(Maps.DEFAULT_MAP, 5, 5) == "", "pemain hanya dekat nenek bila bersebelahan")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 3, 6), "petak nenek tetap bagian peta (diblokir oleh gerak, bukan peta)")

	var merged := {"state": {"level": 3, "xp": 4, "hp": 10, "max_hp": 46, "gold": 9, "map": "desa_awal", "x": 1, "y": 1, "inventory": [{"id": "ramuan", "qty": 2.0}]}, "version": 9.0}
	Session.player.state.x = 8
	Session.merge_server_player(merged)
	_check(Session.player.state.x == 8 and Session.player.state.level == 3, "merge: posisi lokal tetap, statistik ikut server")
	_check(typeof(Session.player.state.inventory[0].qty) == TYPE_INT and Session.player.version == 9, "merge: angka menjadi int")
	Session.merge_server_player(merged, true)
	_check(Session.player.state.x == 1, "merge dengan adopt_position memakai posisi server")

	print("== token salah")
	Api.token = "salah"
	var bad: Dictionary = await Api.get_me()
	_check(not bad.ok and bad.status == 401, "token salah ditolak 401")
