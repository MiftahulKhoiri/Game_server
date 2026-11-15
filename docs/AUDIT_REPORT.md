# Audit Repository — Persiapan Platform Multi-Game (v0.84.0)

Tanggal audit: 15 November 2026, terhadap `main` @ `31b6f3b` (v0.83.0). Audit dilakukan dengan memeriksa
kode, konfigurasi, skrip build, dan menjalankan tes yang ada — bukan hanya README.

## 1. Kondisi aktual

| Bagian | Temuan |
|---|---|
| Server | **Go 1.24** (`cmd/gameserver`, `internal/*`), bukan Python/FastAPI. HTTP `net/http` (ServeMux pola Go 1.22), SQLite lewat `modernc.org/sqlite`, satu koneksi penulis, WAL. Jalan sebagai layanan systemd pengguna di Raspberry Pi 5, keluar ke internet lewat Tailscale Funnel (HTTPS :8443). |
| Database | SQLite `data/game.db`, skema v4 (`players`, `sessions`, `battles`, `trades`), migrasi bertahap di `internal/store/store.go`, `PRAGMA user_version`, cadangan harian otomatis. |
| Autentikasi | Token Bearer acak, hash disimpan di `sessions`, PBKDF2 600 ribu putaran, maks 10 sesi, kedaluwarsa 30/180 hari, pembatas percobaan dan laju. |
| Klien | **Godot 4.7.2**, GDScript, renderer GL Compatibility, layar mendatar 1280×720. Satu proyek `client/` = satu APK `com.miftahulkhoiri.gamepetualang`. |
| Entry point (sebelum) | `run/main_scene = res://scenes/login.tscn`; autoload: `Patcher`, `Api`, `Session`, `Sound`. |
| Navigasi | `change_scene_to_file` antar adegan (`login`, `world3d`, `battle`, `dialog`, `shop`, dst.). UI hampir seluruhnya dibangun lewat kode. |
| Penyimpanan klien | `user://settings.cfg` (server, token, pengaturan), `user://patch/` (patch), `user://cerita.cfg`, `user://draf_penampilan.json`. Progres game ada di **server** (server sumber kebenaran). |
| Sistem unduh yang sudah ada | (1) **Patch konten PCK** (`scripts/patcher.gd`, `internal/api/patch.go`, `scripts/build-patch.sh`): memuat `.pck` skrip+adegan lewat `ProjectSettings.load_resource_pack(path, true)` sebelum autoload lain; cek ukuran + SHA-256; pengaman crash 2× boot. (2) **Updater APK** (`scripts/updater.gd`) dari GitHub Releases. |
| Build Android | GitHub Actions `client.yml`: uji klien↔server, ekspor APK rilis (cadangan debug) dengan keystore debug publik, periksa tanda tangan/versi/izin, lampirkan ke Release saat tag `v*`. Preset ekspor `Android` dan `Patch`. |
| Tes | 328 fungsi tes Go (semua lulus), uji ujung-ke-ujung Godot headless `client/tests/e2e.gd` (±1100 pemeriksaan), uji asap server, tolok ukur. |
| Game petualangan | ±24.000 baris GDScript di `client/scripts/` dan 10 adegan di `client/scenes/`, aset 20 MB di `client/assets/`. Cerita The Last Dragon, dunia 3D, NPC, monster, ekonomi, dll. |

## 2. Modul yang berfungsi

Server (semua endpoint `/v1/...`), database + migrasi + cadangan, autentikasi/sesi, patch PCK, updater APK,
seluruh game petualangan, CI Android. Semua tes Go lulus sebelum perubahan (`go test ./...`).

## 3. Modul yang belum ada (dibutuhkan platform)

Launcher, registry game, GameManager (siklus hidup game), katalog game di server, paket game per game,
tanda tangan digital, pengunduh dengan resume, penyimpanan progres per game, game Pendidikan SD/SMP.

## 4. Potensi bug, konflik, dan risiko perubahan

1. **Patch lama vs APK baru.** `build-patch.sh` menentukan `min_apk` dari isi `client/assets` dan pengaturan
   layar saja. Setelah adegan utama dan daftar autoload berubah, patch baru bisa dikirim ke APK lama yang
   belum punya `GameManager` → skrip gagal dikompilasi (pengaman 2× boot akan membuangnya, tetapi pemain
   sempat gagal membuka aplikasi). **Diperbaiki**: pemeriksaan kecocokan kini juga membandingkan
   `run/main_scene` dan daftar autoload.
2. **`Patcher.confirm()` hanya dipanggil di layar masuk.** Bila launcher menjadi layar pertama dan pemain
   tidak membuka Petualangan, hitungan boot patch naik terus dan patch sehat dibuang. **Diperbaiki**:
   launcher juga memanggil `confirm()`.
3. **Tombol kembali Android** di beranda Petualangan keluar dari aplikasi. Di platform harus kembali ke
   launcher. **Diubah minimum** di `login.gd` (APK lama tanpa `GameManager` tetap berperilaku lama).
4. **Musik desa** diputar autoload `Sound` sejak aplikasi dibuka, sehingga akan ikut berbunyi di game
   pendidikan. **Ditambah** `Sound.set_music_paused()`; GameManager hanya menyalakannya untuk game yang
   memintanya.
5. **PCK tidak bisa dilepas** (Godot 4.7 tidak punya *unload*). Update game yang sudah dimuat di sesi yang
   sama butuh aplikasi dibuka ulang — didokumentasikan dan ditangani (`restart_required`).
6. **PCK dari proyek Godot terpisah** tidak dijamin cocok (path, UID, versi mesin, skrip bersama). Karena itu
   paket game dibangun dari proyek yang SAMA dengan APK (lihat `docs/PCK_PACKAGE_FORMAT.md`).
7. **`load_resource_pack(..., true)`** (dipakai patch) bisa menimpa berkas apa pun. Paket game memakai
   `replace_files=false` + pemeriksaan direktori PCK sebelum dimuat, sehingga tidak bisa menimpa aplikasi
   atau game lain.
8. **HTTP biasa**: templat rilis Android menolak HTTP; server sudah HTTPS lewat Tailscale Funnel. Unduhan
   paket hanya HTTPS, kecuali alamat lokal/LAN (untuk uji di Pi).
9. **APK harus dibangun ulang** untuk perubahan ini (adegan utama, autoload, kunci publik) — patch tidak bisa.

## 5. Rekomendasi arsitektur (dipakai)

Hybrid: satu APK = launcher + game bawaan (Petualangan, tetap di `res://scripts` dan `res://scenes` tanpa
dipindah) + mesin bersama; game tambahan = paket `.pck` per game di `res://games/<id>/`, diunduh dari
server Go yang ada (endpoint baru di bawah `/v1/games`), diverifikasi tanda tangan RSA + SHA-256, dimuat
dengan `replace_files=false`. Rincian: `docs/ARCHITECTURE.md` (bagian Platform Multi-Game).

## 6. Daftar file

**Dibuat**: `client/core/*` (8 modul + `pck_reader.gd`), `client/launcher/*`, `client/config/*`,
`client/shared/edu/*`, `client/games/education_sd/*`, `client/games/education_smp/*`,
`client/tests/platform_test.gd`, `internal/catalog/*`, `internal/api/games.go` (+ tes),
`internal/store/game_progress.go`, `scripts/build-game-pack.sh`, `scripts/game-keys.sh`,
`scripts/platform-test.sh`, `tools/gamepack/*`, dokumen di `docs/`.

**Diubah (minimum)**: `client/project.godot` (adegan utama, autoload `GameManager`, versi),
`client/export_presets.cfg` (sertakan `config/*`, kecualikan `games/*`), `client/scripts/login.gd`
(tombol "Semua Game" + tombol kembali), `client/scripts/sound.gd` (jeda musik), `scripts/build-patch.sh`
(cek kecocokan), `internal/api/api.go` (opsi + rute katalog), `internal/config/config.go`
(`GAME_CATALOG_DIR`), `internal/store/store.go` (skema v5), `cmd/gameserver/main.go`,
`internal/version/version.go`, `Makefile`, `.gitignore`.

**Tidak boleh diubah sembarangan**: `client/scripts/patcher.gd` (harus autoload pertama), `client/scripts/maps.gd`
+ `internal/game/tiles_gen.go` (dibangkitkan berpasangan), skema `players.state` (format save
Petualangan), `internal/store/store.go` (migrasi: hanya boleh menambah langkah), keystore
`deploy/android/debug.keystore` (APK baru harus bisa menimpa APK lama), kunci penerbit
`~/.config/game_server/publisher_private.pem` (ganti kunci = semua APK lama menolak paket baru).
