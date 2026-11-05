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

## Endpoint

### `GET /healthz`
Cek server dan database hidup. `200 {"status":"ok"}`, atau `503`.

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
Menyimpan progress.

Body: `{"version": 1, "state": { ... }}`

`version` adalah versi terakhir yang diterima klien. Jika berbeda dengan versi
di server, simpanan ditolak (`409`) agar data lama tidak menimpa data baru.
Klien harus mengambil `GET /v1/players/me` lalu menggabungkan.

| Status | Arti |
|--------|------|
| 200 | Tersimpan; respons berisi pemain dengan `version` naik 1 |
| 401 | Token tidak valid |
| 409 | Versi tidak cocok |
| 422 | State tidak masuk akal (mis. HP melebihi max_hp) |

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

Saat ini klien mengirim seluruh state dan server hanya memvalidasi. Seiring
game berkembang, server akan menjadi **otoritatif**: klien mengirim aksi
(bergerak, serang, beli) dan server yang menghitung hasilnya, sehingga
curang dan salah hitung tidak mungkin. Perubahan itu akan masuk sebagai
`/v2` atau endpoint aksi baru.
