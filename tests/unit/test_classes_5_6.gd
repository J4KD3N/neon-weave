## Wireghost (Heat: stealth builds it, overheating reveals) and Null Blade
## (Null: absorbs arcane damage as fuel; silence), exercised through the
## generic stealth / ambush / absorb / silence vocabulary, plus the
## stealther enemy archetype.
extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"cond": {"id": "cond", "walkable": true, "surface": "conduit"},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [4, 4], "accuracy": 100, "damage_type": "physical"},
	"cut": {"id": "cut", "name": "Wire Cut", "ap": 1, "range": 1, "damage": [4, 4], "accuracy": 60, "damage_type": "tech"},
	"hide": {"id": "hide", "name": "Shadow Step", "ap": 1, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "stealth"},
	"cool": {"id": "cool", "name": "Cool Down", "ap": 1, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "vent", "heal": 1},
	"bolt": {"id": "bolt", "name": "Arc Bolt", "ap": 1, "range": 5, "damage": [6, 6], "accuracy": 100, "damage_type": "arcane"},
	"lash": {"id": "lash", "name": "Void Lash", "ap": 2, "range": 2, "damage": [8, 8], "accuracy": 100, "damage_type": "physical", "resource_cost": 2},
	"pulse": {"id": "pulse", "name": "Null Pulse", "ap": 1, "range": 3, "damage": [1, 1], "accuracy": 100, "damage_type": "physical", "effect": "silence", "duration": 2},
}
const HEAT: Dictionary = {"id": "heat", "name": "Heat", "builds_on": "tech", "max": 4, "gain_per_cast": 1, "gain_on_stealth": 2, "reveal_at_max": true, "vent_ability": "cool"}
const NULL: Dictionary = {"id": "null", "name": "Null", "max": 5, "absorb": {"type": "arcane", "fraction": 0.5}, "gain_per_absorbed": 1}


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "t", "legend": {".": "floor", "c": "cond", "P": "floor"}, "rows": rows}, TILES)


static func _rules() -> CombatRules:
	var r := CombatRules.new()
	r.min_hit_chance = 0
	r.max_hit_chance = 100
	r.initiative_die = 1
	r.ambush_hit_bonus = 20
	r.ambush_damage_mult = 1.5
	return r


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], hp: int = 30) -> Combatant:
	return Combatant.make(id, id, team, cell, {"hp": hp, "move": 6, "evasion": 0, "initiative": 0}, abilities, 4)


func _state(rows: Array, combatants: Array[Combatant], first: String = "party") -> CombatState:
	var s := CombatState.new()
	s.setup(_map(rows), _rules(), ABILITIES, combatants, 5)
	s.start(first)
	return s


func test_stealth_hides_builds_heat_and_ambushes() -> void:
	var ghost := _c("g", "party", Vector2i(0, 0), ["strike", "cut", "hide", "cool"])
	ghost.set_resource(HEAT)
	var e := _c("e", "enemy", Vector2i(1, 0), ["strike"])
	var s := _state(["P...."], [ghost, e])
	assert_eq(s.can_use(ghost, "hide", ghost.cell), "")
	var st := s.use_ability(ghost, "hide", ghost.cell)
	assert_eq(st["type"], "stealth")
	assert_true(ghost.hidden)
	assert_eq(ghost.resource, 2, "stealth builds 2 Heat")
	assert_any_contains(s.history, "g vanishes.")
	assert_eq(s.can_use(ghost, "hide", ghost.cell), "already hidden")
	assert_eq(s.can_use(e, "strike", ghost.cell), "not your turn")
	var p := s.preview(ghost, "cut", e.cell)
	assert_eq(p["chance"], 80, "60 + 20 ambush")
	assert_eq(p["min"], 6, "4 x 1.5")
	assert_eq(p["tags"], PackedStringArray(["ambush"]))
	var r := s.use_ability(ghost, "cut", e.cell)
	assert_true(bool(r["ambush"]))
	assert_eq(int(r["chance"]), 80)
	assert_false(ghost.hidden, "striking reveals")
	if bool(r["hit"]):
		assert_eq(int(r["damage"]), 6)
		assert_any_contains(s.history, "(ambush)")
	assert_eq(ghost.resource, 3, "tech cast builds 1 more")


func test_hidden_targets_cannot_be_targeted_and_damage_reveals() -> void:
	var ghost := _c("g", "party", Vector2i(0, 0), ["strike", "hide"])
	ghost.set_resource(HEAT)
	var ally := _c("a", "party", Vector2i(0, 1), ["strike"])
	var e := _c("e", "enemy", Vector2i(1, 0), ["strike"])
	var s := _state(["P....", "....."], [ally, e, ghost], "")
	# initiative ties: order a, e, g
	assert_eq(CombatState._ids(s.order), PackedStringArray(["a", "e", "g"]))
	s.end_turn()
	assert_eq(s.current(), e)
	s.end_turn()
	assert_eq(s.current(), ghost)
	s.use_ability(ghost, "hide", ghost.cell)
	s.end_turn()
	assert_eq(s.round_number, 2)
	assert_eq(s.current(), ally)
	assert_eq(s.can_use(ally, "strike", ghost.cell), "", "allies may still target a hidden friend")
	s.end_turn()
	assert_eq(s.current(), e)
	assert_eq(s.can_use(e, "strike", ghost.cell), "target is hidden")
	assert_eq(s.preview(e, "strike", ghost.cell)["why"], "target is hidden")
	assert_true(EnemyBrain.nearest_hostile(s, e) == ally, "the brain ignores hidden targets")
	assert_eq(EnemyBrain.next_action(s, e)["target"], ally.cell)
	# Damage from anywhere reveals: the ally hits the ghost (friendly fire on).
	s.end_turn()
	s.end_turn()
	assert_eq(s.current(), ally)
	ally.ap = 4
	var r := s.use_ability(ally, "strike", ghost.cell)
	assert_true(bool(r["hit"]))
	assert_false(ghost.hidden, "taking damage reveals")


func test_overheat_reveals_and_cool_down_vents() -> void:
	var ghost := _c("g", "party", Vector2i(0, 0), ["cut", "hide", "cool"])
	ghost.set_resource(HEAT)
	var e := _c("e", "enemy", Vector2i(3, 0), ["strike"])
	var s := _state(["P...."], [ghost, e])
	ghost.resource = 3
	ghost.ap = 9
	var st := s.use_ability(ghost, "hide", ghost.cell)
	assert_eq(ghost.resource, 4, "capped at max")
	assert_true(bool(st["revealed"]), "hit the cap: lit up")
	assert_false(ghost.hidden)
	assert_any_contains(s.history, "overheats")
	assert_eq(s.can_use(ghost, "hide", ghost.cell), "overheated: cool down first")
	ghost.hp = 20
	var v := s.use_ability(ghost, "cool", ghost.cell)
	assert_eq(v["type"], "vent")
	assert_eq(ghost.resource, 0)
	assert_eq(ghost.hp, 21)
	assert_eq(s.can_use(ghost, "hide", ghost.cell), "")


func test_null_absorbs_arcane_damage_into_fuel_for_the_lash() -> void:
	var blade := _c("n", "party", Vector2i(0, 0), ["strike", "lash", "pulse"], 30)
	blade.set_resource(NULL)
	var mage := _c("m", "enemy", Vector2i(2, 0), ["bolt", "strike"])
	var s := _state(["P...."], [blade, mage], "")
	# order m, n: the mage acts first and bolts the blade.
	assert_eq(s.current(), mage)
	var r := s.use_ability(mage, "bolt", blade.cell)
	assert_true(bool(r["hit"]))
	assert_eq(int(r["absorbed"]), 3, "half of 6 swallowed")
	assert_eq(int(r["damage"]), 3, "the rest lands")
	assert_eq(blade.hp, 27)
	assert_eq(blade.resource, 3)
	assert_any_contains(s.history, "3 absorbed")
	var phys := s.use_ability(mage, "strike", blade.cell) if LineOfSight.distance(mage.cell, blade.cell) == 1 else {}
	assert_true(phys.is_empty(), "out of melee range; only arcane is absorbed anyway")
	s.end_turn()
	assert_eq(s.current(), blade)
	assert_eq(s.can_use(blade, "lash", mage.cell), "")
	var l := s.use_ability(blade, "lash", mage.cell)
	assert_eq(blade.resource, 1, "spent 2 Null")
	assert_eq(int(l["damage"]), 8)
	assert_eq(s.can_use(blade, "lash", mage.cell), "needs 2 Null")
	# Conduit chain shocks are arcane too: absorbed, and the store caps at max.
	var blade2 := _c("n", "party", Vector2i(1, 0), ["strike"], 30)
	blade2.set_resource(NULL)
	blade2.resource = 4
	var victim := _c("x", "party", Vector2i(2, 0), ["strike"])
	var caster := _c("m", "enemy", Vector2i(4, 0), ["bolt"])
	var s2 := _state(["Pcc.."], [blade2, victim, caster], "")
	s2.rules.conduit_chain_damage = 2
	assert_eq(s2.current(), caster, "m sorts first")
	var chain := s2.use_ability(caster, "bolt", victim.cell)
	assert_true(bool(chain["hit"]))
	assert_eq(blade2.hp, 29, "2 chain damage, 1 absorbed")
	assert_eq(blade2.resource, 5, "capped at max")


func test_silence_blocks_arcane_for_its_duration() -> void:
	var blade := _c("n", "party", Vector2i(0, 0), ["pulse"])
	blade.set_resource(NULL)
	var mage := _c("m", "enemy", Vector2i(2, 0), ["bolt", "strike"])
	var s := _state(["P...."], [blade, mage], "party")
	assert_eq(s.current(), blade)
	var r := s.use_ability(blade, "pulse", mage.cell)
	assert_eq(int(r["silenced"]), 2)
	assert_true(mage.is_silenced())
	assert_any_contains(s.history, "silenced 2")
	s.end_turn()
	assert_eq(s.current(), mage)
	assert_eq(int(mage.statuses["silenced"]), 1, "counts down at the turn start")
	assert_eq(s.can_use(mage, "bolt", blade.cell), "silenced")
	assert_eq(s.preview(mage, "bolt", blade.cell)["why"], "silenced")
	assert_eq(EnemyBrain.usable_ability(s, mage, blade), "", "strike is out of reach, bolt is silenced")
	s.end_turn()
	s.end_turn()
	assert_eq(s.current(), mage)
	assert_false(mage.is_silenced(), "expired")
	assert_eq(s.can_use(mage, "bolt", blade.cell), "")


func test_stealther_hides_closes_and_ambushes() -> void:
	var hero := _c("h", "party", Vector2i(0, 0), ["strike"])
	var lurker := _c("l", "enemy", Vector2i(4, 0), ["strike", "hide"])
	lurker.archetype = "stealther"
	var s := _state(["P....."], [hero, lurker], "")
	assert_eq(s.current(), hero)
	s.end_turn()
	assert_eq(s.current(), lurker)
	var a1 := EnemyBrain.next_action(s, lurker)
	assert_eq(a1["type"], "ability")
	assert_eq(a1["id"], "hide", "nothing in reach: hide first")
	s.use_ability(lurker, "hide", lurker.cell)
	assert_true(lurker.hidden)
	var a2 := EnemyBrain.next_action(s, lurker)
	assert_eq(a2["type"], "move", "then close in unseen")
	s.move(lurker, a2["to"])
	assert_eq(lurker.cell, Vector2i(1, 0))
	var a3 := EnemyBrain.next_action(s, lurker)
	assert_eq(a3["type"], "ability")
	assert_eq(a3["id"], "strike")
	var r := s.use_ability(lurker, "strike", hero.cell)
	assert_true(bool(r["ambush"]))
	assert_false(lurker.hidden)
	assert_eq(int(r["damage"]), 6, "4 x 1.5 from hiding")
	var a4 := EnemyBrain.next_action(s, lurker)
	assert_eq(a4["id"], "strike", "in reach and revealed: keep hitting rather than re-hide")


func test_base_content_wires_the_new_classes() -> void:
	var registry := ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	assert_eq(registry.count("classes"), 6, "six base classes")
	for id: String in ["wireghost", "null_blade"]:
		var cls := registry.get_entry("classes", id)
		assert_false(cls.is_empty(), id)
		assert_eq(Array(cls["subclasses"]).size(), 2)
	var heat := registry.get_entry("resources", "heat")
	assert_eq(int(heat["gain_on_stealth"]), 2)
	assert_true(bool(heat["reveal_at_max"]))
	assert_eq(String(registry.get_entry("resources", "vent_heat")["name"]), "Vent Heat", "the two Heats read differently")
	var null_def := registry.get_entry("resources", "null")
	assert_eq(String(Dictionary(null_def["absorb"])["type"]), "arcane")
	var lurker := registry.get_entry("enemies", "wire_lurker")
	assert_eq(lurker["archetype"], "stealther")
	assert_true(Array(lurker["abilities"]).has("shadow_step"))
	var pool: Array = Dictionary(registry.get_entry("shards", "rusted_undercity")["enemies"])["pool"]
	var in_pool := false
	for p: Dictionary in pool:
		if String(p["type"]) == "wire_lurker":
			in_pool = true
	assert_true(in_pool, "the lurker spawns in the Undercity")
	var rules := CombatRules.from_entry(registry.get_entry("rules", "combat"))
	assert_eq(rules.ambush_hit_bonus, 20)
	assert_eq(rules.ambush_damage_mult, 1.5)
	registry.free()


func test_stealth_is_a_window_that_expires_after_the_next_own_turn() -> void:
	var ghost := _c("g", "party", Vector2i(0, 0), ["hide"])
	var e := _c("e", "enemy", Vector2i(4, 0), ["strike"])
	var s := _state(["P....."], [ghost, e], "party")
	s.use_ability(ghost, "hide", ghost.cell)
	assert_true(ghost.hidden)
	assert_eq(int(ghost.statuses["hidden"]), 2)
	s.end_turn() # e
	assert_true(ghost.hidden, "hidden through the enemy round")
	s.end_turn() # round 2: g
	assert_true(ghost.hidden, "and through the next own turn (the ambush window)")
	assert_eq(int(ghost.statuses["hidden"]), 1)
	s.end_turn() # e
	s.end_turn() # round 3: g
	assert_false(ghost.hidden, "then lit up again: a stuck hidden combatant cannot stall a fight")
	assert_false(ghost.statuses.has("hidden"))
	assert_eq(s.can_use(ghost, "hide", ghost.cell), "")


func test_ability_cooldown_counts_down_at_own_turn_start() -> void:
	var abilities := ABILITIES.duplicate(true)
	abilities["hide_cd"] = {"id": "hide_cd", "name": "Shadow Step", "ap": 1, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "stealth", "duration": 2, "cooldown": 3}
	var ghost := _c("g", "party", Vector2i(0, 0), ["hide_cd"])
	var e := _c("e", "enemy", Vector2i(4, 0), ["strike"])
	var s := CombatState.new()
	s.setup(_map(["P....."]), _rules(), abilities, [ghost, e], 5)
	s.start("party")
	assert_eq(s.can_use(ghost, "hide_cd", ghost.cell), "")
	s.use_ability(ghost, "hide_cd", ghost.cell)
	assert_eq(int(ghost.statuses["cd:hide_cd"]), 3)
	assert_eq(s.can_use(ghost, "hide_cd", ghost.cell), "cooling down (3)")
	s.end_turn()
	s.end_turn() # round 2, g: hidden 1, cd 2
	assert_true(ghost.hidden)
	assert_eq(s.can_use(ghost, "hide_cd", ghost.cell), "cooling down (2)")
	s.end_turn()
	s.end_turn() # round 3, g: revealed, cd 1
	assert_false(ghost.hidden)
	assert_eq(s.can_use(ghost, "hide_cd", ghost.cell), "cooling down (1)", "one exposed turn before hiding again")
	s.end_turn()
	s.end_turn() # round 4, g: cd gone
	assert_eq(s.can_use(ghost, "hide_cd", ghost.cell), "")
