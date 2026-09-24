## The turn-based combat engine. Pure logic over [MapData], [Combatant]s and
## ability entries; no nodes, no timing. Everything observable is emitted as
## an `event` dictionary so a view can animate and log it.
##
## Turn structure (GDD §9): initiative order; each turn the actor gets
## `ap_per_turn` action points and `move_max` cells of free movement.
## Positioning texture: flanking, cover against ranged fire, elevation,
## surfaces (mana pools, conduits, corrosive biogrowth). Class resources
## (Surge, Heat) build per matching cast and pay out as damage.
class_name CombatState
extends RefCounted

signal event(e: Dictionary)

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CHAIN_TYPES: Array[String] = ["tech", "arcane"]

var map: MapData
var rules: CombatRules
var rng := RandomNumberGenerator.new()
var combatants: Array[Combatant] = []
var order: Array[Combatant] = []
var abilities: Dictionary = {} # ability id -> entry
## `enemies` entries by id, for summons. Empty when nothing can summon.
var enemy_entries: Dictionary = {}
## Shard depth for summoned stats (1 = unscaled).
var depth: int = 1
var _summon_count: int = 0
var round_number: int = 0
var turn_index: int = 0
var finished: bool = false
var result: String = ""
var history: Array[String] = []
## The turn group: consecutive same-team combatants in the order, acting in
## any sequence the player likes (BG3-style). Enemies use it too, one by one.
var group: Array[Combatant] = []
var _done: Dictionary = {} # id -> true once that member ended its turn this group
var _begun: Dictionary = {} # id -> true once begin_turn ran for it this group
## The last move, undoable until anything else happens: {"actor", "from", "cost"}.
var _undo: Dictionary = {}


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
	_enter_group_at(0)


func current() -> Combatant:
	if order.is_empty() or finished:
		return null
	return order[turn_index]


## Group members who may still act: active, not done, not the current one.
func switchable() -> Array[Combatant]:
	var out: Array[Combatant] = []
	var cur := current()
	for c: Combatant in group:
		if c != cur and c.is_active() and not _done.has(c.id):
			out.append(c)
	return out


func has_acted(c: Combatant) -> bool:
	return _done.has(c.id)


## Hands control to another member of the current group. Empty string on
## success, else the reason. The member keeps whatever AP/Move it has left.
func switch_to(id: String) -> String:
	if finished:
		return Loc.t("combat over")
	var c := by_id(id)
	if c == null or not group.has(c):
		return Loc.t("not in this turn group")
	if not c.is_active():
		return "down"
	if _done.has(c.id):
		return Loc.t("already acted")
	if c == current():
		return ""
	turn_index = order.find(c)
	_undo = {}
	_emit({"type": "switch", "actor": c.id})
	_lazy_begin(c)
	return ""


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


# --- movement --------------------------------------------------------------

## Cells the actor can still reach this turn -> step cost. Excludes its own cell.
func reachable_cells(actor: Combatant) -> Dictionary:
	return _flood(actor)["costs"]


## Cell path (excluding the start) to `to`, or empty if unreachable this turn.
func move_path(actor: Combatant, to: Vector2i) -> Array[Vector2i]:
	return _path_from(_flood(actor), actor.cell, to)


func _path_from(flood: Dictionary, start: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var costs: Dictionary = flood["costs"]
	if not costs.has(to):
		return path
	var parents: Dictionary = flood["parents"]
	var cur := to
	while cur != start:
		path.push_front(cur)
		cur = parents[cur]
	return path


func can_move(actor: Combatant, to: Vector2i) -> String:
	if actor != current():
		return Loc.t("not your turn")
	if actor.is_rooted():
		return "rooted"
	if actor.move_left <= 0:
		return Loc.t("no movement left")
	if not reachable_cells(actor).has(to):
		return Loc.t("out of reach")
	return ""


## Walks the actor to `to` a cell at a time (S65, D-121): each cell left
## beside a hostile melee fighter that the next cell is not beside draws
## that fighter's free strike, once per fighter per move; a mover put down
## on the way stops where it fell. The move can still be undone; the
## strike it drew stands. The cost is the flood's (a climb costs more).

func move(actor: Combatant, to: Vector2i) -> bool:
	var why := can_move(actor, to)
	if not why.is_empty():
		return false
	var flood := _flood(actor)
	var path := _path_from(flood, actor.cell, to)
	var cost := int(Dictionary(flood["costs"]).get(to, path.size()))
	actor.move_left -= cost
	var from := actor.cell
	var struck: Dictionary = {}
	var provoked := false
	var walked: Array[Vector2i] = []
	for step: Vector2i in path:
		for h: Combatant in _provokers(actor, actor.cell, step):
			if struck.has(h.id):
				continue
			struck[h.id] = true
			provoked = true
			_opportunity(h, actor)
			if not actor.is_active():
				break
		if not actor.is_active():
			break
		actor.cell = step
		walked.append(step)
	_undo = {"actor": actor.id, "from": from, "cost": cost}
	_emit({"type": "move", "actor": actor.id, "from": from, "to": actor.cell, "path": walked, "move_left": actor.move_left, "provoked": provoked})
	if provoked:
		_check_outcome()
		if not finished and not actor.is_active() and actor == current():
			end_turn()
	return true


## Hostile melee fighters whose free strike a step from `from` to `to`
## would draw: active, not hidden, beside `from`, not beside `to`, with a
## reach-1 damaging ability. Nothing while the mover is hidden or the
## rules have the strikes off.
func _provokers(mover: Combatant, from: Vector2i, to: Vector2i) -> Array[Combatant]:
	var out: Array[Combatant] = []
	if not rules.opportunity_attacks or mover.hidden:
		return out
	for h: Combatant in active():
		if h == mover or not h.is_hostile_to(mover) or h.hidden:
			continue
		if LineOfSight.distance(h.cell, from) != 1 or LineOfSight.distance(h.cell, to) <= 1:
			continue
		if melee_ability(h).is_empty():
			continue
		out.append(h)
	return out


## The strikes a whole path would draw, each fighter once (the hover hint
## and the AI read this before moving).
func provokers_along(mover: Combatant, path: Array[Vector2i]) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var at := mover.cell
	for step: Vector2i in path:
		for h: Combatant in _provokers(mover, at, step):
			if not out.has(h):
				out.append(h)
		at = step
	return out


## The first reach-1 ability with damage a combatant carries, or "".
func melee_ability(c: Combatant) -> String:
	for id: String in c.abilities:
		var ability: Dictionary = abilities.get(id, {})
		if int(ability.get("range", 1)) > 1 or String(ability.get("targets", "other")) == "self":
			continue
		var span: Array = ability.get("damage", [0, 0])
		if int(span[span.size() - 1]) > 0:
			return id
	return ""


## One free strike as the mover passes: a plain roll with the fighter's
## melee ability, no AP, no resource, no chain, no counter.
func _opportunity(fighter: Combatant, mover: Combatant) -> void:
	var id := melee_ability(fighter)
	var e := _strike(fighter, abilities[id], id, mover, false, false)
	e["type"] = "opportunity"
	_emit(e)


## True while the current combatant's last move can still be taken back:
## nothing has happened since it (no ability, no swap, no turn end).
func can_undo_move(actor: Combatant) -> bool:
	return not finished and not _undo.is_empty() and actor == current() and String(_undo["actor"]) == actor.id


## Steps the current combatant back to where its last move started and
## refunds the Move. Returns false when there is nothing to undo.
func undo_move() -> bool:
	var actor := current()
	if actor == null or not can_undo_move(actor):
		return false
	var to := actor.cell
	actor.cell = _undo["from"]
	actor.move_left += int(_undo["cost"])
	_undo = {}
	_emit({"type": "undo", "actor": actor.id, "from": to, "to": actor.cell, "move_left": actor.move_left})
	return true


# --- abilities -------------------------------------------------------------

## Empty string when the ability may be used on `target_cell`, else the reason.
func can_use(actor: Combatant, ability_id: String, target_cell: Vector2i) -> String:
	if actor != current():
		return Loc.t("not your turn")
	if not actor.abilities.has(ability_id) or not abilities.has(ability_id):
		return Loc.t("unknown ability")
	var ability: Dictionary = abilities[ability_id]
	var cost := int(ability.get("ap", 1))
	if actor.ap < cost:
		return Loc.t("needs %d AP") % cost
	var lock_ap := int(actor.resource_def.get("lock_ap_at_max", 0))
	if lock_ap > 0 and actor.resource >= actor.resource_max() and cost >= lock_ap:
		return Loc.t("overheated: vent first")
	var resource_cost := int(ability.get("resource_cost", 0))
	if resource_cost > 0 and actor.resource < resource_cost:
		return Loc.t("needs %d %s") % [resource_cost, Loc.any(String(actor.resource_def.get("name", "charge")))]
	if actor.is_silenced() and String(ability.get("damage_type", "")) == "arcane":
		return Loc.t("silenced")
	if actor.statuses.has("cd:" + ability_id):
		return Loc.t("cooling down (%d)") % int(actor.statuses["cd:" + ability_id])
	var target := occupant(target_cell)
	if target == null:
		return Loc.t("no target")
	var self_only := String(ability.get("targets", "other")) == "self"
	if self_only:
		if target != actor:
			return Loc.t("self only")
		if String(ability.get("effect", "")) == "stealth":
			if actor.hidden:
				return Loc.t("already hidden")
			if bool(actor.resource_def.get("reveal_at_max", false)) and actor.resource >= actor.resource_max() and actor.resource_max() > 0:
				return Loc.t("overheated: cool down first")
		if String(ability.get("effect", "")) == "summon":
			if not enemy_entries.has(String(ability.get("summon", ""))):
				return Loc.t("nothing to summon")
			if summons_of(actor).size() >= int(ability.get("summon_max", 1)):
				return Loc.t("swarm at its limit")
			if free_adjacent(actor.cell) == Vector2i(-1, -1):
				return Loc.t("no room")
		return ""
	if target == actor:
		return Loc.t("cannot target self")
	if String(ability.get("effect", "")) == "hack": # S63: only a hackable machine on the other side
		if not bool(target.traits.get("hackable", false)):
			return Loc.t("not a machine you can hack")
		if not actor.is_hostile_to(target):
			return Loc.t("already on your side")
	if not actor.is_hostile_to(target) and not rules.friendly_fire:
		return Loc.t("friendly fire is off")
	if target.hidden and actor.is_hostile_to(target):
		return Loc.t("target is hidden")
	var range_cells := int(ability.get("range", 1)) + int(Dictionary(actor.traits.get("ability_range_bonus", {})).get(ability_id, 0)) # a talent may lengthen it (S66)
	if LineOfSight.distance(actor.cell, target_cell) > range_cells:
		return Loc.t("out of range")
	if bool(ability.get("requires_los", range_cells > 1)) and not LineOfSight.clear(map, actor.cell, target_cell):
		return Loc.t("no line of sight")
	return ""


## A stealth opener (S64): the party struck an enemy that had not noticed
## it, so every standing party member begins hidden for one turn and the
## first blow each lands is an ambush.
func open_from_cover() -> void:
	for c: Combatant in active(Combatant.TEAM_PARTY):
		c.hide(1)
	_emit({"type": "opener", "team": Combatant.TEAM_PARTY})


## Whether the party can see a hidden combatant (S65): a standing member
## with `detect_hidden` within that many cells and a clear line. Hidden
## party members are always drawn to the player; hidden enemies only when
## someone could sense them.
func party_can_sense(c: Combatant) -> bool:
	for m: Combatant in active(Combatant.TEAM_PARTY):
		var sight := int(m.traits.get("detect_hidden", 0))
		if sight > 0 and LineOfSight.distance(m.cell, c.cell) <= sight and LineOfSight.clear(map, m.cell, c.cell):
			return true
	return false


## The fight as data (S68, D-124): every combatant, the order and the
## group by id, the turn, the round, the RNG's state so the next roll is
## the roll it would have been, and the log's tail. The map, the rules and
## the abilities are content and are not written.
func to_dict() -> Dictionary:
	var cs: Array = []
	for c: Combatant in combatants:
		cs.append(c.to_dict())
	return {
		"combatants": cs, "order": _ids(order), "group": _ids(group), "done": _done.keys(), "begun": _begun.keys(),
		"round": round_number, "turn_index": turn_index, "finished": finished, "result": result,
		"rng_state": rng.state, "summon_count": _summon_count, "history": history.slice(maxi(history.size() - 60, 0)),
	}


## Puts a fight back after `setup` (which seeded the RNG); the combatants
## are those `setup` was given, matched to the saved order by id.
func restore_from(d: Dictionary) -> void:
	var by_id: Dictionary = {}
	for c: Combatant in combatants:
		by_id[c.id] = c
	order.clear()
	for id: Variant in d.get("order", []):
		if by_id.has(String(id)):
			order.append(by_id[String(id)])
	group.clear()
	for id: Variant in d.get("group", []):
		if by_id.has(String(id)):
			group.append(by_id[String(id)])
	_done.clear()
	for id: Variant in d.get("done", []):
		_done[String(id)] = true
	_begun.clear()
	for id: Variant in d.get("begun", []):
		_begun[String(id)] = true
	round_number = int(d.get("round", 1))
	turn_index = clampi(int(d.get("turn_index", 0)), 0, maxi(order.size() - 1, 0))
	finished = bool(d.get("finished", false))
	result = String(d.get("result", ""))
	rng.state = int(d.get("rng_state", rng.state))
	_summon_count = int(d.get("summon_count", 0))
	history.assign(d.get("history", []))
	_undo = {}
	_emit({"type": "resumed", "round": round_number, "actor": current().id if current() != null else ""})


## Positioning modifiers for an attack: elevation, cover, mana pool.
## {"hit": int, "damage": int, "cover": int, "elevated": bool, "uphill": bool, "amplified": bool}
func attack_modifiers(actor: Combatant, ability: Dictionary, target: Combatant) -> Dictionary:
	var hit := 0
	var damage := 0
	var ah := map.height_at(actor.cell)
	var th := map.height_at(target.cell)
	var elevated := ah > th
	var uphill := ah < th
	if elevated:
		hit += rules.elevation_hit_bonus
		damage += rules.elevation_damage_bonus
	elif uphill:
		hit -= rules.elevation_hit_bonus
	var cover := 0
	if int(ability.get("range", 1)) > 1 and not elevated:
		var d := actor.cell - target.cell
		cover = map.cover_at(target.cell + Vector2i(signi(d.x), signi(d.y)))
		if cover > 0:
			hit -= rules.cover_hit_penalty
	var amplified := map.surface_at(actor.cell) == "mana_pool" and String(ability.get("damage_type", "")) == "arcane"
	var shroud := int(rules.surface_evasion.get(map.surface_at(target.cell), 0))
	hit -= shroud
	return {"hit": hit, "damage": damage, "cover": cover, "elevated": elevated, "uphill": uphill, "amplified": amplified, "shroud": shroud}


## True when the ability's damage type feeds the actor's class resource.
func builds_resource(actor: Combatant, ability: Dictionary) -> bool:
	return actor.has_resource() and String(ability.get("damage_type", "")) == String(actor.resource_def.get("builds_on", ""))


## Resolves an ability: vents, overloads, to-hit roll with flanking / cover /
## elevation, damage roll with Workshop, resource and elevation bonuses,
## mana-pool amplification, conduit chaining, knock-outs, outcome.
## Returns the resolution event (also emitted), or {} when refused.
func use_ability(actor: Combatant, ability_id: String, target_cell: Vector2i) -> Dictionary:
	var why := can_use(actor, ability_id, target_cell)
	if not why.is_empty():
		return {}
	var ability: Dictionary = abilities[ability_id]
	var target := occupant(target_cell)
	actor.ap -= int(ability.get("ap", 1))
	_undo = {}
	var cooldown := maxi(int(ability.get("cooldown", 0)) - int(Dictionary(actor.traits.get("ability_cooldown_bonus", {})).get(ability_id, 0)), 0) # a talent may shorten it (S66)
	if cooldown > 0:
		actor.statuses["cd:" + ability_id] = cooldown
	var resource_cost := int(ability.get("resource_cost", 0))
	if resource_cost > 0:
		actor.resource = maxi(actor.resource - resource_cost, 0)
	var effect := String(ability.get("effect", ""))
	var mark := String(ability.get("mark", ""))

	if effect == "summon":
		var kind := String(ability.get("summon", ""))
		var entry: Dictionary = enemy_entries.get(kind, {})
		var sm: Dictionary = {}
		for _n: int in maxi(int(ability.get("summon_count", 1)), 1):
			if summons_of(actor).size() >= int(ability.get("summon_max", 1)):
				break
			var cell := free_adjacent(actor.cell)
			if cell == Vector2i(-1, -1):
				break
			_summon_count += 1
			var stats := StatBlock.for_enemy(entry, rules, depth)
			var prefix := "e" if actor.team == Combatant.TEAM_ENEMY else "p"
			var minion := Combatant.make("%s:s%d:%s" % [prefix, _summon_count, kind], String(entry.get("name", kind)), actor.team, cell, stats, Array(entry.get("abilities", []), TYPE_STRING, "", null), rules.ap_per_turn)
			minion.archetype = String(entry.get("archetype", "rusher"))
			minion.damage_bonus = int(stats.get("damage_bonus", 0))
			minion.traits = Dictionary(entry.get("traits", {})).duplicate(true)
			minion.summoned_by = actor.id
			combatants.append(minion)
			order.append(minion)
			sm = {"type": "summon", "actor": actor.id, "team": actor.team, "summoned": minion.id, "kind": kind, "cell": cell, "ap_left": actor.ap}
			_emit(sm)
		return sm

	if effect == "stealth":
		actor.hide(int(ability.get("duration", 2)))
		var gain := int(actor.resource_def.get("gain_on_stealth", 0))
		if actor.has_resource() and gain > 0:
			actor.resource = mini(actor.resource + gain, actor.resource_max())
		var revealed := _check_reveal(actor)
		var st: Dictionary = {"type": "stealth", "actor": actor.id, "ability": ability_id, "hidden": actor.hidden, "revealed": revealed, "resource_after": actor.resource, "ap_left": actor.ap}
		_emit(st)
		return st

	if effect == "vent":
		var heal := int(ability.get("heal", 0))
		if Array(actor.traits.get("heal_immune_types", [])).has(String(ability.get("damage_type", ""))):
			heal = 0 # no magic healing for a Synth
		var before := actor.resource
		actor.resource = 0
		actor.hp = mini(actor.max_hp, actor.hp + heal)
		var v: Dictionary = {"type": "vent", "actor": actor.id, "ability": ability_id, "heal": heal, "resource_before": before, "ap_left": actor.ap}
		_emit(v)
		return v

	var builds := builds_resource(actor, ability)
	var def := actor.resource_def
	if builds and def.has("overload_at") and actor.resource >= int(def["overload_at"]) and rng.randf() < float(def.get("overload_chance", 0.0)):
		var od := int(def.get("overload_damage", 0))
		actor.resource = 0
		var fate := _apply_damage(actor, od)
		var o: Dictionary = {"type": "overload", "actor": actor.id, "ability": ability_id, "damage": od, "actor_hp": actor.hp, "downed": fate["downed"], "killed": fate["killed"], "ap_left": actor.ap}
		_emit(o)
		_check_outcome()
		return o

	if effect == "counter":
		actor.statuses["counter"] = int(ability.get("duration", 1))
		actor.counter_damage = Array(ability.get("counter_damage", ability.get("damage", [1, 1])))
		var cs: Dictionary = {"type": "stance", "actor": actor.id, "ability": ability_id, "stance": "counter", "turns": int(ability.get("duration", 1)), "ap_left": actor.ap}
		_emit(cs)
		return cs

	if effect == "hack": # S63: a Tech roll; on a hit the machine changes sides
		var chance := clampi(int(ability.get("accuracy", 60)) + int(actor.traits.get("hack_bonus", 0)), rules.min_hit_chance, rules.max_hit_chance)
		var roll := rng.randi_range(1, 100)
		var h: Dictionary = {"type": "hack", "actor": actor.id, "ability": ability_id, "target": target.id, "chance": chance, "roll": roll, "hit": roll <= chance, "ap_left": actor.ap}
		if bool(h["hit"]):
			target.team = actor.team
			target.hacked = true
			target.taunted_by = ""
			target.statuses.erase("taunted")
			target.hidden = false
		_emit(h)
		_check_outcome()
		return h

	var ambush := actor.hidden
	actor.reveal() # striking from hiding reveals, hit or miss
	var e := _strike(actor, ability, ability_id, target, ambush, true)
	e["resource_stacks"] = actor.resource if builds else 0
	e["resource_cost"] = resource_cost
	e["ap_left"] = actor.ap
	if bool(e["hit"]) and bool(e["killed"]) and def.has("gain_on_kill"):
		actor.resource = mini(actor.resource + int(def["gain_on_kill"]), actor.resource_max())
	if builds:
		actor.resource = mini(actor.resource + int(def.get("gain_per_cast", 1)), actor.resource_max())
	_refresh_mark_resources()
	if actor.has_resource():
		e["resource_after"] = actor.resource
	_emit(e)
	if bool(e["hit"]) and int(e["damage"]) > 0 and map.surface_at(target.cell) == "conduit" and CHAIN_TYPES.has(String(ability.get("damage_type", ""))):
		_chain_shock(target, actor)
	_counter_against(actor, target)
	# Area: everyone else within `aoe` of the target cell takes their own roll.
	var radius := int(ability.get("aoe", 0))
	if radius > 0:
		for c: Combatant in active():
			if c == actor or c == target or LineOfSight.distance(target.cell, c.cell) > radius:
				continue
			if not actor.is_hostile_to(c) and not rules.friendly_fire:
				continue
			var s := _strike(actor, ability, ability_id, c, false, false)
			s["aoe"] = true
			s["ap_left"] = actor.ap
			_emit(s)
			_counter_against(actor, c)
	_check_outcome()
	return e


## One attack roll against `target` with every modifier, the damage, and
## the on-hit effects (silence, root, mark, taunt, poison, chain). Emits
## nothing: the caller adds resource bookkeeping and emits. `allow_chain`
## is false for area and chain-secondary hits so lightning never loops.
func _strike(actor: Combatant, ability: Dictionary, ability_id: String, target: Combatant, ambush: bool, allow_chain: bool) -> Dictionary:
	var effect := String(ability.get("effect", ""))
	var mark := String(ability.get("mark", ""))
	var flanked := is_flanked(target, actor)
	var mods := attack_modifiers(actor, ability, target)
	var chance := hit_chance(actor, ability, target, flanked, int(mods["hit"]) + (rules.ambush_hit_bonus if ambush else 0))
	var roll := rng.randi_range(1, 100)
	var e: Dictionary = {
		"type": "ability", "actor": actor.id, "ability": ability_id, "target": target.id,
		"chance": chance, "roll": roll, "hit": roll <= chance, "flanked": flanked, "ambush": ambush,
		"cover": mods["cover"], "elevated": mods["elevated"], "uphill": mods["uphill"], "amplified": mods["amplified"], "shroud": mods["shroud"],
		"resource_stacks": 0, "resource_cost": 0,
		"marked": 0, "detonated": 0, "silenced": 0, "absorbed": 0,
		"damage": 0, "target_hp": target.hp, "downed": false, "killed": false, "ap_left": actor.ap,
	}
	if not e["hit"]:
		return e
	var bonus := damage_bonus_for(actor, ability, target, mods)
	if effect == "detonate" and not mark.is_empty():
		e["detonated"] = target.mark_count(mark)
		target.marks.erase(mark)
	var dmg := roll_damage(ability, flanked, bonus)
	if bool(mods["amplified"]):
		dmg = int(round(dmg * rules.mana_pool_amplify))
	if ambush:
		dmg = int(round(dmg * rules.ambush_damage_mult))
	var damage_type := String(ability.get("damage_type", ""))
	var fate := _apply_damage(target, dmg, damage_type)
	e["damage"] = int(fate["dealt"])
	e["absorbed"] = int(fate["absorbed"])
	e["resisted"] = int(fate.get("resisted", 0))
	e["target_hp"] = target.hp
	e["downed"] = fate["downed"]
	e["killed"] = fate["killed"]
	var turns := int(ability.get("duration", 1))
	if effect == "silence" and target.is_active():
		target.statuses["silenced"] = maxi(int(target.statuses.get("silenced", 0)), turns)
		e["silenced"] = turns
	if effect == "root" and target.is_active():
		target.statuses["rooted"] = maxi(int(target.statuses.get("rooted", 0)), turns)
		e["rooted"] = turns
	if effect == "taunt" and target.is_active():
		target.statuses["taunted"] = maxi(int(target.statuses.get("taunted", 0)), turns)
		target.taunted_by = actor.id
		e["taunted"] = turns
	if effect == "poison" and target.is_active():
		_poison(target, turns, int(ability.get("poison_damage", 1)), bool(ability.get("spread", false)), actor.id, damage_type)
		e["poisoned"] = turns
	if effect == "mark" and not mark.is_empty() and target.is_active():
		var cap := int(actor.resource_def.get("max_per_target", 3))
		target.marks[mark] = mini(target.mark_count(mark) + 1, cap)
		e["marked"] = target.marks[mark]
	if effect == "chain" and allow_chain and int(e["damage"]) > 0:
		e["arcs"] = _arc(actor, target, int(e["damage"]), ability, damage_type)
	return e


## Poison (D-086): `turns` of `damage` at the end of each of the victim's own
## turns; with `spread`, it jumps to adjacent teammates as it ticks.
func _poison(target: Combatant, turns: int, damage: int, spread: bool, source: String, damage_type: String) -> void:
	target.statuses["poisoned"] = maxi(int(target.statuses.get("poisoned", 0)), turns)
	target.poison = {"damage": damage, "spread": spread, "source": source, "type": damage_type if not damage_type.is_empty() else "poison"}


## Chain lightning (D-086): the hit jumps to the nearest other hostiles within
## `chain_range` of the target, up to `chain_targets`, for `chain_fraction` of
## the damage. Returns how many it reached.
func _arc(actor: Combatant, target: Combatant, dmg: int, ability: Dictionary, damage_type: String) -> int:
	var jump := int(floor(dmg * clampf(float(ability.get("chain_fraction", 0.5)), 0.0, 1.0)))
	if jump <= 0:
		return 0
	var range_cells := int(ability.get("chain_range", 2))
	var candidates: Array[Combatant] = []
	for c: Combatant in active():
		if c == target or c == actor or not actor.is_hostile_to(c) or c.hidden:
			continue
		if LineOfSight.distance(target.cell, c.cell) <= range_cells:
			candidates.append(c)
	candidates.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		var da := LineOfSight.distance(target.cell, a.cell)
		var db := LineOfSight.distance(target.cell, b.cell)
		return da < db if da != db else a.id < b.id)
	var reached := 0
	for c: Combatant in candidates:
		if reached >= int(ability.get("chain_targets", 1)):
			break
		var fate := _apply_damage(c, jump, damage_type)
		_emit({"type": "arc", "actor": actor.id, "from": target.id, "target": c.id, "damage": int(fate["dealt"]), "target_hp": c.hp, "downed": fate["downed"], "killed": fate["killed"]})
		reached += 1
	return reached


## A counter stance (D-086): a target holding `counter` strikes back at any
## adjacent hostile that attacks it, hit or miss, once per attack.
func _counter_against(attacker: Combatant, target: Combatant) -> void:
	if int(target.statuses.get("counter", 0)) <= 0 or not target.is_active() or not attacker.is_active():
		return
	if not target.is_hostile_to(attacker) or LineOfSight.distance(attacker.cell, target.cell) > 1:
		return
	var span: Array = target.counter_damage if not target.counter_damage.is_empty() else [1, 1]
	var dmg := rng.randi_range(int(span[0]), int(span[span.size() - 1])) + target.damage_bonus
	var fate := _apply_damage(attacker, dmg, "physical")
	_emit({"type": "counter", "actor": target.id, "target": attacker.id, "damage": int(fate["dealt"]), "target_hp": attacker.hp, "downed": fate["downed"], "killed": fate["killed"]})


## Flat damage bonus an attack would carry: Workshop, elevation, resource
## stacks and, for detonations, the marks on the target (not consumed here).
func damage_bonus_for(actor: Combatant, ability: Dictionary, target: Combatant, mods: Dictionary) -> int:
	var bonus := actor.damage_bonus + int(mods["damage"])
	bonus += int(Dictionary(actor.traits.get("ability_damage_bonus", {})).get(String(ability.get("id", "")), 0))
	if builds_resource(actor, ability):
		bonus += actor.resource * int(actor.resource_def.get("damage_per_stack", 0))
	var mark := String(ability.get("mark", ""))
	if String(ability.get("effect", "")) == "detonate" and not mark.is_empty():
		bonus += target.mark_count(mark) * int(ability.get("damage_per_mark", 0))
	return bonus


## What an ability would do to `target_cell` without rolling: the to-hit
## chance and the damage span after every modifier. `why` is non-empty when
## the ability cannot be used there; the numbers are still filled in when
## only AP or resources are short, so the HUD can show them greyed out.
func preview(actor: Combatant, ability_id: String, target_cell: Vector2i) -> Dictionary:
	var why := can_use(actor, ability_id, target_cell)
	var out: Dictionary = {"why": why, "ability": ability_id, "chance": 0, "min": 0, "max": 0, "heal": 0, "tags": PackedStringArray()}
	if not abilities.has(ability_id):
		return out
	var ability: Dictionary = abilities[ability_id]
	out["name"] = String(ability.get("name", ability_id))
	out["ap"] = int(ability.get("ap", 1))
	if String(ability.get("effect", "")) == "vent":
		out["heal"] = int(ability.get("heal", 0))
		return out
	var target := occupant(target_cell)
	if target == null or target == actor:
		return out
	var flanked := is_flanked(target, actor)
	var mods := attack_modifiers(actor, ability, target)
	var ambush := actor.hidden
	out["chance"] = hit_chance(actor, ability, target, flanked, int(mods["hit"]) + (rules.ambush_hit_bonus if ambush else 0))
	var bonus := damage_bonus_for(actor, ability, target, mods)
	var span: Array = ability.get("damage", [1, 1])
	var lo := int(span[0]) if span.size() > 0 else 1
	var hi := int(span[1]) if span.size() > 1 else lo
	var dmin := mini(lo, hi) + bonus
	var dmax := maxi(lo, hi) + bonus
	if flanked:
		dmin = int(round(dmin * rules.flank_damage_mult))
		dmax = int(round(dmax * rules.flank_damage_mult))
	if bool(mods["amplified"]):
		dmin = int(round(dmin * rules.mana_pool_amplify))
		dmax = int(round(dmax * rules.mana_pool_amplify))
	if ambush:
		dmin = int(round(dmin * rules.ambush_damage_mult))
		dmax = int(round(dmax * rules.ambush_damage_mult))
	out["min"] = maxi(dmin, 0)
	out["max"] = maxi(dmax, 0)
	var tags: PackedStringArray = []
	if ambush:
		tags.append("ambush")
	if flanked:
		tags.append("flanked")
	if int(mods["cover"]) > 0:
		tags.append("cover")
	if bool(mods["elevated"]):
		tags.append("high ground")
	if bool(mods["uphill"]):
		tags.append("uphill")
	if bool(mods["amplified"]):
		tags.append("mana pool")
	if int(mods["shroud"]) > 0:
		tags.append("spores")
	out["tags"] = tags
	out["kills"] = out["min"] >= target.hp
	return out


func hit_chance(actor: Combatant, ability: Dictionary, target: Combatant, flanked: bool, extra: int = 0) -> int:
	var chance := int(ability.get("accuracy", 85)) - target.evasion + extra
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


## Total live stacks of a mark across active combatants.
func total_marks(mark: String) -> int:
	var n := 0
	for c: Combatant in active():
		n += c.mark_count(mark)
	return n


## Mark-kind resources (Hexes) read as the number of live marks of their kind.
func _refresh_mark_resources() -> void:
	for c: Combatant in combatants:
		if String(c.resource_def.get("kind", "")) == "marks":
			c.resource = mini(total_marks(String(c.resource_def.get("mark", ""))), c.resource_max())


## Flanked: some other combatant hostile to the target stands adjacent to it.
func is_flanked(target: Combatant, attacker: Combatant) -> bool:
	for c: Combatant in combatants:
		if c == attacker or c == target or not c.is_active():
			continue
		if c.is_hostile_to(target) and LineOfSight.distance(c.cell, target.cell) == 1:
			return true
	return false


## Conduit cells 4-connected to `origin` (including it).
func conduit_network(origin: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if map.surface_at(origin) != "conduit":
		return out
	var seen: Dictionary = {origin: true}
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		out.append(cur)
		for d: Vector2i in DIRS4:
			var n := cur + d
			if not seen.has(n) and map.surface_at(n) == "conduit":
				seen[n] = true
				frontier.append(n)
	return out


func _chain_shock(target: Combatant, source: Combatant) -> void:
	var dmg := rules.conduit_chain_damage
	if dmg <= 0:
		return
	for cell: Vector2i in conduit_network(target.cell):
		var c := occupant(cell)
		if c == null or c == target:
			continue
		var fate := _apply_damage(c, dmg, "arcane")
		_emit({"type": "chain", "actor": source.id, "target": c.id, "damage": int(fate["dealt"]), "absorbed": int(fate["absorbed"]), "target_hp": c.hp, "downed": fate["downed"], "killed": fate["killed"]})


## A resource with `reveal_at_max` lights its owner up at the cap. Returns
## true when this call revealed them.
func _check_reveal(c: Combatant) -> bool:
	if c.hidden and bool(c.resource_def.get("reveal_at_max", false)) and c.resource_max() > 0 and c.resource >= c.resource_max():
		c.reveal()
		return true
	return false


## Applies damage with Story-Protected knock-outs. A resource with
## `absorb: {type, fraction}` swallows part of damage of that type and
## stores it (`gain_per_absorbed`). Any damage taken reveals a hidden
## combatant. Returns {"downed", "killed", "dealt", "absorbed"}.
func _apply_damage(c: Combatant, dmg: int, damage_type: String = "") -> Dictionary:
	var fate := {"downed": false, "killed": false, "dealt": 0, "absorbed": 0}
	if dmg <= 0 or not c.is_active():
		return fate
	var absorb: Dictionary = c.resource_def.get("absorb", {})
	if not absorb.is_empty() and not damage_type.is_empty() and String(absorb.get("type", "")) == damage_type:
		var absorbed := int(floor(dmg * clampf(float(absorb.get("fraction", 0.0)), 0.0, 1.0)))
		if absorbed > 0:
			dmg -= absorbed
			fate["absorbed"] = absorbed
			c.resource = mini(c.resource + absorbed * int(c.resource_def.get("gain_per_absorbed", 1)), c.resource_max())
	if not damage_type.is_empty():
		var r := c.resist(damage_type) + float(Dictionary(rules.surface_resist.get(map.surface_at(c.cell), {})).get(damage_type, 0.0))
		r = clampf(r, -1.0, 1.0)
		if r != 0.0:
			var shrugged := int(floor(dmg * r)) if r > 0.0 else -int(ceil(dmg * -r))
			dmg -= shrugged
			fate["resisted"] = shrugged
	fate["dealt"] = dmg
	c.reveal()
	if dmg <= 0:
		return fate
	c.hp = maxi(c.hp - dmg, 0)
	if c.hp == 0:
		if c.team == Combatant.TEAM_PARTY and rules.story_protected:
			c.downed = true
			fate["downed"] = true
		else:
			fate["killed"] = true
	return fate


# --- turns -----------------------------------------------------------------

func end_turn() -> void:
	if finished or order.is_empty():
		return
	var actor := current()
	_done[actor.id] = true
	_undo = {}
	_tick_poison(actor)
	actor.tick_statuses()
	_emit({"type": "turn_end", "actor": actor.id})
	# Another member of this group still to act: hand over without leaving the group.
	for c: Combatant in group:
		if c.is_active() and not _done.has(c.id):
			turn_index = order.find(c)
			_lazy_begin(c)
			return
	var last := turn_index
	for c: Combatant in group:
		last = maxi(last, order.find(c))
	_enter_group_at(last + 1)


## Starts the group whose first member is the first active combatant at or
## after `from` (wrapping into a new round). Members begin their turns lazily,
## when they first get control, so surface effects land when they act.
func _enter_group_at(from: int) -> void:
	group.clear()
	_done.clear()
	_begun.clear()
	var idx := from
	var tries := 0
	while tries <= order.size():
		if idx >= order.size():
			idx = 0
			round_number += 1
			_emit({"type": "round", "round": round_number})
		if order[idx].is_active():
			break
		idx += 1
		tries += 1
	if tries > order.size():
		_check_outcome()
		return
	turn_index = idx
	var team := order[idx].team
	for i: int in range(idx, order.size()):
		if order[i].team != team or not order[i].is_active():
			break
		group.append(order[i])
	_lazy_begin(order[idx])


func _lazy_begin(c: Combatant) -> void:
	if _begun.has(c.id):
		return
	_begun[c.id] = true
	_begin_turn()


func _begin_turn() -> void:
	var actor := current()
	if actor == null:
		return
	if not actor.is_active():
		end_turn()
		return
	actor.begin_turn()
	_undo = {}
	_emit({"type": "turn_begin", "actor": actor.id, "team": actor.team, "round": round_number})
	var surface := map.surface_at(actor.cell)
	var surface_gains: Dictionary = actor.resource_def.get("gain_on_surface", {})
	if not surface.is_empty() and surface_gains.has(surface):
		var before := actor.resource
		actor.resource = mini(actor.resource + int(surface_gains[surface]), actor.resource_max())
		if actor.resource != before:
			_emit({"type": "harvest", "actor": actor.id, "surface": surface, "gain": actor.resource - before, "resource": actor.resource})
	var regen: Dictionary = actor.traits.get("regen_on_surface", {})
	if not surface.is_empty() and regen.has(surface) and actor.hp < actor.max_hp:
		var healed := mini(int(regen[surface]), actor.max_hp - actor.hp)
		actor.hp += healed
		_emit({"type": "regen", "actor": actor.id, "surface": surface, "heal": healed, "actor_hp": actor.hp})
	var laid: Dictionary = rules.surface_status.get(surface, {})
	for st: String in laid:
		actor.statuses[st] = maxi(int(actor.statuses.get(st, 0)), int(laid[st]))
		_emit({"type": "surface_status", "actor": actor.id, "surface": surface, "status": st, "turns": int(laid[st])})
	var sight := int(actor.traits.get("detect_hidden", 0))
	if sight > 0:
		for c: Combatant in active():
			if c.hidden and c.is_hostile_to(actor) and LineOfSight.distance(actor.cell, c.cell) <= sight and LineOfSight.clear(map, actor.cell, c.cell):
				c.reveal()
				_emit({"type": "detect", "actor": actor.id, "target": c.id, "range": sight})
	if surface == "corrosive" and rules.corrosive_damage > 0 and actor.resist("corrosive") < 1.0:
		var fate := _apply_damage(actor, rules.corrosive_damage, "corrosive")
		_emit({"type": "surface", "actor": actor.id, "surface": "corrosive", "damage": rules.corrosive_damage, "actor_hp": actor.hp, "downed": fate["downed"], "killed": fate["killed"]})
		_check_outcome()
		if not finished and not actor.is_active():
			end_turn()


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


## Cheapest cost to every cell within the actor's Move (S65: a step up in
## height costs `climb_move_cost` more, so this is a shortest-path search,
## not a breadth-first one). Diagonals need both side cells walkable.
func _flood(actor: Combatant) -> Dictionary:
	var costs: Dictionary = {}
	var parents: Dictionary = {}
	var best: Dictionary = {actor.cell: 0}
	var settled: Dictionary = {}
	var frontier: Array[Vector2i] = [actor.cell]
	while not frontier.is_empty():
		var cur: Vector2i = frontier[0]
		var cur_i := 0
		for i: int in range(1, frontier.size()):
			if int(best[frontier[i]]) < int(best[cur]):
				cur = frontier[i]
				cur_i = i
		frontier.remove_at(cur_i)
		if settled.has(cur):
			continue
		settled[cur] = true
		var c: int = best[cur]
		if c >= actor.move_left:
			continue
		for d: Vector2i in DIRS8:
			var n := cur + d
			if settled.has(n) or not _passable(n):
				continue
			if d.x != 0 and d.y != 0:
				if not (map.is_walkable(cur + Vector2i(d.x, 0)) and map.is_walkable(cur + Vector2i(0, d.y))):
					continue
			var step := 1 + (rules.climb_move_cost if map.height_at(n) > map.height_at(cur) else 0)
			if c + step > actor.move_left:
				continue
			if best.has(n) and int(best[n]) <= c + step:
				continue
			best[n] = c + step
			costs[n] = c + step
			parents[n] = cur
			frontier.append(n)
	return {"costs": costs, "parents": parents}


func _passable(cell: Vector2i) -> bool:
	return map.is_walkable(cell) and occupant(cell) == null


## Living combatants summoned by `actor`.
func summons_of(actor: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in combatants:
		if c.summoned_by == actor.id and c.is_active():
			out.append(c)
	return out


## First free walkable cell around `origin` (fixed direction order), or (-1, -1).
func free_adjacent(origin: Vector2i) -> Vector2i:
	for d: Vector2i in DIRS8:
		var n := origin + d
		if _passable(n):
			return n
	return Vector2i(-1, -1)


## Walking distance (steps, same adjacency as movement, occupants ignored)
## from every walkable cell to `goal`. Cells not in the result are cut off
## by walls. Used to approach around obstacles instead of straight at them.
func distance_field(goal: Vector2i) -> Dictionary:
	var dist: Dictionary = {goal: 0}
	var frontier: Array[Vector2i] = [goal]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		var c: int = dist[cur]
		for d: Vector2i in DIRS8:
			var n := cur + d
			if dist.has(n) or not map.is_walkable(n):
				continue
			if d.x != 0 and d.y != 0:
				if not (map.is_walkable(cur + Vector2i(d.x, 0)) and map.is_walkable(cur + Vector2i(0, d.y))):
					continue
			dist[n] = c + 1
			frontier.append(n)
	return dist


func _emit(e: Dictionary) -> void:
	var line := describe(e)
	if not line.is_empty():
		history.append(line)
	event.emit(e)


## Human-readable line for an event, for logs and the HUD.
func _names(ids: Array) -> String:
	var out: PackedStringArray = []
	for id: String in ids:
		out.append(_name(id))
	return ", ".join(out)


func describe(e: Dictionary) -> String:
	match String(e.get("type", "")):
		"start":
			return Loc.t("Combat begins. Order: %s") % _names(e["order"])
		"round":
			return Loc.t("— Round %d —") % int(e["round"])
		"regen":
			return Loc.t("%s mends %d in the %s.") % [_name(e["actor"]), int(e["heal"]), Loc.t(String(e["surface"]))]
		"arc":
			return Loc.t("Lightning arcs from %s to %s for %d.%s") % [_name(e["from"]), _name(e["target"]), int(e["damage"]), (" %s dies." % _name(e["target"])) if bool(e["killed"]) else ""]
		"counter":
			return Loc.t("%s counters %s for %d.%s") % [_name(e["actor"]), _name(e["target"]), int(e["damage"]), (" %s dies." % _name(e["target"])) if bool(e["killed"]) else ""]
		"poison":
			return Loc.t("%s takes %d from poison (%d left).%s") % [_name(e["actor"]), int(e["damage"]), int(e["turns"]) - 1, (" %s dies." % _name(e["actor"])) if bool(e["killed"]) else ""]
		"spread":
			return Loc.t("The poison spreads from %s to %s.") % [_name(e["actor"]), _name(e["target"])]
		"surface_status":
			return Loc.t("%s: the %s font takes the voice (%s %d).") % [_name(e["actor"]), Loc.t(String(e["surface"])), Loc.t(String(e["status"])), int(e["turns"])]
		"stance":
			return Loc.t("%s takes a %s stance (%d).") % [_name(e["actor"]), Loc.t(String(e["stance"])), int(e["turns"])]
		"detect":
			return Loc.t("%s senses %s hiding.") % [_name(e["actor"]), _name(e["target"])]
		"opportunity":
			var ab_name: String = String(Dictionary(abilities.get(e["ability"], {})).get("name", e["ability"]))
			if not bool(e["hit"]):
				return Loc.t("%s swings at %s passing — miss (%d vs %d%%).") % [_name(e["actor"]), _name(e["target"]), int(e["roll"]), int(e["chance"])]
			var line := Loc.t("%s: %s catches %s passing for %d.") % [_name(e["actor"]), ab_name, _name(e["target"]), int(e["damage"])]
			if bool(e["killed"]):
				line += Loc.t(" %s dies.") % _name(e["target"])
			elif bool(e["downed"]):
				line += Loc.t(" %s goes down.") % _name(e["target"])
			return line
		"resumed":
			return Loc.t("— The fight resumes (round %d, %s to act) —") % [int(e["round"]), _name(String(e["actor"])) if not String(e["actor"]).is_empty() else Loc.t("nobody")]
		"opener":
			return Loc.t("The party strikes from cover: nobody saw them coming.")
		"hack":
			if bool(e["hit"]):
				return Loc.t("%s hacks %s: it is ours now.") % [_name(e["actor"]), _name(e["target"])]
			return Loc.t("%s: the hack on %s fails (%d vs %d%%).") % [_name(e["actor"]), _name(e["target"]), int(e["roll"]), int(e["chance"])]
		"turn_begin":
			return Loc.t("%s's turn.") % _name(e["actor"])
		"move":
			return Loc.t("%s moves to %s.") % [_name(e["actor"]), e["to"]]
		"ability":
			var who := _name(e["actor"])
			var whom := _name(e["target"])
			var ab: Dictionary = abilities.get(e["ability"], {})
			var ab_name: String = String(ab.get("name", e["ability"]))
			var tags: PackedStringArray = []
			if bool(e.get("ambush", false)):
				tags.append("ambush")
			if bool(e.get("flanked", false)):
				tags.append("flanked")
			if int(e.get("absorbed", 0)) > 0:
				tags.append("%d absorbed" % int(e["absorbed"]))
			if int(e.get("silenced", 0)) > 0:
				tags.append("silenced %d" % int(e["silenced"]))
			if int(e.get("rooted", 0)) > 0:
				tags.append("rooted %d" % int(e["rooted"]))
			if int(e.get("cover", 0)) > 0:
				tags.append("cover")
			if bool(e.get("elevated", false)):
				tags.append("high ground")
			if bool(e.get("uphill", false)):
				tags.append("uphill")
			if bool(e.get("amplified", false)):
				tags.append("mana pool")
			if int(e.get("shroud", 0)) > 0:
				tags.append("spores")
			if int(e.get("resource_stacks", 0)) > 0:
				tags.append("%d stacks" % int(e["resource_stacks"]))
			if int(e.get("detonated", 0)) > 0:
				tags.append("detonated %d" % int(e["detonated"]))
			if int(e.get("marked", 0)) > 0:
				tags.append("hex ×%d" % int(e["marked"]))
			var tag_text := "" if tags.is_empty() else Loc.t(" (%s)") % ", ".join(tags)
			if not bool(e["hit"]):
				return Loc.t("%s: %s on %s — miss (%d vs %d%%)%s.") % [who, ab_name, whom, e["roll"], e["chance"], tag_text]
			var s := Loc.t("%s: %s hits %s for %d%s.") % [who, ab_name, whom, e["damage"], tag_text]
			if bool(e["killed"]):
				s += Loc.t(" %s dies.") % whom
			elif bool(e["downed"]):
				s += Loc.t(" %s is down.") % whom
			return s
		"vent":
			return Loc.t("%s vents (+%d HP).") % [_name(e["actor"]), int(e["heal"])]
		"summon":
			return Loc.t("%s calls in %s.") % [_name(e["actor"]), _name(e["summoned"])]
		"stealth":
			if bool(e.get("revealed", false)):
				return Loc.t("%s tries to hide but overheats, lit up.") % _name(e["actor"])
			return Loc.t("%s vanishes.") % _name(e["actor"])
		"harvest":
			return Loc.t("%s harvests %d from the %s.") % [_name(e["actor"]), int(e["gain"]), String(e["surface"]).replace("_", " ")]
		"overload":
			var s := Loc.t("%s overloads! %d damage to self.") % [_name(e["actor"]), int(e["damage"])]
			if bool(e["killed"]):
				s += Loc.t(" %s dies.") % _name(e["actor"])
			elif bool(e["downed"]):
				s += Loc.t(" %s is down.") % _name(e["actor"])
			return s
		"chain":
			var s := Loc.t("The conduit arcs: %s takes %d.") % [_name(e["target"]), int(e["damage"])]
			if bool(e["killed"]):
				s += Loc.t(" %s dies.") % _name(e["target"])
			elif bool(e["downed"]):
				s += Loc.t(" %s is down.") % _name(e["target"])
			return s
		"surface":
			var s := Loc.t("%s burns in the biogrowth for %d.") % [_name(e["actor"]), int(e["damage"])]
			if bool(e["killed"]):
				s += Loc.t(" %s dies.") % _name(e["actor"])
			elif bool(e["downed"]):
				s += Loc.t(" %s is down.") % _name(e["actor"])
			return s
		"turn_end", "switch":
			return ""
		"undo":
			return Loc.t("%s steps back to %s.") % [_name(e["actor"]), e["to"]]
		"end":
			return "Victory." if e["result"] == "victory" else Loc.t("The party is wiped out.")
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



## Poison ticks at the end of the victim's own turn; a spreading poison
## jumps to adjacent teammates with one turn less, so it burns out.
func _tick_poison(actor: Combatant) -> void:
	var turns := int(actor.statuses.get("poisoned", 0))
	if turns <= 0 or actor.poison.is_empty() or not actor.is_active():
		return
	var dmg := int(actor.poison.get("damage", 1))
	var fate := _apply_damage(actor, dmg, String(actor.poison.get("type", "poison")))
	_emit({"type": "poison", "actor": actor.id, "damage": int(fate["dealt"]), "actor_hp": actor.hp, "downed": fate["downed"], "killed": fate["killed"], "turns": turns})
	if bool(actor.poison.get("spread", false)) and turns > 1:
		for c: Combatant in active():
			if c == actor or c.team != actor.team or c.statuses.has("poisoned") or LineOfSight.distance(actor.cell, c.cell) > 1:
				continue
			_poison(c, turns - 1, dmg, true, String(actor.poison.get("source", "")), String(actor.poison.get("type", "poison")))
			_emit({"type": "spread", "actor": actor.id, "target": c.id, "turns": turns - 1})
	_check_outcome()
