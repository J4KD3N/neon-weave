extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
	"low": {"id": "low", "walkable": false, "blocks_sight": false},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [2, 4], "accuracy": 85},
	"shoot": {"id": "shoot", "name": "Shoot", "ap": 1, "range": 5, "damage": [1, 3], "accuracy": 75, "requires_los": true},
	"sure": {"id": "sure", "name": "Sure Hit", "ap": 1, "range": 1, "damage": [4, 4], "accuracy": 100},
	"big": {"id": "big", "name": "Big", "ap": 2, "range": 1, "damage": [20, 20], "accuracy": 100},
}

var events: Array[Dictionary] = []


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "c", "legend": {".": "floor", "#": "wall", "x": "low", "P": "floor"}, "rows": rows}, TILES)


static func _rules() -> CombatRules:
	var r := CombatRules.new()
	r.max_hit_chance = 100
	r.min_hit_chance = 0
	return r


static func _c(id: String, team: String, cell: Vector2i, hp: int = 10, abilities: Array[String] = ["strike"], move: int = 6) -> Combatant:
	return Combatant.make(id, id, team, cell, {"hp": hp, "move": move, "evasion": 0, "initiative": 0}, abilities, 4)


func _state(rows: Array, combatants: Array[Combatant], seed_value: int = 1, rules: CombatRules = _rules()) -> CombatState:
	var s := CombatState.new()
	s.setup(_map(rows), rules, ABILITIES, combatants, seed_value)
	events.clear()
	s.event.connect(func(e: Dictionary) -> void: events.append(e))
	return s


func _types() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in events:
		out.append(e["type"])
	return out


func test_initiative_is_deterministic_and_descending() -> void:
	var a := _state(["P....."], [_c("a", "party", Vector2i(0, 0)), _c("b", "enemy", Vector2i(3, 0)), _c("c", "enemy", Vector2i(5, 0))], 42)
	a.start()
	var b := _state(["P....."], [_c("a", "party", Vector2i(0, 0)), _c("b", "enemy", Vector2i(3, 0)), _c("c", "enemy", Vector2i(5, 0))], 42)
	b.start()
	assert_eq(CombatState._ids(a.order), CombatState._ids(b.order), "same seed, same order")
	for i: int in range(1, a.order.size()):
		assert_true(a.order[i - 1].initiative >= a.order[i].initiative)
	assert_eq(a.round_number, 1)
	assert_eq(a.current(), a.order[0])
	assert_eq(_types().slice(0, 3), ["start", "round", "turn_begin"])


func test_first_strike_team_goes_first() -> void:
	var rules := _rules()
	rules.initiative_die = 1
	var s := _state(["P....."], [_c("e1", "enemy", Vector2i(3, 0)), _c("p1", "party", Vector2i(0, 0)), _c("e2", "enemy", Vector2i(5, 0))], 7, rules)
	s.start("party")
	assert_eq(s.current().id, "p1")
	assert_eq(s.current().initiative, 1 + rules.first_strike_initiative_bonus)


func test_turn_start_restores_ap_and_move() -> void:
	var p := _c("p", "party", Vector2i(0, 0))
	var s := _state(["P....."], [p, _c("e", "enemy", Vector2i(5, 0))])
	s.start()
	var first := s.current()
	first.ap = 0
	first.move_left = 0
	s.end_turn()
	s.end_turn()
	assert_eq(s.round_number, 2)
	assert_eq(s.current(), first)
	assert_eq(first.ap, 4)
	assert_eq(first.move_left, first.move_max)


func test_reachable_respects_move_walls_and_occupants() -> void:
	var p := _c("p", "party", Vector2i(0, 1), 10, ["strike"], 2)
	var e := _c("e", "enemy", Vector2i(2, 1))
	var s := _state(["P..#.", "...#.", "....."], [p, e])
	s.start()
	var reach := s.reachable_cells(p)
	assert_false(reach.has(Vector2i(0, 1)), "own cell excluded")
	assert_true(reach.has(Vector2i(1, 1)))
	assert_false(reach.has(Vector2i(2, 1)), "occupied by the enemy")
	assert_false(reach.has(Vector2i(3, 1)), "wall")
	assert_false(reach.has(Vector2i(4, 1)), "beyond the wall and the budget")
	assert_eq(reach[Vector2i(2, 2)], 2)
	assert_eq(reach[Vector2i(1, 0)], 1, "diagonal step costs one")
	for cell: Vector2i in reach:
		assert_true(int(reach[cell]) <= 2)


func test_no_corner_cutting_in_reach() -> void:
	var p := _c("p", "party", Vector2i(0, 0), 10, ["strike"], 1)
	var s := _state(["P#", ".."], [p, _c("e", "enemy", Vector2i(5, 0))])
	s.start()
	var reach := s.reachable_cells(p)
	assert_false(reach.has(Vector2i(1, 1)), "diagonal past the wall corner")
	assert_true(reach.has(Vector2i(0, 1)))


func test_move_spends_budget_and_refuses_bad_moves() -> void:
	var p := _c("p", "party", Vector2i(0, 0), 10, ["strike"], 3)
	var e := _c("e", "enemy", Vector2i(5, 0))
	var s := _state(["P....."], [p, e])
	s.start()
	var actor := s.current()
	var other := e if actor == p else p
	assert_eq(s.can_move(other, Vector2i(1, 0)), "not your turn")
	assert_true(s.move(actor, actor.cell + Vector2i(2 if actor == p else -2, 0)))
	assert_eq(actor.move_left, actor.move_max - 2)
	assert_eq(s.can_move(actor, Vector2i(9, 9)), "out of reach")
	assert_false(s.move(actor, Vector2i(9, 9)))
	actor.move_left = 0
	assert_eq(s.can_move(actor, actor.cell + Vector2i(1, 0)), "no movement left")
	assert_eq(_types().count("move"), 1)


func test_can_use_reasons() -> void:
	var p := _c("p", "party", Vector2i(0, 0), 10, ["strike", "shoot"])
	var ally := _c("a", "party", Vector2i(0, 1))
	var near := _c("n", "enemy", Vector2i(1, 0))
	var far := _c("f", "enemy", Vector2i(4, 0))
	var hidden := _c("h", "enemy", Vector2i(4, 2))
	var rules := _rules()
	rules.initiative_die = 1
	var s := _state(["P....", "...#.", "...#."], [p, ally, near, far, hidden], 1, rules)
	s.start("party")
	assert_true(s.current() == p or s.current() == ally)
	if s.current() != p:
		s.end_turn()
	assert_eq(s.current(), p)
	assert_eq(s.can_use(near, "strike", p.cell), "not your turn")
	assert_eq(s.can_use(p, "nope", near.cell), "unknown ability")
	assert_eq(s.can_use(p, "strike", Vector2i(3, 0)), "no target")
	assert_eq(s.can_use(p, "strike", p.cell), "cannot target self")
	assert_eq(s.can_use(p, "strike", far.cell), "out of range")
	assert_eq(s.can_use(p, "shoot", far.cell), "")
	assert_eq(s.can_use(p, "shoot", hidden.cell), "no line of sight")
	assert_eq(s.can_use(p, "strike", near.cell), "")
	assert_eq(s.can_use(p, "strike", ally.cell), "", "friendly fire is on by default")
	p.ap = 0
	assert_eq(s.can_use(p, "strike", near.cell), "needs 1 AP")


func test_friendly_fire_can_be_disabled() -> void:
	var rules := _rules()
	rules.friendly_fire = false
	rules.initiative_die = 1
	var p := _c("p", "party", Vector2i(0, 0))
	var ally := _c("a", "party", Vector2i(1, 0))
	var s := _state(["P...."], [p, ally, _c("e", "enemy", Vector2i(4, 0))], 1, rules)
	s.start("party")
	if s.current() != p:
		s.end_turn()
	assert_eq(s.can_use(p, "strike", ally.cell), "friendly fire is off")


func test_sure_hit_deals_damage_spends_ap_and_kills() -> void:
	var rules := _rules()
	rules.initiative_die = 1
	var p := _c("p", "party", Vector2i(0, 0), 10, ["sure", "big"])
	var e := _c("e", "enemy", Vector2i(1, 0), 6)
	var s := _state(["P...."], [p, e], 3, rules)
	s.start("party")
	var r := s.use_ability(p, "sure", e.cell)
	assert_true(bool(r["hit"]))
	assert_eq(r["damage"], 4)
	assert_eq(e.hp, 2)
	assert_eq(p.ap, 3)
	assert_false(s.finished)
	var k := s.use_ability(p, "big", e.cell)
	assert_true(bool(k["killed"]))
	assert_eq(e.hp, 0)
	assert_false(e.is_active())
	assert_true(s.finished)
	assert_eq(s.result, "victory")
	assert_eq(p.ap, 1)
	assert_eq(s.use_ability(p, "sure", e.cell), {}, "nothing after the fight ends")
	assert_any_contains(s.history, "Sure Hit hits e for 4")
	assert_any_contains(s.history, "e dies")
	assert_any_contains(s.history, "Victory")


func test_story_protected_downs_party_members_and_defeat() -> void:
	var rules := _rules()
	rules.initiative_die = 1
	var e := _c("e", "enemy", Vector2i(1, 0), 10, ["big"])
	var p := _c("p", "party", Vector2i(0, 0), 5)
	var s := _state(["P...."], [p, e], 3, rules)
	s.start("enemy")
	var r := s.use_ability(e, "big", p.cell)
	assert_true(bool(r["downed"]))
	assert_false(bool(r["killed"]))
	assert_true(p.downed)
	assert_false(p.is_active())
	assert_eq(s.result, "defeat")
	assert_any_contains(s.history, "p is down")


func test_mortal_rules_kill_party_members() -> void:
	var rules := _rules()
	rules.initiative_die = 1
	rules.story_protected = false
	var e := _c("e", "enemy", Vector2i(1, 0), 10, ["big"])
	var p := _c("p", "party", Vector2i(0, 0), 5)
	var s := _state(["P...."], [p, e], 3, rules)
	s.start("enemy")
	var r := s.use_ability(e, "big", p.cell)
	assert_true(bool(r["killed"]))
	assert_false(p.downed)


func test_flanking_raises_hit_chance_and_damage() -> void:
	var rules := _rules()
	rules.max_hit_chance = 95
	rules.initiative_die = 1
	var p := _c("p", "party", Vector2i(0, 0), 10, ["sure"])
	var ally := _c("a", "party", Vector2i(2, 0))
	var e := _c("e", "enemy", Vector2i(1, 0), 20)
	var s := _state(["P...."], [p, ally, e], 5, rules)
	s.start("party")
	assert_true(s.is_flanked(e, p), "ally on the far side")
	assert_false(s.is_flanked(p, e), "nobody hostile beside p")
	var ability: Dictionary = ABILITIES["sure"]
	assert_eq(s.hit_chance(p, ability, e, false), 95, "clamped to max")
	e.evasion = 30
	assert_eq(s.hit_chance(p, ability, e, false), 70)
	assert_eq(s.hit_chance(p, ability, e, true), 85)
	e.evasion = 0
	if s.current() != p:
		s.end_turn()
	var r := s.use_ability(p, "sure", e.cell)
	assert_true(bool(r["flanked"]))
	if bool(r["hit"]):
		assert_eq(r["damage"], 5, "4 × 1.25")


func test_end_turn_skips_inactive_and_wraps_rounds() -> void:
	var a := _c("a", "party", Vector2i(0, 0))
	var b := _c("b", "enemy", Vector2i(2, 0))
	var c := _c("c", "enemy", Vector2i(4, 0))
	var s := _state(["P....."], [a, b, c], 11)
	s.start()
	var second := s.order[1]
	second.hp = 0
	s.end_turn()
	assert_eq(s.current(), s.order[2], "skipped the dead combatant")
	s.end_turn()
	assert_eq(s.current(), s.order[0])
	assert_eq(s.round_number, 2)


func test_move_path_reconstructs_route() -> void:
	var p := _c("p", "party", Vector2i(0, 0), 10, ["strike"], 6)
	var s := _state(["P#...", ".#...", "....."], [p, _c("e", "enemy", Vector2i(4, 0))])
	s.start()
	var path := s.move_path(p, Vector2i(2, 0))
	assert_true(path.size() >= 4, "goes around the wall: %s" % [path])
	assert_eq(path[path.size() - 1], Vector2i(2, 0))
	assert_eq(s.move_path(p, Vector2i(1, 0)), [], "wall is unreachable")
