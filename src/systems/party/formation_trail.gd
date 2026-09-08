## Breadcrumb trail left by the party leader. Followers target points a fixed
## path-distance behind, so they walk exactly where the leader walked.
class_name FormationTrail
extends RefCounted

const MIN_STEP := 0.5

var points := PackedVector2Array()
var max_length: float = 800.0


func reset(origin: Vector2) -> void:
	points = PackedVector2Array([origin])


func push(p: Vector2) -> void:
	if points.is_empty():
		points.append(p)
		return
	if points[points.size() - 1].distance_to(p) < MIN_STEP:
		return
	points.append(p)
	_trim()


func length() -> float:
	var total := 0.0
	for i: int in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func has_distance(distance: float) -> bool:
	return length() >= distance


## The point `distance` back along the trail from its newest point. Clamps
## to the oldest point when the trail is shorter than `distance`.
func point_behind(distance: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var remaining := distance
	for i: int in range(points.size() - 1, 0, -1):
		var a := points[i]
		var b := points[i - 1]
		var seg := a.distance_to(b)
		if seg >= remaining:
			return a.lerp(b, remaining / seg) if seg > 0.0 else a
		remaining -= seg
	return points[0]


func _trim() -> void:
	while points.size() > 2 and length() > max_length:
		points.remove_at(0)
