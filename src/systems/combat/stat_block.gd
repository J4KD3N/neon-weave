## Derives a member's combat stats from class stats plus race modifiers,
## and for a created protagonist: attribute effects and origin modifiers.
## Result keys: hp, move, evasion, initiative.
class_name StatBlock
extends RefCounted

const KEYS: Array[String] = ["hp", "move", "evasion", "initiative"]


## `extras` (optional): {"attributes": {name: points}, "attribute_effects":
## {name: {stat: per_point}}, "origin": origin entry with `stat_mods`}.
static func for_member(class_entry: Dictionary, race_entry: Dictionary, rules: CombatRules, extras: Dictionary = {}) -> Dictionary:
	var base: Dictionary = class_entry.get("stats", {})
	var out: Dictionary = {
		"hp": int(base.get("hp", 10)),
		"move": int(base.get("move", rules.base_move)),
		"evasion": int(base.get("evasion", 0)),
		"initiative": int(base.get("initiative", 0)),
	}
	_add_mods(out, race_entry.get("stat_mods", {}))
	var origin: Dictionary = extras.get("origin", {})
	_add_mods(out, origin.get("stat_mods", {}))
	var attributes: Dictionary = extras.get("attributes", {})
	var effects: Dictionary = extras.get("attribute_effects", {})
	for attr: String in attributes:
		var per_point: Dictionary = effects.get(attr, {})
		for key: String in KEYS:
			out[key] = int(out[key]) + int(per_point.get(key, 0)) * int(attributes[attr])
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


static func _add_mods(out: Dictionary, mods: Dictionary) -> void:
	for key: String in KEYS:
		out[key] = int(out[key]) + int(mods.get(key, 0))
