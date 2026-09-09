## Settings: fullscreen, master volume, pad glyphs, and rebinding of every
## rebindable action (press the new key or button; Esc keeps the old one).
## Left / right adjust values; Enter / A toggles or starts a rebind.
class_name SettingsMenu
extends CanvasLayer

## Actions a player may rebind; movement and ui_* stay fixed.
const REBINDABLE: Array[String] = ["confirm", "cancel", "menu", "end_turn", "next_member", "ability_1", "ability_2", "ability_3", "ability_4", "journal", "weave", "bastion", "creator", "new_shard", "go_home", "extract", "quick_save", "quick_load", "load_autosave"]

var panel: PanelContainer
var label: Label
var cursor: int = 0
var rows: Array[Dictionary] = [] # {"id", "label", "kind": "toggle"|"value"|"rebind"|"action"}
var rebinding: String = "" # action currently waiting for a new event


func _ready() -> void:
	layer = 10
	panel = PanelContainer.new()
	panel.position = Vector2(360, 100)
	panel.size = Vector2(1200, 860)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func show_rows(p_rows: Array[Dictionary]) -> void:
	rows = p_rows
	cursor = clampi(cursor, 0, maxi(rows.size() - 1, 0))
	refresh()
	visible = true


func close() -> void:
	rebinding = ""
	visible = false


func move(delta: int) -> int:
	if not rows.is_empty():
		cursor = posmod(cursor + delta, rows.size())
	refresh()
	return cursor


func selected() -> Dictionary:
	if rows.is_empty() or cursor < 0 or cursor >= rows.size():
		return {}
	return rows[cursor]


func refresh() -> void:
	label.text = render(rows, cursor, rebinding)


## Builds the rows from live settings and bindings (pure; the world calls it).
static func build_rows(settings: Settings) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"id": "fullscreen", "kind": "toggle", "label": "Fullscreen: %s" % ("on" if settings.fullscreen else "off")})
	out.append({"id": "volume", "kind": "value", "label": "Master volume: %d%%" % settings.volume_percent()})
	out.append({"id": "glyphs", "kind": "value", "label": "Pad glyphs: %s%s" % [settings.glyphs, "" if settings.glyphs != "auto" else " (%s)" % Glyphs.resolved_style()]})
	for action: String in REBINDABLE:
		out.append({"id": "rebind:" + action, "kind": "rebind", "label": "%s: %s" % [action.replace("_", " "), InputActions.describe(action)]})
	out.append({"id": "reset", "kind": "action", "label": "Reset all bindings to default"})
	out.append({"id": "back", "kind": "action", "label": "Back"})
	return out


static func render(p_rows: Array[Dictionary], p_cursor: int, p_rebinding: String) -> String:
	var lines: PackedStringArray = []
	lines.append("SETTINGS")
	lines.append("")
	if not p_rebinding.is_empty():
		lines.append("Press the new key or pad button for %s (Esc keeps the current one)" % p_rebinding.replace("_", " "))
		lines.append("")
	var last_kind := ""
	for i: int in p_rows.size():
		var row: Dictionary = p_rows[i]
		var kind := String(row.get("kind", ""))
		if kind == "rebind" and last_kind != "rebind":
			lines.append("Bindings")
		last_kind = kind
		var marker := "▶ " if i == p_cursor else "   "
		lines.append("%s%s" % [marker, row.get("label", row.get("id", "?"))])
	lines.append("")
	lines.append("↑↓ choose · ←→ adjust · %s toggle or rebind · %s back" % [Glyphs.key_and_pad("Enter", Glyphs.confirm()), Glyphs.key_and_pad("Esc", Glyphs.cancel())])
	return "\n".join(lines)
