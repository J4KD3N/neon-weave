## The journal (J, or the system menu): every quest the party has started,
## its current stage, and the stage's objectives ticked off against the
## narrative state. Read-only; Esc / B closes.
class_name JournalMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label


func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.position = Vector2(360, 100)
	panel.size = Vector2(1200, 820)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func show_text(text: String) -> void:
	label.text = text
	visible = true


func close() -> void:
	visible = false


## Pure render. `entries`: [{"name", "main": bool, "stage_summary",
## "complete": bool, "objectives": [{"text", "done": bool}]}]
static func render(entries: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	lines.append("JOURNAL")
	lines.append("")
	if entries.is_empty():
		lines.append("Nothing yet. Talk to people; walk east.")
	var active: Array[Dictionary] = []
	var finished: Array[Dictionary] = []
	for e: Dictionary in entries:
		if bool(e.get("complete", false)):
			finished.append(e)
		else:
			active.append(e)
	for e: Dictionary in active:
		lines.append("%s%s" % ["★ " if bool(e.get("main", false)) else "• ", e.get("name", "?")])
		lines.append("   %s" % e.get("stage_summary", ""))
		for o: Dictionary in e.get("objectives", []):
			lines.append("   %s %s" % ["✓" if bool(o.get("done", false)) else "·", o.get("text", "")])
		lines.append("")
	if not finished.is_empty():
		lines.append("Done")
		for e: Dictionary in finished:
			lines.append("   ✓ %s — %s" % [e.get("name", "?"), e.get("stage_summary", "")])
		lines.append("")
	lines.append("Esc / B / J close")
	return "\n".join(lines)
