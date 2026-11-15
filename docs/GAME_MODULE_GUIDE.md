# Panduan Menambah Game Baru (v0.84.0)

Game baru ditambahkan sebagai **paket unduhan** tanpa membangun ulang APK, selama hanya memakai fitur yang
sudah ada di launcher (mesin Godot 4.7, skrip `res://core/` dan `res://shared/`).

## 1. Buat folder game

```
client/games/<id>/
├── game.json        identitas game (sumber manifest)
├── main.tscn        entry scene
├── main.gd          skrip utama
└── data/, ...       aset/data milik game ini saja
```

Aturan `id`: huruf kecil/angka/garis bawah, 2–32 karakter, diawali huruf (`^[a-z][a-z0-9_]{1,31}$`), unik.
**Semua** berkas game harus di `res://games/<id>/`. Paket yang berisi berkas di luar namespace itu ditolak
launcher (kecuali berkas mesin yang selalu ikut ekspor; lihat `PCK_PACKAGE_FORMAT.md`).

`game.json`:

```json
{
	"id": "game4",
	"name": "Nama Tampilan",
	"description": "Deskripsi singkat untuk launcher.",
	"category": "Pendidikan",
	"version": "1.0.0",
	"entry_scene": "res://games/game4/main.tscn",
	"min_launcher_version": "0.84.0",
	"icon_color": "#2f6f8a",
	"enabled": true
}
```

`type`, `package`, `size`, `sha256`, `min_engine_version`, dan `updated` diisi otomatis saat paket dibangun.

## 2. Kontrak dengan launcher

- Jangan memakai `class_name` (cache kelas global APK tidak tahu kelas dari paket). Pakai `preload()`.
- Ambil autoload lewat `get_node_or_null("/root/GameManager")`, bukan nama global, supaya skrip juga bisa
  dikompilasi di luar platform.
- Simpan progres dengan `GameManager.save_progress(id, data, schema)` dan muat dengan
  `GameManager.load_progress(id, schema, migrations)`. Data disimpan di `user://user_data/progress/<id>/`
  dan dikirim ke server saat online + sudah masuk. Jangan menulis ke folder game lain.
- Kembali ke launcher dengan `GameManager.exit_to_launcher()`. Opsional: sediakan
  `func platform_before_exit() -> void` (boleh `await`) untuk menyimpan sebelum adegan dilepas.
- Tangani `NOTIFICATION_WM_GO_BACK_REQUEST` (tombol kembali Android) dan `NOTIFICATION_APPLICATION_PAUSED`
  (simpan).
- Musik desa Petualangan dijeda otomatis; game memutar audionya sendiri dan menghentikannya saat keluar.
- Naikkan `version` (semver) setiap terbit. Versi yang sudah terbit dengan isi lain ditolak alat terbit.
- Ubah `schema_version` save dan sediakan migrasi bila bentuk data progres berubah.

Contoh game lengkap yang tidak memakai mesin kuis bersama: `client/games/education_sd/` ("Petualangan Pulau
Ilmu", lihat [SD_PULAU_ILMU.md](SD_PULAU_ILMU.md)) — banyak skrip, data, dan uji sendiri di dalam namespace-nya.

## 3. Game pembelajaran (cara cepat)

Game kuis cukup mewarisi mesin bersama:

```gdscript
extends "res://shared/edu/quiz_app.gd"

func _init() -> void:
	game_id = "game4"
	course_path = "res://games/game4/data/course.json"
```

Isi `course.json`: `title`, `subtitle`, `pass_score`, `questions_per_session`, `subjects[]` → `levels[]` berisi
`questions[]` (`q`, `options`, `answer` = indeks benar, `explain` opsional) atau `generator` matematika
(`arith` / `linear` / `power` / `fraction_compare`). Contoh lengkap: `tools/gamepack/make_courses.py`.

## 4. Bangun, tandatangani, terbitkan

```bash
make game-pack GODOT=~/Claude/godot/Godot_v4.7.2-stable_linux.arm64 GAMES="game4"
```

Paket dibangun dari proyek `client/` yang sama dengan APK, diperiksa (`tools/gamepack/gamepack.py check-pck`),
manifest + katalog ditandatangani dengan kunci penerbit, lalu ditaruh di folder katalog server. Launcher
melihatnya saat "Muat ulang katalog". Uji dulu dengan `make platform-test`.

## 5. Kapan butuh APK baru

Bila game butuh: skrip/aset bersama baru di `res://shared` atau `res://core`, autoload baru, plugin/izin
Android, versi Godot lain, atau pengaturan proyek lain. Naikkan `min_launcher_version` ke versi APK itu.
