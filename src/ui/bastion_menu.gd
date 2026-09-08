## The Bastion screen: books, buildings with level/effect/next cost, and the
## Beacon launch line. Text-only for M1; keys are handled by the world.
## A cursor (↑↓ / D-pad, Enter / A) mirrors the number keys for pads.
class_name BastionMenu
extends CanvasLayer

var panel: PanelContainer
var label: Label
var cursor: int = 0
var _count: int = 0


func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.position = Vector2(420, 120)
	panel.size = Vector2(1080, 760)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	visible = false


func refresh(bastion: BastionState, ledger: Ledger) -> void:
	_count = bastion.order.size()
	cursor = clampi(cursor, 0, maxi(_count - 1, 0))
	label.text = render(bastion, ledger, cursor)


## Moves the cursor over the buildings, wrapping. Caller refreshes.
func move(delta: int) -> int:
	if _count > 0:
		cursor = posmod(cursor + delta, _count)
	return cursor


## Pure text for the screen, so tests can check it without nodes.
static func render(bastion: BastionState, ledger: Ledger, p_cursor: int = 0) -> String:
	var lines: PackedStringArray = []
	lines.append("THE BASTION")
	lines.append(ledger.summary())
	lines.append("")
	for i: int in bastion.order.size():
		var id := bastion.order[i]
		var lv := bastion.level(id)
		var max_lv := bastion.max_level(id)
		var marker := "▶ " if i == p_cursor else "   "
		var line := "%s[%d] %s  L%d/%d — %s" % [marker, i + 1, bastion.name_of(id), lv, max_lv, bastion.blurb(id)]
		if lv < max_lv:
			var why := bastion.can_upgrade(id, ledger)
			var cost := BastionState.describe_cost(bastion.next_cost(id))
			line += "\n         next: %s — %s%s" % [bastion.next_blurb(id), cost, "" if why.is_empty() else "  (%s)" % why]
		else:
			line += "\n         (max)"
		lines.append(line)
		lines.append("")
	lines.append("[N] Launch a Shard at depth %d" % bastion.depth())
	lines.append("[B] Close  ·  ↑↓ / D-pad choose, Enter / A upgrade, Esc / B close")
	return "\n".join(lines)
