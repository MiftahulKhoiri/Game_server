extends Control
## Laporan Belajar untuk anak, orang tua, dan guru: ringkasan positif, per mata pelajaran (persentase benar,
## materi dikuasai, materi yang perlu dilatih, ujian), aktivitas 7 hari terakhir, dan riwayat terakhir.
## Kesimpulan hanya dibuat bila jawabannya cukup banyak (minimal 5 jawaban per mata pelajaran).

const UI := preload("res://games/education_sd/scripts/sd_ui.gd")

signal closed

var rep: Dictionary


func setup(report: Dictionary) -> void:
	rep = report
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("fdf6e3")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(UI.DRAG_CANCEL_PX)
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	scroll.add_child(m)
	var v := UI.vbox(12)
	v.name = "Page"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	var h := UI.hbox(12)
	var back := UI.button("Kembali", func() -> void: closed.emit(), Color("cfc8dc"), 24, 64)
	back.name = "Back"
	h.add_child(back)
	h.add_child(UI.label("Laporan Belajar", 38, UI.PRIMARY, false))
	v.add_child(h)
	v.add_child(UI.label("%s · Kelas %d" % [str(rep.name), int(rep.grade)], 28, UI.INK, false))
	var sp := UI.panel(Color("e8f4ff"), 20)
	var sl := UI.label(str(rep.summary), 26, Color("1f4f8a"))
	sl.name = "Summary"
	sp.add_child(sl)
	v.add_child(sp)
	_body(v)


func _pct(x: float) -> int:
	return int(round(x * 100.0))


func _body(v: VBoxContainer) -> void:
	var acc := _pct(float(rep.correct) / maxf(1.0, float(rep.answered)))
	v.add_child(UI.label("Total: %d soal, %d persen benar sejak percobaan pertama, rekor %d benar berturut-turut" % [int(rep.answered), acc,
		int(rep.best_streak)], 22, UI.SOFT))
	v.add_child(UI.label("Mata Pelajaran", 30, UI.PRIMARY, false))
	for r in rep.rooms:
		v.add_child(_room_card(r))
	v.add_child(UI.label("Aktivitas Terakhir", 30, UI.PRIMARY, false))
	if (rep.days as Array).is_empty():
		v.add_child(UI.label("Belum ada aktivitas.", 22, UI.SOFT))
	for d in rep.days:
		v.add_child(UI.label("%s: %d soal, %d benar" % [str(d.date), int(d.total), int(d.correct)], 22, UI.INK, false))
	if not (rep.history as Array).is_empty():
		v.add_child(UI.label("Riwayat", 30, UI.PRIMARY, false))
		for e in rep.history:
			var line := "%s, %s %s, nilai %d" % [str(e.get("at", "")).substr(0, 16), str(e.get("mode", "")).capitalize(),
				str(e.get("subject", "")), int(e.get("score", 0))]
			v.add_child(UI.label(line, 20, UI.INK, false))
	v.add_child(UI.label("Catatan: kecepatan menjawab tidak dinilai. Kesimpulan dibuat dari banyak jawaban, bukan satu-dua soal.", 18, UI.SOFT))


func _room_card(r: Dictionary) -> PanelContainer:
	var card := UI.panel(Color.WHITE, 20)
	card.name = "Room_" + str(r.id)
	var cv := UI.vbox(4)
	var head := UI.hbox(10)
	var nm := UI.label(str(r.name), 26, UI.INK, false)
	UI.expand(nm)
	head.add_child(nm)
	var good := float(r.rate) >= 0.7
	if bool(r.enough):
		head.add_child(UI.label("%d persen benar, %d soal" % [_pct(float(r.rate)), int(r.answered)], 22, UI.GOOD if good else UI.SOFT, false))
	else:
		head.add_child(UI.label("%d soal, belum cukup untuk dinilai" % int(r.answered), 20, UI.SOFT, false))
	cv.add_child(head)
	if bool(r.enough):
		cv.add_child(UI.progress(float(r.rate) * 100.0, 100.0, UI.GOOD if good else Color("f0b429"), 14))
	if not (r.mastered as Array).is_empty():
		cv.add_child(UI.label("Sudah dikuasai: " + ", ".join(r.mastered), 20, UI.GOOD))
	if not (r.practice as Array).is_empty():
		cv.add_child(UI.label("Bisa dilatih lagi: " + ", ".join(r.practice), 20, Color("b5743a")))
	var ex: Dictionary = r.exam
	if not ex.is_empty():
		var t := "Ujian: LULUS, nilai terbaik %d" if bool(ex.passed) else "Ujian: nilai terbaik %d, ayo coba lagi"
		cv.add_child(UI.label(t % int(ex.best), 20, UI.GOOD if bool(ex.passed) else UI.SOFT))
	card.add_child(cv)
	return card


func back() -> bool:
	return false
