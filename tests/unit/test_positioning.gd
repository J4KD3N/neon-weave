## Positioning (S65, D-121; GDD §9 "cover, flanking, elevation"): a climb
## costs Move, leaving a melee fighter's reach draws its free strike, each
## AI archetype weighs the ground its own way, hidden enemies are unseen
## unless someone can sense them, and placed enemies can walk a patrol.
extends TestCase

const LEDGER := "user://test_ledger_pos.json"
const SAVES := "user://test_saves_pos"

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
	"low": {"id": "low", "walkable": false, "blocks_sight": false, "cover": 1},
	"walk": {"id": "walk", "walkable": true, "height": 1},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [4, 4], "accuracy": 100, "damage_type": "physical"},
	"big": {"id": "big", "name": "Big", "ap": 2, "range": 1, "damage": [20, 20], "accuracy": 100, "damage_type": "physical"},
	"shoot": {"id": "shoot", "name": "Shoot", "ap": 1, "range": 5, "damage": [3, 3], "accuracy": 100, "damage_type": "tech", "requires_los": true},
}
const PATROL_MAP: Dictionary = {
	"id": "zz_patrol", "name": "Patrol yard", "biome": "rusted_undercity", "spawn_marker": "P",
	"legend": {".": "floor_concrete", "#": "wall_rust", "P": "floor_concrete"},
	"rows": [
		"####################",
		"#..................#",
		"#P.P...............#",
		"#P.P...............#",
		"#..................#",
		"#..................#",
		"####################",
	],
	"enemies": [{"type": "scav", "cell": [10, 3], "patrol": [[14, 3], [10, 3]], "patrol_speed": 2.0, "patrol_wait": 0.3}],
}

var events: Array[Dictionary] = []


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "p", "legend": {".": "floor", "#": "wall", "x": "low", "k": "walk", "P": "floor"}, "rows": rows}, TILES)


static func _rules() -> CombatRules:
	var r := CombatRules.new()
	r.min_hit_chance = 0
	r.max_hit_chance = 100
	r.initiative_die = 1
	return r


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], move: int = 6, archetype: String = "rusher") -> Combatant:
	var c := Combatant.make(id, id, team, cell, {"hp": 10, "move": move, "evasion": 0, "initiative": 0}, abilities, 4)
	c.archetype = archetype
	return c


func _state(rows: Array, combatants: Array[Combatant], rules: CombatRules = _rules()) -> CombatState:
	var s := CombatState.new()
	s.setup(_map(rows), rules, ABILITIES, combatants, 3)
	events.clear()
	s.event.connect(func(e: Dictionary) -> void: events.append(e))
	s.start("party")
	return s


func _of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if String(e["type"]) == kind:
			out.append(e)
	return out


func test_a_climb_costs_move_and_the_path_knows_it() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["strike"], 3)
	var s := _state(["P.k.."], [p])
	var reach := s.reachable_cells(p)
	assert_eq(int(reach[Vector2i(1, 0)]), 1)
	assert_eq(int(reach[Vector2i(2, 0)]), 3, "one step plus the climb")
	assert_false(reach.has(Vector2i(3, 0)), "the step down is one more than Move 3 allows")
	var p6 := _c("p6", "party", Vector2i(0, 0), ["strike"], 6)
	var s6 := _state(["P.k.."], [p6])
	var reach6 := s6.reachable_cells(p6)
	assert_eq(int(reach6[Vector2i(3, 0)]), 4, "down costs nothing extra")
	assert_eq(int(reach6[Vector2i(4, 0)]), 5)
	assert_true(s6.move(p6, Vector2i(3, 0)))
	assert_eq(p6.move_left, 2, "Move paid at the flood's cost, not the step count")
	assert_eq(int(_of("move")[0]["move_left"]), 2)
	assert_true(s6.undo_move(), "a quiet move undoes")
	assert_eq(p6.move_left, 6)
	# A cheaper way round a hill is taken when there is one.
	var p7 := _c("p7", "party", Vector2i(0, 0), ["strike"], 6)
	var s7 := _state(["P.k..", "....."], [p7])
	var path := s7.move_path(p7, Vector2i(3, 0))
	assert_false(path.has(Vector2i(2, 0)), "the path goes round the catwalk: %s" % [path])
	assert_eq(int(s7.reachable_cells(p7)[Vector2i(3, 0)]), 3)
	var flat := CombatRules.new()
	assert_eq(flat.climb_move_cost, 1, "the shipped rule")
	assert_true(flat.opportunity_attacks)


func test_leaving_a_melee_fighters_reach_draws_a_free_strike_once_each() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["strike"])
	var e := _c("e", "enemy", Vector2i(1, 0), ["strike"])
	var s := _state(["P.....", "......"], [p, e])
	var path := s.move_path(p, Vector2i(3, 1))
	assert_eq(s.provokers_along(p, path).size(), 1, "the hint knows before the move: %s" % [path])
	assert_eq(s.provokers_along(p, s.move_path(p, Vector2i(1, 1))).size(), 0, "staying beside it draws nothing")
	assert_true(s.move(p, Vector2i(3, 1)))
	var strikes := _of("opportunity")
	assert_eq(strikes.size(), 1, "one free strike as p passes")
	assert_eq(String(strikes[0]["actor"]), "e")
	assert_eq(String(strikes[0]["target"]), "p")
	assert_true(bool(strikes[0]["hit"]))
	assert_eq(p.hp, 6, "the strike landed on the way")
	assert_eq(p.cell, Vector2i(3, 1), "and p got there")
	assert_true(bool(_of("move")[0]["provoked"]))
	assert_true(s.can_undo_move(p), "the move can be taken back")
	assert_true(s.undo_move())
	assert_eq(p.hp, 6, "but the strike it drew stands")
	assert_eq(p.cell, Vector2i(0, 0))
	assert_true(s.history.any(func(l: String) -> bool: return l.contains("catches p passing for 4")), "logged: %s" % [s.history])
	# Leaving and coming back beside the same fighter: still once per move.
	var p2 := _c("p2", "party", Vector2i(0, 0), ["strike"])
	var e2 := _c("e2", "enemy", Vector2i(1, 0), ["strike"])
	var s2 := _state(["P......", "......."], [p2, e2])
	assert_true(s2.move(p2, Vector2i(2, 1)))
	assert_eq(_of("opportunity").size(), 0, "(2,1) is still beside (1,0)")
	# A hidden fighter draws nothing, a hidden mover draws nothing, and the rules can turn it off.
	var p3 := _c("p3", "party", Vector2i(0, 0), ["strike"])
	var e3 := _c("e3", "enemy", Vector2i(1, 0), ["strike"])
	var s3 := _state(["P.....", "......"], [p3, e3])
	e3.hide(2)
	assert_true(s3.move(p3, Vector2i(3, 1)))
	assert_eq(_of("opportunity").size(), 0, "a hidden fighter does not step out to swing")
	var p4 := _c("p4", "party", Vector2i(0, 0), ["strike"])
	var e4 := _c("e4", "enemy", Vector2i(1, 0), ["strike"])
	var s4 := _state(["P.....", "......"], [p4, e4])
	p4.hide(2)
	assert_true(s4.move(p4, Vector2i(3, 1)))
	assert_eq(_of("opportunity").size(), 0, "nobody swings at what they cannot see")
	var off := _rules()
	off.opportunity_attacks = false
	var p5 := _c("p5", "party", Vector2i(0, 0), ["strike"])
	var e5 := _c("e5", "enemy", Vector2i(1, 0), ["strike"])
	var s5 := _state(["P.....", "......"], [p5, e5], off)
	assert_true(s5.move(p5, Vector2i(3, 1)))
	assert_eq(_of("opportunity").size(), 0, "off by the rules")
	# A ranged fighter has no reach to swing with.
	var p6 := _c("p6", "party", Vector2i(0, 0), ["strike"])
	var e6 := _c("e6", "enemy", Vector2i(1, 0), ["shoot"])
	var s6 := _state(["P.....", "......"], [p6, e6])
	assert_eq(s6.melee_ability(e6), "")
	assert_true(s6.move(p6, Vector2i(3, 1)))
	assert_eq(_of("opportunity").size(), 0)
	# A mover put down on the way stops where it fell, and the fight can end there.
	var p7 := _c("p7", "party", Vector2i(0, 0), ["strike"])
	var e7 := _c("e7", "enemy", Vector2i(1, 0), ["big"])
	var s7 := _state(["P.....", "......"], [p7, e7])
	assert_true(s7.move(p7, Vector2i(3, 1)))
	assert_eq(_of("opportunity").size(), 1)
	assert_true(bool(_of("opportunity")[0]["killed"]) or bool(_of("opportunity")[0]["downed"]), "put down on the way")
	assert_eq(p7.cell, Vector2i(2, 1), "fell on the cell it was leaving")
	assert_eq(Vector2i(_of("move")[0]["to"]), Vector2i(2, 1))
	assert_true(s7.finished)
	assert_eq(s7.result, "defeat")


func test_each_archetype_weighs_the_ground_its_own_way_and_avoids_free_strikes() -> void:
	var r := _rules()
	r.ai_cover_weight = 4
	r.ai_elevation_weight = 4
	r.ai_archetype_weights = {"ranged": {"cover": 2.0, "elevation": 1.5}, "rusher": {"cover": 0.5}}
	var ranged := _c("r", "enemy", Vector2i(0, 0), ["shoot"], 6, "ranged")
	var rusher := _c("m", "enemy", Vector2i(0, 1), ["strike"], 6, "rusher")
	var target := _c("t", "party", Vector2i(6, 0), ["strike"])
	var s := _state(["P.x...", "......", "..k..."], [target, ranged, rusher], r)
	var behind_cover := Vector2i(1, 0) # the low wall at (2,0) sits between (1,0) and the target
	assert_eq(EnemyBrain.position_score(s, ranged, behind_cover, target), 8, "cover 4 × 2")
	assert_eq(EnemyBrain.position_score(s, rusher, behind_cover, target), 2, "cover 4 × 0.5")
	assert_eq(EnemyBrain.position_score(s, ranged, Vector2i(2, 2), target), 6, "high ground 4 × 1.5")
	assert_eq(EnemyBrain.position_score(s, rusher, Vector2i(2, 2), target), 4, "no scale: the base weight")
	var reg := ContentRegistry.new()
	reg.load_from(ContentRegistry.BASE_ROOT, [])
	var shipped := CombatRules.from_entry(reg.get_entry("rules", "combat"))
	reg.free()
	assert_eq(float(Dictionary(shipped.ai_archetype_weights["ranged"])["cover"]), 1.5, "the shipped table")
	assert_eq(shipped.ai_opportunity_penalty, 6)
	# The approach key counts the strikes a path would draw as lost texture.
	var mover := _c("k", "enemy", Vector2i(0, 0), ["strike"], 6, "rusher")
	var guard := _c("g", "party", Vector2i(1, 0), ["strike"])
	var goal := _c("q", "party", Vector2i(5, 1), ["strike"])
	var s2 := _state(["P......", "......."], [guard, goal, mover], r)
	var field := s2.distance_field(goal.cell)
	var past_guard := EnemyBrain._approach_key(s2, mover, field, Vector2i(3, 1), goal.cell, goal, 3)
	var beside_guard := EnemyBrain._approach_key(s2, mover, field, Vector2i(2, 1), goal.cell, goal, 2)
	assert_eq(int(past_guard[1]), r.ai_opportunity_penalty, "the path to (3,1) leaves the guard's reach")
	assert_eq(int(beside_guard[1]), 0)


func test_hidden_enemies_are_unseen_unless_someone_can_sense_them() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.map_id = "proto_yard"
	w.home_map = "proto_yard"
	w.party_id = "prototype"
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.settings_path = "user://test_settings_pos.json"
	w.input_path = "user://test_input_pos.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	w.combat.animate = false
	w.rules.initiative_die = 1
	w.teleport_party(Vector2i(13, 4))
	w.start_combat(true)
	var s := w.combat.state
	var foe := s.active("enemy")[0]
	var foe_node: WorldActor = w.combat.actors[foe.id]
	var me := s.active("party")[0]
	var me_node: WorldActor = w.combat.actors[me.id]
	foe.hide(2)
	me.hide(2)
	w.combat._sync_all()
	assert_true(is_zero_approx(foe_node.modulate.a), "a hidden enemy is not drawn")
	assert_true(absf(me_node.modulate.a - 0.45) < 0.01, "a hidden party member is faint to the player")
	me.traits["detect_hidden"] = 9
	w.combat._sync_all()
	assert_true(absf(foe_node.modulate.a - 0.45) < 0.01, "sensed: drawn faint")
	me.traits.erase("detect_hidden")
	foe.reveal()
	me.reveal()
	w.combat._sync_all()
	assert_eq(foe_node.modulate.a, 1.0)
	assert_eq(me_node.modulate.a, 1.0)
	(Engine.get_main_loop() as SceneTree).root.remove_child(w)
	w.free()
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))


func test_a_placed_enemy_walks_its_patrol_faces_the_way_and_stops_for_people() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.map_id = "proto_yard"
	w.home_map = "proto_yard"
	w.party_id = "prototype"
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.settings_path = "user://test_settings_pos.json"
	w.input_path = "user://test_input_pos.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	w.combat.animate = false
	assert_true(w._enter(PATROL_MAP.duplicate(true)))
	var e := w.enemy_at(Vector2i(10, 3))
	assert_true(e != null)
	assert_eq(e.patrol, [Vector2i(14, 3), Vector2i(10, 3)])
	assert_eq(e.patrol_speed, 2.0)
	w.teleport_party(Vector2i(2, 2)) # far off, out of its awareness
	for i: int in 6:
		w.check_encounters(0.1)
	assert_eq(e.cell, Vector2i(11, 3), "one step at two cells a second after 0.6 s")
	assert_true(e.has_facing, "the walk gives it a facing")
	assert_eq(e.facing_dir, Vector2i(1, 0), "east, the way it walks")
	assert_true(w.enemy_at(Vector2i(11, 3)) == e, "enemy_at follows the cell")
	assert_true(w.enemy_at(Vector2i(10, 3)) == null)
	var ticks := 0
	while e.cell != Vector2i(14, 3) and ticks < 40:
		w.check_encounters(0.1)
		ticks += 1
	assert_eq(e.cell, Vector2i(14, 3), "at the far point")
	assert_true(ticks >= 10 and ticks <= 20, "three more steps at half a second each: %d ticks" % ticks)
	for i: int in 12:
		w.check_encounters(0.1)
	assert_true(e.cell.x < 14, "waited, then turned back: %s" % e.cell)
	assert_eq(e.facing_dir, Vector2i(-1, 0), "west now")
	assert_eq(w.mode, "explore", "nobody was seen")
	# Someone in the way: it waits.
	var before := e.cell
	w.teleport_party(e.cell + Vector2i(-1, 0))
	w.rules.notice_instant_radius = 0 # so the test can stand beside it a moment without a fight
	e.noticed = 0.0
	var moved := false
	for i: int in 10:
		var was := e.cell
		w.check_encounters(0.1)
		if w.mode != "explore":
			break
		if e.cell != was:
			moved = true
	assert_true(e.cell == before or w.mode == "combat", "blocked by the party or already fighting")
	(Engine.get_main_loop() as SceneTree).root.remove_child(w)
	w.free()
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	# The validator refuses a patrol point in a wall and a speed of nothing.
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	var m: Dictionary = PATROL_MAP.duplicate(true)
	m["enemies"] = [{"type": "scav", "cell": [10, 3], "patrol": [[0, 0]], "patrol_speed": 0}]
	r.put("maps", "zz_patrol_bad", m)
	var problems := ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "patrol point [0, 0] is not a walkable cell")
	assert_any_contains(problems, "patrol_speed must be above 0")
	r.free()
