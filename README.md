# Game_server

Game RPG 2D untuk Android dengan **server utama di Raspberry Pi 5**.
Satu pemain; server menyimpan progress.

[![CI](https://github.com/MiftahulKhoiri/Game_server/actions/workflows/ci.yml/badge.svg)](https://github.com/MiftahulKhoiri/Game_server/actions/workflows/ci.yml)

## Status

| Bagian | Keadaan |
|--------|---------|
| Server (Go) | Berjalan: daftar pemain, simpan posisi, musuh, pertarungan bergiliran, toko, dan misi (otoritatif) |
| Klien Android (Godot 4.7) | Layar masuk, peta grid, gerak, simpan otomatis, pertarungan di ladang, toko, NPC, misi, bos, dan empat peta; sebagian gambar sudah ada |
| APK | Dibangun otomatis oleh GitHub Actions (lihat [`client/README.md`](client/README.md)) |
| Aset gambar | Menunggu ilustrator |

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
curl -s -X POST localhost:8090/v1/players -d '{"name":"Petualang"}'
```

Simpan `token` dari jawaban itu, lalu:

```bash
curl -s -H "Authorization: Bearer <token>" localhost:8090/v1/players/me
```

Menjalankan sebagai layanan di Pi: lihat [`deploy/gameserver.service`](deploy/gameserver.service).

## Dokumen

- [Arsitektur dan pilihan teknologi](docs/ARCHITECTURE.md)
- [Klien Android](client/README.md)
- [Kontrak API](docs/API.md)
- [Versi dan update APK](docs/VERSIONING.md)
- [Desain game (draf)](docs/GAME_DESIGN.md)
- [Referensi desain peta dan sumber aset gratis](docs/MAP_REFERENCES.md)
- [Panduan aset gambar](assets/README.md)
- [Cara berkontribusi](CONTRIBUTING.md)

## Berkontribusi

Repo ini publik dan terbuka untuk kolaborasi. Baca [CONTRIBUTING.md](CONTRIBUTING.md).

## Lisensi

[GPL-3.0](LICENSE)
