## Localization scaffolding (S55, D-110): every string through a table
## (UI by its English source, content by kind.id.path), locales as content
## entries a mod can ship, the pseudo-locale that wraps every string it
## sees, and the test that runs every screen in it and finds what did not
## come through.
extends TestCase

const LEDGER := "user://test_ledger_loc.json"
const SAVES := "user://test_saves_loc"
const ACCOUNT := "user://test_account_loc.json"

var world: ExploreWorld
var _leaks: PackedStringArray = []


func before_each() -> void:
	_cleanup()
	Loc.set_locale(Loc.DEFAULT)
	world = _fresh()


func after_each() -> void:
	world.settings.locale = Loc.DEFAULT
	world.settings.apply()
	Loc.set_locale(Loc.DEFAULT)
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
	w.settings_path = "user://test_settings_loc.json"
	w.input_path = "user://test_input_loc.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


## Records the plain-letter runs a screen still shows under the pseudo-locale.
func _check(screen: String, text: String) -> void:
	var words := Loc.untranslated(text)
	if not words.is_empty():
		_leaks.append("%s: %s" % [screen, ", ".join(words)])


func _entry(kind: String, id: String) -> Dictionary:
	return world.registry.get_entry(kind, id)


func test_the_pseudo_transform_marks_strings_and_keeps_format_tokens() -> void:
	assert_eq(Loc.pseudo("Save game"), "⟦Šåṽé ğåɱé⟧")
	assert_eq(Loc.pseudo("Slot %d — %s · %.1f ms · %+d · %-5s · 100%%"), "⟦Šłöŧ %d — %s · %.1f ɱš · %+d · %-5s · 100%%⟧")
	assert_eq(Loc.pseudo("Slot %d") % 3, "⟦Šłöŧ 3⟧", "formatting still works")
	assert_eq(Loc.pseudo("   "), "   ", "blank stays blank")
	assert_eq(Loc.untranslated("⟦ẋ⟧ 12 · ⟦⟦å⟧: ⟦ƀ⟧⟧ ▶ ↑↓"), [], "accented marks and symbols are clean")
	assert_eq(Loc.untranslated("plain ⟦öķ⟧ words"), ["plain", "words"])
	assert_eq(Loc.untranslated("⟦Ƒüłłšçřééñ: on⟧"), ["on"], "a plain word formatted into a translated frame is caught")


func test_tables_come_from_locales_entries_and_a_mod_can_add_one() -> void:
	assert_eq(Loc.available(), ["en", "pseudo"], "English first, pseudo last")
	assert_eq(Loc.name_of("en"), "English")
	assert_eq(Loc.name_of("pseudo"), "Pseudo-locale (test)")
	assert_eq(Loc.set_locale("xx"), "en", "an unknown locale is English")
	assert_eq(Loc.t("Back"), "Back", "English is the source")
	world.registry.put("locales", "fr", {"name": "Français", "ui": {"Back": "Retour", "Slot %d — %s": "Case %d — %s"}, "content": {"companions.sera.short_name": "Séra", "dialogue.sera_recruit.nodes.start.text": "Bonjour."}})
	Loc.load_from(world.registry)
	assert_eq(Loc.available(), ["en", "fr", "pseudo"])
	assert_eq(Loc.set_locale("fr"), "fr")
	assert_eq(Loc.t("Back"), "Retour")
	assert_eq(Loc.t("Slot %d — %s") % [2, "x"], "Case 2 — x")
	assert_eq(Loc.t("Not in the table"), "Not in the table", "missing means the source")
	assert_eq(Loc.text(_entry("companions", "sera"), "short_name"), "Séra")
	assert_eq(Loc.text(_entry("companions", "dax"), "short_name"), "Dax", "missing content means the source")
	assert_eq(Loc.content("dialogue", "sera_recruit", "nodes.start.text", "Hello."), "Bonjour.")
	assert_true(Loc.seen.has("Back"), "asked-for UI strings are remembered for the extraction tool")
	# The setting.
	world.settings.locale = "fr"
	world.settings.apply()
	assert_eq(Loc.locale, "fr")
	var rows := SettingsMenu.build_rows(world.settings)
	var label := ""
	for r: Dictionary in rows:
		if String(r["id"]) == "language":
			label = String(r["label"])
	assert_contains(label, "Français")
	world.settings.cycle_locale(1)
	assert_eq(world.settings.locale, "pseudo")
	world.settings.cycle_locale(1)
	assert_eq(world.settings.locale, "en", "wraps")
	world.settings.locale = "nope"
	world.settings.apply()
	assert_eq(world.settings.locale, "en", "an unknown saved locale becomes English")
	world.registry._entries["locales"].erase("fr")
	world.registry._fingerprint_cache = ""
	Loc.load_from(world.registry)
	assert_eq(Loc.available(), ["en", "pseudo"])
	# The extraction: every content text field, keyed.
	var strings := Loc.extract_content(world.registry)
	assert_true(strings.size() > 800, "%d content strings" % strings.size())
	print("  loc: %d content strings" % strings.size())
	assert_eq(String(strings.get("companions.sera.short_name", "")), "Sera")
	for key: String in ["dialogue.sera_recruit.nodes.greet.text", "quests.main_waking.stages.gate.objectives.0.text", "quests.main_waking.stages.gate.summary", "rules.credits.lines.0", "buildings.beacon.levels.0.blurb", "races.trueborn.identity"]:
		assert_true(strings.has(key), "extracted: " + key)
	assert_true(strings.has("endings.drift.epilogue.sera.alive") or strings.has("endings.drift.epilogue.sera.absent"), "epilogue lines")
	for key: String in strings:
		assert_true(key.split(".").size() >= 3, "keyed kind.id.path: %s" % key)


func test_every_screen_runs_in_the_pseudo_locale_with_no_untranslated_string() -> void:
	world.settings.locale = Loc.PSEUDO
	world.settings.apply()
	assert_true(Loc.is_pseudo())
	# The title, its pages, the creator.
	world.show_title()
	_check("title", world.title_menu.label.text)
	_check("title version", (world.title_menu.panel.get_child(0).get_child(1) as Label).text)
	world.title_menu.cursor = 0
	world.activate_title()
	_check("difficulty page", world.title_menu.label.text)
	world.title_menu.cursor = 0
	world.activate_title()
	_check("stakes page", world.title_menu.label.text)
	world.title_menu.cursor = 1
	world.activate_title()
	_check("creator", world.creator_menu.label.text)
	world.creator_state.row = world.creator_state.rows.find("origin")
	_check("creator origin row", world.creator_menu.label.text)
	world.creator_state.sheet.name = ""
	world.creator_menu.refresh()
	_check("creator error", world.creator_menu.label.text)
	world.creator_state.sheet.name = "Ķéšŧ" # a typed name is the player's, not a string of ours
	assert_true(world.confirm_creator())
	# Playing: the HUD, the pause menu, the saves, the settings, the journal.
	_check("status line", world.status_line())
	assert_true(world.open_system_menu())
	_check("pause menu", world.system_menu.label.text)
	assert_true(world.open_saves(SavesMenu.PAGE_SAVE))
	_check("save page", world.saves_menu.label.text)
	world.saves_menu.cursor = 0
	world.activate_saves_row()
	_check("save page after a save", world.saves_menu.label.text)
	world.activate_saves_row()
	_check("overwrite question", world.saves_menu.label.text)
	world.cancel_saves()
	assert_true(world.open_saves(SavesMenu.PAGE_LOAD))
	_check("load page", world.saves_menu.label.text)
	world.cancel_saves()
	assert_true(world.open_settings())
	_check("settings", world.settings_menu.label.text)
	for i: int in world.settings_menu.rows.size():
		world.settings_menu.cursor = i
		world.settings_menu.refresh()
		_check("settings row %s" % world.settings_menu.rows[i]["id"], world.settings_menu.label.text)
	world.settings_menu.rebinding = "confirm"
	world.settings_menu.refresh()
	_check("settings rebinding", world.settings_menu.label.text)
	world.settings_menu.rebinding = ""
	world.settings_menu.close() # not close_settings(): that would write the pseudo locale into the real settings file
	assert_true(world.open_journal())
	_check("journal", world.journal_menu.label.text)
	world.close_journal()
	# Talking: the panel with a face and a history.
	assert_true(world.open_dialogue("sera_recruit"))
	_check("dialogue", world.dialogue_menu.label.text)
	assert_true(world.choose(0))
	if world.in_dialogue():
		_check("dialogue with history", world.dialogue_menu.label.text)
	while world.in_dialogue():
		world.choose(0)
	assert_true(world.open_journal())
	_check("journal with history", world.journal_menu.label.text)
	world.close_journal()
	# The Bastion and its screens.
	for id: String in ["sera", "dax"]:
		world.narrative.recruit(id)
		world.add_companion(id)
	assert_true(world.enter_map("bastion"))
	assert_true(world.toggle_bastion())
	_check("bastion", world.bastion_menu.label.text)
	world.toggle_bastion()
	assert_true(world.open_roster())
	_check("roster", world.roster_menu.label.text)
	world.close_roster()
	assert_true(world.open_weave())
	_check("weave", world.weave_menu.label.text)
	world.close_weave()
	assert_true(world.open_inventory())
	_check("inventory", world.inventory_menu.label.text)
	world.close_inventory()
	world.ledger.buildings["archive"] = 1
	world.bastion.setup(world.registry.get_all("buildings"), world.ledger.buildings)
	assert_true(world.open_archive())
	_check("archive", world.archive_menu.label.text)
	world.close_archive()
	# A Shard, a fight, the combat HUD.
	seed(20260922)
	assert_false(world.enter_shard("rusted_undercity", 7, 1).is_empty())
	_check("shard status line", world.status_line())
	var foe: EnemyActor = null
	for e: EnemyActor in world.living_enemies():
		foe = e
		break
	assert_true(foe != null, "a fight to pick")
	world.teleport_party(foe.cell + Vector2i(1, 0) if world.map_data.is_walkable(foe.cell + Vector2i(1, 0)) else world.map_data.nearest_free_cells(foe.cell, 1, [])[0])
	world.start_combat(true)
	assert_eq(world.mode, "combat")
	_check("combat turn", world.hud.turn_label.text)
	_check("combat order", world.hud.order_label.text)
	_check("combat hint", world.hud.hint_label.text)
	_check("combat log", world.hud.log_label.text)
	_check("combat end button", world.hud.end_button.text)
	for b: Button in world.hud._buttons:
		_check("ability button", b.text)
	_check("combat status line", world.status_line())
	# The endings and the demo boundary.
	var drift := _entry("endings", "drift")
	_check("ending", EndingMenu.render(drift, Endings.fates(world.registry, drift, world.narrative), world.demo_stats(), Endings.modifiers(drift, world.dialogue_ctx()), world.credit_lines()))
	_check("demo end", DemoEndMenu.render(world.demo_stats()))
	assert_eq(_leaks, PackedStringArray(), "every screen came through the table:\n" + "\n".join(_leaks))
