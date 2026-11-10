extends RefCounted
## Profil performa per kualitas grafis (roadmap no. 246-251) dan alat ukur ringan (no. 251-255).
##
## Semua batas yang bergantung pada "Hemat / Normal / Tinggi" dikumpulkan di sini supaya mudah
## disetel tanpa mencari ke banyak skrip. Dipakai lewat `const Perf := preload("res://scripts/perf.gd")`.

## Indeks: 0 = Hemat, 1 = Normal, 2 = Tinggi.
const FPS_CAP := [30, 60, 60]                 # batas FPS: Hemat 30 supaya baterai awet dan HP tidak panas
const CAMERA_FAR := [60.0, 90.0, 110.0]       # jarak pandang kamera (petak)
const BANGUNAN_JARAK := [30.0, 42.0, 56.0]    # bangunan lebih jauh dari ini tidak digambar
const ROAM_MULT := [0.6, 1.0, 1.0]            # jumlah musuh berkeliaran dibanding isi peta
const WARGA_LOD_FAR := [12.0, 18.0, 24.0]     # warga lebih jauh dari ini diperbarui jarang
const ROAM_LOD_FAR := [11.0, 16.0, 22.0]      # musuh lebih jauh dari ini diperbarui jarang
const FX_MULT := [0.5, 1.0, 1.3]              # jumlah partikel efek (hujan, percikan, sihir)
const SHADOW_DIST := [0.0, 16.0, 26.0]        # 0 = tanpa bayangan
const SCALE_3D := [0.6, 0.75, 1.0]            # resolusi 3D relatif layar (UI tetap tajam)
const LIGHTS := [2, 5, 9]                     # lampu titik terdekat yang boleh menyala (malam, obor, tungku)


static func q() -> int:
	return clampi(int(Session.quality), 0, 2)


static func pick(table: Array) -> Variant:
	return table[q()]


## Jumlah partikel untuk efek dengan jumlah dasar `base` (minimal 1).
static func fx(base: int) -> int:
	return maxi(1, roundi(base * float(pick(FX_MULT))))


## Batas jumlah musuh berkeliaran untuk peta dengan isi `n`.
static func roam_cap(n: int) -> int:
	if n <= 0:
		return 0
	return maxi(1, ceili(n * float(pick(ROAM_MULT))))


## Potret angka performa saat ini (untuk lapisan FPS dan uji ketahanan).
static func snapshot() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"mem_mb": OS.get_static_memory_usage() / 1048576.0,
		"vmem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


## Teks singkat satu baris untuk lapisan FPS.
static func text(s: Dictionary) -> String:
	return "FPS %d · RAM %d MB · VRAM %d MB · Gambar %d · Node %d" % [
		int(s.fps), roundi(float(s.mem_mb)), roundi(float(s.vmem_mb)), int(s.draw), int(s.nodes)]
