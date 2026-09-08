## Pure movement math: advance a point along waypoints by a distance budget.
class_name Mover
extends RefCounted


## Returns {"position": Vector2, "waypoints": Array[Vector2]} — the new
## position and the waypoints still ahead. Reached waypoints are consumed,
## several per call if the budget allows.
static func advance(position: Vector2, waypoints: Array[Vector2], distance: float) -> Dictionary:
	var pos := position
	var remaining: Array[Vector2] = []
	remaining.assign(waypoints)
	var budget := distance
	while not remaining.is_empty() and budget > 0.0:
		var target: Vector2 = remaining[0]
		var d := pos.distance_to(target)
		if d <= budget:
			pos = target
			budget -= d
			remaining.remove_at(0)
		else:
			pos += (target - pos) / d * budget
			budget = 0.0
	return {"position": pos, "waypoints": remaining}
