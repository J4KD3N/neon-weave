## A collectible lying on a cell: a glowing diamond drawn in the pickup's
## colour. Walking any party member onto it collects it.
class_name PickupActor
extends Node2D

var pickup_id: String = ""
var entry: Dictionary = {}
var cell: Vector2i = Vector2i.ZERO
var tint: Color = Color.WHITE
var collected: bool = false


func setup(p_id: String, p_entry: Dictionary, p_cell: Vector2i) -> void:
	pickup_id = p_id
	entry = p_entry
	cell = p_cell
	name = "%s_%d_%d" % [p_id, p_cell.x, p_cell.y]
	var art: Dictionary = entry.get("art", {})
	tint = Color.html(String(art.get("color", "#ffffff")))
	queue_redraw()


func grants() -> Dictionary:
	return entry.get("grants", {})


func _draw() -> void:
	var glow := Color(tint.r, tint.g, tint.b, 0.25)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -12), Vector2(16, 0), Vector2(0, 12), Vector2(-16, 0)]), glow)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -16), Vector2(8, -8), Vector2(0, 0), Vector2(-8, -8)]), tint)
	draw_polyline(PackedVector2Array([Vector2(0, -16), Vector2(8, -8), Vector2(0, 0), Vector2(-8, -8), Vector2(0, -16)]), tint.lightened(0.5), 1.0)
