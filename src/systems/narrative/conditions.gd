## Gate evaluation for dialogue choices, start nodes and banter lines.
##
## `requires` block: {"flags": {name: bool}, "origin_tag": "x", "race": "x",
## "class": "x", "approval": {companion: {"min": n, "max": n}},
## "recruited": "companion", "not_recruited": "companion",
## "quest": {"id": "q", "stage": "s"}}. Every listed key must hold.
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
	if requires.has("recruited") and not n.is_recruited(String(requires["recruited"])):
		return false
	if requires.has("not_recruited") and n.is_recruited(String(requires["not_recruited"])):
		return false
	if requires.has("quest"):
		var q: Dictionary = requires["quest"]
		if n.stage_of(String(q.get("id", ""))) != String(q.get("stage", "")):
			return false
	return true


## Applies an `effects` block to the narrative state. Returns the list of
## companions recruited by it (the world spawns them).
## {"approval": {companion: delta}, "flags": {name: bool}, "recruit": "id",
## "quest": {"id": "q", "stage": "s"}}
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
	return recruited
