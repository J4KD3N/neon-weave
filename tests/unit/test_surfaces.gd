## Dialogue and journal surfaces (S52, D-107): every text panel has a face
## and a history. Faces for speakers (the leader, companions by race and
## class, NPCs by colour, none for the narrator, the voice's face when the
## speaker has none); the history of lines said, choices
## made and quests moved, shown in the panel and the journal and carried
## by the save; the tracked quest on the HUD; the Roster and the Quarters
## as one screen.
extends TestCase

const LEDGER := "user://test_ledger_surfaces.json"
const SAVES := "user://test_saves_surfaces"
const ACCOUNT := "user://test_account_surfaces.json"

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


func _raise(id: String, to: int) -> void:
	world.ledger.buildings[id] = to
	world.bastion.setup(world.registry.get_all("buildings"), world.ledger.buildings)


func _row(rows: Array[Dictionary], id: String) -> Dictionary:
	for r: Dictionary in rows:
		if String(r.get("id", "")) == id:
			return r
	return {}


func test_every_speaker_with_a_body_has_a_face() -> void:
	assert_true(world.portrait_for("player") != null, "the leader")
	assert_true(world.portrait_for("sera") != null, "a companion")
	assert_true(world.portrait_for("pell") != null, "an NPC by its art colour")
	assert_true(world.portrait_for("sera") == world.portrait_for("sera"), "built once")
	assert_true(world.portrait_for("narrator") == null, "the narrator has no face")
	assert_true(world.portrait_for("choir") != null, "the Choir has an NPC entry, so a face of its colour")
	assert_true(world.portrait_for("nobody") == null, "no entry, no face")
	assert_true(world.portrait_for("") == null)
	assert_true(world.face_for("nobody", "sera") == world.portrait_for("sera"), "a speaker without a face wears the voice's")
	assert_true(world.face_for("choir", "sera") == world.portrait_for("choir"), "a speaker with a face keeps it")
	assert_true(world.face_for("narrator") == null)
	var pell := world.portrait_for("pell").get_image()
	assert_eq(pell.get_size(), PlaceholderActorArt.PORTRAIT_SIZE)
	var shoulder := pell.get_pixel(32, 60)
	assert_true(shoulder.is_equal_approx(Color.html("#e0c07a")), "Pell's shoulders are her colour: %s" % shoulder)
	# The panel wears it.
	assert_true(world.open_dialogue("sera_recruit"))
	assert_true(world.dialogue_menu.portrait.visible)
	assert_true(world.dialogue_menu.portrait.texture == world.portrait_for("sera"))
	world.leave_dialogue()


func test_the_history_records_lines_choices_and_rides_the_save() -> void:
	assert_eq(world.narrative.log, [])
	assert_true(world.open_dialogue("sera_recruit"))
	assert_eq(world.narrative.log.size(), 1, "the first line is history as soon as it is said")
	assert_eq(String(world.narrative.log[0]["who"]), "Sera")
	assert_eq(world.talk_history(), [], "the line on screen is not history yet")
	assert_false(world.dialogue_menu.label.text.contains("‹"))
	var first_text := String(world.narrative.log[0]["text"])
	assert_true(world.choose(0))
	assert_true(world.narrative.log.size() >= 2, "the choice is history")
	assert_eq(String(world.narrative.log[1]["who"]), world.party.leader().display_name)
	assert_true(String(world.narrative.log[1]["text"]).begins_with("→ "))
	if world.in_dialogue():
		assert_eq(world.narrative.log.size(), 3, "and so is the next line")
		assert_eq(world.talk_history().size(), 2)
		assert_contains(world.dialogue_menu.label.text, "‹ Sera: %s" % first_text.substr(0, 20), "the panel shows what was said")
		assert_contains(world.dialogue_menu.label.text, "‹ %s: → " % world.party.leader().display_name)
	while world.in_dialogue():
		world.choose(0)
	var lines := world.narrative.log.size()
	assert_true(lines >= 3)
	# The journal shows it.
	assert_true(world.open_journal())
	assert_contains(world.journal_menu.label.text, "History")
	assert_contains(world.journal_menu.label.text, "Sera: %s" % first_text.substr(0, 20))
	world.close_journal()
	# It rides the save.
	assert_eq(world.save_slot(1), OK)
	world.narrative.log.clear()
	assert_eq(world.load_slot(1), [])
	assert_eq(world.narrative.log.size(), lines, "the history rides the save")
	assert_eq(String(world.narrative.log[0]["text"]), first_text)
	# It is capped.
	for i: int in NarrativeState.LOG_MAX + 30:
		world.narrative.log_line("Test", "line %d" % i)
	assert_eq(world.narrative.log.size(), NarrativeState.LOG_MAX)
	assert_eq(String(world.narrative.log[NarrativeState.LOG_MAX - 1]["text"]), "line %d" % (NarrativeState.LOG_MAX + 29))
	world.narrative.log_line("Test", "   ")
	assert_eq(world.narrative.log.size(), NarrativeState.LOG_MAX, "blank lines are not history")
	# A talk that starts later only shows its own lines.
	assert_true(world.open_dialogue("sera_recruit"))
	assert_eq(world.talk_history(), [])
	world.leave_dialogue()


func test_the_hud_tracks_a_quest_and_the_journal_moves_the_mark() -> void:
	assert_true(world.new_game(false))
	assert_eq(world.tracked_quest_id(), "main_waking", "the main quest by default")
	assert_eq(world.narrative.tracked_quest, "main_waking", "and the default sticks")
	var line := world.tracking_line()
	assert_contains(line, "★ The Waking — The gate road east of the yard is sealed")
	assert_contains(line, "· Pull the relay lever")
	assert_contains(world.status_line(), line, "on the HUD")
	assert_eq(world.status_line().split("\n").size(), 4)
	# A second active quest: the Choir's courting, by its start condition, writes to the history too.
	var before := world.narrative.log.size()
	world.narrative.set_flag("act2", true)
	assert_true(world.advance_quests().has("choir_courting"))
	assert_eq(world.narrative.log.size(), before + 1, "a quest that starts is history")
	assert_eq(String(world.narrative.log[before]["who"]), "Journal")
	assert_contains(String(world.narrative.log[before]["text"]), "Stolen Voices — The singing did not stop")
	assert_eq(world.tracked_quest_id(), "main_waking", "the mark stays where it was")
	assert_eq(world.track_next_quest(1), "choir_courting")
	assert_eq(world.narrative.tracked_quest, "choir_courting")
	assert_contains(world.tracking_line(), "★ Stolen Voices —")
	assert_eq(world.track_next_quest(1), "main_waking", "wraps")
	assert_eq(world.track_next_quest(-1), "choir_courting")
	# The journal marks it and ←→ moves it.
	assert_true(world.open_journal())
	assert_contains(world.journal_menu.label.text, "▶ ★ Stolen Voices  (tracked)")
	assert_contains(world.journal_menu.label.text, "  ★ The Waking\n")
	world.track_next_quest(1)
	assert_contains(world.journal_menu.label.text, "▶ ★ The Waking  (tracked)", "the journal follows the mark")
	world.close_journal()
	# The mark rides the save and falls back when its quest is done.
	world.narrative.tracked_quest = "choir_courting"
	assert_eq(world.save_slot(2), OK)
	world.narrative.tracked_quest = ""
	assert_eq(world.load_slot(2), [])
	assert_eq(world.tracked_quest_id(), "choir_courting")
	world.narrative.tracked_quest = "no_such_quest"
	assert_eq(world.tracked_quest_id(), "choir_courting", "an unknown mark falls back to the first active main quest")
	world.narrative.quests.clear()
	assert_eq(world.tracked_quest_id(), "")
	assert_eq(world.tracking_line(), "")
	assert_eq(world.status_line().split("\n").size(), 3, "no line when nothing is tracked")


func test_the_roster_and_the_quarters_are_one_screen() -> void:
	assert_true(world.new_game(false))
	assert_false(world.open_roster(), "nobody recruited, nobody fallen")
	for id: String in ["sera", "dax"]:
		world.narrative.recruit(id)
		assert_true(world.add_companion(id))
	assert_true(world.enter_map("bastion"))
	assert_true(world.open_roster())
	assert_true(world.roster_menu.visible)
	var rows := world.roster_menu.rows
	assert_eq(String(rows[0]["id"]), "companion:dax", "companions in registry order")
	assert_eq(String(rows[1]["id"]), "companion:sera")
	assert_contains(String(rows[1]["label"]), "Sera — walks with you · ♥+0")
	assert_true(rows[1]["portrait"] != null, "a face per companion")
	assert_true(world.roster_menu.portrait.visible)
	assert_true(world.roster_menu.portrait.texture == rows[0]["portrait"], "the cursor's face")
	assert_false(_row(rows, "note").is_empty(), "no Quarters yet: a note")
	assert_contains(world.roster_menu.label.text, "raise the Quarters")
	# Enter on a companion: she waits; ←→ on the next: he waits too; then the party is full.
	world.roster_menu.cursor = 1
	assert_true(world.activate_roster_row())
	assert_true(world.narrative.is_benched("sera"))
	assert_true(world.roster_menu.visible, "the screen stays open")
	assert_eq(world.roster_menu.cursor, 1, "and keeps its place")
	assert_contains(world.roster_menu.label.text, "Sera — waits at the Bastion")
	assert_true(world.roster_toggle(), "Enter or ←→ again: she walks")
	assert_false(world.narrative.is_benched("sera"))
	world.close_roster()
	assert_false(world.roster_menu.visible)
	# The Quarters: scenes under their companion, Enter plays one.
	_raise("quarters", 1)
	world.narrative.add_approval("sera", 3)
	assert_true(world.open_quarters(), "the Bastion's Quarters item opens the same screen")
	rows = world.roster_menu.rows
	assert_true(_row(rows, "note").is_empty(), "the note is gone")
	var scene := _row(rows, "scene:sera_quarters")
	assert_false(scene.is_empty(), "Sera's scene sits under her")
	assert_eq(rows.find(scene), rows.find(_row(rows, "companion:sera")) + 1)
	assert_contains(String(scene["label"]), "↳ ")
	world.roster_menu.cursor = rows.find(scene)
	world.roster_menu.refresh()
	assert_true(world.roster_menu.portrait.texture == _row(rows, "companion:sera")["portrait"], "a scene row shows its companion's face")
	assert_true(world.activate_roster_row())
	assert_false(world.roster_menu.visible, "the screen closes for the scene")
	assert_true(world.in_dialogue())
	assert_true(world.narrative.flag("scene_sera_quarters_seen"))
	while world.in_dialogue():
		world.choose(0)
	# Loyalty and romance are on the row; the fallen are listed with their scenes.
	world.narrative.set_flag("sera_loyal", true)
	world.narrative.commit_romance("sera")
	assert_true(world.open_roster())
	assert_contains(String(_row(world.roster_menu.rows, "companion:sera")["label"]), "· your partner · loyal")
	world.close_roster()
	world.narrative.dismiss("sera")
	world.narrative.set_flag("sera_dead", true)
	world.narrative.lose_romance("sera")
	world.respawn_party()
	assert_true(world.open_roster())
	var fallen := _row(world.roster_menu.rows, "companion:sera")
	assert_contains(String(fallen["label"]), "Sera — fallen")
	assert_contains(String(fallen["label"]), "what was")
	world.roster_menu.cursor = world.roster_menu.rows.find(fallen)
	assert_false(world.roster_toggle(), "the fallen do not walk")
	assert_false(_row(world.roster_menu.rows, "scene:sera_lost").is_empty(), "the empty bunk is under her")
	# Done closes; the Roster is a home thing; the system menu item says so.
	world.roster_menu.cursor = world.roster_menu.rows.size() - 1
	assert_true(world.activate_roster_row())
	assert_false(world.roster_menu.visible)
	assert_contains(String(_row(world.system_items(), "roster")["label"]), "Roster & Quarters")
	world.enter_shard("rusted_undercity", 3)
	assert_false(world.open_roster())
	assert_false(bool(_row(world.system_items(), "roster")["enabled"]))
