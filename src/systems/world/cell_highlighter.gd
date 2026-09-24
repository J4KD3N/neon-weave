## Draws translucent diamonds over cells: reachable cells, targetable cells,
## a hovered cell. Child of [MapView] so it sits above the ground layer and
## below walls and actors.
class_name CellHighlighter
extends Node2D

var map_view: MapView
var _layers: Dictionary = {} # name -> {"cells": Array[Vector2i], "color": Color}
## The pad cursor glides between cells (S69): the e_cursor layer is drawn at
## `glide`, which slides toward the cell's centre at GLIDE_SPEED.
const GLIDE_SPEED := 900.0
var glide: Vector2 = Vector2.INF
var glide_target: Vector2 = Vector2.INF


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


## Sends the drawn cursor toward a cell: the first call lands it, later
## calls glide it (S69).
func glide_cursor_to(cell: Vector2i) -> void:
	if map_view == null:
		return
	glide_target = map_view.cell_to_world(cell)
	if glide == Vector2.INF:
		glide = glide_target
	queue_redraw()


func clear_glide() -> void:
	glide = Vector2.INF
	glide_target = Vector2.INF


func _process(delta: float) -> void:
	if glide == Vector2.INF or glide == glide_target:
		return
	glide = glide.move_toward(glide_target, GLIDE_SPEED * delta)
	queue_redraw()


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
			if layer_name == "e_cursor" and glide != Vector2.INF:
				c = to_local(glide) # the pad cursor on its way (S69)
			var poly := PackedVector2Array([c + Vector2(0, -15), c + Vector2(30, 0), c + Vector2(0, 15), c + Vector2(-30, 0)])
			draw_colored_polygon(poly, color)
			poly.append(poly[0])
			draw_polyline(poly, outline, 1.0)
