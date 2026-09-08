## The Bastion's books: banked resources and lifetime totals. Persists as a
## small versioned JSON file (GDD §13). Nothing in here is ever lost on a
## wipe; that is what "banked" means.
class_name Ledger
extends RefCounted

const VERSION := 1
const RESOURCES: Array[String] = ["salvage", "aether", "ciphers"]

var path: String = "user://ledger.json"
var resources: Dictionary = {"salvage": 0, "aether": 0, "ciphers": 0}
var xp: int = 0
var runs_completed: int = 0
var runs_wiped: int = 0
var kills: int = 0
## Set when the last load found a file it could not read; the ledger
## starts fresh but the reason is kept for the UI/log.
var load_error: String = ""


static func load_or_new(p_path: String) -> Ledger:
	var ledger := Ledger.new()
	ledger.path = p_path
	if not FileAccess.file_exists(p_path):
		return ledger
	var file := FileAccess.open(p_path, FileAccess.READ)
	if file == null:
		ledger.load_error = "cannot open %s: %s" % [p_path, error_string(FileAccess.get_open_error())]
		return ledger
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		ledger.load_error = "ledger JSON error line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return ledger
	if not json.data is Dictionary:
		ledger.load_error = "ledger is not a JSON object"
		return ledger
	ledger.apply(migrate(json.data))
	return ledger


## Brings an older save shape up to VERSION. Append a step per version bump.
static func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var version := int(d.get("version", 0))
	if version < 1:
		# Pre-versioned prototype saves kept flat resource keys.
		var res: Dictionary = {}
		for key: String in RESOURCES:
			res[key] = int(d.get(key, 0))
		d["resources"] = d.get("resources", res)
		d["version"] = 1
	return d


func apply(d: Dictionary) -> void:
	var res: Dictionary = d.get("resources", {})
	for key: String in RESOURCES:
		resources[key] = int(res.get(key, 0))
	xp = int(d.get("xp", 0))
	runs_completed = int(d.get("runs_completed", 0))
	runs_wiped = int(d.get("runs_wiped", 0))
	kills = int(d.get("kills", 0))


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"resources": resources.duplicate(),
		"xp": xp,
		"runs_completed": runs_completed,
		"runs_wiped": runs_wiped,
		"kills": kills,
	}


func save() -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "  "))
	return OK


## Adds a haul (resource -> amount) to the books.
func bank(haul: Dictionary) -> void:
	for key: String in RESOURCES:
		resources[key] = int(resources[key]) + int(haul.get(key, 0))


func total(key: String) -> int:
	return int(resources.get(key, 0))


func summary() -> String:
	return "banked S%d A%d C%d · XP %d · runs %d · wipes %d" % [total("salvage"), total("aether"), total("ciphers"), xp, runs_completed, runs_wiped]
