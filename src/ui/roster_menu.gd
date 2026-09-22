## The Roster and the Quarters as one screen (S52, D-107): every companion
## the story has given you, walking or waiting or fallen, with their
## approval, loyalty and romance, a portrait of whoever the cursor is on,
## and under each the Quarters scenes they have to offer tonight. Left /
## right (or Enter on a companion) swaps walking and waiting; Enter on a
## scene plays it. Text like every other menu; the world builds the rows.
class_name RosterMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label
var portrait: TextureRect
var rows: Array[Dictionary] = [] # {"id", "kind": companion|scene|note, "label", "enabled", "why", "companion", "portrait"}
var cursor: int = 0


func _ready() -> void:
	layer = 7
	panel = PanelContainer.new()
	panel.position = Vector2(360, 100)
	panel.size = Vector2(1200, 820)
	add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	panel.add_child(box)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(192, 192)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(portrait)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	visible = false


func open(p_rows: Array[Dictionary], keep_cursor: bool = false) -> void:
	rows = p_rows
	if not keep_cursor:
		cursor = 0
	cursor = clampi(cursor, 0, maxi(rows.size() - 1, 0))
	if not rows.is_empty() and not bool(rows[cursor].get("enabled", true)):
		move(1)
	visible = true
	refresh()


func close() -> void:
	visible = false


## Steps the cursor over enabled rows, wrapping.
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


func selected() -> Dictionary:
	if rows.is_empty() or cursor < 0 or cursor >= rows.size():
		return {}
	return rows[cursor]


## The companion the cursor is on, or the one a scene row belongs to.
func selected_companion() -> String:
	return String(selected().get("companion", ""))


func refresh() -> void:
	label.text = render(rows, cursor)
	var face: Variant = null
	for i: int in range(cursor, -1, -1):
		if i < rows.size() and rows[i].get("portrait", null) != null and String(rows[i].get("companion", "")) == selected_companion():
			face = rows[i]["portrait"]
			break
	portrait.texture = face
	portrait.visible = face != null


static func render(p_rows: Array[Dictionary], p_cursor: int) -> String:
	var lines: PackedStringArray = []
	lines.append(Loc.t("ROSTER & QUARTERS"))
	lines.append("")
	for i: int in p_rows.size():
		var row: Dictionary = p_rows[i]
		var marker := "▶ " if i == p_cursor else "   "
		var line := "%s%s" % [marker, row.get("label", row.get("id", "?"))]
		if not bool(row.get("enabled", true)):
			var why := String(row.get("why", ""))
			line += Loc.t("  (%s)") % (why if not why.is_empty() else "unavailable")
		lines.append(line)
	lines.append("")
	lines.append(Loc.t("↑↓ choose · ←→ or Enter: walk with you / wait at the Bastion · Enter on a scene plays it · Esc / B close"))
	return "\n".join(lines)
