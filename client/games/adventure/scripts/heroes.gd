extends RefCounted
## Daftar pahlawan yang bisa dipilih pemain. Harus sama dengan internal/game/hero.go di server
## (server yang menyimpan pilihan dan memakai nama skill di log pertarungan).
## id = nama model di assets/models/<id>.glb.

const DEFAULT := "ksatria"
## Pendamping yang boleh dipasang sekaligus (sama dengan MaxParty di internal/game/ally.go).
const MAX_PARTY := 3

const LIST := [
	{"id": "ksatria", "price": 250, "name": "Ksatria", "short": "Ksatria", "weapon": "Pedang dan perisai",
		"story": "Prajurit kerajaan yang seimbang: tangguh dan tenang.",
		"skill1": "Tebasan Kuat", "skill2": "Perisai Cahaya", "style": "pedang"},
	{"id": "pendekar_kapak", "price": 350, "name": "Pendekar Kapak", "short": "Kapak", "weapon": "Kapak besar",
		"story": "Petarung liar dari pegunungan, mengandalkan ayunan kapak.",
		"skill1": "Belahan Kapak", "skill2": "Teriakan Perang", "style": "kapak"},
	{"id": "pemanah", "price": 300, "name": "Pemanah", "short": "Pemanah", "weapon": "Busur silang",
		"story": "Pemburu perempuan yang gesit dan membidik dari jauh.",
		"skill1": "Panah Tembus", "skill2": "Kabut Pelindung", "style": "busur"},
	{"id": "pendekar_tombak", "price": 300, "name": "Pendekar Tombak", "short": "Tombak", "weapon": "Tombak",
		"story": "Pendekar laki-laki berjangkauan panjang, tusukannya cepat.",
		"skill1": "Tusukan Kilat", "skill2": "Putaran Tombak", "style": "tombak"},
	{"id": "penyihir", "price": 400, "name": "Penyihir", "short": "Penyihir", "weapon": "Tongkat sihir",
		"story": "Pertapa muda dari menara timur; bola sihirnya menembus kulit batu.",
		"skill1": "Bola Api", "skill2": "Perisai Mantra", "style": "sihir"},
]

## Gaya senjata (sama dengan WeaponStyles di internal/game/combat_style.go): ciri serangan biasa.
const STYLE_INFO := {
	"pedang": "Seimbang",
	"kapak": "Lambat, pukulan berat",
	"busur": "Jarak jauh, mudah kritis",
	"tombak": "Cepat, jangkauan panjang",
	"sihir": "Jarak jauh, menembus pertahanan",
}


static func ids() -> Array:
	var out: Array = []
	for h: Dictionary in LIST:
		out.append(h.id)
	return out


## Data pahlawan; id tak dikenal / kosong memberi pahlawan bawaan.
static func get_hero(id: String) -> Dictionary:
	for h: Dictionary in LIST:
		if h.id == id:
			return h
	return LIST[0]


## Pahlawan yang sedang dipakai pemain.
static func current() -> Dictionary:
	return get_hero(str(Session.player.get("state", {}).get("hero", DEFAULT)))
