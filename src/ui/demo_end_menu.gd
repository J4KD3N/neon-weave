## The demo boundary: shown once when `rules/demo.end_flag` is set. A
## thank-you, the run in numbers, and Enter / A / Esc back to the Bastion.
class_name DemoEndMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label


func _ready() -> void:
	layer = 9
	panel = PanelContainer.new()
	panel.position = Vector2(420, 160)
	panel.size = Vector2(1080, 700)
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


## `stats`: {"level", "runs", "wipes", "kills", "companions": [names], "standing": text, "choice": text}
static func render(stats: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("THE WAKING — END OF THE DEMO")
	lines.append("")
	lines.append("It knew your name. The Waking goes on from here: the second and third depths, the Verdant Datacore, the Loom, and the choice the Sundering never finished making.")
	lines.append("")
	lines.append("Your run: party level %d · %d extractions · %d wipes · %d kills" % [int(stats.get("level", 1)), int(stats.get("runs", 0)), int(stats.get("wipes", 0)), int(stats.get("kills", 0))])
	var companions: Array = stats.get("companions", [])
	lines.append("Walking with you: %s" % (", ".join(PackedStringArray(companions)) if not companions.is_empty() else "nobody, which is its own kind of story"))
	lines.append(String(stats.get("standing", "")))
	if stats.has("choice"):
		lines.append(String(stats["choice"]))
	lines.append("")
	lines.append("Thank you for playing. Neon Weave is open source: the whole demo is data you can read and change.")
	lines.append("")
	lines.append("Enter / A / Esc: back to the Bastion")
	return "\n".join(lines)
