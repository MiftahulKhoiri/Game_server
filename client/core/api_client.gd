extends Node
## Klien HTTP kecil untuk katalog game platform. Alamat server dan token login dipakai bersama dengan
## autoload Api milik Game Petualangan (satu akun, satu server). Semua fungsi async dan tidak pernah
## melempar error: hasilnya {ok, status, body: PackedByteArray, error}.

const TIMEOUT_SEC := 8.0

var base_url_override := ""


func base_url() -> String:
	if base_url_override != "":
		return base_url_override
	var api = get_node_or_null("/root/Api")
	return str(api.base_url) if api != null else ""


func _token() -> String:
	var api = get_node_or_null("/root/Api")
	return str(api.token) if api != null else ""


## GET mentah (byte persis, untuk diperiksa tanda tangannya).
func get_bytes(path: String, timeout := TIMEOUT_SEC) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, "", false, timeout)


## Katalog bertanda tangan: {ok, raw, sig, error}
func fetch_catalog() -> Dictionary:
	var cat := await get_bytes("/v1/games")
	if not cat.ok:
		return {"ok": false, "error": cat.error}
	var sig := await get_bytes("/v1/games/catalog.sig")
	if not sig.ok:
		return {"ok": false, "error": "Tanda tangan katalog tidak bisa diambil: " + str(sig.error)}
	return {"ok": true, "raw": cat.body, "sig": (sig.body as PackedByteArray).get_string_from_utf8(), "error": ""}


## Manifest bertanda tangan satu game: {ok, raw, sig, error}
func fetch_manifest(id: String) -> Dictionary:
	var m := await get_bytes("/v1/games/%s/manifest" % id.uri_encode())
	if not m.ok:
		return {"ok": false, "error": m.error}
	var sig := await get_bytes("/v1/games/%s/manifest.sig" % id.uri_encode())
	if not sig.ok:
		return {"ok": false, "error": "Tanda tangan manifest tidak bisa diambil: " + str(sig.error)}
	return {"ok": true, "raw": m.body, "sig": (sig.body as PackedByteArray).get_string_from_utf8(), "error": ""}


## Progres game di server (butuh login). {ok, status, data: Dictionary}
func progress_get(id: String) -> Dictionary:
	var r := await _request(HTTPClient.METHOD_GET, "/v1/games/%s/progress" % id.uri_encode(), "", true, TIMEOUT_SEC)
	r["data"] = _json(r.body)
	return r


func progress_put(id: String, data: Dictionary, schema: int, updated_at: String) -> Dictionary:
	var body := JSON.stringify({"data": data, "schema_version": schema, "updated_at": updated_at})
	var r := await _request(HTTPClient.METHOD_POST, "/v1/games/%s/progress" % id.uri_encode(), body, true, TIMEOUT_SEC)
	r["data"] = _json(r.body)
	return r


func has_login() -> bool:
	return _token() != ""


func _request(method: HTTPClient.Method, path: String, body: String, auth: bool, timeout: float) -> Dictionary:
	var base := base_url()
	if base == "":
		return {"ok": false, "status": 0, "body": PackedByteArray(), "error": "Alamat server belum diatur"}
	if auth and _token() == "":
		return {"ok": false, "status": 401, "body": PackedByteArray(), "error": "Belum masuk"}
	var req := HTTPRequest.new()
	req.timeout = timeout
	req.max_redirects = 0
	req.body_size_limit = 4 * 1024 * 1024
	add_child(req)
	var headers := PackedStringArray(["Accept: application/json",
		"X-Client-Version: " + str(ProjectSettings.get_setting("application/config/version", ""))])
	if body != "":
		headers.append("Content-Type: application/json")
	if auth:
		headers.append("Authorization: Bearer " + _token())
	if req.request(base + path, headers, method, body) != OK:
		req.queue_free()
		return {"ok": false, "status": 0, "body": PackedByteArray(), "error": "Permintaan gagal dikirim"}
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "body": PackedByteArray(), "error": "Server tidak terjangkau"}
	var code := int(res[1])
	var raw: PackedByteArray = res[3]
	if code < 200 or code >= 300:
		var msg := str(_json(raw).get("error", "Server menjawab %d" % code))
		return {"ok": false, "status": code, "body": raw, "error": msg}
	return {"ok": true, "status": code, "body": raw, "error": ""}


static func _json(raw: PackedByteArray) -> Dictionary:
	var v = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
	return v if typeof(v) == TYPE_DICTIONARY else {}
