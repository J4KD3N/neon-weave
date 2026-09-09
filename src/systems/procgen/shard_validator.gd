## Proves a map entry (generated or handcrafted) is solvable under the game's
## movement rules: closed border, four spawn cells, an extraction pad reachable
## from the spawn, every walkable cell reachable (doors count as passable),
## enemies reachable, distinct, off the spawn/exit, and (for generated
## Shards) far enough from the spawn. Shard features have rules of their own:
## secrets and vaults are sealed until their door opens, waypoints are real
## relay tiles on the way, the merchant stands on reachable floor, elites
## only appear past the ramp distance, rarities are known.
class_name ShardValidator
extends RefCounted

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const RARITIES: Array[String] = ["common", "rare", "epic"]


static func validate(entry: Dictionary, tiles_by_id: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var map := MapData.parse(entry, tiles_by_id)
	errors.append_array(map.errors)
	if map.width == 0 or map.height == 0:
		return errors

	for x: int in map.width:
		if map.is_walkable(Vector2i(x, 0)) or map.is_walkable(Vector2i(x, map.height - 1)):
			errors.append("border open at column %d" % x)
			break
	for y: int in map.height:
		if map.is_walkable(Vector2i(0, y)) or map.is_walkable(Vector2i(map.width - 1, y)):
			errors.append("border open at row %d" % y)
			break

	var spawns := map.spawn_cells()
	if spawns.size() < 4:
		errors.append("only %d spawn cells" % spawns.size())
	if spawns.is_empty():
		return errors
	var reach := reachable_from(map, spawns[0], false)
	var reach_open := reachable_from(map, spawns[0], true)
	for s: Vector2i in spawns:
		if not reach.has(s):
			errors.append("spawn %s unreachable from %s" % [s, spawns[0]])

	var walkable := map.walkable_count()
	var reached_walkable := 0
	for c: Vector2i in reach_open:
		if map.is_walkable(c):
			reached_walkable += 1
	if reached_walkable != walkable:
		errors.append("%d of %d walkable cells unreachable from spawn even through doors" % [walkable - reached_walkable, walkable])

	var exit_cell := Vector2i(-1, -1)
	if entry.has("extraction"):
		var raw: Array = entry["extraction"]
		exit_cell = Vector2i(int(raw[0]), int(raw[1]))
		if not map.is_walkable(exit_cell):
			errors.append("extraction %s is not walkable" % exit_cell)
		elif not reach.has(exit_cell):
			errors.append("extraction %s unreachable without opening a door" % exit_cell)
		if spawns.has(exit_cell):
			errors.append("extraction on a spawn cell")

	var generation: Dictionary = entry.get("generation", {})
	var min_dist := int(generation.get("min_spawn_distance", 0))
	var far := int(generation.get("ramp_far_distance", 0))
	var ramp_origin := spawns[0]
	var raw_origin: Array = generation.get("ramp_origin", [])
	if raw_origin.size() == 2:
		ramp_origin = Vector2i(int(raw_origin[0]), int(raw_origin[1]))
	var walk := walking_distances(map, ramp_origin, true) # the generator's own metric and origin
	var seen: Array[Vector2i] = []
	var placements: Array = entry.get("enemies", [])
	for p: Dictionary in placements:
		var raw: Array = p.get("cell", [])
		if raw.size() != 2:
			errors.append("enemy placement without [x, y]")
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if not map.is_walkable(cell):
			errors.append("enemy %s on blocked %s" % [p.get("type"), cell])
		elif not reach.has(cell):
			errors.append("enemy %s unreachable at %s" % [p.get("type"), cell])
		if seen.has(cell):
			errors.append("two enemies on %s" % cell)
		if spawns.has(cell) or cell == exit_cell:
			errors.append("enemy on spawn/extraction %s" % cell)
		if min_dist > 0:
			for s: Vector2i in spawns:
				var d := LineOfSight.distance(cell, s)
				if d < min_dist:
					errors.append("enemy %s too close to spawn %s (%d < %d)" % [p.get("type"), s, d, min_dist])
					break
		if String(p.get("tier", "")) == "elite" and far > 0 and int(walk.get(cell, -1)) < far:
			errors.append("elite %s at %s is before the ramp (%d < %d)" % [p.get("type"), cell, int(walk.get(cell, -1)), far])
		seen.append(cell)

	var pocket_cells: Dictionary = {}
	for feature: String in ["secrets", "vaults"]:
		for f: Dictionary in entry.get(feature, []):
			var raw_door: Array = f.get("door", [])
			if raw_door.size() != 2:
				errors.append("%s without a door" % feature)
				continue
			var door := Vector2i(int(raw_door[0]), int(raw_door[1]))
			var kind := "secret" if feature == "secrets" else "vault"
			if map.door_kind(door) != kind:
				errors.append("%s door at %s is not a %s door tile" % [feature, door, kind])
			var touches := false
			for d: Vector2i in DIRS8:
				if reach.has(door + d):
					touches = true
			if not touches:
				errors.append("%s door at %s cannot be reached" % [feature, door])
			var cells: Array = f.get("cells", [])
			if cells.is_empty():
				errors.append("%s at %s has no interior" % [feature, door])
			for raw_c: Array in cells:
				var c := Vector2i(int(raw_c[0]), int(raw_c[1]))
				pocket_cells[c] = feature
				if not map.is_walkable(c):
					errors.append("%s interior %s is not walkable" % [feature, c])
				if reach.has(c):
					errors.append("%s interior %s is reachable without the door" % [feature, c])
				if not reach_open.has(c):
					errors.append("%s interior %s is unreachable even with the door open" % [feature, c])
			if feature == "vaults":
				var cost: Dictionary = f.get("cost", {})
				if cost.is_empty():
					errors.append("vault at %s has no cost" % door)
				for key: String in cost:
					if not Ledger.RESOURCES.has(key):
						errors.append("vault at %s costs unknown resource %s" % [door, key])

	var pickup_cells: Array[Vector2i] = []
	var vault_pickups := 0
	var pickups: Array = entry.get("pickups", [])
	for p: Dictionary in pickups:
		var raw: Array = p.get("cell", [])
		if raw.size() != 2:
			errors.append("pickup placement without [x, y]")
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		var pocket := String(pocket_cells.get(cell, ""))
		if not map.is_walkable(cell):
			errors.append("pickup %s on blocked %s" % [p.get("type"), cell])
		elif not reach_open.has(cell):
			errors.append("pickup %s unreachable at %s even through doors" % [p.get("type"), cell])
		elif pocket.is_empty() and not reach.has(cell) and map.door_cells("locked").is_empty():
			errors.append("pickup %s unreachable at %s" % [p.get("type"), cell])
		if pocket == "vaults":
			vault_pickups += 1
		if pickup_cells.has(cell) or seen.has(cell):
			errors.append("pickup shares %s" % cell)
		if spawns.has(cell) or cell == exit_cell:
			errors.append("pickup on spawn/extraction %s" % cell)
		var rarity := String(p.get("rarity", "common"))
		if not RARITIES.has(rarity):
			errors.append("pickup %s at %s has unknown rarity %s" % [p.get("type"), cell, rarity])
		pickup_cells.append(cell)
	if Array(entry.get("vaults", [])).size() > 0 and vault_pickups == 0:
		errors.append("vaults hold no pickups")

	var waypoints: Array = entry.get("waypoints", [])
	var wp_seen: Array[Vector2i] = []
	for raw_w: Array in waypoints:
		var w := Vector2i(int(raw_w[0]), int(raw_w[1]))
		if not map.is_waypoint(w):
			errors.append("waypoint %s is not a waypoint tile" % w)
		if not reach.has(w):
			errors.append("waypoint %s unreachable" % w)
		if spawns.has(w) or w == exit_cell:
			errors.append("waypoint %s on spawn/extraction" % w)
		if wp_seen.has(w):
			errors.append("two waypoints on %s" % w)
		if min_dist > 0 and int(walk.get(w, 0)) < min_dist / 2:
			errors.append("waypoint %s too close to the spawn" % w)
		wp_seen.append(w)

	for n: Dictionary in entry.get("npcs", []):
		if not n.has("merchant"):
			continue
		var raw_n: Array = n.get("cell", [])
		if raw_n.size() != 2:
			errors.append("merchant without [x, y]")
			continue
		var c := Vector2i(int(raw_n[0]), int(raw_n[1]))
		if not map.is_walkable(c) or not reach.has(c):
			errors.append("merchant %s unreachable at %s" % [n.get("merchant"), c])
		if seen.has(c) or pickup_cells.has(c) or spawns.has(c) or c == exit_cell:
			errors.append("merchant shares %s" % c)
	return errors


## Cells reachable from `origin` under exploration rules: 8-connected, no
## corner cutting past blocked cells. With `through_doors`, closed door
## tiles count as passable (what the Shard looks like once everything opens).
static func reachable_from(map: MapData, origin: Vector2i, through_doors: bool = false) -> Dictionary:
	var seen: Dictionary = {}
	if not map.is_walkable(origin):
		return seen
	seen[origin] = true
	var frontier: Array[Vector2i] = [origin]
	var head := 0
	while head < frontier.size():
		var cur := frontier[head]
		head += 1
		for d: Vector2i in DIRS8:
			var n := cur + d
			if seen.has(n) or not _passable(map, n, through_doors):
				continue
			if d.x != 0 and d.y != 0 and not (_passable(map, cur + Vector2i(d.x, 0), through_doors) and _passable(map, cur + Vector2i(0, d.y), through_doors)):
				continue
			seen[n] = true
			frontier.append(n)
	return seen


static func _passable(map: MapData, cell: Vector2i, through_doors: bool) -> bool:
	return map.is_walkable(cell) or (through_doors and not map.door_kind(cell).is_empty())


## Walking distance in steps from `origin` for every reachable cell (doors
## closed). `four_way` measures orthogonal steps only, the metric the
## generator uses for its ramp and waypoint distances.
static func walking_distances(map: MapData, origin: Vector2i, four_way: bool = false) -> Dictionary:
	var dist: Dictionary = {}
	if not map.is_walkable(origin):
		return dist
	dist[origin] = 0
	var frontier: Array[Vector2i] = [origin]
	var head := 0
	while head < frontier.size():
		var cur := frontier[head]
		head += 1
		for d: Vector2i in DIRS8:
			if four_way and d.x != 0 and d.y != 0:
				continue
			var n := cur + d
			if dist.has(n) or not map.is_walkable(n):
				continue
			if d.x != 0 and d.y != 0 and not (map.is_walkable(cur + Vector2i(d.x, 0)) and map.is_walkable(cur + Vector2i(0, d.y))):
				continue
			dist[n] = int(dist[cur]) + 1
			frontier.append(n)
	return dist
