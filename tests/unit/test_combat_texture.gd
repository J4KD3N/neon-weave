## Cover, elevation, surfaces and class resources (GDD §9 "full combat").
extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
	"low": {"id": "low", "walkable": false, "blocks_sight": false, "cover": 1},
	"walk": {"id": "walk", "walkable": true, "height": 1},
	"pool": {"id": "pool", "walkable": true, "surface": "mana_pool"},
	"cond": {"id": "cond", "walkable": true, "surface": "conduit"},
	"bio": {"id": "bio", "walkable": true, "surface": "corrosive"},
}
const ABILITIES: Dictionary = {
	"shoot": {"id": "shoot", "name": "Shoot", "ap": 1, "range": 6, "damage": [4, 4], "accuracy": 70, "damage_type": "tech", "requires_los": true},
	"bolt": {"id": "bolt", "name": "Bolt", "ap": 1, "range": 6, "damage": [4, 4], "accuracy": 70, "damage_type": "arcane", "requires_los": true},
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [4, 4], "accuracy": 70, "damage_type": "physical"},
	"heavy": {"id": "heavy", "name": "Heavy", "ap": 2, "range": 1, "damage": [6, 6], "accuracy": 70, "damage_type": "physical"},
	"vent": {"id": "vent", "name": "Vent", "ap": 0, "range": 0, "targets": "self", "effect": "vent", "heal": 2, "damage": [0, 0], "accuracy": 100, "damage_type": "none"},
}
const SURGE: Dictionary = {"id": "surge", "name": "Surge", "builds_on": "arcane", "max": 3, "gain_per_cast": 1, "damage_per_stack": 1, "overload_at": 3, "overload_chance": 0.0, "overload_damage": 3}
const HEAT: Dictionary = {"id": "vent_heat", "name": "Heat", "builds_on": "physical", "max": 3, "gain_per_cast": 1, "damage_per_stack": 1, "lock_ap_at_max": 2}


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "t", "legend": {".": "floor", "#": "wall", "x": "low", "k": "walk", "m": "pool", "c": "cond", "b": "bio", "P": "floor"}, "rows": rows}, TILES)


static func _rules() -> CombatRules:
	var r := CombatRules.new()
	r.min_hit_chance = 0
	r.max_hit_chance = 100
	r.initiative_die = 1
	return r


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], hp: int = 20) -> Combatant:
	return Combatant.make(id, id, team, cell, {"hp": hp, "move": 6, "evasion": 0, "initiative": 0}, abilities, 4)


func _state(rows: Array, combatants: Array[Combatant], first: String = "party", rules: CombatRules = _rules()) -> CombatState:
	var s := CombatState.new()
	s.setup(_map(rows), rules, ABILITIES, combatants, 3)
	s.start(first)
	return s


func test_map_texture_lookups() -> void:
	var map := _map(["P.xkmcb"])
	assert_eq(map.cover_at(Vector2i(2, 0)), 1)
	assert_eq(map.cover_at(Vector2i(1, 0)), 0)
	assert_eq(map.height_at(Vector2i(3, 0)), 1)
	assert_eq(map.height_at(Vector2i(0, 0)), 0)
	assert_eq(map.surface_at(Vector2i(4, 0)), "mana_pool")
	assert_eq(map.surface_at(Vector2i(5, 0)), "conduit")
	assert_eq(map.surface_at(Vector2i(6, 0)), "corrosive")
	assert_eq(map.surface_at(Vector2i(1, 0)), "")
	assert_true(map.is_walkable(Vector2i(3, 0)), "catwalk is walkable")
	assert_false(map.blocks_sight(Vector2i(2, 0)), "low cover does not block sight")


func test_cover_penalises_ranged_but_not_melee_or_high_ground() -> void:
	# p shoots e; the low wall x sits between them on e's side.
	var p := _c("p", "party", Vector2i(0, 0), ["shoot", "strike"])
	var e := _c("e", "enemy", Vector2i(4, 0), ["strike"])
	var s := _state(["P..x.."], [p, e])
	var mods := s.attack_modifiers(p, ABILITIES["shoot"], e)
	assert_eq(int(mods["cover"]), 1)
	assert_eq(int(mods["hit"]), -s.rules.cover_hit_penalty)
	assert_eq(s.hit_chance(p, ABILITIES["shoot"], e, false, int(mods["hit"])), 50)
	# Melee never checks cover.
	var m := s.attack_modifiers(p, ABILITIES["strike"], e)
	assert_eq(int(m["cover"]), 0)
	assert_eq(int(m["hit"]), 0)
	# From the far side there is no cover.
	var far := _c("f", "party", Vector2i(6, 0), ["shoot"])
	var s2 := _state(["P..x..."], [far, _c("e2", "enemy", Vector2i(4, 0), ["strike"])])
	assert_eq(int(s2.attack_modifiers(far, ABILITIES["shoot"], s2.by_id("e2"))["cover"]), 0)
	# High ground ignores cover.
	var high := _c("h", "party", Vector2i(0, 0), ["shoot"])
	var s3 := _state(["k..x.."], [high, _c("e3", "enemy", Vector2i(4, 0), ["strike"])])
	var hm := s3.attack_modifiers(high, ABILITIES["shoot"], s3.by_id("e3"))
	assert_eq(int(hm["cover"]), 0)
	assert_true(bool(hm["elevated"]))


func test_elevation_bonus_and_penalty() -> void:
	var high := _c("h", "party", Vector2i(0, 0), ["shoot"])
	var low := _c("l", "enemy", Vector2i(2, 0), ["shoot"])
	var s := _state(["k.."], [high, low])
	var down := s.attack_modifiers(high, ABILITIES["shoot"], low)
	assert_eq(int(down["hit"]), s.rules.elevation_hit_bonus)
	assert_eq(int(down["damage"]), s.rules.elevation_damage_bonus)
	assert_true(bool(down["elevated"]))
	var up := s.attack_modifiers(low, ABILITIES["shoot"], high)
	assert_eq(int(up["hit"]), -s.rules.elevation_hit_bonus)
	assert_true(bool(up["uphill"]))
	assert_eq(int(up["damage"]), 0)
	# A hit from high ground deals the extra point.
	var r := s.use_ability(high, "shoot", low.cell)
	if bool(r["hit"]):
		assert_eq(int(r["damage"]), 5, "4 + 1 elevation")
		assert_true(bool(r["elevated"]))


func test_mana_pool_amplifies_arcane_only() -> void:
	var caster := _c("c", "party", Vector2i(0, 0), ["bolt", "shoot"])
	var e := _c("e", "enemy", Vector2i(2, 0), ["strike"], 30)
	var s := _state(["m.."], [caster, e])
	assert_true(bool(s.attack_modifiers(caster, ABILITIES["bolt"], e)["amplified"]))
	assert_false(bool(s.attack_modifiers(caster, ABILITIES["shoot"], e)["amplified"]))
	var r := s.use_ability(caster, "bolt", e.cell)
	if bool(r["hit"]):
		assert_eq(int(r["damage"]), 6, "4 × 1.5")
		assert_true(bool(r["amplified"]))
		assert_any_contains(s.history, "mana pool")


func test_conduit_chains_to_everyone_on_the_run_including_allies() -> void:
	# Row 0: conduit cells 1..4 connected; cell 6 is a separate conduit.
	var shooter := _c("s", "party", Vector2i(0, 1), ["shoot", "strike"])
	var t := _c("t", "enemy", Vector2i(1, 0), ["strike"], 30)
	var ally := _c("z", "party", Vector2i(3, 0), ["strike"], 30) # sorts after "s" so the shooter acts first
	var foe := _c("f", "enemy", Vector2i(4, 0), ["strike"], 30)
	var apart := _c("x", "enemy", Vector2i(6, 0), ["strike"], 30)
	var s := _state([".cccc.c", "P......"], [shooter, t, ally, foe, apart])
	assert_eq(s.conduit_network(Vector2i(1, 0)).size(), 4)
	assert_eq(s.conduit_network(Vector2i(0, 0)), [])
	var r := s.use_ability(shooter, "shoot", t.cell)
	if bool(r["hit"]):
		assert_eq(ally.hp, 30 - s.rules.conduit_chain_damage, "friendly fire arcs too")
		assert_eq(foe.hp, 30 - s.rules.conduit_chain_damage)
		assert_eq(apart.hp, 30, "disconnected conduit stays cold")
		assert_eq(t.hp, 30 - 4, "the target takes only the shot")
		assert_any_contains(s.history, "The conduit arcs: z takes 2")
	# A physical hit on a conduit does not chain.
	shooter.ap = 4
	shooter.cell = Vector2i(2, 1)
	var before_ally := ally.hp
	var r2 := s.use_ability(shooter, "strike", Vector2i(1, 0)) if LineOfSight.distance(shooter.cell, Vector2i(1, 0)) == 1 else {}
	if not r2.is_empty() and bool(r2["hit"]):
		assert_eq(ally.hp, before_ally)


func test_corrosive_burns_at_turn_start_and_can_down() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["strike"], 10)
	var e := _c("e", "enemy", Vector2i(2, 0), ["strike"], 3)
	var s := _state(["bbb"], [p, e])
	assert_eq(s.current(), p)
	assert_eq(p.hp, 10 - s.rules.corrosive_damage, "burned at the start of round 1")
	assert_any_contains(s.history, "burns in the biogrowth")
	s.end_turn()
	# e had 3 HP: burns for 2 -> 1, still active.
	assert_eq(e.hp, 1)
	assert_eq(s.current(), e)
	s.end_turn() # back to p (10-2-2 = 6)
	assert_eq(p.hp, 6)
	s.end_turn() # e burns to 0 and dies -> victory
	assert_true(s.finished)
	assert_eq(s.result, "victory")


func test_surge_builds_adds_damage_and_caps() -> void:
	var caster := _c("c", "party", Vector2i(0, 0), ["bolt", "shoot"], 20)
	caster.set_resource(SURGE)
	var e := _c("e", "enemy", Vector2i(2, 0), ["strike"], 99)
	var s := _state(["P.."], [caster, e])
	assert_eq(caster.resource, 0)
	var r1 := s.use_ability(caster, "bolt", e.cell)
	assert_eq(int(r1["resource_stacks"]), 0)
	assert_eq(caster.resource, 1, "arcane cast builds a stack")
	var r2 := s.use_ability(caster, "bolt", e.cell)
	assert_eq(int(r2["resource_stacks"]), 1)
	if bool(r2["hit"]):
		assert_eq(int(r2["damage"]), 5, "4 + 1 stack")
	assert_eq(caster.resource, 2)
	var r3 := s.use_ability(caster, "shoot", e.cell)
	assert_eq(int(r3["resource_stacks"]), 0, "tech does not feed Surge")
	assert_eq(caster.resource, 2)
	caster.ap = 4
	s.use_ability(caster, "bolt", e.cell)
	s.use_ability(caster, "bolt", e.cell)
	assert_eq(caster.resource, 3, "capped at max")


func test_surge_overload_burns_the_caster_and_resets() -> void:
	var def := SURGE.duplicate()
	def["overload_chance"] = 1.0
	var caster := _c("c", "party", Vector2i(0, 0), ["bolt"], 20)
	caster.set_resource(def)
	caster.resource = 3
	var e := _c("e", "enemy", Vector2i(2, 0), ["strike"], 99)
	var s := _state(["P.."], [caster, e])
	var r := s.use_ability(caster, "bolt", e.cell)
	assert_eq(r["type"], "overload")
	assert_eq(int(r["damage"]), 3)
	assert_eq(caster.hp, 17)
	assert_eq(caster.resource, 0)
	assert_eq(caster.ap, 3, "the fizzled cast still costs AP")
	assert_eq(e.hp, 99, "nothing reaches the target")
	assert_any_contains(s.history, "overloads!")
	# Below the threshold no overload can happen even at 100%.
	var r2 := s.use_ability(caster, "bolt", e.cell)
	assert_eq(r2["type"], "ability")


func test_heat_locks_heavy_swings_until_vented() -> void:
	var knight := _c("k", "party", Vector2i(0, 0), ["strike", "heavy", "vent"], 20)
	knight.set_resource(HEAT)
	var e := _c("e", "enemy", Vector2i(1, 0), ["strike"], 99)
	var s := _state(["P."], [knight, e])
	knight.ap = 9
	for _i: int in 3:
		s.use_ability(knight, "strike", e.cell)
	assert_eq(knight.resource, 3)
	assert_eq(s.can_use(knight, "heavy", e.cell), "overheated: vent first")
	assert_eq(s.can_use(knight, "strike", e.cell), "", "1-AP blows still allowed")
	assert_eq(s.can_use(knight, "vent", e.cell), "self only")
	assert_eq(s.can_use(knight, "vent", knight.cell), "")
	knight.hp = 15
	var v := s.use_ability(knight, "vent", knight.cell)
	assert_eq(v["type"], "vent")
	assert_eq(knight.resource, 0)
	assert_eq(knight.hp, 17)
	assert_eq(int(v["resource_before"]), 3)
	assert_eq(s.can_use(knight, "heavy", e.cell), "")
	assert_any_contains(s.history, "k vents (+2 HP)")


func test_resourceless_combatants_are_unaffected() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["bolt", "heavy"], 20)
	var e := _c("e", "enemy", Vector2i(1, 0), ["strike"], 99)
	var s := _state(["P."], [p, e])
	assert_false(p.has_resource())
	assert_eq(s.can_use(p, "heavy", e.cell), "")
	var r := s.use_ability(p, "bolt", e.cell)
	assert_eq(int(r["resource_stacks"]), 0)
	assert_false(r.has("resource_after"))
