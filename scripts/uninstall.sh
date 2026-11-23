#!/usr/bin/env bash
# Copot pemasangan server game dari Pi (kebalikan dari `make install-user-service` & `make install-backup-timer`).
#
#   bash scripts/uninstall.sh               -> hentikan & lepas layanan systemd, hapus bin/. DATA TETAP.
#   bash scripts/uninstall.sh --hapus-data  -> sama, ditambah: cadangan lengkap terakhir (backup-all) lalu hapus data/
#   bash scripts/uninstall.sh --coba        -> hanya tampilkan apa yang akan dilakukan, tidak mengubah apa pun
#   -y / --ya                               -> tanpa pertanyaan konfirmasi
#
# Yang TIDAK pernah dihapus skrip ini:
#   - folder kode Game_server (hapus sendiri bila perlu: rm -rf ~/Game_server)
#   - cadangan di ~/cadangan_game (atau BACKUP_DEST)
#   - kunci penerbit paket ~/.config/game_server/publisher_private.pem (tanpa kunci ini APK lama tak menerima paket baru)
# Memasang lagi: make install-user-service (dan make install-backup-timer).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

HAPUS_DATA=0
COBA=0
YA=0
for a in "$@"; do
	case "$a" in
	--hapus-data) HAPUS_DATA=1 ;;
	--coba | --dry-run) COBA=1 ;;
	-y | --ya) YA=1 ;;
	-h | --help)
		sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "Opsi tidak dikenal: $a (lihat --help)" >&2
		exit 2
		;;
	esac
done

UNIT_DIR="$HOME/.config/systemd/user"
UNITS=(gameserver-backup.timer gameserver-backup.service gameserver.service)

jalan() {
	if [ "$COBA" = 1 ]; then
		echo "  [coba] $*"
	else
		"$@"
	fi
}

# Sama seperti jalan, tetapi keluaran perintah disembunyikan dan kegagalan diabaikan.
jalan_diam() {
	if [ "$COBA" = 1 ]; then
		echo "  [coba] $*"
	else
		"$@" >/dev/null 2>&1 || true
	fi
}

# systemctl --user butuh bus sesi pengguna; isi otomatis bila dijalankan dari SSH/cron tanpa sesi lengkap.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

echo "Copot pemasangan Game_server di $ROOT"
echo "  - hentikan & nonaktifkan: ${UNITS[*]}"
echo "  - hapus berkas layanan di $UNIT_DIR"
echo "  - hapus program bin/"
if [ "$HAPUS_DATA" = 1 ]; then
	echo "  - CADANGAN LENGKAP terakhir ke ${BACKUP_DEST:-$HOME/cadangan_game}, lalu HAPUS data/ (database pemain)"
else
	echo "  - data/ (database pemain) TIDAK dihapus"
fi

if [ "$COBA" = 0 ] && [ "$YA" = 0 ]; then
	if [ "$HAPUS_DATA" = 1 ]; then
		read -r -p "Ketik HAPUS untuk melanjutkan: " jawab
		[ "$jawab" = "HAPUS" ] || { echo "Dibatalkan."; exit 1; }
	else
		read -r -p "Lanjutkan? [y/N] " jawab
		case "$jawab" in y | Y | ya | Ya) ;; *) echo "Dibatalkan."; exit 1 ;; esac
	fi
fi

# 1) Cadangan dulu (selagi server mungkin masih jalan; backup-all aman walau server berjalan).
if [ "$HAPUS_DATA" = 1 ] && [ -f data/game.db ]; then
	echo "Membuat cadangan lengkap terakhir..."
	if [ "$COBA" = 1 ]; then
		echo "  [coba] bash scripts/backup-all.sh"
	elif ! bash scripts/backup-all.sh; then
		echo "Cadangan GAGAL — data tidak dihapus. Perbaiki dulu lalu ulangi." >&2
		exit 1
	fi
fi

# 2) Layanan systemd tingkat pengguna.
if command -v systemctl >/dev/null 2>&1; then
	for u in "${UNITS[@]}"; do
		if [ -f "$UNIT_DIR/$u" ] || systemctl --user cat "$u" >/dev/null 2>&1; then
			echo "Menghentikan $u"
			jalan_diam systemctl --user disable --now "$u"
		fi
	done
fi
for u in "${UNITS[@]}"; do
	if [ -f "$UNIT_DIR/$u" ]; then
		echo "Menghapus $UNIT_DIR/$u"
		jalan rm -f "$UNIT_DIR/$u"
	fi
done
if command -v systemctl >/dev/null 2>&1; then
	jalan_diam systemctl --user daemon-reload
	jalan_diam systemctl --user reset-failed "${UNITS[@]}"
fi

# 3) Program hasil build.
if [ -d bin ]; then
	echo "Menghapus bin/"
	jalan rm -rf bin
fi

# 4) Data (opsional).
if [ "$HAPUS_DATA" = 1 ] && [ -d data ]; then
	echo "Menghapus data/"
	jalan rm -rf data
fi

echo
if [ "$COBA" = 1 ]; then
	echo "Mode coba: tidak ada yang diubah."
else
	echo "Selesai. Server game sudah dicopot."
	if [ "$HAPUS_DATA" = 1 ]; then
		echo "Cadangan tersimpan di ${BACKUP_DEST:-$HOME/cadangan_game} (cara memulihkan: docs/BACKUP.md)."
	fi
fi
echo "Pasang lagi: make install-user-service && make install-backup-timer"
