# Aturan Kematian Musuh dan Pahlawan Pendamping

Dokumen ini menetapkan aturan gameplay untuk implementasi sistem NPC/pendamping. Server tetap menjadi sumber kebenaran untuk HP, kematian, penggunaan item, dan hasil pertarungan; klien Godot hanya menampilkan keadaan dan mengirim aksi.

## Keputusan gameplay

1. **Musuh dapat mati.** Ketika HP musuh mencapai 0, statusnya menjadi mati, serangan dihentikan, hadiah hanya diberikan satu kali, dan entitas musuh tidak boleh terus menyerang atau mengejar pemain.
2. **Pahlawan pendamping dapat tumbang/mati.** Setiap pendamping yang direkrut dan aktif mempunyai HP sendiri. Jika HP mencapai 0, pendamping berstatus tumbang, berhenti mengikuti pemain, berhenti menyerang, dan tidak dihitung sebagai penyerang aktif.
3. **Pendamping dapat disembuhkan dengan ramuan kesehatan.** Item kesehatan yang digunakan untuk pendamping harus mengurangi jumlah item di inventaris tepat satu kali dan memulihkan HP pendamping sampai batas HP maksimum. Pendamping yang tumbang dapat dihidupkan kembali oleh ramuan; HP hasil pemulihan harus positif.
4. **Penduduk, pedagang, pemberi misi, dan NPC layanan tidak dapat dibunuh oleh sistem pertarungan.** Mereka tidak menjadi target serangan dan tidak ikut menerima damage. Aturan ini menjaga fungsi toko, dialog, dan misi.
5. **Prajurit biasa dan pahlawan pendamping dibedakan.** Implementasi awal berfokus pada pahlawan yang tercatat di party. Sistem prajurit biasa tidak boleh ikut berubah perilakunya sebelum skema HP-nya ditentukan.
6. **Pemain tetap mengikuti aturan HP pemain yang sudah ada.** Penambahan HP pendamping tidak boleh mengubah alur kalah/pulang ke desa milik pemain.

## Aturan penggunaan ramuan

- Aksi penggunaan ramuan untuk pendamping harus menyebutkan ID pendamping yang menjadi target.
- Server memvalidasi bahwa target merupakan anggota party milik pemain.
- Server menolak penggunaan jika item tidak tersedia, target tidak ditemukan, atau target sudah memiliki HP penuh.
- Server mengurangi item dan memperbarui HP pendamping dalam satu operasi penyimpanan yang sama.
- Klien memperbarui tampilan party hanya dari respons server, bukan mengubah HP secara lokal.
- Untuk menghindari perilaku tak terduga pada API lama, aksi ramuan pemain yang sudah ada tetap dipertahankan. Aksi pemulihan pendamping ditambahkan secara kompatibel, bukan mengganti arti aksi `potion` lama tanpa migrasi API.

## Perilaku pendamping

| Kondisi | Mengikuti pemain | Menyerang | Bisa disembuhkan |
|---|---:|---:|---:|
| Sehat | Ya | Ya | Ya, jika HP belum penuh |
| Terluka | Ya | Ya | Ya |
| Tumbang (HP 0) | Tidak | Tidak | Ya |
| Tidak ada di party | Tidak | Tidak | Tidak |

Saat pulih, pendamping kembali aktif dan masuk lagi ke formasi mengikuti urutan party.

## Temuan implementasi saat ini

- `client/scripts/companions.gd` membuat model pendamping dari `Session.player.state.party` dan membuat semua anggota party mengikuti pemain.
- `internal/game/battle.go` saat ini menjalankan serangan pendamping secara otomatis melalui `allyStrike`; pendamping belum memiliki HP individual dalam data pertarungan yang dibaca pada audit ini.
- `ActionPotion` di `internal/game/battle.go` saat ini menyembuhkan HP pemain dan mengonsumsi item `ramuan`.
- `client/scripts/world_fight.gd` dan `client/scripts/battle.gd` menampilkan event serangan/penyembuhan dari server.
- Karena data party, penyimpanan pemain, dan API aksi berada di sisi server, fitur kematian/penyembuhan pendamping tidak aman jika hanya dibuat di GDScript.

## Urutan implementasi

1. Tambahkan data HP/max HP/status untuk setiap pahlawan pendamping pada model state server, dengan default aman untuk data pemain lama.
2. Tambahkan validasi dan tes unit untuk migrasi/default HP, pendamping sehat, pendamping tumbang, dan validasi anggota party.
3. Ubah resolusi pertarungan server agar hanya pendamping sehat yang menyerang dan agar damage musuh dapat menumbangkan pendamping sesuai aturan target yang ditetapkan.
4. Tambahkan aksi API terpisah untuk menggunakan ramuan pada pendamping; pertahankan aksi `potion` yang menyembuhkan pemain.
5. Kirim status HP pendamping pada respons API dan sinkronkan tampilan klien.
6. Perbarui `client/scripts/companions.gd` agar pendamping tumbang tidak mengikuti/menyerang dan kembali aktif setelah disembuhkan.
7. Tambahkan UI pemilihan target ramuan pendamping dan indikator HP/status.
8. Jalankan seluruh tes Go, pemeriksaan proyek Godot headless jika tersedia, dan uji alur Android.

## Batas keselamatan perubahan

- Jangan mengubah atau menghapus aset model, scene, dialog, toko, atau misi yang sudah ada tanpa kebutuhan yang terbukti.
- Jangan mengubah kontrak API lama secara diam-diam.
- Jangan memberikan hadiah musuh lebih dari sekali.
- Semua perubahan HP, status tumbang, dan inventaris harus divalidasi serta disimpan di server.
- Implementasi dianggap selesai hanya setelah tes otomatis dan pemeriksaan kompatibilitas berhasil.