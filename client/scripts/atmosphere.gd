extends RefCounted
## Dunia hidup: siklus siang-malam dan cuaca (hujan). Murni di klien, tidak memengaruhi
## server maupun jalannya permainan. Dipakai bersama oleh dunia dan arena pertarungan,
## jadi suasana di keduanya selalu sama.
##
## Waktu berjalan dari jam aplikasi (bukan jam HP) sehingga tidak bergantung pada kapan
## pemain bermain, dan tetap lanjut saat pindah layar. Satu hari permainan = DAY_SECONDS.
## Cuaca ditentukan dari "blok waktu": tiap WEATHER_BLOCK_S detik hujan atau cerah, diundi
## dari nomor blok (tanpa data tersimpan). Gua Batu tidak terpengaruh.

const Maps = preload("res://scripts/maps.gd")

const DAY_SECONDS := 720.0      # 12 menit nyata = 24 jam permainan
const START_HOUR := 8.0         # permainan dimulai pagi hari
const WEATHER_BLOCK_S := 150.0  # lama satu "blok" cuaca
const NIGHT_FROM := 19.0       # warga masuk rumah
const NIGHT_TO := 5.0          # warga keluar lagi
const RAIN_PERCENT := 30        # peluang sebuah blok hujan (blok pertama selalu cerah)
const RAIN_BLEND_S := 8.0       # lama peralihan cerah <-> hujan

const NIGHT_TOP := Color("0a1230")
const NIGHT_HORIZON := Color("1d2a50")
const NIGHT_GROUND := Color("0d1424")
const NIGHT_AMBIENT := Color("7585c8")
const NIGHT_AMBIENT_ENERGY := 0.9   # cukup terang supaya malam tetap bisa dimainkan
const MOON_COLOR := Color("9bb4ff")
const MOON_ENERGY := 0.3
const TWILIGHT := Color("ff9a5a")
const RAIN_TOP := Color("56606c")
const RAIN_HORIZON := Color("8e98a2")
const DEFAULT_SUN_ROT := Vector3(-0.9076, -0.6109, 0.0)  # -52 dan -35 derajat

## Kekuatan hujan sekarang, 0 (cerah) sampai 1 (deras). Berlanjut antar layar.
static var rain := 0.0


## Hanya untuk uji: bila >= 0, dipakai sebagai jam permainan.
static var hour_override := -1.0


## Jam permainan sekarang, 0.0 sampai 24.0.
static func hour() -> float:
	if hour_override >= 0.0:
		return hour_override
	return fposmod(START_HOUR + float(Time.get_ticks_msec()) / 1000.0 / DAY_SECONDS * 24.0, 24.0)


## Kekuatan malam untuk lampu: 0 siang .. 1 malam penuh (mengikuti langit di apply()). Gua punya obor sendiri.
static func night() -> float:
	var s := sin((hour() - 6.0) / 24.0 * TAU)
	return 1.0 - smoothstep(-0.15, 0.4, s)


## Waktu warga desa masuk rumah: dari jam 19.00 sampai 05.00.
static func is_night() -> bool:
	var h := hour()
	return h >= NIGHT_FROM or h < NIGHT_TO


## Hujan sedang/akan turun pada blok waktu ini?
static func raining_now() -> bool:
	var block := int(float(Time.get_ticks_msec()) / 1000.0 / WEATHER_BLOCK_S)
	if block == 0:
		return false
	return absi(hash(block * 7919 + 13)) % 100 < RAIN_PERCENT


## Majukan peralihan cuaca; dipanggil tiap bingkai oleh layar yang menampilkan dunia.
static func tick(delta: float) -> void:
	rain = move_toward(rain, 1.0 if raining_now() else 0.0, delta / RAIN_BLEND_S)


static func outdoors(map_id: String) -> bool:
	return map_id != Maps.GUA and not Maps.is_interior(map_id)


## Nama waktu untuk ditampilkan, mis. "Sore, hujan".
static func label() -> String:
	var h := hour()
	var part := "Malam"
	if h >= 5.0 and h < 10.0:
		part = "Pagi"
	elif h >= 10.0 and h < 15.0:
		part = "Siang"
	elif h >= 15.0 and h < 18.5:
		part = "Sore"
	var text := "%s %02d:%02d" % [part, int(h), int((h - floorf(h)) * 60.0)]
	return text + (", hujan" if rain > 0.5 else "")


## Simpan nilai dasar (suasana per peta dari world_build.gd) sebelum diubah oleh apply().
static func capture(env: Environment, sun: DirectionalLight3D) -> Dictionary:
	var mat := env.sky.sky_material as ProceduralSkyMaterial
	return {
		"top": mat.sky_top_color,
		"horizon": mat.sky_horizon_color,
		"ground": mat.ground_bottom_color,
		"ambient_color": env.ambient_light_color,
		"ambient_energy": env.ambient_light_energy,
		"fog_density": env.fog_density,
		"saturation": env.adjustment_saturation,
		"sun_energy": sun.light_energy,
		"sun_color": sun.light_color,
	}


## Terapkan waktu dan cuaca sekarang ke lingkungan dan matahari. `base` dari capture().
static func apply(env: Environment, sun: DirectionalLight3D, base: Dictionary, map_id: String) -> void:
	if base.is_empty():
		return
	if not outdoors(map_id):
		sun.rotation = DEFAULT_SUN_ROT
		return
	var h := hour()
	# s: ketinggian matahari (-1 tengah malam, 0 terbit/terbenam, 1 tengah hari).
	var s := sin((h - 6.0) / 24.0 * TAU)
	var d := smoothstep(-0.15, 0.4, s)               # 0 malam, 1 siang
	var tw := clampf(1.0 - absf(s) / 0.28, 0.0, 1.0)  # kuat di fajar/senja
	var r := rain

	var top: Color = NIGHT_TOP.lerp(base.top, d)
	var hor: Color = NIGHT_HORIZON.lerp(base.horizon, d).lerp(TWILIGHT, tw * 0.55)
	var ground: Color = NIGHT_GROUND.lerp(base.ground, d)
	if r > 0.0:
		top = top.lerp(RAIN_TOP.lerp(NIGHT_TOP, 1.0 - d), r * 0.8)
		hor = hor.lerp(RAIN_HORIZON.lerp(NIGHT_HORIZON, 1.0 - d), r * 0.8)
	var mat := env.sky.sky_material as ProceduralSkyMaterial
	mat.sky_top_color = top
	mat.sky_horizon_color = hor
	mat.ground_horizon_color = hor
	mat.ground_bottom_color = ground

	env.ambient_light_color = NIGHT_AMBIENT.lerp(base.ambient_color, d)
	env.ambient_light_energy = lerpf(NIGHT_AMBIENT_ENERGY, float(base.ambient_energy), d)
	env.fog_light_color = hor
	env.fog_density = float(base.fog_density) * (1.0 + 0.8 * (1.0 - d) + 1.6 * r)
	env.adjustment_saturation = float(base.saturation) * (1.0 - 0.25 * r)

	var sun_day: float = float(base.sun_energy) * (1.0 - 0.55 * r)
	sun.light_energy = lerpf(MOON_ENERGY, sun_day, d)
	var sun_color: Color = MOON_COLOR.lerp(base.sun_color, d).lerp(TWILIGHT, tw * 0.5)
	sun.light_color = sun_color
	var pitch := lerpf(-14.0, -58.0, d)
	var yaw := -35.0 + (h - 12.0) * 6.0
	sun.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)


## Pemancar hujan. Taruh di atas pemain/arena (dunia, bukan lokal) dan nyalakan lewat set_rain().
static func make_rain(extents: Vector3, amount: int) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.9, 1.0, 0.6)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.022, 0.5, 0.022)
	mesh.material = mat
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = 0.65
	p.preprocess = 0.65
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.DOWN
	p.spread = 3.0
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = 11.0
	p.initial_velocity_max = 13.0
	p.emitting = false
	return p


## Jumlah tetesan menurut kualitas grafis (0 hemat, 1 normal, 2 tinggi).
static func rain_amount(quality: int) -> int:
	return [150, 320, 450][clampi(quality, 0, 2)]


## Nyalakan/matikan hujan sesuai kekuatan hujan sekarang.
static func set_rain(p: CPUParticles3D, map_id: String) -> void:
	if p != null and is_instance_valid(p):
		p.emitting = outdoors(map_id) and rain > 0.3
