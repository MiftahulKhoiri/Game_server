# CHANGELOG

Riwayat rilis sebelum v0.84.0 ada di pesan commit dan tag Git (`git log --oneline`).

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
