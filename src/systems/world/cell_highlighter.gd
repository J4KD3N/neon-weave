## Draws translucent diamonds over cells: reachable cells, targetable cells,
## a hovered cell. Child of [MapView] so it sits above the ground layer and
## below walls and actors.
class_name CellHighlighter
extends Node2D

var map_view: MapView
var _layers: Dictionary = {} # name -> {"cells": Array[Vector2i], "color": Color}


func set_layer(layer_name: String, cells: Array[Vector2i], color: Color) -> void:
	var copy: Array[Vector2i] = []
	copy.assign(cells)
	_layers[layer_name] = {"cells": copy, "color": color}
	queue_redraw()


func clear_layer(layer_name: String) -> void:
	if _layers.erase(layer_name):
		queue_redraw()


func clear_all() -> void:
	_layers.clear()
	queue_redraw()


func cells_in(layer_name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _layers.has(layer_name):
		var layer: Dictionary = _layers[layer_name]
		out.assign(layer["cells"])
	return out


func _draw() -> void:
	if map_view == null:
		return
	var names: Array = _layers.keys()
	names.sort()
	for layer_name: String in names:
		var layer: Dictionary = _layers[layer_name]
		var color: Color = layer["color"]
		var outline := Color(color.r, color.g, color.b, minf(color.a * 2.5, 0.9))
		for cell: Vector2i in layer["cells"]:
			var c := to_local(map_view.cell_to_world(cell))
			var poly := PackedVector2Array([c + Vector2(0, -15), c + Vector2(30, 0), c + Vector2(0, 15), c + Vector2(-30, 0)])
			draw_colored_polygon(poly, color)
			poly.append(poly[0])
			draw_polyline(poly, outline, 1.0)
