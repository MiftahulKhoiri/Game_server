extends SkeletonModifier3D
## Bentuk tubuh dari Character Creator (v0.82.0): mengalikan skala tulang SETELAH animasi diputar, jadi
## klip idle/jalan/serang KayKit tetap dipakai apa adanya (tulang tidak diganti, hanya diperbesar/diperkecil).
## Rangka, animasi, dan hitbox tidak berubah: aturan gerak dan pertarungan dihitung dari petak di server,
## bukan dari ukuran model. Dipasang sebagai anak Skeleton3D oleh LookBuild.apply_body.

const NODE_NAME := "BentukTubuh"

## nama tulang -> Vector3 pengali skala (lokal tulang; sumbu Y = arah tulang).
var scales: Dictionary = {}
var _idx: Dictionary = {}


func set_scales(s: Dictionary) -> void:
	scales = s
	_idx.clear()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or scales.is_empty():
		return
	if _idx.is_empty():
		for b: String in scales:
			_idx[b] = sk.find_bone(b)
	for b: String in scales:
		var i := int(_idx.get(b, -1))
		if i >= 0:
			sk.set_bone_pose_scale(i, sk.get_bone_pose_scale(i) * (scales[b] as Vector3))
