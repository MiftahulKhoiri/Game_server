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
| `client/` | Proyek Godot 4.7 (klien Android) |
| `assets/` | Gambar mentah/sumber dari ilustrator |
| `docs/` | Dokumen desain dan kontrak API |
| `deploy/` | Menjalankan di Pi (systemd) dan kunci debug APK |
| `scripts/` | Skrip bantu (uji klien <-> server) |

Aturan arah ketergantungan: `api` -> `store` -> `game`. Paket `game` tidak
boleh mengimpor paket lain di proyek ini.

## Menjalankan

```bash
make run          # bangun dan jalankan di :8090
make check        # format + vet + tes (sama dengan CI)
```

Pengaturan: `GAME_ADDR` (bawaan `:8090`), `GAME_DB` (bawaan `data/game.db`), cadangan otomatis
`GAME_BACKUP_DIR` (bawaan `data/backup`, `off` = mati), `GAME_BACKUP_HOURS` (24), `GAME_BACKUP_KEEP` (7).

## Audit server dan database (v0.61.0, roadmap no. 219-238)

**Alur permintaan.** `logRequests` -> `recoverPanic` -> `clientGate` (versi klien) -> mux -> `auth` (token ->
pemain) -> handler. Handler yang mengubah data memakai `store.Update` (satu transaksi: baca pemain + pertarungan,
jalankan aturan dari paket `game`, periksa batas ekonomi, simpan, versi +1). Perdagangan antarpemain memakai
satu transaksi untuk dua pemain (`store/trades.go`).

**Server sumber kebenaran.** Klien hanya mengirim *permintaan* (serang, beli, simpan posisi, ...). Semua angka
(HP, XP, emas, barang, kemenangan, hadiah, jam dunia) dihitung server. `PUT /v1/players/me/save` hanya
menerima posisi (peta harus dikenal, petak di dalam peta, rumah hanya pemiliknya); lompatan posisi yang
mustahil dicatat di log sebagai `gerakan mencurigakan` (tidak ditolak, supaya sinyal putus-sambung tidak
membuat pemain gagal menyimpan). Setiap state yang akan disimpan diperiksa `ValidEconomy`.

**Database (SQLite, `modernc.org/sqlite`, satu koneksi).** Skema versi 4 (`PRAGMA user_version`), migrasi
bertahap tanpa kehilangan data (v1 -> v2 akun, v2 -> v3 `trades`, v3 -> v4 `sessions.last_used`).

| Tabel | Isi | Indeks |
|-------|-----|--------|
| `players` | akun + state JSON + versi | `id` (PK), `name`, `email` (UNIQUE, NOCASE) |
| `sessions` | hash token, pemain, dibuat, terakhir dipakai | `token_hash` (PK), `player_id` |
| `battles` | pertarungan berjalan (JSON) | `player_id` (PK) |
| `trades` | tawaran dagang (barang dititipkan) | `(from_id, status)`, `(to_id, status)` |

PRAGMA: WAL, `synchronous=NORMAL` (aman dari listrik padam, paling banyak transaksi terakhir hilang),
`foreign_keys=ON`, `busy_timeout=5000`, `temp_store=MEMORY`, cache 8 MB. Saat menyala server menjalankan
`PRAGMA quick_check`. Uji `TestQueriesUseIndexes` memastikan kueri utama tidak memindai tabel. Tolok ukur di
Pi 5 (`go test -bench . ./internal/store/`): cek token ±0,07 ms, simpan state ±0,13 ms, daftar dagang ±0,12 ms.

**Cadangan.** Server membuat `data/backup/game-YYYYMMDD-HHMMSS.db` (VACUUM INTO, salinan konsisten walau
server berjalan) setiap 24 jam dan menyimpan 7 terbaru. Manual: `make backup`. Pemulihan:
`make restore FILE=data/backup/game-....db` (memeriksa cadangan, menyimpan database lama sebagai
`game.db.sebelum-pulih-WAKTU`, lalu menyalakan server lagi).

**Log.** Setiap permintaan: metode, jalur, status, lama, IP, id pemain. 5xx = ERROR, 4xx dan permintaan
> 1 detik = WARN. Lihat: `journalctl --user -u gameserver -f`.

**Koneksi klien.** GET diulang sekali bila jaringan putus; layar dunia menampilkan "Koneksi terputus",
menanyai server tiap 5 detik, lalu mengambil ulang data dan mengirim posisi yang tertunda saat tersambung.
Token yang ditolak (kedaluwarsa/dicabut) membawa pemain ke beranda untuk masuk lagi.
