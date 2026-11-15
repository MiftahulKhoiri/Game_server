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

---

## Tahap 1 — Fondasi (paket 3.0.0, 15 Nov 2026)

### Hasil

| Bagian | Berkas | Isi |
|---|---|---|
| Data enam pulau | `data/islands.json` | 6 pulau (kelas 1–6): nama, tema, warna, posisi di peta, materi, tempat, bos (model dari APK), cerita "Kabut Lupa". Hanya Pulau 1 `available` |
| World Engine | `scripts/engine/world_engine.gd` | Validasi data; status pulau `open/locked/soon`; pulau terbuka bila kelas pulau ≤ kelas petualang **atau** bos pulau sebelumnya kalah; `start_island`, `travel` (mencatat kunjungan & jumlah pelayaran) |
| Save Engine | `scripts/engine/save_engine.gd` | Skema 3 (`profile`, `rpg`, `world`, `learning`, `quests`, `academy`, `settings`); migrasi 1→2→3 lewat GameManager **dan** dikenali dari isi (data pulihan server); angka JSON dirapikan; data aneh dibersihkan |
| Menu utama | `scripts/ui/title_screen.gd` | Laut + enam pulau + perahu bergerak; Mulai / Lanjutkan Petualangan, Ganti Petualang, Pengaturan, Keluar |
| Profil petualang | `scripts/ui/profile_screen.gd`, `hero_preview.gd` | Nama, kelas 1–6, pahlawan laki-laki/perempuan, warna baju (koleksi), pratinjau 3D berputar |
| Peta enam pulau | `scripts/ui/world_map.gd`, `sea_art.gd` | Pulau bernomor, jalur pelayaran, gembok "Segera hadir/Terkunci", panel info (materi, bos), perahu berlayar ke pulau tujuan |
| Dunia 3D pulau | `scripts/world/island_scene.gd` | Pulau bulat dengan pantai, laut, bukit, pohon GLB, dermaga + perahu (kembali ke peta), papan nama; batas pulau; memakai ulang pemain, kamera, joystick, HUD 2.x |
| Pengatur layar | `main.gd` (1840 → ±520 baris) | Hanya navigasi layar, simpan, diagnosis (jejak langkah & mode aman dipertahankan) |

Alur pemain baru: menu utama → profil → cerita pembuka → peta → Pulau 1 (3D) → dermaga → peta.
Pemain lama (save 2.x): dikenali, disambut pesan "Petualangan Baru!", koin/kostum/catatan belajar terbawa.

### Berkas lama

`main.gd` lama (menu kuis) diganti. Skrip 2.x lain (`sd_minigames.gd`, `sd_art.gd`, `w3d_locations.gd`,
`w3d_missions.gd`, `w3d_items.gd`, `w3d_base.gd`, `w3d_foes.gd`, `w3d_life.gd`) belum dipanggil lagi tetapi
**belum dihapus**: tahap 2–6 memutuskan mana yang dipakai ulang (mis. dunia hidup, pengacau) dan mana yang dibuang.
`sd_question.gd`, `sd_gen.gd`, `sd_data.gd`, `sd_progress.gd` (migrasi), `sd_audio.gd`, `w3d_player/hud/rig.gd` tetap dipakai.

### Pengujian (dijalankan di Pi 5, 15 Nov 2026)

| Uji | Hasil |
|---|---|
| `make sd-test` | **409 pemeriksaan LULUS** — bank soal, 11 tipe soal, progres 1→2, data pulau, aturan buka/pindah pulau, Save Engine + migrasi, menu, profil, peta, berlayar antarpulau, dunia 3D (gerak, batas pulau, papan, perahu), pengaturan, simpan & buka ulang, save 2.x di HP |
| `make platform-test` | **LULUS** (109 ok) — paket PCK SD baru: unduh, main, masuk Pulau 1, sinkron progres skema 3 ke server & pulihkan, main offline; SMP & launcher tidak terganggu |
| `make client-test` (The Last Dragon) | **LULUS** (1162 ok, sama dengan sebelumnya) |

Jumlah pemeriksaan SD turun dari 610 karena uji layar menu kuis & dunia lorong 2.x dihapus bersama fiturnya;
uji bank soal dan tipe soal tetap.

Tangkapan layar (Xvfb, 1280×720) diperiksa: menu utama, profil, cerita pembuka, peta, Pulau 1.

### Belum / catatan

- Paket 3.0.0 **belum diterbitkan** ke katalog: isinya baru fondasi (belum ada belajar, misi, monster).
  Anak-anak masih memakai 2.4.3 sampai Pulau 1 percontohan bisa dimainkan.
- Isi Pulau 1 (desa, akademi, hutan, sungai, gua, benteng) = Tahap 2.
- Belum diuji di HP sungguhan.

---

## Tahap 2 — Pulau 1 "Dunia Pemula" bisa dijelajahi (paket 3.1.0, 15 Nov 2026)

### Hasil

Pulau dibangun dari data **`data/island1.json`** (tata letak), sehingga pulau 2–6 nanti cukup dibuat
berkas datanya. `islands.json` menunjuk berkas itu lewat kolom `layout`.

| Tempat | Isi |
|---|---|
| Dermaga | perahu kembali ke peta, Pak Udin (penjaga dermaga), papan nama |
| Desa Pemula | alun-alun, rumah joglo / rumah gadang / tongkonan, 2 lapak pasar, lampu jalan, papan desa; Pak Lurah Darmo, Nenek Ijah, Dodi, Bu Wati |
| Ladang Pak Budi | petak tanah, 5 baris tanaman (sebagian hilang dicuri goblin), pagar; Pak Budi |
| Akademi Tunas | bukit landai (bisa didaki), gedung perpustakaan, menara, kubah lab, patung angka, buku besar, globe; Bu Guru Sinta; pintu akademi (dibuka di tahap belajar) |
| Sungai Jernih | sungai melintang pulau, tepi tak bisa diterobos, jembatan kayu; Kak Laras penjaga jembatan |
| Hutan Kecil | hutan lebat (pinus & pohon bulat, semak) + pohon jarang di seluruh pulau |
| Gua Goblin | gua + bebatuan; pintu tertutup **batu besar** (kait misi berikutnya) |
| Benteng Raja Goblin | tembok batu, 4 menara beratap merah, gerbang terkunci, bendera goblin; **Raja Goblin Kecil** di singgasana, 2 goblin penjaga |

Sistem baru:
- **NPC Engine** (`scripts/engine/npc_engine.gd`): dialog per penduduk — perkenalan pertama berbeda dengan
  kalimat berikutnya, nama pemain disisipkan, pertemuan dicatat (`world.met`); tempat dikenali dari posisi dan
  dicatat saat pertama ditemukan (`world.found`).
- **Dialog berhalaman**: satu kalimat per halaman, tombol *Lanjut*; penduduk berhenti dan menghadap pemain.
- **Penduduk hidup**: berjalan-jalan di sekitar rumahnya; yang jauh (>40 m) tidak diperbarui/digambar.
- **Penemuan tempat**: masuk wilayah baru → "Tempat baru ditemukan!" + nama tempat di petunjuk layar.
- Tombol **MISI** sementara menampilkan catatan jelajah (tempat ditemukan & penduduk dikenal).
- Kinerja: pohon memakai MultiMesh per jenis; jumlah pohon, bayangan, kabut, jarak gambar mengikuti profil
  grafis Hemat/Seimbang/Tinggi.

### Pengujian (Pi 5)

| Uji | Hasil |
|---|---|
| `make sd-test` | **451 pemeriksaan LULUS** (+42): tata letak & NPC Engine, semua bangunan/model ada, mendaki bukit, menyeberang jembatan, tepi sungai & gerbang benteng menahan pemain, batas pulau, dialog 3 halaman, kalimat kedua berbeda, penduduk berjalan-jalan, catatan jelajah, perahu |
| `make platform-test` | **LULUS** (109 ok) |

Tangkapan layar diperiksa: desa dari dermaga, akademi di bukit, jembatan & benteng, gua.

### Catatan

- FPS di HP belum diukur (perlu HP). Profil Hemat disarankan untuk HP lama.
- Paket 3.1.0 belum diterbitkan (menunggu belajar, misi, pertarungan).
