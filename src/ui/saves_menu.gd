## The saves screen (S54, D-109): one list for saving and one for loading,
## every slot with its title, when it was saved and what it holds, the
## autosave and its older copies on the load page, a thumbnail of the
## slot under the cursor, and a question before a slot is overwritten.
## Text like every other menu; the world builds the rows and acts.
class_name SavesMenu
extends CanvasLayer

const PAGE_SAVE := "save"
const PAGE_LOAD := "load"

var panel: PanelContainer
var label: Label
var thumbnail: TextureRect
var page: String = PAGE_SAVE
var rows: Array[Dictionary] = [] # {"id", "label", "detail", "enabled", "why", "exists", "thumbnail"}
var cursor: int = 0
var pending: String = "" # the row id waiting for "overwrite?" to be answered


func _ready() -> void:
	layer = 7
	panel = PanelContainer.new()
	panel.position = Vector2(360, 100)
	panel.size = Vector2(1200, 820)
	add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	panel.add_child(box)
	thumbnail = TextureRect.new()
	thumbnail.name = "Thumbnail"
	thumbnail.custom_minimum_size = Vector2(320, 180)
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(thumbnail)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	visible = false


func open(p_page: String, p_rows: Array[Dictionary], keep_cursor: bool = false) -> void:
	page = p_page
	rows = p_rows
	pending = ""
	if not keep_cursor:
		cursor = 0
	cursor = clampi(cursor, 0, maxi(rows.size() - 1, 0))
	if not rows.is_empty() and not bool(rows[cursor].get("enabled", true)):
		move(1)
	visible = true
	refresh()


func close() -> void:
	pending = ""
	visible = false


func move(delta: int) -> int:
	if rows.is_empty() or not pending.is_empty():
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


func refresh() -> void:
	label.text = render(page, rows, cursor, pending)
	var tex: Texture2D = null
	var path := String(selected().get("thumbnail", ""))
	if not path.is_empty() and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	thumbnail.texture = tex
	thumbnail.visible = tex != null


static func render(p_page: String, p_rows: Array[Dictionary], p_cursor: int, p_pending: String = "") -> String:
	var lines: PackedStringArray = []
	lines.append("SAVE GAME" if p_page == PAGE_SAVE else "LOAD GAME")
	lines.append("")
	for i: int in p_rows.size():
		var row: Dictionary = p_rows[i]
		var marker := "▶ " if i == p_cursor else "   "
		var line := "%s%s" % [marker, row.get("label", row.get("id", "?"))]
		if not bool(row.get("enabled", true)):
			var why := String(row.get("why", ""))
			line += "  (%s)" % (why if not why.is_empty() else "unavailable")
		lines.append(line)
		var detail := String(row.get("detail", ""))
		if not detail.is_empty():
			lines.append("      %s" % detail)
	lines.append("")
	if not p_pending.is_empty():
		var target := ""
		for row: Dictionary in p_rows:
			if String(row.get("id", "")) == p_pending:
				target = String(row.get("label", p_pending))
		lines.append("Overwrite %s? Enter / A overwrites · Esc / B keeps it" % target)
	elif p_page == PAGE_SAVE:
		lines.append("↑↓ choose · Enter / A saves here · Esc / B back")
	else:
		lines.append("↑↓ choose · Enter / A loads · Esc / B back")
	return "\n".join(lines)
