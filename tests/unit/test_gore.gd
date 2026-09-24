## The gore slider and the mature layer (S61, D-117; GDD §5, §9): a gore
## setting, blood where actors are hit and fall, bodies where they die,
## marks that come back with a save, grime and failing lights as dressing.
extends TestCase

const DT := 1.0 / 60.0
const LEDGER := "user://test_ledger_gore.json"
const SAVES := "user://test_saves_gore"
const SETTINGS := "user://test_settings_gore.json"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()
	DecalLayer.level = "full"


static func _cleanup() -> void:
	for f: String in [LEDGER, SETTINGS]:
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
	w.settings_path = SETTINGS
	w.input_path = "user://test_input_gore.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


## Plays the yard's first fight the way test_world_scene does.
func _play_fight() -> CombatState:
	world.teleport_party(Vector2i(13, 4))
	world.check_encounters()
	var s := world.combat.state
	var steps := 0
	while not s.finished and steps < 600:
		steps += 1
		if not world.combat.current_is_player():
			break
		var actor := s.current()
		var target := EnemyBrain.nearest_hostile(s, actor)
		if target == null:
			break
		if not EnemyBrain.usable_ability(s, actor, target).is_empty():
			world.combat.player_click(target.cell)
		elif actor.move_left > 0:
			var reach := s.reachable_cells(actor)
			var best := actor.cell
			var best_d := LineOfSight.distance(actor.cell, target.cell)
			var cells: Array = reach.keys()
			cells.sort()
			for cell: Vector2i in cells:
				var d := LineOfSight.distance(cell, target.cell)
				if d < best_d:
					best = cell
					best_d = d
			if best == actor.cell:
				world.combat.end_player_turn()
			else:
				world.combat.player_click(best)
		else:
			world.combat.end_player_turn()
	return s


func _kinds(marks: Array) -> Dictionary:
	var out: Dictionary = {}
	for m: Dictionary in marks:
		out[m["kind"]] = int(out.get(m["kind"], 0)) + 1
	return out


func test_gore_is_a_setting_with_three_levels_the_layer_follows() -> void:
	var s := Settings.new()
	assert_eq(s.gore, "full", "full by default: the game is the mature one the GDD describes")
	s.cycle_gore(1)
	assert_eq(s.gore, "off", "cycles round")
	s.cycle_gore(1)
	assert_eq(s.gore, "low")
	assert_eq(DecalLayer.cycle("full", -1), "low")
	assert_eq(s.save(SETTINGS), OK)
	assert_eq(Settings.load_or_default(SETTINGS).gore, "low", "round trip")
	assert_eq(Settings.from_dict({"gore": "bucketloads"}).gore, "full", "a value the layer has no level for is refused")
	s.apply()
	assert_eq(DecalLayer.level, "low", "apply pushes the level to the layer")
	Settings.new().apply()
	# The row, its hint, and adjusting through it.
	var labels: PackedStringArray = []
	var hint := ""
	for r: Dictionary in SettingsMenu.build_rows(world.settings):
		labels.append(String(r["label"]))
		if String(r["id"]) == "gore":
			hint = String(r["hint"])
			assert_eq(String(r["section"]), "Display")
	assert_true(labels.has("Gore: full"))
	assert_contains(hint, "off cleans every fight away")
	assert_true(world.open_settings())
	for i: int in world.settings_menu.rows.size():
		if String(world.settings_menu.rows[i]["id"]) == "gore":
			world.settings_menu.cursor = i
	assert_true(world.adjust_setting(1))
	assert_eq(world.settings.gore, "off")
	assert_eq(DecalLayer.level, "off")
	assert_eq(world.map_view.decals.level, "off", "the layer under the map follows the setting")
	assert_true(world.confirm_setting(), "Enter cycles too")
	assert_eq(world.settings.gore, "low")
	assert_contains(world.settings_menu.label.text, "Gore: low")
	world.close_settings()
	assert_eq(Settings.load_or_default(SETTINGS).gore, "low", "saved on leaving")


func test_a_fight_leaves_blood_pools_and_bodies_the_level_filters() -> void:
	assert_eq(world.marks_here().size(), 0, "a clean yard")
	var s := _play_fight()
	assert_true(s.finished)
	var marks := world.marks_here()
	var kinds := _kinds(marks)
	assert_true(int(kinds.get("splat", 0)) >= 1, "hits left splats: %s" % [kinds])
	assert_true(int(kinds.get("corpse", 0)) >= 1, "the dead left bodies: %s" % [kinds])
	if s.result == "victory":
		assert_eq(int(kinds.get("corpse", 0)), 3, "three engaged enemies died, three bodies")
	for m: Dictionary in marks:
		assert_true(world.map_data.in_bounds(Vector2i(int(m["x"]), int(m["y"]))))
		assert_true(DecalLayer.KINDS.has(String(m["kind"])))
		assert_true(DecalLayer.FLUIDS.has(String(m["fluid"])))
	var decals := world.map_view.decals
	assert_eq(decals.marks.size(), marks.size(), "the layer holds the same list")
	assert_eq(decals.visible_count(), marks.size(), "full draws every mark")
	decals.set_level("low")
	assert_eq(decals.visible_count(), marks.size() - int(kinds.get("splat", 0)), "low hides the splats")
	decals.set_level("off")
	assert_eq(decals.visible_count(), 0)
	decals.set_level("nonsense")
	assert_eq(decals.level, "full")
	assert_true(marks.size() <= DecalLayer.MARKS_MAX)
	assert_eq(world.narrative.marks.get("proto_yard", []).size(), marks.size(), "a handcrafted map keeps them in the story")


func test_machines_leak_oil_wisps_leave_nothing_and_the_cap_holds() -> void:
	assert_eq(DecalLayer.make(Vector2i(1, 2), "pool", 7, "oil", "#123456"), {"x": 1, "y": 2, "kind": "pool", "seed": 7, "fluid": "oil", "color": "#123456"})
	assert_eq(String(DecalLayer.make(Vector2i(0, 0), "gibs", 0, "ichor")["kind"]), "splat", "unknown kinds and fluids fall back")
	assert_eq(String(DecalLayer.make(Vector2i(0, 0), "gibs", 0, "ichor")["fluid"]), "blood")
	assert_true(DecalLayer.shows({"kind": "corpse"}, "low"))
	assert_false(DecalLayer.shows({"kind": "splat"}, "low"))
	assert_false(DecalLayer.shows({"kind": "corpse"}, "off"))
	for id: String in ["feral_drone", "shepherd_drone", "shepherd_turret", "warden_construct", "drone_mother"]:
		assert_eq(String(Dictionary(world.registry.get_entry("enemies", id).get("traits", {})).get("fluid", "")), "oil", "%s is a machine" % id)
	assert_eq(String(Dictionary(world.registry.get_entry("enemies", "echo_wisp").get("traits", {})).get("fluid", "")), "none")
	assert_false(world.registry.get_entry("enemies", "chrome_addict").get("traits", {}).has("fluid"), "flesh says nothing and bleeds")
	# The validator refuses a fluid the layer cannot draw, and a flicker with no glow.
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	r.put("enemies", "zz_ichor", {"name": "Ichor", "family": "bastion", "archetype": "rusher", "stats": {"hp": 1}, "abilities": [], "art": {"placeholder": "rig"}, "traits": {"fluid": "ichor"}})
	r.put("tiles", "zz_dark", {"name": "Dark", "layer": "ground", "walkable": true, "sound": "sfx_step_concrete", "art": {"shape": "floor", "flicker": true}})
	var problems := ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "enemies/zz_ichor (runtime): traits.fluid must be blood, oil or none")
	assert_any_contains(problems, "tiles/zz_dark (runtime): art.flicker needs an art.glow")
	r.free()
	# The cap: the oldest go first.
	for i: int in DecalLayer.MARKS_MAX + 25:
		world.leave_mark(Vector2i(2, 2), "splat", "blood")
	assert_eq(world.marks_here().size(), DecalLayer.MARKS_MAX)
	assert_eq(world.map_view.decals.marks.size(), DecalLayer.MARKS_MAX + 25, "the layer's own list is trimmed on the next restore")
	world.restore_marks()
	assert_eq(world.map_view.decals.marks.size(), DecalLayer.MARKS_MAX)


func test_marks_come_back_with_a_save_on_a_map_and_in_a_shard() -> void:
	world.leave_mark(Vector2i(3, 3), "corpse", "blood", "#c94b3a")
	world.leave_mark(Vector2i(4, 3), "pool", "oil")
	world.teleport_party(Vector2i(6, 12))
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.marks_here().size(), 0)
	assert_eq(again.load_slot(1), [])
	assert_eq(again.marks_here().size(), 2, "the yard's marks came back")
	assert_eq(again.map_view.decals.marks.size(), 2, "and the layer has them")
	assert_eq(String(again.marks_here()[0]["color"]), "#c94b3a")
	_drop(again)
	# A Shard keeps its own in the run; leaving the Shard leaves them behind.
	var entry := world.enter_shard("rusted_undercity", 7)
	assert_true(world.run.in_shard)
	assert_eq(world.marks_here().size(), 0, "a fresh Shard is clean")
	world.leave_mark(Vector2i(5, 5), "pool", "blood")
	assert_eq(world.run.marks.size(), 1)
	assert_eq(world.narrative.marks.get(String(entry["id"]), []).size(), 0, "not in the story")
	world.teleport_party(world.extraction_cell())
	assert_eq(world.save_slot(2), OK)
	var third := _fresh()
	assert_eq(third.load_slot(2), [])
	assert_true(third.run.in_shard)
	assert_eq(third.run.marks.size(), 1, "the Shard's marks ride the run")
	assert_eq(third.map_view.decals.marks.size(), 1)
	assert_true(third.extract())
	assert_eq(third.run.marks.size(), 0, "banked and gone")
	assert_eq(third.marks_here().size(), 2, "home still has its two")
	_drop(third)


func test_grime_and_failing_lights_dress_the_yard_and_every_shard() -> void:
	var grime: Dictionary = world.registry.get_entry("tiles", "floor_grime")
	assert_true(bool(grime.get("walkable", false)))
	assert_eq(String(Dictionary(grime["art"]).get("pattern", "")), "grime")
	var light: Dictionary = world.registry.get_entry("tiles", "dead_light")
	assert_eq(String(Dictionary(light["art"]).get("glow", "")), "failing_light")
	assert_true(bool(Dictionary(light["art"]).get("flicker", false)))
	# The yard has both, and they walk.
	var grime_cells := 0
	var light_cells := 0
	for y: int in world.map_data.height:
		for x: int in world.map_data.width:
			var id := world.map_data.tile_id_at(Vector2i(x, y))
			if id == "floor_grime":
				grime_cells += 1
				assert_true(world.map_data.is_walkable(Vector2i(x, y)))
			elif id == "dead_light":
				light_cells += 1
				assert_true(world.map_data.is_walkable(Vector2i(x, y)))
	assert_eq(grime_cells, 4)
	assert_eq(light_cells, 2)
	assert_eq(world.map_view.lighting.flickering.size(), 2, "a light per failing light")
	var l := world.map_view.lighting.flickering[0]
	var before := l.energy
	world.map_view.lighting._process(0.37)
	assert_true(l.energy != before or absf(LightingRig.flicker_energy(0.9, 0.37) - before) < 0.001, "the light moved")
	assert_true(LightingRig.flicker_energy(0.9, 0.0) > 0.1 and LightingRig.flicker_energy(0.9, 0.0) <= 0.9)
	assert_true(LightingRig.flicker_energy(0.9, 0.05) < LightingRig.flicker_energy(0.9, 0.5), "the stutter drops it")
	# Every Shard template scatters both with its own RNG, so the layout is what it was.
	for t: Dictionary in world.registry.get_all("shards"):
		var template: Dictionary = ShardGenerator.expand_remix(t, world.registry)
		var gen := ShardGenerator.generate(template, 7, 2, [])
		var legend: Dictionary = gen["legend"]
		assert_eq(String(legend.get("g", "")), "floor_grime", "%s legend" % t["id"])
		assert_eq(String(legend.get("l", "")), "dead_light")
		var rows: Array = gen["rows"]
		var g := 0
		var lights := 0
		for row: String in rows:
			g += row.count("g")
			lights += row.count("l")
		assert_true(g >= 5, "%s has grime: %d" % [t["id"], g])
		assert_true(lights >= 1, "%s has a failing light: %d" % [t["id"], lights])
		var bare: Dictionary = template.duplicate(true)
		bare["grime_density"] = 0.0
		bare["light_density"] = 0.0
		var plain := ShardGenerator.generate(bare, 7, 2, [])
		var plain_rows: Array = plain["rows"]
		for i: int in rows.size():
			assert_eq(String(rows[i]).replace("g", ".").replace("l", "."), String(plain_rows[i]), "%s row %d: dressing only replaces plain floor" % [t["id"], i])
	# The pattern draws.
	var img := PlaceholderTiles.draw_tile(grime["art"], world.registry.get_entry("biomes", "rusted_undercity")["palette"])
	var colours: Dictionary = {}
	for y: int in range(34, 62):
		for x: int in range(8, 56):
			colours[img.get_pixel(x, y).to_html()] = true
	assert_true(colours.size() >= 3, "fill, edge and soot: %s" % [colours.keys()])
