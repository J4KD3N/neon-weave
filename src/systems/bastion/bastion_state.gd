## The Bastion's buildings and their levels (GDD §12). Levels come from the
## ledger; costs and effects come from the `buildings` content kind. Pure
## data: the world applies the effects (heal, bonuses, depth).
##
## Building entry: {"name", "order", "levels": [{"cost": {...}, "effects": {...}, "blurb"}]}
## Level 0 is the starting state; upgrading to level n pays levels[n].cost.
class_name BastionState
extends RefCounted

var buildings: Dictionary = {} # id -> entry
var levels: Dictionary = {} # id -> int
var order: Array[String] = []


func setup(entries: Array[Dictionary], saved_levels: Dictionary) -> void:
	buildings.clear()
	levels.clear()
	order.clear()
	var sorted: Array[Dictionary] = []
	sorted.assign(entries)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("order", 99))
		var ob := int(b.get("order", 99))
		return oa < ob if oa != ob else String(a["id"]) < String(b["id"]))
	for e: Dictionary in sorted:
		var id := String(e["id"])
		buildings[id] = e
		order.append(id)
		levels[id] = clampi(int(saved_levels.get(id, 0)), 0, max_level(id))


func has(id: String) -> bool:
	return buildings.has(id)


func level(id: String) -> int:
	return int(levels.get(id, 0))


func max_level(id: String) -> int:
	var entry: Dictionary = buildings.get(id, {})
	var lv: Array = entry.get("levels", [])
	return maxi(lv.size() - 1, 0)


func _level_entry(id: String, n: int) -> Dictionary:
	var entry: Dictionary = buildings.get(id, {})
	var lv: Array = entry.get("levels", [])
	if n < 0 or n >= lv.size():
		return {}
	return lv[n]


## Cost of the next level, or {} when maxed / unknown.
func next_cost(id: String) -> Dictionary:
	if not has(id) or level(id) >= max_level(id):
		return {}
	var raw: Dictionary = _level_entry(id, level(id) + 1).get("cost", {})
	var cost: Dictionary = {}
	for key: String in raw:
		cost[key] = int(raw[key]) # JSON numbers arrive as floats
	return cost


func can_upgrade(id: String, ledger: Ledger) -> String:
	if not has(id):
		return "unknown building"
	if level(id) >= max_level(id):
		return "already at max level"
	if not ledger.can_afford(next_cost(id)):
		return "cannot afford %s" % describe_cost(next_cost(id))
	return ""


## Spends from the ledger and raises the level. False when refused.
func upgrade(id: String, ledger: Ledger) -> bool:
	if not can_upgrade(id, ledger).is_empty():
		return false
	if not ledger.spend(next_cost(id)):
		return false
	levels[id] = level(id) + 1
	return true


## Sum of every building's current-level effects.
func effects() -> Dictionary:
	var out: Dictionary = {}
	for id: String in order:
		var fx: Dictionary = _level_entry(id, level(id)).get("effects", {})
		for key: String in fx:
			out[key] = float(out.get(key, 0.0)) + float(fx[key])
	return out


func effect(key: String, default: float = 0.0) -> float:
	return float(effects().get(key, default))


## Every `unlocks` id declared by a reached level of any building
## (e.g. the Beacon at level 2 finds the Verdant Datacore).
func unlocks() -> Array[String]:
	var out: Array[String] = []
	for id: String in order:
		for n: int in range(0, level(id) + 1):
			for key: String in _level_entry(id, n).get("unlocks", []):
				if not out.has(key):
					out.append(key)
	return out


func has_unlocked(key: String) -> bool:
	return key.is_empty() or unlocks().has(key)


func depth() -> int:
	return maxi(int(effect("depth", 1.0)), 1)


func heal_fraction() -> float:
	return clampf(effect("heal_fraction", 0.0), 0.0, 1.0)


func hp_bonus() -> int:
	return int(effect("hp_bonus", 0.0))


func damage_bonus() -> int:
	return int(effect("damage_bonus", 0.0))


func to_dict() -> Dictionary:
	return levels.duplicate()


func blurb(id: String) -> String:
	return String(_level_entry(id, level(id)).get("blurb", ""))


func next_blurb(id: String) -> String:
	return String(_level_entry(id, level(id) + 1).get("blurb", ""))


func name_of(id: String) -> String:
	var entry: Dictionary = buildings.get(id, {})
	return String(entry.get("name", id))


static func describe_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in Ledger.RESOURCES:
		if int(cost.get(key, 0)) > 0:
			parts.append("%d %s" % [int(cost[key]), key])
	return ", ".join(parts) if not parts.is_empty() else "free"
