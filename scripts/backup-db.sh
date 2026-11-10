#!/usr/bin/env bash
# Cadangkan database sekarang juga (di luar jadwal otomatis server), aman walau server berjalan.
#   bash scripts/backup-db.sh   -> data/backup/game-YYYYMMDD-HHMMSS.db
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${GAME_DB:-data/game.db}
DIR=${GAME_BACKUP_DIR:-data/backup}
mkdir -p "$DIR"
OUT="$DIR/game-$(date -u +%Y%m%d-%H%M%S).db"
python3 - "$DB" "$OUT" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("VACUUM INTO ?", (sys.argv[2],))
print("Cadangan dibuat:", sys.argv[2])
PY
