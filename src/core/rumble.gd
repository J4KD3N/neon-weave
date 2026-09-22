## Pad rumble (S53, D-108): named pulses on every connected joypad, off by
## a setting. Headless and padless runs still record the last pulse, so
## tests can see what the game asked for.
class_name Rumble
extends RefCounted

## kind -> [weak motor 0..1, strong motor 0..1, seconds]
const PULSES: Dictionary = {
	"hit": [0.3, 0.5, 0.15],
	"heavy": [0.5, 0.9, 0.25],
	"downed": [0.8, 1.0, 0.45],
	"victory": [0.2, 0.4, 0.2],
	"wipe": [1.0, 1.0, 0.8],
	"extract": [0.15, 0.35, 0.2],
	"boss": [0.4, 0.8, 0.35],
}

static var enabled: bool = true
static var last: Dictionary = {} # {"kind", "weak", "strong", "duration"}
static var count: int = 0


## Plays a named pulse. Returns false when off or unknown.
static func pulse(kind: String) -> bool:
	if not enabled or not PULSES.has(kind):
		return false
	var p: Array = PULSES[kind]
	last = {"kind": kind, "weak": float(p[0]), "strong": float(p[1]), "duration": float(p[2])}
	count += 1
	for device: int in Input.get_connected_joypads():
		Input.start_joy_vibration(device, float(p[0]), float(p[1]), float(p[2]))
	return true


static func stop_all() -> void:
	for device: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)
