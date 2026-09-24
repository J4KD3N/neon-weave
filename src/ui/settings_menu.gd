## Settings: fullscreen, master volume, pad glyphs, pad rumble, text size
## (S53), and rebinding of every
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


## Builds the rows from live settings and bindings (pure; the world calls
## it). Rows carry a section and a hint (S54): the screen groups them and
## says what the row under the cursor does.
static func build_rows(settings: Settings) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"id": "fullscreen", "kind": "toggle", "section": "Display", "label": Loc.t("Fullscreen: %s") % (Loc.t("on") if settings.fullscreen else Loc.t("off")), "hint": Loc.t("Enter or A switches between a window and the whole screen.")})
	out.append({"id": "text_scale", "kind": "value", "section": "Display", "label": Loc.t("Text size: %s") % Loc.t(settings.text_scale_name()), "hint": Loc.t("Left and right grow or shrink every menu's text. Deck is for a 1280×800 screen.")})
	out.append({"id": "palette", "kind": "value", "section": "Display", "label": Loc.t("Colour-blind palette: %s") % Loc.t(settings.palette), "hint": Loc.t("Left and right pick a filter that keeps reds, greens or blues apart for protanopia, deuteranopia or tritanopia.")})
	out.append({"id": "lighting", "kind": "toggle", "section": "Display", "label": Loc.t("Lighting: %s") % (Loc.t("on") if settings.lighting else Loc.t("off")), "hint": Loc.t("Neon that lights the ground around it and a dim world between. Off is flat and a little faster.")})
	out.append({"id": "screen_fx", "kind": "value", "section": "Display", "label": Loc.t("Screen effects: %s") % Loc.t(settings.screen_fx), "hint": Loc.t("Glow bleeds bright pixels into their neighbours; CRT adds scanlines and a vignette on top; off draws the frame as it is.")})
	out.append({"id": "gore", "kind": "value", "section": "Display", "label": Loc.t("Gore: %s") % Loc.t(settings.gore), "hint": Loc.t("Full leaves blood where it lands and the fallen where they fell; low keeps the fallen and little blood; off cleans every fight away.")})
	out.append({"id": "language", "kind": "value", "section": "Display", "label": Loc.t("Language: %s") % Loc.t(Loc.name_of(settings.locale)), "hint": Loc.t("Left and right pick a language the game has a table for. Pseudo is for testing that every string comes through.")})
	out.append({"id": "volume", "kind": "value", "section": "Audio", "label": Loc.t("Master volume: %d%%") % settings.volume_percent(), "hint": Loc.t("Left and right, in steps. Everything the game plays.")})
	out.append({"id": "music", "kind": "value", "section": "Audio", "label": Loc.t("Music: %d%%") % Settings.percent_of(settings.music_db), "hint": Loc.t("The music on its own.")})
	out.append({"id": "sfx", "kind": "value", "section": "Audio", "label": Loc.t("Sound effects: %d%%") % Settings.percent_of(settings.sfx_db), "hint": Loc.t("Hits, steps, pickups and the menus on their own.")})
	out.append({"id": "glyphs", "kind": "value", "section": "Pad", "label": Loc.t("Pad glyphs: %s%s") % [Loc.t(settings.glyphs), "" if settings.glyphs != "auto" else Loc.t(" (%s)") % Loc.t(Glyphs.resolved_style())], "hint": Loc.t("Which button names the hints use. Auto follows the pad plugged in.")})
	out.append({"id": "rumble", "kind": "toggle", "section": "Pad", "label": Loc.t("Pad rumble: %s") % (Loc.t("on") if settings.rumble else Loc.t("off")), "hint": Loc.t("Hits, downs, wins and wipes in the pad. Enter or A switches it and gives one pulse.")})
	out.append({"id": "autosaves_kept", "kind": "value", "section": "Saves", "label": Loc.t("Autosaves kept: %d") % settings.autosaves_kept, "hint": Loc.t("How many older autosaves stay beside the newest, one to five. Iron Weave keeps one whatever this says.")})
	for action: String in REBINDABLE:
		out.append({"id": "rebind:" + action, "kind": "rebind", "section": "Bindings", "label": Loc.t("%s: %s") % [Loc.t(action.replace("_", " ")), InputActions.describe(action)], "hint": Loc.t("Enter or A, then press the new key or button. Esc keeps the old one.")})
	out.append({"id": "reset", "kind": "action", "section": "Bindings", "label": Loc.t("Reset all bindings to default"), "hint": Loc.t("Every binding back to how the game shipped.")})
	out.append({"id": "back", "kind": "action", "section": "", "label": Loc.t("Back"), "hint": Loc.t("Settings are saved when you leave.")})
	return out


static func render(p_rows: Array[Dictionary], p_cursor: int, p_rebinding: String) -> String:
	var lines: PackedStringArray = []
	lines.append(Loc.t("SETTINGS"))
	lines.append("")
	if not p_rebinding.is_empty():
		lines.append(Loc.t("Press the new key or pad button for %s (Esc keeps the current one)") % Loc.t(p_rebinding.replace("_", " ")))
		lines.append("")
	var last_section := ""
	for i: int in p_rows.size():
		var row: Dictionary = p_rows[i]
		var section := String(row.get("section", ""))
		if section != last_section:
			if not section.is_empty():
				lines.append(Loc.t(section))
			last_section = section
		var marker := "▶ " if i == p_cursor else "   "
		lines.append(Loc.t("%s%s") % [marker, row.get("label", row.get("id", "?"))])
	lines.append("")
	if p_cursor >= 0 and p_cursor < p_rows.size() and p_rebinding.is_empty():
		var hint := String(p_rows[p_cursor].get("hint", ""))
		if not hint.is_empty():
			lines.append(hint)
			lines.append("")
	lines.append(Loc.t("↑↓ choose · ←→ adjust · %s toggle or rebind · %s back") % [Glyphs.key_and_pad("Enter", Glyphs.confirm()), Glyphs.key_and_pad("Esc", Glyphs.cancel())])
	return "\n".join(lines)
