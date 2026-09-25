## The ending state machine (S36, D-091; S43, D-098): `endings` entries carry
## `when` conditions and a `priority`; the ending that holds with the
## highest priority wins (ties by id), so the Weaver's Mend outranks a
## faction ending when its harder conditions are met, and a priority-0
## ending with no conditions is the drift nobody chose. Companion fates
## come from each ending's `epilogue`: {companion: {"alive", "dead",
## "absent", "taken"?, "loyal"?, "romanced"?, "lost"?}}. `modifiers` are
## [{when, text}] paragraphs added to the summary when their conditions hold
## (broken Keys, the ended voice, the catastrophe).
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


## The epilogue key a companion's story resolves to: dead (or `lost` for a
## dead partner), taken by the Choir (`<id>_taken`), or alive as a partner
## (`romanced`), loyal (`loyal`) or simply alive; else absent. Resisted (S72:
## `<id>_resisted`, stood against the Choir) sits above romanced; benched
## (S72: waiting at the Bastion at the end) sits above alive. A key the
## ending does not write falls back along the same ladder.
static func fate_key(id: String, lines: Dictionary, narrative: NarrativeState) -> String:
	var ladder: Array[String] = []
	if narrative.flag("%s_dead" % id):
		if narrative.flag("romance_%s_lost" % id):
			ladder.append("lost")
		ladder.append("dead")
	elif narrative.flag("%s_taken" % id):
		ladder.append("taken")
		ladder.append("absent")
	elif narrative.is_recruited(id):
		if narrative.flag("%s_resisted" % id): # S72: stood against the Choir on the plaza
			ladder.append("resisted")
		if narrative.romance == id:
			ladder.append("romanced")
		if narrative.flag("%s_loyal" % id):
			ladder.append("loyal")
		if narrative.is_benched(id): # S72: waited at the Bastion through the end
			ladder.append("benched")
		ladder.append("alive")
	else:
		ladder.append("absent")
	for key: String in ladder:
		if not String(lines.get(key, "")).is_empty():
			return key
	return ladder[ladder.size() - 1]


## One line per companion in the registry, from the ending's epilogue.
## Empty text is skipped.
static func fates(registry: ContentRegistry, ending: Dictionary, narrative: NarrativeState) -> Array[String]:
	var out: Array[String] = []
	var epilogue: Dictionary = ending.get("epilogue", {})
	for c: Dictionary in registry.get_all("companions"):
		var id := String(c["id"])
		var lines: Dictionary = epilogue.get(id, {})
		var text := String(lines.get(fate_key(id, lines, narrative), ""))
		if not text.is_empty():
			out.append("%s: %s" % [Loc.text(c, "short_name", String(c.get("name", id))), Loc.any(text)])
	return out


## The modifier paragraphs whose conditions hold, in the ending's order.
static func modifiers(ending: Dictionary, ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in ending.get("modifiers", []):
		if Conditions.passes(m.get("when", {}), ctx):
			var text := Loc.any(String(m.get("text", "")))
			if not text.is_empty():
				out.append(text)
	return out
