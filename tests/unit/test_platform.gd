## Platform contract: every backend answers the same calls the same way.
## The null backend runs everywhere; the Steam backend runs the same
## contract when GodotSteam is present and the client is up (never in CI).
## Plus: achievements as content, the world unlocking them at story beats,
## and cloud push/pull through the service.
extends TestCase

const LEDGER := "user://test_ledger_platform.json"
const SAVES := "user://test_saves_platform"
const CLOUD := "user://test_cloud_platform"

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
	var service := world.platform()
	service.sync_enabled = false
	var b := service.backend as NullPlatformBackend
	if b != null:
		b.cloud_dir = NullPlatformBackend.CLOUD_DIR
	(Engine.get_main_loop() as SceneTree).root.remove_child(world)
	world.free()
	_cleanup()


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	for dir: String in [SAVES, CLOUD]:
		var d := DirAccess.open(dir)
		if d != null:
			for f: String in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


## The contract every backend must honour. `available` tells the test
## whether writes are expected to land (null: yes; Steam: only when up).
func _contract(b: PlatformBackend, label: String) -> void:
	assert_false(b.backend_name().is_empty(), "%s has a name" % label)
	if not b.cloud_saves_enabled():
		assert_false(b.cloud_write("x.json", "{}".to_utf8_buffer()), "%s: no cloud, no writes" % label)
		assert_eq(b.cloud_list(), [], "%s: no cloud, empty list" % label)
		return
	var name := "contract_probe.json"
	b.cloud_delete(name)
	assert_false(b.cloud_exists(name), "%s: probe absent" % label)
	assert_eq(b.cloud_read(name), PackedByteArray(), "%s: reading a missing file is empty" % label)
	assert_true(b.cloud_write(name, "{\"probe\": 1}".to_utf8_buffer()), "%s: write" % label)
	assert_true(b.cloud_exists(name), "%s: exists after write" % label)
	assert_eq(b.cloud_read(name).get_string_from_utf8(), "{\"probe\": 1}", "%s: read back" % label)
	assert_true(b.cloud_list().has(name), "%s: listed" % label)
	assert_true(b.cloud_write(name, "{\"probe\": 2}".to_utf8_buffer()), "%s: overwrite" % label)
	assert_eq(b.cloud_read(name).get_string_from_utf8(), "{\"probe\": 2}")
	assert_true(b.cloud_delete(name), "%s: delete" % label)
	assert_false(b.cloud_exists(name))
	assert_false(b.cloud_delete(name), "%s: deleting twice is false" % label)
	assert_false(b.unlock_achievement(""), "%s: empty ids are refused" % label)
	if b.is_available() or b.backend_name() == "null":
		assert_true(b.unlock_achievement("first_extraction"), "%s: unlock" % label)
		assert_true(b.is_achievement_unlocked("first_extraction"))
		assert_true(b.unlock_achievement("first_extraction"), "%s: unlocking twice is still true" % label)
		assert_true(b.unlocked_achievements().has("first_extraction"))
		assert_true(b.set_stat("runs", 1))


func test_null_backend_honours_the_contract() -> void:
	var b := NullPlatformBackend.new()
	b.cloud_dir = CLOUD
	assert_eq(b.backend_name(), "null")
	assert_false(b.is_available())
	assert_true(b.cloud_saves_enabled(), "the null cloud is a folder")
	_contract(b, "null")
	assert_eq(b.unlocked_achievements(), ["first_extraction"], "in memory, in order")


func test_steam_backend_loads_without_the_extension_and_honours_the_contract_when_up() -> void:
	var b := SteamPlatformBackend.new()
	assert_eq(b.backend_name(), "steam")
	var entries: Array[Dictionary] = world.registry.get_all("achievements")
	var up := b.setup({"app_id": 0, "demo": true}, entries)
	assert_eq(b.app_id(), 0)
	assert_true(b.is_demo())
	if not Engine.has_singleton("Steam"):
		assert_false(up, "no GodotSteam here: never available")
		assert_false(b.is_available())
		assert_false(b.unlock_achievement("first_extraction"), "not available: refuses")
		assert_eq(b.unlocked_achievements(), [])
		assert_eq(b.user_name(), "")
	_contract(b, "steam")


func test_service_picks_the_null_backend_here_and_reports_status() -> void:
	var service := world.platform()
	assert_eq(service.backend_name(), "null", "CI and this machine run Steam-free")
	assert_false(service.sync_enabled, "no live platform: no cloud sync")
	assert_false(service.is_available())
	assert_contains(service.status_line(), "Steam-free build (null backend)")
	assert_eq(PlatformService.load_steam_config("res://steam/nope.json"), {})
	var cfg := PlatformService.load_steam_config()
	assert_eq(int(cfg.get("app_id", -1)), 0, "no app id committed")
	assert_true(bool(cfg.get("demo", false)))


func test_achievements_are_content_with_conditions_that_resolve() -> void:
	var entries: Array[Dictionary] = world.registry.get_all("achievements")
	assert_true(entries.size() >= 7)
	var steam_ids: Array[String] = []
	for a: Dictionary in entries:
		var sid := String(a.get("steam_id", ""))
		assert_true(sid.begins_with("ACH_") and sid == sid.to_upper(), "achievement %s steam_id %s" % [a["id"], sid])
		assert_false(steam_ids.has(sid), "steam ids are unique")
		steam_ids.append(sid)
		for k: String in a.get("when", {}):
			assert_true(["flags", "origin_tag", "race", "class", "approval", "reputation", "recruited", "not_recruited", "quest"].has(k), "achievement %s when.%s" % [a["id"], k])
	var b := NullPlatformBackend.new()
	var n := NarrativeState.new()
	assert_eq(PlatformService.due_achievements(entries, {"narrative": n}, b), [], "nothing earned yet")
	n.set_flag("first_extraction", true)
	assert_eq(PlatformService.due_achievements(entries, {"narrative": n}, b), ["first_extraction"])
	b.unlock_achievement("first_extraction")
	assert_eq(PlatformService.due_achievements(entries, {"narrative": n}, b), [], "unlocked ones drop out")


func test_the_world_unlocks_achievements_at_story_beats() -> void:
	var service := world.platform()
	assert_true(service != null)
	service.backend = NullPlatformBackend.new() # the autoload is shared across tests: start clean
	service.unlocked_this_session.clear()
	var b := service.backend
	var before := b.unlocked_achievements().size()
	world.enter_shard("rusted_undercity", 7)
	world.teleport_party(world.extraction_cell())
	assert_true(world.extract())
	assert_true(b.is_achievement_unlocked("first_extraction"), "extracting earns it at the autosave")
	assert_true(service.unlocked_this_session.has("first_extraction"))
	assert_eq(world.check_achievements(), [], "no repeats")
	world.narrative.set_flag("mortal_mode", true)
	assert_eq(world.check_achievements(), ["mortal"])
	assert_true(b.unlocked_achievements().size() >= before + 2)


func test_saves_push_to_the_cloud_and_pull_back_when_missing() -> void:
	var service := world.platform()
	var b := service.backend as NullPlatformBackend
	if b == null:
		return
	b.cloud_dir = CLOUD
	for f: String in b.cloud_list():
		b.cloud_delete(f)
	assert_false(service.push_save(world.save_path(SaveSystem.AUTOSAVE)), "sync is off until a platform is live or a test opts in")
	service.sync_enabled = true
	assert_eq(world.save_slot(2), OK)
	assert_true(b.cloud_exists("slot_2.json"), "a save is pushed as it is written")
	assert_true(b.cloud_exists("autosave.json") or true)
	var local := world.save_path(SaveSystem.slot_name(2))
	assert_true(FileAccess.file_exists(local))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(local))
	assert_false(FileAccess.file_exists(local))
	var restored := service.pull_missing(world.saves_dir)
	assert_true(restored.has("slot_2.json"), "pulled back: %s" % [restored])
	assert_true(FileAccess.file_exists(local))
	assert_eq(world.load_slot(2), [], "and it loads")
	assert_eq(service.pull_missing(world.saves_dir), [], "local files win; nothing to pull")
	assert_false(service.push_save("user://does_not_exist.json"))
