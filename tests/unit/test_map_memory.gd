## Maps remember and gates ask (S71, D-127): a placed enemy killed on a
## handcrafted map stays dead when you leave and come back, through a save
## too; a gate walked onto shows its label and waits for Enter / A, while a
## click on it or a confirm takes you through as before.
extends TestCase

const DT := 1.0 / 60.0
const LEDGER := "user://test_ledger_memory.json"
const SAVES := "user://test_saves_memory"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.map_id = "proto_yard"
	w.home_map = "proto_yard"
	w.party_id = "prototype"
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.settings_path = "user://test_settings_memory.json"
	w.input_path = "user://test_input_memory.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func test_the_yard_remembers_who_died_on_it() -> void:
	var before := world.living_enemies().size()
	assert_eq(before, 4)
	world.rules.initiative_die = 1
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	var s := world.combat.state
	for c: Combatant in s.combatants:
		if c.team == Combatant.TEAM_ENEMY:
			c.hp = 0
	world.combat._sync_all() # the nodes learn they are dead, as they do after a real blow
	s._check_outcome()
	world._on_combat_ended("victory")
	assert_eq(world.mode, "explore")
	assert_eq(world.living_enemies().size(), 1, "the three engaged died; the addict beyond the radius lives")
	var dead: Array = world.narrative.map_kills.get("proto_yard", [])
	assert_eq(dead.size(), 3, "three placement indices in the story: %s" % [dead])
	assert_true(world.enter_map("bastion"))
	assert_true(world.enter_map("proto_yard"))
	assert_eq(world.living_enemies().size(), 1, "back in the yard: still dead")
	assert_true(world.enemy_at(Vector2i(14, 2)) == null, "the scav at (14,2) does not stand up")
	assert_true(world.enemy_at(Vector2i(12, 12)) != null, "the addict does")
	# Through a save, from another map.
	assert_true(world.enter_map("bastion"))
	world.teleport_party(Vector2i(10, 8))
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.map_id, "bastion")
	assert_true(again.enter_map("proto_yard"))
	assert_eq(again.living_enemies().size(), 1, "the save carried the yard's dead")
	_drop(again)
	# Shards are not maps that remember: nothing is written for one.
	world.enter_shard("rusted_undercity", 7)
	var first := world.enemies[0]
	first.dead = true
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_false(world.narrative.map_kills.has(world.map_id), "a Shard keeps its own run deltas")


func test_a_gate_asks_when_walked_onto_and_goes_on_a_click_or_a_confirm() -> void:
	var gate := Vector2i(1, 7) # the yard's gate back to the Bastion
	assert_false(world.transition_at(gate).is_empty())
	world.teleport_party(gate)
	assert_false(world.check_transitions(false), "walked onto it: nothing yet")
	assert_eq(world.map_id, "proto_yard")
	assert_contains(world.status_line(), "Back to the Bastion — Enter / A to go")
	assert_true(world.check_transitions(), "a confirmed check (tests, scripts) still goes")
	assert_eq(world.map_id, "bastion")
	assert_true(world.enter_map("proto_yard"))
	world.teleport_party(gate)
	assert_true(world.interact(), "Enter / A on the gate goes")
	assert_eq(world.map_id, "bastion")
	assert_true(world.enter_map("proto_yard"))
	# A click on the gate means it: the frame that arrives goes through.
	world.teleport_party(Vector2i(3, 7))
	assert_true(world.command_move(gate))
	assert_eq(world.gate_intent, gate)
	var ticks := 0
	while world.party.is_moving() and ticks < 3000:
		world.party.tick(DT)
		ticks += 1
	assert_eq(world.leader_cell(), gate)
	assert_true(world.check_transitions(false), "arrived where the click pointed: through")
	assert_eq(world.map_id, "bastion")
	assert_eq(world.gate_intent, Vector2i(-1, -1), "spent")
	# Walking off a gate that was clicked forgets the intent.
	assert_true(world.enter_map("proto_yard"))
	world.teleport_party(Vector2i(3, 7))
	assert_true(world.command_move(gate))
	world.party.stop()
	world.teleport_party(Vector2i(5, 7))
	assert_false(world.check_transitions(false))
	assert_eq(world.gate_intent, Vector2i(-1, -1), "not on it, not moving: forgotten")
