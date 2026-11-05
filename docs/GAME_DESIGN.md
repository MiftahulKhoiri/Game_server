# Desain Game (DRAF)

> Dokumen hidup. Semua isi di bawah adalah **usulan awal** dan menunggu
> keputusan pemilik proyek. Ubah langsung atau buka issue.

## Pokok yang sudah diputuskan

- Genre: **RPG**, 2D.
- Mode: **satu pemain**; server menyimpan progress (bukan multiplayer).
- Platform: **Android (APK)**; server berjalan di Raspberry Pi 5.

## Keputusan gameplay

- Gerak: **per kotak (grid)**, tampak atas (top-down).
- Pertarungan: **bergiliran (turn-based)**.

Alasannya hemat tenaga: gambar lebih sedikit (tanpa animasi banyak arah), logika
server mudah diuji, dan nyaman di layar sentuh.

## Tema dan gaya (diputuskan pemilik proyek, 5 Nov 2026)

- **Tema:** desa di sebuah kerajaan yang diserang monster. Pemain adalah
  ksatria kerajaan (zirah perak, perisai singa, pedang berhuruf rune) yang
  melindungi penduduk desa.
- **Gaya gambar:** ilustrasi berwarna bergaya komik/lukisan dengan garis tepi
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
| `taring_goblin` | Taring Goblin | material (jatuhan goblin 35%) | - | 12 |
| `koin_kuno` | Koin Kuno | treasure (hadiah misi) | - | 25 |
| `permata_merah` | Permata Merah | treasure (hadiah misi) | - | 60 |

Harga jual selalu lebih murah dari harga beli agar tidak bisa untung tanpa batas.

## Misi (v0.6.0)

Misi bertipe "kalahkan N musuh". Server menghitung kemenangan (klien tidak bisa
memalsukan) dan hadiah diambil satu kali dari NPC pemberi misi. Misi baru = satu
baris di `internal/game/quest.go`; NPC baru = satu entri di `client/scripts/maps.gd`
dan gambar `client/assets/characters/<id npc>.png`.

| Misi | Pemberi | Tugas | Hadiah |
|------|---------|-------|--------|
| Selamatkan Nenek | Nenek Penjual Sayur (3,6) | Usir 5 tikus sawah atau belalang raksasa | 40 emas |
| Selamatkan Petani | Petani (11,6) | Kalahkan 3 goblin di Perbatasan. Terkunci sampai hadiah Nenek diambil | 25 emas + Permata Merah |
| Usir Ogre Batu | Nenek (3,6) | Kalahkan 1 Ogre Batu di Gunung Batu. Terkunci sampai hadiah Petani diambil | 150 emas + 2 Koin Kuno |

Cara main: berdiri di sebelah Nenek, tekan **Bicara**, terima misi, lawan hama di
ladang, lalu kembali ke Nenek untuk **Ambil hadiah**.

## Masih perlu diputuskan (pemilik proyek)

1. **Cerita.** Siapa dalang serangan monster, apa tujuan akhirnya?
2. **Penduduk lain.** Siapa lagi yang perlu diselamatkan? Tiap NPC baru butuh gambar di `client/assets/characters/`.
3. **Setelah Ogre.** Siapa dalang yang mengirim monster, dan di mana ia berada? Apa isi peta berikutnya (istana, hutan, gua)?

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
| Tikus Sawah | Desa | 10 | 3 | 0 | 6 | 2 | 1 | Ramuan 10% |
| Belalang Raksasa | Desa | 14 | 4 | 1 | 8 | 3 | 1 | Ramuan 10% |
| Ular Sawah | Desa | 20 | 6 | 1 | 12 | 5 | 2 | Ramuan 15% |
| Babi Hutan | Desa | 34 | 8 | 3 | 22 | 9 | 3 | Ramuan 25% |
| Goblin | Perbatasan | 26 | 7 | 2 | 15 | 7 | 1 | Taring Goblin 35% |
| Serigala Hutan | Perbatasan dan Gunung Batu | 32 | 9 | 2 | 20 | 9 | 3 | Ramuan 20% |
| Kelelawar Gua | Gunung Batu | 28 | 8 | 1 | 18 | 8 | 3 | Ramuan 20% |
| Golem Kerikil | Gunung Batu | 50 | 10 | 6 | 32 | 14 | 4 | Koin Kuno 25% |
| Ogre Batu | Gunung Batu | 70 | 12 | 5 | 45 | 25 | 5 | Permata Merah 30% |

Musuh dipilih dari wilayah (peta) tempat pemain berada, jadi server perlu tahu peta
terakhir yang tersimpan (klien menyimpan posisi sebelum tiap pertarungan). Serigala
Hutan, Kelelawar Gua, Golem Kerikil, dan Ogre Batu belum punya gambar (pakai bulatan placeholder).
Bila level pemain terlalu rendah untuk sebuah wilayah, ia tetap bertemu musuh terlemah di wilayah itu.

## Peta

| Peta | Isi | Pintu |
|------|-----|-------|
| Desa Awal (`desa_awal`) | Rumah, alun-alun, sungai, ladang, Nenek dan Petani | Gerbang selatan (7,19) ke Perbatasan |
| Perbatasan Kerajaan (`perbatasan`) | Jalan raja, ladang yang dirusak monster, reruntuhan benteng | Utara (7,0) ke desa; selatan (7,19) naik ke Gunung Batu |
| Gunung Batu (`gunung_batu`) | Lereng berbatu dan kerikil, sarang Ogre Batu | Utara (7,0) kembali ke Perbatasan |

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
