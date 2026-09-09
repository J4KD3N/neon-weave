## Turns a party preset (+ an optional protagonist sheet) into member specs
## for [Party.spawn_members]. Pure: registry in, dictionaries out.
class_name PartyBuilder
extends RefCounted

const PROTAGONIST_ID := "protagonist"


## `companions`: recruited companion ids appended after the preset, up to
## `rules.party_max` members in total.
## `level` is the party level; `builds` maps member id -> {"subclass", "talents"}
## (Ledger.builds). Both default to a fresh level-1 party.
static func member_specs(registry: ContentRegistry, preset: Dictionary, protagonist: Dictionary, rules: CombatRules, spawn_positions: Array[Vector2], companions: Array[String] = [], level: int = 1, builds: Dictionary = {}) -> Array[Dictionary]:
	var attr_rules: Dictionary = registry.get_entry("rules", "attributes")
	var prog_rules: Dictionary = registry.get_entry("rules", "progression")
	var members: Array = Array(preset.get("members", [])).duplicate()
	for id: String in companions:
		if members.size() >= rules.party_max:
			break
		var c := registry.get_entry("companions", id)
		if c.is_empty():
			continue
		members.append({"id": id, "name": String(c.get("short_name", c.get("name", id))), "race": String(c.get("race", "")), "class": String(c.get("class", "")), "companion": true})
	var specs: Array[Dictionary] = []
	for i: int in members.size():
		var data: Dictionary = Dictionary(members[i]).duplicate()
		var extras: Dictionary = {}
		if i == 0 and not protagonist.is_empty():
			var sheet := CharacterSheet.from_dict(protagonist)
			data = {"id": PROTAGONIST_ID, "name": sheet.name, "race": sheet.race_id, "class": sheet.class_id, "origin": sheet.origin_id}
			extras = {
				"attributes": sheet.attributes,
				"attribute_effects": attr_rules.get("effects", {}),
				"origin": registry.get_entry("origins", sheet.origin_id),
			}
		var cls: Dictionary = registry.get_entry("classes", String(data.get("class", "")))
		var race: Dictionary = registry.get_entry("races", String(data.get("race", "")))
		var resource: Dictionary = cls.get("resource", {})
		data["resource_id"] = String(resource.get("id", ""))
		var build: Dictionary = builds.get(String(data.get("id", "")), {})
		var fx := Progression.build_effects(registry, cls, level, build, prog_rules)
		var stats := StatBlock.for_member(cls, race, rules, extras)
		var deltas: Dictionary = fx["stats"]
		for key: String in deltas:
			stats[key] = maxi(int(stats[key]) + int(deltas[key]), 1)
		var abilities: Array[String] = []
		abilities.assign(cls.get("abilities", []))
		for id: String in fx["abilities"]:
			if not abilities.has(id):
				abilities.append(id)
		data["level"] = level
		data["subclass"] = String(build.get("subclass", "")) if level >= Progression.subclass_level(cls, prog_rules) else ""
		var eq := ItemSystem.equipment_mods(registry, build.get("equipment", {}))
		for key: String in eq["stats"]:
			if stats.has(key):
				stats[key] = maxi(int(stats[key]) + int(eq["stats"][key]), 1)
		data["damage_bonus"] = int(fx["damage_bonus"]) + int(eq["damage_bonus"])
		specs.append({
			"data": data,
			"color": class_color(registry, String(data.get("class", ""))),
			"overlay": race.get("overlay", {}),
			"sheet_id": String(Dictionary(race.get("art", {})).get("sheet", "")),
			"position": spawn_positions[mini(i, spawn_positions.size() - 1)] if not spawn_positions.is_empty() else Vector2.ZERO,
			"stats": stats,
			"abilities": abilities,
		})
	return specs


## Neon colour of a class's primary branch (GDD §5: Arcane purple, Tech teal, Body coral).
static func class_color(registry: ContentRegistry, class_id: String) -> Color:
	var cls: Dictionary = registry.get_entry("classes", class_id)
	var branches: Array = cls.get("branches", [])
	if branches.is_empty():
		return Color.WHITE
	var branch: Dictionary = registry.get_entry("branches", String(branches[0]))
	return Color.html(String(branch.get("color", "#ffffff")))
