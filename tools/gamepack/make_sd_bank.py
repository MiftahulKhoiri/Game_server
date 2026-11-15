#!/usr/bin/env python3
"""Bank soal "Petualangan Pulau Ilmu" (Game Pembelajaran SD, kelas 1–6).

Menulis client/games/education_sd/data/pulau_ilmu.json setelah memvalidasi seluruh data. Gagal (exit 1)
bila ada: ID kembar, soal tanpa pertanyaan/penjelasan, pilihan kosong/kembar, jawaban di luar indeks,
tipe tidak dikenal, kelas di luar 1–6, gambar (bentuk) yang tidak bisa digambar game, topik tanpa soal.

Jawaban benar pilihan ganda SELALU ditulis pertama di sini; game mengacak urutan pilihan saat tampil.
Matematika berhitung memakai pembuat soal (dihitung, bukan ditebak) yang diatur di TOPICS[...]["gen"].

Pakai:  python3 tools/gamepack/make_sd_bank.py
"""
import json
import os
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "client", "games", "education_sd", "data", "pulau_ilmu.json")

TYPES = {"mc", "tf", "fill", "match", "order_letters", "order_words", "sort_numbers", "count", "pick_image",
         "classify", "logic"}
SHAPES = {"lingkaran", "persegi", "persegi_panjang", "segitiga", "bintang", "belah_ketupat", "trapesium",
          "jajar_genjang", "kubus", "balok", "tabung", "kerucut", "bola", "limas", "apel"}
DIFF = {"tf": 1, "mc": 1, "pick_image": 1, "count": 1, "fill": 2, "order_letters": 2, "order_words": 2,
        "match": 2, "classify": 2, "sort_numbers": 2, "logic": 3}
TYPE_NAMES = {"mc": "Pilihan ganda", "tf": "Benar atau salah", "fill": "Lengkapi yang kosong",
              "match": "Pasangkan", "order_letters": "Susun huruf", "order_words": "Susun urutan",
              "sort_numbers": "Urutkan angka", "count": "Hitung gambar", "pick_image": "Pilih gambar",
              "classify": "Kelompokkan", "logic": "Teka-teki logika"}

REGIONS = [
    {"id": "matematika", "name": "Kerajaan Matematika", "subject": "Matematika", "color": "#3f7fd8",
     "npc": "Raja Angka", "npc_color": "#f0b429",
     "intro": "Selamat datang di Kerajaan Matematika! Jembatan dan gerbang di sini terkunci teka-teki angka. Bantu aku membukanya!"},
    {"id": "bahasa", "name": "Hutan Bahasa", "subject": "Bahasa Indonesia", "color": "#3fae63",
     "npc": "Kak Kancil", "npc_color": "#c98a4b",
     "intro": "Halo, aku Kak Kancil! Pohon-pohon di Hutan Bahasa menyimpan huruf, kata, dan cerita. Ayo kita jelajahi!"},
    {"id": "ipa", "name": "Laboratorium IPA", "subject": "IPA", "color": "#2fb3a6",
     "npc": "Profesor Kiko", "npc_color": "#8a6bd8",
     "intro": "Aku Profesor Kiko. Di laboratorium ini kita mengamati hewan, tumbuhan, tubuh, dan alam semesta!"},
    {"id": "ips", "name": "Negeri Penjelajah IPS", "subject": "IPS", "color": "#e0813d",
     "npc": "Nakhoda Bima", "npc_color": "#3b5b9a",
     "intro": "Ahoi! Aku Nakhoda Bima. Kita akan berlayar mengenal keluarga, peta, budaya, dan sejarah Nusantara."},
]

# Topik = area di peta wilayah. "gen": pembuat soal per kelas (lihat client/games/education_sd/scripts/sd_gen.gd).
# "card": kartu pengetahuan yang didapat saat area selesai (fakta pendek yang benar).
TOPICS = [
    # --- Kerajaan Matematika
    {"id": "berhitung", "region": "matematika", "name": "Lembah Berhitung", "grades": [1, 2],
     "story": "Kurcaci penjaga lembah lupa menghitung buah apelnya. Bantu ia menghitung dan mengurutkan!",
     "gen": {"1": ["count:1:10", "sort:1:20"], "2": ["count:5:20", "sort:10:100"]},
     "card": {"title": "Angka Nol", "fact": "Angka 0 berarti tidak ada benda sama sekali. Bilangan apa pun ditambah 0 hasilnya tetap bilangan itu."}},
    {"id": "penjumlahan", "region": "matematika", "name": "Jembatan Penjumlahan", "grades": [1, 2, 3, 4, 5, 6],
     "story": "Papan jembatan hilang! Setiap jawaban penjumlahan yang benar memasang satu papan baru.",
     "gen": {"1": ["add:1:10"], "2": ["add:10:50"], "3": ["add:100:500"], "4": ["add:1000:5000"], "5": ["add:10000:50000"], "6": ["addneg:-20:20"]},
     "card": {"title": "Sifat Tukar", "fact": "Pada penjumlahan, urutan boleh ditukar: 3 + 5 = 5 + 3. Ini disebut sifat komutatif."}},
    {"id": "pengurangan", "region": "matematika", "name": "Gua Pengurangan", "grades": [1, 2, 3, 4, 5, 6],
     "story": "Kelelawar gua mengambil batu permata. Hitung berapa yang tersisa agar gua terang kembali.",
     "gen": {"1": ["sub:1:20"], "2": ["sub:10:99"], "3": ["sub:100:999"], "4": ["sub:1000:9999"], "5": ["sub:10000:99999"], "6": ["subneg:-20:20"]},
     "card": {"title": "Cek dengan Penjumlahan", "fact": "Hasil pengurangan bisa diperiksa dengan penjumlahan: jika 9 − 4 = 5, maka 5 + 4 = 9."}},
    {"id": "perkalian", "region": "matematika", "name": "Menara Perkalian", "grades": [2, 3, 4, 5, 6],
     "story": "Tangga menara hanya muncul bila perkalian dijawab dengan benar. Ayo naik ke puncak!",
     "gen": {"2": ["mul:1:5"], "3": ["mul:2:10"], "4": ["mul2x1"], "5": ["mul2x2"], "6": ["pow"]},
     "card": {"title": "Perkalian = Penjumlahan Berulang", "fact": "4 × 3 artinya 3 + 3 + 3 + 3 = 12."}},
    {"id": "pembagian", "region": "matematika", "name": "Pasar Pembagian", "grades": [3, 4, 5, 6],
     "story": "Pedagang ingin membagi kue sama banyak ke setiap keranjang. Bantu ia membaginya!",
     "gen": {"3": ["div:2:10"], "4": ["div:2:12"], "5": ["div:5:25"], "6": ["div:10:50"]},
     "card": {"title": "Pembagian Kebalikan Perkalian", "fact": "Jika 6 × 4 = 24, maka 24 : 4 = 6 dan 24 : 6 = 4."}},
    {"id": "pecahan", "region": "matematika", "name": "Taman Pecahan", "grades": [3, 4, 5, 6],
     "story": "Kue di taman dipotong-potong. Bandingkan potongan pecahan agar pesta bisa dimulai.",
     "gen": {"3": ["frac_cmp"], "4": ["frac_cmp", "frac_eq"], "5": ["frac_eq", "frac_cmp"], "6": ["frac_eq", "frac_cmp"]},
     "card": {"title": "Pecahan Senilai", "fact": "1/2 sama besar dengan 2/4 dan 3/6. Pembilang dan penyebut dikali bilangan yang sama."}},
    {"id": "pengukuran", "region": "matematika", "name": "Bengkel Pengukuran", "grades": [1, 2, 3, 4, 5, 6],
     "story": "Tukang bengkel butuh ukuran yang tepat: panjang, berat, waktu, dan isi.",
     "gen": {"2": ["conv:m_cm"], "3": ["conv:kg_g", "conv:jam_menit"], "4": ["conv:km_m", "conv:m_cm"], "5": ["conv:l_ml", "conv:kg_g"], "6": ["conv:km_m", "conv:l_ml", "conv:jam_menit"]},
     "card": {"title": "Satuan Baku", "fact": "Satuan baku seperti meter dan kilogram hasilnya sama di mana pun, berbeda dengan jengkal atau langkah."}},
    {"id": "bangun_datar", "region": "matematika", "name": "Lapangan Bangun Datar", "grades": [1, 2, 3, 4, 5, 6],
     "story": "Prajurit kerajaan berbaris membentuk bangun datar. Kenali bentuk-bentuknya!",
     "card": {"title": "Segitiga", "fact": "Jumlah ketiga sudut pada segitiga selalu 180 derajat."}},
    {"id": "bangun_ruang", "region": "matematika", "name": "Gudang Bangun Ruang", "grades": [4, 5, 6],
     "story": "Gudang penuh kotak, kaleng, dan bola. Kenali bangun ruang untuk merapikannya.",
     "card": {"title": "Kubus", "fact": "Kubus punya 6 sisi persegi, 12 rusuk, dan 8 titik sudut."}},
    {"id": "logika", "region": "matematika", "name": "Gerbang Teka-teki", "grades": [1, 2, 3, 4, 5, 6],
     "story": "Gerbang terakhir hanya terbuka bila pola angka ditebak dengan benar.",
     "gen": {"1": ["pattern:1"], "2": ["pattern:2"], "3": ["pattern:3"], "4": ["pattern:4"], "5": ["pattern:5"], "6": ["pattern:6"]},
     "card": {"title": "Pola Bilangan", "fact": "Pola bilangan adalah susunan bilangan yang mengikuti aturan tetap, misalnya selalu ditambah 2."}},
    # --- Hutan Bahasa
    {"id": "huruf", "region": "bahasa", "name": "Pohon Huruf", "grades": [1, 2],
     "story": "Huruf-huruf berjatuhan dari Pohon Huruf. Susun kembali agar pohonnya berbunga!",
     "card": {"title": "Huruf Vokal", "fact": "Bahasa Indonesia punya 5 huruf vokal: a, i, u, e, o. Huruf lainnya disebut konsonan."}},
    {"id": "kata_kalimat", "region": "bahasa", "name": "Jalan Setapak Kalimat", "grades": [1, 2, 3, 4, 5, 6],
     "story": "Batu-batu di jalan setapak bertuliskan kata. Susun menjadi kalimat agar jalannya terbuka.",
     "card": {"title": "Kalimat", "fact": "Kalimat diawali huruf kapital dan diakhiri tanda titik, tanda tanya, atau tanda seru."}},
    {"id": "tanda_baca", "region": "bahasa", "name": "Sungai Tanda Baca", "grades": [2, 3, 5],
     "story": "Perahu hanya bisa menyeberang bila tanda baca dipasang di tempat yang benar.",
     "card": {"title": "Tanda Tanya", "fact": "Tanda tanya (?) dipakai di akhir kalimat tanya, contohnya: Kamu tinggal di mana?"}},
    {"id": "sinonim_antonim", "region": "bahasa", "name": "Danau Kata Kembar", "grades": [2, 3, 6],
     "story": "Di danau ini setiap kata punya kembaran (sinonim) atau lawan (antonim). Temukan pasangannya!",
     "card": {"title": "Sinonim dan Antonim", "fact": "Sinonim adalah kata yang maknanya sama (pandai–pintar). Antonim adalah lawan kata (besar–kecil)."}},
    {"id": "bacaan", "region": "bahasa", "name": "Perpustakaan Daun", "grades": [3, 4, 5, 6],
     "story": "Burung hantu penjaga perpustakaan ingin tahu apakah kamu memahami bacaan pendek ini.",
     "card": {"title": "Ide Pokok", "fact": "Ide pokok adalah gagasan utama sebuah paragraf; biasanya ada di kalimat utama."}},
    {"id": "cerita", "region": "bahasa", "name": "Panggung Cerita", "grades": [3, 4, 5, 6],
     "story": "Para tokoh cerita lupa naskahnya. Bantu mereka mengenali bagian-bagian cerita!",
     "card": {"title": "Fabel", "fact": "Fabel adalah cerita yang tokohnya binatang yang berperilaku seperti manusia, misalnya Kancil dan Buaya."}},
    {"id": "pantun", "region": "bahasa", "name": "Gubuk Pantun", "grades": [4, 6],
     "story": "Nenek Pantun hanya membuka pintu bagi yang paham aturan pantun.",
     "card": {"title": "Pantun", "fact": "Satu bait pantun terdiri dari 4 baris, bersajak a-b-a-b. Baris 1–2 sampiran, baris 3–4 isi."}},
    # --- Laboratorium IPA
    {"id": "pancaindra", "region": "ipa", "name": "Ruang Pancaindra", "grades": [1],
     "story": "Robot lab kehilangan sensornya. Ajari ia tentang pancaindra manusia!",
     "card": {"title": "Pancaindra", "fact": "Manusia punya lima indra: mata, telinga, hidung, lidah, dan kulit."}},
    {"id": "tubuh", "region": "ipa", "name": "Ruang Tubuh Manusia", "grades": [1, 4, 5],
     "story": "Model tubuh di lab perlu dipasang. Kenali organ dan tugasnya!",
     "card": {"title": "Jantung", "fact": "Jantung adalah otot yang memompa darah ke seluruh tubuh tanpa berhenti."}},
    {"id": "hewan", "region": "ipa", "name": "Kebun Binatang Mini", "grades": [1, 2, 3, 5, 6],
     "story": "Hewan-hewan di kebun mini perlu dikelompokkan sesuai cirinya.",
     "card": {"title": "Herbivora", "fact": "Herbivora adalah hewan pemakan tumbuhan, contohnya sapi, kambing, dan kelinci."}},
    {"id": "tumbuhan", "region": "ipa", "name": "Rumah Kaca", "grades": [1, 2, 4],
     "story": "Tanaman di rumah kaca layu. Pelajari kebutuhan tumbuhan agar segar kembali!",
     "card": {"title": "Fotosintesis", "fact": "Tumbuhan hijau membuat makanannya sendiri di daun dengan bantuan cahaya matahari. Prosesnya disebut fotosintesis."}},
    {"id": "wujud_benda", "region": "ipa", "name": "Meja Percobaan Wujud", "grades": [2, 3],
     "story": "Percobaan es, air, dan uap sedang berlangsung. Amati perubahan wujudnya!",
     "card": {"title": "Tiga Wujud Benda", "fact": "Benda bisa berwujud padat, cair, atau gas. Air bisa menjadi es (padat) dan uap (gas)."}},
    {"id": "energi", "region": "ipa", "name": "Ruang Energi", "grades": [3, 4, 5, 6],
     "story": "Lampu lab padam! Pelajari sumber energi untuk menyalakannya kembali.",
     "card": {"title": "Energi Matahari", "fact": "Matahari adalah sumber energi terbesar bagi Bumi: memberi cahaya dan panas."}},
    {"id": "lingkungan", "region": "ipa", "name": "Taman Lingkungan", "grades": [2, 4],
     "story": "Taman lab kotor. Ayo belajar menjaga lingkungan!",
     "card": {"title": "Daur Ulang", "fact": "Botol plastik bekas bisa didaur ulang menjadi barang baru sehingga sampah berkurang."}},
    {"id": "ekosistem", "region": "ipa", "name": "Akuarium Ekosistem", "grades": [5, 6],
     "story": "Di akuarium raksasa, setiap makhluk hidup saling bergantung. Temukan hubungannya!",
     "card": {"title": "Rantai Makanan", "fact": "Rantai makanan selalu dimulai dari produsen, yaitu tumbuhan hijau."}},
    {"id": "tata_surya", "region": "ipa", "name": "Teropong Tata Surya", "grades": [6],
     "story": "Teropong lab mengarah ke langit malam. Kenali anggota tata surya!",
     "card": {"title": "Yupiter", "fact": "Yupiter adalah planet terbesar di tata surya."}},
    # --- Negeri Penjelajah IPS
    {"id": "keluarga", "region": "ips", "name": "Desa Keluarga", "grades": [1],
     "story": "Penduduk desa sedang berkumpul. Kenali anggota keluarga dan sikap yang baik.",
     "card": {"title": "Keluarga Inti", "fact": "Keluarga inti terdiri dari ayah, ibu, dan anak."}},
    {"id": "masyarakat", "region": "ips", "name": "Alun-alun Masyarakat", "grades": [1, 2, 5],
     "story": "Warga alun-alun saling membantu. Pelajari aturan dan kehidupan bermasyarakat!",
     "card": {"title": "Gotong Royong", "fact": "Gotong royong adalah bekerja bersama-sama untuk kepentingan bersama, misalnya kerja bakti."}},
    {"id": "pekerjaan", "region": "ips", "name": "Pelabuhan Pekerjaan", "grades": [2],
     "story": "Kapal-kapal membawa orang dengan pekerjaan berbeda. Kenali pekerjaan dan tempatnya!",
     "card": {"title": "Barang dan Jasa", "fact": "Petani menghasilkan barang (padi), sedangkan guru dan dokter memberikan jasa."}},
    {"id": "lingkungan_alam", "region": "ips", "name": "Bukit Kenampakan Alam", "grades": [2, 4],
     "story": "Dari puncak bukit terlihat gunung, sungai, dan sawah. Kenali kenampakan alam dan buatan!",
     "card": {"title": "Kenampakan Alam", "fact": "Gunung, sungai, dan laut adalah kenampakan alam; sawah dan waduk dibuat oleh manusia."}},
    {"id": "peta", "region": "ips", "name": "Menara Peta", "grades": [3],
     "story": "Nakhoda butuh navigator! Pelajari peta dan arah mata angin.",
     "card": {"title": "Mata Angin", "fact": "Empat arah mata angin utama adalah utara, timur, selatan, dan barat."}},
    {"id": "ekonomi", "region": "ips", "name": "Pasar Terapung", "grades": [3, 4, 6],
     "story": "Pedagang di pasar terapung sibuk berjual beli. Pelajari kegiatan ekonomi!",
     "card": {"title": "Koperasi", "fact": "Koperasi adalah badan usaha yang berasaskan kekeluargaan."}},
    {"id": "budaya", "region": "ips", "name": "Panggung Budaya Nusantara", "grades": [3, 4],
     "story": "Festival budaya Nusantara dimulai! Kenali rumah adat, tarian, dan alat musik daerah.",
     "card": {"title": "Angklung", "fact": "Angklung adalah alat musik bambu dari Jawa Barat yang dimainkan dengan cara digoyangkan."}},
    {"id": "sejarah", "region": "ips", "name": "Museum Sejarah", "grades": [5, 6],
     "story": "Museum menyimpan kisah perjuangan bangsa. Susun peristiwa sejarah dengan benar!",
     "card": {"title": "Sumpah Pemuda", "fact": "Sumpah Pemuda diikrarkan pada 28 Oktober 1928 oleh para pemuda dari berbagai daerah."}},
    {"id": "geografi", "region": "ips", "name": "Pulau Geografi", "grades": [4, 6],
     "story": "Kapal berlayar mengelilingi Indonesia. Kenali letak dan keadaan alam negeri kita!",
     "card": {"title": "Negara Kepulauan", "fact": "Indonesia adalah negara kepulauan yang terletak di antara Benua Asia dan Australia."}},
]


def mc(t, g, q, correct, *wrong, explain, hint=""):
    return dict(topic=t, grade=g, type="mc", q=q, options=[correct, *wrong], answer=0, explain=explain, hint=hint)


def logic(t, g, q, correct, *wrong, explain, hint=""):
    d = mc(t, g, q, correct, *wrong, explain=explain, hint=hint)
    d["type"] = "logic"
    return d


def tf(t, g, q, ans, explain):
    return dict(topic=t, grade=g, type="tf", q=q, answer=ans, explain=explain)


def fill(t, g, q, correct, *wrong, explain):
    return dict(topic=t, grade=g, type="fill", q=q, options=[correct, *wrong], answer=0, explain=explain)


def pick(t, g, q, correct, *wrong, explain):
    return dict(topic=t, grade=g, type="pick_image", q=q, options=[correct, *wrong], answer=0, explain=explain)


def match(t, g, q, pairs, explain):
    return dict(topic=t, grade=g, type="match", q=q, pairs=[list(p) for p in pairs], explain=explain)


def letters(t, g, q, word, explain):
    return dict(topic=t, grade=g, type="order_letters", q=q, word=word, explain=explain)


def words(t, g, q, items, explain):
    return dict(topic=t, grade=g, type="order_words", q=q, items=list(items), explain=explain)


def sortn(t, g, q, nums, desc, explain):
    return dict(topic=t, grade=g, type="sort_numbers", q=q, numbers=list(nums), desc=desc, explain=explain)


def count(t, g, q, shape, n, explain):
    return dict(topic=t, grade=g, type="count", q=q, shape=shape, count=n, explain=explain)


def classify(t, g, q, bins, items, explain):
    return dict(topic=t, grade=g, type="classify", q=q, bins=list(bins), items=[list(i) for i in items], explain=explain)


Q = [
    # ===================== MATEMATIKA (bank; soal berhitung lain dibuat otomatis)
    pick("bangun_datar", 1, "Manakah yang berbentuk segitiga?", "segitiga", "lingkaran", "persegi", "bintang",
         explain="Segitiga punya 3 sisi dan 3 sudut."),
    pick("bangun_datar", 1, "Manakah yang berbentuk lingkaran?", "lingkaran", "persegi", "segitiga", "belah_ketupat",
         explain="Lingkaran bentuknya bulat dan tidak punya sudut."),
    tf("bangun_datar", 1, "Persegi memiliki 4 sisi yang sama panjang.", True, "Benar. Keempat sisi persegi sama panjang."),
    mc("pengukuran", 1, "Mana yang paling berat?", "gajah", "semut", "kucing", "ayam", explain="Gajah adalah hewan darat yang sangat besar dan berat."),
    mc("pengukuran", 1, "Satu minggu ada berapa hari?", "7", "5", "6", "10", explain="Senin, Selasa, Rabu, Kamis, Jumat, Sabtu, Minggu = 7 hari."),
    count("berhitung", 1, "Ada berapa apel?", "apel", 6, "Hitung satu per satu: ada 6 apel."),
    pick("bangun_datar", 2, "Manakah yang berbentuk persegi panjang?", "persegi_panjang", "persegi", "lingkaran", "segitiga",
         explain="Persegi panjang punya 2 sisi panjang dan 2 sisi pendek yang sama."),
    mc("bangun_datar", 2, "Bangun datar dengan 4 sisi sama panjang dan 4 sudut siku-siku adalah …", "persegi", "segitiga", "lingkaran", "trapesium",
       explain="Itulah ciri persegi."),
    tf("bangun_datar", 2, "Lingkaran memiliki 3 sudut.", False, "Salah. Lingkaran tidak memiliki sudut."),
    mc("pengukuran", 2, "Pukul 07.00 ditambah 2 jam menjadi pukul …", "09.00", "08.00", "10.00", "05.00", explain="7 + 2 = 9, jadi pukul 09.00."),
    fill("berhitung", 2, "5 + ___ = 12", "7", "6", "8", "5", explain="12 − 5 = 7."),
    pick("bangun_datar", 3, "Manakah yang berbentuk belah ketupat?", "belah_ketupat", "persegi_panjang", "trapesium", "lingkaran",
         explain="Belah ketupat punya 4 sisi sama panjang dan bentuknya seperti wajik."),
    mc("bangun_datar", 3, "Keliling persegi dengan sisi 5 cm adalah …", "20 cm", "25 cm", "10 cm", "15 cm", explain="Keliling persegi = 4 × sisi = 4 × 5 = 20 cm."),
    fill("bangun_datar", 3, "Sudut siku-siku besarnya ___ derajat.", "90", "45", "180", "60", explain="Sudut siku-siku seperti pojok buku: 90 derajat."),
    tf("pecahan", 3, "1/2 lebih besar daripada 1/4.", True, "Benar. Setengah kue lebih banyak daripada seperempat kue."),
    mc("pecahan", 3, "Kue dibagi 2 sama besar. Satu bagiannya ditulis …", "1/2", "2/1", "1/4", "2/2", explain="Satu dari dua bagian sama besar = 1/2."),
    mc("bangun_datar", 4, "Luas persegi panjang dengan panjang 8 cm dan lebar 5 cm adalah …", "40 cm²", "26 cm²", "13 cm²", "45 cm²",
       explain="Luas = panjang × lebar = 8 × 5 = 40 cm²."),
    mc("bangun_datar", 4, "Keliling persegi panjang dengan panjang 7 cm dan lebar 3 cm adalah …", "20 cm", "21 cm", "10 cm", "17 cm",
       explain="Keliling = 2 × (7 + 3) = 2 × 10 = 20 cm."),
    pick("bangun_datar", 4, "Manakah gambar trapesium?", "trapesium", "persegi", "segitiga", "lingkaran",
         explain="Trapesium punya sepasang sisi sejajar yang panjangnya berbeda."),
    mc("logika", 4, "FPB dari 12 dan 18 adalah …", "6", "3", "12", "36", explain="Faktor 12: 1,2,3,4,6,12. Faktor 18: 1,2,3,6,9,18. Faktor sama terbesar = 6."),
    mc("logika", 4, "KPK dari 4 dan 6 adalah …", "12", "24", "10", "2", explain="Kelipatan 4: 4,8,12. Kelipatan 6: 6,12. Yang sama dan terkecil = 12."),
    tf("pecahan", 4, "0,5 sama dengan 1/2.", True, "Benar. 1/2 = 5/10 = 0,5."),
    pick("bangun_ruang", 4, "Manakah gambar kubus?", "kubus", "tabung", "bola", "kerucut", explain="Kubus berbentuk seperti dadu: semua sisinya persegi."),
    mc("bangun_datar", 5, "Luas segitiga dengan alas 8 cm dan tinggi 6 cm adalah …", "24 cm²", "48 cm²", "14 cm²", "28 cm²",
       explain="Luas segitiga = alas × tinggi : 2 = 8 × 6 : 2 = 24 cm²."),
    mc("bangun_datar", 5, "Luas jajar genjang dengan alas 10 cm dan tinggi 6 cm adalah …", "60 cm²", "30 cm²", "16 cm²", "32 cm²",
       explain="Luas jajar genjang = alas × tinggi = 10 × 6 = 60 cm²."),
    pick("bangun_datar", 5, "Manakah gambar jajar genjang?", "jajar_genjang", "persegi", "trapesium", "lingkaran",
         explain="Jajar genjang punya dua pasang sisi sejajar dan tampak miring."),
    mc("bangun_ruang", 5, "Volume kubus dengan rusuk 3 cm adalah …", "27 cm³", "9 cm³", "18 cm³", "12 cm³", explain="Volume kubus = s × s × s = 3 × 3 × 3 = 27 cm³."),
    mc("bangun_ruang", 5, "Volume balok dengan panjang 5 cm, lebar 4 cm, dan tinggi 2 cm adalah …", "40 cm³", "11 cm³", "20 cm³", "22 cm³",
       explain="Volume balok = p × l × t = 5 × 4 × 2 = 40 cm³."),
    pick("bangun_ruang", 5, "Manakah gambar tabung?", "tabung", "kubus", "kerucut", "bola", explain="Tabung seperti kaleng: alas dan tutupnya lingkaran."),
    tf("bangun_ruang", 5, "Kubus memiliki 6 sisi berbentuk persegi.", True, "Benar. Coba lihat dadu: ada 6 sisi."),
    mc("pengukuran", 5, "Mobil melaju 60 km setiap jam. Dalam 2 jam mobil menempuh …", "120 km", "60 km", "62 km", "30 km", explain="Jarak = kecepatan × waktu = 60 × 2 = 120 km."),
    mc("pecahan", 5, "25% sama dengan pecahan …", "1/4", "1/2", "1/5", "2/5", explain="25% = 25/100 = 1/4."),
    mc("bangun_datar", 6, "Luas lingkaran dengan jari-jari 7 cm (π = 22/7) adalah …", "154 cm²", "44 cm²", "49 cm²", "308 cm²",
       explain="Luas = π × r × r = 22/7 × 7 × 7 = 154 cm²."),
    mc("bangun_datar", 6, "Keliling lingkaran dengan diameter 14 cm (π = 22/7) adalah …", "44 cm", "22 cm", "154 cm", "88 cm",
       explain="Keliling = π × d = 22/7 × 14 = 44 cm."),
    pick("bangun_ruang", 6, "Manakah gambar kerucut?", "kerucut", "tabung", "balok", "bola", explain="Kerucut seperti topi ulang tahun: alas lingkaran dan satu titik puncak."),
    tf("bangun_ruang", 6, "Tabung memiliki 3 sisi.", True, "Benar: sisi alas, sisi tutup (lingkaran), dan selimut tabung."),
    mc("logika", 6, "Modus dari data 3, 5, 5, 6, 7 adalah …", "5", "3", "6", "7", explain="Modus = nilai yang paling sering muncul. Angka 5 muncul dua kali."),
    mc("logika", 6, "Rata-rata dari 4, 6, dan 8 adalah …", "6", "18", "8", "4", explain="(4 + 6 + 8) : 3 = 18 : 3 = 6."),

    # ===================== HUTAN BAHASA
    mc("huruf", 1, "Huruf vokal adalah …", "a, i, u, e, o", "b, c, d, f, g", "k, l, m, n, p", "r, s, t, w, y", explain="Huruf vokal ada lima: a, i, u, e, o."),
    letters("huruf", 1, "Susun huruf menjadi nama buah:", "APEL", "A-P-E-L dibaca apel."),
    letters("huruf", 1, "Susun huruf menjadi nama hewan:", "KUCING", "K-U-C-I-N-G dibaca kucing."),
    fill("huruf", 1, "B _ K U  (benda untuk dibaca)", "U", "A", "I", "O", explain="Kata yang benar adalah BUKU."),
    mc("huruf", 1, "Kata \"bola\" diawali huruf …", "B", "D", "P", "L", explain="B-O-L-A, huruf pertamanya B."),
    match("huruf", 1, "Pasangkan huruf kecil dengan huruf besarnya", [("a", "A"), ("b", "B"), ("d", "D"), ("g", "G")],
          explain="Setiap huruf kecil punya pasangan huruf kapital."),
    tf("kata_kalimat", 1, "Kata \"meja\" terdiri atas 2 suku kata.", True, "Benar: me-ja."),
    words("kata_kalimat", 1, "Susun kata menjadi kalimat:", ["Adik", "minum", "susu"], "Kalimat yang benar: Adik minum susu."),
    mc("kata_kalimat", 1, "Huruf pertama nama orang ditulis dengan huruf …", "kapital (besar)", "kecil", "miring", "angka", explain="Contoh: Budi, Siti."),
    mc("kata_kalimat", 1, "Penulisan kata yang benar adalah …", "rumah", "ruamh", "rmuah", "rumha", explain="R-U-M-A-H."),
    letters("huruf", 2, "Susun huruf menjadi tempat belajar:", "SEKOLAH", "S-E-K-O-L-A-H dibaca sekolah."),
    mc("sinonim_antonim", 2, "Lawan kata \"besar\" adalah …", "kecil", "tinggi", "panjang", "berat", explain="Besar lawannya kecil."),
    mc("sinonim_antonim", 2, "Persamaan kata \"pandai\" adalah …", "pintar", "malas", "lambat", "lupa", explain="Pandai dan pintar artinya sama."),
    match("sinonim_antonim", 2, "Pasangkan kata dengan lawan katanya", [("siang", "malam"), ("tinggi", "pendek"), ("panas", "dingin"), ("cepat", "lambat")],
          explain="Antonim adalah kata yang maknanya berlawanan."),
    tf("sinonim_antonim", 2, "\"Rajin\" adalah lawan kata dari \"malas\".", True, "Benar. Rajin berlawanan dengan malas."),
    mc("tanda_baca", 2, "Kalimat tanya diakhiri tanda …", "?", ".", "!", ",", explain="Contoh: Siapa namamu?"),
    fill("tanda_baca", 2, "Ibu pergi ke pasar ___  (kalimat berita)", ".", "?", "!", ",", explain="Kalimat berita diakhiri tanda titik."),
    words("kata_kalimat", 2, "Susun kata menjadi kalimat:", ["Kakak", "membaca", "buku", "di", "kamar"], "Kalimat yang benar: Kakak membaca buku di kamar."),
    mc("kata_kalimat", 2, "Kalimat perintah yang tepat adalah …", "Tolong tutup pintunya!", "Pintu itu berwarna cokelat.", "Apakah pintunya terbuka?", "Pintu rumahku besar.",
       explain="Kalimat perintah menyuruh orang melakukan sesuatu."),
    mc("kata_kalimat", 2, "Kata \"bermain\" berasal dari kata dasar …", "main", "bermai", "ain", "bermain", explain="Ber- + main = bermain."),
    mc("cerita", 3, "Cerita tentang binatang yang berperilaku seperti manusia disebut …", "fabel", "legenda", "puisi", "berita", explain="Contoh fabel: Kancil dan Buaya."),
    mc("bacaan", 3, "Bacalah: \"Dina menanam bunga mawar di halaman. Setiap pagi ia menyiramnya.\" Kapan Dina menyiram bunga?",
       "setiap pagi", "setiap malam", "setiap siang", "seminggu sekali", explain="Di bacaan tertulis: setiap pagi ia menyiramnya."),
    mc("bacaan", 3, "Ide pokok paragraf biasanya terdapat pada …", "kalimat utama", "kalimat penjelas", "judul buku", "tanda baca", explain="Kalimat utama berisi gagasan pokok."),
    mc("kata_kalimat", 3, "Kata baku yang benar adalah …", "apotek", "apotik", "aktip", "nasehat", explain="Kata bakunya apotek, aktif, dan nasihat."),
    match("sinonim_antonim", 3, "Pasangkan kata yang artinya sama (sinonim)", [("senang", "gembira"), ("pandai", "cerdas"), ("cepat", "lekas"), ("sedih", "duka")],
          explain="Sinonim adalah kata yang maknanya sama atau mirip."),
    tf("tanda_baca", 3, "Tanda koma (,) dipakai di antara unsur dalam pemerincian, seperti: apel, jeruk, dan mangga.", True,
       "Benar. Koma memisahkan benda-benda yang disebutkan satu per satu."),
    fill("kata_kalimat", 3, "Kata dasar \"tulis\" mendapat awalan me- menjadi ___", "menulis", "metulis", "mentulis", "menyulis", explain="Me- + tulis = menulis."),
    words("kata_kalimat", 3, "Susun kata menjadi kalimat:", ["Kami", "membersihkan", "kelas", "bersama-sama"], "Kalimat yang benar: Kami membersihkan kelas bersama-sama."),
    mc("cerita", 3, "Tokoh yang berwatak baik dalam cerita disebut tokoh …", "protagonis", "antagonis", "figuran", "penonton", explain="Tokoh jahat disebut antagonis."),
    mc("kata_kalimat", 3, "Surat untuk teman atau keluarga disebut surat …", "pribadi", "dinas", "resmi", "niaga", explain="Surat pribadi bahasanya akrab dan tidak resmi."),
    mc("bacaan", 4, "Gagasan utama sebuah paragraf disebut …", "ide pokok", "kalimat penjelas", "judul", "amanat", explain="Ide pokok = gagasan utama."),
    mc("bacaan", 4, "Bacalah: \"Pada musim hujan, Pak Tani menanam padi. Tiga bulan kemudian padi siap dipanen.\" Kapan padi siap dipanen?",
       "tiga bulan kemudian", "satu minggu kemudian", "satu tahun kemudian", "pada musim kemarau", explain="Bacaan menyebut: tiga bulan kemudian padi siap dipanen."),
    mc("pantun", 4, "Sampiran pantun terletak pada baris …", "1 dan 2", "3 dan 4", "1 dan 3", "2 dan 4", explain="Baris 1–2 sampiran, baris 3–4 isi."),
    mc("pantun", 4, "Pantun bersajak …", "a-b-a-b", "a-a-a-a", "a-a-b-b", "a-b-b-a", explain="Bunyi akhir baris 1 sama dengan baris 3, baris 2 sama dengan baris 4."),
    tf("bacaan", 4, "Kalimat \"Matahari terbit di sebelah timur\" adalah fakta.", True, "Benar. Itu kenyataan yang bisa dibuktikan."),
    mc("bacaan", 4, "Kalimat yang berisi pendapat seseorang disebut kalimat …", "opini", "fakta", "perintah", "seru", explain="Opini = pendapat; fakta = kenyataan."),
    words("kata_kalimat", 4, "Susun kata menjadi kalimat:", ["Rina", "membantu", "ibu", "memasak", "di", "dapur"], "Kalimat yang benar: Rina membantu ibu memasak di dapur."),
    match("kata_kalimat", 4, "Pasangkan kata tidak baku dengan kata bakunya", [("apotik", "apotek"), ("nasehat", "nasihat"), ("resiko", "risiko"), ("jadual", "jadwal")],
          explain="Kata baku sesuai Kamus Besar Bahasa Indonesia."),
    mc("cerita", 4, "Bagian awal cerita yang memperkenalkan tokoh dan latar disebut …", "orientasi", "klimaks", "resolusi", "amanat", explain="Orientasi = pengenalan."),
    mc("bacaan", 5, "\"Daun melambai-lambai ditiup angin\" mengandung majas …", "personifikasi", "hiperbola", "litotes", "perumpamaan",
       explain="Daun digambarkan bisa melambai seperti manusia."),
    mc("bacaan", 5, "Majas yang membandingkan memakai kata \"seperti\" atau \"bagai\" disebut …", "perumpamaan", "personifikasi", "hiperbola", "ironi",
       explain="Contoh: Wajahnya bagai bulan purnama."),
    mc("bacaan", 5, "Teks yang berisi langkah-langkah membuat sesuatu disebut teks …", "prosedur", "narasi", "deskripsi", "puisi", explain="Contoh: cara membuat layang-layang."),
    mc("bacaan", 5, "Bacalah: \"Hutan bakau melindungi pantai dari abrasi. Akar bakau menahan tanah agar tidak terbawa ombak.\" Apa manfaat akar bakau?",
       "menahan tanah agar tidak terbawa ombak", "membuat air laut asin", "menjadi makanan ikan paus", "menambah tinggi ombak",
       explain="Bacaan menyebut akar bakau menahan tanah."),
    tf("cerita", 5, "Wawancara adalah kegiatan tanya jawab untuk mendapatkan informasi.", True, "Benar. Ada pewawancara dan narasumber."),
    mc("kata_kalimat", 5, "Penulisan kata serapan yang benar adalah …", "kualitas", "kwalitas", "kwalitet", "qualitas", explain="Kata bakunya kualitas."),
    match("tanda_baca", 5, "Pasangkan tanda baca dengan kegunaannya", [("?", "akhir kalimat tanya"), ("!", "akhir kalimat perintah"), (".", "akhir kalimat berita"), (",", "memisahkan rincian")],
          explain="Setiap tanda baca punya tugas masing-masing."),
    mc("cerita", 5, "Bagian cerita saat masalah memuncak disebut …", "klimaks", "orientasi", "resolusi", "judul", explain="Setelah klimaks biasanya ada penyelesaian (resolusi)."),
    fill("kata_kalimat", 5, "Kata \"mengatasi\" berasal dari kata dasar ___", "atas", "atasi", "mengatas", "tas", explain="Meng- + atas + -i = mengatasi."),
    mc("bacaan", 6, "Teks yang melaporkan hasil pengamatan disebut teks …", "laporan", "puisi", "drama", "pantun", explain="Contoh: laporan pengamatan tumbuhan."),
    mc("cerita", 6, "Pidato yang baik dibuka dengan …", "salam pembuka dan sapaan", "kesimpulan", "ucapan selamat tinggal", "daftar pustaka",
       explain="Pembukaan pidato berisi salam dan sapaan kepada hadirin."),
    mc("bacaan", 6, "Bacalah: \"Ki Hajar Dewantara mendirikan Taman Siswa pada tahun 1922 untuk memberi pendidikan bagi rakyat.\" Apa tujuan Taman Siswa?",
       "memberi pendidikan bagi rakyat", "membangun jalan raya", "berdagang rempah", "membuat kapal", explain="Bacaan menyebut tujuannya memberi pendidikan bagi rakyat."),
    tf("bacaan", 6, "Teks eksplanasi menjelaskan proses terjadinya suatu peristiwa, misalnya terjadinya hujan.", True, "Benar."),
    mc("kata_kalimat", 6, "Kalimat efektif yang benar adalah …", "Para siswa berbaris di lapangan.", "Para siswa-siswa berbaris di lapangan.",
       "Para siswa-siswi pada berbaris di lapangan.", "Siswa-siswa para berbaris di lapangan.", explain="\"Para\" sudah berarti banyak, jadi kata tidak perlu diulang."),
    match("cerita", 6, "Pasangkan unsur cerita dengan artinya", [("tokoh", "pelaku dalam cerita"), ("latar", "tempat dan waktu"), ("alur", "rangkaian peristiwa"), ("amanat", "pesan cerita")],
          explain="Tokoh, latar, alur, dan amanat adalah unsur intrinsik cerita."),
    mc("sinonim_antonim", 6, "Antonim kata \"optimis\" adalah …", "pesimis", "semangat", "yakin", "gembira", explain="Optimis = yakin berhasil; pesimis = ragu."),
    fill("pantun", 6, "Satu bait pantun terdiri dari ___ baris.", "4", "2", "3", "6", explain="Pantun: 4 baris dalam satu bait."),
    words("kata_kalimat", 6, "Susun kata menjadi kalimat:", ["Kita", "harus", "menjaga", "kebersihan", "lingkungan"], "Kalimat yang benar: Kita harus menjaga kebersihan lingkungan."),

    # ===================== LABORATORIUM IPA
    match("pancaindra", 1, "Pasangkan alat indra dengan tugasnya", [("mata", "melihat"), ("telinga", "mendengar"), ("hidung", "mencium"), ("lidah", "mengecap rasa")],
          explain="Pancaindra membantu kita mengenal lingkungan."),
    mc("pancaindra", 1, "Alat indra untuk merasakan panas dan dingin adalah …", "kulit", "mata", "telinga", "hidung", explain="Kulit adalah indra peraba."),
    tf("hewan", 1, "Ikan bernapas dengan insang.", True, "Benar. Insang mengambil oksigen dari air."),
    mc("tumbuhan", 1, "Bagian tumbuhan yang menyerap air dari tanah adalah …", "akar", "daun", "bunga", "buah", explain="Akar menyerap air dan menguatkan tumbuhan."),
    classify("hewan", 1, "Kelompokkan hewan: hidup di air atau di darat?", ["Air", "Darat"],
             [("ikan", 0), ("paus", 0), ("gurita", 0), ("kucing", 1), ("sapi", 1), ("ayam", 1)], explain="Ikan, paus, dan gurita hidup di air."),
    mc("hewan", 1, "Hewan yang berkembang biak dengan bertelur adalah …", "ayam", "kambing", "kucing", "sapi", explain="Ayam bertelur; kambing, kucing, dan sapi melahirkan."),
    mc("tubuh", 1, "Cara merawat gigi yang benar adalah …", "menggosok gigi dua kali sehari", "makan permen sebelum tidur", "tidak pernah menggosok gigi", "menggigit benda keras",
       explain="Gosok gigi pagi dan sebelum tidur."),
    tf("tumbuhan", 1, "Tumbuhan membutuhkan air dan cahaya matahari.", True, "Benar. Tanpa air dan cahaya, tumbuhan layu."),
    mc("tubuh", 1, "Tubuh kita bisa bergerak berkat …", "tulang dan otot", "rambut", "kuku", "pakaian", explain="Tulang dan otot bekerja sama untuk bergerak."),
    classify("wujud_benda", 2, "Kelompokkan benda: padat atau cair?", ["Padat", "Cair"],
             [("batu", 0), ("kayu", 0), ("buku", 0), ("air", 1), ("susu", 1), ("minyak goreng", 1)], explain="Benda cair bentuknya mengikuti wadah."),
    mc("wujud_benda", 2, "Es batu yang dibiarkan di luar kulkas akan …", "mencair", "membeku", "mengeras", "menjadi batu", explain="Panas membuat es mencair."),
    mc("hewan", 2, "Hewan yang hidup di dua alam (air dan darat) adalah …", "katak", "ikan", "sapi", "burung", explain="Katak disebut hewan amfibi."),
    tf("lingkungan", 2, "Membuang sampah ke sungai menjaga kebersihan lingkungan.", False, "Salah. Sampah di sungai bisa menyebabkan banjir dan mencemari air."),
    mc("tumbuhan", 2, "Bagian tumbuhan tempat membuat makanan adalah …", "daun", "akar", "batang", "bunga", explain="Daun hijau membuat makanan dengan bantuan cahaya matahari."),
    mc("hewan", 2, "Ciri makhluk hidup adalah …", "bernapas, tumbuh, dan berkembang biak", "tidak pernah berubah", "terbuat dari plastik", "tidak butuh makan",
       explain="Manusia, hewan, dan tumbuhan bernapas, tumbuh, dan berkembang biak."),
    match("hewan", 2, "Pasangkan hewan dengan makanan kesukaannya", [("kelinci", "wortel"), ("sapi", "rumput"), ("monyet", "pisang"), ("kucing", "ikan")],
          explain="Setiap hewan punya makanan yang berbeda."),
    mc("lingkungan", 2, "Langit gelap tertutup awan tebal biasanya tanda akan …", "hujan", "kemarau panjang", "gempa", "salju", explain="Awan tebal yang gelap membawa banyak titik air."),
    tf("hewan", 2, "Kupu-kupu berasal dari ulat.", True, "Benar. Ulat menjadi kepompong lalu menjadi kupu-kupu."),
    mc("wujud_benda", 3, "Perubahan wujud dari cair menjadi gas disebut …", "menguap", "membeku", "mencair", "mengembun", explain="Contoh: air mendidih menjadi uap."),
    mc("wujud_benda", 3, "Perubahan wujud dari cair menjadi padat disebut …", "membeku", "menguap", "mencair", "menyublim", explain="Contoh: air dimasukkan ke freezer menjadi es."),
    classify("hewan", 3, "Kelompokkan: herbivora (pemakan tumbuhan) atau karnivora (pemakan daging)?", ["Herbivora", "Karnivora"],
             [("sapi", 0), ("kambing", 0), ("kelinci", 0), ("harimau", 1), ("singa", 1), ("elang", 1)], explain="Herbivora makan tumbuhan, karnivora makan daging."),
    mc("energi", 3, "Sumber energi panas terbesar bagi Bumi adalah …", "Matahari", "Bulan", "api unggun", "lampu", explain="Matahari memberi cahaya dan panas."),
    tf("energi", 3, "Menggosokkan kedua telapak tangan menghasilkan panas.", True, "Benar. Gesekan menghasilkan panas."),
    mc("hewan", 3, "Urutan metamorfosis sempurna kupu-kupu adalah …", "telur – ulat – kepompong – kupu-kupu", "telur – kepompong – ulat – kupu-kupu",
       "ulat – telur – kepompong – kupu-kupu", "kepompong – telur – ulat – kupu-kupu", explain="Telur menetas menjadi ulat, lalu kepompong, lalu kupu-kupu."),
    mc("energi", 3, "Benda yang dapat ditarik magnet adalah …", "paku besi", "karet penghapus", "kertas", "kayu", explain="Magnet menarik benda dari besi dan baja."),
    mc("energi", 3, "Kincir angin berputar karena energi …", "angin", "listrik", "makanan", "bunyi", explain="Angin yang bergerak memutar baling-baling kincir."),
    match("wujud_benda", 3, "Pasangkan benda dengan wujudnya", [("es batu", "padat"), ("air sirup", "cair"), ("uap air", "gas")], explain="Benda bisa padat, cair, atau gas."),
    mc("energi", 3, "Bunyi paling cepat merambat melalui …", "benda padat", "benda cair", "udara", "ruang hampa", explain="Bunyi merambat paling cepat di benda padat dan tidak bisa merambat di ruang hampa."),
    mc("tumbuhan", 4, "Proses tumbuhan membuat makanan sendiri disebut …", "fotosintesis", "respirasi", "evaporasi", "metamorfosis", explain="Fotosintesis terjadi di daun dengan bantuan cahaya matahari."),
    mc("tubuh", 4, "Rangka tubuh berfungsi untuk …", "menegakkan tubuh dan melindungi organ", "mencerna makanan", "melihat benda", "mengatur suhu ruangan",
       explain="Contoh: tengkorak melindungi otak."),
    mc("energi", 4, "Gaya yang membuat benda jatuh ke bawah adalah gaya …", "gravitasi", "magnet", "gesek", "pegas", explain="Gravitasi Bumi menarik benda ke bawah."),
    classify("energi", 4, "Kelompokkan sumber energi: dapat diperbarui atau tidak?", ["Dapat diperbarui", "Tidak dapat diperbarui"],
             [("matahari", 0), ("angin", 0), ("air", 0), ("minyak bumi", 1), ("batu bara", 1), ("gas alam", 1)], explain="Minyak bumi, batu bara, dan gas alam bisa habis."),
    tf("energi", 4, "Bunyi dapat merambat di ruang hampa udara.", False, "Salah. Bunyi butuh perantara seperti udara, air, atau benda padat."),
    mc("tumbuhan", 4, "Bagian bunga yang menjadi alat kelamin jantan adalah …", "benang sari", "putik", "kelopak", "tangkai", explain="Putik adalah alat kelamin betina."),
    mc("tumbuhan", 4, "Daur hidup katak: telur → … → katak muda → katak dewasa", "berudu", "ulat", "kepompong", "nimfa", explain="Telur katak menetas menjadi berudu."),
    match("tubuh", 4, "Pasangkan organ dengan tugasnya", [("jantung", "memompa darah"), ("paru-paru", "bernapas"), ("lambung", "mencerna makanan"), ("ginjal", "menyaring darah")],
          explain="Setiap organ punya tugas penting."),
    mc("lingkungan", 4, "Cara mengurangi sampah plastik adalah …", "membawa tas belanja sendiri", "membakar sampah di jalan", "membuang plastik ke laut", "memakai kantong plastik baru setiap hari",
       explain="Tas belanja yang dipakai berulang mengurangi sampah plastik."),
    mc("tubuh", 5, "Organ pernapasan utama manusia adalah …", "paru-paru", "jantung", "lambung", "ginjal", explain="Paru-paru menukar oksigen dan karbon dioksida."),
    mc("tubuh", 5, "Darah dipompa ke seluruh tubuh oleh …", "jantung", "paru-paru", "hati", "usus", explain="Jantung berdetak memompa darah."),
    mc("tubuh", 5, "Penyerapan sari makanan terutama terjadi di …", "usus halus", "lambung", "kerongkongan", "mulut", explain="Usus halus menyerap sari makanan ke dalam darah."),
    classify("ekosistem", 5, "Kelompokkan: produsen atau konsumen?", ["Produsen", "Konsumen"],
             [("rumput", 0), ("padi", 0), ("pohon mangga", 0), ("ulat", 1), ("burung", 1), ("ular", 1)], explain="Produsen (tumbuhan hijau) membuat makanannya sendiri."),
    mc("ekosistem", 5, "Urutan rantai makanan yang benar adalah …", "rumput → belalang → katak → ular", "ular → katak → belalang → rumput",
       "belalang → rumput → ular → katak", "katak → rumput → ular → belalang", explain="Rantai makanan dimulai dari tumbuhan (produsen)."),
    tf("energi", 5, "Air yang dipanaskan sampai mendidih berubah menjadi uap.", True, "Benar. Panas mengubah air menjadi gas (uap)."),
    mc("hewan", 5, "Bunglon mengubah warna kulitnya untuk …", "menyamar dari musuh", "bernapas di air", "mencari makan di laut", "bertelur",
       explain="Cara menyamar dengan mengubah warna kulit disebut mimikri."),
    mc("energi", 5, "Rangkaian listrik yang lampunya tetap menyala walau satu lampu putus adalah rangkaian …", "paralel", "seri", "terbuka", "pendek",
       explain="Pada rangkaian paralel, setiap lampu punya jalur sendiri."),
    match("hewan", 5, "Pasangkan hewan dengan alat pernapasannya", [("ikan", "insang"), ("cacing", "kulit"), ("belalang", "trakea"), ("kucing", "paru-paru")],
          explain="Hewan bernapas dengan alat yang berbeda-beda."),
    mc("ekosistem", 5, "Air laut menguap, menjadi awan, lalu turun kembali sebagai …", "hujan", "pasir", "angin", "pelangi", explain="Itulah daur (siklus) air."),
    mc("tata_surya", 6, "Planet yang paling dekat dengan Matahari adalah …", "Merkurius", "Venus", "Bumi", "Mars", explain="Urutannya: Merkurius, Venus, Bumi, Mars, ..."),
    mc("tata_surya", 6, "Planet terbesar di tata surya adalah …", "Yupiter", "Bumi", "Mars", "Merkurius", explain="Yupiter jauh lebih besar dari Bumi."),
    mc("tata_surya", 6, "Perputaran Bumi pada porosnya disebut …", "rotasi", "revolusi", "gravitasi", "evaporasi", explain="Rotasi Bumi menyebabkan siang dan malam."),
    mc("tata_surya", 6, "Bumi mengelilingi Matahari (revolusi) dalam waktu sekitar …", "1 tahun", "1 hari", "1 minggu", "1 bulan", explain="Satu kali revolusi Bumi ± 365 hari."),
    tf("tata_surya", 6, "Bulan memancarkan cahayanya sendiri.", False, "Salah. Bulan memantulkan cahaya Matahari."),
    mc("tata_surya", 6, "Gerhana matahari terjadi ketika … berada di antara Matahari dan Bumi.", "Bulan", "Mars", "Venus", "komet", explain="Bulan menutupi cahaya Matahari."),
    classify("hewan", 6, "Kelompokkan: melahirkan (vivipar) atau bertelur (ovipar)?", ["Melahirkan", "Bertelur"],
             [("kucing", 0), ("sapi", 0), ("paus", 0), ("ayam", 1), ("penyu", 1), ("buaya", 1)], explain="Paus adalah mamalia, jadi melahirkan."),
    match("tata_surya", 6, "Pasangkan planet dengan cirinya", [("Saturnus", "cincinnya terlihat jelas"), ("Mars", "dijuluki planet merah"),
                                                                    ("Bumi", "planet tempat kita tinggal"), ("Merkurius", "paling dekat dengan Matahari")],
          explain="Setiap planet punya ciri khas."),
    mc("ekosistem", 6, "Kelelawar dapat terbang di malam gelap karena memakai …", "pantulan bunyi (ekolokasi)", "cahaya lampu", "penciuman saja", "insang",
       explain="Kelelawar mengeluarkan bunyi dan mendengar pantulannya."),
    mc("energi", 6, "Cara menghemat listrik di rumah adalah …", "mematikan lampu saat tidak dipakai", "menyalakan TV tanpa ditonton", "membuka kulkas lama-lama", "menyalakan semua lampu siang hari",
       explain="Peralatan yang tidak dipakai sebaiknya dimatikan."),

    # ===================== NEGERI PENJELAJAH IPS
    mc("keluarga", 1, "Keluarga inti terdiri dari …", "ayah, ibu, dan anak", "kakek dan nenek", "paman dan bibi", "tetangga", explain="Keluarga inti disebut juga keluarga kecil."),
    match("keluarga", 1, "Pasangkan sebutan anggota keluarga", [("ayah dari ayah", "kakek"), ("ibu dari ibu", "nenek"), ("adik laki-laki ayah", "paman"), ("adik perempuan ibu", "bibi")],
          explain="Kakek, nenek, paman, dan bibi termasuk keluarga besar."),
    tf("keluarga", 1, "Kita harus menghormati orang tua.", True, "Benar. Contohnya berbicara dengan sopan."),
    mc("masyarakat", 1, "Sampah sebaiknya dibuang …", "di tempat sampah", "di sungai", "di jalan", "di halaman tetangga", explain="Membuang sampah di tempatnya menjaga lingkungan bersih."),
    mc("masyarakat", 1, "Tempat penjual dan pembeli bertemu disebut …", "pasar", "sekolah", "rumah sakit", "kantor polisi", explain="Di pasar terjadi jual beli."),
    mc("masyarakat", 1, "Sikap yang baik kepada tetangga adalah …", "saling menolong", "bertengkar", "mengejek", "berteriak", explain="Hidup rukun dengan saling menolong."),
    mc("keluarga", 1, "Setelah bangun tidur sebaiknya kita …", "merapikan tempat tidur", "langsung bermain", "tidur lagi", "membiarkan kamar berantakan", explain="Merapikan tempat tidur melatih tanggung jawab."),
    words("keluarga", 1, "Susun kata menjadi kalimat:", ["Saya", "sayang", "ayah", "dan", "ibu"], "Kalimat yang benar: Saya sayang ayah dan ibu."),
    mc("masyarakat", 1, "Lambang negara Indonesia adalah …", "Garuda Pancasila", "bendera Merah Putih", "Monas", "Candi Borobudur", explain="Merah Putih adalah bendera, bukan lambang negara."),
    mc("masyarakat", 1, "Hari Kemerdekaan Indonesia diperingati setiap tanggal …", "17 Agustus", "1 Juni", "2 Mei", "28 Oktober", explain="Indonesia merdeka pada 17 Agustus 1945."),
    match("pekerjaan", 2, "Pasangkan pekerjaan dengan tempat kerjanya", [("dokter", "rumah sakit"), ("guru", "sekolah"), ("petani", "sawah"), ("nelayan", "laut")],
          explain="Setiap pekerjaan punya tempat kerja."),
    mc("pekerjaan", 2, "Orang yang menangkap ikan di laut disebut …", "nelayan", "petani", "pedagang", "pilot", explain="Nelayan memakai perahu dan jala."),
    mc("pekerjaan", 2, "Pekerjaan yang memberikan jasa adalah …", "guru", "petani padi", "peternak ayam", "pembuat tempe", explain="Guru memberi jasa mengajar, bukan membuat barang."),
    tf("masyarakat", 2, "Rambu lalu lintas membantu menjaga keselamatan di jalan.", True, "Benar. Patuhi rambu agar selamat."),
    mc("masyarakat", 2, "Lampu lalu lintas berwarna merah artinya …", "berhenti", "jalan terus", "boleh ngebut", "parkir", explain="Merah berhenti, kuning hati-hati, hijau jalan."),
    mc("masyarakat", 2, "Kerja bakti membersihkan lingkungan bersama-sama disebut …", "gotong royong", "lomba lari", "jual beli", "upacara", explain="Gotong royong = bekerja bersama."),
    classify("lingkungan_alam", 2, "Kelompokkan: kenampakan alam atau buatan manusia?", ["Alam", "Buatan"],
             [("gunung", 0), ("sungai", 0), ("danau", 0), ("waduk", 1), ("sawah", 1), ("jalan raya", 1)], explain="Waduk, sawah, dan jalan dibuat oleh manusia."),
    mc("masyarakat", 2, "Bendera Indonesia berwarna …", "merah dan putih", "merah dan kuning", "biru dan putih", "hijau dan putih", explain="Bendera Merah Putih disebut Sang Saka Merah Putih."),
    tf("masyarakat", 2, "Bermain di jalan raya itu aman.", False, "Salah. Jalan raya ramai kendaraan; bermainlah di tempat yang aman."),
    mc("peta", 3, "Gambar permukaan bumi pada bidang datar disebut …", "peta", "globe", "foto", "lukisan", explain="Globe adalah tiruan bumi yang berbentuk bulat."),
    mc("peta", 3, "Arah yang berlawanan dengan utara adalah …", "selatan", "timur", "barat", "tenggara", explain="Utara berlawanan dengan selatan."),
    match("peta", 3, "Pasangkan arah mata angin dengan lawannya", [("timur", "barat"), ("utara", "selatan"), ("timur laut", "barat daya"), ("tenggara", "barat laut")],
          explain="Arah yang berlawanan letaknya berseberangan pada mata angin."),
    mc("peta", 3, "Tanda pada peta yang menunjukkan arah disebut …", "mata angin", "legenda", "judul", "skala", explain="Mata angin menunjukkan utara, selatan, timur, dan barat."),
    mc("ekonomi", 3, "Kegiatan menghasilkan barang atau jasa disebut …", "produksi", "konsumsi", "distribusi", "promosi", explain="Contoh: petani menanam padi."),
    mc("ekonomi", 3, "Kegiatan memakai barang untuk memenuhi kebutuhan disebut …", "konsumsi", "produksi", "distribusi", "ekspor", explain="Contoh: makan nasi."),
    classify("ekonomi", 3, "Kelompokkan: kebutuhan pokok (primer) atau tambahan (sekunder)?", ["Pokok", "Tambahan"],
             [("makanan", 0), ("pakaian", 0), ("rumah", 0), ("sepeda", 1), ("televisi", 1), ("kulkas", 1)], explain="Makanan, pakaian, dan rumah adalah kebutuhan pokok."),
    tf("budaya", 3, "Semboyan negara Indonesia adalah Bhinneka Tunggal Ika.", True, "Benar. Artinya: berbeda-beda tetapi tetap satu."),
    mc("budaya", 3, "Alat musik angklung berasal dari …", "Jawa Barat", "Papua", "Bali", "Aceh", explain="Angklung terbuat dari bambu dan berasal dari Jawa Barat."),
    mc("ekonomi", 3, "Tambahan uang yang diberikan bank atas tabungan disebut …", "bunga", "pajak", "denda", "diskon", explain="Menabung di bank mendapat bunga."),
    mc("geografi", 4, "Indonesia terletak di antara dua benua, yaitu …", "Asia dan Australia", "Asia dan Eropa", "Afrika dan Asia", "Amerika dan Australia", explain="Ini disebut letak geografis Indonesia."),
    mc("geografi", 4, "Indonesia terletak di antara dua samudra, yaitu …", "Hindia dan Pasifik", "Atlantik dan Pasifik", "Hindia dan Atlantik", "Arktik dan Pasifik", explain="Samudra Hindia di barat daya, Samudra Pasifik di timur laut."),
    match("budaya", 4, "Pasangkan rumah adat dengan daerahnya", [("Rumah Gadang", "Sumatera Barat"), ("Joglo", "Jawa Tengah"), ("Honai", "Papua"), ("Tongkonan", "Sulawesi Selatan")],
          explain="Setiap daerah di Indonesia punya rumah adat."),
    mc("budaya", 4, "Tari Kecak berasal dari …", "Bali", "Aceh", "Papua", "Kalimantan", explain="Tari Kecak terkenal dengan seruan \"cak-cak-cak\"."),
    tf("geografi", 4, "Indonesia adalah negara kepulauan.", True, "Benar. Indonesia terdiri dari ribuan pulau."),
    mc("lingkungan_alam", 4, "Sumber daya alam yang dapat diperbarui adalah …", "hutan", "minyak bumi", "batu bara", "emas", explain="Hutan dapat ditanami kembali."),
    mc("ekonomi", 4, "Koperasi adalah badan usaha yang berasaskan …", "kekeluargaan", "persaingan", "keuntungan pribadi", "paksaan", explain="Anggota koperasi bekerja sama."),
    mc("geografi", 4, "Ibu kota Provinsi Jawa Barat adalah …", "Bandung", "Semarang", "Surabaya", "Serang", explain="Semarang ibu kota Jawa Tengah, Surabaya Jawa Timur."),
    classify("lingkungan_alam", 4, "Kelompokkan sumber daya alam: dapat diperbarui atau tidak?", ["Dapat diperbarui", "Tidak dapat diperbarui"],
             [("air", 0), ("tumbuhan", 0), ("hewan", 0), ("minyak bumi", 1), ("batu bara", 1), ("emas", 1)], explain="Barang tambang tidak dapat diperbarui."),
    mc("ekonomi", 4, "Kegiatan menyalurkan barang dari produsen ke konsumen disebut …", "distribusi", "produksi", "konsumsi", "investasi", explain="Contoh: truk mengantar sayur ke pasar."),
    mc("sejarah", 5, "Kerajaan Hindu tertua di Indonesia adalah …", "Kutai", "Majapahit", "Singasari", "Demak", explain="Kutai berada di Kalimantan Timur."),
    mc("sejarah", 5, "Candi Borobudur adalah peninggalan agama …", "Buddha", "Hindu", "Islam", "Kristen", explain="Borobudur di Magelang adalah candi Buddha."),
    mc("sejarah", 5, "Bangsa Eropa yang pertama kali tiba di Kepulauan Maluku (1512) adalah …", "Portugis", "Belanda", "Inggris", "Prancis", explain="Mereka mencari rempah-rempah."),
    mc("sejarah", 5, "Persekutuan dagang Belanda di Nusantara bernama …", "VOC", "PBB", "ASEAN", "KNIL", explain="VOC berdiri tahun 1602."),
    mc("sejarah", 5, "Sumpah Pemuda diikrarkan pada tanggal …", "28 Oktober 1928", "17 Agustus 1945", "20 Mei 1908", "1 Juni 1945", explain="Para pemuda bersumpah: satu nusa, satu bangsa, satu bahasa."),
    tf("sejarah", 5, "Budi Utomo berdiri pada tanggal 20 Mei 1908.", True, "Benar. Hari itu diperingati sebagai Hari Kebangkitan Nasional."),
    words("sejarah", 5, "Urutkan peristiwa dari yang paling dulu:", ["Berdirinya Budi Utomo", "Sumpah Pemuda", "Proklamasi Kemerdekaan"],
          "Budi Utomo (1908), Sumpah Pemuda (1928), Proklamasi (1945)."),
    mc("sejarah", 5, "Tokoh yang mendirikan Taman Siswa adalah …", "Ki Hajar Dewantara", "R.A. Kartini", "Pattimura", "Cut Nyak Dhien", explain="Ki Hajar Dewantara adalah Bapak Pendidikan Nasional."),
    match("sejarah", 5, "Pasangkan pahlawan dengan perjuangannya", [("R.A. Kartini", "pendidikan perempuan"), ("Pangeran Diponegoro", "Perang Jawa"),
                                                                       ("Cut Nyak Dhien", "perlawanan di Aceh"), ("Pattimura", "perlawanan di Maluku")],
          explain="Mereka adalah pahlawan nasional Indonesia."),
    mc("masyarakat", 5, "Interaksi sosial terjadi bila ada …", "kontak sosial dan komunikasi", "uang dan pasar", "rumah dan jalan", "pohon dan sungai", explain="Interaksi = hubungan saling memengaruhi antarmanusia."),
    mc("sejarah", 6, "Teks Proklamasi Kemerdekaan dibacakan oleh …", "Soekarno, didampingi Mohammad Hatta", "Soeharto", "Ki Hajar Dewantara", "Jenderal Sudirman",
       explain="Pembacaan dilakukan di Jalan Pegangsaan Timur 56, Jakarta."),
    mc("sejarah", 6, "Proklamasi Kemerdekaan dibacakan pada tanggal …", "17 Agustus 1945", "28 Oktober 1928", "20 Mei 1908", "1 Juni 1945", explain="Hari Kemerdekaan Indonesia."),
    mc("geografi", 6, "Organisasi negara-negara Asia Tenggara disebut …", "ASEAN", "PBB", "NATO", "OPEC", explain="ASEAN = Perhimpunan Bangsa-Bangsa Asia Tenggara."),
    mc("geografi", 6, "ASEAN didirikan pada tahun …", "1967", "1945", "1955", "1998", explain="ASEAN berdiri 8 Agustus 1967 di Bangkok."),
    tf("geografi", 6, "Indonesia termasuk salah satu negara pendiri ASEAN.", True, "Benar. Pendirinya Indonesia, Malaysia, Filipina, Singapura, dan Thailand."),
    mc("ekonomi", 6, "Ekspor adalah …", "menjual barang ke luar negeri", "membeli barang dari luar negeri", "menabung di bank", "membayar pajak", explain="Membeli dari luar negeri disebut impor."),
    classify("ekonomi", 6, "Kelompokkan dampak globalisasi: positif atau negatif?", ["Positif", "Negatif"],
             [("komunikasi makin mudah", 0), ("ilmu pengetahuan mudah didapat", 0), ("perdagangan antarnegara lancar", 0),
              ("meniru budaya asing tanpa memilah", 1), ("gaya hidup boros", 1), ("melupakan budaya sendiri", 1)],
             explain="Ambil dampak positifnya dan hindari dampak negatifnya."),
    words("sejarah", 6, "Urutkan peristiwa tahun 1945 dari yang paling dulu:", ["Peristiwa Rengasdengklok", "Pembacaan Proklamasi", "Pengesahan UUD 1945"],
          "16 Agustus Rengasdengklok, 17 Agustus Proklamasi, 18 Agustus UUD 1945 disahkan."),
    mc("geografi", 6, "Konferensi Asia Afrika tahun 1955 diselenggarakan di kota …", "Bandung", "Jakarta", "Bogor", "Yogyakarta", explain="Konferensi itu diadakan di Gedung Merdeka, Bandung."),
]

# Mini-game: data dipakai langsung oleh mini-game (lihat client/games/education_sd/scripts/mg_*.gd).
MINIGAMES = {
    "huruf_hilang": {  # Bahasa: cari huruf yang hilang (kata umum, ejaan baku)
        "1": ["BUKU", "BOLA", "MEJA", "SAPI", "IKAN", "TOPI", "KAKI", "RODA", "SUSU", "BATU"],
        "2": ["RUMAH", "KUCING", "SEPATU", "PENSIL", "JERUK", "BUNGA", "KURSI", "PINTU", "MOBIL", "KERETA"],
        "3": ["SEKOLAH", "JENDELA", "PELANGI", "SEMANGKA", "KELINCI", "PERAHU", "LEMARI", "TELINGA", "BINTANG", "MATAHARI"],
        "4": ["PERPUSTAKAAN", "PEMANDANGAN", "KEBERSIHAN", "PETERNAKAN", "PERSAHABATAN", "KESEHATAN", "PENGALAMAN", "KEJUJURAN"],
        "5": ["KEMERDEKAAN", "LINGKUNGAN", "PERTANIAN", "KEBUDAYAAN", "PENGETAHUAN", "PERDAGANGAN", "KEMANUSIAAN", "PERJUANGAN"],
        "6": ["KEBERAGAMAN", "PERSATUAN", "MUSYAWARAH", "TANGGUNG JAWAB", "KEBANGSAAN", "PEMERINTAHAN", "TEKNOLOGI", "KEMANDIRIAN"],
    },
    "hewan": {  # IPA: kelompokkan hewan menurut makanannya
        "herbivora": ["sapi", "kambing", "kelinci", "kuda", "rusa", "jerapah", "kerbau", "zebra"],
        "karnivora": ["harimau", "singa", "elang", "buaya", "serigala", "hiu"],
        "omnivora": ["ayam", "beruang", "tikus", "monyet"],
    },
    "pasangan_ips": {  # IPS: pekerjaan dan alatnya; kelas 4+ ditambah rumah adat dan daerahnya
        "pekerjaan": [["petani", "cangkul"], ["nelayan", "jala"], ["dokter", "stetoskop"], ["tukang kayu", "gergaji"],
                      ["penjahit", "mesin jahit"], ["pelukis", "kuas"], ["koki", "wajan"], ["fotografer", "kamera"]],
        "rumah_adat": [["Rumah Gadang", "Sumatera Barat"], ["Joglo", "Jawa Tengah"], ["Honai", "Papua"], ["Tongkonan", "Sulawesi Selatan"],
                       ["Rumah Lamin", "Kalimantan Timur"], ["Rumah Krong Bade", "Aceh"]],
    },
}

ANIMAL_FACTS = {
    "sapi": "Sapi memamah biak: makanannya dikunyah ulang.", "kambing": "Kambing pandai memanjat bukit berbatu.",
    "kelinci": "Gigi depan kelinci terus tumbuh seumur hidupnya.", "kuda": "Kuda bisa tidur sambil berdiri.",
    "rusa": "Rusa jantan punya tanduk bercabang.", "jerapah": "Jerapah adalah hewan darat tertinggi.",
    "kerbau": "Kerbau suka berkubang di lumpur agar tubuhnya sejuk.", "zebra": "Pola belang setiap zebra berbeda-beda.",
    "harimau": "Harimau sumatera hanya hidup di Pulau Sumatra.", "singa": "Singa hidup berkelompok yang disebut kawanan.",
    "elang": "Elang punya penglihatan yang sangat tajam.", "buaya": "Buaya bertelur dan bisa hidup lebih dari 50 tahun.",
    "serigala": "Serigala berburu bersama kelompoknya.", "hiu": "Hiu adalah ikan; sebagian besar hiu tidak berbahaya bagi manusia.",
    "ayam": "Ayam memakan biji-bijian dan juga serangga.", "beruang": "Beruang madu adalah beruang terkecil di dunia dan hidup di Indonesia.",
    "tikus": "Tikus memakan biji-bijian, sisa makanan, dan serangga.", "monyet": "Monyet memakan buah, daun, dan serangga.",
}

BADGES = [
    {"id": "langkah_pertama", "name": "Langkah Pertama", "desc": "Menjawab soal pertama."},
    {"id": "rajin_10", "name": "Rajin Belajar", "desc": "Menjawab 10 soal dengan benar."},
    {"id": "pintar_50", "name": "Bintang Kelas", "desc": "Menjawab 50 soal dengan benar."},
    {"id": "jagoan_100", "name": "Jagoan Ilmu", "desc": "Menjawab 100 soal dengan benar."},
    {"id": "beruntun_5", "name": "Lima Berturut-turut", "desc": "Menjawab 5 soal benar berturut-turut."},
    {"id": "area_pertama", "name": "Penjelajah Muda", "desc": "Menyelesaikan area petualangan pertama."},
    {"id": "empat_wilayah", "name": "Keliling Pulau", "desc": "Menyelesaikan satu area di keempat wilayah."},
    {"id": "ujian_lulus", "name": "Lulus Ujian", "desc": "Lulus ujian akhir sebuah wilayah."},
    {"id": "mini_game", "name": "Pemain Cerdas", "desc": "Menyelesaikan sebuah mini-game."},
    {"id": "kolektor", "name": "Kolektor Kartu", "desc": "Mengumpulkan 10 kartu pengetahuan."},
    {"id": "tak_menyerah", "name": "Pantang Menyerah", "desc": "Mencoba lagi setelah jawaban belum tepat."},
    {"id": "kuis_100", "name": "Nilai Sempurna", "desc": "Mendapat nilai 100 di Mode Kuis."},
]

SHOP = [  # kostum dibeli dengan koin hasil belajar (tanpa uang sungguhan)
    {"id": "warna_merah", "slot": "outfit", "name": "Baju Merah", "price": 0, "value": "#e05a4f"},
    {"id": "warna_biru", "slot": "outfit", "name": "Baju Biru", "price": 0, "value": "#3f7fd8"},
    {"id": "warna_hijau", "slot": "outfit", "name": "Baju Hijau", "price": 30, "value": "#3fae63"},
    {"id": "warna_ungu", "slot": "outfit", "name": "Baju Ungu", "price": 30, "value": "#8a6bd8"},
    {"id": "warna_emas", "slot": "outfit", "name": "Baju Emas", "price": 120, "value": "#f0b429"},
    {"id": "topi_petualang", "slot": "hat", "name": "Topi Petualang", "price": 40, "value": "petualang"},
    {"id": "topi_mahkota", "slot": "hat", "name": "Mahkota", "price": 150, "value": "mahkota"},
    {"id": "topi_toga", "slot": "hat", "name": "Topi Toga", "price": 100, "value": "toga"},
    {"id": "topi_pita", "slot": "hat", "name": "Pita Rambut", "price": 40, "value": "pita"},
    {"id": "aks_kacamata", "slot": "acc", "name": "Kacamata", "price": 50, "value": "kacamata"},
    {"id": "aks_syal", "slot": "acc", "name": "Syal", "price": 60, "value": "syal"},
    {"id": "aks_ransel", "slot": "acc", "name": "Ransel", "price": 80, "value": "ransel"},
]


def validate():
    errs = []
    topic_ids = {t["id"] for t in TOPICS}
    region_ids = {r["id"] for r in REGIONS}
    for t in TOPICS:
        if t["region"] not in region_ids:
            errs.append(f"topik {t['id']}: wilayah tidak dikenal")
        if not t.get("card", {}).get("fact"):
            errs.append(f"topik {t['id']}: kartu tanpa fakta")
        for g in t["grades"]:
            if not 1 <= g <= 6:
                errs.append(f"topik {t['id']}: kelas {g}")
    seen_ids = set()
    per_tg = {}
    out = []
    for q in Q:
        t, g, ty = q["topic"], q["grade"], q["type"]
        key = (t, g)
        per_tg[key] = per_tg.get(key, 0) + 1
        qid = f"{t}-{g}-{per_tg[key]:02d}"
        tag = f"{qid} ({q.get('q', '')[:40]})"
        if qid in seen_ids:
            errs.append(f"ID kembar {qid}")
        seen_ids.add(qid)
        if t not in topic_ids:
            errs.append(f"{tag}: topik tidak dikenal")
        elif g not in next(x for x in TOPICS if x["id"] == t)["grades"]:
            errs.append(f"{tag}: kelas {g} tidak termasuk kelas topik")
        if ty not in TYPES:
            errs.append(f"{tag}: tipe {ty}")
        if not str(q.get("q", "")).strip():
            errs.append(f"{tag}: pertanyaan kosong")
        if not str(q.get("explain", "")).strip():
            errs.append(f"{tag}: tanpa penjelasan")
        if ty in ("mc", "logic", "fill", "pick_image"):
            opts = q.get("options", [])
            if len(opts) < 2 or any(not str(o).strip() for o in opts):
                errs.append(f"{tag}: pilihan kosong")
            if len(set(opts)) != len(opts):
                errs.append(f"{tag}: pilihan kembar")
            if not 0 <= q.get("answer", -1) < len(opts):
                errs.append(f"{tag}: jawaban di luar indeks")
            if ty == "pick_image" and any(o not in SHAPES for o in opts):
                errs.append(f"{tag}: gambar tidak dikenal")
        elif ty == "tf":
            if not isinstance(q.get("answer"), bool):
                errs.append(f"{tag}: jawaban benar/salah harus boolean")
        elif ty == "match":
            pairs = q.get("pairs", [])
            if len(pairs) < 2 or len({p[0] for p in pairs}) != len(pairs) or len({p[1] for p in pairs}) != len(pairs):
                errs.append(f"{tag}: pasangan kurang/kembar")
        elif ty == "order_letters":
            w = q.get("word", "")
            if len(w) < 3 or len(set(w)) < 2:
                errs.append(f"{tag}: kata terlalu pendek")
        elif ty == "order_words":
            if len(q.get("items", [])) < 3 or len(set(q["items"])) != len(q["items"]):
                errs.append(f"{tag}: susunan kurang/kembar")
        elif ty == "sort_numbers":
            if len(set(q.get("numbers", []))) != len(q.get("numbers", [])) or len(q.get("numbers", [])) < 3:
                errs.append(f"{tag}: angka kurang/kembar")
        elif ty == "count":
            if q.get("shape") not in SHAPES or not 1 <= q.get("count", 0) <= 20:
                errs.append(f"{tag}: gambar/jumlah tidak sah")
        elif ty == "classify":
            bins = q.get("bins", [])
            items = q.get("items", [])
            if len(bins) < 2 or len(items) < 3 or any(not 0 <= i[1] < len(bins) for i in items):
                errs.append(f"{tag}: kelompok tidak sah")
            if len({i[0] for i in items}) != len(items):
                errs.append(f"{tag}: benda kembar")
        d = dict(q)
        d["id"] = qid
        d["subject"] = next(x for x in TOPICS if x["id"] == t)["region"] if t in topic_ids else ""
        d["difficulty"] = DIFF.get(ty, 2)
        d["points"] = 10 * d["difficulty"]
        out.append(d)
    # Setiap (topik, kelas) harus punya soal: dari bank atau pembuat soal.
    for t in TOPICS:
        for g in t["grades"]:
            if per_tg.get((t["id"], g), 0) == 0 and str(g) not in t.get("gen", {}):
                errs.append(f"topik {t['id']} kelas {g}: tidak ada soal")
    for name, animals in MINIGAMES["hewan"].items():
        for a in animals:
            if a not in ANIMAL_FACTS:
                errs.append(f"hewan {a}: tanpa fakta koleksi")
    return errs, out


def main():
    errs, questions = validate()
    if errs:
        print("Bank soal TIDAK SAH:")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    doc = {"schema": 1, "title": "Petualangan Pulau Ilmu", "regions": REGIONS, "topics": TOPICS,
           "questions": questions, "type_names": TYPE_NAMES, "minigames": MINIGAMES, "animal_facts": ANIMAL_FACTS,
           "badges": BADGES, "shop": SHOP}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    by_type = {}
    for q in questions:
        by_type[q["type"]] = by_type.get(q["type"], 0) + 1
    print(f"Bank soal sah: {len(questions)} soal, {len(TOPICS)} topik, {len(REGIONS)} wilayah -> {os.path.normpath(OUT)}")
    print("Per tipe:", ", ".join(f"{k} {v}" for k, v in sorted(by_type.items())))
    for g in range(1, 7):
        print(f"  Kelas {g}: {sum(1 for q in questions if q['grade'] == g)} soal bank")


if __name__ == "__main__":
    main()
