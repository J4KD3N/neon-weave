## Campaign tooling in the real scene: the Bastion map with its buildings,
## transitions between handcrafted maps, a locked gate, triggers, the main
## quest and its journal, and door state surviving re-entry and a reload.
extends TestCase

const LEDGER := "user://test_ledger_campaign.json"
const SAVES := "user://test_saves_campaign"

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


## The default scene: home is the Bastion map.
func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.party_id = "prototype"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func _stand_on(cell: Vector2i) -> void:
	world.teleport_party(cell)
	world.party.leader().position = world.map_view.cell_to_world(cell)


func test_home_is_the_bastion_with_visible_buildings() -> void:
	assert_eq(world.map_id, "bastion")
	assert_eq(world.home_map, "bastion")
	assert_true(world.at_home())
	assert_eq(world.map_data.name, "The Bastion")
	assert_eq(world.buildings.size(), 4, "Beacon, Med-bay, Workshop, Arcanum stand on the plaza")
	var beacon := world.building_at(Vector2i(4, 2))
	assert_true(beacon != null)
	assert_eq(beacon.building_id, "beacon")
	assert_eq(beacon.label.text, "Beacon L0/2")
	assert_eq(beacon.height(), BuildingActor.BASE_HEIGHT)
	world.ledger.bank({"salvage": 15, "aether": 2})
	assert_true(world.upgrade_building("beacon"))
	assert_eq(beacon.label.text, "Beacon L1/2", "upgrades show on the map")
	assert_eq(beacon.height(), BuildingActor.BASE_HEIGHT + BuildingActor.STOREY)
	assert_eq(world.living_enemies().size(), 0, "home is safe")
	assert_true(world.npc_at(Vector2i(5, 3)) == null, "Sera waits in the yard, not the plaza")
	assert_true(world.toggle_bastion())
	world.toggle_bastion()


func test_transitions_walk_between_maps_and_arrive_where_told() -> void:
	_stand_on(Vector2i(22, 7))
	assert_true(world.check_transitions())
	assert_eq(world.map_id, "proto_yard")
	assert_true(world.at_home(), "handcrafted maps are still home ground")
	assert_eq(world.leader_cell(), Vector2i(2, 7), "arrived at the yard gate")
	assert_true(world.npc_at(Vector2i(5, 3)) != null, "Sera is here")
	assert_true(FileAccess.file_exists(world.save_path(SaveSystem.AUTOSAVE)), "travel autosaves")
	_stand_on(Vector2i(1, 7))
	assert_true(world.check_transitions())
	assert_eq(world.map_id, "bastion")
	assert_eq(world.leader_cell(), Vector2i(21, 7))
	assert_false(world.check_transitions(), "not standing on a gate")
	world.enter_shard("rusted_undercity", 7)
	assert_false(world.check_transitions(), "Shards have no gates")


func test_gate_road_plays_end_to_end() -> void:
	assert_eq(world.narrative.stage_of("main_waking"), "gate", "the main quest auto-starts")
	var entries := world.journal_entries()
	assert_eq(entries.size(), 1)
	assert_true(bool(entries[0]["main"]))
	assert_eq(entries[0]["objectives"].size(), 3)
	assert_false(bool(entries[0]["objectives"][0]["done"]))
	assert_true(world.enter_map("proto_yard"))
	_stand_on(Vector2i(18, 14))
	assert_true(world.check_transitions())
	assert_eq(world.map_id, "gate_road")
	assert_eq(world.leader_cell(), Vector2i(1, 4))
	var gate := Vector2i(9, 4)
	assert_eq(world.map_data.door_kind(gate), "locked")
	# The gate refuses until the lever is pulled.
	_stand_on(Vector2i(8, 4))
	assert_eq(world.adjacent_door(), gate)
	assert_eq(world.open_locked(gate), "locked: the relay lever on this road")
	assert_false(world.interact())
	assert_eq(world.map_data.door_kind(gate), "locked")
	# The lever trigger fires once.
	_stand_on(Vector2i(7, 1))
	assert_eq(world.check_triggers(), 1)
	assert_true(world.narrative.flag("gate_lever_pulled"))
	assert_true(world.narrative.flag(ExploreWorld.trigger_flag("gate_road", "lever")))
	assert_eq(world.check_triggers(), 0, "once")
	assert_true(bool(world.journal_entries()[0]["objectives"][0]["done"]), "the journal ticks the lever")
	assert_contains(world.journal_text(), "✓ Pull the relay lever on the gate road")
	assert_contains(world.journal_text(), "· Get through the gate")
	# Now the gate opens and sets its flag.
	_stand_on(Vector2i(8, 4))
	assert_true(world.interact(), "Enter / A opens the gate")
	assert_eq(world.map_data.door_kind(gate), "")
	assert_true(world.map_data.is_walkable(gate))
	assert_true(world.narrative.flag("gate_open"))
	assert_true(world.narrative.flag(ExploreWorld.door_flag("gate_road", gate)))
	# Past the gate, the ambush trigger spawns scavs and starts a fight.
	assert_eq(world.living_enemies().size(), 0)
	_stand_on(Vector2i(12, 4))
	assert_eq(world.check_triggers(), 1)
	assert_eq(world.mode, "combat")
	assert_eq(world.living_enemies().size(), 2)
	for e: EnemyActor in world.living_enemies():
		assert_eq(e.enemy_id, "scav")
	_win_the_fight()
	assert_eq(world.mode, "explore")
	# The end of the road completes the quest.
	assert_eq(world.narrative.stage_of("main_waking"), "gate")
	_stand_on(Vector2i(21, 4))
	assert_eq(world.check_triggers(), 1)
	assert_true(world.narrative.flag("road_end"))
	assert_eq(world.narrative.stage_of("main_waking"), "done")
	var text := world.journal_text()
	assert_contains(text, "Done")
	assert_contains(text, "✓ The Waking")
	# Back to the yard by the west gate; the door stays open on re-entry.
	_stand_on(Vector2i(1, 1))
	assert_true(world.check_transitions())
	assert_eq(world.map_id, "proto_yard")
	assert_eq(world.leader_cell(), Vector2i(17, 14))
	assert_true(world.enter_map("gate_road"))
	assert_true(world.map_data.is_walkable(gate), "the gate remembers")
	assert_eq(world.living_enemies().size(), 0, "the ambush does not repeat")
	# And through a save.
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.map_id, "gate_road")
	assert_true(again.map_data.is_walkable(gate))
	assert_eq(again.narrative.stage_of("main_waking"), "done")
	assert_eq(again.check_triggers(), 0, "spent triggers stay spent")
	_drop(again)


func _win_the_fight() -> void:
	var s := world.combat.state
	var steps := 0
	while not s.finished and steps < 400:
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
	assert_true(s.finished, "the ambush resolves")
	assert_eq(s.result, "victory", "three Weavers beat two scavs")


func test_journal_menu_opens_from_key_and_system_menu() -> void:
	assert_true(world.open_journal())
	assert_true(world.journal_menu.visible)
	assert_contains(world.journal_menu.label.text, "★ The Waking")
	assert_contains(world.journal_menu.label.text, "· Pull the relay lever")
	world.close_journal()
	assert_false(world.journal_menu.visible)
	assert_true(world.open_system_menu())
	assert_true(world.activate_system_item("journal"))
	assert_true(world.journal_menu.visible)
	world.close_journal()
	world.teleport_party(Vector2i(11, 5))
	world.mode = "combat"
	assert_false(world.open_journal(), "not mid-fight")
	world.mode = "explore"
	assert_eq(JournalMenu.render([]).split("\n")[2], "Nothing yet. Talk to people; walk east.")


func test_map_campaign_fields_are_well_formed() -> void:
	var tiles := world.tiles_by_id()
	for m: Dictionary in world.registry.get_all("maps"):
		var map := MapData.parse(m, tiles)
		assert_eq(map.errors, [], "map %s parses" % m["id"])
		for t: Dictionary in m.get("transitions", []):
			var raw: Array = t["cell"]
			assert_true(map.is_walkable(Vector2i(int(raw[0]), int(raw[1]))), "map %s transition cell" % m["id"])
			var to := String(t.get("to", ""))
			var target := world.registry.get_entry("maps", to)
			assert_false(target.is_empty(), "map %s transition to %s" % [m["id"], to])
			var arrive: Array = t.get("arrive", [])
			var target_map := MapData.parse(target, tiles)
			assert_true(target_map.is_walkable(Vector2i(int(arrive[0]), int(arrive[1]))), "map %s arrival on %s" % [m["id"], to])
		for d: Dictionary in m.get("doors", []):
			var raw: Array = d["cell"]
			assert_eq(map.door_kind(Vector2i(int(raw[0]), int(raw[1]))), "locked", "map %s doors entry on a locked_door tile" % m["id"])
		for tr: Dictionary in m.get("triggers", []):
			assert_false(String(tr.get("id", "")).is_empty(), "map %s trigger id" % m["id"])
			for k: String in tr.get("effects", {}):
				assert_true(["approval", "flags", "recruit", "quest", "toast", "open_doors", "enemies", "dialogue", "transition"].has(k), "map %s trigger effect %s" % [m["id"], k])
			for k: String in tr.get("when", {}):
				assert_true(["flags", "origin_tag", "race", "class", "approval", "recruited", "not_recruited", "quest"].has(k), "map %s trigger when.%s" % [m["id"], k])
		for b: Dictionary in m.get("buildings", []):
			assert_true(world.bastion.has(String(b.get("id", ""))), "map %s building %s" % [m["id"], b.get("id")])
