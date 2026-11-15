extends RefCounted
## Gaya antarmuka Pulau Ilmu: tombol besar membulat, warna cerah tidak menyilaukan, huruf besar.

const BG := Color("fdf6e3")
const INK := Color("2b2440")
const SOFT := Color("6b5f86")
const PRIMARY := Color("3f7fd8")
const GOOD := Color("3fae63")
const SOFT_BAD := Color("e0813d")  # jawaban belum tepat: jingga lembut, bukan merah keras
const GOLD := Color("f0b429")
const CARD := Color("ffffff")

## Pengaman sentuhan (HP): tombol tidak bereaksi bila jari baru saja menggeser layar (menggulir),
## atau sesaat setelah layar baru dibangun (sentuhan "nyasar" dari layar sebelumnya).
const DRAG_CANCEL_PX := 24.0
static var guard_until_ms := 0
static var touch_dragged := false


static func guard(ms: int) -> void:
	guard_until_ms = Time.get_ticks_msec() + ms


static func can_press() -> bool:
	return not touch_dragged and Time.get_ticks_msec() >= guard_until_ms


static func box(c: Color, radius := 18, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.shadow_color = Color(0, 0, 0, 0.12)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 3)
	return s


static func label(text: String, size := 26, color := INK, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, color := PRIMARY, size := 28, min_h := 76) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, min_h)
	var fg := Color.WHITE if color.get_luminance() < 0.62 else INK
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.55))
	b.add_theme_stylebox_override("normal", box(color))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.08)))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.12)))
	b.add_theme_stylebox_override("disabled", box(color.lerp(Color("cfc8dc"), 0.6)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if cb.is_valid():
		b.pressed.connect(func() -> void:
			if can_press():
				cb.call())
	return b


static func panel(color := CARD, radius := 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius))
	return p


static func hbox(sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func grid(cols: int, sep := 14) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	return g


static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Animasi ringan: membesar sebentar (tanpa partikel berat).
static func pop(node: Control) -> void:
	if not node.is_inside_tree():
		return
	node.pivot_offset = node.size / 2.0
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.12, 1.12), 0.09)
	tw.tween_property(node, "scale", Vector2.ONE, 0.12)


static func shake(node: Control) -> void:
	if not node.is_inside_tree():
		return
	var x := node.position.x
	var tw := node.create_tween()
	for d in [8.0, -8.0, 5.0, 0.0]:
		tw.tween_property(node, "position:x", x + d, 0.05)


static func fade_in(node: Control) -> void:
	if not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	node.create_tween().tween_property(node, "modulate:a", 1.0, 0.25)


static func progress(value: float, max_value: float, color := GOOD, h := 18) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = maxf(1.0, max_value)
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, h)
	pb.add_theme_stylebox_override("background", box(Color("ece6f5"), 10))
	var fill := box(color, 10)
	fill.shadow_size = 0
	pb.add_theme_stylebox_override("fill", fill)
	return pb


static func line_edit(text: String, placeholder: String, size := 32) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.max_length = 16
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color(SOFT, 0.7))
	e.add_theme_color_override("caret_color", INK)
	e.add_theme_stylebox_override("normal", box(Color.WHITE, 14, PRIMARY, 3))
	e.add_theme_stylebox_override("focus", box(Color.WHITE, 14, GOLD, 3))
	e.custom_minimum_size = Vector2(0, 76)
	return e


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
