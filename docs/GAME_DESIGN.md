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

## Masih perlu diputuskan (pemilik proyek)

1. **Cerita.** Siapa dalang serangan monster, apa tujuan akhirnya?
2. **Kelas karakter.** Satu ksatria tetap atau boleh memilih kelas?
3. **Peran NPC.** Nenek dan petani: pemberi misi, penjual, atau penunjuk jalan?
4. **Nasib hama sawah.** Tikus, belalang, ular, dan babi hutan masih memakai
   tema lama. Dipertahankan sebagai musuh awal, atau diganti monster?

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

| Musuh | HP | Serang | Bertahan | XP | Emas | Min. level | Jatuh ramuan |
|-------|----|--------|----------|----|------|------------|--------------|
| Tikus Sawah | 10 | 3 | 0 | 6 | 2 | 1 | 10% |
| Belalang Raksasa | 14 | 4 | 1 | 8 | 3 | 1 | 10% |
| Ular Sawah | 20 | 6 | 1 | 12 | 5 | 2 | 15% |
| Goblin | 26 | 7 | 2 | 15 | 7 | 2 | 20% |
| Babi Hutan | 34 | 8 | 3 | 22 | 9 | 3 | 25% |

Di klien, tiap langkah di petak ladang punya peluang 18% bertemu musuh
(tidak ada pertemuan baru selama 3 langkah setelah pertarungan).

## Peta jalan

1. Fondasi server + penyimpanan progress (selesai).
2. Klien Godot minimal: daftar, masuk, gerak di peta grid, simpan otomatis (selesai, gambar placeholder).
3. Peta pertama (Desa Awal: rumah, alun-alun, sungai, ladang) sudah ada dengan gambar placeholder; gambar ilustrator menggantikannya, lihat [MAP_REFERENCES](MAP_REFERENCES.md).
4. Musuh dan pertarungan bergiliran (logika di server) (selesai di v0.3.0, gambar placeholder).
5. Inventori, toko, dan misi.
6. Rilis APK lewat GitHub Actions (selesai sejak v0.2.0).
