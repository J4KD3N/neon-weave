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
