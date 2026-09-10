## The ending panel (S36): the ending the state machine resolved, the
## companions' fates, and the run in numbers. Enter / A / Esc returns to
## the title. Text-only like the other panels.
class_name EndingMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label


func _ready() -> void:
	layer = 9
	panel = PanelContainer.new()
	panel.position = Vector2(380, 120)
	panel.size = Vector2(1160, 780)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func show_text(text: String) -> void:
	label.text = text
	visible = true


func close() -> void:
	visible = false


## `ending`: the entry; `fates`: lines from Endings.fates; `stats` as DemoEndMenu.
static func render(ending: Dictionary, fates: Array[String], stats: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append(String(ending.get("name", "THE END")).to_upper())
	lines.append("")
	lines.append(String(ending.get("summary", "")))
	lines.append("")
	if not fates.is_empty():
		lines.append("Afterwards:")
		for f: String in fates:
			lines.append("  %s" % f)
		lines.append("")
	lines.append("Your run: party level %d · %d extractions · %d wipes · %d kills" % [int(stats.get("level", 1)), int(stats.get("runs", 0)), int(stats.get("wipes", 0)), int(stats.get("kills", 0))])
	lines.append(String(stats.get("standing", "")))
	lines.append("")
	lines.append("Enter / A / Esc: the title")
	return "\n".join(lines)
