## `Platform` autoload: the single entry point for platform services.
## Picks the Steam backend when the GodotSteam singleton is present and the
## client answers; otherwise the null backend, which is also what CI runs.
## Achievements are content (`achievements` kind: conditions on the
## narrative); the world asks `due_achievements()` at story beats. Cloud
## saves are pushed after every write and pulled once at startup.
class_name PlatformService
extends Node

const STEAM_CONFIG := "res://steam/steam.json"

var backend: PlatformBackend
## Content ids unlocked through this service this session (any backend).
var unlocked_this_session: Array[String] = []
## Cloud sync runs only against a live platform (or when a test opts in):
## the null backend's folder cloud must never resurrect deleted saves.
var sync_enabled: bool = false


func _ready() -> void:
	backend = _pick_backend()
	sync_enabled = backend.is_available()


func _pick_backend() -> PlatformBackend:
	if Engine.has_singleton("Steam"):
		var steam := SteamPlatformBackend.new()
		var registry := get_node_or_null("/root/Content") as ContentRegistry
		var entries: Array[Dictionary] = registry.get_all("achievements") if registry != null else []
		if steam.setup(load_steam_config(), entries):
			return steam
	return NullPlatformBackend.new()


static func load_steam_config(path: String = STEAM_CONFIG) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data


func backend_name() -> String:
	return backend.backend_name()


func is_available() -> bool:
	return backend.is_available()


func is_demo() -> bool:
	return backend.is_demo()


func user_name() -> String:
	return backend.user_name()


## "Steam: <name>" or "Steam-free build (null backend)".
func status_line() -> String:
	if backend.is_available():
		return "%s: %s%s" % [backend.backend_name().capitalize(), backend.user_name(), " (demo)" if backend.is_demo() else ""]
	return "Steam-free build (%s backend)" % backend.backend_name()


# --- achievements -----------------------------------------------------------

func unlock_achievement(id: String) -> bool:
	var ok := backend.unlock_achievement(id)
	if ok and not unlocked_this_session.has(id):
		unlocked_this_session.append(id)
	return ok


func is_achievement_unlocked(id: String) -> bool:
	return backend.is_achievement_unlocked(id)


## Achievement entries whose `when` conditions hold and that the backend
## has not unlocked yet. Pure over the entries and the condition context.
static func due_achievements(entries: Array[Dictionary], ctx: Dictionary, p_backend: PlatformBackend) -> Array[String]:
	var out: Array[String] = []
	for a: Dictionary in entries:
		var id := String(a["id"])
		if p_backend.is_achievement_unlocked(id):
			continue
		if Conditions.passes(a.get("when", {}), ctx):
			out.append(id)
	return out


func set_stat(id: String, value: int) -> bool:
	return backend.set_stat(id, value)


# --- cloud saves --------------------------------------------------------------

func cloud_saves_enabled() -> bool:
	return backend.cloud_saves_enabled()


## Copies one local save to the cloud store. False when cloud is off.
func push_save(path: String) -> bool:
	if not sync_enabled or not backend.cloud_saves_enabled() or not FileAccess.file_exists(path):
		return false
	return backend.cloud_write(path.get_file(), FileAccess.get_file_as_bytes(path))


## Pulls every cloud file that is missing locally into `dir`. Returns the
## file names restored. Local files always win over cloud copies.
func pull_missing(dir: String) -> Array[String]:
	var restored: Array[String] = []
	if not sync_enabled or not backend.cloud_saves_enabled():
		return restored
	for name: String in backend.cloud_list():
		var local := dir.path_join(name)
		if FileAccess.file_exists(local):
			continue
		var bytes := backend.cloud_read(name)
		if bytes.is_empty():
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var f := FileAccess.open(local, FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer(bytes)
		restored.append(name)
	return restored
