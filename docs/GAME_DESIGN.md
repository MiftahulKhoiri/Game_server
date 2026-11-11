# Desain Game (DRAF)

> Dokumen hidup. Semua isi di bawah adalah **usulan awal** dan menunggu
> keputusan pemilik proyek. Ubah langsung atau buka issue.

## Pokok yang sudah diputuskan

- Genre: **RPG**, 2D.
- Mode: **satu pemain**; server menyimpan progress (bukan multiplayer).
- Platform: **Android (APK)**; server berjalan di Raspberry Pi 5.

## Layar mendatar (diputuskan pemilik proyek, 11 Nov 2026; v0.68.0)

Seluruh game dimainkan dengan HP **posisi tidur (landscape)**: ukuran dasar 1280x720, orientasi sensor landscape
(HP boleh diputar ke kiri atau kanan), aspect "expand" sehingga layar 20:9 mendapat ruang lebih lebar. Beranda
menampilkan gambar judul The Last Dragon selebar layar dengan tombol berjajar di bawahnya; layar pertarungan dan
dialog dua kolom (arena / lawan bicara di kiri, catatan dan tombol di kanan); Menu tiga kolom; Profil dan Atribut
dengan pratinjau 3D di kiri; daftar (Ransel, toko, rekrut, latihan, Jurnal, Bank, tempa) di kolom tengah
(`client/scripts/layar.gd`).

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

## Misi (v0.6.0; sejak v0.67.0 hanya misi sampingan)

Misi bertipe "kalahkan N musuh" atau "antar barang". Server menghitung kemenangan (klien tidak bisa
memalsukan) dan hadiah diambil satu kali dari NPC pemberi misi. Misi baru = satu baris di
`internal/game/quest.go`; NPC baru = satu entri di `client/scripts/maps.gd`.

Misi utama lama (Selamatkan Nenek -> Selamatkan Petani -> Usir Monster Batu -> Hentikan Raja Iblis) **dihapus**
dan diganti cerita utama The Last Dragon (lihat "Cerita utama" di bawah). Catatan misi lama di data pemain dibiarkan
dan tidak berpengaruh. Misi sampingan terbuka menurut langkah cerita (`StoryMin`):

| Misi | Pemberi | Jenis | Tugas | Hadiah | Terbuka mulai |
|------|---------|-------|-------|--------|---------------|
| Kebun yang Dirusak | Nenek | kalahkan | 3 Babi Hutan | 35 emas + Baju Kulit | langkah 1 (setelah bicara dengan Kepala Desa) |
| Serigala di Jalan Raja | Petani | kalahkan | 4 Serigala Hutan | 70 emas + 2 Ramuan | langkah 1 |
| Obat untuk Korban Serangan | Nenek | antar barang | 3 Taring Goblin | 30 emas + 3 Ramuan | langkah 3 (setelah Penjaga Hutan) |
| Sisa Pasukan Terkutuk | Petani | kalahkan | 5 orc Benteng Orc | 300 emas + Zirah Besi | langkah 7 (Panglima Orc Batu kalah) |
| Permata Pengikat Kutukan | Nenek | antar barang | 3 Permata Merah | 120 emas + Pedang Baja | langkah 7 |

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
  yang mengikuti bab cerita utama (sejak v0.67.0: The Last Dragon, enam bab dari Prolog sampai Epilog):
  tiap warga berkomentar soal ancaman yang sedang terjadi dan memberi petunjuk ke mana harus pergi
  berikutnya, dan kalimatnya berganti tiap kali diajak bicara. Dialog murni di klien (tahap dibaca dari
  `GET /v1/quests`). Model KayKit hasil `tools/blender/kaykit_npc.py` (mode ibu, ibu2, bapak, bapak2, anak).

Cara main misi sampingan: berdiri di sebelah Nenek atau Petani, tekan **Bicara**, terima misi, kerjakan, lalu
kembali untuk **Ambil hadiah**. Misi antar barang: barang diambil dari tas saat hadiah diklaim.

## Cerita utama (diputuskan pemilik proyek, 11 Nov 2026)

Naskah cerita resmi ada di [STORY.md](STORY.md), berjudul **The Last Dragon**. Alur utama:
Desa Awal (penculikan Elara) → Hutan Binatang → Gua Goblin → Gunung Berapi (Orc Batu)
→ Istana Kegelapan (Aldragor dan Malzareth) → epilog di Desa Awal.

Malzareth adalah penyihir yang mengutuk binatang, Goblin, Orc, dan menguasai naga terakhir
Aldragor. Semua makhluk itu pada awalnya hidup damai. Mengalahkan Malzareth adalah cara
utama mematahkan kutukan; Aldragor dikalahkan tetapi tidak dibunuh dan pulih setelah kutukan
berakhir. Naskah lengkap, dialog kunci, tujuan bab, dan aturan kesinambungan ada di
[docs/STORY.md](STORY.md).

### Penerapan di game (v0.67.0)

Cerita berjalan sebagai **12 langkah** yang disimpan server di `state.story` (0 = baru mulai, 12 = tamat), didefinisikan
di `internal/game/story.go`. Server yang memeriksa syarat tiap langkah, memberi hadiahnya, dan memajukan cerita; klien
(`client/scripts/story.gd`) menampilkan narasi bab, tujuan di papan kanan atas, dan kartu "Cerita Utama" di Jurnal.

| # | Bab | Tujuan | Selesai bila | Hadiah |
|---|-----|--------|--------------|--------|
| 0 | Prolog | Bicara dengan Kepala Desa (ayah Elara) | bicara di dekatnya (`POST /v1/story/talk`) | 3 Ramuan + 2 Roti (bekal) |
| 1 | Prolog | Temui Kapten Rimba di kem Perbatasan | arahan Kapten (Radar Musuh) | - |
| 2 | Bab 1 Hutan Binatang | Temukan Penjaga Hutan Bayu yang terluka | bicara dengannya di dekat pintu masuk hutan | 2 Ramuan |
| 3 | Bab 1 | Kalahkan tiga Goblin (ujian hutan 25/75/100) | ujian Hutan Binatang tuntas | 150 emas |
| 4 | Bab 2 Gua Goblin | Kalahkan Raja Goblin (bos ketiga Gua Goblin) | ujian Gua Goblin tuntas | 250 emas + Lambang Malzareth |
| 5 | Bab 3 Gunung Berapi | Kalahkan tiga Orc Batu di lereng | ujian lereng tuntas | 350 emas |
| 6 | Bab 3 | Kalahkan Panglima Orc Batu di Benteng Orc | menang lawan bos singgasana Benteng Orc | 400 emas |
| 7 | Bab 3 | Hancurkan Batu Sihir penguat kutukan | tombol **Hancurkan** di dekat batu | - |
| 8 | Bab 3 | Bicara dengan Orc Tua yang mulai sadar | bicara dengannya | 3 Ramuan |
| 9 | Bab 4 Istana Kegelapan | Kalahkan Aldragor tanpa membunuhnya | menang lawan Aldragor | 600 emas |
| 10 | Bab 4 | Kalahkan Malzareth, bebaskan Elara | menang lawan Malzareth (3 fase) | 1000 emas |
| 11 | Epilog | Bawa Elara pulang ke Kepala Desa | bicara dengan Kepala Desa | 1500 emas + Pedang Rune + 3 Permata Merah |

Pencapaian **Legenda Eldoria** (500 emas) terbuka saat cerita tamat. Pemain lama yang sudah jauh berjalan hanya perlu
bicara dengan Kepala Desa, Penjaga Hutan, dan seterusnya; ujian yang sudah tuntas langsung dihitung.

**Wilayah cerita** (id peta tetap supaya data lama aman): Hutan Lebat = **Hutan Binatang** (ditambah Kelelawar
Terkutuk, model kelelawar Quaternius CC0), Gunung Batu = **Lereng Gunung Berapi** (langit berasap jingga dan aliran lava
`L`; bos ujian Orc Batu Lv 1, Orc Batu Lv 2, Panglima Lereng), Gua Batu = **Benteng Orc** (kolam lava, Batu Sihir,
Orc Tua, dan lorong rahasia di selatan yang terbuka mulai langkah 9). Dua peta baru Bab 4:

- **Istana Kegelapan** (`istana_kegelapan`, 31x26): halaman berlantai batu dengan pilar, obor ungu, dan kolam lava;
  penjaga berkeliaran (Kelelawar Kegelapan, Prajurit Terkutuk, Orc Kegelapan, Iblis Bayangan; Lv 10-12); Aldragor di
  singgasana tengah (15,14). Gerbang selatan ke ruang takhta terbuka setelah Aldragor kalah.
- **Ruang Takhta** (`ruang_takhta`, 21x20): Malzareth di singgasana (10,13), Elara ditahan di belakangnya.

**Bos cerita** (layar pertarungan khusus):

| Bos | Tempat | HP | Serang | Tahan | Kemampuan |
|-----|--------|----|--------|-------|-----------|
| Panglima Orc Batu (`raja_goblin`) | Benteng Orc (7,14) | 3200 | 84 | 22 | Hantaman Gada Batu; bisa dilawan lagi |
| Aldragor (`aldragor`, naga Quaternius CC0) | Istana Kegelapan (15,14) | 4200 | 92 | 24 | Semburan Api Naga; hanya pada langkah 9 |
| Malzareth (`malzareth`) | Ruang Takhta (10,13) | 5200 | 98 | 26 | 3 fase: Gelombang Sihir Hitam (HP > 2/3), Panggilan Monster (> 1/3), Kutukan Terakhir (x2); hanya pada langkah 10 |

Setelah tamat, Aldragor yang pulih terbang mengitari langit Desa Awal dan Elara tinggal di desa bersama ayahnya.

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
| **Panglima Orc Batu (bos, `raja_goblin`; dulu Raja Iblis)** | Benteng Orc, singgasana (7,14) | 3200 | 84 | 22 | 1500 | 650 | - | Permata Merah 100% |

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
menyerang musuh otomatis (pukulan pertama 0,8 d setelah mulai, lalu tiap 1,8 d sejak v0.46.0; kerusakan 70% serangan dasar level pemain + 2). Saat musuh mengejar atau sedang dilawan, pendamping berlari mengepung musuh itu, bukan hanya ikut berjalan. Pemain tetap yang
menentukan bertahan, skill, ramuan, dan kabur. Harga 250-350 emas (draf, untuk diseimbangkan).

## Hutan Lebat dan tiga Goblin (v0.46.0)

Hutan Lebat (selatan Perbatasan) berisi binatang liar level 1-6 (kancil, rubah, ular belang, babi bertaring, serigala hitam,
beruang; HP 24-82). Tiap tahap: kalahkan **100 binatang** (penghitung "Binatang X/100" di layar) -> bos **Goblin Level N** muncul
di singgasana (142,47, dekat gerbang Gua Goblin) dan binatang berhenti muncul -> bos kalah -> 100 binatang baru. Tiga tahap:

| Bos | HP | Serang | Tahan | XP | Emas | Jatuhan |
|-----|----|--------|-------|----|------|---------|
| Goblin Level 1 | 170 | 14 | 6 | 90 | 40 | Taring Goblin |
| Goblin Level 2 | 300 | 19 | 9 | 180 | 80 | Taring Goblin |
| Goblin Level 3 | 520 | 25 | 12 | 320 | 150 | Permata Merah |

Setelah Goblin Level 3 kalah, gerbang Gua Goblin (peta 3) terbuka. Angka di atas draf untuk diseimbangkan.

**Musuh ujian makin tangguh (v0.69.0, `internal/game/tahap.go`).** Di Hutan Binatang, Gua Goblin, dan Lereng Gunung
Berapi musuh biasa diperkuat menurut tahap ujian yang sedang berjalan dan tampil dengan nama "... Lv 1/2/3":

| Tahap | HP | Serangan | XP dan emas |
|-------|----|----------|-------------|
| Lv 1 | x1,6 | x1,15 | x1,3 |
| Lv 2 | x2,4 | x1,35 | x1,65 |
| Lv 3 | x3,2 | x1,6 | x2,1 |

Ditambah per level pemain di atas level musuh: HP +8% dan serangan +5% (paling banyak 20 level), supaya pemain yang
sudah kuat tetap tertantang. Bos wilayah dan musuh di peta lain tidak berubah. Di klien musuh yang sedang bertarung
mengitari pemain, mundur bersiap sebelum menyerang, menerjang saat menyerang, dan terpental saat dipukul (`roamer.gd`).

Sejak v0.47.0: Goblin dilawan **di dunia** seperti binatang (berkeliaran di sekitar singgasana, mengejar saat pemain mendekat, lalu
pertarungan langsung); kem (api unggun, tenda, panji) ada di Perbatasan **tepat di bawah gapura desa** sebagai zona aman dengan **Kapten Rimba** yang memberi
tahu tugas (tombol Bicara). Papan misi di layar menampilkan Binatang X/100, kemajuan Goblin, dan panah arah ke singgasana, gerbang
gua, dan kem. Sejak v0.49.0 jalan tanah selebar **2 petak** bercabang tiga (utara, tengah, selatan) dari pintu masuk dan semuanya
bertemu di **satu persimpangan** tepat di depan gerbang Gua Goblin; gerbang 2 petak, tembok dan gapuranya dari batu. Musuh hutan
baru aktif setelah pemain bicara dengan Kapten Rimba, yang memberi **Radar Musuh** (titik merah musuh di layar hutan, oranye = bos).

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
berulang (hadiahnya: XP, emas, dan drop), kecuali bos cerita Aldragor dan Malzareth yang hanya menyambut pemain pada
langkah ceritanya. Sejak v0.67.0 id `raja_goblin` adalah Panglima Orc Batu (model Monster Batu besar kelabu); model
Iblis Biru kini hanya dipakai di layar judul.

## Peta

| Peta | Isi | Pintu |
|------|-----|-------|
| Desa Awal (`desa_awal`, 85x50) | Hutan belantara timur lewat celah pagar timur (kolam, kebun, reruntuhan, tambang, 6 peti); tujuh rumah utara, empat rumah tengah, alun-alun, dua kandang berpagar, sungai, empat ladang berpagar dan pondok tani, dua kolam, Nenek dan Petani, serta 11 warga yang berjalan bebas (ibu, bapak, anak, penjaga, ayam) | Gerbang selatan (22,49) ke Perbatasan |
| Perbatasan Kerajaan (`perbatasan`) | Kem Kapten Rimba tepat di bawah gapura desa (api unggun, tenda, panji), jalan raja, ladang yang dirusak monster, reruntuhan benteng | Utara (7,0) ke desa; selatan (7,19) naik ke Gunung Batu |
| Hutan Binatang (`hutan_lebat`, 170x50) | Hutan pinus lebat, padang terbuka di balik pintu masuk, jalan tanah lebar, kolam, tempat terbuka, singgasana bos dekat gerbang (142,47), enam peti, tiga jalan 2 petak yang bertemu di depan gerbang | Utara (22,0) ke Perbatasan; gerbang selatan (146-147,49) ke Gua Goblin (terkunci sampai tiga Goblin kalah) |
| Gua Goblin (`gua_goblin`, 25x30) | Peta 3: gua sarang goblin (goblin, pemburu, penjaga), tiga peti | Utara kembali ke hutan; selatan (11-13,29) ke Gunung Batu |
| Lereng Gunung Berapi (`gunung_batu`) | Lereng berbatu, aliran lava, Orc Batu | Utara (22,0) ke Gua Goblin; selatan (22,49) masuk Benteng Orc |
| Benteng Orc (`gua_batu`) | Lorong gua, kolam lava, singgasana Panglima Orc Batu, Batu Sihir, Orc Tua | Utara (7,0) ke lereng; selatan (7,19) ke Istana Kegelapan (mulai langkah cerita 9) |
| Istana Kegelapan (`istana_kegelapan`) | Halaman istana, penjaga terkutuk, Aldragor | Utara ke Benteng Orc; selatan (14-16,25) ke ruang takhta (mulai langkah 10) |
| Ruang Takhta (`ruang_takhta`) | Singgasana Malzareth, Elara | Utara (9-11,0) kembali ke halaman |

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

### HUD dan pengaturan (v0.45.0)

HUD kiri atas (nama, level+poin, nyawa dengan angka, energi, berlian, koin emas) disusun satu kolom dengan jarak yang cukup agar
ikon tidak bertumpuk; berlian berada tepat di atas koin emas. Pengaturan (beranda dan menu dalam game) memuat Layar (kualitas
grafis, kecepatan putar kamera, layar tetap menyala) dan Suara (NPC, musik, volume).
