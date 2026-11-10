extends RefCounted
## Warga desa yang berjalan bebas (pemanis). Satu objek = satu warga: titik asal, tujuan
## berikutnya, jeda, dan modelnya. Gerak dihitung di sini supaya bisa diuji tanpa layar.
##
## Aturan: berjalan lurus ke titik acak dalam jari-jarinya (hanya lewat petak jalan/rumput/bunga,
## lihat Maps.warga_free), berhenti sebentar, lalu pilih tujuan baru. Berhenti dan
## menoleh bila pemain atau warga lain terlalu dekat di depannya.
##
## Kecerdasan (roadmap no. 45-55): jadwal harian (`jadwal`: pergi ke tempat kerja pada jam tertentu,
## bekerja di sana, lalu kembali), pekerja di tempat berjalan dari rumah ke tempat kerjanya tiap pagi,
## mengobrol dengan warga lain (start_chat), dan takut pada monster: menjauh, berteriak minta tolong
## bila pemain cukup dekat.

const Maps = preload("res://scripts/maps.gd")

## Awalan id lawan bicara (Session.talk_npc) untuk membedakan warga dari NPC misi.
const TALK_PREFIX := "warga:"
const PLAYER_GAP := 0.85   # jarak minimal ke pemain (petak)
const OTHER_GAP := 0.6     # jarak minimal ke warga lain
const NOTICE := 2.6        # jarak warga yang berhenti mulai menoleh ke pemain
const GREET := 1.9         # pemain sedekat ini: warga berhenti dan menoleh (supaya mudah diajak bicara)
const TURN_RATE := 7.0
const HOME_SPEED := 1.6    # pulang berjalan lebih cepat dari biasanya (pengali kecepatan)
const SCARE := 3.5         # monster sedekat ini: warga takut (no. 53)
const FLEE_MULT := 2.0     # lari menjauh lebih cepat (no. 54)
const HELP_RANGE := 9.0    # pemain sedekat ini: warga berteriak minta tolong (no. 55)
const CHAT_TIME := 3.5     # lama dua warga mengobrol (no. 50)
const KATA_EVERY := 7.0    # jeda kalimat gelembung saat bekerja

var id := ""              # kunci dialog (Maps.WARGA[].id)
var map_id := ""
var home := Vector2.ZERO
var radius := 3.0
var speed := 0.7
var pos := Vector2.ZERO
var yaw := 0.0
var walking := false
var door := Vector2i(-1, -1)  # petak pintu rumahnya (D); (-1,-1) = tidak punya rumah (tetap di luar)
var arah := Vector2i(0, 1)    # arah muka rumah: petak depan pintu = door + arah (rumah biasa menghadap selatan)
var terlihat := false         # tetap terlihat saat "di dalam" (penjaga berdiri di pos jaga yang terbuka)
var inside := false           # sedang di dalam rumah (malam): tidak terlihat dan tidak bisa diajak bicara
var nama := ""
var toko := ""                # penjaga toko: jenis toko yang dijaga ("toko", "makan", "rawat"); kosong = warga biasa
var diam := false             # penjaga toko: tetap berdiri di tempat (hanya menoleh ke pemain)
var peran := ""               # pekerjaan/identitas (roadmap no. 41), tampil di bawah nama
var kerja := ""               # gerakan berulang di tempat ("palu") atau pose siang ("duduk")
var malam := ""               # pose malam bagi warga tanpa rumah ("tidur")
var sleeping := false         # sedang tidur (pose malam "tidur"): tidak menoleh dan tidak bisa diajak bicara
var jadwal: Array = []        # [{dari, sampai, pos, kerja, hadap, kata}] (no. 45)
var job: Dictionary = {}      # jadwal yang sedang berjalan ({} = tidak ada)
var at_job := false           # sudah sampai di tempat kerja jadwalnya
var scared := 0.0             # > 0: sedang takut pada monster (no. 53)
var calling_help := false     # berteriak minta tolong pada pemain (no. 55)
var say := ""                 # kalimat di gelembung atas kepala ("" = tidak ada)
var say_t := 0.0
var chat_t := 0.0             # > 0: sedang mengobrol dengan warga lain (no. 50)
var chat_cd := 0.0            # jeda sebelum boleh mengobrol lagi
var lod_acc := 0.0            # waktu terkumpul untuk warga jauh yang diperbarui jarang (no. 60)
var steps := 0                # berapa kali step() dijalankan (uji optimasi)
var node: Node3D            # wadah di dunia (posisi); model di dalamnya yang berputar
var model: Node3D
var bubble: Label3D         # gelembung kalimat

var _target := Vector2.ZERO
var _has_target := false
var _wait := 0.0
var _route: Array[Vector2] = []
var _route_done := false
var _rng := RandomNumberGenerator.new()
var _home_yaw := 0.0
var _noticed := false        # pemain dekat: pekerja berhenti bekerja dan menoleh
var _going_work := false     # pekerja di tempat: berjalan dari rumah ke tempat kerjanya (no. 47)
var _returning := false      # kembali ke sekitar rumah setelah jadwal/kabur
var _travel: Array[Vector2] = []
var _travel_goal := Vector2(-999, -999)
var _chat_face := Vector2.ZERO
var _kata_t := 0.0
var _kata_i := 0
var _travel_wait := 0.0
const TRAVEL_WAIT := 2.5


func _init(def: Dictionary, seed_value: int) -> void:
	id = str(def.id)
	map_id = str(def.map)
	home = def.pos
	if def.has("rumah"):
		door = def.rumah
	if def.has("arah"):
		arah = def.arah
	terlihat = bool(def.get("terlihat", false))
	nama = str(def.name)
	toko = str(def.get("toko", ""))
	diam = bool(def.get("diam", false))
	peran = str(def.get("peran", ""))
	kerja = str(def.get("kerja", ""))
	malam = str(def.get("malam", ""))
	jadwal = def.get("jadwal", [])
	radius = float(def.radius)
	speed = float(def.speed)
	pos = home
	_rng.seed = seed_value
	_wait = _rng.randf_range(0.0, 2.5)  # tidak semua mulai berjalan serentak
	yaw = deg_to_rad(float(def.hadap)) if def.has("hadap") else _rng.randf_range(-PI, PI)
	_home_yaw = yaw
	chat_cd = _rng.randf_range(3.0, 12.0)


## Memilih tujuan baru yang bisa dicapai lurus dari posisi sekarang. false bila tak ada.
func _pick_target() -> bool:
	for _i in 12:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(1.0, radius)
		var cand := home + Vector2(cos(ang), sin(ang)) * dist
		if Maps.warga_free(map_id, cand) and Maps.warga_path_free(map_id, pos, cand):
			_target = cand
			_has_target = true
			return true
	return false


## Titik tepat di depan pintu rumah (petak di depan D menurut `arah`), tempat warga masuk dan keluar.
func front() -> Vector2:
	return Vector2(door.x + 0.5 + arah.x, door.y + 0.5 + arah.y)


## Tempat warga berhenti saat "di dalam": tengah petak pintu; untuk yang tetap terlihat (penjaga)
## setengah petak lebih dalam, supaya berdiri di bawah atap pos jaga.
func spot() -> Vector2:
	var c := Vector2(door.x + 0.5, door.y + 0.5)
	return c - Vector2(arah) * 0.5 if terlihat else c


## Jalur petak (pusat petak) dari posisi sekarang ke petak `goal`, lewat petak yang boleh dilalui warga.
## Kosong bila tak ada jalur. Pencarian melebar (BFS) pada kisi petak.
func _bfs(goal: Vector2i) -> Array[Vector2]:
	var start := Vector2i(int(floor(pos.x)), int(floor(pos.y)))
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	var found := start == goal
	while qi < queue.size() and not found and qi < 4000:
		var cur := queue[qi]
		qi += 1
		for d: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := cur + d
			if prev.has(n):
				continue
			if n != goal and not Maps.warga_free(map_id, Vector2(n.x + 0.5, n.y + 0.5)):
				continue
			prev[n] = cur
			if n == goal:
				found = true
				break
			queue.append(n)
	var out: Array[Vector2] = []
	if not found:
		return out
	if start == goal:
		return [Vector2(goal.x + 0.5, goal.y + 0.5)]
	var t := goal
	while t != start:
		out.push_front(Vector2(t.x + 0.5, t.y + 0.5))
		t = prev[t]
	return out


## Jalur ke depan pintu rumah.
func _route_home() -> Array[Vector2]:
	return _bfs(Vector2i(door.x + arah.x, door.y + arah.y))


## Berjalan menuju `goal` lewat jalur petak (dihitung sekali per tujuan). true bila sudah sampai.
## Tanpa jalur: langsung ke tujuan (tidak macet selamanya).
func _travel_to(goal: Vector2, delta: float, mult := 1.0, others: Array[Vector2] = []) -> bool:
	if goal != _travel_goal:
		_travel_goal = goal
		_travel = _bfs(Vector2i(int(floor(goal.x)), int(floor(goal.y))))
		if _travel.is_empty() and pos.distance_to(goal) > 0.6:
			pos = goal
			return true
		_travel.push_front(Vector2(floor(pos.x) + 0.5, floor(pos.y) + 0.5))  # ke tengah petak sendiri dulu
		_travel.append(goal)
	if _travel.is_empty():
		return true
	var nxt: Vector2 = _travel[0]
	var to := nxt - pos
	var dist := to.length()
	var stepd := maxf(speed, 0.6) * mult * delta
	# Warga lain di depan: tunggu sebentar (paling lama TRAVEL_WAIT detik, supaya tidak macet selamanya).
	var ahead := pos + to / maxf(dist, 0.001) * minf(stepd, dist)
	for o in others:
		if ahead.distance_to(o) < OTHER_GAP and ahead.distance_to(o) < pos.distance_to(o) and _travel_wait < TRAVEL_WAIT:
			_travel_wait += delta
			return false
	_travel_wait = 0.0
	if dist <= stepd + 0.02:
		pos = nxt
		_travel.remove_at(0)
		if _travel.is_empty():
			_travel_goal = Vector2(-999, -999)
			return true
	else:
		pos += to / dist * stepd
	walking = true
	if dist > 0.01:
		yaw = lerp_angle(yaw, atan2(to.x, to.y), minf(1.0, delta * TURN_RATE * 1.5))
	return false


## Berjalan pulang: ikuti jalur sampai depan pintu, lalu masuk (menghilang). Tidak menunggu pemain/warga lain
## (jalur petak sudah bebas rintangan), supaya tidak macet.
func _step_home(delta: float) -> void:
	if not _route_done:
		_route = _route_home()
		_route_done = true
		job = {}
		at_job = false
		_going_work = false
		_returning = false
		if _route.is_empty():
			inside = true  # tak ada jalur: langsung dianggap sudah di dalam
			return
		_route.append(spot())  # langkah terakhir: masuk lewat pintu
	_has_target = false
	var goal: Vector2 = _route[0]
	var to_goal := goal - pos
	var dist := to_goal.length()
	var stepd := maxf(speed, 0.6) * HOME_SPEED * delta
	if dist <= stepd + 0.02:
		pos = goal
		_route.remove_at(0)
		if _route.is_empty():
			inside = true
			walking = false
			if terlihat:
				yaw = atan2(arah.x, arah.y)  # berdiri menghadap jalan
			return
	else:
		pos += to_goal / dist * stepd
	walking = true
	if dist > 0.01:
		yaw = lerp_angle(yaw, atan2(to_goal.x, to_goal.y), minf(1.0, delta * TURN_RATE * 1.5))


## Pagi hari: keluar dari pintu dan mulai berjalan lagi. Pekerja di tempat berjalan ke tempat kerjanya.
func leave_home() -> void:
	inside = false
	_route = []
	_route_done = false
	pos = front()
	# Penghuni serumah tidak keluar di titik yang persis sama (mis. ayam sekandang): geser sedikit.
	for _i in 8:
		var cand := front() + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0.0, 0.5) * signf(arah.y + 0.01))
		if Maps.warga_free(map_id, cand):
			pos = cand
			break
	_has_target = false
	_wait = _rng.randf_range(0.5, 4.0)
	if diam:
		_going_work = true  # no. 47: pergi bekerja


## Jadwal yang berlaku pada jam `hour` (0-24), atau {}.
func job_at(hour: float) -> Dictionary:
	for j: Dictionary in jadwal:
		var a := float(j.dari)
		var b := float(j.sampai)
		if (a <= b and hour >= a and hour < b) or (a > b and (hour >= a or hour < b)):
			return j
	return {}


## Boleh diajak mengobrol oleh warga lain sekarang?
func can_chat() -> bool:
	return not diam and speed > 0.0 and id != "ayam" and not inside and not sleeping and chat_t <= 0.0 \
		and chat_cd <= 0.0 and job.is_empty() and scared <= 0.0 and not _returning


## Mulai mengobrol (no. 50): berhenti, menghadap lawan bicara, dan mengucapkan `line`.
func start_chat(face: Vector2, line: String) -> void:
	chat_t = CHAT_TIME
	chat_cd = _rng.randf_range(25.0, 45.0)
	_chat_face = face
	_has_target = false
	walking = false
	say = line
	say_t = CHAT_TIME


## Maju delta detik. `player` = posisi pemain, `others` = posisi warga lain, `night` = sudah malam
## (warga yang punya rumah pulang dan bermalam di dalam), `hour` = jam (untuk jadwal),
## `monsters` = posisi musuh di dekatnya.
func step(delta: float, player: Vector2, others: Array[Vector2], night := false, hour := 12.0, monsters: Array[Vector2] = []) -> void:
	steps += 1
	walking = false
	say_t = maxf(0.0, say_t - delta)
	if say_t <= 0.0:
		say = ""
	chat_cd = maxf(0.0, chat_cd - delta)
	if door.x >= 0:
		if night and not inside:
			_step_home(delta)
			return
		if not night and inside:
			leave_home()
		if inside:
			return
	if _react_monsters(delta, player, monsters):
		return
	sleeping = night and malam == "tidur"
	if sleeping:
		yaw = _home_yaw
		return
	if _going_work:
		if _travel_to(home, delta, 1.0, others):
			_going_work = false
			yaw = _home_yaw
		return
	if chat_t > 0.0:
		chat_t -= delta
		var tc := _chat_face - pos
		if tc.length() > 0.01:
			yaw = lerp_angle(yaw, atan2(tc.x, tc.y), minf(1.0, delta * TURN_RATE))
		return
	if _step_job(delta, player, hour, others):
		return
	if _returning:
		if _travel_to(home, delta, 1.0, others):
			_returning = false
		return
	if diam:  # penjaga toko / pekerja: di tempat, menoleh bila pemain mendekat, lalu kembali bekerja
		var near := pos.distance_to(player) < NOTICE
		var want := _home_yaw
		if near and kerja != "duduk":
			var tp := player - pos
			want = atan2(tp.x, tp.y)
		elif near:
			want = yaw
		if near or kerja != "":
			yaw = lerp_angle(yaw, want, minf(1.0, delta * TURN_RATE))
		_noticed = near
		return
	var want_yaw := yaw
	var face_player := false
	if pos.distance_to(player) < GREET:
		face_player = true  # menyapa: diam di tempat sambil menoleh ke pemain
	elif _wait > 0.0:
		_wait -= delta
		face_player = pos.distance_to(player) < NOTICE
	elif not _has_target:
		if not _pick_target():
			_wait = _rng.randf_range(0.8, 2.0)
	else:
		var to_target := _target - pos
		var dist := to_target.length()
		if dist < 0.06:
			_has_target = false
			_wait = _rng.randf_range(1.5, 5.0)
		else:
			var nxt := pos + to_target / dist * minf(speed * delta, dist)
			if _blocked(nxt, player, others):
				# ada yang menghalangi di depan: diam sebentar lalu cari arah lain
				_has_target = false
				_wait = _rng.randf_range(0.5, 1.2)
				face_player = pos.distance_to(player) < NOTICE
			else:
				pos = nxt
				walking = true
				want_yaw = atan2(to_target.x, to_target.y)
	if face_player:
		var tp := player - pos
		want_yaw = atan2(tp.x, tp.y)
	if walking or face_player:
		yaw = lerp_angle(yaw, want_yaw, minf(1.0, delta * TURN_RATE))


## Jadwal harian (no. 45-47, 51-52): pergi ke tempat kerja, bekerja sambil sesekali berkata-kata,
## lalu kembali ke sekitar rumah saat jadwal selesai. true bila jadwal sedang berjalan.
func _step_job(delta: float, player: Vector2, hour: float, others: Array[Vector2] = []) -> bool:
	var j := job_at(hour)
	if j.is_empty():
		if not job.is_empty():
			job = {}
			at_job = false
			_noticed = false
			_returning = pos.distance_to(home) > radius
		return false
	if j != job:
		job = j
		at_job = false
	if not at_job:
		if _travel_to(j.pos, delta, 1.0, others):
			at_job = true
			yaw = deg_to_rad(float(j.get("hadap", 0.0)))
			_kata_t = 1.0
		return true
	var near := pos.distance_to(player) < NOTICE
	_noticed = near and str(j.get("kerja", "")) != "duduk"
	var want := deg_to_rad(float(j.get("hadap", 0.0)))
	if _noticed:
		var tp := player - pos
		want = atan2(tp.x, tp.y)
	yaw = lerp_angle(yaw, want, minf(1.0, delta * TURN_RATE))
	var kata: Array = j.get("kata", [])
	_kata_t -= delta
	if _kata_t <= 0.0 and not kata.is_empty():
		say = str(kata[_kata_i % kata.size()])
		say_t = 3.2
		_kata_i += 1
		_kata_t = KATA_EVERY + _rng.randf_range(0.0, 3.0)
	return true


## Monster di dekat (no. 53-55): warga takut, berteriak (minta tolong bila pemain dekat), dan
## yang bisa berjalan menjauh dari monster. true bila sedang bereaksi (gerak lain ditunda).
func _react_monsters(delta: float, player: Vector2, monsters: Array[Vector2]) -> bool:
	var nearest := Vector2.ZERO
	var nd := SCARE
	for m in monsters:
		var d := pos.distance_to(m)
		if d < nd:
			nd = d
			nearest = m
	if nd >= SCARE:
		calling_help = false
		if scared > 0.0:
			scared -= delta
			if scared <= 0.0 and not diam and pos.distance_to(home) > radius:
				_returning = true
		return false
	scared = 2.0
	sleeping = false
	chat_t = 0.0
	calling_help = pos.distance_to(player) < HELP_RANGE
	say = "Tolong! Ada monster!" if calling_help else "Monster!"
	say_t = 0.6
	_has_target = false
	_travel_goal = Vector2(-999, -999)
	var away := pos - nearest
	away = away.normalized() if away.length() > 0.001 else Vector2(1, 0)
	if diam or speed <= 0.0:
		var tm := nearest - pos
		yaw = lerp_angle(yaw, atan2(tm.x, tm.y), minf(1.0, delta * TURN_RATE))
		return true
	for ang: float in [0.0, 0.6, -0.6, 1.3, -1.3]:
		var dir := away.rotated(ang)
		var nxt := pos + dir * speed * FLEE_MULT * delta
		if Maps.warga_free(map_id, nxt):
			pos = nxt
			walking = true
			yaw = lerp_angle(yaw, atan2(dir.x, dir.y), minf(1.0, delta * TURN_RATE * 1.5))
			break
	return true


## Langkah ke `nxt` ditolak bila menabrak penghalang, atau mendekati pemain/warga lain.
func _blocked(nxt: Vector2, player: Vector2, others: Array[Vector2]) -> bool:
	if not Maps.warga_free(map_id, nxt):
		return true
	if nxt.distance_to(player) < PLAYER_GAP and nxt.distance_to(player) < pos.distance_to(player):
		return true
	for o in others:
		if nxt.distance_to(o) < OTHER_GAP and nxt.distance_to(o) < pos.distance_to(o):
			return true
	return false


## Gerakan kerja yang sedang dilakukan: dari jadwal (di tempat kerja) atau pekerjaan tetapnya.
func current_kerja() -> String:
	if at_job and not job.is_empty():
		return str(job.get("kerja", ""))
	return kerja


## Menyalin keadaan ke node 3D.
func apply() -> void:
	if node == null or not is_instance_valid(node):
		return
	node.position = Vector3(pos.x, 0.0, pos.y)
	node.visible = terlihat or not inside
	if model != null and is_instance_valid(model):
		model.rotation.y = yaw
		if "moving" in model:
			model.moving = walking
		if model.has_method("set_pose"):
			model.call("set_pose", current_pose())
			var k := current_kerja()
			var busy := _noticed or k == "duduk" or walking or _going_work or scared > 0.0
			model.set("loop_action", "" if busy else k)
	if bubble != null and is_instance_valid(bubble):
		bubble.visible = say != "" and node.visible
		if say != "":
			bubble.text = say


## Pose model saat ini: tidur malam, duduk, atau berdiri.
func current_pose() -> String:
	if sleeping:
		return "tidur"
	if walking or _going_work:
		return ""
	return "duduk" if current_kerja() == "duduk" else ""
