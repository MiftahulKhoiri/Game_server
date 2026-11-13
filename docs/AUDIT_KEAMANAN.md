# Laporan Audit Keamanan & Hardening Game Server

Dirilis di v0.77.0 (PR #5 dan #6, digabung ke `main` 13 Nov 2026).

## A. Ringkasan

| | |
|---|---|
| File dibaca langsung | ±32 (semua handler API, store, auth, config, version, main, aturan gerak/peti/rumah/ujian/cerita di `game`, `maps.gd`/`world3d.gd`/`session.gd`/`api.gd` klien, skrip cadangan/pulih, CI) + 66 file Go disisir dengan pencarian |
| File diubah | 26 diubah + 7 baru (33 file, +2.311 / −215 baris) |
| Masalah ditemukan | 21 (1 Critical, 4 High, 10 Medium, 6 Low) |
| Masalah diperbaiki | 21 (no. 20-21 menyusul di cabang `rate-limit`) |
| Belum diperbaiki | 4 batasan desain yang tersisa (lihat bagian G) |

### Daftar temuan

| # | Tingkat | Temuan (bukti di kode) | Status |
|---|---------|------------------------|--------|
| 1 | Critical | `worldAction` menerapkan `worldPose.apply` dari permintaan **tanpa** memeriksa posisi sebelumnya, `CanEnter`, atau gerbang. Peti/benda diperiksa dari koordinat kiriman → buka peti/hancurkan benda dari mana saja, bahkan masuk `rumah_pemain` orang lain lewat `/v1/world/chest` | Diperbaiki |
| 2 | High | `saveMe` menerima lompatan ke petak mana pun di peta yang dikenal, termasuk peta yang gerbangnya masih terkunci (Gua Goblin, Benteng Orc, Istana, Ruang Takhta); `watchMovement` hanya mencatat | Diperbaiki |
| 3 | High | `CreateTrade`/`finishTrade` hanya memeriksa pertarungan SATU pemain (`inBattle(fromID)` / `inBattle(playerID)`) | Diperbaiki |
| 4 | High | `inBattle` menganggap galat database = "tidak bertarung" (gagal terbuka) | Diperbaiki |
| 5 | High | Posisi ekstrem (`fx` 1e300) di `worldPose.apply` diubah ke `int` tanpa batas (hasil tidak terdefinisi) | Diperbaiki |
| 6 | Medium | `clientGate`: `version.Compare` error → permintaan diteruskan | Diperbaiki |
| 7 | Medium | `decode` hanya sekali `Decode`: objek kedua / karakter sisa diterima | Diperbaiki |
| 8 | Medium | Limiter: saat >10.000 kunci, SETIAP kegagalan memindai seluruh map; riwayat per kunci tak terbatas; kunci bisa string 64 KiB | Diperbaiki |
| 9 | Medium | Login lewat nama vs email akun yang sama = dua kunci pembatas terpisah (jatah tebakan ganda, + variasi besar/kecil sudah ditangani `ToLower`) | Diperbaiki |
| 10 | Medium | Header IP dipercaya implisit dari loopback; `X-Forwarded-For` paling kiri (bisa diisi sendiri lewat proxy yang menambahkan) | Diperbaiki (`GAME_TRUSTED_PROXIES`, ambil paling kanan yang tidak tepercaya) |
| 11 | Medium | `migrate`: `user_version` lebih tinggi → `return nil` (server tetap jalan) | Diperbaiki |
| 12 | Medium | Langkah migrasi dan kenaikan `user_version` tidak dalam satu transaksi | Diperbaiki |
| 13 | Medium | `QuickCheck` saat menyala hanya dicatat, server tetap menulis | Diperbaiki (fail-safe) |
| 14 | Medium | `Backup` langsung `VACUUM INTO` nama akhir: gagal di tengah = berkas setengah jadi yang dianggap cadangan terbaru; tidak diperiksa | Diperbaiki |
| 15 | Low | `AuthSession`: galat database apa pun → `ErrNotFound` (401, bukan 500); galat `last_used` dan hapus sesi diabaikan; cap waktu rusak dianggap sesi baru | Diperbaiki |
| 16 | Low | `restore-db.sh` menyalin `game.db` tanpa `-wal` (data transaksi terakhir bisa hilang dari salinan "sebelum-pulih"), salinan tidak atomik | Diperbaiki |
| 17 | Low | Goroutine cadangan bisa masih menulis saat `st.Close()` ketika shutdown | Diperbaiki |
| 18 | Low | `MaxHeaderBytes` bawaan 1 MB | Diperbaiki (32 KiB) |
| 19 | Low | Membuat tawaran menaikkan versi pembeli (409 palsu di klien pembeli) | Diperbaiki |
| 20 | Medium | Tidak ada pembatas laju umum per IP/pemain untuk endpoint yang sudah login (spam → semua permintaan antre di satu koneksi SQLite) | Diperbaiki (ember token per IP 60/d burst 120, per pemain 20/d burst 60) |
| 21 | Low | Endpoint patch (`WithPatches`) berada di luar middleware log/recover | Diperbaiki (`api.PatchDir`) |

Dicek dan **tidak** ditemukan masalah: injeksi SQL (semua kueri berparameter; nama tabel di `Counts` dari daftar tetap),
IDOR (semua handler memakai id dari token; dagang hanya pemilik/penerima — kini ada tesnya), overflow emas/jumlah
(`addGold`, `BankDeposit/Withdraw`, batas qty di toko/tempa/peti simpan sudah aman), token disimpan sebagai SHA-256,
token tidak tercatat di log, panic ditangkap `recoverPanic`, CORS tidak diaktifkan (bawaan aman).

## B. Daftar Perbaikan

| File | Fungsi | Sebelumnya | Solusi | Dampak ke game |
|------|--------|-----------|--------|----------------|
| `internal/game/movement.go` (baru) | `Doors`, `DoorOpen`, `TravelCost`, `MoveTo` | — | Posisi baru diterima bila jarak lurus (lewat pintu antarpeta, sama dengan `EXITS` klien) ≤ 9 petak/detik × waktu sejak gerakan terakhir + 8 petak; pintu terkunci (ujian, cerita langkah 9/10, rumah) tidak bisa dilewati; data lama yang sudah pernah mengunjungi peta tidak dikunci | Pemain jujur tidak terasa (kecepatan tercepat klien ±4,5 petak/detik). Teleport ditolak 422 |
| `internal/game/player.go` | `State.PoseMs`, `Validate` | — | Cap waktu gerakan terakhir (hanya server); cap waktu negatif ditolak | Kolom JSON baru opsional `pose_ms` |
| `internal/store/store.go` | `SavePosition`, `MovePlayer` | Langsung menulis posisi | Lewat `MoveTo`; data lama tanpa `pose_ms` memakai `updated_at` | Tanda tangan `SavePosition` + parameter `now` |
| `internal/api/world.go` | `worldAction`, `pose`, `finiteCoord`, `logMoveReject` | `apply` menimpa posisi | Posisi kiriman divalidasi dulu (angka terhingga & < 1e6, `NormalizePose`, `MovePlayer`), baru jarak peti/benda dihitung dari posisi server | Peti/benda dari jauh 422; log `posisi ditolak` (id pemain, IP, peta, petak, alasan — tanpa token) |
| `internal/api/api.go` | `saveMe` | Hanya log | Tolak 422 + log | Sama |
| `internal/api/account_ext.go` | `watchMovement` (dihapus) | Log saja | Digantikan `MoveTo` | — |
| `internal/store/trades.go` | `checkNotInBattle`, `CreateTrade`, `finishTrade`, `pairUpdate` | Satu pemain diperiksa; galat = lolos | Kedua pemain (buat & terima); batal/tolak memeriksa penjual (satu-satunya yang berubah); galat database menggagalkan transaksi; pemain yang tidak berubah tidak ditulis | Dagang saat salah satu bertarung → 409 |
| `internal/api/api.go` | `clientGate` | Galat versi diabaikan | Kosong = lolos (klien lama); rusak/>32 karakter = 400; di bawah minimum = 426 | Klien resmi mengirim `0.76.0` → tidak terdampak |
| `internal/api/api.go` | `decode` | Satu `Decode` | Wajib EOF setelah objek pertama; 413 untuk badan > 64 KiB; pesan galat konsisten | — |
| `internal/auth/limiter.go` | `Limiter` | Lihat temuan 8 | Riwayat ≤ max per kunci, pembersihan paling sering sekali per ¼ jendela, maks 20.000 kunci (buang 10% tertua bila penuh); tolok ukur 4,3 µs/gagal saat penuh | — |
| `internal/api/api.go` | `login`, `clientIP`, `TrustedProxies` | Lihat temuan 9-10 | Isian kepanjangan ditolak sebelum menjadi kunci; kunci per akun `id:<id>`; proxy tepercaya dikonfigurasi | Perilaku Cloudflare/proxy lokal tetap sama (bawaan loopback) |
| `internal/config/config.go`, `cmd/gameserver/main.go` | `ParseProxies`, `checkDatabase`, `run` | — | `GAME_TRUSTED_PROXIES`, `GAME_DB_CHECK`; menunggu goroutine cadangan; `MaxHeaderBytes` | Server tidak menyala bila database rusak |
| `internal/store/store.go` | `migrate`, `migrateUp`, `inTx` | Lihat temuan 11-12 | `ErrSchemaTooNew`; tiap langkah + `user_version` dalam satu transaksi | — |
| `internal/store/sessions.go` | `AuthSession`, `Backup`, `VerifyBackup` | Lihat temuan 14-15 | `ErrSessionTouch` (sesi tetap sah, dicatat di log), galat DB → 500, cap waktu rusak = kedaluwarsa, pembaruan `last_used` bersyarat; cadangan `.tmp` → periksa → fsync → rename, cadangan lama dihapus setelah berhasil | — |
| `scripts/backup-db.sh`, `scripts/restore-db.sh` | — | Lihat temuan 16 | `.tmp` + `integrity_check` + `os.replace`; pulih menyimpan `-wal/-shm` dan mengganti atomik | — |
| `client/tests/e2e.gd`, `client/scripts/maps.gd` | uji & komentar | e2e memakai teleport | e2e menunggu waktu gerak yang sah; uji singgasana kini memeriksa lompatan ditolak; komentar `EXITS` harus sama dengan `game.Doors` | Kode game klien tidak berubah |

## C. Pengujian

| Perintah | Hasil aktual |
|----------|--------------|
| `gofmt -l cmd internal` | kosong (rapi) |
| `go vet ./...` | lolos |
| `go build ./...` | lolos |
| `go test -count=1 ./...` | 7 paket ok; 305 tes/subtes PASS, 0 FAIL |
| `make check` | lolos |
| `make client-test` (Godot 4 headless ↔ server asli) | EXIT 0: 1.061 pemeriksaan ok, 0 GAGAL (termasuk berjalan sungguhan lewat gerbang desa ke Perbatasan). Pembanding `main`: 1.061 ok + 1 GAGAL lama yang tidak stabil ("tanpa sesi tersimpan tidak ada tombol Lanjutkan") |
| Server baru dengan **salinan** database Pi | `quick_check` sehat, skema v4 tetap, 2 pemain utuh, `/healthz` 200, header versi rusak 400, shutdown bersih |
| `go test -race ./...` | **Tidak bisa dijalankan di Pi 5**: ThreadSanitizer Go arm64 butuh ruang alamat 48-bit, kernel Pi 47-bit (`FATAL: ThreadSanitizer: unsupported VMA range`). CI GitHub (`ci.yml`, Ubuntu) sudah menjalankan `go test -race` di setiap push/PR |

Tes baru (semua lolos): `game/movement_test.go`, `api/movement_test.go`, `api/hardening_test.go`, `auth/limiter_test.go`,
`store/trades_test.go`, `store/hardening_test.go`, `config.TestParseProxies`, `cmd/gameserver.TestCheckDatabaseFailSafe`.
Tes lama yang dulu memakai teleport (8 tes) diubah agar menaruh pemain lewat store (penyiapan tes) atau lewat pintu.

## D. Status Keamanan

| Bagian | Status |
|--------|--------|
| Authentication | Baik: PBKDF2, pembatas per isian/akun/IP, galat DB tidak disamarkan |
| Authorization | Baik: semua data dari id token; IDOR dagang diuji |
| Player movement | Dikendalikan server (batas kecepatan + pintu); jarak lurus mengabaikan tembok (G-2) |
| Map access | Gerbang ujian, cerita, rumah ditegakkan server |
| Loot | Jarak dari posisi server yang sah + jeda 120 ms + masa tumbuh |
| Chest | Sama seperti loot |
| Battle | Sudah server-authoritative sebelumnya (tidak diubah) |
| Trade | Kedua pemain diperiksa dalam satu transaksi; tanpa duplikasi (16 permintaan bersamaan) |
| Inventory | `ValidEconomy` di setiap simpan (sudah ada) |
| Session | Kedaluwarsa, cabut, gagal aman |
| Database | Migrasi atomik, skema lebih baru ditolak, rusak = tidak menyala |
| Backup | Atomik dan diperiksa; restore aman |
| API validation | JSON ketat, versi klien ketat, angka ekstrem ditolak |
| Rate limiting | Login/daftar/ganti sandi + batas laju umum per IP dan per pemain |

## E. Kompatibilitas

- **Klien Godot lama**: kompatibel. Bentuk API tidak berubah; kode baru 400/413/422 hanya untuk masukan yang tidak
  sah. Daftar pintu server diuji sama persis dengan `EXITS` klien (`TestDoorsMatchClient`). Bila suatu simpan posisi
  ditolak, klien mencoba lagi berkala; pemain jujur tidak semestinya kena karena batasnya dua kali kecepatan
  tercepat klien + 8 petak.
- **Database lama**: kompatibel, **tidak perlu migrasi** (skema tetap v4). `state.pose_ms` kolom JSON opsional.
- **Konfigurasi**: env baru opsional `GAME_TRUSTED_PROXIES` (bawaan sama dengan perilaku lama) dan `GAME_DB_CHECK`.
  Perubahan perilaku: server **tidak menyala** bila `quick_check` menemukan kerusakan.
- **Pemeliharaan**: menambah/memindah pintu di `maps.gd` wajib diikuti `game.Doors` (tes akan gagal bila lupa).

## F. File yang Diubah

Kode: `internal/game/{movement.go*, player.go}`, `internal/store/{store.go, trades.go, sessions.go}`,
`internal/api/{api.go, world.go, account_ext.go}`, `internal/auth/limiter.go`, `internal/config/config.go`,
`cmd/gameserver/main.go`, `scripts/{backup-db.sh, restore-db.sh}`, `client/scripts/maps.gd` (komentar).
Tes: `*_test.go` baru (7) dan tes lama yang dulu teleport (`api_test`, `account_test`, `economy_test`, `world_test`,
`store_test`, `config_test`, `main_test`), `client/tests/e2e.gd`.
Dokumen: `docs/{API, ARCHITECTURE, BACKUP, TESTING, VERSIONING}.md`, laporan ini. (* = baru)

## G. Risiko yang Tersisa

1. **Spam/DoS (Low, sisa)**: batas laju umum sudah ada, tetapi penyerang dengan sangat banyak IP tetap bisa
   membebani satu koneksi SQLite; pertahanan lebih jauh ada di Cloudflare/proxy.
2. ~~Tembok~~: sejak commit berikutnya server mengenal bentuk petak (`make maps`) dan menghitung jarak jalan
   menyusuri petak; berdiri di tembok/air/lava ditolak. Sisa: NPC dan peti tidak dihitung sebagai penghalang.
3. **Waktu menganggur (Low)**: waktu sejak gerakan terakhir (termasuk saat offline) menambah jatah jarak; setelah
   lama tidak bermain pemain bisa langsung muncul jauh di wilayah yang sudah terbuka.
4. **HTTP biasa (Low/operasional)**: tanpa TLS kecuali lewat Cloudflare; token terlihat di jaringan lokal (catatan no. 239).
5. **Status 429 per akun** bisa menunjukkan nama dan email milik
   akun yang sama bila penyerang sudah menebak keduanya (Low).
6. Uji `-race` belum dijalankan (lihat C); uji arena 3D "Raja Goblin" di e2e diganti uji penolakan lompatan.

## H. Kesimpulan

**Layak untuk pengujian lokal dan staging.** Semua tes server dan uji klien ujung-ke-ujung lolos, dan server baru
membuka salinan database Pi dengan sehat. Sebelum dipertimbangkan untuk produksi: jalankan CI (termasuk `-race`),
uji main di HP sungguhan beberapa sesi (pindah peta, sinyal putus-sambung, buka peti) sambil memantau log
`posisi ditolak` dan `status=429`.
