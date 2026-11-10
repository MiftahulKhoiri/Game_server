#!/usr/bin/env bash
# Uji asap server yang sedang berjalan (roadmap no. 266, 275): hanya membaca, tidak membuat akun,
# jadi aman untuk server sungguhan yang sedang dimainkan.
#
#   bash scripts/smoke-test.sh                       -> http://127.0.0.1:8090
#   bash scripts/smoke-test.sh http://192.168.1.5:8090   (dari HP/PC lain di jaringan yang sama)
set -uo pipefail
URL=${1:-${GAME_URL:-http://127.0.0.1:8090}}
FAIL=0
pass() { echo "  ok   $1"; }
fail() { echo "  GAGAL $1"; FAIL=1; }

code() { curl -s -o /tmp/smoke.$$ -w '%{http_code}' --max-time 5 "$@"; }

echo "Uji asap: $URL"
[ "$(code "$URL/healthz")" = 200 ] && pass "server menyala (healthz)" || fail "healthz tidak menjawab 200"

if [ "$(code "$URL/v1/version")" = 200 ]; then
	ver=$(python3 -c "import json;d=json.load(open('/tmp/smoke.$$'));print(d['server'],d['latest_client'],d['min_client'],d['api'])" 2>/dev/null)
	[ -n "$ver" ] && pass "versi: server/klien terbaru/klien minimum/api = $ver" || fail "jawaban /v1/version tidak lengkap"
else
	fail "/v1/version tidak menjawab 200"
fi

if [ "$(code "$URL/v1/time")" = 200 ]; then
	drift=$(python3 -c "import json,time;print(abs(int(json.load(open('/tmp/smoke.$$'))['unix'])-int(time.time())))" 2>/dev/null || echo 999)
	[ "$drift" -le 5 ] && pass "jam dunia sesuai jam Pi (selisih ${drift} d)" || fail "jam server melenceng ${drift} detik"
else
	fail "/v1/time tidak menjawab 200"
fi

[ "$(code "$URL/v1/players/me")" = 401 ] && pass "tanpa token ditolak 401" || fail "tanpa token tidak ditolak"
[ "$(code -H 'Authorization: Bearer token-palsu' "$URL/v1/players/me")" = 401 ] && pass "token palsu ditolak 401" || fail "token palsu tidak ditolak"
c=$(code "$URL/v1/tidak-ada")
if [ "$c" = 404 ] && grep -q '"error"' /tmp/smoke.$$; then pass "jalur tak dikenal: 404 JSON"; else fail "jalur tak dikenal: $c"; fi
c=$(code -X POST -H 'Content-Type: application/json' -d '{"login":"bukan-pemain-asap","password":"salah-sekali-123"}' "$URL/v1/login")
[ "$c" = 401 ] || [ "$c" = 429 ] && pass "login salah ditolak ($c)" || fail "login salah menjawab $c"
c=$(code "$URL/v1/patch?apk=0.62.0")
[ "$c" = 200 ] && pass "manifes patch terbaca" || fail "manifes patch menjawab $c"

t=$(curl -s -o /dev/null -w '%{time_total}' --max-time 5 "$URL/v1/version")
python3 -c "import sys;sys.exit(0 if float('$t')<0.5 else 1)" && pass "waktu jawab ${t} d" || fail "server lambat: ${t} d"

rm -f /tmp/smoke.$$
if [ "$FAIL" = 0 ]; then echo "SEMUA LOLOS"; else echo "ADA YANG GAGAL"; fi
exit $FAIL
