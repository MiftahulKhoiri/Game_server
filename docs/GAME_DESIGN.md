# Desain Game (DRAF)

> Dokumen hidup. Semua isi di bawah adalah **usulan awal** dan menunggu
> keputusan pemilik proyek. Ubah langsung atau buka issue.

## Pokok yang sudah diputuskan

- Genre: **RPG**, 2D.
- Mode: **satu pemain**; server menyimpan progress (bukan multiplayer).
- Platform: **Android (APK)**; server berjalan di Raspberry Pi 5.

## Yang perlu diputuskan (pemilik proyek)

1. **Tema dan cerita.** Dunia apa, siapa tokoh utama, apa tujuan akhirnya?
2. **Gaya gerak.** Berjalan per kotak (grid, seperti RPG klasik) atau bebas?
3. **Gaya pertarungan.** Bergiliran (turn-based) atau waktu nyata?
4. **Sudut pandang.** Atas-bawah (top-down) atau samping?
5. **Kelas karakter.** Satu karakter tetap atau boleh memilih kelas?

Usulan paling hemat tenaga untuk memulai: **grid top-down + pertarungan bergiliran**.
Gambar lebih sedikit (tidak perlu animasi banyak arah), logika server lebih mudah
diuji, dan nyaman dimainkan di layar sentuh.

## Sistem yang sudah ada di server

| Data | Keterangan |
|------|------------|
| `level`, `xp` | Perkembangan karakter |
| `hp`, `max_hp` | Nyawa |
| `gold` | Mata uang |
| `map`, `x`, `y` | Lokasi di dunia |
| `inventory` | Daftar `{id, qty}` |

Pemain baru mulai di peta `desa_awal` posisi (5,5) dengan 30 HP.

## Peta jalan

1. Fondasi server + penyimpanan progress (selesai).
2. Klien Godot minimal: daftar, masuk, tampilkan karakter di peta kosong.
3. Gerak di grid + peta pertama dari ilustrator.
4. Musuh dan pertarungan bergiliran (logika di server).
5. Inventori, toko, dan misi.
6. Rilis APK pertama lewat GitHub Actions.
