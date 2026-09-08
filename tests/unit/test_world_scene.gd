## Instantiates the real exploration scene headless and drives it, including
## a full encounter through the combat controller with animation off.
extends TestCase

const DT := 1.0 / 60.0

var world: ExploreWorld


func before_each() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	_root().add_child(world)
	world.combat.animate = false


func after_each() -> void:
	_root().remove_child(world)
	world.free()


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
	var placed := world.map_view.ground.get_used_cells().size() + world.map_view.walls.get_used_cells().size()
	assert_eq(placed, world.map_data.width * world.map_data.height)
	assert_true(world.map_view.walls.get_used_cells().size() > 0, "walls placed on the wall layer")


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
