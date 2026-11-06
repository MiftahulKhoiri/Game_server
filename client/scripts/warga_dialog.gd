extends RefCounted
## Dialog singkat warga desa. Isinya mengikuti alur cerita utama (4 misi berantai):
##   Nenek (kucing/ayam liar) -> Petani (orc ladang) -> Monster Batu (gunung) -> Raja Iblis (gua)
## `tahap` = banyak misi utama yang sudah tuntas (0-4); warga berkomentar sesuai tahap itu.
## Tiap tahap punya 1-2 kalimat yang bergantian setiap kali diajak bicara.

## Misi utama berurutan; kunci = id misi di server.
const MAIN_QUESTS := ["selamatkan_nenek", "selamatkan_petani", "usir_ogre", "hentikan_raja_goblin"]

## id warga -> {"name": nama tampil, "stages": [[kalimat tahap 0], [tahap 1], ... [tahap 4]]}
const WARGA := {
	"bu_sari": {"name": "Bu Sari", "stages": [
		["Semalam ayam dan kucing liar mengamuk di pasar. Kasihan Nenek di sebelah barat, sayurannya habis dirusak.",
		"Kamu ksatria baru itu, ya? Bicaralah dengan Nenek dulu. Dia sudah lama menunggu bantuan."],
		["Syukurlah Nenek selamat! Tapi Petani bilang ada orc hijau di ladang perbatasan. Temui dia di jalan raya.",
		"Bawalah ramuan sebelum ke perbatasan. Aku sudah lihat terlalu banyak orang pulang dengan luka."],
		["Orc-orc itu mundur berkat kamu. Tapi tiap malam ada dentuman dari Gunung Batu. Kamu dengar juga?",
		"Anak-anak mulai takut tidur. Katanya ada raksasa batu di gunung."],
		["Monster Batu sudah tumbang! Tapi para pedagang bilang ada gua gelap di bawah gunung, penuh kerangka.",
		"Kalau kamu masuk gua itu, pulanglah hidup-hidup. Aku siapkan sup hangat untukmu."],
		["Raja Iblis sudah tumbang! Malam ini kita masak besar untuk merayakan, Ksatria.",
		"Desa ini ramai lagi. Semua karena kamu."]]},
	"mbak_dewi": {"name": "Mbak Dewi", "stages": [
		["Kamu pasti ksatria yang dibicarakan semua orang. Mulailah dari Nenek di sebelah barat, ya.",
		"Aku pedagang kain. Sejak monster berdatangan, dagangan sepi sekali."],
		["Petani gemetar semalam, katanya orc menginjak ladangnya. Dia ada di jalan raya, dekat alun-alun.",
		"Orc itu menjatuhkan taring. Nenek butuh taring untuk meracik obat, lho."],
		["Jalan perbatasan makin sepi. Serigala dan kerangka mulai muncul dari arah gunung.",
		"Pedagang yang pulang bilang kerangka itu keluar dari satu lubang di gunung."],
		["Konon ada permata merah berkilau di dalam gua itu. Hati-hati, jangan sembarangan disentuh.",
		"Permata itu katanya sumber kekuatan pasukan iblis."],
		["Permata merahnya sudah aman, syukurlah! Kalau kamu butuh kain untuk jubah baru, aku beri harga teman, Ksatria.",
		"Pedagang mulai berdatangan lagi tiap pagi. Rezeki kami kembali."]]},
	"pak_joko": {"name": "Pak Joko", "stages": [
		["Kalau mau menyeberang sungai, latihan dulu di rumput sekitar desa. Naikkan levelmu, Nak.",
		"Aku dulu prajurit raja. Aku tahu mana monster yang bisa dilawan dan mana yang harus dihindari."],
		["Ladang selatan itu sarang orc. Beli ramuan dan bawa pedang yang layak.",
		"Orc keras kepala, tapi lemah kalau diserang bergantian. Jangan panik."],
		["Gunung Batu itu sarang Monster Batu. Bawa zirah dan pedang yang bagus, jangan nekat.",
		"Aku sudah tua untuk bertarung, tapi aku tahu jalannya: dari Perbatasan terus ke selatan."],
		["Di gua paling dalam ada singgasana. Siapa pun yang duduk di sana bukan manusia lagi.",
		"Kamu satu-satunya harapan kami. Aku bangga padamu, Nak."],
		["Besi bekas pasukan iblis itu kutempa jadi sabit dan cangkul. Dunia damai, Nak.",
		"Kalau butuh pedang baru, kunjungi aku. Untuk pahlawan, harga teman."]]},
	"pak_budi": {"name": "Pak Budi", "stages": [
		["Ladang kami hampir panen. Semoga monster tidak turun ke sini.",
		"Nenek penjual sayur itu langgananku. Tolong jaga dia, ya."],
		["Aku lihat orc hijau mengendap di ladang perbatasan. Mereka membawa taring yang katanya bisa jadi obat.",
		"Pagar ladangku sudah dua kali dijebol. Untung kamu datang."],
		["Tanah bergetar dari arah gunung. Ayam-ayamku sampai tak mau bertelur.",
		"Kalau gunung itu sunyi lagi, aku traktir kamu lima karung sayur."],
		["Kerangka-kerangka itu keluar dari satu lubang di gunung. Kalau kamu menutupnya, desa ini selamat.",
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
		"Kakak sudah ketemu orc? Mereka hijau dan bau, ya?"],
		["Gunung Batu itu tempat peri tinggal, kata Nenek. Tapi Bu Sari bilang itu monster. Siapa yang benar?",
		"Aku lihat kunang-kunang merah di langit semalam."],
		["Kakak menang lagi! Teman-temanku sekarang bercita-cita jadi ksatria.",
		"Kalau kakak pulang dari gua, ceritakan padaku, ya!"],
		["Hore, Kakak menang! Desa kita aman lagi!",
		"Besok aku mau bermain sampai ke ladang. Sekarang tidak ada yang melarang!"]]},
	"penjaga": {"name": "Penjaga Gerbang", "stages": [
		["Gerbang selatan menuju Perbatasan. Di luar penuh monster, pastikan HP-mu penuh sebelum berangkat.",
		"Aku hanya diperintah menjaga gerbang. Tapi aku tahu desa ini butuh pahlawan."],
		["Ada laporan orc di jalan raja. Sebaiknya kamu bersiap, Ksatria.",
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
	return WARGA.has(id)


static func display_name(id: String) -> String:
	return str(WARGA.get(id, {}).get("name", "Penduduk"))


## Kalimat untuk warga `id` pada tahap `stage`; `n` = berapa kali sudah diajak bicara
## (kalimat bergantian bila ada lebih dari satu).
static func line(id: String, stage: int, n: int) -> String:
	if not WARGA.has(id):
		return "Halo."
	var stages: Array = WARGA[id].stages
	var lines: Array = stages[clampi(stage, 0, stages.size() - 1)]
	return str(lines[n % lines.size()])
