extends RefCounted
## Alat petualangan (2.3.0): hadiah misi & ujian, disimpan di progres yang sama (world.inventory, world.equip).
## Satu alat dipakai sekaligus; tiap alat punya fungsi nyata di dunia 3D. Kostum/topi/aksesori tetap memakai
## toko koleksi lama (p.owned, p.player.avatar) — tidak ada mata uang atau sistem simpan baru.

const TOOLS := {
	"kompas": {"name": "Kompas Penjelajah", "desc": "Panah di layar menunjuk tujuan berikutnya.", "from": "Kalahkan Penjaga Kerajaan Matematika"},
	"kaca_pembesar": {"name": "Kaca Pembesar", "desc": "Benda tersembunyi membesar dan bersinar.", "from": "Kalahkan Penjaga Hutan Bahasa"},
	"senter": {"name": "Senter", "desc": "Menerangi jalan saat senja dan malam.", "from": "Kalahkan Penjaga Laboratorium IPA"},
	"teropong": {"name": "Teropong", "desc": "Kamera bisa ditarik lebih jauh untuk melihat sekeliling.", "from": "Kalahkan Penjaga Negeri Penjelajah IPS"},
	"sepatu": {"name": "Sepatu Petualang", "desc": "Berjalan dan berlari 15% lebih cepat.", "from": "Misi: kunjungi keempat pulau"},
	"jaring": {"name": "Jaring Ilmu", "desc": "Saat menjinakkan Pengacau Lupa, satu pilihan jawaban yang salah dihilangkan.", "from": "Misi: jinakkan 5 Pengacau Lupa"},
}

const BOSS_TOOL := {"matematika": "kompas", "bahasa": "kaca_pembesar", "ipa": "senter", "ips": "teropong"}


static func tool_name(id: String) -> String:
	return str(TOOLS.get(id, {}).get("name", id))


static func owned(p: Dictionary) -> Array:
	var out: Array = []
	for id in TOOLS:
		if (p.world.inventory as Dictionary).has(id):
			out.append(id)
	return out


static func give(p: Dictionary, id: String) -> bool:
	if not TOOLS.has(id) or (p.world.inventory as Dictionary).has(id):
		return false
	p.world.inventory[id] = true
	if str(p.world.equip.get("alat", "")) == "":
		p.world.equip["alat"] = id
	return true


static func equipped(p: Dictionary) -> String:
	var id := str(p.world.equip.get("alat", ""))
	return id if (p.world.inventory as Dictionary).has(id) else ""
