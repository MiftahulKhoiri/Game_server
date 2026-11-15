# Game Pembelajaran SD — "Petualangan Pulau Ilmu" (paket `education_sd` v2.0.0)

## 1. Audit awal (sebelum perubahan)

| Bagian | Temuan |
|---|---|
| Game SD v1.0.0 | `main.gd` hanya mewarisi mesin kuis bersama `res://shared/edu/quiz_app.gd` dan membaca `data/course.json` (72 soal pilihan ganda + soal matematika acak). Satu tipe soal, tiga level gabungan (kelas 1–2, 3–4, 5–6), mode Latihan/Kuis, nilai terbaik, riwayat. Tanpa cerita, peta, avatar, hadiah, mini-game, audio, atau laporan. |
| Mesin bersama | `quiz_app.gd` **juga dipakai game SMP** dan ikut APK. Mengubahnya berisiko merusak SMP dan butuh APK baru. |
| Progres | `GameManager.save_progress(id, data, schema)` / `load_progress(id, schema, migrations)` (atomik, `.bak`, migrasi, sinkron server), `restore_progress_from_server(id, schema)`. SD v1 menyimpan skema 1: `{levels, history, last_answers}`. |
| Paket | Dibangun dari proyek yang sama (`make game-pack`), hanya `res://games/<id>/`; `res://shared` dan `res://core` diambil dari APK. |
| Audio | Hanya autoload `Sound` milik The Last Dragon (musik desa), yang dijeda platform di luar game itu. |
| Layar | Aplikasi mendatar 1280×720, `stretch canvas_items` + `aspect expand` (menyesuaikan HP panjang/tablet). |
| Risiko | Tidak ada aset gambar/suara anak di repo; aset luar berisiko lisensi dan menambah ukuran paket. Kompatibilitas: paket hanya boleh memakai API yang ada di APK ≥ 0.84.0. |

**Keputusan**: seluruh game baru dibangun di namespace `res://games/education_sd/`; `quiz_app.gd`, SMP,
launcher, server, autentikasi, tanda tangan paket, dan The Last Dragon **tidak diubah**. Pembuat soal bersama
(`question_gen.gd`) dipakai ulang untuk pecahan. Karena tidak ada perubahan APK, game ini dikirim sebagai
**update paket biasa** (launcher menampilkan UPDATE), `min_launcher_version` tetap 0.84.0.

## 2. Rancangan

```
Pengenalan (nama + kelas) ─► Beranda ─┬─► MULAI PETUALANGAN ─► Peta 4 pulau ─► Wilayah (NPC, area berurutan, ujian akhir, mini-game)
                                      ├─► PILIH PELAJARAN ─► Latihan per topik / Kuis per mapel
                                      ├─► MINI-GAME (4)      ├─► KOLEKSI (kostum, kartu, hewan)
                                      ├─► PRESTASI (lencana) ├─► LAPORAN BELAJAR
                                      └─► PENGATURAN (nama, kelas 1–6, musik, efek suara) ─► KEMBALI KE LAUNCHER
```

- **Wilayah**: Kerajaan Matematika (Raja Angka), Hutan Bahasa (Kak Kancil), Laboratorium IPA (Profesor Kiko),
  Negeri Penjelajah IPS (Nakhoda Bima). Area = topik yang tersedia untuk kelas aktif; area berikutnya terbuka
  setelah area sebelumnya selesai; ujian akhir terbuka setelah semua area selesai (lulus ≥ 70).
- **Kelas 1–6** terpisah: area, ujian, dan kuis disimpan per kelas; ganti kelas tidak menghapus progres kelas lain.
- **Mode**: Latihan (tanpa waktu, coba lagi sampai 3 kali, petunjuk, penjelasan setelah menjawab), Petualangan
  (cerita area, jalan maju setiap jawaban benar, bintang/koin/kartu), Kuis/Ujian (10 soal, nilai, pembahasan di akhir).
- **Adaptif** (`sd_data.gd: pick`): ≥ 4 jawaban terakhir dengan benar < 50% → soal kelas lebih rendah, konsep
  sama, tingkat kesulitan rendah; ≥ 5 jawaban dengan benar ≥ 80% → soal sulit didahulukan. Kecepatan menjawab
  tidak dipakai. Soal yang belum pernah dilihat didahulukan; soal tidak diulang dalam satu sesi.
- **Hadiah karena usaha**: koin untuk setiap jawaban (benar 3, benar setelah mencoba 2, belum tepat 1), bintang
  area (1–3), kartu pengetahuan per topik, koleksi hewan dari mini-game, 12 lencana, XP & level. Kostum dibeli
  dengan koin. **Tidak ada** uang sungguhan, iklan, atau mekanisme undian.

## 3. Tipe soal (11)

| Tipe | Kunci di data | Interaksi |
|---|---|---|
| `mc` pilihan ganda, `logic` teka-teki logika, `fill` melengkapi | `options`, `answer` | tombol besar, pilihan diacak |
| `tf` benar/salah | `answer` (boolean) | Benar / Salah |
| `pick_image` memilih gambar | `options` = nama bentuk | gambar bangun datar/ruang digambar kode |
| `count` hitung gambar | `shape`, `count` | gambar ditampilkan, pilih jumlah |
| `order_letters` susun huruf, `order_words` susun kalimat/urutan peristiwa, `sort_numbers` urutkan angka | `word` / `items` / `numbers`+`desc` | ketuk ubin sesuai urutan |
| `match` pasangkan (kata–kata, huruf–huruf, organ–tugas, …) | `pairs` | ketuk kiri lalu kanan |
| `classify` kelompokkan / eksperimen sederhana (padat–cair, terapung, produsen–konsumen) | `bins`, `items` | ketuk kelompok |

Setiap soal: `id` unik, `subject`, `topic`, `grade`, `difficulty`, `q`, jawaban, `explain`, `hint` opsional,
`points`. Petunjuk: menyembunyikan satu pilihan salah, memasang satu ubin, memasangkan satu pasangan,
memberi nomor gambar, atau menunjukkan kelompok.

## 4. Mini-game (offline)

| Mapel | Mini-game | Tujuan belajar |
|---|---|---|
| Matematika | Pintu Kode Angka | menghitung teliti; ketik hasil untuk membuka 5 pintu (soal sesuai kelas) |
| Bahasa | Huruf yang Hilang | mengeja; 8 kata per kelas |
| IPA | Kelompokkan Hewan | herbivora/karnivora (kelas 1–3), + omnivora (kelas 4–6); hewan benar masuk koleksi dengan fakta |
| IPS | Pasangan Nusantara | pekerjaan–alat; kelas 4+ ditambah rumah adat–daerah |

## 5. Konten

`tools/gamepack/make_sd_bank.py` → `data/pulau_ilmu.json` (± 80 KB). 213 soal bank (kelas 1–6, 35 topik,
4 wilayah, 9 tipe) + soal matematika yang **dihitung** oleh `sd_gen.gd` (penjumlahan s.d. 50.000, pengurangan,
perkalian, pembagian habis, bilangan bulat negatif kelas 6, pangkat dua/tiga, pecahan, konversi satuan, pola
bilangan), 35 kartu pengetahuan, 18 fakta hewan, 12 lencana, 12 kostum. Validator Python menolak: ID kembar,
pertanyaan/penjelasan kosong, pilihan kosong/kembar, jawaban di luar indeks, tipe/gambar tak dikenal, kelas
di luar 1–6, topik tanpa soal. Validator yang sama ada di GDScript (soal tidak sah dilewati saat dimuat).

Kebenaran materi: soal disusun dari materi umum SD (pancaindra, wujud benda, rantai makanan, tata surya,
letak Indonesia, rumah adat, tokoh dan peristiwa sejarah, majas, pantun, satuan, luas/keliling/volume). Fakta
yang mudah berubah (mis. ibu kota negara) sengaja tidak dipakai. Disarankan ditinjau guru sebelum dipakai di
kelas; mengubah atau menambah soal cukup di `make_sd_bank.py` lalu `make game-pack`.

## 6. Visual & audio

Semua gambar (bangun datar/ruang, apel, avatar dengan baju/topi/aksesori, empat karakter NPC, peta pulau)
dan suara (klik, benar, belum tepat yang lembut, bintang, buka pintu, musik latar pentatonik ± 7 detik
berulang) **dibuat dengan kode** — tanpa berkas aset, tanpa masalah lisensi, paket tetap kecil. Animasi
ringan (tween membesar/bergoyang/memudar, NPC bernapas, ombak peta digambar ulang 20–30 kali/detik).
Musik dan efek suara bisa dimatikan terpisah di Pengaturan.

Aset yang **disarankan** bila ingin tampilan lebih kaya (belum ada di repo, tidak dirujuk kode):

| Aset | Spesifikasi | Nama berkas usulan | Lisensi |
|---|---|---|---|
| Ilustrasi 4 pulau | PNG 1024×576, gaya kartun cerah, latar transparan | `games/education_sd/art/pulau_<wilayah>.png` | CC0 / buatan sendiri |
| Ikon hewan (18) | PNG 256×256 | `games/education_sd/art/hewan/<nama>.png` | CC0 (mis. Kenney) |
| Rumah adat (6) | PNG 512×384 | `games/education_sd/art/rumah_adat/<nama>.png` | buatan sendiri |
| Musik latar | OGG ≤ 60 detik, loop, ≤ 300 KB | `games/education_sd/audio/musik.ogg` | CC0 / CC-BY |

## 7. Progres (skema 2)

`player {name, grade, avatar}`, `coins`, `xp`, `grades["1".."6"] {areas, exams, quiz}`,
`topics["<kelas>/<topik>"] {correct, wrong, recent[≤12], seen[≤30]}`, `totals`, `owned`, `cards`, `animals`,
`badges`, `history[≤80]`, `daily[≤30 hari]`, `minigames`, `settings {music, sfx}`, `legacy`.
Disimpan lewat `GameManager.save_progress("education_sd", p, 2)` setelah setiap sesi, perubahan pengaturan,
aplikasi dijeda, dan sebelum kembali ke launcher. Migrasi skema 1 → 2 (`sd_progress.gd: upgrade`): data lama
disimpan utuh di `legacy`, riwayat dipindah, level lama yang lulus menjadi koin. Progres tetap ada setelah
aplikasi ditutup, HP dimulai ulang, game diperbarui, atau game dihapus lalu diunduh ulang (folder progres
tidak dihapus platform), dan dipulihkan dari server bila HP baru dan pemain sudah masuk akun.

## 8. Laporan belajar

Total soal, benar pada percobaan pertama, "sedang dilatih", nilai per mapel, materi dikuasai (≥ 5 jawaban
terakhir, ≥ 80% benar), materi untuk dilatih (≥ 5 jawaban, < 60%), jumlah materi yang datanya belum cukup,
grafik 7 hari, riwayat. Bahasa positif; tidak ada kesimpulan dari data sedikit.

## 9. Berkas

Baru: `client/games/education_sd/scripts/{sd_data,sd_gen,sd_progress,sd_ui,sd_art,sd_audio,sd_question,sd_minigames}.gd`,
`client/games/education_sd/data/pulau_ilmu.json`, `tools/gamepack/make_sd_bank.py`, `client/tests/sd_test.gd`,
`scripts/sd-test.sh`, dokumen ini. Diubah: `client/games/education_sd/main.gd` (game baru; tidak lagi mewarisi
`quiz_app.gd`), `client/games/education_sd/game.json` (v2.0.0), `client/tests/platform_test.gd` (memakai API
game SD baru; versi update uji dibaca dari `game.json`), `scripts/platform-test.sh`, `Makefile` (`make sd-test`).
`data/course.json` lama tetap disimpan (masih dibuat `make_courses.py`) walau tidak dipakai lagi.

## 10. Belum dikerjakan / batasan

- Ilustrasi hewan dan rumah adat masih berupa teks + warna (lihat daftar aset usulan).
- Mini-game "tangkap angka", "susun balok", "susun rantai makanan", "cocokkan provinsi di peta", dan
  "urutan pertumbuhan tanaman" belum dibuat (sebagian materinya sudah ada sebagai tipe soal urutan/kelompok).
- Uji di HP Android sungguhan (sentuhan, audio, performa perangkat bawah) belum dilakukan.
