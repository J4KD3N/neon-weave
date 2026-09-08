extends TestCase

const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"wall": {"id": "wall", "walkable": false},
}


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "n", "legend": {".": "floor", "#": "wall", "P": "floor"}, "rows": rows}, TILES)


static func _nav(rows: Array) -> NavGrid:
	var nav := NavGrid.new()
	nav.build(_map(rows))
	return nav


func test_path_goes_around_walls_and_stays_walkable() -> void:
	var rows: Array = [
		"#######",
		"#P.#..#",
		"#..#..#",
		"#.....#",
		"#######",
	]
	var map := _map(rows)
	var nav := NavGrid.new()
	nav.build(map)
	var path := nav.find_path(Vector2i(1, 1), Vector2i(5, 1))
	assert_true(path.size() > 4, "must detour below the wall")
	assert_eq(path[0], Vector2i(1, 1))
	assert_eq(path[path.size() - 1], Vector2i(5, 1))
	assert_true(path.has(Vector2i(3, 3)), "the only gap is at (3,3)")
	for cell: Vector2i in path:
		assert_true(map.is_walkable(cell), "path crosses %s" % cell)


func test_unreachable_target_gives_empty_path() -> void:
	var nav := _nav(["#####", "#P#.#", "#####"])
	assert_eq(nav.find_path(Vector2i(1, 1), Vector2i(3, 1)), [])


func test_blocked_endpoints_give_empty_path() -> void:
	var nav := _nav(["###", "#P#", "###"])
	assert_eq(nav.find_path(Vector2i(1, 1), Vector2i(0, 0)), [])
	assert_eq(nav.find_path(Vector2i(0, 0), Vector2i(1, 1)), [])


func test_same_cell_is_a_single_step() -> void:
	var nav := _nav(["###", "#P#", "###"])
	assert_eq(nav.find_path(Vector2i(1, 1), Vector2i(1, 1)), [Vector2i(1, 1)])


func test_no_corner_cutting_past_obstacles() -> void:
	var nav := _nav([
		"#####",
		"#P#.#",
		"#...#",
		"#####",
	])
	var path := nav.find_path(Vector2i(1, 1), Vector2i(3, 1))
	# Diagonals past the wall at (2,1) are forbidden, so the route is
	# (1,1) (1,2) (2,2) (3,2) (3,1).
	assert_eq(path.size(), 5)
	assert_eq(path[2], Vector2i(2, 2))


func test_diagonals_used_in_open_space() -> void:
	var nav := _nav([
		"#####",
		"#P..#",
		"#...#",
		"#...#",
		"#####",
	])
	var path := nav.find_path(Vector2i(1, 1), Vector2i(3, 3))
	assert_eq(path.size(), 3, "two diagonal steps")
