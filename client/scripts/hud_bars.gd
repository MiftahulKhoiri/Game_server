extends Control
## Tampilan pemain di pojok kiri atas, digambar dengan kode:
##   bagus                            <- nama pemain, di atas level
##   (tropi) [=====xp======     ]     <- piala bernomor level, bar poin menuju level berikutnya
##    (+)    [=====nyawa=====   ]     <- tanda + merah, bar nyawa bergerak sesuai persentase
##    (petir)[=====energi====    ]     <- ikon petir, bar energi (kekuatan jurus)
##   (berlian) 3                      <- jumlah berlian (item tertinggi, bisa ditukar apa saja)
##   (koin) 47                        <- jumlah emas
## Poin (XP) didapat dari mengalahkan monster. Warna bar nyawa berubah seperti baterai:
## hijau stabilo saat penuh, lalu kuning, oranye, merah saat menipis. Nyawa turun/naik dengan
## gerak halus, bar putih tipis menyusul di belakang saat nyawa berkurang; di bawah 30% berdenyut.

const FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")  # font game (SIL OFL)
const BAR_X := 54.0
const BAR_W := 216.0   # bar berakhir di x=270 supaya tidak menyentuh jam di sebelah kanan
const NAME_H := 30.0   # tinggi baris nama pemain di paling atas
# Tiap baris punya ikon bulat/piala setinggi 30-38 px di kolom kiri; jarak antar baris diatur agar ikon tidak
# saling menumpuk (piala 32..70, tanda + 73..111, petir 114..152, berlian 155..185, koin 188..218).
const XP_Y := 42.0
const XP_H := 18.0
const HP_Y := 79.0
const HP_H := 26.0
const EN_Y := 123.0    # bar energi (petir) di bawah bar nyawa
const EN_H := 20.0
const DIA_Y := 170.0   # titik tengah baris berlian (di atas koin emas)
const COIN_Y := 203.0  # titik tengah baris koin emas
const EN_COLOR := Color("ffc61a")
const NAME_FILL := Color("ffd45e")     # nama pemain: emas hangat...
const NAME_EDGE := Color("7a2d0a")     # ...dengan tepi cokelat tua
const LOW := 0.3
# Warna bar nyawa menurut persentase (seperti ikon baterai): [persen, warna], dari kosong ke penuh.
const HP_STOPS := [
	[0.0, Color("e02020")],
	[0.25, Color("ff7a1a")],
	[0.5, Color("ffd91f")],
	[0.75, Color("a8e81c")],
	[1.0, Color("45ec1c")],
]

var level := 1
var xp := 0
var xp_need := 20
var hp := 30
var max_hp := 30
var player_name := ""
var gold := 0
var diamonds := 0
var energy := 100
var max_energy := 100

var _hp_show := 1.0    # persentase nyawa yang digambar (menyusul target dengan halus)
var _hp_chip := 1.0    # bar putih yang menyusul lebih lambat saat nyawa berkurang
var _xp_show := 0.0
var _en_show := 1.0
var _en_init := false
var _init_done := false
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BAR_X + BAR_W + 8.0, COIN_Y + 22.0)
	size = custom_minimum_size


## Memperbarui nilai. Panggilan pertama langsung memakai nilainya tanpa animasi.
func set_values(new_level: int, new_xp: int, new_xp_need: int, new_hp: int, new_max_hp: int) -> void:
	level = new_level
	xp = new_xp
	xp_need = maxi(1, new_xp_need)
	hp = new_hp
	max_hp = maxi(1, new_max_hp)
	if not _init_done:
		_init_done = true
		_hp_show = hp_fraction()
		_hp_chip = _hp_show
		_xp_show = xp_fraction()
	set_process(true)
	queue_redraw()


## Energi (kekuatan jurus), digambar sebagai bar di bawah bar nyawa.
func set_energy(new_energy: int, new_max: int) -> void:
	max_energy = maxi(1, new_max)
	energy = clampi(new_energy, 0, max_energy)
	if not _en_init:
		_en_init = true
		_en_show = energy_fraction()
	set_process(true)
	queue_redraw()


func energy_fraction() -> float:
	return clampf(float(energy) / float(max_energy), 0.0, 1.0)


## Nama pemain (di atas level), jumlah emas (di samping koin) dan jumlah berlian (di atas koin).
func set_identity(new_name: String, new_gold: int, new_diamonds := 0) -> void:
	player_name = new_name
	gold = new_gold
	diamonds = new_diamonds
	queue_redraw()


## Warna bar nyawa untuk persentase 0..1: hijau stabilo (penuh) -> kuning -> oranye -> merah.
static func hp_color(fraction: float) -> Color:
	var f := clampf(fraction, 0.0, 1.0)
	for i in range(1, HP_STOPS.size()):
		var hi: Array = HP_STOPS[i]
		if f <= float(hi[0]):
			var lo: Array = HP_STOPS[i - 1]
			var t := (f - float(lo[0])) / (float(hi[0]) - float(lo[0]))
			return (lo[1] as Color).lerp(hi[1] as Color, t)
	return HP_STOPS[HP_STOPS.size() - 1][1]


func hp_fraction() -> float:
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


func xp_fraction() -> float:
	return clampf(float(xp) / float(xp_need), 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	var want := hp_fraction()
	_hp_show = move_toward(_hp_show, want, delta * 0.9)
	if _hp_chip > _hp_show:
		_hp_chip = move_toward(_hp_chip, _hp_show, delta * 0.35)
	else:
		_hp_chip = _hp_show
	_xp_show = move_toward(_xp_show, xp_fraction(), delta * 0.8)
	_en_show = move_toward(_en_show, energy_fraction(), delta * 1.2)
	queue_redraw()
	var settled := is_equal_approx(_en_show, energy_fraction()) and is_equal_approx(_hp_show, want) and is_equal_approx(_hp_chip, _hp_show) and is_equal_approx(_xp_show, xp_fraction())
	if settled and want >= LOW:
		set_process(false)  # tidak ada yang bergerak: hemat tenaga


func _rr(rect: Rect2, color: Color, radius: float, border := Color(0, 0, 0, 0), border_w := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	if border_w > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(border_w))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)


func _text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font: Font = FONT
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := Vector2(center.x - w / 2.0, center.y + font_size * 0.35)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.85))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw() -> void:
	# --- nama pemain (paling atas): font game, isi emas, tepi cokelat, bayangan ---
	var font: Font = FONT
	var nm := player_name
	while nm.length() > 1 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x > BAR_X + BAR_W:
		nm = nm.substr(0, nm.length() - 1)
	var nbase := Vector2(6.0, NAME_H - 8.0)
	draw_string(font, nbase + Vector2(2.0, 3.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(0, 0, 0, 0.45))
	draw_string_outline(font, nbase, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, 8, NAME_EDGE)
	draw_string(font, nbase, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, NAME_FILL)
	# --- level: piala emas bernomor level ---
	_trophy(Vector2(27.0, XP_Y + XP_H / 2.0 + 2.0))
	# --- poin menuju level berikutnya ---
	var xr := Rect2(BAR_X, XP_Y, BAR_W, XP_H)
	_rr(xr.grow(2.0), Color(0, 0, 0, 0.55), 10.0)
	if _xp_show > 0.003:
		var fw := maxf(XP_H, BAR_W * _xp_show)
		_rr(Rect2(BAR_X, XP_Y, fw, XP_H), Color("3d9bf0"), 8.0)
		_rr(Rect2(BAR_X + 3.0, XP_Y + 2.0, maxf(0.0, fw - 6.0), XP_H * 0.36), Color(1, 1, 1, 0.28), 4.0)
	_rr(xr, Color(0, 0, 0, 0), 8.0, Color("cfe6ff", 0.8), 1.5)
	_text("%d/%d" % [xp, xp_need], xr.get_center() + Vector2(0, -1.0), 14, Color.WHITE)
	# --- tanda + merah ---
	var low := hp_fraction() < LOW
	var pulse := 1.0 + (0.12 * sin(_t * 9.0) if low else 0.0)
	var c2 := Vector2(27.0, HP_Y + HP_H / 2.0)
	var arm := 15.0 * pulse
	var th := 10.0 * pulse
	var cross_c := Color("e82a2a") if not low or sin(_t * 9.0) > -0.2 else Color("ff6a5a")
	_rr(Rect2(c2.x - arm - 2.5, c2.y - th / 2.0 - 2.5, arm * 2.0 + 5.0, th + 5.0), Color("fff4f0"), 5.0)
	_rr(Rect2(c2.x - th / 2.0 - 2.5, c2.y - arm - 2.5, th + 5.0, arm * 2.0 + 5.0), Color("fff4f0"), 5.0)
	_rr(Rect2(c2.x - arm, c2.y - th / 2.0, arm * 2.0, th), cross_c, 3.0)
	_rr(Rect2(c2.x - th / 2.0, c2.y - arm, th, arm * 2.0), cross_c, 3.0)
	# --- bar nyawa ---
	var hr := Rect2(BAR_X, HP_Y, BAR_W, HP_H)
	_rr(hr.grow(2.0), Color(0, 0, 0, 0.6), 12.0)
	if _hp_chip > 0.003:
		_rr(Rect2(BAR_X, HP_Y, maxf(HP_H, BAR_W * _hp_chip), HP_H), Color(1, 1, 1, 0.55), 10.0)
	if _hp_show > 0.003:
		var w := maxf(HP_H, BAR_W * _hp_show)
		var fill := hp_color(_hp_show)
		if low:
			fill = fill.lightened(0.25) if sin(_t * 9.0) > 0.0 else fill.darkened(0.2)
		_rr(Rect2(BAR_X, HP_Y, w, HP_H), fill, 10.0)
		_rr(Rect2(BAR_X + 4.0, HP_Y + 2.5, maxf(0.0, w - 8.0), HP_H * 0.34), Color(1, 1, 1, 0.3), 5.0)
	_rr(hr, Color(0, 0, 0, 0), 10.0, Color("ffe3df", 0.85), 1.5)
	_text("%d/%d" % [hp, max_hp], hr.get_center() + Vector2(0, -1.0), 16, Color.WHITE)
	# --- petir dan bar energi ---
	var ec := Vector2(27.0, EN_Y + EN_H / 2.0)
	_bolt(ec)
	var er := Rect2(BAR_X, EN_Y, BAR_W, EN_H)
	_rr(er.grow(2.0), Color(0, 0, 0, 0.6), 11.0)
	if _en_show > 0.003:
		var ew := maxf(EN_H, BAR_W * _en_show)
		var ecol := EN_COLOR if _en_show >= 0.2 else EN_COLOR.darkened(0.35)
		_rr(Rect2(BAR_X, EN_Y, ew, EN_H), ecol, 9.0)
		_rr(Rect2(BAR_X + 4.0, EN_Y + 2.0, maxf(0.0, ew - 8.0), EN_H * 0.34), Color(1, 1, 1, 0.35), 5.0)
	_rr(er, Color(0, 0, 0, 0), 9.0, Color("fff2b8", 0.85), 1.5)
	_text("%d/%d" % [energy, max_energy], er.get_center() + Vector2(0, -1.0), 14, Color.WHITE)
	# --- berlian dan jumlahnya (di atas koin emas) ---
	_diamond(Vector2(27.0, DIA_Y))
	var dtxt := str(diamonds)
	var dbase := Vector2(BAR_X - 6.0, DIA_Y + 8.0)
	draw_string_outline(font, dbase, dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 7, Color("0a3a55"))
	draw_string(font, dbase, dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("a8ecff"))
	# --- koin emas dan jumlahnya ---
	var cc := Vector2(27.0, COIN_Y)
	draw_circle(cc, 15.0, Color(0, 0, 0, 0.6))
	draw_circle(cc, 13.0, Color("c98a12"))
	draw_circle(cc, 10.8, Color("ffd23a"))
	draw_arc(cc, 7.8, 0.0, TAU, 24, Color("c98a12"), 2.0, true)
	draw_circle(cc + Vector2(-3.5, -4.2), 2.3, Color(1, 1, 1, 0.55))
	var gtxt := str(gold)
	var gbase := Vector2(BAR_X - 6.0, COIN_Y + 8.0)
	draw_string_outline(font, gbase, gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 7, Color("5a3a05"))
	draw_string(font, gbase, gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("ffe27a"))


## Piala emas dengan nomor level di cangkirnya. `c` = titik tengah cangkir.
func _trophy(c: Vector2) -> void:
	var edge := Color("6b4208")
	var gold_c := Color("f2b82a")
	var light := Color("ffe27a")
	# gagang kiri dan kanan
	for sx in [-1.0, 1.0]:
		draw_arc(c + Vector2(sx * 14.0, -6.0), 7.0, 0.0, TAU, 20, edge, 5.0, true)
		draw_arc(c + Vector2(sx * 14.0, -6.0), 7.0, 0.0, TAU, 20, gold_c, 2.6, true)
	# cangkir (lebar di atas, menyempit ke bawah)
	var cup := PackedVector2Array([
		c + Vector2(-15, -17), c + Vector2(15, -17), c + Vector2(13, -2),
		c + Vector2(7, 6), c + Vector2(-7, 6), c + Vector2(-13, -2)])
	draw_colored_polygon(cup, gold_c)
	draw_polyline(PackedVector2Array([cup[0], cup[1], cup[2], cup[3], cup[4], cup[5], cup[0]]), edge, 2.4, true)
	draw_line(c + Vector2(-10, -13), c + Vector2(-8, -3), light, 2.4, true)  # kilau
	# tangkai dan alas
	_rr(Rect2(c.x - 3.5, c.y + 6.0, 7.0, 7.0), gold_c, 1.0, edge, 1.5)
	_rr(Rect2(c.x - 12.0, c.y + 12.0, 24.0, 7.0), Color("d99a1c"), 2.0, edge, 1.8)
	_text(str(level), c + Vector2(0, -6.0), 20 if level < 10 else (16 if level < 100 else 12), Color("3a2606"))


## Ikon berlian biru muda (potongan brilian: meja di atas, ujung runcing di bawah). `c` = titik tengahnya.
func _diamond(c: Vector2) -> void:
	draw_circle(c, 15.0, Color(0, 0, 0, 0.6))
	var top_l := c + Vector2(-8.0, -5.0)
	var top_r := c + Vector2(8.0, -5.0)
	var tip := c + Vector2(0.0, 10.0)
	var crown := PackedVector2Array([c + Vector2(-4.5, -9.0), c + Vector2(4.5, -9.0), top_r, top_l])
	draw_colored_polygon(crown, Color("c9f6ff"))
	draw_colored_polygon(PackedVector2Array([top_l, top_r, tip]), Color("45c8f2"))
	draw_colored_polygon(PackedVector2Array([top_l, c + Vector2(0.0, -5.0), tip]), Color("8be4ff"))
	var edge := Color("0f6a94")
	draw_polyline(PackedVector2Array([c + Vector2(-4.5, -9.0), c + Vector2(4.5, -9.0), top_r, tip, top_l, c + Vector2(-4.5, -9.0)]), edge, 1.8, true)
	draw_line(top_l, top_r, edge, 1.4, true)
	draw_line(c + Vector2(-2.0, -9.0), top_l.lerp(tip, 0.45), Color(1, 1, 1, 0.6), 1.4, true)


## Ikon petir kuning. `c` = titik tengahnya.
func _bolt(c: Vector2) -> void:
	var pts := PackedVector2Array([
		c + Vector2(4, -15), c + Vector2(-9, 3), c + Vector2(-1.5, 3),
		c + Vector2(-5, 15), c + Vector2(10, -4), c + Vector2(2, -4)])
	draw_circle(c, 19.0, Color(0, 0, 0, 0.6))
	draw_colored_polygon(pts, Color("ffd21a"))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color("8a5a00"), 2.0, true)
