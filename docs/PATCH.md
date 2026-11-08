# Patch isi game (tanpa APK baru)

Peta, skrip, dan adegan bisa diubah lewat server. Pemain cukup **menutup lalu membuka ulang** aplikasi.

## Pakai

1. Ubah file di `client/` (peta, skrip, adegan), commit bila perlu.
2. `make patch GODOT=/path/ke/godot` -> membuat `patches/<versi>-<hash>.pck` dan `patches/latest.json`.
3. Server langsung melayani patch itu (tanpa restart). Buka ulang aplikasi di HP.
4. Label di layar awal menampilkan `| patch <id>` bila patch aktif.
5. Batalkan: `make patch ROLLBACK=1` (menghapus `latest.json`); HP kembali ke isi APK saat dibuka ulang.

## Yang bisa dan tidak bisa

- **Bisa**: `client/scripts/*.gd`, `client/scenes/*.tscn` (termasuk peta di `maps.gd`).
- **Tidak bisa**: aset (`client/assets/*`: model, gambar, suara), pengaturan proyek (daftar autoload,
  izin Android, ikon), versi Godot. Itu tetap butuh APK baru.
- Patch **membawa seluruh skrip dan adegan**, bukan selisih, jadi ukurannya sekitar 0,6 MB.

## Aturan kecocokan

- `min_apk` dihitung otomatis dari git tag: APK paling awal yang sudah punya pemuat patch **dan** isi
  `client/assets` sama dengan sekarang. Ganti manual dengan `MIN_APK=0.47.3`.
- Server hanya memberi patch bila `min_apk <= versi APK <= versi isi patch`.
- Versi APK yang tampil/dikirim ke server tetap versi APK (patch tidak mengubahnya).
- Setelah memasang APK baru, patch lama di HP dibuang otomatis.

## Keamanan dan pengaman

- Patch diunduh lewat alamat server yang sama dengan game; cek ukuran dan SHA-256 sebelum dipakai.
- Pemuat tidak menahan permainan: tanpa jaringan, memakai patch yang sudah tersimpan (atau isi APK).
- Pengaman crash: bila aplikasi dibuka dua kali berturut-turut tanpa sampai layar awal, patch dibuang
  dan id-nya dicatat agar tidak diunduh lagi. Bangun patch baru untuk menggantinya.
- Server ini tidak punya otentikasi untuk patch; siapa pun yang bisa menjangkau servernya bisa
  mengunduhnya. Jangan simpan rahasia di skrip klien.

## Teknis

`Patcher` adalah autoload pertama. Di `_init()` ia memanggil `ProjectSettings.load_resource_pack(path, true)`
sebelum `Api`/`Session`/`Sound` dibuat, sehingga semua skrip berikutnya berasal dari patch.
Keadaan tersimpan di `user://patch/state.cfg`. Di editor / uji, pemuat tidak aktif kecuali env
`GAME_PATCH_URL` diisi.
