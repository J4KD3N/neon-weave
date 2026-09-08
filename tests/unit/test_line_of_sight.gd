extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false, "blocks_sight": true},
	"low": {"id": "low", "walkable": false, "blocks_sight": false},
}


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "l", "legend": {".": "floor", "#": "wall", "x": "low", "P": "floor"}, "rows": rows}, TILES)


func test_cells_between_excludes_endpoints() -> void:
	assert_eq(LineOfSight.cells_between(Vector2i(0, 0), Vector2i(3, 0)), [Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(LineOfSight.cells_between(Vector2i(0, 0), Vector2i(2, 2)), [Vector2i(1, 1)])
	assert_eq(LineOfSight.cells_between(Vector2i(2, 2), Vector2i(2, 2)), [])
	assert_eq(LineOfSight.cells_between(Vector2i(1, 1), Vector2i(1, 2)), [])


func test_walls_block_low_obstacles_do_not() -> void:
	var map := _map(["P.#..", ".....", "..x..", "....."])
	assert_false(LineOfSight.clear(map, Vector2i(0, 0), Vector2i(4, 0)), "wall in the way")
	assert_true(LineOfSight.clear(map, Vector2i(0, 2), Vector2i(4, 2)), "debris does not block sight")
	assert_true(LineOfSight.clear(map, Vector2i(0, 1), Vector2i(4, 1)))
	assert_true(LineOfSight.clear(map, Vector2i(1, 0), Vector2i(2, 0)), "adjacent to a wall is fine")


func test_out_of_bounds_blocks_sight() -> void:
	var map := _map(["P."])
	assert_true(map.blocks_sight(Vector2i(-1, 0)))
	assert_true(map.blocks_sight(Vector2i(5, 5)))
	assert_false(map.blocks_sight(Vector2i(1, 0)))


func test_chebyshev_distance() -> void:
	assert_eq(LineOfSight.distance(Vector2i(0, 0), Vector2i(3, 1)), 3)
	assert_eq(LineOfSight.distance(Vector2i(2, 2), Vector2i(1, 1)), 1)
	assert_eq(LineOfSight.distance(Vector2i(0, 0), Vector2i(0, 0)), 0)
