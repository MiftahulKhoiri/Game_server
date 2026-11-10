# Berkontribusi

Terima kasih sudah mau ikut. Proyek ini terbuka untuk semua orang.

## Pembagian peran

- **Gambar dan arah game**: pemilik proyek (ilustrator). Koreksi dan saran selalu diterima.
- **Kode**: siapa saja boleh mengirim perbaikan; Claude (asisten AI) menjadi pendukung
  utama penulisan kode. Commit yang dibantu Claude mencantumkan `Co-Authored-By`.

## Alur kerja

1. Fork repo, atau buat branch baru dari `main`.
2. Ubah kode. Jika mengubah perilaku API, ubah juga `docs/API.md`.
3. Jalankan `make check` (format, vet, tes). Harus lulus. Bila mengubah klien, jalankan juga
   `make client-test GODOT=...` (lihat [docs/TESTING.md](docs/TESTING.md)).
4. Buka Pull Request dengan penjelasan singkat apa dan mengapa.

## Aturan kode (server Go)

- Format dengan `gofmt` (`make fmt`).
- Logika game masuk `internal/game` dan harus punya tes. Paket itu tidak boleh
  tahu soal HTTP atau database.
- Jangan percaya data dari klien: validasi di server.
- Pesan commit singkat dan jelas, boleh bahasa Indonesia atau Inggris.

## Melapor masalah

Buka issue: sertakan langkah mengulang, hasil yang diharapkan, dan hasil sebenarnya.

## Lisensi

Kontribusi kode dilisensikan di bawah GPL-3.0, sama seperti proyek ini.
