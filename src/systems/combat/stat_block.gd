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


## `tier` ("", "elite", "boss") overrides the entry's own `tier`; `depth` is
## the Shard depth (1 = no scaling). Adds "damage_bonus", "ap_bonus" and
## "tier" beside the four stat keys.
static func for_enemy(enemy_entry: Dictionary, rules: CombatRules, depth: int = 1, tier: String = "") -> Dictionary:
	var base: Dictionary = enemy_entry.get("stats", {})
	var t := tier if not tier.is_empty() else String(enemy_entry.get("tier", ""))
	var hp := float(maxi(int(base.get("hp", 5)), 1))
	var damage_bonus := 0
	var ap_bonus := 0
	match t:
		"elite":
			hp *= rules.elite_hp_mult
			damage_bonus += rules.elite_damage_bonus
		"boss":
			hp *= rules.boss_hp_mult
			damage_bonus += rules.boss_damage_bonus
			ap_bonus += rules.boss_ap_bonus
	var d := maxi(depth, 1)
	hp *= 1.0 + rules.depth_hp_per_level * float(d - 1)
	if rules.depth_damage_every > 0:
		damage_bonus += int((d - 1) / rules.depth_damage_every)
	return {
		"hp": maxi(int(round(hp)), 1),
		"move": maxi(int(base.get("move", rules.base_move)), 1),
		"evasion": int(base.get("evasion", 0)),
		"initiative": int(base.get("initiative", 0)),
		"damage_bonus": damage_bonus,
		"ap_bonus": ap_bonus,
		"tier": t,
	}


static func _add_mods(out: Dictionary, mods: Dictionary) -> void:
	for key: String in KEYS:
		out[key] = int(out[key]) + int(mods.get(key, 0))
