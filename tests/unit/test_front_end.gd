## The front end: settings round-trip and application, binding overrides
## and rebinding, pad glyphs, the title screen driven by pad buttons
## alone into a new game with the death-stakes choice, continue and load,
## and the pause menu reaching settings and the title.
extends TestCase

const LEDGER := "user://test_ledger_front.json"
const SAVES := "user://test_saves_front"
const SETTINGS_PATH := "user://test_settings_front.json"
const INPUT_PATH := "user://test_input_front.json"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	InputActions.reset_overrides()
	Glyphs.style = "auto"
	world = _fresh()


func after_each() -> void:
	_drop(world)
	InputActions.reset_overrides()
	Glyphs.style = "auto"
	_cleanup()


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _cleanup() -> void:
	for p: String in [LEDGER, SETTINGS_PATH, INPUT_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
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
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


static func _pad(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button as JoyButton
	e.pressed = true
	return e


static func _key(key: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = key as Key
	e.pressed = true
	return e


func test_settings_round_trip_and_apply() -> void:
	var s := Settings.new()
	s.fullscreen = true
	s.step_volume(-2)
	s.cycle_glyphs(1)
	assert_eq(s.volume_db, -6.0)
	assert_eq(s.glyphs, "xbox")
	assert_eq(s.save(SETTINGS_PATH), OK)
	var back := Settings.load_or_default(SETTINGS_PATH)
	assert_true(back.fullscreen)
	assert_eq(back.volume_db, -6.0)
	assert_eq(back.glyphs, "xbox")
	assert_eq(back.volume_percent(), 80)
	back.apply()
	assert_eq(Glyphs.style, "xbox")
	assert_eq(Glyphs.confirm(), "A")
	s.cycle_glyphs(1)
	s.apply()
	assert_eq(Glyphs.confirm(), "Cross")
	assert_eq(Glyphs.ability(1), "Triangle")
	assert_eq(Glyphs.key_and_pad("Enter", Glyphs.confirm()), "Enter / Cross")
	var missing := Settings.load_or_default("user://does_not_exist.json")
	assert_false(missing.fullscreen)
	assert_eq(missing.glyphs, "auto")
	assert_eq(Settings.from_dict({"volume_db": -99.0, "glyphs": "weird"}).glyphs, "auto")
	assert_eq(Settings.from_dict({"volume_db": -99.0}).volume_db, Settings.VOLUME_MIN_DB, "clamped")
	Glyphs.style = "auto"
	assert_eq(Glyphs.resolved_style(), "xbox", "no pad connected headless: Xbox names")


func test_bindings_can_be_rebound_persisted_and_reset() -> void:
	assert_eq(InputActions.describe("confirm"), "Enter, Kp Enter / A")
	assert_true(InputActions.rebind("confirm", _key(KEY_SPACE)))
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), "confirm"))
	assert_false(InputMap.event_is_action(_key(KEY_ENTER), "confirm"), "the old key is gone")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_A), "confirm"), "the pad button stays")
	assert_true(InputActions.rebind("confirm", _pad(JOY_BUTTON_Y)))
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_Y), "confirm"))
	assert_false(InputMap.event_is_action(_pad(JOY_BUTTON_A), "confirm"))
	assert_eq(InputActions.describe("confirm"), "Space / Y")
	assert_false(InputActions.rebind("confirm", InputEventMouseButton.new()), "mouse buttons are not bindings")
	assert_false(InputActions.rebind("nope", _key(KEY_X)))
	assert_eq(InputActions.save_overrides(INPUT_PATH), OK)
	InputActions.reset_overrides()
	assert_true(InputMap.event_is_action(_key(KEY_ENTER), "confirm"), "reset restores defaults")
	InputActions.load_overrides(INPUT_PATH)
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), "confirm"), "overrides load back")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_Y), "confirm"))
	InputActions.apply_overrides({"confirm": {"keys": [KEY_TAB]}, "bogus": {"keys": [KEY_Q]}})
	assert_true(InputMap.event_is_action(_key(KEY_TAB), "confirm"))
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_A), "confirm"), "keys-only override keeps the default pad button")
	assert_false(InputActions.overrides.has("bogus"))
	InputActions.reset_overrides()


func test_title_shows_on_a_cold_start_but_not_for_tests() -> void:
	assert_false(world.in_title(), "the test runner marks the session")
	world.show_title()
	assert_true(world.in_title())
	assert_contains(world.title_menu.label.text, "▶ New game")
	assert_contains(world.title_menu.label.text, "Continue  (no autosave yet)")
	assert_contains(world.title_menu.label.text, "Enter / A confirm")
	world.title_menu.close()


func test_pad_alone_starts_a_mortal_game_from_the_title() -> void:
	world.narrative.set_flag("some_old_flag", true)
	world.ledger.bank({"salvage": 40})
	world.show_title()
	# A on New game -> the stakes page; down to Mortal; A.
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_eq(world.title_menu.page, TitleMenu.PAGE_STAKES)
	assert_contains(world.title_menu.label.text, "▶ Story-Protected")
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN))
	assert_contains(world.title_menu.label.text, "▶ Mortal")
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_false(world.in_title(), "playing")
	assert_true(world.is_mortal_mode())
	assert_false(world.rules.story_protected, "the rule follows the choice")
	assert_false(world.narrative.flag("some_old_flag"), "a fresh story")
	assert_eq(world.ledger.total("salvage"), 0, "fresh books")
	assert_eq(world.map_id, "bastion")
	assert_eq(world.party.members.size(), 1)
	assert_eq(world.narrative.stage_of("main_waking"), "gate", "the main quest starts")
	assert_true(FileAccess.file_exists(world.save_path(SaveSystem.AUTOSAVE)), "the first autosave")
	# The mode rides with the save.
	var again := _fresh()
	assert_true(again.rules.story_protected, "default rule before a load")
	assert_eq(again.load_from(SaveSystem.AUTOSAVE), [])
	assert_false(again.rules.story_protected, "loaded: Mortal")
	assert_true(again.is_mortal_mode())
	_drop(again)


func test_back_from_stakes_and_story_protected_default() -> void:
	world.show_title()
	world._unhandled_input(_key(KEY_ENTER))
	assert_eq(world.title_menu.page, TitleMenu.PAGE_STAKES)
	world._unhandled_input(_pad(JOY_BUTTON_B))
	assert_eq(world.title_menu.page, TitleMenu.PAGE_MAIN, "B backs out of the stakes page")
	world._unhandled_input(_pad(JOY_BUTTON_A))
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_false(world.in_title())
	assert_true(world.rules.story_protected)
	assert_false(world.is_mortal_mode())


func test_continue_and_load_from_the_title() -> void:
	world.narrative.set_flag("marker", true)
	assert_eq(world.save_slot(2), OK)
	world.autosave()
	world.show_title()
	assert_contains(world.title_menu.label.text, "   Continue")
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN))
	assert_eq(world.title_menu.selected_id(), "continue")
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_false(world.in_title())
	assert_true(world.narrative.flag("marker"), "continued from the autosave")
	world.show_title()
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN))
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN))
	assert_eq(world.title_menu.selected_id(), "load")
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_false(world.in_title())
	assert_true(world.system_menu.visible, "Load opens the slot list")
	assert_contains(world.system_menu.label.text, "Load slot 2 — The Bastion")
	assert_true(world.activate_system_item("load_2"))


func test_settings_from_title_and_pause_menu_and_rebind_capture() -> void:
	world.settings = Settings.new()
	world.show_title()
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_UP)) # wraps to Quit
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_UP)) # Settings
	assert_eq(world.title_menu.selected_id(), "settings")
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_true(world.settings_menu.visible)
	assert_false(world.in_title())
	assert_contains(world.settings_menu.label.text, "▶ Fullscreen: off")
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_true(world.settings.fullscreen, "A toggles")
	assert_contains(world.settings_menu.label.text, "▶ Fullscreen: on")
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN))
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_LEFT))
	assert_eq(world.settings.volume_db, -3.0, "left lowers the volume")
	assert_contains(world.settings_menu.label.text, "Master volume: 90%")
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN))
	world._unhandled_input(_pad(JOY_BUTTON_DPAD_RIGHT))
	assert_eq(world.settings.glyphs, "xbox")
	# Rebind end_turn to the Y button.
	for _i: int in 4:
		world._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN))
	assert_eq(world.settings_menu.selected()["id"], "rebind:end_turn")
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_eq(world.settings_menu.rebinding, "end_turn")
	assert_contains(world.settings_menu.label.text, "Press the new key or pad button for end turn")
	world._unhandled_input(_pad(JOY_BUTTON_Y))
	assert_eq(world.settings_menu.rebinding, "")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_Y), "end_turn"))
	assert_false(InputMap.event_is_action(_pad(JOY_BUTTON_START), "end_turn"))
	assert_contains(world.settings_menu.label.text, "end turn: Space / Y")
	# Esc while arming keeps the old binding.
	world._unhandled_input(_pad(JOY_BUTTON_A))
	assert_eq(world.settings_menu.rebinding, "end_turn")
	world._unhandled_input(_key(KEY_ESCAPE))
	assert_eq(world.settings_menu.rebinding, "")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_Y), "end_turn"))
	# B closes back to the title, and the file persisted.
	world._unhandled_input(_pad(JOY_BUTTON_B))
	assert_false(world.settings_menu.visible)
	assert_true(world.in_title(), "settings opened from the title return to it")
	assert_true(FileAccess.file_exists(Settings.PATH))
	assert_true(FileAccess.file_exists(InputActions.OVERRIDES_PATH))
	assert_true(Settings.load_or_default().fullscreen, "settings persisted")
	world.title_menu.close()
	# From the pause menu, settings return to the game.
	assert_true(world.open_system_menu())
	assert_true(world.activate_system_item("settings"))
	assert_true(world.settings_menu.visible)
	world._unhandled_input(_key(KEY_ESCAPE))
	assert_false(world.settings_menu.visible)
	assert_false(world.in_title())
	assert_true(world.open_system_menu())
	assert_true(world.activate_system_item("title"))
	assert_true(world.in_title(), "the pause menu reaches the title")
	world.title_menu.close()
	# Leave the machine as we found it.
	InputActions.reset_overrides()
	InputActions.save_overrides()
	Settings.new().save()
