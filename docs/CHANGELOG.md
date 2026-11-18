# CHANGELOG

Riwayat rilis sebelum v0.84.0 ada di pesan commit dan tag Git (`git log --oneline`).

## Server 0.85.3 — Naga Lava Lv2 & Lv3 bisa dikalahkan (19 November 2026)

Hanya server (tanpa paket game / APK baru). Laporan pemain: Naga Lava Lv2 di Gunung Berapi tidak pernah bisa dikalahkan.

- Penyebab: bos wilayah yang memburu (Gua Goblin, Gunung Berapi) diperkuat untuk pemain di atas level wilayahnya
  7% HP & 4% serangan per level, sampai 15 level (HP +105%, serangan +60%). Pahlawan level tinggi tidak bertambah kuat
  secepat itu. Simulasi pertarungan server dengan data akun level 61: Naga Lava Lv2 & Lv3 0 menang dari 20, bahkan
  dengan Hindar tepat waktu dan pedang terpasang (Lv1 ±45%). Bukan masalah posisi: simulasi gerak di klien menunjukkan
  pukulan selalu sampai (naga tidak terbang; posisinya di tanah).
- Perbaikan (`tahap.go`): `BossLevelHP` 2, `BossLevelAtk` 1, `BossLevelMax` 5 = paling banyak HP +10%, serangan +5%.
  Simulasi akun yang sama: Lv1 & Lv2 20/20 menang (±10 s & ±16 s), Induk Naga Lava ±60% menang dengan Hindar,
  ±25% tanpa. Hadiah tidak berubah.
- Uji: `TestGuaGoblinBossHunts` (+pemain level 61: HP bos ≤ +10%, serangan +5%); `go test ./...` LULUS.

## Paket adventure 1.3.0 + server 0.85.2 — hasil review The Last Dragon (18 November 2026)

Game lewat unduhan (tombol UPDATE di launcher), tanpa APK baru. Server di-restart (jumlah binatang Bab 1).
Laporan review & hasil: dokumen Project "Review The Last Dragon - 18 Nov 2026".

- **Istana Kegelapan & Ruang Takhta** (`istana_dekor.gd`, baru; hanya tampilan, petak/server sama): pilar berukir
  dengan kristal ungu melayang, tembok basal tinggi bergigi benteng, panji berlambang mata Malzareth, bibir batu di
  tepi lava, karpet merah-emas, lingkar pemanggilan Aldragor (cincin rune + 4 kristal), singgasana obsidian
  bertanduk di atas undakan, jendela ungu menyala di ruang takhta, sangkar sihir Elara (hanya langkah 10), siluet
  benteng & menara beratap runcing di cakrawala. Langit halaman selalu kelam (tidak ikut fajar/siang).
- **Tokoh cerita berpenampilan khusus** (Character Creator, warna di `LookBuild.NPC_COSM`, tidak butuh katalog
  server): Elara (model pemanah, rambut panjang, mahkota kecil, gaun hijau-emas, selendang, kalung, tanpa senjata),
  Kepala Desa (beruban & berjanggut, jubah bangsawan hijau, mantel merah, tongkat tetua), Malzareth (penyihir
  berkerudung, jubah panjang ungu gelap, mantel, hiasan bahu menyala, mata merah, tongkat kristal).
- **Gunung Berapi lebih berapi** (`gunung_dekor.gd`, baru): tanah abu vulkanik gelap, jalan kemerahan, tanah memerah
  di dekat lava, batu digelapkan jadi basal hangus, ±140 retakan lava menyala, lubang asap, tiga kerucut gunung
  berapi berkawah & beraliran lava di cakrawala; langit merah-jingga, malam tetap membara (bukan biru).
- **Hemat panggilan gambar** (`rakit.gd`, baru): hiasan Bab 3–4 dirakit jadi beberapa mesh berwarna titik
  (padat / rata / pendar / logam). Pi 5, Seimbang, panggilan gambar lama → baru: Desa 409 → 412, Gunung 276 → 285,
  Istana 199 → 192, Ruang Takhta 182 → 184; segitiga Gunung 57 → 70 rb, Istana 26 → 41 rb, Takhta 23 → 32 rb.
- **Bab 1 lebih singkat**: Hutan Binatang 15/30/45 binatang per tahap (dulu 25/75/100). Gua Goblin & Gunung Berapi
  tetap. Server: `HutanStageKills`, `TrialDef.Kills`, `StageNeedOn`, `BossReadyOn`; kemajuan lama yang melebihi
  angka baru langsung membuka bos. Klien: `Maps.stage_need`, dialog Kapten Rimba & papan misi ikut.
- **Adegan prolog bergambar** (`prolog_adegan.gd`, baru): pemain baru melihat 4 potongan 3D (±18 detik, tombol
  Lewati) sebelum layar teks prolog: Aldragor di langit senja, serbuan monster malam & rumah terbakar, Malzareth
  mengangkat Elara dalam bola sihir, penyihir lenyap saat pahlawan (berpenampilan pemain) mengejar.
- **Kamera tidak menembus bangunan** (`cam_clear.gd`, baru): kamera berhenti sebelum rumah, bangunan kecil, tembok
  & pilar istana (dulu separuh layar bisa gelap tertutup dinding rumah di Desa). Pohon & batu tidak dihitung.
- `docs/STORY.md` diselaraskan (Raja Orc Batu, alur & angka Bab 1, adegan prolog).
- `tests/shot.gd`: `SHOT_VIEW` (kamera bebas), `SHOT_PROLOG` (gambar tiap potongan adegan prolog).

## Paket adventure 1.2.0 + server 0.85.1 — serbuan monster: radar otomatis, binatang tulang, penjaga ikut bertarung (17 November 2026)

Game lewat unduhan (tombol UPDATE di launcher), tanpa APK baru. Server di-restart (musuh baru + luka penjaga).

- **Radar serbuan otomatis**: selama serbuan di Desa Awal radar muncul sendiri (tanpa barang Radar) dan hanya
  menunjukkan penyerbu; setelah semua penyerbu kalah radar hilang sendiri, papan berubah "DESA AMAN!".
- **Serbuan terbatas**: total penyerbu = 5 (sama dengan syarat hadiah). Setelah 5 dikalahkan pahlawan tidak ada
  penyerbu baru; masuk lagi ke desa di malam yang sama tidak memunculkan penyerbu.
- **Binatang tulang dari hutan** ikut menyerbu: Rubah Tulang (Lv1), Babi Tulang (Lv2), Serigala Tulang (Lv3),
  Beruang Tulang (Lv5) — model kerangka Gua Goblin, versi desa lebih lemah. Server: `*_tulang_penyerbu` di
  `enemy.go` (Raid, malam, Desa Awal). Papan & pemberitahuan: "SERBUAN MONSTER!".
- **Penjaga desa ikut bertarung** (Penjaga, Damar, Pak Joko, Laras): berjaga di luar sepanjang serbuan walau malam,
  mendekati penyerbu dalam 9 petak dari posnya (Laras memanah dari tempatnya, jangkauan 7,5), menahan dan melukai
  penyerbu tiap 2,2 detik. Penjaga TIDAK bisa mengalahkan penyerbu: tiap luka = -15% HP awal, maks. 3 luka
  (HP awal >= 55%), hanya pahlawan yang bisa mengalahkan. Server: `POST /v1/battle/start` menerima `wounds`;
  `Battle.GuardWounds` hanya berlaku untuk penyerbu, di Desa Awal, selama serbuan, dan dibatasi.
- Uji: `client-test` 1175 ok (+radar muncul/hilang, model penyerbu, penjaga mendekat & menyerang, luka maks tanpa
  mengalahkan, serbuan terbatas, papan desa aman); Go: `TestRaidBonesAndGuardWounds`,
  `TestRaidGuardWoundsBattleStart` (HTTP). `tests/shot.gd`: `SHOT_EVENT`.

## Paket adventure 1.1.0 — tanah & rumput lebih hidup (17 November 2026)

Lewat unduhan (tombol UPDATE di launcher), tanpa APK baru.

- `games/adventure/scripts/ground_fx.gd` (baru), dipakai Desa Awal, Perbatasan, Hutan Binatang. Hanya tampilan:
  petak, jalan, tabrakan, data server tidak berubah (tanah tetap datar).
- Tanah: satu shader untuk petak rumput/jalan/pasir. Jenis petak dari tekstur kecil (1 piksel = 1 petak) + derau →
  tepi jalan tanah berkelok alami dengan pinggiran rumput lebih gelap, rumput dua nada berbercak + bercak kering,
  lantai hutan lebih gelap di bawah pohon, pasir tepi air menyatu, bintik kelopak bunga (tanpa geometri).
- Rumput: rumpun helai gaya Petualangan Ilmu SD (terang ke ujung, bergoyang, ikut angin hujan), mengecil lalu hilang
  di kejauhan; rumput yang bisa dipukul tetap (bentuk baru). Rumput hias tambahan per petak: Hemat 0,8 / Normal 1,8 /
  Tinggi 2,8, jarak 18 / 26 / 36 m, sel 12 m dengan batas jarak gambar. Bunga berkelompok, 6 warna.
- Diukur di Pi (llvmpipe, 3 titik × 3 profil): panggilan gambar +2–5 %, segitiga +0–10 % dibanding sebelumnya.
- Alat: `tests/shot.gd` menerima `SHOT_HOUR` (jam dunia tetap) dan `SHOT_STATS` (cetak angka render).
- Uji: `client-test` 1162 ok.

## v0.85.0 — The Last Dragon jadi game unduhan (17 November 2026)

**Butuh APK baru sekali.** Setelah itu pembaruan The Last Dragon cukup diunduh dari launcher (tombol UPDATE),
seperti Petualangan Ilmu SD — termasuk gambar, font, dan model, bukan hanya kode.

- Isi The Last Dragon dipindah ke `client/games/adventure/` (52 skrip, 10 adegan, gambar item & wajah NPC, font,
  gambar judul, ikon, model alam). Jalur `res://` di semua skrip, adegan, uji, alat Go/Python diperbarui
  (`make maps` membaca `client/games/adventure/scripts/maps.gd`).
- `config/games.json` kosong: tidak ada lagi game bawaan. The Last Dragon tampil di launcher dari katalog server
  (`adventure` 1.0.0, ±3,5 MB, ikon bertanda tangan), tombol DOWNLOAD saat pertama, lalu MAINKAN/UPDATE/HAPUS.
  Progres The Last Dragon tetap di server (akun), jadi menghapus/mengunduh ulang tidak menghilangkan apa pun.
- Tetap di APK (platform): autoload Api/Session/Sound/Patcher, launcher, `core/`, `shared/`, model karakter
  `assets/models/*.glb` (dipakai juga SD), ikon aplikasi, musik. `models.gd` memakai model di paket bila ada
  (`games/adventure/assets/models/`), jadi model baru/perbaikan model tetap bisa lewat unduhan.
- `class_name ClockBadge/MenuBubble` diganti `preload` (kelas global dari paket tidak terdaftar di APK).
- `gamepack.py`: `background_music` ikut katalog (musik desa berbunyi selama The Last Dragon aktif).
- APK lama (≤ 0.84.6) tetap memakai The Last Dragon bawaannya; entri katalog `adventure` diabaikan di sana.
- Uji: `client-test` 1162 ok; `platform-test` semua fase LULUS (+The Last Dragon tidak ada di APK, unduh, pasang,
  buka dari PCK, aset/font/model alam termuat dari paket, model karakter dari APK, hapus & pasang ulang,
  tersedia offline); bukti visual: layar judul & dunia 3D dari paket di salinan proyek tanpa `games/`.

## Launcher 0.84.6 (patch, tanpa APK baru) — 17 November 2026

- Tombol **Pengaturan** pindah dari pojok kanan atas ke bawah daftar game (di bawah kartu terakhir), selebar kartu,
  dengan **ikon roda gigi** (digambar lewat kode, jadi ikut patch). Bila ada APK baru: ikon & teks berwarna kuning
  ("Pengaturan · ada update aplikasi").
- Halaman Pengaturan launcher kini berisi berurutan: **Akun** (tab Masuk / Daftar; bila sudah masuk: nama akun +
  "Keluar dari akun ini"), **Server** (alamat + Tes & simpan), **Pembaruan aplikasi** (periksa, unduh & pasang APK).
  Akun memakai token yang sama dengan The Last Dragon (Session), jadi sekali masuk berlaku untuk semua game; progres SD/SMP
  yang menunggu langsung disinkronkan. Token yang dicabut/kedaluwarsa dideteksi saat Pengaturan dibuka. Kata sandi tidak
  disimpan. Isian bergeser di atas papan ketik HP.
- Uji: `platform-test` +9 pemeriksaan (posisi & ikon tombol, daftar, ulangan sandi beda ditolak, keluar, sandi salah
  ditolak, masuk).

## Paket education_sd 5.2.0 — Prioritas 4–8 + perapian (17 November 2026)

Berisi sistem adaptif (Prioritas 4, di bawah) dan:

- **Soal cerita matematika** (`sd_gen.gd`, Prioritas 5): bentuk baru `story_add`, `story_sub` (cerita mendapat/memberikan
  benda), `money` (uang kembalian, satu atau beberapa barang), `clock` (pukul berapa / berapa lama), `fpb`, `kpk`,
  `mixed` (operasi campuran: kali dulu). Kesulitan 2, pengecoh diagnostik (operasi tertukar, lupa kali dulu, harga satuan
  sebagai kembalian). Terpasang di 16 spesifikasi bank (penjumlahan/pengurangan kelas 1–3, uang kelas 5–6, jam kelas 2–3,
  FPB/KPK kelas 5–6, operasi campuran kelas 5–6).
- **Laporan belajar** (Prioritas 6): tabel SEMUA materi per mata pelajaran untuk kelas yang paling banyak dikerjakan
  (status, jumlah soal, persen benar bila >= 5 soal), **saran materi berikutnya** (maks 3, yang perlu dilatih dulu, tersebar
  ke mapel berbeda, dengan alasan), **perkembangan mingguan** (4 minggu dari catatan harian), riwayat 12 entri.
- **Mini-game tersambung** (Prioritas 7): keempat permainan yang sebelumnya tidak bisa dimainkan kini ada di ruang kelasnya
  (Pintu Kode Angka — Matematika, Huruf yang Hilang — Bahasa, Kelompokkan Hewan — Lab IPAS, Pasangan Nusantara — Balai
  Sosial). Hasil tercatat (`academy["mini/…"]`: main, nilai terbaik) + hadiah kecil; hewan yang dikenali masuk koleksi.
- **Laboratorium Eksperimen IPA** (Prioritas 8): 8 percobaan (`data/experiments.json`, dibuat
  `tools/gamepack/make_sd_experiments.py` dengan validasi) — terapung/tenggelam, es-air-uap, kebutuhan biji tumbuh, rantai
  makanan, sumber energi, penyaringan air, keseimbangan ekosistem sawah, urutan planet; >= 3 percobaan per kelas.
  Alur sesuai rancangan: masalah dari NPC -> instruksi (bisa dibacakan) -> pilih alat/benda -> lakukan (tebak & uji,
  susun, atau atur variabel) -> hasil + alasan -> penjelasan ilmiah -> 2 pertanyaan evaluasi. Tebakan salah tidak dihukum.
  Penyederhanaan disebut terus terang; air saringan diingatkan tetap harus dimasak. Mesin: `experiment_engine.gd`,
  tampilan: `ui/experiment_view.gd` (bak air beranimasi untuk terapung/tenggelam).
- **Perapian** (Prioritas 10): `w3d_missions.gd` (tidak dirujuk di mana pun) dihapus. Berkas w3d 2.x lain tetap karena
  masih dimuat `w3d_world.gd`; `data/course.json` tetap karena ditulis `make_courses.py` yang juga dipakai SMP.
- Uji: `sd_test.gd` 887 pemeriksaan (+35): 660 soal cerita dihitung ulang mandiri, laporan, mini-game lewat ruang kelas,
  setiap percobaan bisa diselesaikan, alur laboratorium penuh lewat tampilan.
- Belum: pengukuran FPS/RAM di HP (Prioritas 9) butuh perangkat Android.

## Sistem pembelajaran adaptif SD — Prioritas 4 (17 November 2026)

Belum diterbitkan (paket tetap 5.1.0). Progres lama tetap terbaca; field adaptif dilengkapi otomatis dari riwayat lama.

- **`scripts/engine/adaptive.gd` (baru)**: semua aturan adaptif di satu modul murni yang transparan dan diuji. Aturan
  berurutan dengan data minimal yang jelas (lihat kepala berkas):
  A. keluar dari mode "mudah" setelah >= 5 jawaban dan 3 dari 5 benar; B. < 5 jawaban: tidak ada perubahan;
  C. level 3 + >= 8 jawaban + >= 85% benar: mode "tantang" + 1 soal **pengayaan** kelas berikutnya;
  D. 4 dari 5 benar: **kesulitan naik satu level** (1 -> 2 -> 3, tidak melompat); E. level > 1, >= 6 jawaban, < 40%:
  **kesulitan turun satu level, kelas tetap**; F. level 1, **>= 8 jawaban**, < 40%: soal kelas lebih rendah (konsep sama).
  Dulu kelas turun setelah 4 jawaban dan tidak ada tingkat kesulitan bertahap.
- **Jenis kesalahan**: jawaban salah PERTAMA anak kini dikirim tampilan soal (`first_wrong`) dan dicatat
  (`mistakes`): lupa menyimpan/meminjam (nilai tempat), operasi tertukar, meleset sedikit, hitung lain, benar/salah,
  konsep. Bila jenis yang sama muncul >= 2 kali, latihan berikutnya menampilkan saran singkat yang ramah.
- **Pengecoh diagnostik** (`sd_gen.gd`): soal penjumlahan bersimpan selalu memuat jawaban "lupa menyimpan"
  (27 + 15 -> 32); pengurangan meminjam memuat jawaban "salah meminjam" (42 − 15 -> 33); juga hasil operasi tertukar.
- **Latihan penguatan**: Jurus Ilmu memilih topik dengan bobot (perlu latihan 4, sedang dipelajari 3, baru 2,
  dikuasai 1), sehingga topik lemah lebih sering diulang dengan soal berbeda (`Learning.pick_topic`).
- **Pemilihan soal**: belum dilihat dulu, lalu tingkat kesulitan terdekat dengan level sasaran. Ujian tanpa sasaran level.
- Uji: `sd_test.gd` 852 pemeriksaan (+43): setiap aturan A–F termasuk batas data (7 vs 8 jawaban), satu jawaban salah di
  posisi mana pun tidak pernah menurunkan kelas, simulasi 12 acakan per tipe anak (95% benar: level naik bertahap sampai 3;
  15% benar: dibantu soal mudah, tidak pernah sebelum 8 jawaban; 70% benar: 119/120 latihan tetap di kelasnya), jenis
  kesalahan, pengecoh diagnostik (200 soal), pengayaan, pilihan topik berbobot, save lama. 6 uji lama disesuaikan karena
  aturan lama (turun kelas setelah 4 jawaban, langsung "tantang") memang diganti.

## Paket education_sd 5.1.0 — terbit (17 November 2026)

Berisi Prioritas 1–3 di bawah: pemeriksa bank soal, bank soal 802 soal dengan kompetensi CP, dan perbaikan bug Learning
Engine. Tanpa APK baru (launcher 0.84.x cukup); di HP cukup buka launcher lalu perbarui game. Progres anak tetap.

## Perbaikan bug Learning Engine SD — Prioritas 3 (17 November 2026)

Tiga bug dari audit Fase A. Tanpa perubahan data soal; progres lama tetap terbaca (tanpa naik versi paket).

- **Petunjuk kosong** (`sd_question.gd`): bila kolom `hint` ada tetapi kosong, tombol Petunjuk dulu menampilkan pesan kosong
  (soal Benar/Salah, dan pilihan ganda setelah pengecoh habis disembunyikan). Kini memakai kalimat bawaan.
- **Urutan soal mode "tantang"** (`sd_data.gd` `pick`): dua `sort_custom` berturut-turut — sort kedua (kesulitan) tidak
  stabil dan menimpa urutan "belum dilihat", sehingga soal yang sudah dilihat bisa didahulukan. Kini satu urutan gabungan:
  belum dilihat dulu, lalu (mode tantang) soal sulit dulu.
- **Penguasaan dari soal kelas lain** (`learning_engine.gd`): pada mode "mudah" soal diambil dari kelas lebih rendah, tetapi
  jawabannya ikut dihitung untuk status "dikuasai" kelas yang sedang dipelajari. Kini statistik punya `recent_own`
  (hanya soal kelas itu sendiri) untuk status penguasaan & laporan; `recent` (semua jawaban) tetap dipakai adaptasi.
  Data lama tanpa `recent_own`: riwayat lama disalin saat jawaban berikutnya, sehingga status lama tidak tiba-tiba hilang.
- Uji: `sd_test.gd` +13 pemeriksaan (809 total). Dibuktikan gagal pada kode lama (3 uji GAGAL + galat skrip) dan lulus pada
  kode baru. Dua uji lama yang menyusun statistik langsung disesuaikan agar mengisi `recent_own` juga (maksud uji sama).

## Bank soal SD diperkaya — Prioritas 2 (17 November 2026)

Data soal saja (gameplay, progres, dan versi paket tidak berubah; paket belum diterbitkan ulang).

- **328 → 802 soal** (+474) di `tools/gamepack/sd_bank_more.py`, ditambahkan SETELAH soal lama sehingga **ID soal lama
  tidak berubah** (diverifikasi: 328 ID lama ada semua, topik/kelas/tipe/kunci sama). Setiap topik × kelas tanpa pembuat
  soal kini punya **6 soal** (sebelumnya 124 dari 169 kurang dari 5; 23 hanya 1 soal).
- **Kompetensi** di setiap soal (`competency`), dari tabel topik × fase yang dipetakan ke elemen Capaian Pembelajaran
  Keputusan Kepala BSKAP No. 046/H/KR/2025 (Fase A kelas 1–2, B kelas 3–4, C kelas 5–6). Soal IPA/IPS kelas 1–2 diberi
  label "pengenalan lingkungan (Fase A, terpadu)" karena IPAS baru menjadi mata pelajaran mulai kelas 3. Materi IPAS
  kelas 3–6 diselaraskan dengan daftar bab buku teks IPAS Kurikulum Merdeka (buku.kemdikbud.go.id).
- **Kesulitan per soal** 1–3 (sebelumnya hanya dari tipe soal; tidak ada soal statis level 3): kini 591 / 184 / 27.
- **Benar/Salah seimbang** per mapel (mis. Pancasila 14:1 → 38:24; Bahasa, Seni, PJOK sebelumnya tanpa jawaban Salah).
- **Petunjuk kosong** tidak lagi ditulis ke data (210 soal); game memakai petunjuk bawaannya. Petunjuk teks nyata di 7 soal baru.
- Soal lama dirapikan tanpa memindah posisi: 8 penjelasan terlalu singkat, 16 soal yang jawabannya ketahuan karena paling
  panjang (pengecoh disamakan panjangnya), `hidup_sehat-1-02` ("kuman hilang" → "membantu membuang kuman"),
  `olahraga-2-02` (pengecualian penjaga gawang), penjelasan bunglon/mimikri.
- `make_sd_bank.py`: helper soal menerima `hint`, `diff`, `competency`; validasi baru: kompetensi wajib, kesulitan 1–3,
  minimal 5 soal per topik × kelas, pilihan kembar beda spasi. Pemeriksa bank: pilihan kembar kini peka huruf besar
  (soal huruf kapital membedakan "Adik" dan "adik").
- Pemeriksa kualitas: **0 galat, 0 peringatan** (sebelumnya 696 peringatan). `sd_test.gd` +10: peringatan cakupan,
  kompetensi, petunjuk kosong, penjelasan minim, B/S timpang, kesulitan datar, soal kembar, kalimat negatif kini wajib 0.
- Catatan jujur: kompetensi adalah ringkasan penyusun yang dipetakan ke elemen CP, bukan kutipan resmi. Fakta dipilih yang
  stabil dan diperiksa, tetapi seluruh soal baru tetap perlu ditinjau guru sebelum dianggap final.

## Pemeriksa kualitas bank soal SD — Prioritas 1 (17 November 2026)

Hanya alat uji; tidak mengubah gameplay, data soal, progres, atau paket yang sudah terbit (tanpa naik versi).

- **`client/games/education_sd/scripts/engine/bank_audit.gd`** (baru): memeriksa bank soal dalam dua tingkat.
  *Galat* (harus 0): data tidak lengkap, struktur tidak sah, ID kembar, topik tidak dikenal, mata pelajaran tidak
  cocok dengan topik, kelas di luar kelas topik, kesulitan bukan 1–3, pilihan kembar (beda huruf besar/spasi),
  **kunci hitungan salah** (soal "A op B = …", "A op ___ = C", "___ op B = C" dihitung sendiri).
  *Peringatan pedagogis* (daftar kerja, tidak menggagalkan): cakupan topik×kelas < 5 soal tanpa pembuat soal,
  tanpa kompetensi, petunjuk kosong, penjelasan terlalu singkat, kalimat terlalu panjang untuk kelasnya, kalimat
  negatif di kelas 1–2, jawaban benar jauh lebih panjang dari pengecoh, pilihan "semua benar", isi soal kembar,
  jawaban Benar/Salah timpang, kesulitan datar per mata pelajaran.
- **`client/tests/sd_bank_report.gd`** (baru): laporan lengkap per soal + tabel cakupan topik×kelas
  (`godot --headless --path client -s res://tests/sd_bank_report.gd`; exit 1 bila ada galat).
- **`client/tests/sd_test.gd`**: +28 pemeriksaan (bank terbit 0 galat; setiap jenis galat & peringatan terdeteksi
  pada soal rusak buatan; 14 bentuk soal hitungan; 960 soal buatan pembuat soal lolos pemeriksa).
- Garis dasar bank saat ini: 328 soal, **0 galat**, 696 peringatan (328 tanpa kompetensi, 210 petunjuk kosong,
  124 topik×kelas tipis, 16 jawaban terpanjang, 8 penjelasan minim, 6 mapel Benar/Salah timpang, 4 mapel kesulitan
  datar). Pemeriksa tidak bisa memastikan fakta non-hitungan atau kesesuaian kurikulum resmi; itu tetap ditinjau guru.

## Paket education_sd 5.0.0 — Paket visual 5.0: dunia 3D lebih indah & hidup (17 November 2026)

Tanpa APK baru (launcher 0.84.x cukup); paket diunduh ulang dari server. Gameplay, data misi, NPC, progres tidak berubah.

- **Medan baru** (`w3d_terrain.gd`): tanah bergelombang lembut di alam liar, gundukan di tepi pulau, alur sungai
  yang menurun, pantai pasir melandai ke laut. Jalan tanah & pelataran bata dicat langsung di permukaan (tepi
  organik, batu kecil di tepi jalan). Bukit lama tetap persis; jalan, tempat & bangunan diratakan. Tabrakan memakai
  HeightMapShape3D 1 m.
- **Air**: laut bergradasi dalam–dangkal dengan buih di garis pantai & riak (shader); sungai mengalir dengan buih tepi.
  Jembatan papan baru dengan pagar & tiang, teratai di sungai.
- **Flora**: rumput & bunga berkelompok (MultiMesh per petak 16 m, mengecil halus di kejauhan, ditanam bertahap
  supaya pulau cepat terbuka), daun pohon bergoyang + variasi warna per pohon. Perbaikan: jenis pohon ganda di
  pulau 2 & 6 dulu digambar dua kali.
- **Hidup**: awan berarak, burung & camar berputar, kupu-kupu di padang bunga, ayam mematuk di ladang/desa,
  serbuk sari melayang — semua animasi di GPU (tanpa beban CPU per bingkai).
- **Pencahayaan**: cahaya ambien langit, cahaya isi tanpa bayangan, bayangan lebih lembut, kabut warna cakrawala,
  dan suasana khas tiap pulau (pagi cerah, hutan berkabut hijau, siang keemasan, tropis, sore hangat, senja naga).
- **Bangunan**: akademi menjadi kastel, rumah beratap warna khas tiap pulau, warung, kincir angin, sumur, lumbung,
  tong/peti/karung, bendera (KayKit Medieval Hexagon Pack, CC0). Rumah adat pertama tiap desa dipertahankan;
  Rumah Gadang & Tongkonan dibuat ulang dengan atap melengkung khas. Ciri tiap pulau: patung angka & menara
  (Kerajaan Angka), mikroskop/globe/tenda (Negeri Penemuan), pandai besi (Kerajaan Ksatria), tambang (Pulau Naga),
  hutan lebih lebat (Hutan Rahasia).
- **Akademi**: lantai papan kayu (shader), karpet, panel kayu dinding, lampu gantung hangat.
- **Profil grafis**: Hemat (medan 2 m, ±4.000 rumpun rumput, tanpa animasi air/daun), Seimbang (1,5 m, ±12.000),
  Tinggi (1 m, ±20.000, rumput terlihat sampai 40 m).
- Uji: SD 758 pemeriksaan LULUS, uji platform LULUS. Waktu bangun pulau di Raspberry Pi 5: ±450 ms
  (sebelumnya ±270 ms; rumput ditanam setelah pulau tampil). FPS di HP belum diukur.

## v0.84.5 + paket education_sd 4.2.0 — Pengaturan launcher, pilihan suara & lagu, resolusi 3D (17 November 2026)

- **Launcher: tombol Pengaturan** (berlaku untuk semua game): alamat server + "Tes & simpan" (alamat disimpan bila
  terjangkau, katalog dimuat ulang) dan **Pembaruan aplikasi** (versi terpasang vs terbaru dari server, unduh & pasang
  APK lewat Updater yang sama). Saat launcher dibuka, versi diperiksa diam-diam: tombol menjadi "Pengaturan (ada update)".
- **The Last Dragon:** isian alamat server dan tombol pembaruan APK dihapus dari Pengaturan (dipindah ke launcher).
  Yang tersisa: status server (centang hijau), akun, layar & suara. Pesan "server belum terhubung"/"wajib update"
  kini menunjuk ke Pengaturan launcher. Uji e2e disesuaikan.
- **Petualangan Ilmu SD 4.2.0:**
  - Suara pembaca bisa diatur orang tua: pilihan suara (semua suara bahasa Indonesia di HP; suara "perlu internet"
    ditandai), kecepatan (Pelan/Sedang/Normal/Cepat), nada (Rendah/Normal/Tinggi), tombol "Coba suara".
  - Pilihan lagu: Petualang Riang, Pulau Ceria, Ombak Tenang (ciptaan sendiri) dan lagu anak domain publik
    instrumental: Bintang Kerlip (Twinkle Twinkle), Domba Kecil (Mary Had a Little Lamb), Bangun Pagi (Frère Jacques),
    Lagu Gembira (Ode to Joy, Beethoven); "Acak" memutar bergantian. Dibuat dengan kode di utas latar (tanpa berkas).
  - **Resolusi 3D**: dunia 3D kini digambar pada piksel layar sungguhan (dulu pada kanvas 1280×720 yang lalu diperbesar
    dan diperkecil lagi oleh skala grafis — di HP beresolusi tinggi gambar jadi buram dan warnanya pudar).
    Pilihan Rendah (540p) / Sedang (720p, bawaan) / Tinggi (1080p); "Efek grafis" (Hemat/Seimbang/Tinggi) terpisah.
  - Halaman Pengaturan bisa digulir dan dikelompokkan: Musik & suara, Suara pembaca, Tampilan.
- Server 0.84.5: versi klien terbaru 0.84.5.

## v0.84.4 + paket education_sd 4.1.0 — suara pembaca untuk kelas 1–2 (16 November 2026)

- APK 0.84.4: `audio/general/text_to_speech` dinyalakan di `project.godot` supaya game bisa memakai mesin suara
  bawaan HP (TTS Android). Pengaturan mesin hanya dibaca saat aplikasi mulai, jadi **perlu APK baru** (paket saja
  tidak cukup). The Last Dragon tidak berubah.
- Paket education_sd 4.1.0 (Petualangan Ilmu SD): pesan penduduk, misi, papan, hadiah, cerita, toast, materi akademi,
  cerita tantangan, soal + pilihan jawaban, dan umpan balik dibacakan. Penduduk/guru tampil sebagai potret 3D yang
  bergerak saat berbicara; pesan tanpa penduduk dibacakan Bu Guru. Kata yang sedang dibaca disorot kuning.
  Tombol "Dengar" untuk mengulang. Pengaturan "Suara pembaca": Otomatis kelas 1–2 (bawaan) / Selalu / Mati,
  plus "Coba suara" dan petunjuk bila suara bahasa Indonesia belum terpasang di HP.
- APK lama tetap bisa memainkan paket 4.1.0 (tanpa suara; Pengaturan menyarankan memperbarui aplikasi).
- Server 0.84.4: versi klien terbaru 0.84.4 (pengingat pembaruan di launcher).

## v0.84.3 — ikon game unduhan di launcher (15 November 2026)

- Server: `GET /v1/games/{id}/icon` melayani `icon.png` dari katalog (hanya PNG ≤ 1 MB, id tervalidasi).
- `gamepack publish`: bila `game.json` punya `icon` (PNG di `res://games/<id>/`), ikon disalin ke katalog dan
  `icon_sha256` dimasukkan ke manifest & katalog yang ditandatangani.
- Launcher (APK 0.84.3): kartu & detail game unduhan menampilkan ikon walau paket belum dipasang — ikon diunduh,
  diverifikasi dengan `icon_sha256`, disimpan di `user://icons/` (tetap tampil offline). Ikon `res://` bawaan
  tetap dipakai lebih dulu; tanpa ikon tetap memakai inisial.
- Paket education_sd 2.4.3 diterbitkan ulang dengan ikon. Uji: `go test ./...`, `make client-test`,
  `make platform-test` (+4 pemeriksaan ikon), `make sd-test` (610) lulus.

## Paket education_sd v2.4.2 — ikon game (15 November 2026)

- Ikon "Petualangan Pulau Ilmu SD" (gambar dari pengguna) di `assets/icon/sd_icon_512.png` & `sd_icon_192.png`,
  tampil di beranda dan layar pengenalan; `game.json` mencantumkan `icon` dan katalog kini meneruskan kolom itu.
- Catatan: kartu launcher APK 0.84.x hanya bisa memuat ikon `res://` yang sudah ada saat itu, jadi ikon game unduhan
  baru tampil di kartu setelah paketnya dimuat (setelah dimainkan sekali per sesi). Supaya selalu tampil, launcher
  perlu membaca ikon dari paket/servernya (perubahan APK).

## Paket education_sd v2.4.1 — warna petualangan & bangunan GLB (15 November 2026)

- Warna tidak lagi pucat/terlalu terang: cahaya matahari & ambien diturunkan, ACES white 6, kontras & saturasi,
  tanah/jalan/langit lebih pekat, pantulan specular rendah.
- 11 bangunan GLB buatan sendiri (gua, menara bertangga, perpustakaan, museum, lab, kios pasar, Rumah Gadang,
  Joglo, Tongkonan, mercusuar, observatorium); tangga Menara Matematika bisa dinaiki ke balkon.

## Paket education_sd v2.4.0 — Fase 9–10: pahlawan 3D & aset lingkungan (15 November 2026)

- Model pahlawan anak laki-laki & perempuan GLB buatan sendiri (CC0): kerangka sama 20 tulang, 12 animasi (idle,
  walk, run, jump, fall, land, interact, wave, celebrate, turn, hit, equip), kostum & topi menempel di tulang.
- Aset lingkungan GLB buatan sendiri: 3 jenis pohon, semak, bunga, 2 batu, patung matematika, buku besar,
  mikroskop, globe, papan informasi, lampu jalan; Istana Angka & rumah lokasi lebih detail.
- Rincian: [SD_PULAU_ILMU_3D.md](SD_PULAU_ILMU_3D.md).

## Paket education_sd v2.3.0 — semi-realistis & kamera 360° (15 November 2026)

- Kamera orang-ketiga bebas 360°: batas vertikal, mengikuti halus, tidak menembus pagar/bangunan/pohon, zoom
  (scroll / cubit dua jari), multisentuh gerak + kamera.
- Karakter semi-realistis (proporsi natural, siku & lutut, transisi animasi halus, topi & aksesori 3D) + pilihan
  karakter Petualang (model KayKit).
- Pengacau Lupa (patroli, kejar, soal cepat untuk menjinakkan) dan Penjaga Wilayah berpola (berjaga, hentakan, lelah).
- Alat petualangan dari misi (Kompas, Kaca Pembesar, Senter, Teropong, Sepatu, Jaring) dan TAS; lingkungan lebih
  kaya (batu, rumput, bunga, kabut, landmark). Rincian: [SD_PULAU_ILMU_3D.md](SD_PULAU_ILMU_3D.md).

## Paket education_sd v2.2.0 — Pulau Ilmu 3D Fase 3–8 (15 November 2026)

- 20 lokasi baru (5 per pulau) dengan teka-teki, warga, museum kartu, hewan, dan mini-game; labirin, jembatan angka,
  tata surya, danau, pasar, museum, dan lainnya.
- Sistem misi: utama, sampingan, teka-teki, warga, eksplorasi, cari benda (5 per pulau), harian — hadiah sekali.
- NPC, warga, penjaga wilayah, dan hewan memakai model GLB KayKit (CC0) yang ada di APK.
- Dunia hidup: warga berjalan, hewan, burung, ikan, pohon & air bergerak, siang-malam, hujan, suara lingkungan.
- Markas Pemain: galeri hewan 3D, museum kartu, lemari kostum, cermin karakter, piala, Buku Petualangan.
- Info kinerja di HP dan penggabungan mesh (draw call −35%). Rincian: [SD_PULAU_ILMU_3D.md](SD_PULAU_ILMU_3D.md).

## Paket education_sd v2.1.0 — Pulau Ilmu 3D (Fase 1–2) (15 November 2026)

- Mode baru "JELAJAHI PULAU 3D" di beranda: karakter 3D (laki-laki/perempuan) dengan kamera orang-ketiga,
  joystick + geser kamera + tombol AKSI/LOMPAT/LARI di HP, WASD/mouse di desktop.
- Empat pulau 3D bertema (Kerajaan Matematika, Hutan Bahasa, Laboratorium IPA, Negeri Penjelajah IPS): gerbang dan
  jembatan rusak per area yang terbuka dengan menjawab soal, NPC pemandu, Peti Pengetahuan (kuis ≥ 70), Penjaga
  Wilayah (ujian akhir), kios mini-game, portal antarpulau, tempat rahasia.
- Semua materi, penilaian, dan hadiah memakai sistem lama; mode 2D tetap ada. Profil grafis Hemat/Seimbang/Tinggi.
- Rincian audit, rancangan, dan hasil uji: [SD_PULAU_ILMU_3D.md](SD_PULAU_ILMU_3D.md).

## Paket education_sd v2.0.5 — perbaikan crash musik di Samsung A18 (15 November 2026)

- Penyebab terlacak: jejak 2.0.4 menunjukkan crash ±7 detik setelah musik diputar, tepat saat musik latar
  (6,72 detik) mencapai titik ulang. Dengan musik mati game berjalan normal. Loop bawaan AudioStreamWAV pada
  suara buatan kode membuat aplikasi crash di SM-A185G (Mali-G57 MC2, Android 16).
- Musik kini tanpa loop WAV: diputar ulang lewat sinyal `finished`. Setiap suara diberi ekor hening 256 sampel.
- Mode aman dari 2.0.4 di-reset sekali saat 2.0.5 dibuka: musik dan animasi menyala lagi.
- Jejak langkah & catatan crash tetap aktif.

## Paket education_sd v2.0.4 — mode aman bertahap untuk crash di Samsung A18 (15 November 2026)

- Jejak dari HP pelapor (SM-A185G, Mali-G57 MC2, layar 1560x720): aplikasi crash 2 kali berturut-turut tepat
  setelah layar pengenalan tampil, tanpa sentuhan. Di Pi (1560x720, OpenGL) layar yang sama berjalan normal.
- Jejak kini juga mencatat audio (mulai/berjalan) dan frame 1/10/60/180/600, untuk memisahkan crash saat audio
  dibuat/diputar dari crash saat menggambar.
- Mode aman bertahap: setelah crash, musik dimatikan (tingkat 1); bila masih crash, animasi gambar maskot/peta
  juga dihentikan (tingkat 2). Tingkat tersimpan di progres (`safe_level`) dan ikut terkirim ke server.

## Paket education_sd v2.0.3 — jejak langkah untuk melacak crash di HP (15 November 2026)

- Di Samsung A18 Android menampilkan "Game server ditutup karena aplikasi ini memiliki bug" (aplikasi crash),
  dan log server tidak menunjukkan langkah terakhirnya. Game SD kini menulis jejak langkah (layar, tombol, sesi,
  mini-game, jeda/lanjut, peringatan memori, model HP, versi Android, GPU, ukuran layar) ke
  `user://education_sd_trail.txt` dengan flush per baris.
- Bila jejak sebelumnya tidak berakhir dengan END, saat game dibuka lagi 30 langkah terakhir disimpan di
  `progress.crash` dan dikirim ke server bersama progres, sehingga titik crash terlihat dari Pi.

## Paket education_sd v2.0.2 — perbaikan: game tertutup sendiri di HP (Samsung A18) (15 November 2026)

- Catatan diagnosis dari HP pelapor: game keluar lewat tombol "KEMBALI KE LAUNCHER" di beranda tanpa
  disengaja. Di HP layar beranda lebih tinggi dari layar, jadi pemain menggulir; jari yang mulai menggeser di atas
  tombol itu lalu dilepas dihitung sebagai tekan.
- Pengaman sentuhan: tombol tidak bereaksi bila jari sudah bergeser lebih dari 24 px (menggulir), dan selama
  0,35 detik setelah layar baru dibangun (sentuhan nyasar dari layar sebelumnya). ScrollContainer memakai
  zona mati gulir 24 px.
- Tombol "KEMBALI KE LAUNCHER" di beranda dan "Kembali ke Launcher" di pengaturan kini juga bertanya dulu.
- Diagnosis lebih rinci: mencatat saat game dibuka, sumber keluar (back Android / tombol beranda / pengaturan),
  dan versi paket.

## Paket education_sd v2.0.1 — perbaikan: game langsung kembali ke launcher (15 November 2026)

- Log server menunjukkan game SD tertutup 4 detik setelah dibuka, saat masih di layar pengenalan: sinyal tombol
  kembali Android (bisa terkirim saat menutup papan ketik / usap dari tepi layar) langsung menutup game.
  Kini dari layar pengenalan dan beranda pemain ditanya dulu ("Kembali ke daftar game?").
- Enter pada kolom nama = tombol Mulai.
- Catatan diagnosis `diag` (alasan & layar saat game ditutup, 10 terakhir) ikut progres dan tersinkron ke server.

## Paket education_sd v2.0.0 — "Petualangan Pulau Ilmu" (tanpa APK baru)

Update paket game unduhan saja (launcher menampilkan UPDATE); APK, SMP, The Last Dragon, launcher, dan server
tidak berubah. Rincian: [SD_PULAU_ILMU.md](SD_PULAU_ILMU.md).

- Game SD baru: pengenalan nama & kelas, beranda (avatar, level, bintang, koin, progres per mapel), peta 4 pulau
  dengan NPC, area berurutan, ujian akhir wilayah; kelas 1–6 terpisah.
- 11 tipe soal (pilihan ganda, benar/salah, lengkapi, pilih gambar, hitung gambar, susun huruf, susun
  kalimat/urutan, urutkan angka, pasangkan, kelompokkan, teka-teki logika), mode Latihan/Petualangan/Kuis,
  petunjuk, pembahasan, pemilihan soal adaptif.
- 213 soal bank tervalidasi + soal matematika terhitung per kelas, 35 kartu pengetahuan, 4 mini-game,
  koleksi kostum/kartu/hewan, 12 lencana, laporan belajar, audio dan gambar buatan kode.
- Progres skema 2 dengan migrasi otomatis dari skema 1 (game SD lama).
- Uji: `make sd-test` (baru); `make platform-test` disesuaikan dan kini gagal bila ada galat skrip.

## v0.84.2 — Nama aplikasi "Game server" (15 November 2026)

- Nama di bawah ikon HP diganti dari "Game Petualang" menjadi "Game server" (preset ekspor Android
  `package/name`). Nama paket `com.miftahulkhoiri.gamepetualang` dan `config/name` tidak diubah, jadi APK
  baru tetap menimpa APK lama dan data di HP (akun, game terpasang, progres) tetap utuh.

## v0.84.1 — Ikon aplikasi platform (15 November 2026)

**APK baru wajib** (ikon adalah aset; patch tidak bisa membawanya).

- Ikon aplikasi baru (rak server berisi tiga game + gamepad) untuk ikon proyek, ikon peluncur lama, dan
  ikon adaptif Android; dibuat ulang dengan `python3 tools/gen_ikon_platform.py`.
- Ikon lama (ksatria & pemanah) dipindah ke `assets/icon/last_dragon_512.png` dan tetap dipakai kartu
  The Last Dragon di launcher.

## v0.84.0 — Platform Multi-Game (15 November 2026)

**APK baru wajib** (adegan utama dan autoload berubah; patch tidak bisa membawanya).

### Baru
- **Launcher** sebagai layar pertama: daftar game dengan ikon/warna, kategori, versi, ukuran, status
  (`NOT_INSTALLED`, `DOWNLOADING`, `VERIFYING`, `INSTALLING`, `INSTALLED`, `UPDATE_AVAILABLE`, `ERROR`,
  `DISABLED`), progres unduhan, pesan error, status koneksi; tombol MAINKAN / DOWNLOAD / UPDATE / BATAL / HAPUS.
- **GameManager** (autoload) dan modul `client/core/`: registry, package manager, PCK reader, download
  manager (streaming + resume HTTP Range + batal + cek ruang), security manager (RSA-SHA256 + SHA-256 +
  validasi), version manager, save manager (per game, atomik, `.bak`, skema + migrasi), api client.
- **Game Pembelajaran SD** dan **SMP** (paket unduhan `education_sd`, `education_smp` v1.0.0): Matematika
  (soal acak terhitung), Bahasa Indonesia, IPA, IPS; 72 soal bank per jenjang; level per kelas; Latihan
  (pembahasan) dan Kuis (nilai, buka level berikutnya); riwayat; progres lokal + sinkron server.
- Server: endpoint `/v1/games` (katalog, manifest, tanda tangan, unduhan dengan Range) dan
  `/v1/games/{id}/progress`; paket `internal/catalog`; tabel `game_progress` (skema DB v5); env
  `GAME_CATALOG_DIR`.
- Pipeline paket: `scripts/build-game-pack.sh`, `scripts/game-keys.sh`, `tools/gamepack/` (cek PCK,
  manifest, katalog, tanda tangan, bank soal); `make game-pack`, `make game-keys`, `make platform-test`.
- Uji: `client/tests/platform_test.gd` + `scripts/platform-test.sh` (3 fase, proses Godot terpisah),
  tes Go `internal/catalog`, `internal/api/games_test.go`.

### Diubah (Game Petualangan tetap utuh)
- `login.gd`: tombol "Semua Game" dan tombol kembali Android di beranda kembali ke launcher (APK lama tanpa
  platform berperilaku seperti dulu).
- `sound.gd`: `set_music_paused()`; musik desa dijeda di launcher dan game lain.
- `build-patch.sh`: patch hanya untuk APK dengan adegan utama dan autoload yang sama.
- Ekspor: `config/*.json`, `config/*.pem` ikut APK; `games/*` tidak ikut APK maupun patch.
- Versi aplikasi & server 0.84.0.

### Diketahui
- Godot 4.7 tidak bisa melepas paket yang sudah dimuat: update game yang sudah dibuka di sesi yang sama
  berlaku setelah aplikasi dibuka ulang.
- Uji di HP sungguhan belum dilakukan (lihat `TEST_REPORT.md`).
