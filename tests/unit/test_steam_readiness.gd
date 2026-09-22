## Steam (S58, D-113), as far as a checkout without a client can go: the
## readiness report names every blocker and every achievement, the Steam
## Input template covers every pad binding, the Workshop round-trips on
## the null backend and its items load as mods, the upload tool validates
## before it publishes, and thumbnails ride the cloud with their saves.
extends TestCase

const LEDGER := "user://test_ledger_steam58.json"
const SAVES := "user://test_saves_steam58"
const CLOUD := "user://test_cloud_steam58"
const WORKSHOP := "user://test_workshop_steam58"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d: String in dir.get_directories():
		_remove_tree(path.path_join(d))
	for f: String in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	for d: String in [SAVES, CLOUD, WORKSHOP]:
		_remove_tree(d)


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.settings_path = "user://test_settings_steam58.json"
	w.input_path = "user://test_input_steam58.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func test_the_readiness_report_names_the_blockers_and_the_achievements() -> void:
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	var result := SteamCheck.report(r, NullPlatformBackend.new())
	var text := "\n".join(result["lines"])
	if not Engine.has_singleton("Steam"):
		assert_false(bool(result["ready"]), "no client here: not ready")
		assert_any_contains(result["blockers"], "GodotSteam is not installed")
	assert_any_contains(result["blockers"], "app_id is 0")
	assert_any_contains(result["blockers"], "app_build.vdf still has")
	assert_contains(text, "## Achievements")
	for a: Dictionary in r.get_all("achievements"):
		assert_contains(text, "| `%s` | %s |" % [a["steam_id"], a["id"]], "the report lists %s for Steamworks" % a["id"])
	assert_contains(text, "slot_1.json, slot_1.png")
	assert_contains(text, "autosave_2.png")
	assert_eq(SteamCheck.cloud_files().size(), 12)
	assert_contains(text, "`--demo`")
	assert_contains(text, "Not ready. Blockers:")
	var doc := FileAccess.get_file_as_string("res://steam/READINESS.md")
	assert_false(doc.is_empty(), "steam/READINESS.md is committed")
	assert_contains(doc, "ACH_ENDING_DRIFT")
	r.free()
	# The build script parser.
	var ids := SteamCheck.build_ids()
	assert_eq(int(ids["app_id"]), 0)
	assert_eq(Array(ids["depots"]).size(), 3, "three platform depots")


func test_the_steam_input_template_covers_every_pad_binding() -> void:
	var bound := SteamCheck.template_bindings()
	for name: String in ["A", "B", "X", "Y", "shoulder_left", "shoulder_right", "start", "select", "dpad_up", "trigger_left", "trigger_right"]:
		assert_true(bound.has(name), "the template binds %s" % name)
	assert_eq(SteamCheck.template_gaps(), [], "every pad binding in InputActions has a Steam Input binding")
	assert_eq(SteamCheck.template_bindings("res://nope.vdf"), [])
	var gaps := SteamCheck.template_gaps("res://nope.vdf")
	assert_true(gaps.size() >= 10, "an empty template misses everything: %d" % gaps.size())


func test_the_workshop_round_trips_on_the_null_backend_and_its_items_load_as_mods() -> void:
	var b := NullPlatformBackend.new()
	b.workshop_dir = WORKSHOP
	assert_eq(b.workshop_items(), [])
	var refused: Dictionary = await b.workshop_publish("res://examples", "x", "y")
	assert_false(bool(refused["ok"]))
	assert_contains(String(refused["why"]), "has no mod.json")
	var first: Dictionary = await b.workshop_publish("res://examples/mods/stranger", "The Stranger", "An example mod")
	assert_true(bool(first["ok"]), String(first["why"]))
	assert_eq(int(first["item_id"]), 1)
	assert_eq(b.workshop_items(), [WORKSHOP.path_join("1")])
	assert_true(FileAccess.file_exists(WORKSHOP.path_join("1").path_join("mod.json")), "the folder was copied")
	assert_true(FileAccess.file_exists(WORKSHOP.path_join("1").path_join("content").path_join("races").path_join("ashwalker.json")), "with its content")
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORKSHOP.path_join("1").path_join("workshop.json")))
	assert_eq(String(Dictionary(meta)["title"]), "The Stranger")
	var second: Dictionary = await b.workshop_publish("res://examples/mods/stranger", "Again", "")
	assert_eq(int(second["item_id"]), 2, "the next id")
	var updated: Dictionary = await b.workshop_publish("res://examples/mods/stranger", "Updated", "", 1)
	assert_eq(int(updated["item_id"]), 1, "an update keeps its id")
	assert_eq(b.workshop_items().size(), 2)
	# An installed item is a mod root: the registry loads it.
	var r := ContentRegistry.new()
	r.extra_mod_roots = b.workshop_items()
	assert_true(r.default_mod_roots().has(WORKSHOP.path_join("1")))
	r.load_from(ContentRegistry.BASE_ROOT, [WORKSHOP.path_join("1")])
	assert_true(r.has_entry("races", "ashwalker"), "the Workshop mod's race loads")
	assert_eq(r.loaded_mods.size(), 1)
	r.free()
	# The upload tool: usage, a broken folder, then a good one on the null backend.
	var usage: Dictionary = await WorkshopUpload.run("")
	assert_eq(int(usage["code"]), 2)
	var broken: Dictionary = await WorkshopUpload.run("res://tests/fixtures/broken_mods/broken", "", "", 0, b)
	assert_eq(int(broken["code"]), 1, "a broken mod is refused")
	assert_any_contains(broken["lines"], "not uploaded: fix the problems above first")
	var good: Dictionary = await WorkshopUpload.run("res://examples/mods/stranger", "", "", 0, b)
	assert_eq(int(good["code"]), 0)
	assert_eq(int(good["item_id"]), 3)
	assert_any_contains(good["lines"], "published res://examples/mods/stranger as item 3 on the null backend")
	assert_eq(b.workshop_items().size(), 3)
	# The service passes through.
	var service := world.platform()
	var nb := service.backend as NullPlatformBackend
	if nb != null:
		nb.workshop_dir = WORKSHOP
		assert_eq(service.workshop_items().size(), 3)
	# The Steam backend without a client refuses politely.
	var s := SteamPlatformBackend.new()
	s.setup({"app_id": 0}, [])
	if not Engine.has_singleton("Steam"):
		assert_eq(s.workshop_items(), [])
		var no: Dictionary = await s.workshop_publish("res://examples/mods/stranger", "x", "")
		assert_false(bool(no["ok"]))
		assert_eq(String(no["why"]), "Steam is not running")


func test_thumbnails_and_rotated_autosaves_ride_the_cloud_with_their_saves() -> void:
	var service := world.platform()
	var b := service.backend as NullPlatformBackend
	if b == null:
		return
	b.cloud_dir = CLOUD
	service.sync_enabled = true
	assert_true(world.new_game(false))
	var img := Image.create_empty(32, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVES))
	assert_eq(img.save_png(SaveSystem.thumbnail_path(world.save_path("slot_1"))), OK, "a thumbnail stands in for the frame")
	assert_eq(world.save_slot(1), OK)
	assert_true(b.cloud_exists("slot_1.json"))
	assert_true(b.cloud_exists("slot_1.png"), "the picture went with the save")
	world.narrative.set_flag("beat", true)
	assert_eq(world.autosave(), OK)
	assert_true(b.cloud_exists("autosave.json"))
	assert_true(b.cloud_exists("autosave_1.json"), "the rotated copy went too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.thumbnail_path(world.save_path("slot_1"))))
	var restored := service.pull_missing(world.saves_dir)
	assert_true(restored.has("slot_1.png"), "and comes back when missing: %s" % [restored])
	service.sync_enabled = false
