## Campaign tooling v2 (S36, D-091): quest branches that fork a stage on
## conditions, with `next` as the fallback and pure fork stages that need
## no objectives. Fixture quests are put into the scene registry under
## ids no content uses.
extends TestCase

const LEDGER := "user://test_ledger_tooling.json"
const SAVES := "user://test_saves_tooling"

const FORK: Dictionary = {
	"name": "The Choosing (fixture)", "start": "gather", "auto_start": false,
	"stages": {
		"gather": {
			"summary": "Find out who wants the Keys.",
			"objectives": [{"text": "Hear the three offers", "done_when": {"flags": {"fx_offers_heard": true}}}],
			"next": "undecided",
			"next_toast": "Nobody has your oath yet.",
			"branches": [
				{"when": {"faction": "lattice"}, "next": "with_lattice", "toast": "The Lattice provides the map."},
				{"when": {"faction": "rootched"}, "next": "with_rootched"},
				{"when": {"faction": "ashfound"}, "next": "with_ashfound"},
			],
		},
		"undecided": {"summary": "Three doors, none opened.", "objectives": [{"text": "Swear to a faction", "done_when": {"flags": {"faction_locked": true}}}], "branches": [
			{"when": {"faction": "lattice"}, "next": "with_lattice"},
			{"when": {"faction": "rootched"}, "next": "with_rootched"},
			{"when": {"faction": "ashfound"}, "next": "with_ashfound"},
		]},
		"with_lattice": {"summary": "Order.", "complete": true},
		"with_rootched": {"summary": "The seed.", "complete": true},
		"with_ashfound": {"summary": "The fire.", "complete": true},
	},
}
const SPLIT: Dictionary = {
	"name": "A pure fork (fixture)", "start": "fork", "auto_start": false,
	"stages": {
		"fork": {"summary": "Which of them is still alive?", "branches": [
			{"when": {"flags": {"fx_sera_dead": true}}, "next": "mourn"},
			{"when": {"recruited": "sera"}, "next": "with_sera"},
		]},
		"mourn": {"summary": "Without her.", "complete": true},
		"with_sera": {"summary": "With her.", "complete": true},
	},
}

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.combat.animate = false
	world.registry.put("quests", "fx_choosing", FORK)
	world.registry.put("quests", "fx_split", SPLIT)


func after_each() -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(world)
	world.free()
	_cleanup()


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


func test_a_stage_forks_three_ways_on_the_oath_and_falls_back_otherwise() -> void:
	for id: String in ["lattice", "rootched", "ashfound"]:
		var n := NarrativeState.new()
		world.narrative = n
		n.set_stage("fx_choosing", "gather")
		assert_eq(world.advance_quests(), [], "objectives not done: nothing moves")
		n.set_flag("fx_offers_heard", true)
		n.set_flag("act2", true)
		assert_eq(world.join_faction(id), "")
		assert_eq(n.stage_of("fx_choosing"), "with_%s" % id, "the %s branch" % id)
	# No oath: the fallback `next`, with its own toast.
	var n := NarrativeState.new()
	world.narrative = n
	n.set_stage("fx_choosing", "gather")
	n.set_flag("fx_offers_heard", true)
	assert_eq(world.advance_quests(), ["fx_choosing"])
	assert_eq(n.stage_of("fx_choosing"), "undecided", "no branch held: the fallback")
	# The undecided stage waits on the oath and then forks by it at the next beat.
	n.set_flag("act2", true)
	assert_eq(world.join_faction("rootched"), "")
	assert_eq(n.stage_of("fx_choosing"), "with_rootched", "joining autosaves, the autosave advances, the branch fires")


func test_a_pure_fork_stage_needs_no_objectives_and_the_first_branch_wins() -> void:
	var n := world.narrative
	n.set_stage("fx_split", "fork")
	assert_eq(world.advance_quests(), [], "no branch holds: the fork waits")
	assert_eq(n.stage_of("fx_split"), "fork")
	n.recruit("sera")
	assert_eq(world.advance_quests(), ["fx_split"])
	assert_eq(n.stage_of("fx_split"), "with_sera")
	var m := NarrativeState.new()
	world.narrative = m
	m.set_stage("fx_split", "fork")
	m.recruit("sera")
	m.set_flag("fx_sera_dead", true)
	world.advance_quests()
	assert_eq(m.stage_of("fx_split"), "mourn", "branches are ordered: the death is checked first")
	# A branch to a stage that does not exist is ignored, not a crash.
	world.registry.put("quests", "fx_bad", {"name": "bad", "start": "a", "stages": {"a": {"summary": "", "branches": [{"when": {}, "next": "nowhere"}]}}})
	m.set_stage("fx_bad", "a")
	assert_eq(world.advance_quests(), [])
	assert_eq(m.stage_of("fx_bad"), "a")


func test_branch_stages_survive_a_save_and_show_in_the_journal() -> void:
	var n := world.narrative
	n.set_stage("fx_choosing", "gather")
	n.set_flag("fx_offers_heard", true)
	n.set_flag("act2", true)
	assert_eq(world.join_faction("ashfound"), "")
	assert_eq(n.stage_of("fx_choosing"), "with_ashfound")
	assert_contains(world.journal_text(), "The fire.")
	assert_eq(world.save_slot(1), OK)
	assert_eq(world.load_slot(1), [])
	assert_eq(world.narrative.stage_of("fx_choosing"), "with_ashfound")



# --- scripted sequences, map edits, endings (S36, D-091) ---------------------

func test_a_scripted_sequence_runs_its_steps_moves_the_camera_and_hands_over() -> void:
	assert_true(world.enter_map("gate_road"))
	var steps: Array = [
		{"camera": [12, 4], "toast": "The gate shudders.", "pause": 0.5},
		{"flags": {"fx_seq_mid": true}, "map_edits": [{"cell": [12, 3], "tile": "debris"}], "pause": 0.5},
		{"camera": "leader", "flags": {"fx_seq_end": true}},
	]
	assert_eq(await world.run_sequence(steps), 3, "instant under tests: every step ran")
	assert_true(world.narrative.flag("fx_seq_mid") and world.narrative.flag("fx_seq_end"))
	assert_eq(world.last_sequence.size(), 3)
	assert_eq(world.last_sequence[0]["camera"], Vector2i(12, 4), "the camera went to the gate")
	assert_eq(world.last_sequence[2]["camera"], world.leader_cell(), "and back to the leader")
	assert_eq(world.camera.target, world.party.leader())
	assert_true(world.party.active, "control returns")
	assert_false(world.sequence_running)
	assert_false(world.map_data.is_walkable(Vector2i(12, 3)), "the edit landed mid-sequence")
	# A fight step ends the sequence: what follows waits for the world.
	var fight: Array = [
		{"flags": {"fx_pre_fight": true}},
		{"enemies": [{"type": "scav", "cell": [14, 4]}]},
		{"flags": {"fx_after_fight": true}},
	]
	world.teleport_party(Vector2i(12, 4))
	assert_eq(await world.run_sequence(fight), 2, "stops at the fight")
	assert_eq(world.mode, "combat")
	assert_true(world.narrative.flag("fx_pre_fight"))
	assert_false(world.narrative.flag("fx_after_fight"), "the step after the fight never ran")
	assert_false(world.party.active)


func test_a_trigger_can_carry_a_sequence_and_blocks_input_while_it_runs() -> void:
	world.registry.put("maps", "fx_seq_map", {
		"name": "Sequence yard", "biome": "rusted_undercity", "spawn_marker": "P",
		"legend": {".": "floor_concrete", "#": "wall_rust", "P": "floor_concrete"},
		"rows": ["########", "#PP....#", "#PP....#", "#......#", "########"],
		"triggers": [{"id": "quake", "cell": [4, 2], "once": true, "effects": {"sequence": [
			{"camera": [6, 1], "toast": "Something under the floor.", "flags": {"fx_quake_seen": true}},
			{"map_edits": [{"cell": [6, 1], "tile": "debris"}, {"map": "gate_road", "cell": [5, 5], "tile": "debris"}], "flags": {"fx_quake_done": true}},
		]}}],
	})
	assert_true(world.enter_map("fx_seq_map"))
	world.teleport_party(Vector2i(4, 2))
	assert_eq(world.check_triggers(), 1)
	assert_true(world.narrative.flag("fx_quake_seen") and world.narrative.flag("fx_quake_done"))
	assert_false(world.map_data.is_walkable(Vector2i(6, 1)), "edited here")
	assert_eq(world.check_triggers(), 0, "once")
	# The edit on another map waits there.
	assert_true(world.enter_map("gate_road"))
	assert_false(world.map_data.is_walkable(Vector2i(5, 5)), "the remote edit applied on arrival")
	# Input is ignored while a sequence runs.
	world.sequence_running = true
	var ev := InputEventAction.new()
	ev.action = "journal"
	ev.pressed = true
	world._unhandled_input(ev)
	assert_false(world.journal_menu.visible, "no menus mid-sequence")
	world.sequence_running = false


func test_map_edits_persist_across_re_entry_and_saves_and_never_touch_shards() -> void:
	assert_true(world.enter_map("gate_road"))
	assert_true(world.map_data.is_walkable(Vector2i(3, 6)))
	assert_true(world.apply_map_edit({"cell": [3, 6], "tile": "debris"}))
	assert_false(world.map_data.is_walkable(Vector2i(3, 6)))
	assert_true(world.apply_map_edit({"cell": [3, 6], "tile": "floor_concrete"}), "the latest edit of a cell wins")
	assert_true(world.map_data.is_walkable(Vector2i(3, 6)))
	assert_eq(Array(world.narrative.map_edits["gate_road"]).size(), 1)
	assert_true(world.apply_map_edit({"cell": [3, 6], "tile": "debris"}))
	assert_false(world.apply_map_edit({"cell": [3, 6], "tile": "no_such_tile"}))
	assert_false(world.apply_map_edit({"map": "nowhere", "cell": [1, 1], "tile": "debris"}))
	assert_true(world.enter_map("bastion"))
	assert_true(world.enter_map("gate_road"))
	assert_false(world.map_data.is_walkable(Vector2i(3, 6)), "re-entry keeps the edit")
	assert_eq(world.save_slot(1), OK)
	assert_eq(world.load_slot(1), [])
	assert_false(world.map_data.is_walkable(Vector2i(3, 6)), "a save keeps the edit")
	world.enter_shard("rusted_undercity", 7)
	var before := world.narrative.map_edits.duplicate(true)
	assert_true(world.apply_map_edit({"map": "gate_road", "cell": [2, 6], "tile": "debris"}), "an edit aimed at a map from inside a Shard is recorded")
	assert_true(world.narrative.map_edits != before)


func test_endings_resolve_by_priority_and_conditions() -> void:
	var r := world.registry
	assert_eq(r.count("endings"), 5)
	world.narrative = NarrativeState.new()
	assert_eq(String(world.resolve_ending()["id"]), "drift", "sworn to nobody: the drift")
	for id: String in ["lattice", "rootched", "ashfound"]:
		var n := NarrativeState.new()
		n.faction = id
		world.narrative = n
		assert_eq(String(r.get_entry("endings", String(world.resolve_ending()["id"]))["when"]["faction"]), id, "the %s ending" % id)
	# The Weaver's Mend needs every Key, a spared fragment and a loyal party, and beats a faction ending.
	var m := NarrativeState.new()
	m.faction = "lattice"
	for k: String in ["key_lattice", "key_rootched", "key_ashfound", "choir_spared"]:
		m.set_flag(k, true)
	m.recruit("sera")
	m.recruit("kaj7")
	m.add_approval("sera", 5)
	m.add_approval("kaj7", 4)
	world.narrative = m
	assert_eq(String(world.resolve_ending()["id"]), "lattice_order", "one companion under the loyalty bar")
	m.add_approval("kaj7", 1)
	assert_eq(String(world.resolve_ending()["id"]), "weavers_mend")
	m.set_flag("choir_spared", false)
	assert_eq(String(world.resolve_ending()["id"]), "lattice_order", "the fragment was not spared")
	# Fates follow the story.
	m.set_flag("choir_spared", true)
	m.set_flag("kaj7_dead", true)
	m.dismiss("kaj7")
	var mend := r.get_entry("endings", "weavers_mend")
	var fates := Endings.fates(r, mend, m)
	assert_eq(fates.size(), 2, "Sera alive, Kaj-7 dead, Dax absent: %s" % [fates])
	assert_true(fates[0].begins_with("Kaj-7: The Choir remembers Kaj-7."), "companions come in id order: %s" % [fates])
	assert_true(fates[1].begins_with("Sera: Sera stays."))
	assert_true(Conditions.passes({"party_approval_min": 5}, {"narrative": NarrativeState.new()}), "nobody recruited: nobody below the bar")


func test_the_ending_effect_shows_the_panel_once_and_flags_it() -> void:
	world.narrative.faction = "ashfound"
	world.narrative.set_flag("act2", true)
	world.narrative.recruit("dax")
	world.respawn_party()
	world.apply_effects({"ending": true})
	assert_true(world.ending_menu.visible)
	assert_contains(world.ending_menu.label.text, "THE FIRE")
	assert_contains(world.ending_menu.label.text, "Dax: Dax's family came up out of the vault into the cold. They are alive.")
	assert_true(world.narrative.flag("ending_ashfound_fire") and world.narrative.flag("ending_seen"))
	world.close_ending()
	assert_false(world.ending_menu.visible)
	assert_false(world.show_ending(), "once")
	assert_eq(world.save_slot(2), OK)
	assert_eq(world.load_slot(2), [])
	assert_true(world.narrative.flag("ending_ashfound_fire"))
