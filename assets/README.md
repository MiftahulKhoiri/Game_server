# Aset gambar

Folder ini untuk gambar dari ilustrator. Aturan di bawah masih **usulan awal**,
supaya semua gambar konsisten dan mudah dipakai klien. Ubah bila perlu.

## Format

- **PNG** dengan latar transparan.
- Tanpa kompresi lossy (jangan simpan sprite sebagai JPG).
- Nama file: huruf kecil, angka, dan garis bawah, tanpa spasi. Contoh: `pohon_besar.png`.

## Ukuran (usulan, untuk grid top-down)

| Jenis | Ukuran | Contoh |
|-------|--------|--------|
| Tile peta | 32x32 px | rumput, tanah, air |
| Karakter / NPC / musuh | 32x32 px per frame | `pemain_jalan_bawah_1.png` |
| Ikon item | 32x32 px | `ikon_ramuan.png` |
| Potret dialog | 128x128 px | `potret_tetua.png` |
| Antarmuka (tombol, bingkai) | bebas, kelipatan 8 px | |

Satu gaya, satu palet: usahakan seluruh gambar terlihat berasal dari satu game.

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
