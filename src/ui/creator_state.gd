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
const ROW_LOADOUT := "loadout"

var sheet := CharacterSheet.new()
var races: Array[String] = []
var origins: Array[String] = []
var locked_origins: Array[Dictionary] = [] # {name, blurb}: earned by a later playthrough
## Loadouts the account may pick, and the ones still locked (S62).
var loadouts: Array[String] = []
var locked_loadouts: Array[Dictionary] = []
## Tones and accents still locked: {part, name, blurb} (S62).
var locked_looks: Array[Dictionary] = []
## The account's keys and how many the content offers, for the header (S62).
var unlocked_count: int = 0
var offered_count: int = 0
var playthroughs: int = 0
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
			locked_origins.append({"name": Loc.text(o, "name", String(o["id"])), "blurb": Loc.text(o, "unlock_blurb", Loc.t("Earned by an earlier playthrough."))})
			continue # earned on the account by an earlier playthrough (S35)
		origins.append(o["id"])
	classes.clear()
	for c: Dictionary in registry.get_all("classes"):
		classes.append(c["id"])
	loadouts.clear()
	locked_loadouts.clear()
	for l: Dictionary in registry.get_all("loadouts"):
		if l.has("unlock_flag") and not unlocked.has("loadout:%s" % String(l["id"])):
			locked_loadouts.append({"name": Loc.text(l, "name", String(l["id"])), "blurb": Loc.text(l, "unlock_blurb", Loc.t("Earned by an earlier playthrough."))})
			continue
		loadouts.append(l["id"])
	locked_looks.clear()
	unlocked_count = 0
	offered_count = Account.offered(registry).size()
	for key: String in unlocked:
		if Account.offered(registry).has(key):
			unlocked_count += 1
	tones.clear()
	tones.append("")
	for t: Variant in look.get("tones", []):
		if t is Dictionary:
			_offer_look("tone", t, unlocked, tones)
	accents.clear()
	accents.append("")
	for a: Variant in look.get("accents", []):
		if a is Dictionary:
			_offer_look("accent", a, unlocked, accents)
	attr_names.clear()
	attr_names.assign(attr_rules.get("names", []))
	rows = [ROW_NAME, "race", "origin", "class", ROW_LOADOUT, ROW_TONE, ROW_ACCENT]
	rows.append_array(attr_names)
	sheet = CharacterSheet.from_dict(existing) if not existing.is_empty() else CharacterSheet.new()
	if existing.is_empty():
		sheet.name = Loc.t(sheet.name)
	if not races.has(sheet.race_id) and not races.is_empty():
		sheet.race_id = races[0]
	if not origins.has(sheet.origin_id) and not origins.is_empty():
		sheet.origin_id = origins[0]
	if not classes.has(sheet.class_id) and not classes.is_empty():
		sheet.class_id = classes[0]
	if not loadouts.has(sheet.loadout_id):
		var fallback := CharacterSheet.default_loadout(registry)
		sheet.loadout_id = fallback if loadouts.has(fallback) else (loadouts[0] if not loadouts.is_empty() else "")
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
		ROW_LOADOUT:
			sheet.loadout_id = _cycle(loadouts, sheet.loadout_id, delta)
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
		return Loc.t("at the cap")
	if points_left() <= 0:
		return Loc.t("no points left")
	var now := preview_stats()
	var then := preview_stats(attribute, 1)
	var parts: PackedStringArray = []
	for key: String in ["hp", "move", "evasion", "initiative"]:
		if int(then.get(key, 0)) != int(now.get(key, 0)):
			parts.append("%s %d → %d" % [_stat_label(key), int(now[key]), int(then[key])])
	return Loc.t("next point: %s") % ", ".join(parts) if not parts.is_empty() else Loc.t("next point changes nothing")


## The sheet's appearance as rig colours (see CharacterSheet.resolve_appearance).
func appearance_colors() -> Dictionary:
	return CharacterSheet.resolve_appearance(_registry, sheet.appearance)


func appearance_name(part: String) -> String:
	var id := String(sheet.appearance.get(part, ""))
	if id.is_empty():
		return Loc.t("race default")
	return Loc.any(String(CharacterSheet.appearance_option(look, part, id).get("name", id)))


## Offers a tone or accent unless it names an `unlock_flag` the account has
## not earned; the locked ones are listed under their row (S62).
func _offer_look(part: String, option: Dictionary, unlocked: Array[String], into: Array[String]) -> void:
	var id := String(option.get("id", ""))
	if option.has("unlock_flag") and not unlocked.has("%s:%s" % [part, id]):
		locked_looks.append({"part": part, "name": Loc.any(String(option.get("name", id))), "blurb": Loc.any(String(option.get("unlock_blurb", Loc.t("Earned by an earlier playthrough."))))})
		return
	into.append(id)


## "Strut blade, Scrap plating, +10 salvage", or "nothing".
func loadout_kit_text(id: String) -> String:
	var l := _registry.get_entry("loadouts", id)
	var parts: PackedStringArray = []
	for item_id: String in l.get("items", []):
		parts.append(Loc.text(_registry.get_entry("items", item_id), "name", item_id))
	var res: Dictionary = l.get("resources", {})
	for key: String in res:
		parts.append("%+d %s" % [int(res[key]), Loc.t(key)])
	return ", ".join(parts) if not parts.is_empty() else Loc.t("nothing")


func render() -> String:
	var lines: PackedStringArray = []
	lines.append(Loc.t("NEW WEAVER"))
	lines.append(Loc.t("↑↓ row · ←→ change · Enter confirm · %s") % (Loc.t("Esc back to the death-stakes") if for_new_game else Loc.t("Esc cancel")))
	lines.append(Loc.t("Account: %d playthroughs · %d of %d unlocks earned") % [playthroughs, unlocked_count, offered_count])
	lines.append("")
	for i: int in rows.size():
		var key := rows[i]
		var marker := "▶ " if i == row else "   "
		match key:
			ROW_NAME:
				lines.append(Loc.t("%sName: %s") % [marker, sheet.name])
			"race":
				var r := _registry.get_entry("races", sheet.race_id)
				lines.append(Loc.t("%sRace: %s — %s") % [marker, Loc.text(r, "name", sheet.race_id), Loc.text(r, "identity")])
				lines.append(Loc.t("      lean: %s · %s") % [Loc.t(String(r.get("faction_lean", "none"))), _mods_text(r.get("stat_mods", {}))])
			"origin":
				var o := _registry.get_entry("origins", sheet.origin_id)
				lines.append(Loc.t("%sOrigin: %s — %s") % [marker, Loc.text(o, "name", sheet.origin_id), Loc.text(o, "summary")])
				lines.append(Loc.t("      %s") % _mods_text(o.get("stat_mods", {})))
				for locked: Dictionary in locked_origins:
					lines.append(Loc.t("      locked: %s — %s") % [locked["name"], locked["blurb"]])
			"class":
				var c := _registry.get_entry("classes", sheet.class_id)
				var res: Dictionary = c.get("resource", {})
				lines.append(Loc.t("%sClass: %s — %s: %s") % [marker, Loc.text(c, "name", sheet.class_id), Loc.content("classes", sheet.class_id, "resource.name", String(res.get("name", "?"))), Loc.content("classes", sheet.class_id, "resource.summary", String(res.get("summary", "")))])
				var ability_names: PackedStringArray = []
				for ability_id: String in c.get("abilities", []):
					ability_names.append(Loc.text(_registry.get_entry("abilities", ability_id), "name", ability_id))
				lines.append(Loc.t("      abilities: %s") % ", ".join(ability_names))
			ROW_LOADOUT:
				var l := _registry.get_entry("loadouts", sheet.loadout_id)
				lines.append(Loc.t("%sLoadout: %s — %s") % [marker, Loc.text(l, "name", sheet.loadout_id), Loc.text(l, "summary")])
				lines.append(Loc.t("      kit: %s") % loadout_kit_text(sheet.loadout_id))
				for locked: Dictionary in locked_loadouts:
					lines.append(Loc.t("      locked: %s — %s") % [locked["name"], locked["blurb"]])
			ROW_TONE:
				lines.append(Loc.t("%sTone: %s") % [marker, appearance_name("tone")])
				for locked: Dictionary in locked_looks:
					if String(locked["part"]) == "tone":
						lines.append(Loc.t("      locked: %s — %s") % [locked["name"], locked["blurb"]])
			ROW_ACCENT:
				lines.append(Loc.t("%sAccent: %s") % [marker, appearance_name("accent")])
				for locked: Dictionary in locked_looks:
					if String(locked["part"]) == "accent":
						lines.append(Loc.t("      locked: %s — %s") % [locked["name"], locked["blurb"]])
			_:
				var fx: Dictionary = Dictionary(attr_rules.get("effects", {})).get(key, {})
				lines.append(Loc.t("%s%s: %s%s  (%s per point · %s)") % [marker, Loc.t(key.capitalize()), "●".repeat(sheet.attribute(key)), "○".repeat(maxi(int(attr_rules.get("max_per_attribute", 4)) - sheet.attribute(key), 0)), _mods_text(fx), next_point_text(key)])
	lines.append("")
	lines.append(Loc.t("Points left: %d") % points_left())
	var s := preview_stats()
	lines.append(Loc.t("Derived: HP %d · Move %d · Evasion %d · Initiative %d") % [s["hp"], s["move"], s["evasion"], s["initiative"]])
	var errs := errors()
	if not errs.is_empty():
		lines.append("")
		lines.append(Loc.t("Cannot confirm: ") + "; ".join(PackedStringArray(errs)))
	return "\n".join(lines)


static func _stat_label(key: String) -> String:
	match key:
		"hp":
			return Loc.t("HP")
		_:
			return Loc.t(key.capitalize())


static func _mods_text(mods: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in mods:
		var v := int(mods[key])
		parts.append("%s%d %s" % ["+" if v >= 0 else "", v, Loc.t(key)])
	return ", ".join(parts) if not parts.is_empty() else Loc.t("no modifiers")


static func _cycle(options: Array[String], current: String, delta: int) -> String:
	if options.is_empty():
		return current
	var i := options.find(current)
	return options[posmod(i + delta, options.size())]
