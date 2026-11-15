# Keamanan Paket Game (v0.84.0)

Audit keamanan server yang lama tetap di [AUDIT_KEAMANAN.md](AUDIT_KEAMANAN.md). Dokumen ini khusus platform
multi-game.

## Kunci penerbit

- RSA 3072, dibuat sekali dengan `make game-keys` (`scripts/game-keys.sh`).
- **Privat**: `~/.config/game_server/publisher_private.pem` di Pi (folder 700, berkas 600). Tidak di repo
  (`.gitignore` mengabaikan `*.pem`), tidak di APK, tidak di server HTTP (server hanya melayani berkas jadi).
  **Cadangkan** ke tempat aman (flashdisk). Hilang = paket baru tidak bisa diterbitkan untuk APK yang ada.
- **Publik**: `client/config/publisher_public.pem`, ikut APK. Ganti kunci (`FORCE=1`) = semua APK lama
  menolak paket baru → harus disertai APK baru.

## Apa yang diperiksa launcher

| Ancaman | Perlindungan |
|---|---|
| Katalog/manifest dipalsukan (server/jaringan disusupi) | Tanda tangan RSA PKCS#1 v1.5 + SHA-256 atas byte persis `catalog.json` dan `manifest.json`, kunci publik di APK. Katalog palsu ditolak; katalog sah terakhir tetap dipakai |
| Paket diganti / rusak saat transfer | Ukuran + SHA-256 dari manifest bertanda tangan (SHA-256 sendiri tidak dipakai sebagai pengganti tanda tangan) |
| Paket rusak di HP | SHA-256 + direktori PCK diperiksa ulang setiap kali dimuat |
| Paket menimpa skrip aplikasi / game lain | `load_resource_pack(path, false)` + daftar path paket diperiksa sebelum dimuat (hanya `games/<id>/` dan berkas mesin) |
| PCK terenkripsi / berflag hapus / terpotong / format asing | Ditolak oleh `pck_reader.gd` |
| Path traversal | `id` hanya `^[a-z][a-z0-9_]{1,31}$`; `entry_scene` wajib di `res://games/<id>/`, tanpa `..`, `\`, `//`, skema lain; nama paket `^[A-Za-z0-9._-]{1,80}\.pck$`; server memeriksa hal yang sama |
| Manifest game lain disisipkan | `id` manifest harus sama dengan game yang diminta; katalog tidak boleh memakai id game bawaan |
| Downgrade | Server menawarkan versi lebih lama dari yang terpasang → ditolak; alat terbit menolak versi mundur |
| Game tidak kompatibel | `min_launcher_version`, `min_engine_version` (MAJOR.MINOR mesin harus sama) |
| Paket raksasa / ruang habis | Batas 512 MB, manifest 64 KB, cek ruang kosong sebelum unduh |
| Sumber asing | Hanya server game yang diatur di aplikasi, jalur `/v1/games/`, HTTPS (HTTP hanya LAN/lokal), tanpa redirect |

## Server

- Endpoint katalog hanya membaca dari `GAME_CATALOG_DIR`; id divalidasi, nama paket diambil dari manifest
  dan harus berada langsung di folder game; ukuran berkas harus sama dengan manifest.
- Progres per game butuh token; `data` harus objek JSON ≤ 64 KiB; pemain hanya bisa membaca/menulis miliknya.
- Tidak ada kunci privat di server.

## Batasan yang diketahui

- Skrip GDScript di paket berjalan dengan hak yang sama seperti aplikasi (Godot tidak punya sandbox). Karena
  itu hanya paket yang ditandatangani kunci penerbit yang dimuat — jaga kunci privat.
- Data `user://` tidak dienkripsi (sama seperti sebelumnya).
