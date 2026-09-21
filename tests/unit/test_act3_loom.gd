## Act 3 (S42, D-097): from the catastrophe to the Loom on every path. The
## Loom Approach opens on `loom_located`; its door site banks the haul and
## carries the party into the Loom; the rival factions' strike teams wait
## for everyone but their own; the Choir's Voice keeps the last door; the
## heart is a choice (spare or end the voice, then set the Loom), which
## fires the ending.
extends TestCase

const LEDGER := "user://test_ledger_act3.json"
const SAVES := "user://test_saves_act3"
const SET_CHOICE: Dictionary = {"lattice": "Order.", "rootched": "Completion.", "ashfound": "Ash.", "": "Leave it weaving"}
const ENDING_NAME: Dictionary = {"lattice": "ORDER", "rootched": "THE BLOOM", "ashfound": "THE FIRE", "": "THE DRIFT"}

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


func _choose_text(fragment: String) -> bool:
	var options := world.dialogue.available_choices()
	for i: int in options.size():
		if String(options[i]["text"]).contains(fragment):
			return world.choose(i)
	fail("no choice containing '%s' in %s" % [fragment, world.dialogue.node_id])
	return false


func _choice_texts() -> String:
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	return "\n".join(texts)


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry.get("pickups", []):
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


func _open_site(entry: Dictionary, pickup: String, dialogue_name: String) -> void:
	var site := _site_cell(entry, pickup)
	assert_true(site.x >= 0, "%s placed" % pickup)
	world.teleport_party(site)
	for _try: int in 6:
		if not world.in_dialogue():
			world.check_pickups()
		if not world.in_dialogue():
			world.teleport_party(site)
			world.check_pickups()
		assert_true(world.in_dialogue(), "a site opened for %s" % pickup)
		if String(world.dialogue.dialogue.get("name", "")) == dialogue_name:
			return
		while world.in_dialogue():
			world.choose(0)
	fail("%s never opened" % dialogue_name)


## The fall by fiat: Act 3's fights are the harness's and the M4 pass's to
## measure (`test_balance.gd` rows them); this test proves the wiring.
func _win() -> void:
	var s := world.combat.state
	assert_true(s != null and not s.finished, "a fight to win")
	if s != null and not s.finished:
		for c: Combatant in s.combatants:
			if c.team == Combatant.TEAM_ENEMY:
				c.hp = 0
		s._check_outcome()
	if world.mode == "combat":
		world._on_combat_ended("victory")
	assert_eq(world.mode, "explore", "the fight is won")
	for m: PartyMember in world.party.members:
		m.downed = false
		m.hp = m.max_hp


func _step_on(cell: Vector2i) -> void:
	world.teleport_party(cell)
	world.party.leader().position = world.map_view.cell_to_world(cell)
	world.check_triggers()


## A world just after the catastrophe on `faction`'s path, three Keys whole.
func _after_catastrophe(faction: String, companions: Array = ["sera", "kaj7", "dax"]) -> void:
	world.narrative = NarrativeState.new()
	for f: String in ["gate_lever_pulled", "gate_open", "road_end", "choir_contact", "act1_complete", "act2", "catastrophe_seen", "loom_located"]:
		world.narrative.set_flag(f, true)
	for k: String in ["lattice", "rootched", "ashfound"]:
		world.narrative.set_flag("key_%s" % k, true)
		world.narrative.set_flag("key_%s_resolved" % k, true)
		world.narrative.set_stage("delve_%s" % k, "taken")
	world.narrative.set_stage("main_waking", "choir")
	world.narrative.set_stage("the_loom", "located")
	if not faction.is_empty():
		world.narrative.join_faction(faction)
	for id: String in companions:
		world.narrative.recruit(id)
	world.ledger.xp = 900
	world.refresh_progression()
	world.respawn_party()
	assert_true(world.enter_map("bastion"), "world.enter_map('bastion')")


func _walk_the_loom(faction: String) -> void:
	assert_eq(world.map_id, "the_loom")
	assert_true(world.narrative.flag("loom_entered"), "the arrival trigger")
	assert_eq(world.narrative.stage_of("the_loom"), "loom", "the door stage handed off")
	var fights := 0
	for rival: String in ["lattice", "rootched", "ashfound"]:
		var column: int = {"lattice": 8, "rootched": 14, "ashfound": 20}[rival]
		_step_on(Vector2i(column, 6))
		if rival == faction:
			assert_eq(world.mode, "explore", "%s: your own faction does not strike you" % rival)
			continue
		assert_eq(world.mode, "combat", "%s path: the %s strike team" % [faction, rival])
		fights += 1
		_win()
		assert_true(world.narrative.flag("loom_rival_%s_beaten" % rival), "world.narrative.flag('loom_rival_%s_beaten' % rival)")
	assert_eq(fights, 2 if not faction.is_empty() else 3, "%s: rivals fought" % faction)
	_step_on(Vector2i(28, 6))
	assert_eq(world.mode, "explore", "the heart waits on the guard")
	assert_false(world.narrative.flag("loom_heart_reached"))
	_step_on(Vector2i(25, 6))
	assert_eq(world.mode, "combat", "the Voice at the last door")
	var boss := false
	for e: EnemyActor in world.living_enemies():
		if e.tier == "boss":
			boss = true
	assert_true(boss, "the Voice is a boss")
	_win()
	assert_true(world.narrative.flag("loom_guard_beaten"), "world.narrative.flag('loom_guard_beaten')")
	_step_on(Vector2i(28, 6))
	assert_true(world.narrative.flag("loom_heart_reached"), "world.narrative.flag('loom_heart_reached')")
	assert_true(world.in_dialogue(), "the heart speaks after the approach")
	assert_eq(world.dialogue.speaker(), "choir")


func test_the_loom_is_reached_from_the_catastrophe_on_every_path() -> void:
	var seed_value := 100
	for faction: String in ["lattice", "rootched", "ashfound", ""]:
		_after_catastrophe(faction)
		assert_eq(world.shard_locked_reason("loom_approach"), "", "%s: the Approach opens on loom_located" % faction)
		assert_true(world.quest_sites("loom_approach").has("loom_door"), "the door is placed in the Approach only")
		assert_false(world.quest_sites("rusted_undercity").has("loom_door"))
		seed_value += 1
		var entry := world.enter_shard("loom_approach", seed_value, 1)
		assert_true(world.run.in_shard, "world.run.in_shard")
		world.run.haul["salvage"] += 7
		_open_site(entry, "loom_door", "The Loom's door")
		if faction == "":
			assert_true(_choose_text("Not yet"), "_choose_text('Not yet')")
			assert_false(world.narrative.flag("loom_door_crossed"), "the door waits")
			assert_true(world.run.in_shard, "still in the Approach")
			var again := world.enter_shard("loom_approach", seed_value + 50, 1)
			assert_true(_site_cell(again, "loom_door").x >= 0, "the site comes back next run")
			world.run.haul["salvage"] += 7
			_open_site(again, "loom_door", "The Loom's door")
		var salvage_before: int = world.ledger.total("salvage")
		assert_true(_choose_text("Go through"), "through the door")
		assert_false(world.run.in_shard, "the run ended at the threshold")
		assert_true(world.ledger.total("salvage") >= salvage_before + 7, "and the haul banked")
		world.check_triggers() # the frame after arriving
		assert_true(world.narrative.flag("loom_door_crossed"), "world.narrative.flag('loom_door_crossed')")
		_walk_the_loom(faction)
		# The heart: spare the voice, set the Loom the path's way.
		assert_true(_choose_text("You are a voice"), "_choose_text('You are a voice')")
		assert_true(world.narrative.flag("choir_spared"), "world.narrative.flag('choir_spared')")
		assert_eq(world.dialogue.node_id, "set")
		var texts := _choice_texts()
		for other: String in SET_CHOICE:
			if other != faction and other != "":
				assert_false(texts.contains(String(SET_CHOICE[other])), "%s: no %s setting" % [faction, other])
		assert_true(texts.contains("Reweave it"), "%s: three whole Keys and a spared voice offer the Mend" % faction)
		assert_true(_choose_text(String(SET_CHOICE[faction])), "_choose_text(String(SET_CHOICE[faction]))")
		assert_false(world.in_dialogue())
		assert_true(world.narrative.flag("loom_set"), "world.narrative.flag('loom_set')")
		assert_true(world.ending_menu.visible, "%s: the ending fires at the Loom" % faction)
		assert_contains(world.ending_menu.label.text, String(ENDING_NAME[faction]))
		assert_true(world.narrative.flag("ending_seen"), "world.narrative.flag('ending_seen')")
		assert_eq(world.narrative.stage_of("the_loom"), "set")
		world.close_ending()


func test_the_mend_and_the_ended_voice_at_the_heart() -> void:
	# A Lattice party that trusted you all the way down, three Keys whole, the voice spared: the Mend.
	_after_catastrophe("lattice", ["sera", "kaj7", "cinder"])
	for id: String in ["sera", "kaj7", "cinder"]:
		world.narrative.approval[id] = 6
	var entry := world.enter_shard("loom_approach", 200, 1)
	_open_site(entry, "loom_door", "The Loom's door")
	assert_true(_choose_text("Cinder, is this the way"), "_choose_text('Cinder, is this the way')")
	assert_eq(world.dialogue.speaker(), "cinder")
	assert_true(_choose_text("Go through"), "_choose_text('Go through')")
	assert_true(world.narrative.flag("cinder_at_the_door"), "cinder at the door")
	world.check_triggers()
	_walk_the_loom("lattice")
	assert_true(_choose_text("Kaj-7. Is this what you heard"), "_choose_text('Kaj-7. Is this what you heard')")
	assert_true(_choose_text("Then it stays"), "_choose_text('Then it stays')")
	assert_true(world.narrative.flag("choir_spared") and world.narrative.flag("kaj7_heard_the_loom"), "world.narrative.flag('choir_spared') and world.narrative.flag('kaj7_heard_the_loom')")
	assert_true(_choose_text("Reweave it"), "_choose_text('Reweave it')")
	assert_true(world.narrative.flag("loom_mended"), "world.narrative.flag('loom_mended')")
	assert_contains(world.ending_menu.label.text, "THE WEAVER'S MEND")
	assert_contains(world.ending_menu.label.text, "Cinder: Cinder tells the Sundering")
	world.close_ending()
	# Ending the voice forecloses the Mend even with three whole Keys.
	_after_catastrophe("ashfound")
	var e := world.enter_shard("loom_approach", 201, 1)
	_open_site(e, "loom_door", "The Loom's door")
	assert_true(_choose_text("Go through"), "through")
	world.check_triggers()
	_walk_the_loom("ashfound")
	assert_true(_choose_text("End it"), "_choose_text('End it')")
	assert_true(world.narrative.flag("choir_ended"), "world.narrative.flag('choir_ended')")
	assert_false(_choice_texts().contains("Reweave it"), "no Mend for an ended voice")
	assert_true(_choose_text("Ash."), "_choose_text('Ash.')")
	assert_contains(world.ending_menu.label.text, "THE FIRE")
	world.close_ending()
	# A broken Key forecloses it too.
	_after_catastrophe("rootched")
	world.narrative.set_flag("key_lattice", false)
	world.narrative.set_flag("key_lattice_broken", true)
	var b := world.enter_shard("loom_approach", 202, 1)
	_open_site(b, "loom_door", "The Loom's door")
	assert_true(_choose_text("Go through"), "through")
	world.check_triggers()
	_walk_the_loom("rootched")
	assert_true(_choose_text("You are a voice"), "_choose_text('You are a voice')")
	assert_false(_choice_texts().contains("Reweave it"), "no Mend with a broken Key")
	assert_true(_choose_text("Completion."), "_choose_text('Completion.')")
	assert_contains(world.ending_menu.label.text, "THE BLOOM")
