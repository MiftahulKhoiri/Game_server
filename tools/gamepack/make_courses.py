#!/usr/bin/env python3
"""Menulis client/games/education_{sd,smp}/data/course.json dari bank soal di berkas ini.

Bank soal ditulis sebagai data Python (mudah ditinjau guru/pengembang) lalu diekspor ke JSON yang dibaca
mesin pembelajaran bersama (client/shared/edu/quiz_app.gd). Jawaban benar SELALU pilihan pertama di
sini; urutan pilihan diacak oleh game setiap kali soal tampil.

Pakai:  python3 tools/gamepack/make_courses.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "client", "games")


def Q(q, correct, *wrong, explain=""):
    d = {"q": q, "options": [correct, *wrong], "answer": 0}
    if explain:
        d["explain"] = explain
    return d


SD = {
    "title": "Belajar SD",
    "subtitle": "Matematika, Bahasa Indonesia, IPA, dan IPS untuk kelas 1–6. Pilih Latihan untuk pembahasan tiap soal, atau Kuis untuk nilai.",
    "pass_score": 70,
    "questions_per_session": 8,
    "subjects": [
        {"id": "matematika", "name": "Matematika", "color": "#2f5d8a", "levels": [
            {"id": "k12", "name": "Kelas 1–2 · Penjumlahan & Pengurangan",
             "generator": {"type": "arith", "ops": ["+", "-"], "min": 1, "max": 20, "count": 10}},
            {"id": "k34", "name": "Kelas 3–4 · Perkalian & Pembagian",
             "generator": {"type": "arith", "ops": ["x", ":"], "min": 2, "max": 10, "count": 10}},
            {"id": "k56", "name": "Kelas 5–6 · Bilangan Dua Angka",
             "generator": {"type": "arith", "ops": ["+", "-", "x"], "min": 10, "max": 99, "count": 10}},
            {"id": "pecahan", "name": "Kelas 5–6 · Membandingkan Pecahan",
             "generator": {"type": "fraction_compare", "count": 8}},
        ]},
        {"id": "bahasa_indonesia", "name": "Bahasa Indonesia", "color": "#8a4b2f", "levels": [
            {"id": "k12", "name": "Kelas 1–2", "questions": [
                Q("Huruf vokal adalah …", "a, i, u, e, o", "b, c, d, f, g", "k, l, m, n, p", "r, s, t, w, y"),
                Q("Kata \"buku\" terdiri atas berapa suku kata?", "2", "1", "3", "4", explain="bu-ku"),
                Q("Lawan kata \"besar\" adalah …", "kecil", "tinggi", "panjang", "berat"),
                Q("Kalimat yang diakhiri tanda tanya (?) adalah kalimat …", "tanya", "perintah", "berita", "seru"),
                Q("Huruf pertama nama orang ditulis dengan huruf …", "kapital (besar)", "kecil", "miring", "angka"),
                Q("Persamaan kata (sinonim) \"pandai\" adalah …", "pintar", "malas", "lambat", "lupa"),
                Q("Lawan kata \"siang\" adalah …", "malam", "pagi", "sore", "terang"),
                Q("Ibu memasak nasi di …", "dapur", "garasi", "atap", "kamar mandi"),
            ]},
            {"id": "k34", "name": "Kelas 3–4", "questions": [
                Q("Ide pokok paragraf biasanya terdapat pada …", "kalimat utama", "kalimat penjelas", "judul buku", "tanda baca"),
                Q("Kata baku yang benar adalah …", "apotek", "apotik", "aktip", "nasehat"),
                Q("Kata dasar \"tulis\" mendapat imbuhan me- menjadi …", "menulis", "metulis", "mentulis", "menyulis"),
                Q("Tanda baca yang tepat untuk kalimat perintah \"Tutup pintu itu …\" adalah …", "!", "?", ",", ":"),
                Q("Cerita tentang binatang yang berperilaku seperti manusia disebut …", "fabel", "legenda", "mite", "sage"),
                Q("Lawan kata \"rajin\" adalah …", "malas", "giat", "tekun", "cermat"),
                Q("Surat kepada teman atau keluarga termasuk surat …", "pribadi", "resmi", "dinas", "niaga"),
                Q("Pada kalimat \"Adik membaca buku.\", subjeknya adalah …", "Adik", "membaca", "buku", "membaca buku"),
            ]},
            {"id": "k56", "name": "Kelas 5–6", "questions": [
                Q("Kalimat yang berisi pendapat seseorang disebut kalimat …", "opini", "fakta", "perintah", "seru"),
                Q("Majas yang membandingkan dua hal memakai kata \"seperti\" atau \"bagai\" disebut …", "perumpamaan (simile)", "personifikasi", "hiperbola", "litotes"),
                Q("\"Daun melambai-lambai ditiup angin\" mengandung majas …", "personifikasi", "hiperbola", "litotes", "simile"),
                Q("Penulisan kata serapan yang benar adalah …", "kualitas", "kwalitas", "kwalitet", "qualitas"),
                Q("Bagian akhir cerita yang berisi penyelesaian masalah disebut …", "resolusi", "orientasi", "komplikasi", "klimaks"),
                Q("Teks yang berisi langkah-langkah melakukan sesuatu disebut teks …", "prosedur", "narasi", "deskripsi", "eksposisi"),
                Q("Kata \"mengatasi\" berasal dari kata dasar …", "atas", "mengatas", "atasi", "tas"),
                Q("Sampiran pantun terletak pada baris …", "1 dan 2", "3 dan 4", "1 dan 3", "2 dan 4"),
            ]},
        ]},
        {"id": "ipa", "name": "IPA", "color": "#2f7d4f", "levels": [
            {"id": "k12", "name": "Kelas 1–2", "questions": [
                Q("Alat indra untuk melihat adalah …", "mata", "telinga", "hidung", "lidah"),
                Q("Alat indra untuk mencium bau adalah …", "hidung", "mata", "kulit", "telinga"),
                Q("Hewan yang hidup di air dan bernapas dengan insang adalah …", "ikan", "kucing", "ayam", "sapi"),
                Q("Agar tumbuh, tanaman membutuhkan …", "air dan cahaya matahari", "gula dan garam", "susu", "minyak goreng"),
                Q("Benda yang memancarkan cahaya sendiri adalah …", "matahari", "bulan", "cermin", "meja"),
                Q("Es batu yang dibiarkan di luar kulkas akan …", "mencair", "membeku", "mengeras", "menjadi batu"),
                Q("Hewan yang berkembang biak dengan bertelur adalah …", "ayam", "kambing", "kucing", "sapi"),
                Q("Bagian tumbuhan yang menyerap air dari tanah adalah …", "akar", "daun", "bunga", "buah"),
            ]},
            {"id": "k34", "name": "Kelas 3–4", "questions": [
                Q("Perubahan wujud dari cair menjadi gas disebut …", "menguap", "membeku", "mencair", "mengembun"),
                Q("Hewan pemakan tumbuhan disebut …", "herbivora", "karnivora", "omnivora", "insektivora"),
                Q("Proses tumbuhan membuat makanan sendiri disebut …", "fotosintesis", "respirasi", "evaporasi", "metamorfosis"),
                Q("Urutan metamorfosis sempurna kupu-kupu adalah …", "telur – ulat – kepompong – kupu-kupu", "telur – kepompong – ulat – kupu-kupu", "ulat – telur – kepompong – kupu-kupu", "telur – kupu-kupu – ulat – kepompong"),
                Q("Gaya yang membuat benda jatuh ke bawah adalah gaya …", "gravitasi", "magnet", "gesek", "pegas"),
                Q("Planet yang paling dekat dengan Matahari adalah …", "Merkurius", "Venus", "Bumi", "Mars"),
                Q("Benda yang dapat ditarik magnet adalah …", "paku besi", "karet penghapus", "kertas", "kayu"),
                Q("Sumber energi panas terbesar bagi Bumi adalah …", "Matahari", "Bulan", "api unggun", "listrik"),
            ]},
            {"id": "k56", "name": "Kelas 5–6", "questions": [
                Q("Organ pernapasan utama manusia adalah …", "paru-paru", "jantung", "lambung", "ginjal"),
                Q("Organ yang memompa darah ke seluruh tubuh adalah …", "jantung", "paru-paru", "hati", "usus"),
                Q("Bunglon mengubah warna kulitnya untuk …", "menyamar dari musuh (mimikri)", "mencari makan di air", "bernapas", "bertelur"),
                Q("Rangkaian listrik yang lampunya tetap menyala walau satu lampu putus adalah rangkaian …", "paralel", "seri", "terbuka", "pendek"),
                Q("Bulan menutupi Matahari bila dilihat dari Bumi disebut …", "gerhana matahari", "gerhana bulan", "pasang surut", "rotasi bumi"),
                Q("Perputaran Bumi pada porosnya yang menyebabkan siang dan malam disebut …", "rotasi", "revolusi", "gravitasi", "evolusi"),
                Q("Garam yang larut merata di dalam air membentuk …", "larutan", "endapan", "suspensi", "lumpur"),
                Q("Peristiwa makan dan dimakan antarmakhluk hidup disebut …", "rantai makanan", "simbiosis", "adaptasi", "fotosintesis"),
            ]},
        ]},
        {"id": "ips", "name": "IPS", "color": "#7a5a1f", "levels": [
            {"id": "k12", "name": "Kelas 1–2", "questions": [
                Q("Keluarga inti terdiri atas …", "ayah, ibu, dan anak", "kakek dan nenek", "paman dan bibi", "tetangga"),
                Q("Tempat penjual dan pembeli bertemu disebut …", "pasar", "sekolah", "rumah sakit", "perpustakaan"),
                Q("Orang yang bekerja mengobati orang sakit adalah …", "dokter", "petani", "nelayan", "pilot"),
                Q("Orang yang menangkap ikan di laut disebut …", "nelayan", "petani", "pedagang", "guru"),
                Q("Sampah sebaiknya dibuang …", "di tempat sampah", "di sungai", "di jalan", "di halaman tetangga"),
                Q("Hari Kemerdekaan Indonesia diperingati setiap tanggal …", "17 Agustus", "1 Juni", "2 Mei", "28 Oktober"),
                Q("Sikap yang baik kepada tetangga adalah …", "saling menolong", "bertengkar", "mengejek", "tidak peduli"),
                Q("Lambang negara Indonesia adalah …", "Garuda Pancasila", "bendera Merah Putih", "Monas", "rumah gadang"),
            ]},
            {"id": "k34", "name": "Kelas 3–4", "questions": [
                Q("Gambar permukaan bumi pada bidang datar disebut …", "peta", "globe", "foto", "lukisan"),
                Q("Arah mata angin yang berlawanan dengan utara adalah …", "selatan", "timur", "barat", "tenggara"),
                Q("Kegiatan menghasilkan barang atau jasa disebut …", "produksi", "konsumsi", "distribusi", "promosi"),
                Q("Kegiatan menyalurkan barang dari produsen ke konsumen disebut …", "distribusi", "produksi", "konsumsi", "investasi"),
                Q("Ibu kota Provinsi Jawa Barat adalah …", "Bandung", "Semarang", "Surabaya", "Serang"),
                Q("Alat transportasi air adalah …", "kapal", "kereta api", "pesawat", "bus"),
                Q("Semboyan negara Indonesia adalah …", "Bhinneka Tunggal Ika", "Tut Wuri Handayani", "Gotong Royong", "Merdeka atau Mati"),
                Q("Sumber daya alam yang dapat diperbarui adalah …", "hutan", "minyak bumi", "batu bara", "emas"),
            ]},
            {"id": "k56", "name": "Kelas 5–6", "questions": [
                Q("Teks Proklamasi Kemerdekaan Indonesia dibacakan oleh …", "Soekarno (didampingi Mohammad Hatta)", "Soeharto", "Ki Hajar Dewantara", "Jenderal Sudirman"),
                Q("Organisasi negara-negara Asia Tenggara disebut …", "ASEAN", "PBB", "NATO", "OPEC"),
                Q("Sumpah Pemuda diikrarkan pada tanggal …", "28 Oktober 1928", "17 Agustus 1945", "20 Mei 1908", "1 Juni 1945"),
                Q("Indonesia terletak di antara dua benua, yaitu …", "Asia dan Australia", "Asia dan Eropa", "Afrika dan Asia", "Amerika dan Australia"),
                Q("Indonesia terletak di antara dua samudra, yaitu …", "Hindia dan Pasifik", "Atlantik dan Pasifik", "Hindia dan Atlantik", "Arktik dan Pasifik"),
                Q("Hari Kebangkitan Nasional (20 Mei) berawal dari berdirinya …", "Budi Utomo", "Sarekat Islam", "PNI", "Taman Siswa"),
                Q("Ekspor adalah …", "menjual barang ke luar negeri", "membeli barang dari luar negeri", "menabung di bank", "membayar pajak"),
                Q("Tambahan uang yang diberikan bank atas tabungan disebut …", "bunga", "pajak", "denda", "diskon"),
            ]},
        ]},
    ],
}

SMP = {
    "title": "Belajar SMP",
    "subtitle": "Matematika, Bahasa Indonesia, IPA, dan IPS untuk kelas 7–9. Latihan memberi pembahasan; Kuis memberi nilai dan membuka level berikutnya.",
    "pass_score": 70,
    "questions_per_session": 8,
    "subjects": [
        {"id": "matematika", "name": "Matematika", "color": "#2f5d8a", "levels": [
            {"id": "k7", "name": "Kelas 7 · Bilangan Bulat",
             "generator": {"type": "arith", "ops": ["+", "-", "x"], "min": -20, "max": 20, "negative": True, "count": 10}},
            {"id": "k8", "name": "Kelas 8 · Persamaan Linear Satu Variabel",
             "generator": {"type": "linear", "min": -10, "max": 10, "count": 10}},
            {"id": "k9", "name": "Kelas 9 · Pangkat, Akar, Pythagoras",
             "generator": {"type": "power", "max": 15, "count": 10}},
        ]},
        {"id": "bahasa_indonesia", "name": "Bahasa Indonesia", "color": "#8a4b2f", "levels": [
            {"id": "k7", "name": "Kelas 7", "questions": [
                Q("Teks yang menggambarkan objek secara rinci sehingga pembaca seolah melihatnya disebut teks …", "deskripsi", "prosedur", "eksposisi", "negosiasi"),
                Q("Struktur teks cerita fantasi adalah …", "orientasi – komplikasi – resolusi", "resolusi – orientasi – komplikasi", "komplikasi – orientasi – resolusi", "tesis – argumen – penegasan ulang"),
                Q("Puisi lama yang setiap baitnya terdiri atas dua baris disebut …", "gurindam", "pantun", "syair", "soneta"),
                Q("Rima akhir syair adalah …", "a-a-a-a", "a-b-a-b", "a-a-b-b", "a-b-b-a"),
                Q("Ani berkata, \"Saya akan datang.\" Kalimat tersebut termasuk kalimat …", "langsung", "tidak langsung", "pasif", "perintah"),
                Q("Kata \"wisatawan\" termasuk kelas kata …", "benda (nomina)", "kerja (verba)", "sifat (adjektiva)", "keterangan (adverbia)"),
                Q("Fabel adalah cerita yang tokoh-tokohnya …", "binatang", "dewa", "pahlawan sejarah", "raja dan ratu"),
                Q("Surat dari sekolah kepada dinas pendidikan termasuk surat …", "dinas (resmi)", "pribadi", "pembaca", "elektronik pribadi"),
            ]},
            {"id": "k8", "name": "Kelas 8", "questions": [
                Q("Teks yang menyampaikan informasi faktual tentang suatu peristiwa disebut teks …", "berita", "cerpen", "puisi", "drama"),
                Q("Pada unsur berita 5W+1H, huruf H berarti …", "how (bagaimana)", "hari", "hasil", "hukum"),
                Q("Teks yang membujuk pembaca agar memakai suatu produk disebut teks …", "iklan", "eksposisi", "laporan", "prosedur"),
                Q("Kata \"mencontoh\" dibentuk dengan imbuhan …", "meN-", "ber-", "di-", "ter-"),
                Q("Teks eksposisi berisi …", "gagasan atau pendapat yang didukung fakta", "cerita khayalan", "langkah membuat sesuatu", "percakapan tokoh drama"),
                Q("\"Buku itu dibaca oleh Rina.\" termasuk kalimat …", "pasif", "aktif", "perintah", "tanya"),
                Q("Puisi yang terikat aturan jumlah baris, rima, dan suku kata disebut puisi …", "lama", "bebas", "kontemporer", "prosa"),
                Q("\"Menurut saya, setiap sekolah sebaiknya menanam pohon.\" Pernyataan tersebut adalah …", "opini", "fakta", "data", "berita"),
            ]},
            {"id": "k9", "name": "Kelas 9", "questions": [
                Q("Bagian teks laporan percobaan adalah …", "tujuan, alat dan bahan, langkah, hasil, simpulan", "orientasi, komplikasi, resolusi", "tesis, argumen, penegasan ulang", "salam pembuka, isi, salam penutup"),
                Q("Bagian pidato yang berisi salam dan sapaan kepada hadirin disebut …", "pembuka", "isi", "penutup", "lampiran"),
                Q("Cerpen termasuk karya sastra berbentuk …", "prosa", "puisi", "drama", "pantun"),
                Q("Teks yang berisi penilaian (kelebihan dan kekurangan) terhadap suatu karya disebut teks …", "ulasan", "prosedur", "deskripsi", "biografi"),
                Q("Teks diskusi menyajikan …", "pendapat pro dan kontra tentang suatu isu", "langkah-langkah kerja", "riwayat hidup tokoh", "cerita fantasi"),
                Q("Kata baku yang benar adalah …", "analisis", "analisa", "analise", "analisys"),
                Q("\"Jika hujan, kami tidak jadi berangkat.\" Kata \"jika\" adalah konjungsi …", "syarat", "waktu", "tujuan", "perlawanan"),
                Q("Unsur intrinsik cerpen yang menunjukkan tempat, waktu, dan suasana disebut …", "latar", "alur", "tema", "amanat"),
            ]},
        ]},
        {"id": "ipa", "name": "IPA", "color": "#2f7d4f", "levels": [
            {"id": "k7", "name": "Kelas 7", "questions": [
                Q("Satuan SI untuk massa adalah …", "kilogram", "gram", "newton", "liter"),
                Q("Alat untuk mengukur suhu adalah …", "termometer", "barometer", "neraca", "stopwatch"),
                Q("Zat tunggal yang tersusun atas satu jenis atom disebut …", "unsur", "senyawa", "campuran", "larutan"),
                Q("Contoh senyawa adalah …", "air (H₂O)", "oksigen (O₂)", "besi (Fe)", "emas (Au)"),
                Q("Suhu 100 °C sama dengan … kelvin.", "373", "100", "212", "273", explain="K = °C + 273"),
                Q("Sistem tata nama ganda (binomial nomenklatur) diperkenalkan oleh …", "Carolus Linnaeus", "Charles Darwin", "Gregor Mendel", "Robert Hooke"),
                Q("Bagian sel tumbuhan yang tidak dimiliki sel hewan adalah …", "dinding sel dan kloroplas", "membran sel", "inti sel", "sitoplasma"),
                Q("Lapisan atmosfer tempat terjadinya cuaca adalah …", "troposfer", "stratosfer", "mesosfer", "termosfer"),
            ]},
            {"id": "k8", "name": "Kelas 8", "questions": [
                Q("Hukum II Newton dirumuskan sebagai …", "F = m × a", "F = m : a", "F = a : m", "F = m + a"),
                Q("Usaha adalah hasil kali gaya dengan …", "perpindahan", "waktu", "massa", "kecepatan"),
                Q("Satuan tekanan dalam SI adalah …", "pascal (Pa)", "newton (N)", "joule (J)", "watt (W)"),
                Q("Penyerapan sari makanan terbanyak terjadi di …", "usus halus", "lambung", "kerongkongan", "usus besar"),
                Q("Pembuluh darah yang membawa darah dari jantung ke seluruh tubuh adalah …", "arteri (nadi)", "vena (balik)", "trakea", "bronkus"),
                Q("Pengungkit dengan titik tumpu di antara beban dan kuasa adalah pengungkit golongan …", "pertama", "kedua", "ketiga", "keempat"),
                Q("Fotosintesis terutama berlangsung di …", "daun", "akar", "batang", "bunga"),
                Q("Bayangan pada cermin datar bersifat …", "maya, tegak, sama besar", "nyata, terbalik", "maya, diperbesar", "nyata, diperkecil"),
            ]},
            {"id": "k9", "name": "Kelas 9", "questions": [
                Q("Ilmu yang mempelajari pewarisan sifat disebut …", "genetika", "ekologi", "anatomi", "astronomi"),
                Q("Bagian sel yang membawa informasi genetik adalah …", "kromosom (DNA)", "ribosom", "vakuola", "dinding sel"),
                Q("Hukum Ohm dirumuskan sebagai …", "V = I × R", "P = V × I", "F = m × a", "W = F × s"),
                Q("Satuan kuat arus listrik adalah …", "ampere", "volt", "ohm", "watt"),
                Q("Dua kutub magnet senama yang didekatkan akan …", "tolak-menolak", "tarik-menarik", "menyatu", "tidak berpengaruh"),
                Q("Alat untuk menaikkan atau menurunkan tegangan listrik bolak-balik (AC) adalah …", "transformator", "generator", "baterai", "amperemeter"),
                Q("Pembelahan sel yang menghasilkan sel kelamin (gamet) adalah …", "meiosis", "mitosis", "fotosintesis", "respirasi"),
                Q("Contoh bioteknologi konvensional adalah pembuatan …", "tempe", "insulin rekayasa genetika", "tanaman transgenik", "kloning domba"),
            ]},
        ]},
        {"id": "ips", "name": "IPS", "color": "#7a5a1f", "levels": [
            {"id": "k7", "name": "Kelas 7", "questions": [
                Q("Letak Indonesia berdasarkan garis lintang dan bujur disebut letak …", "astronomis", "geografis", "geologis", "sosial"),
                Q("Syarat terjadinya interaksi sosial adalah …", "kontak sosial dan komunikasi", "uang dan pasar", "produksi dan distribusi", "ekspor dan impor"),
                Q("Kebutuhan primer manusia adalah …", "sandang, pangan, dan papan", "mobil dan televisi", "perhiasan", "wisata ke luar negeri"),
                Q("Fosil manusia purba banyak ditemukan di situs …", "Sangiran", "Borobudur", "Trowulan", "Prambanan"),
                Q("Kerajaan Hindu tertua di Indonesia adalah …", "Kutai", "Majapahit", "Singasari", "Mataram Islam"),
                Q("Kelangkaan terjadi karena …", "kebutuhan tidak terbatas, alat pemuas terbatas", "semua barang murah", "penduduk sedikit", "uang terlalu banyak"),
                Q("Kegiatan menggunakan barang untuk memenuhi kebutuhan disebut …", "konsumsi", "produksi", "distribusi", "ekspor"),
                Q("Pelaku ekonomi yang menghasilkan barang dan jasa adalah …", "rumah tangga produsen (perusahaan)", "rumah tangga konsumen", "pembeli", "penabung"),
            ]},
            {"id": "k8", "name": "Kelas 8", "questions": [
                Q("Mobilitas sosial adalah …", "perpindahan posisi seseorang dalam struktur sosial", "perpindahan barang", "pergantian musim", "perpindahan antarpulau"),
                Q("Bangsa Eropa yang pertama kali tiba di Kepulauan Maluku (1512) adalah …", "Portugis", "Belanda", "Inggris", "Prancis"),
                Q("Persekutuan dagang Belanda di Hindia Timur bernama …", "VOC", "EIC", "KNIL", "NHM"),
                Q("Sistem tanam paksa (cultuurstelsel) diterapkan oleh …", "Van den Bosch", "Daendels", "Raffles", "Jan Pieterszoon Coen"),
                Q("Pasar tempat penjual dan pembeli bertemu langsung dan tawar-menawar disebut pasar …", "tradisional", "modern", "faktor produksi", "modal"),
                Q("Letak geografis Indonesia menguntungkan karena berada di …", "jalur perdagangan internasional", "kutub utara", "tengah benua Afrika", "gurun pasir"),
                Q("Pajak digunakan pemerintah untuk …", "membiayai pembangunan dan layanan umum", "keuntungan pribadi pegawai", "membeli barang mewah", "disimpan tanpa digunakan"),
                Q("Perlawanan Pangeran Diponegoro terhadap Belanda dikenal sebagai Perang …", "Jawa (1825–1830)", "Padri", "Aceh", "Banjar"),
            ]},
            {"id": "k9", "name": "Kelas 9", "questions": [
                Q("Peristiwa Rengasdengklok terjadi menjelang …", "Proklamasi Kemerdekaan 1945", "Sumpah Pemuda", "Reformasi 1998", "Konferensi Meja Bundar"),
                Q("Konferensi Asia Afrika tahun 1955 diselenggarakan di …", "Bandung", "Jakarta", "Bogor", "Yogyakarta"),
                Q("Era Reformasi di Indonesia dimulai tahun …", "1998", "1945", "1966", "2004"),
                Q("Globalisasi adalah …", "proses mendunia yang membuat hubungan antarnegara makin terbuka", "kembali ke kehidupan purba", "menutup diri dari dunia luar", "perang antarnegara"),
                Q("Lembaga yang berwenang mengeluarkan dan mengedarkan rupiah adalah …", "Bank Indonesia", "bank swasta", "koperasi", "pegadaian"),
                Q("Perdagangan internasional terjadi karena …", "perbedaan sumber daya alam antarnegara", "semua negara menghasilkan barang yang sama", "larangan pemerintah", "tidak ada kebutuhan"),
                Q("Negara-negara Asia Tenggara bergabung dalam …", "ASEAN", "Uni Eropa", "Liga Arab", "NAFTA"),
                Q("Hasil Konferensi Meja Bundar (1949) adalah …", "pengakuan kedaulatan Indonesia oleh Belanda", "Sumpah Pemuda", "Dekrit Presiden", "Supersemar"),
            ]},
        ]},
    ],
}


def write(game, data):
    d = os.path.join(ROOT, game, "data")
    os.makedirs(d, exist_ok=True)
    seen = set()
    for s in data["subjects"]:
        for lv in s["levels"]:
            for q in lv.get("questions", []):
                assert q["q"] not in seen, q["q"]
                seen.add(q["q"])
                assert len(set(q["options"])) == len(q["options"]), q["q"]
    with open(os.path.join(d, "course.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent="\t")
        f.write("\n")
    n = sum(len(lv.get("questions", [])) for s in data["subjects"] for lv in s["levels"])
    print(f"{game}: {len(data['subjects'])} mata pelajaran, {n} soal bank + soal matematika acak")


if __name__ == "__main__":
    write("education_sd", SD)
    write("education_smp", SMP)
