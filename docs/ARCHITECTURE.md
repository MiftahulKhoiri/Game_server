# Arsitektur

```
 HP Android (APK, Godot)  --HTTP/JSON-->  Server Go di Raspberry Pi 5  -->  SQLite
```

## Mengapa Go untuk server

Proyek ini akan panjang dan banyak tangan, jadi yang dipilih adalah bahasa
yang membosankan dalam arti baik:

- **Stabil dan kompatibel ke belakang.** Kode Go lama tetap jalan di versi baru.
- **Konkurensi bawaan.** Cocok untuk banyak koneksi pemain tanpa library tambahan.
- **Satu file biner.** Deploy ke Pi cukup menyalin satu file; bisa di-cross-compile.
- **Mudah dibaca kontributor baru.** Bahasanya kecil, format kode seragam (`gofmt`).
- **Aman memori** dibanding C/C++, tanpa beban belajar Rust.

Database memakai SQLite (driver Go murni, tanpa CGO). Cukup kuat untuk satu Pi
dan dapat diganti bila suatu hari perlu.

## Mengapa Godot 4 untuk klien

Gambar dibuat sendiri oleh pemilik proyek, dan Godot paling mulus untuk
mengimpor PNG, tilemap, dan animasi sprite 2D. Ekspor ke APK didukung langsung
dan bisa diotomatisasi lewat GitHub Actions (Android SDK tidak perlu dipasang di Pi).

## Struktur folder

| Folder | Isi |
|--------|-----|
| `cmd/gameserver/` | Titik masuk program (hanya merangkai komponen) |
| `internal/config/` | Pengaturan dari environment variable |
| `internal/game/` | Aturan dan model game; tidak tahu HTTP/DB |
| `internal/store/` | Penyimpanan SQLite |
| `internal/api/` | Handler HTTP, autentikasi, validasi |
| `internal/catalog/` | Katalog game platform (manifest + paket bertanda tangan) |
| `client/` | Proyek Godot 4.7 (klien Android = launcher platform multi-game) |
| `assets/` | Gambar mentah/sumber dari ilustrator |
| `docs/` | Dokumen desain dan kontrak API |
| `deploy/` | Menjalankan di Pi (systemd) dan kunci debug APK |
| `scripts/` | Skrip bantu (uji klien <-> server, patch, paket game, kunci penerbit) |
| `tools/gamepack/` | Alat paket game: periksa PCK, manifest, katalog, tanda tangan, bank soal |

Aturan arah ketergantungan: `api` -> `store` -> `game`. Paket `game` tidak
boleh mengimpor paket lain di proyek ini.

## Menjalankan

```bash
make run          # bangun dan jalankan di :8090
make check        # format + vet + tes (sama dengan CI)
```

Pengaturan: `GAME_ADDR` (bawaan `:8090`), `GAME_DB` (bawaan `data/game.db`), cadangan otomatis
`GAME_BACKUP_DIR` (bawaan `data/backup`, `off` = mati), `GAME_BACKUP_HOURS` (24), `GAME_BACKUP_KEEP` (7), `GAME_TRUSTED_PROXIES` (proxy tepercaya untuk header IP asli, bawaan `127.0.0.0/8,::1`; `none` = tidak ada), `GAME_DB_CHECK` (`strict` bawaan = tidak menyala bila database rusak; `warn`).

## Audit server dan database (v0.61.0, roadmap no. 219-238)

**Alur permintaan.** `logRequests` -> `recoverPanic` -> `clientGate` (versi klien) -> mux -> `auth` (token ->
pemain) -> handler. Handler yang mengubah data memakai `store.Update` (satu transaksi: baca pemain + pertarungan,
jalankan aturan dari paket `game`, periksa batas ekonomi, simpan, versi +1). Perdagangan antarpemain memakai
satu transaksi untuk dua pemain (`store/trades.go`).

**Server sumber kebenaran.** Klien hanya mengirim *permintaan* (serang, beli, simpan posisi, ...). Semua angka
(HP, XP, emas, barang, kemenangan, hadiah, jam dunia) dihitung server. `PUT /v1/players/me/save` hanya
menerima posisi (peta harus dikenal, petak di dalam peta). Sejak v0.77.0 posisi juga harus bisa dicapai dari
posisi tersimpan (`game.State.MoveTo`: batas kecepatan longgar, jarak jalan menyusuri petak `game/pathing.go`
dengan bentuk peta `tiles_gen.go` yang dibuat `make maps` dari `maps.gd`, pintu antarpeta `game.Doors`, gerbang yang
terkunci); yang mustahil ditolak `422` dan dicatat `posisi ditolak`. `POST /v1/world/break` dan
`/v1/world/chest` memakai pemeriksaan yang sama sebelum menghitung jarak ke benda/peti, jadi hadiah selalu
diukur dari posisi server yang sah. Setiap state yang akan disimpan diperiksa `ValidEconomy`.

**Pembatas percobaan** (`auth.Limiter`): login gagal dihitung per isian, per akun (`id:<pemain>`, jadi nama
dan email akun yang sama berbagi jatah) dan per IP. Biaya terkendali: riwayat per kunci paling banyak `max`,
pembersihan kunci kedaluwarsa paling sering sekali per seperempat jendela, jumlah kunci dibatasi 20.000.
Header IP asli (`CF-Connecting-IP`, `X-Forwarded-For`) hanya dipercaya dari proxy di
`GAME_TRUSTED_PROXIES` (bawaan: mesin ini sendiri).

**Batas laju umum** (`auth.Bucket`, ember token): per IP 60/detik (burst 120) untuk semua jalur kecuali
`/healthz`, dan per pemain 20/detik (burst 60) setelah login; lebih dari itu `429` + `Retry-After`. Endpoint
patch (`/v1/patch`) kini dipasang di dalam server (`api.PatchDir`), jadi ikut log, recover, dan batas laju.

**Database (SQLite, `modernc.org/sqlite`, satu koneksi).** Skema versi 4 (`PRAGMA user_version`), migrasi
bertahap tanpa kehilangan data (v1 -> v2 akun, v2 -> v3 `trades`, v3 -> v4 `sessions.last_used`). Setiap
langkah migrasi dan kenaikan `user_version`-nya berada dalam satu transaksi (mati di tengah = versi lama utuh,
diulang saat menyala). Database dengan versi skema lebih baru dari server ditolak (server tidak menyala).

| Tabel | Isi | Indeks |
|-------|-----|--------|
| `players` | akun + state JSON + versi | `id` (PK), `name`, `email` (UNIQUE, NOCASE) |
| `sessions` | hash token, pemain, dibuat, terakhir dipakai | `token_hash` (PK), `player_id` |
| `battles` | pertarungan berjalan (JSON) | `player_id` (PK) |
| `trades` | tawaran dagang (barang dititipkan) | `(from_id, status)`, `(to_id, status)` |

PRAGMA: WAL, `synchronous=NORMAL` (aman dari listrik padam, paling banyak transaksi terakhir hilang),
`foreign_keys=ON`, `busy_timeout=5000`, `temp_store=MEMORY`, cache 8 MB. Saat menyala server menjalankan
`PRAGMA quick_check`; bila rusak (atau gagal diperiksa) server **tidak menyala** (pulihkan cadangan dulu;
`GAME_DB_CHECK=warn` untuk penyelamatan darurat). Uji `TestQueriesUseIndexes` memastikan kueri utama tidak memindai tabel. Tolok ukur di
Pi 5 (`go test -bench . ./internal/store/`): cek token ±0,07 ms, simpan state ±0,13 ms, daftar dagang ±0,12 ms.

**Cadangan.** Server membuat `data/backup/game-YYYYMMDD-HHMMSS.db` (VACUUM INTO, salinan konsisten walau
server berjalan) setiap 24 jam dan menyimpan 7 terbaru. Manual: `make backup`. Pemulihan:
`make restore FILE=data/backup/game-....db` (memeriksa cadangan, menyimpan database lama sebagai
`game.db.sebelum-pulih-WAKTU`, lalu menyalakan server lagi). Sejak v0.63.0 ada juga cadangan lengkap
mingguan kode + database (`make backup-all`, `gameserver-backup.timer`) — lihat [BACKUP.md](BACKUP.md).

**Log.** Setiap permintaan: metode, jalur, status, lama, IP, id pemain. 5xx = ERROR, 4xx (kecuali `GET /v1/battle` 404 = belum bertarung) dan permintaan
> 1 detik = WARN. Lihat: `journalctl _SYSTEMD_USER_UNIT=gameserver.service -f`.

**Koneksi klien.** GET diulang sekali bila jaringan putus; layar dunia menampilkan "Koneksi terputus",
menanyai server tiap 5 detik, lalu mengambil ulang data dan mengirim posisi yang tertunda saat tersambung.
Token yang ditolak (kedaluwarsa/dicabut) membawa pemain ke beranda untuk masuk lagi.

## Android dan performa (v0.62.0, roadmap no. 239-255)

- **APK rilis.** CI mengekspor dengan templat rilis (`--export-release`), ditandatangani kunci yang sama
  dengan APK lama (`deploy/android/debug.keystore`) supaya APK baru tetap bisa menimpa tanpa uninstall.
  Bila ekspor rilis gagal, atau manifest rilis tidak mengizinkan HTTP biasa (`usesCleartextTraffic`),
  CI kembali ke ekspor debug. Langkah "Periksa APK" memeriksa sertifikat (harus sama dengan kunci),
  nama paket, versionCode/versionName, izin INTERNET, dan mencatat ukuran serta isi terbesar.
- **Profil kualitas** ada di `client/scripts/perf.gd` (satu tempat): batas FPS (Hemat 30), jarak pandang
  kamera, jarak gambar bangunan, jumlah musuh berkeliaran, jarak LOD warga/musuh, jumlah partikel,
  jarak bayangan dan resolusi 3D.
- **Lapisan FPS & memori** (`perf_overlay.gd`), dinyalakan di Pengaturan: FPS, RAM, VRAM, panggilan
  gambar, jumlah node. Dipasang oleh `Session` agar tetap tampil saat berganti layar.
- **Uji ketahanan** di `client/tests/e2e.gd`: 8 kali pindah peta; jumlah node, objek dan node yatim
  harus stabil. Uji ini menemukan kebocoran node "body" pada setiap model pahlawan (sudah diperbaiki).
- **Aset:** gambar judul (`judul.jpg`) diimpor lossy (dulu lossless ~2 MB di dalam APK); animasi model
  diimpor dengan `trimming` agar kunci diam di awal/akhir dibuang.

## Platform Multi-Game (v0.84.0)

Satu APK = **launcher** + mesin bersama (sejak v0.85.0 tanpa game bawaan). Semua game diunduh sebagai paket `.pck` per game,
diverifikasi, lalu bisa dimainkan tanpa internet. Audit sebelum perubahan: [AUDIT_REPORT.md](AUDIT_REPORT.md).

```
client/
├── launcher/scenes/main_menu.tscn   layar pertama aplikasi (run/main_scene)
├── launcher/scripts/launcher.gd     daftar game, status, MAINKAN/DOWNLOAD/UPDATE/BATAL/HAPUS
├── core/                            mesin platform (dimuat lewat preload, tanpa class_name)
│   ├── game_manager.gd              autoload GameManager: katalog, unduh, pasang, main, keluar, sinkron
│   ├── game_registry.gd             bawaan + katalog bertanda tangan + terpasang -> status
│   ├── package_manager.gd           pasang atomik, muat (replace_files=false), rollback, hapus
│   ├── pck_reader.gd                baca header/direktori PCK tanpa memuat (cek path & mesin)
│   ├── download_manager.gd          unduh streaming + HTTP Range + batal + cek ruang
│   ├── security_manager.gd          RSA-SHA256, SHA-256 berkas, validasi manifest/id/path
│   ├── version_manager.gd           semver + kecocokan launcher/mesin
│   ├── save_manager.gd              progres per game, atomik, .bak, skema + migrasi
│   └── api_client.gd                HTTP katalog & progres (server dan token sama dengan Api)
├── config/games.json                game bawaan (kosong sejak v0.85.0)
├── config/platform.json             lokasi data platform
├── config/publisher_public.pem      kunci PUBLIK penerbit paket
├── shared/edu/                      mesin game pembelajaran (ikut APK)
├── games/adventure/                 The Last Dragon — game unduhan (TIDAK ikut APK, sejak v0.85.0)
├── games/education_sd/              game unduhan (TIDAK ikut APK)
├── games/education_smp/             game unduhan (TIDAK ikut APK)
├── scripts/                         skrip platform yang tetap di APK: autoload Api, Session, Sound, Patcher,
│                                    version, updater, build_info, perf, perf_overlay
└── assets/                          aset bersama di APK: model karakter (models/*.glb, dipakai juga SD),
                                     ikon aplikasi, musik/suara (autoload Sound)
```

**The Last Dragon** (`id adventure`, v0.85.0) dipindah dari `res://scripts`, `res://scenes`, dan aset khususnya
ke `res://games/adventure/` dan kini **game unduhan** seperti SD: pembaruan (kode, adegan, gambar, font, model
alam, model baru) cukup diunduh dari launcher (tombol UPDATE), tanpa APK baru. Alasannya: paket dimuat dengan
`replace_files=false`, jadi game yang ikut APK tidak bisa ditimpa paket. Yang tetap di APK dan butuh **patch**
(`make patch`) atau APK untuk diubah: autoload `Api`/`Session`/`Sound` (state pemain, akun, suara) dan model
karakter bersama. Model: `models.gd` mencari `res://games/adventure/assets/models/<id>.glb` dulu, lalu
`res://assets/models/` — jadi model baru/perbaikan model cukup ditaruh di paket. Skrip game tanpa `class_name`
(kelas global paket tidak masuk cache kelas APK); pakai `const X = preload(...)`. Progres tetap di server
(`players.state`). Rilis pembaruan: naikkan `version` di `client/games/adventure/game.json`, lalu
`make game-pack GAMES=adventure`.

**Siklus hidup** (`GameManager`): `play(id)` → (paket unduhan: verifikasi SHA-256 + direktori PCK, muat
dengan `replace_files=false`, bila gagal dan ada versi lama → rollback otomatis) → `change_scene_to_file(entry)`.
`exit_to_launcher()` → sinyal `game_exiting` + `platform_before_exit()` milik game (simpan progres) → hentikan
suara → ganti ke adegan launcher (adegan game dilepas). Hanya satu game aktif. Game hanya dimuat saat
dipilih (lazy). Paket yang sudah dimuat tidak bisa dilepas oleh Godot 4.7; versi lain dari game yang sama
butuh aplikasi dibuka ulang.

**Data di HP** (`user://user_data/`): `registry/` (catalog.json + .sig, installed.json + .bak, launcher.cfg,
sync_pending.json), `packages/<id>/<versi>-<sha8>.pck` (versi aktif + satu sebelumnya), `progress/<id>/save.json`
(+ .bak), `cache/downloads/*.part`.

**Server**: endpoint `/v1/games...` (lihat [API_DOCUMENTATION.md](API_DOCUMENTATION.md)) melayani berkas dari
folder katalog (`GAME_CATALOG_DIR`, bawaan `catalog/`). Server tidak memegang kunci privat. Progres game
selain Petualangan disimpan di tabel `game_progress` (skema v5), satu baris per (pemain, game).

Dokumen terkait: [GAME_MODULE_GUIDE.md](GAME_MODULE_GUIDE.md), [PCK_PACKAGE_FORMAT.md](PCK_PACKAGE_FORMAT.md),
[DOWNLOAD_SYSTEM.md](DOWNLOAD_SYSTEM.md), [SECURITY.md](SECURITY.md), [ANDROID_BUILD.md](ANDROID_BUILD.md),
[TEST_REPORT.md](TEST_REPORT.md), [CHANGELOG.md](CHANGELOG.md).
