#!/usr/bin/env bash
# Bangun paket game unduhan (.pck) dari client/games/<id>/, periksa isinya, tandatangani manifest, lalu
# terbitkan ke folder katalog server (server langsung melayaninya tanpa restart). Aturan: docs/PCK_PACKAGE_FORMAT.md
#
# Pakai:  GODOT=/path/ke/godot scripts/build-game-pack.sh education_sd [education_smp ...]
#                                                      (atau: make game-pack GAMES="education_sd education_smp")
#   CATALOG_DIR=catalog                                 folder katalog (sama dengan GAME_CATALOG_DIR server)
#   GAME_SIGNING_KEY=~/.config/game_server/publisher_private.pem   kunci PRIVAT penerbit (bukan di repo)
#
# Paket dibangun dari proyek klien yang SAMA dengan APK (mesin, skrip bersama, dan path sama), sehingga
# cocok dengan launcher. Isinya hanya res://games/<id>/ (skrip bersama res://shared/ diambil dari APK).
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
CATALOG_DIR="${CATALOG_DIR:-catalog}"
KEY="${GAME_SIGNING_KEY:-$HOME/.config/game_server/publisher_private.pem}"
PUB="${PUBLISHER_PUB:-client/config/publisher_public.pem}"

[ $# -ge 1 ] || { echo "Pakai: $0 <id_game> [...]" >&2; exit 2; }
[ -f "$KEY" ] || { echo "Kunci penerbit tidak ada di $KEY. Buat dulu: scripts/game-keys.sh" >&2; exit 1; }
if ! diff -q <(openssl rsa -in "$KEY" -pubout 2>/dev/null) "$PUB" >/dev/null; then
	echo "Kunci publik di $PUB bukan pasangan $KEY; APK tidak akan menerima paket ini." >&2
	exit 1
fi

engine="$("$GODOT" --version | head -1 | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?')"
[[ "$engine" =~ ^[0-9]+\.[0-9]+$ ]] && engine="$engine.0"

presets="client/export_presets.cfg"
cp "$presets" "$presets.bak-gamepack"
tmp="$(mktemp -d)"
trap 'mv -f "$presets.bak-gamepack" "$presets"; rm -rf "$tmp"' EXIT

"$GODOT" --headless --path client --import >/dev/null 2>&1 || true

for id in "$@"; do
	[[ "$id" =~ ^[a-z][a-z0-9_]{1,31}$ ]] || { echo "id tidak sah: $id" >&2; exit 1; }
	[ -f "client/games/$id/game.json" ] || { echo "client/games/$id/game.json tidak ada" >&2; exit 1; }
	cp "$presets.bak-gamepack" "$presets"
	python3 - "$presets" "$id" <<'PY'
import os, re, sys
path, gid = sys.argv[1], sys.argv[2]
s = open(path, encoding="utf-8").read()
nums = [int(n) for n in re.findall(r"^\[preset\.(\d+)\]$", s, re.M)]
n = max(nums) + 1
# Salin preset "Patch" (pack tanpa APK) lalu ganti nama dan filternya.
m = re.search(r'^\[preset\.(\d+)\]\n\nname="Patch"', s, re.M)
pi = m.group(1)
head = re.search(r"^\[preset\.%s\]\n(.*?)(?=^\[preset\.%s\.options\])" % (pi, pi), s, re.M | re.S).group(1)
opts = re.search(r"^\[preset\.%s\.options\]\n(.*?)(?=^\[preset\.|\Z)" % pi, s, re.M | re.S).group(1)
client = os.path.dirname(path)
excl = []
for e in sorted(os.listdir(client)):
    if e.startswith(".") or e == "games":
        continue
    excl.append(e + "/*" if os.path.isdir(os.path.join(client, e)) else e)
for g in sorted(os.listdir(os.path.join(client, "games"))):
    if g != gid:
        excl.append("games/%s/*" % g)
head = re.sub(r'^name=".*"$', 'name="GamePack"', head, flags=re.M)
head = re.sub(r'^include_filter=".*"$', 'include_filter="games/%s/*.json"' % gid, head, flags=re.M)
head = re.sub(r'^exclude_filter=".*"$', 'exclude_filter="%s"' % ", ".join(excl), head, flags=re.M)
s = s.rstrip("\n") + "\n\n[preset.%d]\n%s[preset.%d.options]\n%s" % (n, head, n, opts)
open(path, "w", encoding="utf-8").write(s)
PY
	out="$tmp/$id.pck"
	"$GODOT" --headless --path client --export-pack "GamePack" "$out" >"$tmp/$id.log" 2>&1 || {
		tail -20 "$tmp/$id.log" >&2
		echo "Gagal mengekspor paket $id" >&2
		exit 1
	}
	python3 tools/gamepack/gamepack.py check-pck "$out" "$id"
	python3 tools/gamepack/gamepack.py publish --id "$id" --pck "$out" --game-json "client/games/$id/game.json" \
		--engine "$engine" --catalog "$CATALOG_DIR" --key "$KEY"
done
echo "Selesai. Launcher melihat versi baru saat katalog dimuat ulang."
