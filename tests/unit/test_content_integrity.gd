## Cross-reference checks over the real base content. Every id a content
## file points at must exist; this is the schema validation until per-kind
## schemas land (docs/gaps.md).
extends TestCase

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])


func after_each() -> void:
	registry.free()


func test_maps_parse_clean_against_base_tiles_and_biomes() -> void:
	var tiles_by_id: Dictionary = {}
	for tile: Dictionary in registry.get_all("tiles"):
		tiles_by_id[tile["id"]] = tile
	for entry: Dictionary in registry.get_all("maps"):
		var map := MapData.parse(entry, tiles_by_id)
		assert_eq(map.errors, [], "map %s" % entry["id"])
		assert_true(registry.has_entry("biomes", map.biome_id), "map %s biome '%s'" % [entry["id"], map.biome_id])
		assert_true(map.spawn_cells().size() >= 4, "map %s needs 4 spawn cells for a full party" % entry["id"])
		for cell: Vector2i in map.spawn_cells():
			assert_true(map.is_walkable(cell), "spawn %s on map %s must be walkable" % [cell, entry["id"]])


func test_parties_reference_existing_races_and_classes() -> void:
	for party: Dictionary in registry.get_all("parties"):
		var members: Array = party.get("members", [])
		assert_true(members.size() >= 1 and members.size() <= 4, "party size 1-4")
		for m: Dictionary in members:
			assert_true(registry.has_entry("races", String(m.get("race", ""))), "race '%s'" % m.get("race"))
			assert_true(registry.has_entry("classes", String(m.get("class", ""))), "class '%s'" % m.get("class"))


func test_classes_reference_existing_branches_with_colours() -> void:
	for cls: Dictionary in registry.get_all("classes"):
		var branches: Array = cls.get("branches", [])
		assert_true(branches.size() >= 1, "class %s has a branch" % cls["id"])
		for b: String in branches:
			assert_true(registry.has_entry("branches", b), "branch '%s'" % b)
			var color: String = String(registry.get_entry("branches", b).get("color", ""))
			assert_true(Color.html_is_valid(color), "branch %s colour '%s'" % [b, color])


func test_biome_palettes_are_sixteen_valid_colours() -> void:
	for biome: Dictionary in registry.get_all("biomes"):
		var palette: Dictionary = biome.get("palette", {})
		assert_eq(palette.size(), 16, "biome %s palette" % biome["id"])
		for role: String in palette:
			assert_true(Color.html_is_valid(String(palette[role])), "%s.%s" % [biome["id"], role])


func test_tile_art_roles_exist_in_every_biome_palette() -> void:
	for tile: Dictionary in registry.get_all("tiles"):
		var art: Dictionary = tile.get("art", {})
		for key: String in ["fill", "edge", "top", "left", "right", "pattern_color"]:
			if not art.has(key):
				continue
			var role: String = String(art[key])
			for biome: Dictionary in registry.get_all("biomes"):
				var palette: Dictionary = biome.get("palette", {})
				assert_true(palette.has(role), "tile %s role '%s' missing from biome %s" % [tile["id"], role, biome["id"]])
