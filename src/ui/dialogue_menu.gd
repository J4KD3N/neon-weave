## Conversation panel: speaker, line, numbered choices. Keys are routed by
## the world (1–4 choose, Esc takes the first exit choice). A cursor
## (↑↓ / D-pad, Enter / A) mirrors the number keys for pads.
class_name DialogueMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label
var runner: DialogueRunner
var speaker_names: Dictionary = {}
var cursor: int = 0


func _ready() -> void:
	layer = 8
	panel = PanelContainer.new()
	panel.position = Vector2(300, 620)
	panel.size = Vector2(1320, 400)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func open(p_runner: DialogueRunner, names: Dictionary) -> void:
	runner = p_runner
	speaker_names = names
	cursor = 0
	visible = true
	refresh()


func refresh() -> void:
	if runner == null or runner.finished:
		visible = false
		return
	cursor = clampi(cursor, 0, maxi(runner.available_choices().size() - 1, 0))
	label.text = render(runner, speaker_names, cursor)


## Moves the cursor over the available choices, wrapping.
func move(delta: int) -> int:
	if runner == null or runner.finished:
		return cursor
	var n := runner.available_choices().size()
	if n > 0:
		cursor = posmod(cursor + delta, n)
	refresh()
	return cursor


## A new node resets the cursor to its first choice.
func node_changed() -> void:
	cursor = 0
	refresh()


static func render(r: DialogueRunner, names: Dictionary, p_cursor: int = 0) -> String:
	var lines: PackedStringArray = []
	var who := String(names.get(r.speaker(), r.speaker().capitalize()))
	lines.append("%s: %s" % [who, r.text()])
	lines.append("")
	var options := r.available_choices()
	for i: int in options.size():
		var marker := "▶ " if i == p_cursor else "   "
		lines.append("%s[%d] %s" % [marker, i + 1, options[i].get("text", "")])
	if r.exit_choice() >= 0:
		lines.append("")
		lines.append("Esc leaves (B on a pad) · ↑↓ and Enter / A choose")
	return "\n".join(lines)
