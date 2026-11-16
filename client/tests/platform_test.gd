extends SceneTree
## Uji platform multi-game (v0.84.0): launcher, registry, GameManager, PCK, unduhan, keamanan, update,
## save, dan offline. Dijalankan oleh scripts/platform-test.sh terhadap SALINAN proyek klien tanpa folder
## games/ (meniru APK: game SD/SMP tidak ikut, harus diunduh) dan server Go sungguhan berisi katalog uji.
##
## Env: GAME_URL (server), TEST_PUB (kunci publik uji), TEST_PHASE (1 = pasang, 2 = update/rollback,
## 3 = offline), TEST_CATALOG (folder katalog server, untuk uji paket rusak).

const GameRegistry := preload("res://core/game_registry.gd")
const SecurityManager := preload("res://core/security_manager.gd")
const VersionManager := preload("res://core/version_manager.gd")
const PckReader := preload("res://core/pck_reader.gd")
const SaveManager := preload("res://core/save_manager.gd")
const PackageManager := preload("res://core/package_manager.gd")
const QuestionGen := preload("res://shared/edu/question_gen.gd")
const State := GameRegistry.State

var _failed := false
var GM: Node
## Versi paket SD sebelum dan sesudah "update" (diisi scripts/platform-test.sh).
var V1 := OS.get_environment("TEST_SD_V1") if OS.get_environment("TEST_SD_V1") != "" else "1.0.0"
var V2 := OS.get_environment("TEST_SD_V2") if OS.get_environment("TEST_SD_V2") != "" else "1.0.1"


func _initialize() -> void:
	await process_frame
	GM = root.get_node("GameManager")
	var pub := CryptoKey.new()
	if pub.load(OS.get_environment("TEST_PUB"), true) != OK:
		print("  GAGAL kunci publik uji tidak terbaca")
		quit(1)
		return
	SecurityManager.override_public_key(pub)
	GM.registry.load_all()  # muat ulang katalog tersimpan dengan kunci uji
	GM.api.base_url_override = OS.get_environment("GAME_URL")
	match OS.get_environment("TEST_PHASE"):
		"1":
			_unit_tests()
			await _phase_install()
		"2":
			await _phase_update()
		"3":
			await _phase_offline()
		_:
			print("  GAGAL TEST_PHASE tidak dikenal")
			_failed = true
	SecurityManager.override_public_key(null)
	print("HASIL: " + ("GAGAL" if _failed else "LULUS"))
	quit(1 if _failed else 0)


func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  GAGAL ") + label)
	if not cond:
		_failed = true


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## Tunggu sampai status game id bukan lagi DOWNLOADING/VERIFYING/INSTALLING (maks `limit` detik).
func _wait_idle(id: String, limit := 60.0) -> Dictionary:
	var t := 0.0
	while t < limit:
		var e: Dictionary = GM.game(id)
		if not (e.state in [State.DOWNLOADING, State.VERIFYING, State.INSTALLING]):
			return e
		await _wait(0.1)
		t += 0.1
	return GM.game(id)


func _wait_scene(path: String, limit := 10.0) -> bool:
	var t := 0.0
	while t < limit:
		if current_scene != null and current_scene.scene_file_path == path:
			return true
		await _wait(0.1)
		t += 0.1
	return false


# --- Uji unit (tanpa jaringan) ------------------------------------------------------------------

func _unit_tests() -> void:
	print("== Versi")
	_check(VersionManager.compare("1.2.0", "1.10.0") < 0, "1.2.0 < 1.10.0")
	_check(VersionManager.compare("0.84.0", "0.84.0") == 0, "versi sama")
	_check(not VersionManager.is_valid("1.0") and not VersionManager.is_valid("01.0.0") and not VersionManager.is_valid("1.0.0-x"), "versi tidak sah ditolak")
	var m := {"type": "download", "min_launcher_version": "99.0.0", "min_engine_version": "4.7.0"}
	_check(VersionManager.incompatibility(m) != "", "launcher terlalu lama ditolak")
	m.min_launcher_version = "0.1.0"
	m.min_engine_version = "4.6.0"
	_check(VersionManager.incompatibility(m) != "", "paket mesin 4.6 ditolak di mesin 4.7")
	m.min_engine_version = VersionManager.engine_version()
	_check(VersionManager.incompatibility(m) == "", "paket mesin sama diterima")

	print("== Validasi manifest & path")
	var good := {"id": "education_sd", "name": "SD", "version": "1.0.0", "type": "download",
		"entry_scene": "res://games/education_sd/main.tscn", "min_launcher_version": "0.84.0",
		"min_engine_version": "4.7.2", "package": "education_sd-1.0.0.pck", "size": 10, "sha256": "a".repeat(64)}
	_check(SecurityManager.validate_manifest(good) == "", "manifest sah diterima")
	var bad_cases := {
		"id kapital": {"id": "Education"},
		"id traversal": {"id": "../x"},
		"entry di luar namespace": {"entry_scene": "res://scripts/login.tscn"},
		"entry traversal": {"entry_scene": "res://games/education_sd/../../scripts/x.tscn"},
		"entry user://": {"entry_scene": "user://games/education_sd/main.tscn"},
		"paket traversal": {"package": "../evil.pck"},
		"sha rusak": {"sha256": "xyz"},
		"ukuran nol": {"size": 0},
		"versi rusak": {"version": "1.0"},
		"tipe asing": {"type": "apk"},
	}
	for label in bad_cases:
		var mm := good.duplicate()
		mm.merge(bad_cases[label], true)
		_check(SecurityManager.validate_manifest(mm) != "", "ditolak: " + label)
	_check(SecurityManager.validate_manifest(good, "education_smp") != "", "ditolak: id manifest beda dengan yang diminta")

	print("== Tanda tangan")
	var raw := FileAccess.get_file_as_bytes(GameRegistry.CATALOG_PATH)
	var sig := FileAccess.get_file_as_string(GameRegistry.CATALOG_SIG_PATH)
	if raw.is_empty():
		var cat_dir := OS.get_environment("TEST_CATALOG")
		raw = FileAccess.get_file_as_bytes(cat_dir + "/catalog.json")
		sig = FileAccess.get_file_as_string(cat_dir + "/catalog.sig")
	_check(SecurityManager.verify_signature(raw, sig), "tanda tangan katalog asli sah")
	var tampered := raw.duplicate()
	tampered[tampered.size() / 2] = tampered[tampered.size() / 2] ^ 1
	_check(not SecurityManager.verify_signature(tampered, sig), "katalog diubah 1 bit ditolak")
	_check(not SecurityManager.verify_signature(raw, "AAAA"), "tanda tangan salah ditolak")
	_check(not SecurityManager.verify_signature(raw, ""), "tanda tangan kosong ditolak")
	var other := Crypto.new().generate_rsa(2048)
	_check(not SecurityManager.verify_signature(raw, sig, other), "kunci publik lain menolak")

	print("== Save per game")
	SaveManager.save("uji_a", {"n": 1}, 1)
	SaveManager.save("uji_b", {"n": 2}, 1)
	_check(int(SaveManager.load_progress("uji_a", 1).data.n) == 1 and int(SaveManager.load_progress("uji_b", 1).data.n) == 2, "progres antargame terpisah")
	SaveManager.save("uji_a", {"n": 3}, 1)
	var f := FileAccess.open(SaveManager.path_for("uji_a"), FileAccess.WRITE)
	f.store_string("{rusak")
	f.close()
	var rest := SaveManager.load_progress("uji_a", 1)
	_check(not rest.is_empty() and bool(rest.restored_from_backup) and int(rest.data.n) == 1, "save rusak dipulihkan dari cadangan .bak")
	SaveManager.save("uji_m", {"skor": 5}, 1)
	var mig := SaveManager.load_progress("uji_m", 2, {1: func(d: Dictionary) -> Dictionary:
		d["nilai"] = d.skor * 20
		return d})
	_check(int(mig.get("schema_version", 0)) == 2 and int(mig.data.nilai) == 100, "migrasi skema v1 -> v2")
	_check(SaveManager.load_progress("uji_m", 2).data.has("nilai"), "hasil migrasi tersimpan")
	_check(not SaveManager.save("../x", {}, 1), "id save tidak sah ditolak")

	print("== Pembuat soal")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all_ok := true
	for cfg in [{"type": "arith", "ops": ["+", "-", "x", ":"], "min": 1, "max": 20, "count": 20},
			{"type": "arith", "ops": ["+", "-", "x"], "min": -20, "max": 20, "negative": true, "count": 20},
			{"type": "linear", "count": 20}, {"type": "power", "count": 20}, {"type": "fraction_compare", "count": 10}]:
		var qs := QuestionGen.generate(cfg, rng)
		if qs.size() < int(cfg.count) / 2:
			all_ok = false
		for q: Dictionary in qs:
			var opts: Array = q.options
			if int(q.answer) < 0 or int(q.answer) >= opts.size() or opts.size() < 3:
				all_ok = false
			var uniq := {}
			for o in opts:
				uniq[o] = true
			if uniq.size() != opts.size():
				all_ok = false
	_check(all_ok, "soal acak: jawaban ada di pilihan, pilihan unik")
	# Jawaban aritmetika benar-benar dihitung benar.
	rng.seed = 11
	var arith_ok := true
	for q: Dictionary in QuestionGen.generate({"type": "arith", "ops": ["+", "-", "x"], "min": -9, "max": 9, "negative": true, "count": 25}, rng):
		var expr := Expression.new()
		var text := str(q.q).replace(" = ?", "").replace("×", "*")
		if expr.parse(text) == OK and int(expr.execute()) != int(q.options[int(q.answer)]):
			arith_ok = false
	_check(arith_ok, "kunci jawaban aritmetika = hasil hitungan")


# --- Fase 1: katalog, unduh (putus + lanjut), verifikasi, pasang, main, kembali --------------------

func _phase_install() -> void:
	print("== Launcher tanpa katalog / sebelum online")
	var ids: Array = []
	for e: Dictionary in GM.games():
		ids.append(e.id)
	_check(ids.has("adventure"), "game bawaan Petualangan selalu ada")
	_check(GM.game("adventure").state == State.INSTALLED, "Petualangan berstatus INSTALLED (bawaan APK)")
	_check(not ResourceLoader.exists("res://games/education_sd/main.tscn"), "game SD tidak ada di APK (harus diunduh)")

	print("== Katalog server")
	var ok: bool = await GM.refresh_catalog()
	_check(ok and GM.online, "katalog bertanda tangan diterima, status online")
	_check(GM.game("education_sd").state == State.NOT_INSTALLED, "SD: NOT_INSTALLED")
	_check(GM.game("education_smp").state == State.NOT_INSTALLED, "SMP: NOT_INSTALLED")
	_check(FileAccess.file_exists(GameRegistry.CATALOG_PATH), "katalog disimpan untuk offline")
	_check(GM.registry.accept_catalog("{\"games\":[]}".to_utf8_buffer(), "AAAA") != "" and GM.registry.catalog.has("education_sd"),
		"katalog palsu ditolak dan katalog lama tetap dipakai")

	print("== Launcher (scene)")
	change_scene_to_file("res://launcher/scenes/main_menu.tscn")
	_check(await _wait_scene("res://launcher/scenes/main_menu.tscn"), "launcher terbuka")
	await _wait(0.5)
	var launcher = current_scene
	_check(launcher._cards.has("adventure") and launcher._cards.has("education_sd") and launcher._cards.has("education_smp"),
		"launcher menampilkan game bawaan + game unduhan")
	var sd_m: Dictionary = GM.game("education_sd").manifest
	_check(str(sd_m.get("icon_sha256", "")).length() == 64, "manifest SD bertanda tangan memuat icon_sha256")
	var icon_rect: TextureRect = null
	for i in 30:
		icon_rect = launcher._cards["education_sd"].find_child("Icon", true, false)
		if icon_rect.texture != null:
			break
		await _wait(0.1)
	_check(icon_rect.texture != null and icon_rect.texture.get_width() > 0, "ikon game SD diunduh dari server & tampil di kartu sebelum dipasang")
	var cached := DirAccess.get_files_at(launcher.ICON_DIR)
	_check(cached.size() == 1 and cached[0].begins_with("education_sd-"), "ikon disimpan di user://icons untuk offline")
	var raw := FileAccess.get_file_as_bytes(launcher.ICON_DIR + cached[0])
	_check(launcher._png_texture(raw, "0".repeat(64)) == null, "ikon dengan sha256 berbeda dari manifest ditolak")
	launcher._select("education_sd")
	_check(launcher._b_download.visible and not launcher._b_play.visible, "SD: tombol DOWNLOAD tampil, MAINKAN tidak")
	launcher._select("adventure")
	_check(launcher._b_play.visible and not launcher._b_delete.visible, "Petualangan: MAINKAN tampil, HAPUS tidak")

	print("== Pengaturan launcher: server & pembaruan aplikasi")
	launcher.open_settings()
	await _wait(0.2)
	var ls = launcher.settings
	_check(ls != null and ls.url_edit.text == GM.api.base_url() and ls.version_label.text.contains(ProjectSettings.get_setting("application/config/version")),
		"Pengaturan launcher: alamat server & versi aplikasi tampil")
	for i in 40:
		if ls.update_msg.text != "Memeriksa pembaruan...":
			break
		await _wait(0.1)
	_check(ls.update_msg.text.contains("terbaru") and not ls.btn_update.visible, "pembaruan diperiksa ke server: aplikasi sudah terbaru (%s)" % ls.update_msg.text)
	ls._apply({"latest_client": "99.0.0", "min_client": "0.1.0", "update_url": "https://github.com/x/y/releases/latest"})
	_check(ls.update_available and ls.btn_update.visible and launcher.update_available and launcher.settings_btn.text.contains("update"),
		"versi baru: tombol Unduh dan pasang + tanda di tombol Pengaturan launcher")
	var good: String = GM.api.base_url()
	ls.url_edit.text = "http://127.0.0.1:1"
	await ls.test_server()
	_check(ls.server_msg.text.begins_with("Server tidak terjangkau") and GM.api.base_url() == good, "alamat salah ditolak, alamat lama tetap dipakai")
	ls.url_edit.text = good
	await ls.test_server()
	_check(ls.server_msg.text.begins_with("Server tersambung") and GM.api.base_url() == good, "alamat benar: server tersambung & disimpan")
	await _wait(0.5)
	ls.close()
	await _wait(0.1)
	_check(launcher.settings == null and quit_on_go_back, "Pengaturan ditutup, kembali ke daftar game")

	print("== Unduhan putus lalu dilanjutkan (HTTP Range)")
	var first_progress := [-1]
	GM.downloads.fail_after_bytes = 60000
	GM.downloads.throttle_bytes_per_poll = 16384
	GM.install("education_sd")
	var e: Dictionary = await _wait_idle("education_sd")
	_check(e.state == State.ERROR and str(e.reason).contains("terputus"), "unduhan putus -> ERROR (" + str(e.reason) + ")")
	var part := "user://user_data/cache/downloads/education_sd-%s.part" % V1
	var have := SecurityManager.file_size(part)
	_check(have >= 60000, "berkas sementara disimpan untuk dilanjutkan (%d byte)" % have)
	_check(not GM.registry.installed.has("education_sd"), "belum tercatat terpasang setelah unduhan putus")
	var cb := func(id: String, r: int, _t: int) -> void:
		if id == "education_sd" and first_progress[0] < 0:
			first_progress[0] = r
	GM.download_progress.connect(cb)
	GM.install("education_sd")
	e = await _wait_idle("education_sd")
	GM.download_progress.disconnect(cb)
	GM.downloads.throttle_bytes_per_poll = 0
	_check(first_progress[0] >= have, "unduhan dilanjutkan dari byte %d, bukan dari 0" % first_progress[0])
	_check(e.state == State.INSTALLED, "SD: INSTALLED setelah verifikasi (" + str(e.state_name) + " " + str(e.reason) + ")")
	_check(not FileAccess.file_exists(part), "berkas sementara dibersihkan")
	var rec: Dictionary = GM.registry.installed.get("education_sd", {})
	_check(str(rec.get("package_path", "")).begins_with("user://user_data/packages/education_sd/"), "paket di folder namespace game")

	print("== Paket rusak di server ditolak (SHA-256)")
	var cat_dir := OS.get_environment("TEST_CATALOG")
	var srv_pck := cat_dir + "/education_smp/education_smp-1.0.0.pck"
	var orig := FileAccess.get_file_as_bytes(srv_pck)
	var broken := orig.duplicate()
	broken[broken.size() - 100] = broken[broken.size() - 100] ^ 0xFF
	var wf := FileAccess.open(srv_pck, FileAccess.WRITE)
	wf.store_buffer(broken)
	wf.close()
	GM.install("education_smp")
	e = await _wait_idle("education_smp")
	_check(e.state == State.ERROR and str(e.reason).contains("SHA-256"), "SMP rusak ditolak: " + str(e.reason))
	_check(not GM.registry.installed.has("education_smp"), "paket rusak tidak tercatat terpasang")
	wf = FileAccess.open(srv_pck, FileAccess.WRITE)
	wf.store_buffer(orig)
	wf.close()

	print("== Manifest bertanda tangan salah ditolak")
	var sig_path := cat_dir + "/education_smp/manifest.sig"
	var real_sig := FileAccess.get_file_as_string(sig_path)
	var sf := FileAccess.open(sig_path, FileAccess.WRITE)
	sf.store_string(FileAccess.get_file_as_string(cat_dir + "/education_sd/manifest.sig"))
	sf.close()
	GM.install("education_smp")
	e = await _wait_idle("education_smp")
	_check(e.state == State.ERROR and str(e.reason).contains("Tanda tangan"), "manifest dengan tanda tangan salah ditolak")
	sf = FileAccess.open(sig_path, FileAccess.WRITE)
	sf.store_string(real_sig)
	sf.close()

	print("== Paket untuk namespace lain ditolak")
	var sd_pck := str(GM.registry.installed.education_sd.package_path)
	var info := PckReader.read(sd_pck)
	_check(info.ok and PckReader.check_paths(info.files, "education_sd") == "", "PCK SD sah untuk namespace education_sd")
	_check(PckReader.check_paths(info.files, "education_smp") != "", "PCK SD ditolak bila diaku sebagai education_smp")
	_check(PckReader.check_paths([{"path": "scripts/login.gd", "flags": 0}, {"path": "games/x/a", "flags": 0}], "x") != "", "PCK yang menyentuh skrip aplikasi ditolak")
	_check(PckReader.check_paths([{"path": "games/x/a", "flags": 2}], "x") != "", "PCK berflag hapus ditolak")
	var trunc := "user://uji_potong.pck"
	var tf := FileAccess.open(trunc, FileAccess.WRITE)
	tf.store_buffer(FileAccess.get_file_as_bytes(sd_pck).slice(0, 2000))
	tf.close()
	_check(not PckReader.read(trunc).ok, "PCK terpotong ditolak")

	print("== Pasang SMP (benar)")
	GM.install("education_smp")
	e = await _wait_idle("education_smp")
	_check(e.state == State.INSTALLED, "SMP: INSTALLED")

	print("== Main game SD lalu kembali ke launcher")
	GM.play("education_sd")
	_check(await _wait_scene("res://games/education_sd/main.tscn"), "entry scene SD berjalan dari paket PCK")
	await _wait(0.3)
	var game = current_scene
	_check(GM.active_game_id == "education_sd", "game aktif tercatat")
	_check(game != null and str(game.get("game_id")) == "education_sd" and game.worlds.islands.size() == 6 and game.data.questions.size() >= 200,
		"skrip game + data enam pulau + bank soal dari paket termuat (%d soal)" % (game.data.questions.size() if game != null else 0))
	# Dunia Enam Pulau: buat profil petualang, masuk peta, lalu masuk Pulau 1.
	game.set_profile({"name": "Uji", "grade": 1, "hero": "laki", "outfit": "warna_merah"})
	game.close_modal()
	game.arrive("pulau1")
	await _wait(0.3)
	_check(game.screen == "island" and game.world != null, "dunia 3D Pulau 1 berjalan dari paket PCK")
	var saved := SaveManager.load_progress("education_sd", 3)
	_check(str(saved.data.profile.name) == "Uji" and str(saved.data.world.island) == "pulau1", "progres tersimpan di user_data/progress/education_sd")
	_check(SaveManager.load_progress("education_smp", 1).is_empty(), "progres SMP tidak tercampur")
	await GM.exit_to_launcher()
	_check(await _wait_scene("res://launcher/scenes/main_menu.tscn"), "kembali ke launcher")
	_check(GM.active_game_id == "", "tidak ada game aktif di launcher")

	print("== Main SMP setelah SD (game sebelumnya sudah dilepas)")
	GM.play("education_smp")
	_check(await _wait_scene("res://games/education_smp/main.tscn"), "SMP berjalan")
	await _wait(0.2)
	_check(str(current_scene.get("game_id")) == "education_smp", "skrip SMP, bukan SD")
	_check(root.get_node_or_null("SDMain") == null, "scene SD sudah dilepas")
	await GM.exit_to_launcher()
	await _wait_scene("res://launcher/scenes/main_menu.tscn")

	print("== Game Petualangan (bawaan)")
	GM.play("adventure")
	_check(await _wait_scene("res://scenes/login.tscn"), "Petualangan (layar masuk lama) terbuka dari launcher")
	await _wait(0.5)
	var has_btn := false
	for b in current_scene.find_children("*", "Button", true, false):
		if (b as Button).text == "Semua Game":
			has_btn = true
	_check(has_btn, "tombol 'Semua Game' ada di beranda Petualangan")
	await GM.exit_to_launcher()
	_check(await _wait_scene("res://launcher/scenes/main_menu.tscn"), "kembali dari Petualangan ke launcher")

	print("== Paket terpasang diubah di HP -> ditolak saat dimuat ulang")
	var copy_path := "user://uji_salin.pck"
	DirAccess.copy_absolute(sd_pck, copy_path)
	var bytes := FileAccess.get_file_as_bytes(copy_path)
	bytes[100] = bytes[100] ^ 1
	var cf := FileAccess.open(copy_path, FileAccess.WRITE)
	cf.store_buffer(bytes)
	cf.close()
	_check(PackageManager.verify_file(copy_path, GM.registry.installed.education_sd.manifest).contains("SHA-256"), "salinan paket yang diubah ditolak")


# --- Fase 2 (proses baru): update per game + rollback ----------------------------------------------

func _phase_update() -> void:
	print("== Update per game")
	var before_smp: Dictionary = GM.registry.installed.education_smp.duplicate(true)
	await GM.refresh_catalog()
	var e: Dictionary = GM.game("education_sd")
	_check(e.state == State.UPDATE_AVAILABLE and e.installed_version == V1 and e.latest_version == V2,
		"SD: UPDATE_AVAILABLE %s -> %s" % [V1, V2])
	_check(GM.game("education_smp").state == State.INSTALLED, "SMP tidak ikut berubah (tetap INSTALLED)")
	_check(GM.game("adventure").state == State.INSTALLED, "Petualangan tidak ikut berubah")
	var progress_before := SaveManager.load_progress("education_sd", 2)
	GM.install("education_sd")
	e = await _wait_idle("education_sd")
	_check(e.state == State.INSTALLED and e.installed_version == V2, "SD diperbarui ke " + V2)
	_check(GM.registry.installed.education_sd.previous.version == V1, "versi %s disimpan untuk rollback" % V1)
	_check(FileAccess.file_exists(str(GM.registry.installed.education_sd.previous.package_path)), "berkas %s masih ada" % V1)
	_check(GM.registry.installed.education_smp.sha256 == before_smp.sha256, "paket SMP tidak diunduh ulang")
	var progress_after := SaveManager.load_progress("education_sd", 2)
	_check(JSON.stringify(progress_after.data) == JSON.stringify(progress_before.data) and not progress_before.is_empty(), "progres SD utuh setelah update")
	GM.play("education_sd")
	_check(await _wait_scene("res://games/education_sd/main.tscn"), "SD %s berjalan" % V2)
	var gj = JSON.parse_string(FileAccess.get_file_as_string("res://games/education_sd/game.json"))
	_check(typeof(gj) == TYPE_DICTIONARY and str(gj.version) == V2, "isi paket yang dimuat adalah versi " + V2)
	await GM.exit_to_launcher()
	await _wait_scene("res://launcher/scenes/main_menu.tscn")

	print("== Rollback")
	var rb: Dictionary = GM.packages.rollback("education_sd")
	_check(rb.ok and GM.registry.installed.education_sd.version == V1, "rollback ke " + V1)
	_check(GM.game("education_sd").state == State.UPDATE_AVAILABLE, "setelah rollback, update %s ditawarkan lagi" % V2)
	var lr: Dictionary = GM.packages.load_game("education_sd")
	_check(not lr.ok and lr.restart_required, "versi lain sudah dimuat di sesi ini -> minta buka ulang aplikasi")

	print("== Hapus game (progres tetap)")
	GM.uninstall("education_smp")
	_check(GM.game("education_smp").state == State.NOT_INSTALLED, "SMP dihapus -> NOT_INSTALLED")
	_check(not DirAccess.dir_exists_absolute("user://user_data/packages/education_smp"), "folder paket SMP dihapus")
	GM.uninstall("adventure")
	_check(GM.game("adventure").state == State.INSTALLED, "game bawaan tidak bisa dihapus")
	GM.install("education_smp")
	e = await _wait_idle("education_smp")
	_check(e.state == State.INSTALLED, "SMP dipasang ulang")

	print("== Sinkron progres ke server (akun) dan pulihkan di HP baru")
	var api := root.get_node("Api")
	var req := HTTPRequest.new()
	root.add_child(req)
	var body := JSON.stringify({"name": "MuridUji", "email": "murid@uji.id", "password": "sandi-rahasia-1"})
	req.request(OS.get_environment("GAME_URL") + "/v1/players", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	var res: Array = await req.request_completed
	var reg = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	_check(int(res[1]) == 201 and typeof(reg) == TYPE_DICTIONARY and str(reg.get("token", "")) != "", "akun uji dibuat")
	api.token = str(reg.get("token", ""))
	var sd := SaveManager.load_progress("education_sd", 3)
	GM.save_progress("education_sd", sd.data, 3)
	await _wait(1.5)
	_check(not FileAccess.get_file_as_string("user://user_data/registry/sync_pending.json").contains("education_sd"), "progres SD terkirim ke server")
	var srv: Dictionary = await GM.api.progress_get("education_sd")
	_check(srv.ok and str(srv.data.data.profile.name) == "Uji", "server menyimpan progres SD akun ini")
	# HP baru: progres lokal kosong -> dipulihkan dari server.
	for f in ["save.json", "save.json.bak"]:
		DirAccess.remove_absolute(SaveManager.dir_for("education_sd") + "/" + f)
	var restored: Dictionary = await GM.restore_progress_from_server("education_sd", 3)
	_check(str(restored.get("profile", {}).get("name", "")) == "Uji", "progres dipulihkan dari server ke HP")
	var smp_srv: Dictionary = await GM.api.progress_get("education_smp")
	_check(smp_srv.ok and not (smp_srv.data.get("data", {}) as Dictionary).has("profile"), "progres SMP di server terpisah dari SD")
	api.token = ""
	req.queue_free()


# --- Fase 3 (proses baru): offline -----------------------------------------------------------------

func _phase_offline() -> void:
	print("== Offline (server mati)")
	GM.api.base_url_override = "http://127.0.0.1:9"
	var ok: bool = await GM.refresh_catalog()
	_check(not ok and not GM.online, "katalog gagal diambil -> offline")
	_check(GM.registry.catalog.has("education_sd"), "katalog terakhir yang sah tetap dipakai")
	change_scene_to_file("res://launcher/scenes/main_menu.tscn")
	_check(await _wait_scene("res://launcher/scenes/main_menu.tscn"), "launcher terbuka tanpa server")
	await _wait(0.3)
	var l = current_scene
	l._select("education_sd")
	_check(l._b_play.visible, "MAINKAN tetap tampil saat offline")
	l._select("education_smp")
	_check(GM.game("adventure").state == State.INSTALLED, "Petualangan tetap tersedia")
	GM.play("education_sd")
	_check(await _wait_scene("res://games/education_sd/main.tscn"), "game unduhan dimainkan offline")
	await _wait(0.3)
	var g = current_scene
	_check(str(g.p.profile.name) == "Uji", "progres lokal terbaca offline")
	g.arrive("pulau1")
	await _wait(0.2)
	_check(g.screen == "island", "Pulau 1 bisa dijelajahi offline")
	g.save()
	_check(FileAccess.file_exists("user://user_data/registry/sync_pending.json"), "progres ditandai untuk sinkron saat online")
	await GM.exit_to_launcher()
	_check(await _wait_scene("res://launcher/scenes/main_menu.tscn"), "kembali ke launcher saat offline")

