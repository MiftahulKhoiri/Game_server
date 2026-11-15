# Petualangan Pulau Ilmu 3D — audit, rancangan, dan laporan Fase 1–8  + 2.3.0 + Fase 9–10 (2.4.0)

Paket `education_sd` **2.1.0**. Dunia 3D ditambahkan **di atas** game 2D yang sudah ada: semua materi, bank soal,
penilaian, hadiah, progres, mini-game, koleksi, prestasi, dan laporan tetap dipakai apa adanya. Hanya paket PCK
yang berubah; APK, launcher, server Go, autentikasi, tanda tangan paket, game SMP, dan The Last Dragon tidak disentuh.

## 1. Audit singkat (sebelum perubahan)

| Bagian | Temuan di kode |
| --- | --- |
| Struktur | `main.tscn` (Control) + `main.gd` sebagai aplikasi satu-scene; layar dibangun ulang lewat `_clear(id)` (ScrollContainer → Page). Skrip pendukung di `scripts/`: `sd_data` (bank soal, `topics_for`, `pick`, `pick_mixed`), `sd_gen` (pembuat soal), `sd_progress` (model progres skema 2), `sd_question` (11 tipe soal), `sd_minigames`, `sd_art` (gambar 2D prosedural), `sd_audio` (suara buatan kode), `sd_ui` (gaya + pengaman sentuhan). |
| Karakter & gerak | Belum ada: avatar 2D statis (`SdArt.Avatar`) dan maskot NPC 2D. |
| UI belajar | Sesi soal `_start_session` → `_show_question` → `_on_answer` (`SdProgress.record_answer`) → `_finish_session` (`finish_area` / `finish_quiz` / `finish_exam`) → `_show_result` (pembahasan). |
| Progres | `GameManager.save_progress("education_sd", p, 2)` / `load_progress(id, 2, migrasi)` / `restore_progress_from_server`; `SdProgress.ensure` melengkapi kunci yang hilang. |
| Mini-game | `start_minigame(id)` → `SdMini.create(id)`, hasil `finish_minigame`; asal layar disimpan di `session.from`. |
| Audio | `SdAudio` (efek + musik buatan kode; musik diulang lewat sinyal `finished`, perbaikan 2.0.5). |
| Launcher | `GameManager.play` memuat PCK lalu `change_scene_to_file(entry)`; keluar lewat `exit_to_launcher()` yang memanggil `platform_before_exit()`. |
| Batasan APK | Templat ekspor resmi Godot 4.7.2, renderer GL Compatibility, tekstur ETC2/ASTC. 3D sudah terbukti jalan di HP (The Last Dragon memakai `world3d`). PCK hanya boleh berisi `res://games/education_sd/`. Tidak ada InputMap khusus game (PCK tidak bisa mengubah `project.godot`), jadi keyboard dibaca langsung. |

Risiko yang dicatat: belum ada aset 3D (GLB) berlisensi di repo; HP kelas rendah (Mali-G57) sensitif terhadap beban
render; dunia 3D tidak boleh membuat sistem simpan kedua.

## 2. Rancangan

- **Satu sistem karakter** (`scripts/world/w3d_rig.gd`): manusia kartun low-poly dari mesh primitif, dipakai pemain,
  NPC, dan penjaga wilayah. Animasi prosedural berbasis status: idle, jalan, lari, lompat, interaksi, sorak (hadiah).
  Ini **placeholder yang benar-benar bisa dimainkan**, bukan model jadi; bisa diganti GLB tanpa mengubah logika.
- **Pemain** (`w3d_player.gd`): `CharacterBody3D`, kamera orang-ketiga `SpringArm3D` (tidak menembus dinding).
- **Pulau** (`w3d_world.gd`): satu pulau per wilayah, dibangun dari data kelas aktif. Alun-alun berisi portal antarpulau,
  NPC pemandu, Peti Pengetahuan, kios mini-game, papan petunjuk, dan tempat rahasia. Jalan ke depan dihalangi
  **gerbang** atau **jembatan rusak** (selang-seling) — satu per area belajar — dan **Penjaga Wilayah** di ujung.
  Tema visual berbeda: Istana Angka + balok angka, rumah pohon + balok huruf, kubah lab + labu + danau, rumah adat +
  perahu + pasar.
- **HUD** (`w3d_hud.gd`): joystick kiri, geser kanan untuk kamera, tombol AKSI/LOMPAT/LARI (multisentuh), dialog NPC.
  Desktop: WASD/panah, seret mouse, Spasi, E/Enter, Shift.
- **Render** di `SubViewport` sendiri (`own_world_3d`), jadi pengaturan 3D tidak bocor ke launcher.

### Belajar sebagai bagian petualangan

| Objek 3D | Aktivitas (sistem lama) | Syarat |
| --- | --- | --- |
| Gerbang / jembatan area ke-n | `start_area` (5 soal, adaptif) | Terbuka hanya bila `area_rec(...).done` (sama dengan mode 2D). Area berikutnya terkunci sampai area sebelumnya selesai. |
| NPC pemandu | Dialog + petunjuk tujuan + `start_practice` (latihan) | — |
| Peti Pengetahuan | `start_quiz` (10 soal) | Peti terbuka bila nilai kuis ≥ 70. Hadiah = hadiah kuis biasa (`finish_quiz`). |
| Penjaga Wilayah | `start_exam` (ujian akhir) | Hanya setelah semua area selesai; kalah/menang mengikuti `finish_exam` (≥ 70). |
| Kios mini-game | `start_minigame` | — |
| Tempat rahasia | Fakta pengetahuan dari kartu topik | Tanpa koin (tidak ada hadiah tanpa hasil belajar). |
| Portal pulau | Pindah wilayah | — |

Semua hadiah tetap dari `SdProgress`; dunia 3D tidak memberi koin/bintang sendiri. Keluar dari sesi di tengah jalan
tidak membuka apa pun.

### Progres

Tambahan di data yang sama (skema tetap 2, dilengkapi `SdProgress.ensure`, jadi data lama aman):
`world = {region, chests, found, seen_done}` dan `settings.hero` (laki/perempuan), `settings.gfx` (hemat/seimbang/tinggi).
Kunci per kelas: `k<kelas>/<wilayah>`.

### Profil grafis (Pengaturan → Dunia 3D)

| Profil | Resolusi 3D | Bayangan | MSAA | Pohon (MultiMesh) | Jarak gambar dekorasi |
| --- | --- | --- | --- | --- | --- |
| Hemat | 60 % | mati | mati | 50 | 38 m |
| Seimbang (bawaan) | 80 % | ya (ortogonal, 32 m) | mati | 110 | 60 m |
| Tinggi | 100 % | ya | 2× | 180 | 95 m |

Optimasi yang dipakai: pohon dengan `MultiMeshInstance3D` (satu panggilan gambar per jenis), `visibility_range_end`
untuk dekorasi dan pohon, material dibagi pakai (cache), satu NPC + satu penjaga per pulau, tanpa partikel, physics
hanya untuk pemain (sisanya StaticBody). Belum ada: LOD otomatis (mesh primitif tidak punya LOD) dan occlusion culling.

## 3. Berkas

Ditambahkan: `client/games/education_sd/scripts/world/{w3d_rig,w3d_player,w3d_world,w3d_hud}.gd`, dokumen ini.
Diubah: `main.gd` (layar `world`, `show_world`, interaksi, kembali dari sesi/mini-game ke dunia, pengaturan karakter &
grafis, tombol beranda "JELAJAHI PULAU 3D"), `scripts/sd_progress.gd` (bawaan `world`, `settings.hero/gfx`),
`game.json` (2.1.0), `client/tests/sd_test.gd` (+39 pemeriksaan).

## 4. Pengujian (hasil sebenarnya, Raspberry Pi 5)

- `make sd-test`: **461 pemeriksaan LULUS** (termasuk 39 pemeriksaan dunia 3D: gerak joystick, pagar & gerbang
  menahan pemain, lompat, Area3D interaksi NPC, dialog membekukan pemain, gerbang/jembatan/ujian terkunci, sesi dari
  gerbang → gerbang terbuka + koin, keluar sesi tanpa hadiah, peti gagal/berhasil, tempat rahasia, mini-game, portal,
  joystick & geser kamera layar sentuh, profil Hemat/Tinggi, karakter perempuan, kembali ke beranda, simpan, data lama).
- `make platform-test`: LULUS.
- Render nyata di Pi (Xvfb + OpenGL, 1560×720) untuk keempat pulau: tampil benar, tanpa galat skrip.
- **Belum diuji di HP Android.** Kinerja nyata di Samsung A18 harus dicek pengguna; bila berat, pilih profil Hemat.

## 5. Risiko & tahap berikutnya

- Model karakter/bangunan masih primitif low-poly. Fase 5: ganti dengan aset GLB berlisensi jelas (mis. CC0 Kenney /
  Quaternius) dan catat sumbernya di sini.
- Fase 3: isi tiap pulau dengan lokasi tambahan (gua teka-teki, perpustakaan alam, kebun percobaan, museum).
- Fase 4: hubungkan koleksi hewan & kartu ke objek 3D (pameran di museum/kebun).
- Fase 6: ukur FPS di HP nyata per profil; tambah penggabungan mesh statis bila panggilan gambar terlalu banyak.


---

# Lanjutan: Fase 3–8 (paket 2.2.0)

## A. Audit 2.1.0 & laporan kesenjangan

| Target | Kondisi 2.1.0 | Dikerjakan di 2.2.0 |
| --- | --- | --- |
| Dunia luas, lokasi beraktivitas | 1 alun-alun kecil + jalan gerbang per pulau | Alun-alun diperbesar (52×41 m), 5 lokasi per pulau (20 total), semuanya punya aktivitas |
| Misi | Hanya petunjuk tujuan | 7 jenis misi dengan hadiah sekali-klaim |
| Model berkualitas | Semua primitif | NPC, warga, penjaga, hewan: GLB KayKit (CC0) dari APK; pemain masih primitif |
| Dunia hidup | Statis | Warga berpatroli, hewan, burung, ikan, air & pohon bergerak, siang-malam, hujan, suara lingkungan |
| Koleksi di 3D | Hanya layar 2D | Markas Pemain (galeri hewan 3D, museum kartu, lemari kostum, cermin karakter, piala, Buku Petualangan) |
| Kinerja | Belum diukur | Info kinerja di HP + pengukuran di Pi + penggabungan mesh |

## B. Fase 3 — lokasi tambahan

| Pulau | Lokasi (aktivitas) |
| --- | --- |
| Kerajaan Matematika | Gua Teka-Teki Angka, Menara Matematika, Labirin Matematika (dinding nyata, teka-teki di tengah), Jembatan Angka (batu loncatan bernomor), Desa Penduduk (warga Pak Hitung) |
| Hutan Bahasa | Perpustakaan Alam (+ kartu pengetahuan), Desa Hewan (warga Bu Rusa + koleksi hewan), Sungai Huruf, Gua Kata, Pohon Cerita |
| Laboratorium IPA | Kebun Percobaan, Laboratorium Eksperimen, Danau Ekosistem (ikan melompat), Hutan Hewan (hewan berkeliaran, Peneliti Ana), Area Tata Surya (planet mengorbit) |
| Negeri Penjelajah IPS | Museum Nusantara (+ kartu), Pelabuhan, Pasar Tradisional (Mbok Sari + mini-game), Desa Rumah Adat, Area Sejarah Indonesia |

Setiap lokasi: zona kunjungan (tercatat saat pemain masuk) dan papan teka-teki **3 soal** dari topik wilayah sesuai
kelas aktif (topik berputar per lokasi), lulus bila **≥ 2 benar pada percobaan pertama**. Koin per jawaban tetap dari
`SdProgress.record_answer`. Berkas: `scripts/world/w3d_locations.gd`.

## C. Fase 4 — misi (`scripts/world/w3d_missions.gd`)

Setiap misi: id, kunci klaim, jenis, nama, deskripsi, tujuan (angka), progres, status selesai/diterima, hadiah, mapel.

| Jenis | Misi | Hadiah |
| --- | --- | --- |
| Utama | Buka semua gerbang; Kalahkan Penjaga Wilayah | 30 koin+50 XP; 40+80 |
| Sampingan / Teka-teki / Warga | Satu per lokasi (labirin & gua = teka-teki, lokasi berwarga = misi warga) | 15+20 |
| Eksplorasi | Kunjungi 5 lokasi; tempat rahasia; kunjungi 4 pulau | 15+20; 10+10; 25+30 |
| Benda | Temukan 5 benda tersembunyi per pulau (Bintang Angka, Gulungan Huruf, Kristal Ilmu, Artefak Kuno) | 20+25 |
| Harian | Jawab 10 soal hari ini; selesaikan 1 teka-teki lokasi hari ini | 10+15 masing-masing |

Misi **dihitung dari progres sah**, bukan dari tombol. Hadiah diberikan sekali per kunci (`world.claimed`); memuat
ulang scene, mengulang teka-teki, atau membuka game lagi tidak membayar dua kali (diuji). Kunci harian disimpan 7 hari.
Tombol **MISI** membuka Buku Petualangan.

## D. Fase 5 — aset 3D

Dipakai (sudah ada di APK, tidak menambah ukuran paket; lisensi di `client/assets/models/LISENSI_*.txt`):

| Peran | Model | Sumber / lisensi |
| --- | --- | --- |
| Raja Angka, penjaga wilayah | `ksatria.glb` (pedang disembunyikan) | KayKit Adventurers, CC0 |
| Kak Kancil, Pak Hitung | `petani.glb` | KayKit Adventurers, CC0 |
| Profesor Kiko | `penyihir.glb` | KayKit Adventurers, CC0 |
| Nakhoda Bima | `pemanah.glb` (busur disembunyikan) | KayKit Adventurers, CC0 |
| Bu Rusa, Mbok Sari | `nenek_penjual.glb` | KayKit Adventurers, CC0 |
| Peneliti Ana | `anak_desa.glb` | KayKit Adventurers, CC0 |
| Hewan | `anak_ayam.glb`, `babi_hutan.glb`, `tikus_sawah.glb` | lihat LISENSI_Quaternius / OpenGameArt (CC0) |

Model diskalakan dari ukuran mesh, kaki di tanah, animasi `idle`/`walk` dari berkas (+ lompat/sorak prosedural).
Bila berkas tidak ada di APK, otomatis kembali ke model primitif (diuji).

**Masih diperlukan:** karakter pemain anak laki-laki & perempuan dengan rangka sama (APK hanya punya model anak
"Rogue" dan nenek), model bangunan bertema (istana, rumah adat, laboratorium), pohon/batu/perabot low-poly untuk
lokasi, dan objek pembelajaran (balok angka, buku, planet bertekstur). Kandidat berlisensi jelas: KayKit (CC0),
Quaternius (CC0), Kenney (CC0). Pemain tetap primitif sampai model anak perempuan tersedia.

## E. Fase 6 — dunia hidup (`scripts/world/w3d_life.gd`)

Warga berpatroli 3 titik dengan jeda + aktivitas menyapa; hewan berkeliaran di sekitar rumahnya; burung terbang
melingkar; ikan melompat di danau; benda bergoyang, gelembung lab, planet mengorbit; pohon bergoyang dan air bergerak
(shader, hanya profil Seimbang/Tinggi); siklus siang-malam 5 menit (malam tetap terang); hujan acak (CPUParticles3D,
mati di Hemat); kicau burung dan suara hujan buatan kode (diputar ulang lewat `finished`, tanpa loop WAV).
Satu `_process` memperbarui semua makhluk; yang lebih jauh dari jarak profil tidak dianimasikan dan disembunyikan.

| Profil | Hewan | Burung | Hujan (partikel) | Efek shader |
| --- | --- | --- | --- | --- |
| Hemat | 2 | 0 | 0 | mati |
| Seimbang | 3 | 3 | 250 | nyala |
| Tinggi | 5 | 5 | 500 | nyala |

## F. Fase 7 — koleksi & kustomisasi (`scripts/world/w3d_base.gd`)

Markas Pemain (lewat portal): galeri hewan 3D (dari `animals`), museum kartu (dari `cards`), lemari kostum (hanya
kostum di `owned`; mengganti baju karakter 3D), cermin pemilihan karakter, rak piala (dari `badges`), Buku Petualangan
(misi semua pulau). Tidak ada mata uang atau hadiah baru.

## G. Fase 8 — pengukuran & optimasi

Diukur di Raspberry Pi 5 (Xvfb, **llvmpipe = GPU perangkat lunak**, 1560×720, kelas 4, 60 frame setelah dunia
dibangun). FPS di sini **bukan** gambaran HP; draw call, objek, node, RAM, dan waktu bangun bisa dibandingkan.

| Profil · pulau | Draw call sebelum → sesudah gabung mesh | Objek | Node | RAM statis | Bangun dunia | FPS rata2 / min (llvmpipe) |
| --- | --- | --- | --- | --- | --- | --- |
| Hemat · Matematika | 291 → **189** | 316 | 457 | 63 MB | 94 ms | 9,7 / 8,7 |
| Hemat · IPS | 187 → **153** | 281 | 361 | 63 MB | 91 ms | 10,2 / 9,2 |
| Seimbang · Matematika | 399 → **262** | 389 | 469 | 66 MB | 97 ms | 6,2 / 5,8 |
| Seimbang · IPS | 341 → **229** | 357 | 373 | 65 MB | 95 ms | 6,6 / 6,0 |
| Tinggi · Matematika | 417 → **274** | 401 | 477 | 66 MB | 98 ms | 1,7 / 1,6 |
| Markas · Seimbang | 165 → **146** | 281 | 174 | 63 MB | 19 ms | 6,3 / 5,9 |

Optimasi yang ditambahkan karena hasil ukur: penggabungan mesh statis per bangunan/lokasi/gerbang/jeruji dan per
bagian karakter (`w3d_merge.gd`), pagar jadi satu mesh, label tanpa bayangan, balok huruf/angka satu label.
LOD otomatis tidak dipakai (mesh primitif tidak punya LOD); jarak gambar (`visibility_range_end`) dipakai untuk
dekorasi, lokasi, dan pohon. Ukuran PCK 2.2.0: lihat katalog (±0,3 MB; model GLB tidak ikut paket karena sudah di APK).

**Pengukuran di HP Android belum dilakukan.** Nyalakan *Pengaturan → Info kinerja* lalu kirim angka FPS
(rata-rata/minimum), draw call, dan RAM dari Samsung A18 untuk tiap profil.

## H. Pengujian 2.2.0

`make sd-test`: **527 pemeriksaan LULUS** (+66 dari 2.1.0): 20 lokasi, labirin bisa dilalui & dindingnya menahan,
kunjungan, teka-teki gagal/berhasil, misi sekali bayar (muat ulang/ulang sesi), warga berpatroli & berhenti saat
diajak bicara, 5 benda per pulau & tidak muncul lagi, 7 jenis misi, misi harian, perpustakaan kartu, burung/hewan per
profil, hujan, siang-malam, aktivasi jarak, info kinerja, Markas (galeri, museum, piala, buku, lemari, cermin, tanpa
koin baru), model GLB + cadangan primitif, penggabungan mesh. `make platform-test`: LULUS.

## I. Risiko

- Belum diuji di HP: kinerja nyata Mali-G57, multisentuh nyata, suara hujan/kicau.
- Draw call Seimbang ±260 masih bisa berat untuk HP kelas bawah: pakai Hemat bila FPS < 30.
- Model GLB memakai berkas APK: bila APK masa depan menghapusnya, game memakai model primitif (aman, tapi tampilan turun).


---

# 2.3.0 — semi-realistis, kamera 360°, pengacau & penjaga, alat

## Audit (Tahap A)

Kamera 2.2.0 sudah bisa berputar horizontal tanpa batas, tetapi diperbarui di langkah fisika (bisa tersendat),
tanpa zoom, dan batang pohon tidak punya tabrakan (kamera bisa menembus). Karakter pemain berproporsi "chibi"
(kepala ±1:3) dengan lengan/tungkai satu ruas dan pose yang langsung berganti. Belum ada musuh, pola perilaku
penjaga, alat/inventaris, dan lingkungan masih jarang di luar lokasi.

## Kamera & kontrol (Tahap B) — `w3d_player.gd`, `w3d_hud.gd`

- Yaw 360° dibungkus 0..TAU; pitch dibatasi −1,2..0,35 rad (tidak terbalik, tidak masuk tanah).
- Kamera mengikuti di `_process` dengan penghalusan eksponensial (tidak bergetar karena langkah fisika).
- `SpringArm3D` dengan probe bola 0,25 m: menahan kamera di depan pagar, bangunan, batu, tanah, dan **batang
  pohon** (pohon dekat jalur kini punya tabrakan statis).
- Jarak kamera 2,2–8 m (Teropong: 12 m): scroll mouse (PC) dan cubit dua jari di sisi kanan (HP).
- Multisentuh: joystick (jari 1) + putar kamera (jari 2) + cubit (jari 3) bersamaan; tombol AKSI/LOMPAT/LARI tetap.

## Karakter (Tahap C) — `w3d_rig.gd`

- Pemain & NPC cadangan semi-realistis: tinggi ±1,45 m, kepala ±1:6, leher, lengan/tungkai dua ruas (siku, lutut),
  tangan, sepatu, kerah, ikat pinggang, alis, hidung, telinga, poni. Topi & aksesori toko kostum lama tampil di 3D
  (petualang, mahkota, toga, pita, kacamata, syal, ransel).
- Animasi prosedural dengan transisi halus (setiap sendi mengejar sudut target): idle bernapas, jalan & lari dengan
  tekukan lutut dan siku, lompat menekuk, interaksi melambai, sorak.
- Pilihan karakter ketiga **Petualang** memakai model KayKit `anak_desa.glb` (rangka & animasi dari berkas).
- NPC, warga, penjaga, hewan tetap GLB KayKit (2.2.0); pengacau memakai `goblin.glb` (Quaternius, CC0) berwarna
  pastel dengan senjata disembunyikan.

## Dunia & gameplay (Tahap D)

- Lingkungan: batu, rumpun rumput, dan bunga dengan MultiMesh (jumlah per profil); kabut atmosfer bertema
  (Seimbang/Tinggi); landmark tinggi di ujung jalur sebagai penunjuk arah: Istana Angka, Pohon Bahasa Raksasa,
  Observatorium, Mercusuar Nusantara.
- **Pengacau Lupa** (`w3d_foes.gd`): patroli → kejar (7 m) → menantang (soal cepat pilihan ganda/benar-salah dari
  topik wilayah kelas aktif, tercatat lewat `SdProgress.record_answer`) → jinak (benar) / mundur & pemain terdorong
  lembut (salah atau dialog ditutup). Tidak ada nyawa atau kalah.
- **Penjaga Wilayah** berpola: berjaga (3 dtk) → hentakan (mendorong pemain dalam 5,5 m) → lelah (4,5 dtk). Ujian
  akhir hanya bisa dimulai saat penjaga lelah.
- **Alat petualangan** (`w3d_items.gd`, disimpan di `world.inventory`/`world.equip`): Kompas (panah tujuan), Kaca
  Pembesar (benda tersembunyi membesar & bersinar), Senter (lampu saat senja/malam), Teropong (zoom 12 m), Sepatu
  Petualang (+15% kecepatan), Jaring Ilmu (satu pilihan salah dihilangkan saat menjinakkan). Didapat dari misi:
  kalahkan penjaga tiap pulau, kunjungi 4 pulau, jinakkan 5 pengacau (misi jenis baru "tantangan").
- **TAS**: daftar alat (pakai satu), kostum/aksesori milik (pakai/lepas), jumlah pengacau dijinakkan & benda.

## Pengujian & ukuran (Tahap E)

- `make sd-test`: **569 pemeriksaan LULUS, 0 gagal** (+42): kamera 360°, batas vertikal, zoom & scroll, tabrakan
  kamera dengan pagar, arah gerak mengikuti kamera, multisentuh joystick+kamera+cubit, sendi dua ruas, transisi
  halus, karakter Petualang GLB, topi 3D, MultiMesh & tabrakan pohon, landmark & kabut, pengacau (patroli, kejar,
  soal, jinak, salah, tutup dialog, Jaring), pola penjaga (berjaga/hentakan/lelah), hadiah alat, efek 5 alat, TAS.
- `make platform-test`: LULUS.
- Ukur di Pi (llvmpipe, kelas 4, 1560×720): draw call Hemat 201/173, Seimbang 285/261, Tinggi 304/270
  (Matematika/IPS); RAM statis 64–70 MB; VRAM 61–85 MB; bangun dunia 91–122 ms. Naik ±6–9% dari 2.2.0 karena
  pengacau, lingkungan, dan landmark.
- **Belum diuji di HP Android** (kinerja, multisentuh nyata, kamera). Hasil HP harus dicatat terpisah.

## Belum selesai / risiko

- Model "semi-realistis" pemain masih prosedural; model anak laki-laki/perempuan GLB beranimasi lengkap
  (lari, lompat, interaksi) dengan lisensi jelas belum tersedia di repo.
- Animasi GLB hanya idle/walk; lompat/interaksi/sorak untuk model GLB masih gerak prosedural sederhana.
- Senjata tidak dibuat (sesuai usia SD); "alat petualangan" menggantikannya.


---

# Fase 9–10 (paket 2.4.0): pahlawan 3D & aset lingkungan

Dasar pekerjaan: commit `4349711` (paket 2.3.0), langsung di `main` atas permintaan pengguna.

## Audit

- APK punya model KayKit/Quaternius (CC0) untuk dewasa, monster, dan hewan, tetapi **tidak ada model anak
  laki-laki/perempuan berkerangka & beranimasi lengkap**. Pemain 2.3.0 = rig prosedural (bagian kaku, tanpa kulit).
- Lingkungan 2.3.0 sebagian besar mesh primitif yang dibangun saat game jalan; belum ada folder `assets/` di paket SD.

## Fase 9 — karakter

Aset **buatan sendiri** (CC0) dari `tools/gamepack/sd_heroes.gd` → `assets/characters/hero/{male,female}/hero_*.glb`:

| | Laki-laki | Perempuan |
| --- | --- | --- |
| Tinggi | ±1,47 m | ±1,47 m |
| Gaya | anak petualang semi-realistis low-poly: rompi hijau, kemeja, celana panjang, sepatu bot, tas selempang, rambut rapi | rompi ungu, kemeja, celana, sepatu bot, ransel kecil, rambut panjang + jepit |
| Ukuran | 11 material, ±6.200 verteks | 11 material, ±6.900 verteks |
| Kerangka | 20 tulang, **sama** | 20 tulang, **sama** |

Kerangka: Root, Pelvis, Spine, Chest, Neck, Head, Shoulder/UpperArm/LowerArm/Hand L/R, UpperLeg/LowerLeg/Foot L/R.
Skinning kaku per bagian (low-poly) dengan bola penutup sendi (bahu, siku, lutut) — tidak bolong saat menekuk.

**Animasi yang benar-benar ada di GLB (12):** idle, walk, run, jump, fall, land, interact, wave, celebrate, turn,
hit, equip. Dipilih otomatis dengan blend 0,18 dtk: lompat/jatuh dari kecepatan vertikal, mendarat setelah > 0,3 dtk
di udara, berbalik bila arah berubah > 130°, *hit* saat didorong pengacau/penjaga, *wave* saat bicara dengan NPC/warga,
*equip* saat memakai alat, *celebrate* saat hadiah.

Kostum: material **Baju** diwarnai sesuai kostum toko lama; topi (petualang, mahkota, toga, pita) dan aksesori
(kacamata, syal, ransel) ditempel ke tulang Head/Chest lewat `BoneAttachment3D`, jadi ikut animasi.
**Petualang** (KayKit `anak_desa.glb`) dipertahankan sebagai pilihan ketiga: proporsinya lebih "chibi" dan hanya
punya idle/walk, jadi tidak seragam dengan model baru — dibiarkan sebagai gaya alternatif. Bila berkas pahlawan
hilang, game kembali ke rig prosedural.

## Fase 10 — lingkungan

Aset **buatan sendiri** (CC0) dari `tools/gamepack/sd_props.gd` → `assets/environment/`:
`vegetation/` tree_round, tree_pine, tree_palm, bush, flowers · `rocks/` rock_a, rock_b · `educational/` math_statue,
big_book, microscope, globe, info_board · `props/` lamp_post (60–1.080 segitiga per aset, material warna tanpa tekstur).

Dipakai: pohon GLB per tema lewat MultiMesh (Matematika bulat; Bahasa & IPA bulat + cemara; IPS kelapa + cemara;
Hemat hanya cemara/kelapa yang ringan) dengan daun tetap bergoyang; batu kecil MultiMesh + 6 batu besar bertabrakan;
semak & bunga MultiMesh; objek pendidikan di tepi jalur tiap gerbang (patung simbol matematika +,−,×,÷…, buku besar,
mikroskop, globe) dengan tabrakan kotak; lampu jalan; 2 papan informasi per pulau berisi fakta kartu pengetahuan kelas
aktif (bisa dibaca dengan AKSI). Istana Angka diberi gerigi benteng, gerbang, jendela, bendera, dan tabrakan; rumah
lokasi diberi pintu ±1,9 m, kusen, jendela, cerobong. Penggabung mesh kini mendukung mesh banyak material.

**Belum dikerjakan di Fase 10** (jujur): model GLB khusus untuk bangunan lokasi (menara, gua, museum, laboratorium,
mercusuar, rumah adat, pasar) masih prosedural (diperkaya, bukan diganti); rumah adat belum mengikuti referensi
daerah tertentu; tangga belum ada (tidak ada lantai bertingkat yang bisa dinaiki).

## Pengujian & ukuran

- `make sd-test`: **604 pemeriksaan LULUS, 0 gagal** (+35 dari 2.3.0): kerangka lengkap & sama, 12 animasi,
  jalur animasi valid, kaki di tanah & tinggi ±1,47 m, pewarnaan baju, 11 pemetaan status→animasi + mendarat,
  topi/ransel di tulang, cadangan prosedural, Petualang tetap jalan, 13 aset lingkungan termuat, pohon GLB, papan
  informasi, batu besar bertabrakan, jalur ke gerbang tidak terhalang.
- `make platform-test`: LULUS.
- Ukur di Pi (llvmpipe, kelas 4, 1560×720), Matematika / IPS:

| Profil | Draw call | Segitiga | RAM statis | VRAM |
| --- | --- | --- | --- | --- |
| Hemat | 215 / 174 | 33k / 52k | 69–73 MB | 65–75 MB |
| Seimbang | 300 / 266 | 61k / 113k | 74 MB | 72–78 MB |
| Tinggi | 321 / 275 | 146k / 156k | 74–75 MB | 84–90 MB |

Pengujian HP sudah dinyatakan aman oleh pengguna untuk 2.3.0; 2.4.0 menambah ±5% draw call dan lebih banyak segitiga
(pohon), jadi tetap disarankan dicek ulang FPS-nya di Samsung A18 (Pengaturan → Info kinerja).
