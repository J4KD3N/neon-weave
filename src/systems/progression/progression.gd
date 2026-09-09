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


static func multiclass_level(rules: Dictionary) -> int:
	return int(rules.get("multiclass_level", 5))


static func capstone_level(rules: Dictionary) -> int:
	return int(rules.get("capstone_level", 8))


## How the party level splits between the main class and the multiclass
## (D-086): the second class holds at most the levels past `multiclass_level`.
static func class_levels(level: int, build: Dictionary, rules: Dictionary) -> Dictionary:
	var mc: Dictionary = build.get("multiclass", {})
	var second := 0
	if not String(mc.get("class", "")).is_empty():
		second = clampi(int(mc.get("levels", 0)), 0, maxi(level - multiclass_level(rules), 0))
	return {"main": level - second, "second": second, "class": String(mc.get("class", ""))}


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
static func build_effects(registry: ContentRegistry, class_entry: Dictionary, party_level: int, build: Dictionary, rules: Dictionary) -> Dictionary:
	var stats: Dictionary = {}
	for key: String in STAT_KEYS:
		stats[key] = 0
	var abilities: Array[String] = []
	var damage_bonus := 0
	var split := class_levels(party_level, build, rules)
	var level := int(split["main"])
	_grow(class_entry, level - 1, stats)
	_unlock(class_entry, level, abilities)
	if level >= capstone_level(rules) and class_entry.has("capstone") and not abilities.has(String(class_entry["capstone"])):
		abilities.append(String(class_entry["capstone"]))
	var second := int(split["second"])
	if second > 0:
		var other := registry.get_entry("classes", String(split["class"]))
		for id: String in other.get("abilities", []):
			if id != "strike" and not abilities.has(id) and not Array(class_entry.get("abilities", [])).has(id):
				abilities.append(id)
		_grow(other, second, stats)
		_unlock(other, second, abilities)
		if second >= capstone_level(rules) and other.has("capstone") and not abilities.has(String(other["capstone"])):
			abilities.append(String(other["capstone"]))
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


static func _grow(class_entry: Dictionary, levels: int, stats: Dictionary) -> void:
	var growth: Dictionary = class_entry.get("growth", {})
	for key: String in growth:
		if stats.has(key):
			stats[key] = int(stats[key]) + int(growth[key]) * maxi(levels, 0)


static func _unlock(class_entry: Dictionary, level: int, abilities: Array[String]) -> void:
	var unlocks: Dictionary = class_entry.get("unlocks", {})
	var unlock_levels: Array = unlocks.keys()
	unlock_levels.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in unlock_levels:
		if level >= int(key):
			for id: String in unlocks[key]:
				if not abilities.has(id):
					abilities.append(id)


## Why a second class cannot be taken now; empty when it can (D-086).
static func can_multiclass(registry: ContentRegistry, class_entry: Dictionary, level: int, build: Dictionary, class_id: String, rules: Dictionary, respec: bool) -> String:
	if class_id == String(class_entry.get("id", "")):
		return "that is the main class"
	if not registry.has_entry("classes", class_id):
		return "unknown class"
	if level < multiclass_level(rules):
		return "needs level %d" % multiclass_level(rules)
	var current := String(Dictionary(build.get("multiclass", {})).get("class", ""))
	if current == class_id:
		return "already chosen"
	if not current.is_empty() and not respec:
		return "needs the Arcanum to change"
	return ""


## Why another level cannot move to the second class; empty when it can.
static func can_add_multiclass_level(level: int, build: Dictionary, rules: Dictionary) -> String:
	var mc: Dictionary = build.get("multiclass", {})
	if String(mc.get("class", "")).is_empty():
		return "no second class yet"
	if int(mc.get("levels", 0)) >= level - multiclass_level(rules):
		return "every level past %d is already placed" % multiclass_level(rules)
	return ""
