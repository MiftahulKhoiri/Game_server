#!/usr/bin/env bash
# Buat pasangan kunci penerbit paket game (RSA 3072). Kunci PRIVAT disimpan di luar repo dan tidak pernah
# masuk APK; kunci PUBLIK ditulis ke client/config/publisher_public.pem (ikut APK untuk memeriksa tanda tangan).
#
# Pakai:  scripts/game-keys.sh            (menolak menimpa kunci yang sudah ada)
#         FORCE=1 scripts/game-keys.sh    (ganti kunci: APK lama TIDAK akan menerima paket baru!)
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="${GAME_SIGNING_KEY:-$HOME/.config/game_server/publisher_private.pem}"
PUB="client/config/publisher_public.pem"
if [ -f "$KEY" ] && [ "${FORCE:-}" != "1" ]; then
	echo "Kunci sudah ada: $KEY (pakai FORCE=1 untuk mengganti; paket lama perlu ditandatangani ulang)." >&2
	openssl rsa -in "$KEY" -pubout -out "$PUB" 2>/dev/null
	echo "Kunci publik disegarkan: $PUB"
	exit 0
fi
mkdir -p "$(dirname "$KEY")"
chmod 700 "$(dirname "$KEY")"
umask 077
openssl genrsa -out "$KEY" 3072 2>/dev/null
chmod 600 "$KEY"
openssl rsa -in "$KEY" -pubout -out "$PUB" 2>/dev/null
echo "Kunci privat : $KEY (cadangkan di tempat aman, JANGAN di-commit)"
echo "Kunci publik : $PUB (commit; ikut APK)"
