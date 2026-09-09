## Pad button names for menu footers and hints. `style` is "xbox",
## "playstation" or "auto" (detect from the first connected pad, Xbox
## names otherwise). Keyboard names sit beside them everywhere, so a
## wrong guess is never blocking.
class_name Glyphs
extends RefCounted

static var style: String = "auto"

const NAMES: Dictionary = {
	"xbox": {"confirm": "A", "cancel": "B", "menu": "Start", "swap": "Select", "ability": ["X", "Y", "LB", "RB"], "zoom": "LT / RT"},
	"playstation": {"confirm": "Cross", "cancel": "Circle", "menu": "Options", "swap": "Share", "ability": ["Square", "Triangle", "L1", "R1"], "zoom": "L2 / R2"},
}


static func resolved_style() -> String:
	if style != "auto":
		return style
	for id: int in Input.get_connected_joypads():
		var joy_name := Input.get_joy_name(id).to_lower()
		if joy_name.contains("ps") or joy_name.contains("dualshock") or joy_name.contains("dualsense") or joy_name.contains("playstation") or joy_name.contains("sony"):
			return "playstation"
	return "xbox"


static func _names() -> Dictionary:
	return NAMES.get(resolved_style(), NAMES["xbox"])


static func confirm() -> String:
	return String(_names()["confirm"])


static func cancel() -> String:
	return String(_names()["cancel"])


static func menu() -> String:
	return String(_names()["menu"])


static func swap() -> String:
	return String(_names()["swap"])


static func ability(index: int) -> String:
	var list: Array = _names()["ability"]
	return String(list[clampi(index, 0, list.size() - 1)])


## "Enter / A" style pair for footers.
static func key_and_pad(key_label: String, pad_label: String) -> String:
	return "%s / %s" % [key_label, pad_label]
