extends RefCounted
## Tata letak nama NPC/warga di atas kepala (perbaikan dari uji Samsung A50):
## - ukuran di layar kira-kira tetap: nama yang dekat kamera tidak lagi membesar, yang jauh tidak mengecil;
## - nama yang jauh disembunyikan;
## - nama yang bertabrakan: yang lebih dekat menang, yang lain cukup nama (tanpa peran) atau disembunyikan;
## - nama tidak tertutup tombol konteks (Bicara/Buka peti), kecuali milik orang yang diajak bicara.
## Dijalankan beberapa kali per detik dari world3d, bukan tiap frame.

const FAR := 20.0          # lebih jauh dari ini (meter/petak dari kamera) nama tidak digambar
const REF_DIST := 7.0      # jarak kamera biasa; di sini skala = 1
const MIN_SCALE := 0.7
const MAX_SCALE := 1.4
const GAP := 4.0           # jarak minimal antarnama di layar (piksel)

var entries: Array = []    # {label: Label3D, full: String, short: String}
var debug := false         # true: catat alasan tiap nama disembunyikan (alat uji tests/shot.gd)
var reasons := {}


func clear() -> void:
	entries.clear()


## Daftarkan label nama. `full` = "Nama\nPeran", `short` = "Nama".
func add(label: Label3D, full: String, short: String) -> void:
	label.set_meta("nama_penuh", full)
	label.set_meta("nama_pendek", short)
	entries.append({"label": label, "full": full, "short": short})


## Teks dasar label (dipakai juga saat menambah "Zzz").
static func suffix(label: Label3D) -> String:
	return "  Zzz" if bool(label.get_meta("zzz", false)) else ""


## Susun ulang semua nama. `obstacle` = kotak tombol konteks di layar (Rect2() bila tidak ada);
## `owner_label` = label milik orang yang ditunjuk tombol itu (tidak disembunyikan oleh tombolnya).
## `hud` = kotak elemen HUD di layar (nama di belakangnya tidak terbaca: disembunyikan).
func layout(camera: Camera3D, obstacle: Rect2, owner_label: Label3D, hud: Array = []) -> void:
	if camera == null:
		return
	var cam_pos := camera.global_position
	var live: Array = []
	for e: Dictionary in entries:
		var l: Label3D = e.label
		if not is_instance_valid(l):
			continue
		var parent := l.get_parent() as Node3D
		if parent == null or not parent.is_visible_in_tree():
			continue
		var d := cam_pos.distance_to(l.global_position)
		if d > FAR or camera.is_position_behind(l.global_position):
			l.visible = false
			if debug:
				reasons[e.short] = "jauh %.1f" % d
			continue
		live.append([d, e])
	live.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var screen := camera.get_viewport().get_visible_rect()
	reasons.clear()
	var placed: Array[Rect2] = []
	for item: Array in live:
		var d: float = item[0]
		var e: Dictionary = item[1]
		var l: Label3D = e.label
		var s := clampf(d / REF_DIST, MIN_SCALE, MAX_SCALE)
		l.scale = Vector3.ONE * s
		l.visible = true
		var chosen := ""
		for text: String in ([e.full, e.short] if e.full != e.short else [e.full]):
			var r := _screen_rect(camera, l, text, s)
			var blocked := not screen.encloses(r)  # terpotong tepi layar
			blocked = blocked or (l != owner_label and obstacle.has_area() and r.intersects(obstacle))
			for hr: Rect2 in hud:
				if blocked:
					break
				blocked = r.intersects(hr)
			if not blocked:
				for p in placed:
					if r.grow(GAP).intersects(p):
						blocked = true
						break
			if not blocked:
				chosen = text
				placed.append(r)
				break
		if chosen == "":
			l.visible = false
			if not debug:
				continue
			var why := []
			var rr := _screen_rect(camera, l, e.short, s)
			if not screen.encloses(rr):
				why.append("tepi")
			if obstacle.has_area() and rr.intersects(obstacle):
				why.append("tombol")
			for hr: Rect2 in hud:
				if rr.intersects(hr):
					why.append("hud %s" % hr)
			for p in placed:
				if rr.grow(GAP).intersects(p):
					why.append("nama lain %s" % p)
			reasons[e.short] = "%s %s" % [rr, why]
		else:
			l.text = chosen + suffix(l)


## Gelembung kalimat warga: dibuat tembus pandang bila tertimpa HUD (tetap berjalan seperti biasa).
static func fade_bubbles(camera: Camera3D, bubbles: Array, hud: Array) -> void:
	for b in bubbles:
		var l := b as Label3D
		if l == null or not is_instance_valid(l) or not l.is_visible_in_tree():
			continue
		var r := _screen_rect(camera, l, l.text, l.scale.x)
		var hit := false
		for hr: Rect2 in hud:
			if r.intersects(hr):
				hit = true
				break
		var a := 0.0 if hit else 1.0
		l.modulate.a = a
		l.outline_modulate.a = a


## Perkiraan kotak teks label di layar.
static func _screen_rect(camera: Camera3D, l: Label3D, text: String, s: float) -> Rect2:
	var lines := text.split("\n")
	var longest := 0
	for ln in lines:
		longest = maxi(longest, ln.length())
	var h := l.font_size * l.pixel_size * s * lines.size() * 1.15
	var w := l.font_size * l.pixel_size * s * longest * 0.55
	var c := l.global_position
	var basis := camera.global_transform.basis
	var p0 := camera.unproject_position(c - basis.x * (w * 0.5) - basis.y * (h * 0.5))
	var p1 := camera.unproject_position(c + basis.x * (w * 0.5) + basis.y * (h * 0.5))
	return Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), (p1 - p0).abs())
