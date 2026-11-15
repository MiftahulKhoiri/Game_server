#!/usr/bin/env bash
# Uji Game Pembelajaran SD "Petualangan Pulau Ilmu" (headless): bank soal (validator Python), lalu
# client/tests/sd_test.gd (data, 11 tipe soal x 3 mode, sesi, adaptif, mini-game, hadiah, simpan, migrasi).
# Pakai:  GODOT=/path/ke/godot scripts/sd-test.sh      (atau: make sd-test)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
python3 tools/gamepack/make_sd_bank.py >/dev/null
git diff --quiet -- client/games/education_sd/data/pulau_ilmu.json 2>/dev/null || \
	echo "Catatan: pulau_ilmu.json dibuat ulang dari tools/gamepack/make_sd_bank.py (commit hasilnya)."
"$GODOT" --headless --path client --import >/dev/null 2>&1 || true
"$GODOT" --headless --path client -s res://tests/sd_test.gd 2>&1 | tee "${LOG:-/tmp/sd-test.log}" | grep -E '^(==|  ok|  GAGAL|SD:|HASIL|SCRIPT ERROR|ERROR|    )' || true
grep -q '^HASIL: LULUS' "${LOG:-/tmp/sd-test.log}"
# Galat skrip menghentikan fungsi uji di tengah jalan tanpa "GAGAL": anggap gagal.
! grep -q 'SCRIPT ERROR' "${LOG:-/tmp/sd-test.log}"
