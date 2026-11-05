extends Node
## Klien HTTP untuk server Game_server. Kontrak lengkap: docs/API.md
##
## Semua fungsi mengembalikan Dictionary:
##   sukses: {"ok": true,  "status": 200, "data": {...}}
##   gagal:  {"ok": false, "status": 409, "error": "pesan"}  (status 0 = tidak terhubung)
## Pemakaian: var res: Dictionary = await Api.get_me()

var base_url: String = "http://192.168.225.3:8090"
var token: String = ""


func health() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/healthz", null, false)


func register(player_name: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/players", {"name": player_name}, false)


func get_me() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/players/me", null, true)


func save(version: int, state: Dictionary) -> Dictionary:
	var body := {"version": version, "state": state}
	return await _call(HTTPClient.METHOD_PUT, "/v1/players/me/save", body, true)


func _call(method: HTTPClient.Method, path: String, body: Variant, auth: bool) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)

	var headers := PackedStringArray(["Content-Type: application/json"])
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
	return {"ok": false, "status": status, "error": str(data.get("error", "Kesalahan %d" % status))}
