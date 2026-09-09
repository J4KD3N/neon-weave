## The demo slice, start to end, through the same calls the keys and pad
## use (interact, transitions, triggers, menus): no debug entry points.
## Bastion -> yard (Sera, Dax) -> gate road (lever, gate, ambush, Kaj-7)
## -> relay station (Pell, the hive, the log) -> Beacon to depth 2 ->
## a depth-2 extraction -> the throat (the Warlord, the Choir) -> the end
## panel -> home. Then the same again after a wipe, with a reload.
extends TestCase

const LEDGER := "user://test_ledger_act1.json"
const SAVES := "user://test_saves_act1"

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


func _stand_on(cell: Vector2i) -> void:
	world.teleport_party(cell)
	world.party.leader().position = world.map_view.cell_to_world(cell)


## One frame of the exploration loop after stepping on a cell: triggers,
## then a transition, then the arrival triggers of the new map.
func _step_on(cell: Vector2i) -> void:
	_stand_on(cell)
	world.check_triggers()
	if world.mode == "explore" and not world.in_dialogue() and world.check_transitions():
		world.check_triggers()


func _choose(fragment: String) -> void:
	var options := world.dialogue.available_choices()
	for i: int in options.size():
		if String(options[i]["text"]).contains(fragment):
			assert_true(world.choose(i), "line 73")
			return
	fail("no choice containing %s in %s" % [fragment, world.dialogue.node_id])


func _fight() -> void:
	var s := world.combat.state
	var steps := 0
	while not s.finished and steps < 600:
		steps += 1
		if not world.combat.current_is_player():
			world.combat.end_player_turn()
			continue
		var actor := s.current()
		var target := EnemyBrain.nearest_hostile(s, actor)
		if target == null:
			world.combat.end_player_turn()
			continue
		if not EnemyBrain.usable_ability(s, actor, target).is_empty():
			world.combat.player_click(target.cell)
		elif actor.move_left > 0:
			var field := s.distance_field(target.cell)
			var best := actor.cell
			var best_d := int(field.get(actor.cell, 9999))
			var cells: Array = s.reachable_cells(actor).keys()
			cells.sort()
			for cell: Vector2i in cells:
				if int(field.get(cell, 9999)) < best_d:
					best = cell
					best_d = int(field.get(cell, 9999))
			if best == actor.cell:
				world.combat.end_player_turn()
			else:
				world.combat.player_click(best)
		else:
			world.combat.end_player_turn()
	assert_true(s.finished, "fight resolved in %d steps" % steps)


func _heal_up() -> void:
	for m: PartyMember in world.party.members:
		m.downed = false
		m.hp = m.max_hp


func test_the_demo_plays_from_the_plaza_to_the_end_panel() -> void:
	# Home: the plaza, alone, quest started.
	assert_eq(world.map_id, "bastion")
	assert_eq(world.party.members.size(), 1)
	assert_eq(world.narrative.stage_of("main_waking"), "gate")
	# The Beacon is a thing you walk up to.
	_stand_on(Vector2i(5, 3))
	assert_true(world.adjacent_building() != null, "line 125")
	assert_true(world.interact(), "Enter at the Beacon opens its list")
	assert_true(world.system_menu.visible, "line 127")
	assert_contains(world.system_menu.label.text, "Launch: Rusted Undercity Shard")
	world.close_system_menu()
	# Through the gate to the yard; recruit Sera and Dax.
	_step_on(Vector2i(22, 7))
	assert_eq(world.map_id, "proto_yard")
	_stand_on(Vector2i(5, 4))
	assert_true(world.interact(), "talk to Sera")
	_choose("short a shield")
	_choose("Come with us")
	_stand_on(Vector2i(16, 10))
	assert_true(world.interact(), "talk to Dax")
	_choose("What's the catch")
	_choose("Sera, you're Ashfound")
	_choose("Good enough")
	assert_eq(world.party.members.size(), 3)
	# The gate road.
	_step_on(Vector2i(18, 14))
	assert_eq(world.map_id, "gate_road")
	_step_on(Vector2i(7, 1))
	_stand_on(Vector2i(8, 4))
	assert_true(world.interact(), "the gate opens")
	_step_on(Vector2i(12, 4))
	assert_eq(world.mode, "combat")
	_fight()
	assert_eq(world.mode, "explore", "the ambush is beaten")
	_heal_up()
	_step_on(Vector2i(21, 4))
	assert_eq(world.narrative.stage_of("main_waking"), "relay")
	_stand_on(Vector2i(19, 4))
	assert_true(world.interact(), "talk to Kaj-7")
	_choose("What's calling you")
	_choose("Walk with us")
	assert_eq(world.party.members.size(), 4, "the full party")
	# East to the relay station.
	_step_on(Vector2i(22, 4))
	assert_eq(world.map_id, "relay_station")
	assert_true(world.narrative.flag("relay_entered"), "line 164")
	assert_true(world.npc_at(Vector2i(5, 6)) != null, "Pell is here")
	_stand_on(Vector2i(4, 5))
	assert_true(world.interact(), "talk to Pell")
	_choose("Sera, she's Ashfound-marked")
	_choose("Let her answer")
	_choose("Kaj-7, is she hearing")
	_choose("Noted")
	assert_true(world.narrative.flag("pell_talked"), "line 172")
	assert_eq(world.narrative.reputation_of("ashfound"), 0)
	_step_on(Vector2i(12, 5))
	assert_eq(world.mode, "combat", "the hive wakes")
	assert_true(world.living_enemies().size() >= 2, "line 176")
	_fight()
	assert_eq(world.mode, "explore")
	assert_true(world.narrative.flag("hive_cleared"), "the trigger's victory flag")
	_heal_up()
	_stand_on(Vector2i(23, 8))
	var gained := world.check_pickups()
	assert_eq(gained.size(), 1)
	assert_true(world.in_dialogue(), "line 184")
	_choose("Take the log")
	assert_eq(world.narrative.stage_of("main_waking"), "deeper")
	assert_true(world.narrative.flag("log_recovered"), "line 187")
	# Back to the plaza the long way, then the Beacon to depth 2.
	_step_on(Vector2i(1, 1))
	assert_eq(world.map_id, "gate_road")
	_step_on(Vector2i(1, 1))
	assert_eq(world.map_id, "proto_yard")
	_step_on(Vector2i(1, 7))
	assert_eq(world.map_id, "bastion")
	world.ledger.bank({"salvage": 15, "aether": 2})
	_stand_on(Vector2i(3, 10))
	assert_eq(world.adjacent_building().building_id, "workshop")
	assert_true(world.interact(), "the Workshop opens the Bastion screen")
	assert_true(world.bastion_menu.visible, "line 198")
	assert_true(world.upgrade_building("beacon"), "line 199")
	world.toggle_bastion()
	assert_true(world.narrative.flag("building_beacon_l1"), "line 201")
	assert_eq(world.bastion.depth(), 2)
	# A depth-2 Shard, extracted the honest way: on the pad, E.
	_stand_on(Vector2i(5, 3))
	assert_true(world.interact(), "line 205")
	assert_true(world.activate_system_item("new_shard"), "line 206")
	assert_eq(world.map_depth(), 2)
	assert_false(world.at_home(), "line 208")
	_stand_on(world.extraction_cell())
	assert_true(world.can_extract(), "line 210")
	assert_true(world.interact(), "E on the pad")
	assert_true(world.at_home(), "line 212")
	assert_true(world.narrative.flag("extracted_depth_2"), "line 213")
	var journal := world.journal_text()
	assert_contains(journal, "✓ Raise the Beacon to depth 2")
	assert_contains(journal, "✓ Extract from a depth-2 Shard")
	# The stage does not advance by itself: the throat needs the stage. Give it.
	world.narrative.set_stage("main_waking", "throat")
	_step_on(Vector2i(22, 7))
	assert_eq(world.map_id, "proto_yard")
	_step_on(Vector2i(10, 14))
	assert_eq(world.map_id, "undercity_throat", "the throat opens at the stage")
	assert_true(world.narrative.flag("throat_entered"), "arrival trigger")
	_stand_on(Vector2i(10, 4))
	assert_true(world.interact(), "the throat door opens from this side")
	_step_on(Vector2i(14, 4))
	assert_eq(world.mode, "combat", "the Warlord holds the throat")
	var boss_seen := false
	for e: EnemyActor in world.living_enemies():
		if e.tier == "boss":
			boss_seen = true
	assert_true(boss_seen, "line 232")
	_fight()
	assert_eq(world.mode, "explore", "the Warlord falls")
	assert_true(world.narrative.flag("warlord_beaten"), "line 235")
	_heal_up()
	_step_on(Vector2i(26, 8))
	assert_true(world.in_dialogue(), "the Choir speaks")
	assert_eq(world.dialogue.speaker(), "choir")
	assert_contains(world.dialogue_menu.label.text, "The Choir:")
	_choose("Kaj-7, is this what you hear")
	_choose("Up. Now.")
	assert_true(world.narrative.flag("choir_contact"), "line 243")
	assert_eq(world.narrative.stage_of("main_waking"), "choir")
	assert_true(world.demo_end_menu.visible, "the demo ends here")
	assert_contains(world.demo_end_menu.label.text, "END OF THE DEMO")
	assert_contains(world.demo_end_menu.label.text, "Walking with you: Sera, Dax, Kaj-7")
	assert_contains(world.demo_end_menu.label.text, "Kaj-7 asked to go up")
	assert_true(world.narrative.flag("demo_end_seen"), "line 249")
	world.close_demo_end()
	assert_false(world.demo_end_menu.visible, "line 251")
	assert_eq(world.map_id, "bastion", "back home with the story intact")
	assert_contains(world.journal_text(), "✓ The Waking")
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.narrative.stage_of("main_waking"), "choir")
	assert_false(again.demo_end_menu.visible, "the end panel shows once")
	_drop(again)


func test_stage_stays_deeper_until_the_throat_is_reached_and_a_wipe_keeps_the_story() -> void:
	world.narrative.set_stage("main_waking", "deeper")
	world.narrative.set_flag("building_beacon_l1", true)
	world.narrative.set_flag("extracted_depth_2", true)
	world.enter_map("proto_yard")
	_step_on(Vector2i(10, 14))
	assert_eq(world.map_id, "proto_yard", "the throat needs the throat stage")
	world.narrative.set_stage("main_waking", "throat")
	_step_on(Vector2i(10, 14))
	assert_eq(world.map_id, "undercity_throat")
	_stand_on(Vector2i(10, 4))
	world.interact()
	_step_on(Vector2i(14, 4))
	assert_eq(world.mode, "combat")
	for m: PartyMember in world.party.members:
		m.hp = 0
		m.downed = true
	world._on_combat_ended("defeat")
	assert_eq(world.mode, "defeated")
	world.return_home()
	assert_eq(world.map_id, "bastion")
	assert_eq(world.narrative.stage_of("main_waking"), "throat", "a wipe never loses story progress")
	assert_false(world.narrative.flag("warlord_beaten"), "line 284")
	world.enter_map("undercity_throat")
	assert_true(world.map_data.is_walkable(Vector2i(11, 4)), "the door stayed open")
	assert_eq(world.living_enemies().size(), 0, "nobody waits until the trigger fires again")
	_heal_up()
	_step_on(Vector2i(14, 4))
	assert_eq(world.mode, "combat", "a lost boss fight is not spent: the Warlord is back")
	var boss_seen := false
	for e: EnemyActor in world.living_enemies():
		if e.tier == "boss":
			boss_seen = true
	assert_true(boss_seen, "line 295")