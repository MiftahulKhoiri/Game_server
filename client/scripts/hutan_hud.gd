extends Control
## Papan misi Hutan Lebat di layar dunia: jumlah binatang yang sudah dikalahkan (X/100 dengan bar), kemajuan
## Goblin (0-3), dan tiga panah penunjuk arah (singgasana bos, gerbang Gua Goblin, kem/jalan pulang) lengkap
## dengan jaraknya. Panah berputar mengikuti arah kamera supaya selalu menunjuk lurus ke tujuan di layar.

const Maps = preload("res://scripts/maps.gd")

const PANEL_SIZE := Vector2(412, 150)
const KEM_POINT := Vector2(22.5, 1.5)       # titik pulang: pintu masuk hutan (ke kem di Perbatasan)
const GATE_POINT := Vector2(147.0, 48.5)    # gerbang Gua Goblin

var kills := 0
var wave := 0
var player := Vector2.ZERO
var cam_yaw := 0.0
var started := true      # sudah bicara dengan Kapten Rimba; bila belum, papan menyuruh menemuinya


func _init() -> void:
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sudut panah (radian, searah jarum jam dari atas layar) ke `target`, dilihat dari kamera berarah `yaw`.
static func arrow_angle(from: Vector2, target: Vector2, yaw: float) -> float:
	var d := target - from
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return atan2(d.dot(right), d.dot(fwd))


func update_view(k: int, w: int, p: Vector2, yaw: float, briefed := true) -> void:
	started = briefed
	kills = k
	wave = w
	player = p
	cam_yaw = yaw
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_style_box(_box(Color(0.05, 0.08, 0.05, 0.62)), Rect2(Vector2.ZERO, PANEL_SIZE))
	var gold := Color("ffe27a")
	var title: String
	if not started:
		title = "Temui Kapten Rimba"
	elif wave >= 3:
		title = "Ketiga Goblin kalah!"
	elif kills >= 100:
		title = "Goblin Level %d menunggu!" % (wave + 1)
	else:
		title = "Binatang %d / 100" % kills
	_text(font, title, Vector2(14, 32), 30, gold)
	# bar kemajuan binatang
	var ratio := 1.0 if (wave >= 3 or kills >= 100) else clampf(float(kills) / 100.0, 0.0, 1.0)
	draw_rect(Rect2(14, 42, PANEL_SIZE.x - 28, 12), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(14, 42, (PANEL_SIZE.x - 28) * ratio, 12), Color("62d04a") if ratio < 1.0 else Color("ffb020"))
	var sub := "Dia menjaga kem di Perbatasan" if not started else "Gerbang Gua Goblin terbuka" if wave >= 3 else "Goblin Level %d  -  kalah %d dari 3" % [wave + 1, wave]
	_text(font, sub, Vector2(14, 80), 22, Color("ffd7c0"))
	# tiga penunjuk arah
	var items: Array = []
	if wave < 3 and started:
		items.append(["Singgasana", Vector2(float(Maps.HUTAN_BOSS.x) + 0.5, float(Maps.HUTAN_BOSS.y) + 0.5), Color("ff8a5c")])
	if started:
		items.append(["Gerbang Gua", GATE_POINT, Color("ffe27a") if wave >= 3 else Color("9a9a9a")])
	items.append(["Pulang", KEM_POINT, Color("8fe08f")])
	var col_w := (PANEL_SIZE.x - 20.0) / float(items.size())
	for i in items.size():
		var cx := 10.0 + col_w * (float(i) + 0.5)
		var tgt: Vector2 = items[i][1]
		var col: Color = items[i][2]
		_arrow(Vector2(cx, 108), arrow_angle(player, tgt, cam_yaw), col)
		var name_w := font.get_string_size(str(items[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		_text(font, str(items[i][0]), Vector2(cx - name_w / 2.0, 138), 17, col)
		var dist := "%d" % int(round(player.distance_to(tgt)))
		_text(font, dist, Vector2(cx + 22, 114), 20, Color.WHITE)


func _box(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(2)
	return sb


func _text(font: Font, t: String, at: Vector2, fs: int, col: Color) -> void:
	draw_string_outline(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, 0.9))
	draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _arrow(c: Vector2, ang: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in [Vector2(0, -17), Vector2(13, 13), Vector2(0, 6), Vector2(-13, 13)]:
		pts.append(c + p.rotated(ang))
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.9), 2.5)
