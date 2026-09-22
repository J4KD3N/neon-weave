## The creator's model: a [CharacterSheet] plus row navigation and the
## option lists pulled from the registry. Pure, so the whole screen is
## testable without nodes; [CreatorMenu] only draws `render()`. Since S51
## it is the first screen of a new game (`for_new_game`), carries the
## appearance rows (tone, accent from `rules/appearance`), lists the
## origins still locked on the account, and previews what the next
## attribute point buys.
class_name CreatorState
extends RefCounted

const ROW_NAME := "name"
const ROW_TONE := "tone"
const ROW_ACCENT := "accent"

var sheet := CharacterSheet.new()
var races: Array[String] = []
var origins: Array[String] = []
var locked_origins: Array[Dictionary] = [] # {name, blurb}: earned by a later playthrough
var classes: Array[String] = []
var tones: Array[String] = []
var accents: Array[String] = []
var attr_names: Array[String] = []
var attr_rules: Dictionary = {}
var look: Dictionary = {}
var rows: Array[String] = []
var row: int = 1
## True while the creator is the first screen of a new game: Esc returns
## to the death-stakes instead of closing over the plaza.
var for_new_game: bool = false

var _registry: ContentRegistry
var _rules: CombatRules


func setup(registry: ContentRegistry, rules: CombatRules, existing: Dictionary = {}, unlocked: Array[String] = []) -> void:
	_registry = registry
	_rules = rules
	attr_rules = registry.get_entry("rules", "attributes")
	look = registry.get_entry("rules", "appearance")
	races.clear()
	for r: Dictionary in registry.get_all("races"):
		if bool(r.get("playable", true)): # companion-only races (Vaultkin) stay off the creator
			races.append(r["id"])
	origins.clear()
	locked_origins.clear()
	for o: Dictionary in registry.get_all("origins"):
		if o.has("unlock_flag") and not unlocked.has("origin:%s" % String(o["id"])):
			locked_origins.append({"name": String(o.get("name", o["id"])), "blurb": String(o.get("unlock_blurb", "Earned by an earlier playthrough."))})
			continue # earned on the account by an earlier playthrough (S35)
		origins.append(o["id"])
	classes.clear()
	for c: Dictionary in registry.get_all("classes"):
		classes.append(c["id"])
	tones.clear()
	tones.append("")
	for t: Variant in look.get("tones", []):
		if t is Dictionary:
			tones.append(String((t as Dictionary).get("id", "")))
	accents.clear()
	accents.append("")
	for a: Variant in look.get("accents", []):
		if a is Dictionary:
			accents.append(String((a as Dictionary).get("id", "")))
	attr_names.clear()
	attr_names.assign(attr_rules.get("names", []))
	rows = [ROW_NAME, "race", "origin", "class", ROW_TONE, ROW_ACCENT]
	rows.append_array(attr_names)
	sheet = CharacterSheet.from_dict(existing) if not existing.is_empty() else CharacterSheet.new()
	if not races.has(sheet.race_id) and not races.is_empty():
		sheet.race_id = races[0]
	if not origins.has(sheet.origin_id) and not origins.is_empty():
		sheet.origin_id = origins[0]
	if not classes.has(sheet.class_id) and not classes.is_empty():
		sheet.class_id = classes[0]
	if not tones.has(String(sheet.appearance.get("tone", ""))):
		sheet.appearance["tone"] = ""
	if not accents.has(String(sheet.appearance.get("accent", ""))):
		sheet.appearance["accent"] = ""
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
		ROW_TONE:
			sheet.appearance["tone"] = _cycle(tones, String(sheet.appearance.get("tone", "")), delta)
		ROW_ACCENT:
			sheet.appearance["accent"] = _cycle(accents, String(sheet.appearance.get("accent", "")), delta)
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


## Derived combat stats for the current sheet, or for the sheet with one
## attribute changed by `delta` (the next-point preview).
func preview_stats(attribute: String = "", delta: int = 0) -> Dictionary:
	var cls := _registry.get_entry("classes", sheet.class_id)
	var race := _registry.get_entry("races", sheet.race_id)
	var attrs := sheet.attributes.duplicate()
	if not attribute.is_empty():
		attrs[attribute] = int(attrs.get(attribute, 0)) + delta
	return StatBlock.for_member(cls, race, _rules, {
		"attributes": attrs,
		"attribute_effects": attr_rules.get("effects", {}),
		"origin": _registry.get_entry("origins", sheet.origin_id),
	})


## What the next point in an attribute buys, as "HP 17 → 19"; why not, when
## it cannot be bought.
func next_point_text(attribute: String) -> String:
	var cap := int(attr_rules.get("max_per_attribute", 4))
	if sheet.attribute(attribute) >= cap:
		return "at the cap"
	if points_left() <= 0:
		return "no points left"
	var now := preview_stats()
	var then := preview_stats(attribute, 1)
	var parts: PackedStringArray = []
	for key: String in ["hp", "move", "evasion", "initiative"]:
		if int(then.get(key, 0)) != int(now.get(key, 0)):
			parts.append("%s %d → %d" % [_stat_label(key), int(now[key]), int(then[key])])
	return "next point: %s" % ", ".join(parts) if not parts.is_empty() else "next point changes nothing"


## The sheet's appearance as rig colours (see CharacterSheet.resolve_appearance).
func appearance_colors() -> Dictionary:
	return CharacterSheet.resolve_appearance(_registry, sheet.appearance)


func appearance_name(part: String) -> String:
	var id := String(sheet.appearance.get(part, ""))
	if id.is_empty():
		return "race default"
	return String(CharacterSheet.appearance_option(look, part, id).get("name", id))


func render() -> String:
	var lines: PackedStringArray = []
	lines.append("NEW WEAVER")
	lines.append("↑↓ row · ←→ change · Enter confirm · %s" % ("Esc back to the death-stakes" if for_new_game else "Esc cancel"))
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
				for locked: Dictionary in locked_origins:
					lines.append("      locked: %s — %s" % [locked["name"], locked["blurb"]])
			"class":
				var c := _registry.get_entry("classes", sheet.class_id)
				var res: Dictionary = c.get("resource", {})
				lines.append("%sClass: %s — %s: %s" % [marker, c.get("name", sheet.class_id), res.get("name", "?"), res.get("summary", "")])
				lines.append("      abilities: %s" % ", ".join(PackedStringArray(c.get("abilities", []))))
			ROW_TONE:
				lines.append("%sTone: %s" % [marker, appearance_name("tone")])
			ROW_ACCENT:
				lines.append("%sAccent: %s" % [marker, appearance_name("accent")])
			_:
				var fx: Dictionary = Dictionary(attr_rules.get("effects", {})).get(key, {})
				lines.append("%s%s: %s%s  (%s per point · %s)" % [marker, key.capitalize(), "●".repeat(sheet.attribute(key)), "○".repeat(maxi(int(attr_rules.get("max_per_attribute", 4)) - sheet.attribute(key), 0)), _mods_text(fx), next_point_text(key)])
	lines.append("")
	lines.append("Points left: %d" % points_left())
	var s := preview_stats()
	lines.append("Derived: HP %d · Move %d · Evasion %d · Initiative %d" % [s["hp"], s["move"], s["evasion"], s["initiative"]])
	var errs := errors()
	if not errs.is_empty():
		lines.append("")
		lines.append("Cannot confirm: " + "; ".join(PackedStringArray(errs)))
	return "\n".join(lines)


static func _stat_label(key: String) -> String:
	match key:
		"hp":
			return "HP"
		_:
			return key.capitalize()


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
