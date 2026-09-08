## Walks a `dialogue` entry: picks the start node by conditions, filters
## choices, applies effects, tracks the end. Pure; the menu only renders.
##
## Entry: {"start": "node" | [{"node", "requires"}...], "nodes": {id:
## {"speaker", "text", "choices": [{"text", "requires", "effects", "next" |
## "end": true}]}}}
class_name DialogueRunner
extends RefCounted

var dialogue: Dictionary = {}
var ctx: Dictionary = {}
var narrative: NarrativeState
var node_id: String = ""
var finished: bool = false
## Companions recruited during this conversation (for the world to spawn).
var recruited: Array[String] = []
## Every effect block applied, in order (tests and logs).
var applied: Array[Dictionary] = []


func start(p_dialogue: Dictionary, p_ctx: Dictionary) -> bool:
	dialogue = p_dialogue
	ctx = p_ctx
	narrative = ctx.get("narrative")
	if narrative == null:
		narrative = NarrativeState.new()
		ctx["narrative"] = narrative
	finished = false
	recruited.clear()
	applied.clear()
	node_id = _pick_start()
	if node_id.is_empty() or not nodes().has(node_id):
		finished = true
		return false
	return true


func nodes() -> Dictionary:
	return dialogue.get("nodes", {})


func current_node() -> Dictionary:
	return nodes().get(node_id, {})


func speaker() -> String:
	return String(current_node().get("speaker", ""))


func text() -> String:
	return String(current_node().get("text", ""))


## Choices whose `requires` pass, with their original index kept in "index".
func available_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var choices: Array = current_node().get("choices", [])
	for i: int in choices.size():
		var c: Dictionary = choices[i]
		if Conditions.passes(c.get("requires", {}), ctx):
			var copy := c.duplicate()
			copy["index"] = i
			out.append(copy)
	return out


## Picks the n-th *available* choice. False when out of range or finished.
func choose(available_index: int) -> bool:
	if finished:
		return false
	var options := available_choices()
	if available_index < 0 or available_index >= options.size():
		return false
	var c := options[available_index]
	var effects: Dictionary = c.get("effects", {})
	if not effects.is_empty():
		recruited.append_array(Conditions.apply(effects, narrative))
		applied.append(effects)
	if bool(c.get("end", false)) or not c.has("next"):
		finished = true
		return true
	var next := String(c["next"])
	if not nodes().has(next):
		finished = true
		return true
	node_id = next
	return true


## The first available choice flagged `end`, or -1.
func exit_choice() -> int:
	var options := available_choices()
	for i: int in options.size():
		if bool(options[i].get("end", false)):
			return i
	return -1


func _pick_start() -> String:
	var start: Variant = dialogue.get("start", "")
	if start is String:
		return String(start)
	if start is Array:
		for entry: Dictionary in start:
			if Conditions.passes(entry.get("requires", {}), ctx):
				return String(entry.get("node", ""))
	return ""


## Banter: the first line for `trigger` whose `requires` pass and whose
## `once` flag is unset. Applies its effects and sets the flag. Returns the
## line ({} when none).
static func pick_banter(banter: Dictionary, trigger: String, ctx: Dictionary) -> Dictionary:
	var n: NarrativeState = ctx.get("narrative")
	if n == null:
		return {}
	var lines: Array = banter.get("lines", [])
	for line: Dictionary in lines:
		if String(line.get("trigger", "")) != trigger:
			continue
		var once := String(line.get("once", ""))
		if not once.is_empty() and n.flag(once):
			continue
		if not Conditions.passes(line.get("requires", {}), ctx):
			continue
		Conditions.apply(line.get("effects", {}), n)
		if not once.is_empty():
			n.set_flag(once, true)
		return line
	return {}
