extends TestCase

const DIR := "user://test_saves_unit"


func before_each() -> void:
	_wipe_dir()


func after_each() -> void:
	_wipe_dir()


static func _wipe_dir() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f: String in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_paths() -> void:
	assert_eq(SaveSystem.slot_name(2), "slot_2")
	assert_eq(SaveSystem.path_for("user://saves", "slot_1"), "user://saves/slot_1.json")


func test_write_and_read_round_trip() -> void:
	var path := SaveSystem.path_for(DIR, "slot_1")
	var data := {"version": 1, "location": {"kind": "shard", "seed": 7}, "party": [{"id": "weaver", "hp": 3}]}
	assert_eq(SaveSystem.write(path, data), OK)
	var back := SaveSystem.read(path)
	assert_false(back.has("_error"))
	assert_eq(int(back["version"]), 1)
	assert_eq(int(Dictionary(back["location"])["seed"]), 7)
	var party: Array = back["party"]
	assert_eq(String(Dictionary(party[0])["id"]), "weaver")


func test_read_errors() -> void:
	assert_contains(String(SaveSystem.read(SaveSystem.path_for(DIR, "nope"))["_error"]), "no save at")
	DirAccess.make_dir_recursive_absolute(DIR)
	var bad := SaveSystem.path_for(DIR, "bad")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("[1, 2")
	f.close()
	assert_contains(String(SaveSystem.read(bad)["_error"]), "JSON error")
	var arr := SaveSystem.path_for(DIR, "arr")
	f = FileAccess.open(arr, FileAccess.WRITE)
	f.store_string("[1, 2]")
	f.close()
	assert_contains(String(SaveSystem.read(arr)["_error"]), "not a JSON object")


func test_migrate_stamps_version_and_upgrades_nested_ledger() -> void:
	var old := {"ledger": {"version": 1, "resources": {"salvage": 2}}, "location": {"kind": "map", "id": "proto_yard"}}
	var m := SaveSystem.migrate(old)
	assert_eq(int(m["version"]), SaveSystem.VERSION)
	assert_true(m.has("content"), "v2 has a content block, empty for a legacy save")
	var ledger: Dictionary = m["ledger"]
	assert_eq(int(ledger["version"]), Ledger.VERSION)
	assert_eq(ledger["buildings"], {})
	assert_false(old.has("version"), "input untouched")


func test_summarize_and_list() -> void:
	assert_eq(SaveSystem.summarize({"_error": "boom"}), "boom")
	var s := SaveSystem.summarize({"map_name": "Proto Yard", "saved_at": "2026-09-08T10:00:00", "ledger": {"version": 2, "resources": {"salvage": 4}, "runs_completed": 1}})
	assert_contains(s, "Proto Yard — 2026-09-08T10:00:00 — banked S4")
	var listing := SaveSystem.list_saves(DIR)
	assert_eq(listing.size(), SaveSystem.SLOTS + 1)
	for row: Dictionary in listing:
		assert_false(bool(row["exists"]))
		assert_eq(row["summary"], "empty")
	assert_eq(listing[3]["name"], "autosave")
	SaveSystem.write(SaveSystem.path_for(DIR, "slot_2"), {"version": 1, "map_name": "X", "saved_at": "t", "ledger": {}})
	listing = SaveSystem.list_saves(DIR)
	assert_true(bool(listing[1]["exists"]))
	assert_contains(String(listing[1]["summary"]), "X — t —")


# --- S27: content fingerprints (D-080) ----------------------------------------

const UNIT_LEDGER := "user://test_ledger_save_unit.json"


func _fresh_world() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.map_id = "proto_yard"
	w.home_map = "proto_yard"
	w.party_id = "prototype"
	w.ledger_path = UNIT_LEDGER
	w.saves_dir = DIR
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	w.combat.animate = false
	return w


func _drop_world(w: ExploreWorld) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(w)
	w.free()
	if FileAccess.file_exists(UNIT_LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UNIT_LEDGER))


func test_entry_hashes_ignore_provenance_and_key_order_but_not_values() -> void:
	var a := {"name": "x", "rows": ["..", ".."], "_path": "res://a.json", "_source": "base"}
	var b := {"rows": ["..", ".."], "name": "x", "_path": "user://mods/a.json", "_source": "mod"}
	assert_eq(ContentRegistry.hash_entry(a), ContentRegistry.hash_entry(b), "same content, same hash")
	var c := {"name": "x", "rows": ["..", ".#"]}
	assert_true(ContentRegistry.hash_entry(a) != ContentRegistry.hash_entry(c), "a changed tile changes the hash")
	assert_eq(ContentRegistry.hash_entry(a).length(), 16)


func test_saves_carry_content_fingerprints_and_a_changed_map_is_refused() -> void:
	var w := _fresh_world()
	var data := SaveSystem.capture(w)
	assert_eq(int(data["version"]), SaveSystem.VERSION)
	var content: Dictionary = data["content"]
	assert_eq(String(content["fingerprint"]), w.registry.fingerprint())
	assert_eq(String(content["game_version"]), String(ProjectSettings.get_setting("application/config/version")))
	var location: Dictionary = data["location"]
	assert_eq(String(location["fingerprint"]), w.registry.entry_fingerprint("maps", "proto_yard"))
	assert_eq(SaveSystem.content_check(data, w.registry), "", "a fresh save matches")
	assert_false(SaveSystem.content_changed(data, w.registry))
	# The map changes underneath the save: refused before the world is touched.
	var tampered := data.duplicate(true)
	Dictionary(tampered["location"])["fingerprint"] = "0000000000000000"
	var hp_before := w.party.members[0].hp
	w.party.members[0].hp = hp_before - 3
	var errors := SaveSystem.restore(w, tampered)
	assert_eq(errors.size(), 1)
	assert_contains(errors[0], "has changed since this save was written")
	assert_eq(w.party.members[0].hp, hp_before - 3, "the refused load left the world alone")
	assert_contains(SaveSystem.summarize(tampered, w.registry), "needs a new game")
	# A v1 save has no fingerprint at all: refused too, with the reason.
	var legacy := data.duplicate(true)
	legacy["version"] = 1
	Dictionary(legacy["location"]).erase("fingerprint")
	legacy.erase("content")
	var migrated := SaveSystem.migrate(legacy)
	assert_eq(int(migrated["version"]), 2)
	assert_contains(SaveSystem.content_check(migrated, w.registry), "predates content checks")
	assert_contains(SaveSystem.restore(w, legacy)[0], "predates content checks")
	# Other content changing (a balance number) still loads, and the list says so.
	var patched := data.duplicate(true)
	Dictionary(patched["content"])["fingerprint"] = "ffffffffffffffff"
	assert_eq(SaveSystem.content_check(patched, w.registry), "")
	assert_true(SaveSystem.content_changed(patched, w.registry))
	assert_contains(SaveSystem.summarize(patched, w.registry), "content changed")
	assert_false(SaveSystem.summarize(patched, w.registry).contains("new game"))
	assert_eq(SaveSystem.restore(w, patched), [], "still loads")
	# The world path: a refused slot shows in the list and the load says why.
	assert_eq(SaveSystem.write(w.save_path("slot_3"), tampered), OK)
	var listing := SaveSystem.list_saves(DIR, w.registry)
	assert_true(bool(listing[2]["exists"]))
	assert_false(bool(listing[2]["loadable"]))
	assert_contains(String(listing[2]["summary"]), "needs a new game")
	var why := w.load_slot(3)
	assert_eq(why.size(), 1)
	assert_contains(why[0], "has changed")
	_drop_world(w)


func test_shard_saves_are_stamped_with_the_template_and_layout_version() -> void:
	var w := _fresh_world()
	w.enter_shard("rusted_undercity", 7)
	var data := SaveSystem.capture(w)
	var location: Dictionary = data["location"]
	assert_eq(String(location["kind"]), "shard")
	assert_true(String(location["fingerprint"]).ends_with("@%d" % ShardGenerator.LAYOUT_VERSION))
	assert_eq(SaveSystem.content_check(data, w.registry), "")
	var other := data.duplicate(true)
	Dictionary(other["location"])["template"] = "nope"
	assert_contains(SaveSystem.content_check(other, w.registry), "no longer exists")
	_drop_world(w)
