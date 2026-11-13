# Pengujian

Ada tiga lapis pengujian. Semuanya otomatis di GitHub Actions setiap push ke `main` dan setiap tag `v*`.

| Lapis | Perintah | Isi |
|-------|----------|-----|
| Tes server (Go) | `make check` | format, `go vet`, 215 tes unit & HTTP (`-race` di CI), cakupan ±82% |
| Uji ujung-ke-ujung | `make client-test GODOT=/path/godot` | klien Godot headless melawan server Go asli: ±870 pemeriksaan di `client/tests/e2e.gd` |
| Uji asap | `make smoke [URL=http://ip:8090]` | server yang sedang berjalan (Pi sungguhan), hanya membaca — aman saat dimainkan |
| Semua | `make test-all GODOT=...` | ketiganya berurutan (pengujian akhir, no. 275) |

Tambahan: `make bench` (tolok ukur), `make cover` (cakupan), CI "Periksa APK" (tanda tangan, versi, izin,
arsitektur, versi Android minimum, ukuran).

Catatan Pi: `go test -race` tidak berjalan di Raspberry Pi 5 (kernel 47-bit VMA); jalankan tanpa `-race`
di Pi, CI menjalankannya dengan `-race`.

## Peta roadmap no. 256–270 ke tes

| No. | Bagian | Tes server (Go) | Uji ujung-ke-ujung (`e2e.gd`) |
|-----|--------|-----------------|-------------------------------|
| 256 | Login | `TestLoginByNameAndEmail`, `TestLoginRejectsSameMessageForUnknownAndWrong`, `TestLoginRateLimit`, `TestLoginSuccessResetsFailures`, `TestRehashOldPasswordOnLogin`, `TestExpiredSessionMessage` | "layar masuk", "akun: email, login, logout", "token salah" |
| 257 | Registrasi | `TestRegisterValidation`, `TestRegisterRejects`, `TestRegisterDoesNotLeakSecrets`, `TestAccountUniquenessAndSessions` | nama/email kembar 409, sandi pendek & email rusak 422, petunjuk isian (v0.60) |
| 258 | Karakter | `TestHeroSelection`, `hero_test.go`, `equipment_test.go`, `progress_test.go`, `train_test.go` | "pahlawan", "v0.57: gaya senjata…", Profil & pratinjau 3D |
| 259 | NPC | `warga_test.go` (reputasi, sapaan) | "desa malam: … warga pulang", jadwal warga, serbuan (warga berlindung) |
| 260 | Monster | `special_test.go`, `hutan_test.go`, `TestBattleEnemyDependsOnMap`, `TestBossBattleOnlyAtBossSpot` | "musuh berkeliaran dan bar nyawa", wilayah & respawn |
| 261 | Pertarungan | `battle_test.go`, `combat_style_test.go` (simulasi keseimbangan), `TestBattleFullFlow`, `TestBattleActionErrors` | "pertarungan", "pertarungan langsung di dunia" |
| 262 | Inventaris | `item_test.go`, `loot_test.go`, `TestInventoryEquipUseRest`, `TestStorageEndpoints` | "tas & perlengkapan" |
| 263 | Toko | `TestShop`, `TestShopPerShop`, `TestConcurrentSellNoDuplicate`, `economy_test.go` | "toko", "energi, makanan, toko per-jenis" |
| 264 | Misi | `quest_test.go`, `TestQuestEndToEnd` | "misi", papan misi Hutan |
| 265 | Database | `store_test.go` (migrasi v1→v4, transaksi, rollback), `sessions_test.go`, `TestBackupRestoreRoundTrip`, `TestQueriesUseIndexes`, `bench_test.go` | — |
| 266 | Koneksi server | `TestHealth`, `TestVersionEndpoint`, `TestOldClientMustUpdate`, `TestPanicRecovered` | "v0.61: server & koneksi" (putus/tersambung, sesi kedaluwarsa); `scripts/smoke-test.sh` |
| 267 | Multiplayer | `TestManyPlayersAtOnce` (12 pemain bersamaan), `TestTradeWhileOthersPlay`, `TestTradeFlow`, `TestTokensAreIsolated`, `TestWorldEventsAndSecret` | — |
| 268 | Keamanan | `security_test.go` (injeksi SQL, token palsu, badan raksasa, IP palsu, panic), `TestSaveOnlyAppliesPosition`, `TestClientIPNotSpoofable` | "token salah" |
| 269 | Performa | `TestServerLatencyUnderLoad` (8 pemain × 25 simpan, p95 < 250 ms), `make bench` | "v0.62: Android dan performa" (profil kualitas, uji ketahanan 8× pindah peta) |
| 270 | Kompatibilitas Android | — | CI "Periksa APK": arm64-v8a, API minimum/target, tanda tangan sama, izin, HTTP |

## Audit keamanan v0.77.0

| Bagian | Tes |
|--------|-----|
| Gerakan & peta | `game/movement_test.go` (batas kecepatan, pintu, gerbang ujian/cerita/rumah, data lama, `TestDoorsMatchClient` = pintu server sama dengan `EXITS` klien, `TestMoveToRespectsWalls`, `TestTilesMatchClient` = petak server sama dengan `maps.gd`), `api/movement_test.go` (teleport, peta terkunci, peti/benda dari jauh, NaN/Inf/ekstrem, jeda jaringan, tersambung lagi) |
| Dagang | `store/trades_test.go` (bertarung: penjual/pembeli/keduanya × buat/terima/batal/tolak; alur normal; kepemilikan & IDOR; rollback; 16 permintaan bersamaan tanpa duplikasi) |
| Versi klien & JSON | `api/hardening_test.go` (`TestClientVersionGate`, `TestDecodeStrictJSON`, `TestTrailingJSONRejectedEndToEnd`) |
| Pembatas & IP | `auth/limiter_test.go` (riwayat terbatas, pulih, banyak identitas, pembersihan, bersamaan, tolok ukur), `TestLoginLimitPerAccountAcrossNameAndEmail`, `TestClientIPTrustedProxies`, `config.TestParseProxies` |
| Batas laju umum & patch | `auth/bucket_test.go` (burst & isi ulang, pemakaian normal tidak pernah kena, kunci terbatas, bersamaan), `TestRateLimitPerIPAndPlayer`, `TestPatchEndpointsInsideServer` |
| Sesi, migrasi, cadangan | `store/hardening_test.go` (sesi sah/kedaluwarsa/dicabut/rusak, gagal last_used, database mati, bersamaan; skema baru/sama/lebih baru/gagal di tengah; kerusakan terdeteksi, cadangan saat ramai, cadangan gagal, pemulihan), `cmd/gameserver.TestCheckDatabaseFailSafe` |

`go test -race` tidak bisa dijalankan di Pi 5 (ThreadSanitizer Go di arm64 butuh ruang alamat 48-bit, kernel Pi
memakai 47-bit); CI (`.github/workflows/ci.yml`, Ubuntu x86-64) menjalankannya di setiap push/PR.

## AI hybrid & adaptive difficulty v0.78.0

| Bagian | Tes |
|--------|-----|
| AI musuh (Fase 1) | `game/ai_test.go`: profil per id, `TestAIUsesNoExtraRandomness` (tiap serangan tetap tepat satu angka acak: deterministik), taktik orc/babi/golem/naga/goblin/serigala/ular/kelelawar, mundur, `TestAIProfilesKeepBalance` (kerusakan rata-rata 0,8-1,25x musuh biasa), JSON pertarungan lama |
| Peran & formasi (Fase 2) | `game/party_test.go`, `api/formation_test.go`: taunt ksatria, heal penyihir, dorong tombak, pemanah vs musuh terbang, 6 formasi, `MaxParty`/`MaxSoldiers` tidak berubah, formasi tak dikenal ditolak |
| Bos (Fase 3) | `game/boss_test.go`: fase 2/3 sekali, jurus khusus, serangan area, bos tidak mundur, Malzareth tetap memakai mekaniknya |
| Klien (Fase 4) | `make client-test` (ancang-ancang, event baru tidak membuat skrip galat); tampilan di HP Android: **belum diuji** |
| Adaptive (Fase 5) | `game/adapt_test.go`: pemain baru/lama netral, butuh 5 pertarungan, sangat kuat (berhenti di 1150), sangat lemah (berhenti di 900), stabil, bergantian, kabur bukan celah, bos/raid/cerita tidak ikut, hadiah tetap, solo = party penuh, validasi data |
| Tolok ukur | `BenchmarkEnemyAttackAI`, `BenchmarkAdapt` (`internal/game/ai_bench_test.go`) |

## Hasil acuan di Raspberry Pi 5 (v0.63.0)

| Ukuran | Hasil |
|--------|-------|
| `GET /v1/players/me` | ±0,21 ms per permintaan |
| Simpan posisi | ±0,43 ms |
| Satu ronde pertarungan | ±0,65 ms |
| 8 pemain × 25 simpan bersamaan | p50 ±2,5 ms, p95 ±5 ms |
| Uji ketahanan klien (8× pindah peta) | node, objek, node yatim stabil |

## Menambah tes

- Aturan game baru → tes di `internal/game/*_test.go`; endpoint baru → `internal/api/*_test.go`
  (pakai `newTestServer`, `register`, `do`; dari goroutine pakai `call` di `multiplayer_test.go`).
- Tampilan/klien → bagian baru di `client/tests/e2e.gd` dengan `_check(kondisi, "keterangan")`.
- Jam dunia dikunci di tes (server `GAME_WORLD_START`, klien `Atmosphere.clock_locked`) supaya hasil tidak
  bergantung pada jam saat tes dijalankan.
