## A parsed, validated map: an ASCII grid whose characters map, via the
## entry's `legend`, to tile ids from the `tiles` content kind.
##
## Entry shape (content/maps/<id>.json):
##   { "name": "...", "biome": "<biome id>", "spawn_marker": "P",
##     "legend": { ".": "floor_concrete", "#": "wall_rust" },
##     "rows": [ "####", "#P.#", "####" ] }
class_name MapData
extends RefCounted

var id: String = ""
var name: String = ""
var biome_id: String = ""
var width: int = 0
var height: int = 0
## Validation problems. A map with errors still loads what it can.
var errors: Array[String] = []

var _cells: Array[String] = [] # row-major tile id per cell ("" when invalid)
var _tiles: Dictionary = {} # tile id -> tile entry, only ids the map uses
var _spawns: Array[Vector2i] = []


## Builds a MapData from a content entry and the available tile entries
## (tile id -> entry). Never throws; check [member errors].
static func parse(entry: Dictionary, tiles_by_id: Dictionary) -> MapData:
	var map := MapData.new()
	map.id = String(entry.get("id", ""))
	map.name = String(entry.get("name", map.id))
	map.biome_id = String(entry.get("biome", ""))
	var legend: Dictionary = entry.get("legend", {})
	var rows: Array = entry.get("rows", [])
	var spawn_marker: String = String(entry.get("spawn_marker", "P"))
	if rows.is_empty():
		map.errors.append("map '%s' has no rows" % map.id)
		return map
	map.height = rows.size()
	map.width = String(rows[0]).length()
	for y: int in map.height:
		var row: String = String(rows[y])
		if row.length() != map.width:
			map.errors.append("map '%s' row %d has length %d, expected %d" % [map.id, y, row.length(), map.width])
		for x: int in map.width:
			var ch: String = row[x] if x < row.length() else ""
			var tile_id: String = String(legend.get(ch, ""))
			if ch.is_empty():
				pass # already reported as a short row
			elif tile_id.is_empty():
				map.errors.append("map '%s' cell (%d,%d): '%s' is not in the legend" % [map.id, x, y, ch])
			elif not tiles_by_id.has(tile_id):
				map.errors.append("map '%s' cell (%d,%d): unknown tile '%s'" % [map.id, x, y, tile_id])
				tile_id = ""
			else:
				map._tiles[tile_id] = tiles_by_id[tile_id]
			map._cells.append(tile_id)
			if ch == spawn_marker:
				map._spawns.append(Vector2i(x, y))
	if map._spawns.is_empty():
		map.errors.append("map '%s' has no spawn marker '%s'" % [map.id, spawn_marker])
	return map


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func tile_id_at(cell: Vector2i) -> String:
	if not in_bounds(cell):
		return ""
	return _cells[cell.y * width + cell.x]


func tile_at(cell: Vector2i) -> Dictionary:
	return _tiles.get(tile_id_at(cell), {})


func is_walkable(cell: Vector2i) -> bool:
	var tile: Dictionary = tile_at(cell)
	return not tile.is_empty() and bool(tile.get("walkable", false))


## Spawn cells in reading order (top-left to bottom-right).
func spawn_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_spawns)
	return out


## The tile entries this map uses, sorted by id.
func tiles() -> Array[Dictionary]:
	var ids: Array = _tiles.keys()
	ids.sort()
	var out: Array[Dictionary] = []
	for tile_id: String in ids:
		out.append(_tiles[tile_id])
	return out


func walkable_count() -> int:
	var n := 0
	for y: int in height:
		for x: int in width:
			if is_walkable(Vector2i(x, y)):
				n += 1
	return n
