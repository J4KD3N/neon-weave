## The turn-based combat engine. Pure logic over [MapData], [Combatant]s and
## ability entries; no nodes, no timing. Everything observable is emitted as
## an `event` dictionary so a view can animate and log it.
##
## Turn structure (GDD §9): initiative order; each turn the actor gets
## `ap_per_turn` action points and `move_max` cells of free movement.
class_name CombatState
extends RefCounted

signal event(e: Dictionary)

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var map: MapData
var rules: CombatRules
var rng := RandomNumberGenerator.new()
var combatants: Array[Combatant] = []
var order: Array[Combatant] = []
var abilities: Dictionary = {} # ability id -> entry
var round_number: int = 0
var turn_index: int = 0
var finished: bool = false
var result: String = ""
var history: Array[String] = []


func setup(p_map: MapData, p_rules: CombatRules, p_abilities: Dictionary, p_combatants: Array[Combatant], p_seed: int) -> void:
	map = p_map
	rules = p_rules
	abilities = p_abilities
	combatants.assign(p_combatants)
	rng.seed = p_seed


## Rolls initiative and begins round 1. `first_strike_team` gets the rules'
## initiative bonus (e.g. the party attacking an unaware enemy).
func start(first_strike_team: String = "") -> void:
	for c: Combatant in combatants:
		c.initiative = rng.randi_range(1, rules.initiative_die) + c.initiative_bonus
		if c.team == first_strike_team:
			c.initiative += rules.first_strike_initiative_bonus
	order.assign(combatants)
	order.sort_custom(_by_initiative)
	round_number = 1
	turn_index = 0
	finished = false
	result = ""
	_emit({"type": "start", "order": _ids(order)})
	_emit({"type": "round", "round": round_number})
	_begin_turn()


func current() -> Combatant:
	if order.is_empty() or finished:
		return null
	return order[turn_index]


func by_id(id: String) -> Combatant:
	for c: Combatant in combatants:
		if c.id == id:
			return c
	return null


func active(team: String = "") -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in combatants:
		if c.is_active() and (team.is_empty() or c.team == team):
			out.append(c)
	return out


func occupant(cell: Vector2i) -> Combatant:
	for c: Combatant in combatants:
		if c.is_active() and c.cell == cell:
			return c
	return null


## Cells the actor can still reach this turn -> step cost. Excludes its own cell.
func reachable_cells(actor: Combatant) -> Dictionary:
	return _flood(actor)["costs"]


## Cell path (excluding the start) to `to`, or empty if unreachable this turn.
func move_path(actor: Combatant, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var flood := _flood(actor)
	var costs: Dictionary = flood["costs"]
	if not costs.has(to):
		return path
	var parents: Dictionary = flood["parents"]
	var cur := to
	while cur != actor.cell:
		path.push_front(cur)
		cur = parents[cur]
	return path


func can_move(actor: Combatant, to: Vector2i) -> String:
	if actor != current():
		return "not your turn"
	if actor.move_left <= 0:
		return "no movement left"
	if not reachable_cells(actor).has(to):
		return "out of reach"
	return ""


func move(actor: Combatant, to: Vector2i) -> bool:
	var why := can_move(actor, to)
	if not why.is_empty():
		return false
	var path := move_path(actor, to)
	actor.move_left -= path.size()
	var from := actor.cell
	actor.cell = to
	_emit({"type": "move", "actor": actor.id, "from": from, "to": to, "path": path, "move_left": actor.move_left})
	return true


## Empty string when the ability may be used on `target_cell`, else the reason.
func can_use(actor: Combatant, ability_id: String, target_cell: Vector2i) -> String:
	if actor != current():
		return "not your turn"
	if not actor.abilities.has(ability_id) or not abilities.has(ability_id):
		return "unknown ability"
	var ability: Dictionary = abilities[ability_id]
	var cost := int(ability.get("ap", 1))
	if actor.ap < cost:
		return "needs %d AP" % cost
	var target := occupant(target_cell)
	if target == null:
		return "no target"
	if target == actor:
		return "cannot target self"
	if not actor.is_hostile_to(target) and not rules.friendly_fire:
		return "friendly fire is off"
	var range_cells := int(ability.get("range", 1))
	if LineOfSight.distance(actor.cell, target_cell) > range_cells:
		return "out of range"
	if bool(ability.get("requires_los", range_cells > 1)) and not LineOfSight.clear(map, actor.cell, target_cell):
		return "no line of sight"
	return ""


## Resolves an attack: to-hit roll, damage roll, flanking, knock-outs, outcome.
## Returns the resolution event (also emitted), or {} when refused.
func use_ability(actor: Combatant, ability_id: String, target_cell: Vector2i) -> Dictionary:
	var why := can_use(actor, ability_id, target_cell)
	if not why.is_empty():
		return {}
	var ability: Dictionary = abilities[ability_id]
	var target := occupant(target_cell)
	actor.ap -= int(ability.get("ap", 1))
	var flanked := is_flanked(target, actor)
	var chance := hit_chance(actor, ability, target, flanked)
	var roll := rng.randi_range(1, 100)
	var e: Dictionary = {
		"type": "ability", "actor": actor.id, "ability": ability_id, "target": target.id,
		"chance": chance, "roll": roll, "hit": roll <= chance, "flanked": flanked,
		"damage": 0, "target_hp": target.hp, "downed": false, "killed": false, "ap_left": actor.ap,
	}
	if e["hit"]:
		var dmg := roll_damage(ability, flanked, actor.damage_bonus)
		target.hp = maxi(target.hp - dmg, 0)
		e["damage"] = dmg
		e["target_hp"] = target.hp
		if target.hp == 0:
			if target.team == Combatant.TEAM_PARTY and rules.story_protected:
				target.downed = true
				e["downed"] = true
			else:
				e["killed"] = true
	_emit(e)
	_check_outcome()
	return e


func hit_chance(actor: Combatant, ability: Dictionary, target: Combatant, flanked: bool) -> int:
	var chance := int(ability.get("accuracy", 85)) - target.evasion
	if flanked:
		chance += rules.flank_hit_bonus
	return clampi(chance, rules.min_hit_chance, rules.max_hit_chance)


func roll_damage(ability: Dictionary, flanked: bool, bonus: int = 0) -> int:
	var span: Array = ability.get("damage", [1, 1])
	var lo := int(span[0]) if span.size() > 0 else 1
	var hi := int(span[1]) if span.size() > 1 else lo
	var dmg := rng.randi_range(mini(lo, hi), maxi(lo, hi)) + bonus
	if flanked:
		dmg = int(round(dmg * rules.flank_damage_mult))
	return maxi(dmg, 0)


## Flanked: some other combatant hostile to the target stands adjacent to it.
func is_flanked(target: Combatant, attacker: Combatant) -> bool:
	for c: Combatant in combatants:
		if c == attacker or c == target or not c.is_active():
			continue
		if c.is_hostile_to(target) and LineOfSight.distance(c.cell, target.cell) == 1:
			return true
	return false


func end_turn() -> void:
	if finished or order.is_empty():
		return
	var actor := current()
	_emit({"type": "turn_end", "actor": actor.id})
	var tries := 0
	while tries < order.size() + 1:
		turn_index += 1
		if turn_index >= order.size():
			turn_index = 0
			round_number += 1
			_emit({"type": "round", "round": round_number})
		if order[turn_index].is_active():
			_begin_turn()
			return
		tries += 1
	_check_outcome()


func _begin_turn() -> void:
	var actor := current()
	if actor == null:
		return
	if not actor.is_active():
		end_turn()
		return
	actor.begin_turn()
	_emit({"type": "turn_begin", "actor": actor.id, "team": actor.team, "round": round_number})


func _check_outcome() -> void:
	if finished:
		return
	if active(Combatant.TEAM_PARTY).is_empty():
		_finish("defeat")
	elif active(Combatant.TEAM_ENEMY).is_empty():
		_finish("victory")


func _finish(p_result: String) -> void:
	finished = true
	result = p_result
	_emit({"type": "end", "result": p_result, "round": round_number})


func _flood(actor: Combatant) -> Dictionary:
	var costs: Dictionary = {}
	var parents: Dictionary = {}
	var seen: Dictionary = {actor.cell: 0}
	var frontier: Array[Vector2i] = [actor.cell]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		var c: int = seen[cur]
		if c >= actor.move_left:
			continue
		for d: Vector2i in DIRS8:
			var n := cur + d
			if seen.has(n) or not _passable(n):
				continue
			if d.x != 0 and d.y != 0:
				if not (map.is_walkable(cur + Vector2i(d.x, 0)) and map.is_walkable(cur + Vector2i(0, d.y))):
					continue
			seen[n] = c + 1
			costs[n] = c + 1
			parents[n] = cur
			frontier.append(n)
	return {"costs": costs, "parents": parents}


func _passable(cell: Vector2i) -> bool:
	return map.is_walkable(cell) and occupant(cell) == null


func _emit(e: Dictionary) -> void:
	var line := describe(e)
	if not line.is_empty():
		history.append(line)
	event.emit(e)


## Human-readable line for an event, for logs and the HUD.
func describe(e: Dictionary) -> String:
	match String(e.get("type", "")):
		"start":
			return "Combat begins. Order: %s" % ", ".join(PackedStringArray(e["order"]))
		"round":
			return "— Round %d —" % int(e["round"])
		"turn_begin":
			return "%s's turn." % _name(e["actor"])
		"move":
			return "%s moves to %s." % [_name(e["actor"]), e["to"]]
		"ability":
			var who := _name(e["actor"])
			var whom := _name(e["target"])
			var ab: Dictionary = abilities.get(e["ability"], {})
			var ab_name: String = String(ab.get("name", e["ability"]))
			if not bool(e["hit"]):
				return "%s: %s on %s — miss (%d vs %d%%)." % [who, ab_name, whom, e["roll"], e["chance"]]
			var s := "%s: %s hits %s for %d%s." % [who, ab_name, whom, e["damage"], " (flanked)" if bool(e["flanked"]) else ""]
			if bool(e["killed"]):
				s += " %s dies." % whom
			elif bool(e["downed"]):
				s += " %s is down." % whom
			return s
		"turn_end":
			return ""
		"end":
			return "Victory." if e["result"] == "victory" else "The party is wiped out."
	return str(e)


func _name(id: String) -> String:
	var c := by_id(id)
	return c.display_name if c != null else id


static func _ids(list: Array[Combatant]) -> PackedStringArray:
	var out: PackedStringArray = []
	for c: Combatant in list:
		out.append(c.id)
	return out


static func _by_initiative(a: Combatant, b: Combatant) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	return a.id < b.id
