## Account-level unlocks across playthroughs (GDD §12, S35, D-090): a
## small JSON file outside every save, holding the keys a playthrough has
## earned ("origin:beacon_keeper"), a playthrough count, and nothing that
## a single save could lose. The world grants keys from origin entries
## with `unlock_flag` at every autosave; the creator reads them.
class_name Account
extends RefCounted

const VERSION := 1
const DEFAULT_PATH := "user://account.json"

var path: String = DEFAULT_PATH
var unlocked: Array[String] = []
var playthroughs: int = 0
## Iron Weave (S50): one save, Mortal, no reloads. The account, not the save,
## remembers a run is underway, so a deleted or swapped save cannot restart it.
var iron_active: bool = false
var iron_difficulty: String = ""
var iron_runs: int = 0


static func load_or_new(p_path: String = DEFAULT_PATH) -> Account:
	var a := Account.new()
	a.path = p_path
	if not FileAccess.file_exists(p_path):
		return a
	var file := FileAccess.open(p_path, FileAccess.READ)
	if file == null:
		return a
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return a
	var d: Dictionary = json.data
	a.unlocked.assign(d.get("unlocked", []))
	a.playthroughs = int(d.get("playthroughs", 0))
	a.iron_active = bool(d.get("iron_active", false))
	a.iron_difficulty = String(d.get("iron_difficulty", ""))
	a.iron_runs = int(d.get("iron_runs", 0))
	return a


func save() -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "unlocked": unlocked.duplicate(), "playthroughs": playthroughs, "iron_active": iron_active, "iron_difficulty": iron_difficulty, "iron_runs": iron_runs}, "  "))
	return OK


func has(key: String) -> bool:
	return unlocked.has(key)


## True when the key was new.
func unlock(key: String) -> bool:
	if key.is_empty() or unlocked.has(key):
		return false
	unlocked.append(key)
	return true


## Keys a narrative state has earned: every origin whose `unlock_flag` is
## set. Returns the new ones (already saved when any).
func grant_from(narrative: NarrativeState, registry: ContentRegistry) -> Array[String]:
	var fresh: Array[String] = []
	for o: Dictionary in registry.get_all("origins"):
		var flag := String(o.get("unlock_flag", ""))
		if flag.is_empty() or not narrative.flag(flag):
			continue
		if unlock("origin:%s" % String(o["id"])):
			fresh.append("origin:%s" % String(o["id"]))
	if not fresh.is_empty():
		save()
	return fresh


## An Iron Weave run begins: counted and marked underway (saved).
func begin_iron(difficulty: String) -> void:
	iron_active = true
	iron_difficulty = difficulty
	iron_runs += 1
	save()


## An Iron Weave run ends, by an ending (`ending` set: the key
## "iron_weave:<ending>" is unlocked) or by death (empty). Saved.
## Returns true when the ending key was new.
func end_iron(ending: String = "") -> bool:
	iron_active = false
	iron_difficulty = ""
	var fresh := false
	if not ending.is_empty():
		fresh = unlock("iron_weave:%s" % ending)
	save()
	return fresh
