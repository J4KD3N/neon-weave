## Flags, companion approval, faction reputation, quest stages and recruits
## (GDD §11 "flag / reputation system"). Pure data, saved under "narrative".
class_name NarrativeState
extends RefCounted

var flags: Dictionary = {}
var approval: Dictionary = {}
## Standing with each faction (Lattice, Rootched, Ashfound): id -> int.
## Joining is an Act 2 decision; Act 1 only moves these numbers.
var reputation: Dictionary = {}
var quests: Dictionary = {} # quest id -> stage id
var recruited: Array[String] = []
## The faction joined (D-087); "" until Act 2 commits. Joining is exclusive.
var faction: String = ""
## Lore fragment ids found (S35): story, never haul, so a wipe keeps them.
var lore: Array[String] = []


func flag(name: String) -> bool:
	return bool(flags.get(name, false))


func set_flag(name: String, value: bool) -> void:
	flags[name] = value


func approval_of(companion: String) -> int:
	return int(approval.get(companion, 0))


func add_approval(companion: String, delta: int) -> void:
	approval[companion] = approval_of(companion) + delta


func reputation_of(faction: String) -> int:
	return int(reputation.get(faction, 0))


func add_reputation(faction: String, delta: int) -> void:
	reputation[faction] = reputation_of(faction) + delta


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
	return {"flags": flags.duplicate(), "approval": approval.duplicate(), "reputation": reputation.duplicate(), "quests": quests.duplicate(), "recruited": recruited.duplicate(), "faction": faction, "lore": lore.duplicate()}


static func from_dict(d: Dictionary) -> NarrativeState:
	var n := NarrativeState.new()
	var f: Dictionary = d.get("flags", {})
	for k: String in f:
		n.flags[k] = bool(f[k])
	var a: Dictionary = d.get("approval", {})
	for k: String in a:
		n.approval[k] = int(a[k])
	var r: Dictionary = d.get("reputation", {})
	for k: String in r:
		n.reputation[k] = int(r[k])
	var q: Dictionary = d.get("quests", {})
	for k: String in q:
		n.quests[k] = String(q[k])
	n.recruited.assign(d.get("recruited", []))
	n.faction = String(d.get("faction", ""))
	n.lore.assign(d.get("lore", []))
	return n


func has_joined() -> bool:
	return not faction.is_empty()


## Commits to a faction; false when one is already joined. Flags
## `joined_<id>` and `faction_locked` ride along for content to read.
func join_faction(id: String) -> bool:
	if has_joined() or id.is_empty():
		return false
	faction = id
	set_flag("joined_%s" % id, true)
	set_flag("faction_locked", true)
	return true
