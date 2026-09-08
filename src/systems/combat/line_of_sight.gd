## Grid line of sight: a Bresenham walk between two cells; any intermediate
## cell that blocks sight (tall walls) breaks the line. Combatants never
## block sight in M0.
class_name LineOfSight
extends RefCounted


static func cells_between(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx + dy
	var x := from.x
	var y := from.y
	while true:
		if not (x == from.x and y == from.y) and not (x == to.x and y == to.y):
			out.append(Vector2i(x, y))
		if x == to.x and y == to.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return out


static func clear(map: MapData, from: Vector2i, to: Vector2i) -> bool:
	for cell: Vector2i in cells_between(from, to):
		if map.blocks_sight(cell):
			return false
	return true


## Chebyshev distance: the range metric on an 8-connected grid.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
