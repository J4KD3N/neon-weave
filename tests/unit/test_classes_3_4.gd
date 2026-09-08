## Circuit-Witch (Hexes) and Drone Shepherd (Scrap Charge) resource loops,
## exercised through the generic mark / cost / harvest vocabulary.
extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"cond": {"id": "cond", "walkable": true, "surface": "conduit"},
}
const ABILITIES: Dictionary = {
	"hex": {"id": "hex", "name": "Hex Bolt", "ap": 1, "range": 5, "damage": [1, 1], "accuracy": 100, "damage_type": "arcane", "effect": "mark", "mark": "hex"},
	"boom": {"id": "boom", "name": "Detonate", "ap": 2, "range": 5, "damage": [2, 2], "accuracy": 100, "damage_type": "arcane", "effect": "detonate", "mark": "hex", "damage_per_mark": 3},
	"shot": {"id": "shot", "name": "Scrap Shot", "ap": 1, "range": 5, "damage": [3, 3], "accuracy": 100, "damage_type": "tech"},
	"over": {"id": "over", "name": "Overcharge", "ap": 2, "range": 5, "damage": [7, 7], "accuracy": 100, "damage_type": "tech", "resource_cost": 2},
}
const HEXES: Dictionary = {"id": "hexes", "name": "Hexes", "kind": "marks", "mark": "hex", "max_per_target": 3, "max": 9}
const SCRAP: Dictionary = {"id": "scrap_charge", "name": "Scrap", "max": 6, "gain_on_kill": 2, "gain_on_surface": {"conduit": 1}}


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "t", "legend": {".": "floor", "c": "cond", "P": "floor"}, "rows": rows}, TILES)


static func _rules() -> CombatRules:
	var r := CombatRules.new()
	r.min_hit_chance = 0
	r.max_hit_chance = 100
	r.initiative_die = 1
	return r


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], hp: int = 30) -> Combatant:
	return Combatant.make(id, id, team, cell, {"hp": hp, "move": 6, "evasion": 0, "initiative": 0}, abilities, 4)


func _state(rows: Array, combatants: Array[Combatant]) -> CombatState:
	var s := CombatState.new()
	s.setup(_map(rows), _rules(), ABILITIES, combatants, 5)
	s.start("party")
	return s


func test_hexes_stack_on_the_target_and_read_out_on_the_witch() -> void:
	var witch := _c("w", "party", Vector2i(0, 0), ["hex", "boom"])
	witch.set_resource(HEXES)
	var e := _c("e", "enemy", Vector2i(2, 0), ["shot"])
	var f := _c("f", "enemy", Vector2i(3, 0), ["shot"])
	var s := _state(["P...."], [witch, e, f])
	witch.ap = 9
	var r1 := s.use_ability(witch, "hex", e.cell)
	assert_eq(int(r1["marked"]), 1)
	assert_eq(e.mark_count("hex"), 1)
	assert_eq(witch.resource, 1, "readout is the live mark total")
	assert_eq(int(r1["resource_after"]), 1)
	s.use_ability(witch, "hex", e.cell)
	s.use_ability(witch, "hex", e.cell)
	s.use_ability(witch, "hex", e.cell)
	assert_eq(e.mark_count("hex"), 3, "capped per target")
	s.use_ability(witch, "hex", f.cell)
	assert_eq(witch.resource, 4, "3 on e + 1 on f")
	assert_eq(s.total_marks("hex"), 4)
	assert_any_contains(s.history, "hex ×3")


func test_detonate_spends_the_stack_for_bonus_damage() -> void:
	var witch := _c("w", "party", Vector2i(0, 0), ["hex", "boom"])
	witch.set_resource(HEXES)
	var e := _c("e", "enemy", Vector2i(2, 0), ["shot"], 40)
	var s := _state(["P..."], [witch, e])
	witch.ap = 9
	for _i: int in 3:
		s.use_ability(witch, "hex", e.cell)
	assert_eq(e.hp, 37)
	var r := s.use_ability(witch, "boom", e.cell)
	assert_eq(int(r["detonated"]), 3)
	assert_eq(int(r["damage"]), 2 + 9, "base 2 + 3 marks × 3")
	assert_eq(e.hp, 26)
	assert_eq(e.mark_count("hex"), 0, "stack consumed")
	assert_eq(witch.resource, 0)
	assert_any_contains(s.history, "detonated 3")
	var r2 := s.use_ability(witch, "boom", e.cell)
	assert_eq(int(r2["detonated"]), 0)
	assert_eq(int(r2["damage"]), 2, "no marks, base damage only")


func test_marks_die_with_the_target() -> void:
	var witch := _c("w", "party", Vector2i(0, 0), ["hex", "boom"])
	witch.set_resource(HEXES)
	var e := _c("e", "enemy", Vector2i(2, 0), ["shot"], 2)
	var f := _c("f", "enemy", Vector2i(3, 0), ["shot"], 30)
	var s := _state(["P...."], [witch, e, f])
	witch.ap = 9
	s.use_ability(witch, "hex", e.cell)
	assert_eq(witch.resource, 1)
	s.use_ability(witch, "hex", e.cell)
	assert_false(e.is_active(), "1 + 1 damage killed it")
	assert_eq(witch.resource, 0, "dead targets carry no live marks")
	assert_eq(int(s.use_ability(witch, "hex", f.cell)["marked"]), 1)


func test_scrap_costs_are_checked_and_spent() -> void:
	var shep := _c("d", "party", Vector2i(0, 0), ["shot", "over"])
	shep.set_resource(SCRAP)
	var e := _c("e", "enemy", Vector2i(2, 0), ["shot"], 40)
	var s := _state(["P..."], [shep, e])
	assert_eq(shep.resource, 0)
	assert_eq(s.can_use(shep, "over", e.cell), "needs 2 Scrap")
	assert_eq(s.use_ability(shep, "over", e.cell), {})
	assert_eq(shep.ap, 4, "refused casts cost nothing")
	shep.resource = 3
	assert_eq(s.can_use(shep, "over", e.cell), "")
	var r := s.use_ability(shep, "over", e.cell)
	assert_eq(int(r["resource_cost"]), 2)
	assert_eq(shep.resource, 1)
	assert_eq(int(r["damage"]), 7)
	assert_eq(int(r["resource_after"]), 1)
	assert_eq(s.can_use(shep, "shot", e.cell), "", "the cheap shot never needs Scrap")


func test_scrap_is_harvested_from_kills_and_conduits() -> void:
	var shep := _c("d", "party", Vector2i(0, 0), ["shot", "over"])
	shep.set_resource(SCRAP)
	var weak := _c("e", "enemy", Vector2i(2, 0), ["shot"], 3)
	var tank := _c("t", "enemy", Vector2i(3, 0), ["shot"], 50)
	var s := _state(["c..."], [shep, weak, tank])
	assert_eq(shep.resource, 1, "standing on a conduit at turn start harvests 1")
	assert_any_contains(s.history, "d harvests 1 from the conduit")
	var r := s.use_ability(shep, "shot", weak.cell)
	assert_true(bool(r["killed"]))
	assert_eq(shep.resource, 3, "+2 for the kill")
	shep.resource = 6
	s.end_turn()
	s.end_turn()
	assert_eq(s.current(), shep)
	assert_eq(shep.resource, 6, "capped at max, no harvest event")
	assert_eq(s.history.count("d harvests 1 from the conduit."), 1)


func test_resourceless_actor_ignores_new_fields() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["hex", "over"])
	var e := _c("e", "enemy", Vector2i(2, 0), ["shot"], 40)
	var s := _state(["c..."], [p, e])
	assert_eq(s.can_use(p, "over", e.cell), "needs 2 charge")
	var r := s.use_ability(p, "hex", e.cell)
	assert_eq(int(r["marked"]), 1, "anyone can place a mark")
	assert_eq(e.mark_count("hex"), 1)
	assert_false(r.has("resource_after"))
