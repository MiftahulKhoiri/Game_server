#!/usr/bin/env bash
# Bangun patch isi game (.pck: skrip + adegan, tanpa aset) dan pasang ke folder patch server.
# Pemakai HP cukup membuka ulang aplikasi; tanpa APK baru. Aturan lengkap: docs/PATCH.md
#
# Pakai:  GODOT=/path/ke/godot scripts/build-patch.sh        (atau: make patch)
#   PATCH_DIR=patches   folder keluaran (sama dengan GAME_PATCH_DIR server)
#   MIN_APK=0.47.3      paksa batas bawah versi APK (bawaan: dihitung dari git tag)
#   ROLLBACK=1          cabut patch aktif: HP kembali ke isi APK
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PATCH_DIR="${PATCH_DIR:-patches}"
mkdir -p "$PATCH_DIR"

if [ "${ROLLBACK:-}" = "1" ]; then
	rm -f "$PATCH_DIR/latest.json"
	echo "Patch dicabut. HP memakai isi APK-nya lagi saat aplikasi dibuka berikutnya."
	exit 0
fi

version="$(sed -n 's/^config\/version="\(.*\)"/\1/p' client/project.godot)"

# Batas bawah APK: tag paling awal yang (a) sudah memuat pemuat patch dan (b) isi folder aset-nya
# sama persis dengan sekarang, karena patch tidak membawa aset. APK yang lebih tua tak diberi patch.
min_apk="${MIN_APK:-}"
if [ -z "$min_apk" ]; then
	want="$(git rev-parse HEAD:client/assets)"
	for tag in $(git tag --sort=v:refname); do
		git cat-file -e "$tag:client/scripts/patcher.gd" 2>/dev/null || continue
		[ "$(git rev-parse "$tag:client/assets" 2>/dev/null)" = "$want" ] || continue
		min_apk="${tag#v}"
		break
	done
fi
if [ -z "$min_apk" ]; then
	min_apk="$version"
	echo "Catatan: belum ada tag APK yang cocok; min_apk = $version (versi ini sendiri)." >&2
fi
if [ -n "$(git status --porcelain client)" ]; then
	echo "Peringatan: ada perubahan klien yang belum di-commit; patch memuatnya." >&2
fi

"$GODOT" --headless --path client --import >/dev/null 2>&1 || true
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$GODOT" --headless --path client --export-pack "Patch" "$tmp/patch.pck" >"$tmp/log" 2>&1 || {
	tail -20 "$tmp/log" >&2
	echo "Gagal membangun patch." >&2
	exit 1
}

sha="$(sha256sum "$tmp/patch.pck" | cut -d' ' -f1)"
size="$(stat -c %s "$tmp/patch.pck")"
id="${version}-${sha:0:8}"
cp "$tmp/patch.pck" "$PATCH_DIR/$id.pck"
built="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"id":"%s","sha256":"%s","size":%s,"version":"%s","min_apk":"%s","built":"%s"}\n' \
	"$id" "$sha" "$size" "$version" "$min_apk" "$built" >"$PATCH_DIR/latest.json.tmp"
mv "$PATCH_DIR/latest.json.tmp" "$PATCH_DIR/latest.json"

# Buang patch lama, sisakan 3 terbaru.
ls -1t "$PATCH_DIR"/*.pck 2>/dev/null | tail -n +4 | xargs -r rm -f

echo "Patch $id ($((size / 1024)) KB) untuk APK >= $min_apk, isi versi $version."
echo "Berlaku saat HP membuka ulang aplikasi."
