## The Archive reading room (S35): every lore fragment in the order the
## history runs, the found ones readable, the missing ones as gaps in the
## record. Text-only like the journal; the world builds the entries.
class_name ArchiveMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label


func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.position = Vector2(300, 80)
	panel.size = Vector2(1320, 880)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color(0.93, 0.9, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func show_text(text: String) -> void:
	label.text = text
	visible = true


func close() -> void:
	visible = false


## `entries`: [{"name", "order", "source", "text", "found": bool}] sorted by order.
static func render(entries: Array[Dictionary], level: int) -> String:
	var lines: PackedStringArray = []
	var found := 0
	for e: Dictionary in entries:
		if bool(e.get("found", false)):
			found += 1
	lines.append("THE ARCHIVE — %d of %d fragments" % [found, entries.size()])
	if level <= 0:
		lines.append("The reading room is sealed. Raise the Archive and the Archivist will read what you bring back.")
	elif found == 0:
		lines.append("Nothing on the shelves yet. Fragments turn up in the Shards.")
	lines.append("")
	for e: Dictionary in entries:
		if bool(e.get("found", false)) and level > 0:
			lines.append("%d. %s  (%s)" % [int(e.get("order", 0)), e.get("name", "?"), e.get("source", "")])
			lines.append("   %s" % String(e.get("text", "")))
		else:
			lines.append("%d. — a gap in the record —" % int(e.get("order", 0)))
		lines.append("")
	lines.append("Esc / B close")
	return "\n".join(lines)
