## Renders a [MapData] as two isometric [TileMapLayer]s (ground, walls) and
## owns the grid<->world projection and the [NavGrid]. Y-sort this node so
## its wall tiles interleave with actors in a sibling Y-sorted node.
class_name MapView
extends Node2D

var ground: TileMapLayer
var walls: TileMapLayer
var map: MapData
var nav := NavGrid.new()
var atlas_coords: Dictionary = {}


func build(map_data: MapData, biome: Dictionary) -> void:
	map = map_data
	_ensure_layers()
	var built: Dictionary = PlaceholderTiles.build(map.tiles(), biome.get("palette", {}))
	var tile_set: TileSet = built["tile_set"]
	atlas_coords = built["atlas_coords"]
	ground.tile_set = tile_set
	walls.tile_set = tile_set
	ground.clear()
	walls.clear()
	for y: int in map.height:
		for x: int in map.width:
			var cell := Vector2i(x, y)
			var tile: Dictionary = map.tile_at(cell)
			if tile.is_empty():
				continue
			var layer: TileMapLayer = walls if String(tile.get("layer", "ground")) == "wall" else ground
			layer.set_cell(cell, PlaceholderTiles.SOURCE_ID, atlas_coords[map.tile_id_at(cell)])
	nav.build(map)


## Centre of `cell` in global coordinates.
func cell_to_world(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return ground.local_to_map(ground.to_local(world_pos))


func is_walkable_world(world_pos: Vector2) -> bool:
	return map != null and map.is_walkable(world_to_cell(world_pos))


## World-space waypoints from the cell under `from_world` to `to_cell`,
## excluding the starting cell. Empty when unreachable.
func path_to(from_world: Vector2, to_cell: Vector2i) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var from := world_to_cell(from_world)
	for cell: Vector2i in nav.find_path(from, to_cell):
		if cell == from:
			continue
		points.append(cell_to_world(cell))
	return points


func _ensure_layers() -> void:
	if ground != null:
		return
	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.z_index = -1 # always beneath walls and actors, whatever Y-sort decides
	add_child(ground)
	walls = TileMapLayer.new()
	walls.name = "Walls"
	walls.y_sort_enabled = true
	add_child(walls)
