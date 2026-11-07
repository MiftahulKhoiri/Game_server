extends RefCounted
## Gerak bebas di dunia 3D di atas petak yang sama dengan peta lama.
## Satuan dunia = 1 petak. Petak (x, y) mencakup x di [x, x+1) dan z di [y, y+1).
## Tabrakan dihitung sendiri (tanpa mesin fisika): pemain berupa kotak kecil yang
## tidak boleh menyentuh petak yang tidak bisa dilewati atau ditempati NPC.

const Maps = preload("res://scripts/maps.gd")

const RADIUS := 0.28
const MAX_STEP := 0.2  # langkah dipecah agar tidak menembus petak tipis saat lag


static func tile_blocked(map_id: String, tx: int, tz: int) -> bool:
	return not Maps.walkable(map_id, tx, tz) or Maps.npc_at(map_id, tx, tz) != "" or Maps.chest_at(map_id, tx, tz) != ""


## true bila pemain berpusat di p (x, z) menyentuh petak yang terhalang.
static func collides(map_id: String, p: Vector2) -> bool:
	for dx: float in [-RADIUS, RADIUS]:
		for dz: float in [-RADIUS, RADIUS]:
			if tile_blocked(map_id, floori(p.x + dx), floori(p.y + dz)):
				return true
	return false


## Menggeser p sebesar d. Sumbu x dan z dicoba terpisah, sehingga pemain
## meluncur menyusuri tembok alih-alih berhenti.
static func move(map_id: String, p: Vector2, d: Vector2) -> Vector2:
	var steps := maxi(1, ceili(d.length() / MAX_STEP))
	var step := d / steps
	for i in steps:
		var nx := Vector2(p.x + step.x, p.y)
		if not collides(map_id, nx):
			p = nx
		var nz := Vector2(p.x, p.y + step.y)
		if not collides(map_id, nz):
			p = nz
	return p


## Petak tempat titik p berada.
static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


## Tempat berdiri yang aman di sekitar tengah petak t: tengah petak itu, atau
## tengah petak terdekat yang bisa dilewati bila t terhalang.
static func safe_spot(map_id: String, t: Vector2i) -> Vector2:
	var center := Vector2(t) + Vector2(0.5, 0.5)
	if not collides(map_id, center):
		return center
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2(t + Vector2i(dx, dy)) + Vector2(0.5, 0.5)
				if not collides(map_id, c):
					return c
	return center
