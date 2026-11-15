# CHANGELOG

Riwayat rilis sebelum v0.84.0 ada di pesan commit dan tag Git (`git log --oneline`).

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
