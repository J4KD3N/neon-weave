## The Ghost Markets as data (S33, D-088): palette roles, tiles, the
## Choir family across all five archetypes with summons that stay in the
## family, the template validating over a hundred seeds, the echo-static
## surface halving tech damage, and the Beacon at depth 3 finding it.
extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"static": {"id": "static", "walkable": true, "surface": "echo"},
}
const ABILITIES: Dictionary = {
	"zap": {"id": "zap", "name": "Zap", "ap": 2, "range": 4, "damage": [4, 4], "accuracy": 100, "damage_type": "tech", "requires_los": true},
	"bolt": {"id": "bolt", "name": "Bolt", "ap": 2, "range": 4, "damage": [4, 4], "accuracy": 100, "damage_type": "arcane", "requires_los": true},
}

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])


func after_each() -> void:
	registry.free()


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String]) -> Combatant:
	return Combatant.make(id, id, team, cell, {"hp": 20, "move": 4, "evasion": 0, "initiative": 0}, abilities, 4)


func _state(rows: Array, combatants: Array[Combatant], first: String) -> CombatState:
	var s := CombatState.new()
	var rules := CombatRules.from_entry({"surface_resist": {"echo": {"tech": 0.5}}, "min_hit_chance": 0, "max_hit_chance": 100, "initiative_die": 1})
	s.setup(MapData.parse({"id": "g", "legend": {".": "floor", "e": "static", "P": "floor"}, "rows": rows}, TILES), rules, ABILITIES, combatants, 1)
	s.start(first)
	return s


func test_ghost_markets_is_a_complete_biome() -> void:
	var biome := registry.get_entry("biomes", "ghost_markets")
	assert_false(biome.is_empty())
	var undercity: Dictionary = registry.get_entry("biomes", "rusted_undercity")["palette"]
	var palette: Dictionary = biome["palette"]
	assert_eq(palette.size(), 16)
	for role: String in undercity:
		assert_true(palette.has(role), "role %s" % role)
		assert_true(String(palette[role]) != String(undercity[role]), "role %s is recoloured" % role)
	var template := registry.get_entry("shards", "ghost_markets")
	assert_eq(template["requires_unlock"], "ghost_markets")
	for key: String in template["tiles"]:
		assert_true(registry.has_entry("tiles", String(template["tiles"][key])), "tile %s" % key)
	assert_eq(int(registry.get_entry("tiles", "stall").get("cover", 0)), 1, "stalls are cover")
	assert_eq(String(registry.get_entry("tiles", "echo_static").get("surface", "")), "echo")
	var surfaces: Dictionary = {}
	for p: Dictionary in Dictionary(template["surfaces"])["pool"]:
		var tile := registry.get_entry("tiles", String(p["tile"]))
		assert_false(tile.is_empty(), "surface tile %s" % p["tile"])
		surfaces[String(tile.get("surface", "height" if tile.has("height") else ""))] = true
	for s: String in ["echo", "mana_pool", "conduit", "height"]:
		assert_true(surfaces.has(s), "the template lays %s" % s)
	assert_true(registry.has_entry("merchants", String(Dictionary(template["features"])["merchant"])))
	for tile: Dictionary in registry.get_all("tiles"):
		if bool(tile.get("walkable", false)):
			assert_true(tile.has("sound"), "walkable tile %s has a footstep" % tile["id"])


func test_the_choir_family_fields_every_archetype() -> void:
	var archetypes: Dictionary = {}
	var boss := ""
	var pool_types: Array[String] = []
	for p: Dictionary in Dictionary(registry.get_entry("shards", "ghost_markets")["enemies"])["pool"]:
		pool_types.append(String(p["type"]))
		assert_true(registry.has_entry("enemies", String(p["type"])), "pool type %s" % p["type"])
	assert_true(pool_types.size() >= 4)
	var traited := 0
	for e: Dictionary in registry.get_all("enemies"):
		if String(e.get("family", "")) != "ghost_markets":
			continue
		archetypes[String(e["archetype"])] = true
		if String(e.get("tier", "")) == "boss":
			boss = String(e["id"])
		if e.has("traits"):
			traited += 1
		for a: String in e["abilities"]:
			assert_true(registry.has_entry("abilities", a), "%s ability %s" % [e["id"], a])
			var ability := registry.get_entry("abilities", a)
			if String(ability.get("effect", "")) == "summon":
				assert_eq(registry.get_entry("enemies", String(ability["summon"])).get("family", ""), "ghost_markets", "summons stay in the family")
	for a: String in ["rusher", "ranged", "stealther", "summoner", "controller"]:
		assert_true(archetypes.has(a), "the family fields a %s" % a)
	assert_eq(boss, "choir_voice")
	assert_true(traited >= 2, "the family uses the trait vocabulary (D-085): %d entries" % traited)
	var beacon := registry.get_entry("buildings", "beacon")
	assert_eq(Dictionary(Array(beacon["levels"])[2]).get("unlocks", []), ["ghost_markets"], "the Beacon at depth 3 finds it")


func test_a_hundred_seeds_validate_at_every_depth() -> void:
	var template := registry.get_entry("shards", "ghost_markets")
	var tiles: Dictionary = {}
	for t: Dictionary in registry.get_all("tiles"):
		tiles[t["id"]] = t
	var stalls := 0
	var statics := 0
	for seed_value: int in 100:
		var depth := 1 + seed_value % 3
		var entry := ShardGenerator.generate(template, seed_value, depth)
		var errors := ShardValidator.validate(entry, tiles)
		assert_eq(errors, [], "seed %d depth %d: %s" % [seed_value, depth, errors])
		for row: String in entry["rows"]:
			stalls += row.count("x")
			statics += row.count("e")
		if depth >= 3:
			var boss_posted := false
			for p: Dictionary in entry["enemies"]:
				if String(p.get("tier", "")) == "boss":
					boss_posted = true
			assert_true(boss_posted, "seed %d: the Voice holds the pad at depth 3" % seed_value)
	assert_true(stalls > 0 and statics > 0, "stalls and static appear: %d / %d" % [stalls, statics])


func test_echo_static_halves_tech_damage_on_whoever_stands_in_it() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["zap", "bolt"])
	var jammed := _c("j", "enemy", Vector2i(2, 0), ["zap"])
	var clear := _c("c", "enemy", Vector2i(0, 2), ["zap"])
	var s := _state(["P.e.", "....", "....", "...."], [p, jammed, clear], "party")
	assert_eq(s.map.surface_at(jammed.cell), "echo")
	var hit := s.use_ability(p, "zap", jammed.cell)
	assert_eq(jammed.hp, 18, "4 tech, half jammed by the static: %s" % [hit])
	assert_eq(int(hit.get("resisted", 0)), 2)
	s.use_ability(p, "bolt", jammed.cell)
	assert_eq(jammed.hp, 14, "arcane is not jammed")
	var r := CombatRules.from_entry(registry.get_entry("rules", "combat"))
	assert_eq(float(Dictionary(r.surface_resist.get("echo", {})).get("tech", 0.0)), 0.5, "the shipped rule")
	var s2 := _state(["P...", "....", "....", "...."], [_c("q", "party", Vector2i(0, 0), ["zap"]), clear], "party")
	s2.use_ability(s2.by_id("q"), "zap", clear.cell)
	assert_eq(clear.hp, 16, "clear floor: the full 4")
