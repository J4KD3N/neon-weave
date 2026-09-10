## The ending state machine (S36, D-091): `endings` entries carry `when`
## conditions and a `priority`; the ending that holds with the highest
## priority wins (ties by id), so the Weaver's Mend outranks a faction
## ending when its harder conditions are met, and a priority-0 ending with
## no conditions is the drift nobody chose. Companion fates come from each
## ending's `epilogue`: {companion: {"alive": text, "dead": text, "absent": text}}.
class_name Endings
extends RefCounted


## The winning ending entry for `ctx` (Conditions context), or {}.
static func resolve(registry: ContentRegistry, ctx: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = []
	for e: Dictionary in registry.get_all("endings"):
		if not Conditions.passes(e.get("when", {}), ctx):
			continue
		var key: Array = [-int(e.get("priority", 0)), String(e["id"])]
		if best.is_empty() or key < best_key:
			best = e
			best_key = key
	return best


## One line per companion in the registry, from the ending's epilogue:
## alive and recruited, dead (`<id>_dead`), or absent. Empty text is skipped.
static func fates(registry: ContentRegistry, ending: Dictionary, narrative: NarrativeState) -> Array[String]:
	var out: Array[String] = []
	var epilogue: Dictionary = ending.get("epilogue", {})
	for c: Dictionary in registry.get_all("companions"):
		var id := String(c["id"])
		var lines: Dictionary = epilogue.get(id, {})
		var key := "absent"
		if narrative.flag("%s_dead" % id):
			key = "dead"
		elif narrative.is_recruited(id):
			key = "alive"
		var text := String(lines.get(key, ""))
		if not text.is_empty():
			out.append("%s: %s" % [c.get("short_name", c.get("name", id)), text])
	return out
