## Loads every piece of game content (base game + mods) into memory, keyed by
## kind and id. ALL content flows through here: items, enemies, abilities,
## classes, races, companions, dialogue, biomes, loot tables, quests, factions.
##
## Layout: `<root>/<kind>/<id>.json`. The `id` defaults to the file stem.
## Mods are folders containing a `mod.json` manifest and a `content/` tree
## with the same layout. Mods load after the base game in ascending
## `priority`; the last write for a (kind, id) wins, so higher priority
## overrides lower.
##
## Registered as the `Content` autoload. Tests construct it directly and call
## [method load_from] with fixture roots.
class_name ContentRegistry
extends Node

signal reloaded

const BASE_ROOT := "res://content"
const DEV_MODS_ROOT := "res://mods"
const MOD_MANIFEST := "mod.json"
const MOD_CONTENT_DIR := "content"
const SOURCE_BASE := "base"

## Everything that went wrong during the last load. Empty means clean.
var load_errors: Array[String] = []
## Manifests of the mods that loaded, in load order.
var loaded_mods: Array[Dictionary] = []

var _entries: Dictionary = {} # kind:String -> { id:String -> Dictionary }


func _ready() -> void:
	reload()


## Reloads base content plus mods from the default roots.
func reload() -> void:
	load_from(BASE_ROOT, default_mod_roots())


## Where mods are looked for, in order. All are optional.
func default_mod_roots() -> Array[String]:
	var roots: Array[String] = [DEV_MODS_ROOT, "user://mods"]
	if not OS.has_feature("editor"):
		roots.append(OS.get_executable_path().get_base_dir().path_join("mods"))
	return roots


## Clears the registry and loads `base_root` followed by every mod found
## under `mod_roots`.
func load_from(base_root: String, mod_roots: Array[String]) -> void:
	_entries.clear()
	load_errors.clear()
	loaded_mods.clear()

	if DirAccess.dir_exists_absolute(base_root):
		_scan_content_root(base_root, SOURCE_BASE)
	else:
		load_errors.append("base content root missing: %s" % base_root)

	for manifest: Dictionary in discover_mods(mod_roots):
		var mod_id: String = manifest["id"]
		var content_root: String = String(manifest["path"]).path_join(MOD_CONTENT_DIR)
		if DirAccess.dir_exists_absolute(content_root):
			_scan_content_root(content_root, mod_id)
		else:
			load_errors.append("mod '%s' has no %s/ directory" % [mod_id, MOD_CONTENT_DIR])
		loaded_mods.append(manifest)

	reloaded.emit()


## Finds mod manifests under each root and returns them sorted by ascending
## priority, ties broken by id. Each dictionary carries `id`, `name`,
## `version`, `priority` and `path`.
func discover_mods(mod_roots: Array[String]) -> Array[Dictionary]:
	var mods: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for root: String in mod_roots:
		var dir: DirAccess = DirAccess.open(root)
		if dir == null:
			continue
		for folder: String in dir.get_directories():
			if folder.begins_with("."):
				continue
			var mod_path: String = root.path_join(folder)
			var manifest_path: String = mod_path.path_join(MOD_MANIFEST)
			if not FileAccess.file_exists(manifest_path):
				load_errors.append("mod folder without %s skipped: %s" % [MOD_MANIFEST, mod_path])
				continue
			var raw: Variant = _load_json_file(manifest_path)
			if not raw is Dictionary:
				continue
			var manifest: Dictionary = raw
			var mod_id: String = String(manifest.get("id", folder))
			if seen_ids.has(mod_id):
				load_errors.append("duplicate mod id '%s' at %s (already loaded from %s)" % [mod_id, mod_path, seen_ids[mod_id]])
				continue
			seen_ids[mod_id] = mod_path
			mods.append({
				"id": mod_id,
				"name": String(manifest.get("name", mod_id)),
				"version": String(manifest.get("version", "0.0.0")),
				"priority": int(manifest.get("priority", 0)),
				"path": mod_path,
			})
	mods.sort_custom(_compare_mods)
	return mods


## Returns the entry for (kind, id) or an empty Dictionary.
func get_entry(kind: String, id: String) -> Dictionary:
	var by_id: Dictionary = _entries.get(kind, {})
	return by_id.get(id, {})


func has_entry(kind: String, id: String) -> bool:
	var by_id: Dictionary = _entries.get(kind, {})
	return by_id.has(id)


## Every entry of a kind, sorted by id for determinism.
func get_all(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by_id: Dictionary = _entries.get(kind, {})
	var ids: Array = by_id.keys()
	ids.sort()
	for id: String in ids:
		out.append(by_id[id])
	return out


func kinds() -> PackedStringArray:
	var out := PackedStringArray(_entries.keys())
	out.sort()
	return out


func count(kind: String) -> int:
	var by_id: Dictionary = _entries.get(kind, {})
	return by_id.size()


func _scan_content_root(root: String, source: String) -> void:
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		load_errors.append("cannot open content root: %s" % root)
		return
	for kind: String in dir.get_directories():
		if kind.begins_with("."):
			continue
		var kind_path: String = root.path_join(kind)
		var seen_in_source: Dictionary = {}
		for file: String in DirAccess.get_files_at(kind_path):
			if file.get_extension() != "json":
				continue
			var path: String = kind_path.path_join(file)
			var raw: Variant = _load_json_file(path)
			if not raw is Dictionary:
				if raw != null:
					load_errors.append("content file is not a JSON object: %s" % path)
				continue
			var entry: Dictionary = raw
			var id: String = String(entry.get("id", file.get_basename()))
			if seen_in_source.has(id):
				load_errors.append("duplicate %s id '%s' in %s: %s and %s" % [kind, id, source, seen_in_source[id], path])
				continue
			seen_in_source[id] = path
			entry["id"] = id
			entry["_kind"] = kind
			entry["_source"] = source
			entry["_path"] = path
			if not _entries.has(kind):
				_entries[kind] = {}
			var by_id: Dictionary = _entries[kind]
			by_id[id] = entry


## Parses a JSON file. Returns null (and records an error) on failure.
func _load_json_file(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_errors.append("cannot read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return null
	var json := JSON.new()
	var err: Error = json.parse(file.get_as_text())
	if err != OK:
		load_errors.append("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func _compare_mods(a: Dictionary, b: Dictionary) -> bool:
	var pa: int = a["priority"]
	var pb: int = b["priority"]
	if pa != pb:
		return pa < pb
	return String(a["id"]) < String(b["id"])
