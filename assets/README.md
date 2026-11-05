# Aset gambar

Folder ini untuk gambar dari ilustrator. Aturan di bawah masih **usulan awal**,
supaya semua gambar konsisten dan mudah dipakai klien. Ubah bila perlu.

## Format

- **PNG** dengan latar transparan.
- Tanpa kompresi lossy (jangan simpan sprite sebagai JPG).
- Nama file: huruf kecil, angka, dan garis bawah, tanpa spasi. Contoh: `pohon_besar.png`.

## Gambar karakter (ilustrasi)

Gaya yang dipilih adalah ilustrasi, bukan pixel art. Gambar yang dipakai klien
disimpan di `client/assets/` (harus di dalam proyek Godot):

| Berkas | Isi |
|--------|-----|
| `characters/ksatria.png` | Pemain |
| `characters/nenek_penjual.png`, `characters/petani.png` | NPC desa |
| `items/<id barang>.png` | Ikon barang (id sama dengan `internal/game/item.go`). Disarankan persegi 128x128 px, latar transparan. Tanpa gambar klien memakai kotak berwarna |
| `enemies/<id musuh>.png` | Musuh; nama berkas = id musuh di server (mis. `goblin.png`). Bila tidak ada, klien memakai bulatan placeholder |

**Penting:** simpan sebagai PNG dengan latar transparan **sungguhan**. Kotak-kotak
abu-putih yang ikut tergambar di JPG bukan transparan; gambar seperti itu harus
dibersihkan dulu. Gambar ogre batu masih punya latar pemandangan, jadi perlu
diekspor ulang dengan latar transparan sebelum bisa dipakai.
Disarankan tinggi sekitar 384-512 px.

Gambar acuan gaya (paket ikon item dan efek sihir) hanya dipakai sebagai referensi
suasana. Jangan menyalin gambar milik orang lain ke repo ini kecuali lisensinya
memperbolehkan dan sumbernya dicatat di sini.

## Ukuran tile (usulan, untuk grid top-down)

| Jenis | Ukuran | Contoh |
|-------|--------|--------|
| Tile peta | 32x32 px | rumput, tanah, air |
| Karakter / NPC / musuh | 32x32 px per frame | `pemain_jalan_bawah_1.png` |
| Ikon item | 32x32 px | `ikon_ramuan.png` |
| Potret dialog | 128x128 px | `potret_tetua.png` |
| Antarmuka (tombol, bingkai) | bebas, kelipatan 8 px | |

Satu gaya, satu palet: usahakan seluruh gambar terlihat berasal dari satu game.

## Daftar gambar tile untuk "Desa Awal"

Ukuran 32x32 px. Sementara ini peta digambar dengan bentuk sederhana lewat
kode; setiap gambar di bawah akan menggantikan satu lambang di peta
(lihat [`docs/MAP_REFERENCES.md`](../docs/MAP_REFERENCES.md)).

| Berkas (di `tiles/`) | Lambang | Keterangan |
|----------------------|---------|------------|
| `rumput.png` | `.` | Dasar. Buat 2-3 variasi agar tidak monoton |
| `jalan_tanah.png` | `=` | Harus menyambung mulus antar-petak |
| `bunga.png` | `f` | Rumput dengan bunga kecil |
| `ladang.png` | `T` | Tanah berpetak/bergaris |
| `jembatan.png` | `B` | Papan kayu di atas air |
| `pintu_rumah.png` | `D` | Dinding rumah dengan pintu |
| `pohon.png` | `#` | Rumput di bawah, pohon di atas (latar transparan) |
| `air.png` | `~` | Idealnya 2-4 bingkai agar beriak |
| `rumah_dinding.png`, `rumah_atap.png` | `H` | Bangunan rumah per petak |
| `pagar.png` | `F` | Pagar kayu |
| `sumur.png` | `W` | Sumur batu |

Pemain: `characters/pemain_{bawah,atas,kiri,kanan}_{1,2,3}.png` (jalan 3 bingkai per arah).
Tidak perlu semuanya sekaligus; kirim satu per satu pun boleh, sisanya tetap placeholder.

## Struktur

```
assets/
  tiles/       tile peta
  characters/  pemain, NPC
  enemies/     musuh
  items/       ikon item
  ui/          tombol, bingkai, ikon antarmuka
  portraits/   potret dialog
```

## Lisensi

Dengan mengirim gambar ke repo ini, pembuatnya setuju gambar tersebut dipakai
dalam game ini. Tulis lisensi aset di sini bila berbeda dari kode.
