# Alat yang sudah terpasang di Raspberry Pi 5

Catatan supaya alat ini bisa dipakai lagi tanpa pasang ulang. Diperbarui 2026-11-06.
Alat bantu buatan Claude (sementara) ada di `~/Claude`; proyek asli di `~/Game_server`.
Kode Go/Godot proyek sendiri ada di repo; folder `~/Claude` tidak ikut repo.

## Ringkasan

| Alat | Versi | Lokasi | Fungsi |
|---|---|---|---|
| TripoSR | model `stabilityai/TripoSR` (MIT) | `~/Claude/triposr/TripoSR`, venv `~/Claude/triposr/env` | Gambar bertransparan -> model 3D `.glb` (CPU, +-1,5 menit/model) |
| Python (venv TripoSR) | 3.13.5 | `~/Claude/triposr/env` | torch 2.15.0+cpu, transformers 4.49.0 (harus 4.x), trimesh 5.2.0, rembg 2.0.86, onnxruntime 1.31.1 |
| Blender | 4.3.2 | `~/Claude/blender_root` (tanpa pasang ke sistem) | Rangka + animasi untuk `.glb` (`tools/blender/rig.py`) |
| Godot | 4.7.2 stable arm64 | `~/Claude/tools/godot-4.7.2/` (salinan lain `~/Claude/godot/`) | Uji klien, tangkapan layar, impor `.glb` |
| Xvfb | paket Debian (diekstrak) | `~/Claude/tools/xvfb` | Layar virtual supaya Godot bisa render tanpa monitor |
| Go | 1.24.4 | sistem | Membangun server `bin/gameserver` |
| Java (OpenJDK) | 21.0.13 | sistem | Pendukung Android; APK dibangun lewat CI GitHub, bukan di Pi |
| ffmpeg, git | sistem | `/usr/bin` | Media dan versi kode |
| llama.cpp | - | `~/llama.cpp` | Server model bahasa lokal |
| x120x | repo `ups_x120x` | `~/ups_x120x` | Pemantau baterai UPS (`python3 -m x120x status`) |

Model yang tersimpan di cache Hugging Face (`~/.cache/huggingface`): `stabilityai/TripoSR`,
`facebook/dino-vitb16`, `openai/clip-vit-base-patch32`.

## Cara pakai

### 1. Gambar -> 3D (TripoSR)
```bash
cd ~/Claude/triposr
env/bin/python gen.py gambar.png out/nama 192 [putar_Y_derajat] [gamma]
```
- Gambar harus PNG bertransparan. Kalau masih berlatar: `env/bin/python cut.py in.png keluar.png [potong_bawah_px] [isnet]`.
- `192` = resolusi mesh (256 lebih detail tapi lebih lambat). Hewan yang menghadap kanan perlu putar `-90`.
- Gamma bawaan 2.2; turunkan ke 1.5 kalau hasil terlalu gelap.
- Detail lengkap: `tools/triposr/README.md`.
- Banyak gambar sekaligus: contoh `~/Claude/triposr/batch_pelengkap.sh` (berhenti sendiri bila baterai <= 30% dan listrik terputus).

### 2. Rangka + animasi (Blender)
```bash
~/Claude/blender.sh -b --factory-startup -P ~/Game_server/tools/blender/rig.py -- masuk.glb keluar.glb biped
```
Jenis: `biped | quad | bat | snake`. Klip: `idle-loop`, `walk-loop`, `attack`, `hurt`, `die`.
Hanya untuk makhluk/karakter. Pohon, batu, dan tanaman tidak perlu dirig.

### 3. Uji klien / tangkapan layar (Godot + Xvfb)
```bash
~/Claude/shot.sh NAMA SHOT_MAP=desa_awal SHOT_X=5.5 SHOT_Z=8.5 SHOT_YAW=20
GODOT=~/Claude/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.arm64 make client-test   # di ~/Game_server
```

### 4. Cek baterai UPS
```bash
cd ~/ups_x120x/src && python3 -m x120x status
```
Kabari user kalau baterai tinggal 30% supaya Pi dicolok ke listrik.

### 5. Unduh gambar bebas lisensi
`~/Claude/unduh_pelengkap.py` mengunduh dari Poly Haven (CC0) ke `~/Gambar_game/Pelengkap/`.
Sumber dan lisensi dicatat di `~/Gambar_game/Pelengkap/SUMBER.md`.

### 6. Kecilkan model untuk dekorasi (Blender)
Hasil TripoSR 15-90 ribu segitiga, terlalu berat untuk ratusan pohon di HP. Kecilkan dulu:
```bash
~/Claude/blender.sh -b --factory-startup -P ~/Game_server/tools/blender/ringankan.py -- masuk.glb keluar.glb [segitiga] [tinggi_m] [maks_lebar_m] [pipih]
```
Contoh pohon: `... 1500 2.0 1.6 pipih` (tinggi 2 m, lebar maks 1,6 m, hanya lebar yang dipipihkan).
Alas model diletakkan di y=0 dan dipusatkan. Warna per titik tetap. Parameter per model ada di
`~/Claude/triposr/ringkas_pelengkap.sh`. Mesh yang terdiri dari banyak serpihan terpisah (mis. lumut)
tidak bisa dikecilkan sampai target.

> Catatan 2026-11-06: model TripoSR untuk pohon/batu/tanaman sudah diganti aset KayKit (lihat bagian "Aset CC0" di bawah); folder `dekor/` tidak dipakai lagi.
### 7. Memasukkan model dekorasi ke game
- Taruh `.glb` ringan di `client/assets/models/dekor/`, lalu impor: `godot --headless --path client --import`.
- `client/scripts/world_build.gd` memakai `TREE_MODELS` (petak `#`) dan `ROCK_MODELS` (petak `R`).
  Bila berkas tidak ada, otomatis kembali ke bentuk dasar lama.
- Cek tanpa layar: `godot --headless --path client -s ~/Claude/gdtest/dekor_check.gd`.

## Status gambar pelengkap (2026-11-06)
- Dikonversi TripoSR: 8 pohon, 6 batu, 7 tanaman (21 model) di `~/Claude/triposr/out/pelengkap/`.
- Versi ringan: `~/Claude/triposr/out/dekor/`; 20 file disalin ke `client/assets/models/dekor/` (lumut `tanaman_moss_01` tidak dipakai: 15 ribu segitiga).
- Terpasang di peta: pohon (5 model) dan batu besar (5 model). Tanaman, tunggul, batang mati, dan tebing belum ditempatkan di peta.
- Belum ada: sumur 3D (Poly Haven tidak punya; sumur di peta masih bentuk dasar).

## Alat bantu kecil di `~/Claude/tools`
- `pilah.py`, `clip_label.py`, `clip_label2.py`, `ascii.py`: memilah dan melabeli isi gambar di `~/Gambar_game` (CLIP, ONNX).
- `dl.py`: unduh berkas besar dengan banyak sambungan (`dl.py URL TUJUAN [sambungan]`).
- `pantau.sh`: ringkasan suhu, RAM, baterai UPS.
- `rig_all.sh`, `rig_test.py`: rig massal dan uji kelayakan rig.

## Catatan penting
- Pasang ulang TripoSR: lihat bagian "Pasang (sekali)" di `tools/triposr/README.md`. Unduhan model +-1,7 GB.
- Hasil TripoSR tanpa rangka dan sisi belakang ditebak model. Gambar berwatermark menghasilkan model berwatermark.
- Bahan CC0 (Poly Haven) bebas dipakai di repo publik. Foto dari Wikimedia selain CC0/domain publik butuh atribusi.

## Aset CC0 siap pakai (KayKit)

Diunduh dari GitHub ke `~/Claude/aset_cc0/` (lisensi CC0, Kay Lousberg; salinan lisensi ada di
`client/assets/models/`):
- `KayKit-Character-Pack-Adventures-1.0`: karakter berrangka + 76 animasi. Ksatria pemain dibuat
  dari `Knight.glb` lewat `tools/blender/kaykit_karakter.py` (membuang perlengkapan cadangan,
  menyisakan klip `idle-loop`, `walk-loop`, `attack`, `hurt`, `die`).
- `KayKit-Medieval-Hexagon-Pack-1.0`: pohon, hutan kecil, gunung, batu, dan tunggul di
  `client/assets/models/alam/` (satu palet warna `hexagons_medieval.png`).

- NPC Nenek Penjual (dari `Mage.glb`) dan Petani (dari `Rogue.glb`) dibuat lewat
  `tools/blender/kaykit_npc.py`: perlengkapan dibuang, warna atlas diubah per rona (jubah mawar,
  rambut putih / tunik cokelat), topi jerami petani ditambah sebagai geometri kepala. Model
  TripoSR lama disimpan di `~/Claude/npc/*_lama.glb`.

Model pohon/batu/tanaman hasil TripoSR yang lama dipindah ke `~/Claude/backup/dekor_triposr/`
(tidak dipakai lagi); alat `tools/blender/ringankan.py` tetap ada untuk model gambar-ke-3D lain.

## Pahlawan KayKit (tools/blender/kaykit_pahlawan.py)

Menyiapkan Pendekar Kapak (Barbarian + kapak besar), Pemanah (Rogue + busur silang) dan Pendekar
Tombak (Knight tanpa helm + tombak buatan sendiri; KayKit tidak punya tombak) menjadi GLB ringan
dengan lima klip (idle-loop, walk-loop, attack, hurt, die). Sumber CC0:
https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
Contoh perintah ada di docstring skripnya.

## Musuh seragam CC0 (tools/blender/siapkan_musuh.py)

Semua 12 musuh memakai model low-poly CC0 berrangka (v0.19.0). Skrip ini mengubah satu sumber
(GLB/glTF/FBX) menjadi GLB ringan: membuang mesh sisa, memberi nama ulang klip menjadi `idle-loop`,
`walk-loop`, `attack`, `hurt`, `die` (opsi lewat JSON, `@berkas.json`), memasang senjata, memutar
arah hadap (`rotz`, model menghadap -Y Blender) dan memperkecil tekstur (`max_tex`).
- Kerangka (KayKit Skeletons, CC0): Minion, Warrior, Rogue ->  kelelawar_gua, golem_kerikil, goblin_penjaga.
  https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0
- Monster (Quaternius, CC0; dari https://github.com/511action/descent-3d-assets): Orc -> goblin,
  Demon -> golem_lava, BlueDemon -> raja_goblin, CreepCreature -> ogre_batu.
- Hewan (Quaternius, CC0, OpenGameArt): Chick -> tikus_sawah, Cat -> belalang_raksasa, Red Fox ->
  ular_sawah, Pig -> babi_hutan, Wolf -> serigala_hutan. Hewan hanya punya klip idle dan jalan;
  serang/terkena/mati digerakkan `model_rig.gd` (badan maju, terhuyung, roboh).
Id musuh tidak berubah; yang berubah hanya nama tampilan (mis. `tikus_sawah` = "Ayam Liar").
