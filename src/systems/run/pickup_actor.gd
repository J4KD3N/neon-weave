## A collectible lying on a cell: a glowing diamond hovering in the pickup's
## colour. Walking any party member onto it collects it.
##
## The diamond floats above wall-top height (a 32 px block directly in front
## on screen covers up to 16 px above the cell centre), so it stays visible
## behind walls, and it bobs so it reads as an item rather than terrain.
class_name PickupActor
extends Node2D

const HOVER := 30.0
const BOB := 3.0

var pickup_id: String = ""
var entry: Dictionary = {}
var cell: Vector2i = Vector2i.ZERO
var tint: Color = Color.WHITE
var collected: bool = false

var _time: float = 0.0


func setup(p_id: String, p_entry: Dictionary, p_cell: Vector2i) -> void:
	pickup_id = p_id
	entry = p_entry
	cell = p_cell
	name = "%s_%d_%d" % [p_id, p_cell.x, p_cell.y]
	var art: Dictionary = entry.get("art", {})
	tint = Color.html(String(art.get("color", "#ffffff")))
	_time = float(p_cell.x * 7 + p_cell.y * 13) * 0.37 # desynchronise the bob
	queue_redraw()


## Rarity from the placement ("common" by default): tints the gem and
## multiplies the grants (rules/loot).
var rarity: String = "common"


func set_rarity(p_rarity: String, color: Color) -> void:
	rarity = p_rarity
	if color.a > 0.0:
		tint = color
	queue_redraw()


func grants() -> Dictionary:
	return entry.get("grants", {})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var lift := HOVER + sin(_time * 2.4) * BOB
	var c := Vector2(0, -lift)
	# Ground shadow and a faint beam so the item reads as belonging to its cell.
	draw_colored_polygon(PackedVector2Array([Vector2(0, -5), Vector2(12, 0), Vector2(0, 5), Vector2(-12, 0)]), Color(0, 0, 0, 0.35))
	draw_line(Vector2(0, -2), c + Vector2(0, 8), Color(tint.r, tint.g, tint.b, 0.35), 1.0)
	# Glow halo and the gem.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -16), c + Vector2(20, 0), c + Vector2(0, 16), c + Vector2(-20, 0)]), Color(tint.r, tint.g, tint.b, 0.22))
	var gem := PackedVector2Array([c + Vector2(0, -9), c + Vector2(8, 0), c + Vector2(0, 9), c + Vector2(-8, 0)])
	draw_colored_polygon(gem, tint)
	gem.append(gem[0])
	draw_polyline(gem, tint.lightened(0.55), 1.0)
