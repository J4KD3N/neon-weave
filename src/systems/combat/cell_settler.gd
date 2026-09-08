## Assigns distinct walkable cells to actors when combat starts. Each actor
## keeps its preferred cell when it is free; otherwise it takes the nearest
## free cell to that preference.
class_name CellSettler
extends RefCounted


static func settle(map: MapData, preferred: Array[Vector2i], blocked: Array[Vector2i]) -> Array[Vector2i]:
	var taken: Array[Vector2i] = []
	taken.assign(blocked)
	var out: Array[Vector2i] = []
	for want: Vector2i in preferred:
		var cell := want
		if not map.is_walkable(cell) or taken.has(cell):
			var options := map.nearest_free_cells(want, 1, taken)
			if options.is_empty():
				options = map.nearest_free_cells(preferred[0], 1, taken)
			cell = options[0] if not options.is_empty() else want
		taken.append(cell)
		out.append(cell)
	return out
