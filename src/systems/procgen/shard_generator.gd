## Seeded rooms-and-corridors generator for Shards (GDD §11). Emits a map
## entry in the same shape as `content/maps/*.json` (rows, legend, spawn
## marker, enemy placements) plus `extraction`, `rooms` and `generation`
## metadata, so the world loads a Shard exactly like a handcrafted map.
##
## Guarantees (checked by [ShardValidator] and the seed-sweep tests):
## every walkable cell is reachable from the spawn, the extraction pad is
## reachable, debris never cuts a corridor, enemies are reachable and at
## least `min_spawn_distance` from the spawn.
class_name ShardGenerator
extends RefCounted

## Bump when the same template, seed and depth would lay out differently:
## saves made inside a Shard carry it and are refused across a change (D-080).
const LAYOUT_VERSION := 1

const WALL := "#"
const FLOOR := "."
const GRATE := ","
const DEBRIS := "x"
const SPAWN := "P"
const EXIT := "E"
const SECRET := "?"
const VAULT := "V"
const WAYPOINT := "W"
const MERCHANT := "M" # floor under the merchant; kept out of the placement pools

const N4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const RING: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

var rng := RandomNumberGenerator.new()
var width: int = 0
var height: int = 0
var cells := PackedStringArray()
var rooms: Array[Rect2i] = []
## Characters that count as floor for reachability and placement: the base
## floor and grate plus every surface char a template declares.
var floor_chars: Dictionary = {FLOOR: true, GRATE: true}
var corridor_width: int = 1


## `depth` (Beacon level) adds depth-1 enemy groups and pickups.
## `extra_pickups`: pickup ids placed once each (quest sites), after the pool.
static func generate(template: Dictionary, seed_value: int, depth: int = 1, extra_pickups: Array[String] = []) -> Dictionary:
	var g := ShardGenerator.new()
	return g._run(template, seed_value, maxi(depth, 1), extra_pickups)


func _run(template: Dictionary, seed_value: int, depth: int, extra_pickups: Array[String] = []) -> Dictionary:
	rng.seed = seed_value
	var size: Dictionary = template.get("size", {})
	width = _pick(size.get("width", [40, 52]))
	height = _pick(size.get("height", [30, 40]))
	cells.resize(width * height)
	cells.fill(WALL)
	rooms.clear()
	floor_chars = {FLOOR: true, GRATE: true}

	var room_spec: Dictionary = template.get("rooms", {})
	_place_rooms(room_spec)
	var oval := String(room_spec.get("style", "box")) == "oval"
	for r: Rect2i in rooms:
		if oval:
			_fill_oval(r, FLOOR)
		else:
			_fill(r, FLOOR)
	var corridor_spec: Dictionary = template.get("corridors", {})
	corridor_width = clampi(int(corridor_spec.get("width", 1)), 1, 3)
	for i: int in range(1, rooms.size()):
		_carve_corridor(_center(rooms[i - 1]), _center(rooms[i]))
	var loops := _pick(corridor_spec.get("extra_loops", [1, 3]))
	for _i: int in loops:
		if rooms.size() >= 3:
			var a := rng.randi_range(0, rooms.size() - 1)
			var b := rng.randi_range(0, rooms.size() - 1)
			if a != b:
				_carve_corridor(_center(rooms[a]), _center(rooms[b]))

	var grate_chance := float(template.get("grate_patch_chance", 0.35))
	for r: Rect2i in rooms:
		if rng.randf() < grate_chance:
			_grate_patch(r)
	var surface_legend := _surface_patches(template.get("surfaces", {}))

	var spawns := _spawn_cells(rooms[0], 4)
	for s: Vector2i in spawns:
		_put(s, SPAWN)

	_scatter_debris(float(template.get("debris_density", 0.04)))

	var dist := _distances(spawns[0])
	_wall_unreachable(dist)

	var exit_cell := _extraction_cell(dist)
	_put(exit_cell, EXIT)

	var features_spec: Dictionary = template.get("features", {})
	var max_dist := 0
	for d: int in dist:
		max_dist = maxi(max_dist, d)
	var far := int(round(float(max_dist) * clampf(float(features_spec.get("ramp_far_fraction", 0.0)), 0.0, 1.0)))

	# Features first: they change the layout (pockets, relay and merchant
	# cells), and the layout must not depend on depth or quest extras.
	var feature_taken: Array[Vector2i] = []
	var features := _carve_features(features_spec, spawns, dist, exit_cell, feature_taken, template.get("pickups", {}), max_dist)

	var enemy_spec: Dictionary = template.get("enemies", {})
	var min_dist := int(enemy_spec.get("min_spawn_distance", 10))
	var enemies := _place_enemies(enemy_spec, spawns, dist, min_dist, depth, exit_cell, far)
	var taken: Array[Vector2i] = feature_taken.duplicate()
	for e: Dictionary in enemies:
		var raw: Array = e["cell"]
		taken.append(Vector2i(int(raw[0]), int(raw[1])))
	var pickups := _place_pickups(template.get("pickups", {}), spawns, dist, taken, depth - 1)
	for p: Dictionary in pickups:
		var raw: Array = p["cell"]
		taken.append(Vector2i(int(raw[0]), int(raw[1])))
	pickups.append_array(_place_extra_pickups(extra_pickups, spawns, dist, taken))
	var rarity_weights: Dictionary = features_spec.get("rarity", {})
	for p: Dictionary in pickups:
		var r := _roll_rarity(rarity_weights)
		if r != "common":
			p["rarity"] = r
	pickups.append_array(features["pickups"])

	var tiles: Dictionary = template.get("tiles", {})
	var template_id := String(template.get("id", "shard"))
	var room_list: Array = []
	for r: Rect2i in rooms:
		room_list.append([r.position.x, r.position.y, r.size.x, r.size.y])
	var legend: Dictionary = {
		WALL: String(tiles.get("wall", "wall_rust")),
		FLOOR: String(tiles.get("floor", "floor_concrete")),
		GRATE: String(tiles.get("grate", "floor_grate")),
		DEBRIS: String(tiles.get("debris", "debris")),
		SPAWN: String(tiles.get("floor", "floor_concrete")),
		EXIT: String(tiles.get("extraction", "extraction_pad")),
		SECRET: String(tiles.get("secret_door", "secret_door")),
		VAULT: String(tiles.get("vault_door", "vault_door")),
		WAYPOINT: String(tiles.get("waypoint", "waypoint")),
		MERCHANT: String(tiles.get("floor", "floor_concrete")),
	}
	for ch: String in surface_legend:
		legend[ch] = surface_legend[ch]
	return {
		"id": "%s_%d" % [template_id, seed_value],
		"name": "%s #%d%s" % [String(template.get("name", "Shard")), seed_value, "" if depth <= 1 else " · depth %d" % depth],
		"biome": String(template.get("biome", "")),
		"spawn_marker": SPAWN,
		"legend": legend,
		"rows": _rows(),
		"enemies": enemies,
		"pickups": pickups,
		"extraction": [exit_cell.x, exit_cell.y],
		"rooms": room_list,
		"secrets": features["secrets"],
		"vaults": features["vaults"],
		"waypoints": features["waypoints"],
		"npcs": features["npcs"],
		"generation": {"template": template_id, "seed": seed_value, "depth": depth, "min_spawn_distance": min_dist, "ramp_far_distance": far, "ramp_origin": [spawns[0].x, spawns[0].y], "extra_pickups": extra_pickups.duplicate()},
	}


# --- rooms & corridors ---------------------------------------------------

func _place_rooms(spec: Dictionary) -> void:
	var target := _pick(spec.get("count", [7, 11]))
	var min_size: Array = spec.get("min", [4, 3])
	var max_size: Array = spec.get("max", [10, 7])
	var attempts := int(spec.get("attempts", 300))
	var tries := 0
	while rooms.size() < target and (tries < attempts or rooms.size() < 2) and tries < attempts * 10:
		tries += 1
		var w := rng.randi_range(int(min_size[0]), int(max_size[0]))
		var h := rng.randi_range(int(min_size[1]), int(max_size[1]))
		if w + 5 > width or h + 5 > height:
			continue
		var x := rng.randi_range(2, width - w - 3)
		var y := rng.randi_range(2, height - h - 3)
		var candidate := Rect2i(x, y, w, h)
		var overlaps := false
		for r: Rect2i in rooms:
			if candidate.grow(1).intersects(r):
				overlaps = true
				break
		if not overlaps:
			rooms.append(candidate)


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_line(a, corner)
	_carve_line(corner, b)


## Carves a straight corridor `corridor_width` cells wide (extra width on
## the +x or +y side, never into the outer wall ring).
func _carve_line(a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var side := Vector2i(0, 1) if step.x != 0 else Vector2i(1, 0)
	var p := a
	while true:
		for w: int in corridor_width:
			var q := p + side * w
			if q.x >= 1 and q.y >= 1 and q.x < width - 1 and q.y < height - 1 and _cell_at(q) == WALL:
				_put(q, FLOOR)
		if p == b:
			break
		p += step


## Carves the ellipse inscribed in `r` (a rounded "hollow" instead of a box).
func _fill_oval(r: Rect2i, ch: String) -> void:
	var cx := float(r.position.x) + float(r.size.x - 1) / 2.0
	var cy := float(r.position.y) + float(r.size.y - 1) / 2.0
	var rx := maxf(float(r.size.x) / 2.0, 1.0)
	var ry := maxf(float(r.size.y) / 2.0, 1.0)
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_put(Vector2i(x, y), ch)


func _grate_patch(r: Rect2i) -> void:
	var w := rng.randi_range(2, maxi(2, r.size.x - 1))
	var h := rng.randi_range(2, maxi(2, r.size.y - 1))
	var x := rng.randi_range(r.position.x, maxi(r.position.x, r.end.x - w))
	var y := rng.randi_range(r.position.y, maxi(r.position.y, r.end.y - h))
	for yy: int in range(y, mini(y + h, r.end.y)):
		for xx: int in range(x, mini(x + w, r.end.x)):
			if _cell_at(Vector2i(xx, yy)) == FLOOR:
				_put(Vector2i(xx, yy), GRATE)


# --- spawn, debris, reachability ------------------------------------------

func _spawn_cells(room: Rect2i, count: int) -> Array[Vector2i]:
	var center := _center(room)
	var candidates: Array[Vector2i] = []
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			candidates.append(Vector2i(x, y))
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
	var out: Array[Vector2i] = []
	for c: Vector2i in candidates:
		if out.size() >= count:
			break
		if _walkable(c):
			out.append(c)
	return out


func _scatter_debris(density: float) -> void:
	if density <= 0.0:
		return
	for y: int in range(1, height - 1):
		for x: int in range(1, width - 1):
			var p := Vector2i(x, y)
			var ch := _cell_at(p)
			if not floor_chars.has(ch):
				continue
			if rng.randf() >= density:
				continue
			if _is_simple_point(p):
				_put(p, DEBRIS)


## True when removing `p` from the walkable set cannot disconnect anything:
## its walkable ring neighbours stay 4-connected through the ring alone.
func _is_simple_point(p: Vector2i) -> bool:
	var walkable_idx: Array[int] = []
	for i: int in RING.size():
		if _walkable(p + RING[i]):
			walkable_idx.append(i)
	if walkable_idx.size() <= 1:
		return true
	# Ring positions are listed clockwise; consecutive indices are 4-adjacent
	# only when one of them is an orthogonal (odd index) neighbour... simpler:
	# BFS over ring cells using actual 4-adjacency of their coordinates.
	var seen: Dictionary = {walkable_idx[0]: true}
	var frontier: Array[int] = [walkable_idx[0]]
	while not frontier.is_empty():
		var i: int = frontier.pop_back()
		for j: int in walkable_idx:
			if seen.has(j):
				continue
			var d: Vector2i = RING[i] - RING[j]
			if absi(d.x) + absi(d.y) == 1:
				seen[j] = true
				frontier.append(j)
	return seen.size() == walkable_idx.size()


## 4-connected BFS distances from `origin` over walkable cells; -1 = unreachable.
func _distances(origin: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	dist[_idx(origin)] = 0
	var frontier: Array[Vector2i] = [origin]
	var head := 0
	while head < frontier.size():
		var cur := frontier[head]
		head += 1
		for d: Vector2i in N4:
			var n := cur + d
			if not _in_bounds(n) or not _walkable(n) or dist[_idx(n)] >= 0:
				continue
			dist[_idx(n)] = dist[_idx(cur)] + 1
			frontier.append(n)
	return dist


func _wall_unreachable(dist: PackedInt32Array) -> void:
	for y: int in height:
		for x: int in width:
			var p := Vector2i(x, y)
			if _walkable(p) and dist[_idx(p)] < 0:
				_put(p, WALL)
			elif _cell_at(p) == DEBRIS and dist[_idx(p)] < 0 and not _has_reachable_neighbour(p, dist):
				_put(p, WALL)


func _has_reachable_neighbour(p: Vector2i, dist: PackedInt32Array) -> bool:
	for d: Vector2i in RING:
		var n := p + d
		if _in_bounds(n) and _walkable(n) and dist[_idx(n)] >= 0:
			return true
	return false


## The reachable floor cell nearest the centre of the farthest room.
func _extraction_cell(dist: PackedInt32Array) -> Vector2i:
	var best_room := -1
	var best_d := -1
	for i: int in range(1, rooms.size()):
		var c := _nearest_reachable(_center(rooms[i]), rooms[i], dist)
		if c.x < 0:
			continue
		var d := dist[_idx(c)]
		if d > best_d:
			best_d = d
			best_room = i
	if best_room < 0:
		# Single-room shard: farthest reachable cell anywhere.
		var far := Vector2i(-1, -1)
		for y: int in height:
			for x: int in width:
				var p := Vector2i(x, y)
				if floor_chars.has(_cell_at(p)) and dist[_idx(p)] > best_d:
					best_d = dist[_idx(p)]
					far = p
		return far
	return _nearest_reachable(_center(rooms[best_room]), rooms[best_room], dist)


func _nearest_reachable(center: Vector2i, room: Rect2i, dist: PackedInt32Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_len := 1 << 30
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var p := Vector2i(x, y)
			var ch := _cell_at(p)
			if floor_chars.has(ch) and dist[_idx(p)] >= 0:
				var l := (p - center).length_squared()
				if l < best_len:
					best_len = l
					best = p
	return best


# --- enemies ---------------------------------------------------------------

## `depth` 1 is the base population; each depth past it adds a group, raises
## the elite chance (`elite_chance_per_depth`, capped at `elite_chance_max`)
## and, from `boss.min_depth`, posts the template's boss beside the pad.
## `far` (walking steps from the spawn) is the difficulty ramp: groups
## placed past it are one larger and are the only ones that roll elites.
func _place_enemies(spec: Dictionary, spawns: Array[Vector2i], dist: PackedInt32Array, min_dist: int, depth: int = 1, exit_cell: Vector2i = Vector2i(-1, -1), far: int = 0) -> Array:
	var out: Array = []
	var pool: Array = spec.get("pool", [])
	if pool.is_empty() or rooms.size() < 2:
		return out
	var extra_groups := maxi(depth, 1) - 1
	var groups := _pick(spec.get("groups", [4, 7])) + extra_groups
	var size_range: Array = spec.get("group_size", [1, 3])
	var base_elite_chance := minf(float(spec.get("elite_chance_per_depth", 0.0)) * float(extra_groups), float(spec.get("elite_chance_max", 0.0)))
	var taken: Dictionary = {}
	var boss: Dictionary = spec.get("boss", {})
	if not boss.is_empty() and depth >= int(boss.get("min_depth", 99)) and exit_cell.x >= 0:
		var post := _boss_post(exit_cell, spawns, min_dist, dist)
		if post.x >= 0:
			taken[post] = true
			out.append({"type": String(boss.get("type", "")), "cell": [post.x, post.y], "tier": "boss"})
	for _g: int in groups:
		var room := rooms[rng.randi_range(1, rooms.size() - 1)]
		var candidates: Array[Vector2i] = []
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				var p := Vector2i(x, y)
				var ch := _cell_at(p)
				if floor_chars.has(ch) and dist[_idx(p)] >= 0 and not taken.has(p) \
						and _distance_to_any(p, spawns) >= min_dist:
					candidates.append(p)
		var centre := _center(room)
		var room_far := far > 0 and dist[_idx(centre)] >= far
		var n := rng.randi_range(int(size_range[0]), int(size_range[1])) + (1 if room_far else 0)
		for _i: int in n:
			if candidates.is_empty():
				break
			var k := rng.randi_range(0, candidates.size() - 1)
			var cell: Vector2i = candidates[k]
			candidates.remove_at(k)
			taken[cell] = true
			var placement: Dictionary = {"type": _weighted_pick(pool), "cell": [cell.x, cell.y]}
			var past_ramp := far <= 0 or dist[_idx(cell)] >= far
			if base_elite_chance > 0.0 and past_ramp and rng.randf() < base_elite_chance:
				placement["tier"] = "elite"
			out.append(placement)
	return out


## The floor cell nearest the extraction pad (not the pad itself) that is
## reachable and far enough from every spawn; (-1, -1) when none.
func _boss_post(exit_cell: Vector2i, spawns: Array[Vector2i], min_dist: int, dist: PackedInt32Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y: int in height:
		for x: int in width:
			var p := Vector2i(x, y)
			if p == exit_cell or not floor_chars.has(_cell_at(p)) or dist[_idx(p)] < 0:
				continue
			if _distance_to_any(p, spawns) < min_dist:
				continue
			var d := LineOfSight.distance(p, exit_cell)
			if d < best_d or (d == best_d and (p.y < best.y or (p.y == best.y and p.x < best.x))):
				best = p
				best_d = d
	return best


## Collectibles anywhere reachable except spawn, exit and enemy cells.
func _place_pickups(spec: Dictionary, spawns: Array[Vector2i], dist: PackedInt32Array, taken: Array[Vector2i], extra: int = 0) -> Array:
	var out: Array = []
	var pool: Array = spec.get("pool", [])
	if pool.is_empty() or rooms.is_empty():
		return out
	var count := _pick(spec.get("count", [3, 6])) + extra
	var used: Dictionary = {}
	for c: Vector2i in taken:
		used[c] = true
	for s: Vector2i in spawns:
		used[s] = true
	for _i: int in count:
		var room := rooms[rng.randi_range(0, rooms.size() - 1)]
		var candidates: Array[Vector2i] = []
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				var p := Vector2i(x, y)
				var ch := _cell_at(p)
				if floor_chars.has(ch) and dist[_idx(p)] >= 0 and not used.has(p):
					candidates.append(p)
		if candidates.is_empty():
			continue
		var cell: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		used[cell] = true
		out.append({"type": _weighted_pick(pool), "cell": [cell.x, cell.y]})
	return out


static func _distance_to_any(p: Vector2i, cells_list: Array[Vector2i]) -> int:
	var best := 1 << 30
	for c: Vector2i in cells_list:
		best = mini(best, LineOfSight.distance(p, c))
	return best


func _weighted_pick(pool: Array) -> String:
	var total := 0.0
	for e: Dictionary in pool:
		total += float(e.get("weight", 1))
	var roll := rng.randf() * total
	for e: Dictionary in pool:
		roll -= float(e.get("weight", 1))
		if roll <= 0.0:
			return String(e.get("type", ""))
	return String(Dictionary(pool[pool.size() - 1]).get("type", ""))


# --- grid helpers ----------------------------------------------------------

func _rows() -> Array:
	var rows: Array = []
	for y: int in height:
		var row := ""
		for x: int in width:
			row += cells[y * width + x]
		rows.append(row)
	return rows


func _pick(span: Variant) -> int:
	var arr: Array = span if span is Array else [span, span]
	var lo := int(arr[0])
	var hi := int(arr[arr.size() - 1])
	return rng.randi_range(mini(lo, hi), maxi(lo, hi))


func _fill(r: Rect2i, ch: String) -> void:
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			_put(Vector2i(x, y), ch)


static func _center(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


func _idx(p: Vector2i) -> int:
	return p.y * width + p.x


func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func _cell_at(p: Vector2i) -> String:
	return cells[_idx(p)] if _in_bounds(p) else WALL


func _put(p: Vector2i, ch: String) -> void:
	if _in_bounds(p):
		cells[_idx(p)] = ch


func _walkable(p: Vector2i) -> bool:
	var ch := _cell_at(p)
	return ch == SPAWN or ch == EXIT or floor_chars.has(ch)


## Surface patches (mana pools, conduits, biogrowth, catwalks) carved into
## room floors. Returns the legend additions {char: tile id}.
## spec: {"patches": [2, 4], "pool": [{"tile": "mana_pool", "char": "m", "weight": 2}, ...]}
func _surface_patches(spec: Dictionary) -> Dictionary:
	var legend: Dictionary = {}
	var pool: Array = spec.get("pool", [])
	if pool.is_empty() or rooms.is_empty():
		return legend
	for e: Dictionary in pool:
		var c := String(e.get("char", "?"))
		legend[c] = String(e.get("tile", ""))
		floor_chars[c] = true
	var patches := _pick(spec.get("patches", [2, 4]))
	for _i: int in patches:
		var e: Dictionary = pool[_weighted_index(pool)]
		var ch := String(e.get("char", "?"))
		var r := rooms[rng.randi_range(0, rooms.size() - 1)]
		var w := rng.randi_range(1, maxi(1, mini(3, r.size.x - 1)))
		var h := rng.randi_range(1, maxi(1, mini(3, r.size.y - 1)))
		var x := rng.randi_range(r.position.x, maxi(r.position.x, r.end.x - w))
		var y := rng.randi_range(r.position.y, maxi(r.position.y, r.end.y - h))
		for yy: int in range(y, mini(y + h, r.end.y)):
			for xx: int in range(x, mini(x + w, r.end.x)):
				var p := Vector2i(xx, yy)
				if floor_chars.has(_cell_at(p)):
					_put(p, ch)
	return legend


func _weighted_index(pool: Array) -> int:
	var total := 0.0
	for e: Dictionary in pool:
		total += float(e.get("weight", 1))
	var roll := rng.randf() * total
	for i: int in pool.size():
		roll -= float(Dictionary(pool[i]).get("weight", 1))
		if roll <= 0.0:
			return i
	return pool.size() - 1


## One placement per id in rooms other than the spawn room, far from spawn
## when possible; falls back to any reachable floor cell.
func _place_extra_pickups(ids: Array[String], spawns: Array[Vector2i], dist: PackedInt32Array, taken: Array[Vector2i]) -> Array:
	var out: Array = []
	if ids.is_empty():
		return out
	var used: Dictionary = {}
	for c: Vector2i in taken:
		used[c] = true
	for s: Vector2i in spawns:
		used[s] = true
	for id: String in ids:
		var candidates: Array[Vector2i] = []
		for i: int in range(1 if rooms.size() > 1 else 0, rooms.size()):
			var r := rooms[i]
			for y: int in range(r.position.y, r.end.y):
				for x: int in range(r.position.x, r.end.x):
					var p := Vector2i(x, y)
					if floor_chars.has(_cell_at(p)) and dist[_idx(p)] >= 0 and not used.has(p):
						candidates.append(p)
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := dist[_idx(a)]
			var db := dist[_idx(b)]
			return da > db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
		var cell: Vector2i = candidates[rng.randi_range(0, mini(candidates.size() - 1, 5))]
		used[cell] = true
		out.append({"type": id, "cell": [cell.x, cell.y]})
	return out



# --- features: secrets, vaults, waypoints, merchant, rarity -----------------

## Carves the Shard features after the walk graph is final. Pockets are dug
## out of solid wall next to a room and sealed by a door tile, so they are
## unreachable until the door opens (the validator proves it). Returns
## {"secrets", "vaults", "waypoints", "npcs", "pickups"}.
func _carve_features(spec: Dictionary, spawns: Array[Vector2i], dist: PackedInt32Array, exit_cell: Vector2i, taken: Array[Vector2i], pickup_spec: Dictionary, max_dist: int) -> Dictionary:
	var out: Dictionary = {"secrets": [], "vaults": [], "waypoints": [], "npcs": [], "pickups": []}
	if spec.is_empty() or rooms.size() < 2:
		return out
	var pool: Array = pickup_spec.get("pool", [])
	var secrets := _pick(spec.get("secrets", [0, 0]))
	for _i: int in secrets:
		var pocket := _carve_pocket(SECRET, 1, dist)
		if pocket.is_empty():
			break
		var cells: Array = pocket["cells"]
		var entry: Dictionary = {"door": pocket["door"], "cells": cells}
		if not pool.is_empty():
			var c: Array = cells[0]
			var pickup: Dictionary = {"type": _weighted_pick(pool), "cell": c}
			var r := _roll_rarity(spec.get("rarity", {}))
			if r != "common":
				pickup["rarity"] = r
			out["pickups"].append(pickup)
		out["secrets"].append(entry)
	var vaults := _pick(spec.get("vaults", [0, 0]))
	var vault_rarity := String(spec.get("vault_rarity", "rare"))
	for _i: int in vaults:
		var pocket := _carve_pocket(VAULT, 2, dist)
		if pocket.is_empty():
			break
		var cells: Array = pocket["cells"]
		var cost: Dictionary = {}
		for key: String in spec.get("vault_cost", {"ciphers": 1}):
			cost[key] = int(Dictionary(spec.get("vault_cost", {"ciphers": 1}))[key])
		out["vaults"].append({"door": pocket["door"], "cells": cells, "cost": cost})
		if not pool.is_empty():
			for c: Array in cells:
				out["pickups"].append({"type": _weighted_pick(pool), "cell": c, "rarity": _at_least(_roll_rarity(spec.get("rarity", {})), vault_rarity)})
	var waypoints := _pick(spec.get("waypoints", [0, 0]))
	var exit_dist := dist[_idx(exit_cell)]
	for i: int in waypoints:
		var target := int(round(float(exit_dist) * float(i + 1) / float(waypoints + 1)))
		var w := _cell_near_distance(target, dist, spawns, exit_cell, taken)
		if w.x < 0:
			break
		_put(w, WAYPOINT)
		taken.append(w)
		out["waypoints"].append([w.x, w.y])
	var merchant := String(spec.get("merchant", ""))
	if not merchant.is_empty():
		var m := _cell_near_distance(int(round(float(exit_dist) * 0.5)), dist, spawns, exit_cell, taken)
		if m.x >= 0:
			_put(m, MERCHANT)
			taken.append(m)
			out["npcs"].append({"merchant": merchant, "cell": [m.x, m.y]})
	return out


## Digs a `depth_cells`-deep pocket into solid wall off a random room edge,
## sealed by a door char on the room side. {} when no wall is thick enough.
func _carve_pocket(door_char: String, depth_cells: int, dist: PackedInt32Array) -> Dictionary:
	for _attempt: int in 60:
		var room := rooms[rng.randi_range(0, rooms.size() - 1)]
		var side := rng.randi_range(0, 3)
		var dir := N4[side]
		var x := rng.randi_range(room.position.x, room.end.x - 1)
		var y := rng.randi_range(room.position.y, room.end.y - 1)
		var inside := Vector2i(x, y)
		# Walk to the room edge in `dir`.
		while _walkable(inside + dir) and room.has_point(inside + dir):
			inside += dir
		if not _walkable(inside) or dist[_idx(inside)] < 0:
			continue
		var door := inside + dir
		var cells: Array[Vector2i] = []
		for k: int in range(1, depth_cells + 1):
			cells.append(door + dir * k)
		if not _pocket_is_sealed(door, cells, dir):
			continue
		_put(door, door_char)
		var raw_cells: Array = []
		for c: Vector2i in cells:
			_put(c, FLOOR)
			raw_cells.append([c.x, c.y])
		return {"door": [door.x, door.y], "cells": raw_cells}
	return {}


## The door and every pocket cell must be wall inside the border. Every
## neighbour of a pocket cell must be wall or part of the pocket; the door
## may touch the room only on its room side (the opening and its two
## flanks), so nothing reaches the pocket around the door.
func _pocket_is_sealed(door: Vector2i, cells: Array[Vector2i], dir: Vector2i) -> bool:
	var all: Array[Vector2i] = [door]
	all.append_array(cells)
	var along := Vector2i(dir.y, dir.x)
	var room_side: Array[Vector2i] = [door - dir, door - dir + along, door - dir - along]
	for c: Vector2i in all:
		if c.x < 1 or c.y < 1 or c.x >= width - 1 or c.y >= height - 1:
			return false
		if _cell_at(c) != WALL:
			return false
	for c: Vector2i in cells:
		for d: Vector2i in RING:
			var n := c + d
			if all.has(n):
				continue
			if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height or _cell_at(n) != WALL:
				return false
	for d: Vector2i in RING:
		var n := door + d
		if all.has(n) or room_side.has(n):
			continue
		if _cell_at(n) != WALL:
			return false
	return true


## A reachable floor cell whose walking distance from the spawn is closest
## to `target`, not taken, not a spawn or the exit. (-1, -1) when none.
func _cell_near_distance(target: int, dist: PackedInt32Array, spawns: Array[Vector2i], exit_cell: Vector2i, taken: Array[Vector2i]) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_gap := 1 << 30
	for y: int in height:
		for x: int in width:
			var p := Vector2i(x, y)
			if _cell_at(p) != FLOOR or dist[_idx(p)] < 0 or taken.has(p) or spawns.has(p) or p == exit_cell:
				continue
			var gap := absi(dist[_idx(p)] - target)
			if gap < best_gap:
				best = p
				best_gap = gap
	return best


func _roll_rarity(weights: Dictionary) -> String:
	var roll := rng.randf()
	var epic := float(weights.get("epic", 0.0))
	var rare := float(weights.get("rare", 0.0))
	if roll < epic:
		return "epic"
	if roll < epic + rare:
		return "rare"
	return "common"


static func _at_least(rarity: String, floor_rarity: String) -> String:
	var order: Array[String] = ["common", "rare", "epic"]
	return rarity if order.find(rarity) >= order.find(floor_rarity) else floor_rarity


## A template with a `remix` block draws its enemy pool from every listed
## family (non-boss entries with awareness, weight 1 each) and its surface
## pool from every listed template (S34, D-089). Returns a new template;
## one without the block comes back as it is.
static func expand_remix(template: Dictionary, registry: ContentRegistry) -> Dictionary:
	if not template.has("remix"):
		return template
	var remix: Dictionary = template["remix"]
	var out := template.duplicate(true)
	var enemies: Dictionary = Dictionary(out.get("enemies", {})).duplicate(true)
	var pool: Array = []
	for family: String in remix.get("families", []):
		for e: Dictionary in registry.get_all("enemies"):
			if String(e.get("family", "")) != family or String(e.get("tier", "")) == "boss" or int(e.get("awareness", 5)) <= 0:
				continue
			pool.append({"type": String(e["id"]), "weight": 1})
	if not pool.is_empty():
		enemies["pool"] = pool
	out["enemies"] = enemies
	var surfaces: Dictionary = Dictionary(out.get("surfaces", {})).duplicate(true)
	var seen: Dictionary = {}
	var spool: Array = []
	for id: String in remix.get("templates", []):
		var other := registry.get_entry("shards", id)
		for p: Dictionary in Dictionary(other.get("surfaces", {})).get("pool", []):
			var tile := String(p.get("tile", ""))
			if tile.is_empty() or seen.has(tile):
				continue
			seen[tile] = true
			spool.append({"tile": tile, "char": String(p.get("char", "s")), "weight": int(p.get("weight", 1))})
	if not spool.is_empty():
		surfaces["pool"] = spool
	out["surfaces"] = surfaces
	return out
