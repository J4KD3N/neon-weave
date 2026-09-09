## A Bastion building standing on the home map: an isometric block that
## grows a storey per level, with the building name and level over it.
## Placed from the map entry's `buildings` list; refreshed on upgrades.
class_name BuildingActor
extends Node2D

const BASE_HEIGHT := 14
const STOREY := 10
const HALF_W := 30
const HALF_H := 15

var building_id: String = ""
var display_name: String = ""
var level: int = 0
var max_level: int = 0
var cell: Vector2i = Vector2i.ZERO
var color: Color = Color(0.55, 0.5, 0.65)
var label: Label


func setup(p_id: String, p_name: String, p_cell: Vector2i, p_color: Color) -> void:
	building_id = p_id
	display_name = p_name
	cell = p_cell
	color = p_color
	name = "building_%s" % p_id
	label = Label.new()
	label.position = Vector2(-70, -BASE_HEIGHT - 40)
	label.size = Vector2(140, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	set_level(0, 0)


func set_level(p_level: int, p_max: int) -> void:
	level = p_level
	max_level = p_max
	label.text = "%s L%d/%d" % [display_name, level, max_level]
	label.position.y = -height() - 40
	queue_redraw()


func height() -> int:
	return BASE_HEIGHT + STOREY * level


func _draw() -> void:
	var h := float(height())
	var top := Color(color.r, color.g, color.b, 1.0).lightened(0.15 * level)
	var left := color.darkened(0.45)
	var right := color.darkened(0.25)
	var o := Vector2(0, 0)
	var diamond := PackedVector2Array([o + Vector2(0, -HALF_H - h), o + Vector2(HALF_W, -h), o + Vector2(0, HALF_H - h), o + Vector2(-HALF_W, -h)])
	draw_colored_polygon(PackedVector2Array([o + Vector2(-HALF_W, -h), o + Vector2(0, HALF_H - h), o + Vector2(0, HALF_H), o + Vector2(-HALF_W, 0)]), left)
	draw_colored_polygon(PackedVector2Array([o + Vector2(0, HALF_H - h), o + Vector2(HALF_W, -h), o + Vector2(HALF_W, 0), o + Vector2(0, HALF_H)]), right)
	draw_colored_polygon(diamond, top)
	for storey: int in level:
		var y := -float(BASE_HEIGHT + STOREY * storey) - 2.0
		draw_line(o + Vector2(-HALF_W, y), o + Vector2(0, y + HALF_H), Color(0, 0, 0, 0.35), 1.0)
		draw_line(o + Vector2(0, y + HALF_H), o + Vector2(HALF_W, y), Color(0, 0, 0, 0.35), 1.0)
	if level >= max_level and max_level > 0:
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(1.0, 0.9, 0.5, 0.9), 1.5)
