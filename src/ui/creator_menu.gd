## Character creator screen: a text panel driven by [CreatorState], a name
## field, a paper-doll preview of the chosen race/class/appearance and a
## placeholder portrait on the same rig (S51). Keys are handled by the
## world; this only renders and edits the name.
class_name CreatorMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label
var name_edit: LineEdit
var preview: WorldActor
var portrait: TextureRect
var state: CreatorState


func _ready() -> void:
	layer = 7
	panel = PanelContainer.new()
	panel.position = Vector2(260, 90)
	panel.size = Vector2(1400, 860)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_edit.max_length = CharacterSheet.MAX_NAME
	name_edit.custom_minimum_size = Vector2(420, 40)
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(func(_text: String) -> void:
		if state != null:
			state.move_row(1)
			refresh())
	box.add_child(name_edit)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.position = Vector2(1420, 120)
	portrait.custom_minimum_size = Vector2(192, 192)
	portrait.size = Vector2(192, 192)
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(portrait)
	visible = false


func open(p_state: CreatorState) -> void:
	state = p_state
	name_edit.text = state.sheet.name
	visible = true
	refresh()


func refresh() -> void:
	if state == null:
		return
	label.text = state.render()
	var wants_focus := state.current_row() == CreatorState.ROW_NAME
	if wants_focus and not name_edit.has_focus():
		name_edit.grab_focus()
	elif not wants_focus and name_edit.has_focus():
		name_edit.release_focus()
	_refresh_preview()


func _refresh_preview() -> void:
	if preview != null:
		preview.queue_free()
		preview = null
	if state == null or state._registry == null:
		return
	var race := state._registry.get_entry("races", state.sheet.race_id)
	var color := PartyBuilder.class_color(state._registry, state.sheet.class_id)
	var overlay: Dictionary = race.get("overlay", {})
	var appearance := state.appearance_colors()
	preview = WorldActor.new()
	preview.position = Vector2(1560, 430)
	preview.scale = Vector2(4, 4)
	preview.build_visuals(state.sheet.name, color, "capsule", overlay, null, appearance)
	add_child(preview)
	portrait.texture = PlaceholderActorArt.portrait_texture(color, overlay, appearance)


func _on_name_changed(text: String) -> void:
	if state == null:
		return
	state.sheet.name = text
	label.text = state.render()
