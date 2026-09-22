## The playtest kit (S47, D-102): with a log attached the world writes one
## JSON line per map, fight, run, choice and ending; the report turns a
## folder of logs into the triage table with the harness band beside each
## story fight; nothing is written without the flag.
extends TestCase

const LEDGER := "user://test_ledger_playtest.json"
const SAVES := "user://test_saves_playtest"
const LOGS := "user://test_playtest_logs"

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
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	for dir: String in [SAVES, LOGS]:
		var d := DirAccess.open(dir)
		if d != null:
			for f: String in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


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


func _win() -> void:
	var s := world.combat.state
	for c: Combatant in s.combatants:
		if c.team == Combatant.TEAM_ENEMY:
			c.hp = 0
	s._check_outcome()
	if world.mode == "combat":
		world._on_combat_ended("victory")


func test_nothing_is_written_without_the_flag() -> void:
	assert_true(world.playtest == null, "off by default")
	world.enter_map("proto_yard")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LOGS)))


func test_the_log_records_what_the_harness_measures_and_the_report_reads_it() -> void:
	var log := PlaytestLog.new()
	log.start(LOGS, "test")
	world.playtest = log
	assert_true(FileAccess.file_exists(log.path), "the session file exists at start")
	# A fight on a story map, by fiat.
	world.narrative.recruit("sera")
	world.narrative.recruit("dax")
	world.respawn_party()
	world.narrative.set_flag("gate_open", true)
	assert_true(world.enter_map("gate_road"))
	world.teleport_party(Vector2i(12, 4))
	world.check_triggers()
	assert_eq(world.mode, "combat")
	_win()
	# A dialogue choice.
	assert_true(world.enter_map("proto_yard"))
	assert_true(world.talk_to("sera"))
	assert_true(world.choose(0))
	world.leave_dialogue()
	# A run, extracted, and a run wiped.
	world.enter_shard("rusted_undercity", 7)
	world.run.haul["salvage"] += 5
	world.teleport_party(world.extraction_cell())
	assert_true(world.extract())
	world.enter_shard("rusted_undercity", 8)
	for m: PartyMember in world.party.members:
		m.hp = 0
		m.downed = true
	world.mode = "combat"
	world._on_combat_ended("defeat")
	world.return_home()
	# An ending.
	world.narrative.set_flag("loom_drift", true)
	world.apply_effects({"ending": true})
	world.close_ending()
	assert_true(log.lines_written >= 9, "%d lines" % log.lines_written)
	var records := PlaytestReport.load_records(LOGS)
	var events: Array[String] = []
	for r: Dictionary in records:
		events.append(String(r["event"]))
	assert_eq(events[0], "start")
	for needed: String in ["map", "fight", "choice", "run", "ending"]:
		assert_true(events.has(needed), "a %s record" % needed)
	var fight: Dictionary = {}
	var runs: Array = []
	for r: Dictionary in records:
		if r["event"] == "fight" and fight.is_empty(): # the first: the gate ambush; the wipe is the second
			fight = r
		if r["event"] == "run":
			runs.append(r)
	assert_eq(String(fight["map"]), "gate_road")
	assert_eq(String(fight["result"]), "victory")
	assert_true(Array(fight["enemies"]).size() >= 2 and Array(fight["enemies"]).has("scav"), "enemy kinds: %s" % [fight["enemies"]])
	assert_true(float(fight["hp_left"]) > 0.0 and int(fight["party"]) == 3)
	assert_eq(runs.size(), 2)
	assert_eq(String(runs[0]["outcome"]), "extracted")
	assert_eq(int(Dictionary(runs[0]["haul"])["salvage"]), 5)
	assert_eq(String(runs[1]["outcome"]), "wiped")
	assert_true(records[records.size() - 1]["event"] == "ending" and records[records.size() - 1]["ending"] == "drift")
	# The report.
	var report := PlaytestReport.build(LOGS)
	assert_contains(report, "1 session, ")
	assert_contains(report, "gate_road: ")
	assert_contains(report, "win 100%")
	assert_contains(report, "[gate ambush 85–100%]", "the harness band beside the story fight")
	assert_contains(report, "rusted_undercity d1")
	assert_contains(report, "extracted  50%")
	assert_contains(report, "sera_recruit/recruited", "the choice by dialogue and node")
	assert_contains(report, "gate_road 0")
	assert_contains(report, "ENDINGS  {")
	assert_contains(report, "drift")
	assert_contains(PlaytestReport.build("user://no_such_logs"), "no logs found")
