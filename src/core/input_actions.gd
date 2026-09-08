## Registers the game's input actions in code so they are versioned with the
## scripts and available headless. Idempotent; call from any entry scene.
##
## Keyboard and gamepad share one action set. Bindings may overlap across
## actions (Esc is both `cancel` and `menu`, Start is both `end_turn` and
## `menu`) because the world only checks the actions its current mode uses.
## Actions without a pad event are reached through the system menu; see
## PAD_ROUTES and docs/controller.md.
class_name InputActions
extends RefCounted

## action -> {"keys": [Key], "buttons": [JoyButton], "axes": [[JoyAxis, sign]]}
const BINDINGS: Dictionary = {
	"move_up": {"keys": [KEY_W, KEY_UP], "buttons": [JOY_BUTTON_DPAD_UP], "axes": [[JOY_AXIS_LEFT_Y, -1]]},
	"move_down": {"keys": [KEY_S, KEY_DOWN], "buttons": [JOY_BUTTON_DPAD_DOWN], "axes": [[JOY_AXIS_LEFT_Y, 1]]},
	"move_left": {"keys": [KEY_A, KEY_LEFT], "buttons": [JOY_BUTTON_DPAD_LEFT], "axes": [[JOY_AXIS_LEFT_X, -1]]},
	"move_right": {"keys": [KEY_D, KEY_RIGHT], "buttons": [JOY_BUTTON_DPAD_RIGHT], "axes": [[JOY_AXIS_LEFT_X, 1]]},
	"confirm": {"keys": [KEY_ENTER, KEY_KP_ENTER], "buttons": [JOY_BUTTON_A]},
	"cancel": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_B]},
	"menu": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START]},
	"ability_1": {"keys": [KEY_1], "buttons": [JOY_BUTTON_X]},
	"ability_2": {"keys": [KEY_2], "buttons": [JOY_BUTTON_Y]},
	"ability_3": {"keys": [KEY_3], "buttons": [JOY_BUTTON_LEFT_SHOULDER]},
	"ability_4": {"keys": [KEY_4], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"end_turn": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_START]},
	"next_member": {"keys": [KEY_TAB], "buttons": [JOY_BUTTON_BACK]},
	"weave": {"keys": [KEY_T]},
	"zoom_in": {"keys": [KEY_EQUAL, KEY_KP_ADD], "axes": [[JOY_AXIS_TRIGGER_RIGHT, 1]]},
	"zoom_out": {"keys": [KEY_MINUS, KEY_KP_SUBTRACT], "axes": [[JOY_AXIS_TRIGGER_LEFT, 1]]},
	"toggle_debug": {"keys": [KEY_F1]},
	"restart": {"keys": [KEY_R]},
	"new_shard": {"keys": [KEY_N]},
	"go_home": {"keys": [KEY_H]},
	"extract": {"keys": [KEY_E]},
	"bastion": {"keys": [KEY_B]},
	"creator": {"keys": [KEY_C]},
	"quick_save": {"keys": [KEY_F5]},
	"quick_load": {"keys": [KEY_F9]},
	"load_autosave": {"keys": [KEY_F10]},
}

## Keyboard-only actions and the pad path that reaches the same thing.
## "menu:<id>" is an item of the system menu (Start); "confirm" means the
## A button in the mode named.
const PAD_ROUTES: Dictionary = {
	"toggle_debug": "menu:registry",
	"restart": "confirm in the defeated screen",
	"new_shard": "menu:new_shard",
	"go_home": "menu:go_home",
	"extract": "confirm on the pad, or menu:extract",
	"bastion": "menu:bastion",
	"creator": "menu:creator",
	"weave": "menu:weave",
	"quick_save": "menu:save_1",
	"quick_load": "menu:load_1",
	"load_autosave": "menu:load_autosave",
}


static func ensure() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var spec: Dictionary = BINDINGS[action]
		for key: int in spec.get("keys", []):
			var k := InputEventKey.new()
			k.physical_keycode = key as Key
			InputMap.action_add_event(action, k)
		for button: int in spec.get("buttons", []):
			var b := InputEventJoypadButton.new()
			b.button_index = button as JoyButton
			InputMap.action_add_event(action, b)
		for axis_spec: Array in spec.get("axes", []):
			var m := InputEventJoypadMotion.new()
			m.axis = int(axis_spec[0]) as JoyAxis
			m.axis_value = float(axis_spec[1])
			InputMap.action_add_event(action, m)


## True when the registered action has at least one gamepad event.
static func has_pad_binding(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return true
	return false


## The menu item ids named by PAD_ROUTES, for the coverage test.
static func routed_menu_items() -> PackedStringArray:
	var out: PackedStringArray = []
	for action: String in PAD_ROUTES:
		for part: String in String(PAD_ROUTES[action]).split(" "):
			var token := part.trim_suffix(",")
			if token.begins_with("menu:"):
				out.append(token.trim_prefix("menu:"))
	return out
