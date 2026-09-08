## Enemy decision-making, one action at a time so the view can animate
## between decisions. Archetypes (GDD §10): rusher closes and hits; ranged
## kites to keep distance and shoots. Others fall back to rusher for now.
class_name EnemyBrain
extends RefCounted

const KITE_MIN := 2


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
		_:
			return _rusher(state, actor, target)


## Stealther: hide when nothing is in reach, close in unseen, strike from
## hiding (an ambush), then hide again once it can.
static func _stealther(state: CombatState, actor: Combatant, target: Combatant) -> Dictionary:
	var id := usable_ability(state, actor, target)
	if not id.is_empty():
		return {"type": "ability", "id": id, "target": target.cell}
	if not actor.hidden:
		for stealth_id: String in actor.abilities:
			var ability: Dictionary = state.abilities.get(stealth_id, {})
			if String(ability.get("effect", "")) == "stealth" and state.can_use(actor, stealth_id, actor.cell).is_empty():
				return {"type": "ability", "id": stealth_id, "target": actor.cell}
	if actor.move_left > 0:
		var to := _closest_reachable(state, actor, target.cell)
		if to != actor.cell:
			return {"type": "move", "to": to}
	return {"type": "end"}


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
static func usable_ability(state: CombatState, actor: Combatant, target: Combatant) -> String:
	var best := ""
	var best_avg := -1.0
	for id: String in actor.abilities:
		if not state.can_use(actor, id, target.cell).is_empty():
			continue
		var ability: Dictionary = state.abilities.get(id, {})
		var span: Array = ability.get("damage", [1, 1])
		var avg := (float(span[0]) + float(span[span.size() - 1])) / 2.0
		if avg > best_avg:
			best_avg = avg
			best = id
	return best


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
	if dist >= KITE_MIN and not id.is_empty():
		return {"type": "ability", "id": id, "target": target.cell}
	if actor.move_left > 0:
		var to := _kite_cell(state, actor, target)
		if to != actor.cell:
			return {"type": "move", "to": to}
	if not id.is_empty():
		return {"type": "ability", "id": id, "target": target.cell}
	return {"type": "end"}


## Reachable cell minimising walking distance to `goal` (around walls, not
## through them), then step cost. Falls back to straight-line distance when
## the goal is cut off. May be the current cell when nothing is better.
static func _closest_reachable(state: CombatState, actor: Combatant, goal: Vector2i) -> Vector2i:
	var field := state.distance_field(goal)
	var best := actor.cell
	var best_d := _walk_distance(field, actor.cell, goal)
	var best_cost := 0
	var reach := state.reachable_cells(actor)
	var cells: Array = reach.keys()
	cells.sort() # deterministic tie-breaks
	for cell: Vector2i in cells:
		var d := _walk_distance(field, cell, goal)
		var cost: int = reach[cell]
		if d < best_d or (d == best_d and cost < best_cost):
			best = cell
			best_d = d
			best_cost = cost
	return best


static func _walk_distance(field: Dictionary, cell: Vector2i, goal: Vector2i) -> int:
	if field.has(cell):
		return int(field[cell])
	return 1000 + LineOfSight.distance(cell, goal)


## A reachable cell with line of sight to the target, at distance in
## [KITE_MIN, range], as far away as possible; else close in.
static func _kite_cell(state: CombatState, actor: Combatant, target: Combatant) -> Vector2i:
	var max_range := 1
	for id: String in actor.abilities:
		var ability: Dictionary = state.abilities.get(id, {})
		max_range = maxi(max_range, int(ability.get("range", 1)))
	var current_d := LineOfSight.distance(actor.cell, target.cell)
	var current_ok := current_d >= KITE_MIN and current_d <= max_range and LineOfSight.clear(state.map, actor.cell, target.cell)
	var best := actor.cell
	var best_d := current_d if current_ok else -1
	var reach := state.reachable_cells(actor)
	var cells: Array = reach.keys()
	cells.sort()
	for cell: Vector2i in cells:
		var d := LineOfSight.distance(cell, target.cell)
		if d < KITE_MIN or d > max_range:
			continue
		if not LineOfSight.clear(state.map, cell, target.cell):
			continue
		if d > best_d:
			best = cell
			best_d = d
	if best_d >= 0:
		return best
	return _closest_reachable(state, actor, target.cell)
