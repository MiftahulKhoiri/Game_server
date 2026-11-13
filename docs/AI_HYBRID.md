# Laporan AI Hybrid • Balanced Graphics • Adaptive Difficulty (v0.78.0)

Dikerjakan langsung di `main` atas permintaan pemilik (bukan cabang terpisah). Commit: `6e37100` (Fase 1), `37ccaad`
(Fase 2), `f753785` (Fase 3), `be34b61` (Fase 4), `b1ca873` (Fase 5), `c3020f4` (rilis v0.78.0, tag `v0.78.0`).

## A. Ringkasan

- **AI musuh di server** (`internal/game/ai.go`): 9 profil perilaku + FSM (`approach`, `windup`, `recover`,
  `retreat`) dan taktik (`heavy`, `quick`, `ambush`, `area`, `ranged`, `special`, `retreat`). Tanpa angka acak tambahan:
  urutan acak pertarungan lama sama persis, hasil tetap ditentukan server.
- **Peran pendamping & formasi prajurit** (`party.go`): ksatria tank, pendekar_kapak heavy, pemanah ranged,
  pendekar_tombak quick, penyihir magic/heal; 6 formasi lewat `POST /v1/soldiers/formation`.
- **Pola bos** (`boss.go`): fase per sepertiga HP, jurus khusus lebih sering di fase 3, serangan area di fase 2; Malzareth
  tetap memakai mekanik ceritanya; bos tidak pernah mundur.
- **Klien**: ancang-ancang serangan besar (lingkaran merah + tulisan, jendela peringatan 1,15 dtk), efek per taktik,
  fase bos, musuh mundur, heal penyihir, panah/sihir pendamping. Ringan, memakai efek yang sudah ada.
- **Adaptive difficulty** (`adapt.go`): faktor 0,90–1,15 hanya untuk HP & serangan musuh biasa; hadiah tidak berubah.
- **Balanced graphics** = profil **Normal** yang sudah ada (nilainya persis sama dengan spesifikasi); hanya didokumentasikan.
- Semua kunci JSON baru opsional; `MaxParty` (3) dan `MaxSoldiers` (50) tidak berubah; id pahlawan/musuh/benda/peta tetap.

## B. Inventaris

| Bagian | File |
|--------|------|
| Server baru | `internal/game/ai.go`, `party.go`, `boss.go`, `adapt.go` |
| Server diubah | `internal/game/battle.go` (settle, strike, allyStrike, area, adapt), `player.go` (`formation`, `adapt`, validasi), `internal/api/api.go` (rute formasi, `formations`/`roles` di progress) |
| Tes baru | `ai_test.go`, `party_test.go`, `boss_test.go`, `adapt_test.go`, `ai_bench_test.go`, `api/formation_test.go` |
| Tes disesuaikan | `battle_test.go` (babi kini serangan berat), `ally_test.go` (pakai pendekar_kapak karena ksatria memancing serangan) |
| Klien | `world_fight.gd`, `battle.gd`, `companions.gd` (posisi formasi), `atribut.gd` (pilihan formasi), `api.gd`, `session.gd`, `perf.gd` (catatan Balanced) |
| Alat | `client/tests/audit_glb.gd` (daftar tulang & klip animasi GLB) |
| Dokumen | `docs/API.md`, `docs/TESTING.md`, dokumen ini |

## C. Audit per file (model GLB)

Semua model punya rig; klip yang tersedia hanya `idle/walk` atau `attack/die/hurt/idle/walk`. **Tidak ada** klip
`run/heavy/block/dodge/stagger/victory/skill`, jadi gerakan taktik memakai cadangan prosedural `model_rig.gd`
(terjang, getar, lingkaran) — tidak ada model yang diganti.

| Model | Tulang | Klip |
|-------|--------|------|
| aldragor | 33 | attack, die, hurt, idle, walk |
| anak_ayam | 13 | idle, walk |
| babi_hutan, belalang_raksasa, serigala_hutan | 34–35 | idle, walk |
| ular_sawah | 18 | idle, walk |
| goblin, raja_goblin, golem_lava | 43 | lengkap (5 klip) |
| goblin_penjaga, golem_kerikil | 41 | lengkap |
| kelelawar_hutan | 28 | lengkap |
| tikus_sawah | 39 | lengkap |
| ogre_batu | 55 | lengkap |
| ksatria, pemanah, pendekar_kapak, pendekar_tombak, petani, nenek_penjual, warga_*, anak_desa | 41 | lengkap |

Saran (opsional, butuh aset baru): klip `attack` untuk babi/belalang/serigala/ular supaya serangan berat/sergapan tidak
hanya prosedural.

## D. Spesifikasi

**Profil AI** (`aiProfiles`): goblin (berkelompok, mundur di HP 25%, serangan cepat 85%), orc/ogre/kepala & raja
goblin/prajurit kutukan (berat tiap 3 serangan 160%, pulih 0,7 dtk), serigala (berkelompok, sergap 140%), ular (sergap
150%), babi (berat tiap 2 serangan 150%), kelelawar & belalang (cepat, lincah: jurus berat pemain hanya 60%), golem (berat
170% + area), keluarga naga/aldragor/ogre_gunung (berat 150% jarak jauh + area), Malzareth (mekanik cerita).

**Formasi**: Barisan, Dinding Perisai, Formasi Tombak, Formasi Pemanah, Lingkaran, Serbuan (tabel di `docs/API.md`).

**Adaptive**: netral 1000 permil, batas 900..1150, naik +10 / turun −20 / kembali ±5, jendela 8 hasil, mulai setelah 5,
menang mudah = HP ≥ 70%. Kabur tidak menurunkan kesulitan. Semua konstanta di awal `adapt.go`.

**Balanced (Normal)**: 60 FPS, skala 3D 0,75, kamera 90, bangunan 42, LOD warga 18 / musuh 16, efek 100%, bayangan 16,
5 lampu; bawaan pemain baru.

## E. Kompatibilitas

- Kunci baru semuanya `omitempty`: `formation`, `adapt` (state); `ai_profile`, `ai_state`, `enemy_intent`,
  `enemy_guard_ms`, `adapt` (pertarungan); `tactic` (event). Klien lama mengabaikannya; tes JSON pertarungan & state lama lulus.
- `min_client` tetap 0.18.0; `latest_client` = 0.78.0.
- Pertarungan yang tersimpan sebelum pembaruan dilanjutkan normal (kunci baru kosong = perilaku netral).
- Database tidak dimigrasi (state disimpan sebagai JSON); cadangan dibuat sebelum restart:
  `data/backup/game-20261113-122145.db` (integrity_check ok).

## F. Rencana fase

| Fase | Isi | Status |
|------|-----|--------|
| 1 | AI musuh server (profil, FSM, taktik, target) | selesai |
| 2 | Peran pendamping, formasi prajurit | selesai |
| 3 | Pola & fase bos | selesai |
| 4 | Animasi/VFX klien mengikuti event server | selesai (uji di HP: belum) |
| 5 | Adaptive difficulty | selesai |
| 6 | Balanced graphics | selesai (profil Normal, didokumentasikan) |
| 7 | Tes, tolok ukur, dokumen, rilis | selesai |

## G. Hasil pengujian

| Tes | Hasil |
|-----|-------|
| `gofmt -l`, `go vet ./...` | bersih |
| `go test ./...` | semua paket ok |
| Tes adaptive (13 tes) | lulus: pemain baru, pemain lama, butuh riwayat, sangat kuat, sangat lemah, stabil, bergantian, kabur bukan celah, bos/raid/cerita, hadiah tetap, solo = party penuh, validasi, tercatat dari pertarungan |
| `make client-test` (Godot headless) | 1063 ok, 0 GAGAL, tanpa galat skrip |
| `make smoke` setelah restart | SEMUA LOLOS; `/v1/version` = 0.78.0 (lokal dan HTTPS 8443) |
| `BenchmarkEnemyAttackAI` (Pi 5) | ±2,2 µs, 4 alokasi per serangan musuh (diukur saat tes klien berjalan) |
| `BenchmarkAdapt` | ±0,45 µs per pertarungan |
| `BenchmarkBattleRound` (API) | ±0,68 ms (acuan v0.63.0: ±0,65 ms) |
| `go test -race` | BELUM DILAKUKAN di Pi (47-bit VMA); dijalankan CI |
| Main di HP Android (FPS, tampilan efek, rasa kesulitan) | **BELUM DILAKUKAN** |
| APK rilis v0.78.0 dari CI | menunggu hasil GitHub Actions dari tag `v0.78.0` |

## H. Status perubahan

Semua sudah di `main` dan ter-push, tag `v0.78.0` ter-push, server Pi sudah direstart dengan v0.78.0. Yang perlu dicek
pemilik: APK dari CI, lalu main langsung di HP (ancang-ancang serangan berat, formasi di menu Atribut, heal penyihir,
fase bos, dan apakah kesulitan terasa pas).
