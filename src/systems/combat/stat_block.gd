## Derives a member's combat stats from class stats plus race modifiers.
## Result keys: hp, move, evasion, initiative.
class_name StatBlock
extends RefCounted

const KEYS: Array[String] = ["hp", "move", "evasion", "initiative"]


static func for_member(class_entry: Dictionary, race_entry: Dictionary, rules: CombatRules) -> Dictionary:
	var base: Dictionary = class_entry.get("stats", {})
	var mods: Dictionary = race_entry.get("stat_mods", {})
	var out: Dictionary = {
		"hp": int(base.get("hp", 10)),
		"move": int(base.get("move", rules.base_move)),
		"evasion": int(base.get("evasion", 0)),
		"initiative": int(base.get("initiative", 0)),
	}
	for key: String in KEYS:
		out[key] = int(out[key]) + int(mods.get(key, 0))
	out["hp"] = maxi(int(out["hp"]), 1)
	out["move"] = maxi(int(out["move"]), 1)
	return out


static func for_enemy(enemy_entry: Dictionary, rules: CombatRules) -> Dictionary:
	var base: Dictionary = enemy_entry.get("stats", {})
	return {
		"hp": maxi(int(base.get("hp", 5)), 1),
		"move": maxi(int(base.get("move", rules.base_move)), 1),
		"evasion": int(base.get("evasion", 0)),
		"initiative": int(base.get("initiative", 0)),
	}
