## Anything that stands on a cell with placeholder visuals: party members and
## enemies. Position is the feet. Draws the leader ring and an HP bar.
class_name WorldActor
extends Node2D

var display_name: String = ""
var tint: Color = Color.WHITE
var max_hp: int = 1
var hp: int = 1:
	set(value):
		hp = clampi(value, 0, maxi(max_hp, 1))
		queue_redraw()
var show_hp: bool = false:
	set(value):
		show_hp = value
		queue_redraw()
var is_leader: bool = false:
	set(value):
		is_leader = value
		queue_redraw()
var downed: bool = false:
	set(value):
		downed = value
		modulate = Color(0.45, 0.45, 0.5, 0.9) if value else Color.WHITE
		queue_redraw()
## Set when the actor has been removed from play (dead enemy).
var dead: bool = false


func build_visuals(text: String, color: Color, shape: String = "capsule") -> void:
	display_name = text
	tint = color

	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = PlaceholderActorArt.shadow_texture()
	add_child(shadow)

	var body := Sprite2D.new()
	body.name = "Body"
	body.texture = PlaceholderActorArt.body_texture(color, shape)
	body.offset = Vector2(0, -PlaceholderActorArt.BODY_SIZE.y / 2.0)
	add_child(body)

	var label := Label.new()
	label.name = "Name"
	label.text = text
	label.position = Vector2(-48, -PlaceholderActorArt.BODY_SIZE.y - 20)
	label.size = Vector2(96, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color.lightened(0.4))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _draw() -> void:
	if is_leader:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 40, tint, 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_hp and max_hp > 0:
		var top := -PlaceholderActorArt.BODY_SIZE.y - 4.0
		var frac := float(hp) / float(max_hp)
		draw_rect(Rect2(-16, top, 32, 4), Color(0, 0, 0, 0.7))
		var bar := Color(0.25, 0.9, 0.45) if frac > 0.5 else (Color(0.95, 0.75, 0.2) if frac > 0.25 else Color(0.95, 0.25, 0.25))
		draw_rect(Rect2(-16, top, 32.0 * frac, 4), bar)
