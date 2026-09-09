## Items (S29, D-084): equipment as content. An `items` entry is a base
## (slot, stat mods, damage bonus); an `affixes` entry is a prefix or
## suffix with its own mods, rolled onto a base by rarity (`rules/loot`:
## `affixes_by_rarity`). An *instance* is what the player owns:
##   {"uid": int, "item": id, "affixes": [ids], "rarity": "rare"}
## Instances live unbanked in `RunState.items` and banked in
## `Ledger.items`; equipped ones sit in `Ledger.builds[member].equipment`
## keyed by slot key ("weapon", "armour", "trinket_1", "cyberware_2").
## Slots every member has come from `rules/loot.slots`; a race adds
## `cyberware_slots` (Chromed: the GDD's extra equipment slots). Pure over
## the registry: no node, no world.
class_name ItemSystem
extends RefCounted

const STAT_KEYS: Array[String] = ["hp", "move", "evasion", "initiative"]
const SLOT_BASES: Array[String] = ["weapon", "armour", "trinket", "cyberware"]


static func loot_rules(registry: ContentRegistry) -> Dictionary:
	return registry.get_entry("rules", "loot")


## 0 for common, higher is rarer; unknown rarities rank as common.
static func rarity_rank(registry: ContentRegistry, rarity: String) -> int:
	var order: Array = loot_rules(registry).get("rarity_order", ["common", "rare", "epic"])
	return maxi(order.find(rarity), 0)


# --- slots ------------------------------------------------------------------

## Slot keys for a member of `race_entry`: the rules' base slots, numbered
## when repeated, plus the race's cyberware slots.
static func slot_keys(registry: ContentRegistry, race_entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var counts: Dictionary = {}
	var bases: Array = Array(loot_rules(registry).get("slots", ["weapon", "armour", "trinket", "trinket"])).duplicate() # never mutate the rules entry
	var cyber := int(race_entry.get("cyberware_slots", int(loot_rules(registry).get("cyberware_slots_default", 0))))
	for _i: int in cyber:
		bases.append("cyberware")
	var totals: Dictionary = {}
	for base: String in bases:
		totals[base] = int(totals.get(base, 0)) + 1
	for base: String in bases:
		counts[base] = int(counts.get(base, 0)) + 1
		out.append(base if int(totals[base]) == 1 else "%s_%d" % [base, int(counts[base])])
	return out


## "trinket_2" -> "trinket".
static func slot_base(slot_key: String) -> String:
	var parts := slot_key.split("_")
	if parts.size() > 1 and parts[parts.size() - 1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	return "_".join(parts)


static func fits(registry: ContentRegistry, inst: Dictionary, slot_key: String) -> bool:
	var item := registry.get_entry("items", String(inst.get("item", "")))
	return not item.is_empty() and String(item.get("slot", "")) == slot_base(slot_key)


# --- instances ----------------------------------------------------------------

static func make(item_id: String, affixes: Array = [], rarity: String = "common", uid: int = 0) -> Dictionary:
	var ids: Array = []
	for a: Variant in affixes:
		ids.append(String(a))
	return {"uid": uid, "item": item_id, "affixes": ids, "rarity": rarity}


## Rolls a drop of `rarity` with `rng`: a weighted base item that fits the
## rarity (and `family`, when the item names families), then as many
## affixes as the rarity allows, each allowed on the slot, no repeats.
## Returns {} when no item qualifies.
static func roll_drop(registry: ContentRegistry, rng: RandomNumberGenerator, rarity: String, family: String = "") -> Dictionary:
	var rank := rarity_rank(registry, rarity)
	var bases: Array[Dictionary] = []
	for item: Dictionary in registry.get_all("items"):
		if rarity_rank(registry, String(item.get("min_rarity", "common"))) > rank:
			continue
		var families: Array = item.get("families", [])
		if not family.is_empty() and not families.is_empty() and not families.has(family):
			continue
		bases.append(item)
	if bases.is_empty():
		return {}
	var base := _weighted(bases, rng)
	var count := int(Dictionary(loot_rules(registry).get("affixes_by_rarity", {})).get(rarity, 0))
	var chosen: Array = []
	var slot := String(base.get("slot", ""))
	for _n: int in count:
		var pool: Array[Dictionary] = []
		for affix: Dictionary in registry.get_all("affixes"):
			if chosen.has(String(affix["id"])):
				continue
			if rarity_rank(registry, String(affix.get("min_rarity", "common"))) > rank:
				continue
			var slots: Array = affix.get("slots", ["any"])
			if not slots.has("any") and not slots.has(slot):
				continue
			pool.append(affix)
		if pool.is_empty():
			break
		chosen.append(String(_weighted(pool, rng)["id"]))
	return make(String(base["id"]), chosen, rarity, rng.randi())


static func _weighted(entries: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var total := 0
	for e: Dictionary in entries:
		total += maxi(int(e.get("weight", 1)), 0)
	if total <= 0:
		return entries[0]
	var pick := rng.randi_range(1, total)
	for e: Dictionary in entries:
		pick -= maxi(int(e.get("weight", 1)), 0)
		if pick <= 0:
			return e
	return entries[entries.size() - 1]


## "Keen Strut blade of Haste".
static func display_name(registry: ContentRegistry, inst: Dictionary) -> String:
	var item := registry.get_entry("items", String(inst.get("item", "")))
	var prefixes: PackedStringArray = []
	var suffixes: PackedStringArray = []
	for id: String in inst.get("affixes", []):
		var affix := registry.get_entry("affixes", id)
		if affix.is_empty():
			continue
		if bool(affix.get("prefix", true)):
			prefixes.append(String(affix.get("name", id)))
		else:
			suffixes.append(String(affix.get("name", id)))
	var parts: PackedStringArray = []
	parts.append_array(prefixes)
	parts.append(String(item.get("name", inst.get("item", "?"))))
	parts.append_array(suffixes)
	return " ".join(parts)


## Base plus affixes: {"stats": {hp, move, evasion, initiative}, "damage_bonus"}.
static func mods(registry: ContentRegistry, inst: Dictionary) -> Dictionary:
	var out := {"stats": {}, "damage_bonus": 0}
	for key: String in STAT_KEYS:
		out["stats"][key] = 0
	var sources: Array[Dictionary] = [registry.get_entry("items", String(inst.get("item", "")))]
	for id: String in inst.get("affixes", []):
		sources.append(registry.get_entry("affixes", id))
	for src: Dictionary in sources:
		var sm: Dictionary = src.get("stat_mods", {})
		for key: String in STAT_KEYS:
			out["stats"][key] = int(out["stats"][key]) + int(sm.get(key, 0))
		out["damage_bonus"] = int(out["damage_bonus"]) + int(src.get("damage_bonus", 0))
	return out


## Every equipped instance's mods summed (Ledger.builds[member].equipment).
static func equipment_mods(registry: ContentRegistry, equipment: Dictionary) -> Dictionary:
	var out := {"stats": {}, "damage_bonus": 0}
	for key: String in STAT_KEYS:
		out["stats"][key] = 0
	for slot_key: String in equipment:
		var m := mods(registry, equipment[slot_key])
		for key: String in STAT_KEYS:
			out["stats"][key] = int(out["stats"][key]) + int(m["stats"][key])
		out["damage_bonus"] = int(out["damage_bonus"]) + int(m["damage_bonus"])
	return out


## "+3 HP, +1 damage" or "no effect".
static func describe_mods(m: Dictionary) -> String:
	var parts: PackedStringArray = []
	var labels := {"hp": "HP", "move": "move", "evasion": "evasion", "initiative": "initiative"}
	var stats: Dictionary = m.get("stats", {})
	for key: String in STAT_KEYS:
		var v := int(stats.get(key, 0))
		if v != 0:
			parts.append("%+d %s" % [v, labels[key]])
	var dmg := int(m.get("damage_bonus", 0))
	if dmg != 0:
		parts.append("%+d damage" % dmg)
	return ", ".join(parts) if not parts.is_empty() else "no effect"


## One line for menus: "Keen Strut blade (weapon, rare): +2 damage".
static func describe(registry: ContentRegistry, inst: Dictionary) -> String:
	var item := registry.get_entry("items", String(inst.get("item", "")))
	var rarity := String(inst.get("rarity", "common"))
	var tag := String(item.get("slot", "?")) + ("" if rarity == "common" else ", " + rarity)
	return "%s (%s): %s" % [display_name(registry, inst), tag, describe_mods(mods(registry, inst))]


## Index of the instance with `uid` in `list`, or -1.
static func find_uid(list: Array, uid: int) -> int:
	for i: int in list.size():
		if int(Dictionary(list[i]).get("uid", -1)) == uid:
			return i
	return -1
