# Character Creator, perlengkapan, inventaris, dan toko (v0.82.0)

Pemain bisa membuat penampilan pahlawan utamanya sendiri, membeli kosmetik dan perlengkapan di toko,
mengganti senjata per jenis, lalu semuanya tersimpan permanen di server.

## Cara membuka

- **Menu > Karakter dan Toko.**
- **Pemain baru** (penampilan belum pernah disimpan, `state.look.made = false`) langsung diajak membuat
  karakter saat pertama masuk dunia (layar Penampilan > Rambut, sapaan "Selamat datang").

## Layar (client/scripts/kreator.gd)

Kiri: pratinjau 3D besar. Geser dengan jari untuk memutar 360 derajat, tombol **Depan / Samping / Belakang**,
**Perbesar / Perkecil** (juga cubit/roda tetikus), **Putar 360** (berputar sendiri). Animasi diam KayKit tetap
berjalan. Setiap pilihan langsung terlihat di model.

Kanan, enam tab:

| Tab | Isi |
|-----|-----|
| Karakter | Ringkasan perlengkapan dan penampilan, **Acak Penampilan**, **Kembali ke Asli** |
| Penampilan | Rambut (model), Warna Rambut, Wajah (bentuk wajah, hidung, mulut, alis, jenggot & kumis), Mata (bentuk + warna), Kulit, Tubuh (bentuk tubuh + penggeser tinggi, lebar badan, otot, ukuran kepala, proporsi badan) |
| Perlengkapan | Pakaian, Celana, Sarung Tangan, Jubah, Topi, Skin, Aksesori (kosmetik), Zirah, Helm, Sepatu, Perisai (perlengkapan tempur) |
| Senjata | Senjata dan perisai: dimiliki = Pakai/Lepas, belum = pratinjau + Beli |
| Inventaris | Hanya barang yang dimiliki: Skin, Rambut, Pakaian, Armor, Helm, Sepatu, Senjata, Aksesori |
| Toko | Skin, Rambut, Pakaian, Armor, Helm & Topi, Jubah, Sepatu, Senjata, Aksesori |

Setiap barang punya ikon (`client/assets/items/<id>.png`, dibuat `tools/gen_ikon_kreator.py`), nama berwarna
kelangkaan, harga, level yang dibutuhkan, dan status (Dimiliki / Dipakai). Ketuk barang = rincian (keterangan,
serangan/pertahanan, kecepatan, kritis, gaya senjata) dan pratinjau di model sebelum membeli. **Beli** membuka
konfirmasi yang menampilkan saldo sebelum dan sesudah. Kosmetik yang dipakai disimpan lewat **Simpan Penampilan**
(atau otomatis saat layar ditutup); perlengkapan tempur langsung dipakai/dilepas di server.

## Kelangkaan

common (Biasa), uncommon (Tidak Biasa), rare (Langka), epic (Epik), legendary (Legendaris), mythic (Mitos).
Barang lama tetap memakai `rarity` tiga tingkat (biasa/langka/epik) untuk klien lama; `tier` enam tingkat baru.

## Server (sumber kebenaran)

- `internal/game/look.go`: katalog kosmetik (`Cosmetics`), pilihan gratis (`LookOptions`), palet warna,
  `State.Look`, `State.Wardrobe`, `BuyCosmetic`, `SetLook`, `Once` (anti pembelian ganda).
- `internal/game/gear.go`: 29 perlengkapan tempur baru (senjata per jenis, perisai, zirah berat/legenda, helm,
  sepatu), slot `boots`/`offhand`, aturan gaya senjata dan level.
- `internal/api/wardrobe.go`: `GET /v1/wardrobe`, `POST /v1/wardrobe/buy`, `POST /v1/players/me/look`.
- Data disimpan di kolom JSON `state` tabel `players` yang sudah ada (tidak ada tabel baru; akun lama
  otomatis `look` kosong = tampilan lama). Setiap perubahan lewat `store.Update` = satu transaksi SQLite:
  pengurangan emas dan penambahan barang/kosmetik selalu bersama-sama atau tidak sama sekali.

Yang diperiksa server: barang/kosmetik dikenal, harga dan level dari katalog server, saldo cukup, belum dimiliki
(kosmetik), dimiliki sebelum dipakai (kosmetik dan perlengkapan), gaya senjata cocok dengan pahlawan, id warna
dari palet, penggeser tubuh -3..3, aksesori maks 4 tanpa ganda. Badan permintaan dengan kolom asing (mis. `price`)
ditolak `400`. Simpan posisi (`PUT /v1/players/me/save`) tidak bisa mengubah penampilan, lemari, atau emas.

**Pembelian ganda:** klien membuat `request_id` acak per konfirmasi Beli. Server mengingat 30 id terakhir per
pemain; permintaan yang diulang (jaringan putus lalu dikirim lagi, atau ketukan ganda) menjawab `200` tanpa
membayar lagi. Uji: `TestCosmeticConcurrentBuy` (8 permintaan bersamaan, saldo berkurang sekali).

## Senjata dan pertarungan

Senjata baru memakai sistem pertarungan yang sudah ada: `Attack` menambah serangan, `SpeedPct` mengubah waktu
isi ulang serangan biasa gaya pahlawan (`State.Style()`), `Crit` menambah peluang kritis. Senjata harus cocok
dengan gaya pahlawan (Ksatria pedang/belati, Pendekar Kapak kapak/palu, Pemanah busur, Pendekar Tombak tombak,
Penyihir tongkat); Pedang Naga Purba (mitos) cocok untuk semua. Perisai menambah pertahanan (gaya pedang, kapak,
tombak). Di model, senjata dan perisai digambar di tulang tangan (`handslot.r` / `handslot.l`) dan senjata
bawaan KayKit disembunyikan, jadi senjata ikut diayun animasi serangan.

## Bentuk tubuh tanpa merusak animasi

`client/scripts/body_shape.gd` adalah `SkeletonModifier3D` yang mengalikan skala tulang **setelah** animasi:
`hips` (lebar), `chest`/`upperarm`/`upperleg` (otot), `spine` (proporsi), `head` (ukuran & bentuk wajah, dibalik
dari skala induk). Tinggi = skala model keseluruhan (kaki tetap di tanah). Rangka, klip animasi, dan tulang tidak
diganti. Collision dan hitbox tidak terpengaruh: gerak memakai petak peta (server `MoveTo`) dan pertarungan
dihitung server dari angka, bukan dari ukuran model.

## Aset

Semua bagian penampilan (rambut, mata, hidung, mulut, topi, mahkota, jubah, sayap, kalung, sepatu, senjata,
perisai) dibuat dari bentuk dasar di `client/scripts/look_build.gd` dan ditempel ke tulang, karena paket KayKit
tidak punya model rambut/aksesori terpisah. Bila nanti ada model 3D final, ganti fungsi pembuat bagiannya
(`_hair`, `_hat`, `weapon_mesh`, dll.) tanpa mengubah server atau data pemain.

## Pengujian

- Server: `internal/game/look_test.go`, `internal/api/wardrobe_test.go` (katalog, beli, tolak tanpa saldo, tolak
  barang ilegal, tolak pakai yang belum dimiliki, simpan, keluar-masuk tetap sama, permintaan diulang/bersamaan).
- Klien (`make client-test`): bagian "Character Creator, toko, perlengkapan" di `client/tests/e2e.gd`.
- Tangkapan layar: `shot.sh NAMA SHOT_SCENE=kreator SHOT_WARDROBE=katalog.json SHOT_TAB=Toko SHOT_SUB=Aksesori
  SHOT_PICK=sayap_malaikat` atau `SHOT_SCENE=models SHOT_LOOKS='[{"look":{...},"equipment":{...}}]'`.
