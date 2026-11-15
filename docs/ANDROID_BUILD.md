# Build Android — Launcher Multi-Game (v0.84.0)

## Satu APK

`client/` diekspor menjadi satu APK (`com.miftahulkhoiri.gamepetualang`, keystore yang sama dengan APK lama
sehingga bisa menimpa tanpa uninstall). Isi APK sejak v0.84.0:

- adegan utama: `res://launcher/scenes/main_menu.tscn`
- autoload: `Patcher` (tetap pertama), `Api`, `Session`, `Sound`, `GameManager`
- game bawaan: The Last Dragon (`res://scripts`, `res://scenes`, `res://assets`)
- mesin platform `res://core`, mesin pembelajaran `res://shared`, `res://config/*.json` + kunci publik `.pem`
  (masuk lewat `include_filter`, karena `.pem` bukan resource Godot)
- **tidak** berisi `res://games/*` (preset `Android` dan `Patch`: `exclude_filter` = `tests/*, games/*`)

## Cara membangun

CI (`.github/workflows/client.yml`) tetap sama: setiap push menjalankan uji klien↔server; tag `v*`
membangun APK dan melampirkannya ke GitHub Release. Rilis platform ini memakai tag `v0.84.0`.

Lokal (butuh export templates 4.7.2 + Android SDK): `godot --headless --path client --export-release Android out.apk`.

## Wajib APK baru, bukan patch

Perubahan adegan utama, autoload, dan kunci publik ada di `project.godot` / berkas non-skrip, yang tidak
ikut patch. `scripts/build-patch.sh` kini membandingkan juga `run/main_scene` dan daftar autoload, sehingga
patch yang dibuat setelah v0.84.0 **tidak** dikirim ke APK ≤ 0.83.0 (yang tidak punya `GameManager`).

## Setelah memasang APK v0.84.0

1. Aplikasi terbuka di launcher ("Game Platform"). The Last Dragon langsung bisa dimainkan; akun, token,
   dan progres lama tidak berubah (disimpan di `user://settings.cfg` dan server seperti sebelumnya).
2. Pembelajaran SD / SMP tampil bila server terjangkau dan katalog sudah diterbitkan
   (`make game-pack GODOT=...` di Pi). Tekan DOWNLOAD, tunggu "Siap dimainkan".
3. Matikan data/Wi-Fi: launcher, The Last Dragon (mode luring yang ada), dan game yang sudah diunduh tetap
   bisa dibuka.

## Status uji Android

Uji di Pi memakai Godot headless (Linux arm64) dengan salinan proyek tanpa `games/` (meniru isi APK). Uji di
HP sungguhan (pemasangan APK, sentuhan, audio, pemuatan PCK dari penyimpanan Android) **belum dijalankan**
pada rilis ini dan dicatat sebagai langkah berikutnya di [TEST_REPORT.md](TEST_REPORT.md).
