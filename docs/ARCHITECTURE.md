# Arsitektur

```
 HP Android (APK, Godot)  --HTTP/JSON-->  Server Go di Raspberry Pi 5  -->  SQLite
```

## Mengapa Go untuk server

Proyek ini akan panjang dan banyak tangan, jadi yang dipilih adalah bahasa
yang membosankan dalam arti baik:

- **Stabil dan kompatibel ke belakang.** Kode Go lama tetap jalan di versi baru.
- **Konkurensi bawaan.** Cocok untuk banyak koneksi pemain tanpa library tambahan.
- **Satu file biner.** Deploy ke Pi cukup menyalin satu file; bisa di-cross-compile.
- **Mudah dibaca kontributor baru.** Bahasanya kecil, format kode seragam (`gofmt`).
- **Aman memori** dibanding C/C++, tanpa beban belajar Rust.

Database memakai SQLite (driver Go murni, tanpa CGO). Cukup kuat untuk satu Pi
dan dapat diganti bila suatu hari perlu.

## Mengapa Godot 4 untuk klien

Gambar dibuat sendiri oleh pemilik proyek, dan Godot paling mulus untuk
mengimpor PNG, tilemap, dan animasi sprite 2D. Ekspor ke APK didukung langsung
dan bisa diotomatisasi lewat GitHub Actions (Android SDK tidak perlu dipasang di Pi).

## Struktur folder

| Folder | Isi |
|--------|-----|
| `cmd/gameserver/` | Titik masuk program (hanya merangkai komponen) |
| `internal/config/` | Pengaturan dari environment variable |
| `internal/game/` | Aturan dan model game; tidak tahu HTTP/DB |
| `internal/store/` | Penyimpanan SQLite |
| `internal/api/` | Handler HTTP, autentikasi, validasi |
| `client/` | Proyek Godot (belum dibuat) |
| `assets/` | Gambar mentah/sumber dari ilustrator |
| `docs/` | Dokumen desain dan kontrak API |
| `deploy/` | File untuk menjalankan di Pi (systemd) |

Aturan arah ketergantungan: `api` -> `store` -> `game`. Paket `game` tidak
boleh mengimpor paket lain di proyek ini.

## Menjalankan

```bash
make run          # bangun dan jalankan di :8090
make check        # format + vet + tes (sama dengan CI)
```

Pengaturan: `GAME_ADDR` (bawaan `:8090`), `GAME_DB` (bawaan `data/game.db`).
