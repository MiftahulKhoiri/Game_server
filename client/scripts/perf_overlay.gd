extends CanvasLayer
## Lapisan FPS & memori (roadmap no. 251): satu baris kecil di tepi atas layar, diperbarui dua kali
## per detik. Dinyalakan dari Pengaturan ("Tampilkan FPS & memori"); dipasang oleh Session sehingga
## tetap terlihat saat berganti layar (beranda, dunia, pertarungan).

const Perf := preload("res://scripts/perf.gd")

var label: Label
var _acc := 0.0


func _init() -> void:
	layer = 120
	name = "LapisanPerforma"


func _ready() -> void:
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("b8ffb8"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	# Layar mendatar (v0.69.0): di atas, di antara nama pemain (kiri atas) dan jam hari (tengah atas).
	label.position = Vector2(176, 10)
	label.size = Vector2(500, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.clip_text = true
	add_child(label)
	refresh()


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 0.5:
		_acc = 0.0
		refresh()


func refresh() -> void:
	label.text = Perf.text(Perf.snapshot())
	# Lebar sampai sebelum jam (jam di world3d.gd: tengahnya 440 + (lebar layar - 720) / 2, lebar ±240).
	var vw := label.get_viewport().get_visible_rect().size.x if label.is_inside_tree() else 1280.0
	label.size.x = clampf(440.0 + (vw - 720.0) * 0.5 - 135.0 - label.position.x, 200.0, 560.0)
	# Layar sempit: tulisan diringkas supaya tetap satu baris dan tidak menabrak jam.
	var font := label.get_theme_font("font")
	if font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > label.size.x:
		label.text = label.text.replace(" MB", "").replace("Gambar", "Gbr").replace(" · ", "·")
