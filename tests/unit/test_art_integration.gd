## Art integration (S56, D-111): every race and enemy draws with a sheet
## that exists or says it is the placeholder rig, and a status doc lists
## them; the lighting pass (ambient, a light per glowing tile up to a
## budget, one on the leader) and the screen effects are settings the
## screenshots can force.
extends TestCase

const LEDGER := "user://test_ledger_art.json"
const SAVES := "user://test_saves_art"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	LightingRig.enabled = true
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()
	LightingRig.enabled = true


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.settings_path = "user://test_settings_art.json"
	w.input_path = "user://test_input_art.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func test_every_race_and_enemy_has_a_sheet_or_a_documented_placeholder() -> void:
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	var result := ArtStatus.report(r)
	assert_eq(result["problems"], PackedStringArray(), "every race and enemy says what it draws with")
	assert_eq(int(result["sheets"]), 2, "the two placeholder sheets: trueborn and scav")
	assert_eq(ArtStatus.art_of(r, r.get_entry("races", "trueborn")), "sheet trueborn")
	assert_eq(ArtStatus.art_of(r, r.get_entry("races", "chromed")), "placeholder rig")
	assert_eq(ArtStatus.art_of(r, r.get_entry("enemies", "scav")), "sheet scav")
	assert_eq(ArtStatus.art_of(r, r.get_entry("enemies", "feral_drone")), "placeholder rig")
	assert_eq(ArtStatus.art_of(r, {"id": "x", "art": {"sheet": "no_such_sheet"}}), "sheet no_such_sheet (missing sidecar)")
	assert_eq(ArtStatus.art_of(r, {"id": "x"}), "")
	# The committed status doc names every race and enemy.
	var doc := FileAccess.get_file_as_string("res://docs/art-status.md")
	assert_false(doc.is_empty(), "docs/art-status.md exists")
	for race: Dictionary in r.get_all("races"):
		assert_contains(doc, "| %s |" % race["name"], "the status doc names %s" % race["id"])
	for e: Dictionary in r.get_all("enemies"):
		assert_contains(doc, "| %s |" % e["name"], "the status doc names %s" % e["id"])
	assert_contains(doc, "placeholder rig")
	assert_contains(doc, "sheet trueborn")
	# The validator refuses silence.
	r.put("races", "zz_mute", {"name": "Mute", "overlay": {"kind": "none"}})
	r.put("enemies", "zz_ghost", {"name": "Ghost", "family": "rusted_undercity", "archetype": "rusher", "stats": {"hp": 1}, "abilities": ["strike"], "art": {"sheet": "no_such_sheet", "color": "#ffffff"}})
	var problems := ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "races/zz_mute (runtime): art needs a sheet or a documented placeholder")
	assert_any_contains(problems, "enemies/zz_ghost (runtime): art.sheet points at sprites 'no_such_sheet'")
	r.put("tiles", "zz_lamp", {"name": "Lamp", "layer": "ground", "walkable": true, "art": {"shape": "floor", "fill": "floor", "glow": "no_such_role"}})
	problems = ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "art.glow role 'no_such_role' is not in the rusted_undercity palette")
	r.free()


func test_the_lighting_pass_lights_glowing_tiles_up_to_a_budget_and_follows_the_leader() -> void:
	var rig := world.map_view.lighting
	assert_true(rig != null, "the map view carries the rig")
	assert_true(rig.ambient_node is CanvasModulate)
	assert_eq(rig.ambient, Color.html(String(world.registry.get_entry("rules", "lighting")["ambient"])), "the ambient comes from the rules")
	assert_eq(rig.ambient_node.color, rig.ambient, "and dims the world")
	seed(20260922)
	assert_false(world.enter_shard("rusted_undercity", 7, 1).is_empty())
	var budget := int(world.registry.get_entry("rules", "lighting")["max_lights"])
	assert_true(rig.lights.size() > 0, "a Shard has glowing tiles: %d lights" % rig.lights.size())
	assert_true(rig.lights.size() <= budget, "no more than the budget")
	var neon := Color.html(String(world.registry.get_entry("biomes", "rusted_undercity")["palette"]["neon_tech"]))
	var pad := world.extraction_cell()
	var pad_light: PointLight2D = null
	for l: PointLight2D in rig.lights:
		if l.position == world.map_view.cell_to_world(pad):
			pad_light = l
	assert_true(pad_light != null, "the extraction pad glows")
	assert_eq(pad_light.color, neon, "in the palette's neon_tech")
	assert_true(pad_light.energy > 0.0)
	assert_eq(pad_light.blend_mode, Light2D.BLEND_MODE_ADD)
	for l: PointLight2D in rig.lights:
		var cell := world.map_view.world_to_cell(l.position)
		assert_false(String(Dictionary(world.map_data.tile_at(cell).get("art", {})).get("glow", "")).is_empty(), "every light stands on a glowing tile")
	# The leader's light walks with the leader.
	world._process(1.0 / 60.0)
	assert_eq(rig.party_light.position, world.party.leader().position)
	world.teleport_party(pad)
	world._process(1.0 / 60.0)
	assert_eq(rig.party_light.position, world.party.leader().position)
	# Off: full brightness, nothing drawn; on again: back.
	world.settings.lighting = false
	world.settings.apply()
	world.apply_visual_settings()
	assert_false(LightingRig.enabled)
	assert_eq(rig.ambient_node.color, Color.WHITE)
	assert_false(rig.party_light.visible)
	assert_false(rig.lights[0].visible)
	world.settings.lighting = true
	world.settings.apply()
	world.apply_visual_settings()
	assert_eq(rig.ambient_node.color, rig.ambient)
	assert_true(rig.lights[0].visible)
	# A map without neon has no lights; the rig survives a rebuild.
	assert_true(world.enter_map("lattice_enclave"))
	var glowing := 0
	for y: int in world.map_data.height:
		for x: int in world.map_data.width:
			var c := Vector2i(x, y)
			if not world.map_data.is_enclosed(c) and not String(Dictionary(world.map_data.tile_at(c).get("art", {})).get("glow", "")).is_empty():
				glowing += 1
	assert_eq(rig.lights.size(), glowing, "one light per glowing cell on a handcrafted map")
	assert_true(world.enter_map("bastion"))
	assert_true(rig.lights.size() >= 0)
	# A tiny budget caps the count.
	world.registry.put("rules", "lighting", {"name": "Lighting", "ambient": "#404040", "max_lights": 3, "glow_energy": 0.5, "glow_radius": 64, "party_light": {"energy": 0.2, "radius": 50}})
	assert_false(world.enter_shard("rusted_undercity", 8, 1).is_empty())
	assert_eq(rig.lights.size(), 3, "capped")
	assert_eq(rig.ambient, Color.html("#404040"))
	assert_true(is_equal_approx(rig.party_light.energy, 0.2))
	world.registry._entries["rules"].erase("lighting")
	world.registry._fingerprint_cache = ""
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	world.registry.put("rules", "lighting", r.get_entry("rules", "lighting"))
	r.free()


func test_screen_effects_are_a_setting_the_screenshots_can_force() -> void:
	assert_eq(world.screen_fx.mode, "glow", "glow by default")
	assert_true(world.screen_fx.visible)
	assert_eq(world.screen_fx.layer, 99, "under the colour filter")
	assert_eq(int(world.screen_fx.material_ref.get_shader_parameter("mode")), 1)
	world.screen_fx.set_mode("crt")
	assert_eq(int(world.screen_fx.material_ref.get_shader_parameter("mode")), 2)
	world.screen_fx.set_mode("off")
	assert_false(world.screen_fx.visible)
	world.screen_fx.set_mode("nonsense")
	assert_eq(world.screen_fx.mode, "glow")
	assert_eq(ScreenFx.cycle("off", -1), "crt")
	assert_eq(world.screen_fx.rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var s := Settings.new()
	assert_eq(s.screen_fx, "glow")
	assert_true(s.lighting)
	s.cycle_screen_fx(1)
	assert_eq(s.screen_fx, "crt")
	s.lighting = false
	assert_eq(s.save("user://test_settings_art2.json"), OK)
	var back := Settings.load_or_default("user://test_settings_art2.json")
	assert_eq(back.screen_fx, "crt")
	assert_false(back.lighting)
	assert_eq(Settings.from_dict({"screen_fx": "weird"}).screen_fx, "glow")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings_art2.json"))
	# The rows.
	var labels: PackedStringArray = []
	for r: Dictionary in SettingsMenu.build_rows(world.settings):
		labels.append(String(r["label"]))
	assert_true(labels.has("Lighting: on"))
	assert_true(labels.has("Screen effects: glow"))
	assert_true(world.open_settings())
	for i: int in world.settings_menu.rows.size():
		if String(world.settings_menu.rows[i]["id"]) == "screen_fx":
			world.settings_menu.cursor = i
	assert_true(world.adjust_setting(1))
	assert_eq(world.settings.screen_fx, "crt")
	assert_eq(world.screen_fx.mode, "crt", "the pass follows the setting")
	for i: int in world.settings_menu.rows.size():
		if String(world.settings_menu.rows[i]["id"]) == "lighting":
			world.settings_menu.cursor = i
	assert_true(world.confirm_setting())
	assert_false(world.settings.lighting)
	assert_eq(world.map_view.lighting.ambient_node.color, Color.WHITE, "the rig follows the setting")
	world.settings_menu.close()
