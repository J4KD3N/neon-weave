## Instantiates the real exploration scene headless and drives it, including
## a full encounter through the combat controller with animation off.
extends TestCase

const DT := 1.0 / 60.0

var world: ExploreWorld


const LEDGER := "user://test_ledger_scene.json"
const SAVES := "user://test_saves_scene"


func before_each() -> void:
	_remove_ledger()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	_root().add_child(world)
	world.combat.animate = false


func after_each() -> void:
	_root().remove_child(world)
	world.free()
	_remove_ledger()


static func _remove_ledger() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _settle(max_ticks: int) -> int:
	var ticks := 0
	while world.party.is_moving() and ticks < max_ticks:
		world.party.tick(DT)
		ticks += 1
	return ticks


func test_map_is_built_from_content() -> void:
	assert_eq(world.map_data.errors, [])
	assert_eq(world.map_data.name, "Proto Yard")
	assert_eq(world.map_view.ground.get_used_cells().size(), world.map_data.walkable_count(), "every walkable cell has ground")
	var walls := world.map_view.walls.get_used_cells().size()
	assert_true(walls > 0, "walls placed on the wall layer")
	var enclosed := 0
	for y: int in world.map_data.height:
		for x: int in world.map_data.width:
			if world.map_data.is_enclosed(Vector2i(x, y)):
				enclosed += 1
	assert_eq(walls + enclosed + world.map_data.walkable_count(), world.map_data.width * world.map_data.height, "walls + void + ground cover the map")


func test_party_spawns_on_spawn_cells_with_class_colours_and_stats() -> void:
	assert_eq(world.party.members.size(), 4)
	var spawns := world.map_data.spawn_cells()
	for i: int in 4:
		var m := world.party.members[i]
		assert_eq(m.position, world.map_view.cell_to_world(spawns[i]))
		assert_eq(m.is_leader, i == 0)
		assert_true(m.max_hp > 1)
		assert_eq(m.hp, m.max_hp)
		assert_true(m.abilities.size() >= 2)
	assert_eq(world.party.members[0].tint, Color.html("#ff7a6b"), "Scrap-Knight is Body coral")
	assert_eq(world.party.members[1].tint, Color.html("#b58cff"), "Aetherbinder is Arcane purple")
	assert_eq(world.party.members[0].max_hp, 22, "Trueborn Scrap-Knight: 20 + 2")
	assert_eq(world.party.members[2].max_hp, 24, "Synth Scrap-Knight: 20 + 4")
	assert_eq(world.leader_cell(), spawns[0])


func test_enemies_spawn_from_the_map() -> void:
	assert_eq(world.living_enemies().size(), 4)
	var scav := world.enemy_at(Vector2i(14, 2))
	assert_true(scav != null)
	assert_eq(scav.enemy_id, "scav")
	assert_eq(scav.position, world.map_view.cell_to_world(Vector2i(14, 2)))
	assert_eq(scav.hp, 8)
	assert_eq(world.enemy_at(Vector2i(17, 6)).archetype, "ranged")
	assert_true(world.enemy_at(Vector2i(2, 2)) == null)


func test_click_move_walks_leader_to_cell() -> void:
	var target := Vector2i(6, 12)
	assert_true(world.map_data.is_walkable(target))
	assert_true(world.command_move(target))
	assert_true(world.party.is_moving())
	var ticks := _settle(3000)
	assert_false(world.party.is_moving(), "arrived within %d ticks" % ticks)
	assert_eq(world.leader_cell(), target)
	assert_eq(world.mode, "explore", "no enemy near that corner")


func test_move_to_blocked_or_unreachable_cell_is_refused() -> void:
	assert_false(world.command_move(Vector2i(0, 0)), "wall")
	assert_false(world.command_move(Vector2i(7, 3)), "debris")
	assert_false(world.command_move(Vector2i(-5, 2)), "off map")
	assert_false(world.party.is_moving())


func test_followers_trail_leader_over_walkable_cells() -> void:
	world.command_move(Vector2i(6, 12))
	_settle(3000)
	for _i: int in 600:
		world.party.tick(DT)
	var leader := world.party.leader()
	for i: int in range(1, 4):
		var m := world.party.members[i]
		var cell := world.map_view.world_to_cell(m.position)
		assert_true(world.map_data.is_walkable(cell), "follower %d stands on %s" % [i, cell])
		var d := m.position.distance_to(leader.position)
		assert_true(d > 4.0, "follower %d is not stacked on the leader (%.1f)" % [i, d])
		assert_true(d <= world.party.spacing * i + 1.0, "follower %d within %d spacing (%.1f)" % [i, i, d])


func test_keyboard_steering_never_enters_walls() -> void:
	var start := world.party.leader().position
	for _i: int in 600:
		world.party.steer_leader(Vector2.LEFT, DT, world.map_view.is_walkable_world)
		assert_true(world.map_data.is_walkable(world.leader_cell()), "leader inside %s" % world.leader_cell())
	assert_true(world.party.leader().position.distance_to(start) > 32.0, "leader moved")


func test_no_encounter_at_spawn() -> void:
	assert_false(world.check_encounters())
	assert_eq(world.mode, "explore")


func test_awareness_triggers_combat_with_engaged_enemies_only() -> void:
	world.teleport_party(Vector2i(13, 4))
	assert_true(world.check_encounters())
	assert_eq(world.mode, "combat")
	assert_false(world.party.active)
	assert_true(world.combat.is_active())
	var s := world.combat.state
	assert_eq(s.active("party").size(), 4)
	assert_eq(s.active("enemy").size(), 3, "the chrome-addict at (12,12) is beyond the engage radius")
	var cells: Array[Vector2i] = []
	for c: Combatant in s.combatants:
		assert_false(cells.has(c.cell), "distinct cells")
		cells.append(c.cell)
		assert_true(world.map_data.is_walkable(c.cell))
	for m: PartyMember in world.party.members:
		assert_true(m.show_hp)


func test_first_strike_gives_party_the_initiative_bonus() -> void:
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	assert_eq(world.mode, "combat")
	for c: Combatant in world.combat.state.combatants:
		if c.team == Combatant.TEAM_PARTY:
			assert_true(c.initiative >= 1 + world.rules.first_strike_initiative_bonus, "%s rolled %d" % [c.id, c.initiative])


func test_full_encounter_resolves_and_returns_to_exploration() -> void:
	world.teleport_party(Vector2i(13, 4))
	world.check_encounters()
	var s := world.combat.state
	var steps := 0
	while not s.finished and steps < 600:
		steps += 1
		if not world.combat.current_is_player():
			break # the controller runs enemy turns itself; should never idle here
		var actor := s.current()
		var target := EnemyBrain.nearest_hostile(s, actor)
		if target == null:
			break
		if not EnemyBrain.usable_ability(s, actor, target).is_empty():
			world.combat.player_click(target.cell)
		elif actor.move_left > 0:
			var reach := s.reachable_cells(actor)
			var best := actor.cell
			var best_d := LineOfSight.distance(actor.cell, target.cell)
			var cells: Array = reach.keys()
			cells.sort()
			for cell: Vector2i in cells:
				var d := LineOfSight.distance(cell, target.cell)
				if d < best_d:
					best = cell
					best_d = d
			if best == actor.cell:
				world.combat.end_player_turn()
			else:
				world.combat.player_click(best)
		else:
			world.combat.end_player_turn()
	assert_true(s.finished, "fight resolved in %d player actions (round %d)" % [steps, s.round_number])
	assert_true(s.history.size() > 5)
	if s.result == "victory":
		assert_eq(world.mode, "explore")
		assert_true(world.party.active)
		assert_eq(world.living_enemies().size(), 1, "only the unengaged chrome-addict remains")
		for m: PartyMember in world.party.members:
			assert_false(m.downed, "story-protected members are back up")
			assert_true(m.hp >= 1)
			assert_false(m.show_hp)
	else:
		assert_eq(world.mode, "defeated")
	assert_eq(s.result, "victory", "seeded fight 4 vs 3 is expected to be won; seed %d" % world.combat_seed)


func test_status_line_mentions_map_mode_and_leader() -> void:
	var line := world.status_line()
	assert_contains(line, "Proto Yard")
	assert_contains(line, "explore")
	assert_contains(line, "leader (2, 2)")
	assert_contains(line, "enemies 4")


func test_enter_shard_generates_a_solvable_level_and_home_returns() -> void:
	var entry := world.enter_shard("rusted_undercity", 7)
	assert_false(entry.is_empty())
	assert_eq(world.mode, "explore")
	assert_contains(world.map_data.name, "Rusted Undercity Shard #7")
	assert_eq(world.map_data.errors, [])
	assert_eq(ShardValidator.validate(entry, world.tiles_by_id()), [])
	var placements: Array = entry["enemies"]
	assert_eq(world.living_enemies().size(), placements.size())
	assert_eq(world.party.members.size(), 4)
	assert_eq(world.leader_cell(), world.map_data.spawn_cells()[0])
	var exit_cell := world.extraction_cell()
	assert_true(world.map_data.is_walkable(exit_cell))
	assert_true(world.command_move(exit_cell), "extraction is reachable by the exploration pathfinder")
	assert_true(world.party.active)
	assert_true(world.enter_map("proto_yard"))
	assert_eq(world.map_data.name, "Proto Yard")
	assert_eq(world.living_enemies().size(), 4)
	assert_eq(world.extraction_cell(), Vector2i(-1, -1))


func test_unknown_shard_template_is_refused() -> void:
	assert_eq(world.enter_shard("nope", 1), {})
	assert_eq(world.map_data.name, "Proto Yard")


func test_pickups_spawn_and_are_collected_by_walking_over() -> void:
	assert_eq(world.remaining_pickups().size(), 2)
	assert_eq(world.ledger.total("salvage"), 0, "fresh ledger")
	world.teleport_party(Vector2i(5, 10))
	var gained := world.check_pickups()
	assert_eq(gained.size(), 1)
	assert_eq(gained[0]["pickup"], "salvage_cache")
	assert_true(int(gained[0]["salvage"]) >= 2 and int(gained[0]["salvage"]) <= 5, "cache rolls 2-5")
	assert_eq(world.remaining_pickups().size(), 1)
	assert_true(world.ledger.total("salvage") >= 2, "at home, loot banks immediately")
	assert_true(world.run.is_empty())
	assert_eq(world.check_pickups().size(), 0, "collected once")
	assert_true(FileAccess.file_exists(LEDGER), "ledger saved on bank")


func test_enemy_kill_adds_loot_xp_and_kills() -> void:
	var scav := world.enemy_at(Vector2i(14, 2))
	var got := world.on_enemy_killed(scav)
	assert_true(int(got["salvage"]) >= 1 and int(got["salvage"]) <= 2)
	assert_eq(int(got["xp"]), 5)
	assert_eq(world.ledger.kills, 1)
	assert_eq(world.ledger.xp, 5)
	assert_true(world.ledger.total("salvage") >= 1)


func test_extraction_banks_haul_records_run_and_returns_home() -> void:
	var entry := world.enter_shard("rusted_undercity", 7)
	assert_true(world.run.in_shard)
	var placements: Array = entry["pickups"]
	assert_true(placements.size() >= 3)
	assert_eq(world.remaining_pickups().size(), placements.size())
	world.run.collect({"salvage": 3, "aether": 1, "xp": 4})
	world.run.kills = 2
	assert_false(world.can_extract(), "not on the pad yet")
	assert_false(world.extract())
	world.teleport_party(world.extraction_cell())
	assert_eq(world.leader_cell(), world.extraction_cell())
	assert_true(world.can_extract())
	assert_true(world.extract())
	assert_eq(world.map_data.name, "Proto Yard")
	assert_eq(world.mode, "explore")
	assert_false(world.run.in_shard)
	assert_true(world.run.is_empty())
	assert_eq(world.ledger.total("salvage"), 3)
	assert_eq(world.ledger.total("aether"), 1)
	assert_eq(world.ledger.xp, 4)
	assert_eq(world.ledger.kills, 2)
	assert_eq(world.ledger.runs_completed, 1)
	var reloaded := Ledger.load_or_new(LEDGER)
	assert_eq(reloaded.runs_completed, 1)
	assert_eq(reloaded.total("salvage"), 3)
	assert_false(world.can_extract(), "no pad at home")


func test_wipe_in_shard_loses_haul_but_not_the_books() -> void:
	world.ledger.bank({"salvage": 10})
	world.enter_shard("rusted_undercity", 7)
	world.run.collect({"salvage": 5, "xp": 3})
	world.run.kills = 1
	world._on_combat_ended("defeat")
	assert_eq(world.mode, "defeated")
	assert_true(world.run.is_empty(), "haul lost")
	assert_eq(world.ledger.runs_wiped, 1)
	assert_eq(world.ledger.runs_completed, 0)
	assert_eq(world.ledger.total("salvage"), 10, "banked salvage untouched")
	assert_eq(world.ledger.xp, 0, "unbanked xp lost")
	assert_eq(world.ledger.kills, 1, "kills still count")
	assert_contains(world.status_line(), "R: return to the yard")
	world.return_home()
	assert_eq(world.mode, "explore")
	assert_eq(world.map_data.name, "Proto Yard")
	for m: PartyMember in world.party.members:
		assert_eq(m.hp, m.max_hp, "fresh party at home")
	assert_eq(Ledger.load_or_new(LEDGER).runs_wiped, 1)


func test_status_line_shows_extraction_prompt_on_the_pad() -> void:
	world.enter_shard("rusted_undercity", 7)
	world.teleport_party(world.extraction_cell())
	assert_contains(world.status_line(), "press E to extract")
	assert_contains(world.status_line(), "haul S0")


func test_party_hp_persists_into_a_shard_and_the_medbay_heals_at_home() -> void:
	var leader := world.party.leader()
	var max_hp := leader.max_hp
	leader.hp = 5
	world.enter_shard("rusted_undercity", 7)
	assert_eq(world.party.leader(), leader, "same party nodes")
	assert_eq(world.party.leader().hp, 5, "wounds carry into the Shard")
	assert_eq(world.leader_cell(), world.map_data.spawn_cells()[0])
	world.enter_map("proto_yard")
	var expected := mini(max_hp, 5 + int(ceil(max_hp * 0.25)))
	assert_eq(world.party.leader().hp, expected, "Med-bay L0 restores a quarter")


func test_wipe_returns_home_and_the_medbay_revives() -> void:
	world.enter_shard("rusted_undercity", 7)
	for m: PartyMember in world.party.members:
		m.hp = 0
		m.downed = true
	world._on_combat_ended("defeat")
	world.return_home()
	assert_eq(world.mode, "explore")
	for m: PartyMember in world.party.members:
		assert_false(m.downed)
		assert_eq(m.hp, int(ceil(m.max_hp * 0.25)), "revived to the Med-bay fraction")


func test_workshop_upgrade_spends_persists_and_raises_max_hp() -> void:
	var leader := world.party.leader()
	assert_eq(leader.max_hp, 22)
	leader.hp = 10
	assert_false(world.upgrade_building("workshop"), "cannot afford")
	world.ledger.bank({"salvage": 50})
	assert_true(world.upgrade_building("workshop"))
	assert_eq(world.ledger.total("salvage"), 38)
	assert_eq(world.bastion.level("workshop"), 1)
	assert_eq(leader.max_hp, 24, "+2 plating")
	assert_eq(leader.hp, 12, "the upgrade heals by what it adds")
	assert_eq(world.ledger.buildings, {"beacon": 0, "medbay": 0, "workshop": 1})
	var saved := Ledger.load_or_new(LEDGER)
	assert_eq(saved.buildings["workshop"], 1)
	# A fresh scene picks the level back up from the ledger.
	var packed: PackedScene = load("res://scenes/main.tscn")
	var again := packed.instantiate() as ExploreWorld
	again.ledger_path = LEDGER
	_root().add_child(again)
	assert_eq(again.bastion.level("workshop"), 1)
	assert_eq(again.party.leader().max_hp, 24)
	_root().remove_child(again)
	again.free()


func test_beacon_depth_scales_generated_shards() -> void:
	var shallow := world.enter_shard("rusted_undercity", 7)
	var shallow_enemies: Array = shallow["enemies"]
	world.enter_map("proto_yard")
	world.ledger.bank({"salvage": 100, "aether": 10, "ciphers": 2})
	assert_true(world.upgrade_building("beacon"))
	assert_true(world.upgrade_building("beacon"))
	assert_eq(world.bastion.depth(), 3)
	var deep := world.enter_shard("rusted_undercity", 7)
	var generation: Dictionary = deep["generation"]
	assert_eq(int(generation["depth"]), 3)
	assert_contains(String(deep["name"]), "depth 3")
	var deep_enemies: Array = deep["enemies"]
	assert_true(deep_enemies.size() >= shallow_enemies.size(), "deeper is never emptier (%d vs %d)" % [deep_enemies.size(), shallow_enemies.size()])
	assert_eq(ShardValidator.validate(deep, world.tiles_by_id()), [])


func test_bastion_menu_opens_only_at_home() -> void:
	assert_true(world.toggle_bastion())
	assert_true(world.bastion_menu.visible)
	assert_contains(world.bastion_menu.label.text, "[1] Beacon")
	assert_false(world.toggle_bastion(), "second press closes")
	assert_false(world.bastion_menu.visible)
	world.enter_shard("rusted_undercity", 7)
	assert_false(world.toggle_bastion(), "not in a Shard")
	assert_false(world.bastion_menu.visible)
	assert_contains(world.status_line(), "depth 1")


func _fresh_scene() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var again := packed.instantiate() as ExploreWorld
	again.combat_seed = 1234
	again.ledger_path = LEDGER
	again.saves_dir = SAVES
	_root().add_child(again)
	again.combat.animate = false
	return again


func _drop(scene: ExploreWorld) -> void:
	_root().remove_child(scene)
	scene.free()


func test_save_is_refused_in_combat() -> void:
	world.teleport_party(Vector2i(13, 4))
	world.check_encounters()
	assert_eq(world.mode, "combat")
	assert_eq(world.save_slot(1), ERR_UNAVAILABLE)
	assert_false(FileAccess.file_exists(world.save_path("slot_1")))
	assert_true(FileAccess.file_exists(world.save_path("autosave")), "combat checkpoint written just before the fight")
	var errors := world.load_slot(1)
	assert_eq(errors.size(), 1)
	assert_contains(errors[0], "no save at")


func test_home_save_round_trip_into_a_fresh_scene() -> void:
	var leader := world.party.leader()
	world.ledger.bank({"salvage": 50, "aether": 3})
	assert_true(world.upgrade_building("workshop"))
	leader.hp = 9
	world.party.members[2].downed = true
	world.party.members[2].hp = 0
	var scav := world.enemy_at(Vector2i(14, 2))
	scav.dead = true
	scav.queue_free()
	world.teleport_party(Vector2i(5, 10))
	assert_eq(world.check_pickups().size(), 1)
	world.teleport_party(Vector2i(6, 12))
	assert_eq(world.save_slot(1), OK)
	var salvage := world.ledger.total("salvage")

	var again := _fresh_scene()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.map_data.name, "Proto Yard")
	assert_eq(again.mode, "explore")
	assert_false(again.run.in_shard)
	assert_eq(again.bastion.level("workshop"), 1)
	assert_eq(again.ledger.total("salvage"), salvage)
	assert_eq(again.party.leader().max_hp, 24, "Workshop plating restored before HP")
	assert_eq(again.party.leader().hp, 9, "wound survives the Med-bay because the save wins")
	assert_true(again.party.members[2].downed)
	assert_eq(again.party.members[2].hp, 0)
	assert_eq(again.leader_cell(), Vector2i(6, 12))
	assert_eq(again.living_enemies().size(), 3)
	assert_true(again.enemy_at(Vector2i(14, 2)) == null, "the dead scav stays dead")
	assert_eq(again.remaining_pickups().size(), 1)
	assert_eq(Ledger.load_or_new(LEDGER).total("salvage"), salvage, "ledger file rewritten from the save")
	_drop(again)


func test_shard_save_round_trip_keeps_seed_depth_haul_and_deltas() -> void:
	world.ledger.bank({"salvage": 100, "aether": 10, "ciphers": 2})
	assert_true(world.upgrade_building("beacon"))
	var entry := world.enter_shard("rusted_undercity", 7)
	assert_contains(String(entry["name"]), "depth 2")
	world.run.collect({"salvage": 6, "aether": 1, "xp": 3})
	world.run.kills = 1
	var first := world.enemies[0]
	first.dead = true
	first.queue_free()
	world.teleport_party(world.extraction_cell())
	assert_eq(world.save_slot(2), OK)
	assert_true(world.upgrade_building("beacon"), "depth moves on after the save")
	assert_eq(world.bastion.depth(), 3)

	var again := _fresh_scene()
	assert_eq(again.bastion.depth(), 3, "fresh scene reads the newer ledger first")
	assert_eq(again.load_slot(2), [])
	assert_eq(again.map_data.name, String(entry["name"]), "same shard at the saved depth")
	assert_eq(again.map_entry["rows"], entry["rows"])
	assert_true(again.run.in_shard)
	assert_eq(again.run.haul, {"salvage": 6, "aether": 1, "ciphers": 0})
	assert_eq(again.run.xp, 3)
	assert_eq(again.run.kills, 1)
	var placements: Array = entry["enemies"]
	assert_eq(again.living_enemies().size(), placements.size() - 1)
	assert_true(again.enemies[0].dead or not is_instance_valid(again.enemies[0]))
	assert_eq(again.leader_cell(), again.extraction_cell())
	assert_true(again.can_extract())
	assert_eq(again.bastion.depth(), 2, "the save's ledger wins over the newer file")
	assert_eq(Ledger.load_or_new(LEDGER).buildings["beacon"], 1)
	_drop(again)


func test_autosave_marks_the_checkpoints() -> void:
	assert_false(FileAccess.file_exists(world.save_path("autosave")))
	world.enter_shard("rusted_undercity", 7)
	var a := SaveSystem.read(world.save_path("autosave"))
	assert_eq(Dictionary(a["location"])["kind"], "shard")
	assert_eq(int(Dictionary(a["location"])["seed"]), 7)
	world.teleport_party(world.extraction_cell())
	assert_true(world.extract())
	var b := SaveSystem.read(world.save_path("autosave"))
	assert_eq(Dictionary(b["location"])["kind"], "map")
	assert_eq(Dictionary(b["location"])["id"], "proto_yard")
	assert_eq(int(Dictionary(b["ledger"])["runs_completed"]), 1)


func test_loading_the_checkpoint_after_a_wipe_replays_the_fight() -> void:
	world.enter_shard("rusted_undercity", 7)
	var before := world.living_enemies().size()
	var target: EnemyActor = world.living_enemies()[0]
	world.teleport_party(target.cell + Vector2i(1, 0) if world.map_data.is_walkable(target.cell + Vector2i(1, 0)) else target.cell + Vector2i(0, 1))
	assert_true(world.check_encounters(), "adjacent enemy sees us")
	assert_eq(world.mode, "combat")
	var cp := SaveSystem.read(world.save_path("autosave"))
	assert_eq(Dictionary(cp["location"])["kind"], "shard")
	world._on_combat_ended("defeat")
	assert_eq(world.mode, "defeated")
	assert_eq(world.load_from(SaveSystem.AUTOSAVE), [])
	assert_eq(world.mode, "explore")
	assert_true(world.run.in_shard)
	assert_eq(world.living_enemies().size(), before, "nobody died in the checkpoint")
	for m: PartyMember in world.party.members:
		assert_true(world.map_data.is_walkable(world.member_cell(m)))
	assert_false(FileAccess.file_exists(world.save_path("slot_1")), "a load never writes a slot")
	var again := SaveSystem.read(world.save_path("autosave"))
	assert_eq(again["party"], cp["party"], "loading did not overwrite the checkpoint it read")


func test_yard_has_surfaces_and_party_has_class_resources() -> void:
	assert_eq(world.map_data.surface_at(Vector2i(9, 6)), "mana_pool")
	assert_eq(world.map_data.surface_at(Vector2i(13, 10)), "conduit")
	assert_eq(world.map_data.surface_at(Vector2i(7, 13)), "corrosive")
	assert_eq(world.map_data.height_at(Vector2i(2, 7)), 1)
	assert_eq(world.map_data.cover_at(Vector2i(7, 3)), 1, "debris gives cover")
	assert_eq(world.party.members[0].resource_id, "vent_heat", "Scrap-Knight")
	assert_eq(world.party.members[1].resource_id, "surge", "Aetherbinder")
	assert_eq(String(world.resource_def_for(world.party.members[0])["builds_on"]), "physical")
	world.teleport_party(Vector2i(13, 4))
	world.check_encounters()
	var s := world.combat.state
	var knight := s.by_id("p:weaver")
	assert_true(knight.has_resource())
	assert_eq(knight.resource_max(), 3)
	assert_true(knight.abilities.has("vent"))
	var caster := s.by_id("p:ash")
	assert_eq(caster.resource_id, "surge")
	for c: Combatant in s.active("enemy"):
		assert_false(c.has_resource(), "enemies have no class resource")
