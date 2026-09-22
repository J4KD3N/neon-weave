## The ending panel (S36, S43): the ending the state machine resolved, its
## modifiers (what the Keys, the voice and the catastrophe changed), the
## companions' fates, the run in numbers, and the credits. Enter / A / Esc
## returns to the title. Text-only like the other panels.
class_name EndingMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label


func _ready() -> void:
	layer = 9
	panel = PanelContainer.new()
	panel.position = Vector2(300, 60)
	panel.size = Vector2(1320, 940)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func show_text(text: String) -> void:
	label.text = text
	visible = true


func close() -> void:
	visible = false


## `ending`: the entry; `fates`: lines from Endings.fates; `stats` as
## DemoEndMenu; `modifiers`: paragraphs from Endings.modifiers; `credits`:
## lines from `rules/credits`.
static func render(ending: Dictionary, fates: Array[String], stats: Dictionary, modifiers: Array[String] = [], credits: Array[String] = []) -> String:
	var lines: PackedStringArray = []
	lines.append(Loc.text(ending, "name", Loc.t("THE END")).to_upper())
	lines.append("")
	lines.append(Loc.text(ending, "summary"))
	for m: String in modifiers:
		lines.append("")
		lines.append(m)
	lines.append("")
	if not fates.is_empty():
		lines.append(Loc.t("Afterwards:"))
		for f: String in fates:
			lines.append(Loc.t("  %s") % f)
		lines.append("")
	lines.append(Loc.t("Your run: party level %d · %d extractions · %d wipes · %d kills") % [int(stats.get("level", 1)), int(stats.get("runs", 0)), int(stats.get("wipes", 0)), int(stats.get("kills", 0))])
	lines.append(String(stats.get("standing", "")))
	if not credits.is_empty():
		lines.append("")
		lines.append(Loc.t("NEON WEAVE"))
		for c: String in credits:
			lines.append(c)
	lines.append("")
	lines.append(Loc.t("Enter / A / Esc: the title"))
	return "\n".join(lines)
