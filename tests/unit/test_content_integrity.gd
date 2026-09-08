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


func _tiles_by_id() -> Dictionary:
	var out: Dictionary = {}
	for tile: Dictionary in registry.get_all("tiles"):
		out[tile["id"]] = tile
	return out


func test_maps_parse_clean_against_base_tiles_and_biomes() -> void:
	var tiles_by_id := _tiles_by_id()
	for entry: Dictionary in registry.get_all("maps"):
		var map := MapData.parse(entry, tiles_by_id)
		assert_eq(map.errors, [], "map %s" % entry["id"])
		assert_true(registry.has_entry("biomes", map.biome_id), "map %s biome '%s'" % [entry["id"], map.biome_id])
		assert_true(map.spawn_cells().size() >= 4, "map %s needs 4 spawn cells for a full party" % entry["id"])
		for cell: Vector2i in map.spawn_cells():
			assert_true(map.is_walkable(cell), "spawn %s on map %s must be walkable" % [cell, entry["id"]])


func test_map_enemy_placements_are_valid() -> void:
	var tiles_by_id := _tiles_by_id()
	for entry: Dictionary in registry.get_all("maps"):
		var map := MapData.parse(entry, tiles_by_id)
		var seen: Array[Vector2i] = []
		var placements: Array = entry.get("enemies", [])
		for p: Dictionary in placements:
			assert_true(registry.has_entry("enemies", String(p.get("type", ""))), "enemy type '%s'" % p.get("type"))
			var raw: Array = p.get("cell", [])
			assert_eq(raw.size(), 2, "cell is [x, y]")
			var cell := Vector2i(int(raw[0]), int(raw[1]))
			assert_true(map.is_walkable(cell), "%s placed on blocked %s" % [p.get("type"), cell])
			assert_false(seen.has(cell), "two enemies on %s" % cell)
			assert_false(map.spawn_cells().has(cell), "enemy on a party spawn %s" % cell)
			seen.append(cell)


func test_parties_reference_existing_races_and_classes() -> void:
	for party: Dictionary in registry.get_all("parties"):
		var members: Array = party.get("members", [])
		assert_true(members.size() >= 1 and members.size() <= 4, "party size 1-4")
		for m: Dictionary in members:
			assert_true(registry.has_entry("races", String(m.get("race", ""))), "race '%s'" % m.get("race"))
			assert_true(registry.has_entry("classes", String(m.get("class", ""))), "class '%s'" % m.get("class"))


func test_classes_reference_existing_branches_abilities_and_stats() -> void:
	for cls: Dictionary in registry.get_all("classes"):
		var branches: Array = cls.get("branches", [])
		assert_true(branches.size() >= 1, "class %s has a branch" % cls["id"])
		for b: String in branches:
			assert_true(registry.has_entry("branches", b), "branch '%s'" % b)
			var color: String = String(registry.get_entry("branches", b).get("color", ""))
			assert_true(Color.html_is_valid(color), "branch %s colour '%s'" % [b, color])
		var abilities: Array = cls.get("abilities", [])
		assert_true(abilities.size() >= 1, "class %s has abilities" % cls["id"])
		for a: String in abilities:
			assert_true(registry.has_entry("abilities", a), "class %s ability '%s'" % [cls["id"], a])
		var stats: Dictionary = cls.get("stats", {})
		for key: String in StatBlock.KEYS:
			assert_true(stats.has(key), "class %s stats.%s" % [cls["id"], key])


func test_enemies_reference_abilities_and_families() -> void:
	var enemies := registry.get_all("enemies")
	assert_true(enemies.size() >= 3, "M0 wants three enemy types")
	for e: Dictionary in enemies:
		assert_true(registry.has_entry("biomes", String(e.get("family", ""))), "enemy %s family" % e["id"])
		assert_true(["rusher", "ranged", "summoner", "stealther", "controller"].has(String(e.get("archetype", ""))), "enemy %s archetype" % e["id"])
		var abilities: Array = e.get("abilities", [])
		assert_true(abilities.size() >= 1, "enemy %s has abilities" % e["id"])
		for a: String in abilities:
			assert_true(registry.has_entry("abilities", a), "enemy %s ability '%s'" % [e["id"], a])
		var stats: Dictionary = e.get("stats", {})
		assert_true(int(stats.get("hp", 0)) >= 1, "enemy %s hp" % e["id"])
		var art: Dictionary = e.get("art", {})
		assert_true(Color.html_is_valid(String(art.get("color", ""))), "enemy %s art colour" % e["id"])


func test_abilities_are_well_formed() -> void:
	for a: Dictionary in registry.get_all("abilities"):
		assert_true(int(a.get("ap", 0)) >= 1, "ability %s ap" % a["id"])
		assert_true(int(a.get("range", 0)) >= 1, "ability %s range" % a["id"])
		var dmg: Array = a.get("damage", [])
		assert_eq(dmg.size(), 2, "ability %s damage is [min, max]" % a["id"])
		if dmg.size() == 2:
			assert_true(int(dmg[0]) <= int(dmg[1]), "ability %s damage ordered" % a["id"])
		var acc := int(a.get("accuracy", 0))
		assert_true(acc >= 1 and acc <= 100, "ability %s accuracy" % a["id"])


func test_combat_rules_entry_exists() -> void:
	assert_true(registry.has_entry("rules", "combat"))
	var r := CombatRules.from_entry(registry.get_entry("rules", "combat"))
	assert_eq(r.ap_per_turn, 4, "GDD §9: 4 AP")
	assert_true(r.friendly_fire, "GDD §9: friendly fire default on")


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
