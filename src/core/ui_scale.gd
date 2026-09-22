## Text size (S53, D-108): every menu sets its font sizes for a 1920×1080
## canvas; the Deck shows that canvas at two thirds. `apply` walks the
## screen-space layers of a node, remembers each Control's designed font
## size the first time it sees it, and sets designed × scale, so the
## setting can move up and down without drift. World-space labels (actors,
## buildings) are not under a CanvasLayer and are left alone.
class_name UiScale
extends RefCounted

const META := "designed_font_size"
const SCALES: Array[float] = [1.0, 1.15, 1.3, 1.5]
const NAMES: Dictionary = {1.0: "normal", 1.15: "large", 1.3: "larger", 1.5: "Deck"}

static var text_scale: float = 1.0


static func name_of(scale: float) -> String:
	for s: float in NAMES:
		if is_equal_approx(s, scale):
			return NAMES[s]
	return "%.2f×" % scale


## Applies the current scale under every CanvasLayer child of `root`, plus
## `extra` Controls (the status overlay). Returns how many Controls moved.
static func apply(root: Node, extra: Array[Control] = []) -> int:
	var touched := 0
	for child: Node in root.get_children():
		if child is CanvasLayer:
			touched += _apply_under(child)
	for c: Control in extra:
		if c != null:
			touched += _scale_control(c)
	return touched


static func _apply_under(node: Node) -> int:
	var touched := 0
	if node is Control:
		touched += _scale_control(node)
	for child: Node in node.get_children():
		touched += _apply_under(child)
	return touched


static func _scale_control(c: Control) -> int:
	if not c.has_theme_font_size_override("font_size"):
		return 0
	if not c.has_meta(META):
		c.set_meta(META, c.get_theme_font_size("font_size"))
	var designed := int(c.get_meta(META))
	var wanted := int(round(designed * text_scale))
	if c.get_theme_font_size("font_size") == wanted:
		return 0
	c.add_theme_font_size_override("font_size", wanted)
	return 1
