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
		_check(Maps.rows(Maps.DEFAULT_MAP)[y].length() == 25, "baris peta %d lebar 25" % y)
	_check(Maps.walkable(Maps.DEFAULT_MAP, Maps.SPAWN.x, Maps.SPAWN.y), "titik awal bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 0, 0), "pohon di tepi tidak bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, -1, 3), "luar peta tidak bisa dilewati")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 12, 16), "jembatan bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 3, 16), "sungai tidak bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 12, 10), "sumur menghalangi")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 3, 9) and Maps.walkable(Maps.DEFAULT_MAP, 7, 11), "pagar kandang menghalangi, gerbang kandang terbuka")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 4, 2), "pintu rumah bisa dilewati")
	_check_map_connected(Maps.DEFAULT_MAP)
	_check_map_connected(Maps.PERBATASAN)
	_check_map_connected(Maps.GUNUNG)
	_check_map_connected(Maps.GUA)
	_check(Maps.tile_at(Maps.GUA, 7, 14) == Maps.BOSS_TILE and Maps.walkable(Maps.GUA, 7, 14), "singgasana bos ada di (7,14)")
	for id: String in Maps.EXITS:
		for e: Dictionary in Maps.EXITS[id]:
			_check(Maps.walkable(id, e.pos.x, e.pos.y), "pintu %s %s berada di petak yang bisa dilewati" % [id, e.pos])
			_check(Maps.walkable(e.to, e.at.x, e.at.y) and Maps.exit_at(e.to, e.at.x, e.at.y).is_empty(), "tujuan pintu %s -> %s aman dan bukan pintu" % [id, e.to])
	_check(not Maps.walkable(Maps.PERBATASAN, 3, 8), "tembok batu menghalangi")
	_check(not Maps.walkable(Maps.GUNUNG, 0, 5) and Maps.walkable(Maps.GUNUNG, 7, 0), "batu besar menghalangi, pintu gunung terbuka")
	_check(Maps.ENCOUNTER_TILES.contains(Maps.tile_at(Maps.GUNUNG, 2, 2)), "kerikil gunung tempat pertemuan musuh")

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
	var old_try: Dictionary = await Api.register("VersiLawas", "lawas@contoh.id", "sandi-lawas-123")
	_check(not old_try.ok and old_try.status == 426, "versi terlalu lama ditolak 426")
	_check(old_try.get("data", {}).has("update_url"), "426 membawa update_url")
	Api.client_version = Version.app_version()

	print("== layar masuk")
	var login: Control = load("res://scenes/login.tscn").instantiate()
	root.add_child(login)
	await create_timer(0.6).timeout
	_check(login._page == "home" and login._pages.home.visible and not login._pages.login.visible and not login._pages.register.visible and not login._pages.settings.visible, "beranda: hanya tombol utama yang tampil")
	_check(login._server_ok and login._server_row.visible and not login._server_box.visible, "server terjangkau: alamat menciut jadi baris bercentang")
	_check(login._home_status.text == "Server tersambung", "beranda memberi tahu server tersambung")
	_check(not login._btn_continue.visible, "tanpa sesi tersimpan tidak ada tombol Lanjutkan")
	login._open_form("login")
	_check(login._page == "login" and login._pages.login.visible and not login._pages.home.visible, "tombol Masuk membuka halaman Masuk")
	_check(login._pass_edit.secret, "kata sandi disamarkan")
	login._show_page("home")
	login._open_form("register")
	_check(login._page == "register" and login._pages.register.visible and login._rpass_edit.secret and login._rpass2_edit.secret, "tombol Daftar membuka halaman Daftar")
	login._show_page("settings")
	_check(login._pages.settings.visible and not login._pages.home.visible, "tombol Pengaturan membuka halaman Pengaturan")
	_check(login._version_label.text.begins_with("Aplikasi "), "Pengaturan menampilkan versi aplikasi")
	_check(not login._btn_update.visible and not login._update_status.visible, "tidak ada ajakan update bila versi sudah terbaru")
	_check(login._looks_like_email("a@b.id") and not login._looks_like_email("a@b") and not login._looks_like_email("a b@c.id") and not login._looks_like_email("@b.id"), "pemeriksaan ringan email di layar")
	login._on_change_server()
	_check(login._server_box.visible and not login._server_row.visible, "tombol Ubah membuka lagi alamat server")
	var good_url: String = Api.base_url
	login._url_edit.text = "http://127.0.0.1:1"
	await login._test_server()
	_check(not login._server_ok and login._server_msg.text.begins_with("Server tidak terjangkau"), "server salah: pesan galat dan alamat tetap terbuka")
	login._show_page("home")
	login._open_form("login")
	_check(login._page == "home" and login._home_status.text.begins_with("Server belum terhubung"), "tanpa server, Masuk/Daftar tidak terbuka")
	Api.base_url = good_url
	login._url_edit.text = good_url
	await login._test_server()
	_check(login._server_ok, "tes server ulang berhasil setelah alamat dibetulkan")
	login._open_form("register")
	_check(login._page == "register", "setelah server pulih, Daftar terbuka lagi")
	login.queue_free()

	var name := "Uji%d" % (Time.get_ticks_usec() % 100000)
	var pw := "sandi-uji-12345"
	var email := name.to_lower() + "@contoh.id"
	var reg: Dictionary = await Api.register(name, email, pw)
	_check(reg.ok, "daftar pemain " + name)
	if not reg.ok:
		return
	Api.token = str(reg.data.token)
	Session.set_player(reg.data.player)
	_check(Session.player.state.x == 5 and typeof(Session.player.state.x) == TYPE_INT, "state memakai int")

	var dup: Dictionary = await Api.register(name, "lain_" + email, pw)
	_check(not dup.ok and dup.status == 409, "nama kembar ditolak 409")

	print("== akun: email, login, logout")
	var dup_mail: Dictionary = await Api.register(name + "x", email.to_upper(), pw)
	_check(not dup_mail.ok and dup_mail.status == 409, "email kembar (beda huruf) ditolak 409")
	var weak: Dictionary = await Api.register(name + "y", "y" + email, "pendek")
	_check(not weak.ok and weak.status == 422, "kata sandi pendek ditolak 422")
	var no_mail: Dictionary = await Api.register(name + "z", "bukan-email", pw)
	_check(not no_mail.ok and no_mail.status == 422, "email rusak ditolak 422")
	var wrong: Dictionary = await Api.login(name, "salah-salah-salah")
	_check(not wrong.ok and wrong.status == 401, "kata sandi salah ditolak 401")
	var by_name: Dictionary = await Api.login(name, pw)
	_check(by_name.ok and str(by_name.data.token) != str(reg.data.token), "login dengan nama memberi token baru")
	var by_mail: Dictionary = await Api.login(email.to_upper(), pw)
	_check(by_mail.ok and str(by_mail.data.player.id) == str(reg.data.player.id), "login dengan email (huruf besar) memberi pemain yang sama")
	_check(str(by_mail.data.player.get("email", "")) == email, "email pemilik ikut di jawaban login")
	var first_token: String = Api.token
	Api.token = str(by_name.data.token)
	var out: Dictionary = await Api.logout()
	_check(out.ok and out.status == 204, "logout berhasil (204)")
	var after_out: Dictionary = await Api.get_me()
	_check(not after_out.ok and after_out.status == 401, "token setelah logout ditolak 401")
	Api.token = first_token
	_check((await Api.get_me()).ok, "token HP lain tetap berlaku setelah logout di HP ini")

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
		_check(scene._enemy_rig != null and scene._hero_rig != null, "arena 3D memuat model pahlawan dan musuh")
		_check(scene._skill_name("skill1") != "" and scene._skill_name("skill2") != "", "tombol skill memakai nama skill pahlawan")
		_check((scene._buttons["potion"] as Button).disabled, "ramuan nonaktif saat HP penuh")
		# Real-time: tombol yang masih cooldown diabaikan, musuh menyerang sendiri lewat sinkron.
		var t0 := Time.get_ticks_msec()
		var used_skill := false
		while not scene._finished and Time.get_ticks_msec() - t0 < 60000:
			if not used_skill and scene._cooldown_left("skill1") == 0:
				scene._on_action("skill1")
				used_skill = true
			scene._on_action("attack")
			await process_frame
		_check(used_skill, "Skill 1 bisa dipakai")
		_check((scene._buttons["skill2"] as Button) != null and (scene._buttons["defend"] as Button) != null, "tombol Bertahan dan Skill 2 ada")
		_check(scene._finished, "pertarungan real-time selesai (%s) dalam %d ms" % [scene._result, Time.get_ticks_msec() - t0])
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

	print("== pahlawan")
	var hs: Dictionary = await Api.set_hero("pemanah")
	_check(hs.ok and hs.data.state.hero == "pemanah", "server menyimpan pahlawan pilihan")
	var hbad: Dictionary = await Api.set_hero("naga")
	_check(not hbad.ok and hbad.status == 422, "pahlawan asing ditolak 422")
	if hs.ok:
		Session.merge_server_player(hs.data)
		_check(Session.player.state.hero == "pemanah", "pahlawan ikut digabung ke data lokal")
	await Api.set_hero("ksatria")
	var hme: Dictionary = await Api.get_me()
	if hme.ok:
		Session.merge_server_player(hme.data)
	_check(hme.ok and Session.player.state.hero == "ksatria", "pahlawan dikembalikan ke Ksatria")

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

	print("== tas & perlengkapan")
	_check(Session.player.state.has("equipment") and Session.player.state.equipment.weapon == "", "pemain baru belum memakai senjata")
	var eq_none: Dictionary = await Api.inventory_equip("pedang_besi")
	_check(not eq_none.ok and eq_none.status == 422, "memasang barang yang tidak dimiliki ditolak 422")
	var eq_potion: Dictionary = await Api.inventory_equip("ramuan")
	_check(not eq_potion.ok and eq_potion.status == 422, "ramuan bukan perlengkapan -> 422")
	var uneq_empty: Dictionary = await Api.inventory_unequip("weapon")
	_check(not uneq_empty.ok and uneq_empty.status == 422, "melepas slot kosong ditolak 422")
	var eq_alien: Dictionary = await Api.inventory_equip("naga")
	_check(not eq_alien.ok and eq_alien.status == 404, "barang asing 404")
	var bag_scene: Control = load("res://scenes/inventory.tscn").instantiate()
	root.add_child(bag_scene)
	await create_timer(0.8).timeout
	_check(bag_scene._list.get_child_count() >= 4, "layar tas menampilkan perlengkapan dan barang")
	_check(bag_scene._summary.text.contains(str(Session.player.name)), "layar tas menampilkan nama pemain")
	var hp_now: int = Session.player.state.hp
	var hp_max: int = Session.player.state.max_hp
	bag_scene._on_rest()
	while bag_scene._busy:
		await process_frame
	var rested: Dictionary = await Api.get_me()
	if hp_now < hp_max:
		_check(int(rested.data.state.hp) == hp_max, "istirahat memulihkan HP penuh di desa")
	else:
		_check(int(rested.data.state.hp) == hp_max, "HP sudah penuh, istirahat tidak mengubah apa pun")
	_check(Session.player.version == int(rested.data.version), "versi lokal sinkron setelah istirahat")
	var rest_full: Dictionary = await Api.rest()
	_check(not rest_full.ok and rest_full.status == 422, "istirahat saat HP penuh ditolak 422")
	var use_full: Dictionary = await Api.inventory_use("ramuan")
	_check(not use_full.ok and use_full.status == 422, "minum ramuan saat HP penuh ditolak 422")
	bag_scene.queue_free()
	await process_frame

	print("== pembaruan dalam aplikasi")
	const Updater = preload("res://scripts/updater.gd")
	_check(Updater.api_url_for("https://github.com/MiftahulKhoiri/Game_server/releases/latest") == "https://api.github.com/repos/MiftahulKhoiri/Game_server/releases/latest", "alamat API rilis diturunkan dari update_url")
	_check(Updater.api_url_for("https://contoh.com/unduh") == "", "alamat selain GitHub tidak dikenali")
	var rel := {"tag_name": "v9.9.9", "assets": [
		{"name": "catatan.txt", "browser_download_url": "https://x/c.txt"},
		{"name": "GamePetualang-v9.9.9-build5.apk", "browser_download_url": "https://x/a.apk", "size": 4096, "digest": "sha256:abc123"}]}
	var picked: Dictionary = Updater.pick_asset(rel)
	_check(picked.name.ends_with(".apk") and picked.url == "https://x/a.apk" and picked.size == 4096 and picked.sha256 == "abc123" and picked.tag == "v9.9.9", "memilih berkas .apk dari rilis")
	_check(Updater.pick_asset({"assets": [{"name": "a.txt", "browser_download_url": "https://x"}]}).is_empty(), "rilis tanpa APK -> kosong")
	_check(not Updater.supported(), "pasang otomatis tidak aktif di luar Android")
	var updater: Node = Updater.new()
	root.add_child(updater)
	var tmp := "user://uji_pembaruan.bin"
	var url: String = str(Api.base_url) + "/healthz"
	var got_progress := [false]
	updater.progress.connect(func(_r: int, _t: int) -> void: got_progress[0] = true)
	var dl_err: String = await updater.download({"url": url, "size": 0}, tmp)
	_check(dl_err == "" and FileAccess.file_exists(tmp), "unduh berkas dari server (%s)" % dl_err)
	var sz := FileAccess.open(tmp, FileAccess.READ).get_length()
	_check(Updater.verify({"size": sz, "sha256": ""}, tmp) != "", "berkas di bawah 1 KB ditolak")
	var big := FileAccess.open(tmp, FileAccess.WRITE)
	big.store_buffer(PackedByteArray([1, 2, 3, 4]).duplicate())
	for i in 300:
		big.store_buffer(PackedByteArray([7, 7, 7, 7]))
	big.close()
	var real_size := FileAccess.open(tmp, FileAccess.READ).get_length()
	var real_hash := FileAccess.get_sha256(tmp)
	_check(Updater.verify({"size": real_size, "sha256": real_hash}, tmp) == "", "berkas utuh lolos pemeriksaan ukuran + sha256")
	_check(Updater.verify({"size": real_size + 1, "sha256": ""}, tmp).contains("Ukuran"), "ukuran tidak cocok ditolak")
	_check(Updater.verify({"size": real_size, "sha256": "0".repeat(64)}, tmp).contains("Sidik"), "sha256 tidak cocok ditolak")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	updater.queue_free()
	await process_frame

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
	_check(q1.data.quests[1].status == "locked", "misi petani terkunci sebelum misi nenek selesai")
	Session.talk_npc = "petani"
	var dialog2: Control = load("res://scenes/dialog.tscn").instantiate()
	root.add_child(dialog2)
	await create_timer(0.8).timeout
	_check(not dialog2._action.visible and dialog2._text.text.contains("Nenek"), "petani minta bantu nenek dulu")
	dialog2.queue_free()
	await process_frame
	_check(Maps.npc_at(Maps.DEFAULT_MAP, 11, 6) == "petani", "petani berdiri di (11,6)")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 3, 6), "petak nenek tetap bagian peta (diblokir oleh gerak, bukan peta)")

	print("== pindah peta")
	var bm: Dictionary = (await Api.get_me()).data
	Session.set_player(bm)
	Session.player.state.map = Maps.DEFAULT_MAP
	Session.player.state.x = 12
	Session.player.state.y = 28
	Session.safe_steps = 100000
	var world2: Node2D = load("res://scenes/world.tscn").instantiate()
	root.add_child(world2)
	await process_frame
	world2._try_move(Vector2i.DOWN)  # (12,28) -> (12,29) = pintu ke perbatasan
	await create_timer(0.5).timeout
	_check(Session.player.state.map == Maps.PERBATASAN and Session.player.state.y == 1, "melewati gerbang selatan masuk Perbatasan (7,1)")
	await create_timer(2.5).timeout
	var moved: Dictionary = await Api.get_me()
	_check(moved.data.state.map == "perbatasan" and int(moved.data.state.y) == 1, "server menyimpan peta baru")
	world2.queue_free()
	await process_frame
	var pb: Dictionary = await Api.battle_start()
	_check(pb.ok and pb.data.battle.enemy_id == "goblin" or pb.ok and pb.data.battle.enemy_id == "serigala_hutan", "musuh di Perbatasan berbeda dari desa (%s)" % (pb.data.battle.enemy_id if pb.ok else "gagal"))
	if pb.ok:
		for i in 40:  # kabur dari pertarungan acak (peluang 60%, cooldown 3 d) supaya tidak menggantung
			var fl: Dictionary = await Api.battle_action("flee")
			if fl.ok and fl.data.status != "ongoing":
				break
			await create_timer(1.0).timeout
		var still: Dictionary = await Api.battle_get()
		_check(not still.ok, "pertarungan acak selesai sebelum uji bos")
	var away: Dictionary = await Api.battle_start(true)
	_check(not away.ok and away.status == 422, "bos tidak bisa dipanggil jauh dari singgasana")
	var cur: Dictionary = (await Api.get_me()).data
	Session.set_player(cur)
	var at_throne: Dictionary = Session.player.state.duplicate(true)
	at_throne.map = Maps.GUA
	at_throne.x = 7
	at_throne.y = 14
	var sv: Dictionary = await Api.save(Session.player.version, at_throne)
	_check(sv.ok, "simpan posisi di singgasana")
	var boss: Dictionary = await Api.battle_start(true)
	_check(boss.ok and boss.data.battle.enemy_id == "raja_goblin", "singgasana memanggil Raja Goblin")
	if boss.ok:
		var bscene: Control = load("res://scenes/battle.tscn").instantiate()
		Session.merge_server_player(boss.data.player)
		Session.battle = boss.data.battle
		root.add_child(bscene)
		await process_frame
		_check(bscene._enemy_rig != null and bscene._enemy_rig.name == "raja_goblin" and bscene._hero_rig != null, "arena 3D memuat ksatria dan Raja Goblin")
		bscene.queue_free()
		await process_frame

	var merged := {"state": {"level": 3, "xp": 4, "hp": 10, "max_hp": 46, "gold": 9, "equipment": {"weapon": "pedang_besi", "armor": ""}, "map": "desa_awal", "x": 1, "y": 1, "inventory": [{"id": "ramuan", "qty": 2.0}]}, "version": 9.0}
	Session.player.state.x = 8
	Session.merge_server_player(merged)
	_check(Session.player.state.x == 8 and Session.player.state.level == 3, "merge: posisi lokal tetap, statistik ikut server")
	_check(Session.player.state.equipment.weapon == "pedang_besi", "merge: perlengkapan ikut server")
	_check(typeof(Session.player.state.inventory[0].qty) == TYPE_INT and Session.player.version == 9, "merge: angka menjadi int")
	Session.merge_server_player(merged, true)
	_check(Session.player.state.x == 1, "merge dengan adopt_position memakai posisi server")

	print("== dunia 3D: gerak, tabrakan, model")
	var Movement = load("res://scripts/movement.gd")
	var WorldBuild = load("res://scripts/world_build.gd")
	var Models = load("res://scripts/models.gd")
	# Titik tengah petak awal bebas tabrakan; tembok/air memblokir.
	_check(not Movement.collides(Maps.DEFAULT_MAP, Vector2(5.5, 5.5)), "tengah petak awal bebas tabrakan")
	_check(Movement.collides(Maps.DEFAULT_MAP, Vector2(-0.5, 5.5)), "di luar peta menabrak")
	var slid: Vector2 = Movement.move(Maps.DEFAULT_MAP, Vector2(5.5, 5.5), Vector2(0.4, 0.0))
	_check(slid.x > 5.5 and not Movement.collides(Maps.DEFAULT_MAP, slid), "bergerak bebas di tanah lapang")
	var far: Vector2 = Vector2(5.5, 5.5)
	for i in 400:  # jalan lurus ke atas sampai mentok: tidak boleh keluar dari peta
		far = Movement.move(Maps.DEFAULT_MAP, far, Vector2(0.0, -0.15))
	_check(not Movement.collides(Maps.DEFAULT_MAP, far) and far.y >= 0.0, "tidak menembus batas peta (z=%.2f)" % far.y)
	var npc_tile := Vector2i(3, 6)
	_check(Maps.npc_at(Maps.DEFAULT_MAP, npc_tile.x, npc_tile.y) != "", "ada NPC di (3,6)")
	var spot: Vector2 = Movement.safe_spot(Maps.DEFAULT_MAP, npc_tile)
	_check(not Movement.collides(Maps.DEFAULT_MAP, spot), "safe_spot menghindari petak NPC")
	_check(Movement.tile_of(Vector2(6.99, 5.01)) == Vector2i(6, 5), "tile_of memakai floor")

	for mid in [Maps.DEFAULT_MAP, Maps.PERBATASAN, Maps.GUNUNG, Maps.GUA]:
		var built: Node3D = WorldBuild.build(mid)
		_check(built != null and built.get_child_count() > 3, "peta 3D '%s' terbangun (%d simpul)" % [mid, built.get_child_count() if built != null else 0])
		built.free()
	for mid in [Maps.DEFAULT_MAP, Maps.PERBATASAN, Maps.GUNUNG, Maps.GUA]:
		_check(WorldBuild.environment_for(mid) != null, "lingkungan 3D '%s'" % mid)

	var model_ids := ["ksatria", "pendekar_kapak", "pemanah", "pendekar_tombak", "nenek_penjual", "petani", "goblin", "goblin_penjaga", "raja_goblin", "ogre_batu",
		"golem_kerikil", "golem_lava", "tikus_sawah", "babi_hutan", "serigala_hutan", "ular_sawah", "belalang_raksasa", "kelelawar_gua"]
	var bad_models: Array[String] = []
	for mdl in model_ids:
		var node: Node3D = Models.create(mdl)
		if node == null or node.get_child_count() == 0:
			bad_models.append(mdl)
		if node != null:
			node.free()
	_check(bad_models.is_empty(), "semua %d model 3D terbuat %s" % [model_ids.size(), str(bad_models)])
	# Model berrangka + animasi (idle/walk/attack/hurt/die) dari Blender.
	for mdl in ["pendekar_kapak", "pemanah", "pendekar_tombak", "petani", "nenek_penjual", "goblin", "goblin_penjaga", "ogre_batu", "golem_kerikil", "golem_lava", "raja_goblin", "kelelawar_gua"]:
		var rm: Node3D = Models.create(mdl)
		var names: Dictionary = rm._anim_names if rm.anim_player != null else {}
		var lengkap := true
		for key: String in ["idle", "walk", "attack", "hurt", "die"]:
			if not names.has(key):
				lengkap = false
		_check(Models.has_glb(mdl) and rm.anim_player != null and lengkap, "model '%s' berrangka dengan 5 klip animasi %s" % [mdl, str(names.keys())])
		rm.play_attack()
		rm.play_hurt()
		rm.play_die()
		rm.free()
	# Hewan (Quaternius): hanya klip idle + jalan; serang/terkena/mati lewat gerak tambahan model_rig.
	for mdl in ["tikus_sawah", "belalang_raksasa", "ular_sawah", "babi_hutan", "serigala_hutan"]:
		var am: Node3D = Models.create(mdl)
		var anames: Dictionary = am._anim_names if am.anim_player != null else {}
		_check(Models.has_glb(mdl) and anames.has("idle") and anames.has("walk") and am.pivots.has("body"), "hewan '%s' berrangka dengan klip idle dan jalan %s" % [mdl, str(anames.keys())])
		am.play_attack()
		am.play_hurt()
		am.play_die()
		am.free()

	Session.offline = true
	Session.player = {"name": "Uji", "state": {"map": Maps.DEFAULT_MAP, "x": 5, "y": 5, "fx": 5.5, "fz": 5.5, "yaw": 0.0, "hp": 30, "max_hp": 30, "level": 1, "xp": 0, "gold": 0, "inventory": [], "equipment": {"weapon": "", "armor": ""}}, "version": 1}
	var w3: Node = load("res://scenes/world3d.tscn").instantiate()
	root.add_child(w3)
	await process_frame
	await process_frame
	_check(w3._player != null and w3._camera != null, "adegan dunia 3D termuat")
	w3._pos = Vector2(7.5, 5.5)
	w3._sync_state()
	_check(Session.player.state.x == 7 and absf(float(Session.player.state.fx) - 7.5) < 0.001, "posisi 3D tersalin ke data pemain (petak 7, fx 7.5)")

	# Dunia hidup: siang-malam, hujan, NPC.
	const Atmo = preload("res://scripts/atmosphere.gd")
	var env_a: Environment = w3._env.environment
	Atmo.hour_override = 12.0
	Atmo.rain = 0.0
	Atmo.apply(env_a, w3._sun, w3._atmo_base, Maps.DEFAULT_MAP)
	var noon_energy: float = w3._sun.light_energy
	var noon_top: Color = (env_a.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	var noon_fog: float = env_a.fog_density
	Atmo.hour_override = 0.0
	Atmo.apply(env_a, w3._sun, w3._atmo_base, Maps.DEFAULT_MAP)
	var night_top: Color = (env_a.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	_check(w3._sun.light_energy < noon_energy * 0.8, "malam: cahaya matahari/bulan lebih redup dari siang")
	_check(night_top.get_luminance() < noon_top.get_luminance() * 0.5, "malam: langit lebih gelap dari siang")
	_check(env_a.ambient_light_energy >= 0.3, "malam: cahaya ambient cukup agar tetap bisa dimainkan")
	Atmo.hour_override = 12.0
	Atmo.rain = 1.0
	Atmo.apply(env_a, w3._sun, w3._atmo_base, Maps.DEFAULT_MAP)
	_check(w3._sun.light_energy < noon_energy and env_a.fog_density > noon_fog, "hujan: cahaya lebih redup dan kabut lebih tebal")
	_check(Atmo.label().contains("hujan"), "label waktu menyebut hujan")
	Atmo.set_rain(w3._rain, Maps.DEFAULT_MAP)
	_check(w3._rain.emitting, "hujan turun di luar ruangan")
	Atmo.set_rain(w3._rain, Maps.GUA)
	_check(not w3._rain.emitting, "tidak hujan di Gua Batu")
	var gua_before: float = w3._sun.light_energy
	Atmo.apply(env_a, w3._sun, w3._atmo_base, Maps.GUA)
	_check(is_equal_approx(w3._sun.light_energy, gua_before), "Gua Batu tidak terpengaruh waktu/cuaca")
	Atmo.hour_override = -1.0
	Atmo.rain = 0.0
	Atmo.apply(env_a, w3._sun, w3._atmo_base, Maps.DEFAULT_MAP)
	_check(Atmo.hour() >= 0.0 and Atmo.hour() < 24.0 and not Atmo.raining_now(), "jam permainan wajar dan blok cuaca pertama cerah")
	# NPC: menoleh ke pemain yang dekat, dan tetap di dalam petaknya.
	w3._pos = Vector2(3.5, 8.5)  # selatan Nenek (3,6)
	for i in 90:
		w3._update_npcs(0.05)
	var nenek: Node3D = w3._npc_models["nenek_penjual"]
	var home := Vector2(3.5, 6.5)
	var np := Vector2(nenek.position.x, nenek.position.z)
	_check(np.distance_to(home) < 0.01, "NPC dekat pemain berdiri di tempatnya")
	_check(absf(angle_difference(nenek.rotation.y, 0.0)) < 0.15, "NPC menoleh ke arah pemain (selatan)")
	w3._pos = Vector2(13.5, 17.5)  # jauh: NPC boleh berjalan pelan
	var max_off := 0.0
	for i in 400:
		w3._update_npcs(0.05)
		var p2 := Vector2(nenek.position.x, nenek.position.z)
		max_off = maxf(max_off, p2.distance_to(home))
	_check(max_off > 0.05 and max_off <= 0.36, "NPC berjalan pelan tapi tetap di dalam petaknya (geser %.2f)" % max_off)
	# Warga desa: berjalan bebas, hanya di petak jalan/rumput/bunga, dan tidak menabrak pemain.
	var wcount := 0
	for d: Dictionary in Maps.WARGA:
		if d.map == Maps.DEFAULT_MAP:
			wcount += 1
			_check(Maps.warga_free(Maps.DEFAULT_MAP, d.pos), "titik asal warga %s berada di petak bebas" % d.name)
	_check(wcount >= 8 and w3._warga.size() == wcount, "%d warga desa muncul di dunia 3D" % w3._warga.size())
	w3._pos = Vector2(24.0, 28.0)  # jauh dari semua warga
	var start_pos: Array[Vector2] = []
	var best_move: Array[float] = []
	for w in w3._warga:
		start_pos.append(w.pos)
		best_move.append(0.0)
	var warga_ok := true
	var model_walked := false
	var min_gap := 99.0
	for i in 1800:  # 90 detik
		w3._update_npcs(0.05)
		for k in w3._warga.size():
			var w = w3._warga[k]
			if not Maps.warga_free(Maps.DEFAULT_MAP, w.pos):
				warga_ok = false
			if w.walking and "moving" in w.model and w.model.moving:
				model_walked = true
			best_move[k] = maxf(best_move[k], w.pos.distance_to(start_pos[k]))
			if w.pos.distance_to(w.home) > w.radius + 0.5:
				warga_ok = false
			for j in range(k + 1, w3._warga.size()):
				min_gap = minf(min_gap, w.pos.distance_to(w3._warga[j].pos))
	var movers := 0
	for m in best_move:
		if m > 1.5:
			movers += 1
	_check(warga_ok, "warga tidak pernah masuk pagar/air/rumah atau keluar dari jari-jarinya")
	_check(movers >= w3._warga.size() - 2, "hampir semua warga benar-benar berjalan jauh (%d dari %d)" % [movers, w3._warga.size()])
	_check(min_gap > 0.35, "warga tidak menumpuk satu sama lain (jarak terdekat %.2f)" % min_gap)
	# Pemain berdiri di tengah alun-alun: warga tidak menembus pemain.
	w3._pos = Vector2(12.5, 8.5)
	var near_player := 99.0
	for i in 1200:
		w3._update_npcs(0.05)
		for w in w3._warga:
			near_player = minf(near_player, w.pos.distance_to(w3._pos))
	_check(near_player > 0.6, "warga menjaga jarak dari pemain (terdekat %.2f)" % near_player)
	_check(model_walked, "model warga memakai animasi jalan saat bergerak")
	w3._pos = Vector2(7.5, 5.5)
	_check(w3._menu != null and not w3._menu.is_open, "menu dalam game ada dan tertutup")
	w3._toggle_menu()
	_check(w3._menu.is_open and w3._locked, "tombol Menu membuka menu dan menahan gerak")
	w3._menu._show_page(false)
	_check(w3._menu._settings.visible and not w3._menu._main.visible, "halaman Pengaturan terbuka dari menu")
	w3._toggle_menu()  # tombol kembali: dari Pengaturan balik ke menu utama
	_check(w3._menu.is_open and w3._menu._main.visible, "tombol kembali dari Pengaturan ke menu utama")
	Session.quality = 2
	w3._apply_quality()
	_check(w3._sun.shadow_enabled, "kualitas Tinggi menyalakan bayangan")
	Session.quality = 0
	w3._apply_quality()
	_check(not w3._sun.shadow_enabled, "kualitas Hemat mematikan bayangan")
	Session.quality = 1
	w3._apply_quality()
	w3._toggle_menu()  # dari menu utama: menutup
	_check(not w3._menu.is_open and not w3._locked, "menu bisa ditutup dan gerak berlanjut")
	# Profil dan pilihan pahlawan (mode uji: pilihan tersimpan lokal).
	Session.offline = true
	w3._toggle_menu()
	w3._menu.profile_requested.emit()
	_check(w3._profile.is_open and not w3._menu.is_open, "Profil terbuka dari menu")
	_check(w3._profile._tabs.size() == 4 and w3._profile._preview_rig != null, "Profil memuat 4 pahlawan dengan pratinjau 3D")
	w3._profile._select(2)
	_check(w3._profile._preview_rig.name == "pemanah", "pratinjau 3D mengikuti pilihan")
	w3._profile._on_use()
	await process_frame
	_check(str(Session.player.state.hero) == "pemanah" and w3._player.name == "pemanah", "memilih Pemanah mengganti model di dunia")
	w3._toggle_menu()  # tombol kembali menutup Profil
	_check(not w3._profile.is_open and not w3._locked, "tombol kembali menutup Profil dan gerak berlanjut")
	Session.offline = false
	w3.queue_free()
	await process_frame
	Session.offline = false

	print("== token salah")
	Api.token = "salah"
	var bad: Dictionary = await Api.get_me()
	_check(not bad.ok and bad.status == 401, "token salah ditolak 401")
