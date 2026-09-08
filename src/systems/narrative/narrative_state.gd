## Flags, companion approval, quest stages and recruits (GDD §11 "flag /
## reputation system"). Pure data, saved under "narrative".
class_name NarrativeState
extends RefCounted

var flags: Dictionary = {}
var approval: Dictionary = {}
var quests: Dictionary = {} # quest id -> stage id
var recruited: Array[String] = []


func flag(name: String) -> bool:
	return bool(flags.get(name, false))


func set_flag(name: String, value: bool) -> void:
	flags[name] = value


func approval_of(companion: String) -> int:
	return int(approval.get(companion, 0))


func add_approval(companion: String, delta: int) -> void:
	approval[companion] = approval_of(companion) + delta


func stage_of(quest: String) -> String:
	return String(quests.get(quest, ""))


func set_stage(quest: String, stage: String) -> void:
	quests[quest] = stage


func is_recruited(companion: String) -> bool:
	return recruited.has(companion)


func recruit(companion: String) -> void:
	if not recruited.has(companion):
		recruited.append(companion)


func dismiss(companion: String) -> void:
	recruited.erase(companion)


func to_dict() -> Dictionary:
	return {"flags": flags.duplicate(), "approval": approval.duplicate(), "quests": quests.duplicate(), "recruited": recruited.duplicate()}


static func from_dict(d: Dictionary) -> NarrativeState:
	var n := NarrativeState.new()
	var f: Dictionary = d.get("flags", {})
	for k: String in f:
		n.flags[k] = bool(f[k])
	var a: Dictionary = d.get("approval", {})
	for k: String in a:
		n.approval[k] = int(a[k])
	var q: Dictionary = d.get("quests", {})
	for k: String in q:
		n.quests[k] = String(q[k])
	n.recruited.assign(d.get("recruited", []))
	return n
