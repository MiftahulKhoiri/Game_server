#!/usr/bin/env bash
# Cadangan lengkap kode + database (roadmap no. 274), aman walau server berjalan.
#
#   bash scripts/backup-all.sh                 -> ~/cadangan_game/game-YYYYMMDD-HHMMSS.tar.gz
#   BACKUP_DEST=/media/flashdisk bash scripts/backup-all.sh   (simpan ke flashdisk / disk lain)
#   BACKUP_KEEP=10 ...                         (jumlah arsip yang disimpan, bawaan 8)
#
# Isi arsip:
#   kode.bundle     seluruh riwayat git (semua cabang & tag): git clone kode.bundle Game_server
#   game.db         salinan database (VACUUM INTO), sudah diperiksa PRAGMA integrity_check
#   patches/        patch konten klien yang sedang dibagikan server
#   deploy/         berkas layanan systemd
#   INFO.txt        versi, commit, waktu, jumlah pemain, cara memulihkan
# Cara memulihkan: lihat docs/BACKUP.md.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
DB=${GAME_DB:-data/game.db}
DEST=${BACKUP_DEST:-$HOME/cadangan_game}
KEEP=${BACKUP_KEEP:-8}
STAMP=$(date -u +%Y%m%d-%H%M%S)
NAME="game-$STAMP"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/$NAME" "$DEST"
OUT="$WORK/$NAME"

# 1) Kode: bundle git berisi semua cabang dan tag, lalu diperiksa.
git bundle create "$OUT/kode.bundle" --all >/dev/null 2>&1
git bundle verify "$OUT/kode.bundle" >/dev/null 2>&1 || { echo "bundle git rusak" >&2; exit 1; }
if [ -n "$(git status --porcelain)" ]; then
	git diff HEAD > "$OUT/perubahan-belum-commit.diff" || true
fi

# 2) Database: salinan konsisten lalu diperiksa keutuhannya.
if [ -f "$DB" ]; then
	python3 - "$DB" "$OUT/game.db" <<'PY'
import sqlite3, sys
src = sqlite3.connect(sys.argv[1])
src.execute("VACUUM INTO ?", (sys.argv[2],))
dst = sqlite3.connect(sys.argv[2])
ok = dst.execute("PRAGMA integrity_check").fetchone()[0]
if ok != "ok":
    sys.exit("database cadangan rusak: " + ok)
PY
	PLAYERS=$(python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute('select count(*) from players').fetchone()[0])" "$OUT/game.db")
else
	PLAYERS="(tidak ada database di $DB)"
fi

# 3) Berkas pendukung.
[ -d patches ] && cp -r patches "$OUT/patches"
cp -r deploy "$OUT/deploy"
{
	echo "Cadangan Game_server $STAMP (UTC)"
	echo "Commit : $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))"
	echo "Tag    : $(git describe --tags --always 2>/dev/null)"
	echo "Pemain : $PLAYERS"
	echo "Host   : $(hostname)"
	echo
	echo "Memulihkan (lihat docs/BACKUP.md):"
	echo "  git clone kode.bundle Game_server && cd Game_server"
	echo "  git remote set-url origin https://github.com/MiftahulKhoiri/Game_server.git"
	echo "  make restore FILE=/jalur/ke/game.db"
} > "$OUT/INFO.txt"

tar -C "$WORK" -czf "$DEST/$NAME.tar.gz" "$NAME"
echo "Cadangan dibuat: $DEST/$NAME.tar.gz ($(du -h "$DEST/$NAME.tar.gz" | cut -f1), pemain: $PLAYERS)"

# 4) Simpan KEEP arsip terbaru saja.
ls -1t "$DEST"/game-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
	rm -f "$old" && echo "Dihapus (lama): $old"
done
cd "$ROOT"
