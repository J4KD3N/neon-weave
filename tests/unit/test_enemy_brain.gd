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
