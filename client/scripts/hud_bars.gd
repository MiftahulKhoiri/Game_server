extends Control
## Tampilan pemain di pojok kiri atas, digambar dengan kode:
##   bagus                            <- nama pemain, di atas level
##   (Lv 3)  [=====xp======     ]     <- level, bar poin menuju level berikutnya
##    (+)    [=====nyawa=====   ]     <- tanda + merah, bar nyawa bergerak sesuai persentase
##   (koin) 47                        <- jumlah emas
## Poin (XP) didapat dari mengalahkan monster. Warna bar nyawa berubah seperti baterai:
## hijau stabilo saat penuh, lalu kuning, oranye, merah saat menipis. Nyawa turun/naik dengan
## gerak halus, bar putih tipis menyusul di belakang saat nyawa berkurang; di bawah 30% berdenyut.

const BAR_X := 66.0
const BAR_W := 300.0
const NAME_H := 34.0   # tinggi baris nama pemain di paling atas
const XP_Y := 44.0
const XP_H := 22.0
const HP_Y := 96.0
const HP_H := 34.0
const COIN_Y := 156.0  # titik tengah baris koin emas
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

var _hp_show := 1.0    # persentase nyawa yang digambar (menyusul target dengan halus)
var _hp_chip := 1.0    # bar putih yang menyusul lebih lambat saat nyawa berkurang
var _xp_show := 0.0
var _init_done := false
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BAR_X + BAR_W + 8.0, COIN_Y + 24.0)
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


## Nama pemain (di atas level) dan jumlah emas (di samping koin).
func set_identity(new_name: String, new_gold: int) -> void:
	player_name = new_name
	gold = new_gold
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
	queue_redraw()
	var settled := is_equal_approx(_hp_show, want) and is_equal_approx(_hp_chip, _hp_show) and is_equal_approx(_xp_show, xp_fraction())
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
	var font := get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := Vector2(center.x - w / 2.0, center.y + font_size * 0.35)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.85))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw() -> void:
	# --- nama pemain (paling atas) ---
	var font := get_theme_default_font()
	var nm := player_name
	while nm.length() > 1 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x > BAR_X + BAR_W:
		nm = nm.substr(0, nm.length() - 1)
	var nbase := Vector2(6.0, NAME_H * 0.5 + 9.0)
	draw_string_outline(font, nbase, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 7, Color(0, 0, 0, 0.9))
	draw_string(font, nbase, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("fff4d0"))
	# --- level ---
	var c1 := Vector2(32.0, XP_Y + XP_H / 2.0)
	draw_circle(c1, 25.0, Color(0, 0, 0, 0.6))
	draw_circle(c1, 22.0, Color("e0b030"))
	draw_circle(c1, 22.0, Color("fff0a8"), false, 2.0, true)
	_text(str(level), c1, 26 if level < 100 else 20, Color("3a2606"))
	# --- poin menuju level berikutnya ---
	var xr := Rect2(BAR_X, XP_Y, BAR_W, XP_H)
	_rr(xr.grow(2.0), Color(0, 0, 0, 0.55), 12.0)
	if _xp_show > 0.003:
		var fw := maxf(XP_H, BAR_W * _xp_show)
		_rr(Rect2(BAR_X, XP_Y, fw, XP_H), Color("3d9bf0"), 11.0)
		_rr(Rect2(BAR_X + 3.0, XP_Y + 2.0, maxf(0.0, fw - 6.0), XP_H * 0.36), Color(1, 1, 1, 0.28), 6.0)
	_rr(xr, Color(0, 0, 0, 0), 11.0, Color("cfe6ff", 0.8), 2.0)
	_text("Poin %d/%d" % [xp, xp_need], xr.get_center(), 16, Color.WHITE)
	# --- tanda + merah ---
	var low := hp_fraction() < LOW
	var pulse := 1.0 + (0.12 * sin(_t * 9.0) if low else 0.0)
	var c2 := Vector2(32.0, HP_Y + HP_H / 2.0)
	var arm := 21.0 * pulse
	var th := 14.0 * pulse
	var cross_c := Color("e82a2a") if not low or sin(_t * 9.0) > -0.2 else Color("ff6a5a")
	_rr(Rect2(c2.x - arm - 3.0, c2.y - th / 2.0 - 3.0, arm * 2.0 + 6.0, th + 6.0), Color("fff4f0"), 6.0)
	_rr(Rect2(c2.x - th / 2.0 - 3.0, c2.y - arm - 3.0, th + 6.0, arm * 2.0 + 6.0), Color("fff4f0"), 6.0)
	_rr(Rect2(c2.x - arm, c2.y - th / 2.0, arm * 2.0, th), cross_c, 4.0)
	_rr(Rect2(c2.x - th / 2.0, c2.y - arm, th, arm * 2.0), cross_c, 4.0)
	# --- bar nyawa ---
	var hr := Rect2(BAR_X, HP_Y, BAR_W, HP_H)
	_rr(hr.grow(2.0), Color(0, 0, 0, 0.6), 15.0)
	if _hp_chip > 0.003:
		_rr(Rect2(BAR_X, HP_Y, maxf(HP_H, BAR_W * _hp_chip), HP_H), Color(1, 1, 1, 0.55), 14.0)
	if _hp_show > 0.003:
		var w := maxf(HP_H, BAR_W * _hp_show)
		var fill := hp_color(_hp_show)
		if low:
			fill = fill.lightened(0.25) if sin(_t * 9.0) > 0.0 else fill.darkened(0.2)
		_rr(Rect2(BAR_X, HP_Y, w, HP_H), fill, 14.0)
		_rr(Rect2(BAR_X + 4.0, HP_Y + 3.0, maxf(0.0, w - 8.0), HP_H * 0.34), Color(1, 1, 1, 0.3), 7.0)
	_rr(hr, Color(0, 0, 0, 0), 14.0, Color("ffe3df", 0.85), 2.0)
	# --- koin emas dan jumlahnya ---
	var cc := Vector2(32.0, COIN_Y)
	draw_circle(cc, 21.0, Color(0, 0, 0, 0.6))
	draw_circle(cc, 18.0, Color("c98a12"))
	draw_circle(cc, 15.0, Color("ffd23a"))
	draw_arc(cc, 11.0, 0.0, TAU, 28, Color("c98a12"), 2.5, true)
	draw_circle(cc + Vector2(-5.0, -6.0), 3.2, Color(1, 1, 1, 0.55))
	var gtxt := str(gold)
	var gbase := Vector2(BAR_X, COIN_Y + 10.0)
	draw_string_outline(font, gbase, gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 7, Color(0, 0, 0, 0.9))
	draw_string(font, gbase, gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("ffe27a"))
