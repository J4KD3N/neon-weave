## Hackable turrets and doors (S63, D-119; GDD §9): a Hack action in
## combat for the Tech-minded that turns a hackable machine to the party's
## side, and a Tech check that opens a locked gate the key would.
extends TestCase

const LEDGER := "user://test_ledger_hack.json"
const SAVES := "user://test_saves_hack"
const ACCOUNT := "user://test_account_hack.json"

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [2, 4], "accuracy": 85},
	"big": {"id": "big", "name": "Big", "ap": 2, "range": 1, "damage": [20, 20], "accuracy": 100},
	"hack": {"id": "hack", "name": "Hack", "ap": 2, "range": 1, "damage": [0, 0], "accuracy": 100, "effect": "hack"},
}

var events: Array[Dictionary] = []


func after_each() -> void:
	_cleanup()


static func _cleanup() -> void:
	for f: String in [LEDGER, ACCOUNT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
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
	w.account_path = ACCOUNT
	w.settings_path = "user://test_settings_hack.json"
	w.input_path = "user://test_input_hack.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], hackable: bool = false) -> Combatant:
	var c := Combatant.make(id, id, team, cell, {"hp": 10, "move": 6, "evasion": 0, "initiative": 0}, abilities, 4)
	if hackable:
		c.traits["hackable"] = true
	return c


func _state(combatants: Array[Combatant], seed_value: int = 1) -> CombatState:
	var s := CombatState.new()
	var r := CombatRules.new()
	r.max_hit_chance = 100
	r.min_hit_chance = 0
	r.initiative_die = 1
	s.setup(MapData.parse({"id": "h", "legend": {".": "floor", "#": "wall", "P": "floor"}, "rows": ["P......", "......."]}, TILES), r, ABILITIES, combatants, seed_value)
	events.clear()
	s.event.connect(func(e: Dictionary) -> void: events.append(e))
	return s


func test_a_hack_turns_a_hackable_machine_and_only_that() -> void:
	var p := _c("p", "party", Vector2i(1, 0), ["strike", "big", "hack"])
	var turret := _c("t", "enemy", Vector2i(2, 0), ["strike"], true)
	var thug := _c("e", "enemy", Vector2i(1, 1), ["strike"])
	var far := _c("f", "enemy", Vector2i(5, 0), ["strike"], true)
	var s := _state([p, turret, thug, far])
	s.start("party")
	assert_eq(s.current(), p)
	assert_eq(s.can_use(p, "hack", thug.cell), "not a machine you can hack")
	assert_eq(s.can_use(p, "hack", far.cell), "out of range", "beside you, the ability says")
	assert_eq(s.can_use(p, "hack", turret.cell), "")
	var h := s.use_ability(p, "hack", turret.cell)
	assert_eq(String(h["type"]), "hack")
	assert_true(bool(h["hit"]), "accuracy 100 under a max of 100")
	assert_eq(int(h["chance"]), 100)
	assert_eq(turret.team, "party", "ours now")
	assert_true(turret.hacked)
	assert_eq(p.ap, 2, "two AP spent")
	assert_eq(s.can_use(p, "hack", turret.cell), "already on your side")
	assert_true(thug.is_hostile_to(turret), "the thug turns on it")
	assert_false(p.is_hostile_to(turret))
	assert_eq(s.active("enemy").size(), 2)
	assert_false(s.finished)
	assert_contains(s.describe(h), "p hacks t: it is ours now.")
	assert_true(s.history[s.history.size() - 1].contains("hacks"), "logged")
	# The bonus and the floor: a poor hacker rolls against less.
	var p2 := _c("p2", "party", Vector2i(1, 0), ["hack"])
	p2.traits["hack_bonus"] = -70
	var t2 := _c("t2", "enemy", Vector2i(2, 0), ["strike"], true)
	var s2 := _state([p2, t2], 3)
	s2.start("party")
	var h2 := s2.use_ability(p2, "hack", t2.cell)
	assert_eq(int(h2["chance"]), 30, "accuracy plus the bonus, clamped")
	if not bool(h2["hit"]):
		assert_eq(t2.team, "enemy", "a miss changes nothing")
		assert_contains(s2.describe(h2), "the hack on t2 fails")
	# Victory counts a turned machine as ours: the last hostile falling ends it.
	var p3 := _c("p3", "party", Vector2i(1, 0), ["big", "hack"])
	var t3 := _c("t3", "enemy", Vector2i(2, 0), ["strike"], true)
	var e3 := _c("e3", "enemy", Vector2i(1, 1), ["strike"])
	var s3 := _state([p3, t3, e3])
	s3.start("party")
	assert_true(bool(s3.use_ability(p3, "hack", t3.cell)["hit"]))
	assert_false(s3.finished, "e3 still stands")
	s3.use_ability(p3, "big", e3.cell)
	assert_true(s3.finished)
	assert_eq(s3.result, "victory", "the hacked turret does not keep the fight alive")


func test_tech_hands_the_hack_to_the_protagonist_and_the_tech_classes() -> void:
	var w := _fresh()
	assert_eq(w.rules.hack_tech_min, 2)
	assert_eq(w.rules.hack_tech_bonus, 15)
	assert_true(w.registry.has_entry("abilities", "hack"))
	assert_true(w.can_hack(w.member_by_id("unit_9")), "a Drone Shepherd has the Tech branch")
	assert_false(w.can_hack(w.member_by_id("weaver")), "a Scrap-Knight does not")
	assert_false(w.can_hack(w.member_by_id("ash")))
	assert_eq(w.hack_bonus(w.member_by_id("unit_9")), 0, "companions get the base roll")
	for id: String in ["shepherd_turret", "feral_drone", "warden_construct"]:
		assert_true(bool(Dictionary(w.registry.get_entry("enemies", id)["traits"]).get("hackable", false)), "%s is hackable" % id)
	assert_false(Dictionary(w.registry.get_entry("enemies", "scav").get("traits", {})).has("hackable"))
	# A protagonist with Tech 4: the Hack action with +30 on the roll.
	var sheet := {"name": "Kest", "race_id": "trueborn", "origin_id": "scav_runner", "class_id": "scrap_knight", "attributes": {"body": 1, "arcane": 1, "tech": 4}}
	assert_true(w.new_game(false, "balanced", false, sheet))
	assert_eq(w.protagonist_tech(), 4)
	var leader := w.party.leader()
	assert_eq(leader.member_id, "protagonist")
	assert_true(w.can_hack(leader), "Tech 4 beats the minimum")
	assert_eq(w.hack_bonus(leader), 30)
	assert_false(leader.abilities.has("hack"), "not on the member: handed out per fight")
	# Tech 1 is under the minimum.
	sheet["attributes"] = {"body": 3, "arcane": 2, "tech": 1}
	assert_true(w.new_game(false, "balanced", false, sheet))
	assert_false(w.can_hack(w.party.leader()))
	# A fight against a turret: the hack lands, the fight ends, the turret powers down and drops nothing.
	sheet["attributes"] = {"body": 1, "arcane": 1, "tech": 4}
	assert_true(w.new_game(false, "balanced", false, sheet))
	w.teleport_party(Vector2i(2, 12))
	var turret := w.spawn_summoned("shepherd_turret", Vector2i(3, 12), "enemy")
	assert_true(turret != null)
	var before := w.living_enemies().size()
	var kills := w.ledger.kills
	w.rules.initiative_die = 1
	w.rules.max_hit_chance = 100
	w.start_combat(true)
	assert_eq(w.mode, "combat")
	var s := w.combat.state
	assert_eq(s.active("enemy").size(), 1, "only the turret is engaged")
	var pc := s.by_id("p:protagonist")
	assert_true(pc != null)
	assert_true(pc.abilities.has("hack"), "the Hack action for the fight")
	assert_eq(int(pc.traits.get("hack_bonus", 0)), 30)
	for c: Combatant in s.active("party"):
		if c.id == "p:unit_9":
			assert_true(c.abilities.has("hack"), "and the Drone Shepherd")
		elif c.id == "p:weaver":
			assert_false(c.abilities.has("hack"))
	if s.current() != pc:
		assert_eq(s.switch_to(pc.id), "")
	pc.traits["hack_bonus"] = 100 # certain, for the test
	var tc := s.by_id(s.active("enemy")[0].id)
	pc.cell = Vector2i(2, 12)
	tc.cell = Vector2i(3, 12)
	assert_eq(s.can_use(pc, "hack", tc.cell), "")
	w.combat.select_ability(pc.abilities.find("hack")) # through the controller, as a click would
	w.combat.player_click(tc.cell)
	assert_true(tc.hacked, "the hack landed")
	assert_true(s.finished, "no hostile left")
	assert_eq(s.result, "victory")
	assert_eq(w.mode, "explore")
	assert_eq(w.living_enemies().size(), before - 1, "the turret powered down")
	assert_eq(w.ledger.kills, kills, "and was no kill")
	_drop(w)


func test_tech_hacks_a_locked_gate_the_lever_would_open() -> void:
	var w := _fresh()
	assert_true(w.enter_map("gate_road"))
	var door := Vector2i(9, 4)
	assert_eq(w.map_data.door_kind(door), "locked")
	assert_eq(int(w.locked_door_at(door)["hack_tech"]), 3)
	w.teleport_party(Vector2i(8, 4))
	assert_eq(w.adjacent_door(), door)
	assert_eq(w.protagonist_tech(), 0, "no protagonist: nobody to hack")
	assert_contains(w.status_line(), "LOCKED GATE — the relay lever on this road · Tech 3 would hack it (you have 0)")
	assert_false(w.interact(), "locked")
	assert_eq(w.map_data.door_kind(door), "locked")
	assert_contains(w.open_locked(door), "Tech 3 would hack it")
	w.protagonist = {"name": "Kest", "race_id": "trueborn", "origin_id": "scav_runner", "class_id": "scrap_knight", "attributes": {"body": 1, "arcane": 2, "tech": 2}}
	assert_contains(w.status_line(), "(you have 2)")
	assert_false(w.interact(), "Tech 2 is not enough")
	w.protagonist["attributes"]["tech"] = 3
	assert_contains(w.status_line(), "LOCKED GATE — [Tech 3] Enter / A hacks it")
	assert_true(w.interact(), "Tech 3 hacks it")
	assert_eq(w.map_data.door_kind(door), "", "open")
	assert_true(w.narrative.flag("gate_open"), "the gate's flag is set as the lever would set it")
	assert_false(w.narrative.flag("gate_lever_pulled"), "the lever was never pulled")
	# A gate with no hack_tech only answers to its key.
	assert_true(w.enter_map("undercity_throat"))
	var throat := Vector2i(11, 4)
	assert_eq(int(w.locked_door_at(throat)["hack_tech"]), 3)
	# The validator: a hack_tech that is not a whole number of at least 1.
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	var m: Dictionary = r.get_entry("maps", "gate_road").duplicate(true)
	m["doors"] = [{"cell": [9, 4], "key_flag": "x", "hack_tech": 0}]
	r.put("maps", "zz_gate", m)
	assert_any_contains(ContentValidator.validate(r, ["runtime"]), "doors[[9, 4]].hack_tech must be a whole number of at least 1")
	r.put("enemies", "zz_soft", {"name": "Soft", "family": "bastion", "archetype": "rusher", "stats": {"hp": 1}, "abilities": [], "art": {"placeholder": "rig"}, "traits": {"hackable": "yes"}})
	assert_any_contains(ContentValidator.validate(r, ["runtime"]), "traits.hackable must be true or false")
	r.free()
	_drop(w)
