# Kontrak API (v1)

Server berbicara JSON lewat HTTP. Alamat bawaan `http://<ip-pi>:8090`.
Dokumen ini adalah **sumber kebenaran** antara server dan klien (APK):
ubah dokumen ini bersamaan dengan kode.

Semua error berbentuk `{"error": "pesan"}`.

## Autentikasi

Akun dibuat dengan **nama + email + kata sandi** (`POST /v1/players`). Kata sandi disimpan
di database sebagai hash PBKDF2-HMAC-SHA256 dengan garam acak (`pbkdf2-sha256$<iterasi>$<garam>$<hash>`),
tidak pernah sebagai teks asli, dan tidak pernah dikirim balik oleh server.

Daftar dan login (`POST /v1/login`) sama-sama menjawab dengan `token` sesi. Klien menyimpannya
dan mengirimnya di setiap permintaan yang butuh login:

```
Authorization: Bearer <token>
```

- Server hanya menyimpan hash token (tabel `sessions`). Satu akun boleh punya beberapa token
  sekaligus (beberapa HP); paling banyak 10, yang tertua dibuang otomatis.
- Token hilang bukan lagi akhir akun: cukup login ulang dengan nama/email dan kata sandi,
  progress tetap ada. Token tidak kedaluwarsa sampai di-logout.
- Klien **tidak boleh** menyimpan kata sandi di HP, hanya token.
- Percobaan login yang gagal dibatasi (lihat `429` di bawah).

## Versi klien

Klien mengirim versinya di setiap permintaan:

```
X-Client-Version: 0.3.0
```

Jika versinya di bawah `min_client` server, semua endpoint (kecuali `/healthz`
dan `/v1/version`) menjawab `426 Upgrade Required`:

```json
{"error": "Versi aplikasi 0.1.0 sudah terlalu lama (minimal 0.2.0). Silakan update.",
 "min_client": "0.2.0", "update_url": "https://github.com/.../releases/latest"}
```

Header yang tidak ada diabaikan (klien lama). Aturan lengkap: [VERSIONING.md](VERSIONING.md).

## Endpoint

### `GET /healthz`
Cek server dan database hidup. `200 {"status":"ok","version":"0.3.0"}`, atau `503`.

### `GET /v1/version`
Info versi, tanpa login. Selalu terbuka, juga untuk klien yang terlalu lama.

```json
{"server": "0.3.0", "commit": "d8f256d", "api": 1,
 "min_client": "0.1.0", "latest_client": "0.3.0",
 "update_url": "https://github.com/MiftahulKhoiri/Game_server/releases/latest"}
```

### `POST /v1/players`
Daftar akun baru.

Body: `{"name": "Petualang", "email": "budi@contoh.id", "password": "sandi-rahasia"}`

- `name`: 3-20 karakter: huruf, angka, `_`. Tidak membedakan huruf besar/kecil.
- `email`: alamat polos (tanpa nama tampilan), maksimal 254 karakter, disimpan huruf kecil.
  Unik, tidak membedakan huruf besar/kecil. Saat ini hanya untuk identitas akun (login lewat
  email dan rencana pemulihan); server belum mengirim email.
- `password`: 8-128 byte, tidak boleh hanya spasi, tidak boleh sama dengan nama atau email.

| Status | Arti |
|--------|------|
| 201 | Berhasil: `{"player": {...}, "token": "..."}` |
| 400 | JSON rusak atau ada field asing |
| 409 | Nama sudah dipakai, atau email sudah terdaftar |
| 422 | Nama / email / kata sandi tidak memenuhi aturan |
| 429 | Terlalu banyak pendaftaran dari alamat yang sama (20 per jam) |

### `POST /v1/login`
Masuk ke akun yang sudah ada. Menghasilkan token **baru**; token lain milik akun ini tetap berlaku.

Body: `{"login": "Petualang", "password": "sandi-rahasia"}`. `login` boleh nama ATAU email.

| Status | Arti |
|--------|------|
| 200 | Berhasil: `{"player": {...}, "token": "..."}` |
| 401 | Nama/email atau kata sandi salah (pesan sama untuk akun yang tidak ada, agar akun tidak bisa ditebak) |
| 422 | Isian kosong |
| 429 | Terlalu banyak percobaan gagal; header `Retry-After` berisi detik tunggu |

Pembatas: 5 kegagalan per nama/email dan 30 per alamat IP dalam 15 menit. Login yang berhasil
mereset hitungan nama. Akun lama (dibuat sebelum v0.16.0) yang belum punya kata sandi tidak bisa
login lewat endpoint ini.

### `POST /v1/logout`  (login)
Mencabut token yang dipakai permintaan ini (token di perangkat lain tetap hidup). `204` tanpa isi,
`401` bila token tidak valid.

### `GET /v1/players/me`  (login)
Mengambil data pemain beserta progress. `200` berisi objek pemain (termasuk `email` milik sendiri), `401` jika token salah.

### `PUT /v1/players/me/save`  (login)
Menyimpan **posisi** pemain. Sejak v0.3.0 server otoritatif: hanya `map`, `x`,
`y` yang diterapkan; sejak v0.13.0 juga posisi halus dunia 3D `fx`, `fz` (satuan
petak, `x <= fx < x+1`, `y <= fz < y+1`) dan arah hadap `yaw` (radian). Posisi halus
di luar petak `x,y` (atau klien lama yang tidak mengirimnya) diganti tengah petak;
nilai bukan angka (NaN/Inf) ditolak `422`. Kalah bertarung memulangkan pemain ke
tengah petak awal. Level, XP, HP, emas, dan tas hanya berubah lewat aksi
server (pertarungan) dan nilai kiriman klien untuk field itu diabaikan.

Body: `{"version": 1, "state": { ... }}`

`version` adalah versi terakhir yang diterima klien. Jika berbeda dengan versi
di server, simpanan ditolak (`409`) agar data lama tidak menimpa data baru.
Klien harus mengambil `GET /v1/players/me` lalu menggabungkan.

| Status | Arti |
|--------|------|
| 200 | Tersimpan; respons berisi pemain dengan `version` naik 1 |
| 401 | Token tidak valid |
| 409 | Versi tidak cocok |
| 426 | Versi aplikasi di bawah `min_client` |
| 422 | State tidak masuk akal, atau posisi di luar peta / peta tidak dikenal (peta: `desa_awal`, `perbatasan`, `gunung_batu`, `gua_batu`, Desa Awal 85x50, lainnya 45x50 (Gua Batu 15x20)) |

## Pertarungan (v0.3.0)

Real-time dengan cooldown (sejak v0.18.0) dan sepenuhnya dihitung server. Musuh menyerang
sendiri tiap beberapa detik tanpa menunggu pemain; pemain memakai aksi yang masing-masing punya
cooldown. Satu pemain hanya punya satu pertarungan aktif; pertarungan tersimpan di database
sehingga bisa dilanjutkan setelah aplikasi ditutup. Server "malas": serangan musuh yang jatuh
tempo dihitung saat ada permintaan (aksi atau `GET /v1/battle`), jadi klien perlu menyapa
server kira-kira saat `enemy_next_ms` habis. Bila klien lama tidak menyapa, serangan susulan
dibatasi (maksimal 2) supaya pemain tidak mati saat aplikasi ditutup.

### `GET /v1/battle`  (login)
Pertarungan yang sedang berjalan sekaligus **sinkronisasi**: serangan musuh yang sudah jatuh
tempo diselesaikan dan dilaporkan di `log`/`events`. `200` berisi respons pertarungan, `404`
bila tidak ada. Pemain bisa kalah di sini (`status: "lost"`).

### `POST /v1/battle/start`  (login)
Body boleh kosong. `{"boss": true}` melawan bos di petak pemain; `422` bila tidak ada bos di sana.
Mulai melawan musuh acak sesuai level pemain dan peta tempat ia berada (peta terakhir yang disimpan). `201` berisi respons pertarungan,
`409` bila sudah ada pertarungan aktif. Musuh pertama menyerang 3 detik setelah mulai.

### `POST /v1/battle/action`  (login)
Body: `{"action": "attack"}`. Aksi dan cooldown:

| Aksi | Efek | Cooldown |
|------|------|----------|
| `attack` | serangan biasa (10% kritis) | 0,9 d |
| `defend` | jendela bertahan 1,2 d: serangan musuh yang tiba di dalamnya dikurangi separuh; bila tiba ≤ 0,45 d setelah ditekan = **tangkisan sempurna** (0 kerusakan, serangan musuh berikutnya tertunda 0,6 d) | 1,8 d |
| `skill1` | Tebasan Kuat: kerusakan 2,2x serangan | 5 d |
| `skill2` | Perisai Cahaya: pulihkan 25% HP maks dan hanya menerima 30% kerusakan selama 3 d | 14 d |
| `potion` | pulihkan 15 HP (memakai 1 ramuan) | 2,5 d |
| `flee` | peluang 60% kabur | 3 d |

Serangan musuh: tiap 2 d (bos 1,6 d). Server memberi kelonggaran jaringan 250 ms: aksi
dianggap terjadi sedikit lebih awal.

| Status | Arti |
|--------|------|
| 200 | Aksi diproses |
| 404 | Tidak ada pertarungan |
| 422 | Aksi tidak dikenal, belum siap (cooldown), tidak punya ramuan, atau HP sudah penuh |

Respons:

```json
{
  "status": "ongoing",
  "battle": {"enemy_id": "tikus_sawah", "enemy_name": "Ayam Liar",
             "enemy_hp": 4, "enemy_max_hp": 10, "round": 2,
             "enemy_next_ms": 1350, "enemy_interval_ms": 2000,
             "cooldowns": {"attack": 900, "defend": 0, "skill1": 0, "skill2": 0, "potion": 0, "flee": 0},
             "cooldown_max": {"attack": 900, "defend": 1800, "skill1": 5000, "skill2": 14000, "potion": 2500, "flee": 3000},
             "guard_ms": 0, "shield_ms": 0},
  "log": ["Kamu menyerang Ayam Liar: -6 HP.", "Ayam Liar menyerang: -2 HP."],
  "events": [{"who": "player", "kind": "attack", "dmg": 6}, {"who": "enemy", "kind": "hit", "dmg": 2}],
  "rewards": null,
  "player": { "...": "objek pemain" }
}
```

Semua waktu di `battle` adalah **sisa milidetik relatif sekarang** (jam klien tidak perlu sama
dengan jam server). `events` untuk animasi: `who` `player`/`enemy`; `kind` `attack`, `crit`,
`skill1`, `skill2`, `guard`, `potion` (pemain) atau `hit`, `guard`, `shield`, `perfect` (musuh).

`status`: `ongoing`, `won`, `lost`, atau `fled`. Saat selesai `battle` bernilai
`null`. `rewards` (menang) berisi `xp`, `gold`, `drop`, `leveled_up`, `new_level`.
Kalah: emas berkurang separuh, HP pulih separuh, dan pemain dipulangkan ke titik
awal desa. Klien harus **menggabungkan** `player` ke data lokal: statistik dan tas
ikut server, sedangkan posisi tetap milik klien (kecuali setelah kalah).

Daftar musuh dan rumusnya ada di [GAME_DESIGN](GAME_DESIGN.md).

## Pahlawan (v0.19.0)

Pemain memilih pahlawan (penampilan model 3D + nama skill; statistik sama untuk semua).
`state.hero` berisi id pilihan (`ksatria` bawaan; akun lama tanpa isian dianggap `ksatria`).
Klien **tidak** bisa mengubahnya lewat `PUT /v1/players/me/save` (hanya posisi yang diterima).

### `GET /v1/heroes`  (login)
`200 {"heroes": [{"id", "name", "weapon", "skill1", "skill2", "price"}], "default": "ksatria"}`.
Pahlawan: `ksatria`, `pendekar_kapak`, `pemanah`, `pendekar_tombak`.

### `POST /v1/players/me/hero`  (login)
Body: `{"hero": "pemanah"}`. `200` berisi pemain terbaru (versi naik), `422` bila id tidak
dikenal, `409` bila sedang bertarung. Nama skill di `log` pertarungan mengikuti pahlawan.

## Pahlawan pendamping (v0.38.0)

Pemain boleh membeli pahlawan (harga = `price` di `GET /v1/heroes`: ksatria 250, pemanah 300, pendekar_tombak 300,
pendekar_kapak 350 emas) lalu memasangnya berbaris di belakang. `state.allies` = yang sudah dibeli,
`state.party` = yang dipasang (maks 3, urutan = urutan berbaris). Keduanya hanya diubah server.
Selama bertarung tiap pendamping yang dipasang menyerang otomatis tiap 2,4 d (kerusakan = serangan dasar
level pemain x 70% + 2, tanpa kritis); kejadiannya `{"who":"ally","kind":"attack","dmg":N,"hero":"pemanah"}`
dan `battle.ally_next_ms` / `ally_interval_ms` memberi jadwal serangan berikutnya.

### `POST /v1/allies/buy`  (login)
Body: `{"hero": "pemanah"}`. `200` berisi pemain terbaru (emas berkurang, pahlawan masuk `allies`, dan langsung
masuk `party` bila masih ada tempat). `422` bila id tidak dikenal, sudah dibeli, atau emas kurang;
`409` bila sedang bertarung.

### `POST /v1/party`  (login)
Body: `{"party": ["pemanah", "pendekar_kapak"]}` (boleh kosong). `200` berisi pemain terbaru. `422` bila lebih
dari 3, ada yang belum dibeli, atau ada yang dobel; `409` bila sedang bertarung.

## Misi (v0.6.0)

Misi "kalahkan N musuh". Kemajuan dihitung server setiap pemain **menang** dalam
pertarungan (kalah atau kabur tidak dihitung), lalu hadiah diambil dari NPC pemberi
misi. Kemajuan dan hadiah disimpan di `state.quests` (hanya server yang mengubahnya).

### `GET /v1/quests`  (login)
`200 {"quests": [{"id", "title", "giver", "description", "target_ids", "target_count",
"reward_gold", "reward_items", "reward_text", "requires", "status", "progress"}]}`.
`status`: `locked` (misi prasyarat `requires` belum diambil hadiahnya), `available`, `active`, `done`, `claimed`.

Jenis misi (v0.20.0): "kalahkan N musuh" (`target_ids` terisi) dan "antar barang" (`collect_id` terisi,
`target_ids` kosong). Pada misi antar barang, `progress` = jumlah barang yang sedang dibawa (maksimal
`target_count`) dan `status` menjadi `done` begitu cukup; barang diambil dari tas saat hadiah diklaim.
Klaim ditolak `422` bila barangnya kurang.

### `POST /v1/quests/accept` dan `POST /v1/quests/claim`  (login)
Body: `{"quest": "selamatkan_nenek"}`. `200 {"player": {...}, "quests": [...], "reward_gold": 40}`
(`reward_gold` dan `reward_text` hanya pada klaim).

| Status | Arti |
|--------|------|
| 404 | Misi tidak dikenal |
| 409 | Sudah diterima / hadiah sudah diambil / sedang bertarung |
| 422 | Klaim padahal misi belum selesai, misi masih terkunci, atau tas penuh saat hadiah berisi barang (tidak ada yang berubah) |

Saat menang, `log` pertarungan memuat baris kemajuan misi, mis. `Misi "Selamatkan Nenek": 2/5.`

## Toko (v0.5.0)

Semua harga ditentukan server. Transaksi atomik: bila gagal, emas dan tas tidak berubah.
Tidak bisa berdagang saat ada pertarungan aktif (`409`).

### `GET /v1/shop?shop=toko|makan|semua`  (login)
Katalog satu toko (v0.39.0): `toko` (bawaan) = Toko Ramuan (ramuan, ramuan kekuatan, senjata, pelindung; membeli semua
selain makanan), `makan` = Rumah Makan (makanan; hanya membeli makanan), `semua` = seluruh daftar barang (untuk ransel).
Toko lain: `404`. Klien membuka toko lewat penjaga di bangunannya (bukan dari Menu).
`200 {"shop": "toko", "items": [{"id", "name", "kind", "buy_price", "sell_price", "shop", "heal"}, ...]}`.
`shop` = toko yang menjual barang itu; `heal` = HP yang dipulihkan saat dimakan (`kind` `food`).
`buy_price` 0 = tidak dijual toko; `sell_price` 0 = toko tidak membeli.
`kind`: `consumable`, `material`, `treasure`, `equipment`, `food`. Perlengkapan juga membawa
`slot` (`weapon`/`armor`), `attack`, `defense` (bonus). Penjualan perlengkapan yang sedang
dipakai (salinan terakhir) ditolak `422`.

### `POST /v1/shop/buy` dan `POST /v1/shop/sell`  (login)
Body: `{"shop": "toko", "item": "ramuan", "qty": 1}` (qty 1..99; `shop` kosong = `toko`). `200` berisi objek pemain terbaru.
Membeli barang di toko yang tidak menjualnya, atau menjual ke toko yang tidak membelinya, ditolak `422`; `shop` asing `404`.

| Status | Arti |
|--------|------|
| 404 | Barang tidak dikenal |
| 409 | Sedang bertarung |
| 422 | Jumlah salah, emas tidak cukup, barang kurang, tas penuh, atau barang tidak dijual / tidak dibeli |

## Tas & perlengkapan (v0.11.0)

Semua aksi atomik dan mengembalikan `200` berisi objek pemain terbaru. `409` bila sedang
bertarung, `404` bila barang tidak dikenal, `422` bila melanggar aturan.

| Endpoint | Body | Efek |
|----------|------|------|
| `POST /v1/inventory/use` | `{"item":"ramuan"}` | Minum ramuan (+15 HP), makan makanan (`roti` +10, `sup_ayam` +25, `daging_bakar` +50 HP), atau minum `ramuan_kekuatan` (isi energi 60 + serangan x1,3). `422` bila HP penuh / tidak punya |
| `POST /v1/inventory/equip` | `{"item":"pedang_besi"}` | Pasang dari tas; yang lama kembali ke tas. `422` bila bukan perlengkapan / tidak dimiliki |
| `POST /v1/inventory/unequip` | `{"slot":"weapon"}` | Lepas ke tas. `422` bila slot kosong / tas penuh |
| `POST /v1/rest` | - | Istirahat gratis, HP dan energi penuh; hanya di `desa_awal` (`422` di tempat lain atau bila HP dan energi sudah penuh) |

Bonus perlengkapan ditambahkan ke serang/tahan dari level, dan dipakai dalam pertarungan.

## Objek

```json
{
  "id": "52269f1b6c7a6e9f",
  "name": "Petualang",
  "version": 1,
  "created_at": "2026-11-05T12:11:01Z",
  "updated_at": "2026-11-05T12:11:01Z",
  "state": {
    "level": 1, "xp": 0, "hp": 30, "max_hp": 30, "gold": 0,
    "map": "desa_awal", "x": 5, "y": 5, "fx": 5.5, "fz": 5.5, "yaw": 0,
    "inventory": [{"id": "ramuan", "qty": 3}],
    "equipment": {"weapon": "", "armor": ""}
  }
}
```

## Rencana

Server sudah otoritatif untuk statistik dan pertarungan. Berikutnya, aksi
lain (beli, pakai item, misi) mengikuti pola yang sama: klien mengirim aksi,
server menghitung hasilnya. Server belum mengenal peta, jadi posisi masih
dipercaya dari klien dan pemicu pertemuan masih dari klien.

## Energi (v0.39.0)

`state.energy_used` (0..100): energi yang terpakai; energi = 100 - `energy_used` (0 = penuh, field hilang di data lama).
Skill 1 memakai 20 dan Skill 2 memakai 25 energi (`422` "energi tidak cukup" bila kurang); serangan biasa +4, menang +15,
naik level dan istirahat penuh, Ramuan Kekuatan +60.

## Peta ruangan (v0.40.0)

Peta baru yang dikenal server untuk posisi tersimpan: `toko_ramuan`, `rumah_makan`, `rumah_sehat` (masing-masing 9x8 petak,
ruangan di dalam bangunan Desa Awal). `POST /v1/rest` sah di `desa_awal` dan ketiga ruangan itu. Isi ruangan (rak, meja,
penjaga) hanya hiasan klien; aturan belanja tetap di `/v1/shop`.

## Toko Peralatan (v0.41.0)

Toko ketiga: `shop=peralatan`. `GET /v1/shop?shop=peralatan` memuat pedang besi, pedang baja, baju kulit, dan zirah besi
(beli) serta semua perlengkapan (jual). Membeli perlengkapan di toko lain ditolak 422 (`toko ini tidak menjual barang itu`);
toko ramuan (`toko`) kini hanya ramuan dan harta, rumah makan (`makan`) hanya makanan. Peta baru `toko_peralatan` (9x8) dikenal
server untuk posisi tersimpan, dan `POST /v1/rest` sah di sana.

## Prajurit biasa (v0.42.0)

`POST /v1/soldiers/buy` (perlu token) membeli satu prajurit seharga 60 emas; maksimum 5. Hasil: `{state, ...}` dengan
`state.soldiers` (jumlah). `409` saat bertarung, `422` bila emas kurang atau sudah penuh, `401` tanpa token. Prajurit
menyerang sebagai pasukan terpisah di tiap giliran sekutu (event `Who:"ally"`, `Hero:"prajurit_n"`); daya serang = 20% serangan
dasar + 1, tidak memakai slot party.

## Aula Pelatihan (v0.43.0)

Pelatihan hanya sah saat pemain berada di peta `aula_pelatihan` (11x8, termasuk `InVillage` sehingga istirahat gratis juga sah).
Dua tempat latihan: `pahlawan` (satu pahlawan pembantu yang sudah dibeli) dan `prajurit` (seluruh pasukan). Tiap tempat
menjalankan satu latihan sekaligus.

- `POST /v1/train/start` `{kind, target}`: `kind` = `pahlawan` (target = id pahlawan) atau `prajurit`. Dari level L ke L+1 biayanya
  pahlawan 80xL emas, prajurit 40xL emas, ditambah 1 `kartu_keahlian` dan energi (pahlawan 30, prajurit 20), dibayar saat mulai.
  Lama: pahlawan 600xL detik, prajurit 300xL detik. `422` bila di luar aula, tempat latihan sibuk, level sudah 20, emas/kartu/energi
  kurang, atau pahlawan belum dibeli / belum punya prajurit. `409` saat bertarung.
- `POST /v1/train/claim` `{kind}`: mengambil hasil bila `ready_at` (detik Unix) sudah lewat; level naik. `422` bila belum selesai atau tidak ada latihan.
- `GET /v1/time`: `{"unix": detik}` jam server, untuk menghitung sisa waktu.

State pemain: `hero_levels` (id pahlawan -> level, kosong = 1), `soldier_level` (0 = 1), `training` (daftar `{kind, target, to_level, ready_at}`).
Serangan pahlawan = serangan dasar x (70 + 10 x (Lv-1))% + 2; prajurit = serangan dasar x (20 + 5 x (Lv-1))% + 1.
Item `kartu_keahlian`: dijual di toko `peralatan` (60 emas), dijual kembali 20 emas di toko ramuan, dan dijatuhkan musuh dengan peluang 8% saat menang.

## Tukar Berlian dan isi peti (v0.44.0)

`POST /v1/shop/barter` `{shop, item, qty}`: menukar `berlian` dengan barang yang dijual toko itu (aturan toko sama dengan `/v1/shop/buy`,
tetapi tanpa emas). Biaya = ceil(harga beli x qty / 500) berlian (`DiamondGold` = 500, juga harga jual berlian). `422` bila berlian kurang,
toko salah, atau barang tidak dijual; `409` saat bertarung.

`POST /v1/world/chest` kini mengundi 3 hadiah berbeda dari: emas (bobot 36), ramuan x2 (20), ramuan kekuatan (12), kartu keahlian (9),
koin kuno (8), permata merah (7), berlian (3 + 2 x tingkat peti).
