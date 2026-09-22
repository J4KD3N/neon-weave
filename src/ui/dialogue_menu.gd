## Conversation panel: a face, the last few lines of this talk, the
## speaker's line, numbered choices. Keys are routed by the world (1–4
## choose, Esc takes the first exit choice). A cursor (↑↓ / D-pad, Enter /
## A) mirrors the number keys for pads. The face and the history come from
## the world through callables (S52), so the panel stays a renderer.
class_name DialogueMenu
extends CanvasLayer

const HISTORY_LINES := 3

var panel: PanelContainer
var label: Label
var portrait: TextureRect
var runner: DialogueRunner
var speaker_names: Dictionary = {}
var faces: Callable
var history: Callable
var cursor: int = 0


func _ready() -> void:
	layer = 8
	panel = PanelContainer.new()
	panel.position = Vector2(300, 620)
	panel.size = Vector2(1320, 400)
	add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(192, 192)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(portrait)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	visible = false


## `p_faces` takes (speaker, voice) and returns a Texture2D or null;
## `p_history` returns the lines of this talk so far ([{"who", "text"}]).
func open(p_runner: DialogueRunner, names: Dictionary, p_faces: Callable = Callable(), p_history: Callable = Callable()) -> void:
	runner = p_runner
	speaker_names = names
	faces = p_faces
	history = p_history
	cursor = 0
	visible = true
	refresh()


func refresh() -> void:
	if runner == null or runner.finished:
		visible = false
		return
	cursor = clampi(cursor, 0, maxi(runner.available_choices().size() - 1, 0))
	var past: Array[Dictionary] = []
	if history.is_valid():
		past.assign(history.call())
	label.text = render(runner, speaker_names, cursor, past)
	var face: Variant = faces.call(runner.speaker(), runner.voice()) if faces.is_valid() else null
	portrait.texture = face
	portrait.visible = face != null


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


static func render(r: DialogueRunner, names: Dictionary, p_cursor: int = 0, past: Array[Dictionary] = []) -> String:
	var lines: PackedStringArray = []
	var start := maxi(past.size() - HISTORY_LINES, 0)
	for i: int in range(start, past.size()):
		lines.append("  ‹ %s: %s" % [past[i].get("who", "?"), past[i].get("text", "")])
	if not past.is_empty():
		lines.append("")
	var who := String(names.get(r.speaker(), r.speaker().capitalize()))
	if not r.voice().is_empty():
		who = "%s, in %s's voice" % [who, String(names.get(r.voice(), r.voice().capitalize()))]
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
