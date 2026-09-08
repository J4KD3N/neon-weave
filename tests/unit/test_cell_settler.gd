extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false},
}


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "s", "legend": {".": "floor", "#": "wall", "P": "floor"}, "rows": rows}, TILES)


func test_free_preferred_cells_are_kept() -> void:
	var map := _map(["P....", ".....", "....."])
	var cells := CellSettler.settle(map, [Vector2i(1, 1), Vector2i(3, 1)], [])
	assert_eq(cells, [Vector2i(1, 1), Vector2i(3, 1)])


func test_duplicates_and_blocked_cells_get_nearest_free() -> void:
	var map := _map(["P....", ".....", "....."])
	var cells := CellSettler.settle(map, [Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 1)], [Vector2i(1, 1)])
	assert_eq(cells[0], Vector2i(2, 1))
	assert_ne(cells[1], cells[0])
	assert_ne(cells[2], cells[0])
	assert_ne(cells[1], cells[2])
	for c: Vector2i in cells:
		assert_true(map.is_walkable(c))
		assert_ne(c, Vector2i(1, 1), "enemy cell is never assigned")
		assert_true(LineOfSight.distance(c, Vector2i(2, 1)) <= 1, "stays adjacent to the preference")


func test_unwalkable_preference_is_relocated() -> void:
	var map := _map(["P.#..", "....."])
	var cells := CellSettler.settle(map, [Vector2i(2, 0)], [])
	assert_true(map.is_walkable(cells[0]))
	assert_true(LineOfSight.distance(cells[0], Vector2i(2, 0)) == 1)


func test_nearest_free_cells_bfs_order() -> void:
	var map := _map(["P..", "...", "..."])
	var near := map.nearest_free_cells(Vector2i(1, 1), 3, [Vector2i(1, 1)])
	assert_eq(near.size(), 3)
	for c: Vector2i in near:
		assert_eq(LineOfSight.distance(c, Vector2i(1, 1)), 1)
