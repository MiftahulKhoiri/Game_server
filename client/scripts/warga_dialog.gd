extends RefCounted
## Dialog singkat warga. Isinya mengikuti cerita utama "The Last Dragon" (docs/STORY.md; server: story.go).
## `tahap` = bab cerita yang sedang berjalan (stage_of_story):
##   0 Prolog (Elara diculik)  1 Hutan Binatang  2 Gua Goblin  3 Gunung Berapi  4 Istana Kegelapan  5 Epilog (damai)
## Tiap tahap punya 1-2 kalimat yang bergantian setiap kali diajak bicara.

## Bab (tahap kalimat warga) untuk langkah cerita `story` (0..12, sama dengan State.Story di server).
static func stage_of_story(story: int) -> int:
	if story <= 1:
		return 0
	if story <= 3:
		return 1
	if story == 4:
		return 2
	if story <= 8:
		return 3
	if story <= 10:
		return 4
	return 5


## id warga -> {"name": nama tampil, "stages": [[kalimat tahap 0], [tahap 1], ... [tahap 5]]}
const WARGA := {
	"bu_sari": {"name": "Bu Sari", "stages": [
		["Semalam monster masuk dari arah hutan... Elara, putri Kepala Desa, dibawa penyihir berjubah hitam!",
		"Kepala Desa tidak tidur semalaman. Temuilah dia di rumahnya di utara, Nak."],
		["Kamu jadi ke Hutan Binatang? Dulu aku sering memetik jamur di sana. Binatangnya jinak sekali, tidak seperti sekarang.",
		"Bawalah ramuan. Binatang yang dikutuk tidak kenal ampun."],
		["Goblin membawa Elara ke gua? Kasihan anak itu. Kubuatkan sup hangat untuk menyambutnya pulang nanti.",
		"Kata orang, Goblin dulu menukar hasil tambang dengan roti di pasar ini. Entah apa yang merasuki mereka."],
		["Langit di selatan merah setiap malam. Gunung berapi itu bangun lagi, ya?",
		"Hati-hati di gunung, Nak. Panasnya bisa melelehkan sepatu."],
		["Istana Kegelapan... bahkan namanya membuatku merinding. Pulanglah bersama Elara, ya.",
		"Seluruh desa berdoa untukmu setiap malam."],
		["Elara pulang! Malam ini kita masak besar untuk merayakan, Pahlawan.",
		"Desa ini ramai lagi. Semua karena kamu."]]},
	"mbak_dewi": {"name": "Mbak Dewi", "stages": [
		["Elara biasa membeli pita di lapakku setiap pagi... Semalam dia diculik. Kamu harus menolongnya!",
		"Penyihir itu datang bersama kabut hitam. Aku melihatnya dari jendela."],
		["Pedagang dari selatan bilang binatang di hutan matanya merah semua. Seram!",
		"Kalau melihat pita kuning di hutan, itu pita Elara. Dia selalu memakainya."],
		["Goblin? Dulu mereka pembeli kain paling setia. Mereka suka warna cokelat tanah.",
		"Kalau mereka cuma diperintah penyihir, kasihan juga, ya."],
		["Kain dari utara tidak datang lagi. Jalan dagang lewat gunung tertutup Orc Batu.",
		"Orc Batu itu katanya dulu penjaga gunung. Kenapa sekarang jadi jahat?"],
		["Kalau kamu bertemu naga itu... katanya dulu ia pelindung Eldoria. Jangan sampai dibunuh, ya.",
		"Aku menjahit selendang baru untuk Elara. Semoga cepat dipakai."],
		["Elara memakai selendang buatanku! Cantik sekali, kan? Terima kasih sudah membawanya pulang.",
		"Pedagang mulai berdatangan lagi tiap pagi. Rezeki kami kembali."]]},
	"pak_joko": {"name": "Pak Joko", "stages": [
		["Aku dulu prajurit raja. Semalam aku mencoba menghadang penyihir itu, tapi tubuhku tak bisa bergerak. Sihir!",
		"Sebelum pergi, beli ramuan dan pedang yang layak. Jalanmu panjang, Nak."],
		["Binatang terkutuk menyerang tanpa takut. Bertahanlah tepat waktu, lalu balas menyerang.",
		"Goblin yang menculik Elara pasti lewat hutan. Ikuti jejak kaki kecil mereka."],
		["Gua Goblin itu dulu tambang. Lorongnya sempit, jangan sampai terkepung.",
		"Pemimpin goblin selalu yang paling besar. Habisi pengawalnya dulu."],
		["Orc Batu kulitnya keras seperti granit. Pukul terus, jangan biarkan dia memulihkan diri.",
		"Aku pernah ke gunung itu waktu muda. Di perutnya ada benteng tua para Orc."],
		["Kamu sudah sejauh ini? Aku bangga padamu, Nak. Prajurit mana pun tak pernah ke Istana Kegelapan.",
		"Penyihir itu licik. Saat dia terdesak, dia akan memanggil pasukannya. Siaga!"],
		["Besi bekas pasukan terkutuk itu kutempa jadi sabit dan cangkul. Dunia damai, Nak.",
		"Anak-anak sekarang berebut jadi pahlawan dalam permainan mereka. Kamu yang jadi tokohnya."]]},
	"pak_budi": {"name": "Pak Budi", "stages": [
		["Pagar ladangku hancur semalam. Untung tak ada warga yang terluka parah... kecuali Elara yang dibawa pergi.",
		"Elara sering membantu menanam bibit. Anak yang baik."],
		["Babi hutan dulu cuma mencuri ubi. Sekarang mereka sebesar sapi dan menyeruduk apa saja!",
		"Kalau hutan sudah aman, aku mau menanam jagung di tepinya lagi."],
		["Goblin itu dulu suka menukar batu berkilau dengan sayurku. Aku tak percaya mereka jahat dari sananya.",
		"Ayam-ayamku sampai tak mau bertelur sejak penyerangan itu."],
		["Tanah bergetar dari arah gunung. Gunung berapi itu marah, atau ada yang membuatnya marah.",
		"Kalau gunung itu tenang lagi, aku traktir kamu lima karung sayur."],
		["Aku lihat bayangan naga di langit utara semalam. Besar sekali... tapi kelihatannya sedih.",
		"Tanaman di ladang layu sejak kutukan itu. Semoga cepat berakhir."],
		["Lihat, tanaman di ladang tumbuh segar lagi! Kutukan itu benar-benar hilang.",
		"Besok aku menanam bibit baru bersama Elara. Tahun ini panen paling baik."]]},
	"rina": {"name": "Rina", "stages": [
		["Kak, Kak Elara diculik! Kak Elara yang suka mendongeng untuk kami...",
		"Ibuku bilang aku tidak boleh keluar gerbang. Di luar banyak monster."],
		["Kak Elara bilang binatang di hutan dulu teman. Kenapa sekarang mereka menggigit?",
		"Kalau Kakak ketemu Kak Elara, bilang aku rindu, ya!"],
		["Goblin itu bau tidak, Kak? Kata Dika mereka hijau dan bau!",
		"Aku menggambar Kakak melawan Raja Orc Batu. Bagus, kan?"],
		["Gunung berapi itu ada lavanya, Kak? Jangan sampai kakinya kepanasan!",
		"Aku mimpi Orc batu menangis. Aneh, ya."],
		["Kak Elara akan pulang, kan? Kakak janji, ya!",
		"Kalau Kakak menang lawan penyihir itu, aku mau jadi pahlawan juga!"],
		["Kak Elara pulang! Dia mendongeng lagi untuk kami! Terima kasih, Kak Pahlawan!",
		"Aku lihat naga besar terbang di langit! Katanya dia sudah baik lagi."]]},
	"dika": {"name": "Dika", "stages": [
		["Aku lihat penyihir itu! Jubahnya hitam, matanya ungu menyala. Aku sembunyi di bawah meja.",
		"Kepala Desa menunggu Kakak di rumahnya. Cepat ke sana!"],
		["Aku dengar lolongan serigala dari arah hutan. Serem!",
		"Kakak sudah ketemu kelelawar raksasa? Kata Pak Ujang ada di hutan."],
		["Gua Goblin itu gelap tidak, Kak? Bawa obor!",
		"Teman-temanku sekarang bermain Kakak-dan-Raja-Goblin. Aku jadi Kakak!"],
		["Kata Nyai Sekar, di gunung ada batu sihir. Hancurkan saja, Kak!",
		"Aku lihat kunang-kunang merah di langit semalam."],
		["Naga terakhir! Kakak mau melawan naga? Hebat sekali!",
		"Jangan takut, Kak. Seluruh desa mendukung Kakak!"],
		["Hore, desa kita aman lagi! Dan ada naga yang menjaga kita sekarang!",
		"Besok aku mau bermain sampai ke ladang. Sekarang tidak ada yang melarang!"]]},
	"kepala_suku": {"name": "Kepala Desa", "stages": [
		["Elara... putriku... Tolong bicaralah denganku. Aku butuh bantuanmu.",
		"Penyihir itu datang bersama kabut hitam. Aku tak sanggup menghentikannya."],
		["Kapten Rimba mengabarkan kamu sudah masuk Hutan Binatang. Terima kasih, Nak.",
		"Elara anak yang berani. Aku yakin dia masih bertahan di luar sana."],
		["Goblin? Dulu bangsa Goblin bersahabat dengan desa ini. Penyihir itu pasti mengendalikan mereka.",
		"Lambang ini... Malzareth. Nama itu pernah diceritakan kakekku sebagai penyihir terlarang."],
		["Gunung berapi itu dulu dijaga bangsa Orc yang bijak. Kalau mereka berubah, kutukan itu sungguh kuat.",
		"Rumahku selalu terbuka untukmu. Istirahatlah sebelum mendaki gunung."],
		["Istana Kegelapan... Bawalah putriku pulang, dan pulanglah dengan selamat juga.",
		"Seluruh desa berdoa untukmu tiap malam di bawah menara lampu."],
		["Putriku pulang dan dunia bebas dari kutukan. Desa ini berutang selamanya padamu.",
		"Malam ini kita berpesta di bawah menara lampu. Kamu tamu kehormatan kami."]]},
	"penjaga": {"name": "Penjaga Gerbang", "stages": [
		["Monster semalam masuk dari arah hutan. Aku gagal menjaga gerbang... Temui Kepala Desa dulu.",
		"Gerbang selatan menuju Perbatasan. Kapten Rimba berkemah tepat di bawah gapura."],
		["Hutan Binatang ada di selatan Perbatasan. Binatangnya dikutuk, jangan lengah.",
		"Aku melihat bayangan hijau di balik pagar ladang. Hati-hati."],
		["Gua Goblin ada di ujung selatan Hutan Binatang. Ikuti jalan tanah sampai persimpangan.",
		"Aku akan menjaga gerbang ini sampai kamu kembali."],
		["Jalan ke gunung berapi: dari Gua Goblin terus ke selatan. Panasnya terasa dari sini.",
		"Pastikan HP-mu penuh sebelum berangkat. Lereng itu tidak memberi ampun."],
		["Kamu satu-satunya harapan kami. Pulanglah hidup-hidup bersama Elara.",
		"Pasukan kerajaan tak pernah sampai ke istana itu. Kamu yang pertama."],
		["Gerbang ini kembali terbuka untuk para pedagang. Hormat, Pahlawan Eldoria!",
		"Kapan pun kamu pergi atau pulang, aku berdiri di sini."]]},
	"ayam": {"name": "Ayam", "stages": [
		["Kluk kluk kluk...", "Kluk! (menatapmu dengan curiga)"],
		["Kluk kluk! (mematuk sepatumu)"],
		["Kluk... (tampak gelisah)"],
		["Kluk... (bersembunyi di balik ember)"],
		["Kluk kluk! (mengepakkan sayap)"],
		["Kluk kluk kluk~ (tampak tenang dan senang)"]],
	},
	"mpu_karta": {"name": "Mpu Karta", "stages": [
		["Pedang yang dipakai menyelamatkan Elara harus tajam. Mampirlah ke landasanku.",
		"Pedang tumpul lebih berbahaya bagi pemiliknya daripada bagi musuh. Rawat senjatamu, Nak."],
		["Kulit binatang terkutuk lebih keras dari biasanya. Belilah Pedang Besi sebelum ke hutan.",
		"Bawakan aku kayu dan batu dari hutan, akan kutempakan sesuatu untukmu."],
		["Helm itu penting! Banyak penambang tumbang karena kepalanya terbentur gada goblin.",
		"Taring goblin itu keras, tapi besi tempaanku lebih keras."],
		["Orc Batu? Kulitnya sekeras granit. Hanya Pedang Baja yang sanggup menggoresnya.",
		"Bara di landasan ini tidak pernah padam sejak monster datang. Pesanan senjata tak ada habisnya."],
		["Naga dan penyihir... Kalau kamu punya Pedang Rune, inilah saatnya. Tapi jangan bunuh naganya, ya.",
		"Zirah Besi lebih baik daripada baju kulit di istana itu, percayalah."],
		["Sekarang aku menempa cangkul dan sabit lagi. Bunyi palu yang damai, ya.",
		"Akan kutempa lencana kecil untuk Pahlawan Eldoria."]]},
	"tuan_wira": {"name": "Tuan Wiranata", "stages": [
		["Aku utusan Raja di desa ini. Penculikan putri Kepala Desa ini akan kulaporkan ke istana.",
		"Rakyat kecil adalah tulang punggung kerajaan. Lindungi mereka."],
		["Hutan Binatang dulu taman perburuan para bangsawan. Sekarang tak seorang pun berani masuk.",
		"Kerajaan mengandalkanmu, Ksatria."],
		["Lambang Malzareth? Nama itu tercatat di arsip istana sebagai penyihir yang diusir seratus tahun lalu.",
		"Pajak panen tahun ini kuhapus untuk desa ini. Mereka sudah cukup menderita."],
		["Bangsa Orc dulu sekutu kerajaan. Kalau mereka dikutuk, perbatasan selatan tak terjaga.",
		"Kalau gunung itu aman, jalan dagang ke ibu kota bisa dibuka kembali."],
		["Raja sudah menyiapkan gelar untuk siapa pun yang mengalahkan Malzareth.",
		"Para bangsawan di ibu kota bertaruh siapa yang akan pulang hidup-hidup."],
		["Atas nama Raja, kunyatakan kamu Pahlawan Eldoria! Pestanya akan dibicarakan seratus tahun.",
		"Kalau kamu ke ibu kota, sebut namaku di gerbang istana."]]},
	"prajurit_damar": {"name": "Damar", "stages": [
		["Aku berpatroli semalaman, tapi penyihir itu menembus pagar seperti asap. Maafkan aku...",
		"Sersan Joni di tenda hijau sedang mencari prajurit baru. Pasukan kita masih kurang."],
		["Jangan pergi ke hutan sendirian, bawa pasukan dari tenda hijau.",
		"Latihan di Aula Pelatihan membuat prajuritmu lebih kuat."],
		["Goblin bergerombol di gua. Pasukan yang terlatih bisa menahan mereka.",
		"Aku dulu dilatih di Aula Pelatihan. Guru Bima galak tapi hebat."],
		["Dari menara aku lihat asap dari arah gunung berapi. Ada yang tidak beres di sana.",
		"Prajurit yang berlatih bertahan lebih lama di garis depan."],
		["Pasukan kerajaan siap menyusulmu kalau kamu memberi tanda.",
		"Aku iri padamu. Tidak semua prajurit mendapat kesempatan melawan naga."],
		["Patroli sekarang terasa seperti jalan-jalan sore. Terima kasih, Pahlawan!",
		"Anak-anak desa ingin jadi sepertimu. Aku harus mulai melatih mereka."]]},
	"laras": {"name": "Laras", "stages": [
		["Semalam panahku tak mengenai penyihir itu. Panahnya menembus kabut begitu saja.",
		"Pemanah tidak boleh panik. Tarik napas, bidik, baru lepaskan."],
		["Kelelawar di hutan terbang zig-zag. Tunggu ia mendekat, baru serang.",
		"Kalau kamu butuh pemanah di barisanmu, Komandan Raka di tenda merah bisa mengaturnya."],
		["Gua itu gelap. Pemanah tak berguna di sana, jadi pedangmulah harapan kita.",
		"Goblin selalu menyerang dari bayangan. Perhatikan polanya."],
		["Panah biasa memantul dari kulit Orc Batu. Bidik sendinya, bukan badannya.",
		"Malam-malam aku melihat cahaya merah dari gunung."],
		["Naga terbang tinggi. Kalau dia turun menyembur, menghindarlah ke samping.",
		"Kembalilah dengan selamat. Aku akan menyalakan obor di gerbang untukmu."],
		["Aku melihat Aldragor terbang di atas desa pagi ini. Indah sekali.",
		"Lain kali kita berlomba memanah, ya, Pahlawan."]]},
	"nyai_sekar": {"name": "Nyai Sekar", "stages": [
		["Kabut semalam bukan kabut biasa. Itu sihir terlarang... sihir yang merusak pikiran makhluk hidup.",
		"Bintang-bintang bilang seorang pahlawan akan membawa Elara pulang. Itukah kamu?"],
		["Binatang di hutan itu korban, bukan musuh. Kutukan merampas pikiran mereka.",
		"Ramuan Kekuatan membakar energimu. Minumlah hanya saat benar-benar perlu."],
		["Lambang itu... Malzareth. Ia ingin pasukan yang tidak bisa membangkang.",
		"Aku merasakan sihir mengalir dari selatan, dari perut gunung berapi."],
		["Di gunung ada batu penguat kutukan. Hancurkan batu itu, tapi ingat: kutukan tak hilang selama penyihirnya hidup.",
		"Orc Batu dulu penjaga gunung yang bijak. Mungkin masih ada yang bisa disadarkan."],
		["Aldragor adalah naga terakhir, pelindung Eldoria. Kalahkan dia, jangan bunuh. Ia akan pulih bila Malzareth jatuh.",
		"Malzareth akan bertarung tiga kali lebih kuat saat terdesak. Bertahanlah sampai akhir."],
		["Langit sudah jernih kembali. Sihir hitam itu telah padam berkat kamu.",
		"Aku melihat masa depan yang cerah untuk desa ini. Dan untukmu, petualangan baru."]]},
	"pak_ujang": {"name": "Pak Ujang", "stages": [
		["Aku pedagang keliling. Semalam aku melihat makhluk-makhluk berlari ke selatan sambil menyeret seseorang!",
		"Kalau binatang mendekat, aku lari dulu! Kamu yang bertarung, ya, Ksatria."],
		["Dari Perbatasan, jalan raja terus ke selatan menuju Hutan Binatang.",
		"Kapten Rimba di kem utara tahu banyak soal hutan. Bicaralah dengannya."],
		["Gua Goblin di ujung hutan itu dulu tempat aku membeli batu permata. Sekarang tak ada yang berani lewat.",
		"Serigala Alfa memimpin kawanan di sini. Bulunya gelap, lebih besar dari serigala biasa."],
		["Jalan dagang lewat gunung tertutup. Orc Batu menghadang siapa pun.",
		"Daganganku tinggal sedikit. Semoga kutukan itu cepat hilang."],
		["Istana Kegelapan? Aku cuma pernah mendengar namanya dari dongeng. Semoga kamu kembali, Ksatria.",
		"Aku menyimpan ramuan terbaik untuk pembeli istimewa. Tapi Toko Ramuan di desa lebih lengkap."],
		["Jalan dagang aman lagi! Daganganku laris, terima kasih, Pahlawan.",
		"Kalau mampir ke kota, kabarkan pada semua orang tentang desa kita."]]},
	# Tokoh cerita The Last Dragon.
	"penjaga_hutan": {"name": "Bayu", "stages": [
		["Ugh... Siapa kau? Hutan ini berbahaya. Kalau mau masuk, temui dulu Kapten Rimba di kem Perbatasan.",
		"Binatang-binatang itu... dulu mereka tidak pernah menyerang manusia."],
		["Ikuti jalan tanah sampai persimpangan di depan Gua Goblin. Di sanalah para Goblin berjaga.",
		"Lukaku tidak apa-apa. Pergilah, gadis itu lebih membutuhkanmu."],
		["Kau mengalahkan para Goblin? Kudengar mereka membawa gadis itu lebih dalam ke gua.",
		"Binatang-binatang mulai tenang sejak para Goblin tumbang."],
		["Asap dari selatan makin pekat. Sumber kutukan itu pasti di gunung berapi.",
		"Aku sudah bisa berjalan lagi, sedikit-sedikit."],
		["Naga terakhir... aku pernah melihatnya waktu kecil. Ia menjaga hutan ini dari langit.",
		"Kembalilah dengan selamat, Pahlawan."],
		["Lihat! Kancil dan rubah bermain lagi di padang. Hutan ini hidup kembali.",
		"Terima kasih telah mengembalikan hutan kami."]]},
	"orc_tua": {"name": "Orc Tua", "stages": [
		["Grrr... (Orc tua itu menggeram. Matanya merah menyala, seperti tidak melihatmu.)"],
		["Grrr... (Orc tua itu menggeram. Matanya merah menyala, seperti tidak melihatmu.)"],
		["Grrr... (Orc tua itu menggeram. Matanya merah menyala, seperti tidak melihatmu.)"],
		["Grrr... (Orc tua itu menggeram. Matanya merah menyala, seperti tidak melihatmu.)",
		"Batu... batu itu... (Ia menatap Batu Sihir di dekat singgasana, lalu menggeram lagi.)"],
		["Lorong rahasia di selatan benteng menuju Istana Kegelapan. Hentikan Malzareth, manusia.",
		"Kami akan menjaga gunung ini lagi, seperti dahulu."],
		["Kutukan telah patah. Bangsa Orc berutang padamu. Gunung ini terbuka untuk sahabat kami.",
		"Kami kembali menjadi penjaga gunung. Terima kasih, Pahlawan."]]},
	"elara": {"name": "Elara", "stages": [
		["(Elara belum ada di sini.)"], ["(Elara belum ada di sini.)"], ["(Elara belum ada di sini.)"], ["(Elara belum ada di sini.)"],
		["Kau datang! Tolong... Malzareth ada di singgasana itu. Ia ingin memakai darahku untuk sihirnya!",
		"Jangan khawatirkan aku. Kalahkan dia, dan semua makhluk akan bebas!"],
		["Ayo pulang. Ayah pasti sangat khawatir.",
		"Terima kasih karena tidak menyerah mencariku."]]},
}

## Elara pada langkah cerita tertentu (tempatnya berbeda): langkah 11 = sudah bebas, menuju desa.
const ELARA_PULANG := ["Kita sudah sampai di desa! Ayah ada di rumah, ayo temui dia.", "Desaku... aku pikir tak akan melihatnya lagi."]


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
	var story := Session.story()
	if id == "orc_tua" and story >= 9:
		stage = maxi(stage, 4)  # sudah sadar setelah Batu Sihir hancur dan diajak bicara
	if id == "elara" and story == 11 and Session.player.get("state", {}).get("map", "") == "desa_awal":
		return str(ELARA_PULANG[n % ELARA_PULANG.size()])
	var stages: Array = WARGA[id].stages
	var lines: Array = stages[clampi(stage, 0, stages.size() - 1)]
	return str(lines[n % lines.size()])


## Kalimat kunci tokoh cerita saat langkah ceritanya selesai di layar bicara (docs/STORY.md).
## id warga -> {langkah cerita: kalimat}.
const STORY_TALK := {
	"kepala_suku": {
		0: "Elara telah dibawa pergi oleh penyihir itu. Aku tidak sanggup meninggalkan desa untuk mencarinya. Tolong temukan putriku dan bawa dia pulang. Aku percaya kepadamu.\n\nTerimalah bekal ini: ramuan dan roti untuk perjalanan. Keluarlah lewat gerbang selatan; Kapten Rimba di kem Perbatasan akan menunjukkan jalan ke hutan.",
		11: "Elara! Putriku!\n\nEngkau telah membawa putriku pulang dan membebaskan dunia dari kutukan. Desa ini tidak akan melupakan keberanianmu. Terimalah Pedang Rune pusaka desa ini.",
	},
	"penjaga_hutan": {
		2: "Jangan kira mereka memilih menjadi seperti ini. Dahulu mereka hidup damai. Sihir hitam telah merampas kendali mereka.\n\nAku melihat para Goblin membawa seorang gadis ke gua di balik hutan. Tiga Goblin besar menjaga jalannya. Ambil ramuanku, aku tak membutuhkannya lagi.",
	},
	"orc_tua": {
		8: "Kami dahulu penjaga gunung, bukan monster. Penyihir itu mengikat pikiran kami. Batu ini hanya penguat kutukannya. Selama Malzareth hidup, kutukan tidak akan berakhir. Naga terakhir pun telah ia kuasai.\n\nAda lorong rahasia di selatan benteng ini. Ia menuju Istana Kegelapan. Pergilah.",
	},
}


## Langkah cerita yang diselesaikan dengan bicara ke warga `id` sekarang (-1 bila tidak ada).
static func story_step_for(id: String, story: int) -> int:
	if STORY_TALK.has(id) and (STORY_TALK[id] as Dictionary).has(story):
		return story
	return -1


## Kapten Rimba (penjaga kem di pintu masuk Hutan Binatang) menjelaskan tugas sesuai kemajuan ujian hutan.
## wave = Goblin yang sudah kalah (0-3), kills = binatang kalah di tahap ini (tahap 1: 25, 2: 75, 3: 100), n = urutan bicara.
## `briefed` = sudah pernah diarahkan; bila belum, ini pertemuan pertama: Kapten memberi Radar Musuh.
static func kapten_line(wave: int, kills: int, n: int, briefed := true) -> String:
	var need: int = [25, 75, 100][clampi(wave, 0, 2)]
	var tugas := "Tugasmu tahap %d: kalahkan %d binatang terkutuk di Hutan Binatang. Setelah itu Goblin Level %d muncul di singgasana, dekat gerbang Gua Goblin." % [wave + 1, need, wave + 1]
	var jalan := "Hutan Binatang ada di selatan kem ini: susuri jalan raja sampai ujung selatan. Di dalam, jalan tanah bercabang tiga (utara, tengah, selatan), tapi semuanya bertemu di satu persimpangan tepat di depan gerbang Gua Goblin. Panah di layar menunjukkan arahnya."
	if not briefed:
		return "Kau mencari putri Kepala Desa? Jejak para penyerbu menuju Hutan Binatang di selatan: binatangnya dikutuk, dan tiga Goblin besar menjaga jalan ke gua mereka. Terimalah Radar Musuh ini: titik merahnya menunjukkan binatang di sekitarmu. Penjaga hutan kami, Bayu, terluka di dekat pintu masuk hutan. Temuilah dia. " + tugas
	if wave >= 3:
		return ["Tiga Goblin sudah kamu tumbangkan! Gerbang Gua Goblin terbuka di ujung selatan Hutan Binatang. Elara pasti dibawa ke sana.",
			"Hutan ini aman berkat kamu. Isi bekalmu di sini sebelum masuk Gua Goblin."][n % 2]
	if kills >= need:
		return ["Semua binatang tahap ini sudah habis! Goblin Level %d menunggumu di singgasana, dekat gerbang Gua Goblin. Ikuti jalan tanah sampai persimpangan." % (wave + 1),
			"Goblin itu lebih kuat dari binatang biasa. Bawa ramuan dan jangan lupa bertahan, ya."][n % 2]
	var progress := ("Sudah %d dari %d binatang kamu kalahkan." % [kills, need]) if kills > 0 else "Belum ada binatang yang kamu kalahkan."
	if wave == 0:
		return ["Binatang di Hutan Binatang dikutuk, dan tiga Goblin menjaga jalan ke gua. " + tugas + " Radar Musuh di ranselmu menunjukkan di mana binatangnya.",
			progress + " " + jalan,
			"Ada tiga tahap: 25, lalu 75, lalu 100 binatang, masing-masing ditutup satu Goblin. Setelah tiga Goblin tumbang, gerbang Gua Goblin terbuka. Di Gua Goblin dan Gunung Berapi ujiannya sama."][n % 3]
	return ["Goblin Level %d sudah kamu kalahkan! Binatang baru muncul di hutan. %s" % [wave, tugas],
		progress + " " + jalan,
		"Tersisa %d Goblin lagi. Terus semangat, Ksatria." % (3 - wave)][n % 3]



## Obrolan singkat antar-warga yang berpapasan (roadmap no. 50): [kalimat pertama, jawaban].
const CHAT_LINES := [
	["Selamat pagi! Sudah sarapan?", "Sudah, sup buatan Bu Sari enak sekali."],
	["Kamu dengar? Ada kabar dari pahlawan itu?", "Katanya dia sudah jauh di selatan. Semoga Elara selamat."],
	["Panen tahun ini bagus, ya?", "Asal babi hutan terkutuk tidak datang lagi."],
	["Mau ke pasar?", "Iya, Mbak Dewi dapat kain baru dari kota."],
	["Cuacanya cerah sekali.", "Semoga tidak hujan sampai sore."],
	["Anak-anak main di dekat sungai lagi.", "Nanti kuingatkan mereka supaya hati-hati."],
]


static func chat_pair(n: int) -> Array:
	return CHAT_LINES[n % CHAT_LINES.size()]
