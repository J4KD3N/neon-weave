## Registers the game's input actions in code so they are versioned with the
## scripts and available headless. Idempotent; call from any entry scene.
class_name InputActions
extends RefCounted

const BINDINGS: Dictionary = {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"toggle_debug": [KEY_F1],
	"ability_1": [KEY_1],
	"ability_2": [KEY_2],
	"ability_3": [KEY_3],
	"ability_4": [KEY_4],
	"end_turn": [KEY_SPACE],
	"cancel": [KEY_ESCAPE],
	"restart": [KEY_R],
	"new_shard": [KEY_N],
	"go_home": [KEY_H],
	"extract": [KEY_E],
	"bastion": [KEY_B],
}


static func ensure() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var keys: Array = BINDINGS[action]
		for key: int in keys:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)
