## GodotSteam backend. Talks to the `Steam` singleton through dynamic
## calls so this script compiles and loads without the GDExtension; when
## the extension is absent or the client is not running, `is_available()`
## is false and the service falls back to the null backend.
##
## Setup: put the GodotSteam GDExtension under addons/godotsteam/, a
## `steam_appid.txt` beside the executable during development, and the
## app id in steam/steam.json. Achievement content ids map to Steam API
## names through `steam_id` on each `achievements` entry.
class_name SteamPlatformBackend
extends PlatformBackend

var steam: Object = null
var _app_id: int = 0
var _demo: bool = false
var _initialised: bool = false
var _achievement_names: Dictionary = {} # content id -> Steam API name
var _unlocked_cache: Array[String] = []


## `config`: the steam/steam.json dictionary; `achievements`: content entries.
func setup(config: Dictionary, achievements: Array[Dictionary]) -> bool:
	_app_id = int(config.get("app_id", 0))
	_demo = bool(config.get("demo", false))
	for a: Dictionary in achievements:
		_achievement_names[String(a["id"])] = String(a.get("steam_id", String(a["id"]).to_upper()))
	if not Engine.has_singleton("Steam"):
		return false
	steam = Engine.get_singleton("Steam")
	var result: Variant = steam.call("steamInitEx", true, _app_id)
	if result is Dictionary:
		_initialised = int(Dictionary(result).get("status", 1)) == 0
	else:
		_initialised = bool(steam.call("isSteamRunning"))
	if _initialised:
		steam.call("requestCurrentStats")
	return _initialised


func backend_name() -> String:
	return "steam"


func is_available() -> bool:
	return _initialised and steam != null


func is_demo() -> bool:
	return _demo


func user_name() -> String:
	return String(steam.call("getPersonaName")) if is_available() else ""


func app_id() -> int:
	return _app_id


func unlock_achievement(id: String) -> bool:
	if not is_available() or not _achievement_names.has(id):
		return false
	var api_name: String = _achievement_names[id]
	if bool(steam.call("setAchievement", api_name)):
		steam.call("storeStats")
		if not _unlocked_cache.has(id):
			_unlocked_cache.append(id)
		return true
	return false


func is_achievement_unlocked(id: String) -> bool:
	if not is_available() or not _achievement_names.has(id):
		return false
	var got: Variant = steam.call("getAchievement", _achievement_names[id])
	if got is Dictionary:
		return bool(Dictionary(got).get("achieved", false))
	return _unlocked_cache.has(id)


func unlocked_achievements() -> Array[String]:
	var out: Array[String] = []
	for id: String in _achievement_names:
		if is_achievement_unlocked(id):
			out.append(id)
	return out


func set_stat(id: String, value: int) -> bool:
	if not is_available():
		return false
	var ok := bool(steam.call("setStatInt", id, value))
	if ok:
		steam.call("storeStats")
	return ok


func cloud_saves_enabled() -> bool:
	return is_available() and bool(steam.call("isCloudEnabledForAccount")) and bool(steam.call("isCloudEnabledForApp"))


func cloud_write(file_name: String, bytes: PackedByteArray) -> bool:
	if not cloud_saves_enabled():
		return false
	return bool(steam.call("fileWrite", file_name.get_file(), bytes))


func cloud_read(file_name: String) -> PackedByteArray:
	if not cloud_saves_enabled() or not cloud_exists(file_name):
		return PackedByteArray()
	var size := int(steam.call("getFileSize", file_name.get_file()))
	var got: Variant = steam.call("fileRead", file_name.get_file(), size)
	if got is Dictionary:
		return Dictionary(got).get("buf", PackedByteArray())
	return got if got is PackedByteArray else PackedByteArray()


func cloud_exists(file_name: String) -> bool:
	return cloud_saves_enabled() and bool(steam.call("fileExists", file_name.get_file()))


func cloud_list() -> Array[String]:
	var out: Array[String] = []
	if not cloud_saves_enabled():
		return out
	var count := int(steam.call("getFileCount"))
	for i: int in count:
		var info: Variant = steam.call("getFileNameAndSize", i)
		if info is Dictionary:
			out.append(String(Dictionary(info).get("name", "")))
	out.sort()
	return out


func cloud_delete(file_name: String) -> bool:
	return cloud_saves_enabled() and bool(steam.call("fileDelete", file_name.get_file()))
