## The title screen: New game (then the death-stakes choice), Continue,
## Load, Settings, Quit. A cursor list like every other menu; the world
## runs the actions. Shown on a cold start, hidden for tests and CI.
class_name TitleMenu
extends CanvasLayer

const PAGE_MAIN := "main"
const PAGE_STAKES := "stakes"

var panel: PanelContainer
var title_label: Label
var label: Label
var cursor: int = 0
var page: String = PAGE_MAIN
var rows: Array[Dictionary] = [] # {"id", "label", "enabled", "why"}


func _ready() -> void:
	layer = 10
	panel = PanelContainer.new()
	panel.position = Vector2(560, 220)
	panel.size = Vector2(800, 640)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title_label = Label.new()
	title_label.text = "NEON WEAVE"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color(0.71, 0.55, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	visible = false


func show_rows(p_page: String, p_rows: Array[Dictionary]) -> void:
	page = p_page
	rows = p_rows
	cursor = 0
	if not rows.is_empty() and not bool(rows[0].get("enabled", true)):
		move(1)
	refresh()
	visible = true


func close() -> void:
	visible = false


func move(delta: int) -> int:
	if rows.is_empty():
		return cursor
	var i := cursor
	for _n: int in rows.size():
		i = posmod(i + delta, rows.size())
		if bool(rows[i].get("enabled", true)):
			cursor = i
			break
	refresh()
	return cursor


func selected_id() -> String:
	if rows.is_empty() or cursor < 0 or cursor >= rows.size():
		return ""
	return String(rows[cursor].get("id", ""))


func refresh() -> void:
	label.text = render(page, rows, cursor)


static func render(p_page: String, p_rows: Array[Dictionary], p_cursor: int) -> String:
	var lines: PackedStringArray = []
	lines.append("")
	if p_page == PAGE_STAKES:
		lines.append("Death-stakes. Choose how much the dice can take from you.")
		lines.append("")
	for i: int in p_rows.size():
		var row: Dictionary = p_rows[i]
		var marker := "▶ " if i == p_cursor else "   "
		var line := "%s%s" % [marker, row.get("label", row.get("id", "?"))]
		if not bool(row.get("enabled", true)):
			var why := String(row.get("why", ""))
			line += "  (%s)" % (why if not why.is_empty() else "unavailable")
		lines.append(line)
		var blurb := String(row.get("blurb", ""))
		if not blurb.is_empty():
			lines.append("      %s" % blurb)
	lines.append("")
	lines.append("↑↓ choose · %s confirm%s" % [Glyphs.key_and_pad("Enter", Glyphs.confirm()), "" if p_page == PAGE_MAIN else " · %s back" % Glyphs.key_and_pad("Esc", Glyphs.cancel())])
	return "\n".join(lines)
