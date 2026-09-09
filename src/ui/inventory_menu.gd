## The pack and equipment screen (I at home, or the system menu): one
## member at a time (←→ / D-pad), their slots with what is in them, the
## banked pack, and what the Workshop can craft. Text-only like the other
## menus; the world builds the rows and runs the actions.
class_name InventoryMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label
var cursor: int = 0
var member_index: int = 0
## Rows built by the world: [{"kind": "slot"|"item"|"craft", "id", "label", "enabled": bool, "why"}]
var rows: Array[Dictionary] = []


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
	lines.append("THE PACK")
	lines.append(header)
	lines.append("")
	var last_kind := ""
	for i: int in p_rows.size():
		var row: Dictionary = p_rows[i]
		var kind := String(row.get("kind", ""))
		if kind != last_kind:
			lines.append({"slot": "Equipped (Enter unequips)", "item": "Pack (Enter equips)", "craft": "Workshop (Salvage)"}.get(kind, kind.capitalize()))
			last_kind = kind
		var marker := "▶ " if i == p_cursor else "   "
		var line := "%s%s" % [marker, row.get("label", row.get("id", "?"))]
		if not bool(row.get("enabled", true)):
			var why := String(row.get("why", ""))
			line += "  (%s)" % (why if not why.is_empty() else "unavailable")
		lines.append(line)
	lines.append("")
	lines.append("←→ / D-pad member · ↑↓ choose · Enter / A confirm · Esc / B / I close")
	return "\n".join(lines)
