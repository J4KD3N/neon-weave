## Grid pathfinding over a [MapData]. Diagonals allowed, corner-cutting past
## a blocked cell is not.
class_name NavGrid
extends RefCounted

var _astar := AStarGrid2D.new()
var _map: MapData


func build(map: MapData) -> void:
	_map = map
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, maxi(map.width, 1), maxi(map.height, 1))
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y: int in map.height:
		for x: int in map.width:
			var cell := Vector2i(x, y)
			if not map.is_walkable(cell):
				_astar.set_point_solid(cell, true)


## Cells from `from` to `to` inclusive, or empty when either end is blocked
## or no route exists. A zero-length move returns `[from]`.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if _map == null or not (_map.is_walkable(from) and _map.is_walkable(to)):
		return empty
	return _astar.get_id_path(from, to)
