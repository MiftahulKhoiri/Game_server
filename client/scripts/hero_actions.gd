extends SkeletonModifier3D
## Gerakan tubuh pahlawan di dunia: tinju, tebas, tusuk, tendang, lompat, tangkis. Dipasang sebagai anak
## Skeleton3D rangka KayKit (tulang upperarm.r, upperleg.r, dst.), jadi dijalankan SETELAH AnimationPlayer:
## klip idle/jalan tetap jadi dasar, lalu tiap tulang diputar sebesar nilai kunci di bawah (radian, sumbu
## lokal tulang). Arah yang sudah diuji: upperarm x+ = lengan naik ke depan; upperleg x- = kaki naik ke
## depan; lowerleg x+ = lutut menekuk; spine x+ = badan condong ke depan.
##
## `k`: "tulang:sumbu" -> [[u, nilai], ...], u = 0..1 (bagian dari `dur` detik), nilai diinterpolasi halus.

const ACTIONS := {
	# Dua pukulan beruntun (kanan lalu kiri/perisai).
	"tinju": {"dur": 0.7, "k": {
		"upperarm.r:x": [[0, 0], [0.08, -0.6], [0.2, 0.8], [0.38, 0], [0.45, -0.6], [0.58, 0.8], [0.78, 0], [1, 0]],
		"upperarm.l:x": [[0, 0], [0.45, 0], [0.58, 0.55], [0.78, 0], [1, 0]],
		"spine:y": [[0, 0], [0.08, 0.3], [0.2, -0.3], [0.38, 0], [0.45, -0.3], [0.58, 0.3], [0.78, 0], [1, 0]],
		"spine:x": [[0, 0], [0.2, 0.2], [0.38, 0], [0.58, 0.2], [0.78, 0], [1, 0]],
	}},
	# Tebasan dari atas ke bawah, lalu tebasan menyamping.
	"tebas": {"dur": 0.9, "k": {
		"upperarm.r:x": [[0, 0], [0.12, 1.5], [0.3, -0.7], [0.42, 0], [0.5, 1.3], [0.62, 1.0], [0.75, -0.4], [0.9, 0], [1, 0]],
		"lowerarm.r:x": [[0, 0], [0.12, 0.5], [0.3, -0.3], [0.42, 0], [1, 0]],
		"spine:x": [[0, 0], [0.12, -0.2], [0.3, 0.4], [0.42, 0], [0.5, -0.1], [0.75, 0.2], [0.9, 0], [1, 0]],
		"spine:y": [[0, 0], [0.5, 0.5], [0.62, 0.5], [0.75, -0.6], [0.9, 0], [1, 0]],
	}},
	# Tusukan: tarik pedang, melangkah, lalu tusuk lurus ke depan.
	"tusuk": {"dur": 0.6, "k": {
		"upperarm.r:x": [[0, 0], [0.3, -0.6], [0.45, 0.35], [0.7, 0.35], [1, 0]],
		"lowerarm.r:x": [[0, 0], [0.3, -0.4], [0.45, 0.3], [0.7, 0.3], [1, 0]],
		"spine:y": [[0, 0], [0.3, 0.4], [0.45, -0.35], [0.7, -0.35], [1, 0]],
		"spine:x": [[0, 0], [0.45, 0.3], [0.7, 0.3], [1, 0]],
		"upperleg.r:x": [[0, 0], [0.3, 0.2], [0.45, -0.7], [0.75, -0.7], [1, 0]],
		"upperleg.l:x": [[0, 0], [0.45, 0.5], [0.75, 0.5], [1, 0]],
	}},
	# Satu tendangan kaki kanan.
	"tendang": {"dur": 0.5, "k": {
		"upperleg.r:x": [[0, 0], [0.3, -1.4], [0.5, -1.4], [1, 0]],
		"lowerleg.r:x": [[0, 0], [0.15, 0.8], [0.3, -0.1], [0.5, -0.1], [1, 0]],
		"upperleg.r:s": [[0, 0], [0.3, 0.45], [0.5, 0.45], [1, 0]],
		"lowerleg.r:s": [[0, 0], [0.3, 0.45], [0.5, 0.45], [1, 0]],
		"hips:x": [[0, 0], [0.3, -0.4], [0.5, -0.4], [1, 0]],
		"spine:x": [[0, 0], [0.3, -0.3], [0.5, -0.3], [1, 0]],
		"upperarm.r:x": [[0, 0], [0.3, -0.5], [1, 0]],
	}},
	# Tendangan dobel: kaki kanan lalu kaki kiri.
	"tendang2": {"dur": 0.95, "k": {
		"upperleg.r:x": [[0, 0], [0.15, -1.4], [0.27, -1.4], [0.42, 0], [1, 0]],
		"lowerleg.r:x": [[0, 0], [0.08, 0.8], [0.15, -0.1], [0.27, -0.1], [0.42, 0], [1, 0]],
		"upperleg.r:s": [[0, 0], [0.15, 0.45], [0.27, 0.45], [0.42, 0], [1, 0]],
		"lowerleg.r:s": [[0, 0], [0.15, 0.45], [0.27, 0.45], [0.42, 0], [1, 0]],
		"upperleg.l:x": [[0, 0], [0.5, 0], [0.65, -1.4], [0.77, -1.4], [0.95, 0], [1, 0]],
		"lowerleg.l:x": [[0, 0], [0.5, 0], [0.57, 0.8], [0.65, -0.1], [0.77, -0.1], [0.95, 0], [1, 0]],
		"upperleg.l:s": [[0, 0], [0.5, 0], [0.65, 0.45], [0.77, 0.45], [0.95, 0], [1, 0]],
		"lowerleg.l:s": [[0, 0], [0.5, 0], [0.65, 0.45], [0.77, 0.45], [0.95, 0], [1, 0]],
		"hips:x": [[0, 0], [0.15, -0.4], [0.27, -0.4], [0.42, 0], [0.65, -0.4], [0.77, -0.4], [0.95, 0], [1, 0]],
		"spine:x": [[0, 0], [0.15, -0.3], [0.42, 0], [0.65, -0.3], [0.95, 0], [1, 0]],
		"upperarm.r:x": [[0, 0], [0.15, -0.5], [0.42, -0.2], [0.65, -0.5], [0.95, 0], [1, 0]],
	}},
	# Lompat: kaki ditekuk ke atas, tangan terangkat.
	"lompat": {"dur": 0.75, "k": {
		"upperleg.r:x": [[0, 0], [0.15, 0.3], [0.3, -0.7], [0.65, -0.7], [0.85, 0.1], [1, 0]],
		"upperleg.l:x": [[0, 0], [0.15, 0.3], [0.3, -0.5], [0.65, -0.5], [0.85, 0.1], [1, 0]],
		"lowerleg.r:x": [[0, 0], [0.15, 0.5], [0.3, 0.8], [0.65, 0.8], [0.85, 0.2], [1, 0]],
		"lowerleg.l:x": [[0, 0], [0.15, 0.5], [0.3, 0.9], [0.65, 0.9], [0.85, 0.2], [1, 0]],
		"upperarm.r:x": [[0, 0], [0.15, -0.3], [0.3, 0.9], [0.65, 0.9], [0.9, 0], [1, 0]],
		"upperarm.l:x": [[0, 0], [0.15, -0.3], [0.3, 0.7], [0.65, 0.7], [0.9, 0], [1, 0]],
		"spine:x": [[0, 0], [0.15, 0.2], [0.3, -0.1], [0.65, -0.1], [1, 0]],
	}},
	# Mengambil barang (roadmap no. 13): jongkok, tangan kanan meraih ke bawah, lalu berdiri.
	"ambil": {"dur": 0.8, "k": {
		"upperleg.r:x": [[0, 0], [0.3, -0.9], [0.6, -0.9], [1, 0]],
		"upperleg.l:x": [[0, 0], [0.3, -0.5], [0.6, -0.5], [1, 0]],
		"lowerleg.r:x": [[0, 0], [0.3, 1.3], [0.6, 1.3], [1, 0]],
		"lowerleg.l:x": [[0, 0], [0.3, 1.1], [0.6, 1.1], [1, 0]],
		"hips:x": [[0, 0], [0.3, 0.15], [0.6, 0.15], [1, 0]],
		"spine:x": [[0, 0], [0.3, 0.55], [0.6, 0.55], [1, 0]],
		"upperarm.r:x": [[0, 0], [0.3, 0.6], [0.45, 0.75], [0.6, 0.4], [1, 0]],
		"lowerarm.r:x": [[0, 0], [0.3, -0.3], [0.6, -0.3], [1, 0]],
	}},
	# Berbicara (roadmap no. 34): tangan bergantian menunjuk dan membuka, kepala mengangguk.
	"bicara": {"dur": 1.6, "k": {
		"upperarm.r:x": [[0, 0], [0.15, 0.55], [0.35, 0.3], [0.5, 0.6], [0.7, 0.2], [1, 0]],
		"lowerarm.r:x": [[0, 0], [0.15, -0.6], [0.5, -0.7], [1, 0]],
		"upperarm.l:x": [[0, 0], [0.4, 0], [0.55, 0.45], [0.75, 0.3], [1, 0]],
		"lowerarm.l:x": [[0, 0], [0.55, -0.5], [1, 0]],
		"head:x": [[0, 0], [0.2, 0.15], [0.35, 0], [0.6, 0.12], [0.75, 0], [1, 0]],
		"spine:y": [[0, 0], [0.3, 0.12], [0.6, -0.1], [1, 0]],
	}},
	# Menempa (roadmap no. 35): angkat palu tinggi, pukul ke landasan.
	"palu": {"dur": 0.9, "k": {
		"upperarm.r:x": [[0, 0.3], [0.45, 1.7], [0.6, 0.25], [0.75, 0.35], [1, 0.3]],
		"lowerarm.r:x": [[0, -0.4], [0.45, -0.9], [0.6, -0.2], [1, -0.4]],
		"spine:x": [[0, 0.2], [0.45, -0.05], [0.6, 0.35], [1, 0.2]],
		"upperarm.l:x": [[0, 0.5], [1, 0.5]],
		"lowerarm.l:x": [[0, -0.6], [1, -0.6]],
	}},
	# Angkat perisai di depan wajah dan tahan.
	"tangkis": {"dur": 1.6, "k": {
		"upperarm.l:x": [[0, 0], [0.08, 1.2], [0.92, 1.2], [1, 0]],
		"lowerarm.r:x": [[0, 0], [0.08, -0.5], [0.92, -0.5], [1, 0]],
		"spine:x": [[0, 0], [0.08, 0.12], [0.92, 0.12], [1, 0]],
	}},
}

const AXIS := {"x": 0, "y": 1, "z": 2}

## Pose diam (roadmap no. 36): putaran tulang tetap selama pose aktif. Tinggi badan diatur model_rig.
const POSES := {
	"duduk": {"upperleg.r": Vector3(-1.45, 0, 0), "upperleg.l": Vector3(-1.45, 0, 0),
		"lowerleg.r": Vector3(1.45, 0, 0), "lowerleg.l": Vector3(1.45, 0, 0),
		"upperarm.r": Vector3(0.35, 0, 0), "upperarm.l": Vector3(0.35, 0, 0),
		"lowerarm.r": Vector3(-0.5, 0, 0), "lowerarm.l": Vector3(-0.5, 0, 0)},
	# Tidur (no. 38): badan direbahkan oleh model_rig; lengan di sisi badan, kepala sedikit miring.
	"tidur": {"upperarm.r": Vector3(0, 0, 0.9), "upperarm.l": Vector3(0, 0, -0.9), "head": Vector3(0, 0.35, 0)},
}

var _name := ""
var _t := 0.0
var _dur := 1.0
## Condong lari (roadmap no. 7), 0..1: badan condong ke depan dan lengan mengayun lebih tinggi.
## Berlaku di atas klip jalan selama tidak ada gerakan lain.
var lean := 0.0
var _lean_t := 0.0
## Pose diam yang sedang dipakai (kunci POSES) atau "".
var pose := ""


func _ready() -> void:
	active = false


## Mulai gerakan `action`. false bila namanya tidak dikenal.
func play(action: String) -> bool:
	if not ACTIONS.has(action):
		return false
	_name = action
	_t = 0.0
	_dur = float((ACTIONS[action] as Dictionary).dur)
	active = true
	return true


## Hentikan gerakan sekarang (tubuh kembali ke klip idle/jalan).
func stop() -> void:
	_name = ""
	active = lean > 0.01 or pose != ""


func current() -> String:
	return _name


func _process(delta: float) -> void:
	_lean_t += delta
	if _name == "":
		active = lean > 0.01 or pose != ""
		return
	_t += delta
	if _t >= _dur:
		stop()


## Nilai kunci pada waktu u (0..1): interpolasi halus antar kunci.
static func sample(keys: Array, u: float) -> float:
	var n := keys.size()
	if n == 0:
		return 0.0
	if u <= float((keys[0] as Array)[0]):
		return float((keys[0] as Array)[1])
	for i in range(1, n):
		var b: Array = keys[i]
		if u <= float(b[0]):
			var a: Array = keys[i - 1]
			var span := float(b[0]) - float(a[0])
			var w := 0.0 if span <= 0.0 else (u - float(a[0])) / span
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, w))
	return float((keys[n - 1] as Array)[1])


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _name == "":
		_apply_pose(sk)
		_apply_lean(sk)
		return
	var u := clampf(_t / _dur, 0.0, 1.0)
	var keys: Dictionary = (ACTIONS[_name] as Dictionary).k
	var deltas: Dictionary = {}
	var scales: Dictionary = {}
	for key: String in keys:
		var parts := key.split(":")
		if parts[1] == "s":
			scales[parts[0]] = 1.0 + sample(keys[key], u)
			continue
		var d: Vector3 = deltas.get(parts[0], Vector3.ZERO)
		d[int(AXIS[parts[1]])] += sample(keys[key], u)
		deltas[parts[0]] = d
	for bone: String in scales:
		var si := sk.find_bone(bone)
		if si >= 0:
			sk.set_bone_pose_scale(si, Vector3.ONE * float(scales[bone]))
	for bone: String in deltas:
		var i := sk.find_bone(bone)
		if i < 0:
			continue
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion.from_euler(deltas[bone]))


## Lari: tulang belakang condong ke depan, lengan mengayun lebih lebar mengikuti irama langkah.
func _apply_lean(sk: Skeleton3D) -> void:
	if lean <= 0.01:
		return
	var swing := sin(_lean_t * 11.0) * 0.45 * lean
	for pair: Array in [["spine", Vector3(0.28 * lean, 0, 0)], ["upperarm.r", Vector3(swing, 0, 0)],
			["upperarm.l", Vector3(-swing, 0, 0)], ["lowerarm.r", Vector3(-0.5 * lean, 0, 0)], ["lowerarm.l", Vector3(-0.5 * lean, 0, 0)]]:
		var i := sk.find_bone(str(pair[0]))
		if i >= 0:
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion.from_euler(pair[1]))


func _apply_pose(sk: Skeleton3D) -> void:
	if pose == "" or not POSES.has(pose):
		return
	var rot: Dictionary = POSES[pose]
	for bone: String in rot:
		var i := sk.find_bone(bone)
		if i >= 0:
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion.from_euler(rot[bone]))
