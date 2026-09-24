## An enemy standing in the world. Data comes from the `enemies` content
## kind; the map places instances by cell.
class_name EnemyActor
extends WorldActor

var enemy_id: String = ""
var entry: Dictionary = {}
var cell: Vector2i = Vector2i.ZERO
var archetype: String = "rusher"
var awareness: int = 5
## Awareness as a cone (S64, D-120): a placement may face the enemy a way
## ("facing": one of the eight names); then it sees a cone that wide around
## it and only hears close behind. No facing means it looks all round, as
## every enemy did before S64. `sweep` degrees swing the facing back and
## forth over `sweep_period` seconds. `noticed` is the detection meter.
var has_facing: bool = false
var facing_dir: Vector2i = Vector2i(0, 1)
var sweep: float = 0.0
var sweep_period: float = 4.0
var noticed: float = 0.0
var _sweep_time: float = 0.0
## A patrol (S65, D-121): cells walked in a loop from the placed cell, at
## `patrol_speed` cells a second with `patrol_wait` seconds at each point.
## The facing follows the walk, so the cone looks where the enemy goes; an
## enemy whose meter is up stops and turns toward what it saw.
var patrol: Array[Vector2i] = []
var patrol_index: int = 0
var patrol_speed: float = 1.0
var patrol_wait: float = 0.8
var _wait_left: float = 0.0
var _step_left: float = 0.0
var walk_target: Vector2 = Vector2.INF # where the node walks to between cells
var stats: Dictionary = {}
var abilities: Array[String] = []
## Tier ("", "elite", "boss") and the flat bonuses it and depth grant (StatBlock.for_enemy).
var tier: String = ""
var damage_bonus: int = 0
var ap_bonus: int = 0
## Entry traits (D-085): the same vocabulary as races, on any enemy.
var traits: Dictionary = {}


func setup(p_id: String, p_entry: Dictionary, p_cell: Vector2i, p_stats: Dictionary, default_awareness: int, sheet: SpriteSheet = null, tint_override: Color = Color.TRANSPARENT) -> void:
	enemy_id = p_id
	entry = p_entry
	cell = p_cell
	archetype = String(entry.get("archetype", "rusher"))
	awareness = int(entry.get("awareness", default_awareness))
	stats = p_stats
	var ab: Array = entry.get("abilities", [])
	abilities.assign(ab)
	max_hp = maxi(int(stats.get("hp", 1)), 1)
	hp = max_hp
	tier = String(stats.get("tier", ""))
	damage_bonus = int(stats.get("damage_bonus", 0))
	traits = Dictionary(entry.get("traits", {})).duplicate(true)
	ap_bonus = int(stats.get("ap_bonus", 0))
	name = "%s_%d_%d" % [enemy_id, cell.x, cell.y]
	var art: Dictionary = entry.get("art", {})
	var color := Color.html(String(art.get("color", "#c94b3a")))
	if tint_override.a > 0.0:
		color = tint_override
	var label := Loc.text(entry, "name", enemy_id)
	if tier == "elite":
		label = "Elite " + label
	build_visuals(label, color, String(art.get("shape", "capsule")), {}, sheet)


const FACINGS: Dictionary = {"e": Vector2i(1, 0), "se": Vector2i(1, 1), "s": Vector2i(0, 1), "sw": Vector2i(-1, 1), "w": Vector2i(-1, 0), "nw": Vector2i(-1, -1), "n": Vector2i(0, -1), "ne": Vector2i(1, -1)}


## Faces the enemy a way; "" clears it (looks all round).
func set_facing_name(name: String, p_sweep: float = 0.0, period: float = 4.0) -> void:
	has_facing = FACINGS.has(name)
	facing_dir = FACINGS.get(name, Vector2i(0, 1))
	sweep = p_sweep
	sweep_period = maxf(period, 0.1)
	_sweep_time = 0.0


## The facing this moment, the sweep applied, as a unit vector in grid space.
func look_dir() -> Vector2:
	var base := Vector2(facing_dir).normalized()
	if sweep <= 0.0:
		return base
	return base.rotated(deg_to_rad(sweep) * sin(TAU * _sweep_time / sweep_period))


func tick_sweep(delta: float) -> void:
	if sweep > 0.0:
		_sweep_time = fmod(_sweep_time + delta, sweep_period)


## Whether `target` is in this enemy's cone (or it has no facing).
func in_cone(target: Vector2i, cone_degrees: float) -> bool:
	if not has_facing or target == cell:
		return true
	return cone_contains(look_dir(), cell, target, cone_degrees)


func set_patrol(points: Array, speed: float = 1.0, wait: float = 0.8) -> void:
	patrol.clear()
	for p: Variant in points:
		var raw: Array = p
		if raw.size() == 2:
			patrol.append(Vector2i(int(raw[0]), int(raw[1])))
	patrol_index = 0
	patrol_speed = maxf(speed, 0.05)
	patrol_wait = maxf(wait, 0.0)
	_wait_left = 0.0
	_step_left = 1.0 / patrol_speed


## Faces a cell (a name from FACINGS when the direction has one).
func face_toward(target: Vector2i) -> void:
	var d := Vector2i(signi(target.x - cell.x), signi(target.y - cell.y))
	if d == Vector2i.ZERO:
		return
	for name: String in FACINGS:
		if FACINGS[name] == d:
			has_facing = true
			facing_dir = d
			return


## One tick of the patrol: waits at a point, else steps one cell toward
## the next point when the step timer runs out and the cell is free
## (`blocked` says whether a cell holds someone). Returns true on a step.
func tick_patrol(delta: float, map: MapData, cell_to_world: Callable, blocked: Callable) -> bool:
	if patrol.is_empty() or noticed > 0.0:
		return false
	var goal: Vector2i = patrol[patrol_index]
	if cell == goal:
		_wait_left += delta
		if _wait_left < patrol_wait:
			return false
		_wait_left = 0.0
		patrol_index = (patrol_index + 1) % patrol.size()
		goal = patrol[patrol_index]
		if cell == goal:
			return false
	_step_left -= delta
	if _step_left > 0.0:
		return false
	_step_left = 1.0 / patrol_speed
	var d := Vector2i(signi(goal.x - cell.x), signi(goal.y - cell.y))
	var options: Array[Vector2i] = [cell + d, cell + Vector2i(d.x, 0), cell + Vector2i(0, d.y)]
	for next: Vector2i in options:
		if next == cell or not map.is_walkable(next) or bool(blocked.call(next)):
			continue
		if next.x != cell.x and next.y != cell.y and not (map.is_walkable(Vector2i(next.x, cell.y)) and map.is_walkable(Vector2i(cell.x, next.y))):
			continue
		face_toward(next)
		cell = next
		walk_target = cell_to_world.call(cell)
		name = "%s_%d_%d" % [enemy_id, cell.x, cell.y]
		return true
	return false


## Walks the node toward the cell it stepped to (a patrol step is a cell
## at a time; the sprite catches up between frames).
func _process(delta: float) -> void:
	if walk_target == Vector2.INF:
		return
	var before := position
	position = position.move_toward(walk_target, 64.0 * patrol_speed * delta * 1.5)
	set_motion(position != before, (walk_target - before).normalized() if walk_target != before else facing)
	if position == walk_target:
		walk_target = Vector2.INF
		set_motion(false, facing)


## Pure: is `to` within `cone_degrees` (whole width) of `dir` seen from `from`.
static func cone_contains(dir: Vector2, from: Vector2i, to: Vector2i, cone_degrees: float) -> bool:
	var d := Vector2(to - from)
	if d.length_squared() < 0.0001 or dir.length_squared() < 0.0001:
		return true
	return rad_to_deg(absf(dir.angle_to(d))) <= cone_degrees / 2.0 + 0.001
