## Turn groups (consecutive allies act in any order), lazy turn starts, and
## the attack preview the HUD shows on hover.
extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [2, 4], "accuracy": 85},
	"sure": {"id": "sure", "name": "Sure Hit", "ap": 1, "range": 1, "damage": [4, 4], "accuracy": 100},
	"big": {"id": "big", "name": "Big", "ap": 2, "range": 1, "damage": [20, 20], "accuracy": 100},
	"shoot": {"id": "shoot", "name": "Shoot", "ap": 1, "range": 5, "damage": [1, 3], "accuracy": 75, "requires_los": true},
}

var events: Array[Dictionary] = []


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "g", "legend": {".": "floor", "#": "wall"}, "rows": rows}, TILES)


## Every combatant rolls 1, so the order is by id: a, b (party) then x, y (enemy).
static func _rules() -> CombatRules:
	var r := CombatRules.new()
	r.max_hit_chance = 100
	r.min_hit_chance = 0
	r.initiative_die = 1
	return r


static func _c(id: String, team: String, cell: Vector2i, hp: int = 10, abilities: Array[String] = ["strike", "sure", "big"]) -> Combatant:
	return Combatant.make(id, id, team, cell, {"hp": hp, "move": 6, "evasion": 0, "initiative": 0}, abilities, 4)


func _state(combatants: Array[Combatant]) -> CombatState:
	var s := CombatState.new()
	s.setup(_map(["........", "........"]), _rules(), ABILITIES, combatants, 1)
	events.clear()
	s.event.connect(func(e: Dictionary) -> void: events.append(e))
	s.start()
	return s


func _four() -> Array[Combatant]:
	return [_c("a", "party", Vector2i(0, 0)), _c("b", "party", Vector2i(1, 0)), _c("x", "enemy", Vector2i(2, 0)), _c("y", "enemy", Vector2i(6, 1))]


func _count(type: String) -> int:
	var n := 0
	for e: Dictionary in events:
		if String(e["type"]) == type:
			n += 1
	return n


func test_consecutive_allies_form_a_group_and_swap_freely() -> void:
	var s := _state(_four())
	assert_eq(CombatState._ids(s.order), PackedStringArray(["a", "b", "x", "y"]))
	assert_eq(s.current().id, "a")
	assert_eq(CombatState._ids(s.group), PackedStringArray(["a", "b"]))
	assert_eq(CombatState._ids(s.switchable()), PackedStringArray(["b"]))
	assert_eq(_count("turn_begin"), 1, "b has not started its turn yet")
	var a := s.by_id("a")
	var b := s.by_id("b")
	a.ap = 2
	assert_eq(s.switch_to("b"), "")
	assert_eq(s.current(), b)
	assert_eq(b.ap, 4, "b begins its turn on first control")
	assert_eq(_count("turn_begin"), 2)
	assert_eq(_count("switch"), 1)
	assert_eq(s.can_use(b, "sure", Vector2i(2, 0)), "", "b may act now")
	assert_eq(s.can_use(a, "sure", Vector2i(2, 0)), "not your turn")
	assert_eq(s.switch_to("a"), "", "back again while a still has its turn")
	assert_eq(a.ap, 2, "a keeps what it spent")
	assert_eq(_count("turn_begin"), 2, "no second turn start for a")
	s.end_turn()
	assert_true(s.has_acted(a))
	assert_eq(s.current(), b, "the group is not done until everyone acted")
	assert_eq(s.switchable(), [])
	s.end_turn()
	assert_eq(s.current().id, "x", "then the enemies")
	assert_eq(CombatState._ids(s.group), PackedStringArray(["x", "y"]))
	s.end_turn()
	assert_eq(s.current().id, "y")
	assert_eq(s.round_number, 1)
	s.end_turn()
	assert_eq(s.round_number, 2)
	assert_eq(s.current(), a)
	assert_eq(a.ap, 4, "round 2 restores AP")
	assert_false(s.has_acted(a))
	assert_eq(CombatState._ids(s.switchable()), PackedStringArray(["b"]))


func test_switch_refusals() -> void:
	var s := _state(_four())
	assert_eq(s.switch_to("x"), "not in this turn group")
	assert_eq(s.switch_to("nobody"), "not in this turn group")
	assert_eq(s.switch_to("a"), "", "switching to yourself is a no-op")
	assert_eq(_count("switch"), 0)
	assert_eq(s.switch_to("b"), "")
	s.end_turn()
	assert_eq(s.current().id, "a")
	assert_eq(s.switch_to("b"), "already acted")
	var b := s.by_id("b")
	s.end_turn()
	s.end_turn()
	s.end_turn()
	assert_eq(s.round_number, 2)
	b.hp = 0
	assert_eq(s.switch_to("b"), "down")
	assert_eq(s.switchable(), [])
	s.end_turn()
	assert_eq(s.current().id, "x", "the downed member is skipped, not waited for")
	s.by_id("y").hp = 0
	s.end_turn()
	assert_eq(s.round_number, 3)
	var a := s.by_id("a")
	assert_eq(s.current(), a)
	var x := s.by_id("x")
	x.hp = 1
	a.cell = Vector2i(2, 1)
	assert_true(bool(s.use_ability(a, "sure", x.cell)["killed"]))
	assert_true(s.finished)
	assert_eq(s.switch_to("a"), "combat over")


func test_group_breaks_where_the_team_changes_and_wraps_rounds() -> void:
	var s := _state([_c("a", "party", Vector2i(0, 0)), _c("m", "enemy", Vector2i(3, 0)), _c("z", "party", Vector2i(1, 1))])
	assert_eq(CombatState._ids(s.order), PackedStringArray(["a", "m", "z"]))
	assert_eq(CombatState._ids(s.group), PackedStringArray(["a"]), "an enemy sits between the allies")
	assert_eq(s.switch_to("z"), "not in this turn group")
	s.end_turn()
	assert_eq(s.current().id, "m")
	s.end_turn()
	assert_eq(s.current().id, "z")
	assert_eq(CombatState._ids(s.group), PackedStringArray(["z"]), "groups never wrap across a round boundary")
	s.end_turn()
	assert_eq(s.round_number, 2)
	assert_eq(s.current().id, "a")


func test_preview_reports_chance_span_tags_and_refusals() -> void:
	var s := _state(_four())
	var a := s.by_id("a")
	var b := s.by_id("b")
	var x := s.by_id("x")
	assert_eq(s.switch_to("b"), "")
	var p := s.preview(b, "sure", x.cell)
	assert_eq(p["why"], "")
	assert_eq(p["chance"], 100)
	assert_eq(p["min"], 4)
	assert_eq(p["max"], 4)
	assert_false(bool(p["kills"]))
	assert_eq(p["tags"], PackedStringArray())
	var big := s.preview(b, "big", x.cell)
	assert_eq(big["min"], 20)
	assert_true(bool(big["kills"]))
	var strike := s.preview(b, "strike", x.cell)
	assert_eq(strike["chance"], 85)
	assert_eq(strike["min"], 2)
	assert_eq(strike["max"], 4)
	b.ap = 0
	var broke := s.preview(b, "sure", x.cell)
	assert_eq(broke["why"], "needs 1 AP")
	assert_eq(broke["chance"], 100, "numbers still shown when only AP is short")
	b.ap = 4
	var far := s.preview(b, "sure", s.by_id("y").cell)
	assert_eq(far["why"], "out of range")
	assert_eq(s.preview(b, "sure", Vector2i(5, 1))["why"], "no target")
	assert_eq(s.preview(b, "nope", x.cell)["why"], "unknown ability")
	assert_eq(s.preview(a, "sure", x.cell)["why"], "not your turn")
	# a stands next to x too, so x is flanked for b: +15 to hit (capped at 100) and x1.25 damage.
	a.cell = Vector2i(2, 1)
	var flank := s.preview(b, "strike", x.cell)
	assert_eq(flank["tags"], PackedStringArray(["flanked"]))
	assert_eq(flank["chance"], 100)
	assert_eq(flank["min"], 3)
	assert_eq(flank["max"], 5)
	var used := s.use_ability(b, "sure", x.cell)
	assert_eq(int(used["chance"]), 100, "the preview and the roll agree")
	assert_eq(int(used["damage"]), 5)


func test_preview_text() -> void:
	var s := _state(_four())
	var x := s.by_id("x")
	var b := s.by_id("b")
	s.switch_to("b")
	assert_eq(CombatController.describe_preview(s.preview(b, "sure", x.cell), x), "Sure Hit → x: 100% to hit, 4 damage")
	assert_eq(CombatController.describe_preview(s.preview(b, "strike", x.cell), x), "Strike → x: 85% to hit, 2–4 damage")
	assert_eq(CombatController.describe_preview(s.preview(b, "big", x.cell), x), "Big → x: 100% to hit, 20 damage · lethal")
	b.ap = 0
	assert_eq(CombatController.describe_preview(s.preview(b, "big", x.cell), x), "Big → x: 100% to hit, 20 damage · lethal · needs 2 AP")
	b.ap = 4
	assert_eq(CombatController.describe_preview(s.preview(b, "sure", s.by_id("y").cell), s.by_id("y")), "Sure Hit → y: 100% to hit, 4 damage · out of range")
	assert_eq(CombatController.describe_preview({"name": "Vent", "heal": 3}, x), "Vent: vent Heat, +3 HP")
	assert_eq(CombatController.describe_preview({"ability": "zap", "why": "no line of sight", "chance": 0}, x), "zap → x: no line of sight")


func test_tab_is_bound_to_next_member() -> void:
	InputActions.ensure()
	assert_true(InputMap.has_action("next_member"))
	var keys: Array = InputMap.action_get_events("next_member")
	assert_eq(keys.size(), 1)
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_TAB)
