## Seed sweep over the Shard generator: every seed must produce a map the
## validator accepts, within the template's budgets.
extends TestCase

const SEEDS := 80

var registry: ContentRegistry
var template: Dictionary
var tiles: Dictionary


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	template = registry.get_entry("shards", "rusted_undercity")
	tiles = {}
	for t: Dictionary in registry.get_all("tiles"):
		tiles[t["id"]] = t


func after_each() -> void:
	registry.free()


func test_template_exists() -> void:
	assert_false(template.is_empty())


func test_same_seed_same_shard() -> void:
	var a := ShardGenerator.generate(template, 99)
	var b := ShardGenerator.generate(template, 99)
	assert_eq(a["rows"], b["rows"])
	assert_eq(a["enemies"], b["enemies"])
	assert_eq(a["extraction"], b["extraction"])
	assert_eq(a["id"], "rusted_undercity_99")
	assert_contains(String(a["name"]), "#99")


func test_different_seeds_differ() -> void:
	var a := ShardGenerator.generate(template, 1)
	var b := ShardGenerator.generate(template, 2)
	assert_ne(a["rows"], b["rows"])


func test_entry_shape_matches_handcrafted_maps() -> void:
	var e := ShardGenerator.generate(template, 5)
	for key: String in ["id", "name", "biome", "spawn_marker", "legend", "rows", "enemies", "pickups", "extraction", "rooms", "generation"]:
		assert_true(e.has(key), "missing %s" % key)
	assert_eq(e["biome"], "rusted_undercity")
	var legend: Dictionary = e["legend"]
	for ch: String in legend:
		assert_true(tiles.has(legend[ch]), "legend '%s' -> unknown tile '%s'" % [ch, legend[ch]])
	var map := MapData.parse(e, tiles)
	assert_eq(map.errors, [])
	var raw: Array = e["extraction"]
	assert_eq(map.tile_id_at(Vector2i(int(raw[0]), int(raw[1]))), "extraction_pad")


func test_seed_sweep_is_always_solvable_and_within_budget() -> void:
	var size: Dictionary = template["size"]
	var room_spec: Dictionary = template["rooms"]
	var enemy_spec: Dictionary = template["enemies"]
	var max_enemies := int(Array(enemy_spec["groups"])[1]) * int(Array(enemy_spec["group_size"])[1])
	var total_enemies := 0
	for seed_value: int in range(1, SEEDS + 1):
		var e := ShardGenerator.generate(template, seed_value)
		var errors := ShardValidator.validate(e, tiles)
		assert_eq(errors, [], "seed %d" % seed_value)
		var rows: Array = e["rows"]
		var w := String(rows[0]).length()
		var h := rows.size()
		assert_true(w >= int(Array(size["width"])[0]) and w <= int(Array(size["width"])[1]), "seed %d width %d" % [seed_value, w])
		assert_true(h >= int(Array(size["height"])[0]) and h <= int(Array(size["height"])[1]), "seed %d height %d" % [seed_value, h])
		var rooms: Array = e["rooms"]
		assert_true(rooms.size() >= 2 and rooms.size() <= int(Array(room_spec["count"])[1]), "seed %d rooms %d" % [seed_value, rooms.size()])
		var enemies: Array = e["enemies"]
		assert_true(enemies.size() >= 1, "seed %d has no enemies" % seed_value)
		assert_true(enemies.size() <= max_enemies, "seed %d enemies %d" % [seed_value, enemies.size()])
		var pickups: Array = e["pickups"]
		assert_true(pickups.size() >= 1 and pickups.size() <= 10, "seed %d pickups %d" % [seed_value, pickups.size()])
		for p: Dictionary in pickups:
			assert_true(registry.has_entry("pickups", String(p["type"])), "seed %d pickup type %s" % [seed_value, p["type"]])
		total_enemies += enemies.size()
		for p: Dictionary in enemies:
			assert_true(registry.has_entry("enemies", String(p["type"])), "seed %d enemy type %s" % [seed_value, p["type"]])
		var map := MapData.parse(e, tiles)
		assert_true(map.walkable_count() > w * h / 8, "seed %d is too empty (%d walkable)" % [seed_value, map.walkable_count()])
	assert_true(total_enemies > SEEDS * 3, "average well above three enemies per shard")


func test_debris_never_blocks_corridors() -> void:
	# A shard with heavy debris must still validate: the simple-point test
	# keeps every corridor open.
	var heavy := template.duplicate(true)
	heavy["debris_density"] = 0.5
	for seed_value: int in range(1, 21):
		var e := ShardGenerator.generate(heavy, seed_value)
		assert_eq(ShardValidator.validate(e, tiles), [], "seed %d" % seed_value)


func test_validator_catches_broken_maps() -> void:
	var e := ShardGenerator.generate(template, 3)
	var rows: Array = e["rows"]
	# Open the border.
	var top := String(rows[0])
	rows[0] = "." + top.substr(1)
	assert_any_contains(ShardValidator.validate(e, tiles), "border open")
	# Enemy on the spawn.
	var f := ShardGenerator.generate(template, 3)
	var map := MapData.parse(f, tiles)
	var s := map.spawn_cells()[0]
	var enemies: Array = f["enemies"]
	enemies.append({"type": "scav", "cell": [s.x, s.y]})
	var errors := ShardValidator.validate(f, tiles)
	assert_any_contains(errors, "enemy on spawn")
	assert_any_contains(errors, "too close to spawn")
	# Unreachable extraction.
	var g := ShardGenerator.generate(template, 3)
	g["extraction"] = [0, 0]
	assert_any_contains(ShardValidator.validate(g, tiles), "extraction (0, 0) is not walkable")


func test_handcrafted_proto_yard_passes_the_solvability_checks() -> void:
	var entry: Dictionary = registry.get_entry("maps", "proto_yard")
	assert_eq(ShardValidator.validate(entry, tiles), [])


func test_depth_adds_groups_and_pickups_and_stays_valid() -> void:
	for seed_value: int in range(1, 16):
		var d1 := ShardGenerator.generate(template, seed_value, 1)
		var d3 := ShardGenerator.generate(template, seed_value, 3)
		assert_eq(ShardValidator.validate(d3, tiles), [], "depth 3 seed %d" % seed_value)
		assert_eq(d1["rows"], d3["rows"], "depth changes population, not layout")
		var g: Dictionary = d3["generation"]
		assert_eq(int(g["depth"]), 3)
		assert_contains(String(d3["name"]), "depth 3")
		assert_false(String(d1["name"]).contains("depth"))
		var p1: Array = d1["pickups"]
		var p3: Array = d3["pickups"]
		assert_true(p1.size() >= 1 and p1.size() <= 10, "seed %d depth-1 pickups %d" % [seed_value, p1.size()])
		assert_true(p3.size() >= 3 and p3.size() <= 12, "seed %d depth-3 pickups %d" % [seed_value, p3.size()])


func test_surface_patches_appear_and_stay_solvable() -> void:
	var seen: Dictionary = {}
	for seed_value: int in range(1, 31):
		var e := ShardGenerator.generate(template, seed_value)
		assert_eq(ShardValidator.validate(e, tiles), [], "seed %d" % seed_value)
		var legend: Dictionary = e["legend"]
		assert_eq(legend.get("m"), "mana_pool")
		assert_eq(legend.get("k"), "catwalk")
		for row: String in e["rows"]:
			for ch: String in ["m", "c", "b", "k"]:
				if row.contains(ch):
					seen[ch] = true
	assert_eq(seen.size(), 4, "every surface kind shows up across 30 seeds: %s" % [seen.keys()])



func test_depth_posts_the_boss_and_rolls_elites_but_depth_one_has_neither() -> void:
	var elites_seen := 0
	for seed_value: int in range(1, 11):
		var d1 := ShardGenerator.generate(template, seed_value, 1)
		for p: Dictionary in d1["enemies"]:
			assert_false(p.has("tier"), "seed %d depth 1 has no tiers" % seed_value)
		var d3 := ShardGenerator.generate(template, seed_value, 3)
		assert_eq(ShardValidator.validate(d3, tiles), [], "depth 3 seed %d" % seed_value)
		var bosses := 0
		var exit_raw: Array = d3["extraction"]
		var exit_cell := Vector2i(int(exit_raw[0]), int(exit_raw[1]))
		for p: Dictionary in d3["enemies"]:
			var tier := String(p.get("tier", ""))
			if tier == "boss":
				bosses += 1
				assert_eq(p["type"], "undercity_warlord")
				var raw: Array = p["cell"]
				assert_true(LineOfSight.distance(Vector2i(int(raw[0]), int(raw[1])), exit_cell) <= 3, "seed %d boss by the pad" % seed_value)
			elif tier == "elite":
				elites_seen += 1
			else:
				assert_eq(tier, "", "seed %d unknown tier %s" % [seed_value, tier])
		assert_eq(bosses, 1, "seed %d posts exactly one boss at depth 3" % seed_value)
		var d2 := ShardGenerator.generate(template, seed_value, 2)
		for p: Dictionary in d2["enemies"]:
			assert_true(String(p.get("tier", "")) != "boss", "seed %d: no boss before depth 3" % seed_value)
	assert_true(elites_seen >= 3, "elites turn up at depth 3 (%d over ten seeds)" % elites_seen)



func test_verdant_datacore_generates_valid_shards_for_a_hundred_seeds() -> void:
	var verdant := registry.get_entry("shards", "verdant_datacore")
	assert_false(verdant.is_empty())
	assert_eq(verdant["biome"], "verdant_datacore")
	var surfaces_seen: Dictionary = {}
	for seed_value: int in range(1, 101):
		var e := ShardGenerator.generate(verdant, seed_value, 1)
		assert_eq(ShardValidator.validate(e, tiles), [], "verdant seed %d" % seed_value)
		var map := MapData.parse(e, tiles)
		assert_eq(map.biome_id, "verdant_datacore")
		for y: int in map.height:
			for x: int in map.width:
				var s := map.surface_at(Vector2i(x, y))
				if not s.is_empty():
					surfaces_seen[s] = true
	for s: String in ["spore", "mana_pool", "conduit", "corrosive"]:
		assert_true(surfaces_seen.has(s), "the Datacore grows %s somewhere in a hundred seeds" % s)
	var deep := ShardGenerator.generate(verdant, 5, 3)
	assert_eq(ShardValidator.validate(deep, tiles), [], "depth 3")
	var bosses := 0
	for p: Dictionary in deep["enemies"]:
		if String(p.get("tier", "")) == "boss":
			bosses += 1
			assert_eq(p["type"], "canopy_matron")
	assert_eq(bosses, 1)


func test_oval_rooms_and_wide_corridors_change_the_carving() -> void:
	var box := template.duplicate(true)
	var oval := template.duplicate(true)
	oval["rooms"] = Dictionary(oval["rooms"]).duplicate()
	oval["rooms"]["style"] = "oval"
	oval["corridors"] = {"extra_loops": [1, 3], "width": 2}
	var a := ShardGenerator.generate(box, 9, 1)
	var b := ShardGenerator.generate(oval, 9, 1)
	assert_eq(ShardValidator.validate(b, tiles), [], "oval + wide stays valid")
	assert_true(a["rows"] != b["rows"], "the carving differs")
	var raw_room: Array = b["rooms"][0]
	var room := Rect2i(int(raw_room[0]), int(raw_room[1]), int(raw_room[2]), int(raw_room[3]))
	var rows_b: Array = b["rows"]
	# An oval room leaves its rectangle corners as wall (the ellipse misses them).
	var corner := String(rows_b[room.position.y]).substr(room.position.x, 1)
	var centre := String(rows_b[room.position.y + room.size.y / 2]).substr(room.position.x + room.size.x / 2, 1)
	assert_true(room.size.x >= 4 and room.size.y >= 3, "room big enough to have corners")
	assert_true(corner != "." or room.size.x <= 2, "ellipse leaves the corner")
	assert_true(centre != "#", "ellipse keeps the centre (floor or the spawn marker), got %s" % centre)
	var wide := 0
	var narrow := 0
	for seed_value: int in range(1, 6):
		var w := ShardGenerator.generate(oval, seed_value, 1)
		var n := ShardGenerator.generate(box, seed_value, 1)
		wide += _floor_count(w)
		narrow += _floor_count(n)
	assert_true(wide > narrow, "two-wide corridors and hollows carve more floor (%d vs %d)" % [wide, narrow])


static func _floor_count(entry: Dictionary) -> int:
	var n := 0
	for row: String in entry["rows"]:
		for ch: String in row:
			if ch != "#":
				n += 1
	return n



# --- S18: secrets, vaults, waypoints, merchant, ramp, rarity ---------------

func _first_with_features(depth: int = 1) -> Dictionary:
	for seed_value: int in range(1, 40):
		var e := ShardGenerator.generate(template, seed_value, depth)
		if Array(e["secrets"]).size() >= 1 and Array(e["vaults"]).size() >= 1 and Array(e["waypoints"]).size() >= 1 and Array(e["npcs"]).size() >= 1:
			return e
	return {}


func test_every_feature_is_emitted_as_data_and_validates() -> void:
	var counts := {"secrets": 0, "vaults": 0, "waypoints": 0, "npcs": 0}
	for seed_value: int in range(1, 31):
		var e := ShardGenerator.generate(template, seed_value, 1)
		assert_eq(ShardValidator.validate(e, tiles), [], "seed %d with features" % seed_value)
		for key: String in counts:
			counts[key] += Array(e[key]).size()
		var gen: Dictionary = e["generation"]
		assert_true(int(gen["ramp_far_distance"]) > 0, "seed %d ramp" % seed_value)
	for key: String in counts:
		assert_true(int(counts[key]) >= 15, "%s appear in most seeds (%d over thirty)" % [key, counts[key]])
	var e := _first_with_features()
	assert_false(e.is_empty(), "some seed carries every feature")
	var map := MapData.parse(e, tiles)
	var secret: Dictionary = e["secrets"][0]
	var door := Vector2i(int(secret["door"][0]), int(secret["door"][1]))
	assert_eq(map.door_kind(door), "secret")
	assert_false(map.is_walkable(door), "closed doors block")
	var reach := ShardValidator.reachable_from(map, map.spawn_cells()[0])
	for raw: Array in secret["cells"]:
		assert_false(reach.has(Vector2i(int(raw[0]), int(raw[1]))), "pocket sealed")
	var vault: Dictionary = e["vaults"][0]
	assert_eq(vault["cost"], {"ciphers": 1})
	var vault_door := Vector2i(int(vault["door"][0]), int(vault["door"][1]))
	assert_eq(map.door_kind(vault_door), "vault")
	var vault_loot := 0
	for p: Dictionary in e["pickups"]:
		var c := Vector2i(int(p["cell"][0]), int(p["cell"][1]))
		for raw: Array in vault["cells"]:
			if c == Vector2i(int(raw[0]), int(raw[1])):
				vault_loot += 1
				assert_true(["rare", "epic"].has(String(p.get("rarity", "common"))), "vault loot is at least rare")
	assert_eq(vault_loot, Array(vault["cells"]).size(), "one pickup per vault cell")
	var w := Vector2i(int(e["waypoints"][0][0]), int(e["waypoints"][0][1]))
	assert_true(map.is_waypoint(w))
	assert_true(reach.has(w), "waypoints are on the open path")
	var npc: Dictionary = e["npcs"][0]
	assert_eq(npc["merchant"], "undercity_fence")
	var m := Vector2i(int(npc["cell"][0]), int(npc["cell"][1]))
	assert_true(reach.has(m) and map.is_walkable(m))


func test_features_never_change_with_depth_or_extras() -> void:
	var extras: Array[String] = ["sera_village_site"]
	for seed_value: int in range(1, 11):
		var a := ShardGenerator.generate(template, seed_value, 1)
		var b := ShardGenerator.generate(template, seed_value, 3, extras)
		assert_eq(a["rows"], b["rows"], "seed %d layout" % seed_value)
		assert_eq(a["secrets"], b["secrets"], "seed %d secrets" % seed_value)
		assert_eq(a["vaults"], b["vaults"], "seed %d vaults" % seed_value)
		assert_eq(a["waypoints"], b["waypoints"], "seed %d waypoints" % seed_value)
		assert_eq(a["npcs"], b["npcs"], "seed %d merchant" % seed_value)


func test_ramp_puts_elites_and_bigger_groups_far_from_the_spawn() -> void:
	var far_elites := 0
	for seed_value: int in range(1, 21):
		var e := ShardGenerator.generate(template, seed_value, 3)
		var map := MapData.parse(e, tiles)
		var origin_raw: Array = Dictionary(e["generation"])["ramp_origin"]
		var walk := ShardValidator.walking_distances(map, Vector2i(int(origin_raw[0]), int(origin_raw[1])), true)
		var far := int(Dictionary(e["generation"])["ramp_far_distance"])
		for p: Dictionary in e["enemies"]:
			if String(p.get("tier", "")) == "elite":
				far_elites += 1
				var c := Vector2i(int(p["cell"][0]), int(p["cell"][1]))
				assert_true(int(walk.get(c, -1)) >= far, "seed %d elite at %s past %d" % [seed_value, c, far])
	assert_true(far_elites >= 5, "elites roll past the ramp (%d)" % far_elites)


func test_validator_rejects_broken_features() -> void:
	var e := _first_with_features()
	assert_false(e.is_empty())
	var ok := ShardValidator.validate(e, tiles)
	assert_eq(ok, [])
	# A secret whose pocket is exposed: punch the door open in the rows.
	var exposed := e.duplicate(true)
	var door: Array = exposed["secrets"][0]["door"]
	var rows: Array = exposed["rows"]
	var row := String(rows[int(door[1])])
	rows[int(door[1])] = row.substr(0, int(door[0])) + "." + row.substr(int(door[0]) + 1)
	var errs := ShardValidator.validate(exposed, tiles)
	assert_true(_any(errs, "is not a secret door tile") and _any(errs, "reachable without the door"), str(errs))
	# A vault with no cost.
	var free := e.duplicate(true)
	free["vaults"][0]["cost"] = {}
	assert_true(_any(ShardValidator.validate(free, tiles), "has no cost"))
	# A waypoint claimed on plain floor.
	var fake := e.duplicate(true)
	var spawn := MapData.parse(e, tiles).spawn_cells()[0]
	fake["waypoints"].append([spawn.x + 1, spawn.y])
	var werrs := ShardValidator.validate(fake, tiles)
	assert_true(_any(werrs, "is not a waypoint tile"), str(werrs))
	# A merchant on the pad.
	var greedy := e.duplicate(true)
	greedy["npcs"][0]["cell"] = greedy["extraction"].duplicate()
	assert_true(_any(ShardValidator.validate(greedy, tiles), "merchant shares"))
	# An elite before the ramp and an unknown rarity.
	var early := e.duplicate(true)
	early["enemies"][0]["tier"] = "elite"
	early["generation"]["ramp_far_distance"] = 9999
	assert_true(_any(ShardValidator.validate(early, tiles), "before the ramp"))
	var odd := e.duplicate(true)
	odd["pickups"][0]["rarity"] = "mythic"
	assert_true(_any(ShardValidator.validate(odd, tiles), "unknown rarity"))


static func _any(errors: Array[String], fragment: String) -> bool:
	for e: String in errors:
		if e.contains(fragment):
			return true
	return false
