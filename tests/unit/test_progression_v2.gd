## Progression v2 (S66, D-122): a subclass and a resource loop for the
## second class of a multiclass, a preview of the next level before it is
## bought, talents that change what abilities do, a line for every capstone.
extends TestCase

const RULES: Dictionary = {"level_cap": 12, "xp_curve": [0, 15, 40, 80, 130, 200, 290, 400, 530, 680, 850, 1050], "subclass_level": 3, "multiclass_level": 5, "capstone_level": 8, "talent_tiers_by_level": {"1": 1, "4": 2, "7": 3, "10": 4}}
const MAIN: Dictionary = {"id": "main", "name": "Main", "resource": {"id": "vent_heat", "name": "Vent Heat"}, "stats": {"hp": 10, "move": 5, "evasion": 0, "initiative": 0}, "growth": {"hp": 2}, "unlocks": {"5": ["boom"]}, "subclasses": ["alpha"], "abilities": ["strike", "poke"], "capstone": "main_cap", "capstone_line": "The main line."}
const SECOND: Dictionary = {"id": "second", "name": "Second", "resource": {"id": "surge", "name": "Surge"}, "stats": {"hp": 8, "move": 6, "evasion": 5, "initiative": 1}, "growth": {"evasion": 1}, "unlocks": {"3": ["second_three"]}, "subclasses": ["sigma"], "abilities": ["strike", "jab"], "capstone": "second_cap"}

const LEDGER := "user://test_ledger_prog2.json"
const SAVES := "user://test_saves_prog2"

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	registry.put("classes", "main", MAIN)
	registry.put("classes", "second", SECOND)
	registry.put("subclasses", "alpha", {"id": "alpha", "name": "Alpha", "class": "main", "abilities": ["alpha_strike"], "stat_mods": {"hp": 3}})
	registry.put("subclasses", "sigma", {"id": "sigma", "name": "Sigma", "class": "second", "abilities": ["sigma_strike"], "stat_mods": {"evasion": 2}, "damage_bonus": 1})
	registry.put("talents", "t_reach", {"id": "t_reach", "name": "Reach", "branch": "arcane", "tier": 1, "cost": {"aether": 2}, "effects": {"hp": 1, "traits": {"ability_range_bonus": {"poke": 2}, "ap_bonus": 1}}})
	registry.put("talents", "t_more", {"id": "t_more", "name": "More", "branch": "arcane", "tier": 1, "cost": {"aether": 2}, "effects": {"traits": {"ability_range_bonus": {"poke": 1}, "resist": {"arcane": 0.5}}}})


func after_each() -> void:
	registry.free()
	_cleanup()


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


func test_the_second_class_has_its_own_subclass_once_it_holds_the_levels() -> void:
	var two := {"multiclass": {"class": "second", "levels": 2, "subclass": "sigma"}}
	var fx2 := Progression.build_effects(registry, MAIN, 8, two, RULES)
	assert_false(Array(fx2["abilities"]).has("sigma_strike"), "two levels there: the subclass waits")
	var three := {"multiclass": {"class": "second", "levels": 3, "subclass": "sigma"}}
	var fx3 := Progression.build_effects(registry, MAIN, 8, three, RULES)
	assert_true(Array(fx3["abilities"]).has("sigma_strike"), "three levels there: its ability: %s" % [fx3["abilities"]])
	assert_eq(int(fx3["stats"]["evasion"]), 3 + 2, "growth for three plus the subclass")
	assert_eq(int(fx3["damage_bonus"]), 1)
	assert_true(Array(fx3["abilities"]).has("second_three"), "the second class's own unlock too")
	# The gate messages.
	assert_eq(Progression.can_choose_second_subclass(registry, 8, {}, "sigma", RULES, false), "no second class yet")
	assert_eq(Progression.can_choose_second_subclass(registry, 8, two, "alpha", RULES, false), "not a subclass of the second class")
	assert_eq(Progression.can_choose_second_subclass(registry, 8, {"multiclass": {"class": "second", "levels": 2}}, "sigma", RULES, false), "needs 3 levels there")
	assert_eq(Progression.can_choose_second_subclass(registry, 8, {"multiclass": {"class": "second", "levels": 3}}, "sigma", RULES, false), "")
	assert_eq(Progression.can_choose_second_subclass(registry, 8, three, "sigma", RULES, false), "already chosen")
	var other := {"multiclass": {"class": "second", "levels": 3, "subclass": "sigma"}}
	registry.put("subclasses", "tau", {"id": "tau", "name": "Tau", "class": "second", "abilities": []})
	var second_two: Dictionary = SECOND.duplicate(true)
	second_two["subclasses"] = ["sigma", "tau"]
	registry.put("classes", "second", second_two)
	assert_eq(Progression.can_choose_second_subclass(registry, 8, other, "tau", RULES, false), "needs the Arcanum to change")
	assert_eq(Progression.can_choose_second_subclass(registry, 8, other, "tau", RULES, true), "")


func test_the_resource_loop_follows_the_class_with_more_levels() -> void:
	assert_eq(String(Progression.resource_class(registry, MAIN, 8, {}, RULES)["id"]), "main", "no second class: the main loop")
	assert_eq(String(Progression.resource_class(registry, MAIN, 8, {"multiclass": {"class": "second", "levels": 3}}, RULES)["id"]), "main", "5 main, 3 second")
	assert_eq(String(Progression.resource_class(registry, MAIN, 12, {"multiclass": {"class": "second", "levels": 6}}, RULES)["id"]), "second", "6 and 6: the second class's loop")
	assert_eq(String(Progression.resource_class(registry, MAIN, 12, {"multiclass": {"class": "second", "levels": 7}}, RULES)["id"]), "second")
	var no_loop: Dictionary = SECOND.duplicate(true)
	no_loop.erase("resource")
	registry.put("classes", "second", no_loop)
	assert_eq(String(Progression.resource_class(registry, MAIN, 12, {"multiclass": {"class": "second", "levels": 7}}, RULES)["id"]), "main", "a class with no loop leaves the main's")


func test_the_next_level_is_previewed_before_it_is_bought() -> void:
	var p4 := Progression.preview(registry, MAIN, 4, {}, RULES)
	assert_eq(int(p4["level"]), 5)
	assert_eq(p4["stats"], {"hp": 2}, "growth for one more level")
	assert_eq(p4["abilities"], ["boom"], "the level-5 unlock")
	assert_eq(int(p4["talent_tier"]), 0, "tier 2 opened at 4")
	assert_false(bool(p4["subclass_opens"]))
	assert_eq(String(p4["capstone"]), "")
	var p3 := Progression.preview(registry, MAIN, 3, {}, RULES)
	assert_eq(int(p3["talent_tier"]), 2, "level 4 opens tier 2")
	assert_true(bool(Progression.preview(registry, MAIN, 2, {}, RULES)["subclass_opens"]), "level 3 opens the subclass")
	var p7 := Progression.preview(registry, MAIN, 7, {}, RULES)
	assert_eq(String(p7["capstone"]), "main_cap", "level 8 in one class: the capstone")
	assert_eq(int(Progression.preview(registry, MAIN, 12, {}, RULES)["level"]), -1, "at the cap")
	var split := Progression.preview(registry, MAIN, 7, {"multiclass": {"class": "second", "levels": 2}}, RULES)
	assert_eq(String(split["capstone"]), "", "the level goes to the main class, which stays under 8 with two levels away")
	assert_eq(split["stats"], {"hp": 2})


func test_talents_carry_traits_the_fight_reads() -> void:
	var fx := Progression.build_effects(registry, MAIN, 4, {"talents": ["t_reach", "t_more"]}, RULES)
	assert_eq(int(fx["stats"]["hp"]), 6 + 1, "growth for three plus the flat talent")
	var traits: Dictionary = fx["traits"]
	assert_eq(int(Dictionary(traits["ability_range_bonus"])["poke"]), 3, "two talents on one ability add up")
	assert_eq(int(traits["ap_bonus"]), 1)
	assert_eq(float(Dictionary(traits["resist"])["arcane"]), 0.5)
	assert_true(Progression.TALENT_TRAIT_KEYS.has("ability_cooldown_bonus"))
	# The shipped talents that use them, and the validator's refusals.
	for id: String in ["long_arc", "cold_barrel", "sure_hand", "second_wind"]:
		assert_true(registry.has_entry("talents", id), "%s ships" % id)
	for problem: String in ContentValidator.validate(registry, ["runtime"]):
		assert_false(problem.begins_with("talents/") and not problem.begins_with("talents/t_"), "the shipped talents are clean (the fixtures name a fixture ability): %s" % problem)
	registry.put("talents", "zz_bad", {"name": "Bad", "branch": "body", "tier": 1, "cost": {"aether": 1}, "effects": {"luck": 3, "traits": {"wings": true, "ability_range_bonus": {"nope": 1}}}})
	var problems := ContentValidator.validate(registry, ["runtime"])
	assert_any_contains(problems, "effects.luck is not a stat, damage_bonus or traits")
	assert_any_contains(problems, "effects.traits.wings is not a trait a talent may carry")
	assert_any_contains(problems, "effects.traits.ability_range_bonus points at abilities 'nope', which does not exist")
	assert_true(Loc.TEXT_FIELDS["classes"].has("capstone_line"), "translators see the capstone lines")
	for cls: Dictionary in registry.get_all("classes"):
		if cls.has("capstone") and String(cls["id"]) != "main" and String(cls["id"]) != "second":
			assert_false(String(cls.get("capstone_line", "")).is_empty(), "%s has a capstone line" % cls["id"])


func test_the_weave_shows_the_loop_and_the_next_level_and_the_second_subclass_and_the_capstone_line() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.map_id = "proto_yard"
	w.home_map = "proto_yard"
	w.party_id = "prototype"
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.settings_path = "user://test_settings_prog2.json"
	w.input_path = "user://test_input_prog2.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	w.combat.animate = false
	assert_contains(w.preview_line("weaver"), "Next level 2:")
	assert_contains(w.preview_line("weaver"), "+2 HP")
	assert_contains(w.loop_line("weaver"), "loop: Vent Heat (Scrap-Knight)")
	w.ledger.xp = 40 # level 3
	w.refresh_progression()
	assert_contains(w.preview_line("weaver"), "Next level 4: +2 HP · talent tier 2")
	w.ledger.xp = 200 # level 6
	w.refresh_progression()
	assert_eq(w.choose_multiclass("weaver", "aetherbinder"), "")
	assert_eq(w.add_multiclass_level("weaver"), "")
	assert_eq(w.choose_subclass("weaver", "stormcaller"), "needs 3 levels there", "one level in the second class")
	w.ledger.xp = 400 # level 8
	w.refresh_progression()
	assert_eq(w.add_multiclass_level("weaver"), "")
	assert_eq(w.add_multiclass_level("weaver"), "")
	assert_eq(w.class_levels_text("weaver"), "Scrap-Knight 5 / Aetherbinder 3")
	assert_eq(w.choose_subclass("weaver", "stormcaller"), "", "three levels there: the second class's subclass")
	var weaver := w.member_by_id("weaver")
	assert_true(weaver.abilities.has("storm_lance"), "its ability: %s" % [weaver.abilities])
	assert_eq(String(Dictionary(w.build_for("weaver")["multiclass"])["subclass"]), "stormcaller", "kept in the build")
	assert_eq(w.choose_subclass("weaver", "wardweaver"), "needs the Arcanum to change")
	var labels: PackedStringArray = []
	for row: Dictionary in w.weave_rows("weaver"):
		labels.append(String(row["label"]))
	assert_true(labels.has("✓ Aetherbinder subclass: Stormcaller — " + String(w.registry.get_entry("subclasses", "stormcaller")["summary"])), "%s" % [labels])
	assert_eq(weaver.resource_id, "vent_heat", "5 main levels, 3 second: the main loop")
	w.ledger.xp = 1050 # level 12
	w.refresh_progression()
	for _i: int in 3:
		assert_eq(w.add_multiclass_level("weaver"), "")
	assert_eq(w.class_levels_text("weaver"), "Scrap-Knight 6 / Aetherbinder 6")
	assert_eq(w.member_by_id("weaver").resource_id, "surge", "level for level: the second class's loop")
	assert_contains(w.loop_line("weaver"), "loop: Surge (Aetherbinder)")
	assert_contains(w.preview_line("weaver"), "At the cap")
	assert_eq(w.save_slot(1), OK)
	assert_eq(w.load_slot(1), [])
	assert_eq(w.member_by_id("weaver").resource_id, "surge", "and it survives a save")
	assert_true(w.member_by_id("weaver").abilities.has("storm_lance"))
	# The capstone line, when the eighth level lands in one class.
	w.ledger.builds["weaver"]["multiclass"]["levels"] = 4
	w.refresh_progression()
	assert_true(w.member_by_id("weaver").abilities.has("line_breaker"))
	var seen := false
	for entry: Dictionary in w.narrative.log:
		if String(entry.get("text", "")).begins_with("Line Breaker:"):
			seen = true
	assert_true(seen, "the capstone line is in the history")
	# A talent's traits reach the fight: Long Arc on Ash, Second Wind on the Weaver.
	w.ledger.bank({"aether": 40})
	assert_eq(w.buy_talent("ash", "weft_sense"), "")
	assert_eq(w.buy_talent("ash", "long_arc"), "")
	assert_eq(w.buy_talent("weaver", "iron_skin"), "")
	assert_eq(w.buy_talent("weaver", "plated_bones"), "")
	assert_eq(w.buy_talent("weaver", "iron_will"), "")
	assert_eq(w.buy_talent("weaver", "second_wind"), "")
	assert_eq(int(Dictionary(w.member_by_id("ash").traits.get("ability_range_bonus", {})).get("arc_bolt", 0)), 1)
	w.rules.initiative_die = 1
	w.teleport_party(Vector2i(13, 4))
	w.start_combat(true)
	var s := w.combat.state
	var ash := s.by_id("p:ash")
	var wv := s.by_id("p:weaver")
	assert_eq(wv.ap_max, w.rules.ap_per_turn + 1, "Second Wind: one more AP a turn")
	var foe := s.active("enemy")[0]
	ash.cell = Vector2i(2, 2)
	foe.cell = Vector2i(8, 2)
	if s.current() != ash:
		s.switch_to(ash.id)
	assert_true(s.can_use(ash, "arc_bolt", foe.cell) != "out of range", "six cells: Long Arc reaches: %s" % s.can_use(ash, "arc_bolt", foe.cell))
	foe.cell = Vector2i(9, 2)
	assert_eq(s.can_use(ash, "arc_bolt", foe.cell), "out of range", "seven is one too many")
	(Engine.get_main_loop() as SceneTree).root.remove_child(w)
	w.free()
