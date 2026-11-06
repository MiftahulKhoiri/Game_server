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
| 422 | State tidak masuk akal, atau posisi di luar peta / peta tidak dikenal (peta: `desa_awal`, `perbatasan`, `gunung_batu`, `gua_batu`, masing-masing 15x20) |

## Pertarungan (v0.3.0)

Bergiliran dan sepenuhnya dihitung server. Satu pemain hanya punya satu
pertarungan aktif; pertarungan tersimpan di database sehingga bisa dilanjutkan
setelah aplikasi ditutup.

### `GET /v1/battle`  (login)
Pertarungan yang sedang berjalan. `200` berisi respons pertarungan, `404` bila tidak ada.

### `POST /v1/battle/start`  (login)
Body boleh kosong. `{"boss": true}` melawan bos di petak pemain; `422` bila tidak ada bos di sana.
Mulai melawan musuh acak sesuai level pemain dan peta tempat ia berada (peta terakhir yang disimpan). `201` berisi respons pertarungan,
`409` bila sudah ada pertarungan aktif.

### `POST /v1/battle/action`  (login)
Body: `{"action": "attack"}`. Aksi: `attack`, `defend` (kurangi separuh serangan
musuh berikutnya), `potion` (pulihkan 15 HP), `flee` (peluang 60%).
Setelah aksi pemain, musuh membalas dalam permintaan yang sama.

| Status | Arti |
|--------|------|
| 200 | Aksi diproses |
| 404 | Tidak ada pertarungan |
| 422 | Aksi tidak dikenal, tidak punya ramuan, atau HP sudah penuh |

Respons:

```json
{
  "status": "ongoing",
  "battle": {"enemy_id": "tikus_sawah", "enemy_name": "Tikus Sawah",
             "enemy_hp": 4, "enemy_max_hp": 10, "round": 2},
  "log": ["Kamu menyerang Tikus Sawah (6 damage).", "Tikus Sawah menggigit (2 damage)."],
  "rewards": null,
  "player": { "...": "objek pemain" }
}
```

`status`: `ongoing`, `won`, `lost`, atau `fled`. Saat selesai `battle` bernilai
`null`. `rewards` (menang) berisi `xp`, `gold`, `drop`, `leveled_up`, `new_level`.
Kalah: emas berkurang separuh, HP pulih separuh, dan pemain dipulangkan ke titik
awal desa. Klien harus **menggabungkan** `player` ke data lokal: statistik dan tas
ikut server, sedangkan posisi tetap milik klien (kecuali setelah kalah).

Daftar musuh dan rumusnya ada di [GAME_DESIGN](GAME_DESIGN.md).

## Misi (v0.6.0)

Misi "kalahkan N musuh". Kemajuan dihitung server setiap pemain **menang** dalam
pertarungan (kalah atau kabur tidak dihitung), lalu hadiah diambil dari NPC pemberi
misi. Kemajuan dan hadiah disimpan di `state.quests` (hanya server yang mengubahnya).

### `GET /v1/quests`  (login)
`200 {"quests": [{"id", "title", "giver", "description", "target_ids", "target_count",
"reward_gold", "reward_items", "reward_text", "requires", "status", "progress"}]}`.
`status`: `locked` (misi prasyarat `requires` belum diambil hadiahnya), `available`, `active`, `done`, `claimed`.

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

### `GET /v1/shop`  (login)
`200 {"items": [{"id", "name", "kind", "buy_price", "sell_price"}, ...]}`.
`buy_price` 0 = tidak dijual toko; `sell_price` 0 = toko tidak membeli.
`kind`: `consumable`, `material`, `treasure`, `equipment`. Perlengkapan juga membawa
`slot` (`weapon`/`armor`), `attack`, `defense` (bonus). Penjualan perlengkapan yang sedang
dipakai (salinan terakhir) ditolak `422`.

### `POST /v1/shop/buy` dan `POST /v1/shop/sell`  (login)
Body: `{"item": "ramuan", "qty": 1}` (qty 1..99). `200` berisi objek pemain terbaru.

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
| `POST /v1/inventory/use` | `{"item":"ramuan"}` | Minum ramuan (+15 HP). `422` bila HP penuh / tidak punya |
| `POST /v1/inventory/equip` | `{"item":"pedang_besi"}` | Pasang dari tas; yang lama kembali ke tas. `422` bila bukan perlengkapan / tidak dimiliki |
| `POST /v1/inventory/unequip` | `{"slot":"weapon"}` | Lepas ke tas. `422` bila slot kosong / tas penuh |
| `POST /v1/rest` | - | Istirahat gratis, HP penuh; hanya di `desa_awal` (`422` di tempat lain atau bila HP penuh) |

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
