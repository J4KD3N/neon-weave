## The Null Cathedral as data (S34, D-089): palette, tiles, the cathedral
## family across all five archetypes, a null surface that silences whoever
## starts a turn in it, a flag gate instead of a Beacon level, and the
## Loom Approach remix template that draws its enemies from every family
## and its surfaces from every template by rule.
extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"font": {"id": "font", "walkable": true, "surface": "null"},
}
const ABILITIES: Dictionary = {
	"bolt": {"id": "bolt", "name": "Bolt", "ap": 2, "range": 4, "damage": [4, 4], "accuracy": 100, "damage_type": "arcane", "requires_los": true},
	"strike": {"id": "strike", "name": "Strike", "ap": 2, "range": 1, "damage": [4, 4], "accuracy": 100, "damage_type": "physical"},
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
	var rules := CombatRules.from_entry({"surface_status": {"null": {"silenced": 1}}, "min_hit_chance": 0, "max_hit_chance": 100, "initiative_die": 1})
	s.setup(MapData.parse({"id": "n", "legend": {".": "floor", "n": "font", "P": "floor"}, "rows": rows}, TILES), rules, ABILITIES, combatants, 1)
	s.start(first)
	return s


func _tiles() -> Dictionary:
	var tiles: Dictionary = {}
	for t: Dictionary in registry.get_all("tiles"):
		tiles[t["id"]] = t
	return tiles


func test_the_cathedral_is_a_complete_biome_behind_a_flag() -> void:
	var biome := registry.get_entry("biomes", "null_cathedral")
	assert_false(biome.is_empty())
	var palette: Dictionary = biome["palette"]
	assert_eq(palette.size(), 16)
	for role: String in registry.get_entry("biomes", "rusted_undercity")["palette"]:
		assert_true(palette.has(role), "role %s" % role)
	var template := registry.get_entry("shards", "null_cathedral")
	assert_eq(String(template.get("requires_unlock", "")), "", "no Beacon level reaches it")
	assert_eq(String(template["requires_flag"]), "null_cathedral_found", "Act 2 opens it")
	for key: String in template["tiles"]:
		assert_true(registry.has_entry("tiles", String(template["tiles"][key])), "tile %s" % key)
	assert_eq(int(registry.get_entry("tiles", "pew").get("cover", 0)), 1)
	assert_eq(String(registry.get_entry("tiles", "null_font").get("surface", "")), "null")
	assert_true(registry.has_entry("merchants", String(Dictionary(template["features"])["merchant"])))
	assert_true(registry.has_entry("audio", String(Dictionary(Dictionary(registry.get_entry("rules", "audio")["music"])["explore"])["null_cathedral"])), "explore music")


func test_the_cathedral_family_fields_every_archetype() -> void:
	var archetypes: Dictionary = {}
	var boss := ""
	for e: Dictionary in registry.get_all("enemies"):
		if String(e.get("family", "")) != "null_cathedral":
			continue
		archetypes[String(e["archetype"])] = true
		if String(e.get("tier", "")) == "boss":
			boss = String(e["id"])
		assert_true(e.has("traits") or String(e["archetype"]) == "ranged" or String(e["archetype"]) == "summoner", "%s carries traits" % e["id"])
		for a: String in e["abilities"]:
			assert_true(registry.has_entry("abilities", a), "%s ability %s" % [e["id"], a])
			var ability := registry.get_entry("abilities", a)
			if String(ability.get("effect", "")) == "summon":
				assert_eq(registry.get_entry("enemies", String(ability["summon"])).get("family", ""), "null_cathedral")
	for a: String in ["rusher", "ranged", "stealther", "summoner", "controller"]:
		assert_true(archetypes.has(a), "the family fields a %s" % a)
	assert_eq(boss, "the_organist")
	assert_eq(String(Dictionary(registry.get_entry("abilities", "great_hush")).get("effect", "")), "silence")
	assert_eq(int(registry.get_entry("abilities", "great_hush").get("aoe", 0)), 2, "the Organist hushes the room")


func test_a_hundred_seeds_validate_and_the_organist_holds_depth_three() -> void:
	var template := registry.get_entry("shards", "null_cathedral")
	var fonts := 0
	for seed_value: int in 100:
		var depth := 1 + seed_value % 3
		var entry := ShardGenerator.generate(template, seed_value, depth)
		var errors := ShardValidator.validate(entry, _tiles())
		assert_eq(errors, [], "seed %d depth %d: %s" % [seed_value, depth, errors])
		for row: String in entry["rows"]:
			fonts += row.count("n")
		if depth >= 3:
			var posted := false
			for p: Dictionary in entry["enemies"]:
				if String(p.get("tier", "")) == "boss":
					posted = true
			assert_true(posted, "seed %d: the Organist at the pad" % seed_value)
	assert_true(fonts > 0, "null fonts appear")


func test_null_fonts_silence_whoever_starts_a_turn_in_them() -> void:
	var caster := _c("c", "party", Vector2i(2, 0), ["bolt", "strike"])
	var clear := _c("k", "party", Vector2i(0, 2), ["bolt"])
	var e := _c("e", "enemy", Vector2i(3, 2), ["strike"])
	var s := _state(["P.n.", "....", "....", "...."], [caster, clear, e], "party")
	s.switch_to("c")
	assert_true(caster.is_silenced(), "the font took the voice at the start of the turn")
	assert_eq(s.can_use(caster, "bolt", e.cell), "silenced")
	assert_eq(s.can_use(caster, "strike", Vector2i(3, 2)), "out of range", "steel still works")
	assert_any_contains(s.history, "the null font takes")
	s.switch_to("k")
	assert_false(clear.is_silenced())
	var r := CombatRules.from_entry(registry.get_entry("rules", "combat"))
	assert_eq(int(Dictionary(r.surface_status.get("null", {})).get("silenced", 0)), 1, "the shipped rule")


func test_the_loom_approach_remix_mixes_every_family_and_surface_by_rule() -> void:
	var raw := registry.get_entry("shards", "loom_approach")
	assert_eq(String(raw["requires_flag"]), "loom_located")
	assert_eq(Array(Dictionary(raw["enemies"])["pool"]).size(), 0, "the file lists no types: the rule fills them")
	var template := ShardGenerator.expand_remix(raw, registry)
	var families: Dictionary = {}
	for p: Dictionary in Dictionary(template["enemies"])["pool"]:
		var e := registry.get_entry("enemies", String(p["type"]))
		assert_false(e.is_empty(), "pool type %s" % p["type"])
		assert_true(String(e.get("tier", "")) != "boss", "bosses stay out of the pool")
		assert_true(int(e.get("awareness", 5)) > 0, "summoned-only minions stay out: %s" % p["type"])
		families[String(e["family"])] = true
	assert_eq(families.size(), 4, "every family: %s" % [families.keys()])
	var surfaces: Dictionary = {}
	for p: Dictionary in Dictionary(template["surfaces"])["pool"]:
		var tile := registry.get_entry("tiles", String(p["tile"]))
		surfaces[String(tile.get("surface", "height" if tile.has("height") else ""))] = true
	for s: String in ["null", "echo", "spore", "corrosive", "mana_pool", "conduit", "height"]:
		assert_true(surfaces.has(s), "the remix lays %s" % s)
	assert_eq(ShardGenerator.expand_remix(registry.get_entry("shards", "rusted_undercity"), registry), registry.get_entry("shards", "rusted_undercity"), "no remix key: untouched")
	for seed_value: int in 50:
		var entry := ShardGenerator.generate(template, seed_value, 1)
		var errors := ShardValidator.validate(entry, _tiles())
		assert_eq(errors, [], "remix seed %d: %s" % [seed_value, errors])
		var posted := false
		for p: Dictionary in entry["enemies"]:
			if String(p.get("tier", "")) == "boss":
				posted = true
		assert_true(posted, "the Organist holds the door at every depth")
