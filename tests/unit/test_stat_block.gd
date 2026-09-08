extends TestCase

var rules := CombatRules.new()


func test_class_stats_plus_race_mods() -> void:
	var s := StatBlock.for_member(
		{"stats": {"hp": 20, "move": 5, "evasion": 5, "initiative": 0}},
		{"stat_mods": {"hp": 2, "initiative": 1}},
		rules)
	assert_eq(s, {"hp": 22, "move": 5, "evasion": 5, "initiative": 1})


func test_defaults_when_missing() -> void:
	var s := StatBlock.for_member({}, {}, rules)
	assert_eq(s["hp"], 10)
	assert_eq(s["move"], rules.base_move)
	assert_eq(s["evasion"], 0)


func test_hp_and_move_never_drop_below_one() -> void:
	var s := StatBlock.for_member({"stats": {"hp": 2, "move": 1}}, {"stat_mods": {"hp": -5, "move": -3}}, rules)
	assert_eq(s["hp"], 1)
	assert_eq(s["move"], 1)


func test_enemy_stats() -> void:
	var s := StatBlock.for_enemy({"stats": {"hp": 8, "evasion": 5, "initiative": 3}}, rules)
	assert_eq(s, {"hp": 8, "move": rules.base_move, "evasion": 5, "initiative": 3})


func test_rules_from_entry_override_defaults() -> void:
	var r := CombatRules.from_entry({"ap_per_turn": 3, "friendly_fire": false, "engage_radius": 4})
	assert_eq(r.ap_per_turn, 3)
	assert_false(r.friendly_fire)
	assert_eq(r.engage_radius, 4)
	assert_eq(r.base_move, 6, "untouched default")
