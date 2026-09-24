## Saves v2 (S68, D-124): F5 asks before it overwrites and F9 is one
## confirm from slot 1, the autosave depth is a setting, and a save written
## mid-fight puts the fight back where it stood, rolls and all.
extends TestCase

const LEDGER := "user://test_ledger_saves2.json"
const SAVES := "user://test_saves_saves2"
const SETTINGS := "user://test_settings_saves2.json"
const ACCOUNT := "user://test_account_saves2.json"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()


static func _cleanup() -> void:
	for f: String in [LEDGER, SETTINGS, ACCOUNT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.map_id = "proto_yard"
	w.home_map = "proto_yard"
	w.party_id = "prototype"
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.settings_path = SETTINGS
	w.account_path = ACCOUNT
	w.input_path = "user://test_input_saves2.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func _exists(save_name: String) -> bool:
	return FileAccess.file_exists(world.save_path(save_name))


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func test_f5_asks_before_it_overwrites_and_f9_is_one_confirm_from_slot_1() -> void:
	assert_false(_exists("slot_1"))
	assert_true(world.quick_save(), "a first F5 saves straight away")
	assert_true(_exists("slot_1"))
	assert_false(world.saves_menu.visible)
	world.narrative.set_flag("later", true)
	assert_true(world.quick_save(), "the second opens the question")
	assert_true(world.saves_menu.visible)
	assert_eq(world.saves_menu.page, SavesMenu.PAGE_SAVE)
	assert_eq(String(world.saves_menu.selected()["id"]), "slot_1", "the cursor on the slot")
	assert_eq(world.saves_menu.pending, "slot_1", "asking")
	assert_contains(world.saves_menu.label.text, "Overwrite Slot 1")
	world.cancel_saves()
	assert_eq(world.saves_menu.pending, "", "Esc answers no")
	assert_true(world.saves_menu.visible, "and the screen stays for another choice")
	world.cancel_saves()
	assert_false(world.saves_menu.visible, "a second Esc closes it; the old save stands")
	var flags: Dictionary = Dictionary(SaveSystem.read(world.save_path("slot_1")).get("narrative", {})).get("flags", {})
	assert_false(bool(flags.get("later", false)), "not overwritten")
	assert_true(world.quick_save())
	assert_true(world.activate_saves_row(), "Enter answers yes")
	flags = Dictionary(SaveSystem.read(world.save_path("slot_1")).get("narrative", {})).get("flags", {})
	assert_true(bool(flags.get("later", false)), "overwritten on the confirm")
	world.cancel_saves()
	# F9.
	world.narrative.set_flag("unsaved", true)
	assert_true(world.quick_load(), "the load page opens")
	assert_eq(world.saves_menu.page, SavesMenu.PAGE_LOAD)
	assert_eq(String(world.saves_menu.selected()["id"]), "slot_1")
	assert_true(world.activate_saves_row(), "one confirm loads")
	assert_false(world.narrative.flag("unsaved"), "back to the save")
	assert_false(world.saves_menu.visible)
	# The keys route there.
	world.narrative.set_flag("unsaved", true)
	world._unhandled_input(_key(KEY_F5))
	assert_true(world.saves_menu.visible and world.saves_menu.pending == "slot_1", "F5 asks")
	world.cancel_saves()
	world._unhandled_input(_key(KEY_F9))
	assert_true(world.saves_menu.visible and world.saves_menu.page == SavesMenu.PAGE_LOAD, "F9 offers")
	world.cancel_saves()
	# Nothing in slot 1 yet: F9 says so.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(world.save_path("slot_1")))
	assert_false(world.quick_load())
	assert_false(world.saves_menu.visible)


func test_the_autosave_depth_is_a_setting() -> void:
	var s := Settings.new()
	assert_eq(s.autosaves_kept, 3, "three, as the constant was")
	s.cycle_autosaves(1)
	s.cycle_autosaves(1)
	s.cycle_autosaves(1)
	assert_eq(s.autosaves_kept, 5, "capped at five")
	s.cycle_autosaves(-9)
	assert_eq(s.autosaves_kept, 1, "never under one")
	assert_eq(Settings.from_dict({"autosaves_kept": 9}).autosaves_kept, 5)
	s.autosaves_kept = 4
	assert_eq(s.save(SETTINGS), OK)
	assert_eq(Settings.load_or_default(SETTINGS).autosaves_kept, 4)
	var labels: PackedStringArray = []
	for r: Dictionary in SettingsMenu.build_rows(world.settings):
		labels.append(String(r["label"]))
		if String(r["id"]) == "autosaves_kept":
			assert_eq(String(r["section"]), "Saves")
	assert_true(labels.has("Autosaves kept: 3"))
	# Five kept: five older copies stay; one kept: none do, and the extras go.
	world.settings.autosaves_kept = 5
	assert_true(world.new_game(false))
	for i: int in 6:
		world.narrative.set_flag("beat_%d" % i, true)
		assert_eq(world.autosave(), OK)
	assert_true(_exists("autosave_4"), "four older copies with five kept")
	assert_false(_exists("autosave_5"))
	assert_eq(SaveSystem.list_saves(SAVES, world.registry, true, 5).size(), SaveSystem.SLOTS + 5)
	assert_eq(world.saves_rows(SavesMenu.PAGE_LOAD).size() >= SaveSystem.SLOTS + 5, true, "the load page lists them")
	world.settings.autosaves_kept = 1
	assert_eq(world.autosave(), OK)
	assert_false(_exists("autosave_1"), "one kept: the older copy is dropped on the next autosave")
	assert_true(world.open_settings())
	for i: int in world.settings_menu.rows.size():
		if String(world.settings_menu.rows[i]["id"]) == "autosaves_kept":
			world.settings_menu.cursor = i
	assert_true(world.adjust_setting(1))
	assert_eq(world.settings.autosaves_kept, 2)
	assert_contains(world.settings_menu.label.text, "Autosaves kept: 2")
	world.close_settings()


func test_a_fight_survives_a_quit_and_resumes_where_it_stood() -> void:
	world.rules.initiative_die = 1
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	assert_eq(world.mode, "combat")
	var s := world.combat.state
	# A couple of actions, so the fight has a shape: HP lost, a move made, a status laid.
	var actor := s.current()
	var foe := EnemyBrain.nearest_hostile(s, actor)
	var blow := EnemyBrain.usable_ability(s, actor, foe)
	if not blow.is_empty():
		world.combat.player_click(foe.cell)
	world.combat.end_player_turn()
	var round_before := s.round_number
	var turn_before := s.turn_index
	var order_before := CombatState._ids(s.order)
	var hp_before: Dictionary = {}
	var cells_before: Dictionary = {}
	for c: Combatant in s.combatants:
		hp_before[c.id] = c.hp
		cells_before[c.id] = c.cell
	assert_eq(world.save_slot(1), ERR_UNAVAILABLE, "slots stay out of a fight")
	assert_eq(world.save_fight(), OK, "the autosave takes the fight")
	var next_roll := s.rng.randi() # what the fight would roll next
	var again := _fresh()
	assert_eq(again.load_from(SaveSystem.AUTOSAVE), [])
	assert_eq(again.mode, "combat", "back in the fight")
	assert_false(again.party.active)
	var t := again.combat.state
	assert_eq(t.round_number, round_before)
	assert_eq(t.turn_index, turn_before)
	assert_eq(CombatState._ids(t.order), order_before, "the same order")
	for c: Combatant in t.combatants:
		assert_eq(c.hp, int(hp_before[c.id]), "%s HP" % c.id)
		assert_eq(c.cell, Vector2i(cells_before[c.id]), "%s cell" % c.id)
		var node: WorldActor = again.combat.actors[c.id]
		assert_true(node != null and is_instance_valid(node), "%s has its actor" % c.id)
		assert_eq(again.map_view.world_to_cell(node.position), c.cell, "%s stands on its cell" % c.id)
	assert_eq(t.rng.randi(), next_roll, "the next roll is the roll it would have been")
	assert_true(t.history.any(func(l: String) -> bool: return l.contains("The fight resumes")), "logged")
	assert_eq(again.living_enemies().size(), world.living_enemies().size(), "the roster is whole")
	# It plays out.
	var steps := 0
	while not t.finished and steps < 600:
		steps += 1
		if not again.combat.current_is_player():
			again.combat.end_player_turn()
			continue
		var a := t.current()
		var target := EnemyBrain.nearest_hostile(t, a)
		if target == null:
			again.combat.end_player_turn()
			continue
		if not EnemyBrain.usable_ability(t, a, target).is_empty():
			var ap := a.ap
			again.combat.player_click(target.cell)
			if a.ap == ap:
				again.combat.end_player_turn()
		elif a.move_left > 0:
			var field := t.distance_field(target.cell)
			var best := a.cell
			var best_d := int(field.get(a.cell, 9999))
			var cells: Array = t.reachable_cells(a).keys()
			cells.sort()
			for cell: Vector2i in cells:
				if int(field.get(cell, 9999)) < best_d and t.provokers_along(a, t.move_path(a, cell)).is_empty():
					best = cell
					best_d = int(field.get(cell, 9999))
			if best == a.cell:
				again.combat.end_player_turn()
			else:
				again.combat.player_click(best)
		else:
			again.combat.end_player_turn()
	assert_true(t.finished, "the resumed fight ends")
	assert_true(["explore", "defeated"].has(again.mode))
	_drop(again)


func test_an_iron_weave_run_continues_mid_fight_and_an_older_save_still_loads() -> void:
	assert_true(world.new_game(true, "balanced", true))
	assert_true(world.is_iron_weave())
	world.rules.initiative_die = 1
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	assert_eq(world.mode, "combat")
	world.combat.end_player_turn()
	var round_now := world.combat.state.round_number
	world._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST) # tests are guarded; the call below is what it does
	assert_eq(world.save_fight(), OK)
	var data := SaveSystem.read(world.save_path(SaveSystem.AUTOSAVE))
	assert_eq(int(data["version"]), 3)
	assert_true(data.has("combat") and data.has("enemy_roster"))
	var again := _fresh()
	assert_true(again.continue_game(), "Continue takes the fight up")
	assert_eq(again.mode, "combat")
	assert_true(again.is_iron_weave())
	assert_eq(again.combat.state.round_number, round_now)
	_drop(again)
	# A v2 save with no fight in it still loads as it did.
	var old := SaveSystem.read(world.save_path(SaveSystem.AUTOSAVE))
	old.erase("combat")
	old.erase("enemy_roster")
	old["version"] = 2
	assert_eq(SaveSystem.write(world.save_path("slot_2"), old), OK)
	var third := _fresh()
	assert_eq(third.load_from("slot_2"), [])
	assert_eq(third.mode, "explore", "no fight in a v2 save")
	_drop(third)
