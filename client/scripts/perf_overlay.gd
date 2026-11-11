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
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("b8ffb8"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -330
	label.offset_right = 330
	# Layar mendatar (v0.68.2): di tepi bawah tengah supaya tidak menutupi jam dan papan misi di atas.
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = -30
	label.offset_bottom = -4
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	refresh()


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 0.5:
		_acc = 0.0
		refresh()


func refresh() -> void:
	label.text = Perf.text(Perf.snapshot())
