extends RefCounted
## Bantuan tata letak layar mendatar (v0.68.0, game berorientasi landscape 1280x720 dengan aspect "expand").
## Layar HP yang lebar (20:9 dan seterusnya) membuat daftar dan tombol memanjang dari ujung ke ujung; `kolom`
## menaruh isi sebuah MarginContainer layar penuh di kolom tengah selebar paling banyak `lebar`.


## Atur tepi kiri-kanan `margin` supaya isinya paling lebar `lebar` (titik layar), minimal `tepi` dari tepi layar;
## tepi atas-bawah dijadikan `atas`. Ikut menyesuaikan saat ukuran layar berubah.
static func kolom(margin: MarginContainer, lebar := 1040.0, tepi := 28, atas := 20) -> void:
	margin.add_theme_constant_override("margin_top", atas)
	margin.add_theme_constant_override("margin_bottom", atas)
	var atur := func() -> void:
		if not is_instance_valid(margin) or not margin.is_inside_tree():
			return
		var w := margin.get_viewport().get_visible_rect().size.x
		var side := int(maxf(float(tepi), (w - lebar) / 2.0))
		margin.add_theme_constant_override("margin_left", side)
		margin.add_theme_constant_override("margin_right", side)
	# MarginContainer layar penuh ikut berubah ukuran bersama layar: cukup dengarkan `resized` (tepi tidak mengubah ukurannya).
	margin.resized.connect(atur)
	if margin.is_inside_tree():
		atur.call()
	else:
		margin.tree_entered.connect(atur, CONNECT_DEFERRED)
