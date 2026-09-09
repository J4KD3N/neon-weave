## Progression math: XP curve and cap, class growth and unlocks, subclass
## and talent gating, build effects, respec refunds. Pure, on fixtures.
extends TestCase

const RULES: Dictionary = {"level_cap": 6, "xp_curve": [0, 15, 40, 80, 130, 200], "subclass_level": 3, "talent_tiers_by_level": {"1": 1, "4": 2}}
const CLASS: Dictionary = {
	"id": "tester", "stats": {"hp": 10, "move": 5, "evasion": 0, "initiative": 0},
	"growth": {"hp": 2, "evasion": 1}, "unlocks": {"2": ["zap"], "5": ["boom"]},
	"subclasses": ["alpha", "beta"], "abilities": ["strike"],
}

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	# Fixture entries on top of the base content.
	registry.put("subclasses", "alpha", {"id": "alpha", "name": "Alpha", "class": "tester", "abilities": ["zap", "alpha_strike"], "stat_mods": {"hp": 3, "move": -1}, "damage_bonus": 1})
	registry.put("subclasses", "beta", {"id": "beta", "name": "Beta", "class": "tester", "abilities": [], "stat_mods": {}})
	registry.put("talents", "t1", {"id": "t1", "name": "Tough", "branch": "body", "tier": 1, "cost": {"aether": 2}, "effects": {"hp": 3}, "requires": []})
	registry.put("talents", "t2", {"id": "t2", "name": "Tougher", "branch": "body", "tier": 2, "cost": {"aether": 4}, "effects": {"hp": 4, "damage_bonus": 1}, "requires": ["t1"]})


func after_each() -> void:
	registry.free()


func test_level_from_xp_curve_and_cap() -> void:
	assert_eq(Progression.level_for_xp(0, RULES), 1)
	assert_eq(Progression.level_for_xp(14, RULES), 1)
	assert_eq(Progression.level_for_xp(15, RULES), 2)
	assert_eq(Progression.level_for_xp(79, RULES), 3)
	assert_eq(Progression.level_for_xp(80, RULES), 4)
	assert_eq(Progression.level_for_xp(200, RULES), 6)
	assert_eq(Progression.level_for_xp(9999, RULES), 6, "capped")
	assert_eq(Progression.level_for_xp(9999, {"level_cap": 3, "xp_curve": [0, 15, 40, 80]}), 3, "cap below the curve")
	assert_eq(Progression.xp_to_next(0, RULES), 15)
	assert_eq(Progression.xp_to_next(30, RULES), 10)
	assert_eq(Progression.xp_to_next(200, RULES), -1, "at the cap")
	assert_eq(Progression.level_for_xp(50, {}), 1, "no rules: everyone is level 1")


func test_growth_unlocks_and_tiers_follow_the_level() -> void:
	var l1 := Progression.build_effects(registry, CLASS, 1, {}, RULES)
	assert_eq(l1["stats"], {"hp": 0, "move": 0, "evasion": 0, "initiative": 0})
	assert_eq(l1["abilities"], [])
	assert_eq(l1["damage_bonus"], 0)
	var l5 := Progression.build_effects(registry, CLASS, 5, {}, RULES)
	assert_eq(l5["stats"]["hp"], 8, "2 per level after the first")
	assert_eq(l5["stats"]["evasion"], 4)
	assert_eq(l5["abilities"], ["zap", "boom"], "unlocks in level order")
	assert_eq(Progression.build_effects(registry, CLASS, 2, {}, RULES)["abilities"], ["zap"])
	assert_eq(Progression.talent_tier_at(1, RULES), 1)
	assert_eq(Progression.talent_tier_at(3, RULES), 1)
	assert_eq(Progression.talent_tier_at(4, RULES), 2)
	assert_eq(Progression.subclass_level(CLASS, RULES), 3)
	assert_eq(Progression.subclass_level({"subclass_level": 2}, RULES), 2, "class override")


func test_subclass_applies_only_at_its_level_and_only_for_its_class() -> void:
	var build := {"subclass": "alpha", "talents": []}
	var early := Progression.build_effects(registry, CLASS, 2, build, RULES)
	assert_eq(early["abilities"], ["zap"], "chosen but not yet active")
	assert_eq(early["damage_bonus"], 0)
	var live := Progression.build_effects(registry, CLASS, 3, build, RULES)
	assert_eq(live["abilities"], ["zap", "alpha_strike"], "no duplicate zap")
	assert_eq(live["stats"]["hp"], 4 + 3)
	assert_eq(live["stats"]["move"], -1)
	assert_eq(live["damage_bonus"], 1)
	var wrong := Progression.build_effects(registry, {"subclasses": ["beta"]}, 3, build, RULES)
	assert_eq(wrong["abilities"], [], "alpha is not a subclass of that class")


func test_subclass_choice_gating() -> void:
	assert_eq(Progression.can_choose_subclass(registry, CLASS, 2, {}, "alpha", RULES, false), "needs level 3")
	assert_eq(Progression.can_choose_subclass(registry, CLASS, 3, {}, "alpha", RULES, false), "")
	assert_eq(Progression.can_choose_subclass(registry, CLASS, 3, {}, "gamma", RULES, false), "not a subclass of this class")
	assert_eq(Progression.can_choose_subclass(registry, CLASS, 3, {"subclass": "alpha"}, "alpha", RULES, false), "already chosen")
	assert_eq(Progression.can_choose_subclass(registry, CLASS, 3, {"subclass": "alpha"}, "beta", RULES, false), "needs the Arcanum to change")
	assert_eq(Progression.can_choose_subclass(registry, CLASS, 3, {"subclass": "alpha"}, "beta", RULES, true), "")


func test_talent_gating_effects_and_refund() -> void:
	assert_eq(Progression.can_buy_talent(registry, 1, {}, "t1", RULES, 1), "needs 2 Aether")
	assert_eq(Progression.can_buy_talent(registry, 1, {}, "t1", RULES, 2), "")
	assert_eq(Progression.can_buy_talent(registry, 1, {"talents": ["t1"]}, "t1", RULES, 9), "already learned")
	assert_eq(Progression.can_buy_talent(registry, 3, {"talents": ["t1"]}, "t2", RULES, 9), "tier 2 opens later")
	assert_eq(Progression.can_buy_talent(registry, 4, {"talents": []}, "t2", RULES, 9), "needs Tough")
	assert_eq(Progression.can_buy_talent(registry, 4, {"talents": ["t1"]}, "t2", RULES, 9), "")
	assert_eq(Progression.can_buy_talent(registry, 4, {}, "nope", RULES, 9), "unknown talent")
	var fx := Progression.build_effects(registry, CLASS, 4, {"talents": ["t1", "t2"]}, RULES)
	assert_eq(fx["stats"]["hp"], 6 + 3 + 4)
	assert_eq(fx["damage_bonus"], 1)
	assert_eq(Progression.refund_for(registry, {"talents": ["t1", "t2"]}, 0.5), 3)
	assert_eq(Progression.refund_for(registry, {"talents": ["t1", "t2"]}, 1.0), 6)
	assert_eq(Progression.refund_for(registry, {"talents": []}, 1.0), 0)
	assert_eq(Progression.refund_for(registry, {"talents": ["t1"]}, 2.0), 2, "refund clamps to 100%")


func test_base_content_subclasses_and_talents_resolve() -> void:
	var prules: Dictionary = registry.get_entry("rules", "progression")
	assert_eq(int(prules["level_cap"]), 12)
	for cls: Dictionary in registry.get_all("classes"):
		var subs: Array = cls.get("subclasses", [])
		assert_eq(subs.size(), 2, "class %s has two subclasses" % cls["id"])
		for sub_id: String in subs:
			var sub := registry.get_entry("subclasses", sub_id)
			assert_false(sub.is_empty(), "subclass %s exists" % sub_id)
			assert_eq(sub.get("class", ""), cls["id"], "subclass %s belongs to %s" % [sub_id, cls["id"]])
			for a: String in sub.get("abilities", []):
				assert_true(registry.has_entry("abilities", a), "subclass %s ability %s" % [sub_id, a])
			var fx := Progression.build_effects(registry, cls, 3, {"subclass": sub_id}, prules)
			assert_true(Array(fx["abilities"]).size() >= 1, "subclass %s grants an ability at level 3" % sub_id)
		for key: String in cls.get("growth", {}):
			assert_true(Progression.STAT_KEYS.has(key), "class %s growth key %s" % [cls["id"], key])
	for t: Dictionary in registry.get_all("talents"):
		assert_true(registry.has_entry("branches", String(t.get("branch", ""))), "talent %s branch" % t["id"])
		assert_true(int(Dictionary(t.get("cost", {})).get("aether", 0)) > 0, "talent %s costs Aether" % t["id"])
		for req: String in t.get("requires", []):
			assert_true(registry.has_entry("talents", req), "talent %s requires %s" % [t["id"], req])
		for key: String in t.get("effects", {}):
			assert_true(Progression.STAT_KEYS.has(key) or key == "damage_bonus", "talent %s effect %s" % [t["id"], key])



# --- S31: level 12, multiclassing, capstones (D-086) ---------------------------

const RULES12: Dictionary = {"level_cap": 12, "xp_curve": [0, 15, 40, 80, 130, 200, 290, 400, 530, 680, 850, 1050], "subclass_level": 3, "multiclass_level": 5, "capstone_level": 8, "talent_tiers_by_level": {"1": 1, "4": 2, "7": 3, "10": 4}}
const MAIN: Dictionary = {"id": "main", "stats": {"hp": 10, "move": 5, "evasion": 0, "initiative": 0}, "growth": {"hp": 2}, "unlocks": {"6": ["big"]}, "subclasses": ["alpha"], "abilities": ["strike", "poke"], "capstone": "main_cap"}


func _second() -> void:
	registry.put("classes", "tester", CLASS)
	registry.put("classes", "second", {"id": "second", "name": "Second", "stats": {"hp": 8, "move": 6, "evasion": 5, "initiative": 1}, "growth": {"evasion": 1}, "unlocks": {"3": ["second_three"]}, "subclasses": [], "abilities": ["strike", "jab"], "capstone": "second_cap"})


func test_the_full_curve_reaches_twelve_and_opens_four_tiers() -> void:
	assert_eq(Progression.level_for_xp(1050, RULES12), 12)
	assert_eq(Progression.level_for_xp(1049, RULES12), 11)
	assert_eq(Progression.xp_to_next(1050, RULES12), -1)
	assert_eq(Progression.talent_tier_at(7, RULES12), 3)
	assert_eq(Progression.talent_tier_at(10, RULES12), 4)
	assert_eq(Progression.multiclass_level(RULES12), 5)
	assert_eq(Progression.capstone_level(RULES12), 8)
	var live := registry.get_entry("rules", "progression")
	assert_eq(int(live["level_cap"]), 12, "the shipped rules reach 12")
	assert_eq(Array(live["xp_curve"]).size(), 12)


func test_levels_split_between_the_classes_and_never_past_the_gate() -> void:
	assert_eq(Progression.class_levels(4, {}, RULES12), {"main": 4, "second": 0, "class": ""})
	var mc := {"multiclass": {"class": "second", "levels": 3}}
	assert_eq(Progression.class_levels(4, mc, RULES12)["second"], 0, "nothing moves before level 5")
	assert_eq(Progression.class_levels(6, mc, RULES12), {"main": 5, "second": 1, "class": "second"}, "only the levels past the gate")
	assert_eq(Progression.class_levels(12, mc, RULES12), {"main": 9, "second": 3, "class": "second"})
	assert_eq(Progression.can_add_multiclass_level(12, mc, RULES12), "")
	assert_eq(Progression.can_add_multiclass_level(8, mc, RULES12), "every level past 5 is already placed")
	assert_eq(Progression.can_add_multiclass_level(8, {}, RULES12), "no second class yet")


func test_multiclass_gating_and_effects() -> void:
	_second()
	assert_eq(Progression.can_multiclass(registry, MAIN, 4, {}, "second", RULES12, false), "needs level 5")
	assert_eq(Progression.can_multiclass(registry, MAIN, 5, {}, "main", RULES12, false), "that is the main class")
	assert_eq(Progression.can_multiclass(registry, MAIN, 5, {}, "nope", RULES12, false), "unknown class")
	assert_eq(Progression.can_multiclass(registry, MAIN, 5, {}, "second", RULES12, false), "")
	var taken := {"multiclass": {"class": "second", "levels": 0}}
	assert_eq(Progression.can_multiclass(registry, MAIN, 6, taken, "second", RULES12, false), "already chosen")
	assert_eq(Progression.can_multiclass(registry, MAIN, 6, taken, "tester", RULES12, false), "needs the Arcanum to change")
	assert_eq(Progression.can_multiclass(registry, MAIN, 6, taken, "tester", RULES12, true), "")
	# Effects: the second class brings its abilities (not strike), its growth per level there, its unlocks at its own level.
	var fx := Progression.build_effects(registry, MAIN, 8, {"multiclass": {"class": "second", "levels": 3}}, RULES12)
	assert_eq(fx["stats"]["hp"], 2 * 4, "main has 5 levels: growth for four")
	assert_eq(fx["stats"]["evasion"], 3, "three levels of the second class")
	assert_true(Array(fx["abilities"]).has("jab"), "second class abilities: %s" % [fx["abilities"]])
	assert_true(Array(fx["abilities"]).has("second_three"), "its level-3 unlock at three levels there")
	assert_false(Array(fx["abilities"]).has("big"), "main is 5, its level-6 unlock is not there")
	assert_false(Array(fx["abilities"]).has("main_cap"))
	var pure := Progression.build_effects(registry, MAIN, 8, {}, RULES12)
	assert_true(Array(pure["abilities"]).has("main_cap"), "eight levels in one class: the capstone")
	assert_true(Array(pure["abilities"]).has("big"))
	var deep := Progression.build_effects(registry, MAIN, 12, {"multiclass": {"class": "second", "levels": 4}}, RULES12)
	assert_true(Array(deep["abilities"]).has("main_cap"), "8 main levels of 12 still reach the capstone")
	assert_false(Array(deep["abilities"]).has("second_cap"), "four second levels do not")
	var split := Progression.build_effects(registry, MAIN, 12, {"multiclass": {"class": "second", "levels": 7}}, RULES12)
	assert_false(Array(split["abilities"]).has("main_cap"), "5 main levels: no capstone")
