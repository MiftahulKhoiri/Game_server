extends Node
## Klien HTTP untuk server Game_server. Kontrak lengkap: docs/API.md
##
## Semua fungsi mengembalikan Dictionary:
##   sukses: {"ok": true,  "status": 200, "data": {...}}
##   gagal:  {"ok": false, "status": 409, "error": "pesan", "data": {...}}  (status 0 = tidak terhubung)
## Pemakaian: var res: Dictionary = await Api.get_me()

const Version = preload("res://scripts/version.gd")

var base_url: String = "http://192.168.225.3:8090"
var token: String = ""
## Dikirim ke server di setiap permintaan; server menolak (426) bila di bawah batas minimum.
var client_version: String = Version.app_version()


func health() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/healthz", null, false)


## Info versi server: {"server", "commit", "api", "min_client", "latest_client", "update_url"}
func version_info() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/version", null, false)


func register(player_name: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/players", {"name": player_name}, false)


func get_me() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/players/me", null, true)


func save(version: int, state: Dictionary) -> Dictionary:
	var body := {"version": version, "state": state}
	return await _call(HTTPClient.METHOD_PUT, "/v1/players/me/save", body, true)


## Pertarungan yang sedang berjalan (404 bila tidak ada).
func battle_get() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/battle", null, true)


## Mulai pertarungan dengan musuh acak (409 bila sudah ada yang berjalan).
## boss = true: lawan bos di petak pemain (422 bila tidak ada bos di sana).
func battle_start(boss := false) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/battle/start", {"boss": true} if boss else null, true)


## action: "attack" | "defend" | "potion" | "flee"
func battle_action(action: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/battle/action", {"action": action}, true)


## Pakai ramuan di luar pertarungan.
func inventory_use(item: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/inventory/use", {"item": item}, true)


## Pasang perlengkapan dari tas.
func inventory_equip(item: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/inventory/equip", {"item": item}, true)


## Lepas perlengkapan dari slot ("weapon" atau "armor").
func inventory_unequip(slot: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/inventory/unequip", {"slot": slot}, true)


## Istirahat: HP pulih penuh, gratis, hanya di desa.
func rest() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/rest", null, true)


## Semua misi beserta kemajuan pemain (status: available/active/done/claimed).
func quests_get() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/quests", null, true)


func quest_accept(quest: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/quests/accept", {"quest": quest}, true)


## Mengambil hadiah misi yang sudah selesai (emas langsung masuk).
func quest_claim(quest: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/quests/claim", {"quest": quest}, true)


## Daftar barang dan harga toko.
func shop_get() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/shop", null, true)


func shop_buy(item: String, qty: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/shop/buy", {"item": item, "qty": qty}, true)


func shop_sell(item: String, qty: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/shop/sell", {"item": item, "qty": qty}, true)


func _call(method: HTTPClient.Method, path: String, body: Variant, auth: bool) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Client-Version: " + client_version,
	])
	if auth and token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := "" if body == null else JSON.stringify(body)

	var err := req.request(base_url + path, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"ok": false, "status": 0, "error": "Tidak bisa mengirim permintaan (kode %d)" % err}

	var result: Array = await req.request_completed
	req.queue_free()

	var net_result: int = result[0]
	var status: int = result[1]
	var raw: PackedByteArray = result[3]
	if net_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "error": "Server tidak terjangkau"}

	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data}
	# "data" ikut dikembalikan: pada 426 berisi min_client dan update_url.
	return {"ok": false, "status": status, "data": data,
			"error": str(data.get("error", "Kesalahan %d" % status))}
