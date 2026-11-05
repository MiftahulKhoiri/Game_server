# Penandatanganan APK (debug)

`debug.keystore` adalah kunci **debug publik** (sandi `android`, alias
`androiddebugkey`), sengaja ada di repo. Fungsinya satu: semua APK uji yang
dibangun CI ditandatangani kunci yang sama, sehingga APK baru bisa dipasang
**menimpa** yang lama tanpa menghapus aplikasi. Menghapus aplikasi berarti
menghapus token login di HP, dan akun tidak bisa dipulihkan.

Kunci ini **tidak rahasia dan tidak boleh dipakai untuk rilis** (mis. Play
Store). Untuk rilis nanti, buat keystore baru, simpan sebagai GitHub Secret,
dan jangan pernah commit ke repo.
