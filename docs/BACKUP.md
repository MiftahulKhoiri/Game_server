# Cadangan dan pemulihan

## Tiga lapis cadangan

| Lapis | Kapan | Isi | Tempat |
|-------|-------|-----|--------|
| Otomatis server | tiap 24 jam (`GAME_BACKUP_HOURS`), simpan 7 (`GAME_BACKUP_KEEP`) | database | `data/backup/game-*.db` |
| Lengkap mingguan | Minggu 03:00 (`gameserver-backup.timer`), simpan 8 | kode (git bundle semua cabang & tag) + database + patch + berkas layanan | `~/cadangan_game/game-*.tar.gz` |
| GitHub | setiap `git push` | kode + riwayat | github.com/MiftahulKhoiri/Game_server |

Manual kapan saja: `make backup` (database saja) atau `make backup-all` (lengkap).

Cadangan database dibuat dengan `VACUUM INTO` (aman saat server berjalan) dan cadangan lengkap
diperiksa `PRAGMA integrity_check` serta `git bundle verify` sebelum disimpan.

## Simpan di tempat lain (disarankan)

Semua cadangan di atas (kecuali GitHub) ada di disk yang sama dengan database. Bila disk Pi rusak,
cadangan ikut hilang. Salin sesekali ke flashdisk/HP/cloud:

```bash
BACKUP_DEST=/media/pi5/FLASHDISK/cadangan_game make backup-all
# atau ubah tujuan jadwal mingguan:
systemctl --user edit gameserver-backup     # tambahkan: [Service] Environment=BACKUP_DEST=/media/...
```

## Memulihkan database saja

```bash
make restore FILE=data/backup/game-20261110-030000.db
```

Server dihentikan, database lama disimpan sebagai `game.db.sebelum-pulih-*`, cadangan diperiksa
`quick_check`, lalu server dinyalakan lagi.

## Memulihkan semuanya (Pi baru / disk baru)

```bash
tar -xzf game-YYYYMMDD-HHMMSS.tar.gz && cd game-YYYYMMDD-HHMMSS
cat INFO.txt                                   # commit, tag, jumlah pemain
git clone kode.bundle ~/Game_server && cd ~/Game_server
git remote set-url origin https://github.com/MiftahulKhoiri/Game_server.git
mkdir -p data && cp ../game-YYYYMMDD-HHMMSS/game.db data/game.db
cp -r ../game-YYYYMMDD-HHMMSS/patches .        # bila ada
make install-user-service                      # bangun + pasang layanan + nyalakan
make install-backup-timer
make smoke                                     # periksa server menjawab
```

`perubahan-belum-commit.diff` (bila ada) berisi perubahan yang belum di-commit saat cadangan dibuat:
`git apply perubahan-belum-commit.diff`.
