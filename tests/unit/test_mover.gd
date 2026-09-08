extends TestCase


func test_partial_step_toward_first_waypoint() -> void:
	var wps: Array[Vector2] = [Vector2(10, 0), Vector2(10, 10)]
	var r: Dictionary = Mover.advance(Vector2.ZERO, wps, 4.0)
	assert_eq(r["position"], Vector2(4, 0))
	assert_eq(r["waypoints"], [Vector2(10, 0), Vector2(10, 10)])


func test_reaching_a_waypoint_consumes_it() -> void:
	var wps: Array[Vector2] = [Vector2(10, 0), Vector2(10, 10)]
	var r: Dictionary = Mover.advance(Vector2.ZERO, wps, 10.0)
	assert_eq(r["position"], Vector2(10, 0))
	assert_eq(r["waypoints"], [Vector2(10, 10)])


func test_budget_carries_across_waypoints() -> void:
	var wps: Array[Vector2] = [Vector2(10, 0), Vector2(10, 10)]
	var r: Dictionary = Mover.advance(Vector2.ZERO, wps, 13.0)
	assert_eq(r["position"], Vector2(10, 3))
	assert_eq(r["waypoints"], [Vector2(10, 10)])


func test_overshoot_stops_at_final_waypoint() -> void:
	var wps: Array[Vector2] = [Vector2(10, 0)]
	var r: Dictionary = Mover.advance(Vector2.ZERO, wps, 100.0)
	assert_eq(r["position"], Vector2(10, 0))
	assert_eq(r["waypoints"], [])


func test_no_waypoints_is_a_no_op() -> void:
	var wps: Array[Vector2] = []
	var r: Dictionary = Mover.advance(Vector2(3, 3), wps, 5.0)
	assert_eq(r["position"], Vector2(3, 3))
	assert_eq(r["waypoints"], [])


func test_input_array_is_not_mutated() -> void:
	var wps: Array[Vector2] = [Vector2(10, 0)]
	Mover.advance(Vector2.ZERO, wps, 100.0)
	assert_eq(wps, [Vector2(10, 0)])
