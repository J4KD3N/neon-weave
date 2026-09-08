extends TestCase

const FIXTURES := "res://tests/fixtures"
const BASE := FIXTURES + "/content"
const MODS := FIXTURES + "/mods"

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()


func after_each() -> void:
	registry.free()


func test_loads_base_entries_by_kind() -> void:
	registry.load_from(BASE, [])
	assert_eq(registry.kinds(), PackedStringArray(["enemies", "items"]))
	assert_eq(registry.count("items"), 2)
	assert_eq(registry.count("enemies"), 1)
	assert_true(registry.has_entry("items", "rusty_blade"))
	assert_true(registry.has_entry("enemies", "scav"))


func test_id_defaults_to_file_stem_and_explicit_id_wins() -> void:
	registry.load_from(BASE, [])
	assert_eq(registry.get_entry("items", "rusty_blade")["name"], "Rusty Blade")
	# scrap_pistol.json declares "id": "scrap_pistol" explicitly.
	assert_eq(registry.get_entry("items", "scrap_pistol")["id"], "scrap_pistol")


func test_entries_carry_provenance() -> void:
	registry.load_from(BASE, [])
	var blade: Dictionary = registry.get_entry("items", "rusty_blade")
	assert_eq(blade["_kind"], "items")
	assert_eq(blade["_source"], ContentRegistry.SOURCE_BASE)
	assert_eq(blade["_path"], BASE + "/items/rusty_blade.json")


func test_missing_entry_is_empty_dictionary() -> void:
	registry.load_from(BASE, [])
	assert_eq(registry.get_entry("items", "nope"), {})
	assert_eq(registry.get_entry("no_such_kind", "nope"), {})
	assert_false(registry.has_entry("items", "nope"))


func test_get_all_is_sorted_by_id() -> void:
	registry.load_from(BASE, [])
	var ids: Array[String] = []
	for entry: Dictionary in registry.get_all("items"):
		ids.append(entry["id"])
	assert_eq(ids, ["rusty_blade", "scrap_pistol"])


func test_missing_base_root_is_reported() -> void:
	registry.load_from("res://tests/fixtures/does_not_exist", [])
	assert_eq(registry.kinds().size(), 0)
	assert_any_contains(registry.load_errors, "base content root missing")


func test_missing_mod_root_is_silent() -> void:
	registry.load_from(BASE, ["res://tests/fixtures/no_such_mods_dir"])
	assert_eq(registry.load_errors, [])
	assert_eq(registry.loaded_mods.size(), 0)


func test_mods_load_in_priority_order() -> void:
	registry.load_from(BASE, [MODS])
	var order: Array[String] = []
	for mod: Dictionary in registry.loaded_mods:
		order.append(mod["id"])
	# beta (5) before alpha (10); broken (0) first.
	assert_eq(order, ["broken_mod", "beta_mod", "alpha_mod"])


func test_highest_priority_mod_wins_override() -> void:
	registry.load_from(BASE, [MODS])
	var blade: Dictionary = registry.get_entry("items", "rusty_blade")
	assert_eq(int(blade["damage"]), 99)
	assert_eq(blade["name"], "Alpha Blade")
	assert_eq(blade["_source"], "alpha_mod")


func test_mod_only_entries_are_added() -> void:
	registry.load_from(BASE, [MODS])
	assert_true(registry.has_entry("items", "beta_only"))
	assert_eq(registry.get_entry("items", "beta_only")["_source"], "beta_mod")
	# Base entries the mods did not touch survive.
	assert_eq(registry.get_entry("items", "scrap_pistol")["_source"], ContentRegistry.SOURCE_BASE)
	assert_eq(registry.count("items"), 3)


func test_malformed_json_is_reported_not_fatal() -> void:
	registry.load_from(BASE, [MODS])
	assert_any_contains(registry.load_errors, "JSON error in " + MODS + "/broken_mod/content/items/bad.json")
	assert_false(registry.has_entry("items", "bad"))
	# A JSON array is not an entry either.
	assert_any_contains(registry.load_errors, "not a JSON object")
	assert_false(registry.has_entry("items", "list"))


func test_folder_without_manifest_is_skipped_with_error() -> void:
	registry.load_from(BASE, [MODS])
	assert_any_contains(registry.load_errors, "mod folder without mod.json")
	assert_false(registry.has_entry("items", "orphan"))


func test_manifest_defaults() -> void:
	registry.load_from(BASE, [MODS])
	var broken: Dictionary = {}
	for mod: Dictionary in registry.loaded_mods:
		if mod["id"] == "broken_mod":
			broken = mod
	assert_eq(broken["priority"], 0)
	assert_eq(broken["version"], "0.0.0")
	assert_eq(broken["name"], "broken_mod")


func test_reload_clears_previous_state() -> void:
	registry.load_from(BASE, [MODS])
	registry.load_from(BASE, [])
	assert_eq(registry.loaded_mods.size(), 0)
	assert_eq(registry.load_errors, [])
	assert_eq(registry.get_entry("items", "rusty_blade")["_source"], ContentRegistry.SOURCE_BASE)
	assert_false(registry.has_entry("items", "beta_only"))


func test_reloaded_signal_fires() -> void:
	var fired: Array[int] = []
	registry.reloaded.connect(func() -> void: fired.append(1))
	registry.load_from(BASE, [])
	assert_eq(fired.size(), 1)
