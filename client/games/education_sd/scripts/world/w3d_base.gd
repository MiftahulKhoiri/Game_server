extends RefCounted
## Markas Pemain (Fase 7): rumah pemain di pulau kecil yang memajang koleksi dari progres yang SAH —
## galeri hewan 3D (koleksi hewan mini-game), dinding kartu pengetahuan (kartu dari area selesai), lemari
## kostum (hanya kostum yang sudah dimiliki), cermin pemilihan karakter, rak piala (lencana prestasi),
## dan Buku Petualangan (misi semua pulau). Tidak ada mata uang atau hadiah baru di sini.

const Rig := preload("res://games/education_sd/scripts/world/w3d_rig.gd")
const Life := preload("res://games/education_sd/scripts/world/w3d_life.gd")

const MAX_ANIMALS := 8
const MAX_CARDS := 12
const MAX_TROPHIES := 10


static func build(w: Node3D, ctx: Dictionary) -> void:
	var b: Dictionary = ctx.base
	var floor_c := Color("e9c47e")
	var g: StaticBody3D = w._static_box_at(w, Vector3(60, 2, 60), Vector3(0, -1, 0), Color("8fd16a"))
	g.name = "Ground"
	var sea := Rig.part(Rig.box(Vector3(260, 0.2, 260)), Color("4aa3df"), Vector3(0, -1.4, 0))
	sea.set_meta("water", true)
	w.add_child(sea)
	var yard := Rig.part(Rig.cyl(13.0, 13.0, 0.04, 32), floor_c, Vector3(0, 0.02, 0))
	w.add_child(yard)
	for side in [-1.0, 1.0]:
		w._wall(Vector3(0.5, 3, 34), Vector3(17 * side, 1.5, 0), Color("c98a4b"))
		w._wall(Vector3(34, 3, 0.5), Vector3(0, 1.5, 17 * side), Color("c98a4b"))
	# Rumah (paviliun terbuka) di belakang
	var house := Node3D.new()
	house.position = Vector3(0, 0, -10)
	house.add_child(Rig.part(Rig.box(Vector3(16, 0.3, 8)), Color("f4efe6"), Vector3(0, 0.15, 0)))
	house.add_child(Rig.part(Rig.box(Vector3(16, 4.2, 0.4)), Color("fff3c4"), Vector3(0, 2.4, -3.8)))
	for x in [-7.6, 7.6]:
		house.add_child(Rig.part(Rig.box(Vector3(0.4, 4.2, 8)), Color("fff3c4"), Vector3(x, 2.4, 0)))
	var roof := PrismMesh.new()
	roof.size = Vector3(17.5, 2.6, 9.5)
	house.add_child(Rig.part(roof, Color("c0503a"), Vector3(0, 5.8, 0)))
	house.add_child(Rig.part(Rig.box(Vector3(17.5, 0.3, 9.5)), Color("a0452e"), Vector3(0, 4.55, 0)))
	w.add_child(house)
	w._static_box_at(w, Vector3(16, 4.2, 0.6), Vector3(0, 2.1, -13.8), null)
	for x in [-7.6, 7.6]:
		w._static_box_at(w, Vector3(0.6, 4.2, 8), Vector3(x, 2.1, -10), null)
	var sign: Label3D = w._label("MARKAS %s" % str(b.get("name", "")).to_upper(), 72, Color("ffd166"))
	sign.position = Vector3(0, 4.0, -6.0)
	w.add_child(sign)
	# Lemari kostum (kiri dalam rumah)
	var wardrobe := Node3D.new()
	wardrobe.position = Vector3(-5.5, 0, -12.6)
	wardrobe.add_child(Rig.part(Rig.box(Vector3(2.4, 3.0, 1.0)), Color("8a5a2b"), Vector3(0, 1.5, 0)))
	var outfits: Array = b.get("outfits", [])
	for i in mini(outfits.size(), 5):
		wardrobe.add_child(Rig.part(Rig.box(Vector3(0.35, 0.9, 0.1)), outfits[i].color, Vector3(-0.8 + i * 0.4, 1.8, 0.55)))
	var wl: Label3D = w._label("Lemari Kostum", 40, Color.WHITE, true)
	wl.position.y = 3.6
	wardrobe.add_child(wl)
	w.add_child(wardrobe)
	w._interactable(wardrobe, "wardrobe", "", "Buka lemari kostum", 2.4)
	# Cermin pemilihan karakter
	var mirror := Node3D.new()
	mirror.position = Vector3(-2.2, 0, -13.2)
	mirror.add_child(Rig.part(Rig.box(Vector3(1.4, 2.4, 0.15)), Color("cfe8ff"), Vector3(0, 1.4, 0)))
	mirror.add_child(Rig.part(Rig.box(Vector3(1.6, 2.6, 0.08)), Color("c9a46a"), Vector3(0, 1.4, -0.08)))
	var ml: Label3D = w._label("Cermin Karakter", 40, Color.WHITE, true)
	ml.position.y = 3.1
	mirror.add_child(ml)
	w.add_child(mirror)
	w._interactable(mirror, "mirror", "", "Pilih karakter", 2.0)
	# Buku Petualangan
	var book := Node3D.new()
	book.position = Vector3(1.6, 0, -11.5)
	book.add_child(Rig.part(Rig.box(Vector3(1.4, 1.0, 0.8)), Color("8a5a2b"), Vector3(0, 0.5, 0)))
	var bk := Rig.part(Rig.box(Vector3(0.9, 0.12, 0.65)), Color("8a6bd8"), Vector3(0, 1.08, 0))
	bk.rotation.x = -0.2
	book.add_child(bk)
	var bl: Label3D = w._label("Buku Petualangan", 40, Color.WHITE, true)
	bl.position.y = 2.0
	book.add_child(bl)
	w.add_child(book)
	w._interactable(book, "book", "", "Baca Buku Petualangan", 2.0)
	w.add_life("bob", bk)
	# Rak piala (lencana)
	var shelf := Node3D.new()
	shelf.position = Vector3(5.2, 0, -13.3)
	shelf.add_child(Rig.part(Rig.box(Vector3(3.6, 0.15, 0.7)), Color("8a5a2b"), Vector3(0, 1.2, 0)))
	shelf.add_child(Rig.part(Rig.box(Vector3(3.6, 0.15, 0.7)), Color("8a5a2b"), Vector3(0, 2.3, 0)))
	var badges: Array = b.get("badges", [])
	for i in mini(badges.size(), MAX_TROPHIES):
		var cup := Node3D.new()
		cup.position = Vector3(-1.5 + (i % 5) * 0.75, 1.3 + (i / 5) * 1.1, 0)
		cup.add_child(Rig.part(Rig.cyl(0.22, 0.1, 0.35, 10), Color("f0b429"), Vector3(0, 0.35, 0)))
		cup.add_child(Rig.part(Rig.cyl(0.12, 0.16, 0.1, 8), Color("c98a1a"), Vector3(0, 0.08, 0)))
		shelf.add_child(cup)
	var sl: Label3D = w._label("Piala Prestasi (%d)" % badges.size(), 40, Color.WHITE, true)
	sl.position.y = 3.2
	shelf.add_child(sl)
	w.add_child(shelf)
	w._interactable(shelf, "trophies", "", "Lihat piala prestasi", 2.2)
	# Dinding kartu pengetahuan (museum kartu) di dinding kanan luar
	var cards: Array = b.get("cards", [])
	var wall := Node3D.new()
	wall.position = Vector3(8.2, 0, -10)
	wall.rotation.y = PI / 2.0
	for i in mini(cards.size(), MAX_CARDS):
		var frame := Rig.part(Rig.box(Vector3(1.1, 1.4, 0.06)), cards[i].color, Vector3(-3.0 + (i % 6) * 1.2, 1.5 + (i / 6) * 1.6, 0.25))
		wall.add_child(frame)
	var cl: Label3D = w._label("Museum Kartu (%d)" % cards.size(), 44, Color("ffd166"))
	cl.position = Vector3(0, 4.3, 0.3)
	wall.add_child(cl)
	w.add_child(wall)
	w._interactable(wall, "cards", "", "Lihat kartu pengetahuan", 3.0)
	# Galeri hewan 3D: alas + model hewan dari koleksi
	var animals: Array = b.get("animals", [])
	var n := maxi(1, mini(animals.size(), MAX_ANIMALS))
	for i in n:
		var ped := Node3D.new()
		var a := PI * 0.15 + i * (PI * 0.7 / maxf(1.0, n - 1.0))
		ped.position = Vector3(cos(a) * -9.5, 0, sin(a) * 9.5 - 1.0)
		ped.rotation.y = atan2(-ped.position.x, -ped.position.z)
		ped.add_child(Rig.part(Rig.cyl(0.9, 1.0, 0.6, 14), Color("e8e2f2"), Vector3(0, 0.3, 0)))
		var aid := ""
		if i < animals.size():
			aid = str(animals[i].id)
			var model: Node3D = Life.make_animal(animals[i].color)
			model.position.y = 0.6
			ped.add_child(model)
			var lbl: Label3D = w._label(str(animals[i].name), 40, Color.WHITE, true)
			lbl.position.y = 2.4
			ped.add_child(lbl)
		else:
			var lbl: Label3D = w._label("Galeri Hewan\n(belum ada hewan)", 36, Color.WHITE, true)
			lbl.position.y = 1.8
			ped.add_child(lbl)
		w.add_child(ped)
		w._interactable(ped, "animal", aid, "Lihat " + (str(animals[i].name) if aid != "" else "galeri hewan"), 1.8)
	# Portal kembali ke pulau
	var portal := Node3D.new()
	portal.position = Vector3(9.0, 0, 7.0)
	portal.rotation.y = -PI / 2.0
	var ring := TorusMesh.new()
	ring.inner_radius = 1.25
	ring.outer_radius = 1.6
	var rmi := Rig.part(ring, Color("8a6bd8"), Vector3(0, 1.8, 0))
	rmi.rotation.x = PI / 2.0
	portal.add_child(rmi)
	var pl: Label3D = w._label("PORTAL PULAU", 48, Color.WHITE, true)
	pl.position.y = 3.8
	portal.add_child(pl)
	w.add_child(portal)
	w._interactable(portal, "portal", "", "Pindah pulau", 2.6)
	for i in 12:
		var t := Vector3(cos(i * TAU / 12.0) * 22.0, 0, sin(i * TAU / 12.0) * 22.0)
		w.add_child(Rig.part(Rig.cyl(0.2, 0.28, 1.6, 7), Color("8a5a2b"), t + Vector3(0, 0.8, 0)))
		w.add_child(Rig.part(Rig.sphere(1.3), Color("3fae63"), t + Vector3(0, 2.4, 0)))
