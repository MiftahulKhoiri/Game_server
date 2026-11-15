# Sistem Unduh & Pasang Game (v0.84.0)

## Alur

```
DOWNLOAD -> berkas sementara (.part) -> VERIFY SIGNATURE (manifest) -> VERIFY SHA-256 + ukuran
         -> VERIFY PACKAGE (header & direktori PCK) -> INSTALL (pindah atomik) -> UPDATE REGISTRY -> READY
```

Urutan nyata di kode (`GameManager.install`): manifest + tanda tangannya diambil dan **diperiksa lebih dulu**
(tanpa tanda tangan sah, unduhan tidak dimulai), lalu paket diunduh, lalu `PackageManager.verify_file` dan
`install`. Status di launcher: `DOWNLOADING` → `VERIFYING` → `INSTALLING` → `INSTALLED` (atau `ERROR`
dengan alasannya). Game tidak pernah berstatus `INSTALLED` sebelum semua pemeriksaan lulus dan registry
tersimpan.

## Pengunduh (`client/core/download_manager.gd`)

- `HTTPClient` dengan polling per frame (tidak menahan UI), potongan 64 KiB ditulis langsung ke
  `user://user_data/cache/downloads/<id>-<versi>.part` (streaming; berkas besar tidak dimuat ke RAM).
- **Lanjut**: bila `.part` sudah ada, dikirim `Range: bytes=<ukuran>-`; jawaban `206` → ditambahkan,
  `200` → server tidak mendukung Range, mulai dari 0; `416` → `.part` tidak cocok, dihapus dan diulang sekali.
- **Putus**: koneksi gagal / macet 30 detik / server 5xx → `.part` disimpan, tekan DOWNLOAD/UPDATE lagi
  untuk melanjutkan.
- **Rusak**: data melebihi ukuran manifest, kode 4xx → `.part` dihapus.
- **Batal** (tombol BATAL): koneksi ditutup dan `.part` dihapus.
- **Ruang**: sebelum mulai, `DirAccess.get_space_left()` harus ≥ sisa unduhan + 8 MB.
- **Sumber**: hanya server game yang dipakai aplikasi, jalur `/v1/games/...`; HTTPS wajib kecuali alamat
  lokal/LAN (127.x, 10.x, 192.168.x, 172.16–31.x) untuk uji. Tanpa pengalihan (redirect).
- Progres diteruskan ke launcher (bilah + "x / y MB").

## Pemasangan atomik & update (`client/core/package_manager.gd`)

- Paket lolos semua cek → `rename` ke `user://user_data/packages/<id>/<versi>-<sha8>.pck`.
- Registry `installed.json` ditulis lewat `.tmp` + `rename` (salinan lama ke `.bak`).
- Versi lama **tidak dihapus** sebelum versi baru tercatat; ia disimpan sebagai `previous` untuk rollback.
  Hanya versi aktif + sebelumnya yang disimpan.
- Update satu game tidak menyentuh game lain; progres (`user_data/progress/<id>`) tidak berubah.
- Saat dimainkan: SHA-256 dan direktori PCK diperiksa ulang. Bila versi baru gagal dimuat dan ada versi
  sebelumnya yang sah → **rollback otomatis**.
- Paket yang sudah dimuat tidak bisa dilepas Godot; memakai versi lain di sesi yang sama → pesan
  "buka ulang aplikasi".
- HAPUS: berkas paket + catatan registry dihapus; progres tetap disimpan.

## Offline

Launcher memakai katalog terakhir yang sah (`registry/catalog.json` + `.sig`, diperiksa ulang tiap dibuka).
Game bawaan dan game terpasang tetap bisa dimainkan. Tombol DOWNLOAD/UPDATE nonaktif saat offline.
Progres yang disimpan offline ditandai di `registry/sync_pending.json` dan dikirim ke server saat katalog
berhasil dimuat lagi (dan pemain sudah masuk akun di Petualangan).
