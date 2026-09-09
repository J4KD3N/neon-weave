## Subclass identities as mechanics (S31, D-086): chain lightning, taunt,
## spreading poison, the counter stance, area attacks, and party-side
## summons (drone swarms, turrets). Fixture combatants first, then the
## world: a level-12 multiclass capstone build saves and loads, a summoned
## drone is ours for one fight and drops nothing, and the Arcanum resets
## the multiclass with everything else.
extends TestCase

const LEDGER := "user://test_ledger_mech.json"
const SAVES := "user://test_saves_mech"
const TILES: Dictionary = {"floor": {"id": "floor", "walkable": true}}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 2, "range": 1, "damage": [4, 4], "accuracy": 100, "damage_type": "physical"},
	"lance": {"id": "lance", "name": "Lance", "ap": 3, "range": 6, "damage": [6, 6], "accuracy": 100, "damage_type": "arcane", "requires_los": true, "effect": "chain", "chain_targets": 2, "chain_range": 2, "chain_fraction": 0.5},
	"bash": {"id": "bash", "name": "Bash", "ap": 2, "range": 1, "damage": [2, 2], "accuracy": 100, "damage_type": "physical", "effect": "taunt", "duration": 2},
	"plague": {"id": "plague", "name": "Plague", "ap": 2, "range": 6, "damage": [1, 1], "accuracy": 100, "damage_type": "arcane", "requires_los": true, "effect": "poison", "duration": 3, "poison_damage": 2, "spread": true},
	"guard": {"id": "guard", "name": "Guard", "ap": 1, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "counter", "duration": 2, "counter_damage": [3, 3]},
	"field": {"id": "field", "name": "Field", "ap": 3, "range": 3, "damage": [2, 2], "accuracy": 100, "damage_type": "physical", "requires_los": true, "effect": "silence", "duration": 3, "aoe": 1},
	"swarm": {"id": "swarm", "name": "Swarm", "ap": 2, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "summon", "summon": "drone", "summon_count": 2, "summon_max": 2, "cooldown": 2},
	"zap": {"id": "zap", "name": "Zap", "ap": 2, "range": 4, "damage": [1, 1], "accuracy": 100, "damage_type": "tech", "requires_los": true},
}
const DRONE: Dictionary = {"id": "drone", "name": "Drone", "archetype": "ranged", "stats": {"hp": 6, "move": 5, "evasion": 0, "initiative": 0}, "abilities": ["zap"]}

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
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


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], hp: int = 10) -> Combatant:
	var c := Combatant.make(id, id, team, cell, {"hp": hp, "move": 4, "evasion": 0, "initiative": 0}, abilities, 4)
	return c


func _state(rows: Array, combatants: Array[Combatant], first: String) -> CombatState:
	var s := CombatState.new()
	var rules := CombatRules.new()
	rules.initiative_die = 1
	rules.story_protected = false
	rules.max_hit_chance = 100
	rules.friendly_fire = true
	rules.flank_damage_mult = 1.0 # flanking is tested elsewhere; keep the arithmetic flat here
	s.enemy_entries = {"drone": DRONE}
	s.setup(MapData.parse({"id": "m", "legend": {".": "floor", "P": "floor"}, "rows": rows}, TILES), rules, ABILITIES, combatants, 1)
	s.start(first)
	return s


func test_chain_lightning_arcs_to_the_nearest_hostiles_near_the_mark() -> void:
	var p := _c("p", "party", Vector2i(0, 1), ["lance"])
	var a := _c("a", "enemy", Vector2i(4, 1), ["strike"])
	var b := _c("b", "enemy", Vector2i(5, 1), ["strike"])
	var c := _c("c", "enemy", Vector2i(6, 1), ["strike"])
	var far := _c("f", "enemy", Vector2i(9, 1), ["strike"])
	var s := _state(["..........", "..........", ".........."], [p, a, b, c, far], "party")
	var e := s.use_ability(p, "lance", a.cell)
	assert_eq(a.hp, 4, "the mark takes 6")
	assert_eq(int(e["arcs"]), 2)
	assert_eq(b.hp, 7, "half arcs to the nearest")
	assert_eq(c.hp, 7, "and the next within two cells")
	assert_eq(far.hp, 10, "three cells past the mark: out of the arc")
	assert_any_contains(s.history, "Lightning arcs from a to b for 3")


func test_taunt_forces_the_brain_onto_the_taunter() -> void:
	var tank := _c("t", "party", Vector2i(2, 1), ["bash"], 20)
	var weak := _c("w", "party", Vector2i(2, 2), ["strike"], 3)
	var e := _c("e", "enemy", Vector2i(3, 1), ["strike"])
	var s := _state(["......", "......", "......"], [tank, weak, e], "party")
	s.switch_to("t")
	var hit := s.use_ability(tank, "bash", e.cell)
	assert_eq(int(hit["taunted"]), 2)
	assert_eq(e.taunted_by, "t")
	assert_eq(EnemyBrain.pick_target(s, e), tank, "focus fire would pick the 3 HP target; the taunt overrides it")
	s.end_turn()
	s.end_turn()
	assert_eq(s.current(), e)
	s.end_turn() # the taunt counts down at the end of the victim's own turns
	assert_eq(int(e.statuses.get("taunted", 0)), 1)
	assert_eq(e.taunted_by, "t")
	for _i: int in 3:
		s.end_turn()
	assert_eq(e.taunted_by, "", "expired")
	assert_eq(EnemyBrain.pick_target(s, e), weak, "back to the weakest in reach")


func test_poison_ticks_at_turn_end_and_spreads_to_neighbours_burning_out() -> void:
	var p := _c("p", "party", Vector2i(0, 1), ["plague"])
	var a := _c("a", "enemy", Vector2i(4, 1), ["strike"])
	var b := _c("b", "enemy", Vector2i(5, 1), ["strike"])
	var c := _c("c", "enemy", Vector2i(6, 1), ["strike"])
	var s := _state(["........", "........", "........"], [p, a, b, c], "party")
	var e := s.use_ability(p, "plague", a.cell)
	assert_eq(int(e["poisoned"]), 3)
	assert_eq(a.hp, 9)
	s.end_turn() # p done; a acts and ends: tick 2, spreads to b with 2 turns
	s.end_turn()
	assert_eq(a.hp, 7, "2 poison at the end of its own turn")
	assert_eq(int(a.statuses.get("poisoned", 0)), 2)
	assert_eq(int(b.statuses.get("poisoned", 0)), 2, "spread to the neighbour with one turn less")
	assert_eq(int(c.statuses.get("poisoned", 0)), 0, "c is not adjacent to a")
	assert_any_contains(s.history, "The poison spreads from a to b")
	s.end_turn() # b ticks: 2 damage, spreads to c with 1 turn
	assert_eq(b.hp, 8)
	assert_eq(int(c.statuses.get("poisoned", 0)), 1)
	s.end_turn() # c ticks once and it is over for c
	assert_eq(c.hp, 8)
	assert_eq(int(c.statuses.get("poisoned", 0)), 0, "burned out")
	s.end_turn() # p
	s.end_turn() # a: second tick
	assert_eq(a.hp, 5)
	for _i: int in 3:
		s.end_turn() # b (last tick), c, p
	s.end_turn() # a: third and last tick
	assert_eq(a.hp, 3)
	assert_eq(int(a.statuses.get("poisoned", 0)), 0)
	assert_true(a.poison.is_empty(), "cleared with the status")


func test_the_counter_stance_answers_every_adjacent_attack() -> void:
	var fencer := _c("f", "party", Vector2i(2, 1), ["guard"], 20)
	var near := _c("n", "enemy", Vector2i(3, 1), ["strike"])
	var far := _c("r", "enemy", Vector2i(2, 3), ["zap"])
	var s := _state(["......", "......", "......", "......"], [fencer, near, far], "party")
	var st := s.use_ability(fencer, "guard", fencer.cell)
	assert_eq(String(st["type"]), "stance")
	assert_eq(int(fencer.statuses["counter"]), 2)
	s.end_turn()
	assert_eq(s.current(), near)
	s.use_ability(near, "strike", fencer.cell)
	assert_eq(fencer.hp, 16)
	assert_eq(near.hp, 7, "3 back, adjacent")
	assert_any_contains(s.history, "f counters n for 3")
	s.end_turn()
	s.use_ability(far, "zap", fencer.cell)
	assert_eq(far.hp, 10, "a shot from two cells away is not answered")


func test_area_attacks_roll_for_everyone_in_the_radius() -> void:
	var p := _c("p", "party", Vector2i(0, 1), ["field"])
	var ally := _c("y", "party", Vector2i(3, 0), ["strike"])
	var a := _c("a", "enemy", Vector2i(3, 1), ["strike"])
	var b := _c("b", "enemy", Vector2i(3, 2), ["strike"])
	var c := _c("c", "enemy", Vector2i(5, 1), ["strike"])
	var s := _state(["......", "......", "......"], [p, ally, a, b, c], "party")
	s.switch_to("p")
	s.use_ability(p, "field", a.cell)
	assert_eq(a.hp, 8)
	assert_eq(b.hp, 8, "one cell from the target: caught")
	assert_eq(int(b.statuses.get("silenced", 0)), 3, "with the effect")
	assert_eq(ally.hp, 8, "friendly fire is on: the ally beside the target is caught too")
	assert_eq(c.hp, 10, "two cells away: clear")
	var aoe_events := 0
	for line: String in s.history:
		if line.contains("Field"):
			aoe_events += 1
	assert_true(aoe_events >= 3, "one line per target: %d" % aoe_events)


func test_summons_come_in_numbers_and_on_the_party_side() -> void:
	var lord := _c("l", "party", Vector2i(2, 1), ["swarm"])
	var e := _c("e", "enemy", Vector2i(6, 1), ["strike"])
	var s := _state(["........", "........", "........"], [lord, e], "party")
	var sm := s.use_ability(lord, "swarm", lord.cell)
	assert_eq(String(sm["type"]), "summon")
	assert_eq(String(sm["team"]), "party")
	assert_eq(s.summons_of(lord).size(), 2, "two drones off one cast")
	for d: Combatant in s.summons_of(lord):
		assert_eq(d.team, "party")
		assert_true(d.id.begins_with("p:s"))
	assert_eq(s.can_use(lord, "swarm", lord.cell), "cooling down (2)")
	lord.statuses.erase("cd:swarm")
	assert_eq(s.can_use(lord, "swarm", lord.cell), "swarm at its limit")
	assert_eq(s.active("party").size(), 3)


func test_a_level_twelve_multiclass_capstone_build_saves_and_loads_and_the_arcanum_resets_it() -> void:
	world.ledger.xp = 1050
	world.refresh_progression()
	assert_eq(world.party_level(), 12)
	assert_eq(world.choose_subclass("weaver", "juggernaut"), "")
	assert_eq(world.choose_multiclass("weaver", "scrap_knight"), "that is the main class")
	assert_eq(world.choose_multiclass("weaver", "aetherbinder"), "")
	for _i: int in 4:
		assert_eq(world.add_multiclass_level("weaver"), "")
	assert_eq(world.add_multiclass_level("weaver"), "", "5th of the 7 movable levels")
	var weaver := world.member_by_id("weaver")
	assert_eq(world.class_levels_text("weaver"), "Scrap-Knight 7 / Aetherbinder 5")
	assert_true(weaver.abilities.has("arc_bolt"), "the second class brings its bolt: %s" % [weaver.abilities])
	assert_false(weaver.abilities.has("line_breaker"), "seven main levels: no capstone yet")
	assert_eq(world.choose_multiclass("weaver", "circuit_witch"), "needs the Arcanum to change")
	# Pull two levels back by respec? No: respec resets everything. Instead place fewer.
	world.ledger.builds["weaver"]["multiclass"]["levels"] = 4
	world.refresh_progression()
	assert_eq(world.class_levels_text("weaver"), "Scrap-Knight 8 / Aetherbinder 4")
	assert_true(weaver.abilities.has("line_breaker"), "eight in the main class: the capstone")
	assert_true(weaver.abilities.has("charge_slam"), "subclass still on")
	world.ledger.bank({"aether": 30})
	assert_eq(world.buy_talent("weaver", "iron_skin"), "")
	assert_eq(world.buy_talent("weaver", "plated_bones"), "")
	assert_eq(world.buy_talent("weaver", "iron_will"), "", "tier 3 at level 12")
	assert_eq(world.buy_talent("weaver", "weft_sense"), "", "cross-branch: the Weave Tree is open to every class")
	assert_eq(world.save_slot(1), OK)
	assert_eq(world.load_slot(1), [])
	var back := world.member_by_id("weaver")
	assert_eq(back.level, 12)
	assert_eq(world.class_levels_text("weaver"), "Scrap-Knight 8 / Aetherbinder 4")
	assert_true(back.abilities.has("line_breaker") and back.abilities.has("arc_bolt") and back.abilities.has("charge_slam"))
	assert_eq(Array(world.build_for("weaver")["talents"]).size(), 4)
	# The Arcanum resets subclass, talents and the second class together.
	world.ledger.bank({"salvage": 40, "aether": 10})
	assert_true(world.upgrade_building("arcanum"))
	assert_eq(world.respec("weaver"), "")
	assert_eq(world.build_for("weaver")["multiclass"], {})
	assert_eq(world.class_levels_text("weaver"), "Scrap-Knight 12")
	assert_false(world.member_by_id("weaver").abilities.has("arc_bolt"))
	assert_true(world.member_by_id("weaver").abilities.has("line_breaker"), "twelve main levels: capstone stays")
	assert_eq(world.choose_multiclass("weaver", "circuit_witch"), "", "free to choose again")
	var rows := world.weave_rows("weaver")
	var kinds: Dictionary = {}
	for row: Dictionary in rows:
		kinds[row["kind"]] = int(kinds.get(row["kind"], 0)) + 1
	assert_eq(int(kinds["multiclass"]), 5, "every other class is a row")
	assert_eq(int(kinds["multiclass_level"]), 1)


func test_a_party_summon_lives_one_fight_and_drops_nothing() -> void:
	world.enter_shard("rusted_undercity", 7)
	var kill := world.ledger.kills
	world.spawn_summoned("scav", world.leader_cell() + Vector2i(2, 0))
	var drone := world.spawn_summoned("shepherd_drone", world.leader_cell() + Vector2i(1, 0), Combatant.TEAM_PARTY)
	assert_true(drone != null)
	assert_eq(world.summons.size(), 1)
	assert_false(world.enemies.has(drone), "not an enemy: no encounter, no loot")
	world.start_combat(true)
	world.combat.state._finish("victory")
	world._on_combat_ended("victory")
	assert_eq(world.summons.size(), 0, "gone with the fight")
	assert_eq(world.ledger.kills, kill)
	assert_eq(world.run.kills, 0)
