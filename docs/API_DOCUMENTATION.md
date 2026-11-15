# API Platform Multi-Game (v0.84.0)

Melengkapi kontrak API utama di [API.md](API.md). Semua endpoint ada di server Go yang sama (bukan API
terpisah), memakai versi API `/v1`, middleware log, pembatas laju, pemulihan panic, dan gerbang versi klien
yang sama. Jawaban error selalu JSON `{"error": "..."}`.

Folder data: `GAME_CATALOG_DIR` (bawaan `catalog/` relatif terhadap direktori kerja server). Isinya dibuat oleh
`scripts/build-game-pack.sh`; perubahan berlaku tanpa restart.

## Katalog (tanpa login)

| Metode & jalur | Jawaban |
|---|---|
| `GET /v1/games` | `catalog.json` **byte persis** yang ditandatangani (`application/json`, `Cache-Control: no-cache`) |
| `GET /v1/games/catalog.sig` | tanda tangan base64 atas `catalog.json` |
| `GET /v1/games/{id}` | satu entri katalog (JSON, untuk tampilan) |
| `GET /v1/games/{id}/version` | `{"id","version"}` |
| `GET /v1/games/{id}/manifest` | `manifest.json` byte persis |
| `GET /v1/games/{id}/manifest.sig` | tanda tangan base64 atas manifest |
| `GET /v1/games/{id}/download` | berkas `.pck` (`application/octet-stream`, header `X-Package-SHA256`). Mendukung `Range: bytes=N-` → `206 Partial Content` |

Status: `404` id tidak sah (`^[a-z][a-z0-9_]{1,31}$`), game tidak ada, atau katalog belum dibuat;
`503` manifest rusak atau ukuran paket di disk tidak sama dengan manifest (mis. sedang disalin).

Klien **tidak mempercayai** jawaban ini tanpa memeriksa tanda tangan dengan kunci publik penerbit di APK.
`GET /v1/games/{id}` hanya untuk tampilan; instalasi selalu memakai manifest bertanda tangan.

## Progres per game (butuh `Authorization: Bearer <token>`)

Untuk game selain Petualangan (progres Petualangan tetap di `GET /v1/players/me` / `PUT /v1/players/me/save`).

`GET /v1/games/{id}/progress`

```json
{"game_id":"education_sd","schema_version":1,"data":{...},"updated_at":"2026-11-15T03:50:00Z",
 "client_updated":"2026-11-15T11:49:58","revision":3}
```

Belum ada progres → `{"game_id":"education_sd","schema_version":0,"data":{},"revision":0}`.

`POST /v1/games/{id}/progress` dengan badan `{"schema_version": 1, "data": {...}, "updated_at": "..."}`
menyimpan (menimpa) progres dan menaikkan `revision`. Validasi: `schema_version` 1..1000, `data` harus objek
JSON, badan ≤ 64 KiB, `updated_at` ≤ 40 karakter, kolom asing ditolak. `id` = `adventure` atau tidak sah → 400.
Tanpa token → 401.

Penyimpanan: tabel `game_progress (player_id, game_id)` (skema database v5), terhapus otomatis bila akun dihapus.

## Contoh

```bash
curl -s https://raspberrypi.tail3e263f.ts.net:8443/v1/games | head
curl -s -o sd.pck https://raspberrypi.tail3e263f.ts.net:8443/v1/games/education_sd/download
curl -s -H 'Range: bytes=100000-' -o sisa.bin .../v1/games/education_sd/download   # 206
```

## Pemetaan ke endpoint konseptual

| Konsep | Implementasi |
|---|---|
| `GET /api/games` | `GET /v1/games` (+ `catalog.sig`) |
| `GET /api/games/{id}` / `version` / `manifest` / `download` | `GET /v1/games/{id}` / `version` / `manifest` (+ `.sig`) / `download` |
| `POST /api/auth/login` | sudah ada: `POST /v1/login` |
| `GET /api/users/me` | sudah ada: `GET /v1/players/me` |
| `GET/POST /api/games/{id}/progress` | `GET/POST /v1/games/{id}/progress` |

Awalan `/v1` dipakai agar konsisten dengan API yang sudah berjalan (tidak membuat API ganda).
