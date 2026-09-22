## Backend used when no platform client is present (open-source builds,
## CI, editor). Achievements are kept in memory (and readable by tests and
## the debug overlay); the "cloud" is a folder under user:// so the sync
## logic runs the same way it will against Steam Cloud.
class_name NullPlatformBackend
extends PlatformBackend

const CLOUD_DIR := "user://cloud_null"
const WORKSHOP_DIR := "user://workshop_null"

## Achievement ids unlocked this session, in order.
var unlocked: Array[String] = []
var cloud_dir: String = CLOUD_DIR
var workshop_dir: String = WORKSHOP_DIR


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


# --- Workshop: a folder standing in for the store (S58) ----------------------

## Every item folder under the workshop dir that holds a mod.json, by id.
func workshop_items() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(workshop_dir)
	if dir == null:
		return out
	var ids: Array[String] = []
	for d: String in dir.get_directories():
		if FileAccess.file_exists(workshop_dir.path_join(d).path_join("mod.json")):
			ids.append(d)
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id: String in ids:
		out.append(workshop_dir.path_join(id))
	return out


## Copies the folder to <workshop_dir>/<item_id>/ (the next id when 0) and
## writes workshop.json beside it, so subscribing and updating round-trip
## without a client.
func workshop_publish(folder: String, title: String, description: String, item_id: int = 0) -> Dictionary:
	if not FileAccess.file_exists(folder.path_join("mod.json")):
		return {"ok": false, "item_id": 0, "why": "%s has no mod.json" % folder}
	if item_id <= 0:
		item_id = 1
		for existing: String in workshop_items():
			item_id = maxi(item_id, int(existing.get_file()) + 1)
	var target := workshop_dir.path_join(str(item_id))
	_remove_tree(target)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
	_copy_tree(folder, target)
	var meta := FileAccess.open(target.path_join("workshop.json"), FileAccess.WRITE)
	if meta != null:
		meta.store_string(JSON.stringify({"item_id": item_id, "title": title, "description": description, "source": folder, "published_at": Time.get_datetime_string_from_system(true, true)}, "  "))
	return {"ok": true, "item_id": item_id, "why": ""}


static func _copy_tree(from: String, to: String) -> void:
	var dir := DirAccess.open(from)
	if dir == null:
		return
	for d: String in dir.get_directories():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to.path_join(d)))
		_copy_tree(from.path_join(d), to.path_join(d))
	for f: String in dir.get_files():
		var bytes := FileAccess.get_file_as_bytes(from.path_join(f))
		var out := FileAccess.open(to.path_join(f), FileAccess.WRITE)
		if out != null:
			out.store_buffer(bytes)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d: String in dir.get_directories():
		_remove_tree(path.path_join(d))
	for f: String in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
