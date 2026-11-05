#!/usr/bin/env bash
# Uji ujung-ke-ujung: klien Godot (headless) <-> server Go asli.
#
# Memulai server dengan database sementara, lalu menjalankan client/tests/e2e.gd.
# Pakai:  GODOT=/path/ke/godot scripts/client-test.sh      (atau: make client-test)
# Opsional: LOG_DIR=/folder  -> log server disalin ke LOG_DIR/client-test-server.log
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-8099}"

TMP="$(mktemp -d)"
SERVER_PID=""
cleanup() {
	[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
	if [ -n "${LOG_DIR:-}" ]; then
		mkdir -p "$LOG_DIR" && cp "$TMP/server.log" "$LOG_DIR/client-test-server.log" 2>/dev/null || true
	fi
	rm -rf "$TMP"
}
trap cleanup EXIT

go build -o "$TMP/gameserver" ./cmd/gameserver
GAME_ADDR="127.0.0.1:$PORT" GAME_DB="$TMP/game.db" "$TMP/gameserver" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 50); do
	curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break
	sleep 0.1
done

# Impor aset dulu agar skrip dan ikon terdaftar.
"$GODOT" --headless --path client --import >/dev/null 2>&1 || true

GAME_URL="http://127.0.0.1:$PORT" "$GODOT" --headless --path client -s res://tests/e2e.gd
