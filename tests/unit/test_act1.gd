## Act 1, start to end, through the same calls the keys and pad use
## (interact, transitions, triggers, menus): no debug entry points.
## Bastion -> yard (Sera, Dax) -> gate road (lever, gate, ambush, Kaj-7)
## -> relay station (Pell, the hive, the log, Whisper in the rafters,
## Pell's three crews) -> Beacon to depth 2 -> a depth-2 extraction -> three
## Shard runs for the lost crews -> the throat (the Warlord, Cinder) -> the
## flooded gallery (the cantor) -> the source (the Choir, the reveal) -> Act
## 2 opens on the plaza. Then a wipe with the story intact, and the demo
## boundary as a switch (S39).
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
			assert_true(world.choose(i), "choose %s" % fragment)
			return
	fail("no choice containing %s in %s" % [fragment, world.dialogue.node_id])


func _choice_texts() -> String:
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	return "\n".join(texts)


## Plays a fight with the naive loop. `by_fiat` takes it outright, as the
## campaign test does for every fight: the cantor's eight-on-four is on a
## knife-edge for a loop that never thinks, and the harness measures it.
func _fight(by_fiat: bool = false) -> void:
	var s := world.combat.state
	if by_fiat:
		for c: Combatant in s.combatants:
			if c.team == Combatant.TEAM_ENEMY:
				c.hp = 0
		s._check_outcome()
		if world.mode == "combat":
			world._on_combat_ended("victory")
		assert_eq(world.mode, "explore", "taken by fiat")
		return
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
				if not s.provokers_along(actor, s.move_path(actor, cell)).is_empty():
					continue # a player would not walk out of a fighter's reach for a cell like any other (S65)
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


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry.get("pickups", []):
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


## Launches a Shard from the Beacon and walks to a story site. Companion
## sites share the far room and a full party covers several cells, so a
## companion's site may open first: it is played through, then the check
## runs again (one site opens per check, S38).
func _launch_and_open(pickup: String, dialogue_name: String) -> void:
	_stand_on(Vector2i(5, 3))
	assert_true(world.interact(), "the Beacon")
	assert_true(world.activate_system_item("new_shard"), "launch")
	assert_false(world.at_home())
	var site := _site_cell(world.map_entry, pickup)
	assert_true(site.x >= 0, "%s placed" % pickup)
	world.teleport_party(site)
	for _try: int in 6:
		if not world.in_dialogue():
			world.check_pickups()
		if not world.in_dialogue():
			world.teleport_party(site)
			world.check_pickups()
		assert_true(world.in_dialogue(), "a site opened")
		if String(world.dialogue.dialogue.get("name", "")) == dialogue_name:
			return
		while world.in_dialogue():
			world.choose(0)
	fail("%s never opened" % dialogue_name)


func _extract() -> void:
	_stand_on(world.extraction_cell())
	assert_true(world.can_extract(), "world.can_extract()")
	assert_true(world.interact(), "E on the pad")
	assert_true(world.at_home(), "world.at_home()")
	_heal_up()


func test_act_1_plays_from_the_plaza_to_the_source_and_opens_act_2() -> void:
	seed(20260921) # launched Shards roll their layout from the global RNG; pin it so the walk is the same every run
	# Home: the plaza, alone, quest started.
	assert_eq(world.map_id, "bastion")
	assert_eq(world.party.members.size(), 1)
	assert_eq(world.narrative.stage_of("main_waking"), "gate")
	_stand_on(Vector2i(5, 3))
	assert_true(world.adjacent_building() != null, "world.adjacent_building() != null")
	assert_true(world.interact(), "Enter at the Beacon opens its list")
	assert_true(world.system_menu.visible, "world.system_menu.visible")
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
	# East to the relay station: Pell, the hive, the log.
	_step_on(Vector2i(22, 4))
	assert_eq(world.map_id, "relay_station")
	assert_true(world.narrative.flag("relay_entered"), "world.narrative.flag('relay_entered')")
	assert_true(world.npc_at(Vector2i(5, 6)) != null, "Pell is here")
	_stand_on(Vector2i(4, 5))
	assert_true(world.interact(), "talk to Pell")
	_choose("Sera, she's Ashfound-marked")
	_choose("Let her answer")
	_choose("Kaj-7, is she hearing")
	_choose("Noted")
	assert_true(world.narrative.flag("pell_talked"), "world.narrative.flag('pell_talked')")
	assert_true(world.npc_at(Vector2i(24, 6)) == null, "nobody in the rafters yet")
	_step_on(Vector2i(12, 5))
	assert_eq(world.mode, "combat", "the hive wakes")
	_fight()
	assert_eq(world.mode, "explore")
	assert_true(world.narrative.flag("hive_cleared"), "the trigger's victory flag")
	_heal_up()
	_stand_on(Vector2i(23, 8))
	assert_eq(world.check_pickups().size(), 1)
	assert_true(world.in_dialogue(), "world.in_dialogue()")
	_choose("Take the log")
	assert_eq(world.narrative.stage_of("main_waking"), "deeper")
	assert_true(world.narrative.flag("log_recovered"), "world.narrative.flag('log_recovered')")
	# Whisper comes down from the rafters; the party is full, so she waits at the Bastion.
	assert_true(world.npc_at(Vector2i(24, 6)) != null, "Whisper, once the hive is dead")
	_stand_on(Vector2i(24, 5))
	assert_true(world.interact(), "talk to Whisper")
	_choose("Why were you")
	_choose("Dax, you have hired")
	_choose("Then she is hired")
	assert_true(world.narrative.is_recruited("whisper") and world.narrative.is_benched("whisper"), "world.narrative.is_recruited('whisper') and world.narrative.is_benched('whisper')")
	assert_eq(world.party.members.size(), 4)
	# Pell's follow-up: the relay station is the hub for the lost crews.
	_stand_on(Vector2i(4, 5))
	assert_true(world.interact(), "Pell again")
	assert_eq(world.dialogue.node_id, "crews")
	_choose("Give me the positions")
	_choose("We'll be back")
	assert_true(world.narrative.flag("pell_hub"), "world.narrative.flag('pell_hub')")
	assert_eq(world.narrative.stage_of("lost_crews"), "ostrand")
	assert_contains(world.journal_text(), "The Lost Crews")
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
	assert_true(world.upgrade_building("beacon"), "world.upgrade_building('beacon')")
	world.toggle_bastion()
	assert_true(world.narrative.flag("building_beacon_l1"), "world.narrative.flag('building_beacon_l1')")
	assert_eq(world.bastion.depth(), 2)
	# A depth-2 Shard, extracted the honest way: on the pad, E.
	_stand_on(Vector2i(5, 3))
	assert_true(world.interact(), "world.interact()")
	assert_true(world.activate_system_item("new_shard"), "world.activate_system_item('new_shard')")
	assert_eq(world.map_depth(), 2)
	_extract()
	assert_true(world.narrative.flag("extracted_depth_2"), "world.narrative.flag('extracted_depth_2')")
	assert_eq(world.narrative.stage_of("main_waking"), "expeditions", "the hand-off is data: the crews next")
	# Three Shard runs for the three crews.
	_launch_and_open("crew_ostrand_marker", "Crew Ostrand — the marker")
	_choose("Kaj-7, is this the signal")
	_choose("Take the marker")
	assert_true(world.narrative.flag("crew_ostrand_found"), "world.narrative.flag('crew_ostrand_found')")
	_extract()
	assert_eq(world.narrative.stage_of("lost_crews"), "vane", "the next crew's site")
	_launch_and_open("crew_vane_nest", "Crew Vane — the nest")
	_choose("Burn it out")
	assert_eq(world.mode, "combat", "a site can start a fight")
	assert_true(world.living_enemies().size() >= 2, "the nest around the party")
	_fight(true) # a depth-2 Shard nest, eight on four: the harness measures it, the loop only wires it
	assert_eq(world.mode, "explore")
	assert_true(world.narrative.flag("crew_vane_found"), "the fight's victory flag")
	_heal_up()
	_extract()
	assert_eq(world.narrative.stage_of("lost_crews"), "marrow")
	_launch_and_open("crew_marrow_cistern", "Crew Marrow — the cistern")
	_choose("Pull them out")
	assert_true(world.narrative.flag("marrow_saved"), "world.narrative.flag('marrow_saved')")
	_extract()
	assert_eq(world.narrative.stage_of("lost_crews"), "done")
	assert_eq(world.narrative.stage_of("main_waking"), "throat", "three crews accounted for: the throat opens")
	assert_contains(world.journal_text(), "✓ The Lost Crews")
	# The throat: the Warlord, then Cinder at the source of the singing.
	_step_on(Vector2i(22, 7))
	assert_eq(world.map_id, "proto_yard")
	_step_on(Vector2i(10, 14))
	assert_eq(world.map_id, "undercity_throat", "the throat opens at the stage")
	assert_true(world.narrative.flag("throat_entered"), "world.narrative.flag('throat_entered')")
	_stand_on(Vector2i(10, 4))
	assert_true(world.interact(), "the throat door opens from this side")
	_step_on(Vector2i(14, 4))
	assert_eq(world.mode, "combat", "the Warlord holds the throat")
	_fight()
	assert_eq(world.mode, "explore", "the Warlord falls")
	assert_true(world.narrative.flag("warlord_beaten"), "world.narrative.flag('warlord_beaten')")
	_heal_up()
	assert_true(world.npc_at(Vector2i(23, 7)) != null, "Cinder stands past the Warlord's post")
	_stand_on(Vector2i(22, 7))
	assert_true(world.interact(), "talk to Cinder")
	_choose("What is a tether")
	_choose("Walk with us, priest")
	assert_true(world.narrative.is_recruited("cinder") and world.narrative.is_benched("cinder"), "the party is full: he waits at the Bastion")
	# Down: the flooded gallery and its cantor.
	_step_on(Vector2i(26, 8))
	assert_eq(world.map_id, "throat_deep", "the descent is three maps")
	assert_true(world.narrative.flag("throat_deep_entered"), "world.narrative.flag('throat_deep_entered')")
	_step_on(Vector2i(11, 5))
	assert_eq(world.mode, "combat", "the cantor")
	assert_true(world.living_enemies().size() >= 4, "world.living_enemies().size() >= 4")
	_fight()
	assert_eq(world.mode, "explore")
	assert_true(world.narrative.flag("cantor_beaten"), "world.narrative.flag('cantor_beaten')")
	_heal_up()
	# The source: a scripted approach, then first contact and the reveal.
	_step_on(Vector2i(26, 10))
	assert_eq(world.map_id, "throat_source")
	_step_on(Vector2i(10, 4))
	assert_true(world.narrative.flag("throat_source_entered"), "world.narrative.flag('throat_source_entered')")
	assert_true(world.in_dialogue(), "the Choir speaks")
	assert_eq(world.dialogue.speaker(), "choir")
	assert_contains(world.dialogue_menu.label.text, "The Choir:")
	_choose("Who drowned you")
	_choose("Chosen how")
	assert_false(_choice_texts().contains("Cinder. You were there"), "Cinder is at the Bastion, not here")
	_choose("Then the Sundering was a choice")
	assert_false(world.in_dialogue())
	for flag: String in ["choir_contact", "choir_heard_truth", "sundering_chosen", "act1_complete", "act2"]:
		assert_true(world.narrative.flag(flag), flag)
	assert_true(world.narrative.lore.has("sundering_choice"), "the reveal is a fragment in the Archive")
	assert_eq(world.narrative.stage_of("main_waking"), "choir")
	assert_false(world.demo_end_menu.visible, "the full game does not end here")
	assert_eq(world.map_id, "throat_source", "and the party is still at the source")
	assert_contains(world.journal_text(), "✓ The Waking")
	# Up, the long way, to a plaza where Act 2 waits.
	_step_on(Vector2i(1, 1))
	assert_eq(world.map_id, "throat_deep")
	_step_on(Vector2i(1, 1))
	assert_eq(world.map_id, "undercity_throat")
	_step_on(Vector2i(1, 1))
	assert_eq(world.map_id, "proto_yard")
	_step_on(Vector2i(1, 7))
	assert_eq(world.map_id, "bastion")
	assert_true(world.npc_at(Vector2i(5, 13)) != null, "Yev came to the plaza")
	_stand_on(Vector2i(12, 12))
	assert_true(world.interact(), "the Lattice envoy")
	_choose("Say your piece")
	_choose("Get to the offer")
	assert_true(_choice_texts().contains("Join the Lattice."), "Act 2: the oath is on the table")
	_choose("Keep talking to us")
	while world.in_dialogue():
		world.choose(0)
	assert_eq(world.narrative.faction, "", "warmed, not sworn")
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.narrative.stage_of("main_waking"), "choir")
	assert_true(again.narrative.is_benched("whisper") and again.narrative.is_benched("cinder"), "again.narrative.is_benched('whisper') and again.narrative.is_benched('cinder')")
	assert_true(again.narrative.flag("act2"), "again.narrative.flag('act2')")
	_drop(again)


func test_stage_stays_deeper_until_the_throat_is_reached_and_a_wipe_keeps_the_story() -> void:
	for id: String in ["sera", "dax", "kaj7"]:
		assert_true(world.add_companion(id), "the demo party reaches the throat together")
	world.ledger.xp = 40
	world.refresh_progression()
	world.narrative.set_stage("main_waking", "expeditions")
	world.narrative.set_flag("pell_hub", true)
	world.narrative.set_flag("crew_ostrand_found", true)
	world.narrative.set_flag("crew_vane_found", true)
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
	assert_false(world.narrative.flag("warlord_beaten"))
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
	assert_true(boss_seen, "boss_seen")
	# The descent is gated on the Warlord: no way down until he falls.
	world._on_combat_ended("defeat")
	world.return_home()
	world.enter_map("undercity_throat")
	_step_on(Vector2i(26, 8))
	assert_eq(world.map_id, "undercity_throat", "the stair down waits on warlord_beaten")


func test_the_demo_boundary_is_a_switch() -> void:
	var rules_demo := world.registry.get_entry("rules", "demo")
	assert_false(bool(rules_demo.get("enabled", true)), "off in the full game")
	world.narrative.set_flag("demo_complete", true)
	assert_false(world.check_demo_end(), "no panel")
	assert_false(world.narrative.flag("demo_end_seen"))
	world.demo_forced = true # `-- --demo`
	assert_true(world.check_demo_end(), "the demo build shows it")
	assert_true(world.demo_end_menu.visible, "world.demo_end_menu.visible")
	assert_contains(world.demo_end_menu.label.text, "END OF THE DEMO")
	world.close_demo_end()
	assert_false(world.check_demo_end(), "once")
	world.demo_forced = false
	var on := rules_demo.duplicate(true)
	on["enabled"] = true
	world.registry.put("rules", "demo", on)
	world.narrative.set_flag("demo_end_seen", false)
	assert_true(world.check_demo_end(), "or the rules turn it on")
	world.close_demo_end()
	world.registry.put("rules", "demo", rules_demo) # the registry is shared across tests
