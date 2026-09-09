## Enemy decision-making, one action at a time so the view can animate
## between decisions. Archetypes (GDD §10):
##   rusher     closes by walking distance and hits;
##   ranged     keeps [KITE_MIN, range] with line of sight and shoots;
##   stealther  hides, closes unseen, ambushes;
##   summoner   calls minions up to its limit, then behaves as ranged;
##   controller lands control effects (root, silence) on fresh targets, then ranged.
## Every move is scored: closer/better range first, then cover between the
## cell and the target, high ground, a mana pool for arcane casters, and a
## penalty for corrosive biogrowth (weights in `rules/combat`).
class_name EnemyBrain
extends RefCounted

const KITE_MIN := 2
const UNREACHABLE := 1000


## Returns {"type": "ability", "id": ..., "target": Vector2i} |
## {"type": "move", "to": Vector2i} | {"type": "end"}.
static func next_action(state: CombatState, actor: Combatant) -> Dictionary:
	var target := nearest_hostile(state, actor)
	if target == null:
		return {"type": "end"}
	match actor.archetype:
		"ranged":
			return _ranged(state, actor, target)
		"stealther":
			return _stealther(state, actor, target)
		"summoner":
			return _summoner(state, actor, target)
		"controller":
			return _controller(state, actor, target)
		_:
			return _rusher(state, actor, target)


static func nearest_hostile(state: CombatState, actor: Combatant) -> Combatant:
	var best: Combatant = null
	var best_d := 1 << 30
	for c: Combatant in state.active():
		if not c.is_hostile_to(actor) or c.hidden:
			continue
		var d := LineOfSight.distance(actor.cell, c.cell)
		if d < best_d or (d == best_d and c.id < best.id):
			best = c
			best_d = d
	return best


## Best usable ability on `target`: highest average damage first.
## Control abilities (root/silence) count only when they add something new.
static func usable_ability(state: CombatState, actor: Combatant, target: Combatant) -> String:
	var best := ""
	var best_avg := -1.0
	for id: String in actor.abilities:
		if not state.can_use(actor, id, target.cell).is_empty():
			continue
		var ability: Dictionary = state.abilities.get(id, {})
		if _is_control(ability) and not _control_is_fresh(ability, target):
			continue
		var span: Array = ability.get("damage", [1, 1])
		var avg := (float(span[0]) + float(span[span.size() - 1])) / 2.0
		if avg > best_avg:
			best_avg = avg
			best = id
	return best


static func _is_control(ability: Dictionary) -> bool:
	return ["root", "silence"].has(String(ability.get("effect", "")))


static func _control_is_fresh(ability: Dictionary, target: Combatant) -> bool:
	match String(ability.get("effect", "")):
		"root":
			return not target.is_rooted()
		"silence":
			return not target.is_silenced()
	return true


# --- archetypes -------------------------------------------------------------

static func _rusher(state: CombatState, actor: Combatant, target: Combatant) -> Dictionary:
	var id := usable_ability(state, actor, target)
	if not id.is_empty():
		return {"type": "ability", "id": id, "target": target.cell}
	if actor.move_left > 0:
		var to := _closest_reachable(state, actor, target.cell)
		if to != actor.cell:
			return {"type": "move", "to": to}
	return {"type": "end"}


static func _ranged(state: CombatState, actor: Combatant, target: Combatant) -> Dictionary:
	var dist := LineOfSight.distance(actor.cell, target.cell)
	var id := usable_ability(state, actor, target)
	if dist >= KITE_MIN and not id.is_empty() and not _better_kite_cell_exists(state, actor, target):
		return {"type": "ability", "id": id, "target": target.cell}
	if actor.move_left > 0:
		var to := _kite_cell(state, actor, target)
		if to != actor.cell:
			return {"type": "move", "to": to}
	if not id.is_empty():
		return {"type": "ability", "id": id, "target": target.cell}
	return {"type": "end"}


## Stealther: hide when nothing is in reach, close in unseen, strike from
## hiding (an ambush), then hide again once it can.
static func _stealther(state: CombatState, actor: Combatant, target: Combatant) -> Dictionary:
	var id := usable_ability(state, actor, target)
	if not id.is_empty():
		return {"type": "ability", "id": id, "target": target.cell}
	if not actor.hidden:
		var stealth_id := _self_ability(state, actor, "stealth")
		if not stealth_id.is_empty():
			return {"type": "ability", "id": stealth_id, "target": actor.cell}
	if actor.move_left > 0:
		var to := _closest_reachable(state, actor, target.cell)
		if to != actor.cell:
			return {"type": "move", "to": to}
	return {"type": "end"}


## Summoner: call minions while under the limit, then fight like a ranged.
static func _summoner(state: CombatState, actor: Combatant, target: Combatant) -> Dictionary:
	var summon_id := _self_ability(state, actor, "summon")
	if not summon_id.is_empty():
		return {"type": "ability", "id": summon_id, "target": actor.cell}
	return _ranged(state, actor, target)


## Controller: put a fresh control effect on the nearest target that lacks
## it (root the runner, silence the caster), otherwise fight like a ranged.
static func _controller(state: CombatState, actor: Combatant, target: Combatant) -> Dictionary:
	for id: String in actor.abilities:
		var ability: Dictionary = state.abilities.get(id, {})
		if not _is_control(ability):
			continue
		for c: Combatant in _hostiles_by_distance(state, actor):
			if _control_is_fresh(ability, c) and state.can_use(actor, id, c.cell).is_empty():
				return {"type": "ability", "id": id, "target": c.cell}
	# The finisher decides the fallback: a melee controller (the Warlord and
	# his fist) closes like a rusher; a ranged one (the Matron) kites.
	if _damage_range(state, actor) <= 1:
		return _rusher(state, actor, target)
	return _ranged(state, actor, target)


## Longest range among the actor's damaging (non-control) abilities.
static func _damage_range(state: CombatState, actor: Combatant) -> int:
	var out := 0
	for id: String in actor.abilities:
		var ability: Dictionary = state.abilities.get(id, {})
		if _is_control(ability):
			continue
		var span: Array = ability.get("damage", [0, 0])
		if float(span[span.size() - 1]) <= 0.0:
			continue
		out = maxi(out, int(ability.get("range", 1)))
	return out


## First usable self-targeted ability with the given effect, or "".
static func _self_ability(state: CombatState, actor: Combatant, effect: String) -> String:
	for id: String in actor.abilities:
		var ability: Dictionary = state.abilities.get(id, {})
		if String(ability.get("effect", "")) == effect and state.can_use(actor, id, actor.cell).is_empty():
			return id
	return ""


static func _hostiles_by_distance(state: CombatState, actor: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in state.active():
		if c.is_hostile_to(actor) and not c.hidden:
			out.append(c)
	out.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		var da := LineOfSight.distance(actor.cell, a.cell)
		var db := LineOfSight.distance(actor.cell, b.cell)
		return da < db if da != db else a.id < b.id)
	return out


# --- positioning ------------------------------------------------------------

## Texture score of standing on `cell` against `target`: cover between the
## two, high ground, a mana pool for arcane casters, corrosive biogrowth.
static func position_score(state: CombatState, actor: Combatant, cell: Vector2i, target: Combatant) -> int:
	var rules := state.rules
	var map := state.map
	var score := 0
	var d := target.cell - cell
	if d != Vector2i.ZERO:
		score += map.cover_at(cell + Vector2i(signi(d.x), signi(d.y))) * rules.ai_cover_weight
	var h := map.height_at(cell)
	var th := map.height_at(target.cell)
	if h > th:
		score += rules.ai_elevation_weight
	elif h < th:
		score -= rules.ai_elevation_weight
	var surface := map.surface_at(cell)
	if surface == "corrosive":
		score -= rules.ai_corrosive_penalty
	elif surface == "mana_pool" and _casts_arcane(state, actor):
		score += rules.ai_mana_pool_weight
	score += int(rules.surface_evasion.get(surface, 0)) / 2 # spores: harder to hit here
	return score


static func _casts_arcane(state: CombatState, actor: Combatant) -> bool:
	for id: String in actor.abilities:
		if String(Dictionary(state.abilities.get(id, {})).get("damage_type", "")) == "arcane":
			return true
	return false


## Reachable cell minimising walking distance to `goal` (around walls, not
## through them); texture breaks ties among equally close cells, then step
## cost. May be the current cell when nothing is better.
static func _closest_reachable(state: CombatState, actor: Combatant, goal: Vector2i) -> Vector2i:
	var field := state.distance_field(goal)
	var target := state.occupant(goal)
	var best := actor.cell
	var best_key := _approach_key(state, actor, field, actor.cell, goal, target, 0)
	var reach := state.reachable_cells(actor)
	var cells: Array = reach.keys()
	cells.sort() # deterministic tie-breaks
	for cell: Vector2i in cells:
		var key := _approach_key(state, actor, field, cell, goal, target, int(reach[cell]))
		if key < best_key:
			best = cell
			best_key = key
	return best


## Lower is better: walking distance dominates, then texture, then cost.
static func _approach_key(state: CombatState, actor: Combatant, field: Dictionary, cell: Vector2i, goal: Vector2i, target: Combatant, cost: int) -> Array:
	var texture := position_score(state, actor, cell, target) if target != null else 0
	return [_walk_distance(field, cell, goal), -texture, cost]


static func _walk_distance(field: Dictionary, cell: Vector2i, goal: Vector2i) -> int:
	if field.has(cell):
		return int(field[cell])
	return UNREACHABLE + LineOfSight.distance(cell, goal)


static func _max_range(state: CombatState, actor: Combatant) -> int:
	var max_range := 1
	for id: String in actor.abilities:
		var ability: Dictionary = state.abilities.get(id, {})
		max_range = maxi(max_range, int(ability.get("range", 1)))
	return max_range


## Firing-position key, higher is better: [in the kite band with line of
## sight, texture score, distance]. Distance only breaks ties among equally
## textured firing cells, so a ranged enemy never abandons a good spot just
## to stand one cell further away.
static func kite_key(state: CombatState, actor: Combatant, cell: Vector2i, target: Combatant) -> Array:
	var max_range := _max_range(state, actor)
	var d := LineOfSight.distance(cell, target.cell)
	var texture := position_score(state, actor, cell, target)
	var in_band := d >= KITE_MIN and d <= max_range and LineOfSight.clear(state.map, cell, target.cell)
	return [1 if in_band else 0, texture, d if in_band else -d]


## A reachable cell with the best kite key; the current cell competes.
static func _kite_cell(state: CombatState, actor: Combatant, target: Combatant) -> Vector2i:
	var best := actor.cell
	var best_key := kite_key(state, actor, actor.cell, target)
	var reach := state.reachable_cells(actor)
	var cells: Array = reach.keys()
	cells.sort()
	for cell: Vector2i in cells:
		var key := kite_key(state, actor, cell, target)
		if key > best_key:
			best = cell
			best_key = key
	if int(best_key[0]) == 1:
		return best
	return _closest_reachable(state, actor, target.cell)


## True when moving would land a firing position with better texture
## (cover, height, a pool): worth the move before shooting.
static func _better_kite_cell_exists(state: CombatState, actor: Combatant, target: Combatant) -> bool:
	if actor.move_left <= 0:
		return false
	var here := kite_key(state, actor, actor.cell, target)
	var reach := state.reachable_cells(actor)
	for cell: Vector2i in reach:
		var key := kite_key(state, actor, cell, target)
		if int(key[0]) > int(here[0]) or (int(key[0]) == int(here[0]) and int(key[1]) > int(here[1])):
			return true
	return false
