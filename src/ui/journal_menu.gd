## The journal (J, or the system menu): every quest the party has started,
## its current stage, and the stage's objectives ticked off against the
## narrative state; the tracked quest (the one on the HUD) marked, ←→
## moving the mark; and the history, the last lines said and done (S52).
## Read-only; Esc / B closes.
class_name JournalMenu
extends CanvasLayer

const HISTORY_LINES := 12

var panel: PanelContainer
var label: Label


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


func show_text(text: String) -> void:
	label.text = text
	visible = true


func close() -> void:
	visible = false


## Pure render. `entries`: [{"id", "name", "main": bool, "stage_summary",
## "complete": bool, "objectives": [{"text", "done": bool}]}]; `tracked`
## the id of the quest on the HUD; `history` [{"who", "text"}], oldest first.
static func render(entries: Array[Dictionary], tracked: String = "", history: Array[Dictionary] = []) -> String:
	var lines: PackedStringArray = []
	lines.append(Loc.t("JOURNAL"))
	lines.append("")
	if entries.is_empty():
		lines.append(Loc.t("Nothing yet. Talk to people; walk east."))
	var active: Array[Dictionary] = []
	var finished: Array[Dictionary] = []
	for e: Dictionary in entries:
		if bool(e.get("complete", false)):
			finished.append(e)
		else:
			active.append(e)
	for e: Dictionary in active:
		var mark := "▶ " if String(e.get("id", "")) == tracked and not tracked.is_empty() else "  "
		lines.append(Loc.t("%s%s%s%s") % [mark, "★ " if bool(e.get("main", false)) else "• ", e.get("name", "?"), Loc.t("  (tracked)") if mark == "▶ " else ""])
		lines.append(Loc.t("     %s") % e.get("stage_summary", ""))
		for o: Dictionary in e.get("objectives", []):
			lines.append(Loc.t("     %s %s") % ["✓" if bool(o.get("done", false)) else "·", o.get("text", "")])
		lines.append("")
	if not finished.is_empty():
		lines.append(Loc.t("Done"))
		for e: Dictionary in finished:
			lines.append(Loc.t("     ✓ %s — %s") % [e.get("name", "?"), e.get("stage_summary", "")])
		lines.append("")
	if not history.is_empty():
		lines.append(Loc.t("History"))
		var start := maxi(history.size() - HISTORY_LINES, 0)
		for i: int in range(start, history.size()):
			lines.append(Loc.t("     %s: %s") % [history[i].get("who", "?"), history[i].get("text", "")])
		lines.append("")
	lines.append(Loc.t("←→ track a quest on the HUD · Esc / B / J close"))
	return "\n".join(lines)
