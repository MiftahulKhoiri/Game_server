# Petualangan Ilmu SD — Dunia Enam Pulau (desain ulang 3.x)

Dokumen kerja desain ulang game `education_sd`. Dasar: dokumen induk "Petualangan Ilmu SD – Dunia Enam
Pulau" (versi 1.0, di Project). Dokumen lama `SD_PULAU_ILMU.md` dan `SD_PULAU_ILMU_3D.md` tetap
disimpan sebagai riwayat versi 1.x–2.x.

Alasan desain ulang: anak-anak yang mencoba versi 2.4.x **tidak tertarik**. Mereka lebih tertarik pada
konsep enam pulau.

---

## Tahap 0 — Audit dan persiapan (15 Nov 2026)

### 0.1 Kondisi game SD saat ini (paket 2.4.3)

| Bagian | Isi | Catatan |
|---|---|---|
| `main.gd` (1840 baris) | Semua layar: pengenalan, beranda menu, pilih wilayah, sesi soal, kuis, ujian, hasil, laporan, koleksi, toko, markas, dunia 3D | Satu berkas besar, layar berbasis menu |
| `data/pulau_ilmu.json` | 4 wilayah **per mata pelajaran** (Matematika, Bahasa, IPA, IPS), topik per kelas, 210 soal, 9 tipe dipakai, mini-game, lencana, toko | Dibuat dari `tools/gamepack/make_sd_bank.py` |
| `scripts/sd_question.gd` | Tampilan 11 tipe soal (pilihan ganda, benar/salah, pasangan, kelompokkan, urutkan kata/huruf, isian, hitung, pilih gambar, …) | **Dipakai ulang** |
| `scripts/sd_gen.gd` | Pembuat soal otomatis (hitung, urut, tambah, kurang, kali, bagi, pecahan) per kelas | **Dipakai ulang**; memakai `res://shared/edu/question_gen.gd` |
| `scripts/sd_progress.gd` | Progres skema 2 lewat `GameManager.save_progress` + migrasi v1 | Akan naik ke skema 3 dengan migrasi |
| `scripts/world/w3d_*.gd` | Dunia 3D per wilayah: alun-alun + **lorong lurus** bergerbang per topik, "Pengacau Lupa", penjaga wilayah, kamera 360°, joystick | Pemain/kamera/HUD/rig **dipakai ulang**; tata dunia diganti |
| `assets/` | Pahlawan anak laki-laki & perempuan (GLB sendiri), 25 aset lingkungan GLB sendiri (rumah adat, perpustakaan, menara, lab, gua, pohon, batu) | **Dipakai ulang** |
| Model dari APK (`res://assets/models`) | KayKit/Quaternius/OpenGameArt CC0: goblin, raja_goblin, serigala_hutan, golem_kerikil, ogre_batu, aldragor (naga), kelelawar, tikus, ular, belalang, warga | Cukup untuk **semua bos enam pulau** tanpa aset baru |
| Uji | `client/tests/sd_test.gd` — **610 pemeriksaan LULUS** (dijalankan 15 Nov 2026 di Pi, `make sd-test`) | Garis dasar sebelum perubahan |

### 0.2 Kenapa anak tidak tertarik (hasil pembacaan kode)

1. **Layar pertama adalah menu**, bukan dunia. Anak memilih kelas → mapel → mode (latihan/kuis/ujian).
   Rasanya seperti aplikasi soal.
2. **Dunia dibagi per mata pelajaran.** "Kerajaan Matematika" isinya hanya soal matematika, jadi dunia
   terasa seperti nama lain untuk bab buku.
3. **Dunia 3D berupa lorong lurus** bergerbang. Tidak ada desa yang dijelajahi, rahasia, atau cerita.
4. **Belajar muncul sebagai sesi soal penuh layar** (5–10 soal), memotong petualangan.
5. **Tidak ada pertarungan, bos, atau rasa menang.** Pengacau hanya mendorong pemain.
6. **Tidak ada cerita** yang mengikat: tidak ada tokoh jahat, tujuan besar, atau alasan pindah pulau.

Konsep baru menjawab semua poin ini: dunia lebih dulu, pulau per kelas, akademi di dalam dunia, soal kecil
di dalam misi, pertarungan bergiliran dengan jurus ilmu, dan bos penjaga tiap pulau.

### 0.3 Ketergantungan dan API yang boleh dipakai

Dari luar folder `client/games/education_sd/`, game SD hanya memakai:

| Dipakai | Status |
|---|---|
| Autoload `GameManager`: `save_progress`, `load_progress` (dengan migrasi), `restore_progress_from_server`, `exit_to_launcher`, `set_platform_music` | Boleh dipakai, **tidak diubah** |
| `res://shared/edu/question_gen.gd` (lewat `sd_gen.gd`) | Hanya dibaca, **tidak diubah** (dipakai SMP) |
| `res://shared/edu/quiz_app.gd` | Hanya disebut di komentar; tidak dipakai SD |
| `res://assets/models/*.glb` (ikut APK) | Hanya dibaca. Tidak ada aset baru di APK, jadi **tidak perlu APK baru** |

Yang **tidak disentuh**: `client/scripts`, `client/scenes` (The Last Dragon), `client/games/education_smp`,
`client/core`, `client/launcher`, server Go, autentikasi, tanda tangan paket.

**Satu-satunya berkas bersama yang perlu disesuaikan**: `client/tests/platform_test.gd` baris 311–328
memeriksa isi game SD lama (`data.regions.size() == 4`, `start_quiz("bahasa")`, `p.grades["1"].quiz`).
Uji itu harus diganti dengan pemeriksaan game baru (memuat, profil, simpan progres, kembali ke launcher).
Dampak: hanya uji; kode launcher/platform tidak berubah.

### 0.4 Keputusan yang diambil (15 Nov 2026, oleh pemilik proyek)

| Topik | Keputusan |
|---|---|
| Kamera & kontrol | Orang ketiga + joystick (kamera bisa diputar), HP landscape |
| Pertarungan | **Bergiliran + jurus ilmu**: Serang / Jurus Ilmu (jawab soal) / Bertahan / Ramuan. Salah jawab = jurus gagal, tidak kehilangan barang. Tidak ada batas waktu menjawab |
| Penguji anak | Kelas 1–2 dan kelas 3–4 |
| Game lama | **Diganti total.** Progres lama dibawa: nama, kelas, koin, kostum, pahlawan, riwayat & statistik belajar |
| Pemain | Bermain sendiri, offline-first (progres disinkron lewat GameManager seperti sekarang) |

Keputusan turunan (dari jawaban di atas):

- **Pulau percontohan = Pulau 1 "Dunia Pemula"**, tetapi khusus versi percontohan **soal mengikuti kelas
  anak di profil** (1–4), supaya anak kelas 3–4 juga mencoba dunia yang sama tanpa soal terlalu mudah.
  Setelah keenam pulau ada, setiap pulau kembali memakai materi kelasnya, dan kelas profil menentukan
  pulau awal.
- Pulau 2–6 tampil di peta dunia sebagai **"segera hadir"** (terkunci, dengan nama & gambar).
- Bos memakai model yang sudah ada di APK: Raja Goblin Kecil (`raja_goblin`), Serigala Hutan Besar
  (`serigala_hutan`), Golem Penjaga (`golem_kerikil`), Penjaga Batu Kuno (`golem_lava`/`golem_kerikil`
  diwarnai), Panglima Orc (`ogre_batu`), Naga Kegelapan (`aldragor`).

Masih terbuka (tidak dianggap final): gaya visual final, ukuran peta tiap pulau, cerita utama lengkap,
jumlah NPC & misi per pulau, struktur materi final per mapel (harus dicek dengan Capaian Pembelajaran
Kurikulum Merdeka fase A/B/C), detail profil siswa di server.

### 0.5 Arsitektur baru

Semua di `client/games/education_sd/`. `main.tscn` tetap jadi pintu masuk (launcher tidak berubah).

```
education_sd/
  main.gd                  pengatur layar tipis: memuat engine, berpindah adegan (menu, peta, pulau, tarung)
  data/
    islands.json           6 pulau: nama, kelas, tema, warna, bos, status (aktif / segera hadir)
    island1.json           isi Pulau 1: wilayah, NPC & dialog, akademi & guru, misi, monster, rahasia
    pulau_ilmu.json        bank soal lama (210 soal) — tetap dipakai Learning Engine
  scripts/
    engine/
      save_engine.gd       skema 3 + migrasi dari skema 2 (lewat GameManager)
      progress_engine.gd   XP, level, koin, kompetensi per mapel/materi
      learning_engine.gd   pilih soal per materi & kelas, petunjuk, adaptasi (memakai sd_gen + bank soal)
      quest_engine.gd      misi utama/sampingan: syarat, langkah, hadiah
      battle_engine.gd     aturan tarung bergiliran (murni data, bisa diuji tanpa layar)
      reward_engine.gd     hadiah usaha & penguasaan, kartu pengetahuan, koleksi
    world/                 dunia pulau (pemakaian ulang w3d_player/hud/rig, tata dunia baru)
    ui/                    menu utama, profil petualang, peta enam pulau, layar tarung, dialog NPC
    sd_question.gd, sd_gen.gd, sd_audio.gd   dipakai ulang
```

Prinsip: aturan permainan (engine) **terpisah dari tampilan**, sehingga bisa diuji headless di Pi.

### 0.6 Rencana tahap berikutnya

| Tahap | Isi | Kriteria selesai | Uji |
|---|---|---|---|
| 1 Fondasi | Menu utama baru (langsung "Mulai Petualangan"), profil petualang (nama, kelas 1–6, pahlawan), peta dunia enam pulau, pindah pulau, save skema 3 + migrasi | Anak baru → buat profil → peta → masuk Pulau 1; save lama terbawa | sd_test baru + platform_test SD diganti |
| 2 Pulau 1 | Desa, akademi, hutan, sungai, gua, kastil goblin; NPC + dialog | Bisa dijelajahi bebas, 30+ FPS di HP | uji dunia + tangkapan layar |
| 3–6 | Learning, misi, RPG, pertarungan + bos Raja Goblin Kecil | Pulau 1 tamat dari awal sampai bos | uji alur ujung-ke-ujung |
| — | **Diuji anak-anak** (kelas 1–4) sebelum Pulau 2–6 | Tanggapan dicatat di dokumen ini | — |

### 0.7 Risiko

- Ukuran paket naik bila dunia besar → pakai ulang GLB dan MultiMesh seperti 2.4.x.
- HP Samsung A18 → profil grafis Hemat/Normal/Tinggi dipertahankan.
- Membuang layar lama membuat banyak uji `sd_test.gd` tidak berlaku → uji ditulis ulang per tahap; uji
  bank soal & tipe soal yang masih dipakai dipertahankan.
