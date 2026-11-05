# Klien Android (Godot 4.7)

Klien RPG 2D untuk server di folder induk. Gambar masih **placeholder** (bentuk
sederhana digambar lewat kode) sampai aset ilustrator masuk ke `../assets/`.

## Yang sudah ada

- **Layar masuk** (`scenes/login.tscn`): isi alamat server, daftar nama baru, atau lanjutkan.
- **Peta** (`scenes/world.tscn`): gerak per kotak, tampak atas, dengan tombol arah
  layar (atau tombol panah di komputer). Pohon, air, dan rumah menghalangi.
- **Simpan otomatis**: 1,5 detik setelah berhenti bergerak, juga saat aplikasi dijeda.
  Bila versi di server berbeda (409), klien mengikuti versi server lalu menyimpan ulang.
- Token login disimpan di `user://settings.cfg` (di HP: penyimpanan aplikasi).

## Struktur

| Berkas | Fungsi |
|--------|--------|
| `scripts/api.gd` | Autoload `Api`: panggilan HTTP sesuai [`docs/API.md`](../docs/API.md) |
| `scripts/session.gd` | Autoload `Session`: pemain aktif dan pengaturan tersimpan |
| `scripts/maps.gd` | Data peta sementara (teks) dan aturan tabrakan |
| `scripts/login.gd`, `scripts/world.gd` | Dua layar |
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

## Membangun APK

Otomatis lewat GitHub Actions (`.github/workflows/client.yml`): setiap push ke
`main` menjalankan uji lalu membangun APK debug. Unduh dari tab **Actions**
(run terbaru -> Artifacts). Untuk tag `v*`, APK juga masuk **Releases**.

Memasang di HP: izinkan "pasang dari sumber tidak dikenal", buka berkas APK.
APK baru menimpa yang lama tanpa menghapus data, karena ditandatangani kunci
debug yang sama (lihat [`deploy/android/README.md`](../deploy/android/README.md)).
**Jangan hapus aplikasi untuk memperbarui:** token login ikut hilang.

## Catatan

- Server di Pi hanya terjangkau lewat Wi-Fi rumah, kecuali memakai tunnel.
- Tabrakan saat ini dihitung di klien. Rencananya server yang menentukan (lihat `docs/API.md`).
