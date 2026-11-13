#!/usr/bin/env bash
# Cadangkan database sekarang juga (di luar jadwal otomatis server), aman walau server berjalan.
#   bash scripts/backup-db.sh   -> data/backup/game-YYYYMMDD-HHMMSS.db
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${GAME_DB:-data/game.db}
DIR=${GAME_BACKUP_DIR:-data/backup}
mkdir -p "$DIR"
OUT="$DIR/game-$(date -u +%Y%m%d-%H%M%S).db"
# Ditulis ke .tmp dulu, diperiksa, lalu diganti nama: tidak ada cadangan setengah jadi bila gagal di tengah.
python3 - "$DB" "$OUT" <<'PY'
import os, sqlite3, sys
src, out = sys.argv[1], sys.argv[2]
tmp = out + ".tmp"
if os.path.exists(tmp):
    os.remove(tmp)
try:
    c = sqlite3.connect(src)
    c.execute("VACUUM INTO ?", (tmp,))
    c.close()
    d = sqlite3.connect("file:" + tmp + "?mode=ro", uri=True)
    r = d.execute("PRAGMA integrity_check").fetchone()[0]
    n = d.execute("SELECT COUNT(*) FROM players").fetchone()[0]
    d.close()
    if r != "ok":
        raise SystemExit("cadangan rusak: " + r)
    with open(tmp, "rb") as f:
        os.fsync(f.fileno())
    os.replace(tmp, out)
    print(f"Cadangan dibuat: {out} (integrity_check ok, pemain={n})")
except BaseException:
    if os.path.exists(tmp):
        os.remove(tmp)
    raise
PY
