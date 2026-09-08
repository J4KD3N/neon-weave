## Turns a party preset (+ an optional protagonist sheet) into member specs
## for [Party.spawn_members]. Pure: registry in, dictionaries out.
class_name PartyBuilder
extends RefCounted

const PROTAGONIST_ID := "protagonist"


static func member_specs(registry: ContentRegistry, preset: Dictionary, protagonist: Dictionary, rules: CombatRules, spawn_positions: Array[Vector2]) -> Array[Dictionary]:
	var attr_rules: Dictionary = registry.get_entry("rules", "attributes")
	var members: Array = preset.get("members", [])
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
		specs.append({
			"data": data,
			"color": class_color(registry, String(data.get("class", ""))),
			"overlay": race.get("overlay", {}),
			"sheet_id": String(Dictionary(race.get("art", {})).get("sheet", "")),
			"position": spawn_positions[mini(i, spawn_positions.size() - 1)] if not spawn_positions.is_empty() else Vector2.ZERO,
			"stats": StatBlock.for_member(cls, race, rules, extras),
			"abilities": cls.get("abilities", []),
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
