## Movement (S69, D-125): the leader and the followers cannot stand in an
## enemy or an NPC, a click path goes round whoever is in the way,
## followers keep a gap from those ahead of them, the party steps into
## its combat cells, and the pad cursor glides between cells.
extends TestCase

const DT := 1.0 / 60.0
const LEDGER := "user://test_ledger_move.json"
const SAVES := "user://test_saves_move"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	world.settings_path = "user://test_settings_move.json"
	world.input_path = "user://test_input_move.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.combat.animate = false


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


func _settle(max_ticks: int) -> int:
	var ticks := 0
	while world.party.is_moving() and ticks < max_ticks:
		world.party.tick(DT)
		ticks += 1
	return ticks


func test_nobody_walks_into_an_enemy_or_an_npc() -> void:
	var scav := world.enemy_at(Vector2i(14, 2))
	assert_true(scav != null)
	assert_true(world.npc_at(Vector2i(5, 3)) != null, "Sera waits in the yard")
	assert_false(world.can_stand_world(world.map_view.cell_to_world(Vector2i(14, 2))), "an enemy's cell")
	assert_false(world.can_stand_world(world.map_view.cell_to_world(Vector2i(5, 3))), "an NPC's cell")
	assert_true(world.can_stand_world(world.map_view.cell_to_world(Vector2i(4, 3))))
	assert_false(world.can_stand_world(world.map_view.cell_to_world(Vector2i(0, 0))), "a wall")
	assert_true(world.occupied_cells().has(Vector2i(14, 2)) and world.occupied_cells().has(Vector2i(5, 3)))
	# Steering into Sera holds at the cell before her.
	world.teleport_party(Vector2i(3, 3))
	var east := (world.map_view.cell_to_world(Vector2i(4, 3)) - world.map_view.cell_to_world(Vector2i(3, 3))).normalized() # grid east on screen
	for _i: int in 400:
		world.party.steer_leader(east, DT, Callable(world, "can_stand_world"))
		world.party.tick(DT)
		assert_true(world.leader_cell() != Vector2i(5, 3), "never in Sera")
	assert_true(world.leader_cell() != Vector2i(5, 3) and world.leader_cell().x <= 5, "held at or beside her: %s" % world.leader_cell())
	# A click on an occupied cell is refused; a path goes round.
	assert_false(world.command_move(Vector2i(5, 3)), "no walking into Sera")
	assert_false(world.command_move(Vector2i(14, 2)), "nor into a scav")
	world.teleport_party(Vector2i(3, 3))
	var path := world.map_view.path_to(world.party.leader().position, Vector2i(8, 3), world.occupied_cells())
	assert_false(path.is_empty(), "there is a way round")
	for p: Vector2 in path:
		assert_true(world.map_view.world_to_cell(p) != Vector2i(5, 3), "the path does not pass through Sera: %s" % [path])
	assert_true(world.command_move(Vector2i(8, 3)))
	_settle(3000)
	assert_eq(world.leader_cell(), Vector2i(8, 3))
	# Followers hold rather than walk into anyone.
	assert_true(world.party.can_stand.is_valid(), "the world answers for the followers")
	assert_false(bool(world.party.can_stand.call(world.map_view.cell_to_world(Vector2i(14, 2)))))


func test_followers_keep_a_gap_from_those_ahead() -> void:
	assert_eq(Party.MIN_GAP, 14.0)
	world.command_move(Vector2i(6, 12))
	_settle(3000)
	for _i: int in 600:
		world.party.tick(DT)
	var members := world.party.members
	for i: int in range(1, members.size()):
		for j: int in i:
			var d := members[i].position.distance_to(members[j].position)
			assert_true(d >= Party.MIN_GAP - 0.5, "member %d keeps its gap from member %d: %.1f" % [i, j, d])
	# The rule itself: a follower whose next step would crowd the one ahead holds.
	var l := world.party.leader()
	var f := members[1]
	var before := f.position
	f.position = l.position + Vector2(Party.MIN_GAP + 30.0, 0.0)
	world.party.trail.reset(l.position)
	world.party.trail.push(l.position + Vector2(1.0, 0.0))
	assert_true(world.party._crowded(l.position + Vector2(5.0, 0.0), 1), "five pixels from the leader is crowded")
	assert_false(world.party._crowded(l.position + Vector2(Party.MIN_GAP + 1.0, 0.0), 1))
	f.position = before


func test_the_party_steps_into_its_combat_cells_and_snaps_when_nothing_animates() -> void:
	world.teleport_party(Vector2i(13, 4))
	var cells: Array[Vector2i] = [Vector2i(12, 4), Vector2i(12, 5), Vector2i(11, 4)]
	world.settle_members(cells)
	for i: int in world.party.members.size():
		assert_eq(world.map_view.world_to_cell(world.party.members[i].position), cells[i], "snapped under tests")
	world.rules.initiative_die = 1
	world.start_combat(true)
	assert_eq(world.mode, "combat")
	for c: Combatant in world.combat.state.active("party"):
		var node: WorldActor = world.combat.actors[c.id]
		assert_eq(world.map_view.world_to_cell(node.position), c.cell, "everyone stands on their fight cell")


func test_the_pad_cursor_glides_between_cells() -> void:
	var h := world.highlighter
	assert_eq(h.glide, Vector2.INF, "no cursor yet")
	world.rules.initiative_die = 1
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	var first := world.combat.move_cursor(Vector2(1, 0))
	assert_true(first != Vector2i(-1, -1))
	assert_eq(h.glide, world.map_view.cell_to_world(first), "the first step lands the cursor")
	var second := world.combat.move_cursor(Vector2(1, 0))
	assert_true(second != first)
	assert_eq(h.glide_target, world.map_view.cell_to_world(second))
	assert_true(h.glide != h.glide_target, "on its way")
	h._process(0.001)
	assert_true(h.glide != h.glide_target and h.glide != world.map_view.cell_to_world(first), "part way after a millisecond")
	h._process(1.0)
	assert_eq(h.glide, h.glide_target, "there after a second")
	assert_eq(h.cells_in("e_cursor"), [second], "the cell layer says where it is going")
	world.combat.release_cursor()
	assert_eq(h.glide, Vector2.INF, "the mouse takes over: no glide")
