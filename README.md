# Game_server

Game RPG 3D bergaya fantasi untuk Android (Godot 4.7) dengan **server utama di Raspberry Pi 5** (Go + SQLite).
Server adalah sumber kebenaran: level, emas, barang, pertarungan, misi, dan dagang antarpemain dihitung di server.

[![CI](https://github.com/MiftahulKhoiri/Game_server/actions/workflows/ci.yml/badge.svg)](https://github.com/MiftahulKhoiri/Game_server/actions/workflows/ci.yml)
[![Klien Android](https://github.com/MiftahulKhoiri/Game_server/actions/workflows/client.yml/badge.svg)](https://github.com/MiftahulKhoiri/Game_server/actions/workflows/client.yml)

## Status

| Bagian | Keadaan |
|--------|---------|
| Server (Go) | Akun (nama/email + kata sandi, sesi berbatas waktu), simpan posisi, pertarungan langsung, 5 pahlawan dengan gaya senjata, pendamping, toko, tempa, bank, peti simpan, dagang antarpemain, misi, pencapaian, jam dunia bersama, serbuan desa, tempat rahasia, cadangan otomatis |
| Klien Android | Dunia 3D (Desa Awal, Perbatasan, Hutan Lebat, Gunung Batu, Gua Batu, Gua Goblin, toko & ruangan), NPC berjadwal, musuh berkeliaran, bos, HUD, Jurnal (Misi/Peta/Kabar), pengaturan grafis/kontrol/suara, pembaruan & patch dalam aplikasi |
| APK | Dibangun otomatis oleh GitHub Actions; unduh dari [Releases](https://github.com/MiftahulKhoiri/Game_server/releases/latest) |
| Aset 3D | Model CC0 KayKit, Quaternius & OpenGameArt; "Grasshopper" oleh Poly by Google (CC-BY 3.0). Lisensi di `client/assets/models/LISENSI_*.txt` |

## Mulai cepat

Butuh Go 1.24 atau lebih baru.

```bash
git clone https://github.com/MiftahulKhoiri/Game_server.git
cd Game_server
make run            # server di :8090, database di data/game.db
```

Coba dari terminal lain:

```bash
curl -s localhost:8090/healthz
curl -s -X POST localhost:8090/v1/players \
  -d '{"name":"Petualang","email":"petualang@contoh.id","password":"sandi-rahasia-1"}'
curl -s -H "Authorization: Bearer <token>" localhost:8090/v1/players/me
```

Menjalankan sebagai layanan di Pi (tanpa sudo): `make install-user-service`, lalu `make restart` setelah mengubah kode.

## Alamat server untuk aplikasi (HTTPS)

Sejak v0.77.1 aplikasi tersambung lewat **https://raspberrypi.tail3e263f.ts.net:8443**, bisa dari mana saja
(tidak hanya wifi rumah). Alamat ini sudah jadi bawaan APK; HP yang masih menyimpan alamat wifi lama
(`http://192.168.225.3:8090`) dipindahkan otomatis. Mengganti manual: layar awal > **Pengaturan** >
**Alamat server** > isi alamat > **Tes server**.

APK sekarang APK rilis, yang hanya mau alamat `https://` (alamat `http://` biasa ditolak Android).

HTTPS disediakan [Tailscale Funnel](https://tailscale.com/kb/1223/funnel) di Pi, yang meneruskan ke server di
`127.0.0.1:8090` dengan sertifikat sah. Sekali saja di Pi: `sudo tailscale set --operator=pi5`. Lalu:

```bash
tailscale funnel --bg --https=8443 http://127.0.0.1:8090   # nyalakan (tetap aktif setelah Pi restart)
tailscale funnel status                                    # lihat yang sedang aktif
tailscale funnel --https=8443 off                          # matikan (server kembali hanya untuk jaringan rumah)
curl -s https://raspberrypi.tail3e263f.ts.net:8443/healthz # periksa dari mana saja
```

Funnel di port 443 (alamat tanpa `:8443`) dipakai layanan lain di Pi; jangan diubah. Server terbuka ke
internet, tetapi tetap dilindungi login, batas laju, dan pemeriksaan gerakan (lihat
[docs/AUDIT_KEAMANAN.md](docs/AUDIT_KEAMANAN.md)). Detail: [docs/API.md](docs/API.md#alamat-server).

## Perintah penting

| Perintah | Guna |
|----------|------|
| `make check` | format + vet + semua tes server (sama dengan CI) |
| `make client-test GODOT=...` | uji ujung-ke-ujung klien Godot ↔ server asli |
| `make bench` / `make cover` | tolok ukur endpoint & database / cakupan tes |
| `make smoke` | uji asap server yang sedang berjalan (hanya membaca) |
| `make patch GODOT=...` | patch skrip klien tanpa APK baru (lihat [docs/PATCH.md](docs/PATCH.md)) |
| `make backup` / `make restore FILE=...` | cadangkan / pulihkan database |
| `make backup-all` / `make install-backup-timer` | cadangan lengkap kode + database (mingguan otomatis) |

## Dokumen

- [Arsitektur, audit server, Android & performa](docs/ARCHITECTURE.md)
- [Kontrak API](docs/API.md)
- [Pengujian](docs/TESTING.md)
- [Cadangan & pemulihan](docs/BACKUP.md)
- [Versi dan update APK](docs/VERSIONING.md) · [Patch](docs/PATCH.md)
- [Klien Android](client/README.md)
- [Desain game](docs/GAME_DESIGN.md) · [Referensi peta & aset](docs/MAP_REFERENCES.md)
- [Alat yang terpasang di Pi](docs/ALAT_TERPASANG.md)
- [Cara berkontribusi](CONTRIBUTING.md)

## Berkontribusi

Repo ini publik dan terbuka untuk kolaborasi. Baca [CONTRIBUTING.md](CONTRIBUTING.md).

## Lisensi

[GPL-3.0](LICENSE)
