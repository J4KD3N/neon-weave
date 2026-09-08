## Quest sites requested as extra pickups: placed once, validated, layout unchanged.
extends TestCase

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


func test_extra_pickups_are_placed_once_and_stay_valid() -> void:
	var extras: Array[String] = ["sera_village_site"]
	for seed_value: int in range(1, 16):
		var e := ShardGenerator.generate(template, seed_value, 1, extras)
		assert_eq(ShardValidator.validate(e, tiles), [], "seed %d" % seed_value)
		var count := 0
		for p: Dictionary in e["pickups"]:
			if String(p["type"]) == "sera_village_site":
				count += 1
		assert_eq(count, 1, "seed %d places the site once" % seed_value)
		var plain := ShardGenerator.generate(template, seed_value, 1)
		assert_eq(plain["rows"], e["rows"], "extras never change the layout")
		assert_eq(Array(plain["pickups"]).size() + 1, Array(e["pickups"]).size())
		var gen: Dictionary = e["generation"]
		assert_eq(gen["extra_pickups"], ["sera_village_site"])
