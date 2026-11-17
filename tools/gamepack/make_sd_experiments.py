#!/usr/bin/env python3
"""Data Laboratorium Eksperimen IPA Petualangan Ilmu SD -> client/games/education_sd/data/experiments.json.

Tiga jenis percobaan (mesin: scripts/engine/experiment_engine.gd):
  uji      pilih benda -> tebak hasil -> lihat hasil + alasan            (items, labels)
  susun    susun bahan/urutan sampai benar                               (items = urutan benar)
  kondisi  atur variabel -> jalankan -> amati hasil tiap kombinasi       (vars, outcomes)
Alur tiap percobaan: masalah dari Profesor Kiko -> instruksi -> pilih & lakukan -> hasil -> penjelasan ilmiah -> 2 pertanyaan.
Fakta dijaga sederhana dan benar; penyederhanaan disebut terus terang ("dalam model sederhana ini").
Jawaban benar pilihan ganda ditulis pertama; game mengacak saat tampil.

Pakai:  python3 tools/gamepack/make_sd_experiments.py
"""
import itertools
import json
import os
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "client", "games", "education_sd", "data", "experiments.json")


def mc(q, correct, *wrong, explain):
    return {"type": "mc", "q": q, "options": [correct, *wrong], "answer": 0, "explain": explain}


def tf(q, ans, explain):
    return {"type": "tf", "q": q, "answer": ans, "explain": explain}


E = [
    {"id": "terapung", "title": "Terapung atau Tenggelam?", "grades": [1, 2, 3, 4], "kind": "uji", "visual": "tangki",
     "problem": "Perahu mainan Dodi tenggelam di sungai! Dodi bingung: mengapa ada benda yang terapung dan ada yang tenggelam?",
     "instruction": "Pilih satu benda, tebak dulu apa yang terjadi, lalu masukkan ke dalam bak air.",
     "labels": ["Terapung", "Tenggelam"],
     "items": [
         {"name": "batu kerikil", "result": 1, "why": "Batu lebih berat daripada air untuk ukuran yang sama, jadi tenggelam."},
         {"name": "gabus", "result": 0, "why": "Gabus sangat ringan dan berisi banyak rongga udara, jadi terapung."},
         {"name": "paku besi", "result": 1, "why": "Besi jauh lebih berat daripada air untuk ukuran yang sama. Paku kecil pun tenggelam."},
         {"name": "ranting kayu kering", "result": 0, "why": "Kayu kering lebih ringan daripada air untuk ukuran yang sama, jadi terapung."},
         {"name": "uang logam", "result": 1, "why": "Logam lebih berat daripada air untuk ukuran yang sama, jadi tenggelam."},
         {"name": "bola plastik berisi udara", "result": 0, "why": "Bola berisi udara sangat ringan untuk ukurannya, jadi terapung."},
     ],
     "science": "Benda terapung bila lebih ringan daripada air untuk ukuran yang sama (massa jenisnya lebih kecil daripada air). "
                "Jadi bukan besar atau kecilnya benda yang menentukan: paku kecil tenggelam, tetapi kapal besar terapung karena "
                "badannya berongga dan berisi udara.",
     "check": [
         tf("Benda yang besar pasti tenggelam.", False, "Salah. Kapal besar bisa terapung, sedangkan paku kecil tenggelam."),
         mc("Mengapa kapal besi yang besar bisa terapung?", "karena badannya berongga dan berisi udara", "karena besi lebih ringan daripada air",
            "karena air laut sangat dangkal", "karena kapal tidak punya berat",
            explain="Rongga berisi udara membuat kapal secara keseluruhan lebih ringan daripada air untuk ukurannya."),
     ]},
    {"id": "wujud", "title": "Es, Air, dan Uap", "grades": [1, 2, 3, 4], "kind": "kondisi", "need": 4,
     "problem": "Es batu untuk minuman Bu Wati hilang dari gelas, padahal tidak ada yang mengambil. Ke mana perginya?",
     "instruction": "Pilih bendanya dan pilih perlakuannya, lalu tekan Coba. Lakukan paling sedikit 4 percobaan berbeda.",
     "vars": [{"name": "Benda", "options": ["es batu", "air", "uap air"]}, {"name": "Perlakuan", "options": ["dipanaskan", "didinginkan"]}],
     "outcomes": {
         "0,0": {"result": "Es mencair menjadi air.", "why": "Panas mengubah benda padat menjadi cair. Peristiwa ini disebut mencair."},
         "0,1": {"result": "Es tetap padat.", "why": "Es sudah dingin dan padat. Didinginkan lagi, wujudnya tidak berubah."},
         "1,0": {"result": "Air berubah menjadi uap air.", "why": "Air yang dipanaskan terus berubah menjadi gas. Peristiwa ini disebut menguap."},
         "1,1": {"result": "Air membeku menjadi es.", "why": "Air yang didinginkan di lemari pembeku berubah menjadi padat. Peristiwa ini disebut membeku."},
         "2,0": {"result": "Uap air tetap berupa gas.", "why": "Uap air sudah berwujud gas. Dipanaskan lagi, wujudnya tidak berubah."},
         "2,1": {"result": "Uap air berubah menjadi titik-titik air.", "why": "Gas yang didinginkan berubah menjadi cair. Peristiwa ini disebut mengembun."},
     },
     "science": "Air punya tiga wujud: padat (es), cair (air), dan gas (uap air). Wujudnya berubah bila dipanaskan atau didinginkan: "
                "mencair, menguap, membeku, dan mengembun. Es Bu Wati tidak hilang; es itu mencair menjadi air karena udara di sekitarnya lebih hangat.",
     "check": [
         mc("Perubahan wujud dari cair menjadi padat disebut …", "membeku", "mencair", "menguap", "mengembun",
            explain="Contohnya air yang menjadi es di lemari pembeku."),
         tf("Es yang dipanaskan akan membeku.", False, "Salah. Es yang dipanaskan mencair menjadi air."),
     ]},
    {"id": "tanaman", "title": "Apa yang Dibutuhkan Biji untuk Tumbuh?", "grades": [1, 2, 3, 4], "kind": "kondisi", "need": 4,
     "problem": "Pak Budi menanam biji kacang hijau di empat pot. Ia ingin tahu apa saja yang dibutuhkan biji supaya tumbuh dengan baik.",
     "instruction": "Atur air dan cahaya untuk satu pot, lalu tekan Coba untuk melihat keadaannya setelah satu minggu. Coba keempat pot.",
     "vars": [{"name": "Air", "options": ["disiram", "tidak disiram"]}, {"name": "Cahaya", "options": ["kena cahaya matahari", "di tempat gelap"]}],
     "outcomes": {
         "0,0": {"result": "Biji tumbuh menjadi tanaman yang hijau dan kuat.", "why": "Air membuat biji mulai tumbuh, dan cahaya membantu daun membuat makanan."},
         "0,1": {"result": "Biji tumbuh, tetapi batangnya panjang, kurus, dan pucat kekuningan.",
                 "why": "Biji cukup air untuk tumbuh, tetapi tanpa cahaya daunnya tidak bisa membuat makanan dan tidak menjadi hijau."},
         "1,0": {"result": "Biji tidak tumbuh.", "why": "Tanpa air, biji tidak bisa mulai tumbuh walaupun ada cahaya."},
         "1,1": {"result": "Biji tidak tumbuh.", "why": "Tanpa air, biji tidak bisa mulai tumbuh."},
     },
     "science": "Biji membutuhkan air untuk mulai tumbuh (berkecambah). Setelah tumbuh, tanaman membutuhkan cahaya supaya daunnya hijau dan "
                "dapat membuat makanan sendiri. Tanaman yang tumbuh di tempat gelap menjadi panjang, kurus, dan pucat.",
     "check": [
         mc("Apa yang dibutuhkan biji agar mulai tumbuh?", "air", "pasir kering", "kegelapan", "angin kencang",
            explain="Pot yang tidak disiram tidak tumbuh, walaupun terkena cahaya."),
         tf("Tanaman yang tumbuh di tempat gelap menjadi hijau dan kuat.", False, "Salah. Tanpa cahaya, tanaman menjadi pucat, panjang, dan kurus."),
     ]},
    {"id": "rantai_makanan", "title": "Siapa Makan Siapa?", "grades": [3, 4, 5, 6], "kind": "susun",
     "problem": "Di sawah Pak Budi ada padi, tikus, ular, dan elang. Bagaimana mereka saling berhubungan?",
     "instruction": "Susun rantai makanan: mulai dari yang dimakan sampai pemangsa terakhir.",
     "order_label": "Dari yang dimakan ke yang memakan",
     "items": ["padi", "tikus", "ular", "elang"],
     "why": "Padi dimakan tikus, tikus dimakan ular, dan ular dimakan elang.",
     "science": "Rantai makanan menunjukkan perpindahan energi dari satu makhluk hidup ke makhluk hidup lain. Rantai selalu dimulai dari "
                "tumbuhan hijau (produsen) yang membuat makanan sendiri dengan bantuan cahaya Matahari. Hewan yang memakannya disebut konsumen.",
     "check": [
         mc("Rantai makanan selalu dimulai dari …", "tumbuhan hijau (produsen)", "hewan pemakan daging", "hewan paling besar", "burung elang",
            explain="Hanya tumbuhan hijau yang membuat makanan sendiri."),
         tf("Pada rantai padi → tikus → ular, ular adalah produsen.", False, "Salah. Produsennya padi; ular adalah konsumen."),
     ]},
    {"id": "energi", "title": "Sumber Energi untuk Desa", "grades": [3, 4, 5, 6], "kind": "uji",
     "problem": "Lampu-lampu desa membutuhkan listrik. Pak Lurah ingin memakai sumber energi yang tidak akan habis.",
     "instruction": "Pilih satu sumber energi dan tebak: terbarukan (selalu tersedia lagi) atau tidak terbarukan (bisa habis)?",
     "labels": ["Terbarukan", "Tidak terbarukan"],
     "items": [
         {"name": "cahaya Matahari", "result": 0, "why": "Matahari bersinar setiap hari. Panel surya mengubah cahayanya menjadi listrik."},
         {"name": "batu bara", "result": 1, "why": "Batu bara terbentuk selama jutaan tahun. Bila terus digali, lama-lama habis."},
         {"name": "angin", "result": 0, "why": "Angin selalu bertiup lagi. Kincir angin mengubah geraknya menjadi listrik."},
         {"name": "minyak bumi", "result": 1, "why": "Minyak bumi terbentuk selama jutaan tahun dan jumlahnya terbatas."},
         {"name": "air sungai yang mengalir", "result": 0, "why": "Air terus mengalir karena siklus air. Aliran air dapat memutar turbin pembangkit listrik."},
         {"name": "panas bumi", "result": 0, "why": "Panas dari dalam Bumi tersedia terus-menerus. Indonesia punya banyak sumber panas bumi."},
     ],
     "science": "Energi terbarukan berasal dari sumber yang selalu tersedia lagi di alam: Matahari, angin, air, dan panas bumi. "
                "Batu bara, minyak bumi, dan gas alam tidak terbarukan karena terbentuk sangat lama dan bisa habis. "
                "Menghemat listrik membantu menjaga sumber energi.",
     "check": [
         tf("Batu bara termasuk sumber energi terbarukan.", False, "Salah. Batu bara terbentuk jutaan tahun dan bisa habis."),
         mc("Manakah yang termasuk sumber energi terbarukan?", "angin", "minyak bumi", "batu bara", "gas alam",
            explain="Angin selalu tersedia lagi di alam."),
     ]},
    {"id": "penyaringan", "title": "Menjernihkan Air Keruh", "grades": [4, 5, 6], "kind": "susun",
     "problem": "Setelah hujan deras, air sungai desa menjadi keruh. Warga butuh air yang lebih jernih untuk mencuci.",
     "instruction": "Susun bahan penyaring di dalam botol dari lapisan paling ATAS sampai paling BAWAH.",
     "order_label": "Dari lapisan atas ke lapisan bawah",
     "items": ["kerikil", "pasir kasar", "pasir halus", "arang", "kapas"],
     "why": "Bahan yang kasar di atas menahan kotoran besar; semakin ke bawah bahannya semakin halus. Arang menyerap bau dan warna, "
            "dan kapas menahan butiran yang paling halus.",
     "science": "Saringan bertingkat menahan kotoran dari yang besar sampai yang halus, sehingga air menjadi lebih jernih. "
                "Tetapi air jernih belum tentu aman diminum: kuman tidak tersaring. Air harus dimasak sampai mendidih sebelum diminum.",
     "check": [
         tf("Air hasil saringan sederhana ini langsung aman diminum.", False, "Salah. Kuman belum hilang; air harus dimasak sampai mendidih."),
         mc("Apa tugas arang pada saringan air?", "menyerap bau dan warna", "menahan batu besar", "membuat air menjadi dingin", "menambah rasa manis",
            explain="Arang punya banyak pori kecil yang menyerap bau dan warna."),
     ]},
    {"id": "ekosistem", "title": "Keseimbangan di Sawah", "grades": [5, 6], "kind": "kondisi", "need": 3,
     "problem": "Di sawah hidup padi, tikus, ular, dan elang. Apa yang terjadi bila salah satunya hilang?",
     "instruction": "Pilih satu perubahan, lalu tekan Coba untuk melihat keadaan sawah beberapa bulan kemudian. Coba ketiganya.",
     "vars": [{"name": "Perubahan", "options": ["tidak ada perubahan", "semua ular ditangkap", "padi dan rumput habis"]}],
     "outcomes": {
         "0": {"result": "Jumlah padi, tikus, ular, dan elang tetap seimbang.", "why": "Setiap makhluk hidup mendapat cukup makanan, dan jumlah mangsa dijaga oleh pemangsanya."},
         "1": {"result": "Tikus bertambah sangat banyak dan memakan habis padi.", "why": "Tanpa ular, tidak ada yang cukup banyak memangsa tikus, sehingga tikus berkembang biak dengan cepat."},
         "2": {"result": "Tikus kelaparan dan berkurang; ular dan elang pun ikut berkurang.", "why": "Tanpa tumbuhan, tikus kehilangan makanan. Pemangsa tikus lalu kehilangan mangsanya."},
     },
     "science": "Dalam ekosistem, makhluk hidup saling bergantung. Dalam model sawah sederhana ini, hilangnya satu jenis makhluk hidup mengganggu "
                "yang lain. Karena itu kita tidak boleh memburu hewan liar sembarangan atau merusak tumbuhan.",
     "check": [
         mc("Jika semua pemangsa tikus hilang, jumlah tikus akan …", "bertambah banyak", "tetap sama", "langsung habis", "berubah menjadi ular",
            explain="Tidak ada lagi yang mengendalikan jumlah tikus."),
         tf("Makhluk hidup dalam satu ekosistem saling bergantung.", True, "Benar. Perubahan pada satu jenis memengaruhi jenis lainnya."),
     ]},
    {"id": "tata_surya", "title": "Urutan Planet", "grades": [5, 6], "kind": "susun",
     "problem": "Peta langit di observatorium berantakan! Bantu Profesor Kiko menyusun kembali delapan planet.",
     "instruction": "Susun planet dari yang paling dekat dengan Matahari sampai yang paling jauh.",
     "order_label": "Dari yang paling dekat dengan Matahari",
     "items": ["Merkurius", "Venus", "Bumi", "Mars", "Yupiter", "Saturnus", "Uranus", "Neptunus"],
     "why": "Urutannya: Merkurius, Venus, Bumi, Mars, Yupiter, Saturnus, Uranus, Neptunus.",
     "science": "Tata surya kita memiliki delapan planet yang mengelilingi Matahari. Empat planet terdekat (Merkurius, Venus, Bumi, Mars) "
                "berbatu; empat planet berikutnya (Yupiter, Saturnus, Uranus, Neptunus) jauh lebih besar. Bumi adalah planet ketiga.",
     "check": [
         mc("Planet ketiga dari Matahari adalah …", "Bumi", "Mars", "Venus", "Yupiter", explain="Urutannya: Merkurius, Venus, Bumi."),
         tf("Neptunus adalah planet yang paling jauh dari Matahari.", True, "Benar. Neptunus adalah planet kedelapan."),
     ]},
]


def validate():
    errs = []
    ids = set()
    for e in E:
        tag = e.get("id", "?")
        if tag in ids:
            errs.append(f"{tag}: id kembar")
        ids.add(tag)
        for f in ("title", "problem", "instruction", "science"):
            if not str(e.get(f, "")).strip():
                errs.append(f"{tag}: tanpa {f}")
        if not e.get("grades") or any(not 1 <= g <= 6 for g in e["grades"]):
            errs.append(f"{tag}: kelas tidak sah")
        k = e.get("kind")
        if k == "uji":
            if len(e.get("labels", [])) != 2 or len(e.get("items", [])) < 4:
                errs.append(f"{tag}: uji butuh 2 label dan >= 4 benda")
            for it in e.get("items", []):
                if it.get("result") not in (0, 1) or not it.get("why") or not it.get("name"):
                    errs.append(f"{tag}: benda tidak lengkap")
            if len({it["result"] for it in e.get("items", [])}) < 2:
                errs.append(f"{tag}: semua benda berhasil sama")
        elif k == "susun":
            if len(e.get("items", [])) < 3 or len(set(e["items"])) != len(e["items"]) or not e.get("why") or not e.get("order_label"):
                errs.append(f"{tag}: susunan tidak sah")
        elif k == "kondisi":
            vs = e.get("vars", [])
            combos = {",".join(map(str, c)) for c in itertools.product(*[range(len(v["options"])) for v in vs])}
            if not vs or combos != set(e.get("outcomes", {})):
                errs.append(f"{tag}: hasil tidak mencakup semua kombinasi")
            if not 2 <= e.get("need", 0) <= len(combos):
                errs.append(f"{tag}: need tidak sah")
            for o in e.get("outcomes", {}).values():
                if not o.get("result") or not o.get("why"):
                    errs.append(f"{tag}: hasil tanpa penjelasan")
        else:
            errs.append(f"{tag}: jenis {k}")
        if len(e.get("check", [])) < 2:
            errs.append(f"{tag}: pertanyaan evaluasi kurang dari 2")
        for q in e.get("check", []):
            if not q.get("explain") or not q.get("q"):
                errs.append(f"{tag}: pertanyaan tidak lengkap")
            if q["type"] == "mc" and (len(set(q["options"])) != 4 or q["answer"] != 0):
                errs.append(f"{tag}: pilihan tidak sah")
            if q["type"] == "tf" and not isinstance(q["answer"], bool):
                errs.append(f"{tag}: benar/salah tidak sah")
    for g in range(1, 7):
        if sum(1 for e in E if g in e["grades"]) < 3:
            errs.append(f"kelas {g}: kurang dari 3 eksperimen")
    return errs


def main():
    errs = validate()
    if errs:
        print("Data eksperimen TIDAK SAH:")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    for e in E:
        for i, q in enumerate(e["check"]):
            q["id"] = f"eks-{e['id']}-{i + 1}"
            q["grade"] = e["grades"][0]
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"schema": 1, "experiments": E}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"Eksperimen sah: {len(E)} -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
