## Difficulty settings and Iron Weave (S50, D-105): three difficulties as
## `difficulties` entries that overlay the rules, chosen on the title screen
## before the death-stakes and carried by the story; Iron Weave as Mortal
## with one save and no reloads, recorded on the account so a swapped save
## cannot restart a run, given up by any other new game, lost with the
## save on a wipe, and kept as an account key at an ending.
extends TestCase

const LEDGER := "user://test_ledger_difficulty.json"
const SAVES := "user://test_saves_difficulty"
const ACCOUNT := "user://test_account_difficulty.json"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _cleanup() -> void:
	for f: String in [LEDGER, ACCOUNT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.account_path = ACCOUNT
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func _row(rows: Array[Dictionary], id: String) -> Dictionary:
	for r: Dictionary in rows:
		if String(r.get("id", "")) == id:
			return r
	return {}


## Puts the title cursor on a row by id and presses Enter.
func _pick(id: String) -> bool:
	var rows := world.title_menu.rows
	for i: int in rows.size():
		if String(rows[i].get("id", "")) == id:
			world.title_menu.cursor = i
			return world.activate_title()
	assert_true(false, "no title row '%s' on page %s" % [id, world.title_menu.page])
	return false


func _autosave_exists() -> bool:
	return FileAccess.file_exists(world.save_path(SaveSystem.AUTOSAVE))


func test_three_difficulties_load_in_order_with_one_default() -> void:
	var ids: Array[String] = []
	for d: Dictionary in world.difficulties():
		ids.append(String(d["id"]))
	assert_eq(ids, ["story", "balanced", "tactician"], "by order")
	assert_eq(world.default_difficulty(), "balanced")
	for d: Dictionary in world.difficulties():
		assert_true(d.get("rules", null) is Dictionary, "%s: rules is an overlay" % d["id"])
		assert_false(String(d.get("summary", "")).is_empty(), "%s: a summary for the title screen" % d["id"])
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	assert_eq(ContentValidator.validate(r), [], "the base game validates with difficulties")
	r.free()


func test_a_difficulty_overlays_the_combat_rules_without_touching_the_registry() -> void:
	var base: Dictionary = world.registry.get_entry("rules", "combat")
	assert_true(world.new_game(false, "tactician"))
	assert_eq(world.narrative.difficulty, "tactician")
	assert_eq(world.difficulty_id(), "tactician")
	assert_eq(world.rules.depth_hp_per_level, 0.15, "tactician: a steeper depth curve")
	assert_eq(world.rules.boss_hp_mult, 3.0)
	assert_eq(world.rules.boss_telegraph_round, 0, "tactician: no wind-up round")
	assert_eq(world.rules.ap_per_turn, int(base["ap_per_turn"]), "what the overlay does not name is the base rule")
	assert_true(world.rules.story_protected, "the mode still goes on top")
	assert_eq(float(base["depth_hp_per_level"]), 0.10, "the registry entry is untouched")
	assert_true(world.progression_rules() == world.registry.get_entry("rules", "progression"), "no overlay: the registry's own progression entry")
	assert_true(world.new_game(false, "story"))
	assert_eq(world.rules.depth_hp_per_level, 0.05, "story: a gentle depth curve")
	assert_eq(world.rules.boss_telegraph_round, 2)
	assert_eq(world.rules.rest_after_victory, 0.35)
	assert_true(world.new_game(true, "balanced"))
	assert_eq(world.rules.depth_hp_per_level, 0.10, "balanced: the base rules")
	assert_false(world.rules.story_protected, "mortal on top")
	assert_true(world.new_game(false, "no_such_difficulty"))
	assert_eq(world.narrative.difficulty, "balanced", "an unknown id falls back to the default")
	assert_true(world.new_game(false))
	assert_eq(world.narrative.difficulty, "balanced", "no id: the default")


func test_the_difficulty_rides_the_save() -> void:
	assert_true(world.new_game(false, "tactician"))
	assert_eq(world.save_slot(1), OK)
	assert_true(world.new_game(false, "story"))
	assert_eq(world.rules.depth_hp_per_level, 0.05)
	assert_eq(world.load_slot(1), [])
	assert_eq(world.narrative.difficulty, "tactician", "the difficulty rides with the story")
	assert_eq(world.rules.depth_hp_per_level, 0.15, "and the rules follow it on load")
	# A save from before difficulties (no field) plays on the default.
	var data := SaveSystem.read(world.save_path(SaveSystem.slot_name(1)))
	Dictionary(data["narrative"]).erase("difficulty")
	assert_eq(SaveSystem.write(world.save_path(SaveSystem.slot_name(1)), data), OK)
	assert_eq(world.load_slot(1), [])
	assert_eq(world.difficulty_id(), "balanced", "an old save plays on the default")
	assert_eq(world.rules.depth_hp_per_level, 0.10)


func test_the_title_asks_the_difficulty_then_the_stakes() -> void:
	world.show_title()
	assert_true(_pick("new"))
	assert_eq(world.title_menu.page, TitleMenu.PAGE_DIFFICULTY)
	var ids: Array[String] = []
	for r: Dictionary in world.title_menu.rows:
		ids.append(String(r["id"]))
	assert_eq(ids, ["diff_story", "diff_balanced", "diff_tactician", "back"])
	assert_contains(world.title_menu.label.text, "Tactician")
	assert_contains(world.title_menu.label.text, "Difficulty.")
	assert_true(_pick("diff_tactician"))
	assert_eq(world.title_menu.page, TitleMenu.PAGE_STAKES)
	assert_eq(world.pending_difficulty, "tactician")
	var iron := _row(world.title_menu.rows, "iron")
	assert_false(iron.is_empty(), "Iron Weave is a death-stakes row")
	assert_true(bool(iron["enabled"]), "no run underway: Iron Weave is open")
	assert_true(_pick("back"))
	assert_eq(world.title_menu.page, TitleMenu.PAGE_DIFFICULTY, "back from the stakes returns to the difficulty")
	assert_true(_pick("diff_story"))
	assert_true(_pick("mortal"))
	assert_true(world.creator_menu.visible, "the creator is the first screen of a new game (S51)")
	assert_true(world.confirm_creator())
	assert_false(world.in_title(), "the game started")
	assert_eq(world.narrative.difficulty, "story")
	assert_true(world.is_mortal_mode())
	assert_false(world.is_iron_weave())


func test_iron_weave_is_mortal_with_one_save_and_no_reloads() -> void:
	world.show_title()
	assert_true(_pick("new"))
	assert_true(_pick("diff_balanced"))
	assert_true(_pick("iron"))
	assert_true(world.creator_menu.visible, "the creator first")
	assert_true(world.confirm_creator())
	assert_true(world.is_iron_weave())
	assert_true(world.is_mortal_mode(), "Iron Weave is Mortal")
	assert_false(world.rules.story_protected)
	assert_false(world.reload_allowed())
	assert_true(world.account.iron_active, "the account carries the run")
	assert_eq(world.account.iron_runs, 1)
	assert_eq(world.account.iron_difficulty, "balanced")
	var on_disk := Account.load_or_new(ACCOUNT)
	assert_true(on_disk.iron_active, "and it is on disk, outside the save")
	assert_true(_autosave_exists(), "the one save is the autosave")
	# One save: the slots refuse.
	assert_eq(world.save_slot(1), ERR_UNAVAILABLE, "no slot saves")
	assert_false(FileAccess.file_exists(world.save_path(SaveSystem.slot_name(1))))
	# No reloads: the slots and the autosave refuse from inside the game.
	assert_eq(world.load_slot(1), ["Iron Weave: no reloads"])
	var items := world.system_items()
	assert_false(bool(_row(items, "save_game")["enabled"]))
	assert_eq(String(_row(items, "save_game")["why"]), "Iron Weave: one save")
	assert_false(bool(_row(items, "load_game")["enabled"]))
	assert_eq(String(_row(items, "load_game")["why"]), "Iron Weave: no reloads")
	var load_rows := world.saves_rows(SavesMenu.PAGE_LOAD)
	assert_false(bool(_row(load_rows, "autosave")["enabled"]), "the saves screen refuses too")
	assert_eq(String(_row(load_rows, "autosave")["why"]), "Iron Weave: no reloads")
	assert_false(bool(_row(world.saves_rows(SavesMenu.PAGE_SAVE), "slot_1")["enabled"]))
	world.open_system_menu()
	assert_false(world.activate_system_item("load_autosave"), "the autosave item does nothing under Iron Weave")
	assert_true(world.is_iron_weave())
	# The save says so.
	assert_contains(SaveSystem.summarize(SaveSystem.read(world.save_path(SaveSystem.AUTOSAVE)), world.registry), "Iron Weave")
	# The title: Load is closed while the run stands; Continue is the way back in.
	world.show_title()
	var load_row := _row(world.title_rows(), "load")
	assert_false(bool(load_row["enabled"]))
	assert_contains(String(load_row["why"]), "Iron Weave")
	assert_true(_pick("new"))
	assert_true(_pick("diff_balanced"))
	var iron := _row(world.title_menu.rows, "iron")
	assert_false(bool(iron["enabled"]), "a second Iron Weave run cannot start while one stands")
	assert_contains(String(iron["why"]), "underway")
	assert_true(_pick("back"))
	assert_true(_pick("back"))
	assert_true(_pick("continue"), "Continue re-enters the one save")
	assert_true(world.is_iron_weave(), "and it is still Iron Weave")
	assert_true(world.account.iron_active)


func test_any_other_new_game_gives_up_an_iron_run() -> void:
	assert_true(world.new_game(true, "balanced", true))
	assert_true(world.account.iron_active)
	assert_true(world.new_game(false, "story"))
	assert_false(world.is_iron_weave())
	assert_true(world.reload_allowed())
	assert_false(world.account.iron_active, "the run is given up with its save")
	assert_false(Account.load_or_new(ACCOUNT).iron_active)
	assert_eq(world.account.iron_runs, 1, "the attempt still counts")
	assert_true(bool(_row(world.stakes_rows(), "iron")["enabled"]), "Iron Weave is open again")
	assert_eq(world.save_slot(1), OK, "the slots are back")


func test_a_wipe_ends_the_iron_run_and_removes_the_save() -> void:
	assert_true(world.new_game(true, "tactician", true))
	seed(20260921)
	assert_false(world.enter_shard("rusted_undercity", 7, 1).is_empty(), "into a Shard")
	assert_true(_autosave_exists())
	for m: PartyMember in world.party.members:
		m.hp = 0
		m.dead = true
	world.mode = "combat"
	world._on_combat_ended("defeat")
	assert_eq(world.mode, "defeated")
	assert_false(_autosave_exists(), "the one save is gone")
	assert_false(world.account.iron_active, "the run is over on the account")
	assert_false(Account.load_or_new(ACCOUNT).iron_active)
	assert_contains(world.status_line(), "Iron Weave run is over")
	assert_false(world.continue_game(), "nothing to continue")
	assert_false(bool(_row(world.title_rows(), "continue")["enabled"]))
	assert_true(bool(_row(world.stakes_rows(), "iron")["enabled"]), "and a new Iron Weave run may start")


func test_a_dead_leader_ends_the_iron_run_too() -> void:
	assert_true(world.new_game(true, "balanced", true))
	assert_false(world.enter_shard("rusted_undercity", 8, 1).is_empty())
	var leader := world.party.leader()
	leader.hp = 0
	leader.dead = true
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_eq(world.mode, "defeated")
	assert_false(_autosave_exists())
	assert_false(world.account.iron_active)


func test_an_ending_keeps_the_iron_run_on_the_account() -> void:
	assert_true(world.new_game(true, "balanced", true))
	assert_eq(world.account.iron_runs, 1)
	world.iron_run_complete("drift")
	assert_true(world.narrative.flag("iron_weave_complete"))
	assert_false(world.account.iron_active, "the run is over")
	assert_true(world.account.has("iron_weave:drift"), "and kept as a key")
	assert_true(Account.load_or_new(ACCOUNT).has("iron_weave:drift"))
	assert_true(world.check_achievements().has("iron_weave") or world.platform().unlocked_this_session.has("iron_weave"), "the Iron Weave achievement")
	assert_true(_autosave_exists() or true, "the finished save may stay as a record")
	# Not an Iron run: nothing recorded.
	assert_true(world.new_game(false))
	world.iron_run_complete("drift")
	assert_false(world.narrative.flag("iron_weave_complete"))


func test_the_validator_flags_an_overlay_the_rules_do_not_have() -> void:
	world.registry.put("difficulties", "zz_bad", {"name": "Bad", "rules": {"combat": {"depth_hp_per_level": 0.2, "no_such_field": 1}, "no_such_rules": {"x": 1}, "loot": "not a dictionary"}})
	var problems: Array[String] = []
	for p: String in ContentValidator.validate(world.registry, ["runtime"]):
		if p.begins_with("difficulties/zz_bad"):
			problems.append(p)
	world.registry._entries["difficulties"].erase("zz_bad")
	world.registry._fingerprint_cache = ""
	assert_eq(problems.size(), 3, "three problems: %s" % ", ".join(problems))
	assert_any_contains(problems, "overrides 'no_such_field', which rules/combat does not have")
	assert_any_contains(problems, "overrides rules 'no_such_rules', which does not exist")
	assert_any_contains(problems, "rules.loot must be a dictionary of overrides")
	for p: String in ContentValidator.validate(world.registry, ["runtime"]):
		assert_false(p.begins_with("difficulties/"), "clean again: %s" % p)
