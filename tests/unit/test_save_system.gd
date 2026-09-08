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
	assert_eq(int(m["version"]), 1)
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
