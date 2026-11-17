# Format Paket Game (PCK) — v0.84.0

## Isi paket

Paket game adalah berkas `.pck` Godot 4.7 hasil `--export-pack` dari proyek `client/` yang sama dengan APK.
Contoh `education_sd-1.0.0.pck` (207 KB, 10 berkas):

```
games/education_sd/main.tscn.remap, main.gd.remap, main.gdc, game.json, data/course.json
.godot/exported/<hash>/export-<md5-path>-main.scn
project.binary, .godot/uid_cache.bin, .godot/global_script_class_cache.cfg, assets/icon/icon_512.png
```

Baris terakhir selalu diikutkan Godot. Karena paket dimuat dengan `replace_files=false`, berkas yang sudah ada
di APK **tidak pernah tertimpa**; berkas itu diabaikan.

## Mengapa dari proyek yang sama

PCK dari proyek Godot terpisah tidak otomatis cocok: path `res://`, UID, skrip bersama, dan versi mesin bisa
berbeda. Pipeline ini menjamin:

- versi mesin sama (header PCK berisi versi mesin; launcher menolak MAJOR.MINOR berbeda),
- path namespace `res://games/<id>/` unik per game,
- skrip bersama (`res://shared`, `res://core`) TIDAK ikut paket — dipakai dari APK,
- game tidak bisa menimpa berkas aplikasi atau game lain.

## Pembangunan (`scripts/build-game-pack.sh`)

1. Tambah sementara preset ekspor `GamePack` (salinan preset `Patch`) dengan
   `exclude_filter` = semua folder/berkas tingkat atas kecuali `games/`, serta `games/<id lain>/*`;
   `include_filter` = `games/<id>/*.json`. `export_presets.cfg` dipulihkan setelahnya.
2. `godot --headless --path client --export-pack GamePack <id>.pck`.
3. `tools/gamepack/gamepack.py check-pck` — aturan sama dengan launcher.
4. `gamepack.py publish` — salin ke `catalog/<id>/<id>-<versi>.pck`, tulis `manifest.json` (+ ukuran,
   SHA-256, `min_engine_version` dari header PCK), tanda tangan `manifest.sig`, bangun ulang `catalog.json` +
   `catalog.sig`. Versi yang lebih lama dari yang sudah terbit, atau versi sama dengan isi berbeda, ditolak.
   Disimpan paket versi aktif + satu sebelumnya.

## Struktur berkas PCK (yang diperiksa launcher)

Little-endian. Header: `"GDPC"`, `u32 format` (3 atau 4; Godot 4.7.2 menulis 4), `u32 major, minor, patch`,
`u32 flags` (bit 1 = direktori terenkripsi → **ditolak**; bit 2 = offset relatif; bit lain → ditolak),
`u64 file_base`, `u64 dir_offset`. Direktori di `dir_offset`: `u32 jumlah`, lalu per berkas `u32 panjang_path`,
path (padding `\0`), `u64 offset`, `u64 ukuran`, `md5[16]`, `u32 flags` (≠ 0 — terenkripsi atau *removal* —
**ditolak**).

`client/core/pck_reader.gd` dan `tools/gamepack/gamepack.py` membaca bagian ini tanpa memuat paket, lalu
memeriksa:

- versi mesin MAJOR.MINOR = mesin aplikasi,
- setiap path: di `games/<id>/`, atau `.godot/exported/…` / `.godot/imported/…` (dialamatkan hash path), atau
  salah satu berkas mesin di atas; path lain (mis. `scripts/login.gd`) atau namespace game lain → ditolak,
- tidak ada `..`, `\`, `//`, path absolut,
- paket benar-benar berisi `games/<id>/`,
- offset + ukuran tiap berkas di dalam batas berkas.

## Manifest

```json
{
 "id": "education_sd", "name": "…", "description": "…", "category": "Pendidikan",
 "version": "1.0.0", "type": "download",
 "entry_scene": "res://games/education_sd/main.tscn",
 "package": "education_sd-1.0.0.pck", "size": 212560, "sha256": "033b…bf7f",
 "min_launcher_version": "0.84.0", "min_engine_version": "4.7.2",
 "icon_color": "#2f6f8a", "enabled": true, "updated": "2026-11-15T03:43:01Z"
}
```

`catalog.json` = `{"catalog_version": 1, "generated": "…", "games": [manifest, …]}` (game unduhan saja).
Game bawaan ada di `client/config/games.json` (ikut APK, `type: "builtin"`). Sejak v0.85.0 daftar ini kosong:
The Last Dragon (`adventure`) juga game unduhan. Kolom tambahan opsional: `background_music: "platform"` (musik
autoload Sound berbunyi selama game ini aktif).

## Batasan yang diketahui

- Godot 4.7 tidak bisa melepas paket yang sudah dimuat. Update game yang sudah dibuka di sesi yang sama
  baru berlaku setelah aplikasi dibuka ulang (launcher memberi tahu).
- Paket tidak bisa membawa autoload, pengaturan proyek, atau plugin Android.
- Ikon aplikasi (±190 KB) ikut terbawa ekspor Godot walau tidak dipakai.
