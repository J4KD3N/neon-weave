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


## Keys a narrative state has earned: every origin, loadout, tone and accent
## whose `unlock_flag` is set (S62: loadouts and cosmetics beside origins,
## GDD §12). Returns the new ones (already saved when any).
func grant_from(narrative: NarrativeState, registry: ContentRegistry) -> Array[String]:
	var fresh: Array[String] = []
	for key: String in earnable(narrative, registry):
		if unlock(key):
			fresh.append(key)
	if not fresh.is_empty():
		save()
	return fresh


## Every unlock key the content offers whose flag the story has set:
## "origin:<id>", "loadout:<id>", "tone:<id>", "accent:<id>".
static func earnable(narrative: NarrativeState, registry: ContentRegistry) -> Array[String]:
	var out: Array[String] = []
	for kind: String in ["origins", "loadouts"]:
		for e: Dictionary in registry.get_all(kind):
			var flag := String(e.get("unlock_flag", ""))
			if not flag.is_empty() and narrative.flag(flag):
				out.append("%s:%s" % [kind.trim_suffix("s"), String(e["id"])])
	var look: Dictionary = registry.get_entry("rules", "appearance")
	for part: String in ["tone", "accent"]:
		for o: Variant in look.get(part + "s", []):
			if not (o is Dictionary):
				continue
			var flag := String((o as Dictionary).get("unlock_flag", ""))
			if not flag.is_empty() and narrative.flag(flag):
				out.append("%s:%s" % [part, String((o as Dictionary).get("id", ""))])
	return out


## Every key the content could ever grant, earned or not (the creator
## counts them against the account).
static func offered(registry: ContentRegistry) -> Array[String]:
	var out: Array[String] = []
	for kind: String in ["origins", "loadouts"]:
		for e: Dictionary in registry.get_all(kind):
			if not String(e.get("unlock_flag", "")).is_empty():
				out.append("%s:%s" % [kind.trim_suffix("s"), String(e["id"])])
	var look: Dictionary = registry.get_entry("rules", "appearance")
	for part: String in ["tone", "accent"]:
		for o: Variant in look.get(part + "s", []):
			if o is Dictionary and not String((o as Dictionary).get("unlock_flag", "")).is_empty():
				out.append("%s:%s" % [part, String((o as Dictionary).get("id", ""))])
	return out


## The name behind a key, for a toast: the entry's name, or the key.
static func key_name(registry: ContentRegistry, key: String) -> String:
	var kind := key.get_slice(":", 0)
	var id := key.get_slice(":", 1)
	match kind:
		"origin", "loadout":
			return Loc.text(registry.get_entry(kind + "s", id), "name", key)
		"tone", "accent":
			var o := CharacterSheet.appearance_option(registry.get_entry("rules", "appearance"), kind, id)
			return Loc.any(String(o.get("name", key)))
	return key


## A playthrough began (S62): counted on the account, saved.
func begin_playthrough() -> void:
	playthroughs += 1
	save()


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
