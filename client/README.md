# Klien Android (Godot 4.7)

Klien RPG 3D untuk server di folder induk (sejak v0.13.0). Model karakter/musuh
masih campuran: ksatria memakai Paladin (`assets/models/ksatria.glb`), goblin, golem, nenek, petani,
babi hutan, tikus, dan Raja Goblin memakai model hasil gambar-ke-3D (TripoSR, lihat `../tools/triposr/`), sisanya
**placeholder** buatan kode (`scripts/models.gd`). Model lain diganti dengan menaruh `assets/models/<id>.glb`
(id = id musuh/NPC) tanpa mengubah kode.

## Yang sudah ada

- **Layar masuk** (`scenes/login.tscn`): isi alamat server, daftar nama baru, atau lanjutkan.
- **Dunia 3D** (`scenes/world3d.tscn`): gerak bebas, kamera di belakang karakter;
  joystick melayang (sentuh kiri), geser di kanan untuk memutar kamera (di komputer:
  WASD/panah, Q/E). Pohon, air, dan rumah menghalangi. Peta diubah dari teks petak
  (`maps.gd`) menjadi 3D oleh `scripts/world_build.gd`. `scenes/world.tscn` (2D lama)
  masih ada untuk uji.
- **Simpan otomatis**: 1,5 detik setelah berhenti bergerak, juga saat aplikasi dijeda.
  Bila versi di server berbeda (409), klien mengikuti versi server lalu menyimpan ulang.
- **Pertarungan** (`scenes/battle.tscn`, arena 3D): muncul acak di ladang, tombol Serang /
  Bertahan / Ramuan / Kabur. Hasil dihitung server; bila aplikasi ditutup di
  tengah pertarungan, pertarungan dilanjutkan saat masuk lagi.
- **Bicara dengan NPC** (`scenes/dialog.tscn`): tombol Bicara aktif bila berdiri di sebelah NPC; terima misi dan ambil hadiah.
- **Toko** (`scenes/shop.tscn`): tombol Toko di peta; beli/jual barang, harga dari server.
- **Tas** (`scenes/inventory.tscn`): tombol Tas di peta; lihat barang, pasang/lepas perlengkapan, minum ramuan, istirahat gratis di desa.
- **Update dalam aplikasi** (`scripts/updater.gd`): unduh APK rilis terbaru dan buka pemasang Android tanpa membuka web (lihat `docs/VERSIONING.md`).
- Token login disimpan di `user://settings.cfg` (di HP: penyimpanan aplikasi).

## Struktur

| Berkas | Fungsi |
|--------|--------|
| `scripts/api.gd` | Autoload `Api`: panggilan HTTP sesuai [`docs/API.md`](../docs/API.md) |
| `scripts/session.gd` | Autoload `Session`: pemain aktif dan pengaturan tersimpan |
| `scripts/version.gd`, `scripts/build_info.gd` | Versi aplikasi dan pembanding versi; `build_info.gd` diisi CI |
| `scripts/maps.gd` | Data peta sementara (teks) dan aturan tabrakan |
| `scripts/world3d.gd`, `movement.gd`, `world_build.gd`, `joystick.gd` | Dunia 3D: adegan, gerak + tabrakan, pembangun peta 3D, joystick |
| `scripts/models.gd`, `model_rig.gd` | Model 3D (GLB atau placeholder) dan animasinya |
| `tests/shot.gd` | Alat pengembang: tangkapan layar 3D (tidak ikut APK) |
| `scripts/login.gd`, `scripts/world.gd`, `scripts/battle.gd`, `scripts/shop.gd`, `scripts/dialog.gd` | Layar-layar game |
| `tests/e2e.gd` | Uji ujung-ke-ujung terhadap server Go asli |
| `export_presets.cfg` | Pengaturan ekspor APK |

## Menjalankan

1. Pasang [Godot 4.7](https://godotengine.org/download) dan buka folder `client/`.
2. Jalankan server: `make run` (di folder induk).
3. Tekan F5. Di kolom alamat isi `http://<ip-server>:8090`.

Membuka `scenes/world.tscn` langsung (F6) memakai pemain uji tanpa server,
berguna untuk mencoba peta dan gambar baru.

## Uji otomatis

```bash
make client-test GODOT=/path/ke/godot
```

Memulai server dengan database sementara lalu menjalankan `tests/e2e.gd`
(daftar, gerak, simpan otomatis, tabrakan, token salah).

## Versi

Aplikasi menampilkan versinya di layar masuk (`v0.2.0 (build 12)`) dan memberi tahu
bila ada versi baru atau wajib update. Aturan dan cara merilis: [`docs/VERSIONING.md`](../docs/VERSIONING.md).
Versi aplikasi = `config/version` di `project.godot`.

## Membangun APK

Otomatis lewat GitHub Actions (`.github/workflows/client.yml`): setiap push ke
`main` menjalankan uji lalu membangun APK debug. Unduh dari tab **Actions**
(run terbaru -> Artifacts); nama berkas memuat versi dan build, mis.
`GamePetualang-v0.2.0-build12.apk`. Untuk tag `v*`, APK juga masuk **Releases**.

Memasang di HP: izinkan "pasang dari sumber tidak dikenal", buka berkas APK.
APK baru menimpa yang lama tanpa menghapus data, karena ditandatangani kunci
debug yang sama (lihat [`deploy/android/README.md`](../deploy/android/README.md)).
**Jangan hapus aplikasi untuk memperbarui:** token login ikut hilang.

## Catatan

- Server di Pi hanya terjangkau lewat Wi-Fi rumah, kecuali memakai tunnel.
- Tabrakan saat ini dihitung di klien. Rencananya server yang menentukan (lihat `docs/API.md`).
