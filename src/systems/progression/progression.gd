## Party-wide levels from banked XP, per-class growth and unlocks, subclass
## and talent effects. Pure functions over registry entries; the builder
## applies the result to member specs and the Weave menu reads it.
##
## `rules/progression`: {"level_cap", "xp_curve": [xp needed to reach level
## i+1], "subclass_level", "talent_tiers_by_level": {"<level>": tier}}.
## Class: {"growth": {stat: per level}, "unlocks": {"<level>": [ability]},
## "subclass_level"?, "subclasses": [ids]}.
## Subclass: {"class", "abilities", "stat_mods", "damage_bonus"}.
## Talent: {"branch", "tier", "cost": {aether}, "effects": {stat|damage_bonus}, "requires": [ids]}.
## A member's build (Ledger.builds[member_id]): {"subclass": id, "talents": [ids]}.
class_name Progression
extends RefCounted

const STAT_KEYS: Array[String] = ["hp", "move", "evasion", "initiative"]


static func level_for_xp(xp: int, rules: Dictionary) -> int:
	var curve: Array = rules.get("xp_curve", [0])
	var cap := maxi(int(rules.get("level_cap", curve.size())), 1)
	var level := 1
	for i: int in curve.size():
		if xp >= int(curve[i]):
			level = i + 1
	return mini(level, cap)


## XP needed for the next level, or -1 at the cap.
static func xp_to_next(xp: int, rules: Dictionary) -> int:
	var level := level_for_xp(xp, rules)
	var curve: Array = rules.get("xp_curve", [0])
	var cap := maxi(int(rules.get("level_cap", curve.size())), 1)
	if level >= cap or level >= curve.size():
		return -1
	return int(curve[level]) - xp


static func subclass_level(class_entry: Dictionary, rules: Dictionary) -> int:
	return int(class_entry.get("subclass_level", rules.get("subclass_level", 3)))


## Highest talent tier open at `level`.
static func talent_tier_at(level: int, rules: Dictionary) -> int:
	var tiers: Dictionary = rules.get("talent_tiers_by_level", {"1": 1})
	var best := 0
	for key: String in tiers:
		if level >= int(key):
			best = maxi(best, int(tiers[key]))
	return best


## Stat deltas and extras a build adds on top of StatBlock: returns
## {"stats": {key: delta}, "abilities": [extra ids], "damage_bonus": int}.
static func build_effects(registry: ContentRegistry, class_entry: Dictionary, level: int, build: Dictionary, rules: Dictionary) -> Dictionary:
	var stats: Dictionary = {}
	for key: String in STAT_KEYS:
		stats[key] = 0
	var abilities: Array[String] = []
	var damage_bonus := 0
	var growth: Dictionary = class_entry.get("growth", {})
	for key: String in growth:
		if stats.has(key):
			stats[key] = int(stats[key]) + int(growth[key]) * maxi(level - 1, 0)
	var unlocks: Dictionary = class_entry.get("unlocks", {})
	var unlock_levels: Array = unlocks.keys()
	unlock_levels.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in unlock_levels:
		if level >= int(key):
			for id: String in unlocks[key]:
				if not abilities.has(id):
					abilities.append(id)
	var sub_id := String(build.get("subclass", ""))
	if not sub_id.is_empty() and level >= subclass_level(class_entry, rules):
		var sub := registry.get_entry("subclasses", sub_id)
		if not sub.is_empty() and Array(class_entry.get("subclasses", [])).has(sub_id):
			for id: String in sub.get("abilities", []):
				if not abilities.has(id):
					abilities.append(id)
			var mods: Dictionary = sub.get("stat_mods", {})
			for key: String in mods:
				if stats.has(key):
					stats[key] = int(stats[key]) + int(mods[key])
			damage_bonus += int(sub.get("damage_bonus", 0))
	for id: String in build.get("talents", []):
		var talent := registry.get_entry("talents", id)
		var fx: Dictionary = talent.get("effects", {})
		for key: String in fx:
			if stats.has(key):
				stats[key] = int(stats[key]) + int(fx[key])
			elif key == "damage_bonus":
				damage_bonus += int(fx[key])
	return {"stats": stats, "abilities": abilities, "damage_bonus": damage_bonus}


## Why a subclass cannot be chosen now; empty when it can.
static func can_choose_subclass(registry: ContentRegistry, class_entry: Dictionary, level: int, build: Dictionary, sub_id: String, rules: Dictionary, respec: bool) -> String:
	if not Array(class_entry.get("subclasses", [])).has(sub_id) or not registry.has_entry("subclasses", sub_id):
		return "not a subclass of this class"
	if level < subclass_level(class_entry, rules):
		return "needs level %d" % subclass_level(class_entry, rules)
	var current := String(build.get("subclass", ""))
	if current == sub_id:
		return "already chosen"
	if not current.is_empty() and not respec:
		return "needs the Arcanum to change"
	return ""


## Why a talent cannot be bought now; empty when it can.
## `cost_mod` shifts the Aether price (a race trait); never below 0.
static func talent_cost(registry: ContentRegistry, talent_id: String, cost_mod: int = 0) -> int:
	return maxi(int(Dictionary(registry.get_entry("talents", talent_id).get("cost", {})).get("aether", 0)) + cost_mod, 0)


static func can_buy_talent(registry: ContentRegistry, level: int, build: Dictionary, talent_id: String, rules: Dictionary, aether: int, cost_mod: int = 0) -> String:
	var talent := registry.get_entry("talents", talent_id)
	if talent.is_empty():
		return "unknown talent"
	var owned: Array = build.get("talents", [])
	if owned.has(talent_id):
		return "already learned"
	if int(talent.get("tier", 1)) > talent_tier_at(level, rules):
		return "tier %d opens later" % int(talent.get("tier", 1))
	for req: String in talent.get("requires", []):
		if not owned.has(req):
			return "needs %s" % String(registry.get_entry("talents", req).get("name", req))
	var cost := talent_cost(registry, talent_id, cost_mod)
	if aether < cost:
		return "needs %d Aether" % cost
	return ""


## Aether returned when a build's talents are dropped at `refund` (0..1).
## `cost_mod` is the same shift the member paid with, so a discount never refunds more than was spent.
static func refund_for(registry: ContentRegistry, build: Dictionary, refund: float, cost_mod: int = 0) -> int:
	var total := 0
	for id: String in build.get("talents", []):
		total += talent_cost(registry, id, cost_mod)
	return int(floor(total * clampf(refund, 0.0, 1.0)))
