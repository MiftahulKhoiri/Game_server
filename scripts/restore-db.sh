#!/usr/bin/env bash
# Pulihkan database dari cadangan (roadmap no. 236).
#
#   bash scripts/restore-db.sh                 # daftar cadangan yang ada
#   bash scripts/restore-db.sh data/backup/game-20261110-090000.db
#
# Langkah: periksa cadangan (quick_check) -> hentikan server -> simpan database sekarang sebagai
# data/game.db.sebelum-pulih-WAKTU -> salin cadangan -> nyalakan server -> periksa /healthz.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${GAME_DB:-data/game.db}
DIR=${GAME_BACKUP_DIR:-data/backup}
if [ $# -eq 0 ]; then
	echo "Cadangan di $DIR:"
	ls -1t "$DIR"/game-*.db 2>/dev/null || echo "  (belum ada)"
	exit 0
fi
SRC=$1
[ -f "$SRC" ] || { echo "Berkas tidak ada: $SRC"; exit 1; }
python3 - "$SRC" <<'PY'
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
r = c.execute("PRAGMA quick_check").fetchone()[0]
n = c.execute("SELECT COUNT(*) FROM players").fetchone()[0]
print(f"Cadangan: quick_check={r}, pemain={n}")
sys.exit(0 if r == "ok" else 1)
PY
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
systemctl --user stop gameserver || true
STAMP=$(date +%Y%m%d-%H%M%S)
[ -f "$DB" ] && cp "$DB" "$DB.sebelum-pulih-$STAMP"
rm -f "$DB-wal" "$DB-shm"
cp "$SRC" "$DB"
systemctl --user start gameserver
for i in $(seq 1 20); do
	if curl -fsS localhost:8090/healthz >/dev/null 2>&1; then
		echo "Server menyala lagi dengan database dari $SRC"
		echo "Database sebelumnya disimpan di $DB.sebelum-pulih-$STAMP"
		exit 0
	fi
	sleep 0.5
done
echo "Server belum menjawab /healthz; periksa: journalctl --user -u gameserver"
exit 1
