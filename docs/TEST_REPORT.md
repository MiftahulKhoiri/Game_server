# Laporan Pengujian — Platform Multi-Game v0.84.0

Dijalankan 15 November 2026 di Raspberry Pi 5 (Linux arm64), Go 1.24, Godot 4.7.2 headless. Semua angka
di bawah berasal dari keluaran perintah yang benar-benar dijalankan.

## Ringkasan

| Rangkaian | Perintah | Hasil |
|---|---|---|
| Server Go (format, vet, semua tes; 339 fungsi tes termasuk yang baru) | `make check` | **LULUS** |
| Katalog (`internal/catalog`) | `go test ./internal/catalog` | **LULUS** (6 tes) |
| Endpoint platform (`internal/api/games_test.go`) | `go test ./internal/api -run Game` | **LULUS** (5 tes) |
| Migrasi database v4 → v5 | tes store yang ada (`user_version == schemaVersion`) | **LULUS** |
| Uji ujung-ke-ujung klien lama (Petualangan) dengan launcher & GameManager aktif | `make client-test` | **LULUS** (1162 pemeriksaan, 0 gagal) |
| Uji platform (3 fase, proses Godot terpisah, server Go sungguhan) | `make platform-test` | **LULUS** (108 pemeriksaan di fase 1, 2, 3; 0 gagal) |
| Tangkapan layar launcher, rincian game, beranda SD, soal (Xvfb + OpenGL) | manual | diperiksa visual; dua cacat tata letak ditemukan dan diperbaiki (label judul tergulung per huruf, kartu terlalu sempit) |

## Uji platform (`scripts/platform-test.sh`)

Menggunakan kunci penerbit UJI sementara dan **salinan proyek klien tanpa `games/`** (meniru isi APK).

**Fase 1 — pasang & main**: versi semver & kecocokan mesin/launcher; 10 manifest tidak sah ditolak (id,
traversal, entry di luar namespace, `user://`, paket, sha, ukuran, versi, tipe) + id beda; tanda tangan sah
diterima, katalog diubah 1 bit / tanda tangan salah / kosong / kunci lain ditolak; save per game terpisah,
save rusak dipulihkan dari `.bak`, migrasi skema v1→v2, id save tidak sah ditolak; soal acak valid dan kunci
jawaban aritmetika = hasil hitungan; launcher tampil tanpa katalog dengan Petualangan INSTALLED; game SD tidak
ada di "APK"; katalog bertanda tangan diterima dan disimpan; katalog palsu ditolak, katalog lama tetap;
launcher menampilkan 3 game dan tombol yang benar; **unduhan diputus pada 64 KB lalu dilanjutkan dari byte
65536 (HTTP Range)**; terpasang setelah verifikasi, `.part` dibersihkan; **paket SMP rusak di server ditolak
(SHA-256)** dan tidak tercatat; **manifest bertanda tangan salah ditolak**; PCK untuk namespace lain / yang
menyentuh skrip aplikasi / berflag hapus / terpotong ditolak; SD dimainkan dari PCK (skrip + data termuat),
kuis 8 soal, nilai 100, level berikutnya terbuka, riwayat & progres tersimpan, progres SMP tidak tercampur;
kembali ke launcher tanpa game aktif; SMP setelah SD (adegan SD dilepas); Petualangan terbuka dari launcher,
tombol "Semua Game" ada, kembali ke launcher; paket terpasang yang diubah ditolak.

**Fase 2 — update (proses baru)**: SD UPDATE_AVAILABLE 1.0.0→1.0.1, SMP & Petualangan tidak berubah; update
hanya SD, versi lama disimpan untuk rollback, paket SMP tidak diunduh ulang, progres utuh; SD 1.0.1 berjalan
dan isi paket yang dimuat benar 1.0.1; rollback ke 1.0.0; memuat versi lain di sesi yang sama → minta buka
ulang; hapus SMP (folder hilang), game bawaan tidak bisa dihapus, pasang ulang; **progres dikirim ke server
dengan akun, dipulihkan ke "HP baru"**, progres SMP di server terpisah.

**Fase 3 — offline (proses baru)**: server tak terjangkau → offline, katalog terakhir tetap dipakai,
launcher terbuka, MAINKAN tetap ada, Petualangan tersedia, game unduhan dimainkan offline, progres lokal
terbaca, mode latihan memberi pembahasan, progres ditandai untuk sinkron, kembali ke launcher.

Pesan `ERROR` yang muncul di log uji dan memang diharapkan: "Parse JSON failed" (uji save rusak) dan
"[save] id game tidak sah: ../x" (uji penolakan id).

## Belum dijalankan (jujur)

| Uji | Alasan / langkah |
|---|---|
| APK v0.84.0 dipasang di HP, launcher berjalan, PCK dimuat dari penyimpanan Android, sentuhan & audio | Butuh HP; APK dibangun CI dari tag `v0.84.0`. Pasang APK, unduh SD/SMP, mainkan, lalu matikan internet dan ulangi |
| Unduhan lewat data seluler sungguhan / HTTPS Tailscale dari HP | idem |
| Pemakaian RAM di berbagai HP | Pengaturan > "Tampilkan FPS & memori" (sudah ada) |
| Ruang penyimpanan penuh | Logika ada (cek `get_space_left` sebelum unduh) tetapi tidak disimulasikan |
