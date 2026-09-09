## Backend used when no platform client is present (open-source builds,
## CI, editor). Achievements are kept in memory (and readable by tests and
## the debug overlay); the "cloud" is a folder under user:// so the sync
## logic runs the same way it will against Steam Cloud.
class_name NullPlatformBackend
extends PlatformBackend

const CLOUD_DIR := "user://cloud_null"

## Achievement ids unlocked this session, in order.
var unlocked: Array[String] = []
var cloud_dir: String = CLOUD_DIR


func backend_name() -> String:
	return "null"


func is_available() -> bool:
	return false


func user_name() -> String:
	return "local"


func unlock_achievement(id: String) -> bool:
	if id.is_empty():
		return false
	if not unlocked.has(id):
		unlocked.append(id)
	return true


func is_achievement_unlocked(id: String) -> bool:
	return unlocked.has(id)


func unlocked_achievements() -> Array[String]:
	return unlocked.duplicate()


func set_stat(_id: String, _value: int) -> bool:
	return true


func cloud_saves_enabled() -> bool:
	return true


func _path(file_name: String) -> String:
	return cloud_dir.path_join(file_name.get_file())


func cloud_write(file_name: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cloud_dir))
	var f := FileAccess.open(_path(file_name), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	return true


func cloud_read(file_name: String) -> PackedByteArray:
	if not FileAccess.file_exists(_path(file_name)):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(_path(file_name))


func cloud_exists(file_name: String) -> bool:
	return FileAccess.file_exists(_path(file_name))


func cloud_list() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(cloud_dir)
	if d == null:
		return out
	for f: String in d.get_files():
		out.append(f)
	out.sort()
	return out


func cloud_delete(file_name: String) -> bool:
	if not cloud_exists(file_name):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(file_name))) == OK
