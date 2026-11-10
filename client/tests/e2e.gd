extends SceneTree
## Uji ujung-ke-ujung klien <-> server. Dijalankan lewat: make client-test
## (butuh server Go yang hidup di GAME_URL, bawaan http://127.0.0.1:8099).

const Maps = preload("res://scripts/maps.gd")
const Movement = preload("res://scripts/movement.gd")
const Version = preload("res://scripts/version.gd")

var _failed := false
var Api: Node  # autoload tidak dikenal saat skrip utama dikompilasi; ambil dari pohon
var Session: Node
var Sound: Node
var Patcher: Node


func _initialize() -> void:
	await _run()
	quit(1 if _failed else 0)


## Apakah ada mesh di bawah n yang materialnya punya tekstur warna dasar.
func _punya_tekstur(n: Node) -> bool:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
				return true
	for c in n.get_children():
		if _punya_tekstur(c):
			return true
	return false


## Semua permukaan mesh pahlawan memakai bahan override toon + cahaya tepi.
func _bahan_pahlawan_ok(n: Node) -> bool:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as StandardMaterial3D
			if m == null or m.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON or not m.rim_enabled:
				return false
	for c in n.get_children():
		if not _bahan_pahlawan_ok(c):
			return false
	return true


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
	Patcher = root.get_node("Patcher")
	Session = root.get_node("Session")
	Sound = root.get_node("Sound")
	print("== peta")
	var WB: GDScript = load("res://scripts/world_build.gd")
	for y in Maps.height(Maps.DEFAULT_MAP):
		_check(Maps.rows(Maps.DEFAULT_MAP)[y].length() == 85, "baris peta %d lebar 85" % y)
	_check(Maps.walkable(Maps.DEFAULT_MAP, Maps.SPAWN.x, Maps.SPAWN.y), "titik awal bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 0, 0), "pohon di tepi tidak bisa dilewati")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, -1, 3), "luar peta tidak bisa dilewati")
	var sungai_membelah := false
	for yy in range(1, 43):
		var seluruh_air := true
		for xx in range(1, 44):
			if Maps.tile_at(Maps.DEFAULT_MAP, xx, yy) != "~":
				seluruh_air = false
		sungai_membelah = sungai_membelah or seluruh_air
	_check(not sungai_membelah and Maps.walkable(Maps.DEFAULT_MAP, 22, 24) and Maps.walkable(Maps.DEFAULT_MAP, 3, 24), "sungai tidak membelah desa: jalan tengah dan sisi barat tetap terbuka")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 2, 30) and not Maps.walkable(Maps.DEFAULT_MAP, 6, 26) and not Maps.walkable(Maps.DEFAULT_MAP, 38, 33), "parit mengelilingi ladang tidak bisa dilewati")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 11, 29) and Maps.walkable(Maps.DEFAULT_MAP, 11, 37) and Maps.walkable(Maps.DEFAULT_MAP, 33, 29) and Maps.walkable(Maps.DEFAULT_MAP, 33, 37), "jembatan parit di depan pintu tiap ladang bisa dilewati")
	_check(Maps.tile_at(Maps.DEFAULT_MAP, 24, 45) == "J" and Maps.tile_at(Maps.DEFAULT_MAP, 25, 46) == "J" and not Maps.walkable(Maps.DEFAULT_MAP, 24, 46), "pos jaga di timur gapura menghalangi jalan")
	_check(Maps.tile_at(Maps.DEFAULT_MAP, 5, 10) == "C" and Maps.tile_at(Maps.DEFAULT_MAP, 39, 11) == "C", "kandang ayam di tiap kandang berpagar")
	var tenda_ok := true
	for rr: Dictionary in WB._kelompok(Maps.tiles_of(Maps.DEFAULT_MAP, "A")):
		tenda_ok = tenda_ok and WB.arah_kecil("A", rr) == Vector2i(1, 0) and Maps.walkable(Maps.DEFAULT_MAP, rr.x1 + 1, rr.z0)
	_check(tenda_ok, "pintu tenda basecamp menghadap timur (api unggun dan jalan utama) dan depannya terbuka")
	var jalan_ok := true
	var rumah_tanpa_jalan := ""
	var rows_d := Maps.rows(Maps.DEFAULT_MAP)
	var jalan_seed := Vector2i(22, 25)
	var seen_j := {jalan_seed: true}
	var q_j: Array[Vector2i] = [jalan_seed]
	while not q_j.is_empty():
		var cj: Vector2i = q_j.pop_back()
		for dj: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nj := cj + dj
			if not seen_j.has(nj) and Maps.tile_at(Maps.DEFAULT_MAP, nj.x, nj.y) == "=":
				seen_j[nj] = true
				q_j.append(nj)
	for zz in rows_d.size():
		for xx in rows_d[zz].length():
			if rows_d[zz][xx] == "D" and not seen_j.has(Vector2i(xx, zz + 1)):
				jalan_ok = false
				rumah_tanpa_jalan = "(%d,%d)" % [xx, zz]
	_check(jalan_ok, "tiap rumah punya jalan tanah yang tersambung ke jalan utama %s" % rumah_tanpa_jalan)
	_check(seen_j.has(Vector2i(23, 45)) or seen_j.has(Vector2i(22, 45)), "pos jaga dan basecamp juga tersambung ke jalan utama")
	var camp := {"A": 0, "U": 0, "Q": 0, "Y": 0}
	for row in Maps.rows(Maps.DEFAULT_MAP):
		for ch in camp:
			camp[ch] += row.count(ch)
	_check(camp.A == 8 and camp.U == 1 and camp.Q == 1 and camp.Y == 1, "basecamp pahlawan: dua tenda, api unggun, dummy, tiang panji")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 22, 13), "sumur menghalangi")
	_check(not Maps.walkable(Maps.DEFAULT_MAP, 3, 9) and Maps.walkable(Maps.DEFAULT_MAP, 11, 13), "pagar kandang menghalangi, gerbang kandang terbuka")
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
	_check(not Maps.walkable(Maps.PERBATASAN, 26, 14), "tembok batu menghalangi")
	_check(not Maps.walkable(Maps.GUNUNG, 0, 5) and Maps.walkable(Maps.GUNUNG, 22, 0), "batu besar menghalangi, pintu gunung terbuka")
	_check(Maps.ENCOUNTER_TILES.contains(Maps.tile_at(Maps.GUNUNG, 6, 8)), "kerikil gunung tempat pertemuan musuh")

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
	# Roadmap no. 14: variasi pakaian.
	var of: Dictionary = await Api.set_outfit(2)
	_check(of.ok and int(of.data.state.get("outfit", 0)) == 2, "server menyimpan pakaian pilihan (outfit 2)")
	var ofbad: Dictionary = await Api.set_outfit(9)
	_check(not ofbad.ok and ofbad.status == 422, "pakaian di luar rentang ditolak 422")
	if of.ok:
		Session.merge_server_player(of.data)
		_check(int(Session.player.state.outfit) == 2, "pakaian ikut digabung ke data lokal")
	# Roadmap no. 139, 145, 150: tempa, pohon kemampuan, pencapaian (aturan di server).
	var g_pr: Dictionary = await Api.progress_get()
	_check(g_pr.ok and g_pr.data.recipes.size() >= 5 and g_pr.data.talents.size() >= 5 and g_pr.data.achievements.size() >= 8, "server memberi resep tempa, pohon kemampuan, dan daftar pencapaian")
	var g_cr: Dictionary = await Api.craft("pedang_besi", 1)
	_check(not g_cr.ok and g_cr.status == 422, "menempa tanpa bahan ditolak 422")
	var g_tl: Dictionary = await Api.learn_talent("mata_elang")
	_check(not g_tl.ok and g_tl.status == 422, "kemampuan cabang tanpa prasyarat/poin ditolak 422")
	var g_ac: Dictionary = await Api.claim_achievement("level_10")
	_check(not g_ac.ok and g_ac.status == 422, "hadiah pencapaian yang belum terbuka ditolak 422")
	# Roadmap no. 127: rumah pemain dibeli di server; tanpa rumah tidak boleh menyimpan posisi di dalamnya.
	var r127_hb: Dictionary = await Api.house_buy()
	_check(not r127_hb.ok and r127_hb.status == 422, "beli rumah tanpa 500 emas ditolak 422")
	var r127_me_h: Dictionary = await Api.get_me()
	if r127_me_h.ok:
		Session.merge_server_player(r127_me_h.data)
		var r127_st_h: Dictionary = Session.player.state.duplicate(true)  # sudah dinormalkan (angka bulat)
		r127_st_h.map = Maps.RUMAH_PEMAIN
		r127_st_h.x = 4
		r127_st_h.y = 5
		r127_st_h.fx = 4.5
		r127_st_h.fz = 5.5
		var r127_sv_h: Dictionary = await Api.save(int(r127_me_h.data.version), r127_st_h)
		_check(not r127_sv_h.ok and r127_sv_h.status == 422, "masuk rumah pemain tanpa memilikinya ditolak server (%d %s)" % [int(r127_sv_h.status), str(r127_sv_h.get("error", ""))])
	var of0: Dictionary = await Api.set_outfit(0)
	if of0.ok:
		Session.merge_server_player(of0.data)

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
	# Dialog warga desa: mengikuti tahap cerita utama.
	var WD = load("res://scripts/warga_dialog.gd")
	_check(WD.stage_from_quests([]) == 0, "tanpa misi tuntas: tahap cerita 0")
	var qs := [{"id": "selamatkan_nenek", "status": "claimed"}, {"id": "selamatkan_petani", "status": "done"}, {"id": "usir_ogre", "status": "active"}, {"id": "hentikan_raja_goblin", "status": "locked"}]
	_check(WD.stage_from_quests(qs) == 2, "dua misi utama tuntas (klaim atau siap klaim): tahap 2")
	qs[2].status = "claimed"
	qs[3].status = "claimed"
	_check(WD.stage_from_quests(qs) == 4, "semua misi utama tuntas: tahap 4")
	qs[1].status = "active"
	_check(WD.stage_from_quests(qs) == 1, "tahap berhenti di misi utama pertama yang belum tuntas")
	var all_lines := true
	var diff_lines := true
	for wid: String in WD.WARGA:
		var stages: Array = WD.WARGA[wid].stages
		all_lines = all_lines and stages.size() == 5
		for lines: Array in stages:
			all_lines = all_lines and lines.size() >= 1
			for l in lines:
				all_lines = all_lines and str(l).length() > 5
		if wid != "ayam":
			diff_lines = diff_lines and WD.line(wid, 0, 0) != WD.line(wid, 4, 0)
	_check(all_lines, "setiap warga punya kalimat untuk kelima tahap cerita")
	_check(diff_lines, "kalimat warga berubah mengikuti tahap cerita")
	_check(WD.line("bu_sari", 1, 0) != WD.line("bu_sari", 1, 1), "kalimat warga bergantian tiap kali diajak bicara")
	var dialog_ok := true
	for d: Dictionary in Maps.WARGA:
		dialog_ok = dialog_ok and (WD.has_warga(str(d.id)) or d.has("toko"))  # penjaga toko membuka toko, bukan dialog
	_check(dialog_ok, "semua warga di peta punya dialog")
	Session.talk_npc = "warga:bu_sari"
	Session.talk_counts["warga:bu_sari"] = 1
	var dialog3: Control = load("res://scenes/dialog.tscn").instantiate()
	root.add_child(dialog3)
	await create_timer(0.8).timeout
	_check(dialog3._name_label.text == "Bu Sari  ·  Juru Masak  ·  Kenalan" and not dialog3._action.visible and dialog3._text.text.ends_with(WD.line("bu_sari", 0, 0)), "bicara dengan Bu Sari: nama, peran, keakraban, dan kalimat tahap 0, tanpa tombol misi")
	# Roadmap no. 58-59: server mengingat pembicaraan; pertemuan pertama = berkenalan.
	_check(Session.rep_talks("bu_sari") == 1 and Session.rep_points("bu_sari") == 1 and dialog3._text.text.begins_with("Senang berkenalan"), "Bu Sari mengingat pertemuan pertama (bicara 1x, keakraban 1, sapaan berkenalan)")
	var tk2: Dictionary = await Api.warga_talk("bu_sari")
	_check(tk2.ok and int(tk2.data.state.reputation.bu_sari.t) == 2 and int(tk2.data.state.reputation.bu_sari.p) == 1, "bicara lagi segera: diingat (2x), keakraban tidak naik (jeda)")
	var tkbad: Dictionary = await Api.warga_talk("naga")
	_check(not tkbad.ok and tkbad.status == 422, "warga asing ditolak 422")
	if tk2.ok:
		Session.merge_server_player(tk2.data)
	var spk: Node3D = dialog3._speaker
	_check(spk != null and spk._actions != null and str(spk._actions.call("current")) == "bicara", "dialog warga: model 3D-nya tampil dan berbicara (bukan lingkaran huruf)")
	dialog3.queue_free()
	await process_frame
	_check(Maps.npc_at(Maps.DEFAULT_MAP, 11, 6) == "petani", "petani berdiri di (11,6)")
	_check(Maps.walkable(Maps.DEFAULT_MAP, 3, 6), "petak nenek tetap bagian peta (diblokir oleh gerak, bukan peta)")

	print("== pindah peta")
	var bm: Dictionary = (await Api.get_me()).data
	Session.set_player(bm)
	Session.player.state.map = Maps.DEFAULT_MAP
	Session.player.state.x = 22
	Session.player.state.y = 48
	Session.safe_steps = 100000
	var world2: Node2D = load("res://scenes/world.tscn").instantiate()
	root.add_child(world2)
	await process_frame
	world2._try_move(Vector2i.DOWN)  # (22,48) -> (22,49) = pintu ke perbatasan
	await create_timer(0.5).timeout
	_check(Session.player.state.map == Maps.PERBATASAN and Session.player.state.y == 1, "melewati gerbang selatan masuk Perbatasan (22,1)")
	await create_timer(2.5).timeout
	var moved: Dictionary = await Api.get_me()
	_check(moved.data.state.map == "perbatasan" and int(moved.data.state.y) == 1, "server menyimpan peta baru")
	world2.queue_free()
	await process_frame
	var pb: Dictionary = await Api.battle_start()
	_check(pb.ok and ["tikus_sawah", "belalang_raksasa", "ular_hutan", "serigala_hutan"].has(str(pb.data.battle.enemy_id)), "musuh di hutan Perbatasan adalah hewan hutan (%s)" % (pb.data.battle.enemy_id if pb.ok else "gagal"))
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
		"golem_kerikil", "golem_lava", "goblin_pemburu", "orc_gua", "orc_penjaga", "orc_buas", "ular_hutan", "serigala_alfa", "tikus_sawah", "babi_hutan", "serigala_hutan", "ular_sawah", "belalang_raksasa", "kelelawar_gua"]
	var bad_models: Array[String] = []
	for mdl in model_ids:
		var node: Node3D = Models.create(mdl)
		if node == null or node.get_child_count() == 0:
			bad_models.append(mdl)
		if node != null:
			node.free()
	_check(bad_models.is_empty(), "semua %d model 3D terbuat %s" % [model_ids.size(), str(bad_models)])
	# NPC dan warga KayKit harus membawa tekstur (tanpa tekstur modelnya tampil putih polos).
	var polos: Array[String] = []
	for mdl in ["nenek_penjual", "petani", "warga_ibu", "warga_ibu2", "warga_bapak", "warga_bapak2", "anak_desa"]:
		var tn: Node3D = Models.create(mdl)
		if not _punya_tekstur(tn):
			polos.append(mdl)
		tn.free()
	_check(polos.is_empty(), "model NPC/warga bertekstur (tidak putih polos) %s" % str(polos))
	# Model berrangka + animasi (idle/walk/attack/hurt/die) dari Blender.
	# Pahlawan (roadmap no. 1): bahan toon + cahaya tepi + tekstur palet tajam pada semua permukaan.
	var hero_bad: Array[String] = []
	for hid in Models.HEROES:
		var hn: Node3D = Models.create(hid)
		if not _punya_tekstur(hn) or not _bahan_pahlawan_ok(hn):
			hero_bad.append(hid)
		hn.free()
	_check(hero_bad.is_empty(), "model pahlawan bertekstur dengan bahan toon + cahaya tepi %s" % str(hero_bad))
	# Roadmap no. 14-18: pakaian dan perlengkapan terlihat di model.
	var dk: Node3D = Models.create("ksatria")
	Models.dress(dk, 1, {"weapon": "pedang_rune", "armor": "zirah_besi", "helmet": "helm_besi"})
	var helm_bawaan := dk.find_child("Knight_Helmet", true, false) as Node3D
	var helm_baru := dk.find_child("helm", true, false)
	var bahu := dk.find_children("bahu", "", true, false)
	var pedang := dk.find_child("1H_Sword", true, false) as MeshInstance3D
	var jubah := dk.find_child("Knight_Cape", true, false) as MeshInstance3D
	var pm := pedang.get_surface_override_material(0) as StandardMaterial3D if pedang != null else null
	var jm := jubah.get_surface_override_material(0) as StandardMaterial3D if jubah != null else null
	_check(helm_bawaan != null and not helm_bawaan.visible and helm_baru != null, "helm dipakai: helm bawaan disembunyikan, helm baru terpasang")
	_check(bahu.size() == 2, "zirah besi memasang 2 bantalan bahu (%d)" % bahu.size())
	_check(pm != null and pm.emission_enabled, "pedang rune berpendar")
	_check(jm != null and jm.albedo_color.r > jm.albedo_color.b, "pakaian Merah Kerajaan mewarnai jubah")
	Models.dress(dk, 0, {"weapon": "", "armor": "", "helmet": ""})
	_check(helm_bawaan.visible and dk.find_child("helm", true, false) == null and not pm.emission_enabled
		and dk.find_children("bahu", "", true, false).is_empty(), "lepas semua: kembali ke tampilan asli")
	_check(jm.albedo_color.is_equal_approx(jm.get_meta("base_col")), "pakaian Asli memakai warna tekstur asli")
	dk.free()
	# Roadmap no. 6-7, 13: klip jalan mengikuti kecepatan, lari condong, aksi ambil.
	var rk: Node3D = Models.create("pemanah")
	rk.moving = true
	rk.move_speed = 1.0
	rk._process(0.016)
	var pelan: float = rk.anim_player.speed_scale
	rk.move_speed = 3.3
	rk._process(0.016)
	_check(pelan < 1.0 and rk.anim_player.speed_scale > 2.0 and rk.is_running(), "klip jalan mengikuti kecepatan (%.2f -> %.2f), lari terdeteksi" % [pelan, rk.anim_player.speed_scale])
	_check(rk._actions != null and float(rk._actions.get("lean")) > 0.5, "lari: badan condong ke depan")
	rk.moving = false
	rk._process(0.016)
	_check(is_equal_approx(rk.anim_player.speed_scale, 1.0) and float(rk._actions.get("lean")) == 0.0, "diam: klip kembali kecepatan normal tanpa condong")
	_check(rk.play_action("ambil"), "aksi ambil barang tersedia")
	rk.free()
	# Roadmap no. 61-88: warna hewan, musuh baru, pemalu, takut, wilayah, patroli.
	var q_ay: Node3D = Models.create("tikus_sawah")
	var q_ay_ok := false
	for q_mi in q_ay.find_children("*", "MeshInstance3D", true, false):
		var q_am := (q_mi as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		if q_am != null and q_am.albedo_color.b < 0.5 and q_am.albedo_color.r > 0.8:
			q_ay_ok = true
	_check(q_ay_ok, "Ayam Liar berwarna kuning, bukan putih polos")
	q_ay.free()
	var q_orw: Node3D = Models.create("ogre_rawa")
	_check(q_orw != null and q_orw.name == "ogre_rawa", "model Ogre Rawa ada")
	q_orw.free()
	var q_RoamerC = load("res://scripts/roamer.gd")
	var q_pm_map := Maps.PERBATASAN
	var q_mspot := Vector2.ZERO
	for q_my in range(6, 20):
		for q_mx in range(2, 40):
			var q_c := Vector2(q_mx + 0.5, q_my + 0.5)
			if q_mspot == Vector2.ZERO and Maps.roam_free(q_pm_map, q_c) and Maps.roam_free(q_pm_map, q_c + Vector2(2, 0)) \
					and Maps.roam_free(q_pm_map, q_c + Vector2(-2, 0)) and Maps.roam_free(q_pm_map, q_c + Vector2(0, 2)) and Maps.roam_free(q_pm_map, q_c + Vector2(0, -2)):
				q_mspot = q_c
	var q_shy_r = q_RoamerC.new({"id": "tikus_sawah", "name": "Ayam Liar", "lv": 1, "pemalu": true}, q_pm_map, q_mspot, 5)
	var q_pl := q_mspot + Vector2(1.5, 0.0)
	var q_d0: float = q_shy_r.pos.distance_to(q_pl)
	var q_shy_touch := false
	for i in 20:
		q_shy_touch = q_shy_touch or q_shy_r.step(0.1, q_pl, true, 1)
	_check(not q_shy_touch and not q_shy_r.chasing and q_shy_r.pos.distance_to(q_pl) > q_d0 + 0.5, "musuh pemalu lari dari pemain (no. 81)")
	var q_weak = q_RoamerC.new({"id": "serigala_hutan", "name": "Serigala Hutan", "lv": 2}, q_pm_map, q_mspot, 6)
	_check(q_weak.afraid_of(7) and not q_weak.afraid_of(3), "musuh lemah takut pada pemain yang 5 level lebih tinggi")
	var q_guard_r = q_RoamerC.new({"id": "goblin_penjaga", "name": "Goblin Penjaga", "lv": 5, "patroli": true}, q_pm_map, q_mspot, 8)
	var q_tgt_ok: bool = q_guard_r._pick_target()
	_check(q_tgt_ok and q_guard_r._patrol_pts.size() >= 2 and q_guard_r._patrol_pts.has(q_guard_r._target), "musuh penjaga berpatroli di titik-titik kelilingnya (no. 78)")
	var q_lane := Vector2.ZERO  # jalur lurus bebas 9 petak untuk uji wilayah
	for q_ly in range(3, 40):
		for q_lx in range(1, 40):
			var q_c2 := Vector2(q_lx + 0.5, q_ly + 0.5)
			if q_lane == Vector2.ZERO and Maps.roam_free(q_pm_map, q_c2) and Maps.roam_free(q_pm_map, q_c2 + Vector2(9, 0)) and Maps.roam_path_free(q_pm_map, q_c2, q_c2 + Vector2(9, 0)):
				q_lane = q_c2
	_check(q_lane != Vector2.ZERO, "ada jalur lurus untuk uji wilayah musuh")
	var q_ter = q_RoamerC.new({"id": "serigala_hutan", "name": "Serigala Hutan", "lv": 2}, q_pm_map, q_lane, 9)
	q_ter.chasing = true
	q_ter.pos = q_lane + Vector2(8.0, 0.0)  # sudah 8 petak dari asalnya (wilayah 7)
	var q_d_awal: float = q_ter.pos.distance_to(q_ter.origin)
	q_ter.step(0.1, q_lane + Vector2(9.0, 0.0), true, 1)
	_check(not q_ter.chasing and q_ter.returning and q_ter.pos.distance_to(q_ter.origin) < q_d_awal, "musuh berhenti mengejar di luar wilayahnya lalu pulang (no. 82)")
	for mdl in ["ksatria", "pendekar_kapak", "pemanah", "pendekar_tombak", "petani", "nenek_penjual", "goblin", "goblin_penjaga", "ogre_batu", "golem_kerikil", "golem_lava", "raja_goblin", "kelelawar_gua"]:
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
	Atmo.hour_override = 10.0  # siang yang pasti: hasil uji warga tidak bergantung lamanya uji berjalan
	w3._pos = Vector2(24.0, 28.0)  # jauh dari semua warga
	var start_pos: Array[Vector2] = []
	var best_move: Array[float] = []
	for w in w3._warga:
		start_pos.append(w.pos)
		best_move.append(0.0)
	var warga_ok := true
	var model_walked := false
	var min_gap := 99.0
	var gap_pair := ""
	for i in 1800:  # 90 detik
		w3._update_npcs(0.05)
		for k in w3._warga.size():
			var w = w3._warga[k]
			if not Maps.warga_free(Maps.DEFAULT_MAP, w.pos):
				warga_ok = false
			if w.walking and "moving" in w.model and w.model.moving:
				model_walked = true
			best_move[k] = maxf(best_move[k], w.pos.distance_to(start_pos[k]))
			if w.jadwal.is_empty() and w.pos.distance_to(w.home) > w.radius + 0.5:  # yang berjadwal boleh pergi bekerja
				warga_ok = false
			for j in range(k + 1, w3._warga.size()):
				var gap: float = w.pos.distance_to(w3._warga[j].pos)
				if gap < min_gap:
					min_gap = gap
					gap_pair = "%s-%s" % [w.id, w3._warga[j].id]
	var movers := 0
	var walkers := 0  # warga yang memang berjalan (bukan penjaga/pekerja yang diam di tempat)
	for k in best_move.size():
		if not w3._warga[k].diam:
			walkers += 1
		if best_move[k] > 1.5:
			movers += 1
	_check(warga_ok, "warga tidak pernah masuk pagar/air/rumah atau keluar dari jari-jarinya")
	_check(movers >= walkers - 2, "hampir semua warga benar-benar berjalan jauh (%d dari %d)" % [movers, walkers])
	_check(min_gap > 0.35, "warga tidak menumpuk satu sama lain (jarak terdekat %.2f, %s)" % [min_gap, gap_pair])
	# Pemain berdiri di tengah alun-alun: warga tidak menembus pemain.
	w3._pos = Vector2(12.5, 8.5)
	var near_player := 99.0
	for i in 1200:
		w3._update_npcs(0.05)
		for w in w3._warga:
			near_player = minf(near_player, w.pos.distance_to(w3._pos))
	_check(near_player > 0.6, "warga menjaga jarak dari pemain (terdekat %.2f)" % near_player)
	w3._pos = w3._warga[0].pos + Vector2(0.6, 0.0)
	_check(w3._npc_in_range().begins_with("warga:"), "warga di dekat pemain bisa diajak bicara")
	_check(model_walked, "model warga memakai animasi jalan saat bergerak")
	# Roadmap no. 22-38, 41: warga berpekerjaan, pose, identitas.
	var by_id := {}
	for w in w3._warga:
		by_id[w.id] = w
	var semua_peran := true
	for w in w3._warga:
		if w.id != "ayam" and w.peran == "":
			semua_peran = false
	_check(semua_peran, "semua warga (kecuali ayam) punya peran/pekerjaan")
	for wid in ["mpu_karta", "tuan_wira", "prajurit_damar", "laras", "nyai_sekar"]:
		_check(by_id.has(wid), "warga baru '%s' ada di Desa Awal" % wid)
	var pandai = by_id.get("mpu_karta")
	var sekar = by_id.get("nyai_sekar")
	w3._pos = Vector2(30.0, 40.0)  # jauh dari pandai besi
	for i in 10:
		w3._update_npcs(0.05)
	_check(pandai != null and pandai.model.loop_action == "palu", "pandai besi menempa saat pemain jauh")
	w3._pos = pandai.pos + Vector2(0.0, 1.2)
	for i in 10:
		w3._update_npcs(0.05)
	_check(pandai.model.loop_action == "", "pandai besi berhenti menempa dan menoleh saat pemain dekat")
	_check(sekar != null and sekar.model.pose == "duduk" and sekar.model.position.y < 0.0, "penyihir duduk di batu (siang)")
	_check(w3._npc_root.find_child("Alat_landasan", false, false) != null and w3._npc_root.find_child("Alat_batu", false, false) != null, "landasan tempa dan batu duduk dipasang")
	var tak_ada: Array[Vector2] = []
	sekar.step(0.05, Vector2(1, 1), tak_ada, true)
	sekar.apply()
	_check(sekar.sleeping and sekar.model.pose == "tidur" and absf(sekar.model.rotation.x) > 1.4, "penyihir tidur berbaring saat malam")
	w3._pos = sekar.pos + Vector2(0.8, 0.0)
	_check(w3._npc_in_range() != "warga:nyai_sekar", "warga yang tidur tidak bisa diajak bicara")
	sekar.step(0.05, Vector2(1, 1), tak_ada, false)
	sekar.apply()
	_check(not sekar.sleeping and sekar.model.pose == "duduk", "pagi: penyihir bangun dan duduk lagi")
	var rina = by_id.get("rina")
	var dika = by_id.get("dika")
	var rb := (rina.model.find_child("Rogue_Body", true, false) as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	var db := (dika.model.find_child("Rogue_Body", true, false) as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	_check(not rb.albedo_color.is_equal_approx(db.albedo_color), "variasi baju: Rina dan Dika (model sama) berbeda warna")
	var HA = load("res://scripts/hero_actions.gd")
	# Roadmap no. 135, 145: stamina dan layar tempa di pandai besi.
	_check(w3._tempa != null and not w3._tempa.is_open, "layar tempa tersedia (tertutup)")
	var g_karta = by_id.get("mpu_karta")
	_check(g_karta != null and g_karta.toko == "tempa", "Mpu Karta membuka layar tempa saat diajak bicara")
	w3.stamina = 100.0
	w3._tired = false
	for i in 200:
		w3._tick_stamina(0.05, true)
	_check(w3._tired and w3._speed_mul() < 1.0, "berlari terus: stamina habis dan hanya bisa berjalan")
	for i in 200:
		w3._tick_stamina(0.05, false)
	_check(not w3._tired and w3.stamina > 90.0, "berjalan/diam: stamina pulih")
	_check(HA.ACTIONS.has("bicara") and HA.ACTIONS.has("palu") and HA.POSES.has("duduk") and HA.POSES.has("tidur"), "gerakan bicara, menempa, duduk, tidur tersedia")
	# Roadmap no. 45-60: jadwal, pergi bekerja, obrolan, takut monster, optimasi.
	var WargaC = load("res://scripts/warga.gd")
	var defs := {}
	for d: Dictionary in Maps.WARGA:
		defs[str(d.id)] = d
	var kosong: Array[Vector2] = []
	var jauh := Vector2(1, 1)
	var budi = WargaC.new(defs["pak_budi"], 7)
	for i in 1600:
		budi.step(0.05, jauh, kosong, false, 9.0)
	_check(budi.at_job and budi.pos.distance_to(Vector2(12.5, 28.5)) < 0.1 and budi.current_kerja() == "cangkul", "jadwal: Pak Budi pergi ke ladang dan mencangkul jam 9 (no. 45, 52)")
	var kata_ok := false
	for i in 300:
		budi.step(0.05, jauh, kosong, false, 9.0)
		kata_ok = kata_ok or budi.say != ""
	_check(kata_ok, "pekerja sesekali berkata-kata di gelembung")
	for i in 1600:
		budi.step(0.05, jauh, kosong, false, 16.0)
	_check(budi.job.is_empty() and budi.pos.distance_to(budi.home) <= budi.radius + 0.5, "jadwal selesai: Pak Budi kembali ke sekitar rumahnya")
	var dewi = WargaC.new(defs["mbak_dewi"], 3)
	var sari = WargaC.new(defs["bu_sari"], 5)
	for i in 1600:
		dewi.step(0.05, jauh, kosong, false, 11.0)
		sari.step(0.05, jauh, kosong, false, 11.0)
	_check(dewi.at_job and sari.at_job and dewi.pos.distance_to(sari.pos) < 1.5 and dewi.current_kerja() == "bicara", "berdagang: Bu Sari berbelanja di lapak Mbak Dewi jam 11 (no. 51)")
	var karta = WargaC.new(defs["mpu_karta"], 11)
	karta.inside = true
	karta.pos = karta.spot()
	karta.step(0.05, jauh, kosong, false, 7.0)
	var mulai: Vector2 = karta.pos
	var jalan_kerja := false
	for i in 2400:
		karta.step(0.05, jauh, kosong, false, 7.0)
		jalan_kerja = jalan_kerja or karta.walking
	_check(mulai.distance_to(karta.home) > 5.0 and jalan_kerja and karta.pos.distance_to(karta.home) < 0.05 and not karta._going_work, "pagi: Mpu Karta berjalan dari rumah ke landasannya (no. 47)")
	var ujang = WargaC.new(defs["pak_ujang"], 13)
	var monster: Vector2 = ujang.pos + Vector2(1.2, 0.0)
	var mons: Array[Vector2] = [monster]
	var awal: float = ujang.pos.distance_to(monster)
	for i in 30:
		ujang.step(0.05, ujang.pos + Vector2(0, 3), kosong, false, 12.0, mons)
	_check(ujang.scared > 0.0 and ujang.pos.distance_to(monster) > awal + 0.5, "Pak Ujang takut dan lari menjauhi binatang buas (no. 53-54)")
	_check(ujang.calling_help and ujang.say.begins_with("Tolong"), "pemain dekat: Pak Ujang berteriak minta tolong (no. 55)")
	var tak_monster: Array[Vector2] = []
	for i in 2000:
		ujang.step(0.05, Vector2(40, 20), kosong, false, 12.0, tak_monster)
	_check(ujang.scared <= 0.0 and not ujang.calling_help and ujang.pos.distance_to(ujang.home) <= ujang.radius + 0.5, "bahaya lewat: Pak Ujang tenang dan kembali ke daerahnya")
	var cw_a = by_id.get("pak_joko")
	var cw_b = by_id.get("tuan_wira")
	cw_a.chat_cd = 0.0
	cw_b.chat_cd = 0.0
	cw_a.job = {}
	cw_b.job = {}
	cw_b.pos = cw_a.pos + Vector2(0.8, 0.0)
	w3._try_chats()
	_check(cw_a.chat_t > 0.0 and cw_b.chat_t > 0.0 and cw_a.say != "" and cw_b.say != "", "dua warga yang berpapasan mengobrol (no. 50)")
	w3._pos = Vector2(2.0, 2.0)
	var dekat_w = null
	var jauh_w = null
	for w in w3._warga:
		w.steps = 0
	for i in 40:
		w3._update_npcs(0.05)
	for w in w3._warga:
		var dd: float = w.pos.distance_to(w3._pos)
		if dd < 15.0 and dekat_w == null:
			dekat_w = w
		if dd > 25.0 and jauh_w == null:
			jauh_w = w
	_check(dekat_w != null and jauh_w != null and jauh_w.steps * 3 <= dekat_w.steps, "optimasi: warga jauh diperbarui jarang (%s vs %s langkah) (no. 60)" % [str(jauh_w.steps if jauh_w else -1), str(dekat_w.steps if dekat_w else -1)])
	Atmo.hour_override = -1.0
	# Roadmap no. 111-128: bangunan, pasar, ruangan baru.
	var b_medan: Node3D = load("res://scripts/world_build.gd").build(Maps.DEFAULT_MAP)
	var b_jenis: Array = b_medan.get_meta("bangunan", [])
	var b_kurang: Array = []
	for b_k in ["pandai_besi", "kuil", "bangsawan", "lumbung", "markas", "penginapan", "rumah_pemain", "kepala_suku", "toko", "rumah_sakit"]:
		if not b_jenis.has(b_k):
			b_kurang.append(b_k)
	_check(b_kurang.is_empty(), "Desa Awal punya pandai besi, kuil, rumah bangsawan, lumbung, markas, penginapan, rumah pemain, istana %s" % str(b_kurang))
	_check(int(b_medan.get_meta("pasar", 0)) >= 6, "pasar desa: lapak dan barang dagangan (%d)" % int(b_medan.get_meta("pasar", 0)))
	b_medan.free()
	for b_map in [Maps.PENGINAPAN, Maps.RUMAH_PEMAIN]:
		var b_in: Node3D = load("res://scripts/world_build.gd").build(b_map)
		_check(b_in != null and b_in.get_child_count() > 20, "ruangan %s tergambar dengan perabot" % b_map)
		b_in.free()
		var b_ex: Dictionary = Maps.EXITS[b_map][0]
		_check(Maps.walkable(b_map, b_ex.pos.x, b_ex.pos.y) and Maps.walkable(b_map, 4, 4), "ruangan %s: pintu keluar dan lantai bisa dilewati" % b_map)
	_check(str(Maps.exit_at(Maps.DEFAULT_MAP, 15, 39).get("to", "")) == Maps.RUMAH_PEMAIN and str(Maps.exit_at(Maps.DEFAULT_MAP, 29, 39).get("to", "")) == Maps.PENGINAPAN, "pintu rumah pemain dan penginapan di Desa Awal")
	# Roadmap no. 89-110: air hidup, pasir tepi air, ilalang, semak, jamur, angin, kabut pagi.
	var d_WB = load("res://scripts/world_build.gd")
	var d_medan_desa: Node3D = d_WB.build(Maps.DEFAULT_MAP)
	var d_hias: Dictionary = d_medan_desa.get_meta("hiasan", {})
	_check(int(d_hias.get("pasir", 0)) > 10 and int(d_hias.get("ilalang", 0)) > 5 and int(d_hias.get("semak", 0)) > 5, "Desa Awal: tepi pasir, ilalang, dan semak (%s)" % str(d_hias))
	var d_air_ok := false
	for d_mmi in d_medan_desa.find_children("*", "MultiMeshInstance3D", true, false):
		var d_mmx := d_mmi as MultiMeshInstance3D
		if d_mmx.material_override is ShaderMaterial and str((d_mmx.material_override as ShaderMaterial).shader.code).contains("riak"):
			d_air_ok = d_mmx.multimesh.get_instance_transform(0).origin.y > -0.06
	_check(d_air_ok, "air memakai shader riak dan berada di atas alas (tidak tertutup)")
	d_medan_desa.free()
	var d_medan_hutan: Node3D = d_WB.build(Maps.HUTAN)
	_check(int(d_medan_hutan.get_meta("hiasan", {}).get("jamur", 0)) > 0, "Hutan Lebat punya jamur")
	d_medan_hutan.free()
	d_WB.set_wind(2.5)
	_check(is_equal_approx(d_WB.wind(), 2.5), "angin bisa dikencangkan (pohon dan rumput)")
	d_WB.set_wind(1.0)
	Atmo.rain = 1.0
	_check(Atmo.wind_strength() > 2.0, "hujan membuat angin kencang")
	Atmo.rain = 0.0
	Atmo.hour_override = 6.5
	var d_kabut_pagi: float = Atmo.dawn_fog()
	Atmo.hour_override = 12.0
	_check(d_kabut_pagi > 0.9 and Atmo.dawn_fog() == 0.0, "kabut tebal pagi hari, hilang siang hari")
	Atmo.hour_override = -1.0
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

	print("== hadiah dunia, peti, tombol aksi")
	var hn := "Pemburu%d" % (Time.get_ticks_usec() % 100000)
	var hreg: Dictionary = await Api.register(hn, hn.to_lower() + "@contoh.id", pw)
	_check(hreg.ok, "daftar pemain pemburu")
	if hreg.ok:
		var saved_token: String = Api.token
		Api.token = str(hreg.data.token)
		var ws: Dictionary = await Api.world_state("desa_awal")
		_check(ws.ok and (ws.data.items as Array).is_empty(), "GET /v1/world awalnya kosong")
		var far_chest: Dictionary = await Api.world_chest("desa_1", "desa_awal", Vector2(5.5, 5.5), 0.0)
		_check(not far_chest.ok and far_chest.status == 422, "peti dari jauh ditolak 422")
		var chest: Dictionary = await Api.world_chest("desa_1", "desa_awal", Vector2(43.5, 9.0), 0.0)
		var kinds_v44: int = (1 if int(chest.data.loot.get("gold", 0)) > 0 else 0) + (chest.data.loot.get("items", []) as Array).size()
		_check(chest.ok and kinds_v44 == 3, "membuka peti memberi 3 hadiah acak yang berbeda (%d)" % kinds_v44)
		if chest.ok:
			_check(int(chest.data.player.state.gold) == int(chest.data.loot.gold), "emas peti masuk ke pemain")
			var diamonds := 0
			for it: Dictionary in chest.data.player.state.inventory:
				if it.id == "berlian":
					diamonds += int(it.qty)
			_check(diamonds <= 1, "peti tingkat 1 memberi paling banyak 1 berlian (%d)" % diamonds)
		var empty_chest: Dictionary = await Api.world_chest("desa_1", "desa_awal", Vector2(43.5, 9.0), 0.0)
		_check(not empty_chest.ok and empty_chest.status == 422, "peti yang sama tidak bisa dibuka lagi 422")
		await create_timer(0.2).timeout
		var brk: Dictionary = await Api.world_break("desa_awal", Vector2(43.5, 9.0), 0.0, [{"kind": "pohon", "x": 44, "z": 9}])
		_check(brk.ok and int(brk.data.loot.broken) == 1, "menghancurkan pohon tercatat")
		var h_bad_kind: Dictionary = await Api.world_break("desa_awal", Vector2(43.5, 9.0), 0.0, [{"kind": "naga", "x": 44, "z": 9}])
		_check(not h_bad_kind.ok and h_bad_kind.status == 422, "jenis benda salah ditolak 422")
		var ws2: Dictionary = await Api.world_state("desa_awal")
		_check(ws2.ok and (ws2.data.items as Array).size() == 2, "dunia mencatat peti terbuka dan pohon hancur")
		Api.token = saved_token
	for c: Dictionary in Maps.CHESTS:
		_check(Maps.walkable(str(c.map), c.pos.x, c.pos.y), "peti %s berada di petak yang bisa dilewati" % c.id)
		_check(Movement.tile_blocked(str(c.map), c.pos.x, c.pos.y), "peti %s menghalangi jalan" % c.id)
	var wt: Node = load("res://scenes/world3d.tscn").instantiate()
	Session.offline = true
	get_root().add_child(wt)
	await process_frame
	_check(wt._breakables != null and wt._breakables.count() > 100, "desa punya ratusan benda yang bisa dihancurkan (%d)" % wt._breakables.count())
	_check(wt._chest_nodes.size() == 9, "desa punya 9 peti harta (3 di desa, 6 di hutan timur)")
	_check(wt._btn_tangan != null and wt._btn_kaki != null and wt._btn_perisai != null and wt._btn_boost != null, "empat tombol aksi ada")
	_check(wt._talk_button != null and not wt._talk_button.visible, "tombol Bicara tersembunyi bila tidak ada orang di dekat")
	_check(wt._menu._btn_tas != null and wt._menu._btn_atribut != null, "Ransel dan Atribut ada di menu")
	print("== Desa: pagar kayu keliling dan gapura")
	var drows: Array[String] = Maps.rows("desa_awal")
	var dw := Maps.width("desa_awal")
	var dh := Maps.height("desa_awal")
	var ring_ok := true
	var ring_blocked := true
	for rx in 45:  # pagar desa: tepi barat, utara, selatan (wilayah timur x >= 45 tidak berpagar)
		for ry in [0, dh - 1]:
			var ch := drows[ry][rx]
			if ch != "P" and ch != "N" and not (rx >= 21 and rx <= 23 and ry == dh - 1):
				ring_ok = false
			if ch == "P" or ch == "N":
				ring_blocked = ring_blocked and not Maps.walkable("desa_awal", rx, ry)
	for ry in range(1, dh - 1):
		for rx in [0, 44]:
			var ch2 := drows[ry][rx]
			var celah_timur: bool = rx == 44 and ry >= 21 and ry <= 25  # celah pagar timur dan dua tiang batunya
			if ch2 != "P" and ch2 != "~" and not celah_timur:
				ring_ok = false
			if ch2 == "P":
				ring_blocked = ring_blocked and not Maps.walkable("desa_awal", rx, ry)
	_check(dw == 85 and Maps.walkable("desa_awal", 44, 22) and Maps.walkable("desa_awal", 44, 23) and Maps.walkable("desa_awal", 44, 24) and not Maps.walkable("desa_awal", 44, 21) and not Maps.walkable("desa_awal", 44, 25), "celah pagar timur (z 22..24) terbuka, diapit dua tiang batu")
	_check(drows[23][44] == "=" and drows[23][60] == "=" and drows[23][81] == "=", "jalan setapak dari celah timur menembus hutan")
	var ujung_ok := true
	for ctr: Dictionary in Maps.chests_in("desa_awal"):
		if int(ctr.pos.x) >= 45:
			ujung_ok = ujung_ok and Maps.walkable("desa_awal", ctr.pos.x, ctr.pos.y)
	_check(ujung_ok, "keenam peti hutan timur ada di petak yang bisa dilewati (dan tersambung, lihat uji sambungan peta)")
	var pohon_timur := 0
	var batu_timur := 0
	for ry2 in dh:
		for rx2 in range(45, dw):
			if drows[ry2][rx2] == "#":
				pohon_timur += 1
			elif drows[ry2][rx2] == "R":
				batu_timur += 1
	_check(pohon_timur > 400 and batu_timur > 40, "hutan timur punya banyak pohon (%d) dan batu (%d) untuk dipanen" % [pohon_timur, batu_timur])
	_check(ring_ok, "tepi Desa Awal berupa pagar kayu (P), gapura (N), jalan keluar, atau sungai")
	_check(ring_blocked, "pagar dan menara gapura menghalangi jalan")
	_check(drows[dh - 1][22] == "=" and Maps.walkable("desa_awal", 22, dh - 1), "jalan keluar di antara menara gapura bisa dilewati")
	_check(drows[dh - 1][19] == "N" and drows[dh - 1][20] == "N" and drows[dh - 1][24] == "N" and drows[dh - 1][25] == "N" and drows[dh - 1][21] == "=" and drows[dh - 1][23] == "=", "dua menara mengapit jalan keluar selebar tiga petak")
	_check(Maps.walkable("desa_awal", 22, dh - 2), "jalan menuju gapura terbuka")
	var spawn_ok := true
	for e: Dictionary in Maps.EXITS.get("perbatasan", []):
		if e.to == "desa_awal":
			spawn_ok = Maps.walkable("desa_awal", e.at.x, e.at.y)
	_check(spawn_ok, "pemain yang kembali dari Perbatasan muncul di jalan depan gapura")
	var pal_world: Node3D = load("res://scripts/world_build.gd").build("desa_awal")
	_check(pal_world != null and pal_world.get_child_count() > 20, "dunia Desa Awal dengan pagar dan gapura terbangun")
	var has_sign := false
	for ch3 in pal_world.get_children():
		if ch3 is Label3D and (ch3 as Label3D).text == "DESA AWAL":
			has_sign = true
	_check(has_sign, "gapura punya papan nama DESA AWAL")
	pal_world.free()
	print("== HUD: warna nyawa, nama, koin, tombol Bicara di atas NPC")
	var HB: Script = load("res://scripts/hud_bars.gd")
	var c_full: Color = HB.hp_color(1.0)
	var c_half: Color = HB.hp_color(0.5)
	var c_low: Color = HB.hp_color(0.1)
	_check(c_full.g > 0.85 and c_full.r < 0.4 and c_full.b < 0.3, "nyawa 100%% hijau stabilo (%s)" % str(c_full))
	_check(c_half.r > 0.9 and c_half.g > 0.75 and c_half.b < 0.3, "nyawa 50%% kuning (%s)" % str(c_half))
	_check(c_low.r > 0.85 and c_low.g < 0.45, "nyawa 10%% merah/oranye (%s)" % str(c_low))
	_check(HB.hp_color(0.75).g > HB.hp_color(0.4).g or HB.hp_color(0.75).r < HB.hp_color(0.4).r, "warna berubah bertahap antara penuh dan separuh")
	var hb: Control = HB.new()
	hb.set_identity("bagus", 47)
	_check(hb.player_name == "bagus" and hb.gold == 47, "HUD menyimpan nama dan jumlah emas")
	_check(hb.size.y >= HB.COIN_Y + 20.0, "HUD cukup tinggi untuk baris koin")
	_check(HB.NAME_H <= HB.XP_Y - 4.0, "nama pemain berada di atas level")
	hb.free()
	print("== v0.45: HUD berlian, pagar kandang, pengaturan layar dan suara")
	var hb_v45: Control = HB.new()
	hb_v45.set_identity("bagus", 47, 3)
	_check(hb_v45.diamonds == 3, "HUD menyimpan jumlah berlian")
	_check(HB.DIA_Y < HB.COIN_Y and HB.DIA_Y > HB.EN_Y + HB.EN_H, "berlian di atas koin emas dan di bawah bar energi")
	_check(HB.COIN_Y - HB.DIA_Y >= 30.0 and HB.DIA_Y - (HB.EN_Y + HB.EN_H / 2.0) >= 34.0, "jarak antar baris cukup (ikon tidak bertumpuk)")
	_check(HB.BAR_X + HB.BAR_W <= 280.0, "bar HUD tidak menyentuh jam di sebelahnya")
	hb_v45.free()
	var inv_v45: Array = Session.player.state.inventory
	var inv_backup_v45: Array = inv_v45.duplicate(true)
	Session.player.state.inventory = [{"id": "berlian", "qty": 4}]
	_check(Session.item_count("berlian") == 4 and Session.item_count("ramuan") == 0, "Session.item_count menghitung isi ransel")
	Session.player.state.inventory = inv_backup_v45
	var WBv45: Script = load("res://scripts/world_build.gd")
	var rows_v45: Array[String] = ["....", ".FFF", ".F..", ".F.."]
	_check(WBv45._tile_f(rows_v45, 1, 1) and not WBv45._tile_f(rows_v45, 0, 0) and not WBv45._tile_f(rows_v45, 9, 9), "_tile_f mengenali petak pagar kandang")
	var posts_v45: Array[Transform3D] = []
	var rails_v45: Array[Transform3D] = []
	WBv45._add_pagar_kandang(rows_v45, 1, 2, Vector3(1.5, 0, 2.5), posts_v45, rails_v45)
	var along_z_v45 := true
	for r_v45: Transform3D in rails_v45:
		along_z_v45 = along_z_v45 and r_v45.basis.get_scale().z > r_v45.basis.get_scale().x
	_check(rails_v45.size() == 2 and along_z_v45, "pagar kandang sisi utara-selatan palangnya memanjang ke arah z")
	var rails_h_v45: Array[Transform3D] = []
	WBv45._add_pagar_kandang(rows_v45, 2, 1, Vector3(2.5, 0, 1.5), posts_v45, rails_h_v45)
	_check(rails_h_v45.size() == 2 and rails_h_v45[0].basis.get_scale().x > rails_h_v45[0].basis.get_scale().z, "pagar kandang sisi timur-barat palangnya memanjang ke arah x")
	var rails_c_v45: Array[Transform3D] = []
	WBv45._add_pagar_kandang(rows_v45, 1, 1, Vector3(1.5, 0, 1.5), posts_v45, rails_c_v45)
	_check(rails_c_v45.size() == 4, "tikungan pagar kandang punya palang ke dua arah")
	var PUv45: Script = load("res://scripts/pengaturan_umum.gd")
	var pu_v45: Control = PUv45.new()
	root.add_child(pu_v45)
	await process_frame
	var labels_v45 := []
	for ch_v45: Node in pu_v45.get_children():
		if ch_v45 is Label:
			labels_v45.append((ch_v45 as Label).text)
	_check(labels_v45.has("Layar") and labels_v45.has("Suara") and labels_v45.has("Kualitas grafis"), "pengaturan beranda punya bagian Layar dan Suara")
	var keep_old_v45: bool = Session.keep_on
	pu_v45._on_keep(true)
	_check(Session.keep_on, "toggle layar tetap menyala tersimpan di Session")
	pu_v45._on_keep(keep_old_v45)
	pu_v45.free()
	var npc_id := ""
	for nid: String in Maps.NPCS:
		if Maps.NPCS[nid].map == wt._map_id:
			npc_id = nid
			break
	_check(npc_id != "", "ada NPC di desa untuk dites")
	if npc_id != "":
		var nn: Dictionary = Maps.NPCS[npc_id]
		wt._pos = Vector2(nn.pos) + Vector2(0.5, 1.2)
		wt._apply_transform()
		await process_frame
		var tb: Button = wt._talk_button
		_check(tb.visible and tb.text == "Bicara", "tombol Bicara muncul dekat NPC")
		var head: Vector2 = wt._camera.unproject_position(wt._npc_anchor(npc_id))
		_check(tb.position.y + tb.size.y <= head.y + 1.0, "tombol Bicara berada di atas kepala NPC (%.0f <= %.0f)" % [tb.position.y + tb.size.y, head.y])
		_check(absf(tb.position.x + tb.size.x * 0.5 - head.x) < 120.0 or tb.position.x <= 9.0 or tb.position.x + tb.size.x >= 710.0, "tombol Bicara sejajar dengan NPC")
	var tree: Dictionary = {}
	for e: Dictionary in wt._breakables._entries:
		if e.kind == "pohon" and e.tile.x < 10 and e.tile.y > 3 and e.tile.y < 44 and Maps.walkable(wt._map_id, e.tile.x + 1, e.tile.y) and Maps.walkable(wt._map_id, e.tile.x + 2, e.tile.y):
			tree = e
			break
	wt._pos = Vector2(tree.pos.x + 1.0, tree.pos.y)
	wt._yaw = atan2(-1.0, 0.0)
	var swings := 0
	while not tree.gone and swings < 8:
		wt._cd.tangan = 0.0
		wt._do_tangan()
		swings += 1
		await create_timer(0.8).timeout  # pukulan mengenai di tengah gerakan (hits)
	_check(tree.gone and swings == 2 and wt._combo == 2, "tinju dobel + tebas dobel menumbangkan pohon (%d tombol)" % swings)
	_check(wt.COMBO.size() == 3 and wt.COMBO[0].anim == "tinju" and wt.COMBO[1].anim == "tebas" and wt.COMBO[2].anim == "tusuk", "tombol Tangan: 1 tinju, 2 tebas, 3 tusuk")
	_check((wt.COMBO[0].hits as Array).size() == 2 and (wt.COMBO[1].hits as Array).size() == 2 and (wt.KICKS[1].hits as Array).size() == 2, "tinju, tebas, dan tendangan dobel masing-masing dua pukulan")
	_check(wt.KICKS.size() == 2 and wt.KICKS[0].anim == "tendang" and wt.KICKS[1].anim == "tendang2", "tombol Kaki: 1 tendang, 2 tendangan dobel")
	wt._combo = 0
	wt._combo_t = 0.0
	wt._cd.kaki = 0.0
	wt._do_kaki()
	_check(wt._kick == 1, "tendangan pertama = tendang")
	wt._cd.kaki = 0.0
	wt._do_kaki()
	_check(wt._kick == 2, "tendangan kedua cepat = tendangan dobel")
	await create_timer(1.0).timeout
	_check(wt._btn_lompat != null and wt._btn_lompat.title == "Lompat", "tombol Lompat ada")
	wt._cd.lompat = 0.0
	wt._jump_t = 0.0
	wt._do_lompat()
	_check(wt._jump_t > 0.0 and is_equal_approx(wt._jump_height(), 0.0), "lompat dimulai dari tanah")
	for k in 20:
		await process_frame
	wt._jump_t = wt.JUMP_TIME * 0.5
	_check(wt._jump_height() > 0.9 * wt.JUMP_HEIGHT, "puncak lompat setinggi %.2f" % wt._jump_height())
	wt._jump_t = 0.0
	wt._tap_t = -10.0
	wt._guard = false
	wt._cd.hindar = 0.0
	var pg: Vector2 = wt._pos
	wt._on_perisai_pressed()
	_check(wt._guard and wt._guard_t > 0.0, "ketuk Perisai sekali mengangkat perisai")
	wt._yaw = 0.0
	await process_frame
	_check((wt._pos - pg).length() < 0.001, "perisai terangkat: pahlawan tetap di tempat")
	_check(tree.rubble != null, "pohon yang tumbang meninggalkan tunggul")
	wt._energy = 100.0
	wt._do_boost()
	_check(wt._boost_t > 0.0 and wt._energy == 0.0, "Boost penuh meledak dan memulai mode Boost")
	wt._cd.hindar = 0.0
	var p0: Vector2 = wt._pos
	wt._on_perisai_pressed()  # ketukan kedua cepat setelah yang pertama di atas
	for k in 20:
		await process_frame
	_check((wt._pos - p0).length() > 0.5 and not wt._guard, "ketuk Perisai dua kali cepat = menghindar (perisai turun)")
	wt.queue_free()
	await process_frame
	Session.offline = false

	print("== musuh berkeliaran dan bar nyawa")
	var saved_pose: Dictionary = Session.player.state.duplicate(true)
	for mid in [Maps.DEFAULT_MAP, Maps.PERBATASAN, Maps.GUNUNG, Maps.GUA]:
		Session.player.state.map = mid
		Session.player.state.x = 7 if mid == Maps.GUA else 22
		Session.player.state.y = 1 if mid != Maps.DEFAULT_MAP else 5
		Session.player.state.fx = 0.0
		Session.player.state.fz = 0.0
		Session.player.state.hp = 15
		Session.player.state.max_hp = 30
		Session.player.state.xp = 10
		Session.player.state.level = 1
		Session.offline = true
		var wr: Node = load("res://scenes/world3d.tscn").instantiate()
		get_root().add_child(wr)
		await process_frame
		if mid == Maps.DEFAULT_MAP:
			_check(not Maps.ROAMERS.has(mid) and wr._roamers.is_empty(), "Desa Awal aman: tak ada musuh berkeliaran")
			wr.queue_free()
			await process_frame
			continue
		var cfg: Dictionary = Maps.ROAMERS[mid]
		_check(wr._roamers.size() >= mini(int(cfg.n), 3), "%s: musuh berkeliaran muncul (%d)" % [mid, wr._roamers.size()])
		var bad_spot := 0
		var bad_kind := 0
		for r in wr._roamers:
			if not Maps.roam_free(mid, r.pos):
				bad_spot += 1
			var okk := false
			for k: Dictionary in cfg.kinds:
				if k.id == r.id and int(k.lv) <= 1 + 100:
					okk = true
			if not okk:
				bad_kind += 1
			if r.pos.distance_to(wr._pos) < 5.0:
				bad_spot += 1
		_check(bad_spot == 0 and bad_kind == 0, "%s: musuh berdiri di petak bebas, jauh dari pemain, jenis sesuai peta" % mid)
		if mid != Maps.DEFAULT_MAP:
			for r in wr._roamers:
				_check(int(Maps.ROAMERS[mid].kinds[0].lv) == 1 or r.id != "serigala_alfa" and r.id != "orc_buas", "%s: level 1 tidak bertemu musuh terkuat" % mid)
				break
		_check(is_equal_approx(wr._bars.hp_fraction(), 0.5) and is_equal_approx(wr._bars.xp_fraction(), 0.5), "%s: bar nyawa 50%% dan poin 10/20" % mid)
		if mid == Maps.PERBATASAN and not wr._roamers.is_empty():
			var rr = null
			var target := Vector2.ZERO
			var found := false
			for cand_r in wr._roamers:
				if cand_r.shy:
					continue  # musuh pemalu lari, bukan mengejar
				for dist: float in [2.5, 2.0, 1.5]:
					for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
						var cand: Vector2 = cand_r.pos + dir * dist
						if not found and Maps.roam_free(mid, cand) and Maps.roam_path_free(mid, cand_r.pos, cand):
							rr = cand_r
							target = cand
							found = true
			_check(found, "ada tempat bebas di dekat musuh untuk uji kejar")
			if found:
				var rr_home: Vector2 = rr.pos
				var calm := 0
				for i in 30:
					rr.step(0.1, target, false)
					if rr.chasing:
						calm += 1
				_check(calm == 0, "musuh tidak mengejar saat jeda awal / mode uji")
				rr.pos = rr_home
				var touched := false
				for i in 80:
					if rr.step(0.1, target, true):
						touched = true
						break
				_check(touched and rr.chasing, "musuh yang pemainnya mendekat mengejar lalu menyentuh")
				rr.pos = target + Vector2(30.0, 0.0)
				rr.step(0.1, target, true)
				_check(not rr.chasing, "pemain jauh: pengejaran tidak dimulai")
		wr.queue_free()
		await process_frame
	Session.offline = false
	Session.player.state = saved_pose


	print("== desa malam: menara lampu, lampu gapura dan rumah, rumah kepala suku, warga pulang")
	var Wg: GDScript = load("res://scripts/warga.gd")
	var terrain: Node3D = WB.build(Maps.DEFAULT_MAP)
	_check(terrain.has_meta("malam"), "desa punya lampu malam")
	var lamp_reg: Dictionary = terrain.get_meta("malam")
	_check((lamp_reg.lights as Array).size() >= 4, "lampu titik: menara, dua lampu gapura, rumah kepala suku (%d)" % (lamp_reg.lights as Array).size())
	WB.set_night(terrain, 1.0)
	_check((lamp_reg.lampu as StandardMaterial3D).emission_energy_multiplier > 0.5 and (lamp_reg.lights[0].node as OmniLight3D).visible and (lamp_reg.lights[0].node as OmniLight3D).light_energy > 0.5, "malam: lampu menyala")
	WB.set_night(terrain, 0.0)
	_check((lamp_reg.lampu as StandardMaterial3D).emission_energy_multiplier == 0.0 and not (lamp_reg.lights[0].node as OmniLight3D).visible, "siang: lampu padam")
	var gate_lamps := 0
	var tower_lamp := 0
	for ch in terrain.get_children():
		if ch.name.begins_with("LampuGapura"):
			gate_lamps += 1
		if ch.name == "LampuMenara":
			tower_lamp += 1
	_check(gate_lamps == 3 and tower_lamp == 1, "tiga lampu di atas gapura dan satu lampu besar di menara (%d, %d)" % [gate_lamps, tower_lamp])
	terrain.free()
	var pb_terrain: Node3D = WB.build(Maps.PERBATASAN)
	var pb_gate_lamps := 0
	for ch in pb_terrain.get_children():
		if ch.name.begins_with("LampuGapura"):
			pb_gate_lamps += 1
	_check(Maps.tile_at(Maps.PERBATASAN, 20, 0) == "N" and Maps.tile_at(Maps.PERBATASAN, 21, 0) == "=" and Maps.tile_at(Maps.PERBATASAN, 22, 0) == "=" and Maps.tile_at(Maps.PERBATASAN, 23, 0) == "=" and Maps.tile_at(Maps.PERBATASAN, 24, 0) == "N" and pb_terrain.has_node("PapanGapura") and pb_gate_lamps == 3, "Perbatasan punya gapura lebar menuju desa di (21..23,0) dengan tiga lampu (%d)" % pb_gate_lamps)
	pb_terrain.free()
	var well_tiles := 0
	for row in Maps.rows(Maps.DEFAULT_MAP):
		well_tiles += row.count("W")
	_check(well_tiles == 1 and Maps.tile_at(Maps.DEFAULT_MAP, 22, 13) == "W", "menara lampu berdiri di tengah alun-alun (petak W)")
	_check(Maps.tile_at(Maps.DEFAULT_MAP, 40, 3) == "D" and Maps.tile_at(Maps.DEFAULT_MAP, 38, 1) == "H" and Maps.tile_at(Maps.DEFAULT_MAP, 42, 3) == "H", "rumah kepala suku 5x3 dengan pintu di (40,3)")
	var chief := false
	for def: Dictionary in Maps.WARGA:
		if def.id == "kepala_suku" and def.rumah == Vector2i(40, 3):
			chief = true
		if def.has("rumah"):
			var dr: Vector2i = def.rumah
			var pintu_ch := Maps.tile_at(Maps.DEFAULT_MAP, dr.x, dr.y)
			var ar: Vector2i = def.get("arah", Vector2i(0, 1))
			_check(["D", "J", "C"].has(pintu_ch) and Maps.warga_free(Maps.DEFAULT_MAP, Vector2(dr.x + 0.5 + ar.x, dr.y + 0.5 + ar.y)), "%s: pintu (rumah D / pos jaga J / kandang C) dan petak di depannya bisa dilewati" % def.id)
	_check(chief, "ada Kepala Suku yang tinggal di rumahnya")
	_check(not Atmo.is_night() or Atmo.hour_override < 0.0, "jam uji belum dipaksa")
	Atmo.hour_override = 12.0
	_check(not Atmo.is_night() and Atmo.night() < 0.1, "siang bolong: bukan malam, lampu padam")
	Atmo.hour_override = 22.0
	_check(Atmo.is_night() and Atmo.night() > 0.9, "jam 22: malam penuh")
	var no_others: Array[Vector2] = []
	var wb = null
	var pj = null
	for def: Dictionary in Maps.WARGA:
		if def.id == "bu_sari":
			wb = Wg.new(def, 3)
		if def.id == "penjaga":
			pj = Wg.new(def, 4)
	var n_steps := 0
	while not wb.inside and n_steps < 6000:
		wb.step(0.05, Vector2(-80, -80), no_others, true)
		n_steps += 1
	_check(wb.inside and wb.pos.distance_to(Vector2(10.5, 2.5)) < 0.1, "Bu Sari berjalan pulang dan masuk lewat pintu rumahnya (%d langkah)" % n_steps)
	for i in 200:
		pj.step(0.05, Vector2(-80, -80), no_others, true)
	var pos_jaga_pintu: Vector2i = Vector2i(-1, -1)
	var kandang_pintu: Array[Vector2i] = []
	var pos_jaga_arah := Vector2i(0, 0)
	for rr: Dictionary in WB._kelompok(Maps.tiles_of(Maps.DEFAULT_MAP, "J")):
		pos_jaga_arah = WB.arah_kecil("J", rr)
		pos_jaga_pintu = WB.pintu_kecil(rr, pos_jaga_arah)
	for rr: Dictionary in WB._kelompok(Maps.tiles_of(Maps.DEFAULT_MAP, "C")):
		kandang_pintu.append(WB.pintu_kecil(rr))
	_check(pj.door == pos_jaga_pintu and pj.door == Vector2i(24, 45) and pos_jaga_arah == Vector2i(-1, 0) and pj.arah == pos_jaga_arah and pj.terlihat, "pos jaga terbuka menghadap barat (ke jalan utama), pintu penjaga %s" % [pj.door])
	_check(Maps.warga_free(Maps.DEFAULT_MAP, pj.front()) and absf(pj.front().x - 23.5) < 0.01, "petak depan pos jaga (23,45) bisa dilewati dan menempel jalan utama")
	var ayam_ok := true
	for def: Dictionary in Maps.WARGA:
		if def.id == "ayam":
			ayam_ok = ayam_ok and kandang_pintu.has(def.rumah)
	_check(ayam_ok and kandang_pintu.size() == 2, "tiap ayam punya pintu kandang ayam")
	var pj_steps := 0
	while not pj.inside and pj_steps < 6000:
		pj.step(0.05, Vector2(-80, -80), no_others, true)
		pj_steps += 1
	_check(pj.inside and pj.pos.distance_to(Vector2(25.0, 45.5)) < 0.1 and absf(pj.yaw - atan2(-1.0, 0.0)) < 0.5, "malam: penjaga berdiri di bawah atap pos jaga menghadap jalan (%d langkah)" % pj_steps)
	var ayam_masuk := 0
	for def: Dictionary in Maps.WARGA:
		if def.id == "ayam":
			var ay = Wg.new(def, 9)
			var n_ay := 0
			while not ay.inside and n_ay < 6000:
				ay.step(0.05, Vector2(-80, -80), no_others, true)
				n_ay += 1
			if ay.inside and ay.pos.distance_to(Vector2(def.rumah.x + 0.5, def.rumah.y + 0.5)) < 0.1:
				ayam_masuk += 1
	_check(ayam_masuk == 4, "malam: keempat ayam masuk ke kandang ayam (%d)" % ayam_masuk)
	Atmo.hour_override = 12.0
	wb.step(0.05, Vector2(-80, -80), no_others, false)
	_check(not wb.inside and wb.pos.distance_to(Vector2(10.5, 3.5)) < 0.7, "pagi: warga keluar dari pintu rumahnya (bergeser sedikit supaya tidak bertumpuk)")
	Atmo.hour_override = 22.0
	Session.offline = true
	Session.player.state.map = Maps.DEFAULT_MAP
	Session.player.state.x = 22
	Session.player.state.y = 20
	Session.player.state.fx = 0.0
	Session.player.state.fz = 0.0
	var wn: Node = load("res://scenes/world3d.tscn").instantiate()
	get_root().add_child(wn)
	await process_frame
	var inside_n := 0
	var out_n := 0
	var guard_out := false
	for ww in wn._warga:
		if ww.inside:
			inside_n += 1
			_check(ww.terlihat or not ww.node.visible, "%s di dalam rumah tidak terlihat (penjaga di pos jaga terbuka tetap terlihat)" % ww.id)
		else:
			# perekrut di tenda, dan yang berjaga/tidur di luar (prajurit patroli, pemanah gerbang, penyihir)
			if not str(ww.id).begins_with("rekrut") and not ["prajurit_damar", "laras", "nyai_sekar"].has(ww.id):
				out_n += 1
			if ww.id == "penjaga":
				guard_out = true
	_check(inside_n == 14 and not guard_out and out_n == 0, "masuk desa saat malam: 9 warga di rumah, penjaga di pos jaga, 4 ayam di kandang (%d di dalam)" % inside_n)
	var guard_seen := false
	for ww in wn._warga:
		if ww.id == "penjaga":
			guard_seen = ww.node.visible and ww.pos.distance_to(Vector2(25.0, 45.5)) < 0.1
	_check(guard_seen, "penjaga terlihat berdiri di pos jaga saat malam")
	_check(wn._npc_in_range() == "" or not wn._npc_in_range().begins_with("warga:bu_sari"), "warga di dalam rumah tidak bisa diajak bicara")
	wn.queue_free()
	await process_frame
	Atmo.hour_override = -1.0
	Session.offline = false

	print("== pertarungan langsung di dunia (tanpa pindah layar)")
	for i in 40:  # sisa pertarungan bos dari uji sebelumnya harus selesai dulu (kabur / kalah)
		var left_b: Dictionary = await Api.battle_get()
		if not left_b.ok:
			break
		await Api.battle_action("flee")
		await create_timer(0.8).timeout
	await Api.rest()  # pulihkan HP bila bisa (di desa), supaya uji menang tidak bergantung pada sisa HP
	var me_fight: Dictionary = await Api.get_me()
	Session.set_player(me_fight.data)
	var fst: Dictionary = Session.player.state.duplicate(true)
	fst.map = Maps.PERBATASAN
	fst.x = 22
	fst.y = 5
	fst.fx = 22.5
	fst.fz = 5.5
	var saved_f: Dictionary = await Api.save(Session.player.version, fst)
	_check(saved_f.ok, "posisi di hutan Perbatasan tersimpan")
	if saved_f.ok:
		Session.set_player(saved_f.data)
		var wf: Node = load("res://scenes/world3d.tscn").instantiate()
		get_root().add_child(wf)
		await process_frame
		await process_frame
		wf._roam_grace = 999.0
		_check(wf._roamers.size() >= 5, "hutan berisi musuh berkeliaran (%d)" % wf._roamers.size())
		var foe = wf._roamers[0]
		foe.pos = wf._pos + Vector2(1.3, 0.0)
		var n_before: int = wf._roamers.size()
		wf._fight.engage(foe, "attack")
		var tf := Time.get_ticks_msec()
		while not wf._fight.active and Time.get_ticks_msec() - tf < 6000:
			await process_frame
		_check(wf._fight.active and wf._fight.roamer == foe and foe.fight, "memukul musuh memulai pertarungan langsung di dunia")
		_check(wf.is_inside_tree() and wf.get_node_or_null("WorldFight") == null and not wf._locked, "layar tetap dunia (tidak pindah ke layar pertarungan) dan pemain tetap bebas bergerak")
		_check(foe.node.get_child_count() >= 5 and wf._fight._bar != null, "musuh punya bar nyawa melayang")
		var fought := 0
		tf = Time.get_ticks_msec()
		while wf._fight.active and Time.get_ticks_msec() - tf < 90000:
			wf._fight.player_action("attack")
			fought += 1
			await process_frame
		_check(not wf._fight.active and wf._fight.last_result != "", "pertarungan langsung selesai (%s) setelah %d bingkai aksi" % [wf._fight.last_result, fought])
		_check(Session.battle.is_empty(), "sesi tidak lagi menyimpan pertarungan")
		var gone_f: Dictionary = await Api.battle_get()
		_check(not gone_f.ok and gone_f.status == 404, "pertarungan terhapus di server")
		if wf._fight.last_result == "won":
			_check(not wf._roamers.has(foe) and foe.dying, "musuh yang kalah dilepas dari dunia")
			var after_f: Dictionary = await Api.get_me()
			_check(int(after_f.data.state.xp) > 0 or int(after_f.data.state.level) > 1, "menang memberi XP")
			_check(int(after_f.data.state.hp) == Session.player.state.hp and int(after_f.data.version) == Session.player.version, "HP dan versi lokal sinkron dengan server")
			_check(wf._roamers.size() == n_before - 1, "jumlah musuh berkurang satu")
		# Kabur otomatis: menjauh dari musuh yang masih menempel.
		if wf._fight.last_result != "lost":
			var foe2 = wf._roamers[0]
			foe2.chase_speed = 0.0
			foe2.pos = wf._pos + Vector2(1.3, 0.0)
			wf._fight.engage(foe2, "")
			tf = Time.get_ticks_msec()
			while not wf._fight.active and Time.get_ticks_msec() - tf < 6000:
				await process_frame
			_check(wf._fight.active, "pertarungan kedua dimulai lewat sentuhan")
			wf._pos = foe2.pos + Vector2(7.0, 0.0)
			tf = Time.get_ticks_msec()
			while wf._fight.active and Time.get_ticks_msec() - tf < 30000:
				await process_frame
			_check(not wf._fight.active and ["fled", "lost", "won"].has(wf._fight.last_result), "menjauh dari musuh = mencoba kabur sampai selesai (%s)" % wf._fight.last_result)
			var left2: Dictionary = await Api.battle_get()
			_check(not left2.ok, "tak ada pertarungan menggantung di server")
		wf.queue_free()
		await process_frame
	Session.player.state = saved_pose

	print("== jam, suara, atribut, pendamping")
	var saved_misc: Dictionary = Session.player.state.duplicate(true)
	var wc: Node = load("res://scenes/world3d.tscn").instantiate()
	get_root().add_child(wc)
	await process_frame
	await process_frame
	_check(wc._clock != null and wc._clock.position.x > 150.0 and wc._clock.position.x + wc._clock.size.x < 570.0 and wc._clock._text != "", "jam berada di tengah atas, di antara nama pemain dan tombol Menu (%s)" % wc._clock._text)
	Atmo.hour_override = 12.0
	wc._update_clock()
	_check(wc._clock._kind == "sun" and wc._clock._text.begins_with("Siang"), "siang: ikon matahari")
	Atmo.hour_override = 23.0
	wc._update_clock()
	_check(wc._clock._kind == "moon" and wc._clock._text.begins_with("Malam"), "malam: ikon bulan")
	Atmo.hour_override = -1.0
	_check(wc._menu._toggle_npc != null and wc._menu._toggle_music != null, "Pengaturan punya pilihan suara NPC dan musik")
	var token_kept: String = Api.token
	Api.token = ""  # save_config() menyimpan token; jangan sampai uji ini meninggalkan sesi di user://
	wc._menu._on_vol_music(0.35)
	wc._menu._on_toggle_npc(false)
	_check(is_equal_approx(Session.vol_music, 0.35) and not Session.snd_npc, "pengaturan suara tersimpan di Session")
	_check(AudioServer.get_bus_index("Musik") >= 0 and AudioServer.get_bus_index("NPC") >= 0 and AudioServer.is_bus_mute(AudioServer.get_bus_index("NPC")), "bus Musik dan NPC ada; NPC dimatikan")
	wc._menu._on_toggle_npc(true)
	wc._menu._on_vol_music(0.6)
	Api.token = token_kept
	_check(Sound._music != null and Sound._music.stream != null and Sound._voices.size() == 6, "musik latar dan 6 suara bicara NPC termuat")
	Sound.npc_say("Selamat datang di desa kami, Ksatria.", 3)
	await process_frame
	Sound.npc_stop()
	_check(true, "suara bicara NPC berjalan tanpa galat")
	var hp_json := JSON.stringify(Session._normalize_state({"ally_hp": {"ksatria": 30.0, "pemanah": -3.0}}).get("ally_hp"))
	_check(hp_json.contains('"ksatria":30,') and hp_json.contains('"pemanah":0}') and not hp_json.contains("."), "HP pendamping dikirim sebagai bilangan bulat (%s)" % hp_json)
	Session.player.state.party = ["pemanah", "pendekar_kapak"]
	wc._companions.sync()
	await process_frame
	_check(wc._companions.count() == 2, "pendamping muncul di dunia sesuai barisan (%d)" % wc._companions.count())
	var gap_c: float = (Vector2(wc._companions.position_of("pemanah").x, wc._companions.position_of("pemanah").z) - wc._pos).length()
	_check(gap_c < 4.0, "pendamping berdiri dekat pemain (%.1f petak)" % gap_c)
	Session.player.state.party = []
	wc._companions.sync()
	_check(wc._companions.count() == 0, "barisan kosong = tanpa pendamping")
	wc.queue_free()
	await process_frame
	Session.player.state = saved_misc

	var gold_now: int = int(Session.player.state.gold)
	var buy1: Dictionary = await Api.buy_ally("pemanah")
	if gold_now >= 300:
		_check(buy1.ok and buy1.data.state.allies.has("pemanah") and buy1.data.state.party.has("pemanah"), "beli pendamping: masuk daftar dan langsung dipasang")
		Session.merge_server_player(buy1.data)
		var unparty: Dictionary = await Api.set_party([])
		_check(unparty.ok and unparty.data.state.party.is_empty() and unparty.data.state.allies.has("pemanah"), "lepas semua pendamping; pahlawan tetap dimiliki")
		Session.merge_server_player(unparty.data)
	else:
		_check(not buy1.ok and buy1.status == 422, "emas kurang (%d): beli pendamping ditolak 422" % gold_now)
	var bad_party: Dictionary = await Api.set_party(["ksatria", "ksatria"])
	_check(not bad_party.ok and bad_party.status == 422, "pendamping dobel / belum dibeli ditolak 422")
	var atr: Node = load("res://scenes/atribut.tscn").instantiate()
	get_root().add_child(atr)
	var ta := Time.get_ticks_msec()
	while atr._catalog.is_empty() and Time.get_ticks_msec() - ta < 4000:
		await process_frame
	await process_frame
	_check(not atr._catalog.is_empty() and atr._tab_buttons.size() == 4 and atr._page_equip.visible and not atr._page_ally.visible, "layar Atribut terbuka di tab Perlengkapan")
	_check(atr._equip_list.get_child_count() >= 3, "tab Perlengkapan menampilkan statistik dan slot (%d baris)" % atr._equip_list.get_child_count())
	atr._show_page(1)
	await process_frame
	_check(atr._page_ally.visible and not atr._page_equip.visible and atr._hero_tabs.size() == 4 and atr._ally_btn.text != "", "tab Pendamping menampilkan 4 pahlawan dan tombol beli/pasang (%s)" % atr._ally_btn.text)
	# Pasang prajurit: pengatur jumlah (v0.49.1)
	Session.player.state["soldiers"] = 3
	Session.player.state["soldiers_rest"] = 1
	_check(Session.active_soldiers() == 2, "dua dari tiga prajurit dipasang (satu menunggu di kem)")
	Session.player.state["soldiers_rest"] = 0
	atr._sol_pick = -1
	atr._refresh_ally()
	_check(atr._sol_row.visible and atr._sol_count.text == "3 / 3" and atr._sol_plus.disabled and not atr._sol_minus.disabled and atr._sol_btn.disabled, "pengatur prajurit: 3 / 3, tombol Pasang mati bila jumlah sama")
	atr._on_sol_step(-1)
	atr._on_sol_step(-1)
	_check(atr._sol_count.text == "1 / 3" and not atr._sol_btn.disabled and atr._sol_btn.text == "Pasang 1 prajurit", "kurangi ke 1: tombol jadi 'Pasang 1 prajurit'")
	atr._on_sol_step(-5)
	_check(atr._sol_count.text == "0 / 3" and atr._sol_minus.disabled, "jumlah tidak bisa di bawah 0")
	Session.player.state["soldiers"] = 0
	atr._sol_pick = -1
	atr._refresh_ally()
	_check(not atr._sol_row.visible and not atr._sol_btn.visible, "tanpa prajurit pengatur disembunyikan")
	var dep_far: Dictionary = await Api.deploy_soldiers(5)
	_check(not dep_far.ok and dep_far.status == 422, "pasang lebih dari yang dimiliki ditolak server (422)")
	var dep_zero: Dictionary = await Api.deploy_soldiers(0)
	_check(dep_zero.ok, "pasang 0 prajurit diterima server")
	atr.queue_free()
	await process_frame
	Session.player.state = saved_misc

	print("== energi, makanan, toko per-jenis, penjaga")
	var saved_toko_v39: Dictionary = Session.player.state.duplicate(true)
	var wtk: Node = load("res://scenes/world3d.tscn").instantiate()
	get_root().add_child(wtk)
	await process_frame
	await process_frame
	# HUD: piala level + bar energi petir di bawah bar nyawa
	Session.player.state.energy_used = 30
	wtk._refresh_hud()
	_check(wtk._bars.energy == 70 and wtk._bars.max_energy == 100 and Session.energy() == 70, "HUD menampilkan energi 70/100 (bar petir)")
	_check(wtk._bars.EN_Y > wtk._bars.HP_Y + wtk._bars.HP_H and wtk._bars.COIN_Y > wtk._bars.EN_Y + wtk._bars.EN_H, "bar energi di bawah bar nyawa, di atas koin")
	# Menu tidak lagi punya tombol Toko
	var has_toko_btn_v39 := false
	for ch in wtk._menu._main.get_children():
		if ch is Button and (ch as Button).text == "Toko":
			has_toko_btn_v39 = true
	_check(not has_toko_btn_v39 and not wtk._menu.has_signal("shop_requested"), "tombol Toko tidak ada di Menu (belanja lewat penjaga di toko)")
	# Pintu bangunan di desa menuju ruangan; ruangannya tersambung penuh dan pintu keluarnya kembali ke desa
	var ikon_n_v41 := 0
	var stack_v41: Array[Node] = [wtk._terrain]
	while not stack_v41.is_empty():
		var nd_v41: Node = stack_v41.pop_back()
		if nd_v41.has_meta("tiang"):  # ikon atap (plang.gd)
			ikon_n_v41 += 1
		stack_v41.append_array(nd_v41.get_children())
	_check(ikon_n_v41 == 5, "lima bangunan (empat toko dan aula) punya ikon atap dan plang (%d)" % ikon_n_v41)
	for pair: Array in [["toko_ramuan", Vector2i(16, 2), "toko"], ["rumah_makan", Vector2i(22, 2), "makan"], ["rumah_sehat", Vector2i(28, 2), "rawat"], ["toko_peralatan", Vector2i(4, 2), "peralatan"]]:
		var rid: String = pair[0]
		var door_in: Dictionary = Maps.exit_at(Maps.DEFAULT_MAP, pair[1].x, pair[1].y)
		var door_out: Dictionary = Maps.exit_at(rid, 4, 7)
		_check(door_in.get("to", "") == rid and door_out.get("to", "") == Maps.DEFAULT_MAP and Maps.is_interior(rid), "pintu bangunan %s di desa menuju ruangan %s dan pintu keluarnya kembali" % [str(pair[1]), rid])
		_check(Maps.width(rid) == 9 and Maps.height(rid) == 8, "ruangan %s berukuran 9x8" % rid)
		var tot_i := 0
		for yy in Maps.height(rid):
			for xx in Maps.width(rid):
				if Maps.walkable(rid, xx, yy):
					tot_i += 1
		var seen_i := {Vector2i(4, 6): true}
		var q_i: Array[Vector2i] = [Vector2i(4, 6)]
		while not q_i.is_empty():
			var ci: Vector2i = q_i.pop_front()
			for di: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var ni: Vector2i = ci + di
				if not seen_i.has(ni) and Maps.walkable(rid, ni.x, ni.y):
					seen_i[ni] = true
					q_i.append(ni)
		_check(seen_i.size() == tot_i and Maps.walkable(rid, 4, 6) and not Maps.walkable(rid, 4, 3), "ruangan %s: lantai tersambung ke pintu, meja kasir menghalangi (%d petak)" % [rid, tot_i])
		# Masuk ke ruangan: penjaga berdiri di balik meja, bisa diajak bicara dari depan meja
		wtk._go_to_map(rid, Vector2i(4, 6))
		await process_frame
		var kp = null
		for w in wtk._warga:
			if w.toko != "":
				kp = w
		_check(kp != null and kp.toko == pair[2] and wtk._warga.size() == 1, "%s punya satu penjaga (%s)" % [rid, pair[2]])
		wtk._pos = Vector2(4.5, 4.5)
		_check(wtk._keeper_of(wtk._npc_in_range()) == kp, "di depan meja kasir %s: Bicara membuka toko lewat penjaga" % rid)
		wtk._pos = Vector2(4.5, 6.5)
		_check(wtk._keeper_of(wtk._npc_in_range()) == null, "jauh dari meja (dekat pintu): penjaga di luar jangkauan")
	# v0.43.0: Aula Pelatihan (bangunan di desa, ruangan 11x8, dua pelatih) dan layar latihan
	var door_aula: Dictionary = Maps.exit_at(Maps.DEFAULT_MAP, 38, 20)
	var out_aula: Dictionary = Maps.exit_at(Maps.AULA, 5, 7)
	_check(door_aula.get("to", "") == Maps.AULA and out_aula.get("to", "") == Maps.DEFAULT_MAP and Maps.is_interior(Maps.AULA), "pintu aula (38,20) menuju Aula Pelatihan dan pintu keluarnya kembali")
	_check(Maps.width(Maps.AULA) == 11 and Maps.height(Maps.AULA) == 8, "Aula Pelatihan berukuran 11x8")
	var tot_a := 0
	for ya in Maps.height(Maps.AULA):
		for xa in Maps.width(Maps.AULA):
			if Maps.walkable(Maps.AULA, xa, ya):
				tot_a += 1
	var seen_a := {Vector2i(5, 6): true}
	var q_a: Array[Vector2i] = [Vector2i(5, 6)]
	while not q_a.is_empty():
		var ca: Vector2i = q_a.pop_front()
		for da: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var na: Vector2i = ca + da
			if not seen_a.has(na) and Maps.walkable(Maps.AULA, na.x, na.y):
				seen_a[na] = true
				q_a.append(na)
	_check(seen_a.size() == tot_a and tot_a > 30, "aula: lantai tersambung ke pintu (%d petak)" % tot_a)
	wtk._go_to_map(Maps.AULA, Vector2i(5, 6))
	await process_frame
	var trainers_a := {}
	for wa in wtk._warga:
		if wa.toko.begins_with("latih_"):
			trainers_a[wa.toko] = wa
	_check(trainers_a.size() == 2 and wtk._warga.size() == 2, "aula punya dua pelatih (pahlawan dan prajurit)")
	wtk._pos = Vector2(4.2, 4.2)
	_check(wtk._keeper_of(wtk._npc_in_range()) == trainers_a.get("latih_pahlawan"), "dekat panggung merah: Bicara membuka latihan pahlawan")
	wtk._pos = Vector2(6.8, 4.2)
	_check(wtk._keeper_of(wtk._npc_in_range()) == trainers_a.get("latih_prajurit"), "dekat panggung hijau: Bicara membuka latihan prajurit")
	var saved_v43: Dictionary = Session.player.state.duplicate(true)
	var st_v43: Dictionary = Session.player.state
	st_v43.allies = ["pemanah"]
	st_v43.soldiers = 2
	st_v43.gold = 1000
	st_v43.inventory = [{"id": "kartu_keahlian", "qty": 2}]
	st_v43.hero_levels = {"pemanah": 3}
	st_v43.soldier_level = 2
	st_v43.training = [{"kind": "pahlawan", "target": "pemanah", "to_level": 4, "ready_at": int(Time.get_unix_time_from_system()) + 1800}]
	_check(Session.hero_level("pemanah") == 3 and Session.hero_level("ksatria") == 1 and Session.squad_level() == 2 and not Session.train_job("pahlawan").is_empty() and Session.train_job("prajurit").is_empty(), "level latihan dan latihan berjalan terbaca dari state")
	var norm_v43: Dictionary = Session._normalize_state({"hero_levels": {"pemanah": 99}, "soldier_level": 7, "training": [{"kind": "prajurit", "to_level": 3, "ready_at": 5}]})
	_check(norm_v43.hero_levels.pemanah == 20 and norm_v43.soldier_level == 7 and norm_v43.training.size() == 1 and norm_v43.training[0].ready_at == 5, "state latihan dinormalkan (level dibatasi 20)")
	Session.train_kind = "pahlawan"
	var tr_v43: Control = load("res://scenes/train.tscn").instantiate()
	get_root().add_child(tr_v43)
	await process_frame
	await process_frame
	_check(tr_v43._list.get_child_count() >= 2 and tr_v43._timers.size() == 1, "layar latihan pahlawan: baris pahlawan dan hitung mundur (%d baris)" % tr_v43._list.get_child_count())
	_check(tr_v43.duration_text(600) == "10 mnt" and tr_v43.duration_text(3900) == "1 jam 5 mnt" and tr_v43.duration_text(45) == "45 dtk", "format lama latihan")
	tr_v43.queue_free()
	await process_frame
	Session.train_kind = "prajurit"
	var tr2_v43: Control = load("res://scenes/train.tscn").instantiate()
	get_root().add_child(tr2_v43)
	await process_frame
	await process_frame
	_check(tr2_v43._list.get_child_count() >= 2 and tr2_v43._timers.is_empty(), "layar latihan prajurit: satu baris pasukan, belum ada latihan")
	tr2_v43.queue_free()
	await process_frame
	Session.train_kind = "pahlawan"
	Session.player.state = saved_v43
	var chest_cls: GDScript = load("res://scripts/chest.gd")
	var shop_cls: GDScript = load("res://scripts/shop.gd")
	_check(chest_cls.SIZE < 1.0 and chest_cls.SIZE > 0.4, "peti harta diperkecil (skala %.2f)" % chest_cls.SIZE)
	_check(shop_cls.barter_cost(15) == 1 and shop_cls.barter_cost(240) == 1 and shop_cls.barter_cost(540) == 2 and shop_cls.DIAMOND_GOLD == 500, "tukar berlian: biaya = harga/500 dibulatkan ke atas, minimal 1")
	wtk._go_to_map("toko_ramuan", Vector2i(4, 6))
	var back_door: Dictionary = Maps.exit_at("toko_ramuan", 4, 7)
	wtk._go_to_map("toko_ramuan", Vector2i(4, 6))
	var atmo_i = load("res://scripts/atmosphere.gd")
	_check(not atmo_i.outdoors("toko_ramuan") and atmo_i.outdoors(Maps.DEFAULT_MAP) and wtk._env.environment != null, "di dalam ruangan tanpa cuaca dan waktu luar")
	wtk._go_to_map(Maps.DEFAULT_MAP, back_door.at)
	await process_frame
	_check(Session.player.state.map == Maps.DEFAULT_MAP and wtk._warga.size() > 8, "keluar dari toko: kembali ke desa di depan pintu")
	wtk.queue_free()
	await process_frame
	Session.player.state = saved_toko_v39

	var cat_all_v39: Dictionary = await Api.item_catalog()
	_check(cat_all_v39.ok and cat_all_v39.data.items.size() >= 14, "katalog seluruh barang untuk ransel")
	var cat_food_v39: Dictionary = await Api.shop_get("makan")
	var food_ids_v39: Array = []
	for it: Dictionary in cat_food_v39.data.get("items", []):
		food_ids_v39.append(str(it.id))
	_check(cat_food_v39.ok and food_ids_v39.has("roti") and food_ids_v39.has("sup_ayam") and food_ids_v39.has("daging_bakar") and not food_ids_v39.has("ramuan"), "rumah makan hanya menjual makanan %s" % str(food_ids_v39))
	var cat_potion_v39: Dictionary = await Api.shop_get("toko")
	var potion_ids_v39: Array = []
	for it: Dictionary in cat_potion_v39.data.get("items", []):
		potion_ids_v39.append(str(it.id))
	_check(cat_potion_v39.ok and potion_ids_v39.has("ramuan") and potion_ids_v39.has("ramuan_kekuatan") and not potion_ids_v39.has("roti"), "toko ramuan menjual ramuan dan ramuan kekuatan, bukan makanan")
	var cat_gear_v41: Dictionary = await Api.shop_get("peralatan")
	var gear_ids_v41: Array = []
	for it: Dictionary in cat_gear_v41.data.get("items", []):
		gear_ids_v41.append(str(it.id))
	_check(cat_gear_v41.ok and gear_ids_v41.has("pedang_besi") and gear_ids_v41.has("zirah_besi") and not gear_ids_v41.has("ramuan") and not potion_ids_v39.has("pedang_besi"), "toko peralatan menjual pedang dan baju, toko ramuan tidak %s" % str(gear_ids_v41))
	# v0.42.0: gerbang tiga petak, perekrut di basecamp, prajurit biasa
	var exits_v42 := 0
	for ex_v42: Dictionary in Maps.EXITS["desa_awal"]:
		if ex_v42.to == "perbatasan" and ex_v42.pos.y == 49 and ex_v42.pos.x >= 21 and ex_v42.pos.x <= 23:
			exits_v42 += 1
	_check(exits_v42 == 3 and Maps.walkable("desa_awal", 21, 49) and Maps.walkable("desa_awal", 23, 49), "gerbang lebar: tiga petak keluar desa menuju Perbatasan")
	var rek_v42: Dictionary = {}
	for wg_v42: Dictionary in Maps.WARGA:
		if str(wg_v42.get("toko", "")).begins_with("rekrut"):
			rek_v42[str(wg_v42.toko)] = wg_v42
			_check(Maps.walkable("desa_awal", int(wg_v42.pos.x), int(wg_v42.pos.y)), "perekrut %s berdiri di petak yang bisa dilewati" % wg_v42.name)
	_check(rek_v42.has("rekrut_pahlawan") and rek_v42.has("rekrut_prajurit"), "ada perekrut pahlawan (tenda merah) dan prajurit (tenda hijau)")
	var sol_ok_v42: Dictionary = await Api.buy_soldier()
	_check(sol_ok_v42.ok or sol_ok_v42.status == 422, "beli prajurit: berhasil atau ditolak aturan (%d)" % int(sol_ok_v42.status))
	if sol_ok_v42.ok:
		Session.merge_server_player(sol_ok_v42.data)
		_check(int(Session.player.state.soldiers) >= 1, "prajurit tersimpan di state pemain")
	Session.recruit_kind = "prajurit"
	var rec_v42: Control = load("res://scenes/recruit.tscn").instantiate()
	get_root().add_child(rec_v42)
	await process_frame
	await process_frame
	_check(rec_v42.is_inside_tree(), "layar rekrut prajurit terbuka")
	rec_v42.queue_free()
	Session.recruit_kind = "pahlawan"
	var rec2_v42: Control = load("res://scenes/recruit.tscn").instantiate()
	get_root().add_child(rec2_v42)
	await process_frame
	await process_frame
	_check(rec2_v42.is_inside_tree(), "layar rekrut pahlawan terbuka")
	rec2_v42.queue_free()
	await process_frame
	var wrong_v39: Dictionary = await Api.shop_buy("ramuan", 1, "makan")
	_check(not wrong_v39.ok and wrong_v39.status == 422, "membeli ramuan di rumah makan ditolak 422")
	var no_shop_v39: Dictionary = await Api.shop_get("pasar")
	_check(not no_shop_v39.ok and no_shop_v39.status == 404, "toko tak dikenal ditolak 404")
	Session.shop_id = "makan"
	Session.shop_keeper = "Bu Wati"
	var food_shop_v39: Control = load("res://scenes/shop.tscn").instantiate()
	get_root().add_child(food_shop_v39)
	var tf_v39 := Time.get_ticks_msec()
	while food_shop_v39._catalog.is_empty() and Time.get_ticks_msec() - tf_v39 < 4000:
		await process_frame
	await process_frame
	_check(food_shop_v39._title.text.begins_with("Rumah Makan") and food_shop_v39._title.text.contains("Bu Wati"), "layar toko memakai nama toko dan penjaganya (%s)" % food_shop_v39._title.text)
	_check(food_shop_v39._list.get_child_count() > 2, "layar rumah makan menampilkan barang")
	food_shop_v39.queue_free()
	await process_frame
	Session.shop_id = "toko"
	Session.shop_keeper = ""
	var gold_f_v39: int = int(Session.player.state.gold)
	if gold_f_v39 >= 8:
		var buy_food_v39: Dictionary = await Api.shop_buy("roti", 1, "makan")
		_check(buy_food_v39.ok, "beli roti di rumah makan")
		Session.merge_server_player(buy_food_v39.data)
		var eat_full_v39: Dictionary = await Api.inventory_use("roti")
		_check(eat_full_v39.ok or eat_full_v39.status == 422, "makan roti: dimakan atau ditolak saat HP penuh")
		if eat_full_v39.ok:
			Session.merge_server_player(eat_full_v39.data)
	else:
		_check(true, "emas %d kurang untuk beli roti; dilewati" % gold_f_v39)
	Session.player.state = saved_toko_v39

	print("== v0.46: Hutan Lebat, Gua Goblin, pendamping membantu")
	_check(Maps.width(Maps.HUTAN) == 170 and Maps.height(Maps.HUTAN) == 50, "Hutan Lebat 170x50 (dua kali lebar Desa Awal)")
	_check(Maps.width(Maps.HUTAN) == 2 * Maps.width(Maps.DEFAULT_MAP), "lebar Hutan Lebat dua kali Desa Awal")
	_check(Maps.width(Maps.GUA_GOBLIN) == 25 and Maps.height(Maps.GUA_GOBLIN) == 30, "Gua Goblin 25x30")
	_check(Maps.tile_at(Maps.HUTAN, Maps.HUTAN_BOSS.x, Maps.HUTAN_BOSS.y) == "K", "singgasana bos hutan di petak K (142,47), dekat gerbang Gua Goblin")
	_check(Maps.exit_at(Maps.PERBATASAN, 22, 49).get("to", "") == Maps.HUTAN, "Perbatasan selatan menuju Hutan Lebat")
	_check(Maps.exit_at(Maps.HUTAN, 147, 49).get("to", "") == Maps.GUA_GOBLIN, "gerbang hutan menuju Gua Goblin")
	_check(Maps.exit_at(Maps.GUA_GOBLIN, 12, 29).get("to", "") == Maps.GUNUNG, "Gua Goblin selatan menuju Gunung Batu")
	_check(Maps.exit_locked(Maps.HUTAN, 147, 49, 0) and Maps.exit_locked(Maps.HUTAN, 146, 49, 2), "gerbang Gua Goblin (2 petak) terkunci sebelum tiga Goblin kalah")
	_check(not Maps.exit_locked(Maps.HUTAN, 147, 49, 3) and not Maps.exit_locked(Maps.HUTAN, 22, 0, 0) and not Maps.exit_locked(Maps.PERBATASAN, 147, 49, 0), "gerbang terbuka setelah tiga Goblin; pintu lain tidak terkunci")
	var seen_v46 := {Vector2i(22, 1): true}
	var queue_v46: Array[Vector2i] = [Vector2i(22, 1)]
	while not queue_v46.is_empty():
		var c_v46: Vector2i = queue_v46.pop_back()
		for d_v46: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n_v46: Vector2i = c_v46 + d_v46
			if not seen_v46.has(n_v46) and Maps.walkable(Maps.HUTAN, n_v46.x, n_v46.y):
				seen_v46[n_v46] = true
				queue_v46.append(n_v46)
	_check(seen_v46.has(Maps.HUTAN_BOSS) and seen_v46.has(Vector2i(147, 48)) and seen_v46.has(Vector2i(147, 49)), "dari jalan masuk hutan, singgasana dan gerbang gua dapat dicapai")
	for ex_v46: Dictionary in Maps.EXITS[Maps.HUTAN]:
		_check(Maps.walkable(ex_v46.to, ex_v46.at.x, ex_v46.at.y), "tujuan pintu hutan %s dapat dipijak" % str(ex_v46.pos))
	for kid_v46: String in ["kancil_hutan", "rubah_hutan", "ular_belang", "babi_bertaring", "serigala_hitam", "beruang_hutan", "goblin_hutan_1", "goblin_hutan_2", "goblin_hutan_3"]:
		_check(load("res://scripts/models.gd").VARIANTS.has(kid_v46), "model musuh %s terdaftar" % kid_v46)
	_check(Maps.ROAMERS[Maps.HUTAN].kinds.size() == 6 and int(Maps.ROAMERS[Maps.HUTAN].n) >= 10, "hutan punya enam jenis binatang berkeliaran")
	var ps_v46: Dictionary = Session._normalize_state({"hutan": {"wave": 9, "kills": 500}})
	_check(ps_v46.hutan.wave == 3 and ps_v46.hutan.kills == 100, "kemajuan hutan dibatasi 3 / 100")
	var saved_h_v46: Variant = Session.player.state.get("hutan", {})
	Session.merge_server_player({"state": {"hutan": {"wave": 1, "kills": 42}}})
	_check(Session.hutan_wave() == 1 and Session.hutan_kills() == 42, "state hutan dari server digabung ke Session")
	Session.player.state["hutan"] = saved_h_v46
	var CPv46: Script = load("res://scripts/companions.gd")
	_check(CPv46.CHARGE_SPEED > CPv46.MAX_SPEED and CPv46.ENGAGE_DIST > 3.0, "pendamping maju lebih cepat saat musuh mengejar")

	print("== v0.47.3: pemuat patch (editor/uji tidak menarik patch)")
	_check(Patcher.active_id == "" and Patcher.suffix() == "", "tanpa patch: id kosong, label versi bersih")
	_check(ResourceLoader.exists("res://scripts/patcher.gd"), "skrip pemuat patch ada")

	print("== v0.47: kem hutan, jalan menyambung, bos di dunia, papan misi")
	var HHv47: Script = load("res://scripts/hutan_hud.gd")
	_check(absf(HHv47.arrow_angle(Vector2(10, 10), Vector2(10, 0), 0.0)) < 0.01, "panah ke utara saat kamera menghadap utara menunjuk lurus ke atas")
	_check(absf(HHv47.arrow_angle(Vector2(10, 10), Vector2(20, 10), 0.0) - PI / 2.0) < 0.01, "panah ke timur menunjuk ke kanan")
	_check(absf(HHv47.arrow_angle(Vector2(10, 10), Vector2(20, 10), PI / 2.0) - PI) < 0.01, "kamera diputar: panah ikut berputar")
	var WDv47: Script = load("res://scripts/warga_dialog.gd")
	_check(WDv47.display_name("kapten_kem") == "Kapten Rimba", "Kapten Rimba punya nama dialog")
	_check(WDv47.kapten_line(0, 0, 0).contains("100 binatang") and WDv47.kapten_line(0, 37, 1).contains("37"), "Kapten menjelaskan tugas dan kemajuan binatang")
	_check(WDv47.kapten_line(1, 100, 0).contains("Level 2"), "Kapten menyebut Goblin berikutnya bila binatang habis")
	_check(WDv47.kapten_line(3, 0, 0).contains("terbuka"), "Kapten menyebut gerbang terbuka setelah tiga Goblin")
	var kapten_v47 := {}
	for wg_v47: Dictionary in Maps.WARGA:
		if wg_v47.id == "kapten_kem":
			kapten_v47 = wg_v47
	_check(not kapten_v47.is_empty() and kapten_v47.map == Maps.PERBATASAN and (Maps.KEM_ZONES[Maps.PERBATASAN] as Rect2i).has_point(Vector2i(int(kapten_v47.pos.x), int(kapten_v47.pos.y))), "Kapten Rimba berdiri di dalam kem, di bawah gapura desa (Perbatasan)")
	_check(not Maps.roam_free(Maps.PERBATASAN, Vector2(27.5, 3.5)) and not Maps.roam_free(Maps.PERBATASAN, Vector2(24.5, 2.5)) and Maps.roam_free(Maps.PERBATASAN, Vector2(5.5, 5.5)), "kem adalah zona aman: binatang tidak boleh masuk")
	_check(Maps.roam_free(Maps.HUTAN, Vector2(50.5, 12.5)) and Maps.roam_free(Maps.HUTAN, Vector2(22.5, 5.5)), "jalan hutan bebas dilalui binatang (kem ada di Perbatasan)")
	var has_fire_v47 := false
	var tents_v47 := 0
	for ry_v47: String in Maps.rows(Maps.PERBATASAN):
		has_fire_v47 = has_fire_v47 or ry_v47.contains("U")
		tents_v47 += ry_v47.count("A")
	_check(has_fire_v47 and tents_v47 >= 8, "kem di Perbatasan punya api unggun dan tenda")
	for pt_v47: Vector2i in [Vector2i(22, 1), Vector2i(23, 10), Vector2i(22, 12), Vector2i(60, 12), Vector2i(100, 24), Vector2i(60, 25), Vector2i(146, 30), Vector2i(147, 40), Vector2i(162, 30), Vector2i(155, 44), Vector2i(100, 45), Vector2i(22, 30), Vector2i(23, 44), Vector2i(146, 46), Vector2i(147, 48)]:
		_check(Maps.tile_at(Maps.HUTAN, pt_v47.x, pt_v47.y) == "=", "jalan hutan menyambung di %s" % str(pt_v47))
	# bos Goblin berkeliaran di dunia (bukan layar penuh) begitu 100 binatang kalah
	var saved_v47: Dictionary = Session.player.state.duplicate(true)
	Session.player.state.map = Maps.HUTAN
	Session.player.state.x = 22
	Session.player.state.y = 2
	Session.player.state.level = 4
	Session.player.state["hutan"] = {"wave": 1, "kills": 100}
	Session.offline = true
	var wh_v47: Node = load("res://scenes/world3d.tscn").instantiate()
	get_root().add_child(wh_v47)
	await process_frame
	await process_frame
	var boss_v47 = null
	var beasts_v47 := 0
	for r_v47 in wh_v47._roamers:
		if r_v47.id.begins_with("goblin_hutan_"):
			boss_v47 = r_v47
		else:
			beasts_v47 += 1
	_check(boss_v47 != null and boss_v47.id == "goblin_hutan_2" and beasts_v47 == 0, "kills 100 wave 1: hanya Goblin Level 2 berkeliaran di dunia")
	_check(boss_v47 != null and boss_v47.pos.distance_to(Vector2(142.5, 45.5)) < 1.0, "Goblin muncul di dekat singgasana")
	_check(wh_v47._hutan_hud.visible, "papan misi hutan tampil di Hutan Lebat")
	Session.player.state["hutan"] = {"wave": 1, "kills": 5}
	wh_v47._refresh_hutan()
	var still_boss_v47 := false
	for r_v47 in wh_v47._roamers:
		if r_v47.id.begins_with("goblin_hutan_") and not r_v47.fight:
			still_boss_v47 = true
	_check(not still_boss_v47, "Goblin hilang dari dunia bila belum waktunya")
	wh_v47.queue_free()
	await process_frame
	Session.offline = false
	Session.player.state = saved_v47

	print("== v0.49: jalan hutan 2 petak, tiga cabang, Kapten Rimba, Radar Musuh")
	var rows_v49 := Maps.rows(Maps.HUTAN)
	var road_v49 := {}
	for ry_v49 in range(1, rows_v49.size()):
		for rx_v49 in rows_v49[ry_v49].length():
			if rows_v49[ry_v49][rx_v49] == "=":
				road_v49[Vector2i(rx_v49, ry_v49)] = true
	var bad2_v49 := 0
	var bad3_v49 := 0
	for t_v49: Vector2i in road_v49:
		var in2 := false
		for o_v49: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
			var q_v49: Vector2i = t_v49 + o_v49
			if road_v49.has(q_v49) and road_v49.has(q_v49 + Vector2i(1, 0)) and road_v49.has(q_v49 + Vector2i(0, 1)) and road_v49.has(q_v49 + Vector2i(1, 1)):
				in2 = true
		if not in2:
			bad2_v49 += 1
		var in3 := true
		for dy_v49 in 3:
			for dx_v49 in 3:
				if not road_v49.has(t_v49 + Vector2i(dx_v49, dy_v49)):
					in3 = false
		if in3:
			bad3_v49 += 1
	_check(road_v49.size() > 300 and bad2_v49 == 0, "setiap petak jalan hutan termasuk blok 2x2 (jalan menyambung)")
	_check(bad3_v49 == 0, "tidak ada jalan hutan yang selebar 3 petak")
	# tiga cabang: hanya lewat jalan, dari jalan masuk sampai persimpangan di depan gerbang
	var junction_v49 := Vector2i(146, 44)
	for blocked_v49: Array in [[Vector2i(100, 11), Vector2i(100, 12)], [Vector2i(100, 24), Vector2i(100, 25)], [Vector2i(100, 44), Vector2i(100, 45)]]:
		var seen_v49 := {Vector2i(22, 1): true}
		var q2_v49: Array[Vector2i] = [Vector2i(22, 1)]
		while not q2_v49.is_empty():
			var c2_v49: Vector2i = q2_v49.pop_back()
			for d2_v49: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n2_v49: Vector2i = c2_v49 + d2_v49
				if seen_v49.has(n2_v49) or not road_v49.has(n2_v49) or n2_v49 in blocked_v49:
					continue
				seen_v49[n2_v49] = true
				q2_v49.append(n2_v49)
		_check(seen_v49.has(junction_v49) and seen_v49.has(Vector2i(147, 48)), "jalan tetap sampai gerbang walau cabang di x=100 terputus %s" % str(blocked_v49[0]))
	_check(Maps.tile_at(Maps.HUTAN, 146, 49) == "=" and Maps.tile_at(Maps.HUTAN, 147, 49) == "=" and Maps.tile_at(Maps.HUTAN, 148, 49) == "N" and Maps.tile_at(Maps.HUTAN, 145, 49) == "N" and Maps.tile_at(Maps.HUTAN, 160, 49) == "P", "gerbang Gua Goblin 2 petak diapit gapura batu, tembok di kiri-kanan")
	_check(not Maps.exit_locked(Maps.HUTAN, 148, 49, 0), "petak 148 bukan lagi gerbang")
	# Kapten Rimba memberi Radar Musuh; musuh hutan baru boleh dilawan setelah itu
	var st0_v49: Dictionary = Session.player.state
	var saved_h_v49: Variant = st0_v49.get("hutan", {})
	st0_v49["hutan"] = {"wave": 0, "kills": 0, "briefed": false}
	_check(not Session.hutan_started(), "pemain baru belum diarahkan Kapten")
	st0_v49["hutan"] = {"wave": 0, "kills": 7}
	_check(Session.hutan_started(), "pemain lama yang sudah punya kemajuan tidak terkunci")
	st0_v49["hutan"] = {"wave": 0, "kills": 0, "briefed": true}
	_check(Session.hutan_started() and Session._hutan({"briefed": true}).briefed, "briefed dibaca dari server")
	st0_v49["hutan"] = saved_h_v49
	_check(WDv47.kapten_line(0, 0, 0, false).contains("Radar Musuh") and not WDv47.kapten_line(0, 0, 0, true).is_empty(), "Kapten memberi radar saat pertemuan pertama")
	var RMv49: Script = load("res://scripts/radar_musuh.gd")
	var b_up_v49: Dictionary = RMv49.blip(Vector2(50, 50), Vector2(50, 40), 0.0, 85.0)
	var b_right_v49: Dictionary = RMv49.blip(Vector2(50, 50), Vector2(60, 50), 0.0, 85.0)
	_check(absf(b_up_v49.at.x) < 0.01 and b_up_v49.at.y < -10.0 and not b_up_v49.clamped, "titik radar: musuh di utara tampil di atas")
	_check(b_right_v49.at.x > 10.0 and absf(b_right_v49.at.y) < 0.01, "titik radar: musuh di timur tampil di kanan")
	_check(RMv49.blip(Vector2(50, 50), Vector2(150, 50), 0.0, 85.0).clamped, "musuh di luar jangkauan radar menempel di tepi")
	var me_v49: Dictionary = await Api.get_me()
	Session.set_player(me_v49.data)
	var s49: Dictionary = Session.player.state.duplicate(true)
	s49.map = Maps.PERBATASAN
	s49.x = 35
	s49.y = 40
	var sv1_v49: Dictionary = await Api.save(Session.player.version, s49)
	_check(sv1_v49.ok, "simpan posisi jauh dari kem")
	Session.player.version = int(sv1_v49.data.version)
	var far_v49: Dictionary = await Api.hutan_brief()
	_check(not far_v49.ok and far_v49.status == 422, "Kapten tidak terjangkau dari jauh -> 422")
	s49.map = Maps.HUTAN
	s49.x = 60
	s49.y = 12
	var sv2_v49: Dictionary = await Api.save(Session.player.version, s49)
	Session.player.version = int(sv2_v49.data.version)
	var early_v49: Dictionary = await Api.battle_start(false, "kancil_hutan")
	_check(not early_v49.ok and early_v49.status == 422, "musuh hutan sebelum bicara dengan Kapten ditolak server (422)")
	s49.map = Maps.PERBATASAN
	s49.x = 23
	s49.y = 5
	var sv3_v49: Dictionary = await Api.save(Session.player.version, s49)
	Session.player.version = int(sv3_v49.data.version)
	var brief_v49: Dictionary = await Api.hutan_brief()
	_check(brief_v49.ok, "Kapten Rimba memberi arahan di kem")
	if brief_v49.ok:
		Session.merge_server_player(brief_v49.data)
		_check(Session.hutan_started() and Session.has_radar(), "setelah arahan: radar ada di ransel dan hutan terbuka")
		var again_v49: Dictionary = await Api.hutan_brief()
		_check(again_v49.ok and int(Session.item_count("radar_musuh")) == 1, "arahan diulang: radar tetap satu")
	# musuh hutan tidak aktif sebelum arahan; radar tampil setelahnya
	var saved_w_v49: Dictionary = Session.player.state.duplicate(true)
	Session.player.state.map = Maps.HUTAN
	Session.player.state.x = 22
	Session.player.state.y = 2
	Session.player.state["hutan"] = {"wave": 0, "kills": 0, "briefed": false}
	Session.offline = true
	var wr_v49: Node = load("res://scenes/world3d.tscn").instantiate()
	get_root().add_child(wr_v49)
	await process_frame
	await process_frame
	_check(not wr_v49._hutan_ok(), "sebelum arahan Kapten musuh hutan tidak aktif")
	Session.player.state["hutan"] = {"wave": 0, "kills": 0, "briefed": true}
	Session.player.state.inventory = [{"id": "radar_musuh", "qty": 1}]
	wr_v49._update_radar()
	_check(wr_v49._hutan_ok() and wr_v49._radar.visible, "setelah arahan musuh aktif dan Radar Musuh tampil")
	Session.player.state.inventory = []
	wr_v49._update_radar()
	_check(not wr_v49._radar.visible, "tanpa radar di ransel, radar tidak tampil")
	wr_v49.queue_free()
	await process_frame
	Session.offline = false
	Session.player.state = saved_w_v49

	print("== token salah")
	Api.token = "salah"
	var bad: Dictionary = await Api.get_me()
	_check(not bad.ok and bad.status == 401, "token salah ditolak 401")
