## Saves and settings (S54, D-109): the saves screen with titled slots,
## thumbnails beside the files, a question before a slot is overwritten,
## older autosaves kept and listed, Music and SFX buses with their own
## volumes, a colour-blind palette as one full-screen pass, and a settings
## screen grouped with a hint per row.
extends TestCase

const LEDGER := "user://test_ledger_saves54.json"
const SAVES := "user://test_saves_saves54"
const SETTINGS_PATH := "user://test_settings_saves54.json"

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


func _row(rows: Array[Dictionary], id: String) -> Dictionary:
	for r: Dictionary in rows:
		if String(r.get("id", "")) == id:
			return r
	return {}


func _exists(save_name: String) -> bool:
	return FileAccess.file_exists(world.save_path(save_name))


func test_saves_have_titles_and_the_screen_lists_them_with_a_thumbnail_slot() -> void:
	assert_true(world.new_game(false))
	world.creator_state = CreatorState.new()
	assert_eq(world.save_title(), "Weaver · The Bastion · Act 1 · level 1")
	world.narrative.set_flag("act2", true)
	assert_eq(world.act_number(), 2)
	world.narrative.set_flag("catastrophe_seen", true)
	assert_eq(world.act_number(), 3)
	assert_contains(world.save_title(), "Act 3")
	assert_eq(world.save_slot(2), OK)
	var data := SaveSystem.read(world.save_path("slot_2"))
	assert_eq(String(data["title"]), world.save_title(), "the title rides the file")
	assert_eq(SaveSystem.thumbnail_path(world.save_path("slot_2")), world.save_path("slot_2").get_basename() + ".png")
	assert_false(FileAccess.file_exists(SaveSystem.thumbnail_path(world.save_path("slot_2"))), "no frame to capture headless")
	var listing := SaveSystem.list_saves(SAVES, world.registry)
	assert_eq(String(listing[1]["title"]), world.save_title())
	assert_eq(String(listing[1]["thumbnail"]), "")
	assert_true(String(listing[1]["saved_at"]).length() > 8)
	# The screen.
	assert_true(world.open_saves(SavesMenu.PAGE_SAVE))
	assert_true(world.saves_menu.visible)
	var rows := world.saves_menu.rows
	assert_eq(rows.size(), SaveSystem.SLOTS + 1, "three slots and Back")
	assert_contains(String(_row(rows, "slot_1")["label"]), "Slot 1 — empty")
	assert_contains(String(_row(rows, "slot_2")["label"]), "Slot 2 — Weaver · The Bastion · Act 3")
	assert_contains(String(_row(rows, "slot_2")["detail"]), "banked")
	assert_true(bool(_row(rows, "slot_2")["exists"]))
	assert_false(world.saves_menu.thumbnail.visible, "no thumbnail, no box")
	assert_contains(world.saves_menu.label.text, "SAVE GAME")
	assert_contains(world.saves_menu.label.text, "Enter / A saves here")
	world.cancel_saves()
	assert_false(world.saves_menu.visible)
	# A thumbnail written by hand shows up.
	var img := Image.create_empty(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	assert_eq(img.save_png(SaveSystem.thumbnail_path(world.save_path("slot_2"))), OK)
	assert_true(world.open_saves(SavesMenu.PAGE_LOAD))
	world.saves_menu.cursor = 1
	world.saves_menu.refresh()
	assert_true(world.saves_menu.thumbnail.visible, "the slot under the cursor shows its picture")
	assert_true(world.saves_menu.thumbnail.texture != null)
	world.saves_menu.cursor = 0
	world.saves_menu.refresh()
	assert_false(world.saves_menu.thumbnail.visible)
	world.cancel_saves()
	SaveSystem.remove(world.save_path("slot_2"))
	assert_false(_exists("slot_2"))
	assert_false(FileAccess.file_exists(SaveSystem.thumbnail_path(world.save_path("slot_2"))), "the picture goes with the file")


func test_saving_over_a_slot_asks_first_and_esc_keeps_it() -> void:
	assert_true(world.new_game(false))
	assert_true(world.open_saves(SavesMenu.PAGE_SAVE))
	assert_eq(world.saves_menu.cursor, 0)
	assert_true(world.activate_saves_row(), "an empty slot saves at once")
	assert_true(_exists("slot_1"))
	assert_eq(world.saves_menu.pending, "")
	assert_true(world.saves_menu.visible, "the screen stays, refreshed")
	assert_contains(String(_row(world.saves_menu.rows, "slot_1")["label"]), "Weaver · The Bastion")
	var first_stamp := String(SaveSystem.read(world.save_path("slot_1"))["saved_at"])
	world.narrative.set_flag("later", true)
	assert_true(world.activate_saves_row(), "a full slot asks")
	assert_eq(world.saves_menu.pending, "slot_1")
	assert_contains(world.saves_menu.label.text, "Overwrite Slot 1 — ")
	assert_eq(world.saves_menu.move(1), 0, "the cursor is held while the question stands")
	world.cancel_saves()
	assert_eq(world.saves_menu.pending, "", "Esc answers no")
	assert_true(world.saves_menu.visible)
	assert_false(bool(Dictionary(SaveSystem.read(world.save_path("slot_1")).get("narrative", {})).get("flags", {}).get("later", false)), "nothing written")
	assert_true(world.activate_saves_row())
	assert_eq(world.saves_menu.pending, "slot_1")
	assert_true(world.activate_saves_row(), "Enter answers yes")
	assert_eq(world.saves_menu.pending, "")
	var flags: Dictionary = Dictionary(SaveSystem.read(world.save_path("slot_1")).get("narrative", {})).get("flags", {})
	assert_true(bool(flags.get("later", false)), "overwritten")
	assert_true(String(SaveSystem.read(world.save_path("slot_1"))["saved_at"]) >= first_stamp)
	# Back closes; the pause menu offers the two pages.
	world.saves_menu.cursor = world.saves_menu.rows.size() - 1
	assert_true(world.activate_saves_row())
	assert_false(world.saves_menu.visible)
	var items := world.system_items()
	assert_true(bool(_row(items, "save_game")["enabled"]))
	assert_true(bool(_row(items, "load_game")["enabled"]))
	assert_true(world.activate_system_item("load_game"))
	assert_eq(world.saves_menu.page, SavesMenu.PAGE_LOAD)
	world.narrative.set_flag("later", false)
	world.saves_menu.cursor = 0
	assert_true(world.activate_saves_row(), "Enter loads")
	assert_true(world.narrative.flag("later"), "loaded slot 1")
	assert_false(world.saves_menu.visible)
	# In combat the save page is closed.
	world.mode = "combat"
	assert_false(world.open_saves(SavesMenu.PAGE_SAVE))
	world.mode = "explore"


func test_older_autosaves_are_kept_listed_and_loadable_but_not_under_iron_weave() -> void:
	assert_true(world.new_game(false))
	assert_true(_exists("autosave"), "the first autosave")
	assert_false(_exists("autosave_1"))
	world.narrative.set_flag("beat_1", true)
	assert_eq(world.autosave(), OK)
	assert_true(_exists("autosave_1"), "the one before is kept")
	world.narrative.set_flag("beat_2", true)
	assert_eq(world.autosave(), OK)
	world.narrative.set_flag("beat_3", true)
	assert_eq(world.autosave(), OK)
	assert_true(_exists("autosave_2"))
	assert_false(_exists("autosave_3"), "no more than AUTOSAVE_KEEP")
	var flags_of := func(save_name: String) -> Dictionary:
		return Dictionary(SaveSystem.read(world.save_path(save_name)).get("narrative", {})).get("flags", {})
	assert_true(bool(flags_of.call("autosave").get("beat_3", false)), "the newest is the autosave")
	assert_true(bool(flags_of.call("autosave_1").get("beat_2", false)) and not bool(flags_of.call("autosave_1").get("beat_3", false)), "the one before")
	assert_true(bool(flags_of.call("autosave_2").get("beat_1", false)) and not bool(flags_of.call("autosave_2").get("beat_2", false)), "the one before that")
	var listing := SaveSystem.list_saves(SAVES, world.registry, true)
	assert_eq(listing.size(), SaveSystem.SLOTS + SaveSystem.AUTOSAVE_KEEP)
	assert_eq(String(listing[4]["name"]), "autosave_1")
	assert_eq(SaveSystem.list_saves(SAVES, world.registry).size(), SaveSystem.SLOTS + 1, "the short list is as it was")
	var rows := world.saves_rows(SavesMenu.PAGE_LOAD)
	assert_contains(String(_row(rows, "autosave")["label"]), "Autosave — Weaver")
	assert_contains(String(_row(rows, "autosave_1")["label"]), "Older autosave 1 — Weaver")
	assert_true(bool(_row(rows, "autosave_2")["enabled"]))
	assert_true(_row(world.saves_rows(SavesMenu.PAGE_SAVE), "autosave_1").is_empty(), "not on the save page")
	assert_eq(world.load_from("autosave_2"), [], "an older autosave loads")
	assert_true(world.narrative.flag("beat_1") and not world.narrative.flag("beat_2"))
	assert_true(world.continue_game(), "Continue takes the newest")
	assert_true(world.narrative.flag("beat_3"))
	# Iron Weave keeps one.
	assert_true(world.new_game(true, "balanced", true))
	assert_true(world.is_iron_weave())
	assert_true(_exists("autosave"))
	for i: int in 3:
		world.narrative.set_flag("iron_beat_%d" % i, true)
		assert_eq(world.autosave(), OK)
	assert_true(world.is_iron_weave())
	var older := SaveSystem.read(world.save_path("autosave_1"))
	assert_false(bool(Dictionary(older.get("narrative", {})).get("flags", {}).get("iron_weave", false)), "no Iron Weave autosave was rotated out")
	world.iron_run_lost()


func test_music_and_sfx_buses_and_the_colour_palette_are_settings() -> void:
	assert_true(AudioServer.get_bus_index(AudioDirector.BUS_MUSIC) >= 0, "the Music bus exists")
	assert_true(AudioServer.get_bus_index(AudioDirector.BUS_SFX) >= 0, "the SFX bus exists")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioDirector.BUS_MUSIC)), &"Master")
	assert_eq(world.audio._music_a.bus, &"Music")
	assert_eq(world.audio._pool[0].bus, &"SFX")
	var before := AudioServer.bus_count
	AudioDirector.ensure_buses()
	assert_eq(AudioServer.bus_count, before, "made once")
	var s := Settings.new()
	assert_eq(s.music_db, 0.0)
	assert_eq(s.palette, "normal")
	s.step_music(-2)
	s.step_sfx(-1)
	s.cycle_palette(1)
	s.cycle_palette(1)
	assert_eq(s.music_db, -6.0)
	assert_eq(s.sfx_db, -3.0)
	assert_eq(s.palette, "deuteranopia")
	assert_eq(Settings.percent_of(-6.0), 80)
	assert_eq(s.save(SETTINGS_PATH), OK)
	var back := Settings.load_or_default(SETTINGS_PATH)
	assert_eq(back.music_db, -6.0)
	assert_eq(back.sfx_db, -3.0)
	assert_eq(back.palette, "deuteranopia")
	assert_eq(Settings.from_dict({"palette": "octarine", "music_db": -99.0}).palette, "normal")
	assert_eq(Settings.from_dict({"music_db": -99.0}).music_db, Settings.VOLUME_MIN_DB)
	back.apply()
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioDirector.BUS_MUSIC)), -6.0, "the bus follows the setting")
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioDirector.BUS_SFX)), -3.0)
	Settings.new().apply()
	# The palette is one full-screen pass, hidden when normal.
	assert_false(world.color_filter.visible)
	world.color_filter.set_mode("tritanopia")
	assert_true(world.color_filter.visible)
	assert_eq(world.color_filter.mode, "tritanopia")
	assert_eq(int(world.color_filter.material_ref.get_shader_parameter("mode")), 3)
	world.color_filter.set_mode("nonsense")
	assert_eq(world.color_filter.mode, "normal")
	assert_false(world.color_filter.visible)
	assert_eq(ColorFilter.cycle("normal", -1), "tritanopia")
	assert_eq(world.color_filter.layer, 100, "above everything")
	assert_eq(world.color_filter.rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	# The settings screen is grouped and explains itself.
	var rows := SettingsMenu.build_rows(world.settings)
	var sections: Array[String] = []
	for r: Dictionary in rows:
		var section := String(r.get("section", ""))
		if not section.is_empty() and not sections.has(section):
			sections.append(section)
		assert_false(String(r.get("hint", "")).is_empty() , "%s has a hint" % r["id"])
	assert_eq(sections, ["Display", "Audio", "Pad", "Saves", "Bindings"])
	var music_row := 0
	for i: int in rows.size():
		if String(rows[i]["id"]) == "music":
			music_row = i
	var text := SettingsMenu.render(rows, music_row, "")
	assert_contains(text, "Display\n")
	assert_contains(text, "▶ Music: 100%")
	assert_contains(text, "The music on its own.")
	assert_false(SettingsMenu.render(rows, music_row, "confirm").contains("The music on its own."), "no hint while rebinding")
