## Instantiates the real exploration scene headless and drives it.
extends TestCase

const DT := 1.0 / 60.0

var world: ExploreWorld


func before_each() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	_root().add_child(world)


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


func test_party_spawns_on_spawn_cells_with_class_colours() -> void:
	assert_eq(world.party.members.size(), 4)
	var spawns := world.map_data.spawn_cells()
	for i: int in 4:
		var m := world.party.members[i]
		assert_eq(m.position, world.map_view.cell_to_world(spawns[i]))
		assert_eq(m.is_leader, i == 0)
	assert_eq(world.party.members[0].tint, Color.html("#ff7a6b"), "Scrap-Knight is Body coral")
	assert_eq(world.party.members[1].tint, Color.html("#b58cff"), "Aetherbinder is Arcane purple")
	assert_eq(world.leader_cell(), spawns[0])


func test_click_move_walks_leader_to_cell() -> void:
	var target := Vector2i(12, 13)
	assert_true(world.map_data.is_walkable(target))
	assert_true(world.command_move(target))
	assert_true(world.party.is_moving())
	var ticks := _settle(3000)
	assert_false(world.party.is_moving(), "arrived within %d ticks" % ticks)
	assert_eq(world.leader_cell(), target)
	assert_true(world.party.leader().position.is_equal_approx(world.map_view.cell_to_world(target)))


func test_move_to_blocked_or_unreachable_cell_is_refused() -> void:
	assert_false(world.command_move(Vector2i(0, 0)), "wall")
	assert_false(world.command_move(Vector2i(7, 3)), "debris")
	assert_false(world.command_move(Vector2i(-5, 2)), "off map")
	assert_false(world.party.is_moving())


func test_move_to_own_cell_is_trivially_accepted() -> void:
	assert_true(world.command_move(world.leader_cell()))
	assert_false(world.party.is_moving())


func test_followers_trail_leader_over_walkable_cells() -> void:
	world.command_move(Vector2i(12, 13))
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
	# Now push into the top wall repeatedly: position must settle, not tunnel.
	var before := world.party.leader().position
	for _i: int in 600:
		world.party.steer_leader(Vector2.UP, DT, world.map_view.is_walkable_world)
	assert_true(world.map_data.is_walkable(world.leader_cell()))
	assert_true(world.party.leader().position.y <= before.y)


func test_status_line_mentions_map_and_leader() -> void:
	var line := world.status_line()
	assert_contains(line, "Proto Yard")
	assert_contains(line, "leader (2, 2)")
