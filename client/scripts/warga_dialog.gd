extends RefCounted
## Dialog singkat warga desa. Isinya mengikuti alur cerita utama (4 misi berantai):
##   Nenek (kucing/ayam liar) -> Petani (goblin gunung) -> Monster Batu (gunung) -> Raja Iblis (gua)
## `tahap` = banyak misi utama yang sudah tuntas (0-4); warga berkomentar sesuai tahap itu.
## Tiap tahap punya 1-2 kalimat yang bergantian setiap kali diajak bicara.

## Misi utama berurutan; kunci = id misi di server.
const MAIN_QUESTS := ["selamatkan_nenek", "selamatkan_petani", "usir_ogre", "hentikan_raja_goblin"]

## id warga -> {"name": nama tampil, "stages": [[kalimat tahap 0], [tahap 1], ... [tahap 4]]}
const WARGA := {
	"bu_sari": {"name": "Bu Sari", "stages": [
		["Semalam ayam dan kucing liar mengamuk di pasar. Kasihan Nenek di sebelah barat, sayurannya habis dirusak.",
		"Kamu ksatria baru itu, ya? Bicaralah dengan Nenek dulu. Dia sudah lama menunggu bantuan."],
		["Syukurlah Nenek selamat! Tapi Petani bilang ada goblin hijau turun dari Gunung Batu. Temui dia di jalan raya.",
		"Bawalah ramuan sebelum ke perbatasan. Aku sudah lihat terlalu banyak orang pulang dengan luka."],
		["Goblin-goblin itu mundur berkat kamu. Tapi tiap malam ada dentuman dari Gunung Batu. Kamu dengar juga?",
		"Anak-anak mulai takut tidur. Katanya ada raksasa batu di gunung."],
		["Monster Batu sudah tumbang! Tapi para pedagang bilang ada gua gelap di bawah gunung, penuh orc.",
		"Kalau kamu masuk gua itu, pulanglah hidup-hidup. Aku siapkan sup hangat untukmu."],
		["Raja Iblis sudah tumbang! Malam ini kita masak besar untuk merayakan, Ksatria.",
		"Desa ini ramai lagi. Semua karena kamu."]]},
	"mbak_dewi": {"name": "Mbak Dewi", "stages": [
		["Kamu pasti ksatria yang dibicarakan semua orang. Mulailah dari Nenek di sebelah barat, ya.",
		"Aku pedagang kain. Sejak monster berdatangan, dagangan sepi sekali."],
		["Petani gemetar semalam, katanya goblin menginjak ladangnya. Dia ada di jalan raya, dekat alun-alun.",
		"Goblin itu menjatuhkan taring. Nenek butuh taring untuk meracik obat, lho."],
		["Jalan perbatasan makin sepi. Serigala liar dan goblin mulai muncul dari arah gunung.",
		"Pedagang yang pulang bilang orc itu keluar dari satu lubang di gunung."],
		["Konon ada permata merah berkilau di dalam gua itu. Hati-hati, jangan sembarangan disentuh.",
		"Permata itu katanya sumber kekuatan pasukan iblis."],
		["Permata merahnya sudah aman, syukurlah! Kalau kamu butuh kain untuk jubah baru, aku beri harga teman, Ksatria.",
		"Pedagang mulai berdatangan lagi tiap pagi. Rezeki kami kembali."]]},
	"pak_joko": {"name": "Pak Joko", "stages": [
		["Kalau mau menyeberang sungai, latihan dulu di rumput sekitar desa. Naikkan levelmu, Nak.",
		"Aku dulu prajurit raja. Aku tahu mana monster yang bisa dilawan dan mana yang harus dihindari."],
		["Gunung di selatan itu sarang goblin. Beli ramuan dan bawa pedang yang layak.",
		"Goblin keras kepala, tapi lemah kalau diserang bergantian. Jangan panik."],
		["Gunung Batu itu sarang Monster Batu. Bawa zirah dan pedang yang bagus, jangan nekat.",
		"Aku sudah tua untuk bertarung, tapi aku tahu jalannya: dari Perbatasan terus ke selatan."],
		["Di gua paling dalam ada singgasana. Siapa pun yang duduk di sana bukan manusia lagi.",
		"Kamu satu-satunya harapan kami. Aku bangga padamu, Nak."],
		["Besi bekas pasukan iblis itu kutempa jadi sabit dan cangkul. Dunia damai, Nak.",
		"Kalau butuh pedang baru, kunjungi aku. Untuk pahlawan, harga teman."]]},
	"pak_budi": {"name": "Pak Budi", "stages": [
		["Ladang kami hampir panen. Semoga monster tidak turun ke sini.",
		"Nenek penjual sayur itu langgananku. Tolong jaga dia, ya."],
		["Aku lihat goblin hijau mengendap di hutan perbatasan. Mereka membawa taring yang katanya bisa jadi obat.",
		"Pagar ladangku sudah dua kali dijebol. Untung kamu datang."],
		["Tanah bergetar dari arah gunung. Ayam-ayamku sampai tak mau bertelur.",
		"Kalau gunung itu sunyi lagi, aku traktir kamu lima karung sayur."],
		["Orc-orc itu keluar dari satu lubang di gunung. Kalau kamu menutupnya, desa ini selamat.",
		"Aku lihat cahaya merah dari arah gua semalam. Perasaanku tidak enak."],
		["Ladang kami aman lagi. Ambil sayur secukupnya, Ksatria.",
		"Besok aku menanam bibit baru. Tahun ini panen paling baik sejak lama."]]},
	"rina": {"name": "Rina", "stages": [
		["Kak Ksatria! Ayam di kandang itu galak, jangan dekat-dekat!",
		"Ibuku bilang aku tidak boleh keluar gerbang. Di luar banyak monster."],
		["Aku lihat Kakak mengusir kucing liar! Keren sekali!",
		"Kata Pak Petani, Kakak mau ke ladang perbatasan? Aku boleh ikut? ...Tidak boleh, ya."],
		["Kata Ibu ada raksasa batu di gunung. Kakak tidak takut?",
		"Aku mimpi raksasa batu itu menangis. Aneh, ya."],
		["Kakak mengalahkan raksasa batu! Pasti sekarang Kakak sangat kuat!",
		"Kalau Kakak menang lawan raja di gua, aku mau jadi ksatria juga!"],
		["Kakak pahlawan kami! Boleh aku pegang pedang Kakak sekali saja?",
		"Aku mau jadi seperti Kakak waktu besar nanti!"]]},
	"dika": {"name": "Dika", "stages": [
		["Jangan berenang di sungai, Kak. Airnya dalam! Lewat jembatan saja.",
		"Aku sudah hafal tiap batu di alun-alun. Ayo main petak umpet!"],
		["Aku dengar lolongan serigala dari seberang sungai. Serem!",
		"Kakak sudah ketemu goblin? Mereka hijau dan bau, ya?"],
		["Gunung Batu itu tempat peri tinggal, kata Nenek. Tapi Bu Sari bilang itu monster. Siapa yang benar?",
		"Aku lihat kunang-kunang merah di langit semalam."],
		["Kakak menang lagi! Teman-temanku sekarang bercita-cita jadi ksatria.",
		"Kalau kakak pulang dari gua, ceritakan padaku, ya!"],
		["Hore, Kakak menang! Desa kita aman lagi!",
		"Besok aku mau bermain sampai ke ladang. Sekarang tidak ada yang melarang!"]]},
	"kepala_suku": {"name": "Kepala Suku", "stages": [
		["Selamat datang di desaku, Ksatria. Dulu desa ini tenang, sekarang monster bermunculan di hutan perbatasan.",
		"Temui Nenek di sebelah barat. Dia yang pertama membutuhkan bantuanmu."],
		["Kamu sudah menolong Nenek, desa ini berhutang padamu. Petani punya kabar buruk soal goblin.",
		"Setiap malam kami berkumpul di bawah menara lampu. Lampunya menjaga kami tetap berani."],
		["Pasukan monster semakin dekat. Pastikan ramuan dan senjatamu siap sebelum ke gunung.",
		"Rumahku selalu terbuka untukmu, Ksatria."],
		["Gua itu sarang Raja Iblis. Aku percaya padamu, tetapi pulanglah dengan selamat.",
		"Seluruh desa berdoa untukmu tiap malam di bawah menara lampu."],
		["Desa ini aman lagi. Atas nama semua warga, terima kasih, Pelindung Kerajaan.",
		"Malam ini kita berpesta di bawah menara lampu. Kamu tamu kehormatan kami."]]},
	"penjaga": {"name": "Penjaga Gerbang", "stages": [
		["Gerbang selatan menuju Perbatasan. Di luar penuh monster, pastikan HP-mu penuh sebelum berangkat.",
		"Aku hanya diperintah menjaga gerbang. Tapi aku tahu desa ini butuh pahlawan."],
		["Ada laporan serigala liar di jalan raja. Sebaiknya kamu bersiap, Ksatria.",
		"Aku sudah melihat bayangan hijau di balik pagar ladang. Hati-hati."],
		["Pasukan dikirim ke gunung, tapi tak satu pun yang kembali. Jangan sendirian di sana.",
		"Terus ke selatan dari Perbatasan, lalu ke Gunung Batu. Itu jalan menuju sarangnya."],
		["Kamu satu-satunya harapan kami di gua itu. Pulanglah hidup-hidup.",
		"Aku akan menjaga gerbang ini sampai kamu kembali."],
		["Gerbang ini kembali terbuka untuk para pedagang. Kerajaan berhutang padamu, Pelindung Kerajaan.",
		"Hormat, Ksatria. Kapan pun kamu pergi atau pulang, aku berdiri di sini."]]},
	"ayam": {"name": "Ayam", "stages": [
		["Kluk kluk kluk...", "Kluk! (menatapmu dengan curiga)"],
		["Kluk kluk! (mematuk sepatumu)"],
		["Kluk... (tampak gelisah)"],
		["Kluk kluk! (mengepakkan sayap)"],
		["Kluk kluk kluk~ (tampak tenang dan senang)"]],
	},
}


## Banyak misi utama yang sudah tuntas (target tercapai atau hadiah sudah diambil), 0-4.
## `quests` = daftar misi dari GET /v1/quests.
static func stage_from_quests(quests: Array) -> int:
	var status := {}
	for q: Dictionary in quests:
		status[str(q.id)] = str(q.status)
	var stage := 0
	for id: String in MAIN_QUESTS:
		var s: String = str(status.get(id, ""))
		if s == "done" or s == "claimed":
			stage += 1
		else:
			break
	return stage


static func has_warga(id: String) -> bool:
	return id == "kapten_kem" or WARGA.has(id)


static func display_name(id: String) -> String:
	if id == "kapten_kem":
		return "Kapten Rimba"
	return str(WARGA.get(id, {}).get("name", "Penduduk"))


## Kalimat untuk warga `id` pada tahap `stage`; `n` = berapa kali sudah diajak bicara
## (kalimat bergantian bila ada lebih dari satu).
static func line(id: String, stage: int, n: int) -> String:
	if id == "kapten_kem":
		return kapten_line(Session.hutan_wave(), Session.hutan_kills(), n, Session.hutan_started())
	if not WARGA.has(id):
		return "Halo."
	var stages: Array = WARGA[id].stages
	var lines: Array = stages[clampi(stage, 0, stages.size() - 1)]
	return str(lines[n % lines.size()])


## Kapten Rimba (penjaga kem di pintu masuk Hutan Lebat) menjelaskan tugas sesuai kemajuan misi.
## wave = Goblin yang sudah kalah (0-3), kills = binatang kalah di tahap ini (0-100), n = urutan bicara.
## `briefed` = sudah pernah diarahkan; bila belum, ini pertemuan pertama: Kapten memberi Radar Musuh.
static func kapten_line(wave: int, kills: int, n: int, briefed := true) -> String:
	var tugas := "Tugasmu: kalahkan 100 binatang buas di Hutan Lebat. Setelah itu Goblin Level %d muncul di singgasana, dekat gerbang Gua Goblin." % (wave + 1)
	var jalan := "Hutan Lebat ada di selatan kem ini: susuri jalan raja sampai ujung selatan. Di dalam, jalan tanah bercabang tiga (utara, tengah, selatan), tapi semuanya bertemu di satu persimpangan tepat di depan gerbang Gua Goblin. Singgasana ada di dekat situ. Panah di layar menunjukkan arahnya."
	if not briefed:
		return "Selamat datang di kem, Ksatria. Hutan Lebat di selatan dikuasai tiga Goblin. Terimalah Radar Musuh ini: titik merahnya menunjukkan binatang buas di sekitarmu. Sekarang kamu boleh melawan mereka. " + tugas
	if wave >= 3:
		return ["Tiga Goblin sudah kamu tumbangkan! Gerbang Gua Goblin sudah terbuka, di ujung selatan Hutan Lebat. Hati-hati di dalam.",
			"Hutan ini aman berkat kamu. Isi bekalmu di sini sebelum masuk Gua Goblin."][n % 2]
	if kills >= 100:
		return ["Semua binatang tahap ini sudah habis! Goblin Level %d menunggumu di singgasana, dekat gerbang Gua Goblin. Ikuti jalan tanah sampai persimpangan." % (wave + 1),
			"Goblin itu lebih kuat dari binatang biasa. Bawa ramuan dan jangan lupa bertahan, ya."][n % 2]
	var progress := "Sudah %d dari 100 binatang kamu kalahkan." % kills if kills > 0 else "Belum ada binatang yang kamu kalahkan."
	if wave == 0:
		return ["Hutan Lebat di selatan dikuasai tiga Goblin. " + tugas + " Radar Musuh di ranselmu menunjukkan di mana binatangnya.",
			progress + " " + jalan,
			"Setelah tiga Goblin tumbang, gerbang Gua Goblin terbuka. Gua itu jalan menuju Gunung Batu."][n % 3]
	return ["Goblin Level %d sudah kamu kalahkan! %d binatang baru muncul di hutan. %s" % [wave, 100, tugas],
		progress + " " + jalan,
		"Tersisa %d Goblin lagi. Terus semangat, Ksatria." % (3 - wave)][n % 3]
