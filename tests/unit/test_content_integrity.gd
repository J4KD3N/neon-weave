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
		var self_only := String(a.get("targets", "other")) == "self"
		assert_true(int(a.get("ap", 0)) >= (0 if self_only else 1), "ability %s ap" % a["id"])
		assert_true(int(a.get("range", 0)) >= (0 if self_only else 1), "ability %s range" % a["id"])
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


func test_shard_templates_reference_existing_tiles_enemies_and_biomes() -> void:
	var templates := registry.get_all("shards")
	assert_true(templates.size() >= 1, "M0 wants one procgen biome")
	for t: Dictionary in templates:
		assert_true(registry.has_entry("biomes", String(t.get("biome", ""))), "shard %s biome" % t["id"])
		var tiles: Dictionary = t.get("tiles", {})
		for role: String in ["wall", "floor", "grate", "debris", "extraction"]:
			assert_true(registry.has_entry("tiles", String(tiles.get(role, ""))), "shard %s tile role %s" % [t["id"], role])
		assert_true(bool(registry.get_entry("tiles", String(tiles.get("extraction", ""))).get("walkable", false)), "extraction tile walkable")
		var enemies: Dictionary = t.get("enemies", {})
		var pool: Array = enemies.get("pool", [])
		assert_true(pool.size() >= 1, "shard %s enemy pool" % t["id"])
		for p: Dictionary in pool:
			assert_true(registry.has_entry("enemies", String(p.get("type", ""))), "shard %s pool type %s" % [t["id"], p.get("type")])
			assert_true(float(p.get("weight", 0)) > 0.0, "shard %s pool weight" % t["id"])


func test_pickups_have_valid_grants_and_placements() -> void:
	var pickups := registry.get_all("pickups")
	assert_true(pickups.size() >= 2)
	var allowed: Array[String] = ["salvage", "aether", "ciphers", "cipher_chance", "xp"]
	for p: Dictionary in pickups:
		var grants: Dictionary = p.get("grants", {})
		if p.has("dialogue"):
			assert_true(registry.has_entry("dialogue", String(p["dialogue"])), "pickup %s dialogue" % p["id"])
		else:
			assert_true(grants.size() >= 1, "pickup %s grants" % p["id"])
		for key: String in grants:
			assert_true(allowed.has(key), "pickup %s unknown grant '%s'" % [p["id"], key])
		var art: Dictionary = p.get("art", {})
		assert_true(Color.html_is_valid(String(art.get("color", ""))), "pickup %s colour" % p["id"])
	for e: Dictionary in registry.get_all("enemies"):
		var loot: Dictionary = e.get("loot", {})
		for key: String in loot:
			assert_true(allowed.has(key), "enemy %s unknown loot '%s'" % [e["id"], key])
	for t: Dictionary in registry.get_all("shards"):
		var spec: Dictionary = t.get("pickups", {})
		for entry: Dictionary in spec.get("pool", []):
			assert_true(registry.has_entry("pickups", String(entry.get("type", ""))), "shard %s pickup pool type" % t["id"])
	var tiles := _tiles_by_id()
	for m: Dictionary in registry.get_all("maps"):
		assert_eq(ShardValidator.validate(m, tiles), [], "map %s placements" % m["id"])


func test_buildings_have_free_base_levels_and_valid_costs_and_effects() -> void:
	var buildings := registry.get_all("buildings")
	assert_eq(buildings.size(), 3, "M1: Beacon, Med-bay, Workshop")
	var effect_keys: Array[String] = ["depth", "heal_fraction", "hp_bonus", "damage_bonus"]
	for b: Dictionary in buildings:
		var levels: Array = b.get("levels", [])
		assert_true(levels.size() >= 2, "building %s has upgrades" % b["id"])
		var base: Dictionary = levels[0]
		assert_eq(Dictionary(base.get("cost", {})).size(), 0, "building %s level 0 is free" % b["id"])
		for lv: Dictionary in levels:
			for key: String in lv.get("cost", {}):
				assert_true(Ledger.RESOURCES.has(key), "building %s cost key '%s'" % [b["id"], key])
			for key: String in lv.get("effects", {}):
				assert_true(effect_keys.has(key), "building %s effect key '%s'" % [b["id"], key])
			assert_false(String(lv.get("blurb", "")).is_empty(), "building %s level blurb" % b["id"])


func test_class_resources_exist_and_are_well_formed() -> void:
	for cls: Dictionary in registry.get_all("classes"):
		var res: Dictionary = cls.get("resource", {})
		var id := String(res.get("id", ""))
		assert_true(registry.has_entry("resources", id), "class %s resource '%s'" % [cls["id"], id])
		var def := registry.get_entry("resources", id)
		var builds_on := String(def.get("builds_on", ""))
		assert_true(builds_on.is_empty() or ["physical", "arcane", "tech"].has(builds_on), "resource %s builds_on" % id)
		if String(def.get("kind", "")) == "marks":
			assert_false(String(def.get("mark", "")).is_empty(), "resource %s mark id" % id)
		for key: String in def.get("gain_on_surface", {}):
			assert_true(["mana_pool", "conduit", "corrosive"].has(key), "resource %s surface %s" % [id, key])
		assert_true(int(def.get("max", 0)) >= 1, "resource %s max" % id)
		if def.has("vent_ability"):
			assert_true(registry.has_entry("abilities", String(def["vent_ability"])), "resource %s vent ability" % id)
			var abilities: Array = cls.get("abilities", [])
			assert_true(abilities.has(String(def["vent_ability"])), "class %s must carry its vent ability" % cls["id"])


func test_surface_tiles_are_walkable_floors_with_known_surfaces() -> void:
	var known: Array[String] = ["mana_pool", "conduit", "corrosive"]
	var found := 0
	for t: Dictionary in registry.get_all("tiles"):
		if t.has("surface"):
			found += 1
			assert_true(known.has(String(t["surface"])), "tile %s surface" % t["id"])
			assert_true(bool(t.get("walkable", false)), "surface tile %s walkable" % t["id"])
		if t.has("cover"):
			assert_false(bool(t.get("walkable", false)), "cover tile %s should block movement" % t["id"])
		if t.has("height"):
			assert_true(bool(t.get("walkable", false)), "raised tile %s walkable" % t["id"])
	assert_eq(found, 3, "mana pool, conduit, biogrowth")
	for s: Dictionary in registry.get_all("shards"):
		var spec: Dictionary = s.get("surfaces", {})
		var chars: Array[String] = []
		for e: Dictionary in spec.get("pool", []):
			assert_true(registry.has_entry("tiles", String(e.get("tile", ""))), "shard %s surface tile" % s["id"])
			var ch := String(e.get("char", ""))
			assert_eq(ch.length(), 1, "surface char")
			assert_false(["#", ".", ",", "x", "P", "E"].has(ch), "surface char clashes with a generator char")
			assert_false(chars.has(ch), "duplicate surface char")
			chars.append(ch)


func test_prototype_party_covers_distinct_classes_and_abilities_resolve() -> void:
	var classes := registry.get_all("classes")
	assert_true(classes.size() >= 4, "M1: four classes")
	var party := registry.get_entry("parties", "prototype")
	var seen: Array[String] = []
	for m: Dictionary in party["members"]:
		var cls := String(m["class"])
		assert_false(seen.has(cls), "prototype party repeats %s" % cls)
		seen.append(cls)
	assert_eq(seen.size(), 3, "three preset classes; Sera brings the knight count to two")
	for a: Dictionary in registry.get_all("abilities"):
		var effect := String(a.get("effect", ""))
		assert_true(["", "vent", "mark", "detonate"].has(effect), "ability %s effect '%s'" % [a["id"], effect])
		if effect == "mark" or effect == "detonate":
			assert_false(String(a.get("mark", "")).is_empty(), "ability %s needs a mark id" % a["id"])
		assert_true(int(a.get("resource_cost", 0)) >= 0)


func test_five_races_with_overlays_origins_and_attribute_rules() -> void:
	var races := registry.get_all("races")
	assert_true(races.size() >= 5, "M2 demo races")
	for r: Dictionary in races:
		var overlay: Dictionary = r.get("overlay", {})
		assert_true(PlaceholderActorArt.OVERLAY_KINDS.has(String(overlay.get("kind", ""))), "race %s overlay kind" % r["id"])
		if String(overlay.get("kind", "")) != "none":
			assert_true(Color.html_is_valid(String(overlay.get("color", ""))), "race %s overlay colour" % r["id"])
		for key: String in r.get("stat_mods", {}):
			assert_true(StatBlock.KEYS.has(key), "race %s stat_mod '%s'" % [r["id"], key])
	var origins := registry.get_all("origins")
	assert_true(origins.size() >= 4)
	for o: Dictionary in origins:
		assert_false(String(o.get("dialogue_tag", "")).is_empty(), "origin %s dialogue_tag" % o["id"])
		for key: String in o.get("stat_mods", {}):
			assert_true(StatBlock.KEYS.has(key), "origin %s stat_mod '%s'" % [o["id"], key])
	var attrs := registry.get_entry("rules", "attributes")
	var names: Array = attrs.get("names", [])
	assert_eq(names.size(), 3)
	assert_true(int(attrs.get("points", 0)) > 0)
	assert_true(int(attrs.get("max_per_attribute", 0)) * names.size() >= int(attrs.get("points", 0)), "budget must be spendable")
	var effects: Dictionary = attrs.get("effects", {})
	for n: String in names:
		assert_true(effects.has(n), "attribute %s has effects" % n)
		for key: String in effects[n]:
			assert_true(StatBlock.KEYS.has(key), "attribute %s effect '%s'" % [n, key])


func test_sprite_sheets_exist_and_are_referenced_correctly() -> void:
	var sheets := registry.get_all("sprites")
	assert_true(sheets.size() >= 2, "one race and one enemy sheet")
	for entry: Dictionary in sheets:
		var dir := String(entry["_path"]).get_base_dir()
		assert_true(FileAccess.file_exists(dir.path_join(String(entry.get("image", "")))), "sheet %s image" % entry["id"])
		var sheet := SpriteSheet.load_entry(entry)
		assert_eq(sheet.errors, [], "sheet %s" % entry["id"])
		for anim: String in ["idle", "walk", "attack", "hit", "death"]:
			assert_true(sheet.has_animation(anim), "sheet %s needs %s" % [entry["id"], anim])
	for r: Dictionary in registry.get_all("races"):
		var art: Dictionary = r.get("art", {})
		if art.has("sheet"):
			assert_true(registry.has_entry("sprites", String(art["sheet"])), "race %s sheet" % r["id"])
	for e: Dictionary in registry.get_all("enemies"):
		var art: Dictionary = e.get("art", {})
		if art.has("sheet"):
			assert_true(registry.has_entry("sprites", String(art["sheet"])), "enemy %s sheet" % e["id"])
	for b: Dictionary in registry.get_all("biomes"):
		var palette: Dictionary = b.get("palette", {})
		var recolors: Dictionary = b.get("recolors", {})
		for sheet_id: String in recolors:
			assert_true(registry.has_entry("sprites", sheet_id), "biome %s recolors unknown sheet %s" % [b["id"], sheet_id])
			assert_true(palette.has(String(recolors[sheet_id])), "biome %s recolor role" % b["id"])
