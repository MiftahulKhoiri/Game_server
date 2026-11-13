extends Node
## Klien HTTP untuk server Game_server. Kontrak lengkap: docs/API.md
##
## Semua fungsi mengembalikan Dictionary:
##   sukses: {"ok": true,  "status": 200, "data": {...}}
##   gagal:  {"ok": false, "status": 409, "error": "pesan", "data": {...}}  (status 0 = tidak terhubung)
## Pemakaian: var res: Dictionary = await Api.get_me()

const Version = preload("res://scripts/version.gd")

var base_url: String = DEFAULT_URL
## Alamat bawaan (v0.77.1): server di Pi lewat Tailscale Funnel dengan HTTPS sah, bisa dari mana saja (tidak hanya
## wifi rumah) dan memungkinkan APK rilis (APK rilis menolak http:// biasa).
const DEFAULT_URL := "https://raspberrypi.tail3e263f.ts.net:8443"
## Alamat bawaan lama (wifi rumah, http://): tersimpan di HP lama, otomatis diganti DEFAULT_URL.
const OLD_DEFAULT_URL := "http://192.168.225.3:8090"
var token: String = ""
## Dikirim ke server di setiap permintaan; server menolak (426) bila di bawah batas minimum.
var client_version: String = Version.app_version()

## Koneksi ke server (roadmap no. 231-232): false setelah permintaan gagal karena jaringan, true lagi saat
## permintaan berikutnya berhasil. Layar dunia menampilkan pemberitahuan dan menyelaraskan ulang data.
var online := true
signal connection_changed(is_online: bool)
## Token ditolak server (sesi kedaluwarsa / dicabut dari perangkat lain): pemain harus masuk lagi.
signal session_expired(message: String)
## Jeda percobaan ulang GET saat jaringan putus (detik); 0 = tanpa ulang (dipakai uji).
var retry_delay := 1.5


## Daftar perangkat yang sedang masuk ke akun ini: {"sessions": [{created, last_used, current}], "idle_days"}.
func sessions_get() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/sessions", null, true)


## Keluarkan akun dari semua perangkat lain. {"revoked": N}
func logout_others() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/logout/others", null, true)


## Ganti kata sandi (sesi di perangkat lain ikut dicabut). Sukses = 204.
func change_password(old_pw: String, new_pw: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/players/me/password", {"old": old_pw, "new": new_pw}, true)


func health() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/healthz", null, false)


## Info versi server: {"server", "commit", "api", "min_client", "latest_client", "update_url"}
func version_info() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/version", null, false)


## Daftar akun baru. Jawaban sukses: {"player", "token"}.
func register(player_name: String, email: String, password: String) -> Dictionary:
	var body := {"name": player_name, "email": email, "password": password}
	return await _call(HTTPClient.METHOD_POST, "/v1/players", body, false)


## Masuk dengan nama ATAU email. Jawaban sukses: {"player", "token"} (token baru untuk HP ini).
## 401 = salah, 429 = terlalu banyak percobaan (pesan error memuat lama tunggu).
func login(login_name: String, password: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/login", {"login": login_name, "password": password}, false)


## Mencabut token HP ini di server (token di perangkat lain tetap hidup). Sukses = 204.
func logout() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/logout", null, true)


func get_me() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/players/me", null, true)


func save(version: int, state: Dictionary) -> Dictionary:
	var body := {"version": version, "state": state}
	return await _call(HTTPClient.METHOD_PUT, "/v1/players/me/save", body, true)


## Ganti pahlawan yang dipakai (id dari scripts/heroes.gd). 409 bila sedang bertarung.
func set_hero(hero: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/players/me/hero", {"hero": hero}, true)


## Ganti variasi pakaian pahlawan (0..3).
func set_outfit(outfit: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/players/me/outfit", {"outfit": outfit}, true)


## Resep tempa, pohon kemampuan, dan daftar pencapaian (roadmap no. 139, 145, 150).
func progress_get() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/progress", null, true)


func craft(recipe: String, qty := 1) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/craft", {"recipe": recipe, "qty": qty}, true)


func learn_talent(talent: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/talent", {"talent": talent}, true)


func claim_achievement(id: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/achievements/claim", {"achievement": id}, true)


## Beli rumah di Desa Awal (500 emas).
func house_buy() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/house/buy", null, true)


# --- ekonomi (roadmap no. 171-185): bank, peti simpan, perdagangan antarpemain ---

func bank(deposit: bool, amount: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/bank/deposit" if deposit else "/v1/bank/withdraw", {"amount": amount}, true)


func storage(put: bool, item: String, qty: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/storage/put" if put else "/v1/storage/take", {"item": item, "qty": qty}, true)


func world_events() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/world/events", null, true)


func world_secret(id: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/world/secret", {"id": id}, true)


func raid_claim() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/world/raid/claim", null, true)


func trades_get() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/trades", null, true)


func trade_offer(to: String, item: String, qty: int, price: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/trades", {"to": to, "item": item, "qty": qty, "price": price}, true)


## accept = true: beli tawaran masuk; false: batalkan (tawaran sendiri) / tolak (tawaran masuk).
func trade_finish(id: int, accept: bool) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/trades/accept" if accept else "/v1/trades/cancel", {"id": id}, true)


## Catat pembicaraan dengan warga (ingatan + keakraban di server).
func warga_talk(warga: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/warga/talk", {"warga": warga}, true)


## Beli pahlawan sebagai pendamping.
func buy_ally(hero: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/allies/buy", {"hero": hero}, true)


## Gunakan satu ramuan kesehatan untuk menyembuhkan pendamping yang dipasang (termasuk yang tumbang).
func heal_ally(hero: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/allies/heal", {"hero": hero}, true)


## Bicara dengan Kapten Rimba di kem hutan: server memberi Radar Musuh dan membuka pertarungan di Hutan Lebat.
## Cerita utama: bicara dengan NPC cerita / memakai benda cerita (server memeriksa posisi tersimpan).
func story_talk(npc: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/story/talk", {"npc": npc}, true)


func hutan_brief() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/hutan/brief", {}, true)


## Pasang `count` prajurit (0..jumlah yang dimiliki) untuk ikut bertarung; sisanya menunggu di kem.
func deploy_soldiers(count: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/soldiers/deploy", {"count": count}, true)


## Beli satu prajurit biasa untuk pasukan.
func buy_soldier() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/soldiers/buy", {}, true)


## Mulai latihan di Aula Pelatihan: kind "pahlawan" (target = id pahlawan) atau "prajurit".
func train_start(kind: String, target := "") -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/train/start", {"kind": kind, "target": target}, true)


## Ambil hasil latihan yang sudah selesai.
func train_claim(kind: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/train/claim", {"kind": kind}, true)


## Jam server (detik Unix), untuk menghitung sisa waktu latihan.
func server_time() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/time", null, false)


## Tetapkan pendamping yang dipasang (urutan = urutan berbaris di belakang pemain).
func set_party(party: Array) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/party", {"party": party}, true)


## Pertarungan yang sedang berjalan (404 bila tidak ada).
func battle_get() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/battle", null, true)


## Mulai pertarungan dengan musuh acak (409 bila sudah ada yang berjalan).
## boss = true: lawan bos di petak pemain (422 bila tidak ada bos di sana).
## enemy = id musuh berkeliaran yang disentuh pemain (dipakai server bila sah di peta dan levelnya).
func battle_start(boss := false, enemy := "") -> Dictionary:
	var body: Variant = null
	if boss:
		body = {"boss": true}
	elif enemy != "":
		body = {"enemy": enemy}
	return await _call(HTTPClient.METHOD_POST, "/v1/battle/start", body, true)


## action: "attack" | "defend" | "skill1" | "skill2" | "potion" | "flee" | "dodge"
func battle_action(action: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/battle/action", {"action": action}, true)


## Pakai ramuan di luar pertarungan.
func inventory_use(item: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/inventory/use", {"item": item}, true)


## Pasang perlengkapan dari tas.
func inventory_equip(item: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/inventory/equip", {"item": item}, true)


## Lepas perlengkapan dari slot ("weapon", "armor", atau "helmet").
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


## Benda dunia yang sedang hancur dan peti yang sudah dibuka di sebuah peta.
func world_state(map_id: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/world?map=" + map_id.uri_encode(), null, true)


## Melaporkan benda yang dihancurkan (maks. 12). `objects`: [{kind, x, z}]. Server mengundi hadiahnya.
func world_break(map_id: String, pos: Vector2, yaw: float, objects: Array) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/world/break", {"map": map_id, "fx": pos.x, "fz": pos.y, "yaw": yaw, "objects": objects}, true)


## Membuka peti harta (pemain harus dekat).
func world_chest(chest_id: String, map_id: String, pos: Vector2, yaw: float) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/world/chest", {"id": chest_id, "map": map_id, "fx": pos.x, "fz": pos.y, "yaw": yaw}, true)


## Daftar barang dan harga toko.
func shop_get(shop := "toko") -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/v1/shop?shop=" + shop, null, true)


## Seluruh daftar barang (nama, jenis, bonus) untuk ransel, bukan katalog satu toko.
func item_catalog() -> Dictionary:
	return await shop_get("semua")


func shop_buy(item: String, qty: int, shop := "toko") -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/shop/buy", {"shop": shop, "item": item, "qty": qty}, true)


## Tukar Berlian dengan barang yang dijual toko itu (butuh ceil(harga / 500) berlian).
func shop_barter(item: String, qty: int, shop := "toko") -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/shop/barter", {"shop": shop, "item": item, "qty": qty}, true)


func shop_sell(item: String, qty: int, shop := "toko") -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/shop/sell", {"shop": shop, "item": item, "qty": qty}, true)


func _call(method: HTTPClient.Method, path: String, body: Variant, auth: bool) -> Dictionary:
	var res := await _call_once(method, path, body, auth)
	# GET aman diulang sekali bila jaringan sempat putus (mis. pindah Wi-Fi ke data seluler).
	if int(res.status) == 0 and method == HTTPClient.METHOD_GET and retry_delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(retry_delay).timeout
		res = await _call_once(method, path, body, auth)
	_track(res, auth, path)
	return res


func _track(res: Dictionary, auth: bool, path: String) -> void:
	var now_online := int(res.status) != 0
	if now_online != online:
		online = now_online
		connection_changed.emit(online)
	if auth and int(res.status) == 401 and token != "" and path != "/v1/players/me/password":
		session_expired.emit(str(res.get("error", "Sesi berakhir; silakan masuk lagi")))


func _call_once(method: HTTPClient.Method, path: String, body: Variant, auth: bool) -> Dictionary:
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

	var text := raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if text.strip_edges() != "" else null  # 204: tanpa isi
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data}
	# "data" ikut dikembalikan: pada 426 berisi min_client dan update_url.
	return {"ok": false, "status": status, "data": data,
			"error": str(data.get("error", "Kesalahan %d" % status))}
