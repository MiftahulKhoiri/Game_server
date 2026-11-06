# Versi dan update

Dua hal yang dijawab sistem ini: **aplikasi di HP sekarang versi berapa**, dan
**apakah perlu update**.

## Format

`MAJOR.MINOR.PATCH`, contoh `0.3.0`.

| Bagian | Naik bila |
|--------|-----------|
| MAJOR | Perubahan besar yang memutus data/permainan lama |
| MINOR | Fitur baru (peta baru, musuh, sistem baru) |
| PATCH | Perbaikan bug kecil |

Selain itu tiap APK punya **nomor build** (urutan build di GitHub Actions) dan
kode commit. Contoh tampilan: `v0.3.0 (build 12)`. Build lokal/editor tampil
sebagai `v0.3.0 (dev)`.

## Di mana versi disimpan

| Apa | Lokasi | Siapa yang mengubah |
|-----|--------|---------------------|
| Versi aplikasi | `config/version` di `client/project.godot` | Manusia/Claude saat merilis |
| Nomor build, commit | `client/scripts/build_info.gd` | CI otomatis |
| Versi server | `Server` di `internal/version/version.go` | Manusia/Claude saat merilis |
| Versi klien minimum / terbaru | `DefaultMinClient`, `DefaultLatestClient` di `internal/version/version.go`, atau env `GAME_MIN_CLIENT`, `GAME_LATEST_CLIENT` | Pemilik server |

Server dan klien tidak harus selalu sama nomornya; yang menentukan adalah
`min_client` dan `latest_client`.

## Cara kerja di HP

1. Saat layar masuk dibuka, aplikasi menanyakan `GET /v1/version` ke server.
2. Di bawah layar tampil `Aplikasi v0.3.0 (build 12) | Server v0.3.0`.
3. Hasil perbandingan:

| Keadaan | Yang terjadi |
|---------|--------------|
| Versi aplikasi >= `latest_client` | Tidak ada pemberitahuan |
| `min_client` <= versi < `latest_client` | Tulisan kuning "Versi baru tersedia" + tombol unduh; tetap boleh main |
| Versi < `min_client` | Tulisan merah "Wajib update"; tombol mulai dikunci; hanya tombol unduh yang aktif |

4. Setiap permintaan membawa header `X-Client-Version`. Jika server dinaikkan
   `min_client`-nya saat pemain sedang main, server menjawab `426` dan aplikasi
   menampilkan pesan update. Jadi aplikasi lama tidak bisa merusak data.

Aplikasi sangat lama (sebelum 0.2.0) belum mengirim versi, jadi tidak bisa
dipaksa update; mereka tetap dilayani.

## Update dalam aplikasi (v0.12.0)

Tombol "Unduh versi baru" / "Update sekarang" tidak lagi membuka web. Di Android,
`client/scripts/updater.gd` bekerja sendiri:

1. Meminta izin **Pasang aplikasi tak dikenal** untuk Game Petualang (sekali saja;
   Android membukakan pengaturannya, pemain mengaktifkan lalu kembali dan menekan tombol lagi).
2. Membaca rilis terbaru lewat API GitHub (alamatnya diturunkan dari `update_url`),
   mengunduh APK dengan bilah kemajuan, lalu memeriksa ukuran dan sha256 dari GitHub.
3. Menyalin APK ke folder Download lewat MediaStore dan membuka pemasang Android.
   Pemain cukup menekan **Pasang**; aplikasi restart sendiri.

Bila ada langkah yang gagal, atau bukan Android, tombol berubah menjadi "Buka halaman
unduhan" (cara lama). Syarat agar APK baru diterima sebagai pembaruan: ditandatangani
dengan kunci yang sama (`deploy/android/debug.keystore`) dan `version code` lebih tinggi
(otomatis dari nomor build CI). Pasang otomatis butuh Android 10 ke atas.

Sejak v0.13.1 langkah pasang tidak memakai bidang statis Java, mencoba `ACTION_VIEW` lalu
`INSTALL_PACKAGE`, dan bila gagal pesan di layar menyebut langkah serta kesalahan Androidnya.
Berkas hasil unduhan juga tersimpan di `Download/` dengan nama yang sama dengan aset rilis
(mis. `GamePetualang-v0.15.1-build41.apk`) sehingga bisa dibuka manual lewat aplikasi File.

v0.15.1 memperbaiki pasang otomatis yang berhenti diam-diam: `resolver.delete(..., null)`
ditolak wrapper Java Godot (parameter `String[]` tidak menerima `null`), sehingga fungsi
terhenti sebelum berkas dibuat dan layar tetap melapor sukses. Kini argumen itu
`PackedStringArray()`, sukses hanya bila hasilnya persis `OK`, dan kegagalan diam-diam
menampilkan langkah terakhir yang dimulai. Aturan untuk kode Java-dari-GDScript: jangan
pernah mengoper `null` ke parameter String/array.

Versi yang memuat fitur ini sendiri harus dipasang manual sekali; setelah itu
pembaruan berikutnya bisa lewat dalam aplikasi.

## Cara merilis versi baru

1. Naikkan `config/version` di `client/project.godot` (mis. `0.3.0`).
2. Jika server ikut berubah, naikkan `Server` di `internal/version/version.go`.
3. Naikkan `DefaultLatestClient` ke versi yang sama (atau set `GAME_LATEST_CLIENT`
   di server). Pemain akan melihat ajakan update.
4. Naikkan `DefaultMinClient` (atau `GAME_MIN_CLIENT`) **hanya** jika versi lama
   tidak boleh dipakai lagi, misalnya format simpanan berubah.
5. Commit dan push ke `main`. CI menguji dan membangun APK.
6. Beri tag yang sama dengan versi: `git tag v0.3.0 && git push origin v0.3.0`.
   CI membuat **Release** berisi APK bernama `GamePetualang-v0.3.0-buildN.apk`.
   CI menolak tag yang berbeda dengan `config/version`.
7. Mulai ulang server di Pi (`make build` lalu restart layanan).

`DefaultUpdateURL` (atau `GAME_UPDATE_URL`) menentukan ke mana tombol unduh
membawa pemain; bawaannya halaman Releases terbaru.

## Catatan

- v0.16.0 menambah akun (email + kata sandi, `POST /v1/login`). Aplikasi lama tidak bisa daftar
  (kata sandi wajib), jadi `DefaultMinClient` dinaikkan ke 0.16.0: aplikasi lama diminta update.

- v0.17.0 menambah model 3D berrangka (Blender) + animasi idle/jalan/serang/luka/mati untuk
  petani, goblin penjaga, ogre batu, serigala, ular, belalang, dan kelelawar. Tidak mengubah API;
  `DefaultMinClient` tetap 0.16.0.

- v0.17.1 menata ulang layar awal: tes server (menciut dengan tanda centang hijau), tombol
  Daftar/Masuk di tengah, info pembaruan di dasar, dan isi layar naik otomatis saat papan ketik muncul.
  Tidak mengubah API.

- APK baru harus dipasang **menimpa** yang lama (jangan hapus aplikasi), karena
  menghapus aplikasi menghapus token login.
- `version code` Android = nomor build, naik terus, sehingga HP menerima APK baru
  sebagai pembaruan.
