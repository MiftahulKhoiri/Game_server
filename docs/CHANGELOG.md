# CHANGELOG

Riwayat rilis sebelum v0.84.0 ada di pesan commit dan tag Git (`git log --oneline`).

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
