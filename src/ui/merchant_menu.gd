## A Shard merchant's stock (`merchants` content kind): rows with costs paid
## from the banked ledger, cursor + Enter / A like the other text menus.
class_name MerchantMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label
var cursor: int = 0
var rows: Array[Dictionary] = [] # {"id", "label", "enabled": bool, "why"}


func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.position = Vector2(460, 200)
	panel.size = Vector2(1000, 600)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func show_rows(header: String, p_rows: Array[Dictionary]) -> void:
	rows = p_rows
	cursor = clampi(cursor, 0, maxi(rows.size() - 1, 0))
	label.text = render(header, rows, cursor)
	visible = true


func close() -> void:
	visible = false


func move(delta: int) -> int:
	if not rows.is_empty():
		cursor = posmod(cursor + delta, rows.size())
	return cursor


func selected() -> Dictionary:
	if rows.is_empty() or cursor < 0 or cursor >= rows.size():
		return {}
	return rows[cursor]


static func render(header: String, p_rows: Array[Dictionary], p_cursor: int) -> String:
	var lines: PackedStringArray = []
	lines.append(header)
	lines.append("")
	for i: int in p_rows.size():
		var row: Dictionary = p_rows[i]
		var marker := "▶ " if i == p_cursor else "   "
		var line := "%s%s" % [marker, row.get("label", row.get("id", "?"))]
		if not bool(row.get("enabled", true)):
			line += "  (%s)" % String(row.get("why", "unavailable"))
		lines.append(line)
	lines.append("")
	lines.append("↑↓ choose · Enter / A buy · Esc / B leave")
	return "\n".join(lines)
