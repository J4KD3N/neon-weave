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
	assert_eq(world.party.members.size(), 3, "three preset members; the fourth slot is for a recruit")
	var spawns := world.map_data.spawn_cells()
	for i: int in 3:
		var m := world.party.members[i]
		assert_eq(m.position, world.map_view.cell_to_world(spawns[i]))
		assert_eq(m.is_leader, i == 0)
		assert_true(m.max_hp > 1)
		assert_eq(m.hp, m.max_hp)
		assert_true(m.abilities.size() >= 2)
	assert_eq(world.party.members[0].tint, Color.html("#ff7a6b"), "Scrap-Knight is Body coral")
	assert_eq(world.party.members[1].tint, Color.html("#b58cff"), "Aetherbinder is Arcane purple")
	assert_eq(world.party.members[0].max_hp, 22, "Trueborn Scrap-Knight: 20 + 2")
	assert_eq(world.party.members[2].max_hp, 20, "Synth Drone Shepherd: 16 + 4")
	assert_eq(world.party.members[2].tint, Color.html("#33e0d6"), "Drone Shepherd is Tech teal")
	assert_eq(world.party.members[2].resource_id, "scrap_charge")
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
	for i: int in range(1, world.party.members.size()):
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
	assert_eq(s.active("party").size(), 3)
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
	assert_eq(s.result, "victory", "seeded fight 3 vs 3 is expected to be won; seed %d" % world.combat_seed)


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
	assert_eq(world.party.members.size(), 3)
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
	assert_eq(world.ledger.buildings, {"beacon": 0, "medbay": 0, "workshop": 1, "arcanum": 0})
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


const VEX: Dictionary = {"name": "Vex", "race_id": "chromed", "origin_id": "corp_asset", "class_id": "circuit_witch", "attributes": {"body": 1, "arcane": 3, "tech": 2}}


func test_protagonist_replaces_the_leader_and_persists_through_saves() -> void:
	assert_eq(world.party.leader().member_id, "weaver")
	assert_eq(world.set_protagonist(VEX), [])
	var l := world.party.leader()
	assert_eq(l.member_id, PartyBuilder.PROTAGONIST_ID)
	assert_eq(l.display_name, "Vex")
	assert_eq(l.class_id, "circuit_witch")
	assert_eq(l.race_id, "chromed")
	assert_eq(l.origin_id, "corp_asset")
	assert_eq(l.resource_id, "hexes")
	assert_eq(l.tint, Color.html("#b58cff"))
	assert_eq(l.max_hp, 17)
	assert_true(l.is_leader)
	assert_eq(world.party.members.size(), 3)
	assert_eq(world.party.members[1].member_id, "ash")
	assert_eq(world.leader_cell(), world.map_data.spawn_cells()[0])
	assert_eq(world.save_slot(1), OK)
	var again := _fresh_scene()
	assert_eq(again.party.leader().member_id, "weaver", "a fresh scene starts with the preset")
	assert_eq(again.load_slot(1), [])
	assert_eq(again.party.leader().display_name, "Vex")
	assert_eq(again.party.leader().max_hp, 17)
	assert_eq(CharacterSheet.from_dict(again.protagonist).to_dict(), VEX, "ints survive the JSON float round trip")
	_drop(again)


func test_invalid_protagonist_is_refused() -> void:
	var bad := VEX.duplicate(true)
	bad["race_id"] = "elf"
	var errors := world.set_protagonist(bad)
	assert_any_contains(errors, "unknown race")
	assert_eq(world.party.leader().member_id, "weaver")
	assert_true(world.protagonist.is_empty())


func test_creator_opens_at_home_only_and_confirms() -> void:
	assert_true(world.open_creator())
	assert_true(world.creator_menu.visible)
	assert_contains(world.creator_menu.label.text, "NEW WEAVER")
	world.creator_state.sheet.name = "Kest"
	world.creator_state.adjust(1)
	var race := world.creator_state.sheet.race_id
	assert_true(world.confirm_creator())
	assert_false(world.creator_menu.visible)
	assert_eq(world.party.leader().display_name, "Kest")
	assert_eq(world.party.leader().race_id, race)
	world.enter_shard("rusted_undercity", 7)
	assert_false(world.open_creator(), "not in a Shard")
	assert_eq(world.party.leader().display_name, "Kest", "the protagonist walks into the Shard")


func test_sheet_actors_and_placeholder_actors_coexist() -> void:
	var leader := world.party.leader()
	assert_true(leader.uses_sheet(), "trueborn has a sheet")
	assert_true(world.party.members[1].uses_sheet(), "Ash is trueborn too")
	assert_false(world.party.members[2].uses_sheet(), "synth still uses the placeholder rig")
	assert_eq(leader.sprite.animation, &"idle_s")
	var scav := world.enemy_at(Vector2i(14, 2))
	assert_true(scav.uses_sheet())
	assert_eq(scav.tint, Color.html("#6b3f2e"), "biome recolour: scav -> rust")
	assert_false(world.enemy_at(Vector2i(17, 6)).uses_sheet(), "drone keeps its orb")
	assert_eq(world.sheets.size(), 2)


func test_walking_drives_the_sheet_animation() -> void:
	var leader := world.party.leader()
	world.command_move(Vector2i(6, 12))
	world.party.tick(DT)
	assert_true(String(leader.sprite.animation).begins_with("walk_"), "moving: %s" % leader.sprite.animation)
	_settle(3000)
	world.party.tick(DT)
	assert_true(String(leader.sprite.animation).begins_with("idle_"), "arrived: %s" % leader.sprite.animation)
	leader.play_action("attack", Vector2(1, 0))
	assert_eq(leader.sprite.animation, &"attack_w")
	assert_true(leader.sprite.flip_h)
	world.party.members[2].play_action("attack")
	assert_false(world.party.members[2].uses_sheet(), "placeholder actors ignore actions")


## With a 1-sided initiative die and first strike, the whole party acts
## first, in id order: p:ash, p:unit_9, p:weaver.
func _party_first_fight() -> CombatState:
	world.rules.initiative_die = 1
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	return world.combat.state


func test_tab_and_clicks_swap_within_the_party_group() -> void:
	var s := _party_first_fight()
	assert_eq(s.current().id, "p:ash")
	assert_eq(s.group.size(), 3, "three allies in a row form one group")
	assert_contains(world.hud.hint_label.text, "Tab or click swaps to Unit-9, Weaver")
	assert_true(world.combat.next_member())
	assert_eq(s.current().id, "p:unit_9")
	assert_contains(world.hud.turn_label.text, "Unit-9")
	var weaver := s.by_id("p:weaver")
	world.combat.player_click(weaver.cell)
	assert_eq(s.current(), weaver, "clicking an ally hands over")
	world.combat.end_player_turn()
	assert_true(s.has_acted(weaver))
	assert_eq(s.current().id, "p:ash", "the first member still to act")
	assert_contains(world.hud.order_label.text, "✓ Weaver")
	assert_contains(world.hud.order_label.text, "⇄ Unit-9")
	world.combat.player_click(weaver.cell)
	assert_eq(world.hud.hint_kind, CombatHud.HINT_WARN)
	assert_contains(world.hud.hint_label.text, "already acted")
	assert_eq(s.current().id, "p:ash")
	assert_true(world.combat.next_member())
	assert_eq(s.current().id, "p:unit_9")
	world.combat.end_player_turn()
	world.combat.end_player_turn()
	assert_true(world.combat.current_is_player() or s.finished, "enemies ran their turns synchronously")
	if not s.finished:
		assert_eq(s.round_number, 2)


func test_hover_previews_paths_attacks_and_swaps() -> void:
	var s := _party_first_fight()
	var actor := s.current()
	var reach: Array = s.reachable_cells(actor).keys()
	reach.sort()
	var far := actor.cell
	for cell: Vector2i in reach:
		if s.move_path(actor, cell).size() > s.move_path(actor, far).size():
			far = cell
	world.combat.hover(far)
	var path := world.highlighter.cells_in("c_path")
	assert_eq(path.size(), s.move_path(actor, far).size())
	assert_eq(path[path.size() - 1], far)
	assert_eq(world.hud.hint_kind, CombatHud.HINT_PREVIEW)
	assert_contains(world.hud.hint_label.text, "Move %d → %d Move left" % [path.size(), actor.move_left - path.size()])
	var foe := EnemyBrain.nearest_hostile(s, actor)
	world.combat.hover(foe.cell)
	assert_true(world.highlighter.cells_in("c_path").is_empty(), "no path over an enemy")
	if EnemyBrain.usable_ability(s, actor, foe).is_empty():
		assert_eq(world.hud.hint_kind, CombatHud.HINT_WARN)
		assert_contains(world.hud.hint_label.text, "Cannot reach %s" % foe.display_name)
	else:
		assert_eq(world.hud.hint_kind, CombatHud.HINT_PREVIEW)
		assert_contains(world.hud.hint_label.text, "% to hit")
	world.combat.hover(s.by_id("p:weaver").cell)
	assert_contains(world.hud.hint_label.text, "Weaver: click to swap")
	world.combat.hover(actor.cell)
	assert_eq(world.hud.hint_kind, CombatHud.HINT_NORMAL)
	assert_contains(world.hud.hint_label.text, "Space ends the turn")
	world.combat.select_ability(1)
	world.combat.hover(far)
	assert_true(world.highlighter.cells_in("c_path").is_empty(), "no move preview while aiming")
	world.combat.cancel_selection()


func test_refused_clicks_explain_themselves_in_red() -> void:
	var s := _party_first_fight()
	var actor := s.current()
	world.combat.player_click(Vector2i(0, 0))
	assert_eq(world.hud.hint_kind, CombatHud.HINT_WARN)
	assert_contains(world.hud.hint_label.text, "Cannot move there")
	var farthest: Combatant = null
	for c: Combatant in s.active("enemy"):
		if farthest == null or LineOfSight.distance(actor.cell, c.cell) > LineOfSight.distance(actor.cell, farthest.cell):
			farthest = c
	if EnemyBrain.usable_ability(s, actor, farthest).is_empty():
		world.combat.player_click(farthest.cell)
		assert_eq(world.hud.hint_kind, CombatHud.HINT_WARN)
		assert_contains(world.hud.hint_label.text, "Cannot reach %s" % farthest.display_name)
		assert_contains(world.hud.hint_label.text, "out of range")
	assert_eq(s.current(), actor, "refusals change nothing")
	assert_eq(actor.ap, 4)


func test_pad_cursor_moves_confirms_and_the_mouse_releases_it() -> void:
	assert_eq(world.combat.move_cursor(Vector2(1, 0)), Vector2i(-1, -1), "no cursor outside combat")
	var s := _party_first_fight()
	var actor := s.current()
	var reach := s.reachable_cells(actor)
	var dir := Vector2.ZERO
	for candidate: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]:
		if reach.has(actor.cell + IsoCursor.step(candidate)):
			dir = candidate
			break
	assert_true(dir != Vector2.ZERO, "some neighbour is reachable")
	var origin := world.map_view.cell_to_world(actor.cell)
	var right := world.map_view.cell_to_world(actor.cell + IsoCursor.step(Vector2(1, 0)))
	var up := world.map_view.cell_to_world(actor.cell + IsoCursor.step(Vector2(0, -1)))
	assert_true(right.x > origin.x and is_equal_approx(right.y, origin.y), "a step right stays level on screen")
	assert_true(up.y < origin.y and is_equal_approx(up.x, origin.x), "a step up stays centred on screen")
	var cell := world.combat.move_cursor(dir)
	assert_eq(cell, actor.cell + IsoCursor.step(dir), "first step starts from the acting member")
	assert_true(world.combat.cursor_active)
	assert_eq(world.hover_override, cell)
	assert_eq(world.highlighter.cells_in("e_cursor"), [cell])
	assert_eq(world.highlighter.cells_in("c_path"), [cell], "the cursor hovers like a mouse")
	assert_contains(world.hud.hint_label.text, "Move 1")
	var move_before := actor.move_left
	assert_true(world.combat.confirm())
	assert_eq(actor.cell, cell, "confirm acts on the cursor cell")
	assert_eq(actor.move_left, move_before - 1)
	assert_eq(world.highlighter.cells_in("e_cursor"), [cell], "cursor survives the move")
	var edge := world.combat.move_cursor(Vector2(0, -1))
	for _i: int in 60:
		edge = world.combat.move_cursor(Vector2(0, -1))
	assert_true(world.map_data.in_bounds(edge), "clamped to the map")
	world._unhandled_input(InputEventMouseMotion.new())
	assert_false(world.combat.cursor_active)
	assert_eq(world.hover_override, Vector2i(-1, -1))
	assert_true(world.highlighter.cells_in("e_cursor").is_empty())
	assert_false(world.combat.confirm(), "nothing to confirm without a cursor")


func test_system_menu_routes_every_keyboard_only_action() -> void:
	assert_true(world.open_system_menu())
	assert_true(world.system_menu.visible)
	var ids: PackedStringArray = []
	for item: Dictionary in world.system_items():
		if not String(item["id"]).begins_with("shard_"):
			ids.append(String(item["id"]))
	assert_eq(ids, PackedStringArray(ExploreWorld.SYSTEM_ITEM_IDS))
	assert_contains(world.system_menu.label.text, "▶ Resume")
	assert_contains(world.system_menu.label.text, "Return to the yard (haul is lost)  (unavailable: already home)")
	assert_contains(world.system_menu.label.text, "Load slot 1 — empty  (unavailable: empty)")
	assert_contains(world.system_menu.label.text, "Save slot 3 — empty")
	assert_false(world.activate_system_item("go_home"), "disabled items refuse")
	assert_true(world.system_menu.visible, "and the menu stays open")
	assert_true(world.activate_system_item("save_1"))
	assert_false(world.system_menu.visible, "activating closes it")
	assert_true(FileAccess.file_exists(world.save_path(SaveSystem.slot_name(1))))
	assert_true(world.open_system_menu())
	assert_true(world.activate_system_item("bastion"))
	assert_true(world.bastion_menu.visible)
	assert_false(world.open_system_menu(), "not over another menu")
	world.toggle_bastion()
	assert_true(world.open_system_menu())
	assert_true(world.activate_system_item("new_shard"))
	assert_false(world.at_home())
	assert_true(world.open_system_menu())
	assert_true(world.activate_system_item("go_home"))
	assert_true(world.at_home())
	assert_true(world.open_system_menu())
	assert_true(world.activate_system_item("load_1"))
	assert_true(world.at_home())
	assert_false(world.activate_system_item("nonsense"))
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	assert_false(world.open_system_menu(), "no pausing a fight")
	assert_eq(world.mode, "combat")


func test_menus_take_a_cursor_and_confirm() -> void:
	assert_true(world.talk_to("sera"))
	assert_eq(world.dialogue_menu.cursor, 0)
	assert_contains(world.dialogue_menu.label.text, "▶ [1]")
	assert_eq(world.dialogue_menu.move(1), 1)
	assert_contains(world.dialogue_menu.label.text, "▶ [2]")
	assert_eq(world.dialogue_menu.move(1), 0, "wraps")
	world.dialogue_menu.move(-1)
	assert_eq(world.dialogue_menu.cursor, 1)
	var node_before := world.dialogue.node_id
	assert_true(world.confirm_dialogue())
	assert_true(world.dialogue.node_id != node_before or not world.in_dialogue(), "confirm picked the cursor line")
	if world.in_dialogue():
		assert_eq(world.dialogue_menu.cursor, 0, "a new node resets the cursor")
		world.leave_dialogue()
	assert_false(world.confirm_dialogue(), "nothing to confirm outside dialogue")
	assert_true(world.toggle_bastion())
	assert_eq(world.bastion_menu.cursor, 0)
	assert_contains(world.bastion_menu.label.text, "▶ [1] Beacon")
	assert_eq(world.bastion_menu.move(1), 1)
	world.bastion_menu.refresh(world.bastion, world.ledger)
	assert_contains(world.bastion_menu.label.text, "▶ [2]")
	var id := world.bastion.order[1]
	var affordable := world.bastion.can_upgrade(id, world.ledger).is_empty()
	var level := world.bastion.level(id)
	assert_eq(world.confirm_bastion(), affordable)
	assert_eq(world.bastion.level(id), level + 1 if affordable else level)
	world.toggle_bastion()
	assert_false(world.confirm_bastion())


func test_interact_talks_nearby_and_extracts_on_the_pad() -> void:
	world.teleport_party(Vector2i(9, 9))
	assert_false(world.interact(), "nothing near")
	world.teleport_party(Vector2i(5, 4))
	assert_true(world.interact())
	assert_true(world.in_dialogue())
	assert_eq(world.dialogue.speaker(), "sera")
	assert_false(world.interact(), "not while talking")
	world.leave_dialogue()
	world.enter_shard("rusted_undercity", 7)
	world.teleport_party(world.extraction_cell())
	assert_true(world.can_extract())
	assert_true(world.interact())
	assert_true(world.at_home(), "confirm on the pad extracts")
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	assert_false(world.interact(), "not in combat")


func test_camera_follows_the_acting_combatant_and_returns_to_the_leader() -> void:
	var s := _party_first_fight()
	assert_eq(world.camera.target, world.combat.actors["p:ash"], "Ash acts first, and Ash is not the leader")
	world.combat.next_member()
	var acting := s.current()
	assert_eq(world.camera.target, world.combat.actors[acting.id])
	world.combat.end_player_turn()
	world.combat.end_player_turn()
	world.combat.end_player_turn()
	if not s.finished:
		assert_true(world.combat.current_is_player())
		assert_eq(world.camera.target, world.combat.actors[s.current().id], "back on the party after the enemy round")
	world.mode = "combat"
	world.combat._finish()
	assert_eq(world.camera.target, world.party.leader(), "exploration follows the leader")


func test_esc_undoes_a_move_when_nothing_is_aimed() -> void:
	var s := _party_first_fight()
	var actor := s.current()
	var reach: Array = s.reachable_cells(actor).keys()
	reach.sort()
	var cell: Vector2i = reach[0]
	var from := actor.cell
	world.combat.player_click(cell)
	assert_eq(actor.cell, cell)
	assert_contains(world.hud.hint_label.text, "Esc undoes the move")
	world.combat.select_ability(0)
	world.combat.cancel_selection()
	assert_eq(actor.cell, cell, "first Esc only clears the aim")
	assert_eq(world.combat.selected_ability, "")
	world.combat.cancel_selection()
	assert_eq(actor.cell, from, "second Esc takes the move back")
	assert_eq(actor.move_left, actor.move_max)
	assert_eq(world.combat.actors[actor.id].position, world.map_view.cell_to_world(from))
	assert_false(world.hud.hint_label.text.contains("Esc undoes"))


func test_system_menu_offers_all_three_slots() -> void:
	assert_eq(world.save_slot(2), OK)
	world.open_system_menu()
	var text: String = world.system_menu.label.text
	assert_contains(text, "Save slot 1 — empty")
	assert_contains(text, "Save slot 2 — Proto Yard")
	assert_contains(text, "Load slot 2 — Proto Yard")
	assert_contains(text, "Load slot 3 — empty  (unavailable: empty)")
	assert_contains(text, "Load the autosave")
	assert_true(world.activate_system_item("save_3"))
	assert_true(FileAccess.file_exists(world.save_path(SaveSystem.slot_name(3))))
	world.enter_shard("rusted_undercity", 7)
	world.open_system_menu()
	assert_true(world.activate_system_item("load_2"))
	assert_true(world.at_home(), "slot 2 was saved at home")
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	var blocked := false
	for item: Dictionary in world.system_items():
		if String(item["id"]) == "save_1":
			blocked = not bool(item["enabled"])
	assert_true(blocked, "saving is unavailable in combat")



func test_level_up_on_extraction_grows_stats_in_place() -> void:
	var weaver := world.member_by_id("weaver")
	assert_eq(world.party_level(), 1)
	assert_eq(weaver.level, 1)
	assert_eq(weaver.max_hp, 22)
	world.ledger.xp = 14
	world.enter_shard("rusted_undercity", 7)
	world.run.collect({"xp": 30})
	weaver.hp = 10
	world.teleport_party(world.extraction_cell())
	assert_true(world.extract())
	assert_eq(world.ledger.xp, 44)
	assert_eq(world.party_level(), 3, "44 XP is level 3 on the base curve")
	assert_eq(weaver.level, 3)
	assert_eq(weaver.max_hp, 26, "+2 HP per level after the first")
	assert_true(weaver.hp >= 14, "current HP moved with the max (then the Med-bay may have healed)")
	assert_contains(world.xp_line(), "36 to next")
	for m: PartyMember in world.party.members:
		assert_eq(m.level, 3)
		assert_eq(m.subclass_id, "", "no subclass until chosen")


func test_subclass_and_talents_persist_through_save_and_load() -> void:
	world.ledger.xp = 40
	world.refresh_progression()
	assert_eq(world.party_level(), 3)
	assert_eq(world.choose_subclass("weaver", "juggernaut"), "")
	var weaver := world.member_by_id("weaver")
	assert_eq(weaver.subclass_id, "juggernaut")
	assert_true(weaver.abilities.has("charge_slam"))
	assert_eq(weaver.damage_bonus, 1)
	assert_eq(weaver.stats["move"], 6, "Juggernaut +1 Move")
	assert_eq(world.choose_subclass("weaver", "warden"), "needs the Arcanum to change")
	assert_eq(world.choose_subclass("weaver", "stormcaller"), "not a subclass of this class")
	assert_eq(world.choose_subclass("nobody", "warden"), "no such member")
	assert_eq(world.buy_talent("weaver", "iron_skin"), "needs 2 Aether")
	world.ledger.bank({"aether": 5})
	assert_eq(world.buy_talent("weaver", "iron_skin"), "")
	assert_eq(world.ledger.total("aether"), 3)
	assert_eq(weaver.max_hp, 26 + 3)
	assert_eq(world.buy_talent("weaver", "plated_bones"), "tier 2 opens later")
	assert_eq(world.buy_talent("weaver", "iron_skin"), "already learned")
	assert_eq(world.build_for("weaver"), {"subclass": "juggernaut", "talents": ["iron_skin"]})
	assert_eq(world.save_slot(1), OK)
	var again := _fresh_scene()
	assert_eq(again.load_slot(1), [])
	var back := again.member_by_id("weaver")
	assert_eq(back.level, 3)
	assert_eq(back.subclass_id, "juggernaut")
	assert_true(back.abilities.has("charge_slam"))
	assert_eq(back.max_hp, 29)
	assert_eq(back.damage_bonus, 1)
	again.teleport_party(Vector2i(13, 4))
	again.start_combat(true)
	var c := again.combat.state.by_id("p:weaver")
	assert_eq(c.damage_bonus, 1, "subclass damage bonus reaches combat")
	assert_true(c.abilities.has("charge_slam"))
	_drop(again)


func test_respec_needs_the_arcanum_and_refunds_aether() -> void:
	world.ledger.xp = 40
	world.ledger.bank({"aether": 2})
	world.refresh_progression()
	assert_eq(world.choose_subclass("weaver", "warden"), "")
	assert_eq(world.buy_talent("weaver", "iron_skin"), "")
	var weaver := world.member_by_id("weaver")
	assert_eq(weaver.max_hp, 26 + 4 + 3)
	assert_eq(world.respec("weaver"), "needs the Arcanum")
	world.ledger.bank({"salvage": 10, "aether": 2})
	assert_true(world.upgrade_building("arcanum"))
	assert_true(world.can_respec())
	assert_eq(world.respec("weaver"), "")
	assert_eq(world.ledger.total("aether"), 1, "half of the 2 Aether talent came back")
	assert_eq(world.build_for("weaver"), {"subclass": "", "talents": []})
	assert_eq(weaver.subclass_id, "")
	assert_false(weaver.abilities.has("shield_bash"))
	assert_eq(weaver.max_hp, 26)
	assert_eq(world.respec("weaver"), "nothing to reset")
	assert_eq(world.choose_subclass("weaver", "juggernaut"), "", "free to pick again")
	assert_eq(world.choose_subclass("weaver", "warden"), "", "the Arcanum allows changing")


func test_weave_menu_rows_and_navigation() -> void:
	assert_true(world.open_weave())
	assert_true(world.weave_menu.visible)
	var text: String = world.weave_menu.label.text
	assert_contains(text, "THE WEAVE")
	assert_contains(text, "Party level 1")
	assert_contains(text, "Weaver — Trueborn Scrap-Knight (no subclass)")
	assert_contains(text, "Juggernaut — Charges; the wall that moves.  (needs level 3)")
	assert_contains(text, "T1 Iron Skin — +3 max HP. (2 Aether)  (needs 2 Aether)")
	assert_contains(text, "Reset subclass and talents (0% Aether back)  (needs the Arcanum)")
	world.weave_member(1)
	assert_contains(world.weave_menu.label.text, "Ash —")
	world.weave_member(-1)
	assert_contains(world.weave_menu.label.text, "Weaver —")
	assert_false(world.confirm_weave(), "a disabled row does nothing")
	world.ledger.xp = 40
	world.ledger.bank({"aether": 2})
	world.refresh_progression()
	world.refresh_weave()
	assert_eq(world.weave_menu.cursor, 0)
	assert_true(world.confirm_weave(), "row 0 is the first subclass")
	assert_eq(world.member_by_id("weaver").subclass_id, "juggernaut")
	assert_contains(world.weave_menu.label.text, "✓ Juggernaut")
	var rows := world.weave_rows("weaver")
	var kinds: PackedStringArray = []
	for r: Dictionary in rows:
		if not kinds.has(String(r["kind"])):
			kinds.append(String(r["kind"]))
	assert_eq(kinds, PackedStringArray(["subclass", "talent", "respec"]))
	world.close_weave()
	assert_false(world.weave_menu.visible)
	world.enter_shard("rusted_undercity", 7)
	assert_false(world.open_weave(), "home only")



func test_depth_three_is_measurably_harder_and_posts_a_boss() -> void:
	var shallow := world.enter_shard("rusted_undercity", 7, 1)
	var shallow_count := world.living_enemies().size()
	var shallow_hp := 0
	for e: EnemyActor in world.living_enemies():
		shallow_hp += e.max_hp
		assert_eq(e.tier, "", "no tiers at depth 1")
	assert_eq(world.map_depth(), 1)
	var deep := world.enter_shard("rusted_undercity", 7, 3)
	assert_eq(world.map_depth(), 3)
	assert_eq(deep["rows"], shallow["rows"], "same layout, different population")
	var deep_hp := 0
	var boss: EnemyActor = null
	for e: EnemyActor in world.living_enemies():
		deep_hp += e.max_hp
		if e.tier == "boss":
			boss = e
	assert_true(world.living_enemies().size() > shallow_count, "more bodies")
	assert_true(deep_hp > shallow_hp * 1.3, "and tougher ones: %d vs %d" % [deep_hp, shallow_hp])
	assert_true(boss != null, "the Warlord guards depth 3")
	assert_eq(boss.enemy_id, "undercity_warlord")
	assert_eq(boss.max_hp, int(round(16 * 3.0 * 1.3)), "boss x3, depth x1.3")
	assert_eq(boss.damage_bonus, 2 + 1)
	assert_eq(boss.ap_bonus, 1)
	assert_true(LineOfSight.distance(boss.cell, world.extraction_cell()) <= 3, "posted by the pad")
	var scav := world.registry.get_entry("enemies", "scav")
	var deep_scav := StatBlock.for_enemy(scav, world.rules, 3)
	assert_true(int(deep_scav["hp"]) > int(scav["stats"]["hp"]), "every enemy scales with depth")


func test_summoner_spawns_a_world_actor_mid_fight() -> void:
	var mother := world.spawn_summoned("drone_mother", Vector2i(12, 4))
	assert_true(mother != null)
	assert_eq(mother.archetype, "summoner")
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(false)
	var s := world.combat.state
	var before := world.living_enemies().size()
	var guard := 0
	while s.round_number < 3 and not s.finished and guard < 40:
		guard += 1
		if world.combat.current_is_player():
			world.combat.end_player_turn()
	var summoned := 0
	for c: Combatant in s.combatants:
		if c.summoned_by.is_empty():
			continue
		summoned += 1
		var node: WorldActor = world.combat.actors.get(c.id)
		assert_true(node != null and is_instance_valid(node), "summon %s has a world actor" % c.id)
		assert_eq((node as EnemyActor).enemy_id, "feral_drone")
		assert_true(world.enemies.has(node as EnemyActor), "tracked with the other enemies")
	assert_true(summoned >= 1, "the Drone-Mother called at least one drone by round %d" % s.round_number)
	assert_true(world.enemies.size() >= before + summoned - 0, "summons join the enemy list")
	assert_any_contains(s.history, "calls in Feral Drone")



func test_beacon_level_two_unlocks_the_datacore_for_launch() -> void:
	assert_eq(world.selected_shard, "rusted_undercity")
	assert_eq(world.shard_locked_reason("verdant_datacore"), "the Beacon has not found it yet")
	assert_eq(world.shard_locked_reason("nowhere"), "unknown Shard")
	assert_false(world.launch_shard("verdant_datacore"), "locked at Beacon level 1")
	assert_true(world.at_home())
	world.open_system_menu()
	var row: Dictionary = {}
	for item: Dictionary in world.system_items():
		if String(item["id"]) == "shard_verdant_datacore":
			row = item
	assert_false(row.is_empty(), "the Datacore is listed")
	assert_false(bool(row["enabled"]))
	assert_contains(world.system_menu.label.text, "Launch instead: Verdant Datacore Shard  (unavailable: the Beacon has not found it yet)")
	world.close_system_menu()
	world.ledger.bank({"salvage": 15, "aether": 2})
	assert_true(world.upgrade_building("beacon"))
	assert_eq(world.bastion.unlocks(), ["verdant_datacore"])
	assert_true(world.bastion.has_unlocked("verdant_datacore"))
	assert_true(world.bastion.has_unlocked(""), "no requirement is always met")
	assert_eq(world.shard_locked_reason("verdant_datacore"), "")
	assert_true(world.launch_shard("verdant_datacore"))
	assert_eq(world.selected_shard, "verdant_datacore")
	assert_false(world.at_home())
	assert_eq(world.map_data.biome_id, "verdant_datacore")
	assert_eq(world.map_depth(), 2, "Beacon level 2 is depth 2")
	var families: Dictionary = {}
	for e: EnemyActor in world.living_enemies():
		families[String(e.entry.get("family", ""))] = true
	assert_eq(families.keys(), ["verdant_datacore"], "only the Datacore family spawns here")
	world.enter_map(ExploreWorld.HOME_MAP)
	world.open_system_menu()
	assert_contains(world.system_menu.label.text, "Launch a new Shard: Verdant Datacore Shard")
	assert_contains(world.system_menu.label.text, "Launch instead: Rusted Undercity Shard")
	world.close_system_menu()
	assert_true(world.activate_system_item("shard_rusted_undercity"))
	assert_eq(world.selected_shard, "rusted_undercity")
	assert_eq(world.map_data.biome_id, "rusted_undercity")


func test_spores_shroud_the_target_in_a_real_fight() -> void:
	world.enter_shard("verdant_datacore", 3)
	var spore_cells: Array[Vector2i] = []
	for y: int in world.map_data.height:
		for x: int in world.map_data.width:
			if world.map_data.surface_at(Vector2i(x, y)) == "spore":
				spore_cells.append(Vector2i(x, y))
	if spore_cells.is_empty():
		return # this seed grew none; the generator test covers coverage across seeds
	var free := world.map_data.nearest_free_cells(spore_cells[0], 1, spore_cells)
	assert_false(free.is_empty())
	world.teleport_party(free[0])
	var foe := world.living_enemies()[0]
	foe.cell = spore_cells[0]
	foe.position = world.map_view.cell_to_world(foe.cell)
	world.rules.initiative_die = 1
	world.start_combat(true)
	var s := world.combat.state
	var attacker := s.current()
	attacker.cell = free[0]
	var target := s.occupant(spore_cells[0])
	assert_true(target != null, "the foe stands in the spores")
	var plain := s.hit_chance(attacker, s.abilities["strike"], target, false, 0)
	var mods := s.attack_modifiers(attacker, s.abilities["strike"], target)
	assert_eq(int(mods["shroud"]), 10)
	assert_true(s.hit_chance(attacker, s.abilities["strike"], target, false, int(mods["hit"])) <= plain - 10 or plain <= world.rules.min_hit_chance + 10)



# --- S18: Shard features in the real scene ----------------------------------

func _enter_featured_shard() -> Dictionary:
	for seed_value: int in range(1, 40):
		var e := world.enter_shard("rusted_undercity", seed_value)
		if Array(e["secrets"]).size() >= 1 and Array(e["vaults"]).size() >= 1 and Array(e["waypoints"]).size() >= 1 and Array(e["npcs"]).size() >= 1:
			return e
	return {}


static func _v(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))


func test_secret_doors_give_when_the_party_stands_beside_them() -> void:
	var e := _enter_featured_shard()
	assert_false(e.is_empty())
	var secret: Dictionary = e["secrets"][0]
	var door := _v(secret["door"])
	var inside := _v(secret["cells"][0])
	assert_eq(world.map_data.door_kind(door), "secret")
	assert_false(world.map_data.is_walkable(door))
	var outside := door + (door - inside)
	assert_true(world.map_data.is_walkable(outside), "the room side of the door")
	world.teleport_party(outside)
	assert_true(world.leader_cell() == outside or LineOfSight.distance(world.leader_cell(), door) <= 2)
	var free := world.map_data.nearest_free_cells(outside, 1, [])
	world.party.leader().position = world.map_view.cell_to_world(outside)
	assert_eq(world.check_secrets(), 1, "one door gives")
	assert_eq(world.map_data.door_kind(door), "")
	assert_true(world.map_data.is_walkable(door), "opened doors are floor")
	assert_eq(world.run.opened, [[door.x, door.y]])
	assert_eq(world.check_secrets(), 0, "and stays open")
	assert_true(free.size() >= 1)
	var reach := ShardValidator.reachable_from(world.map_data, world.leader_cell())
	assert_true(reach.has(inside), "the pocket is reachable now")
	assert_eq(world.save_slot(2), OK)
	var again := _fresh_scene()
	assert_eq(again.load_slot(2), [])
	assert_true(again.map_data.is_walkable(door), "a reload keeps the passage open")
	assert_eq(again.run.opened, [[door.x, door.y]])
	_drop(again)


func test_vault_doors_cost_a_cipher_and_hold_rare_loot() -> void:
	var e := _enter_featured_shard()
	var vault: Dictionary = e["vaults"][0]
	var door := _v(vault["door"])
	var inside := _v(vault["cells"][0])
	var outside := door + (door - inside)
	world.teleport_party(outside)
	world.party.leader().position = world.map_view.cell_to_world(outside)
	assert_eq(world.adjacent_door(), door)
	assert_contains(world.status_line(), "VAULT DOOR")
	world.ledger.resources["ciphers"] = 0
	assert_eq(world.open_vault(door), "needs %s" % BastionState.describe_cost({"ciphers": 1}))
	assert_false(world.interact(), "interact refuses too")
	assert_eq(world.map_data.door_kind(door), "vault")
	world.ledger.resources["ciphers"] = 2
	assert_true(world.interact(), "Enter / A opens it")
	assert_eq(world.ledger.total("ciphers"), 1, "one Cipher spent")
	assert_eq(world.map_data.door_kind(door), "")
	assert_eq(world.open_vault(door), "not a vault door")
	var loot := 0
	for p: PickupActor in world.remaining_pickups():
		for raw: Array in vault["cells"]:
			if p.cell == _v(raw):
				loot += 1
				assert_true(["rare", "epic"].has(p.rarity))
				assert_true(p.tint == world.rarity_color(p.rarity), "rare loot is tinted")
	assert_true(loot >= 2)


func test_relay_waypoint_banks_the_haul_and_a_wipe_cannot_take_it() -> void:
	var e := _enter_featured_shard()
	var w := _v(e["waypoints"][0])
	world.run.collect({"salvage": 7, "aether": 2, "xp": 3})
	world.teleport_party(w)
	world.party.leader().position = world.map_view.cell_to_world(w)
	assert_eq(world.on_waypoint(), w)
	assert_contains(world.status_line(), "RELAY WAYPOINT")
	var banked_before := world.ledger.total("salvage")
	assert_true(world.bank_at_waypoint())
	assert_eq(world.ledger.total("salvage"), banked_before + 7)
	assert_eq(world.ledger.xp, 3)
	assert_true(world.run.is_empty(), "the haul is empty but the run goes on")
	assert_true(world.run.in_shard)
	assert_eq(world.run.waypoints_used, [[w.x, w.y]])
	assert_eq(world.on_waypoint(), Vector2i(-1, -1), "one use")
	assert_false(world.bank_at_waypoint())
	world.run.collect({"salvage": 4})
	world.mode = "combat"
	for m: PartyMember in world.party.members:
		m.hp = 0
		m.downed = true
	world._on_combat_ended("defeat")
	assert_eq(world.mode, "defeated")
	world.return_home()
	assert_eq(world.ledger.total("salvage"), banked_before + 7, "the relay bank survived the wipe; the later 4 did not")


func test_merchant_trades_from_the_banked_ledger() -> void:
	var e := _enter_featured_shard()
	var m := _v(e["npcs"][0]["cell"])
	var trader := world.npc_at(m)
	assert_true(trader != null and trader.is_merchant())
	assert_eq(trader.merchant_id, "undercity_fence")
	var free := world.map_data.nearest_free_cells(m, 1, [m])
	world.teleport_party(free[0])
	world.party.leader().position = world.map_view.cell_to_world(free[0])
	assert_eq(world.merchant_near(), trader)
	assert_contains(world.status_line(), "The Fence")
	world.ledger.resources["salvage"] = 0
	assert_true(world.interact(), "Enter / A opens the stock")
	assert_true(world.merchant_menu.visible)
	var six := BastionState.describe_cost({"salvage": 6})
	assert_contains(world.merchant_menu.label.text, "Field medkit: heal the party by half — %s  (needs %s)" % [six, six])
	assert_eq(world.buy("medkit"), "needs %s" % six)
	assert_eq(world.buy("nothing"), "no such item")
	world.ledger.resources["salvage"] = 20
	var leader := world.party.leader()
	leader.hp = 4
	world.refresh_merchant()
	assert_true(world.confirm_merchant(), "row 0 is the medkit")
	assert_eq(world.ledger.total("salvage"), 14)
	assert_eq(leader.hp, mini(leader.max_hp, 4 + int(ceil(leader.max_hp * 0.5))))
	assert_eq(world.buy("cipher"), "needs %s" % BastionState.describe_cost({"salvage": 15}))
	assert_eq(world.buy("aether"), "")
	assert_eq(world.ledger.total("salvage"), 6)
	assert_eq(world.ledger.total("aether"), 2)
	world.close_merchant()
	assert_false(world.merchant_menu.visible)
	assert_eq(world.current_merchant, "")


func test_rarity_multiplies_grants() -> void:
	assert_eq(world.rarity_multiplier("common"), 1.0)
	assert_eq(world.rarity_multiplier("epic"), 4.0)
	assert_eq(ExploreWorld.scale_grants({"salvage": [2, 5], "xp": 1, "cipher_chance": 0.1}, 2.0), {"salvage": [4, 10], "xp": 2, "cipher_chance": 0.2})
	world.enter_shard("rusted_undercity", 7)
	var rare: PickupActor = null
	for p: PickupActor in world.remaining_pickups():
		if p.rarity != "common":
			rare = p
			break
	if rare == null:
		return
	var reach := ShardValidator.reachable_from(world.map_data, world.leader_cell())
	if not reach.has(rare.cell):
		return
	world.teleport_party(rare.cell)
	world.party.leader().position = world.map_view.cell_to_world(rare.cell)
	var gained := world.check_pickups()
	assert_eq(gained.size(), 1)
	assert_eq(gained[0]["rarity"], rare.rarity)
	var mult := world.rarity_multiplier(rare.rarity)
	var span: Array = Dictionary(rare.grants()).get("salvage", [0, 0])
	assert_true(int(gained[0]["salvage"]) >= int(round(float(span[0]) * mult)), "scaled minimum")
