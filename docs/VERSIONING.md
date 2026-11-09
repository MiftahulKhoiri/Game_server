# Versi dan update

Dua hal yang dijawab sistem ini: **aplikasi di HP sekarang versi berapa**, dan
**apakah perlu update**.

## Format

`MAJOR.MINOR.PATCH`, contoh `0.3.0`.

| Bagian | Naik bila |
|--------|-----------|
| MAJOR | Perubahan besar yang memutus data/permainan lama |
| MINOR | Fitur baru (peta baru, musuh, sistem baru) |
| PATCH | Perbaikan bug kecil |

Selain itu tiap APK punya **nomor build** (urutan build di GitHub Actions) dan
kode commit. Contoh tampilan: `v0.3.0 (build 12)`. Build lokal/editor tampil
sebagai `v0.3.0 (dev)`.

## Di mana versi disimpan

| Apa | Lokasi | Siapa yang mengubah |
|-----|--------|---------------------|
| Versi aplikasi | `config/version` di `client/project.godot` | Manusia/Claude saat merilis |
| Nomor build, commit | `client/scripts/build_info.gd` | CI otomatis |
| Versi server | `Server` di `internal/version/version.go` | Manusia/Claude saat merilis |
| Versi klien minimum / terbaru | `DefaultMinClient`, `DefaultLatestClient` di `internal/version/version.go`, atau env `GAME_MIN_CLIENT`, `GAME_LATEST_CLIENT` | Pemilik server |

Server dan klien tidak harus selalu sama nomornya; yang menentukan adalah
`min_client` dan `latest_client`.

## Cara kerja di HP

1. Saat layar masuk dibuka, aplikasi menanyakan `GET /v1/version` ke server.
2. Di bawah layar tampil `Aplikasi v0.3.0 (build 12) | Server v0.3.0`.
3. Hasil perbandingan:

| Keadaan | Yang terjadi |
|---------|--------------|
| Versi aplikasi >= `latest_client` | Tidak ada pemberitahuan |
| `min_client` <= versi < `latest_client` | Tulisan kuning "Versi baru tersedia" + tombol unduh; tetap boleh main |
| Versi < `min_client` | Tulisan merah "Wajib update"; tombol mulai dikunci; hanya tombol unduh yang aktif |

4. Setiap permintaan membawa header `X-Client-Version`. Jika server dinaikkan
   `min_client`-nya saat pemain sedang main, server menjawab `426` dan aplikasi
   menampilkan pesan update. Jadi aplikasi lama tidak bisa merusak data.

Aplikasi sangat lama (sebelum 0.2.0) belum mengirim versi, jadi tidak bisa
dipaksa update; mereka tetap dilayani.

## Update dalam aplikasi (v0.12.0)

Tombol "Unduh versi baru" / "Update sekarang" tidak lagi membuka web. Di Android,
`client/scripts/updater.gd` bekerja sendiri:

1. Meminta izin **Pasang aplikasi tak dikenal** untuk Game Petualang (sekali saja;
   Android membukakan pengaturannya, pemain mengaktifkan lalu kembali dan menekan tombol lagi).
2. Membaca rilis terbaru lewat API GitHub (alamatnya diturunkan dari `update_url`),
   mengunduh APK dengan bilah kemajuan, lalu memeriksa ukuran dan sha256 dari GitHub.
3. Menyalin APK ke folder Download lewat MediaStore dan membuka pemasang Android.
   Pemain cukup menekan **Pasang**; aplikasi restart sendiri.

Bila ada langkah yang gagal, atau bukan Android, tombol berubah menjadi "Buka halaman
unduhan" (cara lama). Syarat agar APK baru diterima sebagai pembaruan: ditandatangani
dengan kunci yang sama (`deploy/android/debug.keystore`) dan `version code` lebih tinggi
(otomatis dari nomor build CI). Pasang otomatis butuh Android 10 ke atas.

Sejak v0.13.1 langkah pasang tidak memakai bidang statis Java, mencoba `ACTION_VIEW` lalu
`INSTALL_PACKAGE`, dan bila gagal pesan di layar menyebut langkah serta kesalahan Androidnya.
Berkas hasil unduhan juga tersimpan di `Download/` dengan nama yang sama dengan aset rilis
(mis. `GamePetualang-v0.15.1-build41.apk`) sehingga bisa dibuka manual lewat aplikasi File.

v0.15.1 memperbaiki pasang otomatis yang berhenti diam-diam: `resolver.delete(..., null)`
ditolak wrapper Java Godot (parameter `String[]` tidak menerima `null`), sehingga fungsi
terhenti sebelum berkas dibuat dan layar tetap melapor sukses. Kini argumen itu
`PackedStringArray()`, sukses hanya bila hasilnya persis `OK`, dan kegagalan diam-diam
menampilkan langkah terakhir yang dimulai. Aturan untuk kode Java-dari-GDScript: jangan
pernah mengoper `null` ke parameter String/array.

Versi yang memuat fitur ini sendiri harus dipasang manual sekali; setelah itu
pembaruan berikutnya bisa lewat dalam aplikasi.

## Cara merilis versi baru

1. Naikkan `config/version` di `client/project.godot` (mis. `0.3.0`).
2. Jika server ikut berubah, naikkan `Server` di `internal/version/version.go`.
3. Naikkan `DefaultLatestClient` ke versi yang sama (atau set `GAME_LATEST_CLIENT`
   di server). Pemain akan melihat ajakan update.
4. Naikkan `DefaultMinClient` (atau `GAME_MIN_CLIENT`) **hanya** jika versi lama
   tidak boleh dipakai lagi, misalnya format simpanan berubah.
5. Commit dan push ke `main`. CI menguji dan membangun APK.
6. Beri tag yang sama dengan versi: `git tag v0.3.0 && git push origin v0.3.0`.
   CI membuat **Release** berisi APK bernama `GamePetualang-v0.3.0-buildN.apk`.
   CI menolak tag yang berbeda dengan `config/version`.
7. Mulai ulang server di Pi (`make build` lalu restart layanan).

`DefaultUpdateURL` (atau `GAME_UPDATE_URL`) menentukan ke mana tombol unduh
membawa pemain; bawaannya halaman Releases terbaru.

## Catatan

- v0.16.0 menambah akun (email + kata sandi, `POST /v1/login`). Aplikasi lama tidak bisa daftar
  (kata sandi wajib), jadi `DefaultMinClient` dinaikkan ke 0.16.0: aplikasi lama diminta update.

- v0.17.0 menambah model 3D berrangka (Blender) + animasi idle/jalan/serang/luka/mati untuk
  petani, goblin penjaga, ogre batu, serigala, ular, belalang, dan kelelawar. Tidak mengubah API;
  `DefaultMinClient` tetap 0.16.0.

- v0.17.1 menata ulang layar awal: tes server (menciut dengan tanda centang hijau), tombol
  Daftar/Masuk di tengah, info pembaruan di dasar, dan isi layar naik otomatis saat papan ketik muncul.
  Tidak mengubah API.

- v0.17.2 memecah layar awal jadi halaman: Beranda (hanya tombol Masuk, Daftar, Pengaturan),
  halaman Masuk, Daftar, dan Pengaturan (alamat server, keluar akun, info pembaruan APK).
  Tidak mengubah API.

- v0.18.0 mengubah pertarungan jadi real-time dengan cooldown (aksi `skill1`, `skill2`, respons
  `battle` relatif-waktu, `events`). Klien lama (bergiliran) tidak cocok, jadi `DefaultMinClient`
  dinaikkan ke 0.18.0.

- v0.19.0 menambah pilihan pahlawan (`state.hero`, `GET /v1/heroes`, `POST /v1/players/me/hero`) dan
  layar Profil di klien. Hanya menambah; `DefaultMinClient` tetap 0.18.0. Pada rilis yang sama
  semua model musuh diganti model CC0 seragam dan nama tampilan musuh berubah (id tetap).

- v0.20.0 menambah 5 misi sampingan (termasuk jenis "antar barang"), efek pertarungan di klien
  (percikan, kilatan, getar kamera), dan dunia hidup (siang-malam, hujan, NPC bergerak). API hanya menambah field `collect_id` pada misi;
  `DefaultMinClient` tetap 0.18.0. Klien lama masih jalan, tetapi dialog NPC-nya hanya
  menampilkan misi pertama yang belum selesai, jadi misi baru butuh klien 0.20.0.

- v0.21.0 memperlebar Desa Awal (15x20 -> 25x30; server menerima posisi sampai (24,29)), menambah 10 warga
  desa yang berjalan bebas dengan dialog mengikuti alur cerita, dan mengganti model Nenek dan Petani dengan
  model KayKit berrangka. API tidak berubah; `DefaultMinClient` tetap 0.18.0. Klien lama masih jalan, tetapi
  pemain yang tersimpan di bagian desa yang baru (x >= 15 atau y >= 20) dipindahkan ke tempat bebas terdekat.

- v0.22.0 memperlebar Desa Awal lagi (25x30 -> 45x50; server menerima posisi sampai (44,49)) dengan sungai
  berjembatan, ladang, kolam, dan 11 warga, serta memperbaiki model Nenek, Petani, dan warga yang tampil putih
  polos (tekstur hilang saat diekspor dari Blender). API tidak berubah; `DefaultMinClient` tetap 0.18.0. Klien
  lama masih jalan, tetapi pemain yang tersimpan di bagian desa yang baru (x >= 25 atau y >= 30) dipindahkan
  ke tempat bebas terdekat.

- v0.23.0 mengganti rumah kotak di desa dengan model bangunan KayKit (CC0, atap merah-cokelat): rumah pribadi
  (dua bentuk), toko, dapur (kedai), dan rumah sakit (gereja), serta alas jerami di dua kandang berpagar. Hanya
  tampilan klien; server dan API tidak berubah, `DefaultMinClient` tetap 0.18.0.

- v0.24.0 mengganti layar awal (Beranda) dengan diorama 3D senja: pahlawan berjubah di atas batu, pemanah, monster
  mengepung, dan istana jauh, dengan judul emas "PETUALANGAN" dan pita merah "MEMBERANTAS MONSTER". Halaman Masuk,
  Daftar, dan Pengaturan tampil di atas diorama yang digelapkan. Hanya tampilan klien; server dan API tidak
  berubah, `DefaultMinClient` tetap 0.18.0.

- v0.25.0 memakai gambar judul resmi ("PETUALANGAN - MEMBERANTAS MONSTER") sebagai kepala layar awal
  (`client/assets/ui/judul.jpg`), memudar ke latar gelap di atas tombol Masuk, Daftar, dan Pengaturan. Diorama 3D
  v0.24.0 tetap ada sebagai cadangan bila gambar tidak ditemukan. Hanya tampilan klien; server dan API tidak
  berubah, `DefaultMinClient` tetap 0.18.0.

- v0.26.0 memperbesar semua rumah (toko, dapur, rumah sakit, rumah pribadi) sekitar 1,45x dan meringankan
  beban grafis: objek dunia dipecah per kelompok sehingga yang di luar layar tidak digambar, bayangan dimatikan
  untuk benda kecil (rumput, kerikil, alas), dan resolusi 3D mengikuti pengaturan kualitas (Hemat 60%,
  Normal 75%, Tinggi 100%; antarmuka tetap tajam). Segitiga yang digambar per bingkai di Desa Awal turun dari
  sekitar 85 ribu menjadi 30 ribu. MSAA pertarungan hanya di kualitas Tinggi. Server dan API tidak berubah,
  `DefaultMinClient` tetap 0.18.0.

- v0.27.0 memindahkan tombol Tas dan Toko ke Menu, menampilkan tombol Bicara hanya saat dekat warga (atau
  "Buka peti" saat dekat peti), dan mengganti area itu dengan empat tombol aksi: Tangan (pukul, tinju, tebas
  pedang, kombo 3 ayunan), Kaki (tendang pendek/jauh), Perisai (menghindar/bertahan), dan Boost (keahlian
  super, butuh energi penuh). Pohon, batu, dan rumput kini bisa dihancurkan dan memberi hadiah acak (emas,
  ramuan, Berlian, Ramuan Kekuatan); tumbuh kembali setelah 10 menit. Ada peti harta karun di tiap blok peta
  (9 peti, bonus besar, isi ulang 30 menit). Item baru: `berlian` dan `ramuan_kekuatan` (+30% serangan untuk
  3 pertarungan berikutnya). Endpoint baru: `GET /v1/world`, `POST /v1/world/break`, `POST /v1/world/chest`.
  Server yang mengundi hadiah; `DefaultMinClient` tetap 0.18.0 (klien lama tetap jalan, hanya tidak bisa
  menghancurkan objek).

- v0.28.0 melebarkan Perbatasan (hutan) dan Gunung Batu dari 15x20 menjadi 45x50 petak, sama besar dengan
  Desa Awal. Hutan: jalan raja berkelok, tujuh bukaan ladang monster, dua reruntuhan benteng, dua kolam. Gunung:
  jalur berkelok dengan tujuh dataran berkerikil di kiri-kanan. Peti harta bertambah dari 2 menjadi 5 per peta
  (total 16), dengan id lama `perbatasan_1/2` dan `gunung_1/2` dipindah ke posisi baru. Pintu antar-peta
  dipindah ke tengah (x=22). Server: ukuran peta di `worldMaps` dan daftar peta di `chests`. Gua Batu tidak
  berubah. `DefaultMinClient` tetap 0.18.0; pemain yang tersimpan di dalam peta lama dipindahkan ke petak
  bebas terdekat oleh klien baru.

- v0.29.0 mengganti tampilan kesehatan menjadi tanda + merah dengan bar yang bergerak sesuai persentase nyawa,
  lencana level di atasnya, dan bar "Poin" (XP) biru. Level naik dari poin hasil membunuh monster. Musuh dibuat
  bertema: hutan = binatang buas (`ular_hutan`, `serigala_hutan`, `babi_hutan`, `serigala_alfa`), gunung =
  goblin (`goblin`, `goblin_pemburu`, `ogre_batu`), gua = orc (`orc_gua`, `orc_penjaga`, `orc_buas`) dengan
  `raja_goblin` sebagai bos. Musuh kerangka dan golem lava dipensiunkan dari undian acak. Musuh kini terlihat
  berkeliaran di Desa, Perbatasan, Gunung Batu, dan Gua Batu; mengejar bila pemain mendekat, dan menyentuh atau
  memukulnya memulai pertarungan sungguhan. `POST /v1/battle/start` menerima kolom opsional `enemy`; server
  hanya menurutinya bila musuh itu non-bos, sesuai zona peta, dan level pemain cukup, selain itu server
  memilih sendiri. Teks misi dan dialog disesuaikan; item `taring_goblin` bernama "Taring Goblin".
  `DefaultMinClient` tetap 0.18.0.

- v0.30.0 merapikan tampilan layar: tombol "Bicara"/"Buka peti" kini melayang tepat di atas nama NPC atau peti
  yang dituju (mengikuti kamera); bar nyawa berubah warna seperti baterai (hijau stabilo saat penuh, kuning,
  oranye, merah saat menipis); nama pemain berada di atas lencana level; jumlah emas ditampilkan dengan ikon
  koin emas; ramuan dan barang lain tidak lagi ditulis di layar utama melainkan disimpan di **Ransel**
  (sebelumnya "Tas") yang dibuka dari Menu, dan perolehan barang memunculkan petunjuk "Barang masuk Ransel".
  Pesan server "tas penuh" menjadi "ransel penuh". Hanya klien yang berubah; `DefaultMinClient` tetap 0.18.0.

- v0.31.0 memasang pagar kayu besar (lambang peta `P`: batang runcing setinggi 1,6-2 petak dengan palang) di
  seluruh tepi Desa Awal, menggantikan deretan pohon di tepi (sungai tetap mengalir keluar), dan gapura
  bermenara (`N`: dua menara batu beratap merah mengapit jalan keluar, jembatan batu, papan "DESA AWAL").
  Di luar pagar ada jalan lanjutan dan pohon latar tanpa tabrakan. HUD diperkecil (bar nyawa, level, koin);
  nama pemain memakai font game Lilita One (SIL OFL, `client/assets/fonts/`) berwarna emas bertepi cokelat;
  tombol Menu menjadi tombol gelembung biru mengilap (`menu_bubble.gd`). Hanya klien yang berubah;
  `DefaultMinClient` tetap 0.18.0.

- v0.32.0 mengganti sumur desa dengan menara lampu besar (tempat berkumpul), memasang dua lampu di atas gapura
  dan lampu di tiap rumah yang menyala otomatis saat malam (19:00-05:00), serta rumah kepala suku (kastil merah)
  dengan dialognya. Saat malam warga pulang ke rumah masing-masing; satu pengawal tetap berjaga di gerbang.
  Musuh dipindah dari Desa Awal ke hutan Perbatasan (zona musuh di server berubah, teks misi disesuaikan).
  Perkelahian kini langsung di dunia seperti memukul batu/pohon, tanpa pindah layar (Tangan=serang, Kaki=skill,
  Perisai=bertahan, Ramuan, Kabur); bos tetap memakai layar pertarungan. Perbaikan babi hutan yang tak terlihat
  (material model transparan dipaksa solid). `DefaultMinClient` tetap 0.18.0.

- v0.33.0 memasang gapura bermenara "DESA AWAL" di tepi utara hutan Perbatasan, tepat di jalan menuju Desa Awal,
  lengkap dengan pagar kayu di kiri-kanannya, papan nama yang menghadap ke hutan, dua lampu yang menyala saat
  malam, dan jalan serta pohon latar di luar gapura. Batas desa dan hutan jadi jelas dan jalan pulang mudah
  dikenali. Hanya klien yang berubah; `DefaultMinClient` tetap 0.18.0.

- v0.34.0 menata ulang Desa Awal: sungai tidak lagi membelah desa, tetapi hanya berupa parit yang mengelilingi
  tiap ladang (dengan jembatan kayu di depan pintu ladang); pos jaga di timur gapura (penjaga masuk ke dalamnya
  saat malam, jendelanya menyala); basecamp pahlawan di barat gerbang (dua tenda, api unggun yang menyala dan
  bergoyang, dummy latihan, tiang panji dengan papan "BASECAMP PAHLAWAN"); dan kandang ayam di tiap kandang
  berpagar (keempat ayam masuk ke kandang saat malam). Lambang peta baru: `J` pos jaga, `C` kandang ayam,
  `A` tenda, `U` api unggun, `Q` dummy latihan, `Y` tiang panji. Hanya klien yang berubah; `DefaultMinClient`
  tetap 0.18.0.

- v0.35.0 memperbaiki arah pintu di Desa Awal: pos jaga kini bangunan terbuka (atap, dinding belakang, empat
  tiang) yang menghadap jalan utama, dan penjaga berdiri di dalamnya saat malam (tetap terlihat, bisa diajak
  bicara); basecamp ditata ulang dengan dua tenda yang pintunya menghadap api unggun dan jalan utama; dan tiap
  rumah/pondok/basecamp punya jalan tanah yang tersambung ke jalan utama (jalan baru di baris z=23, 33, 42, 45).
  Data warga baru: `arah` (arah muka bangunan) dan `terlihat` (tetap terlihat di dalam). Hanya klien yang
  berubah; `DefaultMinClient` tetap 0.18.0.

- v0.36.0 mengganti ikon aplikasi: ksatria berpedang dan ksatria perempuan pemanah (model karakter game
  sendiri) di depan matahari terbenam. Berkas di `client/assets/icon/` (`icon_512.png`, `main_192.png`,
  `adaptive_foreground_432.png`, `adaptive_background_432.png`), dipasang lewat `launcher_icons/*` di
  `client/export_presets.cfg` dan `config/icon` di `project.godot`. Hanya klien yang berubah;
  `DefaultMinClient` tetap 0.18.0.

- v0.37.0 memperluas peta Desa Awal jadi 85x50: pagar timur punya celah di jalan utama menuju hutan belantara
  timur (jalan setapak utara-selatan, 3 kolam, kebun buah, reruntuhan, tambang batu, hutan selatan; banyak pohon,
  batu, dan rumput yang bisa dihancurkan untuk emas/ramuan/berlian, plus 6 peti baru `timur_1..6`). Server ikut
  berubah (`worldMaps` desa_awal lebar 85, peti baru di `loot.go`). Pagar kiri/kanan diperbaiki (palang kini
  searah pagar, bukan salah posisi). Tombol aksi baru: **Lompat**; **Tangan** 1x tinju dobel, 2x tebas dobel,
  3x tusuk; **Kaki** 1x tendang, 2x tendangan dobel (gerakan kaki sungguhan, bukan tebasan); **Perisai** 1x
  angkat perisai dan tetap di tempat, 2x cepat menghindar. Gerakan tubuh lewat `hero_actions.gd`
  (SkeletonModifier3D di atas klip idle/jalan). `DefaultMinClient` tetap 0.18.0.

- v0.38.0 menata ulang HUD, menambah suara, ikon barang, dan pahlawan pendamping. (1) Jam pindah ke tengah
  atas, di antara nama pemain dan tombol Menu, berikon matahari (siang) atau bulan (malam), ikon gua di Gua
  Batu (`client/scripts/clock_badge.gd`). (2) Pengaturan: Suara orang (NPC) dan Musik (nyala/mati) serta volume
  masing-masing, tersimpan di HP; musik latar desa dan suara bicara NPC (dipakai di layar dialog) dibuat sendiri
  lewat `tools/gen_suara.py` (autoload `Sound`, `client/assets/audio/`). (3) Ikon 11 barang
  (`client/assets/items/<id>.png`, dibuat `tools/gen_ikon_item.py`) dipakai di Toko, Ransel, dan Atribut.
  (4)+(5) Menu baru **Atribut**: tab Perlengkapan (ganti senjata/pelindung, lihat serangan dan pertahanan) dan tab
  Pendamping (beli pahlawan, pasang maks 3 di belakang pemain). Server: `state.allies` / `state.party`,
  `POST /v1/allies/buy`, `POST /v1/party`, `price` di `GET /v1/heroes`, dan serangan otomatis pendamping di
  pertarungan (`internal/game/ally.go`, kejadian `who: "ally"`). Klien lama tetap jalan; `DefaultMinClient`
  tetap 0.18.0.

- v0.39.0 menambah energi, toko di bangunannya, rumah makan, dan penjaga. (1) Level di HUD kini berbentuk
  **piala (tropi)** bernomor level. (2) **Energi (kekuatan)**: bar berikon petir di bawah bar nyawa. Jurus
  memakainya (Skill 1 = 20, Skill 2 = 25), serangan biasa mengisi 4, menang mengisi 15, naik level dan
  istirahat memenuhkan, dan **Ramuan Kekuatan** (kini dijual 40 emas) mengisi 60 di samping menaikkan serangan.
  Server: `state.energy_used` (0 = penuh; data lama otomatis penuh), `MaxEnergy` 100, galat `energi tidak cukup`
  (`internal/game/energy.go`). (3) Tombol **Toko dihapus dari Menu**: belanja hanya lewat penjaga toko di depan
  pintu bangunannya (ketuk Bicara). Tiap toko punya penjaga: Pak Darman (Toko Ramuan: ramuan, ramuan kekuatan,
  senjata, pelindung), Bu Wati (Rumah Makan: Roti Hangat +10, Sup Ayam +25, Daging Bakar +50 HP), dan
  Suster Mira (rumah sehat: pulihkan HP dan energi gratis). Makanan dimakan dari Ransel (atau langsung di
  rumah makan). Server: `GET /v1/shop?shop=toko|makan|semua`, `shop` di badan `POST /v1/shop/buy|sell`
  (kosong = toko ramuan; barang di toko yang salah ditolak 422, toko asing 404), `shop`/`heal` di daftar
  barang, jenis barang `food`. Klien lama tetap jalan; `DefaultMinClient` tetap 0.18.0.

- v0.40.0 menambah **ruangan di dalam bangunan**. Pintu Toko Ramuan, Rumah Makan, dan Rumah Sehat di desa kini
  jalan masuk sungguhan: pemain melangkah ke pintu lalu masuk ke ruangan 9x8 (peta `toko_ramuan`, `rumah_makan`,
  `rumah_sehat`) berisi lantai kayu, rak dagangan (botol ramuan / roti dan toples / ranjang), meja kasir, tong,
  meja makan, karpet, dan papan nama, digambar kode (`client/scripts/interior.gd`) tanpa aset luar. Penjaga
  (Pak Darman, Bu Wati, Suster Mira) berdiri di balik meja kasir; ketuk **Bicara** dari depan meja untuk berbelanja
  (jangkauan penjaga 2,3 petak), keluar lewat keset "Keluar" di bawah. Kamera di dalam ruangan condong ke dalam
  agar meja dan penjaga terlihat; jam menampilkan nama ruangan. Server: tiga peta baru di `worldMaps` (9x8) dan
  istirahat gratis berlaku di desa dan ruangan-ruangan itu (`InVillage`). Penjaga tidak lagi berdiri di jalan
  depan pintu. Klien lama tetap jalan; `DefaultMinClient` tetap 0.18.0.

- v0.41.0 menambah **plang dan ikon atap** di bangunan toko Desa Awal, serta **Toko Peralatan** baru. Tiap bangunan toko
  punya papan nama berdiri di kanan jalan menuju pintunya (TOKO RAMUAN, RUMAH MAKAN, TOKO PERALATAN, RUMAH SEHAT) dan ikon
  besar di atap atau depan atap: botol ramuan (toko ramuan), piza (rumah makan, di atas tong), pedang dan kapak bersilang
  (toko peralatan), palang merah (rumah sehat); semuanya digambar kode (`client/scripts/plang.gd`). Toko Peralatan adalah
  bangunan baru di ujung barat deretan rumah (pintu di petak 4,2) dengan ruangan sendiri (peta `toko_peralatan`, 9x8, rak
  pedang/perisai/helm, landasan tempa, patung zirah) dan penjaga Pak Hasan. Server: pedang besi, pedang baja, baju kulit,
  dan zirah besi kini hanya dijual dan dibeli di toko `peralatan` (`ShopGear`); toko ramuan hanya ramuan dan harta.
  `GET /v1/shop?shop=peralatan` dan `shop` di `/v1/shop/buy|sell` menerima `peralatan`. Istirahat gratis juga sah di
  ruangan baru (`InVillage`). Klien lama tetap jalan; `DefaultMinClient` tetap 0.18.0.

- v0.42.0 mengubah suasana desa dan menjadikan **Basecamp Pahlawan** tempat merekrut. Meja toko diturunkan agar penjaga
  terlihat. Gerbang Desa Awal dan Perbatasan dilebarkan jadi tiga petak dan ditinggikan (menara tinggi, tiga lampu, papan
  lebih besar). Di basecamp, tenda merah (Komandan Raka) merekrut **pahlawan berkelas** dan tenda hijau (Sersan Joni)
  menjual **prajurit biasa** satu per satu (maks 5, 60 emas; `POST /v1/soldiers/buy`, bidang `soldiers` di state).
  Prajurit ikut bertarung sebagai pasukan terpisah (serangan lemah, tidak memakai 3 slot pahlawan). Beli pahlawan di layar
  Atribut dimatikan; arahkan ke basecamp. Klien lama tetap jalan; `DefaultMinClient` tetap 0.18.0.

- v0.43.0 menambah **Aula Pelatihan**: bangunan baru di Desa Awal (pintu di petak 38,20, plang AULA PELATIHAN, ikon perisai
  dan pedang di atap) dengan ruangan sendiri (peta `aula_pelatihan`, 11x8) dan dua pelatih: Guru Bima (panggung merah)
  melatih pahlawan pembantu berkelas, Sersan Anton (panggung hijau) melatih pasukan prajurit biasa. Tiap latihan memakai
  emas, 1 **Kartu Keahlian**, dan energi (dibayar di awal), lalu berjalan menurut jam server (juga saat game ditutup);
  hasilnya diambil lewat tombol Ambil. Makin tinggi level, makin mahal dan makin lama (pahlawan 10 menit x level, prajurit
  5 menit x level; maks level 20). Level pahlawan per pahlawan, level prajurit satu untuk seluruh pasukan; level menambah
  serangan saat membantu bertarung. Kartu Keahlian dijual di Toko Peralatan (60 emas) dan dijatuhkan musuh (8%). Server:
  `POST /v1/train/start`, `POST /v1/train/claim`, `GET /v1/time`; state baru `hero_levels`, `soldier_level`, `training`.
  Klien lama tetap jalan; `DefaultMinClient` tetap 0.18.0.

- v0.44.0 menjadikan **Berlian** barang paling berharga: dijual 500 emas (dulu 100) atau **ditukar (barter) dengan barang apa
  saja** di toko mana pun: tiap baris "Beli" kini punya tombol "N Berlian" (N = harga / 500 dibulatkan ke atas, minimal 1).
  Server: `POST /v1/shop/barter` (`BarterAt`). **Peti harta** kini memberi **3 hadiah acak yang berbeda** (emas, ramuan, ramuan
  kekuatan, kartu keahlian, koin kuno, permata merah, dan berlian bila beruntung; peluang berlian naik menurut tingkat peti)
  dan modelnya diperkecil (skala 0,7). Klien lama tetap jalan; `DefaultMinClient` tetap 0.18.0.

- v0.45.0 (klien saja): **pagar kandang ayam** digambar mengikuti arah pagar (palang memanjang ke utara-selatan/timur-barat,
  tiang di tiap petak, tiang sudut lebih tinggi) sehingga tidak lagi terpotong-potong; **Pengaturan** di beranda kini punya bagian
  **Layar** (kualitas grafis, kecepatan putar kamera, layar tetap menyala) dan **Suara** (suara NPC, musik, volume); **HUD** kiri
  atas ditata ulang (jarak antar baris dilebarkan, angka nyawa tampil) dan menampilkan **jumlah berlian di atas koin emas**.
  Server tidak berubah. `DefaultMinClient` tetap 0.18.0.

- v0.46.0 menambah **Hutan Lebat** (peta 170x50, dua kali lebar Desa Awal) di selatan Perbatasan dan **Gua Goblin** (peta 3, 25x30).
  Di hutan pemain harus mengalahkan **100 binatang** (kancil, rubah, ular belang, babi bertaring, serigala hitam, beruang) lalu
  bos **Goblin Level 1** muncul di singgasana (85,25); setelah ia kalah muncul lagi 100 binatang, lalu Goblin Level 2, dst. sampai
  **Goblin Level 3**. Setelah ketiganya kalah gerbang ke Gua Goblin terbuka (gerbang dikunci di klien; Gua Goblin lalu menuju
  Gunung Batu). Server menghitung kemajuan (state baru `hutan {wave, kills}`; `POST /v1/battle/start {"boss":true}` di singgasana
  menjawab `422` bila binatang belum habis), enam peti baru di hutan dan tiga di gua. **Pendamping** kini maju mengepung musuh
  yang mengejar atau sedang dilawan (dulu hanya ikut berjalan) dan membantu menyerang lebih cepat (pukulan pertama 0,8 d, lalu
  tiap 1,8 d). `DefaultMinClient` tetap 0.18.0.

- v0.47.0 menyempurnakan **Hutan Lebat**: jalan tanah kini **lebar tiga petak dan selalu menyambung** (pintu masuk -> kem -> singgasana
  -> gerbang Gua Goblin, plus dua lingkaran jalan untuk pulang). Di dekat pintu masuk ada **kem** (api unggun, empat tenda, panji) yang
  menjadi zona aman tanpa binatang; **Kapten Rimba** menunggu di sana dan, lewat tombol **Bicara**, menjelaskan tugas sesuai kemajuan
  (binatang X/100, Goblin ke berapa). **Papan misi** di layar hutan menampilkan "Binatang X/100", kemajuan Goblin, dan tiga **panah
  penunjuk arah** (singgasana, gerbang gua, kem/pulang) lengkap dengan jaraknya. **Goblin Level 1-3 kini bertarung di dunia seperti
  binatang** (berkeliaran di sekitar singgasana, mengejar, lalu pertarungan langsung; hanya HP dan seranganya lebih besar), bukan layar
  pertarungan penuh. Server: `POST /v1/battle/start {"enemy":"goblin_hutan_N"}` sah bila pemain di Hutan Lebat dalam 20 petak dari
  singgasana dan 100 binatang tahap itu sudah kalah (selain itu `422`); `{"boss":true}` di petak singgasana tetap berlaku. Posisi enam
  peti hutan dipindah ke padang terbuka baru. `DefaultMinClient` tetap 0.18.0.

- v0.47.1: **kem Hutan Lebat dirapatkan ke pintu masuk**: begitu tiba dari Perbatasan, tenda, panji "KEM HUTAN", api unggun, dan Kapten Rimba
  langsung terlihat di depan (zona aman x 13-31, y 1-9), jalan tanah lurus melewatinya. Posisi enam peti hutan dipindah ulang.
  `DefaultMinClient` tetap 0.18.0.

- v0.47.2: **kem dipindah ke Perbatasan, tepat di bawah gapura desa**, jadi langsung terlihat begitu keluar dari Desa Awal: 4 tenda, 2 panji
  "KEM HUTAN", api unggun, dan **Kapten Rimba** (tombol Bicara) di sisi timur jalan (zona aman x 23-29, y 1-6; binatang tidak masuk).
  Kapten menjelaskan tugas Hutan Lebat dan arah ke sana (selatan, ujung jalan raja). Hutan Lebat tidak lagi punya kem; di papan misi
  panah hijau kini bertuliskan "Pulang" (ke pintu masuk hutan). `DefaultMinClient` tetap 0.18.0.

- APK baru harus dipasang **menimpa** yang lama (jangan hapus aplikasi), karena
  menghapus aplikasi menghapus token login.
- `version code` Android = nomor build, naik terus, sehingga HP menerima APK baru
  sebagai pembaruan.

- v0.47.3 menambah **patch isi game** (`GET /v1/patch`, `client/scripts/patcher.gd`, `make patch`):
  peta, skrip, dan adegan bisa diperbarui lewat server tanpa APK baru. APK v0.47.3 adalah APK
  terakhir yang wajib dipasang untuk fitur ini. Tidak mengubah API lama; `DefaultMinClient` tetap.

- v0.48.0 menambah **kesehatan pahlawan pendamping**: musuh bisa melukai pendamping, pendamping yang kalah
  disembunyikan dan tidak menyerang, serta bisa disembuhkan dengan ramuan (`POST /v1/allies/heal`, tombol heal
  di dunia). Lihat `docs/COMPANION_DEATH_AND_HEALING.md`. Hanya menambah; `DefaultMinClient` tetap 0.18.0.

- v0.48.1 memperbaiki simpan otomatis yang gagal ("cannot unmarshal number 30.0 into ally_hp") sesudah v0.48.0:
  klien kini mengirim HP pendamping sebagai bilangan bulat, dan server menerima bilangan bulat berdesimal (`HPMap`).
  Tidak mengubah API; `DefaultMinClient` tetap 0.18.0.

- v0.48.2 memperbarui tampilan NPC desa: Bu Sari (dan Suster Mira, yang memakai model sama) kini model stylized buatan kode,
  dan seluruh NPC warga memakai shading toon. Hanya klien; server dan API tidak berubah. `DefaultMinClient` tetap 0.18.0.

- v0.48.3 mengembalikan Bu Sari (dan Suster Mira) ke model GLB aslinya; model prosedural dari v0.48.2 dicabut karena
  tampil kusam dan kecil. Toon shading untuk NPC warga tetap. Hanya klien; `DefaultMinClient` tetap 0.18.0.

- v0.49.0 menata ulang Hutan Lebat. Peta jalan: tiga cabang (utara, tengah, selatan) selebar 2 petak yang bertemu di satu
  persimpangan tepat di depan gerbang Gua Goblin (gerbang kini 2 petak, 146-147). Singgasana bos pindah ke (142,47), dekat gerbang;
  tembok dan gapura gerbang Gua Goblin dari batu, bukan kayu. Pertarungan di hutan baru dimulai setelah bicara dengan
  Kapten Rimba, yang memberi barang khusus **Radar Musuh** (`radar_musuh`): titik musuh di layar hutan. Server: `POST /v1/hutan/brief`,
  `hutan.briefed`, `422` untuk pertarungan hutan sebelum arahan (pemain yang sudah punya kemajuan hutan dianggap sudah diarahkan).
  Item baru jenis `special` (tidak dijual). `DefaultMinClient` tetap 0.18.0.
