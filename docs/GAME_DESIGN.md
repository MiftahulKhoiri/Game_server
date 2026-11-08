# Desain Game (DRAF)

> Dokumen hidup. Semua isi di bawah adalah **usulan awal** dan menunggu
> keputusan pemilik proyek. Ubah langsung atau buka issue.

## Pokok yang sudah diputuskan

- Genre: **RPG**, 2D.
- Mode: **satu pemain**; server menyimpan progress (bukan multiplayer).
- Platform: **Android (APK)**; server berjalan di Raspberry Pi 5.

## Keputusan gameplay

- Gerak: **per kotak (grid)**, tampak atas (top-down).
- Pertarungan: **real-time dengan cooldown** (sejak v0.18.0; sebelumnya bergiliran): Serang, Bertahan (tangkis tepat waktu), Skill 1 Tebasan Kuat, Skill 2 Perisai Cahaya, Ramuan, Kabur. Musuh menyerang sendiri tiap 2 d.

Alasannya hemat tenaga: gambar lebih sedikit (tanpa animasi banyak arah), logika
server mudah diuji, dan nyaman di layar sentuh.

## Tema dan gaya (diputuskan pemilik proyek, 5 Nov 2026)

- **Tema:** desa di sebuah kerajaan yang diserang monster. Pemain adalah
  ksatria kerajaan (zirah perak, perisai singa, pedang berhuruf rune) yang
  melindungi penduduk desa.
- **Dunia 3D (v0.13.0, diputuskan pemilik proyek 6 Nov 2026):** gerak bebas dengan
  kamera di belakang karakter (joystick melayang di layar kiri, geser di kanan untuk
  memutar kamera). Semua karakter, NPC, dan musuh berupa model 3D; yang belum punya
  model memakai model sederhana buatan kode, dan dapat diganti dengan menaruh
  `client/assets/models/<id>.glb`. Server tetap pakai petak (tabrakan di klien).
  Pertarungan tetap bergiliran, kini di arena 3D.
- **Gaya gambar (2D lama, dipakai di dialog/toko):** ilustrasi berwarna bergaya komik/lukisan dengan garis tepi
  tebal, bukan pixel art. Karakter, NPC, dan musuh digambar utuh (potret/badan
  penuh) dan dipakai di layar pertarungan dan dialog. Tile peta tetap kecil.
- **Gambar karakter yang sudah ada** (`client/assets/`): ksatria (pemain),
  nenek penjual sayur dan petani (NPC), goblin (musuh). Ogre batu menyusul.
- Gambar masuk bertahap; yang belum ada memakai placeholder.

## Keputusan desain (pemilik proyek, 5 Nov 2026)

1. **Musuh bertambah mengikuti level.** Musuh paling awal paling lemah; tiap naik
   level ada musuh baru yang lebih kuat. Satu musuh baru = satu baris di
   `internal/game/enemy.go` (`MinLevel` menentukan kapan muncul) + gambar
   `client/assets/enemies/<id>.png`. Hama sawah (tikus, belalang, ular, babi hutan)
   dipertahankan sebagai musuh awal; monster menyusul seiring gambarnya tersedia.
2. **Penduduk yang diselamatkan memberi hadiah.** Bila misi berhasil, NPC yang
   ditolong (nenek penjual sayur, petani, dst.) langsung memberikan hadiah
   (emas dan barang). Sistem misi di server: lihat "Rencana misi" di bawah.
3. **Pilihan ksatria.** Pemain nanti bisa memilih ksatria. Saat ini hanya satu
   (`client/assets/characters/ksatria.png`); ksatria lain ditambahkan bertahap
   setelah gambarnya ada.
4. **Nuansa:** kerajaan yang harus dilindungi dari serangan monster.
5. **Barang** dipakai sebagai hadiah misi dan sebagai dagangan toko.

## Barang (v0.5.0)

Daftar ada di `internal/game/item.go`. Barang baru = satu baris di sana + (opsional)
gambar `client/assets/items/<id>.png`; tanpa gambar klien memakai kotak berwarna.

| Id | Nama | Jenis | Beli | Jual |
|----|------|-------|------|------|
| `ramuan` | Ramuan Penyembuh | consumable | 15 | 6 |
| `taring_goblin` | Taring Orc | material (jatuhan orc 35%) | - | 12 |
| `koin_kuno` | Koin Kuno | treasure (hadiah misi) | - | 25 |
| `permata_merah` | Permata Merah | treasure (hadiah misi) | - | 60 |

| `pedang_besi` | Pedang Besi | senjata, serang +3 | 120 | 40 |
| `pedang_baja` | Pedang Baja | senjata, serang +6 | 320 | 110 |
| `pedang_rune` | Pedang Rune | senjata, serang +10 (hadiah misi akhir) | - | - |
| `baju_kulit` | Baju Kulit | pelindung, tahan +2 | 80 | 25 |
| `zirah_besi` | Zirah Besi | pelindung, tahan +4 | 240 | 80 |

Harga jual selalu lebih murah dari harga beli agar tidak bisa untung tanpa batas.

### Tas, perlengkapan, istirahat (v0.11.0)
Dua slot: senjata dan pelindung. Bonusnya menambah serang/tahan dari level. Ramuan
bisa diminum di luar pertarungan. Istirahat di desa gratis dan memulihkan HP penuh,
jadi ramuan dipakai untuk perjalanan jauh. Pedang Rune hanya didapat dari misi
"Hentikan Raja Goblin".

## Misi (v0.6.0)

Misi bertipe "kalahkan N musuh". Server menghitung kemenangan (klien tidak bisa
memalsukan) dan hadiah diambil satu kali dari NPC pemberi misi. Misi baru = satu
baris di `internal/game/quest.go`; NPC baru = satu entri di `client/scripts/maps.gd`
dan gambar `client/assets/characters/<id npc>.png`.

| Misi | Pemberi | Tugas | Hadiah |
|------|---------|-------|--------|
| Selamatkan Nenek | Nenek Penjual Sayur (3,6) | Usir 5 ayam liar atau kucing liar | 40 emas |
| Selamatkan Petani | Petani (11,6) | Kalahkan 3 orc ladang di Perbatasan. Terkunci sampai hadiah Nenek diambil | 25 emas + Permata Merah |
| Usir Monster Batu | Nenek (3,6) | Kalahkan 1 Monster Batu di Gunung Batu. Terkunci sampai hadiah Petani diambil | 150 emas + 2 Koin Kuno |
| Hentikan Raja Iblis | Petani (11,6) | Kalahkan Raja Iblis di Gua Batu. Terkunci sampai hadiah Ogre diambil | 500 emas + 3 Permata Merah |

### Dunia hidup (v0.20.0)

Murni tampilan di klien (`client/scripts/atmosphere.gd`), tidak memengaruhi server atau data pemain.
- **Siang-malam:** satu hari permainan = 12 menit nyata, mulai pagi. Langit, cahaya, kabut, dan arah
  matahari berubah; malam bercahaya bulan kebiruan dan tetap terang cukup untuk bermain. Jam tampil di layar.
- **Hujan:** tiap 150 detik diundi hujan atau cerah (30%, blok pertama selalu cerah); langit kelabu, kabut
  menebal, tetesan turun mengikuti pemain. Jumlah tetesan mengikuti kualitas grafis.
- **Arena pertarungan** memakai waktu dan cuaca yang sama. **Gua Batu** tidak terpengaruh.
- **NPC** menoleh ke pemain yang dekat dan berjalan pelan di dalam petaknya sendiri, jadi petak NPC
  tetap terblokir dan jangkauan bicara tidak berubah.
- **Warga desa** (`Maps.WARGA`, logika di `client/scripts/warga.gd`): 10 warga pemanis di Desa Awal
  (ibu, bapak, dua anak, penjaga, tiga ayam di kandang) berjalan bebas ke titik acak dalam jari-jari
  masing-masing, lewat petak jalan/rumput/bunga saja (tidak menembus pagar, air, atau rumah), berhenti
  sebentar, lalu lanjut. Mereka menghindari pemain dan sesama warga, tidak menghalangi, dan berhenti
  menyapa bila pemain mendekat. Tombol **Bicara** membuka dialog singkat (`client/scripts/warga_dialog.gd`)
  yang mengikuti tahap cerita utama (Nenek -> Petani -> Monster Batu -> Raja Iblis, 0-4 misi tuntas):
  tiap warga berkomentar soal ancaman yang sedang terjadi dan memberi petunjuk ke mana harus pergi
  berikutnya, dan kalimatnya berganti tiap kali diajak bicara. Dialog murni di klien (tahap dibaca dari
  `GET /v1/quests`). Model KayKit hasil `tools/blender/kaykit_npc.py` (mode ibu, ibu2, bapak, bapak2, anak).

### Misi sampingan (v0.20.0)

Tidak perlu gambar baru: pemberinya Nenek dan Petani. Dialog menampilkan misi yang paling relevan
(siap diklaim, lalu baru ditawarkan, lalu sedang dikerjakan), jadi misi utama tidak tertutup misi sampingan.

| Misi | Pemberi | Jenis | Tugas | Hadiah | Terbuka setelah |
|------|---------|-------|-------|--------|-----------------|
| Kebun yang Dirusak | Nenek | kalahkan | 3 Babi Hutan | 35 emas + Baju Kulit | Selamatkan Nenek |
| Obat untuk Pengungsi | Nenek | antar barang | 3 Taring Orc | 30 emas + 3 Ramuan | Selamatkan Nenek |
| Serigala di Jalan Raja | Petani | kalahkan | 4 Serigala Hutan | 70 emas + 2 Ramuan | Selamatkan Petani |
| Sisa Pasukan Iblis | Petani | kalahkan | 5 kerangka (gua, pejuang, penjaga) | 300 emas + Zirah Besi | Hentikan Raja Iblis |
| Permata Sumber Kekuatan | Nenek | antar barang | 3 Permata Merah | 120 emas + Pedang Baja | Hentikan Raja Iblis |

Misi antar barang: barang yang diminta diambil dari tas saat hadiah diklaim. Misi baru jenis ini =
satu baris di `internal/game/quest.go` dengan `CollectID` (tanpa `TargetIDs`).

Cara main: berdiri di sebelah Nenek, tekan **Bicara**, terima misi, lawan hama di
ladang, lalu kembali ke Nenek untuk **Ambil hadiah**.

## Masih perlu diputuskan (pemilik proyek)

1. **Cerita.** Siapa dalang serangan monster, apa tujuan akhirnya?
2. **Penduduk lain.** Siapa lagi yang perlu diselamatkan? Tiap NPC baru butuh gambar di `client/assets/characters/`.
3. **Setelah Raja Goblin.** Cerita akhir atau lanjut ke ancaman baru? Gambar Raja Goblin dan musuh gua perlu dibuat.

## Sistem yang sudah ada di server

| Data | Keterangan |
|------|------------|
| `level`, `xp` | Perkembangan karakter |
| `hp`, `max_hp` | Nyawa |
| `gold` | Mata uang |
| `map`, `x`, `y` | Lokasi di dunia |
| `inventory` | Daftar `{id, qty}` |

Pemain baru mulai di peta `desa_awal` posisi (5,5) dengan 30 HP dan 2 ramuan.

## Pertarungan (v0.3.0)

Bergiliran, dihitung server. Pemain memilih satu aksi, lalu musuh membalas.

| Rumus | Nilai |
|-------|-------|
| HP maksimum | 30 + 8 x (level - 1) |
| Serangan | 4 + 2 x level |
| Pertahanan | 1 + level |
| XP ke level berikut | 20 x level |
| Damage | max(1, serangan - pertahanan) x 80-120%; kritis pemain 10% (x1,5) |

Naik level memulihkan HP penuh. Kalah: emas berkurang separuh, HP pulih
separuh, kembali ke titik awal desa.

| Musuh | Wilayah | HP | Serang | Bertahan | XP | Emas | Min. level | Jatuhan |
|-------|---------|----|--------|----------|----|------|------------|---------|
| Ayam Liar (`tikus_sawah`) | Desa | 10 | 3 | 0 | 6 | 2 | 1 | Ramuan 10% |
| Kucing Liar (`belalang_raksasa`) | Desa | 14 | 4 | 1 | 8 | 3 | 1 | Ramuan 10% |
| Rubah Sawah (`ular_sawah`) | Desa | 20 | 6 | 1 | 12 | 5 | 2 | Ramuan 15% |
| Babi Hutan | Desa | 34 | 8 | 3 | 22 | 9 | 3 | Ramuan 25% |
| Orc Ladang (`goblin`) | Perbatasan | 26 | 7 | 2 | 15 | 7 | 1 | Taring Orc 35% |
| Serigala Hutan | Perbatasan dan Gunung Batu | 32 | 9 | 2 | 20 | 9 | 3 | Ramuan 20% |
| Kerangka Gua (`kelelawar_gua`) | Gunung Batu | 28 | 8 | 1 | 18 | 8 | 3 | Ramuan 20% |
| Kerangka Pejuang (`golem_kerikil`) | Gunung Batu | 50 | 10 | 6 | 32 | 14 | 4 | Koin Kuno 25% |
| Monster Batu (`ogre_batu`) | Gunung Batu | 70 | 12 | 5 | 45 | 25 | 5 | Permata Merah 30% |
| Kerangka Penjaga (`goblin_penjaga`) | Gua Batu | 45 | 11 | 4 | 28 | 12 | 5 | Taring Orc 50% |
| Iblis Lava (`golem_lava`) | Gua Batu | 62 | 13 | 6 | 40 | 18 | 6 | Permata Merah 20% |
| **Raja Iblis (bos, `raja_goblin`)** | Gua Batu, singgasana (7,14) | 120 | 14 | 6 | 100 | 60 | 7 | Permata Merah 100% |

Musuh dipilih dari wilayah (peta) tempat pemain berada, jadi server perlu tahu peta
terakhir yang tersimpan (klien menyimpan posisi sebelum tiap pertarungan). Serigala
Hutan, Kelelawar Gua, dan Ogre Batu kini punya model 3D berrangka dari gambar kiriman (v0.17.0);
Sejak v0.19.0 semua musuh seragam memakai model 3D low-poly CC0 (KayKit Skeletons dan Quaternius):
hewan (ayam, kucing, rubah, babi, serigala) dan monster/kerangka/iblis, semua berrangka dan beranimasi.
Nama tampilan musuh ikut berubah; id musuh (`tikus_sawah`, dst.) tidak berubah supaya data lama aman.
Bila level pemain terlalu rendah untuk sebuah wilayah, ia tetap bertemu musuh terlemah di wilayah itu.

## Pahlawan pendamping (v0.38.0)

Pahlawan (ksatria, pemanah, pendekar tombak, pendekar kapak) bisa dibeli dengan emas di menu **Atribut** lalu
dipasang berbaris di belakang pemain (maks 3). Di dunia mereka mengikuti pemain; saat bertarung mereka
menyerang musuh otomatis tiap 2,4 d (kerusakan 70% serangan dasar level pemain + 2). Pemain tetap yang
menentukan bertahan, skill, ramuan, dan kabur. Harga 250-350 emas (draf, untuk diseimbangkan).

## Energi, makanan, dan toko (v0.39.0)

- **Energi** (bar petir): jurus memakainya (Skill 1 = 20, Skill 2 = 25 dari 100); serangan biasa +4, menang +15, naik level
  atau istirahat = penuh, Ramuan Kekuatan +60 (dan serangan x1,3 tiga pertarungan).
- **Toko** dimasuki sungguhan (v0.40.0): melangkah ke pintu bangunan membawa pemain ke ruangan di dalamnya; penjaga
  berdiri di balik meja kasir dan berbelanja lewat Bicara. Keluar lewat keset di bawah ruangan. Isi toko: Toko Ramuan (Pak Darman: ramuan 15,
  ramuan kekuatan 40, senjata, pelindung), Rumah Makan (Bu Wati: Roti Hangat 8 emas +10 HP, Sup Ayam 20 +25,
  Daging Bakar 45 +50), dan rumah sehat (Suster Mira: pulih gratis). Tombol Toko di Menu dihapus.

## Bos

Bos tidak muncul acak. Injak singgasana (petak `K`); klien meminta `POST /v1/battle/start`
dengan `{"boss": true}` dan server memeriksa posisi tersimpan pemain. Bos bisa dilawan
berulang (hadiahnya: XP, emas, dan drop). Raja Iblis (id `raja_goblin`) memakai model Iblis Biru.

## Peta

| Peta | Isi | Pintu |
|------|-----|-------|
| Desa Awal (`desa_awal`, 85x50) | Hutan belantara timur lewat celah pagar timur (kolam, kebun, reruntuhan, tambang, 6 peti); tujuh rumah utara, empat rumah tengah, alun-alun, dua kandang berpagar, sungai, empat ladang berpagar dan pondok tani, dua kolam, Nenek dan Petani, serta 11 warga yang berjalan bebas (ibu, bapak, anak, penjaga, ayam) | Gerbang selatan (22,49) ke Perbatasan |
| Perbatasan Kerajaan (`perbatasan`) | Jalan raja, ladang yang dirusak monster, reruntuhan benteng | Utara (7,0) ke desa; selatan (7,19) naik ke Gunung Batu |
| Gunung Batu (`gunung_batu`) | Lereng berbatu dan kerikil, sarang Ogre Batu | Utara (7,0) ke Perbatasan; selatan (7,19) masuk Gua Batu |
| Gua Batu (`gua_batu`) | Lorong gua, sarang Raja Goblin | Utara (7,0) kembali ke Gunung Batu |

Server mengenal ukuran tiap peta (`internal/game/world.go`) dan menolak posisi di luar
peta atau peta asing. Bentuk petak (tembok, air) masih milik klien (`client/scripts/maps.gd`);
pintu baru = satu entri di `EXITS` plus peta baru di kedua sisi.

Di klien, tiap langkah di petak ladang (`T`, di kedua peta) punya peluang 18% bertemu musuh
(tidak ada pertemuan baru selama 3 langkah setelah pertarungan).

## Peta jalan

1. Fondasi server + penyimpanan progress (selesai).
2. Klien Godot minimal: daftar, masuk, gerak di peta grid, simpan otomatis (selesai, gambar placeholder).
3. Peta pertama (Desa Awal: rumah, alun-alun, sungai, ladang) sudah ada dengan gambar placeholder; gambar ilustrator menggantikannya, lihat [MAP_REFERENCES](MAP_REFERENCES.md).
4. Musuh dan pertarungan bergiliran (logika di server) (selesai di v0.3.0, gambar placeholder).
5. Toko dan barang (selesai di v0.5.0, ikon placeholder); inventori menyusul. Misi pertama selesai di v0.6.0.
6. Rilis APK lewat GitHub Actions (selesai sejak v0.2.0).

### Toko Peralatan, plang, dan ikon atap (v0.41.0)

Desa Awal punya empat bangunan toko berplang: Toko Peralatan (barat, pedang dan baju zirah; ikon pedang dan kapak), Toko
Ramuan (ramuan dan harta; ikon botol), Rumah Makan (makanan; ikon piza di atas tong), dan Rumah Sehat (istirahat gratis;
ikon palang merah). Tiap toko berpapan nama di depan dan berpenjaga di ruangannya (Pak Hasan di Toko Peralatan).

### Basecamp Pahlawan dan prajurit (v0.42.0)

Di basecamp Desa Awal (barat gerbang): tenda merah, Komandan Raka merekrut pahlawan berkelas (layar rekrut dengan potret);
tenda hijau, Sersan Joni menjual prajurit biasa per orang. Prajurit lemah tetapi semuanya ikut bertarung dan mengikuti
pemain; pahlawan tetap maksimal 3 slot. Gerbang desa lebar tiga petak dan tinggi; meja toko rendah agar penjaga tampak.

### Aula Pelatihan (v0.43.0)

Bangunan di tengah Desa Awal (pintu 38,20). Di dalam, Guru Bima melatih pahlawan pembantu berkelas satu per satu dan Sersan Anton
melatih seluruh pasukan prajurit. Syarat tiap latihan: emas, 1 Kartu Keahlian, dan energi; waktunya berjalan di server
(10 menit x level untuk pahlawan, 5 menit x level untuk prajurit) dan bisa ditinggal. Level maksimum 20. Kartu Keahlian
dibeli di Toko Peralatan atau jatuh dari musuh. Dua tempat latihan berjalan bersamaan.

### Berlian dan peti harta (v0.44.0)

Berlian barang tertinggi: bisa dijual 500 emas atau ditukar dengan barang apa saja di toko. Peti harta memberi 3 hadiah acak yang
berbeda; berlian hanya jika beruntung (lebih mungkin di peti bertingkat tinggi). Peti diperkecil agar proporsional dengan pemain.
