## Gate evaluation for dialogue choices, start nodes and banter lines.
##
## `requires` block: {"flags": {name: bool}, "origin_tag": "x", "race": "x",
## "class": "x", "approval": {companion: {"min": n, "max": n}},
## "recruited": "companion" (walking with the party now: recruited and not
## waiting at the Bastion, D-093), "not_recruited": "companion",
## "quest": {"id": "q", "stage": "s"}, "faction": "id" (the joined faction;
## "" for none yet), "not_faction": "id", "romance": "id" (the committed
## companion; "" for nobody), "not_romance": "id", "romance_open": "id"
## (nobody, or that companion), "party_race": "id" and "party_race_tag": "tag"
## (anyone walking with the party, S44), "attribute": {name: {"min", "max"}}
## (the leader's creator attributes), "disguised": bool (a reshaping race
## whose arcane control holds)}. Every listed key must hold.
##
## `ctx`: {"narrative": NarrativeState, "origin_tag": String, "race": String,
## "class": String}
class_name Conditions
extends RefCounted


static func passes(requires: Dictionary, ctx: Dictionary) -> bool:
	if requires.is_empty():
		return true
	var n: NarrativeState = ctx.get("narrative")
	if n == null:
		n = NarrativeState.new()
	var flags: Dictionary = requires.get("flags", {})
	for name: String in flags:
		if n.flag(name) != bool(flags[name]):
			return false
	if requires.has("origin_tag") and String(requires["origin_tag"]) != String(ctx.get("origin_tag", "")):
		return false
	if requires.has("race") and String(requires["race"]) != String(ctx.get("race", "")):
		return false
	if requires.has("race_tag") and not Array(ctx.get("race_tags", [])).has(String(requires["race_tag"])):
		return false
	if requires.has("class") and String(requires["class"]) != String(ctx.get("class", "")):
		return false
	if requires.has("party_race") and not Array(ctx.get("party_races", [])).has(String(requires["party_race"])):
		return false
	if requires.has("party_race_tag") and not Array(ctx.get("party_race_tags", [])).has(String(requires["party_race_tag"])):
		return false
	if requires.has("disguised") and bool(ctx.get("disguised", false)) != bool(requires["disguised"]):
		return false
	var attribute: Dictionary = requires.get("attribute", {})
	for name: String in attribute:
		var bounds: Dictionary = attribute[name]
		var v := int(Dictionary(ctx.get("attributes", {})).get(name, 0))
		if bounds.has("min") and v < int(bounds["min"]):
			return false
		if bounds.has("max") and v > int(bounds["max"]):
			return false
	var approval: Dictionary = requires.get("approval", {})
	for companion: String in approval:
		var bounds: Dictionary = approval[companion]
		var v := n.approval_of(companion)
		if bounds.has("min") and v < int(bounds["min"]):
			return false
		if bounds.has("max") and v > int(bounds["max"]):
			return false
	var reputation: Dictionary = requires.get("reputation", {})
	for faction: String in reputation:
		var bounds: Dictionary = reputation[faction]
		var rep := n.reputation_of(faction)
		if bounds.has("min") and rep < int(bounds["min"]):
			return false
		if bounds.has("max") and rep > int(bounds["max"]):
			return false
	if requires.has("recruited") and not _walking(n, String(requires["recruited"])):
		return false
	if requires.has("faction") and n.faction != String(requires["faction"]): # "" means none joined
		return false
	if requires.has("party_approval_min"):
		for id: String in n.recruited:
			if n.approval_of(id) < int(requires["party_approval_min"]):
				return false
	if requires.has("not_faction") and n.faction == String(requires["not_faction"]) and not n.faction.is_empty():
		return false
	if requires.has("romance") and n.romance != String(requires["romance"]): # "" means nobody
		return false
	if requires.has("not_romance") and n.romance == String(requires["not_romance"]) and not n.romance.is_empty():
		return false
	if requires.has("romance_open") and not n.romance.is_empty() and n.romance != String(requires["romance_open"]):
		return false
	if requires.has("not_recruited") and _walking(n, String(requires["not_recruited"])):
		return false
	if requires.has("walking") and not _walking(n, String(requires["walking"])): # S72: the same as recruited, said plainly
		return false
	if requires.has("benched") and not (n.is_recruited(String(requires["benched"])) and n.is_benched(String(requires["benched"]))): # S72: recruited and waiting at the Bastion
		return false
	if requires.has("map") and String(ctx.get("map", "")) != String(requires["map"]): # S74: where the party stands
		return false
	if requires.has("quest"):
		var q: Dictionary = requires["quest"]
		if n.stage_of(String(q.get("id", ""))) != String(q.get("stage", "")):
			return false
	return true


## Recruited and not benched: the companion is here to speak.
static func _walking(n: NarrativeState, id: String) -> bool:
	return n.is_recruited(id) and not n.is_benched(id)


## Applies an `effects` block to the narrative state. Returns the list of
## companions recruited by it (the world spawns them).
## {"approval": {companion: delta}, "flags": {name: bool}, "recruit": "id",
## "quest": {"id": "q", "stage": "s"}, "romance": {"commit": "id"} | {"end": true}, "dismiss": "id"}
static func apply(effects: Dictionary, n: NarrativeState) -> Array[String]:
	var recruited: Array[String] = []
	if effects.is_empty():
		return recruited
	var approval: Dictionary = effects.get("approval", {})
	for companion: String in approval:
		n.add_approval(companion, int(approval[companion]))
	var flags: Dictionary = effects.get("flags", {})
	for name: String in flags:
		n.set_flag(name, bool(flags[name]))
	var reputation: Dictionary = effects.get("reputation", {})
	for faction: String in reputation:
		n.add_reputation(faction, int(reputation[faction]))
	if effects.has("recruit"):
		var id := String(effects["recruit"])
		if not n.is_recruited(id):
			n.recruit(id)
			recruited.append(id)
	if effects.has("quest"):
		var q: Dictionary = effects["quest"]
		n.set_stage(String(q.get("id", "")), String(q.get("stage", "")))
	if effects.has("dismiss"): # the story takes someone off the roster (S41); flags are the content's
		n.dismiss(String(effects["dismiss"]))
	if effects.has("romance"):
		var r: Dictionary = effects["romance"]
		if r.has("commit"):
			n.commit_romance(String(r["commit"]))
		if bool(r.get("end", false)):
			n.end_romance()
	return recruited
