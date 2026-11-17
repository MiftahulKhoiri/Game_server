extends SkeletonModifier3D
## Bentuk tubuh dari Character Creator (v0.82.0, diperbaiki v0.82.1): mengubah skala tulang SETELAH animasi
## diputar, jadi klip idle/jalan/lari/serang KayKit tetap dipakai apa adanya (tulang tidak diganti, hanya
## diperbesar/diperkecil). Rangka, animasi, dan hitbox tidak berubah: aturan gerak dan pertarungan dihitung dari
## petak di server, bukan dari ukuran model. Dipasang sebagai anak Skeleton3D oleh LookBuild.apply_body.
##
## Hasil SELALU dihitung dari skala dasar tulang, tidak pernah dari hasil frame sebelumnya:
## - Godot 4.7 mengembalikan pose ke hasil animasi setelah tiap pembaruan, jadi biasanya skala dasar = skala pose
##   saat modifier dipanggil.
## - Bila pose TIDAK dikembalikan (modifier dipanggil dua kali tanpa animasi di antaranya, tulang tanpa trek skala,
##   atau AnimationPlayer berhenti), skala yang terbaca adalah hasil kita sendiri. Itu dikenali dari _out, lalu
##   skala dasar yang tersimpan (_base) yang dipakai, sehingga skala tidak terus membesar/mengecil.

const NODE_NAME := "BentukTubuh"

## nama tulang -> Vector3 pengali skala (lokal tulang; sumbu Y = arah tulang).
var scales: Dictionary = {}
var _idx: Dictionary = {}   # nama tulang -> indeks
var _base: Dictionary = {}  # indeks -> skala dasar terakhir (sebelum dikalikan)
var _out: Dictionary = {}   # indeks -> skala yang terakhir kita tulis


func set_scales(s: Dictionary) -> void:
	scales = s
	_idx.clear()
	_base.clear()
	_out.clear()


## Skala dasar tulang `bone` yang dipakai pada pembaruan terakhir (untuk uji).
func base_of(bone: String) -> Vector3:
	return _base.get(int(_idx.get(bone, -1)), Vector3.ONE)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or scales.is_empty():
		return
	if _idx.is_empty():
		for b: String in scales:
			_idx[b] = sk.find_bone(b)
	for b: String in scales:
		var i := int(_idx.get(b, -1))
		if i < 0:
			continue
		var cur := sk.get_bone_pose_scale(i)
		var base := cur
		if _out.has(i) and cur.is_equal_approx(_out[i] as Vector3):
			base = _base[i]  # pose belum dikembalikan sejak tulisan terakhir: pakai skala dasar, bukan hasil kita
		var res := base * (scales[b] as Vector3)
		_base[i] = base
		_out[i] = res
		sk.set_bone_pose_scale(i, res)
