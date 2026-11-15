#!/usr/bin/env bash
# Uji platform multi-game (v0.84.0) ujung-ke-ujung dengan Godot headless + server Go sungguhan:
#   1. kunci penerbit UJI sementara (kunci asli tidak disentuh), paket SD & SMP 1.0.0 dibangun + ditandatangani
#   2. salinan proyek klien TANPA client/games (meniru APK: game unduhan tidak ikut)
#   3. fase 1: katalog, unduh putus + lanjut, paket/manifest rusak ditolak, pasang, main, kembali ke launcher
#   4. SD 1.0.1 diterbitkan; fase 2 (proses baru): update per game, rollback, hapus/pasang ulang
#   5. fase 3 (proses baru): server tak terjangkau -> launcher & game terpasang tetap jalan
# Pakai:  GODOT=/path/ke/godot scripts/platform-test.sh      (atau: make platform-test)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-8097}"
TMP="$(mktemp -d)"
SERVER_PID=""
GJ="client/games/education_sd/game.json"
cp "$GJ" "$TMP/game.json.asli"
cleanup() {
	[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
	cp "$TMP/game.json.asli" "$GJ"
	rm -rf "$TMP"
}
trap cleanup EXIT

# Versi paket SD sekarang dan versi "update" uji (patch + 1).
SD_V1="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$GJ")"
SD_V2="$(python3 -c 'import sys;a=sys.argv[1].split(".");a[2]=str(int(a[2])+1);print(".".join(a))' "$SD_V1")"
export TEST_SD_V1="$SD_V1" TEST_SD_V2="$SD_V2"

openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
openssl rsa -in "$TMP/key.pem" -pubout -out "$TMP/pub.pem" 2>/dev/null
export GAME_SIGNING_KEY="$TMP/key.pem" PUBLISHER_PUB="$TMP/pub.pem" CATALOG_DIR="$TMP/catalog" GODOT
bash scripts/build-game-pack.sh education_sd education_smp

go build -o "$TMP/gameserver" ./cmd/gameserver
GAME_BACKUP_DIR=off GAME_CATALOG_DIR="$TMP/catalog" GAME_ADDR="127.0.0.1:$PORT" GAME_DB="$TMP/game.db" "$TMP/gameserver" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break; sleep 0.1; done

# Salinan proyek seperti isi APK: tanpa games/, nama aplikasi lain supaya user:// terpisah dari uji lain.
SIM="$TMP/sim"
mkdir -p "$SIM"
tar -C client --exclude=./games --exclude=./export -cf - . | tar -C "$SIM" -xf -
sed -i 's/^config\/name=".*"/config\/name="Game Platform Uji"/' "$SIM/project.godot"
USERDIR="$HOME/.local/share/godot/app_userdata/Game Platform Uji"
rm -rf "$USERDIR"
"$GODOT" --headless --path "$SIM" --import >/dev/null 2>&1 || true

run_phase() {
	echo "### Fase $1"
	GAME_URL="http://127.0.0.1:$PORT" TEST_PUB="$TMP/pub.pem" TEST_PHASE="$1" TEST_CATALOG="$TMP/catalog" \
		"$GODOT" --headless --path "$SIM" -s res://tests/platform_test.gd 2>&1 | tee "$TMP/fase$1.log" | grep -E '^(==|  ok|  GAGAL|HASIL|SCRIPT ERROR|ERROR)' || true
	grep -q '^HASIL: LULUS' "$TMP/fase$1.log"
	# Galat skrip menghentikan fungsi uji di tengah jalan tanpa "GAGAL": anggap gagal.
	! grep -q 'SCRIPT ERROR' "$TMP/fase$1.log"
}
run_phase 1
sed -i "s/\"version\": \"$SD_V1\"/\"version\": \"$SD_V2\"/" "$GJ"
bash scripts/build-game-pack.sh education_sd
cp "$TMP/game.json.asli" "$GJ"
run_phase 2
run_phase 3
rm -rf "$USERDIR"
echo "Uji platform: SEMUA FASE LULUS"
