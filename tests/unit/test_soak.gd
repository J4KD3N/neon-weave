## Scripted playthroughs: several seeded runs of the whole loop (yard →
## Shard → fights → save/load mid-run → extract or wipe → Bastion) with a
## simple policy. Catches crashes and broken invariants no single-feature
## test would, the way a playtester does, but headless and on every PR.
extends TestCase

const LEDGER := "user://test_ledger_soak.json"
const SAVES := "user://test_saves_soak"
const RUNS: Array[int] = [11, 23, 47]
const MAX_ACTIONS := 400

var world: ExploreWorld
var rng := RandomNumberGenerator.new()
var log_lines: PackedStringArray = []


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.combat.animate = false
	log_lines.clear()


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


func _note(text: String) -> void:
	log_lines.append(text)


func _where() -> String:
	return "\n  ".join(log_lines.slice(maxi(log_lines.size() - 12, 0)))


## Invariants that must hold after every action, whatever the mode.
func _check_invariants(tag: String) -> void:
	assert_true(["explore", "combat", "defeated"].has(world.mode), "%s mode %s\n  %s" % [tag, world.mode, _where()])
	assert_true(world.party.members.size() >= 1 and world.party.members.size() <= world.rules.party_max, "%s party size\n  %s" % [tag, _where()])
	for m: PartyMember in world.party.members:
		assert_true(m.hp >= 0 and m.hp <= m.max_hp, "%s %s hp %d/%d\n  %s" % [tag, m.member_id, m.hp, m.max_hp, _where()])
		assert_true(world.map_data.is_walkable(world.member_cell(m)) or world.mode == "combat", "%s %s off the floor\n  %s" % [tag, m.member_id, _where()])
	assert_true(int(world.ledger.resources["salvage"]) >= 0 and int(world.ledger.resources["aether"]) >= 0, "%s ledger negative\n  %s" % [tag, _where()])
	if world.mode == "combat":
		var s := world.combat.state
		var cells: Array[Vector2i] = []
		var ids: Array[String] = []
		for c: Combatant in s.active():
			var clash := cells.find(c.cell)
			assert_false(clash >= 0, "%s two combatants on %s: %s and %s\n  %s" % [tag, c.cell, c.id, ids[clash] if clash >= 0 else "", _where()])
			cells.append(c.cell)
			ids.append(c.id)
		assert_true(s.current() != null, "%s combat with no current actor\n  %s" % [tag, _where()])


## One player action in combat: attack if anything reaches, else close the
## distance, else end the turn. Occasionally swaps, undoes and aims.
func _combat_step() -> void:
	var s := world.combat.state
	if not world.combat.current_is_player():
		world.combat.end_player_turn()
		return
	var actor := s.current()
	var roll := rng.randf()
	if roll < 0.1 and not s.switchable().is_empty():
		assert_true(world.combat.next_member(), "swap\n  %s" % _where())
		_note("swap -> %s" % s.current().id)
		return
	var target := EnemyBrain.nearest_hostile(s, actor)
	if target == null:
		world.combat.end_player_turn()
		return
	var usable := EnemyBrain.usable_ability(s, actor, target)
	if not usable.is_empty():
		if roll < 0.4:
			world.combat.select_ability(actor.abilities.find(usable))
			_note("%s aims %s at %s" % [actor.id, usable, target.id])
		var ap_before := actor.ap
		world.combat.player_click(target.cell)
		_note("%s -> %s (ap %d -> %d)" % [actor.id, target.id, ap_before, actor.ap])
		if actor.ap == ap_before:
			world.combat.cancel_selection()
			world.combat.end_player_turn()
		return
	if actor.move_left > 0:
		var reach := s.reachable_cells(actor)
		var field := s.distance_field(target.cell)
		var cells: Array = reach.keys()
		cells.sort()
		var best := actor.cell
		var best_d := int(field.get(actor.cell, 9999))
		for cell: Vector2i in cells:
			var d := int(field.get(cell, 9999))
			if d < best_d:
				best = cell
				best_d = d
		if best != actor.cell:
			var from := actor.cell
			world.combat.player_click(best)
			_note("%s moves %s -> %s" % [actor.id, from, actor.cell])
			if rng.randf() < 0.15:
				assert_true(world.combat.undo_move(), "undo after a move\n  %s" % _where())
				assert_eq(actor.cell, from, "undo returns to the start\n  %s" % _where())
				_note("%s undoes" % actor.id)
				world.combat.player_click(best)
			return
	world.combat.end_player_turn()


## One exploration action: mostly a hop toward the pad or a pickup, with
## saves, loads and Bastion visits mixed in.
func _explore_step(in_shard: bool) -> void:
	var roll := rng.randf()
	if in_shard and roll < 0.08:
		assert_eq(world.save_slot(2), OK, "mid-shard save\n  %s" % _where())
		var haul: Dictionary = world.run.haul.duplicate()
		var cell := world.leader_cell()
		assert_eq(world.load_slot(2), [], "mid-shard load\n  %s" % _where())
		assert_eq(world.leader_cell(), cell, "load restores the leader cell\n  %s" % _where())
		assert_eq(world.run.haul, haul, "load restores the haul\n  %s" % _where())
		_note("save/load slot 2 at %s" % cell)
		return
	if in_shard:
		# Shard features first: bank at a relay, open a vault, trade.
		if world.on_waypoint().x >= 0:
			var haul_before: Dictionary = world.run.haul.duplicate()
			assert_true(world.bank_at_waypoint(), "relay bank\n  %s" % _where())
			assert_true(world.run.is_empty(), "relay empties the haul\n  %s" % _where())
			_note("banked %s at a relay" % haul_before)
			return
		var door := world.adjacent_door()
		if door.x >= 0 and world.map_data.door_kind(door) == "vault":
			var why := world.open_vault(door)
			_note("vault at %s: %s" % [door, "opened" if why.is_empty() else why])
			if why.is_empty():
				assert_true(world.map_data.door_kind(door).is_empty(), "vault door became floor\n  %s" % _where())
				return
		var trader := world.merchant_near()
		if trader != null and roll < 0.5:
			assert_true(world.open_merchant(trader), "merchant opens\n  %s" % _where())
			for row: Dictionary in world.merchant_menu.rows:
				if bool(row["enabled"]):
					assert_eq(world.buy(String(row["id"])), "", "buy %s\n  %s" % [row["id"], _where()])
					_note("bought %s" % row["id"])
					break
			world.close_merchant()
			return
		var reach := ShardValidator.reachable_from(world.map_data, world.leader_cell())
		var pickups: Array[PickupActor] = []
		for p: PickupActor in world.remaining_pickups():
			if reach.has(p.cell):
				pickups.append(p)
		var goal := world.extraction_cell()
		if not pickups.is_empty() and roll < 0.6:
			goal = pickups[rng.randi_range(0, pickups.size() - 1)].cell
		var here := world.leader_cell()
		if here == goal or roll < 0.1:
			world.teleport_party(goal)
		else:
			var taken: Array[Vector2i] = []
			var free := world.map_data.nearest_free_cells(goal, 1, taken)
			world.teleport_party(free[0] if not free.is_empty() else goal)
		_note("hop to %s (goal %s)" % [world.leader_cell(), goal])
		world.check_pickups()
		world.check_encounters()
		if world.mode == "explore" and world.can_extract():
			assert_true(world.extract(), "extract on the pad\n  %s" % _where())
			_note("extracted; banked %s" % world.ledger.summary())
		return
	# At home: spend, talk, then launch.
	for id: String in world.bastion.order:
		if world.bastion.can_upgrade(id, world.ledger).is_empty() and rng.randf() < 0.5:
			assert_true(world.upgrade_building(id), "upgrade %s\n  %s" % [id, _where()])
			_note("upgraded %s" % id)
	if world.npc_at(Vector2i(5, 3)) != null and rng.randf() < 0.5:
		world.talk_to("sera")
		while world.in_dialogue():
			var n := world.dialogue.available_choices().size()
			world.choose(rng.randi_range(0, n - 1))
		_note("talked to sera; recruited=%s" % world.narrative.is_recruited("sera"))


func test_seeded_runs_survive_the_whole_loop() -> void:
	for run_seed: int in RUNS:
		if world.mode != "explore":
			fail("world stuck in mode %s before seed %d; stopping\n  %s" % [world.mode, run_seed, _where()])
			break
		rng.seed = run_seed
		world.combat_seed = run_seed
		world.enter_map(world.home_map)
		var actions := 0
		var extractions := 0
		var wipes := 0
		var shards := 0
		while actions < MAX_ACTIONS and extractions + wipes < 3:
			actions += 1
			var tag := "seed %d action %d" % [run_seed, actions]
			match world.mode:
				"combat":
					_combat_step()
				"defeated":
					wipes += 1
					_note("wiped")
					world.return_home()
					assert_true(world.at_home(), "%s wipe returns home\n  %s" % [tag, _where()])
				"explore":
					if world.at_home():
						var before := extractions
						_explore_step(false)
						if rng.randf() < 0.7 or shards == 0:
							var entry := world.enter_shard(ExploreWorld.DEFAULT_SHARD, run_seed * 100 + shards)
							assert_false(entry.is_empty(), "%s shard\n  %s" % [tag, _where()])
							shards += 1
							_note("entered shard %d depth %d" % [shards, world.bastion.depth()])
						assert_eq(extractions, before)
					else:
						var banked := world.ledger.runs_completed
						_explore_step(true)
						if world.ledger.runs_completed > banked:
							extractions += 1
			_check_invariants(tag)
		if world.mode == "combat" and actions >= MAX_ACTIONS:
			var s := world.combat.state
			_note("STALL round %d current %s" % [s.round_number, s.current().id if s.current() != null else "none"])
			for c: Combatant in s.combatants:
				_note("  %s %s hp %d/%d ap %d move %d hidden=%s statuses=%s active=%s" % [c.id, c.cell, c.hp, c.max_hp, c.ap, c.move_left, c.hidden, c.statuses, c.is_active()])
		assert_true(extractions + wipes >= 1, "seed %d never finished a run in %d actions\n  %s" % [run_seed, actions, _where()])
		_note("seed %d: %d shards, %d extractions, %d wipes, %d actions" % [run_seed, shards, extractions, wipes, actions])
		print("  soak ", log_lines[log_lines.size() - 1])
