extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [2, 4], "accuracy": 85},
	"zap": {"id": "zap", "name": "Zap", "ap": 1, "range": 4, "damage": [1, 3], "accuracy": 75, "requires_los": true},
}


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "b", "legend": {".": "floor", "#": "wall", "P": "floor"}, "rows": rows}, TILES)


static func _c(id: String, team: String, cell: Vector2i, archetype: String = "rusher", abilities: Array[String] = ["strike"], move: int = 4) -> Combatant:
	var c := Combatant.make(id, id, team, cell, {"hp": 10, "move": move, "evasion": 0, "initiative": 0}, abilities, 4)
	c.archetype = archetype
	return c


func _state(rows: Array, combatants: Array[Combatant], first: String) -> CombatState:
	var s := CombatState.new()
	var rules := CombatRules.new()
	rules.initiative_die = 1
	s.setup(_map(rows), rules, ABILITIES, combatants, 1)
	s.start(first)
	return s


func test_rusher_attacks_when_adjacent() -> void:
	var e := _c("e", "enemy", Vector2i(1, 0))
	var s := _state(["P......"], [_c("p", "party", Vector2i(0, 0)), e], "enemy")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "ability")
	assert_eq(a["id"], "strike")
	assert_eq(a["target"], Vector2i(0, 0))


func test_rusher_closes_distance_then_attacks() -> void:
	var e := _c("e", "enemy", Vector2i(6, 0))
	var p := _c("p", "party", Vector2i(0, 0))
	var s := _state(["P......"], [p, e], "enemy")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "move")
	assert_eq(a["to"], Vector2i(2, 0), "four cells of movement, straight at the target")
	s.move(e, a["to"])
	var b := EnemyBrain.next_action(s, e)
	assert_eq(b["type"], "end", "out of movement and still out of range")


func test_rusher_ends_when_out_of_ap() -> void:
	var e := _c("e", "enemy", Vector2i(1, 0))
	var s := _state(["P......"], [_c("p", "party", Vector2i(0, 0)), e], "enemy")
	e.ap = 0
	e.move_left = 0
	assert_eq(EnemyBrain.next_action(s, e)["type"], "end")


func test_rusher_picks_nearest_hostile() -> void:
	var e := _c("e", "enemy", Vector2i(3, 0))
	var s := _state(["P......"], [_c("far", "party", Vector2i(0, 0)), _c("near", "party", Vector2i(5, 0)), e], "enemy")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "move")
	assert_eq(a["to"], Vector2i(4, 0))


func test_ranged_shoots_at_distance() -> void:
	var d := _c("d", "enemy", Vector2i(3, 0), "ranged", ["zap"])
	var s := _state(["P......"], [_c("p", "party", Vector2i(0, 0)), d], "enemy")
	var a := EnemyBrain.next_action(s, d)
	assert_eq(a["type"], "ability")
	assert_eq(a["id"], "zap")


func test_ranged_kites_away_when_adjacent() -> void:
	var d := _c("d", "enemy", Vector2i(1, 0), "ranged", ["zap"])
	var p := _c("p", "party", Vector2i(0, 0))
	var s := _state(["P......", ".......", "......."], [p, d], "enemy")
	var a := EnemyBrain.next_action(s, d)
	assert_eq(a["type"], "move")
	var dist := LineOfSight.distance(a["to"], p.cell)
	assert_true(dist >= 2 and dist <= 4, "kites to %s (distance %d)" % [a["to"], dist])
	s.move(d, a["to"])
	assert_eq(EnemyBrain.next_action(s, d)["type"], "ability", "then shoots")


func test_ranged_moves_to_regain_line_of_sight() -> void:
	var d := _c("d", "enemy", Vector2i(4, 0), "ranged", ["zap"])
	var p := _c("p", "party", Vector2i(0, 0))
	var s := _state(["P.#....", ".......", "......."], [p, d], "enemy")
	assert_false(LineOfSight.clear(s.map, d.cell, p.cell))
	var a := EnemyBrain.next_action(s, d)
	assert_eq(a["type"], "move")
	assert_true(LineOfSight.clear(s.map, a["to"], p.cell), "new cell sees the target")


func test_no_hostiles_ends_turn() -> void:
	var e := _c("e", "enemy", Vector2i(1, 0))
	var p := _c("p", "party", Vector2i(0, 0))
	p.hp = 0
	var s := _state(["P......"], [p, e], "enemy")
	assert_eq(EnemyBrain.next_action(s, e)["type"], "end")


func test_usable_ability_prefers_higher_damage() -> void:
	var e := _c("e", "enemy", Vector2i(1, 0), "rusher", ["strike", "zap"])
	var p := _c("p", "party", Vector2i(0, 0))
	var s := _state(["P......"], [p, e], "enemy")
	assert_eq(EnemyBrain.usable_ability(s, e, p), "strike", "3 avg beats 2 avg")



# --- S16: texture-aware positioning, summoner, controller, scripted fights ---

const TEXTURE_TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
	"low": {"id": "low", "walkable": false, "blocks_sight": false, "cover": 1},
	"high": {"id": "high", "walkable": true, "height": 1},
	"bio": {"id": "bio", "walkable": true, "surface": "corrosive"},
	"pool": {"id": "pool", "walkable": true, "surface": "mana_pool"},
}
const S16_ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [3, 3], "accuracy": 100, "damage_type": "physical"},
	"zap": {"id": "zap", "name": "Zap", "ap": 1, "range": 4, "damage": [2, 2], "accuracy": 100, "damage_type": "tech", "requires_los": true},
	"bolt": {"id": "bolt", "name": "Bolt", "ap": 1, "range": 4, "damage": [2, 2], "accuracy": 100, "damage_type": "arcane", "requires_los": true},
	"spawn": {"id": "spawn", "name": "Spawn", "ap": 2, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "summon", "summon": "drone", "summon_max": 2, "cooldown": 1},
	"net": {"id": "net", "name": "Net", "ap": 1, "range": 4, "damage": [1, 1], "accuracy": 100, "damage_type": "physical", "requires_los": true, "effect": "root", "duration": 1},
}
const DRONE: Dictionary = {"id": "drone", "name": "Drone", "archetype": "rusher", "stats": {"hp": 4, "move": 5, "evasion": 0, "initiative": 0}, "abilities": ["strike"]}


static func _tmap(rows: Array) -> MapData:
	return MapData.parse({"id": "t", "legend": {".": "floor", "#": "wall", "x": "low", "^": "high", "b": "bio", "m": "pool", "P": "floor"}, "rows": rows}, TEXTURE_TILES)


static func _tc(id: String, team: String, cell: Vector2i, archetype: String, abilities: Array[String], hp: int = 10, move: int = 4) -> Combatant:
	var c := Combatant.make(id, id, team, cell, {"hp": hp, "move": move, "evasion": 0, "initiative": 0}, abilities, 4)
	c.archetype = archetype
	return c


func _tstate(rows: Array, combatants: Array[Combatant], first: String) -> CombatState:
	var s := CombatState.new()
	var rules := CombatRules.new()
	rules.initiative_die = 1
	rules.min_hit_chance = 0
	rules.max_hit_chance = 100
	s.enemy_entries = {"drone": DRONE}
	s.setup(_tmap(rows), rules, S16_ABILITIES, combatants, 1)
	s.start(first)
	return s


func test_ranged_moves_behind_cover_before_shooting() -> void:
	# The shooter at (4,0) is in band already; (4,1) has debris between it and the target.
	var p := _tc("p", "party", Vector2i(0, 1), "rusher", ["strike"])
	var e := _tc("e", "enemy", Vector2i(4, 0), "ranged", ["zap"])
	var s := _tstate(["......", "..x...", "......"], [p, e], "enemy")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "move", "a covered firing cell exists")
	var to: Vector2i = a["to"]
	assert_true(EnemyBrain.position_score(s, e, to, p) > EnemyBrain.position_score(s, e, e.cell, p), "moved to better texture")
	s.move(e, to)
	var b := EnemyBrain.next_action(s, e)
	assert_eq(b["type"], "ability", "then shoots")
	assert_eq(b["id"], "zap")


func test_ranged_in_a_good_spot_shoots_instead_of_wandering() -> void:
	var p := _tc("p", "party", Vector2i(0, 0), "rusher", ["strike"])
	var e := _tc("e", "enemy", Vector2i(3, 0), "ranged", ["zap"])
	var s := _tstate(["......"], [p, e], "enemy")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "ability", "no better texture anywhere: stay and shoot")


func test_rusher_avoids_biogrowth_and_takes_high_ground() -> void:
	# Two ways to reach the target: over biogrowth (1,0) or high ground (1,2).
	var p := _tc("p", "party", Vector2i(2, 1), "rusher", ["strike"])
	var e := _tc("e", "enemy", Vector2i(0, 1), "rusher", ["strike"], 10, 1)
	var s := _tstate([".b..", "....", ".^.."], [p, e], "enemy")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "move")
	assert_eq(a["to"], Vector2i(1, 2), "the raised cell, not the biogrowth (both one step away)")
	assert_true(EnemyBrain.position_score(s, e, Vector2i(1, 0), p) < 0, "biogrowth scores negative")
	assert_true(EnemyBrain.position_score(s, e, Vector2i(1, 2), p) > 0, "height scores positive")


func test_arcane_caster_favours_the_mana_pool() -> void:
	var p := _tc("p", "party", Vector2i(0, 0), "rusher", ["strike"])
	var caster := _tc("e", "enemy", Vector2i(3, 0), "ranged", ["bolt"])
	var techie := _tc("t", "enemy", Vector2i(3, 2), "ranged", ["zap"])
	var s := _tstate(["......", "......", "...m.."], [p, caster, techie], "enemy")
	assert_true(EnemyBrain.position_score(s, caster, Vector2i(3, 2), p) > 0, "a pool is worth something to a caster")
	assert_eq(EnemyBrain.position_score(s, techie, Vector2i(3, 2), p), 0, "and nothing to a gunner")


func test_summoner_calls_minions_to_its_limit_then_kites() -> void:
	var p := _tc("p", "party", Vector2i(0, 0), "rusher", ["strike"])
	var mother := _tc("m", "enemy", Vector2i(4, 0), "summoner", ["spawn", "zap"], 12)
	var s := _tstate(["......", "......"], [p, mother], "enemy")
	mother.ap = 9
	var a := EnemyBrain.next_action(s, mother)
	assert_eq(a["id"], "spawn")
	var r := s.use_ability(mother, "spawn", mother.cell)
	assert_eq(r["type"], "summon")
	assert_eq(s.summons_of(mother).size(), 1)
	var minion := s.by_id(String(r["summoned"]))
	assert_eq(minion.team, "enemy")
	assert_eq(minion.summoned_by, "m")
	assert_true(LineOfSight.distance(minion.cell, mother.cell) == 1, "placed beside her")
	assert_true(s.order.has(minion), "acts at the end of the order")
	assert_any_contains(s.history, "m calls in Drone.")
	assert_eq(s.can_use(mother, "spawn", mother.cell), "cooling down (1)")
	mother.statuses.erase("cd:spawn")
	s.use_ability(mother, "spawn", mother.cell)
	assert_eq(s.summons_of(mother).size(), 2)
	mother.statuses.erase("cd:spawn")
	assert_eq(s.can_use(mother, "spawn", mother.cell), "swarm at its limit")
	var b := EnemyBrain.next_action(s, mother)
	assert_true(b["type"] == "ability" and b["id"] == "zap" or b["type"] == "move", "at the limit she fights like a ranged")
	minion.hp = 0
	mother.statuses.erase("cd:spawn")
	assert_eq(s.can_use(mother, "spawn", mother.cell), "", "a dead minion frees a slot")


func test_controller_roots_the_runner_then_shoots() -> void:
	var p := _tc("p", "party", Vector2i(0, 0), "rusher", ["strike"])
	var q := _tc("q", "party", Vector2i(0, 2), "rusher", ["strike"])
	var boss := _tc("b", "enemy", Vector2i(3, 1), "controller", ["net", "zap"])
	var s := _tstate(["....", "....", "...."], [p, q, boss], "enemy")
	boss.ap = 9
	var a := EnemyBrain.next_action(s, boss)
	assert_eq(a["id"], "net")
	assert_eq(a["target"], p.cell, "nearest un-rooted target first")
	var r := s.use_ability(boss, "net", p.cell)
	assert_eq(int(r["rooted"]), 1)
	assert_true(p.is_rooted())
	assert_any_contains(s.history, "rooted 1")
	var b := EnemyBrain.next_action(s, boss)
	assert_eq(b["id"], "net")
	assert_eq(b["target"], q.cell, "then the next fresh target")
	s.use_ability(boss, "net", q.cell)
	var c := EnemyBrain.next_action(s, boss)
	assert_true(c["type"] == "ability" and c["id"] == "zap" or c["type"] == "move", "everyone rooted: back to shooting")
	assert_eq(EnemyBrain.usable_ability(s, boss, p), "zap", "a spent control effect is not chosen again")
	s.end_turn()
	assert_eq(s.current(), p)
	assert_eq(p.move_left, 0, "rooted: no movement this turn")
	assert_eq(s.can_move(p, Vector2i(1, 0)), "rooted")
	s.end_turn()
	s.end_turn()
	s.end_turn()
	assert_eq(s.current(), p)
	assert_false(p.is_rooted(), "free again next turn")
	assert_eq(p.move_left, p.move_max)


func test_every_archetype_beats_a_party_that_only_swings_back() -> void:
	for archetype: String in ["rusher", "ranged", "stealther", "summoner", "controller"]:
		var abilities: Array[String] = []
		match archetype:
			"rusher":
				abilities = ["strike"]
			"ranged":
				abilities = ["zap"]
			"stealther":
				abilities = ["strike", "hide"]
			"summoner":
				abilities = ["spawn", "zap"]
			"controller":
				abilities = ["net", "zap"]
		var all_abilities := S16_ABILITIES.duplicate(true)
		all_abilities["hide"] = {"id": "hide", "name": "Hide", "ap": 1, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "stealth", "duration": 2, "cooldown": 3}
		var p := _tc("p", "party", Vector2i(0, 1), "rusher", ["strike"], 12)
		var e := _tc("e", "enemy", Vector2i(5, 1), archetype, abilities, 30, 4)
		var s := CombatState.new()
		var rules := CombatRules.new()
		rules.initiative_die = 1
		rules.min_hit_chance = 0
		rules.max_hit_chance = 100
		s.enemy_entries = {"drone": DRONE}
		s.setup(_tmap(["........", "........", "........"]), rules, all_abilities, [p, e], 3)
		s.start("party")
		var guard := 0
		while not s.finished and guard < 400:
			guard += 1
			var actor := s.current()
			if actor.team == "party":
				# Naive: swing at anything adjacent and visible, otherwise wait.
				var swung := false
				for c: Combatant in s.active("enemy"):
					if not c.hidden and LineOfSight.distance(actor.cell, c.cell) == 1 and s.can_use(actor, "strike", c.cell).is_empty():
						s.use_ability(actor, "strike", c.cell)
						swung = true
						break
				if not swung:
					s.end_turn()
			else:
				var action := EnemyBrain.next_action(s, actor)
				match String(action["type"]):
					"ability":
						assert_false(s.use_ability(actor, action["id"], action["target"]).is_empty(), "%s: %s refused" % [archetype, action["id"]])
					"move":
						assert_true(s.move(actor, action["to"]), "%s: move refused" % archetype)
					_:
						s.end_turn()
		assert_true(s.finished, "%s fight resolves (round %d)" % [archetype, s.round_number])
		assert_eq(s.result, "defeat", "%s wins against a passive party" % archetype)


## S27: a controller whose only damage is melee (the Warlord's fist) closes
## in after its nets instead of kiting away from the target it cannot shoot.
func test_melee_controller_closes_in_after_its_nets() -> void:
	var p := _tc("p", "party", Vector2i(0, 1), "rusher", ["strike"])
	var boss := _tc("b", "enemy", Vector2i(3, 1), "controller", ["net", "strike"])
	var s := _tstate(["......", "......", "......"], [p, boss], "enemy")
	boss.ap = 9
	var a := EnemyBrain.next_action(s, boss)
	assert_eq(a["id"], "net", "control first")
	s.use_ability(boss, "net", p.cell)
	var b := EnemyBrain.next_action(s, boss)
	assert_eq(b["type"], "move", "then close: %s" % [b])
	assert_true(LineOfSight.distance(Vector2i(b["to"]), p.cell) < 3, "toward the target, not away")
	var shooter := _tc("z", "enemy", Vector2i(3, 1), "controller", ["net", "zap"])
	var s2 := _tstate(["......", "......", "......"], [p, shooter], "enemy")
	shooter.ap = 9
	s2.use_ability(shooter, "net", p.cell)
	var c := EnemyBrain.next_action(s2, shooter)
	assert_true(c["type"] == "ability" and c["id"] == "zap" or c["type"] == "move", "a ranged controller still shoots or kites: %s" % [c])


# --- S28: focus fire and retreat -------------------------------------------------

func test_focus_fire_picks_the_weakest_target_in_reach() -> void:
	var tank := _tc("t", "party", Vector2i(2, 1), "rusher", ["strike"])
	var weak := _tc("w", "party", Vector2i(4, 1), "rusher", ["strike"])
	var far := _tc("f", "party", Vector2i(9, 1), "rusher", ["strike"])
	var e := _tc("e", "enemy", Vector2i(1, 1), "rusher", ["strike"])
	var s := _tstate(["..........", "..........", ".........."], [tank, weak, far, e], "enemy")
	tank.hp = 20
	weak.hp = 3
	far.hp = 1
	assert_eq(EnemyBrain.pick_target(s, e), weak, "the weakest hostile it can reach this turn, not the nearest")
	assert_eq(EnemyBrain.nearest_hostile(s, e), tank, "nearest is still nearest")
	e.move_left = 0
	assert_eq(EnemyBrain.pick_target(s, e), tank, "with no movement only the adjacent one is in reach")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "ability")
	assert_eq(a["target"], tank.cell)


func test_a_wounded_rusher_breaks_off_once_toward_its_allies() -> void:
	var p := _tc("p", "party", Vector2i(2, 1), "rusher", ["strike"])
	var e := _tc("e", "enemy", Vector2i(3, 1), "rusher", ["strike"])
	var ally := _tc("a", "enemy", Vector2i(9, 1), "rusher", ["strike"])
	var s := _tstate(["..........", "..........", ".........."], [p, e, ally], "enemy")
	e.max_hp = 10
	e.hp = 3
	assert_true(EnemyBrain.should_retreat(s, e), "3/10 next to a hostile with an ally up")
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "move", "breaks off: %s" % [a])
	var to: Vector2i = a["to"]
	assert_true(LineOfSight.distance(to, p.cell) >= 3, "gains at least two cells: %s" % to)
	assert_true(LineOfSight.distance(to, ally.cell) < LineOfSight.distance(e.cell, ally.cell), "toward the ally")
	assert_true(e.retreated)
	s.move(e, to)
	assert_false(EnemyBrain.should_retreat(s, e), "once per fight")
	var b := EnemyBrain.next_action(s, e)
	assert_true(b["type"] != "move" or LineOfSight.distance(Vector2i(b["to"]), p.cell) < LineOfSight.distance(to, p.cell), "then fights on")
	# Alone, it never runs.
	var lone := _tc("l", "enemy", Vector2i(3, 1), "rusher", ["strike"])
	var s2 := _tstate(["......", "......", "......"], [p, lone], "enemy")
	lone.max_hp = 10
	lone.hp = 1
	assert_false(EnemyBrain.should_retreat(s2, lone), "a lone survivor fights to the end")
	assert_eq(EnemyBrain.next_action(s2, lone)["type"], "ability")
