## The protagonist as data: name, race, origin, class, appearance (S51: a
## tone and an accent from `rules/appearance`; empty means the race's
## default look), attributes. Validated
## against the registry and the `rules/attributes` entry; serialised into
## saves under "protagonist".
class_name CharacterSheet
extends RefCounted

const MAX_NAME := 24

var name: String = "Weaver"
var race_id: String = "trueborn"
var origin_id: String = "scav_runner"
var class_id: String = "scrap_knight"
var attributes: Dictionary = {"body": 2, "arcane": 2, "tech": 2}
var appearance: Dictionary = {"tone": "", "accent": ""}


static func from_dict(d: Dictionary) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.name = String(d.get("name", s.name))
	s.race_id = String(d.get("race_id", s.race_id))
	s.origin_id = String(d.get("origin_id", s.origin_id))
	s.class_id = String(d.get("class_id", s.class_id))
	var look: Dictionary = d.get("appearance", {})
	s.appearance = {"tone": String(look.get("tone", "")), "accent": String(look.get("accent", ""))}
	var attrs: Dictionary = d.get("attributes", {})
	if not attrs.is_empty():
		s.attributes = {}
		for key: String in attrs:
			s.attributes[key] = int(attrs[key])
	return s


func to_dict() -> Dictionary:
	return {"name": name, "race_id": race_id, "origin_id": origin_id, "class_id": class_id, "attributes": attributes.duplicate(), "appearance": appearance.duplicate()}


func attribute(key: String) -> int:
	return int(attributes.get(key, 0))


func points_spent() -> int:
	var n := 0
	for key: String in attributes:
		n += int(attributes[key])
	return n


func validate(registry: ContentRegistry, attr_rules: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		errors.append(Loc.t("name is empty"))
	elif trimmed.length() > MAX_NAME:
		errors.append(Loc.t("name is longer than %d characters") % MAX_NAME)
	if not registry.has_entry("races", race_id):
		errors.append(Loc.t("unknown race '%s'") % race_id)
	if not registry.has_entry("origins", origin_id):
		errors.append(Loc.t("unknown origin '%s'") % origin_id)
	if not registry.has_entry("classes", class_id):
		errors.append(Loc.t("unknown class '%s'") % class_id)
	var look: Dictionary = registry.get_entry("rules", "appearance")
	for part: String in ["tone", "accent"]:
		var id := String(appearance.get(part, ""))
		if not id.is_empty() and appearance_option(look, part, id).is_empty():
			errors.append(Loc.t("unknown %s '%s'") % [part, id])
	var names: Array = attr_rules.get("names", [])
	var points := int(attr_rules.get("points", 0))
	var cap := int(attr_rules.get("max_per_attribute", 99))
	for key: String in attributes:
		if not names.has(key):
			errors.append(Loc.t("unknown attribute '%s'") % key)
	for key: String in names:
		var v := attribute(key)
		if v < 0 or v > cap:
			errors.append(Loc.t("%s must be between 0 and %d") % [key, cap])
	if points_spent() != points:
		errors.append(Loc.t("attributes spend %d of %d points") % [points_spent(), points])
	return errors


## One option of `rules/appearance` ({id, name, color}) by part ("tone" or
## "accent") and id; empty when there is none.
static func appearance_option(look: Dictionary, part: String, id: String) -> Dictionary:
	for o: Variant in look.get(part + "s", []):
		if o is Dictionary and String((o as Dictionary).get("id", "")) == id:
			return o
	return {}


## The sheet's appearance as colours for the rig: {"tone": Color, "accent":
## Color}, only the parts that are set and known.
static func resolve_appearance(registry: ContentRegistry, appearance: Dictionary) -> Dictionary:
	var look: Dictionary = registry.get_entry("rules", "appearance")
	var out: Dictionary = {}
	for part: String in ["tone", "accent"]:
		var o := appearance_option(look, part, String(appearance.get(part, "")))
		if not o.is_empty():
			out[part] = Color.html(String(o.get("color", "#ffffff")))
	return out
