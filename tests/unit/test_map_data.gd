extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "layer": "wall"},
}


static func _entry(rows: Array) -> Dictionary:
	return {"id": "t", "name": "T", "biome": "b", "legend": {".": "floor", "#": "wall", "P": "floor"}, "rows": rows}


func test_parses_dimensions_walkability_and_spawn() -> void:
	var map := MapData.parse(_entry(["###", "#P.", "###"]), TILES)
	assert_eq(map.errors, [])
	assert_eq(map.width, 3)
	assert_eq(map.height, 3)
	assert_eq(map.biome_id, "b")
	assert_true(map.is_walkable(Vector2i(1, 1)))
	assert_true(map.is_walkable(Vector2i(2, 1)))
	assert_false(map.is_walkable(Vector2i(0, 0)))
	assert_false(map.is_walkable(Vector2i(-1, 0)), "out of bounds is not walkable")
	assert_false(map.is_walkable(Vector2i(3, 1)), "out of bounds is not walkable")
	assert_eq(map.spawn_cells(), [Vector2i(1, 1)])
	assert_eq(map.tile_id_at(Vector2i(0, 0)), "wall")
	assert_eq(map.tile_id_at(Vector2i(1, 1)), "floor")
	assert_eq(map.walkable_count(), 2)


func test_tiles_are_only_those_used_sorted_by_id() -> void:
	var map := MapData.parse(_entry(["P."]), TILES)
	var ids: Array[String] = []
	for tile: Dictionary in map.tiles():
		ids.append(tile["id"])
	assert_eq(ids, ["floor"])


func test_ragged_rows_are_reported() -> void:
	var map := MapData.parse(_entry(["###", "#P", "###"]), TILES)
	assert_any_contains(map.errors, "row 1 has length 2, expected 3")
	assert_false(map.is_walkable(Vector2i(2, 1)))


func test_unknown_legend_char_is_reported() -> void:
	var map := MapData.parse(_entry(["#P?"]), TILES)
	assert_any_contains(map.errors, "'?' is not in the legend")
	assert_false(map.is_walkable(Vector2i(2, 0)))


func test_unknown_tile_id_is_reported() -> void:
	var entry := _entry(["#P~"])
	var legend: Dictionary = entry["legend"]
	legend["~"] = "lava"
	var map := MapData.parse(entry, TILES)
	assert_any_contains(map.errors, "unknown tile 'lava'")
	assert_eq(map.tile_id_at(Vector2i(2, 0)), "")


func test_missing_spawn_is_reported() -> void:
	var map := MapData.parse(_entry(["#.#"]), TILES)
	assert_any_contains(map.errors, "has no spawn marker 'P'")


func test_no_rows_is_reported() -> void:
	var map := MapData.parse(_entry([]), TILES)
	assert_any_contains(map.errors, "has no rows")
	assert_eq(map.width, 0)
	assert_eq(map.height, 0)


func test_enclosed_cells_have_no_walkable_neighbour() -> void:
	var map := MapData.parse(_entry(["####", "#P.#", "####", "####"]), TILES)
	assert_true(map.is_enclosed(Vector2i(0, 3)), "corner far from the floor")
	assert_true(map.is_enclosed(Vector2i(1, 3)))
	assert_false(map.is_enclosed(Vector2i(0, 0)), "diagonal to the spawn")
	assert_false(map.is_enclosed(Vector2i(1, 2)), "below the floor")
	assert_false(map.is_enclosed(Vector2i(1, 1)), "walkable cells are never enclosed")
