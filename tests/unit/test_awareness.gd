## Awareness as a cone and a detection roll (S64, D-120; GDD §9): a placed
## enemy sees a cone and hears close behind, notices at once up close and
## over a meter farther out, rolls against the party's stealth at the top,
## and striking one that has not noticed you is an opener from cover.
extends TestCase

const LEDGER := "user://test_ledger_aware.json"
const SAVES := "user://test_saves_aware"

const CONE_MAP: Dictionary = {
	"id": "zz_cone", "name": "Cone yard", "biome": "rusted_undercity", "spawn_marker": "P",
	"legend": {".": "floor_concrete", "#": "wall_rust", "P": "floor_concrete"},
	"rows": [
		"####################",
		"#..................#",
		"#P.P...............#",
		"#P.P......E........#",
		"#..................#",
		"#..................#",
		"####################",
	],
	"enemies": [{"type": "scav", "cell": [10, 3], "facing": "e"}],
}

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
	world.settings_path = "user://test_settings_aware.json"
	world.input_path = "user://test_input_aware.json"
	_root().add_child(world)
	world.combat.animate = false


func after_each() -> void:
	_root().remove_child(world)
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


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _enter_cone_map() -> EnemyActor:
	var entry := CONE_MAP.duplicate(true)
	world.mode = "explore" # a fight from an earlier step is over for the test's purposes
	world.party.active = true
	entry["rows"] = Array(entry["rows"]).duplicate()
	entry["rows"][3] = "#P.P...............#" # E was only a marker for the reader
	assert_true(world._enter(entry))
	var e := world.enemy_at(Vector2i(10, 3))
	assert_true(e != null)
	return e


func test_the_cone_is_pure_geometry_and_a_placement_faces_an_enemy() -> void:
	assert_true(EnemyActor.cone_contains(Vector2(1, 0), Vector2i(0, 0), Vector2i(5, 0), 180.0), "dead ahead")
	assert_true(EnemyActor.cone_contains(Vector2(1, 0), Vector2i(0, 0), Vector2i(3, 3), 180.0), "45 degrees off, inside a half circle")
	assert_true(EnemyActor.cone_contains(Vector2(1, 0), Vector2i(0, 0), Vector2i(0, 4), 180.0), "the edge counts")
	assert_false(EnemyActor.cone_contains(Vector2(1, 0), Vector2i(0, 0), Vector2i(-1, 4), 180.0), "just behind the edge")
	assert_false(EnemyActor.cone_contains(Vector2(1, 0), Vector2i(0, 0), Vector2i(-5, 0), 180.0), "behind")
	assert_false(EnemyActor.cone_contains(Vector2(1, 0), Vector2i(0, 0), Vector2i(3, 3), 60.0), "a narrow cone misses 45 degrees")
	assert_true(EnemyActor.cone_contains(Vector2(1, 0), Vector2i(2, 2), Vector2i(2, 2), 60.0), "your own cell")
	assert_eq(EnemyActor.FACINGS.size(), 8)
	var e := _enter_cone_map()
	assert_true(e.has_facing)
	assert_eq(e.facing_dir, Vector2i(1, 0))
	assert_eq(e.look_dir(), Vector2(1, 0))
	assert_true(e.in_cone(Vector2i(14, 3), world.rules.vision_cone_degrees))
	assert_false(e.in_cone(Vector2i(6, 3), world.rules.vision_cone_degrees))
	assert_true(e.facing.x > 0.0, "the sprite faces the way it looks (screen east is +x)")
	e.set_facing_name("")
	assert_false(e.has_facing)
	assert_true(e.in_cone(Vector2i(6, 3), world.rules.vision_cone_degrees), "no facing: all round, as before S64")
	# A sweep swings the look.
	e.set_facing_name("e", 90.0, 4.0)
	assert_eq(e.look_dir(), Vector2(1, 0))
	e.tick_sweep(1.0) # a quarter period: full swing one way
	assert_true(absf(rad_to_deg(e.look_dir().angle())) > 80.0, "swung 90 degrees: %s" % e.look_dir())
	e.tick_sweep(1.0)
	assert_true(absf(e.look_dir().angle()) < 0.01, "back to straight ahead at the half period")
	# Every placed facing is one of the eight, says the validator.
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	var m: Dictionary = r.get_entry("maps", "proto_yard").duplicate(true)
	m["enemies"] = [{"type": "scav", "cell": [14, 2], "facing": "up", "sweep": 400}]
	r.put("maps", "zz_face", m)
	var problems := ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "enemy at (14, 2) faces 'up'; use e, se, s, sw, w, nw, n or ne")
	assert_any_contains(problems, "sweep must be 0 to 180 degrees")
	r.free()
	assert_eq(String(Dictionary(world.registry.get_entry("maps", "proto_yard")["enemies"][3]).get("facing", "")), "n", "the yard's addict looks north and sweeps")


func test_behind_a_facing_enemy_is_safe_beyond_earshot_and_a_settled_look_ahead_is_a_fight() -> void:
	var e := _enter_cone_map()
	assert_eq(e.awareness, 5)
	world.teleport_party(Vector2i(6, 3)) # four cells behind it
	assert_false(world.check_encounters(), "behind the cone, beyond hearing")
	assert_eq(world.mode, "explore")
	world.teleport_party(Vector2i(8, 3)) # two cells behind: it hears
	assert_true(world.check_encounters(), "close behind, it hears")
	assert_eq(world.mode, "combat")
	assert_eq(world.combat.state.active("party")[0].hidden, false, "an awareness fight is no opener")


func test_the_meter_fills_in_view_empties_out_of_view_and_rolls_at_the_top() -> void:
	var e := _enter_cone_map()
	world.rules.detect_base = 1.0 # certain, for the first pass
	world.teleport_party(Vector2i(14, 3)) # four ahead: in the cone, past the instant radius
	assert_false(world.check_encounters(0.1), "one frame is not enough")
	assert_true(e.noticed > 0.0 and e.noticed < 1.0, "the meter moved: %f" % e.noticed)
	assert_contains(world.status_line(), "⚠ noticed")
	var was := e.noticed
	world.teleport_party(Vector2i(6, 3)) # out of view
	assert_false(world.check_encounters(0.5))
	assert_true(e.noticed < was, "it empties")
	world.teleport_party(Vector2i(14, 3))
	var frames := 0
	while world.mode == "explore" and frames < 100:
		world.check_encounters(0.1)
		frames += 1
	assert_eq(world.mode, "combat", "the meter filled and the roll was certain")
	assert_true(frames >= 5 and frames <= 20, "about a second at four cells: %d frames" % frames)
	# Up close it is instant.
	var again := _enter_cone_map()
	world.teleport_party(Vector2i(12, 3))
	assert_true(world.check_encounters(0.016), "two cells ahead: noticed at once")
	assert_eq(again.noticed, 1.0)
	# The roll: sharper enemies and stealthier parties.
	var r := CombatRules.new() # the shipped numbers, not the certain ones set above
	assert_eq(ExploreWorld.detection_chance(r, r.awareness_default, 0), r.detect_base)
	assert_true(ExploreWorld.detection_chance(r, 8, 0) > r.detect_base, "a sharp one")
	assert_true(ExploreWorld.detection_chance(r, 5, 2) < r.detect_base, "a quiet party")
	assert_eq(ExploreWorld.detection_chance(r, 0, 99), 0.05, "never below 5%")
	assert_eq(world.party_stealth(), 0)
	world.party.leader().traits["stealth"] = 2
	assert_eq(world.party_stealth(), 2, "the best among the standing")
	assert_eq(int(Dictionary(world.registry.get_entry("origins", "scav_runner")["traits"]).get("stealth", 0)), 1, "a Scav Runner knows how to move")
	# A failed roll is a second look, not a free pass: with detection at the floor the meter drops to half and refills.
	var third := _enter_cone_map()
	world.rules.detect_base = 0.0
	world.detect_rng.seed = 7
	world.teleport_party(Vector2i(14, 3))
	var looks := 0
	var second_looks := 0
	while world.mode == "explore" and looks < 400:
		var before := third.noticed
		world.check_encounters(0.1)
		if third.noticed < before:
			second_looks += 1
		looks += 1
	assert_true(second_looks >= 1, "at least one failed roll reset the meter to half")
	assert_eq(world.mode, "combat", "5% a look gets there in the end")


func test_striking_an_unaware_enemy_is_an_opener_from_cover() -> void:
	var e := _enter_cone_map()
	world.teleport_party(Vector2i(12, 3))
	assert_eq(e.noticed, 0.0)
	world.rules.initiative_die = 1
	world.start_combat(true, true)
	assert_eq(world.mode, "combat")
	var s := world.combat.state
	for c: Combatant in s.active("party"):
		assert_true(c.hidden, "%s starts from cover" % c.id)
	assert_true(s.history[s.history.size() - 1].contains("strikes from cover") or s.history.any(func(l: String) -> bool: return l.contains("strikes from cover")), "logged")
	var actor := s.current()
	assert_eq(actor.team, "party")
	var foe := EnemyBrain.nearest_hostile(s, actor)
	actor.cell = Vector2i(11, 3) # beside it, for the strike
	foe.cell = Vector2i(10, 3)
	var blow := EnemyBrain.usable_ability(s, actor, foe)
	assert_false(blow.is_empty(), "something to hit with")
	var ev := s.use_ability(actor, blow, foe.cell)
	assert_true(bool(ev.get("ambush", false)), "the first blow is an ambush")
	assert_false(actor.hidden, "and it reveals")
	# The plain first strike, as every test before S64 uses it, is no opener.
	var again := _enter_cone_map()
	assert_true(again != null)
	world.teleport_party(Vector2i(12, 3))
	world.start_combat(true)
	for c: Combatant in world.combat.state.active("party"):
		assert_false(c.hidden)
