## The Verdant Datacore as data: palette roles, tiles, family archetype mix,
## template references; and the spore surface as a mechanic.
extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"spore": {"id": "spore", "walkable": true, "surface": "spore"},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 1, "range": 1, "damage": [3, 3], "accuracy": 80, "damage_type": "physical"},
	"zap": {"id": "zap", "name": "Zap", "ap": 1, "range": 4, "damage": [2, 2], "accuracy": 80, "damage_type": "tech", "requires_los": true},
}

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])


func after_each() -> void:
	registry.free()


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "v", "legend": {".": "floor", "s": "spore", "P": "floor"}, "rows": rows}, TILES)


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], archetype: String = "rusher") -> Combatant:
	var c := Combatant.make(id, id, team, cell, {"hp": 20, "move": 4, "evasion": 0, "initiative": 0}, abilities, 4)
	c.archetype = archetype
	return c


func _state(rows: Array, combatants: Array[Combatant], first: String) -> CombatState:
	var s := CombatState.new()
	var rules := CombatRules.from_entry({"surface_evasion": {"spore": 10}, "min_hit_chance": 0, "max_hit_chance": 100, "initiative_die": 1})
	s.setup(_map(rows), rules, ABILITIES, combatants, 1)
	s.start(first)
	return s


func test_datacore_is_a_complete_biome() -> void:
	var biome := registry.get_entry("biomes", "verdant_datacore")
	assert_false(biome.is_empty())
	var undercity: Dictionary = registry.get_entry("biomes", "rusted_undercity")["palette"]
	var palette: Dictionary = biome["palette"]
	assert_eq(palette.size(), 16)
	for role: String in undercity:
		assert_true(palette.has(role), "role %s" % role)
		assert_true(String(palette[role]) != String(undercity[role]), "role %s is recoloured" % role)
	var template := registry.get_entry("shards", "verdant_datacore")
	assert_eq(template["requires_unlock"], "verdant_datacore")
	assert_eq(Dictionary(template["rooms"])["style"], "oval")
	assert_eq(int(Dictionary(template["corridors"])["width"]), 2)
	for key: String in template["tiles"]:
		assert_true(registry.has_entry("tiles", String(template["tiles"][key])), "tile %s" % key)
	var surfaces: Dictionary = {}
	for p: Dictionary in Dictionary(template["surfaces"])["pool"]:
		var tile := registry.get_entry("tiles", String(p["tile"]))
		assert_false(tile.is_empty(), "surface tile %s" % p["tile"])
		surfaces[String(tile.get("surface", "height" if tile.has("height") else ""))] = true
	for s: String in ["spore", "mana_pool", "conduit", "corrosive", "height"]:
		assert_true(surfaces.has(s), "the template grows %s" % s)


func test_datacore_family_covers_the_archetypes() -> void:
	var archetypes: Dictionary = {}
	var boss := ""
	var pool_types: Array[String] = []
	for p: Dictionary in Dictionary(registry.get_entry("shards", "verdant_datacore")["enemies"])["pool"]:
		pool_types.append(String(p["type"]))
	assert_true(pool_types.size() >= 4, "four types in the pool")
	for e: Dictionary in registry.get_all("enemies"):
		if String(e.get("family", "")) != "verdant_datacore":
			continue
		archetypes[String(e["archetype"])] = true
		if String(e.get("tier", "")) == "boss":
			boss = String(e["id"])
		for a: String in e["abilities"]:
			assert_true(registry.has_entry("abilities", a), "%s ability %s" % [e["id"], a])
			var ability := registry.get_entry("abilities", a)
			if String(ability.get("effect", "")) == "summon":
				var kind := String(ability["summon"])
				assert_eq(registry.get_entry("enemies", kind).get("family", ""), "verdant_datacore", "summons stay in the family")
	for a: String in ["rusher", "ranged", "stealther", "summoner", "controller"]:
		assert_true(archetypes.has(a), "the family fields a %s" % a)
	assert_eq(boss, "canopy_matron")
	assert_eq(Dictionary(Dictionary(registry.get_entry("shards", "verdant_datacore")["enemies"])["boss"])["type"], "canopy_matron")
	var beacon := registry.get_entry("buildings", "beacon")
	var unlocks: Array = Dictionary(Array(beacon["levels"])[1]).get("unlocks", [])
	assert_eq(unlocks, ["verdant_datacore"], "the Beacon upgrade to depth 2 finds it")


func test_spores_grant_evasion_to_the_target_and_tag_the_roll() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["strike"])
	var e := _c("e", "enemy", Vector2i(1, 0), ["strike"])
	var s := _state(["Ps..."], [p, e], "party")
	var mods := s.attack_modifiers(p, s.abilities["strike"], e)
	assert_eq(int(mods["shroud"]), 10)
	assert_eq(int(mods["hit"]), -10)
	var preview := s.preview(p, "strike", e.cell)
	assert_eq(int(preview["chance"]), 70, "80 - 10 for the spores")
	assert_eq(preview["tags"], PackedStringArray(["spores"]))
	var r := s.use_ability(p, "strike", e.cell)
	assert_eq(int(r["chance"]), 70)
	assert_eq(int(r["shroud"]), 10)
	if not bool(r["hit"]):
		assert_any_contains(s.history, "(spores)")
	var back := s.attack_modifiers(e, s.abilities["strike"], p)
	assert_eq(int(back["shroud"]), 0, "the attacker standing in spores gains nothing on offence")


func test_enemies_value_a_spore_bed() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["strike"])
	var e := _c("e", "enemy", Vector2i(3, 0), ["zap"], "ranged")
	var s := _state(["......", "...s.."], [p, e], "enemy")
	assert_eq(EnemyBrain.position_score(s, e, Vector2i(3, 1), p), 5, "half the evasion bonus")
	assert_eq(EnemyBrain.position_score(s, e, Vector2i(3, 0), p), 0)
	var a := EnemyBrain.next_action(s, e)
	assert_eq(a["type"], "move", "a better firing cell exists")
	assert_eq(a["to"], Vector2i(3, 1))


func test_rules_parse_surface_evasion() -> void:
	var r := CombatRules.from_entry(registry.get_entry("rules", "combat"))
	assert_eq(r.surface_evasion, {"spore": 10})
	assert_eq(CombatRules.from_entry({}).surface_evasion, {})
