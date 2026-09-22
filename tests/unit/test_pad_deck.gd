## Pad and Deck (S53, D-108): analog glide on the walk and the combat
## cursor, rumble on hits, downs, wins, wipes and extractions behind a
## setting, text size as a setting the Deck defaults to, and the
## performance budget every map and the largest Shard of every biome
## stay under.
extends TestCase

const LEDGER := "user://test_ledger_paddeck.json"
const SAVES := "user://test_saves_paddeck"
const SETTINGS_PATH := "user://test_settings_paddeck.json"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	Rumble.enabled = true
	Rumble.last = {}
	Rumble.count = 0
	UiScale.text_scale = 1.0
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()
	Rumble.enabled = true
	UiScale.text_scale = 1.0


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _cleanup() -> void:
	for f: String in [LEDGER, SETTINGS_PATH]:
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
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func test_a_tilted_stick_walks_slower_and_the_cursor_glides_with_the_tilt() -> void:
	var leader := world.party.leader()
	var start := leader.position
	var anywhere := func(_p: Vector2) -> bool: return true
	world.party.steer_leader(Vector2(1.0, 0.0), 1.0, anywhere)
	var full := leader.position.x - start.x
	assert_true(full > 0.0, "a full tilt walks")
	world.party.steer_leader(Vector2(-0.5, 0.0), 1.0, anywhere)
	var half := full - (leader.position.x - start.x)
	assert_true(absf(half - full * 0.5) < 0.01, "a half tilt walks half as far: %.1f of %.1f" % [half, full])
	world.party.steer_leader(Vector2(3.0, 0.0), 1.0, anywhere)
	assert_true(absf((leader.position.x - start.x) - (full * 0.5 + full)) < 0.01, "keys (a long vector) never walk faster than a full tilt")
	# The combat cursor: a first step, a pause, then a glide that follows the tilt.
	assert_eq(ExploreWorld.glide_repeat(Vector2(1.0, 0.0)), ExploreWorld.CURSOR_REPEAT, "a full tilt races")
	assert_true(is_equal_approx(ExploreWorld.glide_repeat(Vector2(0.5, 0.0)), ExploreWorld.CURSOR_REPEAT / 0.5), "a half tilt creeps at half pace")
	assert_true(is_equal_approx(ExploreWorld.glide_repeat(Vector2(0.1, 0.0)), ExploreWorld.CURSOR_REPEAT / 0.35), "a nudge is clamped, never a crawl")
	world._cursor_hold = 0.0
	world._tick_cursor(Vector2(0.5, 0.0), 0.0)
	assert_eq(world._cursor_hold, ExploreWorld.CURSOR_FIRST_REPEAT, "the first step waits the long pause")
	world._tick_cursor(Vector2(0.5, 0.0), ExploreWorld.CURSOR_FIRST_REPEAT + 0.01)
	assert_true(is_equal_approx(world._cursor_hold, ExploreWorld.CURSOR_REPEAT / 0.5), "then glides at the tilt's pace")
	world._tick_cursor(Vector2.ZERO, 0.0)
	assert_eq(world._cursor_hold, 0.0, "letting go resets")


func test_rumble_follows_hits_downs_wins_wipes_and_extractions_behind_a_setting() -> void:
	assert_true(Rumble.pulse("hit"))
	assert_eq(String(Rumble.last["kind"]), "hit")
	assert_false(Rumble.pulse("no_such_pulse"))
	Rumble.enabled = false
	assert_false(Rumble.pulse("hit"), "off: nothing")
	Rumble.enabled = true
	Rumble.last = {}
	var c := world.combat
	c._rumble_for_event({"type": "ability", "target": "e:0:scav", "hit": true, "damage": 4})
	assert_eq(Rumble.last, {}, "an enemy hit is not felt")
	c._rumble_for_event({"type": "ability", "target": "p:weaver", "hit": false, "damage": 0})
	assert_eq(Rumble.last, {}, "a miss is not felt")
	c._rumble_for_event({"type": "ability", "target": "p:weaver", "hit": true, "damage": 3})
	assert_eq(String(Rumble.last["kind"]), "hit")
	c._rumble_for_event({"type": "chain", "target": "p:weaver", "damage": 7})
	assert_eq(String(Rumble.last["kind"]), "heavy", "six or more is heavy")
	c._rumble_for_event({"type": "ability", "target": "p:weaver", "hit": true, "damage": 9, "downed": true})
	assert_eq(String(Rumble.last["kind"]), "downed")
	# The world: a win, a wipe, an extraction.
	var before := Rumble.count
	world.enter_shard("rusted_undercity", 7, 1)
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_eq(String(Rumble.last["kind"]), "victory")
	world.teleport_party(world.extraction_cell())
	assert_true(world.extract())
	assert_eq(String(Rumble.last["kind"]), "extract")
	world.enter_shard("rusted_undercity", 8, 1)
	world.mode = "combat"
	world._on_combat_ended("defeat")
	assert_eq(String(Rumble.last["kind"]), "wipe")
	assert_eq(Rumble.count, before + 3)
	# The setting.
	world.settings.rumble = false
	world.settings.apply()
	assert_false(Rumble.enabled)
	assert_false(Rumble.pulse("hit"))
	world.settings.rumble = true
	world.settings.apply()
	assert_true(Rumble.enabled)


func test_text_size_is_a_setting_the_deck_defaults_to() -> void:
	var s := Settings.new()
	assert_eq(s.text_scale, 1.0)
	assert_true(s.rumble)
	assert_eq(s.text_scale_name(), "normal")
	s.cycle_text_scale(1)
	assert_eq(s.text_scale, 1.15)
	assert_eq(s.text_scale_name(), "large")
	s.cycle_text_scale(-2)
	assert_eq(s.text_scale, 1.5, "wraps to the Deck size")
	assert_eq(s.text_scale_name(), "Deck")
	s.rumble = false
	assert_eq(s.save(SETTINGS_PATH), OK)
	var back := Settings.load_or_default(SETTINGS_PATH)
	assert_eq(back.text_scale, 1.5, "rides the file")
	assert_false(back.rumble)
	assert_eq(Settings.nearest_scale(1.2), 1.15, "an odd value snaps to a step")
	assert_eq(Settings.from_dict({"text_scale": 9.0}).text_scale, 1.5)
	assert_eq(Settings.from_dict({}).text_scale, 1.0)
	assert_false(Settings.looks_like_deck(), "headless is not a Deck")
	assert_eq(Settings.deck_default().text_scale, 1.0)
	# Applied to every menu, not to the world.
	var rows := SettingsMenu.build_rows(world.settings)
	var labels: PackedStringArray = []
	for r: Dictionary in rows:
		labels.append(String(r["label"]))
	assert_true(labels.has("Pad rumble: on"))
	assert_true(labels.has("Text size: normal"))
	var menu_size := world.system_menu.label.get_theme_font_size("font_size")
	var actor_label: Label = world.party.leader().get_node("Name")
	var actor_size := actor_label.get_theme_font_size("font_size")
	assert_true(world.open_settings())
	for i: int in world.settings_menu.rows.size():
		if String(world.settings_menu.rows[i]["id"]) == "text_scale":
			world.settings_menu.cursor = i
	assert_true(world.adjust_setting(1))
	assert_eq(world.settings.text_scale, 1.15)
	assert_eq(world.system_menu.label.get_theme_font_size("font_size"), int(round(menu_size * 1.15)), "menus grow")
	assert_eq(world.settings_menu.label.get_theme_font_size("font_size"), 23)
	assert_eq(world.dialogue_menu.label.get_theme_font_size("font_size"), int(round(21 * 1.15)))
	assert_eq(actor_label.get_theme_font_size("font_size"), actor_size, "world-space labels stay")
	assert_contains(world.settings_menu.label.text, "Text size: large")
	assert_true(world.adjust_setting(1))
	assert_true(world.adjust_setting(1))
	assert_eq(world.settings.text_scale, 1.5)
	assert_eq(world.system_menu.label.get_theme_font_size("font_size"), int(round(menu_size * 1.5)), "from the designed size, no drift")
	assert_true(world.adjust_setting(1))
	assert_eq(world.settings.text_scale, 1.0)
	assert_eq(world.system_menu.label.get_theme_font_size("font_size"), menu_size, "and back")
	for i: int in world.settings_menu.rows.size():
		if String(world.settings_menu.rows[i]["id"]) == "rumble":
			world.settings_menu.cursor = i
	assert_true(world.confirm_setting())
	assert_false(world.settings.rumble)
	assert_contains(world.settings_menu.label.text, "Pad rumble: off")
	world.close_settings()


func test_every_map_and_the_largest_shard_of_every_biome_fits_the_budget() -> void:
	var result: Dictionary = PerfBudget.measure(_root(), 20)
	for line: String in result["lines"]:
		print("  " + line)
	assert_eq(int(result["code"]), 0, "every count in budget")
	var shards := 0
	for row: Dictionary in result["rows"]:
		if String(row["kind"]) == "shard":
			shards += 1
			assert_true(float(row["logic_ms"]) < 8.0, "%s: the game's own frame work stays small headless (%.2f ms)" % [row["id"], row["logic_ms"]])
	assert_eq(shards, world.registry.get_all("shards").size(), "every template measured at its largest")
