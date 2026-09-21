## The content validator (S45, D-100): the base game is clean; the
## stranger's example mod (a race, a class, a companion, a map and more)
## validates clean and loads into a world; a broken fixture mod is reported
## problem by problem with the kind, id and mod named; the command line
## returns 0 for clean, 1 for problems, 2 for bad usage.
extends TestCase

const STRANGER := "res://examples/mods"
const BROKEN := "res://tests/fixtures/broken_mods"


func test_the_base_game_validates_clean() -> void:
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	var problems := ContentValidator.validate(r)
	assert_eq(problems, [], "base content problems:\n%s" % "\n".join(problems))
	assert_eq(r.load_errors, [])
	for kind: String in r.kinds():
		assert_true(ContentValidator.SCHEMAS.has(kind), "kind %s has a schema" % kind)
	r.free()


func test_the_strangers_mod_validates_clean_and_loads() -> void:
	var r := ContentRegistry.new()
	var roots: Array[String] = [STRANGER]
	r.load_from(ContentRegistry.BASE_ROOT, roots)
	assert_eq(r.load_errors, [])
	assert_eq(r.loaded_mods.size(), 1)
	assert_eq(String(r.loaded_mods[0]["id"]), "stranger")
	var problems := ContentValidator.validate(r, ["stranger"])
	assert_eq(problems, [], "stranger problems:\n%s" % "\n".join(problems))
	assert_eq(ContentValidator.validate(r), [], "and nothing in the base broke")
	for pair: Array in [["races", "ashwalker"], ["classes", "lamplighter"], ["subclasses", "lamp_warden"], ["abilities", "lamp_flare"], ["resources", "lamp_oil"], ["items", "tin_lamp"], ["companions", "tamsin"], ["dialogue", "tamsin_recruit"], ["quests", "tamsin_lamp"], ["maps", "lamp_room"]]:
		assert_true(r.has_entry(String(pair[0]), String(pair[1])), "%s/%s loaded" % pair)
		assert_eq(String(r.get_entry(String(pair[0]), String(pair[1]))["_source"]), "stranger")
	assert_eq(r.count("companions"), 7, "six plus Tamsin")
	r.free()
	# It plays: the world takes the mod's registry, the race is on the creator,
	# the map enters, Tamsin stands in it, talks, recruits, banters and walks.
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.ledger_path = "user://test_ledger_validator.json"
	w.saves_dir = "user://test_saves_validator"
	var own := ContentRegistry.new()
	own.load_from(ContentRegistry.BASE_ROOT, roots)
	w.registry = own # not a child: a ContentRegistry in the tree reloads itself from the default roots
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	w.combat.animate = false
	assert_true(w.registry.has_entry("companions", "tamsin"))
	assert_true(w.open_creator())
	assert_true(w.creator_state.races.has("ashwalker"), "the mod's race is on the creator")
	w.close_creator()
	assert_true(w.enter_map("lamp_room"))
	assert_true(w.npc_at(Vector2i(8, 3)) != null, "Tamsin stands in the lamp room")
	assert_true(w.talk_to("tamsin"))
	assert_eq(w.dialogue.node_id, "greet")
	assert_true(w.choose(0))
	assert_true(w.narrative.is_recruited("tamsin"))
	assert_eq(w.narrative.stage_of("tamsin_lamp"), "start")
	var tamsin := w.member_by_id("tamsin")
	assert_true(tamsin != null and tamsin.class_id == "lamplighter" and tamsin.race_id == "ashwalker")
	assert_eq(w.banter("enter_shard").size(), 1, "her banter fires")
	w.teleport_party(Vector2i(1, 3))
	assert_true(w.check_transitions())
	assert_eq(w.map_id, "bastion")
	(Engine.get_main_loop() as SceneTree).root.remove_child(w)
	w.free()
	own.free()
	if FileAccess.file_exists("user://test_ledger_validator.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_ledger_validator.json"))


func test_a_broken_mod_is_reported_problem_by_problem() -> void:
	var r := ContentRegistry.new()
	var roots: Array[String] = [BROKEN]
	r.load_from(ContentRegistry.BASE_ROOT, roots)
	var problems := ContentValidator.validate(r, ["broken"])
	var joined := "\n".join(problems)
	for needle: String in [
		"companions/ghost (broken): race points at races 'nope'",
		"companions/ghost (broken): quest points at quests 'missing_quest'",
		"companions/ghost (broken): dialogue.banter points at dialogue 'missing_banter'",
		"companions/ghost (broken): scene ghost_scene requires has an unknown key 'mood'",
		"companions/ghost (broken): scene ghost_scene is a romance scene but the companion is not romanceable",
		"dialogue/bad_talk (broken): start node 'nowhere' does not exist",
		"dialogue/bad_talk (broken): node greet borrows the voice of 'nobody'",
		"dialogue/bad_talk (broken): node greet -> 'missing' does not exist",
		"dialogue/bad_talk (broken): node greet effects has an unknown key 'explode'",
		"dialogue/bad_talk (broken): node greet effects.recruit points at companions 'nobody'",
		"dialogue/bad_talk (broken): node greet requires.race points at races 'elf'",
		"maps/hole (broken): biome points at biomes 'nowhere'",
		"maps/hole (broken): needs 4 spawn cells",
		"maps/hole (broken): enemies points at enemies 'dragon'",
		"maps/hole (broken): transition points at maps 'narnia'",
		"zzz_kind/thing (broken): unknown content kind 'zzz_kind'",
		"companions/Bad-Id (broken): id must be lowercase snake_case",
		"companions/Bad-Id (broken): name is empty",
	]:
		assert_true(joined.contains(needle), "expected a problem containing:\n  %s\nin:\n%s" % [needle, joined])
	assert_true(problems.size() >= 18, "%d problems" % problems.size())
	assert_eq(ContentValidator.validate(r, ["base"]).size(), 0, "the base is still clean beside it")
	r.free()


func test_the_command_line_reports_and_exits_by_result() -> void:
	var usage := ContentValidator.run_cli(PackedStringArray([]))
	assert_eq(int(usage["code"]), 2)
	assert_true(String(Array(usage["lines"])[0]).begins_with("usage:"))
	var clean := ContentValidator.run_cli(PackedStringArray(["--mods=%s" % STRANGER]))
	assert_eq(int(clean["code"]), 0, "\n".join(clean["lines"]))
	assert_true("\n".join(clean["lines"]).contains("loaded mod stranger 1.0.0"))
	assert_true("\n".join(clean["lines"]).contains("0 problems"))
	var one := ContentValidator.run_cli(PackedStringArray(["--mods=%s/stranger" % STRANGER]))
	assert_eq(int(one["code"]), 0, "a single mod folder works too:\n%s" % "\n".join(one["lines"]))
	var broken := ContentValidator.run_cli(PackedStringArray(["--mods=%s" % BROKEN]))
	assert_eq(int(broken["code"]), 1)
	assert_true("\n".join(broken["lines"]).contains("dialogue/bad_talk (broken)"))
	var nowhere := ContentValidator.run_cli(PackedStringArray(["--mods=res://tests/fixtures/no_such_dir"]))
	assert_true("\n".join(nowhere["lines"]).contains("no mod found"))
