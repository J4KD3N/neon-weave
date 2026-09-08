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

const WALL := "#"
const FLOOR := "."
const GRATE := ","
const DEBRIS := "x"
const SPAWN := "P"
const EXIT := "E"

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


static func generate(template: Dictionary, seed_value: int) -> Dictionary:
	var g := ShardGenerator.new()
	return g._run(template, seed_value)


func _run(template: Dictionary, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	var size: Dictionary = template.get("size", {})
	width = _pick(size.get("width", [40, 52]))
	height = _pick(size.get("height", [30, 40]))
	cells.resize(width * height)
	cells.fill(WALL)
	rooms.clear()

	_place_rooms(template.get("rooms", {}))
	for r: Rect2i in rooms:
		_fill(r, FLOOR)
	for i: int in range(1, rooms.size()):
		_carve_corridor(_center(rooms[i - 1]), _center(rooms[i]))
	var loops := _pick(Dictionary(template.get("corridors", {})).get("extra_loops", [1, 3]))
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

	var spawns := _spawn_cells(rooms[0], 4)
	for s: Vector2i in spawns:
		_put(s, SPAWN)

	_scatter_debris(float(template.get("debris_density", 0.04)))

	var dist := _distances(spawns[0])
	_wall_unreachable(dist)

	var exit_cell := _extraction_cell(dist)
	_put(exit_cell, EXIT)

	var enemy_spec: Dictionary = template.get("enemies", {})
	var min_dist := int(enemy_spec.get("min_spawn_distance", 10))
	var enemies := _place_enemies(enemy_spec, spawns, dist, min_dist)

	var tiles: Dictionary = template.get("tiles", {})
	var template_id := String(template.get("id", "shard"))
	var room_list: Array = []
	for r: Rect2i in rooms:
		room_list.append([r.position.x, r.position.y, r.size.x, r.size.y])
	return {
		"id": "%s_%d" % [template_id, seed_value],
		"name": "%s #%d" % [String(template.get("name", "Shard")), seed_value],
		"biome": String(template.get("biome", "")),
		"spawn_marker": SPAWN,
		"legend": {
			WALL: String(tiles.get("wall", "wall_rust")),
			FLOOR: String(tiles.get("floor", "floor_concrete")),
			GRATE: String(tiles.get("grate", "floor_grate")),
			DEBRIS: String(tiles.get("debris", "debris")),
			SPAWN: String(tiles.get("floor", "floor_concrete")),
			EXIT: String(tiles.get("extraction", "extraction_pad")),
		},
		"rows": _rows(),
		"enemies": enemies,
		"extraction": [exit_cell.x, exit_cell.y],
		"rooms": room_list,
		"generation": {"template": template_id, "seed": seed_value, "min_spawn_distance": min_dist},
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


func _carve_line(a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	while true:
		if _cell_at(p) == WALL:
			_put(p, FLOOR)
		if p == b:
			break
		p += step


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
			if ch != FLOOR and ch != GRATE:
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
				if _cell_at(p) == FLOOR and dist[_idx(p)] > best_d:
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
			if (ch == FLOOR or ch == GRATE) and dist[_idx(p)] >= 0:
				var l := (p - center).length_squared()
				if l < best_len:
					best_len = l
					best = p
	return best


# --- enemies ---------------------------------------------------------------

func _place_enemies(spec: Dictionary, spawns: Array[Vector2i], dist: PackedInt32Array, min_dist: int) -> Array:
	var out: Array = []
	var pool: Array = spec.get("pool", [])
	if pool.is_empty() or rooms.size() < 2:
		return out
	var groups := _pick(spec.get("groups", [4, 7]))
	var size_range: Array = spec.get("group_size", [1, 3])
	var taken: Dictionary = {}
	for _g: int in groups:
		var room := rooms[rng.randi_range(1, rooms.size() - 1)]
		var candidates: Array[Vector2i] = []
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				var p := Vector2i(x, y)
				var ch := _cell_at(p)
				if (ch == FLOOR or ch == GRATE) and dist[_idx(p)] >= 0 and not taken.has(p) \
						and _distance_to_any(p, spawns) >= min_dist:
					candidates.append(p)
		var n := rng.randi_range(int(size_range[0]), int(size_range[1]))
		for _i: int in n:
			if candidates.is_empty():
				break
			var k := rng.randi_range(0, candidates.size() - 1)
			var cell: Vector2i = candidates[k]
			candidates.remove_at(k)
			taken[cell] = true
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
	return ch == FLOOR or ch == GRATE or ch == SPAWN or ch == EXIT
