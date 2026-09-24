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


## Pure: is `to` within `cone_degrees` (whole width) of `dir` seen from `from`.
static func cone_contains(dir: Vector2, from: Vector2i, to: Vector2i, cone_degrees: float) -> bool:
	var d := Vector2(to - from)
	if d.length_squared() < 0.0001 or dir.length_squared() < 0.0001:
		return true
	return rad_to_deg(absf(dir.angle_to(d))) <= cone_degrees / 2.0 + 0.001
