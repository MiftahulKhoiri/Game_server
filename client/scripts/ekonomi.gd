extends CanvasLayer
## Layar ekonomi (roadmap no. 171-185): Bank (Pak Saleh), Peti Simpan di rumah, dan Dagang antarpemain.
## Semua aturan (emas, batas, titipan barang dagang) ada di server; layar ini hanya menampilkan state
## pemain (bank, storage, ledger) dan mengirim permintaan.

signal closed

const MODE_BANK := "bank"
const MODE_PETI := "peti"
const MODE_DAGANG := "dagang"
const QUICK := [10, 100, 1000]
const STORAGE_SLOTS := 30  # sama dengan StorageSlots di internal/game/economy.go
const KIND_NAMES := {"beli": "Beli", "jual": "Jual", "tukar": "Tukar", "pertarungan": "Pertarungan", "misi": "Hadiah",
	"bank": "Bank", "dagang": "Dagang", "rumah": "Rumah", "peti": "Peti", "bayar": "Bayar"}

var is_open := false
var mode := MODE_BANK
var keeper := "Pak Saleh"
var trades: Array = []      # dari GET /v1/trades (untuk uji bisa diisi langsung)
var recent: Array = []      # nama pemain aktif 7 hari terakhir (GET /v1/players/recent, no. 176)

var _title: Label
var _info: Label
var _list: VBoxContainer
var _status: Label
var _catalog: Dictionary = {}
var _busy := false
# formulir dagang
var _to: LineEdit
var _item: OptionButton
var _qty: SpinBox
var _price: SpinBox
var _item_ids: Array[String] = []
var _to_name := ""          # nama tujuan tetap ada saat layar digambar ulang


func _init() -> void:
	layer = 11
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preload("res://scripts/layar.gd").kolom(margin, 1040.0)  # layar mendatar: isi di kolom tengah
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1f2a24")
	sb.border_color = Color("d4b04a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = _label("", 42)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color("ffe08a"))
	box.add_child(_title)
	_info = _label("", 26)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_status = _label("", 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("ffd27a"))
	box.add_child(_status)
	box.add_child(_button("Tutup", func() -> void: closed.emit(), 84))


## Buka layar dengan mode MODE_BANK / MODE_PETI / MODE_DAGANG.
func open(p_mode: String) -> void:
	mode = p_mode
	visible = true
	is_open = true
	_status.text = {MODE_BANK: "%s: Emas di bank aman, tidak hilang walau kamu pingsan." % keeper,
		MODE_PETI: "Peti simpan di rumahmu: barang di sini tidak memenuhi ransel.",
		MODE_DAGANG: "Tawarkan barang ke pemain lain. Barang dititipkan sampai tawaran diterima, ditolak, atau dibatalkan."}.get(mode, "")
	_rebuild()
	if _catalog.is_empty() and not Session.offline:
		var res: Dictionary = await Api.item_catalog()
		if res.ok:
			for d: Dictionary in res.data.get("items", []):
				_catalog[str(d.id)] = d
	if mode == MODE_DAGANG and not Session.offline:
		await _load_trades()
	if mode == MODE_BANK and not Session.offline:
		await _claim_interest()
	_rebuild()


func close() -> void:
	visible = false
	is_open = false


func _state() -> Dictionary:
	return Session.player.get("state", {})


func name_of(id: String) -> String:
	return str(_catalog.get(id, {}).get("name", id.capitalize()))


func _rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var st := _state()
	var gold := int(st.get("gold", 0))
	var bank := int(st.get("bank", 0))
	match mode:
		MODE_BANK:
			_title.text = "Bank Desa"
			_info.text = "Dibawa: %d emas     Tabungan: %d emas\nBunga %d%% sehari untuk %d emas pertama" % [
				gold, bank, BANK_INTEREST_PERMIL / 10, BANK_INTEREST_CAP]
			_build_bank(gold, bank)
		MODE_PETI:
			_title.text = "Peti Simpan"
			_info.text = "Isi peti: %d/%d tumpukan" % [(st.get("storage", []) as Array).size(), STORAGE_SLOTS]
			_build_peti()
		MODE_DAGANG:
			_title.text = "Dagang"
			_info.text = "Emasmu: %d" % gold
			_build_dagang()


# --- bank ---

func _build_bank(gold: int, bank: int) -> void:
	for pair: Array in [["Simpan", true, gold], ["Ambil", false, bank]]:
		_list.add_child(_label(str(pair[0]), 28))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for n: int in QUICK:
			var b := _button(str(n), _on_bank.bind(bool(pair[1]), n), 76)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = _busy or int(pair[2]) < n
			row.add_child(b)
		var all := _button("Semua", _on_bank.bind(bool(pair[1]), int(pair[2])), 76)
		all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		all.disabled = _busy or int(pair[2]) <= 0
		row.add_child(all)
		_list.add_child(row)
	_build_ledger()


## Riwayat transaksi (no. 182): terbaru di atas.
func _build_ledger() -> void:
	_list.add_child(_label("Riwayat transaksi", 28))
	var ledger: Array = _state().get("ledger", [])
	if ledger.is_empty():
		_list.add_child(_label("Belum ada transaksi.", 22))
		return
	for i in range(ledger.size() - 1, -1, -1):
		var e: Dictionary = ledger[i]
		var g := int(e.get("gold", 0))
		var when := Time.get_datetime_string_from_unix_time(int(e.get("at", 0)) + _tz_offset(), true).substr(5, 11).replace("T", " ")
		var line := "%s  [%s] %s" % [when, KIND_NAMES.get(str(e.get("kind", "")), str(e.get("kind", ""))), str(e.get("note", ""))]
		if g != 0:
			line += "  %s%d" % ["+" if g > 0 else "", g]
		var l := _label(line, 21)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color("9fe6a0") if g > 0 else (Color("ff9c8c") if g < 0 else Color("d8d8d0")))
		_list.add_child(l)


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## Bunga sama dengan server (internal/game/economy.go); server yang menghitung.
const BANK_INTEREST_PERMIL := 10
const BANK_INTEREST_CAP := 20000


## Saat layar bank dibuka, bunga yang tertunda dikreditkan server lalu diberitahukan.
func _claim_interest() -> void:
	var before := int(_state().get("bank", 0))
	var res: Dictionary = await Api.bank_interest()
	if not res.ok:
		return
	var gain := int((res.data.get("state", {}) as Dictionary).get("bank", 0)) - before
	if gain > 0:  # hanya bila bunga benar-benar masuk (tanpa bunga, state di layar sudah sama dengan server)
		Session.merge_server_player(res.data)
		_status.text = "%s: Bunga tabunganmu +%d emas sudah masuk ke bank." % [keeper, gain]


func _on_bank(deposit: bool, amount: int) -> void:
	if _busy or amount <= 0:
		return
	_busy = true
	_rebuild()
	var res: Dictionary = await Api.bank(deposit, amount)
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = ("Menabung %d emas." if deposit else "Mengambil %d emas.") % amount
	else:
		_status.text = str(res.error)
	_rebuild()


# --- peti simpan ---

func _build_peti() -> void:
	var st := _state()
	_list.add_child(_label("Di peti", 28))
	var stored: Array = st.get("storage", [])
	if stored.is_empty():
		_list.add_child(_label("Peti masih kosong.", 22))
	for it: Dictionary in stored:
		_list.add_child(_stack_row(it, false))
	_list.add_child(_label("Di ransel", 28))
	for it: Dictionary in st.get("inventory", []):
		_list.add_child(_stack_row(it, true))


func _stack_row(it: Dictionary, put: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var id := str(it.id)
	var qty := int(it.qty)
	var l := _label("%s x%d" % [name_of(id), qty], 24)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var verb := "Simpan" if put else "Ambil"
	var one := _button(verb + " 1", _on_stack.bind(put, id, 1), 70)
	one.custom_minimum_size.x = 150
	one.disabled = _busy
	row.add_child(one)
	if qty > 1:
		var all := _button("Semua", _on_stack.bind(put, id, qty), 70)
		all.custom_minimum_size.x = 120
		all.disabled = _busy
		row.add_child(all)
	return row


func _on_stack(put: bool, id: String, qty: int) -> void:
	if _busy:
		return
	_busy = true
	_rebuild()
	var res: Dictionary = await Api.storage(put, id, qty)
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = "%s %s x%d." % ["Disimpan:" if put else "Diambil:", name_of(id), qty]
	else:
		_status.text = str(res.error)
	_rebuild()


# --- dagang antarpemain ---

func _load_trades() -> void:
	var res: Dictionary = await Api.trades_get()
	if res.ok:
		trades = res.data.get("trades", [])
	else:
		_status.text = str(res.error)
	var rp: Dictionary = await Api.players_recent()
	if rp.ok:
		recent = rp.data.get("players", [])


func _build_dagang() -> void:
	var me := str(Session.player.get("name", ""))
	_list.add_child(_label("Tawarkan barang", 28))
	_to = LineEdit.new()
	_to.placeholder_text = "Nama pemain tujuan"
	_to.custom_minimum_size = Vector2(0, 72)
	_to.add_theme_font_size_override("font_size", 26)
	_to.text = _to_name
	_to.text_changed.connect(func(t: String) -> void: _to_name = t)
	var to_row := HBoxContainer.new()
	to_row.add_theme_constant_override("separation", 8)
	_to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_row.add_child(_to)
	var add := _button("+ Teman", _on_friend_add, 72)
	add.custom_minimum_size.x = 150
	add.disabled = _busy
	to_row.add_child(add)
	_list.add_child(to_row)
	_build_people()
	_item = OptionButton.new()
	_item.custom_minimum_size = Vector2(0, 72)
	_item.add_theme_font_size_override("font_size", 24)
	_item_ids = []
	for it: Dictionary in _state().get("inventory", []):
		_item.add_item("%s (punya %d)" % [name_of(str(it.id)), int(it.qty)])
		_item_ids.append(str(it.id))
	_list.add_child(_item)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_label("Jumlah", 24))
	_qty = _spin(1, 999, 1)
	row.add_child(_qty)
	row.add_child(_label("Harga", 24))
	_price = _spin(0, 1000000, 10)
	row.add_child(_price)
	_list.add_child(row)
	var send := _button("Kirim tawaran", _on_offer, 80)
	send.disabled = _busy or _item_ids.is_empty()
	_list.add_child(send)

	var incoming: Array = []
	var outgoing: Array = []
	var done: Array = []
	for t: Dictionary in trades:
		if str(t.get("status", "")) != "pending":
			done.append(t)
		elif str(t.get("to", "")).to_lower() == me.to_lower():
			incoming.append(t)
		else:
			outgoing.append(t)
	_list.add_child(_label("Tawaran masuk", 28))
	if incoming.is_empty():
		_list.add_child(_label("Tidak ada.", 22))
	for t: Dictionary in incoming:
		_list.add_child(_trade_row(t, "Dari %s: %s x%d seharga %d emas" % [t.from, name_of(str(t.item)), int(t.qty), int(t.price)],
			[["Beli", true], ["Tolak", false]]))
	_list.add_child(_label("Tawaranmu", 28))
	if outgoing.is_empty():
		_list.add_child(_label("Tidak ada.", 22))
	for t: Dictionary in outgoing:
		_list.add_child(_trade_row(t, "Ke %s: %s x%d seharga %d emas" % [t.to, name_of(str(t.item)), int(t.qty), int(t.price)],
			[["Batalkan", false]]))
	if not done.is_empty():
		_list.add_child(_label("Selesai", 28))
		var words := {"done": "terjual", "cancelled": "dibatalkan", "declined": "ditolak"}
		for t: Dictionary in done:
			var l := _label("%s → %s: %s x%d (%d emas) %s" % [t.from, t.to, name_of(str(t.item)), int(t.qty), int(t.price),
				words.get(str(t.status), str(t.status))], 21)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_list.add_child(l)


## Pilihan cepat tujuan dagang (no. 176): teman tersimpan di server dan pemain yang aktif seminggu terakhir.
func _build_people() -> void:
	var friends: Array = _state().get("friends", [])
	var others: Array = []
	for n: Variant in recent:
		if not _has_name(friends, str(n)):
			others.append(str(n))
	for group: Array in [["Teman", friends, true], ["Pemain aktif", others, false]]:
		var names: Array = group[1]
		if names.is_empty():
			continue
		_list.add_child(_label(str(group[0]), 22))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for n: Variant in names:
			var b := _button(str(n), _pick_to.bind(str(n)), 60)
			b.disabled = _busy
			flow.add_child(b)
			if bool(group[2]):
				var x := _button("x", _on_friend_remove.bind(str(n)), 60)
				x.custom_minimum_size.x = 56
				x.disabled = _busy
				flow.add_child(x)
		_list.add_child(flow)


static func _has_name(list: Array, name: String) -> bool:
	for n: Variant in list:
		if str(n).to_lower() == name.to_lower():
			return true
	return false


func _pick_to(name: String) -> void:
	_to_name = name
	if _to != null:
		_to.text = name


func _on_friend_add() -> void:
	var name := _to_name.strip_edges()
	if _busy or name == "":
		_status.text = "Tulis nama pemain yang mau dijadikan teman."
		return
	_busy = true
	var res: Dictionary = await Api.friend_add(name)
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = "%s masuk daftar teman." % name
	else:
		_status.text = str(res.error)
	_rebuild()


func _on_friend_remove(name: String) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.friend_remove(name)
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = "%s dihapus dari daftar teman." % name
	else:
		_status.text = str(res.error)
	_rebuild()


func _trade_row(t: Dictionary, text: String, actions: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _label(text, 23)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	for a: Array in actions:
		var b := _button(str(a[0]), _on_finish.bind(int(t.id), bool(a[1])), 70)
		b.custom_minimum_size.x = 130
		b.disabled = _busy
		row.add_child(b)
	return row


func _on_offer() -> void:
	if _busy or _item_ids.is_empty():
		return
	var to := _to_name.strip_edges()
	if to == "":
		_status.text = "Tulis nama pemain tujuan."
		return
	var id := _item_ids[clampi(_item.selected, 0, _item_ids.size() - 1)]
	_busy = true
	var res: Dictionary = await Api.trade_offer(to, id, int(_qty.value), int(_price.value))
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = "Tawaran %s x%d dikirim ke %s." % [name_of(id), int(_qty.value), to]
		await _load_trades()
	else:
		_status.text = str(res.error)
	_rebuild()


func _on_finish(id: int, accept: bool) -> void:
	if _busy:
		return
	_busy = true
	_rebuild()
	var res: Dictionary = await Api.trade_finish(id, accept)
	_busy = false
	if res.ok:
		Session.merge_server_player(res.data)
		_status.text = "Barang masuk ranselmu." if accept else "Tawaran selesai; barang kembali ke pemiliknya."
	else:
		_status.text = str(res.error)
	await _load_trades()
	_rebuild()


# --- bantuan tampilan ---

func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = lo if lo > 0 else 0
	s.custom_minimum_size = Vector2(170, 64)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.get_line_edit().add_theme_font_size_override("font_size", 24)
	return s


func _label(text: String, size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, h := 80) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 26)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b
