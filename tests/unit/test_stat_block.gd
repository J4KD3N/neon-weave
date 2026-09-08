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
	assert_eq(s, {"hp": 8, "move": rules.base_move, "evasion": 5, "initiative": 3, "damage_bonus": 0, "ap_bonus": 0, "tier": ""})


func test_enemy_tiers_and_depth_scale_stats() -> void:
	var entry := {"stats": {"hp": 10, "move": 5, "evasion": 0, "initiative": 0}}
	var elite := StatBlock.for_enemy(entry, rules, 1, "elite")
	assert_eq(elite["hp"], 15)
	assert_eq(elite["damage_bonus"], rules.elite_damage_bonus)
	assert_eq(elite["tier"], "elite")
	var boss := StatBlock.for_enemy({"stats": {"hp": 10}, "tier": "boss"}, rules)
	assert_eq(boss["hp"], 30, "the entry tier applies when the placement has none")
	assert_eq(boss["damage_bonus"], rules.boss_damage_bonus)
	assert_eq(boss["ap_bonus"], rules.boss_ap_bonus)
	var deep := StatBlock.for_enemy(entry, rules, 3)
	assert_eq(deep["hp"], 13, "10 x (1 + 0.15 x 2) = 13")
	assert_eq(deep["damage_bonus"], 1, "+1 damage every 2 depths past 1")
	assert_eq(deep["tier"], "")
	var deep_elite := StatBlock.for_enemy(entry, rules, 5, "elite")
	assert_eq(deep_elite["hp"], 24, "15 x 1.6")
	assert_eq(deep_elite["damage_bonus"], 3, "elite 1 + depth 2")
	assert_eq(StatBlock.for_enemy(entry, rules, 0)["hp"], 10, "depth below 1 is depth 1")


func test_rules_from_entry_override_defaults() -> void:
	var r := CombatRules.from_entry({"ap_per_turn": 3, "friendly_fire": false, "engage_radius": 4})
	assert_eq(r.ap_per_turn, 3)
	assert_false(r.friendly_fire)
	assert_eq(r.engage_radius, 4)
	assert_eq(r.base_move, 6, "untouched default")
