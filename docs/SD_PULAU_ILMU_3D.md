# Petualangan Pulau Ilmu 3D — audit, rancangan, dan laporan Fase 1–2

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
