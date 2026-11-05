# Kontrak API (v1)

Server berbicara JSON lewat HTTP. Alamat bawaan `http://<ip-pi>:8090`.
Dokumen ini adalah **sumber kebenaran** antara server dan klien (APK):
ubah dokumen ini bersamaan dengan kode.

Semua error berbentuk `{"error": "pesan"}`.

## Autentikasi

Saat mendaftar, server memberi `token` **sekali saja**. Klien menyimpannya dan
mengirim di setiap permintaan yang butuh login:

```
Authorization: Bearer <token>
```

Server hanya menyimpan hash token. Token hilang = akun tidak bisa dipulihkan
(untuk saat ini).

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
Daftar pemain baru.

Body: `{"name": "Petualang"}`. Nama 3-20 karakter: huruf, angka, `_`. Nama tidak
membedakan huruf besar/kecil.

| Status | Arti |
|--------|------|
| 201 | Berhasil: `{"player": {...}, "token": "..."}` |
| 400 | JSON rusak atau ada field asing |
| 409 | Nama sudah dipakai |
| 422 | Nama tidak memenuhi aturan |

### `GET /v1/players/me`  (login)
Mengambil data pemain beserta progress. `200` berisi objek pemain, `401` jika token salah.

### `PUT /v1/players/me/save`  (login)
Menyimpan **posisi** pemain. Sejak v0.3.0 server otoritatif: hanya `map`, `x`,
`y` yang diterapkan. Level, XP, HP, emas, dan tas hanya berubah lewat aksi
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
| 422 | State tidak masuk akal, atau posisi di luar peta / peta tidak dikenal (peta: `desa_awal`, `perbatasan`, `gunung_batu`, masing-masing 15x20) |

## Pertarungan (v0.3.0)

Bergiliran dan sepenuhnya dihitung server. Satu pemain hanya punya satu
pertarungan aktif; pertarungan tersimpan di database sehingga bisa dilanjutkan
setelah aplikasi ditutup.

### `GET /v1/battle`  (login)
Pertarungan yang sedang berjalan. `200` berisi respons pertarungan, `404` bila tidak ada.

### `POST /v1/battle/start`  (login)
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
`kind`: `consumable`, `material`, `treasure`.

### `POST /v1/shop/buy` dan `POST /v1/shop/sell`  (login)
Body: `{"item": "ramuan", "qty": 1}` (qty 1..99). `200` berisi objek pemain terbaru.

| Status | Arti |
|--------|------|
| 404 | Barang tidak dikenal |
| 409 | Sedang bertarung |
| 422 | Jumlah salah, emas tidak cukup, barang kurang, tas penuh, atau barang tidak dijual / tidak dibeli |

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
    "map": "desa_awal", "x": 5, "y": 5,
    "inventory": [{"id": "ramuan", "qty": 3}]
  }
}
```

## Rencana

Server sudah otoritatif untuk statistik dan pertarungan. Berikutnya, aksi
lain (beli, pakai item, misi) mengikuti pola yang sama: klien mengirim aksi,
server menghitung hasilnya. Server belum mengenal peta, jadi posisi masih
dipercaya dari klien dan pemicu pertemuan masih dari klien.
