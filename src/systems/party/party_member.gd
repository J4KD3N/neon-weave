## One party member in the world. Position is the feet (cell centre when
## standing on a cell). Visuals are placeholder art tinted by class branch.
class_name PartyMember
extends Node2D

var member_id: String = ""
var display_name: String = ""
var class_id: String = ""
var race_id: String = ""
var tint: Color = Color.WHITE
var facing: Vector2 = Vector2.DOWN
var is_leader: bool = false:
	set(value):
		is_leader = value
		queue_redraw()


func setup(data: Dictionary, color: Color) -> void:
	member_id = String(data.get("id", ""))
	display_name = String(data.get("name", member_id))
	class_id = String(data.get("class", ""))
	race_id = String(data.get("race", ""))
	tint = color
	name = member_id if not member_id.is_empty() else "Member"

	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = PlaceholderActorArt.shadow_texture()
	add_child(shadow)

	var body := Sprite2D.new()
	body.name = "Body"
	body.texture = PlaceholderActorArt.body_texture(color)
	body.offset = Vector2(0, -PlaceholderActorArt.BODY_SIZE.y / 2.0)
	add_child(body)

	var label := Label.new()
	label.name = "Name"
	label.text = display_name
	label.position = Vector2(-48, -PlaceholderActorArt.BODY_SIZE.y - 20)
	label.size = Vector2(96, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color.lightened(0.4))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _draw() -> void:
	if not is_leader:
		return
	# A flattened neon ring under the leader's feet.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 40, tint, 2.0, true)
