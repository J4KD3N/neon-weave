## One expedition's unbanked haul (GDD §11: lost on a wipe, banked on
## extraction). Rolls grants from data with its own seeded RNG so a given
## Shard seed yields the same loot.
##
## Grant blocks (on enemies as `loot`, on pickups as `grants`):
##   {"salvage": [1, 3], "aether": 1, "cipher_chance": 0.1, "xp": 5}
## A resource value is a number or an inclusive [min, max] range.
class_name RunState
extends RefCounted

var shard_id: String = ""
var in_shard: bool = false
var haul: Dictionary = {"salvage": 0, "aether": 0, "ciphers": 0}
var xp: int = 0
var kills: int = 0
var pickups: int = 0
## Shard-feature deltas, saved with the run: opened door cells ([x, y]) and
## relay waypoints already used ([x, y]).
var opened: Array = []
var waypoints_used: Array = []
var rng := RandomNumberGenerator.new()


func begin(p_shard_id: String, seed_value: int) -> void:
	shard_id = p_shard_id
	in_shard = not p_shard_id.is_empty()
	rng.seed = hash("%s:%d" % [p_shard_id, seed_value])
	clear()


func clear() -> void:
	for key: String in Ledger.RESOURCES:
		haul[key] = 0
	xp = 0
	kills = 0
	pickups = 0
	opened = []
	waypoints_used = []


## Empties the haul and XP after a relay bank; kills, pickups and the
## feature deltas stay with the run.
func clear_haul() -> void:
	for key: String in Ledger.RESOURCES:
		haul[key] = 0
	xp = 0


func is_empty() -> bool:
	for key: String in Ledger.RESOURCES:
		if int(haul[key]) > 0:
			return false
	return xp == 0


## Rolls a grant block into concrete amounts (resources + "xp").
func roll(grants: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in Ledger.RESOURCES:
		out[key] = _roll_value(grants.get(key, 0))
	var chance := float(grants.get("cipher_chance", 0.0))
	if chance > 0.0 and rng.randf() < chance:
		out["ciphers"] = int(out["ciphers"]) + 1
	out["xp"] = _roll_value(grants.get("xp", 0))
	return out


## Rolls and adds to the haul. Returns what was gained.
func collect(grants: Dictionary) -> Dictionary:
	var gained := roll(grants)
	for key: String in Ledger.RESOURCES:
		haul[key] = int(haul[key]) + int(gained[key])
	xp += int(gained["xp"])
	return gained


func take() -> Dictionary:
	var out := haul.duplicate()
	out["xp"] = xp
	return out


func summary() -> String:
	return "haul S%d A%d C%d · XP %d · kills %d" % [haul["salvage"], haul["aether"], haul["ciphers"], xp, kills]


static func describe(gained: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in Ledger.RESOURCES:
		if int(gained.get(key, 0)) > 0:
			parts.append("+%d %s" % [int(gained[key]), key])
	if int(gained.get("xp", 0)) > 0:
		parts.append("+%d xp" % int(gained["xp"]))
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _roll_value(v: Variant) -> int:
	if v is Array:
		var arr: Array = v
		if arr.is_empty():
			return 0
		var lo := int(arr[0])
		var hi := int(arr[arr.size() - 1])
		return rng.randi_range(mini(lo, hi), maxi(lo, hi))
	return maxi(int(v), 0)
