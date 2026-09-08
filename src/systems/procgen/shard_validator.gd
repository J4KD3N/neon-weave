## Proves a map entry (generated or handcrafted) is solvable under the game's
## movement rules: closed border, four spawn cells, an extraction pad reachable
## from the spawn, every walkable cell reachable, enemies reachable, distinct,
## off the spawn/exit, and (for generated Shards) far enough from the spawn.
class_name ShardValidator
extends RefCounted

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


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
	var reach := reachable_from(map, spawns[0])
	for s: Vector2i in spawns:
		if not reach.has(s):
			errors.append("spawn %s unreachable from %s" % [s, spawns[0]])

	var walkable := map.walkable_count()
	if reach.size() != walkable:
		errors.append("%d of %d walkable cells unreachable from spawn" % [walkable - reach.size(), walkable])

	var exit_cell := Vector2i(-1, -1)
	if entry.has("extraction"):
		var raw: Array = entry["extraction"]
		exit_cell = Vector2i(int(raw[0]), int(raw[1]))
		if not map.is_walkable(exit_cell):
			errors.append("extraction %s is not walkable" % exit_cell)
		elif not reach.has(exit_cell):
			errors.append("extraction %s unreachable" % exit_cell)
		if spawns.has(exit_cell):
			errors.append("extraction on a spawn cell")

	var generation: Dictionary = entry.get("generation", {})
	var min_dist := int(generation.get("min_spawn_distance", 0))
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
		seen.append(cell)

	var pickup_cells: Array[Vector2i] = []
	var pickups: Array = entry.get("pickups", [])
	for p: Dictionary in pickups:
		var raw: Array = p.get("cell", [])
		if raw.size() != 2:
			errors.append("pickup placement without [x, y]")
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if not map.is_walkable(cell):
			errors.append("pickup %s on blocked %s" % [p.get("type"), cell])
		elif not reach.has(cell):
			errors.append("pickup %s unreachable at %s" % [p.get("type"), cell])
		if pickup_cells.has(cell) or seen.has(cell):
			errors.append("pickup shares %s" % cell)
		if spawns.has(cell) or cell == exit_cell:
			errors.append("pickup on spawn/extraction %s" % cell)
		pickup_cells.append(cell)
	return errors


## Cells reachable from `origin` under exploration rules: 8-connected, no
## corner cutting past blocked cells.
static func reachable_from(map: MapData, origin: Vector2i) -> Dictionary:
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
			if seen.has(n) or not map.is_walkable(n):
				continue
			if d.x != 0 and d.y != 0 and not (map.is_walkable(cur + Vector2i(d.x, 0)) and map.is_walkable(cur + Vector2i(0, d.y))):
				continue
			seen[n] = true
			frontier.append(n)
	return seen
