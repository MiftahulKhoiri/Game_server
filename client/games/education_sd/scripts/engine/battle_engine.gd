extends RefCounted
## Battle Engine — pertarungan bergiliran berbasis pengetahuan (dokumen induk §6). Murni data.
## Giliran pemain: serang (fisik) | ilmu (jurus ilmu: jawab soal) | bertahan | barang (kue/ramuan/perisai) | kabur.
## Lalu giliran musuh (kecuali pertarungan selesai). Prinsip ramah anak:
##   - Jawaban salah = jurus gagal saja (tidak ada kerusakan untuk pemain, barang tidak hilang).
##   - Kalah = pingsan lalu bangun di desa dengan HP penuh; tidak ada progres atau barang yang hilang.
##   - Bos punya perisai yang hanya bisa ditembus jurus ilmu; serangan berat bos diberi aba-aba dulu
##     sehingga anak bisa memilih Bertahan.
##   - Kesulitan menyesuaikan: setiap kalah dari musuh yang sama, serangan musuh itu berkurang 15% (maks 45%).

const PHYS_SHIELDED := 0.25  # serangan fisik saat perisai bos aktif
const SHIELD_DOWN_TURNS := 2
const HEAVY := 1.6

var rng := RandomNumberGenerator.new()
var player: Dictionary = {}
var enemy: Dictionary = {}
var def: Dictionary = {}
var turn := 0
var over := false
var won := false
var fled := false
var history: Array = []
var heavy_next := false


## stats: dari RewardEngine.stats(p). monster: definisi dari monstersN.json. ease: 0..3 (kali kalah sebelumnya).
func start(stats: Dictionary, monster_id: String, monster: Dictionary, ease := 0, seed_value := -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	def = monster
	player = {"hp": int(stats.hp), "max": int(stats.hp), "atk": int(stats.atk), "def": int(stats.def), "ilmu": int(stats.ilmu),
		"guard": 1.0, "boost": 1.0}
	var soften := 1.0 - 0.15 * clampi(ease, 0, 3)
	enemy = {"id": monster_id, "name": str(monster.name), "hp": int(monster.hp), "max": int(monster.hp),
		"atk": maxi(1, int(round(int(monster.atk) * soften))), "def": int(monster.def), "boss": bool(monster.get("boss", false)),
		"shield": bool(monster.get("boss", false)) and str(monster.get("shield", "")) != "", "shield_down": 0}
	turn = 0
	over = false
	won = false
	fled = false
	heavy_next = false
	history = [str(monster.get("taunt", "%s muncul!" % str(monster.name)))]


func _roll(base: float) -> int:
	return maxi(1, int(round(base * rng.randf_range(0.85, 1.15))))


func shield_up() -> bool:
	return bool(enemy.shield) and int(enemy.shield_down) <= 0


## Kerusakan serangan fisik pemain (sebelum acak).
func phys_base() -> float:
	var b := maxf(1.0, float(player.atk) - float(enemy.def) * 0.5)
	return b * (PHYS_SHIELDED if shield_up() else 1.0)


## Jurus ilmu. correct = akhirnya benar; first_try = benar tanpa salah.
func ilmu_base(correct: bool, first_try: bool) -> float:
	if not correct:
		return 0.0
	return float(player.ilmu) * (1.6 if first_try else 0.8) * float(player.boost)


## Satu aksi pemain + balasan musuh. Mengembalikan catatan {player_dmg, enemy_dmg, healed, text: [..]}.
func act(action: String, arg := {}) -> Dictionary:
	var out := {"player_dmg": 0, "enemy_dmg": 0, "healed": 0, "text": []}
	if over:
		return out
	turn += 1
	player.guard = 1.0
	match action:
		"serang":
			var d := _roll(phys_base())
			enemy.hp = maxi(0, int(enemy.hp) - d)
			out.enemy_dmg = d
			out.text.append("Kamu menyerang! %s kena %d." % [str(enemy.name), d] + (" Perisainya menahan sebagian besar seranganmu!" if shield_up() else ""))
		"ilmu":
			var ok := bool(arg.get("correct", false))
			var ft := bool(arg.get("first_try", false))
			if ok:
				var d2 := _roll(ilmu_base(true, ft))
				enemy.hp = maxi(0, int(enemy.hp) - d2)
				out.enemy_dmg = d2
				out.text.append(("Jurus ilmu sempurna! " if ft else "Jurus ilmu berhasil! ") + "%s kena %d." % [str(enemy.name), d2])
				player.boost = 1.0
				if bool(enemy.shield):
					if shield_up():
						out.text.append("%s hancur! Sekarang seranganmu terasa penuh." % str(def.get("shield", "Perisai")))
					enemy.shield_down = SHIELD_DOWN_TURNS + 1
			else:
				out.text.append("Jurus ilmu belum berhasil. Tidak apa-apa, coba lagi di giliran berikutnya!")
		"bertahan":
			player.guard = 0.5
			var h := maxi(1, int(round(int(player.max) * 0.05)))
			player.hp = mini(int(player.max), int(player.hp) + h)
			out.healed = h
			out.text.append("Kamu bertahan dan mengatur napas (+%d HP)." % h)
		"barang":
			var item := str(arg.get("item", ""))
			var power := int(arg.get("power", 0))
			match str(arg.get("use", "")):
				"heal":
					var before := int(player.hp)
					player.hp = mini(int(player.max), int(player.hp) + power)
					out.healed = int(player.hp) - before
					out.text.append("Kamu memakai %s (+%d HP)." % [str(arg.get("name", item)), int(out.healed)])
				"boost":
					player.boost = float(power)
					out.text.append("Kamu meminum %s. Jurus ilmu berikutnya jauh lebih kuat!" % str(arg.get("name", item)))
				"guard":
					player.guard = 1.0 - power / 100.0
					out.text.append("Kamu memasang %s." % str(arg.get("name", item)))
		"kabur":
			if bool(enemy.boss):
				out.text.append("Tidak bisa kabur dari pertarungan bos!")
			else:
				fled = true
				over = true
				out.text.append("Kamu berlari menjauh dengan selamat.")
				history.append_array(out.text)
				return out
	if int(enemy.hp) <= 0:
		over = true
		won = true
		out.text.append("%s kalah!" % str(enemy.name))
		history.append_array(out.text)
		return out
	_enemy_turn(out)
	history.append_array(out.text)
	return out


func _enemy_turn(out: Dictionary) -> void:
	var mult := 1.0
	if heavy_next:
		mult = HEAVY
		heavy_next = false
	var d := _roll(maxf(1.0, float(enemy.atk) - float(player.def) * 0.5) * mult * float(player.guard))
	player.hp = maxi(0, int(player.hp) - d)
	out.player_dmg = d
	out.text.append(("%s memukul sekuat tenaga! Kamu kena %d." if mult > 1.0 else "%s menyerang. Kamu kena %d.") % [str(enemy.name), d])
	if int(enemy.shield_down) > 0:
		enemy.shield_down = int(enemy.shield_down) - 1
		if int(enemy.shield_down) == 0:
			out.text.append("%s memasang %s lagi!" % [str(enemy.name), str(def.get("shield", "perisai"))])
	var every := int(def.get("heavy_every", 0))
	if every > 0 and (turn + 1) % every == 0:
		heavy_next = true
		out.text.append("%s mengangkat tongkatnya tinggi-tinggi... Bersiaplah! (Pilih Bertahan)" % str(enemy.name))
	if int(player.hp) <= 0:
		over = true
		won = false
		out.text.append("Kamu kelelahan dan pingsan... Tenang, kamu akan bangun di desa dengan HP penuh.")


## Hadiah menang: {xp, coins, drop}. Bila kalah/kabur: kosong.
func rewards(rng_drop: RandomNumberGenerator = null) -> Dictionary:
	if not won:
		return {}
	var r := rng_drop if rng_drop != null else rng
	var drop := ""
	var dd: Dictionary = def.get("drop", {})
	if not dd.is_empty() and r.randf() < float(dd.get("chance", 0.0)):
		drop = str(dd.item)
	return {"xp": int(def.get("xp", 0)), "coins": int(def.get("coins", 0)), "drop": drop}
