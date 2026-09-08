## The system menu (Start / Esc in exploration): every keyboard-only action
## as a cursor-navigable list, so a gamepad reaches all of them. Text-only
## for M1 like the other menus; the world builds the items and runs them.
class_name SystemMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label
var items: Array[Dictionary] = [] # {"id", "label", "enabled": bool, "why": String}
var cursor: int = 0


func _ready() -> void:
	layer = 7
	panel = PanelContainer.new()
	panel.position = Vector2(560, 180)
	panel.size = Vector2(800, 680)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func open(p_items: Array[Dictionary]) -> void:
	items = p_items
	cursor = 0
	if not items.is_empty() and not bool(items[0].get("enabled", true)):
		move(1)
	visible = true
	refresh()


func close() -> void:
	visible = false


## Steps the cursor over enabled items, wrapping. No enabled item: stays.
func move(delta: int) -> int:
	if items.is_empty():
		return cursor
	var i := cursor
	for _n: int in items.size():
		i = posmod(i + delta, items.size())
		if bool(items[i].get("enabled", true)):
			cursor = i
			break
	refresh()
	return cursor


func selected_id() -> String:
	if items.is_empty() or cursor < 0 or cursor >= items.size():
		return ""
	return String(items[cursor].get("id", ""))


func refresh() -> void:
	label.text = render(items, cursor)


static func render(p_items: Array[Dictionary], p_cursor: int) -> String:
	var lines: PackedStringArray = []
	lines.append("SYSTEM")
	lines.append("")
	for i: int in p_items.size():
		var item: Dictionary = p_items[i]
		var marker := "▶ " if i == p_cursor else "   "
		var line := "%s%s" % [marker, item.get("label", item.get("id", "?"))]
		if not bool(item.get("enabled", true)):
			var why := String(item.get("why", ""))
			line += "  (unavailable%s)" % ("" if why.is_empty() else ": " + why)
		lines.append(line)
	lines.append("")
	lines.append("↑↓ or D-pad choose · Enter or A confirm · Esc, B or Start close")
	return "\n".join(lines)
