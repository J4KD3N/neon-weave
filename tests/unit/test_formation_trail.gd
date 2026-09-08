extends TestCase

var trail: FormationTrail


func before_each() -> void:
	trail = FormationTrail.new()
	trail.reset(Vector2.ZERO)
	trail.push(Vector2(10, 0))
	trail.push(Vector2(20, 0))
	trail.push(Vector2(20, 10))


func test_length_sums_segments() -> void:
	assert_true(is_equal_approx(trail.length(), 30.0))
	assert_true(trail.has_distance(30.0))
	assert_false(trail.has_distance(30.5))


func test_point_behind_walks_back_along_segments() -> void:
	assert_eq(trail.point_behind(0.0), Vector2(20, 10))
	assert_eq(trail.point_behind(5.0), Vector2(20, 5))
	assert_eq(trail.point_behind(15.0), Vector2(15, 0))
	assert_eq(trail.point_behind(30.0), Vector2(0, 0))


func test_point_behind_clamps_to_oldest() -> void:
	assert_eq(trail.point_behind(1000.0), Vector2(0, 0))


func test_tiny_steps_are_ignored() -> void:
	var before := trail.points.size()
	trail.push(Vector2(20, 10.2))
	assert_eq(trail.points.size(), before)


func test_trims_to_max_length_from_the_oldest_end() -> void:
	trail.max_length = 12.0
	trail.push(Vector2(20, 20)) # total 40 -> drop oldest until <= 12
	assert_true(trail.length() <= 12.0)
	assert_eq(trail.points[trail.points.size() - 1], Vector2(20, 20))
	assert_true(trail.points.size() >= 2)


func test_empty_trail_is_safe() -> void:
	var t := FormationTrail.new()
	assert_eq(t.point_behind(5.0), Vector2.ZERO)
	assert_false(t.has_distance(0.1))
	t.push(Vector2(1, 1))
	assert_eq(t.points.size(), 1)
