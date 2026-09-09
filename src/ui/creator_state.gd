## The creator's model: a [CharacterSheet] plus row navigation and the
## option lists pulled from the registry. Pure, so the whole screen is
## testable without nodes; [CreatorMenu] only draws `render()`.
class_name CreatorState
extends RefCounted

const ROW_NAME := "name"

var sheet := CharacterSheet.new()
var races: Array[String] = []
var origins: Array[String] = []
var classes: Array[String] = []
var attr_names: Array[String] = []
var attr_rules: Dictionary = {}
var rows: Array[String] = []
var row: int = 1

var _registry: ContentRegistry
var _rules: CombatRules


func setup(registry: ContentRegistry, rules: CombatRules, existing: Dictionary = {}, unlocked: Array[String] = []) -> void:
	_registry = registry
	_rules = rules
	attr_rules = registry.get_entry("rules", "attributes")
	races.clear()
	for r: Dictionary in registry.get_all("races"):
		if bool(r.get("playable", true)): # companion-only races (Vaultkin) stay off the creator
			races.append(r["id"])
	origins.clear()
	for o: Dictionary in registry.get_all("origins"):
		if o.has("unlock_flag") and not unlocked.has("origin:%s" % String(o["id"])):
			continue # earned on the account by an earlier playthrough (S35)
		origins.append(o["id"])
	classes.clear()
	for c: Dictionary in registry.get_all("classes"):
		classes.append(c["id"])
	attr_names.clear()
	attr_names.assign(attr_rules.get("names", []))
	rows = [ROW_NAME, "race", "origin", "class"]
	rows.append_array(attr_names)
	sheet = CharacterSheet.from_dict(existing) if not existing.is_empty() else CharacterSheet.new()
	if not races.has(sheet.race_id) and not races.is_empty():
		sheet.race_id = races[0]
	if not origins.has(sheet.origin_id) and not origins.is_empty():
		sheet.origin_id = origins[0]
	if not classes.has(sheet.class_id) and not classes.is_empty():
		sheet.class_id = classes[0]
	for a: String in attr_names:
		if not sheet.attributes.has(a):
			sheet.attributes[a] = 0
	row = 1


func current_row() -> String:
	return rows[row]


func move_row(delta: int) -> void:
	row = posmod(row + delta, rows.size())


## Left/right on the current row. Returns true when something changed.
func adjust(delta: int) -> bool:
	var key := current_row()
	match key:
		ROW_NAME:
			return false
		"race":
			sheet.race_id = _cycle(races, sheet.race_id, delta)
		"origin":
			sheet.origin_id = _cycle(origins, sheet.origin_id, delta)
		"class":
			sheet.class_id = _cycle(classes, sheet.class_id, delta)
		_:
			var cap := int(attr_rules.get("max_per_attribute", 4))
			var v := sheet.attribute(key)
			var nv := clampi(v + delta, 0, cap)
			if delta > 0 and points_left() <= 0:
				return false
			if nv == v:
				return false
			sheet.attributes[key] = nv
	return true


func points_left() -> int:
	return int(attr_rules.get("points", 0)) - sheet.points_spent()


func errors() -> Array[String]:
	return sheet.validate(_registry, attr_rules)


func is_valid() -> bool:
	return errors().is_empty()


## Derived combat stats for the current sheet.
func preview_stats() -> Dictionary:
	var cls := _registry.get_entry("classes", sheet.class_id)
	var race := _registry.get_entry("races", sheet.race_id)
	return StatBlock.for_member(cls, race, _rules, {
		"attributes": sheet.attributes,
		"attribute_effects": attr_rules.get("effects", {}),
		"origin": _registry.get_entry("origins", sheet.origin_id),
	})


func render() -> String:
	var lines: PackedStringArray = []
	lines.append("NEW WEAVER")
	lines.append("↑↓ row · ←→ change · Enter confirm · Esc cancel")
	lines.append("")
	for i: int in rows.size():
		var key := rows[i]
		var marker := "▶ " if i == row else "   "
		match key:
			ROW_NAME:
				lines.append("%sName: %s" % [marker, sheet.name])
			"race":
				var r := _registry.get_entry("races", sheet.race_id)
				lines.append("%sRace: %s — %s" % [marker, r.get("name", sheet.race_id), r.get("identity", "")])
				lines.append("      lean: %s · %s" % [r.get("faction_lean", "none"), _mods_text(r.get("stat_mods", {}))])
			"origin":
				var o := _registry.get_entry("origins", sheet.origin_id)
				lines.append("%sOrigin: %s — %s" % [marker, o.get("name", sheet.origin_id), o.get("summary", "")])
				lines.append("      %s" % _mods_text(o.get("stat_mods", {})))
			"class":
				var c := _registry.get_entry("classes", sheet.class_id)
				var res: Dictionary = c.get("resource", {})
				lines.append("%sClass: %s — %s: %s" % [marker, c.get("name", sheet.class_id), res.get("name", "?"), res.get("summary", "")])
				lines.append("      abilities: %s" % ", ".join(PackedStringArray(c.get("abilities", []))))
			_:
				var fx: Dictionary = Dictionary(attr_rules.get("effects", {})).get(key, {})
				lines.append("%s%s: %s%s  (%s per point)" % [marker, key.capitalize(), "●".repeat(sheet.attribute(key)), "○".repeat(maxi(int(attr_rules.get("max_per_attribute", 4)) - sheet.attribute(key), 0)), _mods_text(fx)])
	lines.append("")
	lines.append("Points left: %d" % points_left())
	var s := preview_stats()
	lines.append("Derived: HP %d · Move %d · Evasion %d · Initiative %d" % [s["hp"], s["move"], s["evasion"], s["initiative"]])
	var errs := errors()
	if not errs.is_empty():
		lines.append("")
		lines.append("Cannot confirm: " + "; ".join(PackedStringArray(errs)))
	return "\n".join(lines)


static func _mods_text(mods: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in mods:
		var v := int(mods[key])
		parts.append("%s%d %s" % ["+" if v >= 0 else "", v, key])
	return ", ".join(parts) if not parts.is_empty() else "no modifiers"


static func _cycle(options: Array[String], current: String, delta: int) -> String:
	if options.is_empty():
		return current
	var i := options.find(current)
	return options[posmod(i + delta, options.size())]
