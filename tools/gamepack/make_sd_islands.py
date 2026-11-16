#!/usr/bin/env python3
"""Pembuat data Pulau 2–6 Petualangan Ilmu SD (Tahap 8).

Setiap pulau memakai tata ruang yang sudah teruji di Pulau 1 (dermaga di selatan, desa, ladang, akademi di
bukit, sungai + jembatan, hutan, tempat rahasia bertutup batu, benteng bos di utara), dengan variasi:
dicerminkan kiri-kanan, bangunan, pepohonan, warna langit/benteng, gunung, penduduk, cerita, misi,
tantangan sesuai kelas pulau, musuh, dan bos. Keluaran: client/games/education_sd/data/island{n}.json,
quests{n}.json, monsters{n}.json. Jalankan ulang setiap kali spesifikasi di bawah diubah.
"""
import copy
import json
import os

DATA = os.path.join(os.path.dirname(__file__), "..", "..", "client", "games", "education_sd", "data")


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def save(name, doc):
    with open(os.path.join(DATA, name), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent="\t")
        f.write("\n")


# --- Spesifikasi pulau --------------------------------------------------------------------------------------------

ISLANDS = {
    2: {
        "mirror": True,
        "academy": "Akademi Daun",
        "places": {"dermaga": "Dermaga Kayu", "desa": "Desa Pohon", "ladang": "Kebun Beri", "akademi": "Akademi Daun",
                   "sungai": "Sungai Akar", "hutan": "Hutan Ajaib", "gua": "Lubang Akar Tua", "benteng": "Sarang Serigala"},
        "houses": ["tongkonan", "rumah_gadang", "tongkonan", "joglo"],
        "academy_b": ["library", "observatory", "lab_dome"],
        "tree_kinds": ["vegetation/tree_pine", "vegetation/tree_pine", "vegetation/bush", "vegetation/flowers"],
        "colors": {"sky_top": "#2f7f6a", "sky_horizon": "#cdeedc", "ground": "#5fb35a", "wall": "#7a5232", "roof": "#3f8f3f", "flag": "#5a5a66"},
        "shapes": [],
        "npcs": [
            ("tetua", "Kakek Rimba", "Tetua Desa", "warga_bapak2"), ("guru", "Bu Guru Melati", "Guru Akademi", "warga_ibu"),
            ("pekebun", "Pak Jati", "Pekebun Beri", "petani"), ("ibu", "Mak Kenanga", "Pembuat Selai", "nenek_penjual"),
            ("anak", "Rara", "Anak Desa", "anak_desa"), ("warga", "Bu Anggrek", "Penenun", "warga_ibu2"),
            ("dermaga", "Pak Bakau", "Penjaga Dermaga", "warga_bapak"), ("jembatan", "Kak Pinus", "Penjaga Hutan", "pemanah"),
            ("pedagang", "Mbak Rotan", "Pedagang", "warga_ibu2")],
        "story": "Kabut Lupa membuat Hutan Rahasia tersesat. Serigala Hutan Besar menjaga sarangnya dan menakuti para penduduk.",
        "q2": {"title": "Persediaan Makanan", "item": "beri", "item_name": "Buah Beri", "item_desc": "Beri manis untuk persediaan musim hujan.",
               "offer": ["Persediaan makanan desa berkurang! Babi hutan menjatuhkan buah beri di jalan ke Hutan Ajaib.",
                         "Kumpulkan 5 buah beri, lalu bantu aku menghitung persediaannya."],
               "say": ["Terima kasih! Persediaan desa cukup sampai musim hujan."],
               "reward_item": ("keranjang_rotan", "Keranjang Rotan", "Hadiah dari Pak Jati.")},
        "q3": {"title": "Petunjuk Harta Karun", "item": "peti_harta", "item_name": "Peti Harta Kecil", "item_desc": "Peti berisi hiasan desa yang hilang.",
               "offer": ["Hiasan desa dicuri dan disembunyikan di Hutan Ajaib.", "Ada pohon tua bertulisan. Bacalah petunjuknya!"],
               "clue": "Pohon Bertulis", "clue_say": ["Tulisan di pohon tua bersinar! Petunjuknya: cari di balik semak paling lebat."],
               "deliver": ["Hiasan desa kembali! Desa Pohon jadi cantik lagi."]},
        "q4": {"title": "Akar Raksasa", "subject": "ipa", "boulder_name": "Akar Raksasa",
               "boulder_text": "Akar raksasa menutup Lubang Akar Tua. Mungkin akar ini bergeser bila kamu paham tentang tumbuhan.",
               "offer": ["Kak! Kata Kakek Rimba, akar raksasa itu mau bergeser kalau ada yang menjawab teka-teki tumbuhan!"],
               "say": ["Akar raksasa bergeser pelan... Lubang Akar Tua terbuka!"],
               "key": ("taring_perak", "Kunci Taring Perak", "Kunci berbentuk taring untuk membuka Sarang Serigala.")},
        "q5": {"title": "Gerbang Sarang", "offer": ["Kunci Taring Perak! Itu kunci pintu Sarang Serigala.", "Hati-hati, Serigala Hutan Besar ada di dalam!"],
               "say": ["Pintu kayu sarang terbuka!", "Serigala Hutan Besar melolong: \"Auuuu! Siapa berani masuk?\""]},
        "side_beach": {"title": "Daun Ajaib", "item": "daun_ajaib", "item_name": "Daun Ajaib", "offer": ["Daun ajaib bercahaya tertiup ke pantai.", "Kumpulkan 5 helai untukku, ya!"],
                       "outfit": "warna_ungu", "say": ["Indah sekali! Ini baju ungu untukmu."]},
        "side_challenge": {"title": "Lagu Hutan", "subject": "seni", "prefer": ["musik", "warna", "tari"],
                           "offer": ["Aku sedang belajar lagu daerah dan warna. Bantu aku, ya!"], "say": ["Hebat! Kamu paham seni Nusantara."]},
        "boss": {"id": "serigala_besar", "name": "Serigala Hutan Besar", "model": "serigala_hutan", "scale": 1.6, "shield": "Bulu Baja",
                 "tint": "#b8c4d0", "taunt": "Auuuu! Hutan ini milikku!", "defeat": "Auuu... kamu hebat. Aku akan menjaga hutan dengan baik mulai sekarang."},
        "minions": [("babi_nakal", "Babi Hutan Nakal", "babi_hutan", 0.8, "ipa"), ("anak_serigala", "Anak Serigala", "serigala_hutan", 0.7, "bahasa"),
                    ("belalang", "Belalang Raksasa", "belalang_raksasa", 0.7, "matematika")],
        "guards": ("serigala_hutan", "Serigala Penjaga", 0.8),
        "math": ["penjumlahan", "perkalian", "pengukuran", "berhitung"], "bahasa": ["kata_kalimat", "sinonim_antonim", "tanda_baca", "huruf"],
        "q4prefer": ["tumbuhan", "hewan", "wujud_benda", "lingkungan"],
    },
    3: {
        "mirror": False,
        "academy": "Akademi Kerajaan",
        "places": {"dermaga": "Dermaga Kerajaan", "desa": "Kota Kerajaan", "ladang": "Lumbung Kerajaan", "akademi": "Akademi Kerajaan",
                   "sungai": "Kanal Kerajaan", "hutan": "Taman Kerajaan", "gua": "Pintu Teka-teki", "benteng": "Benteng Kutukan"},
        "houses": ["joglo", "rumah_gadang", "rumah_gadang", "joglo"],
        "academy_b": ["museum", "math_tower", "math_tower"],
        "tree_kinds": ["vegetation/tree_round", "vegetation/tree_round", "vegetation/bush", "vegetation/flowers"],
        "colors": {"sky_top": "#3a5fb8", "sky_horizon": "#e8dcff", "ground": "#86c063", "wall": "#8f86a6", "roof": "#6a4fb0", "flag": "#2b2440"},
        "shapes": [],
        "npcs": [
            ("tetua", "Ratu Sekar", "Ratu Kerajaan", "penyihir"), ("guru", "Pak Guru Arif", "Guru Akademi", "warga_bapak"),
            ("pekebun", "Pak Lumbung", "Penjaga Lumbung", "petani"), ("ibu", "Bu Juru Masak", "Juru Masak Istana", "nenek_penjual"),
            ("anak", "Pangeran Kecil", "Putra Ratu", "anak_desa"), ("warga", "Bu Bendahara", "Bendahara Istana", "warga_ibu2"),
            ("dermaga", "Pak Nahkoda", "Penjaga Dermaga", "warga_bapak2"), ("jembatan", "Kapten Bayu", "Kapten Pengawal", "ksatria"),
            ("pedagang", "Saudagar Emas", "Pedagang", "warga_bapak")],
        "story": "Kutukan Kabut Lupa membekukan Kerajaan Angka. Golem Penjaga Kerajaan menutup benteng dan tidak mengenali rakyatnya.",
        "q2": {"title": "Membagi Makanan", "item": "karung_gandum", "item_name": "Karung Gandum", "item_desc": "Gandum untuk dibagi adil ke seluruh rakyat.",
               "offer": ["Karung gandum lumbung terjatuh di jalan ke Taman Kerajaan.", "Kumpulkan 5 karung, lalu bantu aku membaginya dengan adil!"],
               "say": ["Semua rakyat mendapat bagian yang sama. Adil sekali!"],
               "reward_item": ("timbangan_emas", "Timbangan Emas", "Hadiah dari Pak Lumbung.")},
        "q3": {"title": "Peta Kerajaan", "item": "peta_kerajaan", "item_name": "Peta Kerajaan", "item_desc": "Peta lama yang menunjukkan jalan rahasia istana.",
               "offer": ["Resep istana hilang bersama peta kerajaan!", "Di Taman Kerajaan ada prasasti. Pecahkan tulisannya untuk menemukan peta."],
               "clue": "Prasasti Taman", "clue_say": ["Prasasti bersinar! Peta tersembunyi di bawah pohon paling besar."],
               "deliver": ["Peta kerajaan kembali! Kini aku tahu letak dapur rahasia."]},
        "q4": {"title": "Pintu Teka-teki", "subject": "ips", "boulder_name": "Pintu Batu Angka",
               "boulder_text": "Pintu batu penuh angka dan peta. Pintu ini terbuka bagi yang memahami peta dan budaya Nusantara.",
               "offer": ["Ibunda Ratu bilang, Pintu Teka-teki menyimpan kunci benteng!", "Pintunya terbuka kalau kamu paham peta dan budaya."],
               "say": ["Pintu batu bergeser... Ruang rahasia terbuka!"],
               "key": ("kunci_mahkota", "Kunci Mahkota", "Kunci emas pembuka Benteng Kutukan.")},
        "q5": {"title": "Membuka Benteng Kutukan", "offer": ["Kunci Mahkota! Bukalah Benteng Kutukan, petualang.", "Golem Penjaga sangat kuat. Gunakan jurus ilmumu!"],
               "say": ["Gerbang benteng turun!", "Golem Penjaga Kerajaan bangkit: \"PENYUSUP... HARUS... DIHENTIKAN.\""]},
        "side_beach": {"title": "Koin Kuno", "item": "koin_kuno", "item_name": "Koin Kuno", "offer": ["Koin kuno kerajaan tersebar di pantai.", "Kumpulkan 5 untuk museum kerajaan!"],
                       "outfit": "topi_toga", "say": ["Koleksi museum lengkap! Ini topi toga untukmu."]},
        "side_challenge": {"title": "Rakyat yang Rukun", "subject": "pancasila", "prefer": ["gotong_royong", "keberagaman", "hak_kewajiban", "aturan"],
                           "offer": ["Rakyat kerajaan sedang bermusyawarah. Bantu aku memahami aturan dan kerukunan!"], "say": ["Terima kasih! Rakyat kini hidup rukun."]},
        "boss": {"id": "golem_kerajaan", "name": "Golem Penjaga Kerajaan", "model": "golem_kerikil", "scale": 1.7, "shield": "Kulit Batu",
                 "tint": "#c8b8ff", "taunt": "PENYUSUP... TIDAK... BOLEH... LEWAT.", "defeat": "Kutukan... hilang. Aku... ingat sekarang. Aku penjaga rakyat."},
        "minions": [("prajurit_kutukan", "Prajurit Kutukan", "goblin_penjaga", 1.1, "matematika"), ("tikus_gudang", "Tikus Gudang", "tikus_sawah", 0.6, "pancasila"),
                    ("kelelawar_istana", "Kelelawar Istana", "kelelawar_hutan", 0.8, "bahasa")],
        "guards": ("goblin_penjaga", "Prajurit Kutukan", 1.15),
        "math": ["pembagian", "perkalian", "pecahan", "pengukuran"], "bahasa": ["bacaan", "kata_kalimat", "cerita", "sinonim_antonim"],
        "q4prefer": ["peta", "budaya", "ekonomi"],
    },
    4: {
        "mirror": True,
        "academy": "Akademi Ilmuwan",
        "places": {"dermaga": "Pelabuhan Penemu", "desa": "Kota Penemu", "ladang": "Kebun Percobaan", "akademi": "Akademi Ilmuwan",
                   "sungai": "Sungai Tercemar", "hutan": "Hutan Palem", "gua": "Reruntuhan Kuno", "benteng": "Kuil Batu Kuno"},
        "houses": ["joglo", "rumah_gadang", "tongkonan", "joglo"],
        "academy_b": ["lab_dome", "observatory", "math_tower"],
        "tree_kinds": ["vegetation/tree_palm", "vegetation/tree_palm", "vegetation/bush", "vegetation/flowers"],
        "colors": {"sky_top": "#2f8fd8", "sky_horizon": "#fff2cf", "ground": "#9cc466", "wall": "#c9a46a", "roof": "#2f8f8a", "flag": "#e0813d"},
        "shapes": [{"type": "cone", "pos": [52, 8], "r": 9, "top": 2.5, "h": 9, "color": "#a08a6a"}],
        "npcs": [
            ("tetua", "Profesor Tua", "Kepala Penemu", "penyihir"), ("guru", "Bu Guru Ratih", "Guru Akademi", "warga_ibu"),
            ("pekebun", "Pak Mesin", "Ahli Mesin", "pendekar_kapak"), ("ibu", "Bu Sungai", "Penjaga Sungai", "warga_ibu2"),
            ("anak", "Tito", "Penemu Cilik", "anak_desa"), ("warga", "Kak Atlet", "Pelatih Olahraga", "pendekar_tombak"),
            ("dermaga", "Pak Kapal", "Penjaga Pelabuhan", "warga_bapak"), ("jembatan", "Kak Peneliti", "Peneliti Reruntuhan", "pemanah"),
            ("pedagang", "Pak Toko Alat", "Pedagang", "warga_bapak2")],
        "story": "Mesin-mesin kuno Negeri Penemuan berhenti dan sungainya tercemar. Penjaga Batu Kuno terbangun di kuil dan menutup jalan.",
        "q2": {"title": "Memperbaiki Mesin Kuno", "item": "roda_gigi", "item_name": "Roda Gigi", "item_desc": "Roda gigi kuningan untuk mesin kuno.",
               "offer": ["Mesin kincir kota mati! Roda giginya tercecer di jalan ke Hutan Palem.", "Kumpulkan 5 roda gigi, lalu bantu aku menghitung ukurannya."],
               "say": ["Mesin kincir berputar lagi! Lampu kota menyala!"],
               "reward_item": ("kunci_inggris", "Kunci Inggris", "Hadiah dari Pak Mesin.")},
        "q3": {"title": "Menyelidiki Sungai", "item": "botol_sampel", "item_name": "Botol Sampel Air", "item_desc": "Sampel air sungai untuk diteliti.",
               "offer": ["Sungai kita tercemar! Ada catatan peneliti di Hutan Palem.", "Baca catatannya dan ambil sampel air untukku."],
               "clue": "Catatan Peneliti", "clue_say": ["Catatan peneliti terbaca! Sampel air disimpan di dekat pohon palem tertinggi."],
               "deliver": ["Dengan sampel ini kita tahu penyebab pencemarannya: sampah! Ayo jaga sungai bersama."]},
        "q4": {"title": "Reruntuhan Kuno", "subject": "ipa", "boulder_name": "Pintu Batu Bercahaya",
               "boulder_text": "Pintu batu reruntuhan bercahaya. Ia hanya terbuka bagi yang memahami energi dan alam.",
               "offer": ["Kata Profesor Tua, pintu reruntuhan terbuka dengan teka-teki ilmiah!"],
               "say": ["Pintu batu bercahaya terang lalu bergeser... Reruntuhan terbuka!"],
               "key": ("kristal_kuno", "Kristal Kuno", "Kristal bercahaya pembuka Kuil Batu Kuno.")},
        "q5": {"title": "Kuil Batu Kuno", "offer": ["Kristal Kuno! Pasang di gerbang kuil untuk membukanya.", "Penjaga Batu Kuno menunggu di dalam."],
               "say": ["Kristal bersinar, gerbang kuil turun!", "Penjaga Batu Kuno bergemuruh: \"Buktikan ilmumu!\""]},
        "side_beach": {"title": "Sampah Pantai", "item": "sampah_plastik", "item_name": "Sampah Plastik", "offer": ["Pantai kotor oleh sampah plastik.", "Bantu kumpulkan 5 sampah untuk didaur ulang!"],
                       "outfit": "aks_syal", "say": ["Pantai bersih lagi! Ini syal dari bahan daur ulang."]},
        "side_challenge": {"title": "Sehat dan Bugar", "subject": "pjok", "prefer": ["olahraga", "hidup_sehat"],
                           "offer": ["Ayo jadi penemu yang sehat! Jawab pertanyaanku tentang olahraga dan hidup sehat."], "say": ["Hebat! Tubuh sehat, pikiran cerdas."]},
        "boss": {"id": "penjaga_batu", "name": "Penjaga Batu Kuno", "model": "golem_lava", "scale": 1.7, "shield": "Pelindung Kristal",
                 "tint": "#9ad8ff", "taunt": "GRRR... Hanya penemu sejati yang boleh lewat!", "defeat": "Kau penemu sejati. Mesin dan sungai akan kembali bersih."},
        "minions": [("golem_kerikil", "Golem Kerikil", "golem_kerikil", 0.9, "ipa"), ("ular_sungai", "Ular Sungai", "ular_sawah", 0.6, "matematika"),
                    ("belalang_mesin", "Belalang Mesin", "belalang_raksasa", 0.8, "bahasa")],
        "guards": ("golem_kerikil", "Golem Penjaga", 1.0),
        "math": ["bangun_datar", "bangun_ruang", "logika", "perkalian"], "bahasa": ["bacaan", "pantun", "kata_kalimat", "cerita"],
        "q4prefer": ["energi", "lingkungan", "tumbuhan", "tubuh"],
    },
    5: {
        "mirror": False,
        "academy": "Akademi Ksatria",
        "places": {"dermaga": "Dermaga Benteng", "desa": "Kota Ksatria", "ladang": "Ladang Gandum", "akademi": "Akademi Ksatria",
                   "sungai": "Sungai Jernih", "hutan": "Lembah Pertahanan", "gua": "Mata Air Tersembunyi", "benteng": "Perkemahan Orc"},
        "houses": ["rumah_gadang", "joglo", "joglo", "tongkonan"],
        "academy_b": ["museum", "math_tower", "lab_dome"],
        "tree_kinds": ["vegetation/tree_round", "vegetation/tree_pine", "vegetation/bush", "vegetation/flowers"],
        "colors": {"sky_top": "#5a6fb0", "sky_horizon": "#f0e0d0", "ground": "#74b45c", "wall": "#5a3a22", "roof": "#8a2a2a", "flag": "#2b2440"},
        "shapes": [{"type": "cone", "pos": [-54, 10], "r": 8, "top": 3, "h": 6, "color": "#8a8174"}],
        "npcs": [
            ("tetua", "Raja Satria", "Raja", "ksatria"), ("guru", "Pak Guru Wira", "Guru Akademi", "warga_bapak"),
            ("pekebun", "Pak Gandum", "Petani Gandum", "petani"), ("ibu", "Bu Tabib", "Tabib Kerajaan", "nenek_penjual"),
            ("anak", "Kesatria Kecil", "Murid Ksatria", "anak_desa"), ("warga", "Bu Penasihat", "Penasihat Raja", "warga_ibu2"),
            ("dermaga", "Pak Laut", "Penjaga Dermaga", "warga_bapak2"), ("jembatan", "Kapten Tombak", "Kapten Pasukan", "pendekar_tombak"),
            ("pedagang", "Pak Pandai Besi", "Pandai Besi", "pendekar_kapak")],
        "story": "Pasukan Orc mengepung Kerajaan Ksatria. Panglima Orc menutup mata air dan membuat tanaman sakit.",
        "q2": {"title": "Kebutuhan Pasukan", "item": "perbekalan", "item_name": "Kotak Perbekalan", "item_desc": "Perbekalan makanan untuk pasukan penjaga.",
               "offer": ["Perbekalan pasukan dicuri orc dan tercecer di jalan ke Lembah Pertahanan.", "Kumpulkan 5 kotak, lalu bantu aku menghitung kebutuhan pasukan."],
               "say": ["Perbekalan cukup untuk seluruh pasukan. Terima kasih, ksatria!"],
               "reward_item": ("perisai_kecil", "Perisai Kecil", "Hadiah dari Pak Gandum.")},
        "q3": {"title": "Tanaman yang Sakit", "item": "obat_tanaman", "item_name": "Ramuan Tanaman", "item_desc": "Ramuan untuk menyembuhkan tanaman yang sakit.",
               "offer": ["Tanaman ladang layu dan sakit!", "Di Lembah Pertahanan ada gulungan tabib. Bacalah untuk menemukan ramuannya."],
               "clue": "Gulungan Tabib", "clue_say": ["Gulungan terbaca! Ramuan tumbuh di bawah pohon besar di lembah."],
               "deliver": ["Ramuan ini menyembuhkan tanaman! Ladang hijau kembali."]},
        "q4": {"title": "Mencari Sumber Air Bersih", "subject": "ipa", "boulder_name": "Batu Mata Air",
               "boulder_text": "Batu besar menutup mata air. Ia bergeser bagi yang paham tubuh manusia dan ekosistem.",
               "offer": ["Rakyat butuh air bersih! Mata air tersembunyi ditutup batu oleh orc."],
               "say": ["Batu bergeser! Air bersih mengalir lagi untuk seluruh kerajaan."],
               "key": ("terompet_perang", "Terompet Ksatria", "Terompet untuk membuka gerbang Perkemahan Orc.")},
        "q5": {"title": "Menyelamatkan Kerajaan", "offer": ["Terompet Ksatria! Tiup di depan gerbang perkemahan orc.", "Panglima Orc sangat kuat, susun strategimu!"],
               "say": ["Terompet berbunyi, gerbang perkemahan terbuka!", "Panglima Orc mengangkat kapaknya: \"Siapa berani menantangku?!\""]},
        "side_beach": {"title": "Tombak yang Hilang", "item": "tombak_patah", "item_name": "Tombak Patah", "offer": ["Tombak pasukan hanyut ke pantai.", "Kumpulkan 5 untuk diperbaiki pandai besi!"],
                       "outfit": "warna_emas", "say": ["Pasukan bersenjata lagi! Ini baju emas ksatria untukmu."]},
        "side_challenge": {"title": "Sumpah Ksatria", "subject": "pancasila", "prefer": ["sila_pancasila", "negaraku", "hak_kewajiban"],
                           "offer": ["Ksatria sejati paham dasar negara dan kewajibannya. Siap diuji?"], "say": ["Kamu layak menjadi ksatria!"]},
        "boss": {"id": "panglima_orc", "name": "Panglima Orc", "model": "ogre_batu", "scale": 1.5, "shield": "Zirah Besi",
                 "tint": "#b0d090", "taunt": "HARR! Kerajaan ini akan jadi milik pasukanku!", "defeat": "Harr... kau ksatria sejati. Pasukanku akan pergi dan tidak kembali!"},
        "minions": [("pengintai_orc", "Pengintai Orc", "goblin", 1.1, "matematika"), ("babi_perang", "Babi Perang", "babi_hutan", 0.9, "ipa"),
                    ("serigala_pasukan", "Serigala Pasukan", "serigala_hutan", 0.8, "pancasila")],
        "guards": ("goblin_penjaga", "Penjaga Orc", 1.2),
        "math": ["pecahan", "pengukuran", "perkalian", "pembagian"], "bahasa": ["bacaan", "cerita", "tanda_baca", "kata_kalimat"],
        "q4prefer": ["tubuh", "ekosistem", "hewan"],
    },
    6: {
        "mirror": True,
        "academy": "Akademi Legenda",
        "places": {"dermaga": "Dermaga Terakhir", "desa": "Desa Terakhir", "ladang": "Kebun Abu", "akademi": "Akademi Legenda",
                   "sungai": "Sungai Lava Dingin", "hutan": "Hutan Hangus", "gua": "Gua Sandi Kuno", "benteng": "Sarang Naga"},
        "houses": ["tongkonan", "joglo", "rumah_gadang", "tongkonan"],
        "academy_b": ["library", "observatory", "lighthouse"],
        "tree_kinds": ["vegetation/tree_pine", "vegetation/tree_pine", "vegetation/bush", "vegetation/bush"],
        "colors": {"sky_top": "#4a3a5e", "sky_horizon": "#ecd8c8", "ground": "#6f8c58", "wall": "#3a3440", "roof": "#c0392b", "flag": "#e05a4f"},
        "shapes": [{"type": "cone", "pos": [50, 8], "r": 12, "top": 3, "h": 14, "color": "#5a4a48", "glow": "#ff7a2a"}],
        "npcs": [
            ("tetua", "Nenek Legenda", "Penjaga Legenda", "penyihir"), ("guru", "Pak Guru Agung", "Guru Akademi", "warga_bapak2"),
            ("pekebun", "Pak Pengukur", "Juru Ukur", "petani"), ("ibu", "Bu Penyelamat", "Pemimpin Pengungsi", "warga_ibu"),
            ("anak", "Bima Muda", "Pemberani Cilik", "anak_desa"), ("warga", "Kak Seniman", "Seniman Desa", "warga_ibu2"),
            ("dermaga", "Pak Mercusuar", "Penjaga Mercusuar", "warga_bapak"), ("jembatan", "Panglima Ksatria", "Pemimpin Pahlawan", "ksatria"),
            ("pedagang", "Saudagar Naga", "Pedagang", "pendekar_kapak")],
        "story": "Inilah pulau terakhir. Naga Kegelapan, sumber Kabut Lupa, bersarang di dekat gunung api. Hanya pahlawan ilmu yang bisa mengalahkannya.",
        "q2": {"title": "Jarak Sarang Naga", "item": "batu_penanda", "item_name": "Batu Penanda", "item_desc": "Batu penanda jarak jalan menuju sarang naga.",
               "offer": ["Untuk menyerang sarang naga, kita harus tahu jaraknya.", "Kumpulkan 5 batu penanda di jalan ke Hutan Hangus, lalu bantu aku menghitung jaraknya."],
               "say": ["Jarak dan peta sudah tepat. Kita siap!"],
               "reward_item": ("kompas_naga", "Kompas Naga", "Hadiah dari Pak Pengukur.")},
        "q3": {"title": "Menyelamatkan Penduduk", "item": "lonceng_evakuasi", "item_name": "Lonceng Evakuasi", "item_desc": "Lonceng untuk memanggil penduduk ke tempat aman.",
               "offer": ["Penduduk Hutan Hangus terjebak! Ada tugu bertulis di hutan.", "Bacalah tugu itu untuk menemukan lonceng evakuasi."],
               "clue": "Tugu Bertulis", "clue_say": ["Tulisan tugu terbaca! Lonceng ada di tengah Hutan Hangus."],
               "deliver": ["Loncengnya berbunyi! Semua penduduk berkumpul dengan selamat."]},
        "q4": {"title": "Sandi Kuno", "subject": "ipa", "boulder_name": "Pintu Sandi Kuno",
               "boulder_text": "Pintu batu dengan sandi kuno tentang tata surya dan energi.",
               "offer": ["Kak! Gua Sandi Kuno menyimpan Pedang Cahaya. Pintunya terbuka dengan sandi tata surya!"],
               "say": ["Sandi terpecahkan! Pintu gua terbuka dan cahaya terang memancar."],
               "key": ("pedang_cahaya", "Pedang Cahaya", "Pedang legenda untuk membuka Sarang Naga.")},
        "q5": {"title": "Strategi Melawan Naga", "offer": ["Pedang Cahaya! Hanya pedang ini yang bisa membuka Sarang Naga.", "Ini pertarungan terakhir. Kami semua percaya padamu!"],
               "say": ["Pedang Cahaya bersinar, gerbang sarang runtuh!", "Naga Kegelapan membuka matanya: \"Akhirnya... sang pahlawan ilmu datang.\""]},
        "side_beach": {"title": "Kerang Mutiara", "item": "mutiara", "item_name": "Mutiara", "offer": ["Mutiara indah terdampar di pantai.", "Kumpulkan 5 untuk menghias mercusuar!"],
                       "outfit": "topi_mahkota", "say": ["Mercusuar bersinar indah! Ini mahkota pahlawan untukmu."]},
        "side_challenge": {"title": "Karya Seni Nusantara", "subject": "seni", "prefer": ["musik", "kerajinan", "tari"],
                           "offer": ["Seni Nusantara memberi semangat para pahlawan. Ayo kita bahas!"], "say": ["Indah sekali! Semangat kita bertambah."]},
        "boss": {"id": "naga_kegelapan", "name": "Naga Kegelapan", "model": "aldragor", "scale": 1.3, "shield": "Sisik Kegelapan",
                 "tint": "", "taunt": "Hahaha! Kabut Lupa akan menutupi dunia selamanya!", "defeat": "Tidak... cahaya ilmu terlalu terang... Kabut Lupa... lenyap..."},
        "minions": [("golem_lava", "Golem Lava", "golem_lava", 0.9, "ipa"), ("kelelawar_api", "Kelelawar Api", "kelelawar_hutan", 0.9, "matematika"),
                    ("ular_bara", "Ular Bara", "ular_sawah", 0.7, "bahasa")],
        "guards": ("golem_lava", "Penjaga Lava", 1.1),
        "math": ["logika", "bangun_ruang", "bangun_datar", "pengukuran"], "bahasa": ["bacaan", "kata_kalimat", "pantun", "cerita"],
        "q4prefer": ["tata_surya", "energi", "ekosistem"],
    },
}

SLOT_ORDER = ["tetua", "guru", "pekebun", "ibu", "anak", "warga", "dermaga", "jembatan", "pedagang"]
ISLAND1_NPC = ["pak_lurah", "bu_guru", "pak_budi", "nenek_ijah", "dodi", "bu_wati", "pak_udin", "kak_laras", "pak_darto"]


def mx(pt, mirror):
    return [-pt[0], pt[1]] if mirror else [pt[0], pt[1]]


def slug(text):
    return "".join(ch if ch.isalnum() else "_" for ch in text.lower()).strip("_")


def build_layout(n, spec, base):
    m = spec["mirror"]
    lay = copy.deepcopy(base)
    lay["island"] = "pulau%d" % n
    lay["academy_name"] = spec["academy"]
    lay["tree_kinds"] = spec["tree_kinds"]
    lay["colors"] = spec["colors"]
    lay["shapes"] = [dict(s, pos=mx(s["pos"], False)) for s in spec["shapes"]]
    lay["paths"] = [[mx(a, m), mx(b, m)] for a, b in base["paths"]]
    lay["farm"]["pos"] = mx(base["farm"]["pos"], m)
    lay["forest"]["pos"] = mx(base["forest"]["pos"], m)
    for pl in lay["places"]:
        pl["name"] = spec["places"][pl["id"]]
        pl["pos"] = mx(pl["pos"], m)
        if "sign" in pl:
            pl["sign"] = mx(pl["sign"], m)
    objs = []
    houses = iter(spec["houses"])
    acad = spec["academy_b"]
    for o in base["objects"]:
        o = copy.deepcopy(o)
        a = o["asset"]
        if a in ("buildings/joglo", "buildings/rumah_gadang", "buildings/tongkonan"):
            o["asset"] = "buildings/" + next(houses)
        elif a == "buildings/library":
            o["asset"] = "buildings/" + acad[0]
            o["scale"] = {"library": 1.0, "museum": 1.0, "lab_dome": 1.0}.get(acad[0], 1.0)
        elif a == "buildings/math_tower":
            o["asset"] = "buildings/" + acad[1]
            o["scale"] = {"observatory": 0.5, "math_tower": 0.6, "lighthouse": 0.55}.get(acad[1], 0.55)
        elif a == "buildings/lab_dome":
            o["asset"] = "buildings/" + acad[2]
            o["scale"] = {"lab_dome": 0.55, "math_tower": 0.6, "lighthouse": 0.5, "observatory": 0.5}.get(acad[2], 0.55)
        o["pos"] = mx(o["pos"], m)
        if m and "rot" in o:
            o["rot"] = -o["rot"]
        objs.append(o)
    lay["objects"] = objs
    lay["boulder"] = {"pos": mx(base["boulder"]["pos"], m), "scale": 2.6, "flag": "p%d_terbuka" % n}
    lay["fort"] = dict(base["fort"], flag="p%d_gerbang" % n, key="p%d_%s" % (n, spec["q4"]["key"][0]))
    b = spec["boss"]
    lay["boss"] = {"model": b["model"], "name": b["name"], "pos": base["boss"]["pos"], "scale": b["scale"], "monster": b["id"],
                   "flag": "p%d_bos" % n, "tint": b["tint"]}
    g = spec["guards"]
    lay["guards"] = [{"model": g[0], "name": g[1], "pos": [-4.5, -43.5], "height": g[2]}, {"model": g[0], "name": g[1], "pos": [4.5, -43.5], "height": g[2]}]
    lay["signs"] = {
        "gate": {"title": spec["places"]["benteng"], "text": "Gerbangnya terkunci rapat. %s ada di dalam." % b["name"]},
        "boulder": {"title": spec["q4"]["boulder_name"], "text": spec["q4"]["boulder_text"]},
        "gate_hint": {"title": spec["places"]["benteng"], "text": "Kuncinya cocok... Tanyakan dulu pada %s." % spec["npcs"][7][1]},
    }
    npcs = []
    for i, slot in enumerate(SLOT_ORDER):
        base_npc = next(x for x in base["npcs"] if x["id"] == ISLAND1_NPC[i])
        _, name, role, model = spec["npcs"][i]
        nid = "p%d_%s" % (n, slot)
        npc = {"id": nid, "name": name, "role": role, "model": model, "pos": mx(base_npc["pos"], m), "wander": base_npc.get("wander", 2.0),
               "lines": npc_lines(slot, name, spec), "again": npc_again(slot, spec)}
        if slot == "anak":
            npc["height"] = 1.3
        if slot == "pedagang":
            npc["shop"] = "toko_p%d" % n
        npcs.append(npc)
    lay["npcs"] = npcs
    return lay


def npc_lines(slot, name, spec):
    p = spec["places"]
    lines = {
        "tetua": ["Selamat datang di %s, {name}! Aku %s." % (p["desa"], name), spec["story"],
                  "Belajarlah dulu di %s di atas bukit, lalu bantu para penduduk." % spec["academy"]],
        "guru": ["Halo {name}! Aku %s, guru di %s." % (name, spec["academy"]), "Di sini kamu belajar materi yang lebih menantang. Ayo masuk ke akademi!"],
        "pekebun": ["Halo, {name}. Aku %s." % name, "Banyak pekerjaan di sini sejak Kabut Lupa datang."],
        "ibu": ["Nak {name}, hati-hati di %s, ya." % p["hutan"], "Aku butuh bantuanmu."],
        "anak": ["Kak {name}! Kakak petualang hebat itu, ya?", "Aku pernah melihat %s. Ada sesuatu di dalamnya!" % p["gua"]],
        "warga": ["Halo, {name}! Senang bertemu petualang.", "Di desa kami, semua saling membantu."],
        "dermaga": ["Perahumu aman di %s." % p["dermaga"], "Naik perahu untuk berlayar ke pulau lain."],
        "jembatan": ["Berhenti, {name}! Di seberang sungai banyak makhluk liar.", "%s ada di ujung utara pulau." % p["benteng"]],
        "pedagang": ["Selamat datang di lapakku, {name}!", "Aku menjual kue, ramuan, perisai, dan kostum. Bayar pakai koin, ya."],
    }
    return lines[slot]


def npc_again(slot, spec):
    again = {
        "tetua": ["Semangat, {name}! Seluruh %s percaya padamu." % spec["places"]["desa"]],
        "guru": ["Pintu %s selalu terbuka. Belajarlah bersama para guru." % spec["academy"]],
        "pekebun": ["Terima kasih sudah peduli pada desa kami."],
        "ibu": ["Hati-hati di perjalanan, Nak."],
        "anak": ["Aku ingin jadi pahlawan seperti Kakak!"],
        "warga": ["Jaga kesehatan dan tetap rajin belajar, ya."],
        "dermaga": ["Laut sedang tenang hari ini."],
        "jembatan": ["Gunakan jurus ilmumu untuk melawan musuh!"],
        "pedagang": ["Mau belanja lagi? Koin didapat dari belajar dan menolong warga."],
    }
    return again[slot]


def build_quests(n, spec, base_q):
    p = "p%d_" % n
    nid = lambda slot: "p%d_%s" % (n, slot)
    q2, q3, q4, q5 = spec["q2"], spec["q3"], spec["q4"], spec["q5"]
    sb, sc = spec["side_beach"], spec["side_challenge"]
    m = spec["mirror"]
    base_pick = {q["id"]: q for q in base_q["quests"]}
    seeds = [mx(pt, m) for pt in base_pick["bibit_hilang"]["steps"][0]["pickups"]]
    basket = mx(base_pick["keranjang_nenek"]["steps"][1]["pickups"][0], m)
    key_pos = mx(base_pick["pintu_gua"]["steps"][1]["pickups"][0], m)
    beach = [mx(pt, m) for pt in base_pick["kerang_pantai"]["steps"][0]["pickups"]]
    clue_pos = mx(base_q["spots"][0]["pos"], m)
    ilv = 1 + n  # skala hadiah
    items = {
        p + "lencana": {"name": "Lencana %s" % spec["academy"], "desc": "Tanda murid %s." % spec["academy"]},
        p + q2["item"]: {"name": q2["item_name"], "desc": q2["item_desc"]},
        p + q2["reward_item"][0]: {"name": q2["reward_item"][1], "desc": q2["reward_item"][2]},
        p + q3["item"]: {"name": q3["item_name"], "desc": q3["item_desc"]},
        p + q4["key"][0]: {"name": q4["key"][1], "desc": q4["key"][2]},
        p + sb["item"]: {"name": sb["item_name"], "desc": "Barang untuk %s." % spec["npcs"][6][1]},
        p + "piala": {"name": "Piala %s" % spec["places"]["desa"], "desc": "Bukti kamu pahlawan pulau ini."},
        "kue": {"name": "Kue Manis", "desc": "Kue manis. Memulihkan HP dalam pertarungan."},
        "perisai_daun": {"name": "Perisai Daun", "desc": "Mengurangi serangan musuh berikutnya menjadi setengah."},
    }
    region_name = {"ipa": "ipa", "ips": "ips"}
    challenges = {
        p + "hitung": {"title": q2["title"], "story": "Bantu %s menghitung dengan tepat!" % spec["npcs"][2][1], "region": "matematika",
                       "prefer": spec["math"], "n": 3, "pass": 2},
        p + "petunjuk": {"title": q3["clue"], "story": "Ada tulisan kuno. Pecahkan teka-teki bahasanya!", "region": "bahasa",
                         "prefer": spec["bahasa"], "n": 3, "pass": 2},
        p + "batu": {"title": q4["boulder_name"], "story": q4["boulder_text"], "region": region_name[q4["subject"]],
                     "prefer": spec["q4prefer"], "n": 3, "pass": 2},
        p + "sampingan": {"title": sc["title"], "story": sc["offer"][0], "region": sc["subject"], "prefer": sc["prefer"], "n": 3, "pass": 2},
    }
    minion_a = "p%d_%s" % (n, spec["minions"][0][0])
    quests = [
        {"id": p + "murid_baru", "kind": "main", "giver": nid("tetua"), "title": "Murid Baru %s" % spec["academy"],
         "offer": ["{name}, kamu sudah sampai di pulau kami!", "Petualang sejati selalu belajar. Selesaikan satu latihan di %s." % spec["academy"]],
         "steps": [{"type": "learn", "count": 1, "text": "Selesaikan 1 latihan di %s" % spec["academy"], "where": {"place": "akademi"}},
                   {"type": "talk", "npc": nid("tetua"), "text": "Kembali ke %s" % spec["npcs"][0][1], "where": {"npc": nid("tetua")},
                    "say": ["Bagus sekali, {name}! Ini lencana murid %s." % spec["academy"], "Sekarang bantulah para penduduk."]}],
         "reward": {"coins": 30 + 10 * ilv, "xp": 60 + 30 * ilv, "items": {p + "lencana": 1}}},
        {"id": p + "misi_2", "kind": "main", "giver": nid("pekebun"), "requires": [p + "murid_baru"], "title": q2["title"], "offer": q2["offer"],
         "steps": [{"type": "collect", "item": p + q2["item"], "count": 5, "text": "Kumpulkan %s" % q2["item_name"], "where": {"pos": mx([-12, -34], m)},
                    "pickups": seeds},
                   {"type": "challenge", "challenge": p + "hitung", "npc": nid("pekebun"), "text": "Bantu %s menghitung" % spec["npcs"][2][1],
                    "where": {"npc": nid("pekebun")}, "say": q2["say"]}],
         "reward": {"coins": 40 + 10 * ilv, "xp": 80 + 30 * ilv, "items": {p + q2["reward_item"][0]: 1}}},
        {"id": p + "misi_3", "kind": "main", "giver": nid("ibu"), "requires": [p + "murid_baru"], "title": q3["title"], "offer": q3["offer"],
         "steps": [{"type": "challenge", "challenge": p + "petunjuk", "spot": p + "clue", "text": "Pecahkan teka-teki %s" % q3["clue"],
                    "where": {"spot": p + "clue"}, "say": q3["clue_say"]},
                   {"type": "collect", "item": p + q3["item"], "count": 1, "text": "Temukan %s" % q3["item_name"], "where": {"pos": basket}, "pickups": [basket]},
                   {"type": "talk", "npc": nid("ibu"), "text": "Bawa %s ke %s" % (q3["item_name"], spec["npcs"][3][1]), "where": {"npc": nid("ibu")},
                    "take": {p + q3["item"]: 1}, "say": q3["deliver"]}],
         "reward": {"coins": 40 + 10 * ilv, "xp": 80 + 30 * ilv, "items": {"kue": 3}}},
        {"id": p + "misi_4", "kind": "main", "giver": nid("anak"), "requires": [p + "misi_2", p + "misi_3"], "title": q4["title"], "offer": q4["offer"],
         "steps": [{"type": "challenge", "challenge": p + "batu", "spot": "boulder", "text": "Pecahkan teka-teki %s" % q4["boulder_name"],
                    "where": {"spot": "boulder"}, "flags": ["p%d_terbuka" % n], "say": q4["say"]},
                   {"type": "collect", "item": p + q4["key"][0], "count": 1, "text": "Ambil %s" % q4["key"][1], "where": {"pos": key_pos}, "pickups": [key_pos]}],
         "reward": {"coins": 50 + 10 * ilv, "xp": 100 + 30 * ilv}},
        {"id": p + "misi_5", "kind": "main", "giver": nid("jembatan"), "requires": [p + "misi_4"], "title": q5["title"], "offer": q5["offer"],
         "steps": [{"type": "use", "target": "gate", "item": p + q4["key"][0], "text": "Buka gerbang %s" % spec["places"]["benteng"],
                    "where": {"spot": "gate"}, "flags": ["p%d_gerbang" % n], "take": {p + q4["key"][0]: 1}, "say": q5["say"]}],
         "reward": {"coins": 50 + 10 * ilv, "xp": 100 + 30 * ilv}},
        {"id": p + "bos", "kind": "main", "auto": True, "requires": [p + "misi_5"], "title": "Kalahkan %s" % spec["boss"]["name"],
         "steps": [{"type": "defeat", "target": spec["boss"]["id"], "count": 1, "text": "Kalahkan %s" % spec["boss"]["name"], "where": {"spot": "boss"},
                    "say": ["%s kalah! Kabut Lupa di %s menghilang." % (spec["boss"]["name"], spec["places"]["desa"]),
                            "Seluruh penduduk bersorak untukmu, {name}!"]}],
         "reward": {"coins": 100 + 20 * ilv, "xp": 200 + 50 * ilv, "items": {p + "piala": 1}}},
        {"id": p + "pantai", "kind": "side", "giver": nid("dermaga"), "title": sb["title"], "offer": sb["offer"],
         "steps": [{"type": "collect", "item": p + sb["item"], "count": 5, "text": "Kumpulkan %s" % sb["item_name"], "where": {"pos": beach[0]}, "pickups": beach},
                   {"type": "talk", "npc": nid("dermaga"), "text": "Berikan kepada %s" % spec["npcs"][6][1], "where": {"npc": nid("dermaga")},
                    "take": {p + sb["item"]: 5}, "say": sb["say"]}],
         "reward": {"coins": 30 + 5 * ilv, "xp": 40 + 20 * ilv, "outfit": sb["outfit"]}},
        {"id": p + "warga", "kind": "side", "giver": nid("warga"), "requires": [p + "murid_baru"], "title": sc["title"], "offer": sc["offer"],
         "steps": [{"type": "challenge", "challenge": p + "sampingan", "npc": nid("warga"), "text": "Jawab tantangan %s" % spec["npcs"][5][1],
                    "where": {"npc": nid("warga")}, "say": sc["say"]}],
         "reward": {"coins": 30 + 5 * ilv, "xp": 50 + 20 * ilv, "items": {"kue": 1}}},
        {"id": p + "usir", "kind": "side", "giver": nid("jembatan"), "requires": [p + "murid_baru"], "title": "Usir %s" % spec["minions"][0][1],
         "offer": ["%s berkeliaran di %s." % (spec["minions"][0][1], spec["places"]["hutan"]), "Kalahkan 3 dengan jurus ilmumu!"],
         "steps": [{"type": "defeat", "target": minion_a, "count": 3, "text": "Kalahkan %s" % spec["minions"][0][1], "where": {"pos": mx([-44, -36], m)}},
                   {"type": "talk", "npc": nid("jembatan"), "text": "Lapor ke %s" % spec["npcs"][7][1], "where": {"npc": nid("jembatan")},
                    "say": ["Hebat! Jalan sekarang lebih aman."]}],
         "reward": {"coins": 40 + 5 * ilv, "xp": 60 + 20 * ilv, "items": {"perisai_daun": 1}}},
        {"id": p + "jelajah", "kind": "side", "auto": True, "title": "Penjelajah %s" % spec["places"]["desa"],
         "steps": [{"type": "places_all", "text": "Temukan semua tempat di pulau"}], "reward": {"coins": 50 + 5 * ilv, "xp": 60}},
        {"id": p + "kenal", "kind": "side", "auto": True, "title": "Sahabat %s" % spec["places"]["desa"],
         "steps": [{"type": "meet_all", "text": "Berkenalan dengan semua penduduk"}], "reward": {"coins": 30 + 5 * ilv, "xp": 50}},
    ]
    return {"schema": 1, "island": "pulau%d" % n, "items": items, "challenges": challenges,
            "spots": [{"id": p + "clue", "name": q3["clue"], "pos": clue_pos}], "quests": quests}


def build_monsters(n, spec, base_m):
    m = spec["mirror"]
    out = {}
    lv = 2 * n - 1
    for i, (mid, name, model, h, subj) in enumerate(spec["minions"]):
        k = i * 0.15
        out["p%d_%s" % (n, mid)] = {"name": name, "model": model, "height": h, "level": lv + i,
                                    "hp": int(20 + 12 * (n - 1) * (1 + k)), "atk": int(6 + 3 * (n - 1) + i), "def": 1 + 2 * (n - 1),
                                    "xp": 15 + 15 * n, "coins": 6 + 4 * n, "subject": subj, "drop": {"item": "kue", "chance": 0.3},
                                    "taunt": "%s menghadang jalanmu!" % name}
    b = spec["boss"]
    out[b["id"]] = {"name": b["name"], "model": b["model"], "height": 1.7 if b["model"] != "aldragor" else 2.2, "level": 2 * n + 3,
                    "hp": 110 + 45 * (n - 1), "atk": 10 + 3 * (n - 1), "def": 6 + 2 * (n - 1), "xp": 150 + 50 * (n - 1), "coins": 100 + 40 * (n - 1),
                    "boss": True, "shield": b["shield"], "heavy_every": 3, "subject": "campur", "taunt": b["taunt"], "defeat": b["defeat"]}
    if b["tint"]:
        out[b["id"]]["tint"] = b["tint"]
    kinds = list(out.keys())[:3]
    spawns = []
    for i, sp in enumerate(base_m["spawns"]):
        mon = kinds[0] if "goblin" in sp["id"] else (kinds[1] if "tikus" in sp["id"] else kinds[2])
        spawns.append({"id": "p%d_%s" % (n, sp["id"]), "monster": mon, "pos": mx(sp["pos"], m), "leave_on_boss": mon == kinds[0]})
    return {"schema": 1, "island": "pulau%d" % n, "monsters": out, "spawns": spawns}


def main():
    base = load("island1.json")
    base_q = load("quests1.json")
    base_m = load("monsters1.json")
    rpg = load("rpg.json")
    stock = rpg["shop"]["pak_darto"]["stock"]
    for n, spec in ISLANDS.items():
        save("island%d.json" % n, build_layout(n, spec, base))
        save("quests%d.json" % n, build_quests(n, spec, base_q))
        save("monsters%d.json" % n, build_monsters(n, spec, base_m))
        rpg["shop"]["toko_p%d" % n] = {"title": "Toko %s" % spec["npcs"][8][1], "greet": "Selamat datang, {name}! Barang terbaik di %s." % spec["places"]["desa"],
                                       "stock": stock}
    save("rpg.json", rpg)
    isl = load("islands.json")
    for e in isl["islands"]:
        k = int(e["number"])
        e["available"] = True
        e["layout"] = "island%d.json" % k
        e["quests"] = "quests%d.json" % k
        e["monsters"] = "monsters%d.json" % k
        if k in ISLANDS:
            e["places"] = list(ISLANDS[k]["places"].values())[1:]
    save("islands.json", isl)
    # Paket visual 5.0: bangunan KayKit + dekorasi desa (idempoten, lihat sd_visual5.py).
    import runpy
    runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sd_visual5.py"))
    print("Pulau 2–6 dibuat: island/quests/monsters + toko; islands.json: semua pulau tersedia")


if __name__ == "__main__":
    main()
